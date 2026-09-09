import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Focused window title. Shows the active toplevel's title in a pill. Click
// invokes a window menu duck (no menu surface yet); empty while no toplevel is
// focused.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null

  readonly property string focusTitle: ToplevelManager.activeToplevel
    ? ToplevelManager.activeToplevel.title
    : ""
  readonly property string cleanedTitle: root.focusTitle.trim()
  visible: root.cleanedTitle !== ""
  width: root.cleanedTitle === "" ? 0 : root.visualWidth

  content: Component {
    Item {
      implicitWidth: root.cleanedTitle === "" ? 0 : Math.min(220, titleText.implicitWidth)
      implicitHeight: titleText.implicitHeight + 2
      Text {
        id: titleText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        text: root.cleanedTitle
        color: Theme.widgetTextColor
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize()
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
