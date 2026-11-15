# Trackpad-friendly click-to-move

The service is `WindowControls.qml`, triangle overlays are `TiledTriangles.qml`,
and the compositor runtime is `hypr/window-controls.lua`. Native resize option
ownership lives separately in `hypr/resize-settings.lua`.

Floating borders and tiled triangles have vertical Close / Move / Tile-or-Float
menus. Move or a right **click** picks up the selected window. Cursor motion
then moves it without any button held; a consumed left click places it, and
Escape cancels. A right drag does nothing. The floating input band is outside
the client rectangle (up to 10 logical pixels), not over application content.

## Why not latch native dragging?

On the supported Hyprland version, `hl.dsp.window.drag()` depends on the current
mouse press/release context and the compositor ends native dragging on later
input. It is not a sticky move API. The current implementation instead uses
native window move/float/workspace dispatches from a reusable **16ms native Lua
timer**, armed only during a picked-up move. Idle timers are disarmed. Ticks
perform no subprocesses, network calls or filesystem polling; saved workspace
policy is checked at pickup and when entering a different workspace.

Tiled pickup uses the native floating action and anchors the cursor relative to
the resulting floating size. Placement returns the selected window to tiling
at its destination workspace. Cancellation returns it to the original workspace
and, for originally floating windows, position. No default sizing, decoration
or application-launch settings are changed. This is not the former native
right-drag path: native drag thresholds and drag-specific snapping do not apply.

For Dwindle, placement chooses the nearest destination tile and its nearest
normalized edge (left/right/top/bottom). A synchronous native `preselect` applies
that drop direction even with `force_split`; it is cleared immediately afterward,
including with persistent direction overrides enabled. An explicit drop replaces
any existing Dwindle preselection. No global layout option is changed. Other
layouts and empty destinations retain native insertion behavior; cancellation
and reload recovery do not apply drop preselection.
Native orientation policy still applies: with `preserve_split`, `smart_split`
and `precise_mouse_move` all disabled, Dwindle recalculates split orientation
from the tile's aspect ratio. Enable the desired orientation policy in desktop
configuration if top/bottom splits on wide tiles should persist.

## Input and lifecycle safety

- Five owner-scoped handles are disabled/reused, never broadly unbound or removed.
- Ordinary content left/right clicks pass through; normal left border resizing
  stays native. A moved/resized press is not a menu click or right-click pickup.
- The drop press and its release must not reach the application beneath it.
- Escape only consumes input while moving. Border/triangle hits retain active-
  workspace, fullscreen, occlusion, special-workspace and logical-screen guards.
- Move requests validate selected addresses and current state, never titles or
  classes, and check the current owner. IPC event/recovery records are bounded
  and validated before constructing Lua code.
- Disable, closure, fullscreen changes, workspace switches and ownership transfer
  stop the timer. Compositor reload loses Lua state, so the shell carries a
  validated recovery record into the next installation to restore the target.
- No triangle retention or full-screen input layer is needed: pickup happens
  after right-button release (or the menu action). Hints are input-empty.

The disposable pointer/UI harness tests both menus, all border midpoints,
unpressed cursor following, consumed drop clicks, Escape, native resizing,
right-drag removal, reload recovery, restart, closure and cross-monitor movement
on a negative-origin fractional-scale output. See
[integration checks](../tests/integration/README.md).
