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

  content: Component {
    Text {
      text: root.focusTitle
      color: Theme.widgetTextColor
      font.family: Theme.fontFamily
      font.pixelSize: root.textSize()
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
      width: root.focusTitle === "" ? 0 : 160
      clip: true
    }
  }
}
