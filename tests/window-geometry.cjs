// Run from the project root: node tests/window-geometry.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const model = {};
vm.runInNewContext(fs.readFileSync('WindowGeometry.js', 'utf8'), model);
const monitor = { id: 1, x: -1920, y: -200, width: 1920, height: 1080, workspace: 4, special: false };
const tiled = { address: '0xabc', at: [-1900, -170], size: [900, 800], workspace: { id: 4 },
  monitor: 1, mapped: true, hidden: false, visible: true, floating: false, fullscreen: 0, tags: [] };
const marker = (window = tiled, windows = [window], screen = monitor) => model.triangleMarker(window, screen, windows, 14);
const point = marker();
assert.equal(point.x, -1014);
assert.equal(point.y, -170);
for (const change of [{ floating: true }, { fullscreen: 1 }, { fullscreen: 2 }, { hidden: true },
  { mapped: false }, { visible: false }, { workspace: { id: 5 } }, { workspace: { id: -1 } },
  { monitor: 2 }, { address: '0xabc;bad' }, { address: '<img src="https://example.invalid">' },
  { at: [NaN, 0] }, { size: [0, 100] }, { tags: ['omarchy-floating-workspace*'] },
  { tags: ['hypr-underlay'] }, { tags: ['hypr-underlay*'] }]) {
  assert.equal(marker({ ...tiled, ...change }), null, JSON.stringify(change));
}
assert.equal(marker(tiled, [tiled], { ...monitor, special: true }), null);
assert.equal(marker({ ...tiled, at: [-500, -170] }), null, 'off-screen scrolling tile');
const floating = { ...tiled, address: '0xdef', floating: true, at: [-1020, -175], size: [200, 200] };
assert.equal(marker(tiled, [tiled, floating]), null, 'covered triangle');
for (const tag of ['hypr-underlay', 'hypr-underlay*']) {
  assert.ok(marker(tiled, [tiled, { ...floating, tags: [tag], pinned: true }]),
    'Underlay background must not hide a foreground triangle');
  assert.equal(model.isBackground({ tags: [tag] }), true);
}
assert.equal(model.isBackground({ tags: ['not-hypr-underlay', 'hypr-underlay-extra'] }), false);
assert.equal(model.isBackground(null), false);
assert.ok(marker(tiled, [tiled, { ...floating, workspace: { id: 8 } }]));
assert.equal(marker(tiled, [tiled, { ...floating, workspace: { id: 8 }, pinned: true }]), null);
assert.ok(marker(tiled, [tiled, { ...floating, at: [-1500, 0] }]));
assert.equal(marker(tiled, [tiled, { ...floating, fullscreen: 2, at: [-1500, 0] }]), null);
assert.equal(model.validAddress('0xABC123'), true);
assert.equal(model.validAddress('address:0xabc'), false);
// Regression: a flush-right marker used to anchor exactly outside its screen.
const edgeAnchor = model.menuAnchor({ x: 2546, y: 0, width: 14, height: 14 });
assert.equal(edgeAnchor.x, 2559);
assert.equal(edgeAnchor.y, 13);
const leftAnchor = model.menuAnchor({ x: -14, y: -200, width: 14, height: 14 });
assert.equal(leftAnchor.x, -1, 'negative-coordinate monitor must retain ownership');
assert.equal(leftAnchor.y, -187);
for (const [x, y] of [[2559, 13], [2559, 1439], [0, 0], [0, 1439], [1279, 719]]) {
  for (const preferLeft of [true, false]) {
    const position = model.menuPosition(x, y, 180, 48, 2560, 1440, preferLeft);
    assert.ok(position.x >= 8 && position.x + 180 <= 2552);
    assert.ok(position.y >= 8 && position.y + 48 <= 1432);
    if (x === 2559) assert.ok(position.x + 180 <= x, 'right edge menu must open inward');
    if (y === 1439) assert.ok(position.y + 48 < y, 'bottom edge menu must open upward');
  }
}
assert.equal(model.menuPosition(900, 100, 180, 48, 2560, 1440, true).x, 721);
assert.equal(model.menuPosition(900, 100, 180, 48, 2560, 1440, true).y, 108);
console.log('PASS: tiled markers, workspace/occlusion safety, in-screen anchors and inward popup placement at every screen edge');
