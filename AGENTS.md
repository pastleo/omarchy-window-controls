# Development guide

## Start here

- Read `README.md` for behavior, installation and test commands.
- Read `docs/standalone-investigation.md` before touching runtime bindings.
- If present, read the Git-ignored `AGENTS.local.md` for private development
  context. Never copy that context into public files, commits or issue reports.
- Inspect the working tree before editing. Preserve unrelated changes and do not
  commit, configure remotes, publish or submit to a marketplace unless requested.

## Product boundary

This is an Omarchy **shell service plugin** for window-action menus, not a window
manager, theme or application-launch policy:

- Floating border left click: vertical **Close / Move / Tile** menu. Interior
  content is not a border. Left border dragging remains native resizing.
- Tiled top-right triangle left click: **Close / Move / Float**.
- A right **click** on a floating border or tiled triangle picks up the window;
  it follows the unpressed cursor until a consumed left click places it. Escape
  cancels. There is no right-drag interaction and app context menus stay normal.
- Tile means unfloat into the workspace's tiling arrangement, not maximize or
  fullscreen. Actions target the selected window, not merely the focused one.
- Installation/enabling must not require editing user Hyprland configuration.
- Enable native border resizing with an 8px extended grab area and hover cursor.
  Snapshot these three general options on activation and conditionally restore
  them on disable; preserve later external edits and the baseline across owners.
- Explicit per-window opacity adjustments from the menu are supported; do not
  add global opacity or application opacity rules.
- Do not add application border, shadow, rounding, initial-size,
  default-application or default-layout settings. Popup styling is part of the UI;
  application-window decoration is outside the plugin's scope.

The manifest/IPC identifier is `pastleo.window-controls`, migrated from
`pastleo.floating-corners`. Treat it as a stable interface; future renaming
requires updating all references and planning migration.
Legacy event prefixes, registry keys and layer namespaces are also retained for
owner handover between old/new shell components. See `docs/compatibility.md`.

## Architecture

| File | Responsibility |
| --- | --- |
| `WindowControls.qml` | Service entry point, validated target selection, shared action popup and IPC |
| `TiledTriangles.qml` | Per-toplevel triangle surfaces, visibility/occlusion, native IPC geometry refresh |
| `WindowGeometry.js` | Pure identity, triangle geometry, anchor and popup-placement helpers |
| `MenuActions.js` | Validated per-window opacity and workspace commands and choices |
| `RuntimeBindings.qml` | Async runtime installation, limited retry, reload detection and teardown |
| `RuntimeCode.js` | Local helper URL resolution, Lua quoting, owner-scoped cancellation code |
| `hypr/window-controls.lua` | Border/triangle hit-tests, click detection, owner-scoped movement timer and runtime registry |
| `hypr/resize-settings.lua` | Three native resize options, original snapshot, conditional restoration |
| `tests/` | Lua/Node regression tests and disposable-session integration harness |

Omarchy supplies `qs.Commons`, `qs.Ui`, `ShellIpc`, theme colors and Quickshell's
Hyprland integration. Read packaged sources when needed, but never modify them
to make this plugin work. Match the surrounding two-space QML/JS/Lua style.

## Runtime-binding invariants

1. Never call `hl.unbind("mouse:272")`, `binding:remove()` or `binding:unbind()`.
   On affected Hyprland versions these can remove unrelated bindings sharing the
   key and expire both observer handles. Some expired-handle methods can crash
   the compositor.
2. Use `set_enabled(false/true)` only after the existing safe expiry check.
   Disabled observers remain inert and reusable until the next config reload;
   repeated activation must not accumulate pairs of bindings.
3. Normal left/right clicks must pass through. Only a validated right border/
   triangle click, a movement-placement click, or Escape during movement may be
   consumed. Reject drags/resizes/stale presses before opening menus or pickup.
   Do not use native `window.drag()` or synthetic held buttons for click-to-move.
4. Preserve owner tokens and cancellation tombstones. Old teardown must not
   disable a newer owner; delayed installation must not revive a retired owner.
5. Config reload clears the compositor's Lua state. The shell must reinstall
   automatically when `configreloaded` arrives.
6. Compositor callbacks must not block. No subprocess probes, sleeps, network
   access or long-running work inside mouse callbacks. Shell-side activation is
   asynchronous and invokes `hyprctl` with an argument array, not shell text.
7. The reusable 16ms movement timer must be disarmed while idle and on every
   finish, cancellation, teardown or failure. Only native APIs run per tick;
   no processes or filesystem polling. Restore original tiling on placement,
   and original workspace/position on cancellation. Carry validated recovery
   data across compositor reload; stale owners cannot start or stop a new move.

## UI and safety invariants

- Keep the rest of the screen click-through; do not place large invisible input
  surfaces over applications. Triangles use stable toplevel identities.
- Click-to-move must not require retained triangle surfaces or a full-screen
  input layer. Its instruction hint is input-empty and never grabs the keyboard.
- Preserve fullscreen, special-workspace, off-screen and floating-window
  occlusion checks. Geometry is in logical coordinates, including negative
  monitor origins and scaled screens.
- Keep triangle anchors inside exclusive screen bounds. Tiled popups open
  inward/below-left and remain clamped to their owning screen. Do not derive
  initial screen ownership from an unmapped panel's zero dimensions.
- Validate window addresses before constructing dispatch expressions and
  recheck target state before acting. Never interpolate window titles/classes
  or raw filesystem paths into executable Lua/shell code.
- Treat text from applications, IPC, configuration and files as untrusted. Use
  plain-text rendering for new text sinks; keep shared toolkit behavior in mind.
- Keep the current 4Hz triangle refresh and active-move-only 16ms timer disclosed.
  Use native IPC rather than spawning
  polling processes; do not introduce network access without explicit scope.

## Validation workflow

```sh
make test
make validate
```

`make test` needs Lua, Node.js and Lua available to the Node subprocess tests.
`make validate` needs `luac` and Omarchy's plugin validator; validate the real
project directory rather than an installation symlink.

For lifecycle changes, also run the real Quickshell integration harness against
a **disposable nested compositor with a separate runtime directory**:

```sh
python3 tests/integration/runtime_lifecycle.py --runtime-dir /path/to/private-runtime --signature INSTANCE
```

It tests enable/disable, reload reinstallation and unrelated-binding preservation.
Do not weaken its live-runtime refusal. Mocked tests cannot establish native
handle safety. Exercise rapid activation/teardown, shell restart, expired handles
and compositor reload when changing this lifecycle.

For UI changes, test disposable windows: both action menus, outside-click/Escape,
normal content clicks, border resizing, right/bottom screen edges, multiple
monitors and fullscreen/occlusion. Allow opening animations to settle; a native
resize drag begins outside the application content/border, not inside it.

Do not experiment with known-crashing native teardown on a live desktop. Obtain
approval before disruptive live-session testing; preserve other applications and
clean up only test-owned windows/processes. Refresh session identifiers after a
compositor restart rather than trusting stale inherited environment variables.

## Public/private documentation

Keep paths, hostnames, monitor/application configuration, local symlink state,
session identifiers, PIDs, crash timestamps, logs and recovery details out of
public documentation. Use generic examples and `$HOME`/XDG variables. The
published manifest's author and plugin identifier are intentional project
metadata, not local setup instructions.
