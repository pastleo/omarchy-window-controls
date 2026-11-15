"""Lifecycle tests against an already-running DISPOSABLE nested Hyprland.

Refuses the inherited live runtime directory. Does not start/restart compositors.
"""
import argparse
import json
import os
from pathlib import Path
import re
import selectors
import socket
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime-dir', required=True, type=Path)
parser.add_argument('--signature', required=True)
args = parser.parse_args()
runtime = args.runtime_dir.resolve()
if runtime == Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid()))).resolve():
    parser.error('Use a separate disposable runtime, never the live desktop')
if not re.fullmatch(r'[A-Za-z0-9_-]+', args.signature):
    parser.error('Invalid compositor instance signature')
lock = runtime / 'hypr' / args.signature / 'hyprland.lock'
lines = lock.read_text().splitlines()
env = os.environ.copy()
env.update(XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE=args.signature,
           WAYLAND_DISPLAY=lines[1], QS_DISABLE_FILE_WATCHER='1', QS_NO_RELOAD_POPUP='1',
           WINDOW_CONTROLS_RUNTIME_SOURCE=(Path(__file__).resolve().parents[2] / 'RuntimeBindings.qml').as_uri())
events = socket.socket(socket.AF_UNIX)
events.settimeout(8)
events.connect(str(lock.parent / '.socket2.sock'))
# Seed a non-plugin baseline before the shell can install the runtime.
subprocess.run(['hyprctl', 'eval', 'hl.config({general={resize_on_border=false,extend_border_grab_area=2,hover_icon_on_border=false}})'],
               env=env, check=True, capture_output=True, timeout=5)
process = subprocess.Popen(['quickshell', '-p', str(Path(__file__).with_name('shell.qml'))],
                           env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
buffer = b''


def ready():
    global buffer
    deadline = time.monotonic() + 10
    while b'WINDOW_CONTROLS_READY' not in buffer:
        if not selector.select(max(0, deadline - time.monotonic())):
            raise TimeoutError(buffer.decode(errors='replace'))
        data = os.read(process.stdout.fileno(), 65536)
        if not data:
            raise RuntimeError(buffer.decode(errors='replace'))
        buffer += data
    buffer = buffer.split(b'WINDOW_CONTROLS_READY', 1)[1]


def lua(code):
    return subprocess.check_output(['hyprctl', 'repl', code], env=env, text=True, timeout=5).strip()


def call(method):
    subprocess.run(['quickshell', 'ipc', '--pid', str(process.pid), 'call', 'lifecycle', method],
                   env=env, check=True, capture_output=True, timeout=5)


def instrument():
    # Test-only event acknowledgment: wait for real async deactivation, no sleeps.
    lua('local r=_G.__omarchy_window_corners_runtime; local old=r.deactivate; '
        'r.deactivate=function() old(); hl.dispatch(hl.dsp.event("window-controls-test-disabled")) end; '
         '_G.controls_test_left=hl.bind("mouse:272",function()end,'
         '{non_consuming=true,description="Window controls left integration sentinel"}); '
         '_G.controls_test_right=hl.bind("mouse:273",function()end,'
         '{non_consuming=true,description="Window controls right integration sentinel"})')


def disabled():
    while b'custom>>window-controls-test-disabled' not in events.recv(65536):
        pass
    assert lua('return tostring(_G.__omarchy_window_corners_runtime.active)') == 'false'
    assert lua('return _G.controls_test_left:is_enabled()') == 'true'
    assert lua('return _G.controls_test_right:is_enabled()') == 'true'
    assert lua('return tostring(_G.__omarchy_window_corners_runtime.timer:is_enabled())') == 'false'


def resize_values():
    return lua('return tostring(hl.get_config("general.resize_on_border"))..","..'
               'tostring(hl.get_config("general.extend_border_grab_area"))..","..'
               'tostring(hl.get_config("general.hover_icon_on_border"))')


try:
    ready()
    assert resize_values() == 'true,8,true'
    baseline = 'false,2,false'
    instrument()
    for index in range(15):
        call('disable')
        disabled()
        assert resize_values() == baseline
        call('enable')
        ready()
        assert resize_values() == 'true,8,true'
        assert lua('return #_G.__omarchy_window_corners_runtime.bindings') == '5'
        assert lua('return _G.controls_test_left:is_enabled()') == 'true'
        assert lua('return _G.controls_test_right:is_enabled()') == 'true'
        if index == 6:
            # Reload must snapshot the actual file configuration, not our old
            # runtime values. The test's disposable config supplies this baseline.
            subprocess.run(['hyprctl', 'reload'], env=env, check=True, stdout=subprocess.DEVNULL)
            ready()
            assert resize_values() == 'true,8,true'
            baseline = lua('local p=_G.__omarchy_window_corners_runtime.resize_previous; '
                           'return tostring(p.resize_on_border)..","..tostring(p.extend_border_grab_area)..","..tostring(p.hover_icon_on_border)')
            instrument()
    lua('hl.config({general={extend_border_grab_area=13}})')
    call('disable')
    disabled()
    fields = baseline.split(','); fields[1] = '13'
    assert resize_values() == ','.join(fields), 'disable overwrote later external resize edit'
    print('PASS: 15 Quickshell cycles, reload, resize restoration/external edits, unrelated binding preservation')
finally:
    process.terminate()
    process.wait(timeout=10)
    lua('local b=_G.controls_test_left; '
        'if b and not tostring(b):find("(expired)",1,true) then b:set_enabled(false) end; '
        'b=_G.controls_test_right; '
        'if b and not tostring(b):find("(expired)",1,true) then b:set_enabled(false) end')
    events.close()
    selector.close()
