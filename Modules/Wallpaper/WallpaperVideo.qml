import QtQuick
import QtMultimedia
import qs.Modules.Wallpaper
import qs.Services

Item {
  id: root

  property url mediaSource: ""
  property var targetScreen: null
  readonly property bool audioOwner: WallpaperService.isMediaAudioOwner(root.targetScreen)
  property real zoomFactor: 1
  property real horizontalOffset: 0
  property real verticalOffset: 0
  property real pinchStartZoom: 1
  readonly property real maximumHorizontalOffset: width * (0.25 + (zoomFactor - 1) / 2)
  readonly property real maximumVerticalOffset: height * (0.25 + (zoomFactor - 1) / 2)
  readonly property bool hasSeparateAudio:
    WallpaperService.mediaAudioSourceFor(root.mediaSource).length > 0
  readonly property bool hasAudio: root.hasSeparateAudio || mediaPlayer.hasAudio
  readonly property bool isPlaying: mediaPlayer.playbackState === MediaPlayer.PlayingState
  readonly property bool seekable: mediaPlayer.seekable
  readonly property int position: mediaPlayer.position
  readonly property int duration: mediaPlayer.duration

  function panVideo(horizontalDelta, verticalDelta) {
    root.horizontalOffset = Math.max(
      -root.maximumHorizontalOffset,
      Math.min(root.maximumHorizontalOffset, root.horizontalOffset + horizontalDelta)
    )
    root.verticalOffset = Math.max(
      -root.maximumVerticalOffset,
      Math.min(root.maximumVerticalOffset, root.verticalOffset + verticalDelta)
    )
  }

  function zoomVideo(delta) {
    root.setVideoZoom(root.zoomFactor * Math.exp(delta * 0.003))
  }

  function setVideoZoom(value) {
    root.zoomFactor = Math.max(1, Math.min(3, value))
    root.horizontalOffset = Math.max(
      -root.maximumHorizontalOffset,
      Math.min(root.maximumHorizontalOffset, root.horizontalOffset)
    )
    root.verticalOffset = Math.max(
      -root.maximumVerticalOffset,
      Math.min(root.maximumVerticalOffset, root.verticalOffset)
    )
  }

  function resetVideoView() {
    root.zoomFactor = 1
    root.horizontalOffset = 0
    root.verticalOffset = 0
    root.pinchStartZoom = 1
  }

  function togglePlayback() {
    if (root.isPlaying)
      mediaPlayer.pause()
    else
      mediaPlayer.play()
    root.syncSeparateAudio()
  }

  function seekTo(position) {
    if (root.seekable)
      mediaPlayer.seek(position)
    if (root.hasSeparateAudio && separateAudioPlayer.seekable)
      separateAudioPlayer.seek(position)
  }

  function syncSeparateAudio() {
    if (!root.hasSeparateAudio || !root.audioOwner) {
      separateAudioPlayer.pause()
      return
    }

    if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
      if (separateAudioPlayer.seekable
          && Math.abs(separateAudioPlayer.position - mediaPlayer.position) > 500) {
        separateAudioPlayer.seek(mediaPlayer.position)
      }
      separateAudioPlayer.play()
    } else if (mediaPlayer.playbackState === MediaPlayer.PausedState) {
      separateAudioPlayer.pause()
    } else {
      separateAudioPlayer.stop()
    }
  }

  function updateAudioRegistration() {
    if (root.audioOwner)
      WallpaperService.registerMediaController(root)
    else
      WallpaperService.unregisterMediaController(root)
  }

  Component.onCompleted: root.updateAudioRegistration()
  Component.onDestruction: WallpaperService.unregisterMediaController(root)
  onAudioOwnerChanged: {
    root.updateAudioRegistration()
    root.syncSeparateAudio()
  }
  onMediaSourceChanged: {
    root.resetVideoView()
  }

  Item {
    anchors.fill: parent

    clip: true

    WallpaperAudioVisualizer {
      anchors.fill: parent
      z: 1
      visible: !mediaPlayer.hasVideo && root.hasAudio
      audioSource: root.mediaSource
      position: mediaPlayer.position
      duration: mediaPlayer.duration
      playing: root.isPlaying
    }

    Video {
      id: mediaPlayer
      width: parent.width * root.zoomFactor
      height: parent.height * root.zoomFactor
      x: (parent.width - width) / 2 + root.horizontalOffset
      y: (parent.height - height) / 2 + root.verticalOffset
      source: WallpaperService.mediaVideoSourceFor(root.mediaSource)
      fillMode: VideoOutput.PreserveAspectCrop
      loops: MediaPlayer.Infinite
      autoPlay: true
      visible: hasVideo
      muted: !root.audioOwner || WallpaperService.mediaMuted || root.hasSeparateAudio
      volume: WallpaperService.mediaVolume
      onPlaybackStateChanged: root.syncSeparateAudio()
      onErrorOccurred: function(error, errorString) {
        WallpaperService.error = qsTr("Could not play this media or stream: ") + errorString
      }
    }

    MediaPlayer {
      id: separateAudioPlayer
      source: WallpaperService.mediaAudioSourceFor(root.mediaSource)
      autoPlay: false
      loops: MediaPlayer.Infinite
      audioOutput: AudioOutput {
        volume: root.audioOwner && !WallpaperService.mediaMuted
          ? WallpaperService.mediaVolume
          : 0
      }
      onMediaStatusChanged: {
        if (mediaStatus === MediaPlayer.LoadedMedia
            || mediaStatus === MediaPlayer.BufferedMedia) {
          root.syncSeparateAudio()
        }
      }
      onErrorOccurred: function(error, errorString) {
        WallpaperService.error = qsTr("Could not play the separate audio stream: ")
          + errorString
      }
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.hasSeparateAudio && root.audioOwner && root.isPlaying
    onTriggered: root.syncSeparateAudio()
  }

  WheelHandler {
    orientation: Qt.Horizontal
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    target: null
    onWheel: function(event) {
      const delta = event.pixelDelta.x !== 0
        ? event.pixelDelta.x
        : event.angleDelta.x / 120 * 24
      if (mediaPlayer.hasVideo)
        root.panVideo(delta, 0)
      event.accepted = true
    }
  }

  WheelHandler {
    orientation: Qt.Vertical
    acceptedDevices: PointerDevice.TouchPad
    target: null
    onWheel: function(event) {
      const delta = event.pixelDelta.y !== 0
        ? event.pixelDelta.y
        : event.angleDelta.y / 120 * 24
      if (mediaPlayer.hasVideo)
        root.panVideo(0, delta)
      event.accepted = true
    }
  }

  WheelHandler {
    orientation: Qt.Vertical
    acceptedDevices: PointerDevice.Mouse
    target: null
    onWheel: function(event) {
      const delta = event.pixelDelta.y !== 0
        ? event.pixelDelta.y
        : event.angleDelta.y / 120 * 24
      if (mediaPlayer.hasVideo)
        root.zoomVideo(delta)
      event.accepted = true
    }
  }

  TapHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.TouchScreen
    acceptedButtons: Qt.LeftButton
    onDoubleTapped: root.resetVideoView()
  }

  PinchHandler {
    id: pinchHandler
    acceptedDevices: PointerDevice.TouchPad | PointerDevice.TouchScreen
    target: null
    onActiveChanged: {
      if (active)
        root.pinchStartZoom = root.zoomFactor
    }
    onScaleChanged: {
      if (active)
        root.setVideoZoom(root.pinchStartZoom * pinchHandler.activeScale)
    }
  }
}
