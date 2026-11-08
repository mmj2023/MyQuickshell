import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Common
import qs.Modules.Bar
import qs.Services

// The top bar. Instantiates one PanelWindow layer surface per screen via
// Variants over Quickshell.screens. Clicking empty bar space toggles its
// background; right-clicking opens per-bar display options.
Item {
  id: root

  readonly property int barTransparency: typeof SettingsData !== "undefined" ? (SettingsData.barTransparency || 0) : 0

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activespecial")
        Hyprland.refreshMonitors()
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData
        screen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    property real contextMenuX: 0
    readonly property bool backgroundEnabled: root.barTransparency !== 0
    readonly property var hyprlandMonitor: Hyprland.monitorFor(barWindow.screen)
    readonly property var specialWorkspace: barWindow.hyprlandMonitor?.lastIpcObject?.specialWorkspace
    readonly property bool specialWorkspaceOverFullscreen: {
      const special = barWindow.specialWorkspace
      const monitor = barWindow.hyprlandMonitor
      const activeToplevel = Hyprland.activeToplevel
      if (!monitor || !special || !activeToplevel || !activeToplevel.workspace)
        return false
      return !!monitor
        && !!monitor.activeWorkspace?.hasFullscreen
        && special.id !== 0
        && special.name.startsWith("special:")
        && (activeToplevel.workspace.name !== special.name || !activeToplevel.workspace.hasFullscreen)
    }

    anchors {
      top: true
      left: true
      right: true
    }

    implicitHeight: Theme.barHeight + Theme.space2() * 2
    color: barWindow.backgroundEnabled
      ? Theme.withAlpha(Theme.surfaceContainer, 1)
      : "transparent"
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Auto
    WlrLayershell.namespace: "mybar"
    WlrLayershell.layer: barWindow.specialWorkspaceOverFullscreen
      ? WlrLayer.Overlay : WlrLayer.Top

    BackgroundEffect.blurRegion: SettingsData.barBlurEnabled ? barBlurRegion : null

    Region {
      id: barBlurRegion
      x: 0
      y: 0
      width: barWindow.width
      height: barWindow.height
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          barWindow.contextMenuX = mouse.x
          barContextMenu.visible = true
        } else {
          SettingsData.set("barTransparency", barWindow.backgroundEnabled ? 0 : 1)
        }
      }
    }

    PopupWindow {
      id: barContextMenu
      anchor.window: barWindow
      anchor.rect.x: Math.max(Theme.spaceS, Math.min(
        barWindow.width - implicitWidth - Theme.spaceS,
        barWindow.contextMenuX - implicitWidth / 2
      ))
      anchor.rect.y: barWindow.height + Theme.spaceXS
      visible: false
      grabFocus: true
      color: "transparent"
      surfaceFormat.opaque: false
      implicitWidth: 216
      implicitHeight: contextMenuContent.implicitHeight + Theme.spaceS * 2

      Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.6)

        Column {
          id: contextMenuContent
          anchors.fill: parent
          anchors.margins: Theme.spaceS
          spacing: Theme.spaceXS

          Repeater {
            model: [
              { label: "Bar background", enabled: barWindow.backgroundEnabled, setting: "background" },
              { label: "Blur behind bar", enabled: SettingsData.barBlurEnabled, setting: "blur" }
            ]

            delegate: Item {
              required property var modelData
              width: contextMenuContent.width
              height: Theme.spaceXL + Theme.spaceS

              Rectangle {
                anchors.fill: parent
                radius: Theme.hoverRadius
                color: optionMouse.containsMouse
                  ? Theme.withAlpha(Theme.primary, 0.12)
                  : "transparent"
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spaceS
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: Theme.surfaceText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spaceS
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.enabled ? "On" : "Off"
                color: modelData.enabled ? Theme.primary : Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }

              MouseArea {
                id: optionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData.setting === "background")
                    SettingsData.set("barTransparency", barWindow.backgroundEnabled ? 0 : 1)
                  else
                    SettingsData.set("barBlurEnabled", !SettingsData.barBlurEnabled)
                }
              }
            }
          }

        }
      }
    }

    BarBody {
      anchors.fill: parent
      anchors.margins: Theme.space2()
      screen: barWindow.screen
      barWindow: barWindow
    }
  }
}
