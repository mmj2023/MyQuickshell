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

      DmsIcon {
        name: root.batteryIcon()
        size: root.iconSize(-4)
        color: root._charging ? Theme.primary : (root._low ? Theme.error : Theme.widgetIconColor)
        anchors.verticalCenter: parent.verticalCenter
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

  function batteryIcon() {
    if (root._charging) {
      if (root.level >= 90) return "battery_charging_full"
      if (root.level >= 80) return "battery_charging_90"
      if (root.level >= 60) return "battery_charging_80"
      if (root.level >= 50) return "battery_charging_60"
      if (root.level >= 30) return "battery_charging_50"
      if (root.level >= 20) return "battery_charging_30"
      return "battery_charging_20"
    }

    if (root.level >= 95) return "battery_full"
    if (root.level >= 85) return "battery_6_bar"
    if (root.level >= 70) return "battery_5_bar"
    if (root.level >= 55) return "battery_4_bar"
    if (root.level >= 40) return "battery_3_bar"
    if (root.level >= 25) return "battery_2_bar"
    return "battery_1_bar"
  }
}
