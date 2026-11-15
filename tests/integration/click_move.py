"""Real click-to-move/UI checks in an empty DISPOSABLE nested Hyprland.

Requires one 1280x800 scale-1 output and a compiled virtual-pointer helper.
Optional --multi-monitor creates/removes one test-owned fractional-scale output.
"""
import argparse
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime-dir', required=True, type=Path)
parser.add_argument('--signature', required=True)
parser.add_argument('--pointer', required=True, type=Path)
parser.add_argument('--shell-source', type=Path, default=Path('/usr/share/omarchy/shell'))
parser.add_argument('--multi-monitor', action='store_true')
parser.add_argument('--placement-only', action='store_true',
                    help='Run isolated directional-drop regressions, then clean up')
parser.add_argument('--occlusion-only', action='store_true',
                    help='Run isolated Underlay-tag and floating-stack regressions')
parser.add_argument('--underlay-plugin', type=Path,
                    help='Optional existing Underlay library, loaded only in the disposable compositor')
args = parser.parse_args()
if args.placement_only and args.occlusion_only:
    parser.error('Choose only one isolated regression mode')
if args.underlay_plugin and not args.occlusion_only:
    parser.error('--underlay-plugin requires --occlusion-only')
runtime = args.runtime_dir.resolve()
live = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid()))).resolve()
if runtime == live:
    parser.error('Use a separate disposable runtime, never the live desktop')
if not re.fullmatch(r'[A-Za-z0-9_-]+', args.signature):
    parser.error('Invalid compositor instance signature')
lock = runtime / 'hypr' / args.signature / 'hyprland.lock'
env = os.environ.copy()
env.update(XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE=args.signature,
           WAYLAND_DISPLAY=lock.read_text().splitlines()[1],
           QS_DISABLE_FILE_WATCHER='1', QS_NO_RELOAD_POPUP='1',
           WINDOW_CONTROLS_SOURCE=(Path(__file__).resolve().parents[2] / 'WindowControls.qml').as_uri())
source = Path(__file__).resolve().parent
processes = []
pointer = None
service = None
output = None
underlay_loaded = False


def ctl(*arguments):
    return subprocess.check_output(['hyprctl', *arguments], env=env, text=True, timeout=5).strip()


def lua(code):
    return ctl('repl', code)


def dispatch(expression):
    return ctl('dispatch', expression)


def ipc(process, target, method, *arguments):
    return subprocess.check_output(['quickshell', 'ipc', '--pid', str(process.pid), 'call', '--',
                                    target, method, *map(str, arguments)], env=env, text=True, timeout=5,
                                   stderr=subprocess.DEVNULL).strip()


def status():
    try:
        return json.loads(ipc(service, 'pastleo.window-controls', 'status'))
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return {}


def wait(predicate, message):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.04)
    raise AssertionError(message)


def clients():
    return json.loads(ctl('-j', 'clients'))


def client(address):
    return next((window for window in clients() if window['address'] == address), None)


def act(address, action, fields=''):
    dispatch('hl.dsp.window.' + action + '({' + (fields + ',' if fields else '')
             + 'window="address:' + address + '"})')


def counts():
    return json.loads(ipc(apps, 'client-test', 'counts'))


def send(command):
    pointer.stdin.write(command + '\n')
    pointer.stdin.flush()
    with selectors.DefaultSelector() as selector:
        selector.register(pointer.stdout, selectors.EVENT_READ)
        if not selector.select(5):
            raise TimeoutError('Virtual pointer acknowledgment')
        assert pointer.stdout.readline().strip() == 'ok'
    time.sleep(.08)


def move(x, y):
    monitors = json.loads(ctl('-j', 'monitors'))
    left = min(m['x'] for m in monitors)
    top = min(m['y'] for m in monitors)
    right = max(m['x'] + round(m['width'] / m['scale']) for m in monitors)
    bottom = max(m['y'] + round(m['height'] / m['scale']) for m in monitors)
    send(f'move {round((x-left)/(right-left)*1280)} {round((y-top)/(bottom-top)*800)}')


def button(state, code=272):
    send(f'button {code} {state}')


