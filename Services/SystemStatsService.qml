pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared resource pollers. CPU, memory, and temperature use cheap kernel
// interfaces frequently; filesystem accounting is probed separately and only
// reformatted when the filesystem's free-block signature changes.
Singleton {
  id: root

  property real cpuUsage: 0
  property real memoryUsage: 0
  property real diskUsage: 0
  property real cpuTemperature: -1
  property string memUsedText: "0B"
  property string memTotalText: "0B"
  property string diskUsedText: "0B"
  property string diskTotalText: "0B"
  property var diskMounts: []

  property var _prevTotal: 0
  property var _prevIdle: 0
  property string _diskSignature: ""

  function refresh() {
    statsProc.running = true
  }

  function refreshDisk() {
    diskProbe.running = true
  }

  // Outputs CPU counters, memory values, and CPU temperature.
  property Process statsProc: Process {
    id: statsProc
    command: [
      "bash", "-c",
      "cpu=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat); " +
      "mem=$(awk '/^MemTotal:/{total=$2} /^MemAvailable:/{available=$2} END{print total, available}' /proc/meminfo); " +
      "temp=; " +
      "for preferred in x86_pkg_temp TCPU_PCI TCPU; do " +
      "for z in /sys/class/thermal/thermal_zone*/; do " +
      "[ -r \"$z/type\" ] && [ \"$(cat \"$z/type\")\" = \"$preferred\" ] || continue; " +
      "value=$(cat \"$z/temp\" 2>/dev/null); " +
      "case \"$value\" in ''|*[!0-9]*) continue;; esac; " +
      "if [ \"$value\" -ge 20000 ] && [ \"$value\" -le 120000 ]; then temp=$((value / 1000)); break 2; fi; " +
      "done; done; echo \"$cpu $mem ${temp:-0}\""
    ]
    stdout: SplitParser {
      onRead: function(line) {
        const parts = String(line).trim().split(/\s+/)
        if (parts.length < 5) return
        const cpuTotal = parseFloat(parts[0]) || 0
        const cpuIdle  = parseFloat(parts[1]) || 0
        const memTotalKB = parseFloat(parts[2]) || 0
        const memAvailKB = parseFloat(parts[3]) || 0
        const temperature = parseFloat(parts[4]) || 0
        if (temperature > 0)
          root.cpuTemperature = temperature

        if (root._prevTotal > 0 && cpuTotal > root._prevTotal) {
          const dTot  = cpuTotal - root._prevTotal
          const dIdle = cpuIdle  - root._prevIdle
          root.cpuUsage = Math.min(100, Math.max(0, (dTot - dIdle) / dTot * 100))
        }
        root._prevTotal = cpuTotal
        root._prevIdle  = cpuIdle

        if (memTotalKB > 0) {
          const memUsedKB = memTotalKB - memAvailKB
          root.memoryUsage  = Math.min(100, Math.max(0, memUsedKB / memTotalKB * 100))
          root.memUsedText  = root._fmtKB(memUsedKB)
          root.memTotalText = root._fmtKB(memTotalKB)
        }

      }
    }
  }

  // Report mounted filesystems backed by a physical block device. This avoids
  // showing Flatpak, portal, network, and other virtual mounts as storage.
  property Process diskProbe: Process {
    id: diskProbe
    command: [
      "bash", "-c",
      "df -P 2>/dev/null | awk 'NR > 1 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && !seen[$1]++ " +
      "{print $1 \"|\" $6 \"|\" ($3 * 1024) \"|\" ($2 * 1024)}' | " +
      "while IFS='|' read -r source mount used total; do " +
      "case \"$source\" in /dev/*) ;; *) continue;; esac; " +
      "if lsblk -s -nr -o TYPE,TRAN \"$source\" 2>/dev/null | " +
      "awk '$1 == \"disk\" && $2 != \"\" {found=1} END {exit !found}'; then " +
      "printf '%s|%s|%s\\n' \"$mount\" \"$used\" \"$total\"; fi; done"
    ]
    stdout: StdioCollector {
      onStreamFinished: root.updateDiskMounts(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("SystemStatsService: physical disk probe failed with exit code", exitCode)
    }
  }

  function updateDiskMounts(output) {
    const mounts = []
    for (const line of String(output).split(/\r?\n/)) {
      const parts = line.trim().split("|")
      if (parts.length < 3)
        continue
      const used = Number(parts[1])
      const total = Number(parts[2])
      if (!parts[0] || !Number.isFinite(used) || !Number.isFinite(total) || total <= 0)
        continue
      mounts.push({
        mount: parts[0],
        used: used,
        total: total,
        usage: Math.min(100, Math.max(0, used / total * 100))
      })
    }
    root.diskMounts = mounts

    const primary = mounts.find(item => item.mount === "/") || mounts[0]
    if (primary) {
      root.diskUsage = primary.usage
      root.diskUsedText = root._fmtBytes(primary.used)
      root.diskTotalText = root._fmtBytes(primary.total)
    } else {
      root.diskUsage = 0
      root.diskUsedText = "0B"
      root.diskTotalText = "0B"
    }
  }

  function _fmtKB(kb) {
    const units = ["KiB", "MiB", "GiB", "TiB"]
    let v = kb
    let i = 0
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    return (v >= 100 ? Math.round(v) : Math.round(v * 10) / 10) + units[i]
  }

  function _fmtBytes(bytes) {
    return root._fmtKB(bytes / 1024)
  }

  property Timer pollTimer: Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  property Timer diskPollTimer: Timer {
    interval: 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshDisk()
  }
}
