pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

  property bool vendorChecked: false
  property string systemVendor: ""
  property var profiles: []
  property string currentProfile: ""
  property bool available: profiles.length > 0
  property bool profileLoading: false
  property bool busy: false
  property string errorMessage: ""
  property string batteryTemperature: ""
  property string _pendingProfile: ""
  property string _setErrorOutput: ""

  readonly property bool isAsus: /asus/i.test(systemVendor)
  readonly property string backendName: isAsus ? "asusctl" : "powerprofilesctl"
  readonly property string unavailableMessage: {
    if (!vendorChecked)
      return "Detecting power controls…"
    if (available)
      return ""
    return isAsus
      ? "No ASUS power profiles found. Check that asusctl is installed and running."
      : "Power profiles are unavailable. Install power-profiles-daemon to enable them."
  }

  function refresh() {
    if (!root.vendorChecked) {
      if (!vendorProc.running)
        vendorProc.running = true
      return
    }

    if (!profileListProc.running)
      profileListProc.running = true
    if (!profileGetProc.running) {
      root.profileLoading = true
      profileGetProc.running = true
    }
    if (!temperatureProc.running)
      temperatureProc.running = true
  }

  function applyProfile(profile) {
    if (!root.available || root.busy || root.profileLoading
        || !root.profiles.some(item => item.id === profile))
      return false

    if (root.currentProfile === profile)
      return true

    root.errorMessage = ""
    root._setErrorOutput = ""
    root._pendingProfile = profile
    setProfileProc.command = root.isAsus
      ? ["asusctl", "profile", "set", profile]
      : ["powerprofilesctl", "set", profile]
    root.busy = true
    setProfileProc.running = true
    return true
  }

  function acceptVendor(value) {
    root.systemVendor = String(value || "").trim()
    root.vendorChecked = true
    root.refresh()
  }

  function acceptProfiles(value) {
    const text = String(value || "").trim()
    const genericProfiles = [
      { id: "power-saver", label: "Power Saver", icon: "eco" },
      { id: "balanced", label: "Balanced", icon: "speed" },
      { id: "performance", label: "Performance", icon: "bolt" }
    ]

    if (root.isAsus) {
      const byId = {
        quiet: { id: "Quiet", label: "Quiet", icon: "eco" },
        balanced: { id: "Balanced", label: "Balanced", icon: "speed" },
        performance: { id: "Performance", label: "Performance", icon: "bolt" }
      }
      root.profiles = text.split(/\r?\n/)
        .map(line => byId[line.trim().toLowerCase()])
        .filter(profile => profile !== undefined)
    } else {
      const lower = text.toLowerCase()
      root.profiles = genericProfiles.filter(profile => lower.includes(profile.id))
    }

    if (root.profiles.length > 0)
      root.errorMessage = ""
  }

  function acceptCurrentProfile(value) {
    const text = String(value || "").trim()
    if (root.isAsus) {
      const match = text.match(/Active profile:\s*([^\s]+)/i)
      root.currentProfile = match ? match[1] : ""
    } else {
      root.currentProfile = text.split(/\s+/).pop() || ""
    }
  }

  function acceptTemperature(value) {
    const readings = String(value || "").trim().split(/\s+/)
      .map(value => Number(value))
      .filter(value => isFinite(value) && value > 0 && value <= 1200)
      .map(value => value / 10)

    if (readings.length === 0) {
      root.batteryTemperature = ""
      return
    }
    root.batteryTemperature = (readings.reduce((sum, value) => sum + value, 0) / readings.length).toFixed(1)
  }

  property Process vendorProc: Process {
    id: vendorProc
    command: ["cat", "/sys/class/dmi/id/sys_vendor"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptVendor(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.vendorChecked) {
        root.vendorChecked = true
        root.systemVendor = ""
        root.refresh()
      }
    }
  }

  property Process profileListProc: Process {
    id: profileListProc
    command: root.isAsus ? ["asusctl", "profile", "list"] : ["powerprofilesctl", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptProfiles(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.profiles = []
        root.errorMessage = root.isAsus
          ? "Unable to read ASUS power profiles (exit code " + exitCode + ")."
          : "Unable to read system power profiles (exit code " + exitCode + ")."
      }
    }
  }

  property Process profileGetProc: Process {
    id: profileGetProc
    command: root.isAsus ? ["asusctl", "profile", "get"] : ["powerprofilesctl", "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptCurrentProfile(text)
    }
    onExited: function(exitCode) {
      root.profileLoading = false
      if (exitCode !== 0 && root.profiles.length > 0)
        root.errorMessage = "Unable to read the current power profile (exit code " + exitCode + ")."
    }
  }

  property Process setProfileProc: Process {
    id: setProfileProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._setErrorOutput = text.trim()
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.busy = false
        root.errorMessage = root._setErrorOutput
          || "Unable to set the power profile (exit code " + exitCode + ")."
        return
      }

      root.currentProfile = root._pendingProfile
      root.errorMessage = ""
      if (!profileGetProc.running) {
        root.profileLoading = true
        profileGetProc.running = true
      }
      root.busy = false
    }
  }

  property Process temperatureProc: Process {
    id: temperatureProc
    command: [
      "sh", "-c",
      "for path in /sys/class/power_supply/BAT*/temp; do " +
        "[ -r \"$path\" ] || continue; " +
        "IFS= read -r value < \"$path\" || continue; " +
        "case \"$value\" in ''|*[!0-9]*) continue;; esac; " +
        "printf '%s\\n' \"$value\"; " +
      "done"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptTemperature(text)
    }
  }

}
