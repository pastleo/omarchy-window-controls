// Pure geometry/identity helpers, also exercised by the Node regression tests.
function validAddress(address) {
  return typeof address === "string" && /^0x[0-9a-fA-F]+$/.test(address)
}

function rectangle(window) {
  if (!window || !window.at || !window.size) return null
  var values = [window.at[0], window.at[1], window.size[0], window.size[1]]
  if (!values.every(function(value) { return typeof value === "number" && isFinite(value) })) return null
  if (values[2] <= 0 || values[3] <= 0) return null
  return { x: values[0], y: values[1], width: values[2], height: values[3] }
}

function intersects(a, b) {
  return a.x < b.x + b.width && a.x + a.width > b.x
    && a.y < b.y + b.height && a.y + a.height > b.y
}

// Keep both coordinates INSIDE the marker's screen, including a flush-right
// or flush-bottom tile. The exclusive screen bounds must not select a neighbor.
function menuAnchor(mark) {
  return { x: Math.floor(mark.x + mark.width - 1), y: Math.floor(mark.y + mark.height - 1) }
}

function menuPosition(x, y, width, height, screenWidth, screenHeight, preferLeft) {
  var gap = 8
  var px = preferLeft ? x - width + 1 : x + gap
  var py = y + gap
  if (!preferLeft && px + width > screenWidth - gap) px = x - width - gap
  if (py + height > screenHeight - gap) py = y - height - gap
  return {
    x: Math.max(gap, Math.min(px, screenWidth - width - gap)),
    y: Math.max(gap, Math.min(py, screenHeight - height - gap))
  }
}

function triangleMarker(window, monitor, windows, edge) {
  if (!window || !monitor || !validAddress(window.address) || window.floating
      || window.fullscreen || window.hidden || window.visible === false || !window.mapped
      || !window.workspace || window.workspace.id < 1
      || window.workspace.id !== monitor.workspace || window.monitor !== monitor.id
      || monitor.special) return null
  if ((window.tags || []).some(function(tag) {
    return tag === "omarchy-floating-workspace" || tag === "omarchy-floating-workspace*"
  })) return null
  var rect = rectangle(window)
  if (!rect || rect.width < edge || rect.height < edge) return null
  var mark = { x: rect.x + rect.width - edge, y: rect.y, width: edge, height: edge }
  if (mark.x < monitor.x || mark.y < monitor.y || mark.x + edge > monitor.x + monitor.width
      || mark.y + edge > monitor.y + monitor.height) return null
  for (var i = 0; i < windows.length; i++) {
    var other = windows[i]
    if (!other || other.address === window.address || !other.mapped || other.hidden
        || other.visible === false || !other.workspace) continue
    if (other.workspace.id !== monitor.workspace && !other.pinned) continue
    if (other.fullscreen && other.monitor === monitor.id) return null
    var covering = rectangle(other)
    if (other.floating && covering && intersects(mark, covering)) return null
  }
  return mark
}
