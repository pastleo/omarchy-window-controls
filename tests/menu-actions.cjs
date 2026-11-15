const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const actions = {};
vm.runInNewContext(fs.readFileSync('MenuActions.js', 'utf8'), actions);
for (const address of ['', 'foo', '0x12"; os.exit()', null]) {
  assert.throws(() => actions.opacityCode(address, 50));
  assert.throws(() => actions.workspaceCode(address, 2));
}
for (const value of [0, 9, 101, NaN, 50.5, '50'])
  assert.throws(() => actions.opacityCode('0xabc', value));
for (const value of [0, -1, Infinity, 1.5, '2', 2147483648])
  assert.throws(() => actions.workspaceCode('0xabc', value));
assert.equal(actions.opacityPercent('0.85\n'), 85);
for (const value of ['', 'error', 'ok', '-1', '1.1'])
  assert.equal(actions.opacityPercent(value), -1);
const choices = actions.workspaces([
  { id: 2, name: '<b>untrusted</b>' }, { id: -99, name: 'special' }, { id: 23, name: '23' }
], 12, [
  { name: 'left', activeWorkspace: { id: 1 } },
  { name: 'right', activeWorkspace: { id: 11 } }
], {});
assert.equal(choices.length, 21);
assert.equal(choices[0].id, 11);
assert.equal(choices[0].label, '1');
assert.equal(choices[0].screen, 'right');
assert.equal(choices[1].id, 12);
assert.equal(choices[1].label, '2');
assert.equal(choices[9].id, 20);
assert.equal(choices.find(c => c.id === 2).label, '2 · <b>untrusted</b>');
assert.equal(choices.find(c => c.id === 23).screen, 'Other workspaces');
assert.equal(choices.find(c => c.id === 23).label, '23');
const blocks = actions.readBlocks('1\tleft\tmetadata\n0\tright\tmetadata\nbad\tinvalid\tx\n-1\tnegative\tx');
assert.equal(blocks.left, 1);
assert.equal(blocks.right, 0);
assert.equal(blocks.invalid, undefined);
assert.equal(blocks.negative, undefined);
const persisted = actions.workspaces([], 12, [
  // A visiting workspace must not override the persisted block ownership.
  { name: 'left', activeWorkspace: { id: 1 } },
  { name: 'right', activeWorkspace: { id: 11 } }
], blocks);
assert.equal(persisted.find(c => c.id === 12).screen, 'left');
assert.equal(persisted.find(c => c.id === 2).screen, 'right');
assert.equal(actions.workspaces([], 1, [], {}).length, 10);
assert.ok(actions.opacityCode('0xabc', 95).includes('value="0.95"'));
const lua = `
local calls = {}
local w = { mapped=true, hidden=false, fullscreen=0, workspace={id=1} }
hl = {
  get_window=function(selector) assert(selector == "address:0xabc"); return w end,
  dispatch=function(action) calls[#calls+1] = action end,
  dsp={window={set_prop=function(t) return t end, move=function(t) return t end}}
}
local function opacity() ${actions.opacityCode('0xabc', 60)} end
local function move() ${actions.workspaceCode('0xabc', 12)} end
opacity()
assert(#calls == 4)
assert(calls[1].prop == "opacity" and calls[1].value == "0.60")
assert(calls[2].prop == "opacity_inactive")
assert(calls[3].prop == "opacity_override" and calls[3].value == "1")
assert(calls[4].prop == "opacity_inactive_override")
move()
assert(calls[5].workspace == "12" and calls[5].follow == false)
for _, action in ipairs(calls) do assert(action.window == "address:0xabc") end
for _, field in ipairs({"mapped", "hidden", "fullscreen", "workspace"}) do
  local original = w[field]
  if field == "mapped" then w[field]=false
  elseif field == "hidden" then w[field]=true
  elseif field == "fullscreen" then w[field]=1
  else w[field]={id=-99} end
  opacity(); move()
  assert(#calls == 5, "Stale/excluded window was acted on")
  w[field]=original
end
w = nil
opacity(); move()
assert(#calls == 5)
`;
execFileSync('lua', ['-'], { input: lua, stdio: ['pipe', 'inherit', 'inherit'] });
console.log('PASS: per-window opacity, workspace choices, safe native action dispatch');
