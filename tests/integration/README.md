# Disposable compositor checks

Never point these runners at the live desktop. Both require an already-running
disposable nested Hyprland with a **separate, short, private runtime directory**.
They refuse the inherited live runtime directory. Do not change that refusal.
Use `HYPRLAND_NO_SD_VARS=1` and `HYPRLAND_NO_SD_NOTIFY=1` when starting a nested
compositor so it cannot replace desktop activation environment variables.
Keep Unix socket paths within the platform limit.

## Runtime lifecycle

```sh
python3 tests/integration/runtime_lifecycle.py \
  --runtime-dir "$TEST_RUNTIME" --signature "$TEST_SIGNATURE"
```

This exercises the real Quickshell bridge through 15 enable/disable cycles,
compositor reload and preservation of unrelated left/right bindings.

## Real pointer and UI

Requirements: Quickshell, Omarchy's packaged `Commons`/`Ui` modules, `hyprctl`,
Python, `wtype`, a C compiler, `libwayland-client`, `wayland-scanner`, and
`wlr-virtual-pointer-unstable-v1.xml` from
[wlr-protocols](https://gitlab.freedesktop.org/wlroots/wlr-protocols).
The test does not download dependencies or install anything.

Build the test-only virtual pointer in a disposable build directory. Set
`PROJECT` to the project root, `BUILD` to that directory, and `PROTOCOL_XML` to
the protocol XML's location:

```sh
wayland-scanner client-header "$PROTOCOL_XML" "$BUILD/pointer-client.h"
wayland-scanner private-code "$PROTOCOL_XML" "$BUILD/pointer-protocol.c"
cc "$PROJECT/tests/integration/virtual-pointer.c" "$BUILD/pointer-protocol.c" \
  -I "$BUILD" -lwayland-client -o "$BUILD/virtual-pointer"
python3 tests/integration/click_move.py \
  --runtime-dir "$TEST_RUNTIME" --signature "$TEST_SIGNATURE" \
  --pointer "$BUILD/virtual-pointer"
```

Use an empty nested compositor with one 1280×800, scale-1 output. The runner
refuses existing windows or a different monitor arrangement. It creates only
test-owned windows/processes, runs the actual service with read-only symlinks to
the packaged UI modules, and cleans up its temporary files and processes.
Use `--shell-source` if the packaged modules are in a different directory.

Border menus use native owner-scoped events, not a desktop-wide shell command.
The runner exercises actual pointer clicks and the actual popup/service.
Left/right content input, vertical menus and Close/Move/Float/Tile actions,
5%-step opacity submenu readback/adjustment and silent workspace submenu actions
(for both tiled and floating targets),
right-drag removal, unpressed cursor following, consumed placement clicks,
all floating border midpoints, native left resizing, fullscreen, repeated
enable/disable, Escape, reload recovery, shell restart and closure during
movement are checked. Add `--multi-monitor` to create a test-owned headless
output to check screen-grouped local workspace numbers and keyboard scrolling,
and a negative-origin fractional-scale output to exercise cross-monitor
placement, then remove only that output.

Run the pointer harness with `--placement-only` separately to exercise
cursor-directed Dwindle drops with forced splits and active/persistent split
modes. It changes only the disposable compositor's layout options and cleans
up its test windows/service before exiting. Add `--multi-monitor` to that mode
for cross-monitor left/right drops on a negative-origin fractional-scale screen.

Use `--occlusion-only` for Underlay-tag exclusions, overlapping floating borders,
both stacking orders, exposed lower borders, content pass-through and pinned
priority. Optionally add `--underlay-plugin /path/to/hypr-underlay.so` to exercise
an already-built, ABI-matching Underlay library too. It is loaded/unloaded only
inside the disposable compositor; no native Window Controls plugin is needed.

The plugin itself enables native resize settings in the disposable compositor;
the pointer runner verifies those settings rather than supplying them. Lifecycle
checks verify restoration and later external edits. Neither runner edits desktop
configuration or reloads the live session.
Also manually check animations/drag thresholds, multiple monitors/scales,
negative origins, monitor crossing, special/floating-layout workspaces, and
screen edges when changing input or surface lifetimes.
