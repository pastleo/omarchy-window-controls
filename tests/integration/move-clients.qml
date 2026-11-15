import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  property int leftPresses: 0
  property int rightPresses: 0
  property int rightReleases: 0
  Variants {
    model: ["A", "B"]
    FloatingWindow {
      required property string modelData
      title: "window-control-test-" + modelData
      color: "#202830"
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: event => {
          if (event.button === Qt.LeftButton) root.leftPresses++
          if (event.button === Qt.RightButton) root.rightPresses++
        }
        onReleased: event => { if (event.button === Qt.RightButton) root.rightReleases++ }
      }
    }
  }
  IpcHandler {
    target: "client-test"
    function counts(): string { return JSON.stringify([root.leftPresses, root.rightPresses, root.rightReleases]) }
  }
}
