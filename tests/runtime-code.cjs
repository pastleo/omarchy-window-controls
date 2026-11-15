const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const code = {};
vm.runInNewContext(fs.readFileSync('RuntimeCode.js', 'utf8'), code);
for (const value of ['/home/me/plugin/hypr/window-controls.lua', '/tmp/a "quote" and \\ slash',
  '/tmp/中文/プラグイン.lua', '/tmp/line\nreturn os.execute("oops")', '\0\x01\x1f',
  '"); os.execute("touch /tmp/should-not-exist"); --']) {
  const result = execFileSync('lua', ['-e', 'os.execute=function() error("code injection") end; io.write(' + code.luaString(value) + ')']);
  assert.equal(result.toString(), value);
}
assert.equal(code.localPath('qs:///home/me/a%20b/hypr/window-controls.lua'), '/home/me/a b/hypr/window-controls.lua');
assert.equal(code.localPath('file:///tmp/a%23b.lua'), '/tmp/a#b.lua');
for (const url of ['https://example.invalid/helper.lua', 'file://server/helper.lua', 'file:///tmp/%00']) assert.throws(() => code.localPath(url));
const path = '/tmp/odd "path".lua';
execFileSync('lua', ['-e', 'dofile=function(path) assert(path == ' + code.luaString(path) + '); return {install=function(owner) assert(owner=="test-owner"); return true end} end; ' + code.installCode(path, 'test-owner')]);
for (const owner of ['old-owner', 'new-owner']) {
  const result = execFileSync('lua', ['-e', 'local disabled=false; _G.__omarchy_window_corners_runtime={owner="new-owner",deactivate=function() disabled=true end}; '
    + code.deactivateCode(owner) + '; assert(_G.__omarchy_window_corners_cancelled[' + code.luaString(owner) + ']); io.write(tostring(disabled))']);
  assert.equal(result.toString(), owner === 'new-owner' ? 'true' : 'false');
}
console.log('PASS: path resolution, Lua string safety, owner-scoped deactivation and cancellation tombstones');
const recovery = { address: '0xabc', tiled: true, workspace: 1, x: -500, y: 20, width: 600, height: 400 };
const event = 'window-corners-move:test-owner:0xabc:1:1:-500:20:600:400';
assert.equal(JSON.stringify(code.parseMoveEvent(event, 'test-owner')), JSON.stringify(recovery));
assert.equal(code.parseMoveEvent('window-corners-move:test-owner:', 'test-owner'), null);
for (const data of [event.replace('test-owner', 'other'), event + ':extra', event.replace('600', 'NaN'),
  event.replace('0xabc', 'x;bad'), event.replace(':400', ':0')]) assert.equal(code.parseMoveEvent(data, 'test-owner'), undefined);
for (const record of [{ ...recovery, x: Infinity }, { ...recovery, address: '0xabc;command' },
  { ...recovery, width: 0 }, { ...recovery, workspace: -1 }, { ...recovery, y: '1;command' }]) assert.throws(() => code.recordCode(record));
execFileSync('lua', ['-e', 'dofile=function() return {install=function(owner,r) assert(owner=="o" and r.address=="0xabc" and r.tiled and r.x==-500);return true end} end; ' + code.installCode('/test.lua', 'o', recovery)]);
for (const owner of ['old', 'new']) {
  const result = execFileSync('lua', ['-e', 'local moved=false;_G.__omarchy_window_corners_runtime={owner="new",active=true,start_move=function(a)assert(a=="0xabc");moved=true end};'
    + code.startMoveCode(owner, '0xabc') + ';io.write(tostring(moved))']);
  assert.equal(result.toString(), owner === 'new' ? 'true' : 'false');
}
assert.throws(() => code.startMoveCode('owner', '0xabc;command'));
console.log('PASS: move event/recovery validation, safe encoding and owner-scoped pickup');
const menu = 'window-corners-menu:controls-owner:0xabc:-100:20';
assert.equal(JSON.stringify(code.parseMenuEvent(menu, 'controls-owner')), JSON.stringify({ address: '0xabc', x: -100, y: 20 }));
for (const data of [null, menu.replace('controls-owner', 'other'), menu + ':extra',
  menu.replace('0xabc', '<img>'), menu.replace('-100', '1;command'), menu.replace('-100', '10000000'),
  menu.replace(':20', ':NaN')]) assert.equal(code.parseMenuEvent(data, 'controls-owner'), undefined);
assert.equal(code.parseMenuEvent(menu, ''), undefined);
const os = require('node:os');
const pathModule = require('node:path');
const directory = fs.mkdtempSync(pathModule.join(os.tmpdir(), 'window-controls-'));
try {
  const relocated = pathModule.join(directory, 'quoted " controls 中文');
  fs.mkdirSync(relocated);
  for (const file of ['window-controls.lua', 'resize-settings.lua']) fs.copyFileSync('hypr/' + file, pathModule.join(relocated, file));
  execFileSync('lua', ['-e', 'assert(type(dofile(' + code.luaString(pathModule.join(relocated, 'window-controls.lua')) + ').install)=="function")']);
  execFileSync('lua', ['-e', 'assert(type(dofile("window-controls.lua").install)=="function")'], { cwd: relocated });
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
console.log('PASS: owner-scoped menu events and sibling helper resolution from relocated paths');
