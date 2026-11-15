# Stacking-aware controls without native code

On Hyprland v0.56.2, Lua's `hl.get_windows()` iterates
`Desktop::windowState()->windows()` in order. That vector is bottom-to-top:
`raise()` moves a window to its end, and native hit-testing walks it in reverse.
Pinned floating windows are tested/rendered in a separate pass above ordinary
floating windows. Focus-history IDs are not used to infer stacking.

Relevant sources at the supported build:

- [Lua window queries](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/config/lua/bindings/LuaBindingsQuery.cpp)
- [Window stacking](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/desktop/state/WindowState.cpp)
- [Native hit-testing](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/desktop/state/ViewHitTester.cpp)

Floating controls now reject a candidate only when a higher floating window
covers the pointer, including its border grab band. Lower application content
does not block a higher window's border; higher application content still blocks
a lower border. Existing fullscreen, workspace, screen-bound and click-vs-drag
checks remain in place.

## Underlay integration

Hypr Underlay keeps its selected window logically floating but renders it behind
ordinary windows. Standard floating-vs-tiled ordering therefore cannot describe
it. Its controller already applies the `hypr-underlay` tag; Window Controls
recognizes that exact tag (including Hyprland's dynamic-tag `*` spelling).

Tagged windows do not hide tiled triangles or block floating border actions.
They are also excluded as control targets, so controls cannot accidentally
reposition, tile or close the background. Restore a background through Underlay
before controlling it normally. No title/class matching, controller subprocess,
extra polling, or new native plugin is required.

This is an explicit integration contract, not detection of arbitrary renderer
hooks. Other plugins that change render order need their own supported metadata.
Lua geometry hit-tests and layer-shell triangles are still not genuine native
decorations: this does not claim native popup-surface or animated-shape
hit-testing parity. Recheck the ordering contract when supporting new Hyprland
versions.
