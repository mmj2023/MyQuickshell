import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Disk usage pill. Reads the shared SystemStatsService so all stats share one
// poller. Left click cycles the display format (percent vs a short label).
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null

  property bool showLabel: false
  property bool detailsOpen: false
  property int popupX: 0
  property int popupY: 0
  readonly property var mounts: SystemStatsService.diskMounts

  content: Component {
    Item {
      implicitWidth: collapsedRow.implicitWidth
      implicitHeight: collapsedRow.implicitHeight
      Row {
        id: collapsedRow
        visible: !root.showLabel
        spacing: 4
        anchors.centerIn: parent
        Repeater {
          model: root.mounts
          delegate: Row {
            required property var modelData
            spacing: 3
            DmsIcon {
              name: "storage"
              size: root.iconSize()
              color: root.usageColor(modelData.usage)
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: root.displayMount(modelData.mount) + " " + Math.round(modelData.usage) + "%"
              color: Theme.widgetTextColor
              font.family: Theme.monoFontFamily
              font.pixelSize: root.textSize()
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }
      Column {
        id: expandedColumn
        visible: false
      }

      PopupWindow {
        id: detailsPopup
        anchor.window: root.barWindow
        anchor.rect.x: root.popupX
        anchor.rect.y: root.popupY
        visible: root.detailsOpen && root.mounts.length > 0
        grabFocus: false
        color: "transparent"
        implicitWidth: Math.max(180, detailsColumn.implicitWidth + 20)
        implicitHeight: detailsColumn.implicitHeight + 16

        Rectangle {
          anchors.fill: parent
          radius: Theme.cornerRadius
          color: {
            const transparency = typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.6
            return Theme.withAlpha(Theme.surfaceContainer, transparency)
          }
          border.width: 1
          border.color: Theme.withAlpha(Theme.outline, 0.35)

          Column {
            id: detailsColumn
            anchors.centerIn: parent
            spacing: 3

            Repeater {
              model: root.mounts
              delegate: Text {
                required property var modelData
                text: modelData.mount + " " + Math.round(modelData.usage) + "% "
                  + SystemStatsService._fmtBytes(modelData.used) + "/"
                  + SystemStatsService._fmtBytes(modelData.total)
                color: Theme.widgetTextColor
                font.family: Theme.monoFontFamily
                font.pixelSize: root.textSize()
              }
            }

          }

          MouseArea {
            anchors.fill: parent
            z: 1
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.detailsOpen = false
              detailsTimer.stop()
              analyzerProc.running = true
            }
          }
        }
      }
    }
  }

  function usageColor(usage) {
    return usage > 90 ? Theme.error
      : (usage > 75 ? Theme.warning : Theme.widgetIconColor)
  }

  function displayMount(mount) {
    const homePrefix = "/home/" + Quickshell.env("USER")
    return mount === homePrefix ? "~" :
      (mount.indexOf(homePrefix + "/") === 0 ? "~" + mount.slice(homePrefix.length) : mount)
  }

  function updatePopupPosition() {
    if (!root.barWindow)
      return
    const point = root.mapToItem(root.barWindow.contentItem, 0, root.height)
    root.popupX = Math.round(point.x)
    root.popupY = Math.round(point.y)
  }

  Timer {
    id: detailsTimer
    interval: 5000
    repeat: false
    onTriggered: root.detailsOpen = false
  }

  Process {
    id: analyzerProc
    command: ["baobab", "/"]
  }

  onClicked: {
    root.updatePopupPosition()
    if (root.detailsOpen) {
      root.detailsOpen = false
      detailsTimer.stop()
      return
    }
    root.detailsOpen = true
    detailsTimer.restart()
  }
}
