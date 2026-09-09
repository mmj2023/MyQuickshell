import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Running apps. Renders one icon per open toplevel on the current screen using
// ToplevelManager.toplevels directly (a reactive QML model). Icons resolve from
// the app id via the icon theme with a generic fallback.
BasePill {
  id: root

  property var barWindow: null
  property QtObject parentScreen: null
  property bool overflowOpen: false
  property int popupX: 0
  property int popupY: 0
  readonly property var screenToplevels: Array.from(ToplevelManager.toplevels.values)
  readonly property var hyprlandToplevels: Array.from(Hyprland.toplevels ? Hyprland.toplevels.values : [])
  readonly property string currentSpecialWorkspace: root._currentSpecialWorkspace()
  readonly property int currentWorkspaceId: root._currentWorkspaceId()
  readonly property var currentWorkspaceWindows: root.screenToplevels.filter(function(t) {
    if (root.currentSpecialWorkspace !== "")
      return root.workspaceName(t) === root.currentSpecialWorkspace
    return root.currentWorkspaceId <= 0 || root.workspaceId(t) === root.currentWorkspaceId
  })
  readonly property var hiddenWorkspaceWindows: root.screenToplevels.filter(function(t) {
    if (root.currentSpecialWorkspace !== "")
      return root.workspaceName(t) !== root.currentSpecialWorkspace
    return root.currentWorkspaceId > 0 && root.workspaceId(t) !== root.currentWorkspaceId
  })
  readonly property bool hasWindows: root.currentWorkspaceWindows.length > 0

  function workspaceId(toplevel) {
    if (!toplevel)
      return 0
    const hyprlandToplevel = root.hyprlandToplevels.find(function(t) {
      return t.wayland === toplevel
    })
    if (hyprlandToplevel && hyprlandToplevel.workspace)
      return Number(hyprlandToplevel.workspace.id)
    return 0
  }

  function workspaceName(toplevel) {
    if (!toplevel)
      return ""
    const hyprlandToplevel = root.hyprlandToplevels.find(function(t) {
      return t.wayland === toplevel
    })
    const workspace = hyprlandToplevel ? hyprlandToplevel.workspace : null
    return workspace ? root._normalizeSpecialWorkspaceName(workspace.name) : ""
  }

  function _normalizeSpecialWorkspaceName(value) {
    let name = value
    if (name && typeof name === "object")
      name = name.name
    name = String(name || "")
    if (name === "")
      return ""
    if (name === "special")
      return "special:special"
    return name.indexOf("special:") === 0 ? name : "special:" + name
  }

  function _currentSpecialWorkspace() {
    const name = root.parentScreen ? root.parentScreen.name : ""
    const monitor = Hyprland.monitors
      ? Hyprland.monitors.values.find(function(m) { return m.name === name })
      : null
    const candidates = monitor ? [monitor.activeSpecialWorkspace] : []
    for (let i = 0; i < candidates.length; ++i) {
      const workspaceName = root._normalizeSpecialWorkspaceName(candidates[i])
      if (workspaceName !== "")
        return workspaceName
    }

    const activeToplevel = root.hyprlandToplevels.find(function(t) {
      const monitorName = t.monitor ? t.monitor.name : ""
      return t.activated
        && (!name || monitorName === name)
        && t.workspace
        && Number(t.workspace.id) < 0
    })
    if (activeToplevel && activeToplevel.workspace)
      return root._normalizeSpecialWorkspaceName(activeToplevel.workspace.name)

    return ""
  }

  function _currentWorkspaceId() {
    const name = root.parentScreen ? root.parentScreen.name : ""
    const monitor = Hyprland.monitors
      ? Hyprland.monitors.values.find(function(m) { return m.name === name })
      : null
    if (monitor && monitor.activeWorkspace)
      return Number(monitor.activeWorkspace.id)
    return Number(WorkspacesService.activeWorkspaceId(name)) || 0
  }

  function toggleOverflow() {
    const point = root.mapToItem(root.barWindow.contentItem, root.width / 2, root.height)
    root.popupX = Math.round(point.x - runningAppsPopup.width / 2)
    root.popupY = Math.round(point.y)
    root.overflowOpen = !root.overflowOpen
  }

  content: Component {
    Row {
      spacing: 2

      Repeater {
        model: root.currentWorkspaceWindows

        delegate: Rectangle {
          required property var modelData
          readonly property var win: modelData

          width: win.activated ? 28 : 26
          height: 26
          anchors.verticalCenter: parent.verticalCenter
          radius: Theme.pillRadius
          color: win.activated ? Theme.surfaceText_12 : "transparent"

          IconImage {
            anchors.centerIn: parent
            source: Theme.getAppIcon(win.appId)
            implicitSize: 18
            asynchronous: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: win.activate()
          }
        }
      }

      Rectangle {
        visible: root.hiddenWorkspaceWindows.length > 0
        width: 24
        height: 26
        radius: Theme.pillRadius
        color: appOverflowMouse.containsMouse ? Theme.surfaceText_12 : "transparent"

        Canvas {
          id: appOverflowChevron
          anchors.centerIn: parent
          width: 14
          height: 14

          onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = Theme.widgetTextColor
            ctx.lineWidth = 2
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.beginPath()
            if (root.overflowOpen) {
              ctx.moveTo(2, 9)
              ctx.lineTo(7, 4)
              ctx.lineTo(12, 9)
            } else {
              ctx.moveTo(2, 5)
              ctx.lineTo(7, 10)
              ctx.lineTo(12, 5)
            }
            ctx.stroke()
          }

          Connections {
            target: Theme
            function onWidgetTextColorChanged() { appOverflowChevron.requestPaint() }
          }

          Connections {
            target: root
            function onOverflowOpenChanged() { appOverflowChevron.requestPaint() }
          }
        }

        MouseArea {
          id: appOverflowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleOverflow()
        }
      }
    }
  }

  PopupWindow {
    id: runningAppsPopup
    anchor.window: root.barWindow
    anchor.rect.x: root.popupX
    anchor.rect.y: root.popupY
    visible: root.overflowOpen
    grabFocus: true
    color: "transparent"
    implicitWidth: Math.max(48, hiddenAppsRow.implicitWidth + 16)
    implicitHeight: 42

    onVisibleChanged: {
      if (!visible)
        root.overflowOpen = false
    }

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: {
        const transparency = typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.6
        return Theme.withAlpha(Theme.surfaceContainer, transparency)
      }
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.35)

      Row {
        id: hiddenAppsRow
        anchors.centerIn: parent
        spacing: 2

        Repeater {
          model: root.hiddenWorkspaceWindows

          delegate: Rectangle {
            required property var modelData
            readonly property var win: modelData
            width: 26
            height: 26
            radius: Theme.pillRadius
            color: hiddenAppMouse.containsMouse ? Theme.surfaceText_12 : "transparent"

            IconImage {
              anchors.centerIn: parent
              source: Theme.getAppIcon(win.appId)
              implicitSize: 18
              asynchronous: true
            }

            MouseArea {
              id: hiddenAppMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.overflowOpen = false
                win.activate()
              }
            }
          }
        }
      }
    }
  }
}
