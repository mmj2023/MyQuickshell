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
  property string memUsedText: "0B"
  property string memTotalText: "0B"
  property string diskUsedText: "0B"
  property string diskTotalText: "0B"

  property var _prevTotal: 0
  property var _prevIdle: 0

  function refresh() {
    statsProc.running = true
  }

  // Outputs one line: <cpuTotal> <cpuIdle> <memTotalKB> <memAvailKB> <diskUsedB> <diskAvailB>
  property Process statsProc: Process {
    id: statsProc
    command: [
      "bash", "-c",
      "read -r _ u n s i o w ir st </proc/stat; " +
      "cpuTotal=$((u+n+s+i+o+w+ir+st)); cpuIdle=$((i+o)); " +
      "memTotal=$(awk '/^MemTotal:/{print $2}' /proc/meminfo); " +
      "memAvail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo); " +
      "eval $(df -BK / | awk 'NR==2{gsub(/K/,\"\",$2); gsub(/K/,\"\",$3); gsub(/K/,\"\",$4); print \"dSize=\"$2\" dUsed=\"$3\" dAvail=\"$4}'); " +
      "echo \"$cpuTotal $cpuIdle $memTotal $memAvail $dUsed $dAvail $dSize\""
    ]
    stdout: SplitParser {
      onRead: function(line) {
        const parts = String(line).trim().split(/\s+/)
        if (parts.length < 6) return
        const cpuTotal = parseFloat(parts[0]) || 0
        const cpuIdle  = parseFloat(parts[1]) || 0
        const memTotalKB = parseFloat(parts[2]) || 0
        const memAvailKB = parseFloat(parts[3]) || 0
        const dUsedKB    = parseFloat(parts[4]) || 0
        const dAvailKB   = parseFloat(parts[5]) || 0
        const dSizeKB    = parts.length >= 7 ? (parseFloat(parts[6]) || 0) : (dUsedKB + dAvailKB)

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

        const diskTotKB = dSizeKB > 0 ? dSizeKB : (dUsedKB + dAvailKB)
        if (diskTotKB > 0) {
          root.diskUsage    = dUsedKB / diskTotKB * 100
          root.diskUsedText  = root._fmtKB(dUsedKB)
          root.diskTotalText = root._fmtKB(diskTotKB)
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

  property Timer pollTimer: Timer {
    interval: 4000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
