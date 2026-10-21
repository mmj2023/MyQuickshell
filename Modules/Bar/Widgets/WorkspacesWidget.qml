import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Workspace switcher. Renders a numbered circle per known workspace; the
// active one is filled with primary, occupied ones get a stronger tone, and
// empty ones are dimmed. Reads state through the compositor-agnostic
// WorkspacesService.
BasePill {
  id: root

  property var barWindow: null
  property QtObject parentScreen: null

  readonly property string monitorName: parentScreen ? parentScreen.name : ""
  readonly property int activeId: WorkspacesService.activeWorkspaceId(monitorName)
  property var specialWorkspaces: []
  property int specialPopupX: 0
  property int specialPopupY: 0
  property bool specialPopupOpen: false
  property int previewWorkspaceId: 0
  property int previewX: 0
  property int previewY: 0
  property bool previewOpen: false
  property var previewWindows: []

  function collectSpecialWorkspaces() {
    const windows = Array.from(Hyprland.toplevels ? Hyprland.toplevels.values : [])
    const groups = {}

    for (let i = 0; i < windows.length; i++) {
      const window = windows[i]
      if (!window.workspace || Number(window.workspace.id) >= 0)
        continue

      let name = window.workspace.name
      if (name && typeof name === "object")
        name = name.name
      name = String(name || "").replace(/^special:/, "") || "special"

      if (!groups[name])
        groups[name] = []

      const waylandWindow = window.wayland
      groups[name].push({
        "title": String(waylandWindow && waylandWindow.title
          ? waylandWindow.title
          : (waylandWindow && waylandWindow.appId ? waylandWindow.appId : "Application"))
      })
    }

    return Object.keys(groups).sort().map(function(name) {
      return {
        "name": name,
        "windows": groups[name]
      }
    })
  }

  function refreshSpecialWorkspaces() {
    Hyprland.refreshToplevels()
    specialWorkspaces = root.collectSpecialWorkspaces()
  }

  function toggleSpecialPopup(rootX, rootY) {
    if (!root.barWindow)
      return

    if (specialPopupOpen) {
      specialPopupOpen = false
      return
    }

    root.refreshSpecialWorkspaces()
    const position = root.mapToItem(root.barWindow.contentItem, rootX, rootY)
    specialPopupX = Math.max(8, Math.min(
      root.barWindow.width - specialWorkspacePopup.implicitWidth - 8,
      position.x - specialWorkspacePopup.implicitWidth / 2
    ))
    specialPopupY = position.y + Theme.spaceXS
    specialPopupOpen = true
  }

  onRightClicked: function(rootX, rootY) {
    root.toggleSpecialPopup(rootX, rootY)
  }

  PopupWindow {
    id: specialWorkspacePopup

    anchor.window: root.barWindow
    anchor.rect.x: root.specialPopupX
    anchor.rect.y: root.specialPopupY
    visible: root.specialPopupOpen
    grabFocus: true
    color: "transparent"
    surfaceFormat.opaque: false
    implicitWidth: 300
    implicitHeight: Math.min(460, Math.max(100, specialContent.implicitHeight + 28))

    onVisibleChanged: {
      if (!visible)
        root.specialPopupOpen = false
    }

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.withAlpha(Theme.widgetBaseBackgroundColor, typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.6)
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.35)

      Flickable {
        anchors.fill: parent
        anchors.margins: 14
        contentHeight: specialContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: specialContent

          width: parent.width
          spacing: 12

          Text {
            width: parent.width
            text: qsTr("Special workspaces")
            color: Theme.widgetTextColor
            font.pixelSize: 15
            font.weight: Font.DemiBold
          }

          Repeater {
            model: root.specialWorkspaces

            delegate: Column {
              required property var modelData

              width: specialContent.width
              spacing: 6

              Text {
                  id: specialWorkspaceName
                  width: parent.width
                  text: modelData.name
                  color: specialWorkspaceMouse.containsMouse ? Theme.widgetTextColor : Theme.primary
                  font.pixelSize: 13
                  font.weight: Font.Medium

                  MouseArea {
                    id: specialWorkspaceMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      const workspaceName = String(modelData.name)
                        .replace(/\\/g, "\\\\")
                        .replace(/'/g, "\\'")
                      toggleSpecialWorkspaceProcess.command = [
                        "hyprctl", "dispatch",
                        "hl.dsp.workspace.toggle_special('" + workspaceName + "')"
                      ]
                      toggleSpecialWorkspaceProcess.running = false
                      toggleSpecialWorkspaceProcess.running = true
                    }
                  }
              }

              Process {
                id: toggleSpecialWorkspaceProcess
                onExited: function(exitCode, exitStatus) {
                  if (exitCode !== 0)
                    console.warn("Failed to toggle special workspace", modelData.name,
                      "exit code", exitCode, "status", exitStatus)
                }
              }

              Repeater {
                model: modelData.windows

                delegate: Row {
                  required property var modelData

                  width: parent.width
                  height: 28
                  spacing: 8

                  DmsIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "apps"
                    size: 17
                    color: Theme.widgetInactiveIconColor
                  }

                  Text {
                    width: parent.width - 28
                    height: parent.height
                    text: modelData.title
                    color: Theme.widgetTextColor
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.specialWorkspaces.length === 0
            text: qsTr("No special workspaces with open applications")
            color: Theme.widgetInactiveIconColor
            font.pixelSize: 12
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  Timer {
    interval: 500
    repeat: true
    running: root.specialPopupOpen
    onTriggered: root.refreshSpecialWorkspaces()
  }

  function collectWorkspaceWindows(workspaceId) {
    const windows = Array.from(Hyprland.toplevels ? Hyprland.toplevels.values : [])
    return windows.filter(function(window) {
      if (!window.workspace || Number(window.workspace.id) !== Number(workspaceId) || !window.wayland)
        return false

      return !root.monitorName || !window.monitor || window.monitor.name === root.monitorName
    })
  }

  function refreshPreviewWindows() {
    Hyprland.refreshToplevels()
    previewWindows = root.collectWorkspaceWindows(previewWorkspaceId)
  }

  function togglePreview(workspaceId, button) {
    const id = Number(workspaceId)
    if (previewOpen && previewWorkspaceId === id) {
      previewOpen = false
      return
    }

    if (!root.barWindow)
      return

    previewWorkspaceId = id
    const position = button.mapToItem(root.barWindow.contentItem, button.width / 2, button.height)
    previewX = Math.max(8, Math.min(root.barWindow.width - workspacePreviewPopup.implicitWidth - 8, position.x - workspacePreviewPopup.implicitWidth / 2))
    previewY = position.y + Theme.spaceXS
    previewOpen = true
    root.refreshPreviewWindows()
  }

  PopupWindow {
    id: workspacePreviewPopup

    anchor.window: root.barWindow
    anchor.rect.x: root.previewX
    anchor.rect.y: root.previewY
    visible: root.previewOpen
    grabFocus: true
    color: "transparent"
    surfaceFormat.opaque: false
    implicitWidth: 420
    implicitHeight: 286

    onVisibleChanged: {
      if (!visible)
        root.previewOpen = false
    }

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.withAlpha(Theme.widgetBaseBackgroundColor, typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.6)
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.35)

      Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Text {
          width: parent.width
          height: 20
          text: qsTr("Workspace %1").arg(root.previewWorkspaceId)
          color: Theme.widgetTextColor
          font.pixelSize: 14
          font.weight: Font.DemiBold
          verticalAlignment: Text.AlignVCenter
        }

        Item {
          id: previewCanvas

          readonly property int windowCount: root.previewWindows.length
          readonly property int columns: Math.max(1, Math.ceil(Math.sqrt(windowCount)))
          readonly property int rows: Math.max(1, Math.ceil(windowCount / columns))
          readonly property real cellWidth: width / columns
          readonly property real cellHeight: height / rows

          width: parent.width
          height: 218
          clip: true

          Repeater {
            model: root.previewWindows

            delegate: Rectangle {
              required property int index
              required property var modelData

              x: (index % previewCanvas.columns) * previewCanvas.cellWidth + 2
              y: Math.floor(index / previewCanvas.columns) * previewCanvas.cellHeight + 2
              width: Math.max(1, previewCanvas.cellWidth - 4)
              height: Math.max(1, previewCanvas.cellHeight - 4)
              radius: Theme.cornerRadius
              color: Theme.surfaceContainer
              clip: true

              ScreencopyView {
                  anchors.fill: parent
                  captureSource: modelData.wayland ?? null
                  live: root.previewOpen
                  constraintSize.width: parent.width
                  constraintSize.height: parent.height
              }

              Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: 22
                  color: Theme.withAlpha(Theme.surfaceContainer, 0.85)

                  Text {
                      anchors.fill: parent
                      anchors.leftMargin: 6
                      anchors.rightMargin: 6
                      text: modelData.title || modelData.wayland.title || qsTr("Application")
                      color: Theme.widgetTextColor
                      font.pixelSize: 10
                      elide: Text.ElideRight
                      verticalAlignment: Text.AlignVCenter
                  }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.previewWindows.length === 0
            text: qsTr("No open windows")
            color: Theme.widgetInactiveIconColor
            font.pixelSize: 13
          }
        }

        Text {
          width: parent.width
          height: 14
          text: qsTr("Right-click an inactive workspace to preview it")
          color: Theme.widgetInactiveIconColor
          font.pixelSize: 10
          elide: Text.ElideRight
        }
      }
    }
  }

  Timer {
    interval: 500
    repeat: true
    running: root.previewOpen
    onTriggered: root.refreshPreviewWindows()
  }

  content: Component {
    Row {
      spacing: 5

      Repeater {
        model: WorkspacesService.workspaceIds

        delegate: Rectangle {
          required property int modelData
          readonly property bool isActive: modelData === root.activeId
          readonly property bool isOccupied: WorkspacesService.occupiedIds.indexOf(modelData) !== -1

          width: isActive ? 32 : 24
          height: 24
          anchors.verticalCenter: parent.verticalCenter
          radius: height / 2
          color: isActive ? Theme.primary
                      : (isOccupied ? Theme.surfaceContainerHighest : Theme.surfaceVariant)
          opacity: isActive ? 1.0 : (isOccupied ? 0.75 : 0.45)

          Behavior on width {
            NumberAnimation {
              duration: 180
              easing.type: Easing.OutCubic
            }
          }
          Behavior on color {
            ColorAnimation {
              duration: 180
              easing.type: Easing.OutCubic
            }
          }
          Behavior on opacity {
            NumberAnimation {
              duration: 180
              easing.type: Easing.OutCubic
            }
          }

          Text {
            anchors.centerIn: parent
            text: String(modelData)
            color: isActive ? Theme.onPrimary : Theme.withAlpha(Theme.surfaceText, 0.9)
            font.pixelSize: Theme.fontSizeSmall
            font.bold: isActive
            opacity: isActive ? 1.0 : 0.95
          }

          MouseArea {
            z: 1
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
              mouse.accepted = true
              if (mouse.button === Qt.RightButton) {
                  if (!isActive)
                      root.togglePreview(Number(modelData), parent)
                  return
              }
              root.switchToWorkspace(Number(modelData), switchProcess)
            }
          }

          Process {
            id: switchProcess
            command: WorkspacesService.switchCommand(Number(modelData))
          }
        }
      }
    }
  }

  function switchToWorkspace(workspaceId, process) {
    const id = Number(workspaceId)
    if (!Number.isFinite(id) || id < 1) return
    console.log("Switching to workspace", id)
    process.command = WorkspacesService.switchCommand(id)
    process.running = true
  }
}
