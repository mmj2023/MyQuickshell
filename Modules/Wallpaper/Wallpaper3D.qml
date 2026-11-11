import QtQuick
import QtQuick3D
import QtQuick3D.AssetUtils
import qs.Common
import qs.Services

Item {
  id: root

  property url modelSource: ""
  property real modelYaw: 0
  property real modelPitch: 0
  property real modelRoll: 0
  property real zoomFactor: 1
  property real pinchStartZoom: 1
  property real pinchStartRoll: 0
  property bool rollMode: false
  readonly property bool runtimeAsset: /\.(glb|gltf)$/.test(
    String(modelSource).toLowerCase().split(/[?#]/)[0]
  )
  readonly property real baseCameraDistance: runtimeAsset && modelBounds.diameter > 0
    ? modelBounds.diameter * 1.6 : 300
  readonly property real cameraDistance: baseCameraDistance / zoomFactor

  function zoomModel(delta) {
    root.setModelZoom(root.zoomFactor * Math.exp(delta * 0.003))
  }

  function setModelZoom(value) {
    root.zoomFactor = Math.max(0.3, Math.min(3, value))
  }

  function rollModel(delta) {
    root.modelRoll += delta * 0.35
  }

  onModelSourceChanged: {
    root.modelYaw = 0
    root.modelPitch = 0
    root.modelRoll = 0
    root.zoomFactor = 1
  }

  QtObject {
    id: modelBounds
    property vector3d minimum: Qt.vector3d(0, 0, 0)
    property vector3d maximum: Qt.vector3d(0, 0, 0)
    readonly property vector3d center: Qt.vector3d(
      (minimum.x + maximum.x) / 2,
      (minimum.y + maximum.y) / 2,
      (minimum.z + maximum.z) / 2
    )
    readonly property vector3d size: Qt.vector3d(
      maximum.x - minimum.x,
      maximum.y - minimum.y,
      maximum.z - minimum.z
    )
    readonly property real diameter: Math.max(size.x, size.y, size.z)
  }

  View3D {
    anchors.fill: parent
    environment: SceneEnvironment {
      backgroundMode: SceneEnvironment.Color
      clearColor: Theme.surface
    }

    PerspectiveCamera {
      z: root.cameraDistance
      clipNear: root.runtimeAsset && modelBounds.diameter > 0
        ? Math.max(0.01, modelBounds.diameter / 1000) : 0.1
      clipFar: root.runtimeAsset && modelBounds.diameter > 0
        ? root.cameraDistance + modelBounds.diameter * 2 : 10000
    }

    DirectionalLight {
      eulerRotation.x: -30
      eulerRotation.y: -35
      brightness: 1.5
    }

    RuntimeLoader {
      id: runtimeLoader
      source: root.runtimeAsset ? root.modelSource : ""
      position: Qt.vector3d(-modelBounds.center.x, -modelBounds.center.y, -modelBounds.center.z)
      eulerRotation: Qt.vector3d(root.modelPitch, root.modelYaw, root.modelRoll)
      onBoundsChanged: {
        modelBounds.minimum = bounds.minimum
        modelBounds.maximum = bounds.maximum
      }
      onStatusChanged: {
        if (status === RuntimeLoader.Error) {
          const detail = String(errorString || "").trim()
          WallpaperService.error = detail.toLowerCase().includes("assimp")
            ? qsTr("GLB/GLTF wallpapers require the system Assimp importer.")
            : detail.length > 0
              ? qsTr("Could not load 3D wallpaper: %1").arg(detail)
              : qsTr("Could not load 3D wallpaper.")
        }
      }
    }

    Model {
      source: root.runtimeAsset ? "" : root.modelSource
      scale: Qt.vector3d(100, 100, 100)
      eulerRotation: Qt.vector3d(root.modelPitch, root.modelYaw, root.modelRoll)
    }
  }

  WheelHandler {
    orientation: Qt.Horizontal
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    target: null
    onWheel: function(event) {
      const delta = event.pixelDelta.x !== 0
        ? event.pixelDelta.x
        : event.angleDelta.x / 120 * 24
      if (root.rollMode || (event.buttons & Qt.RightButton))
        root.rollModel(delta)
      else
        root.modelYaw += delta * 0.35
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
      if (root.rollMode || (event.buttons & Qt.RightButton))
        root.rollModel(delta)
      else
        root.modelPitch = Math.max(-85, Math.min(85, root.modelPitch + delta * 0.35))
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
      if (root.rollMode || (event.buttons & Qt.RightButton))
        root.rollModel(delta)
      else
        root.zoomModel(delta)
      event.accepted = true
    }
  }

  TapHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.TouchScreen
    acceptedButtons: Qt.LeftButton
    onDoubleTapped: root.rollMode = !root.rollMode
  }

  PinchHandler {
    id: pinchHandler
    acceptedDevices: PointerDevice.TouchPad | PointerDevice.TouchScreen
    target: null
    onActiveChanged: {
      if (active) {
        root.pinchStartZoom = root.zoomFactor
        root.pinchStartRoll = root.modelRoll
      }
    }
    onScaleChanged: {
      if (active)
        root.setModelZoom(root.pinchStartZoom * pinchHandler.activeScale)
    }
    onRotationChanged: {
      if (active)
        root.modelRoll = root.pinchStartRoll + pinchHandler.activeRotation
    }
  }

  Rectangle {
    visible: root.rollMode
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Theme.spaceM
    width: rollModeLabel.implicitWidth + Theme.spaceM * 2
    height: rollModeLabel.implicitHeight + Theme.spaceS * 2
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.surfaceContainer, 0.88)

    Text {
      id: rollModeLabel
      anchors.centerIn: parent
      text: qsTr("Roll mode - double-click to exit")
      color: Theme.surfaceText
      font.pixelSize: Theme.fontSizeSmall
    }
  }
}
