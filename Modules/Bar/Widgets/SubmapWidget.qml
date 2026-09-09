import QtQuick
import Quickshell.Hyprland
import qs.Common
import qs.Modules.Bar.Widgets

BasePill {
  id: root

  property QtObject barWindow: null
  property QtObject parentScreen: null
  property string submapName: ""
  visible: root.submapName !== ""
  width: visible ? visualWidth : 0

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || event.name !== "submap")
        return
      root.submapName = String(event.data || "").trim()
    }
  }

  content: Component {
    Item {
      implicitWidth: submapText.implicitWidth
      implicitHeight: submapText.implicitHeight + 2

      Text {
        id: submapText
        anchors.centerIn: parent
        text: root.submapName
        color: Theme.widgetTextColor
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize()
      }
    }
  }
}
