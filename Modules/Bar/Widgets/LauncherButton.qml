import QtQuick
import Quickshell.Io
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

    Canvas {
      anchors.centerIn: parent
      width: 22
      height: 22

      onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = Theme.primary
        ctx.beginPath()
        ctx.moveTo(11, 1)
        ctx.lineTo(2, 21)
        ctx.lineTo(6.5, 21)
        ctx.lineTo(8.2, 16.5)
        ctx.lineTo(13.8, 16.5)
        ctx.lineTo(15.5, 21)
        ctx.lineTo(20, 21)
        ctx.closePath()
        ctx.fill()

        ctx.fillStyle = Theme.surfaceContainer
        ctx.beginPath()
        ctx.moveTo(11, 8)
        ctx.lineTo(9.3, 14)
        ctx.lineTo(12.7, 14)
        ctx.closePath()
        ctx.fill()
      }

      Connections {
        target: Theme
        function onPrimaryChanged() { parent.requestPaint() }
        function onSurfaceContainerChanged() { parent.requestPaint() }
      }
    }
    }
  }

  property Process overviewProc: Process {
    id: overviewProc
    command: ["hyprctl", "dispatch", "overview:toggle"]
  }
}