def click(x, y, code=272):
    move(x, y); button(1, code); button(0, code)


def marker(address):
    def settled_marker():
        window = client(address)
        if not window:
            return None
        return next((mark for mark in status().get('markers', [])
                     if mark['address'] == address
                     and mark['x'] == window['at'][0] + window['size'][0] - mark['size']
                     and mark['y'] == window['at'][1]), None)
    return wait(settled_marker, 'Triangle missing or geometry not settled')


def pickup(address):
    mark = marker(address)
    click(mark['x'] + 10, mark['y'] + 3, 273)
    wait(lambda: status().get('movingAddress') == address, 'Right click did not pick up')
    wait(lambda: client(address)['floating'], 'Tiled pickup did not float')


def drop():
    before = counts()[0]
    button(1); button(0)
    wait(lambda: status().get('movingAddress') == '', 'Left click did not place')
    assert counts()[0] == before, 'Drop click leaked into an application'
    assert lua('return tostring(_G.__omarchy_window_corners_runtime.timer:is_enabled())') == 'false'


def escape():
    subprocess.run(['wtype', '-k', 'Escape'], env=env, check=True, timeout=5)
    wait(lambda: status().get('movingAddress') == '', 'Escape did not cancel')


def menu_item(index):
    menu_control(['close', 'move', 'state'][index])


def menu_control(name):
    menu = wait(lambda: status().get('menus'), 'Menu missing')[0]
    rect = menu['controls'][name]
    click(rect['x'] + rect['width'] / 2, rect['y'] + rect['height'] / 2)


def check_extra_actions(address, floating):
    other = next(window for window in clients() if window['address'] != address)
    other_opacity = ctl('getprop', 'address:' + other['address'], 'opacity')
    def open_menu():
        if floating:
            w = client(address)
            click(w['at'][0]-3, w['at'][1]+100)
        else:
            mark = marker(address)
            click(mark['x']+10, mark['y']+3)
        wait(lambda: status().get('opened'), 'Action menu missing')
        wait(lambda: status().get('opacityPercent', -1) >= 0, 'Opacity read failed')

    open_menu()
    assert 'opacityDown' not in status()['menus'][0]['controls'], 'Opacity controls leaked into main menu'
    menu_control('opacity')
    wait(lambda: status().get('opacityMenu'), 'Opacity submenu missing')
    menu_control('opacityDown')
    wait(lambda: status().get('opacityPercent') == 95, 'Opacity decrease failed')
    assert float(ctl('getprop', 'address:' + address, 'opacity')) == .95
    assert float(ctl('getprop', 'address:' + address, 'opacity_inactive')) == .95
    assert ctl('getprop', 'address:' + other['address'], 'opacity') == other_opacity
    assert status()['opened'], 'Opacity adjustment dismissed menu'
    menu_control('opacityUp')
    wait(lambda: status().get('opacityPercent') == 100, 'Opacity increase failed')
    # The applied value is read back when reopening rather than cached by address.
    subprocess.run(['wtype', '-k', 'Escape'], env=env, check=True, timeout=5)
    wait(lambda: status().get('opened') and not status().get('opacityMenu'), 'Opacity submenu Escape failed')
    subprocess.run(['wtype', '-k', 'Escape'], env=env, check=True, timeout=5)
    wait(lambda: not status().get('opened'), 'Main-menu Escape failed')
    open_menu()
    assert status()['opacityPercent'] == 100
    menu_control('workspaces')
    wait(lambda: status().get('workspaceMenu'), 'Workspace submenu missing')
    subprocess.run(['wtype', '-k', 'Escape'], env=env, check=True, timeout=5)
    wait(lambda: status().get('opened') and not status().get('workspaceMenu'), 'Submenu Escape failed')
    menu_control('workspaces')
    menu_control('workspace2')
    wait(lambda: client(address)['workspace']['id'] == 2, 'Workspace move failed')
    assert client(address)['floating'] == floating
    assert client(other['address'])['workspace'] == other['workspace'], 'Wrong window moved'
    assert json.loads(ctl('-j', 'monitors'))[0]['activeWorkspace']['id'] == 1, 'Workspace move followed target'
    assert not status()['opened']
    act(address, 'move', 'workspace="1",follow=false')
    time.sleep(.35)
    if floating:
        original = client(address)['at']
        act(address, 'move', 'x=860,y=500')
        time.sleep(.3)
        open_menu()
        for submenu in [False, True]:
            if submenu:
                menu_control('workspaces')
            menu = wait(lambda: status().get('menus'), 'Edge menu missing')[0]
            assert (menu['x'] >= 0 and menu['y'] >= 0
                    and menu['x'] + menu['width'] <= 1280
                    and menu['y'] + menu['height'] <= 800), 'Expanded menu escaped screen'
        click(100, 750)
        wait(lambda: not status().get('opened'), 'Submenu outside-click failed')
        act(address, 'move', f'x={original[0]},y={original[1]}')
        time.sleep(.3)


