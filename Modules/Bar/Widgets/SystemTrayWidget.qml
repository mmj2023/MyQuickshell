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
  property var submenuStack: []
  property int menuX: 0
  property int menuY: 0
  property int submenuX: 0
  property int submenuY: 0
  property bool overflowOpen: false
  property int trayRevision: 0

  readonly property var allItems: {
    void trayRevision
    return TrayService.items.values || []
  }

  function _activateEntry(entry) {
    if (!entry)
      return
    if (typeof entry.activate === "function")
      entry.activate()
    else if (typeof entry.triggered === "function")
      entry.triggered()
    else if (typeof entry.sendTriggered === "function")
      entry.sendTriggered()
  }

  readonly property var hiddenIds: typeof SettingsData !== "undefined" ? SettingsData.hiddenTrayIds : []
  readonly property var hiddenItems: root.allItems.filter(function(item) {
    return root.hiddenIds.indexOf(root.trayKey(item)) !== -1
  })
  readonly property var visibleItems: root.allItems.filter(function(item) {
    return root.hiddenIds.indexOf(root.trayKey(item)) === -1
  })

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  function resetSubmenus() {
    const stack = root.submenuStack
    root.submenuStack = []
    for (let i = stack.length - 1; i >= 0; --i)
      stack[i].opener.destroy()
  }

  function openSubmenu(entry, x, y) {
    const stack = root.submenuStack.slice()
    if (stack.length > 0) {
      const previous = stack.pop()
      previous.opener.destroy()
    }
    const opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener)
      return
    root.submenuX = Math.round(x)
    root.submenuY = Math.round(y)
    stack.push({ opener: opener })
    root.submenuStack = stack
  }

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
            id: trayIcon
            anchors.centerIn: parent
            source: root._iconOf(item)
            width: 18
            height: 18
            asynchronous: true
            smooth: true
            mipmap: true
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: !trayIcon.visible
            text: root._fallbackLabel(item)
            color: Theme.widgetTextColor
            font.pixelSize: 10
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
            function onWidgetTextColorChanged() { overflowChevron.requestPaint() }
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
      root.resetSubmenus()
    }
  }

  Connections {
    target: TrayService.items
    function onValuesChanged() {
      root.trayRevision++
      root.overflowOpen = false
      root.openMenuItem = null
      root.resetSubmenus()
    }
  }

  function _iconOf(item) {
    return _iconSource(item && item.icon)
  }

  function _fallbackLabel(item) {
    if (!item)
      return "?"
    const itemId = String(item.id || "").trim()
    return itemId === "" ? "?" : itemId.charAt(0).toUpperCase()
  }

  function _iconSource(icon) {
    if (!icon)
      return ""

    const value = String(icon)
    if (value === "")
      return ""

    if (value.indexOf("?path=") !== -1) {
      const split = value.split("?path=")
      if (split.length === 2) {
        const name = split[0]
        const path = split[1]
        let fileName = name.substring(name.lastIndexOf("/") + 1)
        if (fileName.indexOf("dropboxstatus") === 0)
          fileName = "hicolor/16x16/status/" + fileName
        return "file://" + path + "/" + fileName
      }
    }

    if (value.indexOf("/") === 0 && value.indexOf("file://") !== 0)
      return "file://" + value

    return value
  }

  function _menuText(entry) {
    if (!entry || !entry.text)
      return ""
    return String(entry.text).replace(/\s*<IMAGE>/g, "")
  }

  function _trayClick(item, button) {
    if (!item) return
    if (button === Qt.RightButton && item.hasMenu) {
      const point = root.mapToItem(root.barWindow.contentItem, root.width / 2, root.height)
      const x = Math.round(point.x - trayMenu.width / 2)
      const y = Math.round(point.y)

      // Reset first so repeated clicks on the same item always rehydrate the
      // QsMenuOpener and reopen a popup that the compositor already closed.
      root.openMenuItem = null
      root.resetSubmenus()
      root.menuX = x
      root.menuY = y
      Qt.callLater(function() {
        root.openMenuItem = item
      })
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
              id: hiddenTrayIcon
              anchors.centerIn: parent
              source: root._iconOf(modelData)
              width: 18
              height: 18
              asynchronous: true
              smooth: true
              mipmap: true
              visible: status === Image.Ready
            }

            Text {
              anchors.centerIn: parent
              visible: !hiddenTrayIcon.visible
              text: root._fallbackLabel(modelData)
              color: Theme.widgetTextColor
              font.pixelSize: 10
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
          readonly property var iconSource: entry.icon
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
            anchors.leftMargin: iconSource !== "" ? 38 : 10
            anchors.verticalCenter: parent.verticalCenter
            text: root._menuText(entry)
            color: "#ffffff"
            font.pixelSize: Theme.fontSizeSmall
          }

          Image {
            visible: !entry.isSeparator && iconSource
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            source: iconSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
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
                root.openSubmenu(entry, root.menuX + trayMenu.width, root.menuY + y)
              else {
                root._activateEntry(entry)
                root.openMenuItem = null
              }
            }
          }

          PopupWindow {
            id: submenuPopup
            anchor.window: trayMenu
            anchor.rect.x: trayMenu.width
            anchor.rect.y: root.submenuY - root.menuY
            visible: root.openMenuItem !== null && root.submenuStack.length > 0
            grabFocus: true
            color: "transparent"
            implicitWidth: 240
            implicitHeight: Math.min(420, submenuList.contentHeight + 16)

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
                id: submenuList
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 2
                model: {
                  const level = root.submenuStack[root.submenuStack.length - 1]
                  const children = level ? level.opener.children : null
                  return children && children.values ? children.values : (children || [])
                }

                delegate: Rectangle {
                  required property var modelData
                  readonly property var entry: modelData
                  readonly property var iconSource: entry.icon
                  width: submenuList.width
                  height: entry.isSeparator ? 1 : 32
                  radius: 6
                  color: entry.isSeparator ? Theme.withAlpha(Theme.outline, 0.3)
                                           : (submenuMouse.containsMouse ? Theme.surfaceText_12 : "transparent")
                  opacity: entry.enabled ? 1 : 0.45

                  Rectangle {
                    visible: entry.isSeparator
                    anchors.fill: parent
                    color: Theme.withAlpha(Theme.outline, 0.3)
                  }

                  Text {
                    visible: !entry.isSeparator
                    anchors.left: parent.left
                    anchors.leftMargin: iconSource !== "" ? 38 : 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._menuText(entry)
                    color: "#ffffff"
                    font.pixelSize: Theme.fontSizeSmall
                  }

                  Image {
                    visible: !entry.isSeparator && iconSource
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    source: iconSource
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
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
                    id: submenuMouse
                    anchors.fill: parent
                    enabled: !entry.isSeparator && entry.enabled
                    hoverEnabled: true
                    onClicked: {
                      if (entry.hasChildren)
                        root.openSubmenu(entry, root.submenuX + submenuPopup.width, root.submenuY + y)
                      else {
                        root._activateEntry(entry)
                        root.openMenuItem = null
                        root.resetSubmenus()
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
