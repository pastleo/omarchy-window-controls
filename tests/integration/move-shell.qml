import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  Loader { id: service; source: Quickshell.env("WINDOW_CONTROLS_SOURCE") }
  IpcHandler {
    target: "move-test"
    function enable(): void { service.active = true }
    function disable(): void { service.active = false }
  }
}
