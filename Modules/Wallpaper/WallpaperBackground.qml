import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

PanelWindow {
  id: root

  property var targetScreen: null
  readonly property string source: WallpaperService.sourceForTarget(
    "workspace", root.targetScreen
  )
  readonly property string sourceType: WallpaperService.typeForTarget(
    "workspace", root.targetScreen
  )
  readonly property url sourceUrl: sourceType === "app" || source.startsWith("#")
    ? ""
    : (source.includes("://") ? source : WallpaperService.urlForPath(source))
  readonly property var appSource: sourceType === "app"
    ? WallpaperService.appWindowForSource(source)
    : null

  function resolveActiveMedia() {
    if (root.sourceType === "video" || root.sourceType === "audio")
      WallpaperService.resolveMediaSource(root.source, root.sourceType, false)
  }

  Component.onCompleted: root.resolveActiveMedia()
  onSourceChanged: root.resolveActiveMedia()
  onSourceTypeChanged: root.resolveActiveMedia()
  onSourceUrlChanged: {
    if (videoLoader.item)
      videoLoader.item.mediaSource = root.sourceUrl
  }
  onTargetScreenChanged: {
    if (videoLoader.item)
      videoLoader.item.targetScreen = root.targetScreen
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

  Rectangle {
    anchors.fill: parent
    color: root.sourceType === "color"
      && /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(root.source)
      ? Qt.color(root.source)
      : Theme.surface

    AnimatedImage {
      anchors.fill: parent
      source: root.sourceType === "image" ? root.sourceUrl : ""
      fillMode: SettingsData.wallpaperFit === "contain" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      playing: root.sourceType === "image" && status === Image.Ready
      visible: root.sourceType === "image"
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
          WallpaperService.error = qsTr("Media playback is unavailable; install the Qt Multimedia QML module.")
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
