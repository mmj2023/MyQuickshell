import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Modules.Bar.Widgets

// Compact MPRIS controls for the active media player.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null
  readonly property real controlSize: Math.round(root.textSize() * 1.5)
  readonly property real overviewSurfaceAlpha: SettingsData.barWidgetTransparency
  readonly property real overviewElementAlpha: Math.max(0.9, root.overviewSurfaceAlpha)
  readonly property real overviewWidth: root.parentScreen
    ? Math.max(320, Math.min(920, root.parentScreen.width - 32))
    : 920
  readonly property real overviewX: root.parentScreen
    ? Math.max(16, Math.min(root.parentScreen.width - root.overviewWidth - 16, root.popupX - root.overviewWidth / 2))
    : root.popupX - root.overviewWidth / 2
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var audioSinks: Pipewire.nodes ? Pipewire.nodes.values.filter(node => node.audio && node.isSink && !node.isStream) : []
  readonly property var player: root.activePlayer()
  readonly property bool hasMedia: !!root.player && String(root.player.trackTitle || "").trim() !== ""
  readonly property bool lyricsAvailable: LyricsService.hasLyrics
  property bool overviewOpen: false
  property bool lyricsOpen: false
  property var selectedPlayer: null
  property int popupX: 0
  property int popupY: 0
  property real displayedPosition: root.player ? root.player.position : 0
  property var visualizerLevels: [0.35, 0.7, 0.5, 0.85, 0.4]

  Component.onCompleted: LyricsService.setPlayer(root.player)
  onPlayerChanged: LyricsService.setPlayer(root.player)
  onLyricsAvailableChanged: {
    if (!root.lyricsAvailable)
      root.lyricsOpen = false
  }

  Timer {
    interval: 90
    repeat: true
    running: root.hasMedia && root.player.isPlaying
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
    running: root.overviewOpen && root.hasMedia
    onTriggered: {
      if (root.player)
        root.player.positionChanged()
      root.displayedPosition = root.player ? root.player.position : 0
    }
  }

  onClicked: {
    if (!root.hasMedia || !root.barWindow)
      return
    const point = root.mapToItem(root.barWindow.contentItem, 0, root.height)
    root.popupX = Math.round(point.x + root.width / 2)
    root.popupY = Math.round(point.y + Theme.spaceS)
    root.overviewOpen = !root.overviewOpen
  }

  PopupWindow {
  id: overviewPopup
  anchor.window: root.barWindow
  anchor.rect.x: root.overviewX
  anchor.rect.y: root.popupY
  visible: root.overviewOpen && root.hasMedia
  grabFocus: true
  color: "transparent"
  implicitWidth: root.overviewWidth
  implicitHeight: root.lyricsOpen ? 500 : 460

  onVisibleChanged: {
    if (!visible)
      root.overviewOpen = false
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: Theme.cornerRadius - 1
      color: "transparent"
      clip: true

      ClippingRectangle {
        anchors.fill: parent
        radius: parent.radius
        color: backdropImage.status === Image.Ready ? "transparent" : Theme.widgetBaseBackgroundColor
        antialiasing: true
        opacity: root.overviewSurfaceAlpha

        Image {
          id: backdropImage
          anchors.fill: parent
          source: root.player ? root.player.trackArtUrl : ""
          fillMode: Image.PreserveAspectCrop
          sourceSize.width: 960
          sourceSize.height: 540
          asynchronous: true
          cache: true
          visible: status === Image.Ready
        }
      }
    }

    Item {
      anchors.fill: parent
      anchors.margins: 24

      Item {
        id: mediaPane
        width: parent.width * 0.44
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Item {
          id: mediaPaneHeader
          anchors.left: parent.left
          anchors.right: parent.right
          height: 32

          Row {
            anchors.fill: parent
            spacing: Theme.spaceXS

            Repeater {
              model: root.lyricsAvailable
                ? [{ label: "Artwork", lyrics: false }, { label: "Lyrics", lyrics: true }]
                : [{ label: "Artwork", lyrics: false }]

              delegate: Item {
                required property var modelData
                readonly property bool selected: root.lyricsOpen === modelData.lyrics
                width: tabLabel.implicitWidth + Theme.spaceM * 2
                height: parent.height

                Rectangle {
                  anchors.fill: parent
                  radius: height / 2
                  color: parent.selected
                    ? Theme.withAlpha(Theme.primary, root.overviewElementAlpha)
                    : "transparent"
                }

                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  text: parent.modelData.label
                  color: parent.selected ? "#fffaf4" : "#eee5dc"
                  font.family: Theme.fontFamily
                  font.pixelSize: 12
                  font.weight: parent.selected ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.lyricsOpen = parent.modelData.lyrics
                }
              }
            }
          }
        }

        ComboBox {
          id: outputSelector
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: mediaPaneHeader.bottom
          anchors.topMargin: Theme.spaceXS
          height: 32
          visible: root.audioSinks.length > 1
          model: root.audioSinks.map(sink => sink.description || sink.nickname || sink.name)
          currentIndex: root.audioSinks.indexOf(Pipewire.defaultAudioSink)
          contentItem: Text {
            leftPadding: 10
            rightPadding: 30
            text: outputSelector.currentText || "Output device"
            color: "#f3eee8"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
          indicator: DmsIcon {
            x: outputSelector.width - width - 8
            anchors.verticalCenter: parent.verticalCenter
            name: "expand_more"
            size: 18
            color: "#eee5dc"
          }
          background: Rectangle {
            radius: 9
            color: Theme.withAlpha(Theme.surfaceDim, 0.96)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outlineVariant, 0.85)
          }
          popup: Popup {
            y: outputSelector.height
            width: outputSelector.width
            implicitHeight: contentItem.implicitHeight
            padding: 4
            background: Rectangle {
              radius: 9
              color: Theme.withAlpha(Theme.surfaceDim, 0.97)
              border.width: 1
              border.color: Theme.withAlpha(Theme.outlineVariant, 0.9)
            }
            contentItem: ListView {
              clip: true
              implicitHeight: contentHeight
              model: outputSelector.popup.visible ? outputSelector.delegateModel : null
              currentIndex: outputSelector.highlightedIndex
              boundsBehavior: Flickable.StopAtBounds
            }
          }
          delegate: ItemDelegate {
            required property int index
            required property var modelData
            width: outputSelector.width
            text: String(modelData)
            highlighted: outputSelector.highlightedIndex === index
            contentItem: Text {
              text: outputSelector.textAt(index)
              color: "#f3eee8"
              font.family: Theme.fontFamily
              font.pixelSize: 12
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
            }
            background: Rectangle {
              radius: 6
              color: parent.highlighted
                ? Theme.withAlpha(Theme.primary, root.overviewElementAlpha * 0.6)
                : "transparent"
            }
          }
          onActivated: index => {
            if (root.audioSinks[index])
              Pipewire.preferredDefaultAudioSink = root.audioSinks[index]
          }
        }

        Item {
          id: mediaContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: outputSelector.visible ? outputSelector.bottom : mediaPaneHeader.bottom
          anchors.bottom: parent.bottom
          anchors.topMargin: Theme.spaceS
        }

      ClippingRectangle {
        id: artwork
        width: Math.min(mediaContent.width, mediaContent.height)
        height: width
        anchors.horizontalCenter: mediaContent.horizontalCenter
        anchors.verticalCenter: mediaContent.verticalCenter
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.primaryContainer, root.overviewElementAlpha)
        visible: !root.lyricsOpen

        Image {
          id: artworkImage
          anchors.fill: parent
          source: root.player ? root.player.trackArtUrl : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          visible: status === Image.Ready
        }

        DmsIcon {
          anchors.centerIn: parent
          name: "music_note"
          size: 64
          color: Theme.withAlpha(Theme.primary, root.overviewElementAlpha)
          visible: !artworkImage.visible
        }
      }

        PlayerLyricsView {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: mediaContent.top
          anchors.bottom: parent.bottom
          anchors.topMargin: 0
          visible: root.lyricsOpen
          textSize: 14
        }
      }

      ComboBox {
        id: playerSelector
        anchors.left: playerSelectorLabel.right
        anchors.leftMargin: Theme.spaceS
        anchors.top: parent.top
        width: Math.min(190, Math.max(130, parent.width * 0.24))
        height: 34
        model: root.players.map(candidate => candidate.identity || candidate.trackTitle || "Media player")
        currentIndex: root.players.indexOf(root.player)
        visible: root.players.length > 1
        onActivated: index => {
          root.selectedPlayer = root.players[index] || null
          LyricsService.setPlayer(root.player)
        }
        contentItem: Text {
          leftPadding: 12
          rightPadding: 30
          text: playerSelector.currentText
          color: "#f3eee8"
          font.family: Theme.fontFamily
          font.pixelSize: 13
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
        indicator: DmsIcon {
          x: playerSelector.width - width - 8
          anchors.verticalCenter: parent.verticalCenter
          name: "expand_more"
          size: 20
          color: "#eee5dc"
        }
        background: Rectangle {
          radius: 10
          color: Theme.withAlpha(Theme.surfaceDim, 0.97)
          border.width: 1
          border.color: Theme.withAlpha(Theme.outlineVariant, 0.9)
        }
        popup: Popup {
          y: playerSelector.height
          width: playerSelector.width
          implicitHeight: contentItem.implicitHeight
          padding: 4
          background: Rectangle {
            radius: 10
            color: Theme.withAlpha(Theme.surfaceDim, 0.97)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outlineVariant, 0.9)
          }
          contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: playerSelector.popup.visible ? playerSelector.delegateModel : null
            currentIndex: playerSelector.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
          }
        }
        delegate: ItemDelegate {
          required property int index
          required property var modelData
          width: playerSelector.width
          text: String(modelData)
          highlighted: playerSelector.highlightedIndex === index
          contentItem: Text {
            text: playerSelector.textAt(index)
            color: "#f3eee8"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
          background: Rectangle {
            radius: 7
            color: parent.highlighted
              ? Theme.withAlpha(Theme.primary, root.overviewElementAlpha * 0.6)
              : "transparent"
          }
        }
      }

      Rectangle {
        anchors.left: playerSelectorLabel.left
        anchors.right: playerSelectorLabel.right
        anchors.top: playerSelectorLabel.top
        anchors.bottom: playerSelectorLabel.bottom
        anchors.margins: -Theme.spaceS
        radius: 9
        color: Theme.withAlpha(Theme.surfaceDim, 0.97)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.9)
      }

      Text {
        id: playerSelectorLabel
        anchors.left: parent.left
        anchors.verticalCenter: playerSelector.verticalCenter
        width: Math.min(110, implicitWidth)
        text: "Listening from"
        color: "#eee5dc"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        visible: playerSelector.visible
        elide: Text.ElideRight
      }

      Rectangle {
        anchors.left: metadata.left
        anchors.right: metadata.right
        anchors.top: metadata.top
        anchors.bottom: metadata.bottom
        anchors.margins: -Theme.spaceM
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceDim, 0.97)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.9)
      }

      Column {
        id: metadata
        anchors.left: parent.left
        anchors.right: mediaPane.left
        anchors.rightMargin: Theme.spaceL
        anchors.top: playerSelector.visible ? playerSelector.bottom : parent.top
        anchors.topMargin: playerSelector.visible ? Theme.spaceL * 2 : 0
        height: 126
        spacing: 2

        Text {
          id: trackTitle
          width: parent.width
          height: 74
          text: root.player ? (root.player.trackTitle || "Unknown track") : ""
          color: "#fffaf4"
          font.family: "Gabarito"
          font.pixelSize: 34
          font.weight: Font.Black
          font.letterSpacing: 0.15
          font.capitalization: Font.AllUppercase
          fontSizeMode: Text.Fit
          minimumPixelSize: 17
          style: Text.Outline
          styleColor: "#91553f"
          maximumLineCount: 2
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: parent.width
          height: 24
          text: root.player ? (root.player.trackArtist || "Unknown Artist") : ""
          color: "#eee5dc"
          font.family: Theme.fontFamily
          font.pixelSize: 15
          font.weight: Font.DemiBold
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: parent.width
          height: 20
          text: root.player ? (root.player.trackAlbum || root.player.identity || "") : ""
          color: "#c9bdb2"
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.weight: Font.Medium
          font.letterSpacing: 0.4
          font.capitalization: Font.AllUppercase
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }

      Rectangle {
        anchors.left: seekBlock.left
        anchors.right: seekBlock.right
        anchors.top: seekBlock.top
        anchors.bottom: parent.bottom
        anchors.margins: -Theme.spaceM
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceDim, 0.97)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.9)
      }

      Item {
        id: seekBlock
        anchors.left: parent.left
        anchors.right: mediaPane.left
        anchors.rightMargin: Theme.spaceL
        anchors.bottom: transport.top
        anchors.bottomMargin: Theme.spaceS
        height: 44

        Slider {
          id: progressSlider
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 22
          from: 0
          to: root.player ? Math.max(1, root.player.length) : 1
          value: Math.min(to, root.displayedPosition)
          enabled: root.player ? root.player.positionSupported : false
          onMoved: {
            if (root.player)
              root.player.position = value
          }

          background: Item {
            x: progressSlider.leftPadding
            y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
            width: progressSlider.availableWidth
            height: 4

            Rectangle {
              anchors.fill: parent
              radius: 2
              color: Theme.withAlpha(Theme.onSurfaceVariant, 0.85)
            }
            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, progressSlider.visualPosition))
              height: parent.height
              radius: 2
              color: Theme.primary
            }
          }

          handle: Rectangle {
            x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
            y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
            width: 12
            height: 12
            radius: 6
            color: Theme.primary
            border.width: 1
            border.color: Theme.surfaceContainer
          }
        }

        Row {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          Text {
            text: root.formatTime(root.displayedPosition)
            color: Theme.surfaceText
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
          }
          Item { width: parent.width - 90; height: 1 }
          Text {
            text: root.formatTime(root.player ? root.player.length : 0)
            color: Theme.surfaceText
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
          }
        }
      }

      Row {
        id: volumeControl
        anchors.left: parent.left
        anchors.right: mediaPane.left
        anchors.rightMargin: Theme.spaceL
        anchors.bottom: parent.bottom
        height: 28
        spacing: Theme.spaceS
        visible: root.player ? root.player.volumeSupported : false

        DmsIcon {
          anchors.verticalCenter: parent.verticalCenter
          name: "volume_up"
          size: 16
          color: "#eee5dc"
        }

        Slider {
          id: volumeSlider
          width: parent.width - 76
          height: parent.height
          from: 0
          to: 1
          value: root.player ? root.player.volume : 0
          onMoved: {
            if (root.player)
              root.player.volume = value
          }
          background: Item {
            x: volumeSlider.leftPadding
            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
            width: volumeSlider.availableWidth
            height: 4

            Rectangle {
              anchors.fill: parent
              radius: 2
              color: Theme.withAlpha("#f3eee8", 0.3)
            }
            Rectangle {
              width: parent.width * volumeSlider.visualPosition
              height: parent.height
              radius: 2
              color: Theme.withAlpha(Theme.primary, root.overviewElementAlpha)
            }
          }
          handle: Rectangle {
            x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
            width: 12
            height: 12
            radius: 6
            color: Theme.withAlpha(Theme.primary, root.overviewElementAlpha)
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: 38
          text: Math.round((root.player ? root.player.volume : 0) * 100) + "%"
          color: "#fffaf4"
          font.family: Theme.fontFamily
          font.pixelSize: 12
          horizontalAlignment: Text.AlignRight
        }
      }

      Row {
        id: transport
        anchors.horizontalCenter: seekBlock.horizontalCenter
        anchors.bottom: volumeControl.visible ? volumeControl.top : parent.bottom
        anchors.bottomMargin: volumeControl.visible ? Theme.spaceS : 0
        spacing: Theme.spaceS

        Item {
          width: 44
          height: 44
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.withAlpha(Theme.secondaryContainer, root.overviewElementAlpha)
          }
          DmsIcon {
            anchors.centerIn: parent
            name: "skip_previous"
            size: 22
            color: "#f3eee8"
          }
          MouseArea {
            anchors.fill: parent
            enabled: root.player ? root.player.canGoPrevious : false
            onClicked: root.player.previous()
          }
        }

        Item {
          width: 64
          height: 56
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.fill: parent
            radius: 14
            color: Theme.withAlpha(Theme.primaryContainer, root.overviewElementAlpha)
          }
          DmsIcon {
            anchors.centerIn: parent
            name: root.player && root.player.isPlaying ? "pause" : "play_arrow"
            size: 30
            color: "#fffaf4"
          }
          MouseArea {
            anchors.fill: parent
            enabled: root.player ? root.player.canTogglePlaying : false
            onClicked: root.player.togglePlaying()
          }
        }

        Item {
          width: 44
          height: 44
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.withAlpha(Theme.secondaryContainer, root.overviewElementAlpha)
          }
          DmsIcon {
            anchors.centerIn: parent
            name: "skip_next"
            size: 22
            color: "#f3eee8"
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
    Item {
      implicitWidth: root.hasMedia ? playerContent.implicitWidth : 0
      implicitHeight: root.hasMedia ? playerContent.implicitHeight : 0

      Column {
        id: playerContent
        visible: root.hasMedia
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
            opacity: controlEnabled ? 1 : 0.55
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
            opacity: controlEnabled ? 1 : 0.55
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
            opacity: controlEnabled ? 1 : 0.55
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
  }

  function activePlayer() {
    if (root.selectedPlayer && root.players.indexOf(root.selectedPlayer) >= 0 &&
        String(root.selectedPlayer.trackTitle || "").trim() !== "")
      return root.selectedPlayer
    for (const candidate of root.players) {
      if (candidate && candidate.isPlaying && String(candidate.trackTitle || "").trim() !== "")
        return candidate
    }
    for (const candidate of root.players) {
      if (candidate && String(candidate.trackTitle || "").trim() !== "")
        return candidate
    }
    return null
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
