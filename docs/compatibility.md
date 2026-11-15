# Naming and compatibility

The current product is **Omarchy Window Controls**: floating-border menus,
tiled-triangle menus, click-to-move, and native border resizing. Source names
describe those responsibilities rather than the original corner-only prototype.

| Previous source | Current source |
| --- | --- |
| `CornerMenu.qml` | `WindowControls.qml` |
| `TiledCorners.qml` | `TiledTriangles.qml` |
| `CornerModel.js` | `WindowGeometry.js` |
| `hypr/corner-menu.lua` | `hypr/window-controls.lua` |
| Inline resize ownership | `hypr/resize-settings.lua` |
| `tests/floating-corners.lua` | `tests/runtime.lua` |
| `tests/tiled-corners.cjs` | `tests/window-geometry.cjs` |

## Plugin ID migration

The public plugin/IPC ID is now **`pastleo.window-controls`**, replacing
`pastleo.floating-corners`. The manifest, installation directory, shell plugin
registration and IPC target must agree. The old IPC endpoint is retired; for
example, use `omarchy shell pastleo.window-controls status`.

For an existing installation, before updating the source:

1. Disable `pastleo.floating-corners` with `omarchy plugin disable`.
2. Update the checkout, then rename its installation directory or symlink from
   `pastleo.floating-corners` to `pastleo.window-controls`. Stop if the new path
   already exists; do not overwrite a separate installation or leave two links
   pointing at the same manifest.
3. Run `omarchy shell shell rescanPlugins`, then
   `omarchy plugin enable pastleo.window-controls`.
4. Check `omarchy shell pastleo.window-controls status`. If Omarchy retained an
   old component, `omarchy restart shell` loads the new endpoint without
   restarting Hyprland. Update any external scripts that call the old IPC ID.

Keep unrelated shell settings and any plugin options when replacing a shell
registration directly. Existing runtime handles and resize baseline can hand
over to the new owner through the shared internal keys below; explicit disable/
enable instead restores and reapplies resize settings normally.

### Moving a symlinked checkout later

Renaming the workspace folder does not retarget an absolute installation
symlink. After moving the checkout, update **only its installation symlink**:

```sh
ln -sfn "$NEW_CHECKOUT" "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/pastleo.window-controls"
omarchy shell shell rescanPlugins
```

Set `NEW_CHECKOUT` to the new absolute checkout directory first, and verify the
installation path is a symlink, not a real plugin directory. Restart the shell
if it retains components or runtime helper paths from the old checkout location.

## Internal handover compatibility

These internal identifiers are **intentionally unchanged**:

- Lua registry and cancellation keys: `__omarchy_window_corners_runtime` and
  `__omarchy_window_corners_cancelled`.
- Events: `window-corners-menu:` and `window-corners-move:`.
- Popup/triangle layer namespaces: `pastleo-floating-corners` and
  `pastleo-tiled-corner`.
- IPC methods and the `status()` result shape, including `markers`.

Keeping these wire names avoids two independent runtime owners during the
public-ID migration and preserves existing layer rules. The naming migration
retained runtime generation 6. Cursor-directed Dwindle placement uses generation
7; stacking-aware hit-testing and Underlay exclusions use generation 8 so old
callbacks cannot survive an upgrade. Generation changes safely disable
the old handles and restore owned resize options before installing the new
runtime; differing external edits are preserved. Same-generation owner handover
reuses live handles, the timer and the resize baseline. Compositor reload
installs a fresh runtime normally.

The manifest names the renamed service entry point; external developer
harnesses that loaded `CornerMenu.qml`
directly should use `WindowControls.qml` instead. Historical investigation notes
retain the old terminology where they describe the original experiments.
