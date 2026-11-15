// Per-window actions only: no rules, desktop opacity or launch policy.
function validAddress(address) {
  return typeof address === "string" && /^0x[0-9a-fA-F]+$/.test(address)
}

function guarded(address, body) {
  if (!validAddress(address)) throw new Error("Invalid window address")
  return 'local w = hl.get_window("address:' + address + '"); '
    + 'if not w or not w.mapped or w.hidden or w.fullscreen ~= 0 '
    + 'or not w.workspace or w.workspace.id < 1 then return end; ' + body
}

function opacityCode(address, percent) {
  if (!Number.isInteger(percent) || percent < 10 || percent > 100)
    throw new Error("Invalid opacity")
  var value = (percent / 100).toFixed(2)
  return guarded(address, 'for _, prop in ipairs({"opacity", "opacity_inactive"}) do '
    + 'hl.dispatch(hl.dsp.window.set_prop({window="address:' + address
    + '", prop=prop, value="' + value + '"})); end; '
    + 'for _, prop in ipairs({"opacity_override", "opacity_inactive_override"}) do '
    + 'hl.dispatch(hl.dsp.window.set_prop({window="address:' + address
    + '", prop=prop, value="1"})); end')
}

function workspaceCode(address, id) {
  if (!Number.isInteger(id) || id < 1 || id > 2147483647)
    throw new Error("Invalid workspace")
  return guarded(address, 'hl.dispatch(hl.dsp.window.move({window="address:'
    + address + '", workspace="' + id + '", follow=false}))')
}

function opacityPercent(text) {
  var value = Number(String(text).trim())
  if (!String(text).trim() || !isFinite(value) || value < 0 || value > 1) return -1
  return Math.round(value * 100)
}

function readBlocks(text) {
  var blocks = Object.create(null)
  String(text || "").split("\n").forEach(function(line) {
    var fields = line.split("\t")
    if (fields.length >= 3 && /^\d+$/.test(fields[0]) && fields[1]
        && Number(fields[0]) < 214748364)
      blocks[fields[1]] = Number(fields[0])
  })
  return blocks
}

function workspaces(existing, current, monitors, blocks) {
  var byId = {}
  var owners = {}
  blocks = blocks || {}
  // Match Omarchy's bar: persisted connector blocks, with active-workspace
  // fallback until the compositor has written its state file.
  var screens = monitors || []
  screens.forEach(function(monitor) {
    var block = Object.prototype.hasOwnProperty.call(blocks, monitor.name) ? blocks[monitor.name] : undefined
    if (block === undefined && monitor.activeWorkspace && monitor.activeWorkspace.id > 0)
      block = Math.floor((monitor.activeWorkspace.id - 1) / 10)
    if (!Number.isInteger(block) || block < 0 || owners[block]) return
    owners[block] = monitor.name
  })
  var currentBlock = Math.floor((Math.max(1, current) - 1) / 10)
  function choice(id, name) {
    var block = Math.floor((id - 1) / 10)
    var screen = owners[block] || "Other workspaces"
    var number = owners[block] ? (id - 1) % 10 + 1 : id
    return { id: id, screen: screen, label: String(number)
      + (name && name !== String(id) ? " · " + name : ""), block: block }
  }
  Object.keys(owners).forEach(function(block) {
    for (var slot = 1; slot <= 10; slot++) {
      var id = Number(block) * 10 + slot
      byId[id] = choice(id, "")
    }
  })
  // Still offer empty local slots if monitor information is not ready.
  for (var slot = 1; slot <= 10; slot++) {
    var id = currentBlock * 10 + slot
    if (!byId[id]) byId[id] = choice(id, "")
  }
  existing.forEach(function(workspace) {
    var id = workspace.id
    if (!Number.isInteger(id) || id < 1 || id > 2147483647) return
    var name = String(workspace.name || id)
    byId[id] = choice(id, name)
  })
  var currentScreen = owners[currentBlock] || "Other workspaces"
  return Object.keys(byId).map(function(id) { return byId[id] }).sort(function(a, b) {
    if (a.screen !== b.screen) {
      if (a.screen === currentScreen) return -1
      if (b.screen === currentScreen) return 1
    }
    return a.screen.localeCompare(b.screen) || a.id - b.id
  })
}
