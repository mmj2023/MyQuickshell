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
  property bool appTooltipHovered: false
  property string appTooltipText: ""
  property int appTooltipX: 0
  property int appTooltipY: 0
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

  function showAppTooltip(icon, title) {
    if (!root.barWindow || !title)
      return
    root.appTooltipText = title
    const point = icon.mapToItem(root.barWindow.contentItem, icon.width / 2, icon.height)
    const screenWidth = root.parentScreen ? root.parentScreen.width : root.barWindow.width
    const popupWidth = Math.min(appTooltipPopup.implicitWidth, Math.max(120, screenWidth - 32))
    root.appTooltipX = Math.max(16, Math.min(
      screenWidth - popupWidth - 16,
      point.x - popupWidth / 2
    ))
    root.appTooltipY = Math.round(point.y + Theme.spaceXS)
    appTooltipDelay.restart()
  }

  function hideAppTooltip() {
    root.appTooltipHovered = false
    appTooltipDelay.stop()
    appTooltipPopup.visible = false
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
            id: appIconMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
              root.appTooltipHovered = true
              root.showAppTooltip(parent, win.title)
            }
            onExited: root.hideAppTooltip()
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
          onEntered: {
            root.appTooltipHovered = true
            root.showAppTooltip(parent, "more active apps")
          }
          onExited: root.hideAppTooltip()
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
              onEntered: {
                root.appTooltipHovered = true
                root.showAppTooltip(parent, win.title)
              }
              onExited: root.hideAppTooltip()
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

  Timer {
    id: appTooltipDelay
    interval: 450
    repeat: false
    onTriggered: {
      if (root.appTooltipHovered && root.appTooltipText !== "")
        appTooltipPopup.visible = true
    }
  }

  TextMetrics {
    id: appTooltipMetrics
    font.family: Theme.fontFamily
    font.pixelSize: root.textSize()
    text: root.appTooltipText
  }

  PopupWindow {
    id: appTooltipPopup
    anchor.window: root.barWindow
    anchor.rect.x: root.appTooltipX
    anchor.rect.y: root.appTooltipY
    visible: false
    color: "transparent"
    implicitWidth: Math.min(
      appTooltipMetrics.advanceWidth + Theme.spaceL * 2,
      Math.max(120, (root.parentScreen ? root.parentScreen.width : 512) - 32)
    )
    implicitHeight: Math.min(
      appTooltipTextItem.implicitHeight + Theme.spaceM * 2,
      Math.max(80, (root.parentScreen ? root.parentScreen.height : 800) * 0.5)
    )

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.withAlpha(
        Theme.widgetBaseBackgroundColor,
        typeof SettingsData !== "undefined" ? SettingsData.barWidgetTransparency : 0.65
      )
      border.width: 0

      Text {
        id: appTooltipTextItem
        anchors.fill: parent
        anchors.margins: Theme.spaceM
        text: root.appTooltipText
        color: Theme.widgetTextColor
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize()
        wrapMode: Text.Wrap
      }
    }
  }
}