def launch(qml, log):
    with open(log, 'w') as stream:
        process = subprocess.Popen(['quickshell', '-p', str(qml)], env=env, stdout=stream, stderr=stream)
    processes.append(process)
    return process


def check_occlusion(a, b):
    global underlay_loaded

    def close_menu():
        subprocess.run(['wtype', '-k', 'Escape'], env=env, check=True, timeout=5)
        wait(lambda: not status().get('opened'), 'Menu Escape failed')
        wait(lambda: lua('for _,l in ipairs(hl.get_layers({namespace="pastleo-floating-corners"})) do '
                         'if l.mapped then return false end end return true') == 'true', 'Menu layer did not unmap')

    def menu_at(address, x, y):
        click(x, y)
        wait(lambda: status().get('opened'), 'Stacked border/triangle menu did not open')
        assert status()['address'] == address, ('Wrong stacked menu target', status())
        close_menu()

    def move_at(address, x, y):
        before = counts()[1]
        click(x, y, 273)
        wait(lambda: status().get('movingAddress') == address, 'Stacked handle did not pick up selected window')
        assert counts()[1] == before, 'Handle right press leaked into application'
        escape()

    def content_at(x, y):
        before = counts()
        click(x, y, 273); click(x, y)
        after = counts()
        assert not status()['opened'] and not status()['movingAddress'], 'Covered lower border stole content input'
        assert after[0] == before[0] + 1 and after[1] == before[1] + 1, 'Content clicks were consumed'

    act(b, 'float', 'action="on"')
    act(b, 'resize', 'x=1280,y=800'); act(b, 'move', 'x=0,y=0')
    time.sleep(.35)
    wait(lambda: all(m['address'] != a for m in status()['markers']), 'Ordinary full-screen float must cover triangle')
    if args.underlay_plugin:
        assert ctl('plugin', 'load', str(args.underlay_plugin.resolve())) == 'ok'
        underlay_loaded = True
    # Loading/unloading a native plugin may reload compositor configuration.
    # Install test rules afterward, just as the real Underlay controller does.
    lua('_G.window_controls_test_underlay_rule=hl.window_rule({match={tag="hypr-underlay"},'
        'no_focus=true,no_follow_mouse=true})')
    act(b, 'tag', 'tag="+hypr-underlay"')
    act(b, 'pin', 'action="on"')
    if underlay_loaded:
        assert ctl('underlay', 'on', 'address:' + b) == 'ok'
        wait(lambda: json.loads(ctl('underlay-status'))['background_frames'] > 0, 'Underlay did not render background')
    mark = marker(a)
    menu_at(a, mark['x'] + 10, mark['y'] + 3)
    move_at(a, mark['x'] + 10, mark['y'] + 3)
    assert not client(a)['floating'] and client(b)['floating'] and client(b)['pinned']
    act(a, 'float', 'action="on"')
    act(a, 'resize', 'x=420,y=300'); act(a, 'move', 'x=350,y=250')
    time.sleep(.35)
    menu_at(a, 347, 400); move_at(a, 347, 400)
    assert client(b)['at'] == [0, 0] and client(b)['size'] == [1280, 800], 'Background was modified'
    assert lua('return tostring(_G.__omarchy_window_corners_runtime.start_move("' + b + '"))') == 'false'
    print('PASS: Underlay-tag background preserves tiled menus/pickup and floating border controls; background is excluded')
    if underlay_loaded:
        assert ctl('underlay', 'off') == 'ok'
    lua('_G.window_controls_test_underlay_rule:set_enabled(false); _G.window_controls_test_underlay_rule=nil')
    act(b, 'tag', 'tag="-hypr-underlay"'); act(b, 'pin', 'action="off"')
    if underlay_loaded:
        assert ctl('plugin', 'unload', str(args.underlay_plugin.resolve())) == 'ok'
        underlay_loaded = False
        wait(lambda: lua('local r=_G.__omarchy_window_corners_runtime; return tostring(r and r.active)') == 'true',
             'Runtime did not reinstall after native plugin unload')
    act(b, 'resize', 'x=600,y=450'); act(b, 'move', 'x=200,y=200')
    act(a, 'alter_zorder', 'mode="top"')
    time.sleep(.35)
    menu_at(a, 347, 400) # Upper A border inside lower B content.
    act(b, 'resize', 'x=500,y=400'); act(b, 'move', 'x=500,y=200')
    act(b, 'alter_zorder', 'mode="top"')
    time.sleep(.35)
    content_at(773, 400) # Lower A border inside higher B content.
    menu_at(b, 497, 400); move_at(b, 497, 400)
    menu_at(a, 347, 400) # Exposed border of lower A remains usable.
    act(a, 'alter_zorder', 'mode="top"')
    menu_at(a, 773, 400); move_at(a, 773, 400)
    content_at(497, 400) # Lower B border inside higher A content.
    act(b, 'pin', 'action="on"'); act(b, 'alter_zorder', 'mode="bottom"')
    order = lua('local t={} for _,w in ipairs(hl.get_windows()) do t[#t+1]=w.address end '
                'return table.concat(t,",")').split(',')
    assert order.index(b) < order.index(a), 'Pinned fixture must oppose vector order'
    menu_at(b, 497, 400); move_at(b, 497, 400)
    print('PASS: overlapping floating menus/pickup, exposed lower borders, content pass-through, reversed z-order and pinned priority')


