pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Single shared poller for CPU / memory / disk, backed by one bash process
// that reads /proc.* and df every few seconds. Keeps previous CPU counters to
// compute a usage delta. Exposes ready-made percentages so bar widgets share
// one timer instead of each polling independently.
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

  property var _prevTotal: 0
  property var _prevIdle: 0

  function refresh() {
    statsProc.running = true
  }

  // Outputs one line: CPU counters, memory values, disk values, and CPU temperature.
  property Process statsProc: Process {
    id: statsProc
    command: [
      "bash", "-c",
      "cpu=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat); " +
      "mem=$(awk '/^MemTotal:/{total=$2} /^MemAvailable:/{available=$2} END{print total, available}' /proc/meminfo); " +
      "disk=$(df -Pk / | awk 'NR==2 {print $3*1024, $2*1024}'); " +
      "temp=; " +
      "for preferred in x86_pkg_temp TCPU_PCI TCPU; do " +
      "for z in /sys/class/thermal/thermal_zone*/; do " +
      "[ -r \"$z/type\" ] && [ \"$(cat \"$z/type\")\" = \"$preferred\" ] || continue; " +
      "value=$(cat \"$z/temp\" 2>/dev/null); " +
      "case \"$value\" in ''|*[!0-9]*) continue;; esac; " +
      "if [ \"$value\" -ge 20000 ] && [ \"$value\" -le 120000 ]; then temp=$((value / 1000)); break 2; fi; " +
      "done; done; echo \"$cpu $mem $disk ${temp:-0}\""
    ]
    stdout: SplitParser {
      onRead: function(line) {
        const parts = String(line).trim().split(/\s+/)
        if (parts.length < 7) return
        const cpuTotal = parseFloat(parts[0]) || 0
        const cpuIdle  = parseFloat(parts[1]) || 0
        const memTotalKB = parseFloat(parts[2]) || 0
        const memAvailKB = parseFloat(parts[3]) || 0
        const dUsedB     = parseFloat(parts[4]) || 0
        const dTotalB    = parseFloat(parts[5]) || 0
        const temperature = parseFloat(parts[6]) || 0
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

        if (dTotalB > 0) {
          root.diskUsage    = Math.min(100, Math.max(0, dUsedB / dTotalB * 100))
          root.diskUsedText  = root._fmtBytes(dUsedB)
          root.diskTotalText = root._fmtBytes(dTotalB)
        }
      }
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
}
