pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared resource pollers. CPU and memory use cheap kernel interfaces;
// filesystem and GPU accounting are probed separately at lower frequencies.
Singleton {
  id: root

  property real cpuUsage: 0
  property string cpuModel: ""
  property int cpuCoreCount: 0
  property var perCoreCpuUsage: []
  property var cpuHistory: []
  property var processes: []
  property var gpus: []
  property bool gpuProcessUsageAvailable: false
  property int processCount: 0
  property int currentUid: -1
  property string processListError: ""
  property bool processActionRunning: false
  property string processActionError: ""
  property string gpuStatsError: ""
  property real memoryUsage: 0
  property real memAvailableKB: 0
  property real memFreeKB: 0
  property real memCachedKB: 0
  property real memBuffersKB: 0
  property real swapUsage: 0
  property real swapUsedKB: 0
  property real swapTotalKB: 0
  property var memoryHistory: []
  property int overviewRefCount: 0
  readonly property bool overviewActive: overviewRefCount > 0
  property real diskUsage: 0
  property real cpuTemperature: -1
  property string memUsedText: "0B"
  property string memTotalText: "0B"
  property string diskUsedText: "0B"
  property string diskTotalText: "0B"
  property var diskMounts: []

  property var _prevCpuCounters: ({})
  property var _prevGpuEngineCounters: ({})
  property real _gpuSampleTime: 0
  property string _diskSignature: ""

  onOverviewActiveChanged: {
    if (!overviewActive) {
      cpuHistory = []
      memoryHistory = []
    }
    refreshGpu()
  }

  function refresh() {
    statsProc.running = true
  }

  function refreshDisk() {
    diskProbe.running = true
  }

  function refreshProcesses() {
    if (root.overviewActive && !processProbe.running)
      processProbe.running = true
  }

  function refreshGpu() {
    if (!gpuProbe.running) {
      gpuProbe.command = ["bash", "-c", root.gpuProbeScript, "myquickshell-gpu",
        root.overviewActive ? "1" : "0"]
      gpuProbe.running = true
    }
  }

  readonly property string gpuProbeScript:
    "if command -v nvidia-smi >/dev/null 2>&1; then " +
      "if gpu_csv=$(nvidia-smi --query-gpu=index,uuid,name,pci.bus_id,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null); then " +
        "while IFS= read -r line; do [ -n \"$line\" ] && printf 'NVIDIA|%s\\n' \"$line\"; done <<< \"$gpu_csv\"; " +
      "else printf 'ERROR|NVIDIA|telemetry unavailable\\n'; fi; " +
    "fi; " +
    "for card in /sys/class/drm/card[0-9]*; do " +
      "[[ \"${card##*/}\" =~ ^card[0-9]+$ ]] || continue; " +
      "[ -r \"$card/device/vendor\" ] || continue; " +
      "pci=$(basename \"$(readlink -f \"$card/device\")\"); " +
      "vendor=$(cat \"$card/device/vendor\" 2>/dev/null); device=$(cat \"$card/device/device\" 2>/dev/null); " +
      "driver=$(basename \"$(readlink -f \"$card/device/driver\" 2>/dev/null)\"); " +
      "case \"$vendor\" in 0x8086) maker=Intel;; 0x1002) maker=AMD;; 0x10de) maker=NVIDIA;; *) maker=GPU;; esac; " +
      "name=$(cat \"$card/device/product_name\" 2>/dev/null); " +
      "[ -n \"$name\" ] || name=\"$maker GPU (${device#0x})\"; " +
      "busy=$(cat \"$card/device/gpu_busy_percent\" 2>/dev/null); " +
      "case \"$busy\" in ''|*[!0-9]*) busy=-1;; esac; " +
      "used=$(cat \"$card/device/mem_info_vram_used\" 2>/dev/null); total=$(cat \"$card/device/mem_info_vram_total\" 2>/dev/null); " +
      "case \"$used\" in ''|*[!0-9]*) used=-1;; esac; case \"$total\" in ''|*[!0-9]*) total=-1;; esac; " +
      "printf 'DRM|%s|%s|%s|%s|%s|%s|%s|%s\\n' \"$pci\" \"$vendor\" \"$driver\" \"$name\" \"$busy\" \"$used\" \"$total\" \"${card##*card}\"; " +
    "done; " +
    "if [ \"$1\" = 1 ]; then " +
      "if command -v nvidia-smi >/dev/null 2>&1; then " +
        "nvidia-smi pmon -c 1 -s um 2>/dev/null | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {print \"PMON|\" $1 \"|\" $2 \"|\" $4 \"|\" $5}'; " +
        "nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv,noheader,nounits 2>/dev/null | awk -F, 'NF >= 3 {gsub(/^[ \\t]+|[ \\t]+$/, \"\", $1); gsub(/^[ \\t]+|[ \\t]+$/, \"\", $2); gsub(/^[ \\t]+|[ \\t]+$/, \"\", $3); print \"NAPP|\" $1 \"|\" $2 \"|\" $3}'; " +
      "fi; " +
      "find /proc/[0-9]*/fdinfo -maxdepth 1 -type f -exec awk ' " +
        "function emit() { if (driver != \"\" && pdev != \"\" && (engine > 0 || vram > 0)) printf \"ENGINE|%s|%s|%s|%.0f|%.0f\\n\", pid, pdev, driver, engine, vram; driver = \"\"; pdev = \"\"; engine = 0; vram = 0 } " +
        "FNR == 1 { emit(); split(FILENAME, path, \"/\"); pid = path[3] } " +
        "/^drm-driver:/ { driver = $2 } /^drm-pdev:/ { pdev = $2 } " +
        "/^drm-engine-[^:]+:/ { if ($2 ~ /^[0-9]+$/) engine += $2 } " +
        "/^drm-resident-vram[^:]*:/ { amount = $2 + 0; if ($3 == \"MiB\") amount *= 1024; else if ($3 == \"GiB\") amount *= 1048576; vram += amount } " +
        "END { emit() } " +
      "' {} + 2>/dev/null || true; " +
    "fi"

  function parseCsvFields(line) {
    const fields = []
    let field = ""
    let quoted = false
    for (let index = 0; index < line.length; index++) {
      const character = line[index]
      if (character === "\"" && quoted && line[index + 1] === "\"") {
        field += "\""
        index++
      } else if (character === "\"") {
        quoted = !quoted
      } else if (character === "," && !quoted) {
        fields.push(field.trim())
        field = ""
      } else {
        field += character
      }
    }
    fields.push(field.trim())
    return fields
  }

  function normalizedPciAddress(address) {
    const match = /^([0-9a-f]+):([0-9a-f]{2}):([0-9a-f]{2})\.([0-7])$/i.exec(String(address).trim())
    return match ? (Number.parseInt(match[1], 16).toString(16).padStart(4, "0") + ":"
      + match[2].toLowerCase() + ":" + match[3].toLowerCase() + "." + match[4]) : ""
  }

  function finiteGpuNumber(value) {
    const text = String(value).trim()
    if (!/[0-9]/.test(text))
      return -1
    const number = Number(text.replace(/[^0-9.+-]/g, ""))
    return Number.isFinite(number) ? number : -1
  }

  function handleGpuProbe(output) {
    const gpus = []
    const gpuByPci = ({})
    const processGpuByPid = ({})
    const processGpuDevicesByPid = ({})
    const processGpuMemoryByPid = ({})
    const engineCounters = ({})
    const pmonSamples = []

    for (const line of String(output).split(/\r?\n/)) {
      if (!line)
        continue
      if (line.startsWith("ERROR|")) {
        root.gpuStatsError = line.slice(6)
      } else if (line.startsWith("DRM|")) {
        const fields = line.split("|")
        const pci = root.normalizedPciAddress(fields[1])
        if (!pci)
          continue
        if (gpuByPci[pci])
          continue
        const index = Number(fields[8])
        const gpu = {
          id: pci,
          pciAddress: pci,
          index: Number.isInteger(index) ? index : gpus.length,
          name: fields[4] || qsTr("GPU"),
          driver: fields[3] || qsTr("Unknown driver"),
          vendor: fields[2] === "0x8086" ? "Intel"
            : (fields[2] === "0x1002" ? "AMD"
            : (fields[2] === "0x10de" ? "NVIDIA" : qsTr("Other"))),
          utilization: root.finiteGpuNumber(fields[5]),
          memoryUsage: -1,
          memoryTotal: -1,
          memoryPercent: -1,
          memoryControllerUtilization: -1,
          temperature: -1,
          power: -1,
          nvidiaIndex: -1,
          uuid: "",
          utilizationSource: fields[5] === "-1" ? "DRM process counters" : "Kernel driver"
        }
        if (gpu.utilization < 0)
          gpu.utilizationSource = "Waiting for driver counters"
        if (root.finiteGpuNumber(fields[6]) >= 0 && root.finiteGpuNumber(fields[7]) >= 0) {
          gpu.memoryUsage = root.finiteGpuNumber(fields[6]) / (1024 * 1024)
          gpu.memoryTotal = root.finiteGpuNumber(fields[7]) / (1024 * 1024)
          gpu.memoryPercent = gpu.memoryTotal > 0 ? gpu.memoryUsage / gpu.memoryTotal * 100 : -1
        }
        gpuByPci[pci] = gpu
        gpus.push(gpu)
      } else if (line.startsWith("NVIDIA|")) {
        const fields = root.parseCsvFields(line.slice(7))
        if (fields.length < 10)
          continue
        const pci = root.normalizedPciAddress(fields[3])
        if (!pci)
          continue
        let gpu = gpuByPci[pci]
        if (!gpu) {
          gpu = {
            id: pci, pciAddress: pci, index: root.finiteGpuNumber(fields[0]),
            nvidiaIndex: root.finiteGpuNumber(fields[0]),
            uuid: fields[1],
            name: fields[2], driver: "nvidia", vendor: "NVIDIA",
            utilization: -1, memoryUsage: -1, memoryTotal: -1, memoryPercent: -1,
            memoryControllerUtilization: -1,
            temperature: -1, power: -1, utilizationSource: "NVIDIA driver"
          }
          gpuByPci[pci] = gpu
          gpus.push(gpu)
        }
        gpu.index = root.finiteGpuNumber(fields[0])
        gpu.nvidiaIndex = root.finiteGpuNumber(fields[0])
        gpu.uuid = fields[1]
        gpu.name = fields[2] || gpu.name
        gpu.driver = "nvidia"
        gpu.vendor = "NVIDIA"
        gpu.utilization = root.finiteGpuNumber(fields[4])
        gpu.memoryControllerUtilization = root.finiteGpuNumber(fields[5])
        gpu.memoryUsage = root.finiteGpuNumber(fields[6])
        gpu.memoryTotal = root.finiteGpuNumber(fields[7])
        gpu.memoryPercent = gpu.memoryUsage >= 0 && gpu.memoryTotal > 0
          ? gpu.memoryUsage / gpu.memoryTotal * 100 : -1
        gpu.temperature = root.finiteGpuNumber(fields[8])
        gpu.power = root.finiteGpuNumber(fields[9])
        gpu.utilizationSource = "NVIDIA driver"
        root.gpuStatsError = ""
      } else if (line.startsWith("PMON|")) {
        const fields = line.split("|")
        pmonSamples.push({
          index: Number(fields[1]),
          pid: Number(fields[2]),
          utilization: root.finiteGpuNumber(fields[3]),
          memoryPercent: root.finiteGpuNumber(fields[4])
        })
      } else if (line.startsWith("NAPP|")) {
        const fields = line.split("|")
        const gpu = gpus.find(candidate => candidate.uuid === fields[1])
        const pid = Number(fields[2])
        const memoryMB = root.finiteGpuNumber(fields[3])
        if (gpu && Number.isInteger(pid)) {
          if (!processGpuDevicesByPid[pid])
            processGpuDevicesByPid[pid] = ({})
          processGpuDevicesByPid[pid][gpu.pciAddress] = true
        }
        if (gpu && Number.isInteger(pid) && memoryMB >= 0)
          processGpuMemoryByPid[pid] = (processGpuMemoryByPid[pid] || 0) + memoryMB
      } else if (line.startsWith("ENGINE|")) {
        const fields = line.split("|")
        const pid = Number(fields[1])
        const pci = root.normalizedPciAddress(fields[2])
        const counter = Number(fields[4])
        const vramKB = Number(fields[5])
        if (Number.isInteger(pid) && pci && Number.isFinite(counter)) {
          const key = pid + "|" + pci
          if (!processGpuDevicesByPid[pid])
            processGpuDevicesByPid[pid] = ({})
          processGpuDevicesByPid[pid][pci] = true
          if (!engineCounters[key])
            engineCounters[key] = { engine: 0, vramKB: 0 }
          engineCounters[key].engine += counter
          engineCounters[key].vramKB += Number.isFinite(vramKB) ? vramKB : 0
        }
      }
    }

    const now = Date.now()
    const elapsed = root._gpuSampleTime > 0 ? (now - root._gpuSampleTime) * 1000000 : 0
    root._gpuSampleTime = now
    const nextEngineCounters = ({})
    for (const key in engineCounters) {
      const current = engineCounters[key].engine
      const previous = root._prevGpuEngineCounters[key]
      nextEngineCounters[key] = current
      if (previous !== undefined && elapsed > 0 && current >= previous) {
        const [pid, pci] = key.split("|")
        const usage = Math.min(100, Math.max(0, (current - previous) / elapsed * 100))
        if (!processGpuByPid[pid])
          processGpuByPid[pid] = ({})
        processGpuByPid[pid][pci] = usage
      }
      const [pid, pci] = key.split("|")
      if (engineCounters[key].vramKB > 0) {
        processGpuMemoryByPid[pid] = (processGpuMemoryByPid[pid] || 0)
          + engineCounters[key].vramKB / 1024
      }
    }
    root._prevGpuEngineCounters = nextEngineCounters

    for (const sample of pmonSamples) {
      if (sample.utilization < 0)
        continue
      const gpu = gpus.find(candidate => candidate.vendor === "NVIDIA" && candidate.nvidiaIndex === sample.index)
      if (!gpu)
        continue
      const pid = String(sample.pid)
      if (!processGpuDevicesByPid[pid])
        processGpuDevicesByPid[pid] = ({})
      processGpuDevicesByPid[pid][gpu.pciAddress] = true
      if (!processGpuByPid[pid])
        processGpuByPid[pid] = ({})
      processGpuByPid[pid][gpu.pciAddress] = sample.utilization
    }
    root.gpuProcessUsageAvailable = Object.keys(processGpuByPid).length > 0

    for (const gpu of gpus) {
      if (gpu.utilization < 0 && gpu.vendor !== "NVIDIA") {
        let total = 0
        for (const pid in processGpuByPid)
          total += processGpuByPid[pid][gpu.pciAddress] || 0
        if (total > 0) {
          gpu.utilization = Math.min(100, total)
          gpu.utilizationSource = "DRM engine counters"
        }
      }
    }
    const responsiveGpus = gpus.filter(gpu =>
      !(gpu.vendor === "NVIDIA" && !gpu.uuid && gpu.utilization < 0
        && gpu.memoryUsage < 0 && !Object.keys(processGpuByPid).some(pid =>
          processGpuByPid[pid][gpu.pciAddress] !== undefined)))
    responsiveGpus.sort((a, b) => a.index - b.index || a.name.localeCompare(b.name))
    for (let index = 0; index < responsiveGpus.length; index++)
      responsiveGpus[index].displayIndex = index + 1
    root.gpus = responsiveGpus

    root.processes = root.processes.map(process => {
      const metrics = processGpuByPid[process.pid] || ({})
      const gpuDevices = processGpuDevicesByPid[process.pid] || ({})
      const deviceUsages = []
      let totalUsage = 0
      const pciAddresses = Object.keys(gpuDevices)
      for (const pci of pciAddresses) {
        const gpu = gpuByPci[pci]
        const utilization = metrics[pci] === undefined ? 0 : metrics[pci]
        totalUsage += utilization
        deviceUsages.push({ name: gpu ? gpu.name : pci, utilization: utilization })
      }
      const updatedProcess = ({})
      for (const key in process)
        updatedProcess[key] = process[key]
      updatedProcess.gpuUsage = deviceUsages.length
        ? Math.min(100, totalUsage)
        : (root.gpuProcessUsageAvailable ? 0 : null)
      updatedProcess.gpuPciAddresses = pciAddresses
      updatedProcess.gpuDetails = deviceUsages.map(item =>
        item.name + " " + item.utilization.toFixed(1) + "%").join(", ")
      updatedProcess.gpuMemoryMB = processGpuMemoryByPid[process.pid] !== undefined
        ? processGpuMemoryByPid[process.pid] : null
      return updatedProcess
    })
  }

  function signalProcess(pid, signal) {
    const allowedSignals = [
      "HUP", "INT", "QUIT", "KILL", "TERM", "STOP", "CONT", "TSTP",
      "TTIN", "TTOU", "USR1", "USR2", "ALRM", "ABRT", "PIPE", "CHLD",
      "WINCH", "URG", "XCPU", "XFSZ", "VTALRM", "PROF", "IO", "SYS",
      "TRAP", "FPE", "ILL", "BUS", "SEGV", "STKFLT", "PWR"
    ]
    const targetPid = Number(pid)
    if (!Number.isInteger(targetPid) || targetPid <= 1 || !allowedSignals.includes(signal)) {
      root.processActionError = "Invalid process or signal"
      return false
    }
    if (root.processActionRunning) {
      root.processActionError = "Another process action is still running"
      return false
    }
    if (root.currentUid < 0 || !root.processes.some(process =>
      process.pid === targetPid && process.uid === root.currentUid)) {
      root.processActionError = "Process is no longer available or is owned by another user"
      return false
    }

    root.processActionError = ""
    root.processActionRunning = true
    processAction.command = [
      "bash", "-c",
      "pid=\"$1\"; expected_uid=\"$2\"; signal=\"$3\"; " +
        "actual_uid=$(awk '/^Uid:/ {print $2; exit}' \"/proc/$pid/status\") || exit 3; " +
        "[ \"$actual_uid\" = \"$expected_uid\" ] || exit 4; " +
        "kill -s \"$signal\" -- \"$pid\"",
      "myquickshell-signal",
      String(targetPid),
      String(root.currentUid),
      signal
    ]
    processAction.running = true
    return true
  }

  function handleProcesses(output) {
    const processes = []
    root.processListError = ""
    for (const line of String(output).split(/\r?\n/)) {
      const trimmed = line.trim()
      if (!trimmed)
        continue
      if (trimmed.startsWith("SELF ")) {
        const uid = Number(trimmed.slice(5))
        if (Number.isInteger(uid) && uid >= 0)
          root.currentUid = uid
        continue
      }
      const match = /^(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(\S+)(?:\s+(.*))?$/.exec(trimmed)
      if (!match)
        continue
      const args = String(match[9] || "").trim()
      processes.push({
        pid: Number(match[1]),
        ppid: Number(match[2]),
        uid: Number(match[3]),
        cpu: Number(match[4]) || 0,
        memoryPercent: Number(match[5]) || 0,
        memoryKB: Number(match[6]) || 0,
        state: match[7],
        name: match[8],
        command: args || match[8],
        fullCommand: args || match[8],
        gpuUsage: null,
        gpuDetails: "",
        gpuPciAddresses: [],
        isUser: Number(match[3]) === root.currentUid,
        isPaused: match[7].includes("T")
      })
    }
    processes.sort((a, b) => a.pid - b.pid)
    root.processes = processes
    root.processCount = processes.length
  }

  function addOverviewRef() {
    overviewRefCount++
  }

  function removeOverviewRef() {
    overviewRefCount = Math.max(0, overviewRefCount - 1)
  }

  // Read processor counters and memory details from kernel-provided procfs.
  property Process statsProc: Process {
    id: statsProc
    command: [
      "bash", "-c",
      "awk '/^cpu([0-9]+)? / {printf \"CPU %s\", $1; for (i=2; i<=NF; i++) printf \" %s\", $i; print \"\"}' /proc/stat; " +
      "awk '/^(MemTotal|MemAvailable|MemFree|Buffers|Cached|SReclaimable|Shmem|SwapTotal|SwapFree):/ {print \"MEM\", $1, $2}' /proc/meminfo; " +
      "awk -F ': *' '/^(model name|Hardware|Processor)[[:space:]]*:/ && !model {print \"MODEL\", $2; model=1} /^processor[[:space:]]*:/ {cores++} END {print \"CORES\", cores}' /proc/cpuinfo; " +
      "temp=; " +
      "for preferred in x86_pkg_temp TCPU_PCI TCPU; do " +
      "for z in /sys/class/thermal/thermal_zone*/; do " +
      "[ -r \"$z/type\" ] && [ \"$(cat \"$z/type\")\" = \"$preferred\" ] || continue; " +
      "value=$(cat \"$z/temp\" 2>/dev/null); " +
      "case \"$value\" in ''|*[!0-9]*) continue;; esac; " +
      "if [ \"$value\" -ge 20000 ] && [ \"$value\" -le 120000 ]; then temp=$((value / 1000)); break 2; fi; " +
      "done; done; echo \"TEMP ${temp:-0}\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleStats(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("SystemStatsService: processor and memory probe failed with exit code", exitCode)
    }
  }

  property Process processProbe: Process {
    id: processProbe
    command: [
      "bash", "-c",
      "printf 'SELF %s\\n' \"$(id -u)\"; " +
        "ps -eo pid=,ppid=,uid=,pcpu=,pmem=,rss=,stat=,comm=,args= --no-headers"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleProcesses(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.processListError = "Unable to read process list (exit code " + exitCode + ")"
        console.warn("SystemStatsService: process list probe failed with exit code", exitCode)
      }
    }
  }

  property Process gpuProbe: Process {
    id: gpuProbe
    command: ["bash", "-c", root.gpuProbeScript, "myquickshell-gpu", "0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleGpuProbe(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.gpuStatsError = "GPU probe failed (exit code " + exitCode + ")"
        console.warn("SystemStatsService:", root.gpuStatsError)
      }
    }
  }

  property Process processAction: Process {
    id: processAction
    onExited: function(exitCode) {
      root.processActionRunning = false
      if (exitCode !== 0) {
        root.processActionError = exitCode === 3 || exitCode === 4
          ? "Process exited or changed owner before the signal was sent"
          : "Signal request failed (exit code " + exitCode + ")"
        console.warn("SystemStatsService:", root.processActionError)
      }
      root.refreshProcesses()
    }
  }

  function handleStats(output) {
    const nextCores = []
    const memory = ({})
    for (const line of String(output).split(/\r?\n/)) {
      const parts = line.trim().split(/\s+/)
      if (parts[0] === "CPU" && parts.length >= 5) {
        const name = parts[1]
        const counters = parts.slice(2).map(Number)
        if (counters.some(value => !Number.isFinite(value)))
          continue
        const total = counters.slice(0, 8).reduce((sum, value) => sum + value, 0)
        const idle = (counters[3] || 0) + (counters[4] || 0)
        const previous = root._prevCpuCounters[name]
        let usage = root.cpuUsage
        if (previous && total > previous.total) {
          const deltaTotal = total - previous.total
          const deltaIdle = idle - previous.idle
          usage = Math.min(100, Math.max(0, (deltaTotal - deltaIdle) / deltaTotal * 100))
        }
        root._prevCpuCounters[name] = { total: total, idle: idle }
        if (name === "cpu")
          root.cpuUsage = usage
        else if (/^cpu\d+$/.test(name))
          nextCores.push({ name: name, index: Number(name.slice(3)), usage: usage })
      } else if (parts[0] === "MEM" && parts.length >= 3) {
        memory[parts[1].replace(":", "")] = Number(parts[2])
      } else if (parts[0] === "MODEL") {
        root.cpuModel = parts.slice(1).join(" ")
      } else if (parts[0] === "CORES") {
        root.cpuCoreCount = Number(parts[1]) || nextCores.length
      } else if (parts[0] === "TEMP") {
        const temperature = Number(parts[1])
        if (temperature > 0)
          root.cpuTemperature = temperature
      }
    }

    root.perCoreCpuUsage = nextCores.sort((a, b) => a.index - b.index)
    const totalKB = memory.MemTotal || 0
    const availableKB = memory.MemAvailable || 0
    if (totalKB > 0) {
      const usedKB = Math.max(0, totalKB - availableKB)
      root.memAvailableKB = availableKB
      root.memFreeKB = memory.MemFree || 0
      root.memBuffersKB = memory.Buffers || 0
      root.memCachedKB = Math.max(0, (memory.Cached || 0) + (memory.SReclaimable || 0) - (memory.Shmem || 0))
      root.memoryUsage = Math.min(100, Math.max(0, usedKB / totalKB * 100))
      root.memUsedText = root._fmtKB(usedKB)
      root.memTotalText = root._fmtKB(totalKB)
      if (root.overviewActive) {
        root.memoryHistory = root.memoryHistory.concat([root.memoryUsage]).slice(-60)
        root.cpuHistory = root.cpuHistory.concat([root.cpuUsage]).slice(-60)
      }
    }

    root.swapTotalKB = memory.SwapTotal || 0
    root.swapUsedKB = Math.max(0, root.swapTotalKB - (memory.SwapFree || 0))
    root.swapUsage = root.swapTotalKB > 0 ? root.swapUsedKB / root.swapTotalKB * 100 : 0
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
    interval: root.overviewActive ? 1000 : 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  property Timer processPollTimer: Timer {
    interval: 2000
    repeat: true
    running: root.overviewActive
    triggeredOnStart: true
    onTriggered: root.refreshProcesses()
  }

  property Timer gpuPollTimer: Timer {
    interval: root.overviewActive ? 2000 : 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshGpu()
  }

  property Timer diskPollTimer: Timer {
    interval: 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshDisk()
  }
}
