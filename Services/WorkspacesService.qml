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
    switchProc.command = ["hyprctl", "dispatch", "workspace", String(id)]
    switchProc.running = true
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
