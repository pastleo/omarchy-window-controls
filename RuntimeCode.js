// Legacy registry/event names are compatibility contracts shared with Lua.
function luaString(value) {
  return '"' + String(value).replace(/[\x00-\x1f\\"]/g, function(character) {
    return "\\" + ("000" + character.charCodeAt(0)).slice(-3)
  }) + '"'
}

function localPath(url) {
  var value = String(url)
  if (!/^(file|qs):\/\/\//.test(value)) throw new Error("Window controls helper must be a local file")
  var path = decodeURIComponent(value.replace(/^(file|qs):\/\//, ""))
  if (path.charAt(0) !== "/" || path.indexOf("\x00") >= 0) throw new Error("Invalid window controls helper path")
  return path
}

function recordCode(record) {
  if (!record) return "nil"
  if (!/^0x[0-9a-fA-F]+$/.test(record.address) || typeof record.tiled !== "boolean") throw new Error("Invalid move record")
  var keys = ["workspace", "x", "y", "width", "height"]
  var fields = ["address=" + luaString(record.address), "tiled=" + record.tiled]
  keys.forEach(function(key) {
    var value = record[key]
    if (typeof value !== "number" || !isFinite(value) || Math.floor(value) !== value || Math.abs(value) > 10000000)
      throw new Error("Invalid move geometry")
    fields.push(key + "=" + value)
  })
  if (record.workspace < 1 || record.width < 1 || record.height < 1) throw new Error("Invalid move dimensions")
  return "{" + fields.join(",") + "}"
}

function parseMoveEvent(data, owner) {
  var prefix = "window-corners-move:" + owner + ":"
  if (!owner || typeof data !== "string" || data.indexOf(prefix) !== 0) return undefined
  var tail = data.slice(prefix.length)
  if (tail === "") return null
  var fields = tail.split(":")
  if (fields.length !== 7 || !/^0x[0-9a-fA-F]+$/.test(fields[0]) || !/^[01]$/.test(fields[1])) return undefined
  if (!fields.slice(2).every(function(value) { return /^-?\d+$/.test(value) })) return undefined
  var record = { address: fields[0], tiled: fields[1] === "1", workspace: Number(fields[2]),
    x: Number(fields[3]), y: Number(fields[4]), width: Number(fields[5]), height: Number(fields[6]) }
  try { recordCode(record) } catch (error) { return undefined }
  return record
}

function parseMenuEvent(data, owner) {
  var prefix = "window-corners-menu:" + owner + ":"
  if (!owner || typeof data !== "string" || data.indexOf(prefix) !== 0) return undefined
  var fields = data.slice(prefix.length).split(":")
  if (fields.length !== 3 || !/^0x[0-9a-fA-F]+$/.test(fields[0])
      || !/^-?\d+$/.test(fields[1]) || !/^-?\d+$/.test(fields[2])) return undefined
  var x = Number(fields[1]), y = Number(fields[2])
  if (Math.abs(x) >= 10000000 || Math.abs(y) >= 10000000) return undefined
  return { address: fields[0], x: x, y: y }
}

function installCode(path, owner, recovery) {
  return "assert(dofile(" + luaString(path) + ").install(" + luaString(owner) + "," + recordCode(recovery)
    + "), 'Window controls owner already retired')"
}

function startMoveCode(owner, address) {
  if (!/^0x[0-9a-fA-F]+$/.test(address)) throw new Error("Invalid window address")
  return 'local r=rawget(_G,"__omarchy_window_corners_runtime"); if r and r.owner==' + luaString(owner)
    + ' and r.active then r.start_move(' + luaString(address) + ') end'
}

function deactivateCode(owner) {
  // Tombstones also cover a quick unload racing an in-flight installation.
  return 'local cancelled = rawget(_G, "__omarchy_window_corners_cancelled") or {}; '
    + 'rawset(_G, "__omarchy_window_corners_cancelled", cancelled); '
    + "cancelled[" + luaString(owner) + "] = true; "
    + 'local runtime = rawget(_G, "__omarchy_window_corners_runtime"); '
    + "if runtime and runtime.owner == " + luaString(owner) + " then runtime.deactivate() end"
}
