pragma Singleton

import QtQuick
import Quickshell.Services.Pipewire
import qs.Common

QtObject {
  id: root

  readonly property var nodes: {
    const values = Pipewire.nodes ? Pipewire.nodes.values : null
    return values || []
  }
  property int nodeRevision: 0

  property PwObjectTracker nodeTracker: PwObjectTracker {
    objects: root.nodes
  }

  property Connections nodesConnection: Connections {
    target: Pipewire.nodes
    function onValuesChanged() {
      root.nodeRevision++
    }
  }

  readonly property bool microphoneActive: {
    root.nodeRevision
    for (const node of root.nodes) {
      if (!node)
        continue

      const properties = node.properties || {}
      if (properties["media.class"] !== "Stream/Input/Audio"
          || root.isSystemVirtualMic(node)) {
        continue
      }

      if (node.audio && node.audio.muted)
        continue
      if (properties["stream.is-live"] === false
          || properties["stream.is-live"] === "false") {
        continue
      }
      return true
    }
    return false
  }

  readonly property bool cameraActive: {
    root.nodeRevision
    for (const node of root.nodes) {
      if (!node || !node.ready)
        continue

      const properties = node.properties || {}
      if (properties["media.role"] === "Screen"
          || properties["media.class"] !== "Stream/Input/Video") {
        continue
      }
      if (properties["stream.is-live"] === true
          || properties["stream.is-live"] === "true") {
        return true
      }
    }
    return false
  }

  readonly property bool screensharingActive: {
    root.nodeRevision
    for (const node of root.nodes) {
      if (!node || !node.ready)
        continue

      const properties = node.properties || {}
      const mediaClass = properties["media.class"]
      const isVideoStream = mediaClass === "Video/Source"
        || mediaClass === "Stream/Output/Video"
      if (isVideoStream && root.looksLikeScreencast(node))
        return true

      if (mediaClass === "Stream/Input/Audio") {
        const mediaName = String(properties["media.name"] || "").toLowerCase()
        const appName = String(properties["application.name"] || "").toLowerCase()
        const isScreenAudio = mediaName.includes("desktop")
          || appName.includes("screen")
          || appName === "obs"
        const isLive = properties["stream.is-live"] === true
          || properties["stream.is-live"] === "true"
        if (isScreenAudio && isLive && (!node.audio || !node.audio.muted))
          return true
      }
    }
    return false
  }

  readonly property var activeIndicators: {
    const indicators = []
    if (root.microphoneActive)
      indicators.push({ name: "mic", color: Theme.error })
    if (root.cameraActive)
      indicators.push({ name: "camera_video", color: Theme.error })
    if (root.screensharingActive)
      indicators.push({ name: "screen_share", color: Theme.warning })
    return indicators
  }

  function isSystemVirtualMic(node) {
    const properties = node.properties || {}
    const combined = [
      node.name || "",
      properties["media.name"] || "",
      properties["application.name"] || ""
    ].join(" ").toLowerCase()
    return /cava|monitor|system/.test(combined)
  }

  function looksLikeScreencast(node) {
    const properties = node.properties || {}
    const combined = [
      properties["application.name"] || "",
      node.name || "",
      properties["media.name"] || ""
    ].join(" ").toLowerCase()
    return /xdg-desktop-portal|xdpw|screencast|screen-cast|screen|gnome shell|kwin|obs|niri/.test(combined)
  }
}
