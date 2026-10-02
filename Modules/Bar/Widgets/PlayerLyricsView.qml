import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services

Item {
  id: root

  property real textSize: 16

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.surfaceDim, 0.97)
  }

  ListView {
    id: lyricsList
    anchors.fill: parent
    anchors.margins: Theme.spaceM
    clip: true
    spacing: Theme.spaceM
    model: LyricsService.synced ? LyricsService.lines : LyricsService.plainLines
    currentIndex: LyricsService.synced ? LyricsService.activeIndex : -1
    boundsBehavior: Flickable.StopAtBounds
    onCurrentIndexChanged: {
      if (LyricsService.synced && currentIndex >= 0)
        positionViewAtIndex(currentIndex, ListView.Contain)
    }
    ScrollBar.vertical: ScrollBar {
      policy: ScrollBar.AsNeeded
      background: Rectangle { color: "transparent" }
      contentItem: Rectangle {
        radius: width / 2
        color: Theme.withAlpha(Theme.primary, Math.max(0.9, SettingsData.barWidgetTransparency))
      }
    }
    delegate: Text {
      required property var modelData
      required property int index
      width: lyricsList.width - 8
      text: root.lineText(modelData, index)
      textFormat: LyricsService.synced ? Text.RichText : Text.PlainText
      color: "#f3eee8"
      opacity: LyricsService.synced && index !== LyricsService.activeIndex ? 0.72 : 1
      font.family: Theme.fontFamily
      font.pixelSize: root.textSize
      font.weight: LyricsService.synced && index === LyricsService.activeIndex ? Font.DemiBold : Font.Normal
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
      onYChanged: {
        if (LyricsService.synced && index === LyricsService.activeIndex)
          lyricsList.positionViewAtIndex(index, ListView.Contain)
      }
    }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width - Theme.spaceL * 2
    spacing: Theme.spaceS
    visible: LyricsService.state !== "ready"

    Text {
      width: parent.width
      text: {
        switch (LyricsService.state) {
        case "loading": return "Searching for lyrics…"
        case "instrumental": return "Instrumental"
        case "unavailable": return "Lyrics are unavailable"
        case "error": return "Lyrics could not be loaded"
        case "none": return "No lyrics found"
        default: return "Lyrics are not available"
        }
      }
      color: "#eee5dc"
      font.family: Theme.fontFamily
      font.pixelSize: 14
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: LyricsService.state === "none" || LyricsService.state === "error"
      text: "Retry"
      color: "#ffd2bd"
      font.family: Theme.fontFamily
      font.pixelSize: 13
      MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        onClicked: LyricsService.retry()
      }
    }
  }

  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: Theme.spaceM
    anchors.bottomMargin: Theme.spaceXS
    visible: LyricsService.state === "ready" && LyricsService.attributionName !== ""
    text: LyricsService.attributionName
    color: "#c9bdb2"
    font.family: Theme.fontFamily
    font.pixelSize: 10
    opacity: 0.9
    MouseArea {
      anchors.fill: parent
      enabled: LyricsService.attributionUrl !== ""
      cursorShape: Qt.PointingHandCursor
      onClicked: Qt.openUrlExternally(LyricsService.attributionUrl)
    }
  }

  onVisibleChanged: {
    if (visible && LyricsService.synced && LyricsService.activeIndex >= 0)
      lyricsList.positionViewAtIndex(LyricsService.activeIndex, ListView.Contain)
  }

  function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
  }

  function lineText(line, index) {
    if (!LyricsService.synced)
    return String(line)
    const text = typeof line.x === "string" ? line.x : ""
    const words = Array.isArray(line.w) ? line.w : []
    if (index !== LyricsService.activeIndex || words.length === 0)
    return escapeHtml(text)
    return words.map((word, wordIndex) => {
    const content = escapeHtml(word.x)
    return wordIndex === LyricsService.activeWordIndex
      ? "<font color=\"" + Theme.primary + "\">" + content + "</font>"
      : content
    }).join("")
  }
}
