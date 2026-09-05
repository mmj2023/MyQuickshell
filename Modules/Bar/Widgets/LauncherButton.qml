import QtQuick
import QtQuick.Effects
import Quickshell.Io
import Quickshell.Widgets
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Launcher button. Renders a theme-colored Arch Linux mark in a pill. Left click is
// a hook reserved for the launcher modal (Phase 4); right click toggles the
// compositor overview.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null

  onRightClicked: {
    overviewProc.command = ["hyprctl", "dispatch", "overview:toggle"]
    overviewProc.running = true
  }

  content: Component {
    Item {
      implicitWidth: 28
    implicitHeight: 22

    IconImage {
      id: archLogo
      anchors.centerIn: parent
      width: 22
      height: 22
      source: "file:///usr/share/pixmaps/archlinux-logo.svg"
      asynchronous: true
      layer.enabled: true
      layer.effect: MultiEffect {
        saturation: 0
        colorization: 1
        colorizationColor: Theme.primary
        brightness: 0.5
        contrast: 1
      }
    }
    }
  }

  property Process overviewProc: Process {
    id: overviewProc
    command: ["hyprctl", "dispatch", "overview:toggle"]
  }
}
