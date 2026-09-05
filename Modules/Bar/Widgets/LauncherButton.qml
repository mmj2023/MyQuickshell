import QtQuick
import Quickshell.Io
import Quickshell.Widgets
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Launcher button. Renders a primary-tinted grid glyph in a pill. Left click is
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
      implicitHeight: 20
      IconImage {
        anchors.centerIn: parent
        source: "view-grid-symbolic"
        implicitSize: 18
      }
    }
  }

  property Process overviewProc: Process {
    id: overviewProc
    command: ["hyprctl", "dispatch", "overview:toggle"]
  }
}
