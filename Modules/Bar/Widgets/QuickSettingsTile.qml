import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Modules.Bar.Widgets

Rectangle {
  id: root

  property string iconName: ""
  property string title: ""
  property string subtitle: ""
  property bool sensitiveSubtitle: false
  property bool active: false
  property bool available: true

  signal clicked
  signal rightClicked

  radius: Theme.cornerRadius
  color: Theme.withAlpha(active ? Theme.primary : Theme.surfaceContainerHigh, active ? 0.22 : 0.55)
  border.width: 1
  border.color: Theme.withAlpha(active ? Theme.primary : Theme.outlineVariant, 0.35)
  opacity: available ? 1 : 0.55

  Row {
    anchors.fill: parent
    anchors.margins: 9
    spacing: 8

    DmsIcon {
      anchors.verticalCenter: parent.verticalCenter
      name: root.iconName
      size: 24
      color: root.active ? Theme.primary : Theme.widgetIconColor
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 34
      spacing: 2

      Text {
        width: parent.width
        text: root.title
        color: Theme.widgetTextColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }

      Item {
        id: subtitleContainer
        width: parent.width
        height: subtitleText.implicitHeight

        Text {
          id: subtitleText
          anchors.fill: parent
          text: root.subtitle
          color: Theme.widgetInactiveIconColor
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall - 2
          elide: Text.ElideRight
          layer.enabled: root.sensitiveSubtitle && !subtitleHover.containsMouse
          layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
          }
        }

        MouseArea {
          id: subtitleHover
          anchors.fill: parent
          visible: root.sensitiveSubtitle
          acceptedButtons: Qt.NoButton
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.available
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton)
        root.rightClicked()
      else
        root.clicked()
    }
  }
}
