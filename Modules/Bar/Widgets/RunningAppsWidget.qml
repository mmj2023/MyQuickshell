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
  property var previewAppWindow: null
  property string previewAppTitle: ""
  property bool previewFromHiddenAppsMenu: false
  property int previewPopupX: 0
  property int previewPopupY: 0
  property bool appContextMenuOpen: false
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
    root.popupY = Math.round(point.y + Theme.spaceXS)
    root.overflowOpen = !root.overflowOpen
  }

  function toggleAppContextMenu(icon, window, fromHiddenAppsMenu) {
    if (!root.barWindow || !window)
      return

    if (root.appContextMenuOpen && root.previewAppWindow === window) {
      root.appContextMenuOpen = false
      return
    }

    root.previewAppWindow = window
    root.previewAppTitle = String(window.title || window.appId || qsTr("Application"))
    root.previewFromHiddenAppsMenu = fromHiddenAppsMenu
    const screenWidth = root.parentScreen ? root.parentScreen.width : root.barWindow.width
    if (fromHiddenAppsMenu) {
      const point = icon.mapToItem(
        runningAppsPopup.contentItem,
        icon.width / 2,
        icon.height
      )
      const desiredX = root.popupX + point.x - appContextPopup.implicitWidth / 2
      const clampedX = Math.max(Theme.spaceS, Math.min(
        screenWidth - appContextPopup.implicitWidth - Theme.spaceS,
        desiredX
      ))
      root.previewPopupX = clampedX - root.popupX
      root.previewPopupY = runningAppsPopup.height + Theme.spaceXS
    } else {
      const point = icon.mapToItem(root.barWindow.contentItem, icon.width / 2, icon.height)
      root.previewPopupX = Math.max(Theme.spaceS, Math.min(
        screenWidth - appContextPopup.implicitWidth - Theme.spaceS,
        point.x - appContextPopup.implicitWidth / 2
      ))
      root.previewPopupY = Math.round(point.y + Theme.spaceXS)
    }
    root.appContextMenuOpen = true
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
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) {
                root.hideAppTooltip()
                root.toggleAppContextMenu(parent, win, false)
                return
              }
              win.activate()
            }
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
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                root.appTooltipHovered = true
                root.showAppTooltip(parent, win.title)
              }
              onExited: root.hideAppTooltip()
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  root.hideAppTooltip()
                  root.toggleAppContextMenu(parent, win, true)
                  return
                }
                root.overflowOpen = false
                win.activate()
              }
            }
          }

        }
      }
    }
  }

  PopupWindow {
    id: appContextPopup
    anchor.window: root.previewFromHiddenAppsMenu ? runningAppsPopup : root.barWindow
    anchor.rect.x: root.previewPopupX
    anchor.rect.y: root.previewPopupY
    visible: root.appContextMenuOpen
    grabFocus: true
    color: "transparent"
    surfaceFormat.opaque: false
    implicitWidth: 320
    implicitHeight: appContextContent.implicitHeight + Theme.spaceS * 2

    onVisibleChanged: {
      if (!visible)
        root.appContextMenuOpen = false
    }

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.withAlpha(
        Theme.widgetBaseBackgroundColor,
        typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.6
      )
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.35)

      Column {
        id: appContextContent
        anchors.fill: parent
        anchors.margins: Theme.spaceS
        spacing: Theme.spaceXS

        Item {
          width: parent.width
          height: Theme.spaceXL
          implicitHeight: Theme.spaceXL

          Row {
            anchors.fill: parent
            spacing: Theme.spaceS

            IconImage {
              width: Theme.spaceL
              height: Theme.spaceL
              anchors.verticalCenter: parent.verticalCenter
              source: Theme.getAppIcon(root.previewAppWindow ? root.previewAppWindow.appId : "")
              asynchronous: true
            }

            Text {
              width: parent.width - Theme.spaceL - Theme.spaceS
              height: parent.height
              text: root.previewAppTitle
              color: Theme.surfaceText
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
              font.weight: Font.DemiBold
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 148
          implicitHeight: height
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainer, 0.82)
          clip: true

          ScreencopyView {
            id: appPreviewCapture
            anchors.fill: parent
            captureSource: root.previewAppWindow
            live: root.appContextMenuOpen
            constraintSize.width: parent.width
            constraintSize.height: parent.height
          }

          Text {
            anchors.centerIn: parent
            visible: !appPreviewCapture.hasContent
            text: qsTr("Preview unavailable")
            color: Theme.surfaceText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          implicitHeight: height
          color: Theme.withAlpha(Theme.outlineVariant, 0.6)
        }

        Item {
          visible: WorkspacesService.windowScratchpadName(root.previewAppWindow) !== ""
          width: parent.width
          height: Theme.spaceXL + Theme.spaceS
          implicitHeight: height

          Rectangle {
            anchors.fill: parent
            radius: Theme.hoverRadius
            color: moveOutMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
          }

          DmsIcon {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceS
            anchors.verticalCenter: parent.verticalCenter
            name: "outbox"
            size: Theme.iconSizeSmall
            color: Theme.surfaceText
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceXL + Theme.spaceS
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Move out of scratchpad")
            color: Theme.surfaceText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
          }

          MouseArea {
            id: moveOutMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              const window = root.previewAppWindow
              root.appContextMenuOpen = false
              WorkspacesService.moveWindowOutOfScratchpad(window)
            }
          }
        }

        Repeater {
          model: WorkspacesService.windowScratchpadName(root.previewAppWindow) === ""
            ? WorkspacesService.specialWorkspaceNames
            : []

          delegate: Item {
            required property string modelData
            width: appContextContent.width
            height: Theme.spaceXL + Theme.spaceS
            implicitHeight: height

            Rectangle {
              anchors.fill: parent
              radius: Theme.hoverRadius
              color: scratchpadMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
            }

            DmsIcon {
              anchors.left: parent.left
              anchors.leftMargin: Theme.spaceS
              anchors.verticalCenter: parent.verticalCenter
              name: "inbox"
              size: Theme.iconSizeSmall
              color: Theme.surfaceText
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Theme.spaceXL + Theme.spaceS
              anchors.verticalCenter: parent.verticalCenter
              text: modelData === "special"
                ? qsTr("Move to scratchpad")
                : qsTr("Move to scratchpad: %1").arg(modelData)
              color: Theme.surfaceText
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }

            MouseArea {
              id: scratchpadMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                const window = root.previewAppWindow
                const name = modelData
                root.appContextMenuOpen = false
                WorkspacesService.moveWindowToScratchpad(window, name)
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          implicitHeight: height
          color: Theme.withAlpha(Theme.outlineVariant, 0.6)
        }

        Item {
          width: parent.width
          height: Theme.spaceXL + Theme.spaceS
          implicitHeight: height

          Rectangle {
            anchors.fill: parent
            radius: Theme.hoverRadius
            color: closeWindowMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.12) : "transparent"
          }

          DmsIcon {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceS
            anchors.verticalCenter: parent.verticalCenter
            name: "close"
            size: Theme.iconSizeSmall
            color: Theme.error
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceXL + Theme.spaceS
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Close")
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
          }

          MouseArea {
            id: closeWindowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              const window = root.previewAppWindow
              root.appContextMenuOpen = false
              WorkspacesService.closeWindow(window)
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
