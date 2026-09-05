import QtQuick
import Quickshell.Services.UPower
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Battery pill. Renders percentage (and a charging indicator) from UPower,
// guarded so it renders nothing when no battery is present.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null

  readonly property real level: UPower.displayDevice ? (UPower.displayDevice.percentage * 100) : -1
  readonly property bool hasBattery: level >= 0

  content: Component {
    Row {
      visible: root.hasBattery
      spacing: 4

      Text {
        visible: root._charging
        anchors.verticalCenter: parent.verticalCenter
        text: "⚡"
        color: Theme.widgetIconColor
        font.pixelSize: root.textSize()
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.level) + "%"
        color: root._low ? Theme.error : Theme.widgetTextColor
        font.family: Theme.monoFontFamily
        font.pixelSize: root.textSize()
      }
    }
  }

  readonly property bool _charging: UPower.displayDevice ? UPower.displayDevice.state === 1 : false
  readonly property bool _low: root.hasBattery && root.level <= 20
}
