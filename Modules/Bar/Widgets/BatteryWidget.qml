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
  readonly property var accessoryDevices: {
    if (!UPower.devices)
      return []

    const accessoryTypes = [
      UPowerDeviceType.BluetoothGeneric,
      UPowerDeviceType.Headphones,
      UPowerDeviceType.Headset,
      UPowerDeviceType.Keyboard,
      UPowerDeviceType.Mouse,
      UPowerDeviceType.Speakers,
      UPowerDeviceType.Touchpad,
      UPowerDeviceType.GamingInput
    ]
    return UPower.devices.values.filter(device =>
      device && device.ready && !device.isLaptopBattery &&
      accessoryTypes.includes(device.type) && device.percentage >= 0)
  }
  property bool _notificationStateReady: false
  property bool _previousCharging: false
  property bool _lowNotified: false
  property bool _fullNotified: false
  property var _accessoryNotificationStates: ({})

  content: Component {
    Row {
      visible: root.hasBattery || root.accessoryDevices.length > 0
      spacing: 4

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

      Repeater {
        model: root.accessoryDevices

        delegate: Row {
          required property var modelData
          spacing: 4

          DmsIcon {
            name: root.accessoryIcon(modelData)
            size: root.iconSize(-4)
            color: modelData.state === UPowerDeviceState.Charging
              ? Theme.primary
              : (root.accessoryLevel(modelData) <= 20 ? Theme.error : Theme.widgetIconColor)
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.accessoryLevel(modelData) + "%"
            color: root.accessoryLevel(modelData) <= 20 ? Theme.error : Theme.widgetTextColor
            font.family: Theme.monoFontFamily
            font.pixelSize: root.textSize()
          }
        }
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
    running: root.hasBattery || root.accessoryDevices.length > 0
    triggeredOnStart: true
    onTriggered: root.checkBatteryNotifications()
  }

  function sendNotification(summary, body, urgency) {
    sendDeviceNotification(summary, body, urgency, "battery")
  }

  function sendDeviceNotification(summary, body, urgency, icon) {
    Quickshell.execDetached([
      "notify-send",
      "-a", "MyQuickshell",
      "-u", urgency,
      "-i", icon,
      summary,
      body
    ])
  }

  function checkBatteryNotifications() {
    if (!root.hasBattery) {
      root.checkAccessoryNotifications()
      return
    }

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
    root.checkAccessoryNotifications()
  }

  function checkAccessoryNotifications() {
    const activePaths = {}

    for (const device of root.accessoryDevices) {
      const key = device.nativePath || device.model || String(device.type)
      const level = root.accessoryLevel(device)
      const charging = device.state === UPowerDeviceState.Charging
      const previous = root._accessoryNotificationStates[key] || {
        charging: charging,
        lowNotified: false,
        fullNotified: false
      }

      activePaths[key] = true

      if (!previous.charging && charging)
        previous.fullNotified = false

      if (!charging && level <= 20) {
        if (!previous.lowNotified) {
          previous.lowNotified = true
          root.sendDeviceNotification(
            "Low Battery",
            root.accessoryName(device) + " is at " + level + "%.",
            "critical",
            root.accessoryIcon(device)
          )
        }
      } else if (level > 23 || charging) {
        previous.lowNotified = false
      }

      if (charging && level >= 100) {
        if (!previous.fullNotified) {
          previous.fullNotified = true
          root.sendDeviceNotification(
            "Battery Full",
            root.accessoryName(device) + " is fully charged.",
            "normal",
            root.accessoryIcon(device)
          )
        }
      } else if (previous.charging && !charging) {
        root.sendDeviceNotification(
          "Charging Stopped",
          root.accessoryName(device) + " is no longer charging at " + level + "%.",
          "normal",
          root.accessoryIcon(device)
        )
        previous.fullNotified = false
      } else if (!charging || level < 97) {
        previous.fullNotified = false
      }

      previous.charging = charging
      root._accessoryNotificationStates[key] = previous
    }

    for (const key in root._accessoryNotificationStates) {
      if (!activePaths[key])
        delete root._accessoryNotificationStates[key]
    }
  }

  function accessoryName(device) {
    return device.model || UPowerDeviceType.toString(device.type)
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

  function accessoryLevel(device) {
    return Math.round(device.percentage * 100)
  }

  function accessoryIcon(device) {
    if (device.state === UPowerDeviceState.Charging)
      return "battery_charging_full"

    switch (device.type) {
    case UPowerDeviceType.Keyboard:
      return "keyboard"
    case UPowerDeviceType.Mouse:
    case UPowerDeviceType.Touchpad:
      return "mouse"
    case UPowerDeviceType.Headset:
    case UPowerDeviceType.Headphones:
      return "headphones"
    case UPowerDeviceType.Speakers:
      return "speaker"
    case UPowerDeviceType.GamingInput:
      return "gamepad"
    case UPowerDeviceType.BluetoothGeneric:
      return "bluetooth"
    default:
      return "battery_std"
    }
  }
}
