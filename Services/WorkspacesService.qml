pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Compositor-agnostic workspace state.
//
// The bar binds to this one interface instead of reaching into any specific
// compositor. The current implementation shells out to hyprctl (Hyprland), the
// same approach the Omarchy shell relies on, and yields data through a small
// sink-shaped surface:
//   workspaceIds   - every workspace id present in the layout (sorted)
//   occupiedIds    - workspaces that currently have a window open
//   activeWorkspaceId(name) - active workspace id for a monitor, by name
//   switchTo(id)   - focus a workspace
//
// A Niri/I3/generic backend can later implement the same surface without the
// bar changing. When no workspaces are reported the bar simply renders empty.
QtObject {
  id: root

  property var workspaceIds: []
  property var occupiedIds: []

  // Active workspace id per monitor name, refreshed from hyprctl.
  property var activeByMonitor: ({})
  readonly property string desktop: (Quickshell.env("XDG_CURRENT_DESKTOP") || Quickshell.env("DESKTOP_SESSION") || "").toLowerCase()
  readonly property string backend: desktop.indexOf("niri") !== -1 ? "niri"
    : (desktop.indexOf("hypr") !== -1 ? "hyprland"
    : (desktop.indexOf("mango") !== -1 ? "mango"
    : (desktop.indexOf("dwl") !== -1 ? "dwl"
    : (desktop.indexOf("labwc") !== -1 ? "labwc" : "hyprland"))))

  function activeWorkspaceId(monitorName) {
    var v = activeByMonitor[monitorName]
    return v === undefined ? 0 : v
  }

  function refreshAll() {
    listProc.running = true
    monitorsProc.running = true
  }

  property Process listProc: Process {
    id: listProc
    command: ["hyprctl", "-j", "workspaces"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleWorkspaces(text)
    }
  }

  function handleWorkspaces(raw) {
    var ids = []
    var occupied = []
    try {
      var arr = JSON.parse(String(raw || ""))
      if (Array.isArray(arr)) {
        for (var i = 0; i < arr.length; i++) {
          var w = arr[i]
          if (w.id === undefined || w.id < 1) continue
          if (ids.indexOf(w.id) === -1) ids.push(w.id)
          occupied.push(w.id)
        }
      }
    } catch (e) { }
    ids.sort(function(a, b) { return a - b })
    workspaceIds = ids
    occupiedIds = occupied
  }

  property Process monitorsProc: Process {
    id: monitorsProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleMonitors(text)
    }
  }

  function handleMonitors(raw) {
    var byMonitor = {}
    try {
      var arr = JSON.parse(String(raw || ""))
      if (Array.isArray(arr)) {
        for (var i = 0; i < arr.length; i++) {
          var m = arr[i]
          var name = String(m.name || "")
          var active = m.activeWorkspace ? m.activeWorkspace.id : 0
          if (name) byMonitor[name] = active
        }
      }
    } catch (e) { }
    activeByMonitor = byMonitor
  }

  function switchTo(id) {
    if (!id) return
    switchProc.command = switchCommand(id)
    switchProc.running = true
  }

  function switchCommand(id) {
    const workspace = String(id)
    switch (root.backend) {
    case "niri": return ["niri", "msg", "action", "focus-workspace", workspace]
    case "mango": return ["mmsg", "-d", "workspace", workspace]
    case "dwl": return ["dwlmsg", "-s", "view", workspace]
    case "labwc": return ["wlrctl", "window", "switch-to-workspace", workspace]
    // Hyprland 0.56+ exposes dispatchers through its Lua API. Keep the
    // command as one argument so hyprctl does not parse the workspace number
    // as a Lua token.
    default: return ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + workspace + " })"]
    }
  }

  property Process switchProc: Process {
    id: switchProc
    command: ["hyprctl", "dispatch", "workspace"]
  }

  property Timer refreshTimer: Timer {
    id: refreshTimer
    interval: 100
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshAll()
  }
}
