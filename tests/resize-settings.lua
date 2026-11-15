local settings = dofile("hypr/resize-settings.lua")
local values = { resize_on_border = false, extend_border_grab_area = 2, hover_icon_on_border = false }
local writes = 0
hl = {
  get_config = function(key) return values[assert(key:match("^general%.(.+)$"))] end,
  config = function(config)
    writes = writes + 1
    for section, options in pairs(config) do
      assert(section == "general", "Resize ownership must not affect decoration")
      for key, value in pairs(options) do
        assert(values[key] ~= nil, "Only the three native resize options are allowed")
        values[key] = value
      end
    end
  end,
}
local runtime = {}
assert(writes == 0, "Loading the helper must not change native settings")
settings.apply(runtime)
local baseline = runtime.resize_previous
assert(baseline.resize_on_border == false and baseline.extend_border_grab_area == 2 and baseline.hover_icon_on_border == false)
assert(values.resize_on_border == true and values.extend_border_grab_area == 8 and values.hover_icon_on_border == true)
settings.apply(runtime)
assert(writes == 1 and runtime.resize_previous == baseline, "Repeated activation preserves snapshot identity")
values.extend_border_grab_area = 13
runtime.owner = "replacement"
settings.apply(runtime)
assert(writes == 1 and values.extend_border_grab_area == 13, "Owner transfer must not overwrite external edits")
settings.restore(runtime)
assert(not runtime.resize_previous and writes == 2)
assert(values.resize_on_border == false and values.extend_border_grab_area == 13 and values.hover_icon_on_border == false)
settings.restore(runtime)
assert(writes == 2, "Repeated teardown is inert")
settings.apply(runtime)
assert(runtime.resize_previous.extend_border_grab_area == 13, "A new activation snapshots the new baseline")
values.resize_on_border = false
values.extend_border_grab_area = 20
values.hover_icon_on_border = false
settings.restore(runtime)
assert(writes == 3 and not runtime.resize_previous, "All externally changed options must remain untouched")
print("PASS: isolated resize ownership, owner transfer, conditional restoration and later external edits")
