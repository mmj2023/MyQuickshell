import QtQuick
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Running apps. Renders one icon per open toplevel on the current screen using
// ToplevelManager.toplevels directly (a reactive QML model). Icons resolve from
// the app id via the icon theme with a generic fallback.
BasePill {
  id: root

  property var barWindow: null
  property QtObject parentScreen: null

  readonly property bool hasWindows: root.screenToplevels.length > 0
  readonly property var screenToplevels: Array.from(ToplevelManager.toplevels.values).filter(function(t) {
    if (!root.parentScreen) return true
    return !t.screens || t.screens.indexOf(root.parentScreen) !== -1
  })

  content: Component {
    Row {
      spacing: 2

      Repeater {
        model: root.screenToplevels

        delegate: Rectangle {
          required property var modelData
          readonly property var win: modelData

          width: win.activated ? 28 : 26
          height: 26
          anchors.verticalCenter: parent.verticalCenter
          radius: Theme.pillRadius
          color: win.activated ? Theme.surfaceText_12 : "transparent"

          IconImage {
            anchors.centerIn: parent
            source: Theme.getAppIcon(win.appId)
            implicitSize: 18
            asynchronous: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: win.activate()
          }
        }
      }
    }
  }
}
