import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Common
import qs.Services

PanelWindow {
  id: root

  property var targetScreen: null
  readonly property var backingWindow: wallpaperContent.backingWindow
  readonly property var layers: WallpaperService.effectiveStackForScreen(
    root.targetScreen
  ).layers

  function resolveActiveMedia() {
    for (const layer of root.layers) {
      if (layer.type === "video" || layer.type === "audio")
        WallpaperService.resolveMediaSource(layer.source, layer.type, false)
      if (layer.type === "audio")
        WallpaperService.ensureAudioWaveform(layer.source)
    }
  }

  function requestSurfaceRefresh() {
    root.backingWindow?.update()
    surfaceRecoveryTimer.restart()
  }

  Component.onCompleted: {
    root.resolveActiveMedia()
    Qt.callLater(root.requestSurfaceRefresh)
  }
  onLayersChanged: {
    root.resolveActiveMedia()
    root.requestSurfaceRefresh()
  }
  onTargetScreenChanged: {
    root.resolveActiveMedia()
    root.requestSurfaceRefresh()
  }

  screen: root.targetScreen
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  surfaceFormat.opaque: false
  WlrLayershell.namespace: "myquickshell-wallpaper"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Timer {
    id: surfaceRecoveryTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (!root.visible || !root.backingWindow)
        return
      console.warn("Wallpaper surface stopped presenting frames; reattaching it.")
      root.visible = false
      Qt.callLater(function() {
        root.visible = true
        root.backingWindow?.update()
      })
    }
  }

  Connections {
    target: root.backingWindow
    function onFrameSwapped() {
      surfaceRecoveryTimer.stop()
    }
    function onVisibleChanged() {
      root.requestSurfaceRefresh()
    }
    function onWidthChanged() {
      root.requestSurfaceRefresh()
    }
    function onHeightChanged() {
      root.requestSurfaceRefresh()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      Qt.callLater(root.requestSurfaceRefresh)
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded")
        Qt.callLater(root.requestSurfaceRefresh)
    }
  }

  Connections {
    target: root
    function onResourcesLost() {
      Qt.callLater(root.requestSurfaceRefresh)
    }
  }

  Rectangle {
    id: wallpaperContent
    readonly property var backingWindow: Window.window

    anchors.fill: parent
    color: Theme.surface

    Repeater {
      model: root.layers

      delegate: WallpaperLayer {
        required property var modelData
        required property int index

        anchors.fill: parent
        layerData: modelData
        layerIndex: index
        targetScreen: root.targetScreen
        scrollControlsEnabled: WallpaperService.scrollLayerIdForScreen(
          root.targetScreen
        ) === modelData.id
      }
    }
  }
}
