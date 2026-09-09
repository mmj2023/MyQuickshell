import QtQuick
import Quickshell
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
  property bool _notificationStateReady: false
  property bool _previousCharging: false
  property bool _lowNotified: false
  property bool _fullNotified: false

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

  // Keep the charging glyph while AC power is connected, including when a
  // charge limit leaves the battery below 100% or UPower reports full.
  readonly property bool _charging: UPower.displayDevice ? !UPower.onBattery : false
  readonly property bool _actuallyCharging: UPower.displayDevice
    ? UPower.displayDevice.state === UPowerDeviceState.Charging
    : false
  readonly property bool _low: root.hasBattery && root.level <= 20

  Component.onCompleted: {
    root._previousCharging = root._actuallyCharging
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.hasBattery
    triggeredOnStart: true
    onTriggered: root.checkBatteryNotifications()
  }

  function sendNotification(summary, body, urgency) {
    Quickshell.execDetached([
      "notify-send",
      "-a", "MyQuickshell",
      "-u", urgency,
      "-i", "battery",
      summary,
      body
    ])
  }

  function checkBatteryNotifications() {
    if (!root.hasBattery)
      return

    const charging = root._actuallyCharging
    // UPower can briefly expose a zero percentage while the device is being
    // initialized after the shell starts. Establish the first complete
    // sample as the baseline instead of notifying from that transient value.
    if (!root._notificationStateReady) {
      root._previousCharging = charging
      root._notificationStateReady = true
      return
    }

    if (!charging && root.level <= 20) {
      if (!root._lowNotified) {
        root._lowNotified = true
        root.sendNotification("Low Battery", "Battery is at " + Math.round(root.level) + "%.", "critical")
      }
    } else if (root.level > 23 || charging) {
      root._lowNotified = false
    }

    if (root._charging && root.level >= 100) {
      if (!root._fullNotified) {
        root._fullNotified = true
        root.sendNotification("Battery Full", "Battery is fully charged.", "normal")
      }
    } else if (root._previousCharging && !charging && root._charging) {
      root.sendNotification("Charging Stopped", "The battery is no longer charging at " + Math.round(root.level) + "%.", "normal")
      root._fullNotified = false
    } else if (!charging || root.level < 97) {
      root._fullNotified = false
    }

    root._previousCharging = charging
  }

  function batteryIcon() {
    if (root._charging) {
      if (root.level >= 100) return "battery_charging_full"
      if (root.level >= 90) return "battery_charging_90"
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
