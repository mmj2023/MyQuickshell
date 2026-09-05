import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// System tray. Renders a pill containing each StatusNotifier item as an icon.
// Left click activates, right click opens the item's menu when available.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null
  property var openMenuItem: null
  property int menuX: 0
  property int menuY: 0

  content: Component {
    Row {
      spacing: 2

      Repeater {
        // Use the actual SNI objects rather than the collection wrapper so
        // delegates expose activate() and display() directly.
        model: TrayService.items.values

        delegate: Rectangle {
          required property var modelData
          readonly property var item: modelData

          width: 26
          height: 26
          anchors.verticalCenter: parent.verticalCenter
          radius: Theme.pillRadius
          color: hovered ? Theme.surfaceText_12 : "transparent"

          property bool hovered: false

          IconImage {
            anchors.centerIn: parent
            source: root._iconOf(item)
            implicitSize: 18
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: parent.hovered = true
            onExited: parent.hovered = false
            onClicked: function(mouse) {
              root._trayClick(item, mouse.button)
            }
          }
        }
      }
    }
  }

  function _iconOf(item) {
    return item && item.icon ? item.icon : ""
  }

  function _trayClick(item, button) {
    if (!item) return
    if (button === Qt.RightButton && item.hasMenu) {
      const point = root.mapToItem(root.barWindow.contentItem, root.width / 2, root.height)
      root.menuX = Math.round(point.x - trayMenu.width / 2)
      root.menuY = Math.round(point.y)
      root.openMenuItem = item
    } else if (button === Qt.LeftButton) {
      item.activate()
    }
  }

  QsMenuOpener {
    id: menuOpener
    menu: root.openMenuItem ? root.openMenuItem.menu : null
  }

  PopupWindow {
    id: trayMenu
    parentWindow: root.barWindow
    relativeX: root.menuX
    relativeY: root.menuY
    visible: root.openMenuItem !== null
    grabFocus: true
    color: "transparent"
    implicitWidth: 240
    implicitHeight: Math.min(420, menuList.contentHeight + 16)

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: {
        const transparency = typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.6
        return Theme.withAlpha(Theme.surfaceContainer, transparency)
      }
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.35)

      ListView {
        id: menuList
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        spacing: 2
        model: menuOpener.children.values

        delegate: Rectangle {
          required property var modelData
          readonly property var entry: modelData
          width: menuList.width
          height: entry.isSeparator ? 1 : 32
          radius: 6
          color: entry.isSeparator ? Theme.withAlpha(Theme.outline, 0.3)
                                   : (menuMouse.containsMouse ? Theme.surfaceText_12 : "transparent")
          opacity: entry.enabled ? 1 : 0.45

          Rectangle {
            visible: entry.isSeparator
            anchors.fill: parent
            color: Theme.withAlpha(Theme.outline, 0.3)
          }

          Text {
            visible: !entry.isSeparator
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: entry.text
            color: "#ffffff"
            font.pixelSize: Theme.fontSizeSmall
          }

          Text {
            visible: !entry.isSeparator && entry.hasChildren
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: "#ffffff"
            font.pixelSize: Theme.fontSizeMedium
          }

          MouseArea {
            id: menuMouse
            anchors.fill: parent
            enabled: !entry.isSeparator && entry.enabled
            hoverEnabled: true
            onClicked: {
              if (entry.hasChildren)
                entry.display(root.barWindow, root.menuX + trayMenu.width, root.menuY + y)
              else {
                entry.sendTriggered()
                root.openMenuItem = null
              }
            }
          }
        }
      }
    }
  }
}
