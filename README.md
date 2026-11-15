# Omarchy Window Controls

Small, themed window-action menus for Omarchy:

- **Floating window:** left-click any border for **Close / Move / Tile**.
- **Tiled window:** left-click the 14px top-right triangle for **Close / Move / Float**.
- Menus are vertical. Choose **Move**, or single right-click a floating border
  or tiled triangle, to pick up that window. It follows the cursor **without
  holding a button**. Single left-click to place; Escape cancels.
- Floating windows stay floating; tiled windows rejoin tiling when placed.
- Application right-clicks inside floating windows remain normal. Only the
  outside border band is a pickup/menu target, not application content.
- Right-drag pickup has been removed. Left-button border dragging remains native resizing.
- Tiled menus open below-and-left of their triangle, clamped inside the screen.
- Click outside, press Escape, or wait 10 seconds to dismiss a menu.
- Tab / Shift+Tab and Enter also operate the buttons.
- Both menus include an **Opacity ›** submenu (`< 100% >`), adjusting the selected
  window in 5 percentage-point steps, from 10–100%. Changes apply equally when
  focused/unfocused, overriding compositor opacity for that window only. They
  are runtime-only, not saved as configuration; application-rendered transparency
  is unchanged.
- **Workspace ›** opens a scrollable submenu grouped by screen, with local
  numbers 1–10 matching Omarchy's bar (including empty slots). Existing workspaces
  outside connected screens' blocks appear under **Other workspaces** with their
  actual IDs. Moving does not follow the
  window or change its floating/tiled state. Escape returns to the main menu.

**Window controls only.** This project does not set window borders, rounding,
shadows, initial window sizes, default applications,
or which applications open floating. Those preferences belong to your desktop
configuration, independently of this plugin.

Plugin ID: `pastleo.window-controls`. Plugin kind: Omarchy shell service.
Existing `pastleo.floating-corners` installations need the
[ID migration](docs/compatibility.md#plugin-id-migration) once; IPC callers should
use the new ID as well.

## Requirements

- Omarchy's Quickshell shell and Hyprland **Lua** configuration/API.
- `omarchy` and `hyprctl` on the session's PATH.
- Hyprland's runtime Lua binding and timer APIs (`hl.bind`, `hl.timer`, `set_enabled`).

## Local development installation

From this project directory, for a fresh installation:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
ln -s "$PWD" "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/pastleo.window-controls"
omarchy shell shell rescanPlugins
omarchy plugin enable pastleo.window-controls
```

Do not overwrite an existing plugin directory or unrelated symlink.

**No Hyprland configuration edits are required.** Enabling the shell service
loads the bundled click detector through runtime IPC. It reinstalls itself after
Hyprland reloads and deactivates its five runtime bindings when disabled.
It does not replace existing keybindings or consume ordinary application input.
Only right-clicks on validated handles,
the placement click, and Escape during movement are consumed. Ordinary content
clicks pass through. Dragging does not open a menu or pick up a window.

The plugin enables Hyprland's native border resizing (`resize_on_border = true`),
an 8px extended grab area (`extend_border_grab_area = 8`), and the resize hover
cursor (`hover_icon_on_border = true`). These are compositor-wide options, not
window decoration rules. Activation snapshots their previous values; disable
restores each option only if it still equals the plugin's value, preserving
later external edits. Owner replacement retains the snapshot; compositor reload
captures the freshly loaded desktop configuration before reapplying the options.

If upgrading from the earlier manual version, remove its optional
`hypr/corner-menu.lua` include from your config and run `hyprctl reload` once.

## Scope and behavior

- Floating-border clicks apply to normal **tiled-layout workspaces**. Omarchy's
  saved floating-layout workspaces and special workspaces are excluded.
- Tiled triangles hide for fullscreen/special workspaces, off-screen scrolling
  tiles, and triangles covered by floating windows. Only each triangle's small
  square intercepts input; the rest of the screen stays click-through.
- Close sends a graceful close request. Float and Tile change only the selected
  window's floating state; neither is a fullscreen/maximize command.
- Actions validate the selected window's address and current state rather than
  acting on whichever window has focus. Window titles are not used as commands.
- Movement uses native window dispatches from a compositor-side **16ms timer
  only while a window is picked up** (about 60Hz). The timer is disarmed while
  idle; there are no per-frame processes, synthetic held buttons, or full-screen
  input surfaces. An input-empty hint explains how to place/cancel.
- Fullscreen and excluded workspaces are ignored. Ambiguous overlapping floating
  borders are conservatively left alone. Cross-monitor placement uses the normal
  workspace under the cursor; monitor gaps keep the last position.
- Escape and disable restore the original workspace/position and tiling state.
  Workspace changes and window closure stop movement. Compositor reload recovers
  the original state; shell restart cancels on replacement-owner activation.
- The floating helper reads Omarchy's saved layout files as data, never as code.
- Triangle geometry refreshes through Quickshell's native Hyprland IPC at 4Hz
  while tiled windows exist, plus window/workspace events. No external polling
  processes or network access are used.

## Uninstall

Disable the service:

```sh
omarchy plugin disable pastleo.window-controls
```

You can then remove the installation symlink. This leaves your personal borders,
shadows, application defaults and window-opening rules alone. Native resize
options are restored as described above.
On Hyprland v0.56.2, the bindings are disabled and reused rather than removed
through the unsafe keybind removal API. They do no work while disabled and are
cleared completely at the next Hyprland reload. Repeated enable/disable cycles
do not accumulate bindings. Upgrading from an older runtime version leaves its
obsolete bindings disabled until the next compositor reload.

## Project structure

```text
manifest.json             Omarchy service manifest
WindowControls.qml        Service, action menus and movement hint
TiledTriangles.qml        Tiled-window triangle overlays
WindowGeometry.js         Geometry, identity and popup-placement helpers
RuntimeBindings.qml       Automatic runtime activation, reload and deactivation
RuntimeCode.js            Safe Lua command/path encoding and owner-scoped cleanup
MenuActions.js            Validated per-window opacity/workspace commands
hypr/window-controls.lua  Border/triangle clicks and cursor-following move timer
hypr/resize-settings.lua  Native resize settings snapshot/restore ownership
tests/                    Menu/runtime regression tests; no decoration setup
```

## Checks

```sh
make test       # Lua and Node.js regression tests
make validate   # Lua syntax and Omarchy manifest validation
```

The Lua tests allow only the three native resize options and reject decoration
configuration and window-rule calls to keep appearance and layout policy separate.

For real lifecycle tests, start a **disposable nested compositor with its own
runtime directory**, then run:

```sh
python3 tests/integration/runtime_lifecycle.py --runtime-dir /path/to/private-runtime --signature INSTANCE
```

The runner refuses the live runtime directory. It exercises real Quickshell
component destruction/recreation, native binding state, unrelated mouse bindings
and compositor reloads. See [the investigation notes](docs/standalone-investigation.md)
for the v0.56.2 keybind-removal pitfall this avoids.

The pointer/UI harness also checks both menus, application input, native resizing,
click-to-move placement and cancellation. Setup and commands are in
[tests/integration/README.md](tests/integration/README.md).

## Contributing

See [AGENTS.md](AGENTS.md) for architecture, runtime-binding invariants, safety
requirements and the validation workflow. Keep machine-specific development
notes in a Git-ignored `AGENTS.local.md`, not in public documentation.
