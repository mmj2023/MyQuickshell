import QtQuick
import qs.Common
import qs.Services

// DMS BasePill replica (simplified). The shared wrapper for bar widgets: a
// rounded pill whose background is widgetBaseBackgroundColor blended by the
// widgetTransparency, tinted with primary on hover, with click / right-click /
// wheel signals and DMS-style barIconSize/barTextSize helpers. Vertical
// orientation is supported though the current bar is horizontal.
Item {
  id: root

  property QtObject screen: null
  property real widgetThickness: Theme.widgetThickness
  property real barThickness: Theme.barThickness
  property real barSpacing: 0
  property bool vertical: false
  property alias content: contentLoader.sourceComponent

  signal clicked
  signal rightClicked(real rootX, real rootY)
  signal wheel(var wheelEvent)

  readonly property real dpr: root.screen ? Theme.screenScaleOf(root.screen) : 1
  readonly property real horizontalPadding: Theme.snap(Math.max(0, widgetThickness / 30) * 10, dpr)
  readonly property bool isMouseHovered: mouseArea.containsMouse

  readonly property real visualWidth: vertical
    ? widgetThickness
    : (contentLoader.item ? contentLoader.item.implicitWidth + horizontalPadding * 2 : 20)
  readonly property real visualHeight: vertical
    ? (contentLoader.item ? contentLoader.item.implicitHeight + horizontalPadding * 2 : 20)
    : widgetThickness

  width: vertical ? barThickness : visualWidth
  height: vertical ? visualHeight : barThickness

  // Convenience size helpers for widgets that render their own text/icons.
  function iconSize(offset, maximize, scale) {
    return Theme.barIconSize(root.barThickness, offset, maximize, scale)
  }
  function textSize(maximize) {
    return Theme.barTextSize(root.barThickness, undefined, maximize)
  }

  Item {
    id: visualContent
    width: root.visualWidth
    height: root.visualHeight
    anchors.centerIn: parent

    Rectangle {
      id: background
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: {
        const raw = typeof SettingsData !== "undefined" ? SettingsData.barWidgetTransparency : 0.65
        const isHovered = root.isMouseHovered
        const transparency = isHovered ? Math.max(0.3, raw) : raw
        const base = isHovered ? Theme.widgetBaseHoverColor : Theme.widgetBaseBackgroundColor
        return Theme.withAlpha(base, transparency)
      }
    }

    Loader {
      id: contentLoader
      anchors.centerIn: parent
    }
  }

  MouseArea {
    id: mouseArea
    z: -1
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        const pos = mouseArea.mapToItem(root, mouse.x, mouse.y)
        root.rightClicked(pos.x, pos.y)
      } else {
        root.clicked()
      }
    }
    onWheel: function(wheelEvent) {
      wheelEvent.accepted = false
      root.wheel(wheelEvent)
    }
  }
}
