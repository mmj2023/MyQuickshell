import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Services

Item {
  id: root

  property var layerData: ({})
  property var targetScreen: null
  property int layerIndex: 0
  property bool scrollControlsEnabled: false
  readonly property string layerId: String(root.layerData.id || "")
  readonly property string source: String(root.layerData.source || "")
  readonly property string sourceType: String(root.layerData.type || "image")
  readonly property real layerOpacity: Math.max(
    0, Math.min(1, Number(root.layerData.opacity ?? 1))
  )
  readonly property url sourceUrl: root.sourceType === "app" || root.source.startsWith("#")
    ? ""
    : (root.source.includes("://") ? root.source : WallpaperService.urlForPath(root.source))

  opacity: root.layerOpacity
  z: root.layerIndex

  function syncMediaLayer() {
    if (!mediaLoader.item)
      return
    const nextSource = String(root.sourceUrl)
    if (String(mediaLoader.item.mediaSource) !== nextSource)
      mediaLoader.item.savePlaybackState()
    mediaLoader.item.mediaSource = root.sourceUrl
    mediaLoader.item.targetScreen = root.targetScreen
    mediaLoader.item.layerId = root.layerId
    mediaLoader.item.scrollControlsEnabled = root.scrollControlsEnabled
  }

  function syncModelLayer() {
    if (!modelLoader.item)
      return
    const item = modelLoader.item
    const nextSource = root.sourceUrl
    if (item.layerId !== root.layerId || item.targetScreen !== root.targetScreen
        || String(item.modelSource) !== String(nextSource))
      item.saveModelState()
    item.layerId = root.layerId
    item.targetScreen = root.targetScreen
    item.modelSource = nextSource
  }

  Rectangle {
    anchors.fill: parent
    visible: root.sourceType === "color"
    color: /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(root.source)
      ? Qt.color(root.source)
      : Theme.surface
  }

  AnimatedImage {
    anchors.fill: parent
    source: root.sourceType === "image" ? root.sourceUrl : ""
    fillMode: SettingsData.wallpaperFit === "contain"
      ? Image.PreserveAspectFit : Image.PreserveAspectCrop
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
    id: mediaLoader
    anchors.fill: parent
    active: root.sourceType === "video" || root.sourceType === "audio"
    source: active ? Qt.resolvedUrl("WallpaperVideo.qml") : ""
    asynchronous: true
    onLoaded: root.syncMediaLayer()
    onStatusChanged: {
      if (status === Loader.Error)
        WallpaperService.error = qsTr("Could not load the wallpaper media player. Check the Quickshell log for details.")
    }
  }

  Loader {
    anchors.fill: parent
    active: root.sourceType === "scene"
    source: active ? root.sourceUrl : ""
    asynchronous: true
    onStatusChanged: {
      if (status === Loader.Error)
        WallpaperService.error = qsTr("Could not load this QML wallpaper scene.")
    }
  }

  Loader {
    id: modelLoader
    anchors.fill: parent
    active: root.sourceType === "model3d"
    source: active ? Qt.resolvedUrl("Wallpaper3D.qml") : ""
    asynchronous: true
    onLoaded: root.syncModelLayer()
    onStatusChanged: {
      if (status === Loader.Error)
        WallpaperService.error = qsTr("3D wallpaper support requires the Qt Quick 3D QML module.")
    }
  }

  ScreencopyView {
    anchors.fill: parent
    visible: root.sourceType === "app"
    captureSource: WallpaperService.appWindowForSource(root.source)
    live: visible && captureSource !== null && !WallpaperService.appPreviewPaused
    onLiveChanged: {
      if (!live && captureSource)
        captureFrame()
    }
  }

  onLayerDataChanged: {
    root.syncMediaLayer()
    root.syncModelLayer()
  }
  onTargetScreenChanged: {
    root.syncMediaLayer()
    root.syncModelLayer()
  }
  onScrollControlsEnabledChanged: root.syncMediaLayer()
}
