import QtQuick
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
            color: isActive ? Theme.onPrimary : Theme.onSurface
            font.pixelSize: Theme.fontSizeSmall
            font.bold: isActive
            opacity: parent.opacity > 0.6 ? 1.0 : 0.8
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: WorkspacesService.switchTo(modelData)
          }
        }
      }
    }
  }
}
