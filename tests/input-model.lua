local controls = dofile("hypr/window-controls.lua")
local real_open = io.open
local modes = {}
io.open = function(path)
  local text = modes[path:match('([^/]+)$')]
  if text then return { read = function() return text end, close = function() end } end
end
local monitor = { id = 0, x = -1280, y = -100, width = 2560, height = 1600, scale = 2,
  active_workspace = { id = 1 } }
local window = { address = "0x123", mapped = true, floating = false, hidden = false,
  visible = true, fullscreen = 0, at = { x = -1200, y = 0 }, size = { x = 600, y = 500 },
  workspace = { id = 1 }, monitor = monitor }
local cursor = { x = -605, y = 3 }
local windows = { window }
assert(controls.is_tiling_workspace({ id = 1 }) and not controls.is_tiling_workspace({ id = -1 }))
assert(controls.hit_target(cursor, windows) == window, "scaled negative-origin triangle")
assert(controls.hit_target(cursor, windows, true) == nil, "floating-only menu detection")
for _, field in ipairs({ "fullscreen", "hidden", "mapped", "visible", "address", "workspace" }) do
  local original = window[field]
  window[field] = ({ fullscreen = 1, hidden = true, mapped = false, visible = false,
    address = "bad;code", workspace = { id = -1 } })[field]
  assert(controls.hit_target(cursor, windows) == nil, field)
  window[field] = original
end
monitor.active_special_workspace = { id = -1 }
assert(not controls.hit_target(cursor, windows))
monitor.active_special_workspace = nil
monitor.active_workspace.id = 2
assert(not controls.hit_target(cursor, windows))
monitor.active_workspace.id = 1
modes['1.lua'] = 'mode = "floating"'
assert(not controls.hit_target(cursor, windows))
modes['1.lua'] = nil
window.tags = { 'omarchy-floating-workspace*' }
assert(not controls.hit_target(cursor, windows))
window.tags = nil
local covering = { address = "0x456", mapped = true, visible = true, floating = true, fullscreen = 0,
  at = { x = -610, y = -5 }, size = { x = 200, y = 200 }, workspace = { id = 1 }, monitor = monitor }
windows = { window, covering }
assert(controls.hit_target(cursor, windows) ~= window, "covered triangle")
for _, tag in ipairs({ "hypr-underlay", "hypr-underlay*" }) do
  covering.tags = { tag }
  assert(controls.hit_target(cursor, windows) == window, "Underlay background does not cover triangle")
  assert(controls.hit_target({ x = covering.at.x - 3, y = covering.at.y + 100 }, { covering }) == nil,
    "background itself must not become an action target")
end
covering.tags = { "not-hypr-underlay", "hypr-underlay-extra" }
assert(controls.hit_target(cursor, windows) ~= window, "only exact integration tags are excluded")
covering.tags = nil
covering.workspace.id = 2
assert(controls.hit_target(cursor, windows) == window)
covering.pinned = true
assert(controls.hit_target(cursor, windows) ~= window, "pinned occlusion")
windows = { window }
window.floating = true
for _, point in ipairs({ {-1200, 250}, {-600, 250}, {-900, 0}, {-900, 500}, {-1203, 250}, {-900, -3} }) do
  assert(controls.hit_target({ x = point[1], y = point[2] }, windows) == window, "all floating borders")
end
for _, point in ipairs({ {-900, 250}, {-1199, 1}, {-1211, 250}, {-900, 511} }) do
  assert(not controls.hit_target({ x = point[1], y = point[2] }, windows), "content/outside border band")
end
covering.at = { x = -1300, y = -50 }; covering.size = { x = 900, y = 650 }
covering.workspace.id = 1; covering.pinned = false
cursor = { x = -1203, y = 250 } -- window's left border, inside covering's content
assert(controls.hit_target(cursor, { covering, window }) == window, "lower content cannot block top border")
assert(controls.hit_target(cursor, { window, covering }) == nil, "higher content blocks lower border")
covering.pinned = true
assert(controls.hit_target(cursor, { covering, window }) == nil, "pinned floats override vector order")
window.pinned = true
assert(controls.hit_target(cursor, { covering, window }) == window, "pinned peers use stacking order")
window.pinned = false; covering.pinned = false
covering.at.x = -1200 -- overlap both left grab bands
assert(controls.hit_target(cursor, { window, covering }) == covering, "overlapping borders choose top float")
assert(controls.hit_target(cursor, { covering, window }) == window, "raising changes border target")
covering.tags = { "hypr-underlay" }; covering.pinned = true
assert(controls.hit_target(cursor, { window, covering }) == window, "pinned Underlay cannot block border")
window.tags = { "hypr-underlay" }
assert(controls.hit_target(cursor, { covering, window }) == nil, "background windows are never selectable")
window.tags = nil; window.pinned = nil
window.floating = false
window.monitor = { id = 2, x = 2000, y = 1000, width = 2560, height = 1600,
  scale = 1.6000000238418579, active_workspace = { id = 1 } }
window.at = { x = 2000, y = 1026 }; window.size = { x = 1600, y = 974 }
assert(controls.hit_target({ x = 3596, y = 1029 }, windows) == window, "float32 scale flush-right")
window.at.y, window.size.y = 1986, 14
assert(controls.hit_target({ x = 3596, y = 1989 }, windows) == window, "float32 scale flush-bottom")
window.at.x = 2001
assert(not controls.hit_target({ x = 3596, y = 1989 }, windows), "genuinely off-screen marker")
window.at = { x = 2000, y = 1000 }; window.size = { x = 1000, y = 1600 }; window.monitor.transform = 1
assert(controls.hit_target({ x = 2996, y = 1003 }, windows) == window, "rotated fractional scale")
io.open = real_open
print("PASS: border-only input, triangle geometry, occlusion, workspaces, fractional scales and screen bounds")
