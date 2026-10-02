import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Common
import qs.Modules.Bar.Widgets

Item {
  id: root

  signal closeRequested

  property var batteryDevice: null
  property var batteryDevices: []
  property var accessoryDevices: []
  property bool onBattery: UPower.onBattery
  readonly property real level: batteryDevice ? Math.max(0, Math.min(100, batteryDevice.percentage * 100)) : 0
  readonly property int health: {
    const devices = root.batteryDevices.filter(device =>
      device.ready && device.healthSupported && device.healthPercentage > 0)
    if (devices.length === 0)
      return -1
    return Math.round(devices.reduce((sum, device) => sum + device.healthPercentage, 0) / devices.length)
  }
  readonly property real capacity: root.batteryDevices
    .filter(device => device.ready && device.energyCapacity > 0)
    .reduce((sum, device) => sum + device.energyCapacity, 0)
  readonly property string statusText: {
    if (!root.batteryDevice)
      return "Battery unavailable"
    switch (root.batteryDevice.state) {
    case UPowerDeviceState.Charging:
      return "Charging"
    case UPowerDeviceState.Discharging:
      return "Discharging"
    case UPowerDeviceState.Empty:
      return "Empty"
    case UPowerDeviceState.FullyCharged:
      return "Fully Charged"
    case UPowerDeviceState.PendingCharge:
      return "Pending Charge"
    case UPowerDeviceState.PendingDischarge:
      return "Pending Discharge"
    default:
      return root.onBattery ? "On battery" : "Plugged in"
    }
  }

  implicitWidth: 500
  implicitHeight: overviewColumn.implicitHeight + 36

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.withAlpha(
      Theme.widgetBaseBackgroundColor,
      typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.65
    )
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.35)

    Flickable {
      anchors.fill: parent
      anchors.margins: 18
      contentHeight: overviewColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: overviewColumn
        width: parent.width
        spacing: 14

        Rectangle {
          width: parent.width
          height: 94
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)

          Row {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            Item {
              width: 66
              height: 66
              anchors.verticalCenter: parent.verticalCenter

              Canvas {
                id: mainRing
                anchors.fill: parent
                property real progress: root.level / 100
                property color accent: root.level <= 20 && root.onBattery ? Theme.error : Theme.primary
                onProgressChanged: requestPaint()
                onAccentChanged: requestPaint()

                onPaint: {
                  const context = getContext("2d")
                  context.reset()
                  const center = width / 2
                  const radius = Math.min(width, height) / 2 - 3
                  context.lineWidth = 5
                  context.lineCap = "round"
                  context.strokeStyle = Theme.withAlpha(Theme.outline, 0.35)
                  context.beginPath()
                  context.arc(center, center, radius, 0, Math.PI * 2)
                  context.stroke()
                  context.strokeStyle = accent
                  context.beginPath()
                  context.arc(center, center, radius, -Math.PI / 2,
                    -Math.PI / 2 + Math.PI * 2 * Math.max(0, Math.min(1, progress)))
                  context.stroke()
                }
              }

              DmsIcon {
                anchors.centerIn: parent
                name: root.onBattery ? "battery_std" : "battery_charging_full"
                size: 26
                color: root.level <= 20 && root.onBattery ? Theme.error : Theme.primary
              }
            }

            Column {
              width: parent.width - 66 - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2

              Text {
                width: parent.width
                text: Math.round(root.level) + "%"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium + 6
                font.weight: Font.Medium
              }

              Text {
                width: parent.width
                text: root.statusText
                color: Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
              }
            }
          }
        }

        Row {
          width: parent.width
          height: 118
          spacing: 2
          visible: root.health >= 0 || root.capacity > 0

          Rectangle {
            width: parent.width / (root.health >= 0 && root.capacity > 0 ? 2 : 1)
            height: parent.height
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
            visible: root.health >= 0

            Column {
              anchors.centerIn: parent
              spacing: 4

              Item {
                width: 42
                height: 42
                anchors.horizontalCenter: parent.horizontalCenter

                Canvas {
                  anchors.fill: parent
                  property real progress: Math.max(0, root.health) / 100
                  property color accent: root.health < 80 ? Theme.error : Theme.primary
                  onProgressChanged: requestPaint()
                  onAccentChanged: requestPaint()
                  onPaint: {
                    const context = getContext("2d")
                    context.reset()
                    context.lineWidth = 3
                    context.lineCap = "round"
                    context.strokeStyle = Theme.withAlpha(Theme.outline, 0.35)
                    context.beginPath()
                    context.arc(width / 2, height / 2, 17, -Math.PI * 0.8, Math.PI * 0.8)
                    context.stroke()
                    context.strokeStyle = accent
                    context.beginPath()
                    context.arc(width / 2, height / 2, 17, -Math.PI * 0.8,
                      -Math.PI * 0.8 + Math.PI * 1.6 * progress)
                    context.stroke()
                  }
                }

                DmsIcon {
                  anchors.centerIn: parent
                  name: "ecg_heart"
                  size: 19
                  color: root.health < 80 ? Theme.error : Theme.primary
                }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.health + "%"
                color: root.health < 80 ? Theme.error : Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Health"
                color: Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }
            }
          }

          Rectangle {
            x: root.health >= 0 ? parent.width / 2 : 0
            width: parent.width / (root.health >= 0 && root.capacity > 0 ? 2 : 1)
            height: parent.height
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
            visible: root.capacity > 0

            Column {
              anchors.centerIn: parent
              spacing: 5

              DmsIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "battery_full"
                size: 26
                color: Theme.primary
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.capacity.toFixed(1) + " Wh"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Capacity"
                color: Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }
            }
          }
        }

        Repeater {
          model: root.accessoryDevices

          delegate: Rectangle {
            required property var modelData
            width: overviewColumn.width
            height: 160
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)

            Item {
              id: accessoryGauge
              width: 112
              height: 112
              anchors.horizontalCenter: parent.horizontalCenter
              y: 10

              Canvas {
                anchors.fill: parent
                property real progress: Math.max(0, Math.min(1, modelData.percentage))
                property color accent: modelData.state === UPowerDeviceState.Charging
                  ? Theme.primary
                  : (modelData.percentage <= 20 ? Theme.error : Theme.primary)
                onProgressChanged: requestPaint()
                onAccentChanged: requestPaint()
                onPaint: {
                  const context = getContext("2d")
                  context.reset()
                  context.lineWidth = 7
                  context.lineCap = "round"
                  context.strokeStyle = Theme.withAlpha(Theme.outline, 0.35)
                  context.beginPath()
                  context.arc(width / 2, height / 2, 48, Math.PI * 0.75, Math.PI * 2.25)
                  context.stroke()
                  context.strokeStyle = accent
                  context.beginPath()
                  context.arc(width / 2, height / 2, 48, Math.PI * 0.75,
                    Math.PI * 0.75 + Math.PI * 1.5 * progress)
                  context.stroke()
                }
              }

              DmsIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                name: root.accessoryIcon(modelData)
                size: 25
                color: Theme.primary
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.bottom
                text: root.accessoryLevel(modelData).toString()
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
              }
            }

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 12
              text: root.accessoryName(modelData)
              color: Theme.widgetInactiveIconColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }

  function accessoryLevel(device) {
    return Math.round(device.percentage * 100)
  }

  function accessoryName(device) {
    return device.model || UPowerDeviceType.toString(device.type)
  }

  function accessoryIcon(device) {
    switch (device.type) {
    case UPowerDeviceType.BluetoothGeneric: return "bluetooth"
    case UPowerDeviceType.Headphones: return "headphones"
    case UPowerDeviceType.Headset: return "headset_mic"
    case UPowerDeviceType.Keyboard: return "keyboard"
    case UPowerDeviceType.Mouse: return "mouse"
    case UPowerDeviceType.Touchpad: return "touchpad_mouse"
    case UPowerDeviceType.Speakers: return "speaker"
    case UPowerDeviceType.GamingInput: return "sports_esports"
    default: return "battery_std"
    }
  }
}
