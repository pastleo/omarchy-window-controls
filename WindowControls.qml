import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "WindowGeometry.js" as WindowGeometry
import "RuntimeCode.js" as RuntimeCode
import "MenuActions.js" as MenuActions

Item {
  id: root
  property var shell: null
  property var manifest: null
  property string address: ""
  property int globalX: 0
  property int globalY: 0
  property bool opened: false
  property bool floatingTarget: true
  property string submenu: ""
  readonly property bool workspaceMenu: submenu === "workspace"
  readonly property bool opacityMenu: submenu === "opacity"
  property var workspaceBlocks: ({})
  property int opacityPercent: -1
  property var workspaceChoices: []
  property int currentWorkspace: -1
  property string opacityAddress: ""

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
      + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.workspaceBlocks = MenuActions.readBlocks(text())
    onLoadFailed: root.workspaceBlocks = ({})
  }

  function readOpacity() {
    if (opacityReader.running || !root.opened) return
    root.opacityAddress = root.address
    opacityReader.command = ["hyprctl", "getprop", "address:" + root.address, "opacity"]
    opacityReader.running = true
  }

  function changeOpacity(delta) {
    if (!target() || opacityWriter.running || opacityReader.running || root.opacityPercent < 0) return
    var percent = Math.max(10, Math.min(100, root.opacityPercent + delta))
    if (percent === root.opacityPercent) return
    opacityWriter.command = ["hyprctl", "eval", MenuActions.opacityCode(root.address, percent)]
    opacityWriter.running = true
    dismissTimer.restart()
  }

  function showWorkspaces() {
    var window = target()
    if (!window || !window.lastIpcObject.workspace) return
    root.currentWorkspace = window.lastIpcObject.workspace.id
    root.workspaceChoices = MenuActions.workspaces(Hyprland.workspaces.values,
      root.currentWorkspace, Hyprland.monitors.values, root.workspaceBlocks)
    root.submenu = "workspace"
    dismissTimer.restart()
  }

  function moveToWorkspace(id) {
    var window = target()
    root.closeMenu()
    if (!window || id === window.lastIpcObject.workspace.id) return
    Quickshell.execDetached(["hyprctl", "eval", MenuActions.workspaceCode(root.address, id)])
  }

  Process {
    id: opacityReader
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.opened && root.address === root.opacityAddress)
          root.opacityPercent = MenuActions.opacityPercent(text)
      }
    }
    onExited: {
      if (root.opened && root.address !== root.opacityAddress) Qt.callLater(root.readOpacity)
    }
  }
  Process {
    id: opacityWriter
    stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Window opacity:", text.trim()) }
    onExited: Qt.callLater(root.readOpacity)
  }

  RuntimeBindings {
    id: runtimeBindings
    onMovingAddressChanged: if (movingAddress) root.closeMenu()
  }

  function target() {
    var windows = Hyprland.toplevels.values
    for (var i = 0; i < windows.length; i++) {
      var ipc = windows[i].lastIpcObject
      if (ipc && ipc.address === root.address && !ipc.fullscreen && !ipc.hidden
          && !WindowGeometry.isBackground(ipc))
        return windows[i]
    }
    return null
  }

  function closeMenu() { root.opened = false }

  function openMenu(address, x, y, floating) {
    if (!WindowGeometry.validAddress(address)) return
    root.address = address
    root.globalX = x
    root.globalY = y
    root.floatingTarget = floating
    root.submenu = ""
    root.opacityPercent = -1
    Hyprland.refreshToplevels()
    root.opened = true
    dismissTimer.restart()
    root.readOpacity()
  }

  function act(action) {
    var window = target()
    root.closeMenu()
    if (!window) return
    if (action === "close") {
      Quickshell.execDetached(["hyprctl", "dispatch",
        'hl.dsp.window.close({ window = "address:' + root.address + '" })'])
    }
    else if (action === "tile" && window.lastIpcObject.floating) {
      // A validated address, never a title or executable shell text. This is
      // unfloat, not fullscreen/maximize; it rejoins the workspace's tiling.
      Quickshell.execDetached(["hyprctl", "dispatch",
        'hl.dsp.window.float({ action = "off", window = "address:' + root.address + '" })'])
    }
    else if (action === "float" && !window.lastIpcObject.floating) {
      Quickshell.execDetached(["hyprctl", "dispatch",
        'hl.dsp.window.float({ action = "on", window = "address:' + root.address + '" })'])
    }
    else if (action === "move") runtimeBindings.startMove(root.address)
  }

  ShellIpc {
    target: "pastleo.window-controls"
    function show(address: string, x: int, y: int): void {
      // The compositor can report a new border click before Quickshell has
      // received that window's IPC snapshot. Refresh asynchronously; actions
      // still validate the live target before dispatching anything.
      root.openMenu(address, x, y, true)
    }
    function hide(): void { root.closeMenu() }
    function status(): string {
      return JSON.stringify({ opened: root.opened, address: root.address,
        bindingsInstalled: runtimeBindings.installed,
        movingAddress: runtimeBindings.movingAddress,
        workspaceMenu: root.workspaceMenu, opacityMenu: root.opacityMenu,
        workspaces: root.workspaceMenu ? root.workspaceChoices : [],
        opacityPercent: root.opacityPercent,
        mode: root.floatingTarget ? "floating" : "tiled", markers: tiledTriangles.status(),
        menus: menuPanels.instances.filter(function(panel) { return panel.visible }).map(function(panel) {
          return { x: panel.monitor.x + panel.menuRect.x, y: panel.monitor.y + panel.menuRect.y,
            width: panel.menuWidth, height: panel.menuHeight, screen: panel.screen.name,
            controls: panel.controlRects() }
        }) })
    }
  }

  // Never leave stale controls behind when their window closes, tiles, moves,
  // becomes fullscreen or switches workspace. No network access or polling.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom") {
        var request = RuntimeCode.parseMenuEvent(event.data, runtimeBindings.owner)
        if (request) root.openMenu(request.address, request.x, request.y, true)
      }
      if (!root.opened) return
      if (["closewindow", "changefloatingmode", "movewindow", "movewindowv2",
           "fullscreen", "workspace", "workspacev2", "focusedmon", "monitoradded",
           "monitoraddedv2", "monitorremoved", "monitorremovedv2"].indexOf(event.name) >= 0)
        root.closeMenu()
    }
  }
  Timer { id: dismissTimer; interval: 10000; onTriggered: root.closeMenu() }

  TiledTriangles {
    id: tiledTriangles
    onMenuRequested: function(address, x, y) { root.openMenu(address, x, y, false) }
  }

  Variants {
    id: menuPanels
    model: Quickshell.screens
    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      readonly property var monitor: Hyprland.monitorFor(screen)
      readonly property real menuWidth: card.width
      readonly property real menuHeight: card.height
      function backToMain() {
        var fromOpacity = root.opacityMenu
        root.submenu = ""
        dismissTimer.restart()
        if (fromOpacity) opacityButton.forceActiveFocus()
        else workspaceButton.forceActiveFocus()
      }
      function controlRects() {
        var result = {}
        var items = { close: closeButton, move: moveButton, state: stateButton,
          opacity: opacityButton, opacityDown: opacityDown, opacityUp: opacityUp,
          workspaces: workspaceButton, back: root.opacityMenu ? opacityBackButton : backButton }
        Object.keys(items).forEach(function(key) {
          var item = items[key]
          if (!item.visible) return
          var point = item.mapToItem(card, 0, 0)
          result[key] = { x: monitor.x + card.x + point.x, y: monitor.y + card.y + point.y,
            width: item.width, height: item.height }
        })
        if (root.workspaceMenu) {
          workspaceList.contentItem.children.forEach(function(item) {
            if (!item.modelData || item.y < workspaceList.contentY
                || item.y + item.height > workspaceList.contentY + workspaceList.height) return
            var point = item.mapToItem(card, 0, 0)
            result["workspace" + item.modelData.id] = {
              x: monitor.x + card.x + point.x, y: monitor.y + card.y + point.y,
              width: item.width, height: item.height }
          })
        }
        return result
      }
      readonly property var menuRect: WindowGeometry.menuPosition(
        root.globalX - (monitor ? monitor.x : 0), root.globalY - (monitor ? monitor.y : 0),
        card.width, card.height, panel.width, panel.height, !root.floatingTarget)
      readonly property bool ownsPoint: !!monitor && root.globalX >= monitor.x && root.globalY >= monitor.y
        && root.globalX < monitor.x + screen.width && root.globalY < monitor.y + screen.height
      visible: root.opened && ownsPoint
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
      WlrLayershell.namespace: "pastleo-floating-corners"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      mask: Region { item: card }

      HyprlandFocusGrab {
        active: panel.visible
        windows: [panel]
        onCleared: root.closeMenu()
      }
      onVisibleChanged: if (visible) card.forceActiveFocus()

      Rectangle {
        id: card
        width: buttons.width + 16
        height: (root.workspaceMenu ? workspacePage.height
          : root.opacityMenu ? opacityPage.height : buttons.implicitHeight) + 16
        x: panel.menuRect.x
        y: panel.menuRect.y
        radius: 5
        color: Commons.Color.background
        border.color: Commons.Color.accent
        border.width: 1
        focus: true
        Keys.onEscapePressed: {
          if (root.submenu) panel.backToMain()
          else root.closeMenu()
        }
        Column {
          id: buttons
          anchors.centerIn: parent
          spacing: 6
          visible: !root.submenu
          width: Math.max(160, closeButton.implicitWidth, moveButton.implicitWidth,
            stateButton.implicitWidth, workspaceButton.implicitWidth, opacityButton.implicitWidth)
          Ui.Button {
            id: closeButton
            width: buttons.width
            text: "Close"
            iconText: "×"
            leftAlign: true
            focusable: true
            onClicked: root.act("close")
          }
          Ui.Button {
            id: moveButton
            width: buttons.width
            text: "Move"
            iconText: "↔"
            leftAlign: true
            focusable: true
            enabled: runtimeBindings.installed
            onClicked: root.act("move")
          }
          Ui.Button {
            id: stateButton
            width: buttons.width
            text: root.floatingTarget ? "Tile" : "Float"
            iconText: "□"
            leftAlign: true
            focusable: true
            onClicked: root.act(root.floatingTarget ? "tile" : "float")
          }
          Ui.Button {
            id: opacityButton
            width: buttons.width
            text: "Opacity ›"
            iconText: "◐"
            leftAlign: true
            focusable: true
            onClicked: {
              root.submenu = "opacity"
              dismissTimer.restart()
              opacityBackButton.forceActiveFocus()
            }
          }
          Ui.Button {
            id: workspaceButton
            width: buttons.width
            text: "Workspace ›"
            iconText: "▦"
            leftAlign: true
            focusable: true
            onClicked: { root.showWorkspaces(); backButton.forceActiveFocus() }
          }
        }
        Column {
          id: opacityPage
          visible: root.opacityMenu
          anchors.centerIn: parent
          width: card.width - 16
          spacing: 6
          Ui.Button {
            id: opacityBackButton
            width: parent.width
            text: "‹ Opacity"
            focusable: true
            onClicked: panel.backToMain()
          }
          Row {
            width: opacityPage.width
            spacing: 6
            Ui.Button {
              id: opacityDown
              width: (parent.width - opacityLabel.width - 12) / 2
              text: "<"
              tooltipText: "Decrease window opacity"
              focusable: true
              // Keep keyboard focus while the asynchronous write/read runs.
              // changeOpacity rejects busy/unknown values and clamps bounds.
              opacity: root.opacityPercent > 10 ? 1 : 0.4
              onClicked: root.changeOpacity(-5)
            }
            Text {
              id: opacityLabel
              width: 64
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignHCenter
              text: root.opacityPercent < 0 ? "—" : root.opacityPercent + "%"
              textFormat: Text.PlainText
              color: Commons.Color.foreground
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.body
            }
            Ui.Button {
              id: opacityUp
              width: opacityDown.width
              text: ">"
              tooltipText: "Increase window opacity"
              focusable: true
              opacity: root.opacityPercent >= 0 && root.opacityPercent < 100 ? 1 : 0.4
              onClicked: root.changeOpacity(5)
            }
          }
        }
        Column {
          id: workspacePage
          visible: root.workspaceMenu
          anchors.centerIn: parent
          width: card.width - 16
          spacing: 6
          Ui.Button {
            id: backButton
            width: parent.width
            text: "‹ Workspace"
            focusable: true
            onClicked: panel.backToMain()
          }
          ListView {
            id: workspaceList
            width: parent.width
            height: Math.min(300, Math.max(40, panel.height - backButton.height - 32))
            model: root.workspaceChoices
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            section.property: "screen"
            section.delegate: Text {
              required property string section
              width: workspaceList.width
              height: implicitHeight + 8
              text: section
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Commons.Color.accent
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.body
            }
            delegate: Ui.Button {
              required property int index
              required property var modelData
              width: ListView.view.width
              text: modelData.label
              selected: modelData.id === root.currentWorkspace
              focusable: true
              onActiveFocusChanged: if (activeFocus) ListView.view.positionViewAtIndex(index, ListView.Contain)
              onClicked: root.moveToWorkspace(modelData.id)
            }
          }
        }
      }
    }
  }

  // Visible instructions without a keyboard grab or any input region.
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: !!runtimeBindings.movingAddress
      anchors { bottom: true }
      margins.bottom: 36
      implicitWidth: hint.width + 24
      implicitHeight: hint.height + 16
      color: Commons.Color.background
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
      mask: Region {}
      WlrLayershell.namespace: "pastleo-window-move-hint"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      Text {
        id: hint
        anchors.centerIn: parent
        text: "Moving · Left-click to place · Esc to cancel"
        textFormat: Text.PlainText
        color: Commons.Color.foreground
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
      }
    }
  }
}
