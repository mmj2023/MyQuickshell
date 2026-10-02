pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

  property bool brightnessAvailable: false
  property int brightnessPercent: 0
  property string brightnessDevice: ""
  property int pendingBrightnessPercent: 0
  property bool hasPendingBrightness: false
  property bool keepAwake: false
  property bool networkManagerAvailable: false
  property string activeConnectionUuid: ""
  property string dnsProvider: "DHCP"
  property var vpnProfiles: []
  property var activeVpnUuids: []
  property bool networkBusy: false
  property string errorMessage: ""
  property string pickedColor: ""
  property var recentColors: []
  property bool colorPickerRunning: colorPickerProc.running
  property bool nightModeAvailable: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
  property bool nightModeEnabled: false
  property bool nightModeBusy: false
  property bool nightDaemonStarted: false
  property bool requestedNightMode: false

  function refresh() {
    if (!brightnessProc.running)
      brightnessProc.running = true
    if (!profilesProc.running)
      profilesProc.running = true
    if (!activeProc.running)
      activeProc.running = true
    if (root.nightModeAvailable && !nightStatusProc.running)
      nightStatusProc.running = true
  }

  function updateBrightness(raw) {
    const lines = String(raw || "").trim().split("\n")
    let selected = null
    for (let i = 0; i < lines.length; i++) {
      const fields = lines[i].split(",")
      if (fields.length < 4 || fields[1] === "leds")
        continue
      const percent = Number(String(fields[3]).replace("%", ""))
      if (!isFinite(percent))
        continue
      const candidate = { device: fields[0], className: fields[1], percent: Math.round(percent) }
      if (!selected || (candidate.className === "backlight" && selected.className !== "backlight"))
        selected = candidate
    }
    root.brightnessAvailable = selected !== null
    if (selected) {
      root.brightnessDevice = selected.device
      root.brightnessPercent = selected.percent
    } else {
      root.brightnessDevice = ""
    }
  }

  function setBrightness(percent) {
    if (!root.brightnessAvailable)
      return
    root.pendingBrightnessPercent = Math.max(0, Math.min(100, Math.round(percent)))
    root.hasPendingBrightness = true
    brightnessWriteTimer.restart()
  }

  function parseNmcliRow(line) {
    const fields = []
    let field = ""
    let escaped = false
    for (let i = 0; i < line.length; i++) {
      const ch = line[i]
      if (escaped) {
        field += ch
        escaped = false
      } else if (ch === "\\") {
        escaped = true
      } else if (ch === ":") {
        fields.push(field)
        field = ""
      } else {
        field += ch
      }
    }
    fields.push(field)
    return fields
  }

  function updateProfiles(raw) {
    const rows = String(raw || "").trim().split("\n")
    const profiles = []
    for (let i = 0; i < rows.length; i++) {
      if (!rows[i])
        continue
      const fields = root.parseNmcliRow(rows[i])
      if (fields.length >= 3 && fields[2] === "vpn")
        profiles.push({ name: fields[0], uuid: fields[1] })
    }
    root.vpnProfiles = profiles
    root.networkManagerAvailable = true
  }

  function updateActiveConnections(raw) {
    const rows = String(raw || "").trim().split("\n")
    let connectionUuid = ""
    const vpnUuids = []
    for (let i = 0; i < rows.length; i++) {
      if (!rows[i])
        continue
      const fields = root.parseNmcliRow(rows[i])
      if (fields.length < 3)
        continue
      if (fields[2] === "vpn")
        vpnUuids.push(fields[1])
      else if (!connectionUuid && fields[2] !== "loopback" && fields[2] !== "bridge")
        connectionUuid = fields[1]
    }
    root.activeVpnUuids = vpnUuids
    root.activeConnectionUuid = connectionUuid
    if (connectionUuid) {
      connectionConfigProc.command = [
        "nmcli", "-g", "ipv4.method,ipv4.dns,ipv4.ignore-auto-dns",
        "connection", "show", "uuid", connectionUuid
      ]
      if (!connectionConfigProc.running)
        connectionConfigProc.running = true
    } else {
      root.dnsProvider = "DHCP"
    }
  }

  function updateDnsConfig(raw) {
    const fields = String(raw || "").trim().split("\n")
    const method = fields[0] || ""
    const dns = fields[1] || ""
    const ignoreAutoDns = fields[2] || ""
    if (method === "auto" && ignoreAutoDns !== "yes") {
      root.dnsProvider = "DHCP"
    } else if (dns.indexOf("1.1.1.1") !== -1 || dns.indexOf("1.0.0.1") !== -1) {
      root.dnsProvider = "Cloudflare"
    } else {
      root.dnsProvider = "Custom"
    }
  }

  function setDnsProvider(provider) {
    if (root.networkBusy || !root.activeConnectionUuid)
      return
    if (provider !== "DHCP" && provider !== "Cloudflare")
      return

    root.errorMessage = ""
    root.networkBusy = true
    const uuid = root.activeConnectionUuid
    const command = [
      "nmcli", "connection", "modify", "uuid", uuid
    ]
    if (provider === "Cloudflare") {
      command.push(
        "ipv4.dns", "1.1.1.1 1.0.0.1",
        "ipv4.ignore-auto-dns", "yes",
        "ipv6.dns", "2606:4700:4700::1111 2606:4700:4700::1001",
        "ipv6.ignore-auto-dns", "yes"
      )
    } else {
      command.push(
        "ipv4.dns", "",
        "ipv4.ignore-auto-dns", "no",
        "ipv6.dns", "",
        "ipv6.ignore-auto-dns", "no"
      )
    }
    pendingDnsUuid = uuid
    dnsModifyProc.command = command
    dnsModifyProc.running = true
  }

  function toggleVpn(uuid) {
    if (root.networkBusy || !uuid)
      return
    root.errorMessage = ""
    root.networkBusy = true
    const connect = root.activeVpnUuids.indexOf(uuid) === -1
    vpnProc.command = connect
      ? ["nmcli", "connection", "up", "uuid", uuid]
      : ["nmcli", "connection", "down", "uuid", uuid]
    vpnProc.running = true
  }

  function pickColor() {
    if (!colorPickerProc.running) {
      root.errorMessage = ""
      colorPickerProc.running = true
    }
  }

  function copyColor(color) {
    const value = String(color || "").trim()
    if (!/^#[0-9a-fA-F]{6,8}$/.test(value))
      return
    root.pickedColor = value
    Quickshell.clipboardText = value
    const recent = root.recentColors.filter(item => item.toLowerCase() !== value.toLowerCase())
    recent.unshift(value)
    root.recentColors = recent.slice(0, 10)
  }

  function setNightMode(enabled) {
    if (!root.nightModeAvailable || root.nightModeBusy)
      return
    root.errorMessage = ""
    root.nightModeBusy = true
    root.requestedNightMode = enabled
    applyNightTemperature()
  }

  function applyNightTemperature() {
    nightApplyProc.command = [
      "hyprctl", "hyprsunset", "temperature",
      root.requestedNightMode ? "4000" : "6500"
    ]
    nightApplyProc.running = true
  }

  function finishNetworkAction(exitCode, operation) {
    root.networkBusy = false
    if (exitCode !== 0) {
      root.errorMessage = operation + " failed. Check NetworkManager permissions and connection state."
    } else {
      networkRefreshTimer.restart()
    }
  }

  property string pendingDnsUuid: ""

  property Process brightnessProc: Process {
    id: brightnessProc
    command: ["brightnessctl", "-m"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateBrightness(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.brightnessAvailable = false
    }
  }

  property Process brightnessWriteProc: Process {
    id: brightnessWriteProc
    command: ["brightnessctl", "set", "50%"]
    onExited: function(exitCode) {
      if (exitCode === 0 && !brightnessProc.running)
        brightnessProc.running = true
      else if (exitCode !== 0)
        root.errorMessage = "Brightness change failed. Check brightness device permissions."
    }
  }

  property Timer brightnessWriteTimer: Timer {
    id: brightnessWriteTimer
    interval: 120
    onTriggered: {
      if (brightnessWriteProc.running) {
        restart()
        return
      }
      if (!root.hasPendingBrightness)
        return
      root.hasPendingBrightness = false
      brightnessWriteProc.command = [
        "brightnessctl", "-d", root.brightnessDevice, "set", root.pendingBrightnessPercent + "%"
      ]
      brightnessWriteProc.running = true
    }
  }

  property Process profilesProc: Process {
    id: profilesProc
    command: ["nmcli", "-t", "--escape", "yes", "-f", "NAME,UUID,TYPE", "connection", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateProfiles(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.networkManagerAvailable = false
        root.vpnProfiles = []
      }
    }
  }

  property Process activeProc: Process {
    id: activeProc
    command: ["nmcli", "-t", "--escape", "yes", "-f", "NAME,UUID,TYPE", "connection", "show", "--active"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateActiveConnections(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.networkManagerAvailable = false
    }
  }

  property Process connectionConfigProc: Process {
    id: connectionConfigProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDnsConfig(text)
    }
  }

  property Process dnsModifyProc: Process {
    id: dnsModifyProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.finishNetworkAction(exitCode, "DNS update")
        return
      }
      dnsActivateProc.command = ["nmcli", "connection", "up", "uuid", root.pendingDnsUuid]
      dnsActivateProc.running = true
    }
  }

  property Process dnsActivateProc: Process {
    id: dnsActivateProc
    onExited: function(exitCode) {
      root.finishNetworkAction(exitCode, "Network reconnect")
    }
  }

  property Process vpnProc: Process {
    id: vpnProc
    onExited: function(exitCode) {
      root.finishNetworkAction(exitCode, "VPN connection")
    }
  }

  property Process colorPickerProc: Process {
    id: colorPickerProc
    command: ["hyprpicker", "-q", "-f", "hex"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const color = String(text || "").trim()
        if (/^#[0-9a-fA-F]{6,8}$/.test(color))
          root.copyColor(color)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.errorMessage = "Color picker failed or was canceled."
    }
  }

  property Process nightStatusProc: Process {
    id: nightStatusProc
    command: ["hyprctl", "hyprsunset", "temperature"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const match = String(text || "").match(/[0-9]+/)
        if (match) {
          root.nightModeAvailable = true
          root.nightModeEnabled = Number(match[0]) < 6000
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.nightDaemonStarted)
        root.nightModeEnabled = false
    }
  }

  property Process nightApplyProc: Process {
    id: nightApplyProc
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.nightModeEnabled = root.requestedNightMode
        root.nightModeBusy = false
        root.nightDaemonStarted = false
        return
      }
      if (!root.nightDaemonStarted) {
        root.nightDaemonStarted = true
        Quickshell.execDetached(["hyprsunset"])
        nightStartTimer.start()
      } else {
        root.nightModeBusy = false
        root.errorMessage = "Night mode failed. Ensure hyprsunset is installed and running."
      }
    }
  }

  property Timer nightStartTimer: Timer {
    id: nightStartTimer
    interval: 1000
    onTriggered: root.applyNightTemperature()
  }

  property Timer networkRefreshTimer: Timer {
    id: networkRefreshTimer
    interval: 1200
    onTriggered: {
      if (!profilesProc.running)
        profilesProc.running = true
      if (!activeProc.running)
        activeProc.running = true
    }
  }
}
