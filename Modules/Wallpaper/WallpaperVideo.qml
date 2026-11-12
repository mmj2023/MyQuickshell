import QtQuick
import QtMultimedia
import qs.Modules.Wallpaper
import qs.Services

Item {
  id: root

  property url mediaSource: ""
  property var targetScreen: null
  property string layerId: ""
  property bool scrollControlsEnabled: false
  property string sessionSource: ""
  property var registeredScreen: null
  property string registeredLayerId: ""
  property bool playbackStateRestored: false
  property bool restoringPlaybackState: false
  property int pendingRestorePosition: -1
  property bool restoreSeekRequested: false
  readonly property bool audioOwner: WallpaperService.isMediaAudioOwner(
    root.targetScreen, root.layerId
  )
  property real zoomFactor: 1
  property real horizontalOffset: 0
  property real verticalOffset: 0
  property real pinchStartZoom: 1
  readonly property real maximumHorizontalOffset: width * (0.25 + (zoomFactor - 1) / 2)
  readonly property real maximumVerticalOffset: height * (0.25 + (zoomFactor - 1) / 2)
  readonly property bool hasSeparateAudio:
    WallpaperService.mediaAudioSourceFor(root.mediaSource).length > 0
  readonly property bool hasAudio: root.hasSeparateAudio || mediaPlayer.hasAudio
  readonly property bool supportsScroll: mediaPlayer.hasVideo
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

  function restorePlaybackState() {
    if (mediaPlayer.mediaStatus !== MediaPlayer.LoadedMedia
        && mediaPlayer.mediaStatus !== MediaPlayer.BufferedMedia)
      return

    if (!root.playbackStateRestored) {
      const state = WallpaperService.mediaStateForSource(root.mediaSource)
      const position = state ? Math.max(0, Number(state.position) || 0) : 0
      root.pendingRestorePosition = position > 0 ? position : -1
      root.restoreSeekRequested = false
      root.playbackStateRestored = true
      root.restoringPlaybackState = true
      if (root.pendingRestorePosition >= 0 && mediaPlayer.seekable) {
        mediaPlayer.position = root.pendingRestorePosition
        root.restoreSeekRequested = true
      }
      if (state && state.playing === false)
        mediaPlayer.pause()
      else
        mediaPlayer.play()
      root.restoringPlaybackState = false
    }

    if (root.pendingRestorePosition >= 0 && mediaPlayer.seekable
        && !root.restoreSeekRequested) {
      root.restoringPlaybackState = true
      mediaPlayer.position = root.pendingRestorePosition
      root.restoreSeekRequested = true
      root.restoringPlaybackState = false
    }

    if (root.pendingRestorePosition >= 0 && root.restoreSeekRequested)
      restoreSettleTimer.restart()
    root.syncSeparateAudio()
  }

  function savePlaybackState() {
    const source = root.sessionSource || String(root.mediaSource)
    if (!source)
      return false

    const savedState = WallpaperService.mediaStateForSource(source)
    const canReadPlayerState = root.playbackStateRestored
      && !root.restoringPlaybackState
    const canReadPosition = canReadPlayerState && root.pendingRestorePosition < 0
    const muted = root.audioOwner && source === String(root.mediaSource)
      ? WallpaperService.mediaMuted
      : savedState ? !!savedState.muted : false
    const volume = root.audioOwner && source === String(root.mediaSource)
      ? WallpaperService.mediaVolume
      : savedState && Number.isFinite(Number(savedState.volume))
        ? Number(savedState.volume) : 0.45
    return WallpaperService.saveMediaPlaybackState(
      source,
      canReadPosition ? mediaPlayer.position : savedState?.position || 0,
      canReadPlayerState ? root.isPlaying : savedState?.playing !== false,
      muted,
      volume
    )
  }

  function seekTo(position) {
    if (root.seekable)
      mediaPlayer.position = position
    if (root.hasSeparateAudio && separateAudioPlayer.seekable)
      separateAudioPlayer.position = position
    seekSaveTimer.restart()
  }

  function syncSeparateAudio() {
    if (!root.hasSeparateAudio || !root.audioOwner) {
      separateAudioPlayer.pause()
      return
    }

    if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
      if (separateAudioPlayer.seekable
          && Math.abs(separateAudioPlayer.position - mediaPlayer.position) > 500) {
        separateAudioPlayer.position = mediaPlayer.position
      }
      separateAudioPlayer.play()
    } else if (mediaPlayer.playbackState === MediaPlayer.PausedState) {
      separateAudioPlayer.pause()
    } else {
      separateAudioPlayer.stop()
    }
  }

  function updateAudioRegistration() {
    if (root.registeredScreen === root.targetScreen
        && root.registeredLayerId === root.layerId) {
      WallpaperService.refreshMediaControllers()
      return
    }
    if (root.registeredScreen && root.registeredLayerId)
      WallpaperService.unregisterMediaController(
        root, root.registeredScreen, root.registeredLayerId
      )
    root.registeredScreen = root.targetScreen
    root.registeredLayerId = root.layerId
    if (root.registeredScreen && root.registeredLayerId)
      WallpaperService.registerMediaController(
        root, root.registeredScreen, root.registeredLayerId
      )
  }

  Component.onCompleted: {
    if (!root.sessionSource)
      root.sessionSource = String(root.mediaSource)
    root.updateAudioRegistration()
  }
  Component.onDestruction: {
    root.savePlaybackState()
    if (root.registeredScreen && root.registeredLayerId)
      WallpaperService.unregisterMediaController(
        root, root.registeredScreen, root.registeredLayerId
      )
  }
  onAudioOwnerChanged: {
    root.syncSeparateAudio()
  }
  onHasAudioChanged: WallpaperService.refreshMediaControllers()
  onSupportsScrollChanged: WallpaperService.refreshMediaControllers()
  onLayerIdChanged: root.updateAudioRegistration()
  onTargetScreenChanged: root.updateAudioRegistration()
  onMediaSourceChanged: {
    root.savePlaybackState()
    restoreSettleTimer.stop()
    seekSaveTimer.stop()
    root.sessionSource = String(root.mediaSource)
    root.playbackStateRestored = false
    root.pendingRestorePosition = -1
    root.restoreSeekRequested = false
    root.resetVideoView()
    root.updateAudioRegistration()
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

    VideoOutput {
      id: videoOutput
      width: parent.width * root.zoomFactor
      height: parent.height * root.zoomFactor
      x: (parent.width - width) / 2 + root.horizontalOffset
      y: (parent.height - height) / 2 + root.verticalOffset
      fillMode: VideoOutput.PreserveAspectCrop
      visible: mediaPlayer.hasVideo
    }

    MediaPlayer {
      id: mediaPlayer
      source: WallpaperService.mediaVideoSourceFor(root.mediaSource)
      videoOutput: videoOutput
      loops: MediaPlayer.Infinite
      autoPlay: false
      audioOutput: AudioOutput {
        muted: !root.audioOwner || WallpaperService.mediaMuted || root.hasSeparateAudio
        volume: WallpaperService.mediaVolume
      }
      onMediaStatusChanged: root.restorePlaybackState()
      onSeekableChanged: root.restorePlaybackState()
      onPlaybackStateChanged: {
        root.syncSeparateAudio()
        if (!root.restoringPlaybackState)
          root.savePlaybackState()
      }
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
    id: restoreSettleTimer
    interval: 1000
    repeat: false
    onTriggered: {
      root.pendingRestorePosition = -1
      root.restoreSeekRequested = false
      root.savePlaybackState()
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.hasSeparateAudio && root.audioOwner && root.isPlaying
    onTriggered: root.syncSeparateAudio()
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.playbackStateRestored && root.isPlaying
      && root.pendingRestorePosition < 0
      && WallpaperService.isMediaPlaybackOwner(root.targetScreen, root.layerId)
    onTriggered: root.savePlaybackState()
  }

  Timer {
    id: seekSaveTimer
    interval: 250
    repeat: false
    onTriggered: root.savePlaybackState()
  }

  WheelHandler {
    enabled: root.scrollControlsEnabled && mediaPlayer.hasVideo
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
    enabled: root.scrollControlsEnabled && mediaPlayer.hasVideo
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
    enabled: root.scrollControlsEnabled && mediaPlayer.hasVideo
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
    enabled: root.scrollControlsEnabled && mediaPlayer.hasVideo
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.TouchScreen
    acceptedButtons: Qt.LeftButton
    onDoubleTapped: root.resetVideoView()
  }

  PinchHandler {
    id: pinchHandler
    enabled: root.scrollControlsEnabled && mediaPlayer.hasVideo
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
