pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Services

Singleton {
  id: root

  property bool visible: false
  property bool sessionActive: false
  property string initialAddress: ""
  property string lastActivatedAddress: ""
  property int activationGeneration: 0
  property string monitorName: ""
  property var windows: []
  property int selectedIndex: -1
  property var recentAddresses: []
  property bool switcherKeyReleasedWhileAltHeld: false
  property bool switcherKeyReleasedAfterAlt: false
  property bool overlayLatched: false
  property bool altReleasedWhileLatched: false
  property bool altPressedAfterLatch: false
  property bool altReleased: false
  property bool altHeld: false
  property bool waitingForSwitcherKeyRelease: false
  readonly property int switcherReleaseGraceMs: 150
  readonly property int overlayActivationDelayMs: switcherReleaseGraceMs + 1

  Timer {
    id: overlayActivationTimer
    interval: root.overlayActivationDelayMs
    repeat: false
    onTriggered: root.confirmAltHeld()
  }

  Timer {
    id: switcherReleaseTimer
    interval: root.switcherReleaseGraceMs
    repeat: false
    onTriggered: {
      root.waitingForSwitcherKeyRelease = false
      if (!root.sessionActive) {
        root.altReleased = false
        root.altHeld = false
        root.switcherKeyReleasedWhileAltHeld = false
        root.switcherKeyReleasedAfterAlt = false
      }
    }
  }

  function addressOf(window) {
    return window && window.address !== undefined
      ? String(window.address).toLowerCase() : ""
  }

  function rememberActiveWindow() {
    const address = root.addressOf(Hyprland.activeToplevel)
    if (!address)
      return

    const next = [address]
    for (const previous of root.recentAddresses) {
      if (previous !== address && next.length < 128)
        next.push(previous)
    }
    root.recentAddresses = next
  }

  function collectWindows() {
    const activeMonitor = Hyprland.focusedMonitor
    const activeWindow = Hyprland.activeToplevel
    const monitorName = String(activeMonitor?.name || activeWindow?.monitor?.name || "")
    const activeWorkspace = activeWindow
      && String(activeWindow.monitor?.name || "") === monitorName
      ? activeWindow.workspace : activeMonitor?.activeWorkspace
    const workspaceId = activeWorkspace ? Number(activeWorkspace.id) : NaN
    const windows = Array.from(Hyprland.toplevels?.values || [])
      .filter(function(window) {
        return !!window.wayland
          && (!monitorName || String(window.monitor?.name || "") === monitorName)
          && (!Number.isFinite(workspaceId)
            || Number(window.workspace?.id) === workspaceId)
      })
      .map(function(window) {
        const wayland = window.wayland
        return {
          address: root.addressOf(window),
          window: wayland,
          title: String(wayland.title || window.title || wayland.appId || qsTr("Application")),
          appId: String(wayland.appId || "")
        }
      })

    const recent = root.recentAddresses
    windows.sort(function(first, second) {
      const firstIndex = recent.indexOf(first.address)
      const secondIndex = recent.indexOf(second.address)
      if (firstIndex < 0 && secondIndex < 0)
        return 0
      if (firstIndex < 0)
        return 1
      if (secondIndex < 0)
        return -1
      return firstIndex - secondIndex
    })
    return { monitorName: monitorName, windows: windows }
  }

  function keepSessionWindowOrder(currentWindows) {
    const ordered = []
    for (const previous of root.windows) {
      const current = currentWindows.find(
        window => window.address === previous.address)
      if (current)
        ordered.push(current)
    }

    for (const current of currentWindows) {
      if (!ordered.some(window => window.address === current.address))
        ordered.push(current)
    }
    return ordered
  }

  function cycle(direction, fromSwitcherKey) {
    const completeAfterCycle = fromSwitcherKey
      && root.altReleased
      && root.waitingForSwitcherKeyRelease
      && switcherReleaseTimer.running
    const completeAfterRelease = fromSwitcherKey && root.switcherKeyReleasedAfterAlt
    const altWasReleased = root.altReleased

    root.switcherKeyReleasedWhileAltHeld = false
    root.switcherKeyReleasedAfterAlt = false
    root.altReleased = false
    root.waitingForSwitcherKeyRelease = false
    switcherReleaseTimer.stop()

    const collected = root.collectWindows()
    const activeAddress = root.addressOf(Hyprland.activeToplevel)
    let startedSession = false
    let nextIndex

    if (!root.sessionActive) {
      if (collected.windows.length === 0)
        return false
      startedSession = true
      const activeIndex = collected.windows.findIndex(
        window => window.address === activeAddress)
      nextIndex = activeIndex < 0
        ? (direction > 0 ? 0 : collected.windows.length - 1)
        : (activeIndex + direction + collected.windows.length)
          % collected.windows.length
      root.monitorName = collected.monitorName
      root.windows = collected.windows
      root.initialAddress = activeAddress
      root.lastActivatedAddress = activeAddress
      root.sessionActive = true
      root.altHeld = !altWasReleased
      if (!completeAfterCycle && !completeAfterRelease && root.altHeld)
        overlayActivationTimer.restart()
    } else {
      if (collected.windows.length === 0) {
        root.cancel()
        return false
      }

      const orderedWindows = root.keepSessionWindowOrder(collected.windows)
      const selectedAddress = root.windows[root.selectedIndex]?.address || ""
      const previousIndex = orderedWindows.findIndex(
        window => window.address === selectedAddress)
      const baseIndex = previousIndex >= 0
        ? previousIndex : Math.max(0, Math.min(root.selectedIndex, orderedWindows.length - 1))
      nextIndex = (baseIndex + direction + orderedWindows.length)
        % orderedWindows.length
      root.windows = orderedWindows
    }

    root.selectedIndex = nextIndex
    if (completeAfterCycle || completeAfterRelease)
      root.commit()
    else if (!startedSession && !root.overlayLatched)
      root.activateSelected()
    return true
  }

  function handleSwitcherKeyRelease() {
    if (root.altReleased) {
      if (!root.waitingForSwitcherKeyRelease)
        return
      if (!root.visible) {
        root.switcherKeyReleasedAfterAlt = true
        return
      }
      root.waitingForSwitcherKeyRelease = false
      switcherReleaseTimer.stop()
      root.commit()
      return
    }

    root.switcherKeyReleasedWhileAltHeld = true
  }

  function handleAltRelease() {
    if (!root.sessionActive && !root.altHeld)
      return

    if (root.overlayLatched) {
      root.altReleased = true
      root.altHeld = false
      if (root.altPressedAfterLatch) {
        root.commit()
      } else {
        root.altReleasedWhileLatched = true
      }
      return
    }

    root.altReleased = true
    root.altHeld = false
    overlayActivationTimer.stop()

    if (root.sessionActive) {
      root.commit()
      return
    }

    if (root.switcherKeyReleasedWhileAltHeld) {
      root.switcherKeyReleasedAfterAlt = true
    }

    root.waitingForSwitcherKeyRelease = true
    switcherReleaseTimer.restart()
  }

  function handleAltPress() {
    if (root.overlayLatched && root.altReleasedWhileLatched) {
      root.altPressedAfterLatch = true
      root.altReleased = false
      root.altHeld = true
    }
  }

  function latchOverlay() {
    if (!root.visible || !root.sessionActive || root.overlayLatched)
      return

    root.overlayLatched = true
    root.altReleasedWhileLatched = false
    root.altPressedAfterLatch = false
  }

  function cancel(restoreInitial) {
    const selectedAddress = root.windows[root.selectedIndex]?.address || ""
    if (restoreInitial !== false)
      root.activationGeneration += 1

    if (restoreInitial !== false && root.sessionActive && root.initialAddress
        && selectedAddress !== root.initialAddress) {
      const initialWindow = Array.from(Hyprland.toplevels?.values || [])
        .find(window => root.addressOf(window) === root.initialAddress)?.wayland
      if (initialWindow && typeof initialWindow.activate === "function") {
        const generation = root.activationGeneration
        Qt.callLater(function() {
          if (generation === root.activationGeneration)
            initialWindow.activate()
        })
      }
    }

    overlayActivationTimer.stop()
    switcherReleaseTimer.stop()
    root.visible = false
    root.sessionActive = false
    root.initialAddress = ""
    root.lastActivatedAddress = ""
    root.altHeld = false
    root.windows = []
    root.selectedIndex = -1
    root.monitorName = ""
    root.switcherKeyReleasedWhileAltHeld = false
    root.switcherKeyReleasedAfterAlt = false
    root.overlayLatched = false
    root.altReleasedWhileLatched = false
    root.altPressedAfterLatch = false
    root.altReleased = false
    root.waitingForSwitcherKeyRelease = false
  }

  function activateSelected(force) {
    const selected = root.windows[root.selectedIndex]
    if (!selected || (!force && selected.address === root.lastActivatedAddress)
        || !selected.window || typeof selected.window.activate !== "function")
      return

    root.lastActivatedAddress = selected.address
    const window = selected.window
    root.activationGeneration += 1
    const generation = root.activationGeneration
    Qt.callLater(function() {
      if (generation === root.activationGeneration)
        window.activate()
    })
  }

  function commit() {
    root.activateSelected(true)
    root.cancel(false)
  }

  function confirmAltHeld() {
    if (!root.sessionActive)
      return

    const showCommand = root.luaString(root.ipcCommand("displayOverlay"))
    const finishCommand = root.luaString(root.ipcCommand("finish"))
    root.dispatchLua("if hl.is_key_down('Alt_L') or hl.is_key_down('Alt_R') then "
      + "hl.exec_cmd(" + showCommand + ") "
      + "else hl.exec_cmd(" + finishCommand + ") end")
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function ipcCommand(action) {
    return "qs -p " + root.shellQuote(Quickshell.shellDir)
      + " ipc call window-switcher " + action
  }

  function luaString(value) {
    return JSON.stringify(String(value))
  }

  function dispatchLua(statement) {
    Hyprland.dispatch("function() " + statement + " end")
  }

  function unbind(combo) {
    root.dispatchLua("hl.unbind(" + root.luaString(combo) + ")")
  }

  function bind(combo, action, description, flags) {
    const command = root.ipcCommand(action)
    root.dispatchLua("hl.bind("
      + root.luaString(combo)
      + ", hl.dsp.exec_cmd(" + root.luaString(command) + ")"
      + ", { " + flags + ", description = "
      + root.luaString(description) + " })")
  }

  function forceLoadKeybindings() {
    if (WorkspacesService.backend !== "hyprland")
      return

    const hyprshellBindings = [
      "ALT + Tab",
      "ALT + SHIFT + Tab",
      "ALT + grave",
      "ALT + Alt_L",
      "ALT + Alt_R",
      "SHIFT + Shift_L",
      "SHIFT + Shift_R"
    ]
    for (const combo of hyprshellBindings)
      root.unbind(combo)

    root.bind("ALT + Tab", "next", "MyQuickshell window switcher", "auto_consuming = true")
    root.bind("ALT + SHIFT + Tab", "previous", "MyQuickshell window switcher (reverse)", "auto_consuming = true")
    root.bind("ALT + grave", "previous", "MyQuickshell window switcher (reverse)", "auto_consuming = true")
    root.bind("ALT + Tab", "switcherKeyReleased", "Window switcher key released", "release = true, transparent = true")
    root.bind("ALT + SHIFT + Tab", "switcherKeyReleased", "Window switcher key released", "release = true, transparent = true")
    root.bind("ALT + grave", "switcherKeyReleased", "Window switcher key released", "release = true, transparent = true")
    root.bind("ALT + Alt_L", "release", "Select window and close switcher", "release = true, auto_consuming = true, transparent = true")
    root.bind("ALT + Alt_R", "release", "Select window and close switcher", "release = true, auto_consuming = true, transparent = true")
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      root.rememberActiveWindow()
    }
  }

  Component.onCompleted: {
    root.rememberActiveWindow()
    root.forceLoadKeybindings()
  }

  Component.onDestruction: {
    overlayActivationTimer.stop()
    switcherReleaseTimer.stop()
    const bindings = [
      "ALT + Tab",
      "ALT + SHIFT + Tab",
      "ALT + grave",
      "ALT + Alt_L",
      "ALT + Alt_R"
    ]
    for (const combo of bindings)
      root.unbind(combo)
  }

  IpcHandler {
    target: "window-switcher"

    function next(): string {
      root.cycle(1, true)
      return "Advanced window switcher selection"
    }

    function previous(): string {
      root.cycle(-1, true)
      return "Reversed window switcher selection"
    }

    function release(): string {
      root.handleAltRelease()
      return "Handled window switcher modifier release"
    }

    function displayOverlay(): string {
      if (root.sessionActive && root.altHeld)
        root.visible = true
      return "Showed window switcher"
    }

    function finish(): string {
      if (root.sessionActive)
        root.commit()
      return "Finished window switcher"
    }

    function switcherKeyReleased(): string {
      root.handleSwitcherKeyRelease()
      return "Handled window switcher key release"
    }

    function cancel(): string {
      root.cancel()
      return "Cancelled window switcher"
    }
  }
}
