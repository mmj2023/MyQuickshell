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
  readonly property string homeMountPath: "/home/" + Quickshell.env("USER")
  readonly property var primaryMounts: [
    root.mounts.find(item => item.mount === "/") || null,
    root.mounts.find(item => item.mount === "/boot") || null,
    root.mounts.find(item => item.mount === "/home" || item.mount === root.homeMountPath) || null
  ].filter(item => item !== null)
  readonly property var secondaryMounts: root.mounts
    .filter(item => !root.primaryMounts.some(primary => primary.mount === item.mount))
    .slice()
    .sort((a, b) => {
      const groupA = root.mountGroup(a.mount)
      const groupB = root.mountGroup(b.mount)
      if (groupA !== groupB)
        return groupA - groupB
      const depthA = a.mount.split("/").filter(part => part !== "").length
      const depthB = b.mount.split("/").filter(part => part !== "").length
      return depthA === depthB ? a.mount.localeCompare(b.mount) : depthA - depthB
    })
    readonly property real secondaryLineHeight: Math.max(9, Math.round(root.textSize() * 0.7)) + 2
    readonly property real primaryLineHeight: Math.max(root.iconSize(), root.textSize()) + 2
    readonly property real primaryGroupHeight: {
      let maxHeight = 0
      for (let i = 0; i < root.primaryMounts.length; i++)
        maxHeight = Math.max(maxHeight, root.primaryLineHeight
          + root.secondaryMountsFor(root.primaryMounts[i].mount).length * root.secondaryLineHeight)
      return maxHeight
  }

  content: Component {
    Item {
      id: contentRoot
      implicitWidth: storageColumn.implicitWidth
      implicitHeight: storageColumn.implicitHeight

      Column {
        id: storageColumn
        anchors.centerIn: parent
        spacing: 1
        visible: !root.showLabel

        Row {
          id: primaryMountRow
          spacing: 4
          height: root.primaryGroupHeight

          Repeater {
            model: root.primaryMounts

            delegate: Item {
              id: mountGroup
              required property var modelData
              readonly property var childMounts: root.secondaryMountsFor(modelData.mount)
              readonly property real lineHeight: root.primaryLineHeight

              implicitWidth: groupColumn.implicitWidth
              width: implicitWidth
              height: root.primaryGroupHeight

              Column {
                id: groupColumn
                y: parent.childMounts.length > 0
                  ? 0 : (parent.height - parent.lineHeight) / 2
                spacing: 0

                Row {
                  id: primaryLine
                  height: root.primaryLineHeight
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
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Repeater {
                  model: mountGroup.childMounts

                  delegate: Row {
                    required property var modelData
                    height: root.secondaryLineHeight
                    spacing: 3

                    Item {
                      width: root.iconSize()
                      height: root.secondaryLineHeight

                      DmsIcon {
                        anchors.centerIn: parent
                        name: "storage"
                        size: Math.max(10, Math.round(root.iconSize() * 0.65))
                        color: Theme.widgetInactiveIconColor
                      }
                    }

                    Text {
                      text: root.displayMountRelative(modelData.mount, mountGroup.modelData.mount)
                        + " " + Math.round(modelData.usage) + "%"
                      color: Theme.widgetInactiveIconColor
                      font.family: Theme.monoFontFamily
                      font.pixelSize: Math.max(9, Math.round(root.textSize() * 0.7))
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }
            }
          }
        }

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

  function displayMountRelative(mount, parentMount) {
    const homePrefix = "/home/" + Quickshell.env("USER")
    if (mount === homePrefix || mount.indexOf(homePrefix + "/") === 0)
      return root.displayMount(mount)
    const prefix = parentMount === "/" ? "/" : parentMount + "/"
    return mount.indexOf(prefix) === 0 ? mount.slice(parentMount.length) : root.displayMount(mount)
  }

  function mountGroup(mount) {
    if (mount.indexOf("/boot/") === 0)
      return 0
    if (mount === "/home" || mount.indexOf("/home/") === 0)
      return 1
    return 2
  }

  function secondaryMountsFor(primaryMount) {
    return root.secondaryMounts.filter(item => root.primaryParentFor(item.mount) === primaryMount)
  }

  function primaryParentFor(mount) {
    let parentMount = ""
    for (let i = 0; i < root.primaryMounts.length; i++) {
      const candidate = root.primaryMounts[i].mount
      const prefix = candidate === "/" ? "/" : candidate + "/"
      if (mount.indexOf(prefix) === 0 && candidate.length > parentMount.length)
        parentMount = candidate
    }
    return parentMount
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
