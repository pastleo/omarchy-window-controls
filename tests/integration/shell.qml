import QtQuick
import Quickshell
import Quickshell.Io

// Minimal shell: exercises the actual runtime bridge without starting Omarchy's
// notification, lock, audio or other session-wide services in the test session.
ShellRoot {
  Loader { id: bridge; source: Quickshell.env("WINDOW_CONTROLS_RUNTIME_SOURCE"); active: true }
  Connections {
    target: bridge.item
    function onInstalledChanged() { if (bridge.item.installed) console.log("WINDOW_CONTROLS_READY") }
  }
  IpcHandler {
    target: "lifecycle"
    function enable(): void { bridge.active = true }
    function disable(): void { bridge.active = false }
  }
}
