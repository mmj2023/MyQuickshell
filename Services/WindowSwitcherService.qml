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
  property var sessionWorkspaceId: NaN
  property string sessionSpecialWorkspaceName: ""
  property bool startedOnSpecialWorkspace: false
  property var regularWindows: []
  property var specialWorkspaceGroups: []
  property string viewMode: "top"
  property string expandedSpecialWorkspaceName: ""
  property var expandedRegularWorkspaceId: NaN
  property var windows: []
  property int selectedIndex: -1
  property var recentAddresses: []
  readonly property string viewTitle: root.viewMode === "specialWorkspace"
    ? root.specialWorkspaceLabel(root.expandedSpecialWorkspaceName)
    : root.viewMode === "regularWorkspace"
      ? qsTr("Workspace %1").arg(Number.isFinite(root.expandedRegularWorkspaceId)
        ? root.expandedRegularWorkspaceId : qsTr("current"))
      : qsTr("Window Switcher")
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

  function normalizeSpecialWorkspaceName(value, allowBareName) {
    let name = value && typeof value === "object" ? value.name : value
    name = String(name || "")
    if (name === "special" || name.startsWith("special:"))
      return name
    if (allowBareName && name)
      return "special:" + name
    return ""
  }

  function specialWorkspaceName(window) {
    return root.normalizeSpecialWorkspaceName(window?.workspace?.name)
  }

  function specialWorkspaceLabel(name) {
    return name === "special" ? qsTr("special")
      : String(name).slice("special:".length)
  }

  function isSpecialWorkspace(window) {
    return root.specialWorkspaceName(window) !== ""
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

  function sortByPosition(windows) {
    return windows.slice().sort(function(first, second) {
      const firstPositioned = Number.isFinite(first.positionX)
        && Number.isFinite(first.positionY)
      const secondPositioned = Number.isFinite(second.positionX)
        && Number.isFinite(second.positionY)
      if (firstPositioned !== secondPositioned)
        return firstPositioned ? -1 : 1
      if (firstPositioned) {
        if (first.positionY !== second.positionY)
          return first.positionY - second.positionY
        if (first.positionX !== second.positionX)
          return first.positionX - second.positionX
      }

      const firstIndex = root.recentAddresses.indexOf(first.address)
      const secondIndex = root.recentAddresses.indexOf(second.address)
      if (firstIndex < 0 && secondIndex < 0)
        return 0
      if (firstIndex < 0)
        return 1
      if (secondIndex < 0)
        return -1
      return firstIndex - secondIndex
    })
  }

  function sortByRecency(windows) {
    return windows.slice().sort(function(first, second) {
      const firstIndex = root.recentAddresses.indexOf(first.address)
      const secondIndex = root.recentAddresses.indexOf(second.address)
      if (firstIndex < 0 && secondIndex < 0)
        return 0
      if (firstIndex < 0)
        return 1
      if (secondIndex < 0)
        return -1
      return firstIndex - secondIndex
    })
  }

  function sortByRecencyThenPosition(windows) {
    const ordered = root.sortByPosition(windows)
    const recentWindows = []
    for (const address of root.recentAddresses) {
      const recentIndex = ordered.findIndex(window => window.address === address)
      if (recentIndex >= 0)
        recentWindows.push(ordered.splice(recentIndex, 1)[0])
      if (recentWindows.length === 2)
        break
    }
    return recentWindows.concat(ordered)
  }

  function orderApplicationWindows(windows) {
    return root.visible
      ? root.sortByRecencyThenPosition(windows)
      : root.sortByRecency(windows)
  }

  function selectionKey(item) {
    if (!item)
      return ""
    if (item.type === "specialWorkspace")
      return "special:" + item.workspaceName
    if (item.type === "regularWorkspace")
      return "workspace:" + item.workspaceId
    return "window:" + item.address
  }

  function sameWorkspaceId(first, second) {
    const firstId = Number(first)
    const secondId = Number(second)
    if (Number.isFinite(firstId) && Number.isFinite(secondId))
      return firstId === secondId
    return String(first) === String(second)
  }

  function isGroupItem(item) {
    return !!item && (item.type === "specialWorkspace"
      || item.type === "regularWorkspace")
  }

  function collectWindows(monitorNameOverride, workspaceIdOverride) {
    const activeMonitor = Hyprland.focusedMonitor
    const activeWindow = Hyprland.activeToplevel
    const isSessionRefresh = monitorNameOverride !== undefined
    const monitorName = isSessionRefresh
      ? String(monitorNameOverride)
      : String(activeMonitor?.name || activeWindow?.monitor?.name || "")
    const activeWorkspace = activeMonitor?.activeWorkspace
      || (activeWindow
        && String(activeWindow.monitor?.name || "") === monitorName
        ? activeWindow.workspace : null)
    const workspaceId = isSessionRefresh
      ? Number(workspaceIdOverride)
      : activeWorkspace ? Number(activeWorkspace.id) : NaN
    let activeSpecialWorkspaceName = isSessionRefresh
      ? root.sessionSpecialWorkspaceName
      : root.normalizeSpecialWorkspaceName(
        activeMonitor?.activeSpecialWorkspace, true)
    if (!activeSpecialWorkspaceName && activeWindow
        && String(activeWindow.monitor?.name || "") === monitorName) {
      activeSpecialWorkspaceName = root.specialWorkspaceName(activeWindow)
    }
    const windows = Array.from(Hyprland.toplevels?.values || [])
      .filter(function(window) {
        return !!window.wayland
          && (!monitorName || String(window.monitor?.name || "") === monitorName)
          && (root.isSpecialWorkspace(window)
            || !Number.isFinite(workspaceId)
            || Number(window.workspace?.id) === workspaceId)
      })
      .map(function(window) {
        const wayland = window.wayland
        const client = window.lastIpcObject || {}
        const position = client.at
        return {
          type: "window",
          address: root.addressOf(window),
          window: wayland,
          title: String(wayland.title || window.title || wayland.appId || qsTr("Application")),
          appId: String(wayland.appId || ""),
          workspaceId: Number(window.workspace?.id),
          specialWorkspaceName: root.specialWorkspaceName(window),
          positionX: position && position.length > 0
            ? Number(position[0]) : NaN,
          positionY: position && position.length > 1
            ? Number(position[1]) : NaN
        }
      })

    return {
      monitorName: monitorName,
      workspaceId: workspaceId,
      activeSpecialWorkspaceName: activeSpecialWorkspaceName,
      windows: root.sortByRecency(windows)
    }
  }

  function createSpecialWorkspaceGroups(windows) {
    const groups = []
    for (const window of windows) {
      if (!window.specialWorkspaceName)
        continue
      let group = groups.find(
        candidate => candidate.workspaceName === window.specialWorkspaceName)
      if (!group) {
        group = {
          workspaceName: window.specialWorkspaceName,
          windows: []
        }
        groups.push(group)
      }
      group.windows.push(window)
    }

    return groups.map(function(group) {
      const groupWindows = root.orderApplicationWindows(group.windows)
      const label = group.workspaceName === "special"
        ? qsTr("special")
        : group.workspaceName.slice("special:".length)
      return {
        type: "specialWorkspace",
        workspaceName: group.workspaceName,
        title: qsTr("%1 · %2 apps").arg(label).arg(groupWindows.length),
        appId: groupWindows[0].appId,
        window: groupWindows[0].window,
        windows: groupWindows
      }
    })
  }

  function baseSessionItems() {
    if (!root.startedOnSpecialWorkspace)
      return root.regularWindows.slice()

    const currentGroup = root.specialWorkspaceGroups.find(
      group => group.workspaceName === root.sessionSpecialWorkspaceName)
    const items = currentGroup ? currentGroup.windows.slice() : []
    if (root.regularWindows.length === 1 || root.regularWindows.length === 2) {
      for (const window of root.regularWindows)
        items.push(window)
    } else if (root.regularWindows.length > 2) {
      const firstWindow = root.regularWindows[0]
      const workspaceOption = {
        type: "regularWorkspace",
        workspaceId: root.sessionWorkspaceId,
        title: qsTr("Workspace %1 · %2 apps")
          .arg(Number.isFinite(root.sessionWorkspaceId)
            ? root.sessionWorkspaceId : qsTr("current"))
          .arg(root.regularWindows.length),
        appId: firstWindow.appId,
        window: firstWindow.window,
        windows: root.regularWindows
      }
      return root.orderApplicationWindows(items).concat([workspaceOption])
    }
    return root.orderApplicationWindows(items)
  }

  function topLevelItems() {
    const items = root.baseSessionItems()
    if (!root.overlayLatched)
      return items

    for (const group of root.specialWorkspaceGroups) {
      if (root.startedOnSpecialWorkspace
          && group.workspaceName === root.sessionSpecialWorkspaceName)
        continue
      items.push(group)
    }
    return items
  }

  function rebuildVisibleItems(preferredKey) {
    const key = preferredKey || root.selectionKey(root.windows[root.selectedIndex])
    if (root.viewMode === "specialWorkspace") {
      const group = root.specialWorkspaceGroups.find(
        candidate => candidate.workspaceName === root.expandedSpecialWorkspaceName)
      if (!group || group.windows.length === 0) {
        root.viewMode = "top"
        root.expandedSpecialWorkspaceName = ""
      } else {
        root.windows = group.windows
      }
    } else if (root.viewMode === "regularWorkspace") {
      if (!root.sameWorkspaceId(
            root.expandedRegularWorkspaceId, root.sessionWorkspaceId)
          || root.regularWindows.length === 0) {
        root.viewMode = "top"
        root.expandedRegularWorkspaceId = NaN
      } else {
        root.windows = root.regularWindows
      }
    }

    if (root.viewMode === "top")
      root.windows = root.topLevelItems()

    const foundIndex = root.windows.findIndex(
      item => root.selectionKey(item) === key)
    root.selectedIndex = foundIndex >= 0
      ? foundIndex : Math.max(0, Math.min(root.selectedIndex, root.windows.length - 1))
  }

  function refreshSessionWindows() {
    const preferredKey = root.selectionKey(root.windows[root.selectedIndex])
    const collected = root.collectWindows(root.monitorName, root.sessionWorkspaceId)
    root.regularWindows = root.orderApplicationWindows(collected.windows.filter(
      window => !window.specialWorkspaceName
        && (!Number.isFinite(root.sessionWorkspaceId)
          || window.workspaceId === Number(root.sessionWorkspaceId))))
    root.specialWorkspaceGroups = root.createSpecialWorkspaceGroups(
      collected.windows.filter(window => !!window.specialWorkspaceName))
    root.rebuildVisibleItems(preferredKey)
  }

  function startSession(collected, activeAddress, direction) {
    root.monitorName = collected.monitorName
    root.sessionWorkspaceId = collected.workspaceId
    root.sessionSpecialWorkspaceName = collected.activeSpecialWorkspaceName
    root.regularWindows = root.orderApplicationWindows(collected.windows.filter(
      window => !window.specialWorkspaceName
        && (!Number.isFinite(collected.workspaceId)
          || window.workspaceId === Number(collected.workspaceId))))
    root.specialWorkspaceGroups = root.createSpecialWorkspaceGroups(
      collected.windows.filter(window => !!window.specialWorkspaceName))
    root.startedOnSpecialWorkspace = !!root.sessionSpecialWorkspaceName
      && root.specialWorkspaceGroups.some(
        group => group.workspaceName === root.sessionSpecialWorkspaceName)
    root.viewMode = "top"
    root.expandedSpecialWorkspaceName = ""
    root.overlayLatched = false
    root.windows = root.baseSessionItems()
    if (root.windows.length === 0 && root.specialWorkspaceGroups.length === 0)
      return false

    const activeIndex = root.windows.findIndex(item =>
      item.type === "window" && item.address === activeAddress)
    root.selectedIndex = root.windows.length === 0 ? -1
      : activeIndex < 0
        ? (direction > 0 ? 0 : root.windows.length - 1)
        : (activeIndex + direction + root.windows.length) % root.windows.length
    root.initialAddress = activeAddress
    root.lastActivatedAddress = activeAddress
    root.sessionActive = true
    return true
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

    let startedSession = false
    if (!root.sessionActive) {
      const collected = root.collectWindows()
      if (collected.windows.length === 0)
        return false
      startedSession = true
      const activeAddress = root.addressOf(Hyprland.activeToplevel)
      if (!root.startSession(collected, activeAddress, direction))
        return false
      root.altHeld = !altWasReleased
      if (!completeAfterCycle && !completeAfterRelease && root.altHeld)
        overlayActivationTimer.restart()
    } else {
      root.refreshSessionWindows()
      if (root.windows.length === 0) {
        if (root.specialWorkspaceGroups.length > 0 && !root.overlayLatched)
          return true
        root.cancel()
        return false
      }

      root.selectedIndex = (root.selectedIndex + direction + root.windows.length)
        % root.windows.length
    }

    if (completeAfterCycle || completeAfterRelease)
      root.commit()
    else if (!startedSession && !root.visible
        && !root.isGroupItem(root.windows[root.selectedIndex]))
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

    const selectedKey = root.selectionKey(root.windows[root.selectedIndex])
    root.overlayLatched = true
    root.altReleasedWhileLatched = false
    root.altPressedAfterLatch = false
    root.rebuildVisibleItems(selectedKey)
  }

  function enterSelectedGroup() {
    const selected = root.windows[root.selectedIndex]
    if (!root.isGroupItem(selected))
      return false

    let groupWindows = []
    if (selected.type === "specialWorkspace") {
      const group = root.specialWorkspaceGroups.find(
        candidate => candidate.workspaceName === selected.workspaceName)
      groupWindows = group ? group.windows : []
      root.expandedSpecialWorkspaceName = selected.workspaceName
      root.expandedRegularWorkspaceId = NaN
      root.viewMode = "specialWorkspace"
    } else {
      if (!root.sameWorkspaceId(selected.workspaceId, root.sessionWorkspaceId))
        return false
      groupWindows = root.regularWindows
      root.expandedSpecialWorkspaceName = ""
      root.expandedRegularWorkspaceId = selected.workspaceId
      root.viewMode = "regularWorkspace"
    }
    if (groupWindows.length === 0)
      return false

    root.windows = groupWindows
    const activeAddress = root.addressOf(Hyprland.activeToplevel)
    const activeIndex = root.windows.findIndex(
      item => item.address === activeAddress)
    root.selectedIndex = activeIndex >= 0 ? activeIndex : 0
    return true
  }

  function handleEnter() {
    if (root.isGroupItem(root.windows[root.selectedIndex]))
      root.enterSelectedGroup()
    else
      root.commit()
  }

  function handleEscape() {
    if (root.viewMode === "specialWorkspace"
        || root.viewMode === "regularWorkspace") {
      const selectedGroupKey = root.viewMode === "specialWorkspace"
        ? "special:" + root.expandedSpecialWorkspaceName
        : "workspace:" + root.expandedRegularWorkspaceId
      root.viewMode = "top"
      root.expandedSpecialWorkspaceName = ""
      root.expandedRegularWorkspaceId = NaN
      root.rebuildVisibleItems(selectedGroupKey)
      return
    }

    if (root.overlayLatched
        && !root.isGroupItem(root.windows[root.selectedIndex]))
      root.commit()
    else
      root.cancel()
  }

  function cancel(restoreInitial) {
    const selected = root.windows[root.selectedIndex]
    const selectedAddress = selected?.type === "window" ? selected.address : ""
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
    root.sessionWorkspaceId = NaN
    root.sessionSpecialWorkspaceName = ""
    root.startedOnSpecialWorkspace = false
    root.regularWindows = []
    root.specialWorkspaceGroups = []
    root.viewMode = "top"
    root.expandedSpecialWorkspaceName = ""
    root.expandedRegularWorkspaceId = NaN
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
    if (!selected || root.isGroupItem(selected)
        || (!force && selected.address === root.lastActivatedAddress)
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
    if (root.isGroupItem(root.windows[root.selectedIndex])) {
      root.enterSelectedGroup()
      return
    }
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
      if (root.sessionActive && root.altHeld && !root.visible) {
        root.visible = true
        root.refreshSessionWindows()
      }
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
