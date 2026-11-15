-- Compositor-side controls and native border resizing. Decoration, initial
-- sizing, layout policy and shadows remain the desktop configuration's job.
local M = {}
local source = debug.getinfo(1, "S").source
assert(source:sub(1, 1) == "@", "Window controls must be loaded from a local file")
local directory = source:sub(2):match("^(.*/)") or "./"
local ResizeSettings = dofile(directory .. "resize-settings.lua")

-- Legacy registry/event/layer names intentionally remain wire-compatible.
local registry_key = "__omarchy_window_corners_runtime"
local runtime_version = 7
local triangle_size = 14
local border_padding = 10
local click_tolerance = 4
local move_interval_ms = 16

local function valid_handle(binding)
  -- v0.56.2 methods can dereference expired handles; tostring is safe.
  return binding and not tostring(binding):find("(expired)", 1, true)
end
local state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
  .. "/omarchy/workspace-layouts/"

local function saved_mode(name, key)
  local file = io.open(state .. name .. ".lua", "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return content:match(key .. '%s*=%s*"([%a]+)"')
end

function M.is_tiling_workspace(workspace)
  if not workspace or workspace.id < 1 then return false end
  local mode = saved_mode(tostring(workspace.id), "mode") or saved_mode("default", "default")
  return mode ~= "floating"
end

function M.border_hit(window, cursor)
  if not window or not cursor or not window.at or not window.size then return false end
  local x, y = cursor.x - window.at.x, cursor.y - window.at.y
  local width, height = window.size.x, window.size.y
  return x >= -border_padding and y >= -border_padding and x <= width + border_padding and y <= height + border_padding
    and (x <= 0 or y <= 0 or x >= width or y >= height)
end

local function present(window)
  return window and window.mapped and not window.hidden and window.visible ~= false
    and type(window.address) == "string" and window.address:match("^0x%x+$")
end

local function on_workspace(window, monitor)
  return window.pinned or (window.workspace and monitor.active_workspace
    and window.workspace.id == monitor.active_workspace.id)
end

local function contains(window, cursor, padding)
  return cursor.x >= window.at.x - padding and cursor.x < window.at.x + window.size.x + padding
    and cursor.y >= window.at.y - padding and cursor.y < window.at.y + window.size.y + padding
end

local function eligible_window(window)
  local monitor = window and window.monitor
  if not present(window) or not monitor or window.fullscreen ~= 0
      or not M.is_tiling_workspace(window.workspace) or monitor.active_special_workspace
      or not on_workspace(window, monitor) then return false end
  for _, tag in ipairs(window.tags or {}) do
    if tag == "omarchy-floating-workspace" or tag == "omarchy-floating-workspace*" then return false end
  end
  return true
end

local function logical_size(monitor)
  -- Native scale is float32. Round to match the UI's integer logical screen,
  -- including fractional-scale handles flush with a right/bottom screen edge.
  local scale = monitor.scale or 1
  local width = math.floor(monitor.width / scale + 0.5)
  local height = math.floor(monitor.height / scale + 0.5)
  if (monitor.transform or 0) % 2 == 1 then width, height = height, width end
  return width, height
end

-- Match the UI's small square, including its screen and occlusion guards.
-- All calculations are logical coordinates; monitor width/height are pixels.
function M.hit_target(cursor, windows, floating_only)
  if not cursor then return nil end
  for _, window in ipairs(windows) do
    local monitor = window.monitor
    if eligible_window(window) then
      local width, height = logical_size(monitor)
      local inside = cursor.x >= monitor.x and cursor.y >= monitor.y
        and cursor.x < monitor.x + width and cursor.y < monitor.y + height
      local x, y = window.at.x + window.size.x - triangle_size, window.at.y
      local hit = window.floating and M.border_hit(window, cursor)
        or (not floating_only and not window.floating and window.size.x >= triangle_size and window.size.y >= triangle_size
          and x >= monitor.x and y >= monitor.y and x + triangle_size <= monitor.x + width
          and y + triangle_size <= monitor.y + height and cursor.x >= x and cursor.x < x + triangle_size
          and cursor.y >= y and cursor.y < y + triangle_size)
      if inside and hit then
        local covered = false
        for _, other in ipairs(windows) do
          if present(other) and other.address ~= window.address and on_workspace(other, monitor) then
            if other.fullscreen ~= 0 and other.monitor and other.monitor.id == monitor.id then covered = true end
            if other.floating then
              if not window.floating then
                if other.at.x < x + triangle_size and other.at.x + other.size.x > x
                    and other.at.y < y + triangle_size and other.at.y + other.size.y > y then covered = true end
              -- Lua exposes focus history, not authoritative stacking order.
              -- Reject ambiguous overlaps rather than moving a different
              -- window than the validated border target.
              elseif contains(other, cursor, border_padding) then covered = true end
            end
          end
        end
        if not covered then return window end
      end
    end
  end
end

local function valid_record(record)
  if type(record) ~= "table" or type(record.address) ~= "string"
      or not record.address:match("^0x%x+$") or type(record.tiled) ~= "boolean" then return false end
  for _, key in ipairs({ "workspace", "x", "y", "width", "height" }) do
    local value = record[key]
    if type(value) ~= "number" or value ~= math.floor(value) or math.abs(value) > 10000000 then return false end
  end
  return record.workspace > 0 and record.width > 0 and record.height > 0
end

-- Dwindle's ordinary unfloat honors force_split, not the drop direction.
-- Pick the nearest destination tile and the nearest normalized edge, like
-- native smart-split. Other layouts keep their own insertion semantics.
function M.drop_target(cursor, windows, workspace, address)
  if not cursor then return nil end
  local target, distance
  for _, window in ipairs(windows) do
    if window.address ~= address and eligible_window(window) and not window.floating
        and window.workspace.id == workspace and window.size.x > 0 and window.size.y > 0 then
      local dx = math.max(window.at.x - cursor.x, 0, cursor.x - window.at.x - window.size.x)
      local dy = math.max(window.at.y - cursor.y, 0, cursor.y - window.at.y - window.size.y)
      local d = dx * dx + dy * dy
      if not distance or d < distance then target, distance = window, d end
    end
  end
  if not target or not target.layout or target.layout.name ~= "dwindle" then return nil end
  local dx = (cursor.x - target.at.x) / target.size.x - 0.5
  local dy = (cursor.y - target.at.y) / target.size.y - 0.5
  local direction
  if math.abs(dx) > math.abs(dy) then direction = dx < 0 and "left" or "right"
  else direction = dy < 0 and "up" or "down" end
  return target, direction
end

-- Click-to-move uses only native dispatches and a reusable 16ms timer. There
-- are no held/synthetic buttons, native drag handles, or per-frame processes.
function M.install(owner, recovery)
  assert(type(owner) == "string" and owner:match("^[%w-]+$"), "Invalid window-controls owner")
  local cancelled = rawget(_G, "__omarchy_window_corners_cancelled") or {}
  if cancelled[owner] then return false end
  local previous = rawget(_G, registry_key)
  if previous then
    local reusable = previous.version == runtime_version and #previous.bindings == 5
      and valid_handle(previous.timer)
    for _, binding in ipairs(previous.bindings) do
      if not valid_handle(binding) then reusable = false end
    end
    if reusable then
      previous.activate(owner)
      return true
    end
    previous.deactivate()
  end
  local runtime = { owner = owner, bindings = {}, active = true, version = runtime_version }
  local left, right
  local function event(kind, data)
    hl.dispatch(hl.dsp.event("window-corners-" .. kind .. ":" .. runtime.owner .. ":" .. (data or "")))
  end
  local function restore(record, cancel)
    local window = hl.get_window("address:" .. record.address)
    -- Cancellation/reload must also restore a target on an inactive workspace;
    -- visibility is a hit-test guard, not a teardown guard.
    if not window or not window.mapped or window.hidden or not window.floating or window.fullscreen ~= 0 then return end
    local selector = "address:" .. record.address
    if cancel then
      hl.dispatch(hl.dsp.window.move({ window = selector, workspace = tostring(record.workspace), follow = false }))
      if not record.tiled then
        hl.dispatch(hl.dsp.window.move({ window = selector, x = record.x, y = record.y }))
      end
    end
    if record.tiled then
      local target, direction
      if not cancel then
        target, direction = M.drop_target(hl.get_cursor_pos(), hl.get_windows(), window.workspace.id, record.address)
      end
      if target then
        -- Focus selects the destination workspace and also supports
        -- use_active_for_splits. All layout commands run synchronously.
        hl.dispatch(hl.dsp.focus({ window = "address:" .. target.address }))
        pcall(function() hl.dispatch(hl.dsp.layout("preselect " .. direction)) end)
        local ok, err = pcall(function()
          hl.dispatch(hl.dsp.window.float({ window = selector, action = "off" }))
        end)
        -- Clear even with permanent_direction_override, or a failed dispatch:
        -- this drop must not control where future application windows open.
        pcall(function() hl.dispatch(hl.dsp.layout("preselect none")) end)
        hl.dispatch(hl.dsp.focus({ window = selector }))
        if not ok then error(err) end
      else
        hl.dispatch(hl.dsp.window.float({ window = selector, action = "off" }))
      end
    end
  end
  function runtime.finish_move(cancel)
    local move = runtime.moving
    if not move then return end
    runtime.moving = nil
    left, right = nil, nil
    runtime.timer:set_enabled(false)
    pcall(restore, move, cancel)
    event("move")
  end
  function runtime.update_move()
    local move = runtime.moving
    if not move or not runtime.active then return end
    local window = hl.get_window("address:" .. move.address)
    local cursor = hl.get_cursor_pos()
    if not present(window) or not window.floating or window.fullscreen ~= 0 or not cursor then
      runtime.finish_move(false)
      return
    end
    local destination
    for _, monitor in ipairs(hl.get_monitors()) do
      local width, height = logical_size(monitor)
      if cursor.x >= monitor.x and cursor.y >= monitor.y
          and cursor.x < monitor.x + width and cursor.y < monitor.y + height then destination = monitor; break end
    end
    if not destination then return end -- Keep last position over monitor gaps.
    if destination.active_special_workspace or not destination.active_workspace then runtime.finish_move(true); return end
    local workspace = destination.active_workspace.id
    if workspace ~= move.currentWorkspace then
      if not M.is_tiling_workspace(destination.active_workspace) then runtime.finish_move(true); return end
      hl.dispatch(hl.dsp.window.move({ window = "address:" .. move.address, workspace = tostring(workspace), follow = false }))
      move.currentWorkspace = workspace
    end
    if cursor.x ~= move.lastX or cursor.y ~= move.lastY then
      local result = hl.dispatch(hl.dsp.window.move({ window = "address:" .. move.address,
        x = math.floor(cursor.x - move.offsetX), y = math.floor(cursor.y - move.offsetY) }))
      if result and result.ok == false then runtime.finish_move(true); return end
      move.lastX, move.lastY = cursor.x, cursor.y
    end
  end
  runtime.timer = hl.timer(function()
    local ok = pcall(runtime.update_move)
    if not ok then runtime.finish_move(true) end
  end, { timeout = move_interval_ms, type = "repeat" })
  runtime.timer:set_enabled(false)
  function runtime.start_move(address)
    if not runtime.active or type(address) ~= "string" or not address:match("^0x%x+$") then return false end
    local window = hl.get_window("address:" .. address)
    if not eligible_window(window) then return false end
    runtime.finish_move(true)
    left, right = nil, nil
    local cursor = hl.get_cursor_pos()
    if not cursor then return false end
    local at, size = window.at, window.size
    local move = { address = address, tiled = not window.floating, workspace = window.workspace.id,
      x = at.x, y = at.y, width = size.x, height = size.y, currentWorkspace = window.workspace.id }
    if not valid_record(move) then return false end
    local ratioX = math.max(0, math.min(1, (cursor.x - at.x) / math.max(1, size.x)))
    local ratioY = math.max(0, math.min(1, (cursor.y - at.y) / math.max(1, size.y)))
    runtime.moving = move
    event("move", string.format("%s:%d:%d:%d:%d:%d:%d", address, move.tiled and 1 or 0,
      move.workspace, move.x, move.y, move.width, move.height))
    hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
    if move.tiled then hl.dispatch(hl.dsp.window.float({ window = "address:" .. address, action = "on" })) end
    local floatingSize = window.size
    move.offsetX, move.offsetY = ratioX * floatingSize.x, ratioY * floatingSize.y
    runtime.update_move()
    if runtime.moving then runtime.timer:set_enabled(true) end
    return runtime.moving ~= nil
  end
  local function popup_open()
    for _, layer in ipairs(hl.get_layers({ namespace = "pastleo-floating-corners" })) do
      if layer.mapped then return true end
    end
    return false
  end
  local function capture(floating_only)
    if popup_open() then return nil end -- Never retarget a click on our popup.
    local cursor = hl.get_cursor_pos()
    local window = M.hit_target(cursor, hl.get_windows(), floating_only)
    if not window then return nil end
    return { address = window.address, x = cursor.x, y = cursor.y,
      wx = window.at.x, wy = window.at.y, width = window.size.x, height = window.size.y }
  end
  local function clicked(start, floating_only)
    if not start or not runtime.active or popup_open() then return nil end
    local cursor = hl.get_cursor_pos()
    local window = M.hit_target(cursor, hl.get_windows(), floating_only)
    if not window or window.address ~= start.address or math.abs(cursor.x - start.x) > click_tolerance
        or math.abs(cursor.y - start.y) > click_tolerance or window.at.x ~= start.wx or window.at.y ~= start.wy
        or window.size.x ~= start.width or window.size.y ~= start.height then return nil end
    return window, cursor
  end
  runtime.bindings[1] = hl.bind("mouse:272", function()
    left = nil
    if runtime.active and runtime.moving then
      runtime.update_move()
      runtime.finish_move(false)
      return { pass_event = false }
    end
    if runtime.active then left = capture(true) end
    return { pass_event = true } -- Native left border resizing remains untouched.
  end, { auto_consuming = true, description = "Floating border menu / place picked-up window" })
  runtime.bindings[2] = hl.bind("mouse:272", function()
    local start = left; left = nil
    local window, cursor = clicked(start, true)
    if window and not runtime.moving then
      event("menu", string.format("%s:%d:%d", window.address, math.floor(cursor.x), math.floor(cursor.y)))
    end
  end, { release = true, non_consuming = true, ignore_mods = true, description = "Floating border menu (click, not resize)" })
  runtime.bindings[3] = hl.bind("mouse:273", function()
    right = nil
    if not runtime.active or runtime.moving then return { pass_event = true } end
    right = capture(false)
    return { pass_event = right == nil }
  end, { auto_consuming = true, description = "Right-click window border / triangle" })
  runtime.bindings[4] = hl.bind("mouse:273", function()
    local start = right; right = nil
    local window = clicked(start, false)
    if window and not runtime.moving then runtime.start_move(window.address) end
  end, { release = true, non_consuming = true, ignore_mods = true, description = "Pick up window on right click" })
  runtime.bindings[5] = hl.bind("Escape", function()
    if not runtime.active or not runtime.moving then return { pass_event = true } end
    runtime.finish_move(true)
    return { pass_event = false }
  end, { auto_consuming = true, ignore_mods = true, description = "Cancel picked-up window" })
  runtime.subscriptions = {
    hl.on("window.close", function(window)
      if runtime.active and window and runtime.moving and runtime.moving.address == window.address then runtime.finish_move(false) end
    end),
    hl.on("workspace.active", function() if runtime.active then runtime.finish_move(true) end end),
    hl.on("workspace.special_active", function() if runtime.active then runtime.finish_move(true) end end),
  }

  function runtime.activate(new_owner)
    runtime.finish_move(true)
    ResizeSettings.apply(runtime)
    left, right = nil, nil
    runtime.owner = new_owner
    runtime.active = true
    for _, binding in ipairs(runtime.bindings) do
      if valid_handle(binding) then binding:set_enabled(true) end
    end
  end
  function runtime.deactivate()
    runtime.finish_move(true)
    ResizeSettings.restore(runtime)
    left, right = nil, nil
    runtime.active = false
    -- Never call remove(): on v0.56.2 it removes all binds for the same key,
    -- including others' binds, and leaves the second handle expired.
    for _, binding in ipairs(runtime.bindings) do
      if valid_handle(binding) then binding:set_enabled(false) end
    end
  end
  ResizeSettings.apply(runtime)
  rawset(_G, registry_key, runtime)
  if valid_record(recovery) then restore(recovery, true) end
  return true
end

return M
