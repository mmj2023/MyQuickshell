pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

QtObject {
  id: root

  property var brightnessDevices: []
  readonly property bool brightnessAvailable: brightnessDevices.length > 0
  property var brightnessWriteQueue: []
  property string writingBrightnessDevice: ""
  property bool keepAwake: false
  property bool networkManagerAvailable: false
  property string activeConnectionUuid: ""
  property string dnsProvider: "DHCP"
  property var networkInfo: ({})
  property real networkDownloadRate: 0
  property real networkUploadRate: 0
  property real previousNetworkRxBytes: 0
  property real previousNetworkTxBytes: 0
  property real previousNetworkSampleTime: 0
  property string previousNetworkInterface: ""
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
    if (!networkDetailsProc.running)
      networkDetailsProc.running = true
    if (root.nightModeAvailable && !nightStatusProc.running)
      nightStatusProc.running = true
  }

  function updateBrightness(raw) {
    const lines = String(raw || "").trim().split("\n")
    const devices = []
    for (let i = 0; i < lines.length; i++) {
      const fields = lines[i].split(",")
      if (fields.length < 5)
        continue
      const percent = Number(String(fields[3]).replace("%", ""))
      if (!isFinite(percent))
        continue
      const device = fields[0]
      const className = fields[1]
      const isScreenBacklight = className === "backlight"
      const isKeyboardBacklight = className === "leds" && /(kbd|keyboard).*backlight|backlight.*(kbd|keyboard)/i.test(device)
      if (!isScreenBacklight && !isKeyboardBacklight)
        continue
      const prettyDevice = device
        .replace(/^asus::kbd_backlight$/i, "ASUS Keyboard Backlight")
        .replace(/::/g, " ")
        .replace(/[_-]+/g, " ")
        .replace(/\b\w/g, character => character.toUpperCase())
      devices.push({
        device: device,
        title: isKeyboardBacklight ? "Keyboard Backlight" : prettyDevice,
        classLabel: isKeyboardBacklight ? "LED device" : "Backlight device",
        className: className,
        percent: Math.round(percent),
        current: Number(fields[2]),
        max: Number(fields[4])
      })
    }
    devices.sort((left, right) => {
      if (left.className === right.className)
        return left.title.localeCompare(right.title)
      return left.className === "backlight" ? -1 : 1
    })
    root.brightnessDevices = devices
  }

  function setBrightness(device, percent) {
    if (!device || !root.brightnessDevices.some(item => item.device === device))
      return
    const queue = root.brightnessWriteQueue.slice()
    const value = Math.max(0, Math.min(100, Math.round(percent)))
    const index = queue.findIndex(item => item.device === device)
    if (index >= 0)
      queue[index] = { device: device, percent: value }
    else
      queue.push({ device: device, percent: value })
    root.brightnessWriteQueue = queue
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

  function updateNetworkDetails(raw) {
    const lines = String(raw || "").split("\n")
    const details = {}
    for (let i = 0; i < lines.length; i++) {
      const separator = lines[i].indexOf("\t")
      if (separator <= 0)
        continue
      details[lines[i].slice(0, separator)] = lines[i].slice(separator + 1).trim()
    }

    const rxBytes = Number(details.rx_bytes || 0)
    const txBytes = Number(details.tx_bytes || 0)
    const now = Date.now() / 1000
    if (!details.iface || details.iface !== root.previousNetworkInterface
        || root.previousNetworkSampleTime === 0) {
      root.networkDownloadRate = 0
      root.networkUploadRate = 0
    } else {
      const elapsed = now - root.previousNetworkSampleTime
      if (elapsed > 0) {
        root.networkDownloadRate = Math.max(0, (rxBytes - root.previousNetworkRxBytes) / elapsed)
        root.networkUploadRate = Math.max(0, (txBytes - root.previousNetworkTxBytes) / elapsed)
      }
    }

    root.previousNetworkInterface = details.iface || ""
    root.previousNetworkSampleTime = details.iface ? now : 0
    root.previousNetworkRxBytes = rxBytes
    root.previousNetworkTxBytes = txBytes
    root.networkInfo = details
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
    command: ["brightnessctl", "-l", "-m"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateBrightness(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.brightnessDevices = []
    }
  }

  property Process brightnessWriteProc: Process {
    id: brightnessWriteProc
    command: ["brightnessctl", "set", "50%"]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.errorMessage = "Brightness change failed for " + root.writingBrightnessDevice + ". Check device permissions."
      }
      root.writingBrightnessDevice = ""
      if (root.brightnessWriteQueue.length > 0)
        brightnessWriteTimer.restart()
      else if (exitCode === 0 && !brightnessProc.running)
        brightnessProc.running = true
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
      if (root.brightnessWriteQueue.length === 0)
        return
      const queue = root.brightnessWriteQueue.slice()
      const next = queue.shift()
      root.brightnessWriteQueue = queue
      root.writingBrightnessDevice = next.device
      brightnessWriteProc.command = [
        "brightnessctl", "-d", next.device, "set", next.percent + "%"
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

  property Process networkDetailsProc: Process {
    id: networkDetailsProc
    command: ["sh", "-c",
      "route=$(ip route get 1.1.1.1 2>/dev/null || true)\n" +
      "iface=$(printf '%s\\n' \"$route\" | awk '{ for (i = 1; i <= NF; i++) if ($i == \"dev\") { print $(i + 1); exit } }')\n" +
      "[ -n \"$iface\" ] || exit 0\n" +
      "printf 'iface\\t%s\\n' \"$iface\"\n" +
      "printf '%s\\n' \"$route\" | awk '{ for (i = 1; i <= NF; i++) if ($i == \"src\") { print \"ip\\t\" $(i + 1); exit } }'\n" +
      "printf '%s\\n' \"$route\" | awk '{ for (i = 1; i <= NF; i++) if ($i == \"via\") { print \"gateway\\t\" $(i + 1); exit } }'\n" +
      "ip -o -4 addr show dev \"$iface\" scope global 2>/dev/null | awk 'NR == 1 { split($4, address, \"/\"); print \"ip\\t\" address[1]; print \"prefix\\t\" address[2] }'\n" +
      "printf 'mac\\t%s\\n' \"$(cat \"/sys/class/net/$iface/address\" 2>/dev/null || true)\"\n" +
      "printf 'rx_bytes\\t%s\\n' \"$(cat \"/sys/class/net/$iface/statistics/rx_bytes\" 2>/dev/null || true)\"\n" +
      "printf 'tx_bytes\\t%s\\n' \"$(cat \"/sys/class/net/$iface/statistics/tx_bytes\" 2>/dev/null || true)\"\n" +
      "printf 'dns\\t%s\\n' \"$(nmcli -g IP4.DNS device show \"$iface\" 2>/dev/null | paste -sd ', ' -)\"\n" +
      "if [ -d \"/sys/class/net/$iface/wireless\" ]; then\n" +
      "  printf 'type\\twifi\\n'\n" +
      "  if command -v iw >/dev/null 2>&1; then\n" +
      "    iw dev \"$iface\" link 2>/dev/null | awk '/signal:/ { print \"signal_dbm\\t\" $2; next } /freq:/ { print \"frequency\\t\" $2; next } /tx bitrate:/ { print \"bitrate\\t\" $3 \" \" $4; exit }'\n" +
      "  fi\n" +
      "else\n" +
      "  printf 'type\\tethernet\\n'\n" +
      "  printf 'speed\\t%s\\n' \"$(cat \"/sys/class/net/$iface/speed\" 2>/dev/null || true)\"\n" +
      "  printf 'duplex\\t%s\\n' \"$(cat \"/sys/class/net/$iface/duplex\" 2>/dev/null || true)\"\n" +
      "fi\n"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateNetworkDetails(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.updateNetworkDetails("")
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
