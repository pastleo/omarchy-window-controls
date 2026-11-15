-- Runtime regression tests with a deterministic native API/timer model.
local bindings, events, subscriptions, timers = {}, {}, {}, {}
local monitor = { id = 0, x = 0, y = 0, width = 1280, height = 800, scale = 1,
  active_workspace = { id = 1 } }
local window = { address = "0x123", mapped = true, visible = true, floating = true,
  fullscreen = 0, at = { x = 100, y = 100 }, size = { x = 400, y = 300 },
  monitor = monitor, workspace = { id = 1 } }
local cursor = { x = 97, y = 250 }
local real_open = io.open
local popup = false
local config = { resize_on_border = false, extend_border_grab_area = 2, hover_icon_on_border = false }
io.open = function() return nil end
hl = {
  get_config = function(key) return config[assert(key:match("^general%.(.+)$"))] end,
  config = function(options)
    for section, values in pairs(options) do
      assert(section == "general", "No decoration configuration")
      for key, value in pairs(values) do
        assert(config[key] ~= nil, "Only native border resize settings are allowed")
        config[key] = value
      end
    end
  end,
  unbind = function() error("No broad keybind removal") end,
  window_rule = function() error("No window policy") end,
  get_windows = function() return window and { window } or {} end,
  get_window = function(selector) return window and selector == "address:" .. window.address and window or nil end,
  get_cursor_pos = function() return cursor end,
  get_monitors = function() return { monitor } end,
  get_layers = function() return popup and { { mapped = true } } or {} end,
  dispatch = function(action) return action() end,
  on = function(name, callback) subscriptions[name] = callback; return {} end,
  bind = function(key, callback, flags)
    assert(flags.non_consuming or flags.auto_consuming)
    local handle = { enabled = true, expired = false, callback = callback, flags = flags }
    setmetatable(handle, { __tostring = function(self) return self.expired and "HL.Keybind(expired)" or "HL.Keybind(test)" end })
    function handle:set_enabled(value) assert(not self.expired); self.enabled = value end
    function handle:remove() error("Unsafe native handle removal") end
    bindings[#bindings + 1] = handle
    return handle
  end,
  timer = function(callback, options)
    assert(options.timeout == 16 and options.type == "repeat")
    local timer = { callback = callback, enabled = true }
    function timer:set_enabled(value) self.enabled = value end
    timers[#timers + 1] = timer
    return timer
  end,
  dsp = {
    focus = function() return function() return { ok = true } end end,
    event = function(text) return function() events[#events + 1] = text end end,
    window = {
      drag = function() error("Press-and-hold drag must be removed") end,
      float = function(options) return function() window.floating = options.action == "on"; return { ok = true } end end,
      move = function(options) return function()
        assert(options.window == "address:" .. window.address)
        if options.x then window.at = { x = options.x, y = options.y } end
        if options.workspace then window.workspace = { id = tonumber(options.workspace) } end
        return { ok = true }
      end end,
    },
  },
}
local controls = dofile("hypr/window-controls.lua")
assert(#bindings == 0)
assert(controls.install("owner-1") and #bindings == 5 and #timers == 1)
assert(config.resize_on_border and config.extend_border_grab_area == 8 and config.hover_icon_on_border)
assert(controls.install("owner-1") and #bindings == 5 and #timers == 1)
local runtime = _G.__omarchy_window_corners_runtime
local function call(index) return bindings[index].callback() end
assert(not runtime.timer.enabled, "idle timer must be disarmed")
popup = true
assert(call(1).pass_event and call(3).pass_event, "popup clicks must not retarget underlying borders")
call(2); call(4)
assert(#events == 0 and not runtime.moving)
popup = false
assert(call(1).pass_event); call(2)
assert(events[#events] == "window-corners-menu:owner-1:0x123:97:250", "left border menu")
local count = #events
call(1); cursor.y = 280; call(2)
assert(#events == count, "left drag must not open a menu")
cursor.y = 250
assert(not call(3).pass_event)
assert(not runtime.moving, "right press alone must not pick up")
cursor.y = 280; call(4)
assert(not runtime.moving, "right drag must not pick up on release")
cursor.y = 250
call(3); call(4)
assert(runtime.moving and runtime.timer.enabled, "right click latches movement after release")
cursor.x, cursor.y = 250, 350
runtime.timer.callback()
assert(window.at.x == 250 and window.at.y == 200, "cursor following without held buttons")
assert(not call(1).pass_event, "drop click must be consumed")
call(2)
assert(not runtime.moving and not runtime.timer.enabled and window.floating)
local old = { x = window.at.x, y = window.at.y }
assert(runtime.start_move(window.address))
cursor.x = 500; runtime.timer.callback()
assert(not call(5).pass_event and not runtime.moving, "Escape cancels and consumes")
assert(window.at.x == old.x and window.at.y == old.y, "cancel restores floating position")
assert(call(5).pass_event, "Escape stays normal while idle")
window.floating = false
assert(runtime.start_move(window.address) and window.floating)
runtime.deactivate()
assert(not config.resize_on_border and config.extend_border_grab_area == 2 and not config.hover_icon_on_border,
  "disable restores pre-plugin resize settings")
assert(not window.floating and not runtime.moving and not runtime.timer.enabled, "disable restores tiled target")
for _, handle in ipairs(bindings) do assert(not handle.enabled) end
assert(controls.install("owner-2") and #bindings == 5 and #timers == 1)
assert(runtime.owner == "owner-2")
assert(config.resize_on_border and config.extend_border_grab_area == 8 and config.hover_icon_on_border)
config.extend_border_grab_area = 12
assert(controls.install("replacement") and runtime.owner == "replacement")
runtime.deactivate()
assert(config.extend_border_grab_area == 12 and not config.resize_on_border and not config.hover_icon_on_border,
  "owner replacement retains baseline; disable preserves later external edits")
runtime.deactivate()
assert(config.extend_border_grab_area == 12, "repeated disable is inert")
assert(controls.install("owner-2"))
assert(runtime.start_move(window.address))
window.visible = false
subscriptions['workspace.active']()
assert(not runtime.moving and not window.floating, "workspace switch cancels")
window.visible = true
assert(runtime.start_move(window.address))
local saved = window; window = nil
runtime.timer.callback()
assert(not runtime.moving and not runtime.timer.enabled, "closed target stops timer")
window = saved
window.floating = false
_G.__omarchy_window_corners_cancelled = { retired = true }
assert(not controls.install("retired") and runtime.owner == "owner-2")
assert(not pcall(controls.install, 'bad"owner'))
for _, handle in ipairs(bindings) do handle.expired = true end
assert(controls.install("owner-3") and #bindings == 10 and #timers == 2, "safe expiry recovery")
runtime = _G.__omarchy_window_corners_runtime
runtime.deactivate()
_G.__omarchy_window_corners_runtime = nil
window.floating = true
local recovery = { address = window.address, tiled = true, workspace = 1, x = 100, y = 100, width = 400, height = 300 }
assert(controls.install("reloaded", recovery) and not window.floating, "reload recovery rejoins tiling")
assert(not _G.__omarchy_window_corners_runtime.timer.enabled)
io.open = real_open
print("PASS: border menus, click-vs-drag, sticky movement/drop/Escape, lifecycle, timer reuse and reload recovery")
