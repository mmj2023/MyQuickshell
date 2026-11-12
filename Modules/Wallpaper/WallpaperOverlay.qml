import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

PanelWindow {
  id: root

  property var targetScreen: null
  property bool chooserOpen: false
  property bool appPickerOpen: false
  property bool chooserAddLayer: false
  property string chooserScope: "global"
  property bool gifAnimationDelayElapsed: false
  property var collapsedDirectories: []
  readonly property bool overlayVisible: WallpaperService.overlayMode !== ""
    && WallpaperService.overlayScreen === root.targetScreen
  readonly property bool overviewMode: WallpaperService.overlayMode === "overview"
  readonly property string selectedScope: root.overviewMode
    ? SettingsData.wallpaperApplyScope : WallpaperService.switcherApplyScope
  readonly property string selectedSource: WallpaperService.sourceForTarget(
    root.selectedScope, root.targetScreen
  )
  readonly property string selectedType: WallpaperService.typeForTarget(
    root.selectedScope, root.targetScreen
  )
  readonly property var selectedAppWindow: WallpaperService.appWindowForSource(
    root.selectedSource
  )

  onOverlayVisibleChanged: {
    if (root.overlayVisible)
      gifAnimationDelay.restart()
    else {
      gifAnimationDelay.stop()
      root.gifAnimationDelayElapsed = false
    }
  }

  onOverviewModeChanged: {
    if (!overviewMode)
      root.appPickerOpen = false
  }

  function isGifSource(source) {
    return String(source).toLowerCase().split(/[?#]/)[0].endsWith(".gif")
  }

  function toggleDirectoryGroup(path) {
    const collapsed = root.collapsedDirectories.slice()
    const index = collapsed.indexOf(path)
    if (index < 0)
      collapsed.push(path)
    else
      collapsed.splice(index, 1)
    root.collapsedDirectories = collapsed
  }

  screen: root.targetScreen
  visible: root.overlayVisible
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  surfaceFormat.opaque: false
  WlrLayershell.namespace: "myquickshell-wallpaper-overlay"
  WlrLayershell.layer: root.chooserOpen ? WlrLayer.Background : WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.chooserOpen
    ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

  Timer {
    id: gifAnimationDelay
    interval: 100
    repeat: false
    onTriggered: root.gifAnimationDelayElapsed = true
  }

  Item {
    id: overlayContent
    anchors.fill: parent
    visible: root.overlayVisible && !root.chooserOpen
    focus: root.overlayVisible
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (WallpaperService.shortcutCaptureActive) {
        WallpaperService.captureShortcut(event.key, event.modifiers)
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Escape) {
        if (root.appPickerOpen)
          root.appPickerOpen = false
        else
          WallpaperService.closeOverlay()
        event.accepted = true
      } else if (event.key === Qt.Key_Left) {
        if (root.overviewMode)
          WallpaperService.previousWallpaper(SettingsData.wallpaperApplyScope,
            root.targetScreen)
        else
          quickSwitcher.moveSelection(-1)
        event.accepted = true
      } else if (event.key === Qt.Key_Right) {
        if (root.overviewMode)
          WallpaperService.nextWallpaper(SettingsData.wallpaperApplyScope,
            root.targetScreen)
        else
          quickSwitcher.moveSelection(1)
        event.accepted = true
      } else if (!root.overviewMode && event.key === Qt.Key_Shift) {
        if (WallpaperService.toggleSwitcherApplyScope())
          quickSwitcher.refreshSelection()
        event.accepted = true
      } else if (!root.overviewMode
                 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
        quickSwitcher.applySelection()
        event.accepted = true
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Theme.withAlpha(Theme.scrim, 0.72)

      MouseArea {
        anchors.fill: parent
        onClicked: WallpaperService.closeOverlay()
      }
    }

    Rectangle {
      id: panel
      visible: root.overlayVisible && root.overviewMode
      width: Math.min(parent.width - Theme.spaceXL * 2, 1120)
      height: Math.min(parent.height - Theme.spaceXL * 2, 760)
      anchors.centerIn: parent
      radius: Theme.cornerRadius
      color: Theme.withAlpha(
        Theme.widgetBaseBackgroundColor,
        SettingsData.barWidgetTransparency
      )
      border.width: 1
      border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

      Column {
        anchors.fill: parent
        anchors.margins: Theme.spaceL
        spacing: Theme.spaceM

        Row {
          width: parent.width
          height: 40
          spacing: Theme.spaceS

          Column {
            width: parent.width - quickButton.width - closeButton.width - Theme.spaceS * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
              text: root.overviewMode ? qsTr("Wallpaper library") : qsTr("Change wallpaper")
              color: Theme.surfaceText
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeMedium
              font.weight: Font.DemiBold
            }

            Text {
              text: WallpaperService.targetLabelForScope(
                root.selectedScope, root.targetScreen
              ) + " · " + root.selectedType + " · "
                + root.selectedSource
              width: parent.width
              color: Theme.surfaceVariantText
              font.family: Theme.monoFontFamily
              font.pixelSize: Theme.fontSizeSmall
              elide: Text.ElideMiddle
            }
          }

          Rectangle {
            id: quickButton
            width: 150
            height: 36
            radius: Theme.hoverRadius
            color: quickButtonMouse.containsMouse
              ? Theme.withAlpha(Theme.primary, 0.2)
              : Theme.withAlpha(Theme.primary, 0.12)

            Text {
              anchors.centerIn: parent
              text: root.overviewMode ? qsTr("Quick switch") : qsTr("Wallpaper library")
              color: Theme.surfaceText
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }

            MouseArea {
              id: quickButtonMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.overviewMode)
                  WallpaperService.openSwitcher(root.targetScreen)
                else
                  WallpaperService.openOverview(root.targetScreen)
              }
            }
          }

          Rectangle {
            id: closeButton
            width: 36
            height: 36
            radius: Theme.hoverRadius
            color: closeMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"

            Text {
              anchors.centerIn: parent
              text: "×"
              color: Theme.surfaceText
              font.pixelSize: Theme.fontSizeMedium
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: WallpaperService.closeOverlay()
            }
          }
        }

        Row {
          width: parent.width
          height: parent.height - 40 - parent.spacing
            - (mediaControls.visible ? mediaControls.height + parent.spacing : 0)
          spacing: Theme.spaceM

          Flickable {
            id: options
            width: root.overviewMode ? 270 : 0
            height: parent.height
            contentWidth: width
            contentHeight: optionsContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: root.overviewMode

            Column {
              id: optionsContent
              width: options.width
              height: implicitHeight
              spacing: Theme.spaceS

              Text {
                text: qsTr("SET WALLPAPER")
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }

              Row {
                width: parent.width
                height: 36
                spacing: Theme.spaceXS

                ActionButton {
                  width: (parent.width - parent.spacing * 2) / 3
                  label: qsTr("Global")
                  emphasized: SettingsData.wallpaperApplyScope === "global"
                  onClicked: WallpaperService.setDefaultApplyScope("global")
                }

                ActionButton {
                  width: (parent.width - parent.spacing * 2) / 3
                  label: qsTr("Monitor")
                  emphasized: SettingsData.wallpaperApplyScope === "monitor"
                  enabled: WallpaperService.monitorKeyForScreen(root.targetScreen).length > 0
                  onClicked: WallpaperService.setDefaultApplyScope("monitor")
                }

                ActionButton {
                  width: (parent.width - parent.spacing * 2) / 3
                  label: qsTr("Workspace")
                  emphasized: SettingsData.wallpaperApplyScope === "workspace"
                  enabled: WallpaperService.workspaceKeyForScreen(root.targetScreen).length > 0
                  onClicked: WallpaperService.setDefaultApplyScope("workspace")
                }
              }

              Text {
                width: parent.width
                text: WallpaperService.targetLabelForScope(
                  root.selectedScope, root.targetScreen
                )
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
              }

              ActionButton {
                width: parent.width
                visible: root.selectedScope === "workspace"
                  && WallpaperService.hasWorkspaceOverrideForScreen(root.targetScreen)
                label: WallpaperService.hasMonitorOverrideForScreen(root.targetScreen)
                  ? qsTr("Use monitor wallpaper for this workspace")
                  : qsTr("Use global wallpaper for this workspace")
                onClicked: WallpaperService.clearWorkspaceOverride(root.targetScreen)
              }

              ActionButton {
                width: parent.width
                visible: root.selectedScope === "monitor"
                  && WallpaperService.hasMonitorOverrideForScreen(root.targetScreen)
                label: qsTr("Use global wallpaper on this monitor")
                onClicked: WallpaperService.clearMonitorOverride(root.targetScreen)
              }

              Row {
                width: parent.width
                height: 36
                spacing: Theme.spaceXS

                ActionButton {
                  width: (parent.width - parent.spacing) / 2
                  label: WallpaperService.shortcutCaptureActive
                    ? qsTr("Press a shortcut…")
                    : qsTr("Record shortcut")
                  onClicked: {
                    WallpaperService.beginShortcutCapture()
                    overlayContent.forceActiveFocus()
                  }
                }

                ActionButton {
                  width: (parent.width - parent.spacing) / 2
                  label: qsTr("Apply shortcut")
                  onClicked: WallpaperService.applyShortcut()
                }
              }

              Text {
                width: parent.width
                text: qsTr("Shortcut: %1").arg(WallpaperService.pendingShortcut)
                color: Theme.surfaceText
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: WallpaperService.shortcutStatus.length > 0
                text: WallpaperService.shortcutStatus
                color: WallpaperService.shortcutStatusIsError
                  ? Theme.error
                  : Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
              }

              Text {
                width: parent.width
                text: qsTr("Checks Lua config binds too; if a bind expression cannot be resolved, the shortcut won't be applied.")
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
              }

              ActionButton {
                width: parent.width
                label: qsTr("Choose media file…")
                onClicked: WallpaperService.chooseMediaFile(
                  root.targetScreen, SettingsData.wallpaperApplyScope
                )
              }

              ActionButton {
                width: parent.width
                label: qsTr("Add media file as a layer…")
                onClicked: WallpaperService.chooseMediaFile(
                  root.targetScreen, SettingsData.wallpaperApplyScope, true
                )
              }

              ActionButton {
                width: parent.width
                label: root.selectedType === "app"
                  ? qsTr("Change app preview…")
                  : qsTr("Use app preview…")
                onClicked: {
                  WallpaperService.error = ""
                  WallpaperService.refreshAppWindows()
                  root.appPickerOpen = true
                }
              }

              Text {
                width: parent.width
                visible: root.selectedType === "app"
                text: root.selectedAppWindow
                  ? qsTr("Live app preview: %1").arg(
                    WallpaperService.appWindowTitleForSource(root.selectedSource)
                  )
                  : qsTr("App preview unavailable. Choose an open window.")
                color: root.selectedAppWindow
                  ? Theme.surfaceVariantText
                  : Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
              }

              ActionButton {
                width: parent.width
                label: qsTr("Add wallpaper folder…")
                onClicked: WallpaperService.chooseDirectory(root.targetScreen)
              }

              Row {
                width: parent.width
                height: 36
                spacing: Theme.spaceXS

                Rectangle {
                  width: parent.width - colorButton.width - addColorLayerButton.width
                    - Theme.spaceXS * 2
                  height: parent.height
                  radius: Theme.hoverRadius
                  color: Theme.surfaceContainerHigh

                  TextInput {
                    id: colorInput
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spaceS
                    anchors.rightMargin: Theme.spaceXS
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.surfaceText
                    font.family: Theme.monoFontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    text: root.selectedType === "color" ? root.selectedSource : "#000000"
                    selectByMouse: true
                    clip: true
                    onAccepted: WallpaperService.setColor(text,
                      SettingsData.wallpaperApplyScope, root.targetScreen)
                  }
                }

                Rectangle {
                  id: colorButton
                  width: 64
                  height: parent.height
                  radius: Theme.hoverRadius
                  color: Theme.withAlpha(Theme.primary, 0.16)

                  Text {
                    anchors.centerIn: parent
                    text: qsTr("Apply")
                    color: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: WallpaperService.setColor(colorInput.text,
                      SettingsData.wallpaperApplyScope, root.targetScreen)
                  }
                }

                Rectangle {
                  id: addColorLayerButton
                  width: 46
                  height: parent.height
                  radius: Theme.hoverRadius
                  color: Theme.withAlpha(Theme.primary, 0.1)

                  Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: WallpaperService.setColor(colorInput.text,
                      SettingsData.wallpaperApplyScope, root.targetScreen, true)
                  }
                }
              }

              Rectangle {
                width: parent.width
                height: 1
                color: Theme.withAlpha(Theme.outlineVariant, 0.5)
              }

              Text {
                text: qsTr("MEDIA URL")
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }

              Rectangle {
                width: parent.width
                height: 36
                radius: Theme.hoverRadius
                color: Theme.surfaceContainerHigh

                TextInput {
                  id: urlInput
                  anchors.fill: parent
                  anchors.leftMargin: Theme.spaceS
                  anchors.rightMargin: Theme.spaceXS
                  verticalAlignment: TextInput.AlignVCenter
                  color: Theme.surfaceText
                  font.family: Theme.monoFontFamily
                  font.pixelSize: Theme.fontSizeSmall
                  text: root.selectedSource.startsWith("http")
                    ? root.selectedSource
                    : ""
                  selectByMouse: true
                  clip: true
                  onAccepted: applyUrl()
                }
              }

              ActionButton {
                width: parent.width
                label: qsTr("Use URL as video/stream")
                onClicked: applyUrl()
              }

              ActionButton {
                width: parent.width
                label: qsTr("Add URL as a layer")
                onClicked: applyUrl(true)
              }

              Text {
                visible: WallpaperService.requiresYouTubeExtraction(root.selectedSource)
                text: qsTr("VIDEO QUALITY")
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
              }

              ComboBox {
                id: videoResolutionSelector
                width: parent.width
                height: 36
                visible: WallpaperService.requiresYouTubeExtraction(root.selectedSource)
                model: WallpaperService.videoResolutionOptions
                textRole: "label"
                valueRole: "value"
                currentIndex: {
                  const options = WallpaperService.videoResolutionOptions
                  for (let index = 0; index < options.length; index++) {
                    if (options[index].value === SettingsData.wallpaperVideoResolution)
                      return index
                  }
                  return 0
                }
                onActivated: index => WallpaperService.setVideoResolution(
                  WallpaperService.videoResolutionOptions[index].value
                )

                contentItem: TextInput {
                  leftPadding: Theme.spaceS
                  rightPadding: Theme.spaceXL
                  text: videoResolutionSelector.currentText
                  color: Theme.surfaceText
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeSmall
                  verticalAlignment: Text.AlignVCenter
                  enabled: false
                  autoScroll: false
                  readOnly: true
                  selectByMouse: false
                  cursorVisible: false
                  clip: true
                }

                indicator: DmsIcon {
                  x: videoResolutionSelector.width - width - Theme.spaceXS
                  anchors.verticalCenter: parent.verticalCenter
                  name: "expand_more"
                  size: 18
                  color: Theme.surfaceText
                }

                background: Rectangle {
                  radius: Theme.hoverRadius
                  color: Theme.surfaceContainerHigh
                  border.width: 1
                  border.color: Theme.outlineVariant
                }

                popup: Popup {
                  y: videoResolutionSelector.height + Theme.spaceXS
                  width: videoResolutionSelector.width
                  implicitHeight: contentItem.implicitHeight
                  padding: Theme.spaceXS

                  background: Rectangle {
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainer
                    border.width: 1
                    border.color: Theme.outlineVariant
                  }

                  contentItem: ListView {
                    clip: true
                    implicitHeight: Math.min(contentHeight, 216)
                    model: videoResolutionSelector.popup.visible
                      ? videoResolutionSelector.delegateModel
                      : null
                    currentIndex: videoResolutionSelector.highlightedIndex
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds
                  }
                }

                delegate: ItemDelegate {
                  required property int index
                  required property var modelData
                  width: videoResolutionSelector.width - Theme.spaceXS * 2
                  text: modelData.label
                  highlighted: videoResolutionSelector.highlightedIndex === index

                  contentItem: Text {
                    text: modelData.label
                    color: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                  }

                  background: Rectangle {
                    radius: Theme.hoverRadius
                    color: parent.highlighted
                      ? Theme.withAlpha(Theme.primary, 0.2)
                      : "transparent"
                  }
                }
              }

              Text {
                visible: WallpaperService.requiresYouTubeExtraction(root.selectedSource)
                width: parent.width
                text: qsTr("Best available selects the highest video stream; caps fall back to a lower resolution when needed.")
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
              }

              Rectangle {
                width: parent.width
                height: 1
                color: Theme.withAlpha(Theme.outlineVariant, 0.5)
              }

              ActionButton {
                width: parent.width
                label: SettingsData.wallpaperCycleEnabled
                  ? qsTr("Slideshow: on")
                  : qsTr("Slideshow: off")
                onClicked: SettingsData.set("wallpaperCycleEnabled", !SettingsData.wallpaperCycleEnabled)
              }

              Row {
                width: parent.width
                height: 34
                spacing: Theme.spaceXS

                Text {
                  width: parent.width - intervalInput.width - Theme.spaceXS
                  anchors.verticalCenter: parent.verticalCenter
                  text: qsTr("Change every (minutes)")
                  color: Theme.surfaceText
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeSmall
                  elide: Text.ElideRight
                }

                Rectangle {
                  width: 64
                  height: parent.height
                  radius: Theme.hoverRadius
                  color: Theme.surfaceContainerHigh

                  TextInput {
                    id: intervalInput
                    anchors.fill: parent
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    text: String(SettingsData.wallpaperIntervalMinutes)
                    color: Theme.surfaceText
                    font.family: Theme.monoFontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    validator: IntValidator { bottom: 1; top: 1440 }
                    onAccepted: {
                      if (acceptableInput)
                        SettingsData.set("wallpaperIntervalMinutes", Number(text))
                    }
                  }
                }
              }

              ActionButton {
                width: parent.width
                label: qsTr("Fit: ") + SettingsData.wallpaperFit
                onClicked: SettingsData.set(
                  "wallpaperFit",
                  SettingsData.wallpaperFit === "cover" ? "contain" : "cover"
                )
              }

              Text {
                width: parent.width
                visible: WallpaperService.error.length > 0
                text: WallpaperService.error
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
              }
            }
          }

          Column {
            width: parent.width - options.width - (root.overviewMode ? parent.spacing : 0)
            height: parent.height
            spacing: Theme.spaceS

            Row {
              width: parent.width
              height: 32
              spacing: Theme.spaceS

              Text {
                width: parent.width - refreshButton.width
                anchors.verticalCenter: parent.verticalCenter
                text: root.overviewMode
                  ? qsTr("Library · %1 media items").arg(WallpaperService.items.length)
                  : qsTr("Select a wallpaper or media · ← → to browse")
                color: Theme.surfaceText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
              }

              Rectangle {
                id: refreshButton
                width: 36
                height: 32
                radius: Theme.hoverRadius
                color: refreshMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "↻"
                  color: Theme.surfaceText
                  font.pixelSize: Theme.fontSizeMedium
                }

                MouseArea {
                  id: refreshMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: WallpaperService.scanDirectories()
                }
              }
            }

            Rectangle {
              id: layerGraph
              width: parent.width
              height: 178
              visible: root.overviewMode
              radius: Theme.cornerRadius
              color: Theme.withAlpha(Theme.surfaceContainer, 0.72)
              border.width: 1
              border.color: Theme.withAlpha(Theme.outlineVariant, 0.55)

              Column {
                anchors.fill: parent
                anchors.margins: Theme.spaceS
                spacing: Theme.spaceXS

                Row {
                  width: parent.width
                  height: 22
                  spacing: Theme.spaceS

                  Text {
                    width: parent.width - layerOrderHint.width - parent.spacing
                    text: qsTr("Wallpaper layers")
                    color: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                  }

                  Text {
                    id: layerOrderHint
                    text: qsTr("Bottom → top")
                    color: Theme.surfaceVariantText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                  }
                }

                ListView {
                  id: layerList
                  width: parent.width
                  height: parent.height - 22 - parent.spacing
                  orientation: ListView.Horizontal
                  spacing: Theme.spaceS
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  model: WallpaperService.layersForTarget(
                    root.selectedScope, root.targetScreen
                  )

                  delegate: Item {
                    required property var modelData
                    required property int index
                    width: 264
                    height: layerList.height

                    Rectangle {
                      anchors.fill: parent
                      radius: Theme.cornerRadius
                      color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.92)
                      border.width: 1
                      border.color: Theme.withAlpha(Theme.outlineVariant, 0.65)
                      clip: true

                      Rectangle {
                        id: layerPreview
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spaceXS
                        height: 62
                        radius: Theme.hoverRadius
                        color: modelData.type === "color"
                          ? Qt.color(modelData.source)
                          : Theme.surfaceContainer
                        clip: true

                        Image {
                          anchors.fill: parent
                          visible: modelData.type === "image"
                          source: visible ? modelData.source : ""
                          fillMode: Image.PreserveAspectCrop
                          sourceSize: Qt.size(420, 120)
                          asynchronous: true
                          cache: true
                        }

                        Text {
                          anchors.centerIn: parent
                          visible: modelData.type !== "image"
                            && modelData.type !== "color"
                          text: String(modelData.type).toUpperCase()
                          color: Theme.surfaceText
                          font.family: Theme.fontFamily
                          font.pixelSize: Theme.fontSizeSmall
                          font.weight: Font.DemiBold
                        }

                        Text {
                          anchors.left: parent.left
                          anchors.top: parent.top
                          anchors.margins: Theme.spaceXS
                          text: index === layerList.count - 1
                            ? qsTr("TOP")
                            : qsTr("LAYER %1").arg(index + 1)
                          color: Theme.surfaceText
                          font.family: Theme.fontFamily
                          font.pixelSize: Theme.fontSizeSmall - 1
                          font.weight: Font.DemiBold
                        }
                      }

                      Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: layerPreview.bottom
                        anchors.leftMargin: Theme.spaceS
                        anchors.rightMargin: Theme.spaceS
                        anchors.topMargin: Theme.spaceXS
                        height: 18
                        text: String(modelData.source).split("/").pop()
                        color: Theme.surfaceText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideMiddle
                      }

                      Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Theme.spaceXS
                        spacing: Theme.spaceXS
                        height: 28

                        ActionButton {
                          width: 24
                          height: parent.height
                          label: "↑"
                          enabled: index < layerList.count - 1
                          onClicked: WallpaperService.moveLayer(
                            modelData.id, 1, root.selectedScope, root.targetScreen
                          )
                        }

                        ActionButton {
                          width: 24
                          height: parent.height
                          label: "↓"
                          enabled: index > 0
                          onClicked: WallpaperService.moveLayer(
                            modelData.id, -1, root.selectedScope, root.targetScreen
                          )
                        }

                        ActionButton {
                          width: 56
                          height: parent.height
                          label: WallpaperService.stackForScope(
                            root.selectedScope, root.targetScreen
                          ).controlLayerId === modelData.id
                            ? qsTr("Preferred")
                            : qsTr("Controls")
                          emphasized: WallpaperService.stackForScope(
                            root.selectedScope, root.targetScreen
                          ).controlLayerId === modelData.id
                          onClicked: WallpaperService.setControlLayer(
                            WallpaperService.stackForScope(
                              root.selectedScope, root.targetScreen
                            ).controlLayerId === modelData.id ? "" : modelData.id,
                            root.selectedScope, root.targetScreen
                          )
                        }

                        ActionButton {
                          width: 24
                          height: parent.height
                          label: "−"
                          onClicked: WallpaperService.setLayerOpacity(
                            modelData.id, Math.max(0, modelData.opacity - 0.1),
                            root.selectedScope, root.targetScreen
                          )
                        }

                        Text {
                          width: 38
                          height: parent.height
                          verticalAlignment: Text.AlignVCenter
                          horizontalAlignment: Text.AlignHCenter
                          text: Math.round(modelData.opacity * 100) + "%"
                          color: Theme.surfaceVariantText
                          font.family: Theme.monoFontFamily
                          font.pixelSize: Theme.fontSizeSmall
                        }

                        ActionButton {
                          width: 24
                          height: parent.height
                          label: "+"
                          onClicked: WallpaperService.setLayerOpacity(
                            modelData.id, Math.min(1, modelData.opacity + 0.1),
                            root.selectedScope, root.targetScreen
                          )
                        }

                        ActionButton {
                          width: 24
                          height: parent.height
                          label: "×"
                          onClicked: WallpaperService.removeLayer(
                            modelData.id, root.selectedScope, root.targetScreen
                          )
                        }
                      }

                      Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 30
                        horizontalAlignment: Text.AlignHCenter
                        text: WallpaperService.scrollLayerIdForScreen(root.targetScreen)
                          === modelData.id ? qsTr("Active control layer") : ""
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall - 1
                      }
                    }
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: layerList.count === 0
                text: qsTr("No layers in this target. Choose a wallpaper below.")
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }
            }

            Flickable {
              id: wallpaperLibrary
              width: parent.width
              height: parent.height - 32 - parent.spacing
                - (layerGraph.visible ? layerGraph.height + parent.spacing : 0)
              contentWidth: width
              contentHeight: wallpaperGroups.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: wallpaperGroups
                width: wallpaperLibrary.width
                height: implicitHeight
                spacing: Theme.spaceS

                Repeater {
                  id: wallpaperGroupRepeater
                  model: root.overviewMode ? WallpaperService.directoryGroups : []

                  delegate: Column {
                    id: directoryGroup
                    required property var modelData
                    readonly property bool collapsed: root.collapsedDirectories.indexOf(
                      directoryGroup.modelData.path
                    ) !== -1
                    readonly property int groupContentHeight: collapsed
                      ? 0
                      : directoryGroup.modelData.items.length > 0
                        ? Math.ceil(directoryGroup.modelData.items.length / 3) * 152
                        : 36
                    width: wallpaperGroups.width
                    height: 44 + (groupContentHeight > 0 ? Theme.spaceXS + groupContentHeight : 0)
                    spacing: groupContentHeight > 0 ? Theme.spaceXS : 0

                    Rectangle {
                      width: parent.width
                      height: 44
                      radius: Theme.cornerRadius
                      color: Theme.withAlpha(
                        Theme.widgetBaseBackgroundColor,
                        SettingsData.barWidgetTransparency
                      )
                      border.width: 1
                      border.color: Theme.withAlpha(Theme.outlineVariant, 0.5)

                      Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spaceXS
                        spacing: Theme.spaceS

                        Text {
                          width: parent.width - groupCount.width - collapseButton.width
                            - removeDirectoryButton.width - parent.spacing * 3
                          anchors.verticalCenter: parent.verticalCenter
                          text: directoryGroup.modelData.path
                          color: Theme.surfaceText
                          font.family: Theme.monoFontFamily
                          font.pixelSize: Theme.fontSizeSmall
                          elide: Text.ElideMiddle
                        }

                        Text {
                          id: groupCount
                          width: 76
                          anchors.verticalCenter: parent.verticalCenter
                          horizontalAlignment: Text.AlignRight
                          text: qsTr("%1 items").arg(directoryGroup.modelData.items.length)
                          color: Theme.surfaceVariantText
                          font.family: Theme.fontFamily
                          font.pixelSize: Theme.fontSizeSmall
                        }

                        Rectangle {
                          id: collapseButton
                          width: 36
                          height: parent.height
                          radius: Theme.hoverRadius
                          color: collapseMouse.containsMouse
                            ? Theme.withAlpha(Theme.primary, 0.2)
                            : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: directoryGroup.collapsed ? "›" : "⌄"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                          }

                          MouseArea {
                            id: collapseMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleDirectoryGroup(directoryGroup.modelData.path)
                          }
                        }

                        Rectangle {
                          id: removeDirectoryButton
                          width: 72
                          height: parent.height
                          radius: Theme.hoverRadius
                          color: removeDirectoryMouse.containsMouse
                            ? Theme.withAlpha(Theme.error, 0.2)
                            : Theme.withAlpha(Theme.error, 0.1)

                          Text {
                            anchors.centerIn: parent
                            text: qsTr("Remove")
                            color: Theme.surfaceText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                          }

                          MouseArea {
                            id: removeDirectoryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WallpaperService.removeDirectory(directoryGroup.modelData.path)
                          }
                        }
                      }
                    }

                    Item {
                      id: directoryItemsViewport
                      width: parent.width
                      height: directoryGroup.groupContentHeight
                      readonly property real viewportHeight: Math.min(
                        height, wallpaperLibrary.height
                      )
                      readonly property real scrollOffset: {
                        const localScroll = wallpaperLibrary.contentY
                          - mapToItem(wallpaperLibrary.contentItem, 0, 0).y
                        return Math.max(0, Math.min(
                          height - viewportHeight, localScroll
                        ))
                      }

                      GridView {
                        width: parent.width
                        height: directoryItemsViewport.viewportHeight
                        y: directoryItemsViewport.scrollOffset
                        contentY: directoryItemsViewport.scrollOffset
                        property int columnCount: 3
                        cellWidth: width / columnCount
                        cellHeight: 152
                        cacheBuffer: cellHeight
                        model: directoryGroup.collapsed
                          ? []
                          : directoryGroup.modelData.items
                        delegate: wallpaperDelegate
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: false
                        clip: true
                        visible: !directoryGroup.collapsed
                          && directoryGroup.modelData.items.length > 0
                      }

                      Text {
                        visible: !directoryGroup.collapsed
                          && directoryGroup.modelData.items.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("No supported media in this folder.")
                        color: Theme.surfaceVariantText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                      }
                    }
                  }
                }

                Text {
                  visible: root.overviewMode && WallpaperService.directoryGroups.length === 0
                  width: parent.width
                  height: 120
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  text: qsTr("No wallpaper folders added.\nAdd one or more folders to build your library.")
                  color: Theme.surfaceVariantText
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSizeMedium
                }
              }
            }
          }
        }

        Row {
          id: mediaControls
          width: parent.width
          height: 48
          spacing: Theme.spaceXS
          visible: WallpaperService.mediaHasAudio
            || (root.selectedType === "app" && root.selectedAppWindow !== null)

          ActionButton {
            id: playbackButton
            width: 92
            height: 40
            visible: WallpaperService.mediaHasAudio
            anchors.verticalCenter: parent.verticalCenter
            label: WallpaperService.mediaIsPlaying ? qsTr("Pause") : qsTr("Play")
            iconName: WallpaperService.mediaIsPlaying ? "pause" : "play_arrow"
            emphasized: true
            onClicked: WallpaperService.toggleMediaPlayback()
          }

          ActionButton {
            id: appPreviewButton
            width: 120
            visible: root.selectedType === "app" && root.selectedAppWindow !== null
            anchors.verticalCenter: parent.verticalCenter
            label: WallpaperService.appPreviewPaused
              ? qsTr("Resume preview")
              : qsTr("Pause preview")
            onClicked: WallpaperService.appPreviewPaused = !WallpaperService.appPreviewPaused
          }

          Text {
            visible: root.selectedType === "app" && root.selectedAppWindow === null
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("App preview unavailable")
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
          }

          Text {
            id: mediaPosition
            width: 40
            visible: WallpaperService.mediaHasAudio
            anchors.verticalCenter: parent.verticalCenter
            text: WallpaperService.formatMediaTime(WallpaperService.mediaPosition)
            color: Theme.surfaceVariantText
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall
          }

          Item {
            id: seekTrack
            visible: WallpaperService.mediaHasAudio
            width: Math.max(0, parent.width - playbackButton.width - mediaPosition.width
              - durationLabel.width - muteButton.width - volumeTrack.width - parent.spacing * 5)
            height: 24
            anchors.verticalCenter: parent.verticalCenter
            enabled: WallpaperService.mediaSeekable

            Rectangle {
              id: seekBackground
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: 4
              radius: Theme.pillRadius
              color: Theme.withAlpha(Theme.surfaceText, 0.2)
            }

            Rectangle {
              anchors.verticalCenter: seekBackground.verticalCenter
              width: WallpaperService.mediaDuration > 0
                ? seekBackground.width * Math.min(1, WallpaperService.mediaPosition
                  / WallpaperService.mediaDuration)
                : 0
              height: seekBackground.height
              radius: seekBackground.radius
              color: Theme.primary
            }

            MouseArea {
              anchors.fill: parent
              enabled: parent.enabled && WallpaperService.mediaDuration > 0
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onPressed: WallpaperService.seekMedia(
                Math.round(mouse.x / width * WallpaperService.mediaDuration)
              )
              onPositionChanged: {
                if (pressed)
                  WallpaperService.seekMedia(
                    Math.round(mouse.x / width * WallpaperService.mediaDuration)
                  )
              }
            }
          }

          Text {
            id: durationLabel
            width: 40
            visible: WallpaperService.mediaHasAudio
            anchors.verticalCenter: parent.verticalCenter
            text: WallpaperService.formatMediaTime(WallpaperService.mediaDuration)
            color: Theme.surfaceVariantText
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall
          }

          ActionButton {
            id: muteButton
            width: 104
            height: 40
            visible: WallpaperService.mediaHasAudio
            anchors.verticalCenter: parent.verticalCenter
            label: WallpaperService.mediaMuted ? qsTr("Unmute") : qsTr("Mute")
            iconName: WallpaperService.mediaMuted
              ? "volume_off"
              : WallpaperService.mediaVolume < 0.25
                ? "volume_down"
                : "volume_up"
            emphasized: WallpaperService.mediaMuted
            onClicked: WallpaperService.mediaMuted = !WallpaperService.mediaMuted
          }

          Item {
            id: volumeTrack
            visible: WallpaperService.mediaHasAudio
            width: 96
            height: 24
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              id: volumeBackground
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: 4
              radius: Theme.pillRadius
              color: Theme.withAlpha(Theme.surfaceText, 0.2)
            }

            Rectangle {
              anchors.verticalCenter: volumeBackground.verticalCenter
              width: volumeBackground.width * WallpaperService.mediaVolume
              height: volumeBackground.height
              radius: volumeBackground.radius
              color: Theme.primary
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onPressed: WallpaperService.setMediaVolume(mouse.x / width)
              onPositionChanged: {
                if (pressed)
                  WallpaperService.setMediaVolume(mouse.x / width)
              }
            }
          }
        }
      }
    }

    Item {
      id: appWindowPicker
      anchors.fill: panel
      visible: root.appPickerOpen && root.overviewMode
      z: 10

      Rectangle {
        anchors.fill: parent
        color: Theme.withAlpha(Theme.scrim, 0.42)

        MouseArea {
          anchors.fill: parent
          onClicked: root.appPickerOpen = false
        }
      }

      Rectangle {
        width: Math.min(parent.width - Theme.spaceXL * 2, 460)
        height: Math.min(parent.height - Theme.spaceXL * 2, 460)
        anchors.centerIn: parent
        radius: Theme.cornerRadius
        color: Theme.withAlpha(
          Theme.widgetBaseBackgroundColor,
          SettingsData.barWidgetTransparency
        )
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

        Column {
          anchors.fill: parent
          anchors.margins: Theme.spaceM
          spacing: Theme.spaceS

          Row {
            id: appPickerHeader
            width: parent.width
            height: 32
            spacing: Theme.spaceS

            Text {
              width: parent.width - closeAppPicker.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              text: qsTr("Choose an app preview")
              color: Theme.surfaceText
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeMedium
              font.weight: Font.Medium
              elide: Text.ElideRight
            }

            Rectangle {
              id: closeAppPicker
              width: 32
              height: parent.height
              radius: Theme.hoverRadius
              color: closeAppPickerMouse.containsMouse
                ? Theme.withAlpha(Theme.primary, 0.2)
                : "transparent"

              Text {
                anchors.centerIn: parent
                text: "×"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
              }

              MouseArea {
                id: closeAppPickerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.appPickerOpen = false
              }
            }
          }

          Text {
            id: appPickerDescription
            width: parent.width
            text: qsTr("Click a window to replace the target, or use Add layer to stack it.")
            color: Theme.surfaceVariantText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.Wrap
          }

          Item {
            width: parent.width
            height: parent.height - appPickerHeader.height
              - appPickerDescription.implicitHeight - parent.spacing * 2

            ListView {
              id: appWindowList
              anchors.fill: parent
              clip: true
              model: WallpaperService.appWindows
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                required property var modelData
                width: appWindowList.width
                height: 52
                radius: Theme.hoverRadius
                color: appWindowMouse.containsMouse
                  ? Theme.withAlpha(Theme.primary, 0.16)
                  : "transparent"

                Column {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  height: implicitHeight
                  anchors.leftMargin: Theme.spaceS
                  anchors.rightMargin: addAppWindowLayerButton.width + Theme.spaceS
                  spacing: Theme.spaceXS

                  Text {
                    width: parent.width
                    text: modelData.title
                    color: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    visible: modelData.appId.length > 0
                    text: modelData.appId
                    color: Theme.surfaceVariantText
                    font.family: Theme.monoFontFamily
                    font.pixelSize: Theme.fontSizeSmall - 1
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  id: appWindowMouse
                  anchors.fill: parent
                  anchors.rightMargin: addAppWindowLayerButton.width + Theme.spaceS
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (WallpaperService.setAppWindow(
                      modelData, SettingsData.wallpaperApplyScope, root.targetScreen
                    ))
                      root.appPickerOpen = false
                  }
                }

                ActionButton {
                  id: addAppWindowLayerButton
                  width: 84
                  height: 36
                  anchors.right: parent.right
                  anchors.rightMargin: Theme.spaceXS
                  anchors.verticalCenter: parent.verticalCenter
                  label: qsTr("Add layer")
                  emphasized: true
                  onClicked: {
                    if (WallpaperService.addAppWindowLayer(
                      parent.modelData, SettingsData.wallpaperApplyScope, root.targetScreen
                    ))
                      root.appPickerOpen = false
                  }
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: appWindowList.count === 0
              text: qsTr("No open app windows available.")
              color: Theme.surfaceVariantText
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }
          }
        }
      }
    }

    Item {
      id: quickSwitcher
      anchors.fill: parent
      visible: root.overlayVisible && !root.overviewMode
      focus: visible
      property int selectedIndex: 0
      property var previewItems: []
      property int previewImagesReady: 0
      property real scrollAccumulator: 0
      property bool scrollGestureConsumed: false
      property bool scopeMenuOpen: false

      function refreshPreviewItems() {
        quickSwitcher.previewItems = quickSwitcher.visible
          ? WallpaperService.switcherPreviewItems(quickSwitcher.selectedIndex, 3,
            WallpaperService.switcherApplyScope, root.targetScreen)
          : []
        quickSwitcher.previewImagesReady = Math.min(1, quickSwitcher.previewItems.length)
      }

      function refreshSelection() {
        quickSwitcher.selectedIndex = WallpaperService.currentSwitcherIndex(
          WallpaperService.switcherApplyScope, root.targetScreen
        )
        quickSwitcher.refreshPreviewItems()
      }

      function moveSelection(amount) {
        const count = WallpaperService.switcherItemCount(
          WallpaperService.switcherApplyScope, root.targetScreen
        )
        if (count > 0) {
          quickSwitcher.selectedIndex = (quickSwitcher.selectedIndex + amount
            + count) % count
          quickSwitcher.refreshPreviewItems()
        }
      }

      function consumeScrollDelta(delta) {
        quickSwitcher.scrollAccumulator += delta
        if (!quickSwitcher.scrollGestureConsumed
            && Math.abs(quickSwitcher.scrollAccumulator) >= 24) {
          quickSwitcher.scrollGestureConsumed = true
          quickSwitcher.moveSelection(quickSwitcher.scrollAccumulator > 0 ? -1 : 1)
        }
        scrollGestureTimer.restart()
      }

      function finishScrollGesture() {
        quickSwitcher.scrollAccumulator = 0
        quickSwitcher.scrollGestureConsumed = false
      }

      function applySelection() {
        if (WallpaperService.applySwitcherItem(quickSwitcher.selectedIndex,
          WallpaperService.switcherApplyScope, root.targetScreen))
          WallpaperService.closeOverlay()
      }

      onVisibleChanged: {
        if (visible) {
          quickSwitcher.scopeMenuOpen = false
          quickSwitcher.refreshSelection()
        } else {
          quickSwitcher.scopeMenuOpen = false
          quickSwitcher.previewItems = []
          quickSwitcher.previewImagesReady = 0
          quickSwitcher.scrollAccumulator = 0
          quickSwitcher.scrollGestureConsumed = false
          scrollGestureTimer.stop()
        }
      }

      Timer {
        id: scrollGestureTimer
        interval: 120
        onTriggered: quickSwitcher.finishScrollGesture()
      }

      Timer {
        interval: 100
        repeat: true
        running: quickSwitcher.visible
          && quickSwitcher.previewImagesReady < quickSwitcher.previewItems.length
        onTriggered: quickSwitcher.previewImagesReady += 1
      }

      Connections {
        target: WallpaperService
        function onSourceChanged() {
          if (quickSwitcher.visible)
            quickSwitcher.refreshSelection()
        }
        function onItemsChanged() {
          if (quickSwitcher.visible)
            quickSwitcher.refreshSelection()
        }
      }

      Connections {
        target: SettingsData
        function onWallpaperWorkspaceOverridesChanged() {
          if (quickSwitcher.visible)
            quickSwitcher.refreshSelection()
        }
        function onWallpaperStacksChanged() {
          if (quickSwitcher.visible)
            quickSwitcher.refreshSelection()
        }
      }

      WheelHandler {
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        target: null
        onWheel: function(event) {
          const delta = event.pixelDelta.x !== 0
            ? event.pixelDelta.x
            : event.angleDelta.x
          if (delta !== 0)
            quickSwitcher.consumeScrollDelta(delta)
          event.accepted = true
        }
      }

      WheelHandler {
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        target: null
        onWheel: function(event) {
          const delta = event.pixelDelta.y !== 0
            ? event.pixelDelta.y
            : event.angleDelta.y
          if (delta !== 0)
            quickSwitcher.consumeScrollDelta(delta)
          event.accepted = true
        }
      }

      Rectangle {
        id: switcherScopeButton
        width: 280
        height: 36
        x: (parent.width - width) / 2
        y: parent.height * 0.045
        radius: Theme.hoverRadius
        color: scopeButtonMouse.containsMouse
          ? Theme.withAlpha(Theme.primary, 0.24)
          : Theme.withAlpha(Theme.surfaceContainerHigh, 0.9)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.7)
        z: 2

        Text {
          anchors.fill: parent
          anchors.margins: Theme.spaceS
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
          text: qsTr("Apply to: %1  ·  Shift toggles").arg(
            WallpaperService.targetLabelForScope(
              WallpaperService.switcherApplyScope, root.targetScreen
            )
          )
          color: Theme.surfaceText
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall
          elide: Text.ElideRight
        }

        MouseArea {
          id: scopeButtonMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: quickSwitcher.scopeMenuOpen = !quickSwitcher.scopeMenuOpen
        }
      }

      Rectangle {
        id: switcherScopeMenu
        width: switcherScopeButton.width
        height: scopeMenuColumn.implicitHeight + Theme.spaceXS * 2
        x: switcherScopeButton.x
        y: switcherScopeButton.y + switcherScopeButton.height + Theme.spaceXS
        visible: quickSwitcher.scopeMenuOpen
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)
        z: 3

        Column {
          id: scopeMenuColumn
          anchors.fill: parent
          anchors.margins: Theme.spaceXS
          spacing: Theme.spaceXS

          Repeater {
            model: ["global", "monitor", "workspace"]

            delegate: Rectangle {
              required property string modelData
              width: scopeMenuColumn.width
              height: 36
              radius: Theme.hoverRadius
              color: switcherScopeRowMouse.containsMouse
                ? Theme.withAlpha(Theme.primary, 0.2)
                : WallpaperService.switcherApplyScope === modelData
                  ? Theme.withAlpha(Theme.primary, 0.12)
                  : "transparent"
              opacity: modelData === "global"
                || (modelData === "monitor"
                  && WallpaperService.monitorKeyForScreen(root.targetScreen).length > 0)
                || (modelData === "workspace"
                  && WallpaperService.workspaceKeyForScreen(root.targetScreen).length > 0)
                ? 1 : 0.55

              Text {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceS
                anchors.rightMargin: Theme.spaceS
                verticalAlignment: Text.AlignVCenter
                text: WallpaperService.targetLabelForScope(
                  modelData, root.targetScreen
                )
                color: Theme.surfaceText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
              }

              MouseArea {
                id: switcherScopeRowMouse
                anchors.fill: parent
                enabled: modelData === "global"
                  || (modelData === "monitor"
                    && WallpaperService.monitorKeyForScreen(root.targetScreen).length > 0)
                  || (modelData === "workspace"
                    && WallpaperService.workspaceKeyForScreen(root.targetScreen).length > 0)
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (WallpaperService.setSwitcherApplyScope(modelData)) {
                    quickSwitcher.scopeMenuOpen = false
                    quickSwitcher.refreshSelection()
                  }
                }
              }
            }
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: switcherScopeButton.bottom
        anchors.topMargin: Theme.spaceXS
        visible: quickSwitcher.visible && WallpaperService.error.length > 0
        text: WallpaperService.error
        color: Theme.error
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
      }

      Item {
        id: switcherStage
        x: parent.width * 0.075
        y: parent.height * 0.14
        width: parent.width * 0.85
        height: parent.height * 0.72
        clip: true

        Item {
          id: switcherCards
          anchors.fill: parent
          clip: true

          Row {
            id: switcherCardRow
            width: implicitWidth
            property real cardWidth: Math.min(switcherCards.width * 0.68, switcherCards.height * 1.7)
            height: switcherCards.height
            spacing: Theme.spaceM

            Repeater {
              model: quickSwitcher.previewItems

              delegate: Item {
                required property string modelData
                required property int index
                width: switcherCardRow.cardWidth
                height: switcherCardRow.height
                opacity: index === 0 ? 1 : 0.66

                Rectangle {
                  anchors.fill: parent
                  radius: Theme.cornerRadius
                  color: modelData.startsWith("#")
                    ? Qt.color(modelData)
                    : Theme.withAlpha(
                      Theme.widgetBaseBackgroundColor,
                      SettingsData.barWidgetTransparency
                    )
                  border.width: index === 0 ? 3 : 1
                  border.color: index === 0
                    ? Theme.primary
                    : Theme.withAlpha(Theme.outlineVariant, 0.8)
                  clip: true

                  AnimatedImage {
                    anchors.fill: parent
                    source: index < quickSwitcher.previewImagesReady
                      && !modelData.startsWith("#")
                      && WallpaperService.typeForSwitcherItem(modelData,
                        WallpaperService.switcherApplyScope, root.targetScreen) === "image"
                      && (!root.isGifSource(modelData) || root.gifAnimationDelayElapsed)
                      ? modelData
                      : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    playing: !root.isGifSource(modelData) || root.gifAnimationDelayElapsed
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: WallpaperService.typeForSwitcherItem(modelData,
                      WallpaperService.switcherApplyScope, root.targetScreen) !== "image"
                      && !modelData.startsWith("#")
                    text: WallpaperService.typeForSwitcherItem(modelData,
                      WallpaperService.switcherApplyScope, root.targetScreen).toUpperCase()
                    color: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 64
                    color: Theme.withAlpha(
                      Theme.widgetBaseBackgroundColor,
                      SettingsData.barWidgetTransparency
                    )

                    Column {
                      anchors.fill: parent
                      anchors.margins: Theme.spaceM
                      spacing: Theme.spaceXS

                      Text {
                        width: parent.width
                        text: String(modelData).split("/").pop()
                        color: Theme.surfaceText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        elide: Text.ElideMiddle
                      }

                      Text {
                        text: index === 0
                          ? qsTr("Selected · Enter to apply")
                          : qsTr("Click to select")
                        color: Theme.surfaceVariantText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                      }

                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (index === 0)
                        quickSwitcher.applySelection()
                      else
                        quickSwitcher.moveSelection(index)
                    }
                  }

                }
              }
            }
          }
        }

      }

      Text {
        anchors.centerIn: switcherStage
        visible: quickSwitcher.visible && quickSwitcher.previewItems.length === 0
        text: qsTr("No wallpapers available. Add a folder in the library.")
        color: Theme.surfaceText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
      }

      Text {
        anchors.left: switcherStage.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.075
        text: qsTr("Swipe or ← → browse · Shift toggles target · Enter apply · Esc close")
        color: Theme.surfaceText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
      }
    }

    Component {
      id: wallpaperDelegate

      Item {
        required property string modelData
        required property int index
        width: GridView.view.cellWidth
        height: GridView.view.cellHeight
        property bool previewActivated: false
        readonly property bool selectedInStack: WallpaperService.layersForTarget(
          root.selectedScope, root.targetScreen
        ).some(layer => layer.source === modelData)
        readonly property bool previewNearViewport: {
          const itemTop = mapToItem(wallpaperLibrary.contentItem, 0, 0).y
          const scrollTop = wallpaperLibrary.contentY
          return root.overviewMode
            && itemTop + height >= scrollTop - height
            && itemTop <= scrollTop + wallpaperLibrary.height + height
        }
        Component.onCompleted: {
          if (previewNearViewport)
            previewActivated = true
        }
        onPreviewNearViewportChanged: {
          if (previewNearViewport)
            previewActivated = true
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: Theme.spaceXS
          radius: Theme.cornerRadius
          color: parent.parent.selectedInStack
            ? Theme.withAlpha(Theme.primary, 0.22)
            : Theme.withAlpha(
              Theme.widgetBaseBackgroundColor,
              SettingsData.barWidgetTransparency
            )
          border.width: parent.parent.selectedInStack ? 2 : 1
          border.color: parent.parent.selectedInStack
            ? Theme.primary
            : Theme.withAlpha(Theme.outlineVariant, 0.65)
          clip: true

          AnimatedImage {
            anchors.fill: parent
            source: parent.parent.previewActivated
              && WallpaperService.typeForSource(parent.parent.modelData) === "image"
              && (!root.isGifSource(parent.parent.modelData) || root.gifAnimationDelayElapsed)
              ? parent.parent.modelData
              : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(240, 120)
            asynchronous: true
            cache: true
            playing: !root.isGifSource(parent.parent.modelData)
              || (parent.parent.previewActivated && root.gifAnimationDelayElapsed)
            opacity: status === Image.Ready ? 1 : 0

            Behavior on opacity {
              NumberAnimation {
                duration: 100
                easing.type: Theme.standardEasing
              }
            }
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.spaceXS
            height: 28
            verticalAlignment: Text.AlignVCenter
            text: String(parent.parent.modelData).split("/").pop()
            color: Theme.surfaceText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideMiddle
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              WallpaperService.setSource(modelData, undefined,
                SettingsData.wallpaperApplyScope, root.targetScreen)
              if (!root.overviewMode)
                WallpaperService.closeOverlay()
            }
          }

          ActionButton {
            visible: root.overviewMode
            width: 32
            height: 32
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.spaceS
            label: "+"
            emphasized: true
            onClicked: WallpaperService.addLayer(
              parent.parent.modelData, undefined,
              SettingsData.wallpaperApplyScope, root.targetScreen
            )
          }
        }
      }
    }
  }

  component ActionButton: Rectangle {
    required property string label
    property string iconName: ""
    property bool emphasized: false
    signal clicked

    height: 36
    radius: Theme.cornerRadius
    opacity: enabled ? 1 : 0.55
    color: actionMouse.containsMouse
      ? Theme.withAlpha(Theme.primary, 0.2)
      : emphasized
        ? Theme.withAlpha(Theme.primaryContainer, 0.9)
        : Theme.withAlpha(Theme.surfaceContainerHigh, 0.75)
    border.width: 1
    border.color: emphasized || actionMouse.containsMouse
      ? Theme.primary
      : Theme.withAlpha(Theme.outlineVariant, 0.55)

    DmsIcon {
      visible: parent.iconName.length > 0
      anchors.left: parent.left
      anchors.leftMargin: Theme.spaceS
      anchors.verticalCenter: parent.verticalCenter
      name: parent.iconName
      size: 18
      color: parent.emphasized ? Theme.primary : Theme.surfaceText
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: parent.iconName.length > 0
        ? Theme.spaceS + 18 + Theme.spaceXS
        : Theme.spaceS
      anchors.right: parent.right
      anchors.rightMargin: Theme.spaceS
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      color: Theme.surfaceText
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSmall
      elide: Text.ElideRight
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      enabled: parent.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.clicked()
    }
  }

  FileDialog {
    id: mediaDialog
    title: qsTr("Choose wallpaper media")
    fileMode: FileDialog.OpenFile
    currentFolder: WallpaperService.urlForPath(
      StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/"
    )
    nameFilters: [
      qsTr("Wallpapers and media (*.png *.jpg *.jpeg *.webp *.bmp *.gif *.avif *.mp3 *.m4a *.aac *.ogg *.opus *.flac *.wav *.wma *.aiff *.alac *.mp4 *.m4v *.webm *.mov *.mkv *.avi *.av1 *.m3u8 *.mpd *.qml *.glb *.gltf *.mesh)"),
      qsTr("All files (*)")
    ]
    onAccepted: {
      if (root.chooserAddLayer)
        WallpaperService.addLayer(selectedFile.toString(), undefined,
          root.chooserScope, root.targetScreen)
      else
        WallpaperService.setSource(selectedFile.toString(), undefined,
          root.chooserScope, root.targetScreen)
      root.chooserOpen = false
      root.chooserAddLayer = false
    }
    onRejected: {
      root.chooserOpen = false
      root.chooserAddLayer = false
    }
  }

  FolderDialog {
    id: folderDialog
    title: qsTr("Add a wallpaper folder")
    currentFolder: WallpaperService.urlForPath(
      StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/"
    )
    onAccepted: {
      WallpaperService.addDirectory(selectedFolder)
      root.chooserOpen = false
    }
    onRejected: root.chooserOpen = false
  }

  Connections {
    target: WallpaperService
    function onFileChooserFallback(operation, screen, scope) {
      if (screen !== root.targetScreen)
        return
      root.chooserScope = scope
      root.chooserAddLayer = operation === "media-layer"
      root.chooserOpen = true
      Qt.callLater(function() {
        if (operation === "media" || operation === "media-layer")
          mediaDialog.open()
        else
          folderDialog.open()
      })
    }
  }

  function applyUrl(addAsLayer) {
    const url = urlInput.text.trim()
    if (!/^https?:\/\//i.test(url)) {
      WallpaperService.error = qsTr("Enter a valid http or https media URL.")
      return
    }
    if (addAsLayer)
      WallpaperService.addLayer(url, "video",
        SettingsData.wallpaperApplyScope, root.targetScreen)
    else
      WallpaperService.setSource(url, "video",
        SettingsData.wallpaperApplyScope, root.targetScreen)
  }
}