monitors = json.loads(ctl('-j', 'monitors'))
if len(monitors) != 1 or monitors[0]['width'] != 1280 or monitors[0]['height'] != 800 or monitors[0]['scale'] != 1:
    parser.error('This harness needs one disposable 1280x800, scale-1 monitor')
if clients():
    parser.error('Use an empty disposable compositor; existing windows will not be touched')

with tempfile.TemporaryDirectory(prefix='move-', dir=runtime) as directory:
    work = Path(directory)
    for module in ['Commons', 'Ui']:
        (work / module).symlink_to(args.shell_source / module, target_is_directory=True)
    shutil.copyfile(source / 'move-shell.qml', work / 'shell.qml')
    try:
        apps = launch(source / 'move-clients.qml', work / 'clients.log')
        wait(lambda: len(clients()) == 2, 'Test clients failed to map')
        service = launch(work / 'shell.qml', work / 'shell.log')
        wait(lambda: status().get('bindingsInstalled'), 'Service installation failed')
        pointer = subprocess.Popen([str(args.pointer.resolve())], env=env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, text=True)
        a, b = [window['address'] for window in clients()]
        if args.occlusion_only:
            check_occlusion(a, b)
            raise SystemExit(0)
        w = client(a); x, y = w['at'][0] + 100, w['at'][1] + 100
        before = counts()
        click(x, y, 273); click(x, y)
        after = counts()
        assert after[0] == before[0] + 1 and after[1] == before[1] + 1 and after[2] == before[2] + 1
        assert not status()['opened'] and not status()['movingAddress']
        mark = marker(a)
        move(mark['x'] + 10, mark['y'] + 3); button(1, 273); move(850, 400); button(0, 273)
        assert not status()['movingAddress'] and not client(a)['floating'], 'Right drag was not removed'
        dispatch('hl.dsp.focus({window="address:' + b + '"})')
        pickup(a)
        old = client(a)['at']; move(800, 400)
        wait(lambda: client(a)['at'] != old, 'Window does not follow an unpressed cursor')
        time.sleep(.4)
        assert status()['movingAddress'] == a, 'Movement did not latch'
        drop()
        wait(lambda: not client(a)['floating'], 'Drop did not rejoin tiling')
        print('PASS: ordinary input, removed right drag, single-click tiled pickup, cursor follow and consumed left drop')

        if args.placement_only:
            # Reproduce force_split=2, then exercise both forced modes,
            # active-node selection and persistent preselection.
            for force, active, persistent, preserve in [(2, False, False, False), (2, False, False, True),
                                                        (1, True, True, True)]:
                lua('hl.config({dwindle={force_split=' + str(force)
                    + ',use_active_for_splits=' + str(active).lower()
                    + ',preserve_split=' + str(preserve).lower()
                    + ',permanent_direction_override=' + ('1' if persistent else '0') + '}})')
                points = ([(640, 80, 1, True), (640, 720, 1, False)] if preserve else [])
                points += [(100, 400, 0, True), (1180, 400, 0, False)]
                for x, y, axis, less in points:
                    pickup(a)
                    move(x, y); drop()
                    wait(lambda: not client(a)['floating'], 'Directional drop did not retile')
                    assert (client(a)['at'][axis] < client(b)['at'][axis]) == less, (
                        'Drop direction ignored', force, active, persistent, x, y, client(a), client(b))
            lua('hl.config({dwindle={force_split=2,use_active_for_splits=false,permanent_direction_override=0,preserve_split=false}})')
            print('PASS: left/right/top/bottom tiled placement with forced splits and persistent/active split modes')
            if args.multi_monitor:
                before = {m['name'] for m in json.loads(ctl('-j', 'monitors'))}
                ctl('output', 'create', 'headless')
                output = next(m['name'] for m in json.loads(ctl('-j', 'monitors')) if m['name'] not in before)
                lua('hl.monitor({output="' + output + '",mode="2560x1600@60",position="-1600x-200",scale=1.6})')
                destination = next(m['activeWorkspace']['id'] for m in json.loads(ctl('-j', 'monitors'))
                                   if m['name'] == output)
                act(b, 'move', f'workspace="{destination}",follow=false')
                time.sleep(.5)
                service.terminate(); service.wait(timeout=8)
                service = launch(work / 'shell.qml', work / 'placement-screens.log')
                wait(lambda: status().get('bindingsInstalled'), 'Directional-drop two-screen shell failed')
                for x, less in [(-1500, True), (-100, False)]:
                    pickup(a); move(x, 300)
                    wait(lambda: client(a)['workspace']['id'] == destination, 'Cross-monitor directional pickup failed')
                    drop()
                    wait(lambda: not client(a)['floating'], 'Cross-monitor directional drop did not retile')
                    assert (client(a)['at'][0] < client(b)['at'][0]) == less, 'Cross-monitor drop side ignored'
                print('PASS: cross-monitor left/right placement on a negative-origin fractional-scale destination')
            raise SystemExit(0)

        mark = marker(a); click(mark['x'] + 10, mark['y'] + 3)
        wait(lambda: status().get('opened'), 'Tiled menu did not open')
        subprocess.run(['wtype', '-k', 'Escape'], env=env, check=True, timeout=5)
        wait(lambda: not status().get('opened'), 'Idle Escape did not dismiss menu')
        check_extra_actions(a, False)
        mark = marker(a); click(mark['x'] + 10, mark['y'] + 3)
        menu_item(1)
        wait(lambda: status().get('movingAddress') == a, 'Menu Move failed')
        move(600, 400); drop()
        mark = marker(a); click(mark['x'] + 10, mark['y'] + 3)
        menu_item(2)
        wait(lambda: client(a)['floating'], 'Float action failed')
        act(a, 'resize', 'x=420,y=300'); act(a, 'move', 'x=350,y=250')
        time.sleep(.3)
        check_extra_actions(a, True)
        print('PASS: tiled/floating per-window opacity and silent workspace submenu')
        if args.multi_monitor:
            before_monitors = {m['name'] for m in json.loads(ctl('-j', 'monitors'))}
            original_monitor = next(iter(before_monitors))
            ctl('output', 'create', 'headless')
            output = next(m['name'] for m in json.loads(ctl('-j', 'monitors'))
                          if m['name'] not in before_monitors)
            lua('hl.monitor({output="' + output + '",mode="1280x800@60",position="1280x0",scale=1})')
            dispatch('hl.dsp.focus({monitor="' + output + '"})')
            dispatch('hl.dsp.focus({workspace="11"})')
            dispatch('hl.dsp.focus({monitor="' + original_monitor + '"})')
            time.sleep(.3)
            service.terminate(); service.wait(timeout=8)
            service = launch(work / 'shell.qml', work / 'workspace-screens.log')
            wait(lambda: status().get('bindingsInstalled'), 'Two-screen menu shell failed')
            w = client(a); click(w['at'][0]-3, w['at'][1]+100)
            menu_control('workspaces')
            choices = status()['workspaces']
            assert next(c for c in choices if c['id'] == 1)['label'] == '1'
            second = next(c for c in choices if c['id'] == 11)
            assert second['label'] == '1' and second['screen'] == output
            assert next(c for c in choices if c['id'] == 12)['label'] == '2'
            # Tab through the first screen's ten slots to the second screen's
            # second slot. This also exercises keyboard scrolling past headers.
            for _ in range(12):
                subprocess.run(['wtype', '-k', 'Tab'], env=env, check=True, timeout=5)
            wait(lambda: 'workspace12' in status()['menus'][0]['controls'], 'Keyboard did not scroll workspace list')
            menu_control('workspace12')
            wait(lambda: client(a)['workspace']['id'] == 12, 'Screen-local workspace 2 targeted wrong ID')
            assert client(a)['floating']
            assert next(m for m in json.loads(ctl('-j', 'monitors'))
                        if m['name'] == original_monitor)['activeWorkspace']['id'] == 1
            act(a, 'move', 'workspace="1",follow=false')
            ctl('output', 'remove', output)
            output = None
            time.sleep(.3)
            service.terminate(); service.wait(timeout=8)
            service = launch(work / 'shell.qml', work / 'after-workspace-screens.log')
            wait(lambda: status().get('bindingsInstalled'), 'Single-screen menu shell failed')
            print('PASS: screen-grouped local workspace numbers, keyboard scrolling and cross-screen target')
        before = counts()
        click(351, 400, 273); click(450, 400)
        after = counts()
        assert after[0] == before[0] + 1 and after[1] == before[1] + 1 and after[2] == before[2] + 1
        assert not status()['movingAddress'] and not status()['opened'], 'Floating content was treated as a border'
        assert lua('return tostring(hl.get_config("general.resize_on_border"))') == 'true'
        assert lua('return hl.get_config("general.extend_border_grab_area")') == '8'
        assert lua('return tostring(hl.get_config("general.hover_icon_on_border"))') == 'true'
        for side in range(4):
            w = client(a); x, y = w['at']; width, height = w['size']
            point = [(x-3, y+height/2), (x+width+3, y+height/2),
                     (x+width/2, y-3), (x+width/2, y+height+3)][side]
            click(*point)
            wait(lambda: status().get('opened'), 'Border midpoint did not open menu')
            click(100, 750)
            wait(lambda: not status().get('opened'), 'Outside click did not dismiss')
            click(*point, 273)
            wait(lambda: status().get('movingAddress') == a, 'Border right-click failed')
            move(point[0]+20, point[1]+15)
            drop()
            assert client(a)['floating'] and client(a)['size'] == w['size']
            act(a, 'move', 'x=350,y=250')
        print('PASS: vertical Close/Move/Float menu and all four floating border midpoints')

        old = client(a)['at']
        click(old[0]-3, old[1]+100, 273); move(600, 500); escape()
        wait(lambda: client(a)['at'] == old, 'Escape did not restore floating position')
        time.sleep(.3) # Let the client's resize/configure acknowledgments settle.
        w = client(a); x, y = w['at']; width, height = w['size']
        # Use a straight border: diagonal corner hit areas depend on the
        # desktop's rounding, which this plugin deliberately does not set.
        move(x+width+3, y+height/2); button(1); move(x+width+33, y+height/2); button(0)
        wait(lambda: client(a)['size'] != w['size'], 'Native left-border resize failed')
        assert not status()['opened'] and not status()['movingAddress']
        w = client(a); click(w['at'][0]-3, w['at'][1]+100)
        menu_item(1)
        wait(lambda: status().get('movingAddress') == a, 'Floating menu Move failed')
        move(600, 500); drop()
        act(a, 'resize', 'x=420,y=300'); act(a, 'move', 'x=860,y=500')
        time.sleep(.3)
        w = client(a); click(w['at'][0]-3, w['at'][1]+290)
        edge = wait(lambda: status().get('menus'), 'Edge menu failed')[0]
        assert edge['x'] >= 0 and edge['y'] >= 0 and edge['x'] + edge['width'] <= 1280 and edge['y'] + edge['height'] <= 800
        menu_item(2)
        wait(lambda: not client(a)['floating'], 'Tile action failed')
        print('PASS: floating Move/Tile, Escape restore and unchanged native left resizing')

        act(b, 'float', 'action="on"'); act(b, 'resize', 'x=220,y=160'); act(b, 'move', 'x=100,y=200')
        time.sleep(.35)
        mark = marker(a)
        act(b, 'move', f'x={mark["x"]-60},y={mark["y"]-10}')
        wait(lambda: all(m['address'] != a for m in status()['markers']), 'Covered triangle remained visible')
        click(mark['x']+10, mark['y']+3, 273)
        assert not status()['movingAddress'] and not client(a)['floating']
        act(b, 'float', 'action="off"')
        act(a, 'float', 'action="on"'); act(a, 'resize', 'x=420,y=300'); act(a, 'move', 'x=350,y=250')
        act(a, 'move', 'workspace="special:move-test",follow=true')
        time.sleep(.35)
        w = client(a)
        click(w['at'][0]-3, w['at'][1]+100, 273)
        assert not status()['movingAddress'] and not status()['opened'], 'Special workspace was not excluded'
        act(a, 'move', 'workspace="1",follow=true')
        if json.loads(ctl('-j', 'monitors'))[0]['specialWorkspace']['id']:
            dispatch('hl.dsp.workspace.toggle_special("move-test")')
        act(a, 'float', 'action="off"')
        print('PASS: floating occlusion and special-workspace exclusion')

        act(a, 'fullscreen', 'action="set"')
        wait(lambda: client(a)['fullscreen'] != 0, 'Fullscreen setup')
        click(1277, 3, 273)
        assert not status()['movingAddress']
        act(a, 'fullscreen', 'action="unset"')
        wait(lambda: client(a)['fullscreen'] == 0, 'Fullscreen cleanup')
        for cycle in range(6):
            pickup(a); move(800, 450)
            if cycle % 2:
                ipc(service, 'move-test', 'disable')
                wait(lambda: lua('return tostring(_G.__omarchy_window_corners_runtime.active)') == 'false', 'Disable failed')
                assert lua('return tostring(_G.__omarchy_window_corners_runtime.timer:is_enabled())') == 'false'
                ipc(service, 'move-test', 'enable')
                wait(lambda: status().get('bindingsInstalled'), 'Enable failed')
            else:
                escape()
            wait(lambda: not client(a)['floating'], 'Cancellation failed to retile')
        print('PASS: fullscreen, repeated pickup/cancel and timer-safe enable/disable')

        pickup(a); move(800, 450)
        dispatch('hl.dsp.focus({workspace="2"})')
        wait(lambda: status().get('movingAddress') == '', 'Workspace switch did not stop movement')
        assert not client(a)['floating'], 'Inactive target was not returned to tiling'
        dispatch('hl.dsp.focus({workspace="1"})')

        lua('hl.config({animations={enabled=true}})')
        pickup(a); move(800, 450)
        time.sleep(.5)
        drop()
        wait(lambda: not client(a)['floating'], 'Animated placement failed')
        time.sleep(.8)
        lua('hl.config({animations={enabled=false}})')

        pickup(a); move(800, 450)
        ctl('reload')
        wait(lambda: status().get('bindingsInstalled') and status().get('movingAddress') == '', 'Reload installation failed')
        wait(lambda: not client(a)['floating'], 'Reload recovery left target floating')
        pickup(a); move(800, 450)
        ctl('reload'); ctl('reload')
        wait(lambda: status().get('bindingsInstalled') and status().get('movingAddress') == '', 'Rapid reload installation failed')
        wait(lambda: not client(a)['floating'], 'Rapid reload lost the recovery record')
        pickup(a); move(700, 400)
        service.terminate(); service.wait(timeout=8)
        service = launch(work / 'shell.qml', work / 'restart.log')
        wait(lambda: status().get('bindingsInstalled'), 'Shell restart failed')
        wait(lambda: not client(a)['floating'], 'New owner did not cancel previous movement')
        print('PASS: compositor reload recovery and abrupt shell restart')

        if args.multi_monitor:
            before = {m['name'] for m in json.loads(ctl('-j', 'monitors'))}
            ctl('output', 'create', 'headless')
            output = next(m['name'] for m in json.loads(ctl('-j', 'monitors')) if m['name'] not in before)
            lua('hl.monitor({output="' + output + '",mode="2560x1600@60",position="-1600x-200",scale=1.6})')
            destination = next(m['activeWorkspace']['id'] for m in json.loads(ctl('-j', 'monitors')) if m['name'] == output)
            act(a, 'move', f'workspace="{destination}",follow=false')
            time.sleep(.5)
            # Runtime monitor rules do not broadcast a full monitor-geometry
            # snapshot. Start the shell after the disposable layout is settled.
            service.terminate(); service.wait(timeout=8)
            service = launch(work / 'shell.qml', work / 'multi-monitor.log')
            wait(lambda: status().get('bindingsInstalled'), 'Multi-monitor shell startup failed')
            pickup(a)
            move(600, 400)
            wait(lambda: client(a)['workspace']['id'] == 1, 'Monitor crossing failed')
            drop()
            wait(lambda: not client(a)['floating'], 'Cross-monitor drop failed')
            print('PASS: negative-origin fractional-scale triangle, monitor crossing and tiling drop')

        pickup(a)
        act(a, 'close')
        wait(lambda: client(a) is None, 'Target close failed')
        wait(lambda: status().get('movingAddress') == '', 'Closed target left movement active')
        assert lua('return tostring(_G.__omarchy_window_corners_runtime.timer:is_enabled())') == 'false'
        mark = marker(b); click(mark['x']+10, mark['y']+3); menu_item(0)
        wait(lambda: client(b) is None, 'Close menu failed')
        print('PASS: target closure cleanup and Close menu')
    except Exception:
        print('Failure state:', json.dumps({'service': status(), 'clients': clients(),
                                            'cursor': json.loads(ctl('-j', 'cursorpos')),
                                            'layers': json.loads(ctl('-j', 'layers'))}))
        for log in work.glob('*.log'):
            print(log.name + ':\n' + log.read_text()[-6000:])
        raise
    finally:
        if underlay_loaded:
            try:
                ctl('underlay', 'off')
                ctl('plugin', 'unload', str(args.underlay_plugin.resolve()))
            except (subprocess.SubprocessError, OSError):
                pass
        try:
            lua('local r=_G.__omarchy_window_corners_runtime; if r then r.deactivate() end')
        except (subprocess.SubprocessError, OSError):
            pass # Still stop test-owned children if the nested compositor died.
        if pointer and pointer.poll() is None:
            try:
                button(0); button(0, 273)
                pointer.stdin.close(); pointer.wait(timeout=5)
            except (BrokenPipeError, subprocess.TimeoutExpired, TimeoutError, AssertionError):
                pointer.terminate(); pointer.wait(timeout=5)
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait(timeout=5)
        if output:
            try:
                ctl('output', 'remove', output)
            except (subprocess.SubprocessError, OSError):
                pass
