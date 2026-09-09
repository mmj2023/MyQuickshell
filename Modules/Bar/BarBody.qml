import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Modules.Bar.Widgets

// The bar's visual body: a transparent canvas laying out bar widgets into
// left / center / right groups, driven by the SettingsData widget lists.
// Widgets that have no component yet are skipped. Each widget id maps to an
// inline Component over the registered widget type. The bar surface wraps this
// and supplies the screen.
Item {
  id: root

  property QtObject screen: null
  property QtObject barWindow: null

  readonly property int spacing: typeof SettingsData !== "undefined" ? SettingsData.barSpacing : 0
  readonly property int innerPadding: typeof SettingsData !== "undefined" ? SettingsData.barInnerPadding : 0

  Component { id: launcherButtonComp; LauncherButton {} }
  Component { id: submapComp; SubmapWidget {} }
  Component { id: workspaceSwitcherComp; WorkspacesWidget {} }
  Component { id: runningAppsComp; RunningAppsWidget {} }
  Component { id: focusedWindowComp; FocusedWindowWidget {} }
  Component { id: clockComp; ClockWidget {} }
  Component { id: systemTrayComp; SystemTrayWidget {} }
  Component { id: cpuUsageComp; CpuWidget {} }
  Component { id: cpuTemperatureComp; TemperatureWidget {} }
  Component { id: memUsageComp; RamWidget {} }
  Component { id: diskUsageComp; DiskWidget {} }
  Component { id: batteryComp; BatteryWidget {} }

  function registryFor(id) {
    switch (id) {
    case "launcherButton": return launcherButtonComp
    case "submap": return submapComp
    case "workspaceSwitcher": return workspaceSwitcherComp
    case "runningApps": return runningAppsComp
    case "focusedWindow": return focusedWindowComp
    case "clock": return clockComp
    case "systemTray": return systemTrayComp
    case "cpuUsage": return cpuUsageComp
    case "cpuTemperature": return cpuTemperatureComp
    case "memUsage": return memUsageComp
    case "diskUsage": return diskUsageComp
    case "battery": return batteryComp
    default: return null
    }
  }

  property var _created: []

  function fillRow(list, hostRow) {
    if (!list) return
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (!entry || entry.enabled !== true) continue
      var comp = root.registryFor(entry.id)
      if (comp === null) { console.error("MQBAR skip (no comp):", entry.id); continue }
      var obj = comp.createObject(hostRow, {
        "screen": root.screen,
        "parentScreen": root.screen,
        "barWindow": root.barWindow
      })
      root._created.push(obj)
      console.error("MQBAR created:", entry.id, "parent=", hostRow.objectName, "w=", obj.width, "h=", obj.height, "vis=", obj.visible)
    }
  }

  function rebuild() {
    for (var i = 0; i < root._created.length; i++) {
      root._created[i].destroy()
    }
    root._created = []
    root.fillRow(SettingsData.barLeftWidgets, leftRow)
    root.fillRow(SettingsData.barCenterWidgets, centerRow)
    root.fillRow(SettingsData.barRightWidgets, rightRow)
    console.error("MQBAR done. leftRow children=", leftRow.data.length, "centerRow children=", centerRow.data.length, "rightRow children=", rightRow.data.length)
    console.error("MQBAR leftRow w=", leftRow.width, "centerRow w=", centerRow.width, "rightRow w=", rightRow.width)
  }

  Component.onCompleted: {
    root.rebuild()
  }

  Connections {
    target: SettingsData
    function onSettingsApplied() {
      root.rebuild()
    }
  }

  Row {
    id: leftRow
    anchors.left: parent.left
    anchors.leftMargin: Math.max(0, root.innerPadding)
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.spacing
  }

  Row {
    id: centerRow
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.spacing
  }

  Row {
    id: rightRow
    anchors.right: parent.right
    anchors.rightMargin: Math.max(0, root.innerPadding)
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.spacing
  }
}
