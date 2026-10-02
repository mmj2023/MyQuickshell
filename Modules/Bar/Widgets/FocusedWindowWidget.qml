import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Focused window title. Shows the active toplevel's title in a pill. Click
// invokes a window menu duck (no menu surface yet); empty while no toplevel is
// focused.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null
  property real maxWidth: 220
  property bool titleHovered: false
  property int tooltipX: 0
  property int tooltipY: 0

  readonly property string focusTitle: ToplevelManager.activeToplevel
    ? ToplevelManager.activeToplevel.title
    : ""
  readonly property string cleanedTitle: root.focusTitle.trim()
  readonly property bool titleTruncated: titleMetrics.advanceWidth >
    Math.max(0, Math.min(220, root.maxWidth) - root.horizontalPadding * 2)
  visible: root.cleanedTitle !== ""
  width: root.cleanedTitle === "" ? 0 : Math.min(root.maxWidth, root.visualWidth)

  TextMetrics {
    id: titleMetrics
    font.family: Theme.fontFamily
    font.pixelSize: root.textSize()
    text: root.cleanedTitle
  }

  content: Component {
    Item {
      implicitWidth: root.cleanedTitle === "" ? 0 : Math.min(
        Math.max(0, root.maxWidth - root.horizontalPadding * 2),
        titleText.implicitWidth
      )
      implicitHeight: titleText.implicitHeight + 2
      Text {
        id: titleText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        text: root.cleanedTitle
        color: Theme.widgetTextColor
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize()
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        horizontalAlignment: Text.AlignHCenter
      }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onEntered: {
          root.titleHovered = true
          tooltipDelay.restart()
        }
        onExited: {
          root.titleHovered = false
          tooltipDelay.stop()
          fullTitlePopup.visible = false
        }
      }
    }
  }

  Timer {
    id: tooltipDelay
    interval: 450
    repeat: false
    onTriggered: {
      if (root.titleHovered && root.titleTruncated) {
        root.updateTooltipPosition()
        fullTitlePopup.visible = true
      }
    }
  }

  PopupWindow {
    id: fullTitlePopup
    anchor.window: root.barWindow
    anchor.rect.x: root.tooltipX
    anchor.rect.y: root.tooltipY
    visible: false
    color: "transparent"
    implicitWidth: Math.min(
      titleText.implicitWidth + Theme.spaceL * 2,
      Math.max(120, (root.parentScreen ? root.parentScreen.width : 512) - 32)
    )
    implicitHeight: Math.min(
      titleText.implicitHeight + Theme.spaceM * 2,
      Math.max(80, (root.parentScreen ? root.parentScreen.height : 800) * 0.5)
    )

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.withAlpha(
        Theme.widgetBaseBackgroundColor,
        typeof SettingsData !== "undefined" ? SettingsData.barWidgetTransparency : 0.65
      )
      border.width: 0

      Flickable {
        id: titleFlickable
        anchors.fill: parent
        anchors.margins: Theme.spaceM
        clip: true
        contentHeight: titleText.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Text {
          id: titleText
          width: titleFlickable.width
          height: implicitHeight
          text: root.cleanedTitle
          color: Theme.widgetTextColor
          font.family: Theme.fontFamily
          font.pixelSize: root.textSize()
          wrapMode: Text.Wrap
        }
      }
    }
  }

  function updateTooltipPosition() {
    if (!root.barWindow)
      return
    const point = root.mapToItem(root.barWindow.contentItem, 0, root.height)
    const screenWidth = root.parentScreen ? root.parentScreen.width : root.barWindow.width
    const popupWidth = Math.min(fullTitlePopup.implicitWidth, Math.max(120, screenWidth - 32))
    root.tooltipX = Math.max(16, Math.min(
      screenWidth - popupWidth - 16,
      point.x + root.width / 2 - popupWidth / 2
    ))
    root.tooltipY = Math.round(point.y + Theme.spaceXS)
  }
}
