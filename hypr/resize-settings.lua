-- Own only native resize behavior, never application decoration or layout.
local M = {}
local options = { resize_on_border = true, extend_border_grab_area = 8, hover_icon_on_border = true }

function M.apply(runtime)
  -- Preserve this field across owners: it is the original baseline, not the
  -- values currently applied by the plugin. Reapplying would lose user edits.
  if runtime.resize_previous then return end
  local previous = {}
  for key in pairs(options) do previous[key] = hl.get_config("general." .. key) end
  hl.config({ general = options })
  runtime.resize_previous = previous
end

function M.restore(runtime)
  if not runtime.resize_previous then return end
  local restore = {}
  for key, value in pairs(options) do
    if hl.get_config("general." .. key) == value then restore[key] = runtime.resize_previous[key] end
  end
  if next(restore) then hl.config({ general = restore }) end
  runtime.resize_previous = nil
end

return M
