import QtQuick
import QtQuick.Controls
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

  readonly property var wifiDevice: Networking.devices
    ? Networking.devices.values.find(device => device.type === DeviceType.Wifi) || null
    : null
  readonly property var networks: root.wifiDevice && root.wifiDevice.networks
    ? root.wifiDevice.networks.values.slice().sort((a, b) => b.signalStrength - a.signalStrength)
    : []
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var bluetoothDevices: Bluetooth.devices
    ? Bluetooth.devices.values.filter(device =>
      device.paired || device.connected || (root.adapter && root.adapter.discovering))
    : []
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
    return connected ? connected.name : (root.wifiDevice && root.wifiDevice.connected ? "Connected" : "Not connected")
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
            iconName: "wifi"
            title: "Wi-Fi"
            subtitle: root.connectionName
            active: Networking.wifiEnabled && root.activeQuickSection === "wifi"
            available: root.wifiDevice !== null && root.wifiDevice.nmManaged
            onClicked: root.toggleQuickSection("wifi")
          }

          QuickSettingsTile {
            width: (parent.width - parent.spacing * 2) / 3
            height: parent.height
            iconName: "bluetooth"
            title: "Bluetooth"
            subtitle: root.adapter && root.adapter.enabled
              ? (root.bluetoothDevices.find(device => device.connected)
                ? root.bluetoothDevices.find(device => device.connected).name : "On")
              : "Off"
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
          visible: root.activeQuickSection === "wifi" && !!root.wifiDevice

          Column {
            id: wifiSection
            anchors.fill: parent
            anchors.margins: 9
            spacing: 4

            QuickSettingsTile {
              width: parent.width
              height: 48
              iconName: "wifi"
              title: "Wi-Fi"
              subtitle: Networking.wifiEnabled ? "On" : "Off"
              active: Networking.wifiEnabled
              onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }

            Item {
              visible: Networking.wifiEnabled
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
              visible: Networking.wifiEnabled && root.networks.length === 0
              width: parent.width
              text: "Looking for networks…"
              color: Theme.widgetInactiveIconColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }

            ListView {
              id: wifiNetworkList
              visible: Networking.wifiEnabled && root.networks.length > 0
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
              visible: Networking.wifiEnabled && root.connectionError !== ""
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

            // Pairing request / status card
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
                  Text {
                    width: parent.width - 118
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name || modelData.deviceName || modelData.address
                    color: Theme.widgetTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
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
              contentItem: Text {
                leftPadding: 10
                rightPadding: 30
                text: sinkSelector.currentText
                color: Theme.surfaceText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
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
                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: SettingsPanelService.brightnessPercent + "%"
                  color: Theme.widgetTextColor
                  font.family: Theme.monoFontFamily
                  font.pixelSize: Theme.fontSizeSmall
                }
              }

              Slider {
                width: parent.width
                height: 26
                from: 0
                to: 100
                value: SettingsPanelService.brightnessPercent
                onMoved: SettingsPanelService.setBrightness(value)
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
