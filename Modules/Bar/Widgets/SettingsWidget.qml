import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null
  property bool panelOpen: false
  property string activeQuickSection: ""
  property int popupX: 0
  property int popupY: 0
  property var pendingNetwork: null
  property string networkPassword: ""
  property string connectionError: ""
  property bool colorPickerOpen: false
  property int colorPickerX: 0
  property int colorPickerY: 0
  property string selectedBrightnessDevice: ""
  property bool brightnessDevicesExpanded: false

  readonly property var wifiDevice: Networking.devices
    ? Networking.devices.values.find(device => device.type === DeviceType.Wifi) || null
    : null
  readonly property var wiredDevice: Networking.devices
    ? Networking.devices.values.find(device => device.type === DeviceType.Wired && device.connected)
      || Networking.devices.values.find(device => device.type === DeviceType.Wired)
      || null
    : null
  readonly property bool hasNetworkDevice: !!root.wifiDevice || !!root.wiredDevice
  readonly property bool hasActiveNetworkDevice: !!(root.wifiDevice && root.wifiDevice.connected)
    || !!(root.wiredDevice && root.wiredDevice.connected)
  readonly property var networks: root.wifiDevice && root.wifiDevice.networks
    ? root.wifiDevice.networks.values.slice().sort((a, b) => b.signalStrength - a.signalStrength)
    : []
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var bluetoothDevices: Bluetooth.devices
    ? Bluetooth.devices.values.filter(device =>
      device.paired || device.connected || (root.adapter && root.adapter.discovering))
    : []
  readonly property var connectedBluetoothDevice: root.bluetoothDevices.find(device => device.connected) || null
  readonly property string brightnessPinKey: root.parentScreen ? root.parentScreen.name : "default"
  readonly property var brightnessPins: {
    const saved = SettingsData.brightnessDevicePins || {}
    const pins = saved[root.brightnessPinKey]
    return Array.isArray(pins)
      ? pins.filter(device => SettingsPanelService.brightnessDevices.some(item => item.device === device))
      : []
  }
  readonly property string brightnessSelectedDevice: {
    const devices = SettingsPanelService.brightnessDevices
    if (root.selectedBrightnessDevice && devices.some(item => item.device === root.selectedBrightnessDevice))
      return root.selectedBrightnessDevice
    if (root.brightnessPins.length > 0)
      return root.brightnessPins[0]
    const screen = devices.find(item => item.className === "backlight")
    return screen ? screen.device : (devices.length > 0 ? devices[0].device : "")
  }
  readonly property string brightnessControlDevice: root.brightnessPins.length > 0
    ? root.brightnessPins[0] : root.brightnessSelectedDevice
  readonly property var brightnessControlDevices: root.brightnessPins.length > 0
    ? root.brightnessPins : (root.brightnessControlDevice ? [root.brightnessControlDevice] : [])
  readonly property real brightnessControlPercent: {
    const devices = SettingsPanelService.brightnessDevices
    const values = root.brightnessControlDevices.map(name => {
      const device = devices.find(item => item.device === name)
      return device ? root.brightnessSliderValue(device) : null
    }).filter(value => value !== null)
    return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0
  }
  readonly property var connectedBluetoothDetails: {
    const device = root.connectedBluetoothDevice
    if (!device)
      return []
    return [
      ["Device", device.name || device.deviceName || "Bluetooth device", true],
      ["Address", device.address || "", true],
      ["Status", BluetoothDeviceState.toString(device.state), false],
      ["Paired", device.paired ? "Yes" : "No", false],
      ["Trusted", device.trusted ? "Yes" : "No", false],
      ["Blocked", device.blocked ? "Yes" : "No", false],
      ["Battery", device.batteryAvailable ? Math.round(device.battery * 100) + "%" : "", false]
    ].filter(row => row[1] !== "")
  }
  readonly property var audioSinks: Pipewire.nodes
    ? Pipewire.nodes.values.filter(node => node.audio && node.isSink && !node.isStream)
    : []
  readonly property var audioSources: Pipewire.nodes
    ? Pipewire.nodes.values.filter(node => node.audio && !node.isSink && !node.isStream)
    : []
  readonly property var activeSink: Pipewire.defaultAudioSink
  readonly property var activeSource: Pipewire.defaultAudioSource
  readonly property bool audioReady: !!root.activeSink && root.activeSink.ready && !!root.activeSink.audio
  readonly property string connectionName: {
    const connected = root.networks.find(network => network.connected)
    if (connected)
      return connected.name
    if (root.wifiDevice && root.wifiDevice.connected)
      return "Connected"
    if (root.wiredDevice && root.wiredDevice.connected)
      return "Ethernet"
    return "Not connected"
  }
  readonly property var networkDetailRows: {
    const info = SettingsPanelService.networkInfo || {}
    if (!info.iface)
      return []
    const rows = [
      ["Interface", info.iface, false],
      ["IPv4 address", info.ip ? info.ip + (info.prefix ? "/" + info.prefix : "") : "", true],
      ["Gateway", info.gateway || "", true],
      ["DNS", info.dns || "", true],
      ["MAC address", info.mac || "", true]
    ]
    if (info.rx_bytes !== undefined && info.rx_bytes !== "" && info.tx_bytes !== undefined && info.tx_bytes !== "") {
      rows.push(["Receiving", formatNetworkRate(SettingsPanelService.networkDownloadRate), true])
      rows.push(["Sending", formatNetworkRate(SettingsPanelService.networkUploadRate), true])
      rows.push(["Downloaded", formatNetworkBytes(info.rx_bytes), true])
      rows.push(["Uploaded", formatNetworkBytes(info.tx_bytes), true])
    }
    if (info.type === "wifi") {
      rows.push(["Signal", info.signal_dbm ? info.signal_dbm + " dBm" : "", false])
      rows.push(["Frequency", info.frequency ? info.frequency + " MHz" : "", false])
      rows.push(["Transmit rate", info.bitrate || "", false])
    } else {
      rows.push(["Link speed", formatNetworkLinkSpeed(info.speed), false])
      rows.push(["Duplex", info.duplex || "", false])
    }
    return rows.filter(row => row[1] !== "")
  }

  function formatNetworkBytes(value) {
    let bytes = Number(value)
    if (!isFinite(bytes) || bytes < 0)
      return "--"
    const units = ["B", "KB", "MB", "GB", "TB"]
    let unit = 0
    while (bytes >= 1024 && unit < units.length - 1) {
      bytes /= 1024
      unit++
    }
    return bytes.toFixed(unit === 0 ? 0 : 1) + " " + units[unit]
  }

  function formatNetworkRate(value) {
    return formatNetworkBytes(value) + "/s"
  }

  function formatNetworkLinkSpeed(value) {
    const mbps = Number(value)
    if (!isFinite(mbps) || mbps <= 0)
      return ""
    return mbps >= 1000 ? (mbps / 1000).toFixed(mbps % 1000 === 0 ? 0 : 1) + " Gbit/s"
      : mbps + " Mbit/s"
  }

  function isBrightnessPinned(device) {
    return root.brightnessPins.indexOf(device) !== -1
  }

  function brightnessControlTitle() {
    const device = SettingsPanelService.brightnessDevices.find(item => item.device === root.brightnessControlDevice)
    if (!device)
      return "Selected device"
    return device.title
  }

  function toggleBrightnessPin(device) {
    const pinsByScreen = JSON.parse(JSON.stringify(SettingsData.brightnessDevicePins || {}))
    const pins = root.brightnessPins.slice()
    const index = pins.indexOf(device)
    if (index >= 0)
      pins.splice(index, 1)
    else {
      pins.push(device)
      root.selectedBrightnessDevice = device
    }
    if (pins.length)
      pinsByScreen[root.brightnessPinKey] = pins
    else
      delete pinsByScreen[root.brightnessPinKey]
    SettingsData.set("brightnessDevicePins", pinsByScreen)
  }

  function brightnessExponential(device) {
    return (SettingsData.brightnessExponentialDevices || []).indexOf(device) !== -1
  }

  function toggleBrightnessCurve(device) {
    const devices = (SettingsData.brightnessExponentialDevices || []).slice()
    const index = devices.indexOf(device)
    if (index >= 0)
      devices.splice(index, 1)
    else
      devices.push(device)
    SettingsData.set("brightnessExponentialDevices", devices)
  }

  function brightnessSliderValue(device) {
    const percent = Math.max(0, Math.min(100, Number(device.percent) || 0))
    return root.brightnessExponential(device.device) && device.className !== "leds"
      ? Math.round(Math.pow(percent / 100, 1 / 2.2) * 100)
      : percent
  }

  function setDeviceBrightness(device, sliderPercent) {
    const curve = root.brightnessExponential(device.device) && device.className !== "leds"
      ? Math.pow(Math.max(0, Math.min(100, sliderPercent)) / 100, 2.2) * 100
      : sliderPercent
    SettingsPanelService.setBrightness(device.device, curve)
  }

  function setBrightnessTargets(sliderPercent) {
    const value = Math.max(0, Math.min(100, sliderPercent))
    for (let i = 0; i < root.brightnessControlDevices.length; i++) {
      const name = root.brightnessControlDevices[i]
      const device = SettingsPanelService.brightnessDevices.find(item => item.device === name)
      if (device)
        root.setDeviceBrightness(device, value)
    }
  }

  PwObjectTracker {
    objects: [root.activeSink, root.activeSource]
  }

  IdleInhibitor {
    window: root.barWindow
    enabled: SettingsPanelService.keepAwake
  }

  Timer {
    interval: 8000
    repeat: true
    running: root.panelOpen
    triggeredOnStart: true
    onTriggered: SettingsPanelService.refresh()
  }

  // Resume adapter scanning once a pairing session is no longer active.
  Connections {
    target: BluetoothService
    function onBusyChanged() {
      if (!BluetoothService.busy && root.panelOpen
          && root.activeQuickSection === "bluetooth" && root.adapter)
        root.adapter.discovering = true
    }
  }

  content: Component {
    Row {
      spacing: 5

      DmsIcon {
        name: root.wifiDevice && root.wifiDevice.connected ? "wifi" : "wifi_off"
        size: root.iconSize(-4)
        color: root.wifiDevice && root.wifiDevice.connected ? Theme.primary : Theme.widgetInactiveIconColor
        filled: !!root.wifiDevice && root.wifiDevice.connected
        anchors.verticalCenter: parent.verticalCenter
      }

      DmsIcon {
        name: root.adapter && !root.adapter.enabled
          ? "bluetooth_disabled"
          : (root.bluetoothDevices.some(device => device.connected) ? "bluetooth_connected" : "bluetooth")
        size: root.iconSize(-4)
        color: root.bluetoothDevices.some(device => device.connected)
          ? Theme.primary
          : (root.adapter && root.adapter.enabled ? Theme.widgetIconColor : Theme.widgetInactiveIconColor)
        filled: root.bluetoothDevices.some(device => device.connected)
        anchors.verticalCenter: parent.verticalCenter
      }

      DmsIcon {
        name: root.volumeIcon()
        size: root.iconSize(-4)
        color: root.audioReady && !root.activeSink.audio.muted
          && root.activeSink.audio.volume > 0 ? Theme.primary : Theme.widgetInactiveIconColor
        filled: root.audioReady && !root.activeSink.audio.muted
          && root.activeSink.audio.volume > 0
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  onClicked: {
    if (!root.barWindow)
      return
    if (root.panelOpen) {
      root.panelOpen = false
      return
    }
    const point = root.mapToItem(root.barWindow.contentItem, 0, root.height)
    const width = Math.min(380, root.parentScreen ? root.parentScreen.width - 24 : 380)
    root.popupX = Math.round(Math.max(8, Math.min(
      (root.parentScreen ? root.parentScreen.width : root.barWindow.width) - width - 8,
      point.x + root.width / 2 - width / 2
    )))
    root.popupY = Math.round(point.y + Theme.spaceXS)
    root.panelOpen = true
  }

  function openColorPicker() {
    if (!root.barWindow)
      return
    root.panelOpen = false
    const screenWidth = root.parentScreen ? root.parentScreen.width : root.barWindow.width
    const screenHeight = root.parentScreen ? root.parentScreen.height : root.barWindow.height
    root.colorPickerX = Math.round(Math.max(8, (screenWidth - colorPickerPopup.implicitWidth) / 2))
    root.colorPickerY = Math.round(Math.max(8, (screenHeight - colorPickerPopup.implicitHeight) / 2))
    root.colorPickerOpen = true
  }

  PopupWindow {
    id: settingsPopup
    anchor.window: root.barWindow
    anchor.rect.x: root.popupX
    anchor.rect.y: root.popupY
    visible: root.panelOpen
    grabFocus: true
    color: "transparent"
    surfaceFormat.opaque: false
    implicitWidth: Math.min(380, root.parentScreen ? root.parentScreen.width - 24 : 380)
    implicitHeight: Math.min(
      settingsColumn.implicitHeight + 28,
      Math.max(240, root.parentScreen ? root.parentScreen.height - root.popupY - 16 : 700)
    )

    onVisibleChanged: {
      if (visible) {
        if (root.wifiDevice)
          root.wifiDevice.scannerEnabled = root.activeQuickSection === "wifi"
        if (root.adapter)
          root.adapter.discovering = root.activeQuickSection === "bluetooth"
      } else {
        root.panelOpen = false
        root.activeQuickSection = ""
        root.pendingNetwork = null
        root.networkPassword = ""
        root.connectionError = ""
        if (root.wifiDevice)
          root.wifiDevice.scannerEnabled = false
        if (root.adapter)
          root.adapter.discovering = false
      }

    }

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.withAlpha(
        Theme.widgetBaseBackgroundColor,
        typeof SettingsData !== "undefined" ? SettingsData.barWidgetTransparency : 0.65
      )

      Flickable {
        anchors.fill: parent
        anchors.margins: 14
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

      Column {
        id: settingsColumn
        width: parent.width
        spacing: 10

        Item {
          width: parent.width
          height: 28

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Quick settings"
            color: Theme.widgetTextColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.DemiBold
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Done"
            color: Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: root.panelOpen = false
            }
          }
        }

        Row {
          width: parent.width
          height: 68
          spacing: 8

          QuickSettingsTile {
            width: (parent.width - parent.spacing * 2) / 3
            height: parent.height
            iconName: root.wifiDevice ? "wifi" : "settings_ethernet"
            title: root.wifiDevice ? "Wi-Fi" : "Ethernet"
            subtitle: root.connectionName
            active: root.activeQuickSection === "wifi"
              && (!root.wifiDevice || Networking.wifiEnabled)
            available: root.hasNetworkDevice
            onClicked: root.toggleQuickSection("wifi")
          }

          QuickSettingsTile {
            width: (parent.width - parent.spacing * 2) / 3
            height: parent.height
            iconName: "bluetooth"
            title: "Bluetooth"
            subtitle: root.adapter && root.adapter.enabled
              ? (root.connectedBluetoothDevice
                ? (root.connectedBluetoothDevice.name || root.connectedBluetoothDevice.deviceName || root.connectedBluetoothDevice.address)
                : "On")
              : "Off"
            sensitiveSubtitle: !!root.connectedBluetoothDevice
            active: !!root.adapter && root.adapter.enabled && root.activeQuickSection === "bluetooth"
            available: root.adapter !== null
            onClicked: root.toggleQuickSection("bluetooth")
          }

          QuickSettingsTile {
            width: (parent.width - parent.spacing * 2) / 3
            height: parent.height
            iconName: root.volumeIcon()
            title: "Sound"
            subtitle: root.audioReady
              ? Math.round(root.activeSink.audio.volume * 100) + "%" : "Unavailable"
            active: root.activeQuickSection === "sound"
            available: root.audioReady
            onClicked: root.toggleQuickSection("sound")
          }
        }

        Rectangle {
          width: parent.width
          height: wifiSection.implicitHeight + 18
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.45)
          visible: root.activeQuickSection === "wifi" && root.hasNetworkDevice

          Column {
            id: wifiSection
            anchors.fill: parent
            anchors.margins: 9
            spacing: 4

            QuickSettingsTile {
              visible: !!root.wifiDevice
              width: parent.width
              height: 48
              iconName: "wifi"
              title: "Wi-Fi"
              subtitle: Networking.wifiEnabled ? "On" : "Off"
              active: Networking.wifiEnabled
              onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }

            Column {
              width: parent.width
              spacing: 3
              visible: root.hasActiveNetworkDevice

              Text {
                width: parent.width
                text: "Connection details"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }

              Text {
                visible: root.networkDetailRows.length === 0
                width: parent.width
                text: "Interface details unavailable"
                color: Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall - 1
              }

              GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: 12
                rowSpacing: 2

                Repeater {
                  model: root.networkDetailRows
                  delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                      text: modelData[0]
                      color: Theme.widgetInactiveIconColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall - 1
                      elide: Text.ElideRight
                    }

                    Item {
                      id: valueContainer
                      Layout.fillWidth: true
                      implicitHeight: detailValue.implicitHeight

                      Text {
                        id: detailValue
                        anchors.fill: parent
                        text: modelData[1]
                        color: Theme.widgetTextColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall - 1
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        layer.enabled: modelData[2] === true && !revealArea.containsMouse
                        layer.effect: MultiEffect {
                          blurEnabled: true
                          blur: 1.0
                        }
                      }

                      MouseArea {
                        id: revealArea
                        anchors.fill: parent
                        visible: modelData[2] === true
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                      }
                    }
                  }
                }
              }
            }

            Item {
              visible: !!root.wifiDevice && Networking.wifiEnabled
              width: parent.width
              height: 24
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Available networks"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.wifiDevice && root.wifiDevice.scannerEnabled ? "Scanning…" : "Refresh"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall - 1
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -6
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.refreshWifiNetworks()
                }
              }
            }

            Text {
              visible: !!root.wifiDevice && Networking.wifiEnabled && root.networks.length === 0
              width: parent.width
              text: "Looking for networks…"
              color: Theme.widgetInactiveIconColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }

            ListView {
              id: wifiNetworkList
              visible: !!root.wifiDevice && Networking.wifiEnabled && root.networks.length > 0
              width: wifiSection.width
              height: Math.min(contentHeight, 34 * 5 + 4 * 4)
              model: root.networks
              spacing: 4
              clip: true
              interactive: contentHeight > height
              boundsBehavior: Flickable.StopAtBounds

              ScrollIndicator.vertical: ScrollIndicator {}

              Connections {
                target: root
                function onPendingNetworkChanged() {
                  Qt.callLater(function() {
                    const index = wifiNetworkList.model.indexOf(root.pendingNetwork)
                    if (index >= 0)
                      wifiNetworkList.positionViewAtIndex(index, ListView.Contain)
                  })
                }
              }

              delegate: Item {
                required property var modelData
                width: wifiNetworkList.width
                height: networkRow.height + (passwordRow.visible ? passwordRow.height + 6 : 0)

                Row {
                  id: networkRow
                  y: 0
                  width: parent.width
                  height: 34
                  spacing: 7

                  DmsIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.connected ? "wifi" : (modelData.known ? "wifi" : "wifi_lock")
                    size: 17
                    color: modelData.connected ? Theme.primary : Theme.widgetIconColor
                  }

                  Text {
                    width: Math.max(0, parent.width - 92)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name || "Hidden network"
                    color: Theme.widgetTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.connected ? "Connected" : (modelData.stateChanging ? "Connecting…" : "Connect")
                    color: modelData.connected ? Theme.primary : Theme.widgetInactiveIconColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall - 1
                  }
                }

                MouseArea {
                  anchors.left: networkRow.left
                  anchors.top: networkRow.top
                  width: networkRow.width
                  height: networkRow.height
                  cursorShape: modelData.stateChanging ? Qt.ArrowCursor : Qt.PointingHandCursor
                  enabled: !modelData.stateChanging
                  onClicked: root.activateNetwork(modelData)
                }

                Row {
                  id: passwordRow
                  y: networkRow.height + 2
                  visible: Networking.wifiEnabled && root.pendingNetwork === modelData
                  width: parent.width
                  height: 32
                  spacing: 6

                  TextField {
                    id: wifiPassword
                    width: parent.width - connectButton.width - 6
                    height: 32
                    placeholderText: "Wi-Fi password"
                    echoMode: TextInput.Password
                    text: root.networkPassword
                    onTextChanged: root.networkPassword = text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    background: Rectangle {
                      radius: Theme.cornerRadius
                      color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.75)
                      border.width: 1
                      border.color: wifiPassword.activeFocus ? Theme.primary : Theme.outlineVariant
                    }
                    color: Theme.surfaceText
                  }

                  Rectangle {
                    id: connectButton
                    width: 80
                    height: 32
                    radius: Theme.hoverRadius
                    color: joinMouse.containsMouse
                      ? Theme.withAlpha(Theme.primary, 0.18)
                      : Theme.withAlpha(Theme.surfaceContainerHighest, 0.75)
                    border.width: 1
                    border.color: joinMouse.containsMouse ? Theme.primary : Theme.outlineVariant

                    Text {
                      anchors.centerIn: parent
                      text: "Join"
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall
                      color: Theme.surfaceText
                    }

                    MouseArea {
                      id: joinMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.connectPendingNetwork()
                    }
                  }
                }

                Connections {
                  target: modelData
                  function onConnectionFailed(reason) {
                    root.connectionError = "Connection failed: " + ConnectionFailReason.toString(reason)
                  }
                }
              }
            }

            Text {
              visible: !!root.wifiDevice && Networking.wifiEnabled && root.connectionError !== ""
              width: parent.width
              text: root.connectionError
              color: Theme.error
              wrapMode: Text.Wrap
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall - 1
            }
          }
        }

        Rectangle {
          width: parent.width
          height: bluetoothSection.implicitHeight + 18
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.45)
          visible: root.activeQuickSection === "bluetooth" && !!root.adapter

          Column {
            id: bluetoothSection
            anchors.fill: parent
            anchors.margins: 9
            spacing: 4

            QuickSettingsTile {
              width: parent.width
              height: 48
              iconName: "bluetooth"
              title: "Bluetooth"
              subtitle: root.adapter && root.adapter.enabled ? "On" : "Off"
              active: !!root.adapter && root.adapter.enabled
              onClicked: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
            }

            Item {
              visible: root.adapter && root.adapter.enabled
              width: parent.width
              height: 24

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Visible to nearby devices"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall - 1
              }

              Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: visibilityLabel.implicitWidth + 18
                height: 22
                radius: Theme.pillRadius
                color: visibilityMouse.containsMouse
                  ? Theme.withAlpha(Theme.primary, 0.18)
                  : Theme.withAlpha(root.adapter && root.adapter.discoverable ? Theme.primary : Theme.surfaceContainerHighest, 0.2)
                border.width: 1
                border.color: Theme.withAlpha(root.adapter && root.adapter.discoverable ? Theme.primary : Theme.outlineVariant, 0.45)

                Text {
                  id: visibilityLabel
                  anchors.centerIn: parent
                  text: root.adapter && root.adapter.discoverable ? "On" : "Off"
                  color: root.adapter && root.adapter.discoverable ? Theme.primary : Theme.widgetInactiveIconColor
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeSmall - 2
                }

                MouseArea {
                  id: visibilityMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.adapter)
                      return
                    const visible = !root.adapter.discoverable
                    root.adapter.discoverable = visible
                    root.adapter.pairable = visible
                  }
                }
              }
            }

            Item {
              visible: root.adapter && root.adapter.enabled
              width: parent.width
              height: 24
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Bluetooth devices"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.adapter && root.adapter.discovering ? "Scanning…" : "Scan"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall - 1
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -6
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.refreshBluetoothDevices()
                }
              }
            }

            Text {
              visible: root.adapter && root.adapter.enabled && root.bluetoothDevices.length === 0
              width: parent.width
              text: "No paired devices"
              color: Theme.widgetInactiveIconColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }

            Column {
              visible: !!root.connectedBluetoothDevice
              width: parent.width
              spacing: 4

              Text {
                width: parent.width
                text: "Connected device"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }

              GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: 12
                rowSpacing: 2

                Repeater {
                  model: root.connectedBluetoothDetails
                  delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                      text: modelData[0]
                      color: Theme.widgetInactiveIconColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall - 1
                    }

                    Item {
                      id: bluetoothDetailValue
                      Layout.fillWidth: true
                      implicitHeight: bluetoothDetailText.implicitHeight

                      Text {
                        id: bluetoothDetailText
                        anchors.fill: parent
                        text: modelData[1]
                        color: Theme.widgetTextColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall - 1
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        layer.enabled: modelData[2] === true && !bluetoothDetailHover.containsMouse
                        layer.effect: MultiEffect {
                          blurEnabled: true
                          blur: 1.0
                        }
                      }

                      MouseArea {
                        id: bluetoothDetailHover
                        anchors.fill: parent
                        visible: modelData[2] === true
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                      }
                    }
                  }
                }
              }

              Row {
                width: parent.width
                spacing: 5

                Repeater {
                  model: [
                    { label: root.connectedBluetoothDevice && root.connectedBluetoothDevice.trusted ? "Trusted" : "Trust", action: "trust" },
                    { label: root.connectedBluetoothDevice && root.connectedBluetoothDevice.blocked ? "Unblock" : "Block", action: "block" },
                    { label: root.connectedBluetoothDevice && root.connectedBluetoothDevice.wakeAllowed ? "Wake allowed" : "Allow wake", action: "wake" }
                  ]

                  delegate: Rectangle {
                    id: deviceCard
                    required property var modelData
                    width: actionLabel.implicitWidth + 16
                    height: 24
                    radius: Theme.pillRadius
                    color: actionMouse.containsMouse
                      ? Theme.withAlpha(Theme.primary, 0.18)
                      : Theme.withAlpha(Theme.surfaceContainerHighest, 0.55)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outlineVariant, 0.4)

                    Text {
                      id: actionLabel
                      anchors.centerIn: parent
                      text: modelData.label
                      color: Theme.widgetTextColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall - 2
                    }

                    MouseArea {
                      id: actionMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        const device = root.connectedBluetoothDevice
                        if (device && modelData.action === "trust") {
                          device.trusted = !device.trusted
                        } else if (device && modelData.action === "block") {
                          device.blocked = !device.blocked
                        } else if (device && modelData.action === "wake") {
                          device.wakeAllowed = !device.wakeAllowed
                        }
                      }
                    }
                  }
                }
              }
            }

            // Pairing request / status card. The request name and passkey are
            // transient pairing data, not saved-device details.
            Rectangle {
              id: pairingRequestCard
              visible: root.adapter && root.adapter.enabled && BluetoothService.requestState !== "idle"
              width: bluetoothSection.width
              height: pairingRequestContent.implicitHeight + 12
              radius: Theme.hoverRadius
              color: Theme.withAlpha(Theme.primary, BluetoothService.requestState === "failed" ? 0.08 : 0.1)
              border.width: 1
              border.color: Theme.withAlpha(Theme.primary, 0.3)

              Column {
                id: pairingRequestContent
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 6
                spacing: 4

                Row {
                  width: parent.width
                  spacing: 7
                  DmsIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: BluetoothService.requestState === "failed" ? "error" : "bluetooth_searching"
                    size: 15
                    color: BluetoothService.requestState === "failed" ? Theme.error : Theme.primary
                  }
                  Text {
                    width: parent.width - 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: BluetoothService.requestState === "failed"
                      ? (BluetoothService.requestMessage || "Pairing failed")
                      : ((BluetoothService.requestName || BluetoothService.requestAddress) + " — "
                        + (BluetoothService.requestMessage || "Pairing…"))
                    color: BluetoothService.requestState === "failed" ? Theme.error : Theme.widgetTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                  }
                }

                Row {
                  width: parent.width
                  spacing: 4

                  Rectangle {
                    visible: BluetoothService.requestState === "pin"
                    width: pinInput.width + 12
                    height: 26
                    radius: Theme.hoverRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.8)
                    border.width: 1
                    border.color: pinInput.activeFocus ? Theme.withAlpha(Theme.primary, 0.6) : Theme.withAlpha(Theme.outline, 0.25)

                    TextInput {
                      id: pinInput
                      anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                      verticalAlignment: TextInput.AlignVCenter
                      color: Theme.surfaceText
                      font.family: Theme.monoFontFamily
                      font.pixelSize: Theme.fontSizeSmall
                      focus: true
                      onAccepted: BluetoothService.confirmRequest(BluetoothService.submitPinText(pinInput.text))
                    }
                  }

                  Rectangle {
                    visible: BluetoothService.requestState === "confirm" || BluetoothService.requestState === "pin"
                    width: acceptLabel.implicitWidth + Theme.spaceM
                    height: 24
                    radius: Theme.pillRadius
                    color: pairingAcceptMa.containsMouse ? Theme.withAlpha(Theme.primary, 0.75) : Theme.primary
                    Text {
                      id: acceptLabel
                      anchors.centerIn: parent
                      text: BluetoothService.requestState === "confirm" ? "Confirm" : "Pair"
                      color: Theme.primaryText
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall - 1
                      font.weight: Font.Medium
                    }
                    MouseArea {
                      id: pairingAcceptMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: BluetoothService.confirmRequest(BluetoothService.requestState !== "pin" || BluetoothService.submitPinText(pinInput.text))
                    }
                  }

                  Rectangle {
                    width: cancelLabel.implicitWidth + Theme.spaceM
                    height: 24
                    radius: Theme.pillRadius
                    color: pairingCancelMa.containsMouse ? Theme.withAlpha(Theme.surfaceContainerHigh, 0.9) : Theme.withAlpha(Theme.surfaceContainerHigh, 0.6)
                    Text {
                      id: cancelLabel
                      anchors.centerIn: parent
                      text: BluetoothService.requestState === "failed" ? "Dismiss" : "Cancel"
                      color: Theme.widgetTextColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall - 1
                    }
                    MouseArea {
                      id: pairingCancelMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: BluetoothService.requestState === "failed"
                        ? BluetoothService.dismiss()
                        : BluetoothService.cancelPairing()
                    }
                  }
                }
              }
            }

            ListView {
              id: btDeviceList
              visible: root.adapter && root.adapter.enabled && root.bluetoothDevices.length > 0
              width: bluetoothSection.width
              height: Math.min(contentHeight, 34 * 5 + 4 * 4)
              model: root.bluetoothDevices
              spacing: 4
              clip: true
              interactive: contentHeight > height
              boundsBehavior: Flickable.StopAtBounds

              ScrollIndicator.vertical: ScrollIndicator {}

              delegate: Item {
                required property var modelData
                width: btDeviceList.width
                height: 34
                Row {
                  anchors.fill: parent
                  spacing: 7
                  DmsIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.connected ? "bluetooth_connected" : "bluetooth"
                    size: 17
                    color: modelData.connected ? Theme.primary : Theme.widgetIconColor
                  }
                  Item {
                    id: bluetoothNameContainer
                    width: parent.width - 118
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: bluetoothName.implicitHeight

                    Text {
                      id: bluetoothName
                      anchors.fill: parent
                      text: modelData.name || modelData.deviceName || modelData.address
                      color: Theme.widgetTextColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall
                      elide: Text.ElideRight
                      layer.enabled: (modelData.paired || modelData.connected) && !bluetoothNameHover.containsMouse
                      layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                      }
                    }

                    MouseArea {
                      id: bluetoothNameHover
                      anchors.fill: parent
                      visible: modelData.paired || modelData.connected
                      acceptedButtons: Qt.NoButton
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                    }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.connected ? "Disconnect"
                      : (modelData.state === BluetoothDeviceState.Connecting ? "Connecting…"
                        : (modelData.paired ? "Connect" : "Pair"))
                    color: modelData.connected ? Theme.primary : Theme.widgetInactiveIconColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall - 1
                  }
                  Item {
                    width: 17
                    height: 17
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.paired && !modelData.pairing
                    DmsIcon {
                      anchors.fill: parent
                      anchors.margins: 2
                      name: "close"
                      size: 13
                      color: forgetMa.containsMouse ? Theme.error : Theme.widgetInactiveIconColor
                    }
                    MouseArea {
                      id: forgetMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: BluetoothService.forgetDevice(modelData)
                    }
                  }
                }
                MouseArea {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: parent.width - 34
                  enabled: modelData.state !== BluetoothDeviceState.Connecting && !modelData.pairing
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: {
                    if (modelData.connected)
                      modelData.disconnect()
                    else if (modelData.paired)
                      modelData.connect()
                    else
                      BluetoothService.pairDevice(modelData)
                  }
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: audioSection.implicitHeight + 18
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.45)
          visible: root.activeQuickSection === "sound" && !!root.activeSink

          Column {
            id: audioSection
            anchors.fill: parent
            anchors.margins: 9
            spacing: 7

            Item {
              width: parent.width
              height: 23
              DmsIcon {
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                name: root.volumeIcon()
                size: 18
                color: Theme.widgetIconColor
              }
              Text {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                text: "Sound"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.audioReady
                  ? Math.round(root.activeSink.audio.volume * 100) + "%" : "--"
                color: Theme.widgetTextColor
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall
              }
            }

            Row {
              width: parent.width
              spacing: 8
              DmsIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.volumeIcon()
                size: 17
                color: Theme.widgetIconColor
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.audioReady)
                    root.activeSink.audio.muted = !root.activeSink.audio.muted
                }
              }
              Slider {
                id: volumeSlider
                width: parent.width - 25
                height: 26
                from: 0
                to: 1.5
                value: root.audioReady ? root.activeSink.audio.volume : 0
                onMoved: if (root.audioReady)
                  root.activeSink.audio.volume = value
              }
            }

            ComboBox {
              id: sinkSelector
              width: parent.width
              height: 32
              visible: root.audioSinks.length > 1
              model: root.audioSinks.map(node => node.description || node.nickname || node.name)
              currentIndex: root.audioSinks.indexOf(Pipewire.defaultAudioSink)
              onActivated: index => Pipewire.preferredDefaultAudioSink = root.audioSinks[index]
              contentItem: TextInput {
                leftPadding: 10
                rightPadding: 30
                text: sinkSelector.currentText
                color: Theme.surfaceText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                verticalAlignment: Text.AlignVCenter
                enabled: false
                autoScroll: false
                readOnly: true
                selectByMouse: false
                cursorVisible: false
                clip: true
              }
              indicator: DmsIcon {
                x: sinkSelector.width - width - 8
                anchors.verticalCenter: parent.verticalCenter
                name: "expand_more"
                size: 18
                color: Theme.widgetIconColor
              }
              background: Rectangle {
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.8)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outlineVariant, 0.6)
              }
              popup: Popup {
                y: sinkSelector.height
                width: sinkSelector.width
                implicitHeight: contentItem.implicitHeight
                padding: 4
                background: Rectangle {
                  radius: Theme.cornerRadius
                  color: Theme.surfaceContainer
                  border.width: 1
                  border.color: Theme.withAlpha(Theme.outlineVariant, 0.7)
                }
                contentItem: ListView {
                  clip: true
                  implicitHeight: contentHeight
                  model: sinkSelector.popup.visible ? sinkSelector.delegateModel : null
                  currentIndex: sinkSelector.highlightedIndex
                  highlightFollowsCurrentItem: false
                  boundsBehavior: Flickable.StopAtBounds
                }
              }
              delegate: ItemDelegate {
                required property int index
                required property var modelData
                width: sinkSelector.width
                text: String(modelData)
                highlighted: sinkSelector.highlightedIndex === index
                contentItem: Text {
                  text: sinkSelector.textAt(index)
                  color: Theme.surfaceText
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeSmall
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                }
                background: Rectangle {
                  radius: Theme.hoverRadius
                  color: parent.highlighted
                    ? Theme.withAlpha(Theme.primary, 0.2)
                    : "transparent"
                }
              }
            }

            Row {
              visible: !!root.activeSource && root.activeSource.ready && !!root.activeSource.audio
              width: parent.width
              spacing: 8
              DmsIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.activeSource && root.activeSource.ready && root.activeSource.audio
                  && root.activeSource.audio.muted
                  ? "mic_off" : "mic"
                size: 17
                color: Theme.widgetIconColor
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.activeSource && root.activeSource.ready && root.activeSource.audio)
                    root.activeSource.audio.muted = !root.activeSource.audio.muted
                }
              }
              Slider {
                width: parent.width - 25
                height: 26
                from: 0
                to: 1.5
                value: root.activeSource && root.activeSource.ready && root.activeSource.audio
                  ? root.activeSource.audio.volume : 0
                onMoved: if (root.activeSource && root.activeSource.ready && root.activeSource.audio)
                  root.activeSource.audio.volume = value
              }
            }
          }
          }

          Rectangle {
            width: parent.width
            height: brightnessSection.implicitHeight + 18
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.45)
            visible: SettingsPanelService.brightnessAvailable

            Column {
              id: brightnessSection
              anchors.fill: parent
              anchors.margins: 9
              spacing: 4

              Item {
                id: brightnessHeader
                width: parent.width
                height: 22
                DmsIcon {
                  x: 0
                  anchors.verticalCenter: parent.verticalCenter
                  name: "brightness_medium"
                  size: 17
                  color: Theme.widgetIconColor
                }
                Text {
                  x: 24
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Brightness"
                  color: Theme.widgetTextColor
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeSmall
                  font.weight: Font.DemiBold
                }
                DmsIcon {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  name: root.brightnessDevicesExpanded ? "expand_less" : "expand_more"
                  size: 17
                  color: brightnessHeaderMouse.containsMouse ? Theme.primary : Theme.widgetInactiveIconColor
                }
                MouseArea {
                  id: brightnessHeaderMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.brightnessDevicesExpanded = !root.brightnessDevicesExpanded
                }
              }

              Text {
                width: parent.width
                text: root.brightnessPins.length > 1
                  ? "Pinned devices · " + root.brightnessPins.length
                  : root.brightnessControlTitle()
                color: Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall - 1
                elide: Text.ElideRight
              }
              Slider {
                width: parent.width
                height: 26
                from: 0
                to: 100
                value: root.brightnessControlPercent
                onMoved: root.setBrightnessTargets(value)
              }

              Column {
                id: brightnessDeviceList
                visible: root.brightnessDevicesExpanded
                width: parent.width
                spacing: 4

                Repeater {
                  model: SettingsPanelService.brightnessDevices

                  delegate: Rectangle {
                    id: deviceCard
                    required property var modelData
                    readonly property bool selected: root.brightnessSelectedDevice === modelData.device
                    property bool exponential: root.brightnessExponential(modelData.device)
                    width: brightnessDeviceList.width
                    implicitHeight: deviceCardContent.implicitHeight + 12
                    radius: Theme.cornerRadius
                    color: selected
                      ? Theme.withAlpha(Theme.primary, 0.1)
                      : Theme.withAlpha(Theme.surfaceContainerHighest, 0.38)
                    border.width: selected ? 2 : 1
                    border.color: selected ? Theme.primary : Theme.withAlpha(Theme.outlineVariant, 0.35)

                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.selectedBrightnessDevice = modelData.device
                    }

                    Column {
                      id: deviceCardContent
                      anchors.fill: parent
                      anchors.margins: 6
                      spacing: 3

                      Row {
                        width: parent.width
                        height: 28
                        spacing: 6

                        DmsIcon {
                          anchors.verticalCenter: parent.verticalCenter
                          name: modelData.className === "leds" ? "keyboard" : "brightness_medium"
                          size: 19
                          color: deviceCard.selected ? Theme.primary : Theme.widgetIconColor
                        }

                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          width: parent.width - 80
                          spacing: 1

                          Text {
                            width: parent.width
                            text: modelData.className === "backlight"
                              ? "Backlight: " + modelData.title
                              : modelData.title
                            color: Theme.widgetTextColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                          }

                          Text {
                            width: parent.width
                            text: modelData.device + " · " + modelData.classLabel
                            color: Theme.widgetInactiveIconColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall - 2
                            elide: Text.ElideRight
                          }
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.percent + "%"
                          color: Theme.widgetTextColor
                          font.family: Theme.monoFontFamily
                          font.pixelSize: Theme.fontSizeSmall - 1
                        }

                        Item {
                          width: 26
                          height: 26

                          DmsIcon {
                            anchors.centerIn: parent
                            name: "push_pin"
                            size: 16
                            color: root.isBrightnessPinned(modelData.device) ? Theme.primary : Theme.widgetInactiveIconColor
                          }

                          MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleBrightnessPin(modelData.device)
                          }
                        }
                      }

                      Slider {
                        width: parent.width
                        height: 26
                        from: 0
                        to: 100
                        value: root.brightnessSliderValue(modelData)
                        onMoved: root.setDeviceBrightness(modelData, value)
                      }

                      Item {
                        visible: modelData.className !== "leds"
                        width: parent.width
                        height: 22

                        Rectangle {
                          anchors.fill: parent
                          radius: Theme.hoverRadius
                          color: curveMouse.containsMouse
                            ? Theme.withAlpha(Theme.primary, 0.16)
                            : Theme.withAlpha(Theme.surfaceContainerHighest, 0.55)

                          Text {
                            anchors.centerIn: parent
                            text: deviceCard.exponential ? "Exponential" : "Linear"
                            color: Theme.widgetTextColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall - 2
                          }

                          MouseArea {
                            id: curveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleBrightnessCurve(modelData.device)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: dnsSection.implicitHeight + 18
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.45)
            visible: root.activeQuickSection === "wifi"
              && SettingsPanelService.networkManagerAvailable
              && SettingsPanelService.activeConnectionUuid !== ""

            Column {
              id: dnsSection
              anchors.fill: parent
              anchors.margins: 9
              spacing: 6

              Text {
                width: parent.width
                text: "DNS provider"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }

              Row {
                width: parent.width
                height: 54
                spacing: 8

                QuickSettingsTile {
                  width: (parent.width - parent.spacing) / 2
                  height: parent.height
                  iconName: "settings_ethernet"
                  title: "DHCP"
                  subtitle: "Use automatic DNS"
                  active: SettingsPanelService.dnsProvider === "DHCP"
                  available: !SettingsPanelService.networkBusy
                  onClicked: SettingsPanelService.setDnsProvider("DHCP")
                }

                QuickSettingsTile {
                  width: (parent.width - parent.spacing) / 2
                  height: parent.height
                  iconName: "dns"
                  title: "Cloudflare"
                  subtitle: "1.1.1.1"
                  active: SettingsPanelService.dnsProvider === "Cloudflare"
                  available: !SettingsPanelService.networkBusy
                  onClicked: SettingsPanelService.setDnsProvider("Cloudflare")
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: vpnSection.implicitHeight + 18
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.45)
            visible: root.activeQuickSection === "wifi" && SettingsPanelService.networkManagerAvailable

            Column {
              id: vpnSection
              anchors.fill: parent
              anchors.margins: 9
              spacing: 4

              Text {
                width: parent.width
                height: 22
                text: "VPN"
                color: Theme.widgetTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }

              Text {
                visible: SettingsPanelService.vpnProfiles.length === 0
                width: parent.width
                text: "No VPN profiles configured"
                color: Theme.widgetInactiveIconColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }

              Repeater {
                model: SettingsPanelService.vpnProfiles
                delegate: Item {
                  required property var modelData
                  readonly property bool connected: SettingsPanelService.activeVpnUuids.indexOf(modelData.uuid) !== -1
                  width: vpnSection.width
                  height: 34

                  Row {
                    anchors.fill: parent
                    spacing: 7

                    DmsIcon {
                      anchors.verticalCenter: parent.verticalCenter
                      name: "vpn_key"
                      size: 17
                      color: parent.parent.connected ? Theme.primary : Theme.widgetIconColor
                    }
                    Text {
                      width: parent.width - 100
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.name
                      color: Theme.widgetTextColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall
                      elide: Text.ElideRight
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: parent.parent.connected ? "Connected" : "Connect"
                      color: parent.parent.connected ? Theme.primary : Theme.widgetInactiveIconColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall - 1
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: !SettingsPanelService.networkBusy
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: SettingsPanelService.toggleVpn(modelData.uuid)
                  }
                }
              }
            }
          }

          Row {
            width: parent.width
            height: 64
            spacing: 8

            QuickSettingsTile {
              id: colorPickerTile
              width: (parent.width - parent.spacing) / 2
              height: parent.height
              iconName: "palette"
              title: "Color picker"
              subtitle: SettingsPanelService.colorPickerRunning
                ? "Picking screen color…" : (SettingsPanelService.pickedColor || "Choose a color")
              active: root.colorPickerOpen || SettingsPanelService.colorPickerRunning
              onClicked: root.openColorPicker()
              onRightClicked: SettingsPanelService.pickColor()
            }

            QuickSettingsTile {
              width: (parent.width - parent.spacing) / 2
              height: parent.height
              iconName: "coffee"
              title: "Keep awake"
              subtitle: SettingsPanelService.keepAwake ? "Preventing sleep" : "Normal power management"
              active: SettingsPanelService.keepAwake
              onClicked: SettingsPanelService.keepAwake = !SettingsPanelService.keepAwake
            }
          }

          QuickSettingsTile {
            width: parent.width
            height: 58
            iconName: "dark_mode"
            title: "Night mode"
            subtitle: SettingsPanelService.nightModeBusy
              ? "Applying…" : (SettingsPanelService.nightModeEnabled ? "Warm colors enabled" : "Off")
            active: SettingsPanelService.nightModeEnabled
            available: SettingsPanelService.nightModeAvailable && !SettingsPanelService.nightModeBusy
            visible: SettingsPanelService.nightModeAvailable
            onClicked: SettingsPanelService.setNightMode(!SettingsPanelService.nightModeEnabled)
          }

          Text {
            visible: SettingsPanelService.errorMessage !== ""
            width: parent.width
            text: SettingsPanelService.errorMessage
            color: Theme.error
            wrapMode: Text.Wrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall - 1
          }
        }
      }
    }
  }

  PopupWindow {
    id: colorPickerPopup
    anchor.window: root.barWindow
    anchor.rect.x: root.colorPickerX
    anchor.rect.y: root.colorPickerY
    visible: root.colorPickerOpen
    grabFocus: true
    color: "transparent"
    implicitWidth: Math.min(360, root.parentScreen ? root.parentScreen.width - 24 : 360)
    implicitHeight: Math.min(
      colorPickerPanel.implicitHeight,
      Math.max(320, root.parentScreen ? root.parentScreen.height - 24 : 700)
    )

    onVisibleChanged: {
      if (!visible)
        root.colorPickerOpen = false
    }

    ColorPickerPanel {
      id: colorPickerPanel
      width: colorPickerPopup.width
      height: colorPickerPopup.height
      onCloseRequested: root.colorPickerOpen = false
    }
  }

  function volumeIcon() {
    if (!root.audioReady || root.activeSink.audio.muted)
      return "volume_off"
    const volume = root.activeSink.audio.volume
    return volume < 0.01 ? "volume_mute" : (volume < 0.5 ? "volume_down" : "volume_up")
  }

  function toggleQuickSection(section) {
    root.activeQuickSection = root.activeQuickSection === section ? "" : section
    if (root.wifiDevice)
      root.wifiDevice.scannerEnabled = root.panelOpen && root.activeQuickSection === "wifi"
    if (root.adapter)
      root.adapter.discovering = root.panelOpen && root.activeQuickSection === "bluetooth"
  }

  function activateNetwork(network) {
    root.connectionError = ""
    root.pendingNetwork = null
    root.networkPassword = ""
    if (network.connected) {
      network.disconnect()
      return
    }
    if (network.known || network.security === WifiSecurityType.Open) {
      network.connect()
      return
    }
    root.pendingNetwork = network
  }

  function refreshWifiNetworks() {
    if (!root.wifiDevice)
      return
    root.wifiDevice.scannerEnabled = false
    Qt.callLater(function() {
      if (root.panelOpen && root.activeQuickSection === "wifi" && root.wifiDevice)
        root.wifiDevice.scannerEnabled = true
    })
  }

  function refreshBluetoothDevices() {
    if (!root.adapter)
      return
    root.adapter.discovering = false
    Qt.callLater(function() {
      if (root.panelOpen && root.activeQuickSection === "bluetooth" && root.adapter)
        root.adapter.discovering = true
    })
  }

  function connectPendingNetwork() {
    if (!root.pendingNetwork)
      return
    root.pendingNetwork.connectWithPsk(root.networkPassword)
    root.pendingNetwork = null
    root.networkPassword = ""
  }
}
