import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "RuntimeCode.js" as RuntimeCode

Item {
  id: root
  readonly property string owner: "controls-" + Quickshell.processId + "-" + Date.now()
    + "-" + Math.floor(Math.random() * 0x100000000).toString(16)
  readonly property string helperPath: RuntimeCode.localPath(Qt.resolvedUrl("hypr/window-controls.lua"))
  property bool installed: false
  property bool pending: false
  property int attempts: 0
  property var moveState: null
  property var recovery: null
  readonly property string movingAddress: moveState ? moveState.address : ""

  function startMove(address) {
    if (!root.installed) return
    Quickshell.execDetached(["hyprctl", "eval", RuntimeCode.startMoveCode(root.owner, address)])
  }

  function install() {
    root.installed = false
    if (installer.running) { root.pending = true; return }
    root.attempts++
    installer.running = true
  }
  Process {
    id: installer
    command: ["hyprctl", "eval", RuntimeCode.installCode(root.helperPath, root.owner, root.recovery)]
    stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Window control bindings:", text.trim()) }
    onExited: function(code, status) {
      root.installed = code === 0 && !root.pending
      if (root.installed) root.recovery = null
      if (root.pending) {
        root.pending = false
        Qt.callLater(root.install)
      } else if (code !== 0 && root.attempts < 3) {
        retry.restart()
      } else if (code !== 0) {
        console.warn("Window control bindings could not be installed; tiled triangles remain available")
      }
    }
  }
  Timer { id: retry; interval: 500; onTriggered: root.install() }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom") {
        var state = RuntimeCode.parseMoveEvent(event.data, root.owner)
        if (state !== undefined) root.moveState = state
      }
      if (event.name !== "configreloaded") return
      root.recovery = root.moveState || root.recovery
      root.moveState = null
      root.attempts = 0
      root.install()
    }
  }
  Component.onCompleted: root.install()
  Component.onDestruction: Quickshell.execDetached(["hyprctl", "eval", RuntimeCode.deactivateCode(root.owner)])
}
