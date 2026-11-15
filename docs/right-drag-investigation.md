# Right-button corner drag feasibility

> Historical investigation. Right-drag was superseded by trackpad-friendly
> click-to-move in version 1.2. See [click-to-move](click-to-move.md) for the
> current runtime and safety model; the experiments below are not current controls.

## Result

A disposable nested Hyprland v0.56.2 experiment demonstrated native window
movement from right-button presses at floating corners and tiled triangle
surfaces. The experiment was subsequently integrated as right-drag controls.
No desktop configuration edits are required. The observations below explain
the prototype and the safety differences in the integrated implementation.

The prototype used a conditional runtime `mouse:273` binding calling
`hl.dispatch(hl.dsp.window.drag())` inside the mouse callback. Starting this
action asynchronously through shell IPC is not equivalent: the native action
needs the current press/release context. No custom geometry polling or repeated
window-move subprocesses were needed.

## Checks performed

Using disposable terminal windows and a Wayland virtual pointer:

- Right-press a real triangle layer surface, then move: native tiled pickup.
- Release: window rejoins tiling, rather than remaining floating.
- Drag ordinary window content with the right button: no corner drag starts.
- Drag each of the four floating corners: position changes, size stays fixed,
  and the window stays floating.
- Move the pointer after release: the floating window no longer follows it.
- Successful prototype run: five starts and five matching stops.

The triangle component was copied into the disposable shell with a fixed test
color in place of the shell theme import. Its visibility was changed as
described below; the installed component was not edited.

## Important failure found

With the existing `visible: !!point` behavior, native pickup makes the window
floating, its marker becomes invalid, and its layer surface unmaps. In the
experiment, the release binding then failed to run and the window remained in
a stuck drag. Source inspection is consistent with layer refocusing clearing
held-button tracking; that exact internal path was not instrumented.

Keeping the small layer surface mapped allowed the same test to release and
retile correctly. The feasibility workaround kept test surfaces mapped even
when their marker was invalid; **do not ship that workaround as-is**. A proper
implementation must retain only the active drag's surface for the required
lifetime, without leaving stale markers or input regions over applications.

An initial prototype with separate press/release bindings also produced extra
start/stop calls. A single stateful callback, including native release handling,
passed the five-start/five-stop test. Conditional/no-hit releases, repeated
gestures and cancellation still need thorough regression coverage.

## Integration

The integrated runtime uses five reusable handles: two left-click observers,
one conditional right-press binding, and two non-consuming right-release
observers bracketing it. Native `window.drag()` sets `releasePending` on its
calling handle. A stateful toggle alone cannot distinguish a real press from
a release after cancellation; a release observer that calls the drag action
can itself become pending and run unexpectedly on the next press. Bracketing
the main callback avoids both problems without modifying native handles.

The shell retains only the active triangle's original small surface and screen,
with no visible shape or input region. A 150ms input-empty retirement grace
handles ordering across geometry replies and drag events. The original screen
is retained during cross-monitor movement to avoid remapping the surface.

Native disposable-session checks passed for both menus/actions, content input,
four floating corners, left-button border resizing, fullscreen, floating
occlusion, repeated drags, rapid disable/re-enable, keyboard cancellation,
compositor reload, shell restart and target closure. A separate two-monitor
check passed pickup on a negative-origin, scale-2 output, movement onto a scale-1
output, release and retiling. The lifecycle harness also passed 15 component
enable/disable cycles with unrelated left/right bindings preserved.

A fractional-scale edge regression additionally covers native float32 scale
precision: dividing by an exposed `1.6000000238…` must produce the same integer
logical bounds as the marker UI, not reject a flush-right triangle because the
calculated screen width is a few millionths of a pixel too small.

See [the integration harness](../tests/integration/README.md) for repeatable
pointer/UI tests. Multi-monitor geometry also has pure regression coverage.

## Continuing regression requirements

- Preserve tiled behavior: native pickup and retiling/reordering on drop, not
  permanently floating the window.
- Preserve selected-window validation, active-workspace and fullscreen guards,
  floating occlusion, screen bounds, and excluded workspace policy. The minimal
  prototype did not implement all production guards.
- Verify both left-click menus, ordinary application right-click delivery,
  left-button border resizing, non-focused targets, cross-monitor moves,
  animations, and compositor drag thresholds.
- Use conditional event consumption deliberately. The final prototype used
  `auto_consuming` and returned the native action result for a hit, or
  `{ pass_event = true }` for a miss; it is not a global consuming right binding.
- Extend owner-scoped binding reuse/cancellation and test disable, shell restart,
  reload, window closure and teardown during a drag in a disposable compositor.
  Do not remove native binding handles or experiment on the live desktop first.

Relevant native implementation:
[mouse drag dispatcher](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/config/lua/bindings/LuaBindingsDispatchers.cpp),
[drag controller](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/layout/supplementary/DragController.cpp),
[button tracking](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/managers/input/InputManager.cpp).
