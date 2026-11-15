import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons as Commons
import "WindowGeometry.js" as WindowGeometry

Item {
  id: root
  signal menuRequested(string address, int x, int y)
  readonly property int triangleSize: 14
  readonly property var snapshots: Hyprland.toplevels.values.map(function(window) { return window.lastIpcObject })
  readonly property bool needsRefresh: snapshots.some(function(window) {
    return window && window.mapped && !window.hidden && !window.floating && !window.fullscreen
  })

  // Hyprland's socket doesn't publish window geometry on each resize/swap.
  // Refresh through Quickshell's native IPC (no processes) at 4Hz while there
  // are tiled windows, plus immediately on window/workspace changes.
  Timer {
    interval: 250
    repeat: true
    running: root.needsRefresh
    onTriggered: Hyprland.refreshToplevels()
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (["openwindow", "closewindow", "activewindowv2", "movewindowv2", "changefloatingmode",
           "workspacev2", "fullscreen", "monitoradded", "monitorremoved", "configreloaded"].indexOf(event.name) >= 0)
        Hyprland.refreshToplevels()
    }
  }
  Component.onCompleted: Hyprland.refreshToplevels()

  function status() {
    return triangles.instances.filter(function(triangle) { return triangle.visible && triangle.point }).map(function(triangle) {
      return { address: triangle.ipc.address, x: triangle.point.x, y: triangle.point.y, size: root.triangleSize }
    })
  }

  // Stable toplevel QObject identities keep the layer surfaces in place across
  // refreshes. Each surface is only 14x14: everything else stays click-through.
  Variants {
    id: triangles
    model: Hyprland.toplevels.values
    PanelWindow {
      id: triangle
      required property var modelData
      readonly property var ipc: modelData.lastIpcObject
      readonly property var monitor: modelData.monitor
      readonly property var targetScreen: {
        if (!monitor) return null
        return Quickshell.screens.find(function(screen) { return screen.name === triangle.monitor.name }) || null
      }
      screen: targetScreen
      readonly property var point: {
        if (!targetScreen || !monitor || !monitor.activeWorkspace) return null
        return WindowGeometry.triangleMarker(ipc, { id: monitor.id, x: monitor.x, y: monitor.y,
          width: targetScreen.width, height: targetScreen.height, workspace: monitor.activeWorkspace.id,
          special: !!(monitor.lastIpcObject.specialWorkspace && monitor.lastIpcObject.specialWorkspace.id) },
          root.snapshots, root.triangleSize)
      }
      visible: !!point
      color: "transparent"
      anchors { top: true; left: true }
      margins.left: point ? Math.round(point.x - monitor.x) : 0
      margins.top: point ? Math.round(point.y - monitor.y) : 0
      implicitWidth: root.triangleSize
      implicitHeight: root.triangleSize
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
      WlrLayershell.namespace: "pastleo-tiled-corner"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Shape {
        anchors.fill: parent
        opacity: mouse.containsMouse ? 1 : 0.7
        ShapePath {
          strokeWidth: 0
          fillColor: Commons.Color.accent
          startX: 0; startY: 0
          PathLine { x: root.triangleSize; y: 0 }
          PathLine { x: root.triangleSize; y: root.triangleSize }
          PathLine { x: 0; y: 0 }
        }
      }
      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: {
          if (!triangle.point || !WindowGeometry.validAddress(triangle.ipc.address)) return
          var anchor = WindowGeometry.menuAnchor(triangle.point)
          root.menuRequested(triangle.ipc.address, anchor.x, anchor.y)
        }
      }
    }
  }
}
