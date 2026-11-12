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
  readonly property string source: WallpaperService.sourceForTarget(
    "workspace", root.targetScreen
  )
  readonly property string sourceType: WallpaperService.typeForTarget(
    "workspace", root.targetScreen
  )
  readonly property bool sourceIsImage: root.sourceType === "image"
    && WallpaperService.typeForSource(root.source) === "image"
  readonly property url sourceUrl: sourceType === "app" || source.startsWith("#")
    ? ""
    : (source.includes("://") ? source : WallpaperService.urlForPath(source))
  readonly property var appSource: sourceType === "app"
    ? WallpaperService.appWindowForSource(source)
    : null

  function resolveActiveMedia() {
    if (root.sourceType === "video" || root.sourceType === "audio")
      WallpaperService.resolveMediaSource(root.source, root.sourceType, false)
    if (root.sourceType === "audio")
      WallpaperService.ensureAudioWaveform(root.source)
  }

  function requestSurfaceRefresh() {
    root.backingWindow?.update()
    surfaceRecoveryTimer.restart()
  }

  Component.onCompleted: {
    root.resolveActiveMedia()
    Qt.callLater(root.requestSurfaceRefresh)
  }
  onSourceChanged: {
    root.resolveActiveMedia()
    root.requestSurfaceRefresh()
  }
  onSourceTypeChanged: {
    root.resolveActiveMedia()
    root.requestSurfaceRefresh()
  }
  onSourceUrlChanged: {
    if (videoLoader.item) {
      videoLoader.item.savePlaybackState()
      videoLoader.item.mediaSource = root.sourceUrl
    }
    root.requestSurfaceRefresh()
  }
  onTargetScreenChanged: {
    if (videoLoader.item)
      videoLoader.item.targetScreen = root.targetScreen
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
    color: root.sourceType === "color"
      && /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(root.source)
      ? Qt.color(root.source)
      : Theme.surface

    AnimatedImage {
      anchors.fill: parent
      source: root.sourceIsImage ? root.sourceUrl : ""
      fillMode: SettingsData.wallpaperFit === "contain" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      playing: root.sourceIsImage && status === Image.Ready
      visible: root.sourceIsImage
      onStatusChanged: {
        if (status === Image.Error)
          WallpaperService.error = qsTr("Could not load this wallpaper image.")
      }
    }

    Loader {
      id: videoLoader
      anchors.fill: parent
      active: root.sourceType === "video" || root.sourceType === "audio"
      source: active ? Qt.resolvedUrl("WallpaperVideo.qml") : ""
      asynchronous: true
      onLoaded: {
        item.mediaSource = root.sourceUrl
        item.targetScreen = root.targetScreen
        root.resolveActiveMedia()
      }
      onStatusChanged: {
        if (status === Loader.Error)
          WallpaperService.error = qsTr("Could not load the wallpaper media player. Check the Quickshell log for details.")
      }
    }

    Loader {
      anchors.fill: parent
      active: root.sourceType === "scene"
      source: active ? root.sourceUrl : ""
      onStatusChanged: {
        if (status === Loader.Error)
          WallpaperService.error = qsTr("Could not load this QML wallpaper scene.")
      }
      asynchronous: true
    }

    Loader {
      anchors.fill: parent
      active: root.sourceType === "model3d"
      source: active ? Qt.resolvedUrl("Wallpaper3D.qml") : ""
      asynchronous: true
      onLoaded: item.modelSource = root.sourceUrl
      onStatusChanged: {
        if (status === Loader.Error)
          WallpaperService.error = qsTr("3D wallpaper support requires the Qt Quick 3D QML module.")
      }
    }

    ScreencopyView {
      anchors.fill: parent
      visible: root.sourceType === "app"
      captureSource: root.appSource
      live: visible && root.appSource !== null
        && !WallpaperService.appPreviewPaused
      onLiveChanged: {
        if (!live && captureSource)
          captureFrame()
      }
    }
  }
}
