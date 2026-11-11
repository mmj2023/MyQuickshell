import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services

Item {
  id: root

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: switcherWindow
      required property var modelData
      screen: modelData
      visible: WindowSwitcherService.visible
        && modelData.name === WindowSwitcherService.monitorName
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      surfaceFormat.opaque: false
      WlrLayershell.namespace: "quickshell"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: visible
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      Item {
        id: overlay
        anchors.fill: parent
        focus: switcherWindow.visible

        Rectangle {
          anchors.fill: parent
          color: Theme.withAlpha(Theme.scrim, 0.3)

          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (WindowSwitcherService.overlayLatched)
                WindowSwitcherService.commit()
              else
                WindowSwitcherService.cancel()
            }
          }
        }

        Rectangle {
          id: switcherCard
          readonly property int cardWidth: 220
          readonly property int cardHeight: 206
          readonly property int listWidth: Math.max(1, Math.min(
            overlay.width - Theme.spaceXL * 2,
            Math.max(cardWidth, Math.min(WindowSwitcherService.windows.length, 5)
              * cardWidth + (Math.min(WindowSwitcherService.windows.length, 5) - 1)
              * Theme.spaceS)))
          anchors.centerIn: parent
          transformOrigin: Item.Center
          scale: switcherWindow.visible ? 1 : 0.94
          transform: Translate {
            y: switcherWindow.visible ? 0 : Theme.spaceS

            Behavior on y {
              NumberAnimation {
                duration: 40
                easing.type: Theme.standardEasing
              }
            }
          }
          width: Math.max(1, Math.min(overlay.width - Theme.spaceXL * 2,
            listWidth + Theme.spaceL * 2))
          height: switcherContent.implicitHeight + Theme.spaceL * 2
          radius: Theme.cornerRadius
          color: Theme.withAlpha(
            Theme.widgetBaseBackgroundColor,
            SettingsData.popupTransparency
          )
          border.width: 1
          border.color: Theme.withAlpha(Theme.outline, 0.35)

          Behavior on scale {
            NumberAnimation {
              duration: 40
              easing.type: Theme.standardEasing
            }
          }

          Column {
            id: switcherContent
            anchors.fill: parent
            anchors.margins: Theme.spaceL
            spacing: Theme.spaceM

            Row {
              width: parent.width
              height: Theme.spaceXL

              Text {
                width: parent.width - switcherCount.width
                height: parent.height
                text: WindowSwitcherService.viewTitle
                color: Theme.surfaceText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                verticalAlignment: Text.AlignVCenter
              }

              Text {
                id: switcherCount
                width: implicitWidth
                height: parent.height
                text: WindowSwitcherService.windows.length > 0
                  ? qsTr("%1 / %2").arg(WindowSwitcherService.selectedIndex + 1)
                    .arg(WindowSwitcherService.windows.length)
                  : ""
                color: Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                verticalAlignment: Text.AlignVCenter
              }
            }

            ListView {
              id: windowList
              width: switcherCard.listWidth
              height: switcherCard.cardHeight
              orientation: ListView.Horizontal
              spacing: Theme.spaceS
              clip: true
              model: WindowSwitcherService.windows
              currentIndex: WindowSwitcherService.selectedIndex
              highlightFollowsCurrentItem: false
              onCurrentIndexChanged: {
                if (currentIndex >= 0)
                  positionViewAtIndex(currentIndex, ListView.Contain)
              }

              delegate: Rectangle {
                id: windowCard
                required property int index
                required property var modelData
                width: switcherCard.cardWidth
                height: switcherCard.cardHeight
                radius: Theme.cornerRadius
                color: Theme.withAlpha(
                  Theme.surfaceContainerHigh,
                  SettingsData.popupTransparency
                )
                border.width: index === WindowSwitcherService.selectedIndex ? 2 : 1
                border.color: index === WindowSwitcherService.selectedIndex
                  ? Theme.primary : Theme.withAlpha(Theme.outlineVariant, 0.5)
                clip: true

                Column {
                  anchors.fill: parent
                  anchors.margins: windowCard.border.width
                  spacing: 0

                  Rectangle {
                    width: parent.width
                    height: 150
                    color: "transparent"
                    clip: true

                    Rectangle {
                      anchors.fill: parent
                      visible: !windowPreview.hasContent
                      color: Theme.surfaceContainer

                      Text {
                        anchors.centerIn: parent
                        text: qsTr("Preview unavailable")
                        color: Theme.surfaceText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                      }
                    }

                    ScreencopyView {
                      id: windowPreview
                      anchors.fill: parent
                      captureSource: windowCard.modelData.window
                      live: switcherWindow.visible
                        && index === WindowSwitcherService.selectedIndex
                      constraintSize.width: parent.width
                      constraintSize.height: parent.height
                    }
                  }

                  Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: parent.height - 150
                    spacing: Theme.spaceS
                    anchors.leftMargin: Theme.spaceS
                    anchors.rightMargin: Theme.spaceS

                    IconImage {
                      anchors.verticalCenter: parent.verticalCenter
                      source: Theme.getAppIcon(windowCard.modelData.appId)
                      implicitSize: Theme.spaceL
                      asynchronous: true
                    }

                    Text {
                      width: parent.width - Theme.spaceXL - Theme.spaceS * 3
                      height: parent.height
                      text: windowCard.modelData.title
                      color: Theme.surfaceText
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall
                      verticalAlignment: Text.AlignVCenter
                      elide: Text.ElideRight
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: WindowSwitcherService.selectedIndex = windowCard.index
                  onClicked: {
                    WindowSwitcherService.selectedIndex = windowCard.index
                    if (WindowSwitcherService.isGroupItem(windowCard.modelData))
                      WindowSwitcherService.enterSelectedGroup()
                    else
                      WindowSwitcherService.commit()
                  }
                }
              }
            }

            Text {
              width: parent.width
              height: Theme.spaceL
              text: WindowSwitcherService.viewMode !== "top"
                ? qsTr("Tab cycles apps · Enter selects · Esc returns")
                : qsTr("Ctrl pins · Tab cycles · Enter opens/selects · Alt release commits")
              color: Theme.widgetInactiveIconColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
            }
          }
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Control) {
            if (!event.isAutoRepeat)
              WindowSwitcherService.latchOverlay()
            event.accepted = true
          } else if (event.key === Qt.Key_Alt) {
            WindowSwitcherService.handleAltPress()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
              || event.key === Qt.Key_QuoteLeft) {
            if (!event.isAutoRepeat) {
              const reverse = event.key === Qt.Key_Backtab
                || (event.modifiers & Qt.ShiftModifier) !== 0
              WindowSwitcherService.cycle(reverse ? -1 : 1, true)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            WindowSwitcherService.handleEscape()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            WindowSwitcherService.handleEnter()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            WindowSwitcherService.cycle(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            WindowSwitcherService.cycle(1)
            event.accepted = true
          }
        }

        Keys.onReleased: function(event) {
          if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
              || event.key === Qt.Key_QuoteLeft) {
            if (event.isAutoRepeat) {
              event.accepted = true
              return
            }
            WindowSwitcherService.handleSwitcherKeyRelease()
            event.accepted = true
          } else if (event.key === Qt.Key_Alt) {
            WindowSwitcherService.handleAltRelease()
            event.accepted = true
          }
        }
      }
    }
  }
}
