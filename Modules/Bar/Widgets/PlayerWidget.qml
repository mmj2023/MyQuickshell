import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Mpris
import qs.Common
import qs.Modules.Bar.Widgets

// Compact MPRIS controls for the active media player.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null
  readonly property real controlSize: Math.round(root.textSize() * 1.5)
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: root.activePlayer()
  readonly property bool hasPlayer: root.player !== null
  property bool overviewOpen: false
  property int popupX: 0
  property int popupY: 0
  property real displayedPosition: root.player ? root.player.position : 0
  property var visualizerLevels: [0.35, 0.7, 0.5, 0.85, 0.4]

  Timer {
    interval: 90
    repeat: true
    running: root.hasPlayer && root.player.isPlaying
    onTriggered: {
      const next = []
      for (let i = 0; i < root.visualizerLevels.length; i++)
        next.push(0.25 + Math.random() * 0.75)
      root.visualizerLevels = next
    }
  }

  Timer {
    interval: 500
    repeat: true
    running: root.overviewOpen && root.hasPlayer
    onTriggered: {
      if (root.player)
        root.player.positionChanged()
      root.displayedPosition = root.player ? root.player.position : 0
    }
  }

  onClicked: {
    if (!root.hasPlayer || !root.barWindow)
      return
    const point = root.mapToItem(root.barWindow.contentItem, 0, root.height)
    root.popupX = Math.round(point.x + root.width / 2)
    root.popupY = Math.round(point.y + Theme.spaceS)
    root.overviewOpen = !root.overviewOpen
  }

  PopupWindow {
  id: overviewPopup
  anchor.window: root.barWindow
  anchor.rect.x: root.popupX - implicitWidth / 2
  anchor.rect.y: root.popupY
  visible: root.overviewOpen && root.hasPlayer
  grabFocus: false
  color: "transparent"
  implicitWidth: 520
  implicitHeight: 560

  Rectangle {
    anchors.fill: parent
    radius: 18
    clip: true
    color: Theme.withAlpha(Theme.surfaceContainerLowest, 0.58)
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.38)

    Image {
      id: backgroundArtworkSource
      width: parent.width
      height: parent.height
      source: root.player ? root.player.trackArtUrl : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      visible: false
    }

    OpacityMask {
      id: backgroundArtwork
      width: parent.width
      height: parent.height
      opacity: 0.22
      source: backgroundArtworkSource
      maskSource: Rectangle {
        width: backgroundArtwork.width
        height: backgroundArtwork.height
        radius: 18
        color: "white"
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: 18
      color: Theme.withAlpha(Theme.surfaceContainerLowest, 0.28)
    }

    Column {
      anchors.fill: parent
      anchors.margins: 38
      spacing: 14

      Image {
        id: artwork
        width: 260
        height: 260
        anchors.horizontalCenter: parent.horizontalCenter
        source: root.player ? root.player.trackArtUrl : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: status === Image.Ready
      }

      Rectangle {
        width: 260
        height: 260
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !artwork.visible
        radius: 130
        color: Theme.primaryContainer
        border.width: 2
        border.color: Theme.primary

        DmsIcon {
          anchors.centerIn: parent
          name: "music_note"
          size: 84
          color: Theme.primary
        }
      }

      Text {
        width: parent.width
        text: root.player ? (root.player.trackTitle || "Unknown track") : ""
        color: Theme.widgetTextColor
        font.family: Theme.fontFamily
        font.pixelSize: 20
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: root.player ? (root.player.trackArtist || "Unknown Artist") : ""
        color: Theme.widgetInactiveIconColor
        font.family: Theme.fontFamily
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: root.player ? (root.player.identity || "") : ""
        color: Theme.widgetInactiveIconColor
        font.family: Theme.fontFamily
        font.pixelSize: 13
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Slider {
        id: progressSlider
        width: parent.width
        from: 0
        to: root.player ? Math.max(1, root.player.length) : 1
        value: Math.min(to, root.displayedPosition)
        enabled: root.player ? root.player.positionSupported : false
        onMoved: {
          if (root.player)
            root.player.position = value
        }
      }

      Row {
        width: parent.width
        spacing: 10

        Text {
          text: root.formatTime(root.displayedPosition)
          color: Theme.widgetInactiveIconColor
          font.family: Theme.monoFontFamily
          font.pixelSize: 12
        }
        Item { width: parent.width - 90; height: 1 }
        Text {
          text: root.formatTime(root.player ? root.player.length : 0)
          color: Theme.widgetInactiveIconColor
          font.family: Theme.monoFontFamily
          font.pixelSize: 12
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 24

        Item {
          width: 40
          height: 52
          anchors.verticalCenter: parent.verticalCenter
          DmsIcon {
            anchors.centerIn: parent
            name: "skip_previous"
            size: 28
            color: Theme.widgetTextColor
          }
          MouseArea {
            anchors.fill: parent
            enabled: root.player ? root.player.canGoPrevious : false
            onClicked: root.player.previous()
          }
        }

        Item {
          width: 56
          height: 56
          anchors.verticalCenter: parent.verticalCenter
          DmsIcon {
            anchors.centerIn: parent
            name: root.player && root.player.isPlaying ? "pause" : "play_arrow"
            size: 42
            color: Theme.primary
          }
          MouseArea {
            anchors.fill: parent
            enabled: root.player ? root.player.canTogglePlaying : false
            onClicked: root.player.togglePlaying()
          }
        }

        Item {
          width: 40
          height: 52
          anchors.verticalCenter: parent.verticalCenter
          DmsIcon {
            anchors.centerIn: parent
            name: "skip_next"
            size: 28
            color: Theme.widgetTextColor
          }
          MouseArea {
            anchors.fill: parent
            enabled: root.player ? root.player.canGoNext : false
            onClicked: root.player.next()
          }
        }
      }
    }
  }
  }

  content: Component {
    Column {
      visible: root.hasPlayer
      spacing: 0
      anchors.horizontalCenter: parent.horizontalCenter

      Item {
        implicitWidth: root.controlSize * 3 + 4 + 30 + 4
        implicitHeight: root.controlSize
        anchors.horizontalCenter: parent.horizontalCenter

        Item {
          id: visualizer
          visible: root.player && root.player.isPlaying
          width: 30
          height: root.controlSize
          clip: true
          anchors.right: controls.left
          anchors.rightMargin: 4
          anchors.verticalCenter: controls.verticalCenter

          Row {
            anchors.fill: parent
            anchors.margins: 2
            spacing: 2
            Repeater {
              model: root.visualizerLevels.length
              delegate: Rectangle {
                required property int index
                width: 3
                height: Math.max(3, parent.height * root.visualizerLevels[index])
                anchors.bottom: parent.bottom
                radius: width / 2
                color: Theme.primary
                Behavior on height {
                  NumberAnimation {
                    duration: 80
                    easing.type: Easing.OutQuad
                  }
                }
              }
            }
          }
        }

        Row {
          id: controls
          anchors.centerIn: parent
          spacing: 2

          Item {
            property string iconName: "skip_previous"
            property bool controlEnabled: root.player ? root.player.canGoPrevious : false
            implicitWidth: root.controlSize
            implicitHeight: root.controlSize
            opacity: controlEnabled ? 1 : 0.35
            DmsIcon {
              anchors.fill: parent
              name: parent.iconName
              size: root.controlSize
              color: Theme.widgetTextColor
            }
            MouseArea {
              anchors.fill: parent
              enabled: parent.controlEnabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.player.previous()
            }
          }

          Item {
            property string iconName: root.player && root.player.isPlaying ? "pause" : "play_arrow"
            property bool controlEnabled: root.player ? root.player.canTogglePlaying : false
            implicitWidth: root.controlSize
            implicitHeight: root.controlSize
            opacity: controlEnabled ? 1 : 0.35
            DmsIcon {
              anchors.fill: parent
              name: parent.iconName
              size: root.controlSize
              color: Theme.primary
            }
            MouseArea {
              anchors.fill: parent
              enabled: parent.controlEnabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.player.togglePlaying()
            }
          }

          Item {
            property string iconName: "skip_next"
            property bool controlEnabled: root.player ? root.player.canGoNext : false
            implicitWidth: root.controlSize
            implicitHeight: root.controlSize
            opacity: controlEnabled ? 1 : 0.35
            DmsIcon {
              anchors.fill: parent
              name: parent.iconName
              size: root.controlSize
              color: Theme.widgetTextColor
            }
            MouseArea {
              anchors.fill: parent
              enabled: parent.controlEnabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.player.next()
            }
          }
        }
      }

      Text {
        width: Math.min(180, Math.max(implicitWidth, 3 * root.controlSize + 4))
        text: root.trackText()
        color: Theme.widgetTextColor
        font.family: Theme.monoFontFamily
        font.pixelSize: root.textSize() * 0.8
        elide: Text.ElideRight
      }
    }
  }

  function activePlayer() {
    for (const candidate of root.players) {
      if (candidate && candidate.isPlaying)
        return candidate
    }
    return root.players.length > 0 ? root.players[0] : null
  }

  function trackText() {
    if (!root.player)
      return ""
    const title = root.player.trackTitle || "Unknown track"
    const artist = root.player.trackArtist
    return artist ? title + " - " + artist : title
  }

  function formatTime(seconds) {
    const total = Math.max(0, Math.floor(Number(seconds) || 0))
    const minutes = Math.floor(total / 60)
    const remaining = total % 60
    return minutes + ":" + remaining.toString().padStart(2, "0")
  }
}
