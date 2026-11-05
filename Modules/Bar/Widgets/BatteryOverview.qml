import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

Item {
  id: root

  signal closeRequested

  property var batteryDevice: null
  property var batteryDevices: []
  property var accessoryDevices: []
  property bool active: false
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
  readonly property real signedPowerRate: {
    const activeDevices = root.batteryDevices.filter(device =>
      device.ready && isFinite(device.changeRate) && device.changeRate > 0.05)
    if (activeDevices.length === 0)
      return 0
    const rate = activeDevices.reduce((sum, device) => sum + device.changeRate, 0)
    return activeDevices.some(device => device.state === UPowerDeviceState.Charging) ? rate : -rate
  }
  readonly property color powerRateColor: {
    const draw = Math.abs(root.signedPowerRate)
    if (root.signedPowerRate >= 0)
      return Theme.primary
    if (draw >= 30)
      return Theme.error
    if (draw >= 15)
      return Theme.warning
    return Theme.widgetTextColor
  }
  readonly property real temperature: Number(BatteryPowerService.batteryTemperature) || 0
  readonly property string timeRemaining: root.deviceTime(root.batteryDevice)
  readonly property string estimatedCompletionTime: root.completionClockTime(root.timeRemaining)
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
  readonly property string statusSummary: {
    if (!root.timeRemaining)
      return root.statusText
    if (root.batteryDevice && root.batteryDevice.state === UPowerDeviceState.Charging)
      return root.statusText + " · Time until full: " + root.timeRemaining
        + (root.estimatedCompletionTime ? " (" + root.estimatedCompletionTime + ")" : "")
    if (root.batteryDevice && root.batteryDevice.state === UPowerDeviceState.Discharging)
      return root.statusText + " · " + root.timeRemaining + " remaining"
    return root.statusText
  }
  readonly property string performanceWarning: {
    if (!BatteryPowerService.vendorChecked
        || BatteryPowerService.isAsus
        || typeof PowerProfiles === "undefined")
      return ""
    if (PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected)
      return "Performance limited: lap detected"
    if (PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature)
      return "Performance limited: high temperature"
    return ""
  }
  property bool batteriesExpanded: false

  implicitWidth: 500
  implicitHeight: overviewColumn.implicitHeight + 36

  onActiveChanged: {
    if (root.active)
      BatteryPowerService.refresh()
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.active
    onTriggered: BatteryPowerService.refresh()
  }

  function deviceTime(device) {
    if (!device)
      return ""

    let seconds = 0
    if (device.state === UPowerDeviceState.Charging)
      seconds = device.timeToFull
    else if (device.state === UPowerDeviceState.Discharging)
      seconds = device.timeToEmpty

    if ((!isFinite(seconds) || seconds <= 0) && device.changeRate > 0) {
      if (device.state === UPowerDeviceState.Charging && device.energyCapacity > device.energy)
        seconds = 3600 * (device.energyCapacity - device.energy) / device.changeRate
      else if (device.state === UPowerDeviceState.Discharging && device.energy > 0)
        seconds = 3600 * device.energy / device.changeRate
    }

    if (!isFinite(seconds) || seconds <= 0 || seconds > 86400)
      return ""
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m"
  }

  function completionClockTime(duration) {
    if (!duration || !root.batteryDevice
        || root.batteryDevice.state !== UPowerDeviceState.Charging)
      return ""

    let remaining = 0
    const match = duration.match(/(?:(\d+)h\s*)?(\d+)m/)
    if (!match)
      return ""
    remaining = (Number(match[1] || 0) * 60) + Number(match[2])
    if (remaining <= 0 || remaining > 1440)
      return ""

    const eta = new Date(Date.now() + remaining * 60 * 1000)
    return Qt.formatTime(eta, "hh:mm")
  }

  function deviceState(device) {
    switch (device.state) {
    case UPowerDeviceState.Charging: return "Charging"
    case UPowerDeviceState.Discharging: return "Discharging"
    case UPowerDeviceState.Empty: return "Empty"
    case UPowerDeviceState.FullyCharged: return "Fully Charged"
    case UPowerDeviceState.PendingCharge: return "Pending Charge"
    case UPowerDeviceState.PendingDischarge: return "Pending Discharge"
    default: return "Unknown"
    }
  }

  function deviceName(device, index) {
    return device.model || ("Battery " + (index + 1))
  }

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
                text: root.statusSummary
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

        Row {
          width: parent.width
          height: 86
          spacing: Theme.spaceXS
          visible: root.temperature > 0 || root.signedPowerRate !== 0

          Rectangle {
            width: parent.width / (root.temperature > 0 && root.signedPowerRate !== 0 ? 2 : 1)
            height: parent.height
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
            visible: root.temperature > 0

            Row {
              anchors.centerIn: parent
              spacing: Theme.spaceM

              DmsIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "device_thermostat"
                size: 24
                color: Theme.primary
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spaceXXS

                Text {
                  text: root.temperature.toFixed(1) + " °C"
                  color: Theme.widgetTextColor
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeMedium
                }

                Text {
                  text: "Temperature"
                  color: Theme.widgetInactiveIconColor
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeSmall
                }
              }
            }
          }

          Rectangle {
            x: root.temperature > 0 ? parent.width / 2 : 0
            width: parent.width / (root.temperature > 0 && root.signedPowerRate !== 0 ? 2 : 1)
            height: parent.height
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
            visible: root.signedPowerRate !== 0

            Row {
              anchors.centerIn: parent
              spacing: Theme.spaceM

              DmsIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.signedPowerRate > 0 ? "bolt" : "electrical_services"
                size: 24
                color: root.powerRateColor
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spaceXXS

                Text {
                  text: (root.signedPowerRate > 0 ? "+" : "-")
                    + Math.abs(root.signedPowerRate).toFixed(1) + " W"
                  color: root.powerRateColor
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeMedium
                }

                Text {
                  text: root.signedPowerRate > 0 ? "Charging rate" : "Power draw"
                  color: Theme.widgetInactiveIconColor
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeSmall
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
          height: profileColumn.implicitHeight + Theme.spaceM * 2

          Column {
            id: profileColumn
            anchors.fill: parent
            anchors.margins: Theme.spaceM
            spacing: Theme.spaceS

            Row {
              width: parent.width

              Text {
                width: parent.width - profileBackend.implicitWidth - Theme.spaceS
                text: "Power profile"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
              }

              Text {
                id: profileBackend
                text: BatteryPowerService.backendName
                color: Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignRight
              }
            }

            Row {
              id: profileButtons
              width: parent.width
              spacing: Theme.spaceXS
              visible: BatteryPowerService.profiles.length > 0

              Repeater {
                model: BatteryPowerService.profiles

                delegate: Rectangle {
                  id: profileButton
                  required property var modelData
                  readonly property bool selected:
                    BatteryPowerService.currentProfile.toLowerCase() === modelData.id.toLowerCase()
                  width: (profileButtons.width - profileButtons.spacing
                    * (BatteryPowerService.profiles.length - 1))
                    / BatteryPowerService.profiles.length
                  height: 44
                  radius: Theme.pillRadius
                  color: selected ? Theme.primary
                    : (profileButtonMouse.containsMouse
                      ? Theme.withAlpha(Theme.primary, 0.14)
                      : Theme.surfaceContainer)
                  border.width: selected ? 0 : 1
                  border.color: Theme.withAlpha(Theme.outline, 0.35)
                  opacity: BatteryPowerService.busy || BatteryPowerService.profileLoading ? 0.6 : 1

                  Row {
                    anchors.centerIn: parent
                    spacing: Theme.spaceXS

                    DmsIcon {
                      anchors.verticalCenter: parent.verticalCenter
                      name: modelData.icon
                      size: 18
                      color: selected ? Theme.primaryText : Theme.widgetTextColor
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.label
                      color: selected ? Theme.primaryText : Theme.widgetTextColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall
                    }
                  }

                  MouseArea {
                    id: profileButtonMouse
                    anchors.fill: parent
                    enabled: !BatteryPowerService.busy && !BatteryPowerService.profileLoading
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: BatteryPowerService.applyProfile(modelData.id)
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: text.length > 0
              text: BatteryPowerService.errorMessage || BatteryPowerService.unavailableMessage
              color: BatteryPowerService.errorMessage ? Theme.error : Theme.widgetInactiveIconColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
              wrapMode: Text.WordWrap
            }
          }
        }

        Rectangle {
          width: parent.width
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.error, 0.14)
          visible: root.performanceWarning.length > 0
          height: performanceWarningText.implicitHeight + Theme.spaceM * 2

          Text {
            id: performanceWarningText
            anchors.fill: parent
            anchors.margins: Theme.spaceM
            text: root.performanceWarning
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
          }
        }

        Column {
          width: parent.width
          spacing: Theme.spaceXS
          visible: root.batteryDevices.filter(device => device.ready).length > 1

          Rectangle {
            width: parent.width
            height: 48
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Theme.spaceM
              anchors.rightMargin: Theme.spaceM
              spacing: Theme.spaceXS

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - batteryCount.implicitWidth - batteryDisclosure.implicitWidth - parent.spacing * 2
                text: "Individual batteries"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
              }

              Text {
                id: batteryCount
                anchors.verticalCenter: parent.verticalCenter
                text: String(root.batteryDevices.filter(device => device.ready).length)
                color: Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }

              DmsIcon {
                id: batteryDisclosure
                anchors.verticalCenter: parent.verticalCenter
                name: root.batteriesExpanded ? "expand_less" : "expand_more"
                size: 20
                color: Theme.widgetIconColor
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.batteriesExpanded = !root.batteriesExpanded
            }
          }

          Column {
            width: parent.width
            spacing: Theme.spaceXS
            visible: root.batteriesExpanded

            Repeater {
              model: root.batteryDevices.filter(device => device.ready)

              delegate: Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: batteryDetails.implicitHeight + Theme.spaceM * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)

                Column {
                  id: batteryDetails
                  anchors.fill: parent
                  anchors.margins: Theme.spaceM
                  spacing: Theme.spaceXS

                  Row {
                    width: parent.width
                    spacing: Theme.spaceS

                    Text {
                      width: parent.width - batteryPercent.implicitWidth - parent.spacing
                      text: root.deviceName(modelData, index)
                      color: Theme.widgetTextColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeMedium
                      font.weight: Font.Medium
                      elide: Text.ElideRight
                    }

                    Text {
                      id: batteryPercent
                      text: Math.round(modelData.percentage * 100) + "%"
                      visible: modelData.percentage > 0 || modelData.state === UPowerDeviceState.Empty
                      color: Theme.widgetTextColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeMedium
                      font.weight: Font.Medium
                    }
                  }

                  Text {
                    width: parent.width
                    text: root.deviceState(modelData)
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                  }

                  Text {
                    width: parent.width
                    visible: modelData.nativePath.length > 0
                    text: modelData.nativePath
                    color: Theme.widgetInactiveIconColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideMiddle
                  }

                  Text {
                    width: parent.width
                    visible: text.length > 0
                    text: {
                      const details = []
                      if (modelData.healthSupported && modelData.healthPercentage > 0)
                        details.push("Health " + Math.round(modelData.healthPercentage) + "%")
                      if (modelData.energyCapacity > 0)
                        details.push("Capacity " + modelData.energyCapacity.toFixed(1) + " Wh")
                      const time = root.deviceTime(modelData)
                      if (time)
                        details.push((modelData.state === UPowerDeviceState.Charging ? "To full " : "Remaining ") + time)
                      return details.join(" · ")
                    }
                    color: Theme.widgetInactiveIconColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                  }
                }
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
                name: modelData.state === UPowerDeviceState.Charging
                  ? "bolt"
                  : root.accessoryIcon(modelData)
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
    case UPowerDeviceType.Pen: return "stylus"
    case UPowerDeviceType.Phone: return "smartphone"
    case UPowerDeviceType.Tablet: return "tablet"
    case UPowerDeviceType.MediaPlayer: return "media_output"
    case UPowerDeviceType.Wearable: return "watch"
    default: return "battery_std"
    }
  }
}
