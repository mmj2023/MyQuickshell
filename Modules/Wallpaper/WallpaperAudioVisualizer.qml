import QtQuick
import qs.Common
import qs.Services

Item {
  id: root

  property url audioSource: ""
  property int position: 0
  property int duration: 0
  property bool playing: false
  property real animationPhase: 0
  property var waveformPoints: []

  readonly property var waveform: WallpaperService.audioWaveformFor(root.audioSource)
  readonly property var samples: root.waveform ? root.waveform.samples : []
  readonly property real progress: root.duration > 0
    ? Math.max(0, Math.min(1, root.position / root.duration))
    : 0
  readonly property real currentLevel: root.samples.length > 0
    ? root.samples[Math.min(root.samples.length - 1,
      Math.floor(root.progress * root.samples.length))]
    : 0

  function rebuildWaveform() {
    const sampleCount = root.samples.length
    const canvasWidth = waveformCanvas.width
    const canvasHeight = waveformCanvas.height
    if (sampleCount < 2 || canvasWidth <= 0 || canvasHeight <= 0) {
      root.waveformPoints = []
      waveformCanvas.requestPaint()
      return
    }

    const pointCount = Math.min(sampleCount,
      Math.max(96, Math.floor(canvasWidth / 5)))
    const maximumAmplitude = canvasHeight * 0.31
    const points = []
    for (let index = 0; index < pointCount; index++) {
      const sourceIndex = Math.round(index * (sampleCount - 1) / (pointCount - 1))
      const level = Math.max(0.025, Math.min(1, Number(root.samples[sourceIndex]) || 0))
      points.push({
        x: index * canvasWidth / (pointCount - 1),
        amplitude: maximumAmplitude * Math.pow(level, 0.82),
        phase: index * 0.035
      })
    }
    root.waveformPoints = points
    waveformCanvas.requestPaint()
  }

  onSamplesChanged: root.rebuildWaveform()
  Component.onCompleted: root.rebuildWaveform()

  Timer {
    interval: 16
    repeat: true
    running: root.playing
    onTriggered: {
      root.animationPhase = (root.animationPhase + 0.055) % (2 * Math.PI)
      waveformCanvas.requestPaint()
    }
  }

  onProgressChanged: waveformCanvas.requestPaint()
  onCurrentLevelChanged: waveformCanvas.requestPaint()

  Rectangle {
    anchors.fill: parent
    color: Theme.withAlpha(Theme.surface, 0.72)
  }

  Canvas {
    id: waveformCanvas
    anchors.fill: parent
    antialiasing: true
    renderStrategy: Canvas.Threaded
    onWidthChanged: root.rebuildWaveform()
    onHeightChanged: root.rebuildWaveform()

    onPaint: {
      const context = getContext("2d")
      const canvasWidth = width
      const canvasHeight = height
      if (canvasWidth <= 0 || canvasHeight <= 0)
        return

      context.clearRect(0, 0, canvasWidth, canvasHeight)
      const centerX = canvasWidth / 2
      const centerY = canvasHeight / 2
      const maximumAmplitude = canvasHeight * 0.31
      const points = root.waveformPoints
      const pointCount = points.length

      const backdrop = context.createRadialGradient(
        centerX, centerY, Math.min(canvasWidth, canvasHeight) * 0.04,
        centerX, centerY, Math.max(canvasWidth, canvasHeight) * 0.68
      )
      backdrop.addColorStop(0, Theme.withAlpha(Theme.primary, 0.13))
      backdrop.addColorStop(0.52, Theme.withAlpha(Theme.secondary, 0.055))
      backdrop.addColorStop(1, Theme.withAlpha(Theme.surface, 0))
      context.fillStyle = backdrop
      context.fillRect(0, 0, canvasWidth, canvasHeight)

      if (pointCount < 2)
        return

      const waveformGradient = context.createLinearGradient(0, 0, canvasWidth, 0)
      waveformGradient.addColorStop(0, Theme.withAlpha(Theme.primary, 0.52))
      waveformGradient.addColorStop(0.52, Theme.withAlpha(Theme.tertiary, 0.46))
      waveformGradient.addColorStop(1, Theme.withAlpha(Theme.secondary, 0.52))

      context.beginPath()
      for (let index = 0; index < pointCount; index++) {
        const point = points[index]
        const pulse = root.playing
          ? 0.96 + 0.04 * Math.sin(root.animationPhase + point.phase)
          : 1
        const amplitude = point.amplitude * pulse
        if (index === 0)
          context.moveTo(point.x, centerY - amplitude)
        else
          context.lineTo(point.x, centerY - amplitude)
      }
      for (let index = pointCount - 1; index >= 0; index--) {
        const point = points[index]
        const pulse = root.playing
          ? 0.96 + 0.04 * Math.sin(root.animationPhase + point.phase)
          : 1
        const amplitude = point.amplitude * pulse
        context.lineTo(point.x, centerY + amplitude)
      }
      context.closePath()
      context.fillStyle = waveformGradient
      context.fill()

      context.save()
      context.beginPath()
      context.rect(0, 0, canvasWidth * root.progress, canvasHeight)
      context.clip()
      context.beginPath()
      for (let index = 0; index < pointCount; index++) {
        const point = points[index]
        if (index === 0)
          context.moveTo(point.x, centerY - point.amplitude)
        else
          context.lineTo(point.x, centerY - point.amplitude)
      }
      for (let index = pointCount - 1; index >= 0; index--) {
        const point = points[index]
        context.lineTo(point.x, centerY + point.amplitude)
      }
      context.closePath()
      context.fillStyle = Theme.withAlpha(Theme.primary, 0.2)
      context.fill()
      context.strokeStyle = Theme.withAlpha(Theme.primary, 0.74)
      context.lineWidth = Math.max(1.5, Math.min(3, canvasWidth / 720))
      context.lineJoin = "round"
      context.lineCap = "round"
      context.stroke()
      context.restore()

      context.beginPath()
      context.moveTo(0, centerY)
      context.lineTo(canvasWidth, centerY)
      context.strokeStyle = Theme.withAlpha(Theme.surfaceText, 0.1)
      context.lineWidth = 1
      context.stroke()

      const playheadX = canvasWidth * root.progress
      context.beginPath()
      context.moveTo(playheadX, centerY - maximumAmplitude * 1.22)
      context.lineTo(playheadX, centerY + maximumAmplitude * 1.22)
      context.strokeStyle = Theme.withAlpha(Theme.surfaceText, 0.72)
      context.lineWidth = 1
      context.stroke()

      const radius = Math.min(canvasWidth, canvasHeight)
        * (0.095 + root.currentLevel * 0.045
          + (root.playing ? 0.008 * Math.sin(root.animationPhase) : 0))
      context.beginPath()
      context.arc(centerX, centerY, radius, 0, Math.PI * 2)
      context.strokeStyle = Theme.withAlpha(Theme.primary, 0.12 + root.currentLevel * 0.12)
      context.lineWidth = Math.max(1, canvasHeight / 500)
      context.stroke()
    }
  }
}
