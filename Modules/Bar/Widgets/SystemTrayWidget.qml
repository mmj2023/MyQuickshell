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
  property bool overflowOpen: false
  property int trayRevision: 0

  readonly property var allItems: {
    void trayRevision
    return TrayService.items.values || []
  }
  readonly property var hiddenIds: typeof SettingsData !== "undefined" ? SettingsData.hiddenTrayIds : []
  readonly property var hiddenItems: root.allItems.filter(function(item) {
    return root.hiddenIds.indexOf(root.trayKey(item)) !== -1
  })
  readonly property var visibleItems: root.allItems.filter(function(item) {
    return root.hiddenIds.indexOf(root.trayKey(item)) === -1
  })

  function trayKey(item) {
    return item && item.id ? String(item.id) : ""
  }

  content: Component {
    Row {
      spacing: 2

      Repeater {
        // Use the actual SNI objects rather than the collection wrapper so
        // delegates expose activate() and display() directly.
        model: root.visibleItems

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
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: parent.hovered = true
            onExited: parent.hovered = false
            onClicked: function(mouse) {
              if (mouse.button === Qt.MiddleButton) {
                SettingsData.hideTrayId(root.trayKey(item))
                return
              }
              root._trayClick(item, mouse.button)
            }
          }
        }
      }

      Rectangle {
        visible: root.hiddenItems.length > 0
        width: 24
        height: 26
        radius: Theme.pillRadius
        color: overflowMouse.containsMouse ? Theme.surfaceText_12 : "transparent"

        Canvas {
          id: overflowChevron
          anchors.centerIn: parent
          width: 14
          height: 14

          onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = Theme.widgetTextColor
            ctx.lineWidth = 2
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.beginPath()
            if (root.overflowOpen) {
              ctx.moveTo(2, 9)
              ctx.lineTo(7, 4)
              ctx.lineTo(12, 9)
            } else {
              ctx.moveTo(2, 5)
              ctx.lineTo(7, 10)
              ctx.lineTo(12, 5)
            }
            ctx.stroke()
          }

          Connections {
            target: Theme
            function onWidgetTextColorChanged() { parent.requestPaint() }
          }

          Connections {
            target: root
            function onOverflowOpenChanged() { overflowChevron.requestPaint() }
          }
        }

        MouseArea {
          id: overflowMouse
          z: 2
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPressed: function(mouse) {
            mouse.accepted = true
            const point = root.mapToItem(root.barWindow.contentItem, root.width / 2, root.height)
            root.menuX = Math.round(point.x - overflowPopup.width / 2)
            root.menuY = Math.round(point.y)
            root.overflowOpen = !root.overflowOpen
          }
        }
      }
    }
  }

  Connections {
    target: SettingsData
    function onHiddenTrayIdsChanged() {
      root.trayRevision++
      root.overflowOpen = false
      root.openMenuItem = null
    }
  }

  Connections {
    target: TrayService.items
    function onValuesChanged() {
      root.trayRevision++
      root.overflowOpen = false
      root.openMenuItem = null
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

  PopupWindow {
    id: overflowPopup
    anchor.window: root.barWindow
    anchor.rect.x: root.menuX
    anchor.rect.y: root.menuY
    visible: root.overflowOpen
    grabFocus: true
    color: "transparent"
    implicitWidth: Math.max(48, hiddenRow.implicitWidth + 16)
    implicitHeight: 42

    onVisibleChanged: {
      if (!visible)
        root.overflowOpen = false
    }

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: {
        const transparency = typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.6
        return Theme.withAlpha(Theme.surfaceContainer, transparency)
      }
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.35)

      Row {
        id: hiddenRow
        anchors.centerIn: parent
        width: childrenRect.width
        spacing: 2

        Repeater {
          model: root.hiddenItems
          delegate: Rectangle {
            required property var modelData
            width: 26
            height: 26
            radius: Theme.pillRadius
            color: hiddenMouse.containsMouse ? Theme.surfaceText_12 : "transparent"

            IconImage {
              anchors.centerIn: parent
              source: root._iconOf(modelData)
              implicitSize: 18
            }

            MouseArea {
              id: hiddenMouse
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton && modelData.hasMenu) {
                  root._trayClick(modelData, Qt.RightButton)
                } else if (mouse.button === Qt.LeftButton) {
                  // Keep the button state in sync before activating an item.
                  // PopupWindow can also close itself when its grab is released.
                  root.overflowOpen = false
                  if (modelData.onlyMenu && modelData.hasMenu)
                    root._trayClick(modelData, Qt.RightButton)
                  else
                    modelData.activate()
                }
              }
            }
          }
        }
      }
    }
  }

  QsMenuOpener {
    id: menuOpener
    menu: root.openMenuItem ? root.openMenuItem.menu : null
  }

  PopupWindow {
    id: trayMenu
    anchor.window: root.barWindow
    anchor.rect.x: root.menuX
    anchor.rect.y: root.menuY
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
        header: Rectangle {
          width: menuList.width
          height: 32
          radius: 6
          color: menuHeaderMouse.containsMouse ? Theme.surfaceText_12 : "transparent"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: SettingsData.isTrayHidden(root.trayKey(root.openMenuItem))
              ? "Show icon"
              : "Hide icon in overflow"
            color: "#ffffff"
            font.pixelSize: Theme.fontSizeSmall
          }

          MouseArea {
            id: menuHeaderMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              const itemKey = root.trayKey(root.openMenuItem)
              if (SettingsData.isTrayHidden(itemKey))
                SettingsData.showTrayId(itemKey)
              else
                SettingsData.hideTrayId(itemKey)
              root.openMenuItem = null
            }
          }
        }

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
