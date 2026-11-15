# Standalone activation and the v0.56.2 removal pitfall

The plugin activates its floating-border and tiled-triangle controls through
runtime Lua IPC. No user configuration include is needed. Observers are disabled
and reused, never removed via the native keybind removal method.

## Why not remove binding handles?

Native removal of shared-key mouse observers can invalidate handles and crash
affected compositor versions during teardown. Mocked unit tests alone cannot
establish native lifecycle safety.

Two relevant v0.56.2 behaviors are visible in
[`LuaKeybind.cpp`](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/config/lua/objects/LuaKeybind.cpp):

- `remove()` removes all bindings with the same modifiers/key, not only that
  handle. The press and release observers share a key, as can unrelated bindings.
- Expired-handle lookup wraps a possibly empty shared pointer in an engaged
  `std::optional`; several methods then dereference it. `tostring` explicitly
  checks the locked pointer and is safe to use for an expiry check.

The replacement uses `set_enabled(false/true)` on live handles, checks expiry
without dereferencing stale handles, and reuses its bindings across instances.
The current five handles are left press/release, right press/release, and Escape.
Only validated right-handle presses, placement clicks, and Escape during an
active move are consumed. A reusable native timer follows the cursor while
picked up, and is disabled while idle. This replaces the former right-drag
release-phase machinery; no native drag action or held button is used.
Cleanup is owner-scoped so a retiring instance cannot deactivate a newer one.
Retired-owner tombstones also prevent a delayed install from reviving a disabled
instance. A compositor reload discards the Lua state; the shell observes the
reload and reinstalls the set. A runtime-version/handle-count change disables
the obsolete set and installs a new one without unsafe removal.

## Regression coverage

No broad unbind/remove call is used by the plugin. The regression tests cover
activation/deactivation, reuse, cancellation and expired handles.
`tests/integration/runtime_lifecycle.py` additionally exercises repeated actual
Quickshell component destruction/recreation, preservation of unrelated mouse
bindings and automatic reinstallation after compositor reload in a separate
nested session/runtime.

Do not reintroduce the native removal approach in the user's live compositor.
Further runtime-binding changes need a disposable/nested Hyprland
session and explicit enable, disable, reload, restart and removal tests. Retain
native resize behavior, avoid config-file edits, and keep borders/shadows/window
policy outside the plugin.

Current source names are `hypr/window-controls.lua`, `WindowControls.qml`, and
`TiledTriangles.qml`; historical corner-prefixed protocol identifiers are kept
intentionally. See [compatibility](compatibility.md).
