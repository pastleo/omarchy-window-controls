const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const manifest = JSON.parse(fs.readFileSync('manifest.json', 'utf8'));
assert.equal(manifest.id, 'pastleo.window-controls');
assert.equal(manifest.name, 'Window controls');
assert.equal(manifest.entryPoints.service, 'WindowControls.qml');
const service = fs.readFileSync(manifest.entryPoints.service, 'utf8');
assert.ok(service.includes('target: "' + manifest.id + '"'));
assert.equal(service.includes('target: "pastleo.floating-corners"'), false, 'Old IPC endpoint must be retired');
assert.ok(fs.readFileSync('tests/integration/click_move.py', 'utf8').includes("'pastleo.window-controls'"));
assert.ok(service.includes('namespace: "pastleo-floating-corners"'));
assert.ok(fs.readFileSync('TiledTriangles.qml', 'utf8').includes('namespace: "pastleo-tiled-corner"'));
const runtime = fs.readFileSync('hypr/window-controls.lua', 'utf8');
const code = {};
vm.runInNewContext(fs.readFileSync('RuntimeCode.js', 'utf8'), code);
for (const key of ['__omarchy_window_corners_runtime', '__omarchy_window_corners_cancelled']) {
  assert.ok(runtime.includes('"' + key + '"'));
  assert.ok(code.deactivateCode('old-owner').includes('"' + key + '"'));
}
assert.ok(runtime.includes('local runtime_version = 6'), 'Pure refactor must preserve live resize baseline/handles');
assert.ok(runtime.includes('window-corners-'));
assert.ok(code.parseMenuEvent('window-corners-menu:new-owner:0xabc:10:20', 'new-owner'));
assert.ok(code.parseMoveEvent('window-corners-move:new-owner:0xabc:1:1:10:20:100:100', 'new-owner'));
for (const file of ['CornerMenu.qml', 'CornerModel.js', 'TiledCorners.qml', 'hypr/corner-menu.lua']) {
  assert.equal(fs.existsSync(file), false, 'Obsolete entry point must not remain: ' + file);
}
console.log('PASS: migrated public ID/IPC with shared runtime identifiers and resize-safe owner handover');
