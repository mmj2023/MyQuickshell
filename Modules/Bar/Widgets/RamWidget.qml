import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Memory usage pill. Reads the shared SystemStatsService so all stats share one
// poller. Left click cycles the display format (percent vs used/total label).
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null

  property bool showLabel: false

  content: Component {
    Column {
      spacing: 0
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.showLabel ? "MEM" : Math.round(SystemStatsService.memoryUsage) + "%"
        color: Theme.widgetTextColor
        font.family: Theme.monoFontFamily
        font.pixelSize: root.textSize()
      }
      Text {
        visible: root.showLabel
        anchors.horizontalCenter: parent.horizontalCenter
        text: SystemStatsService.memUsedText + "/" + SystemStatsService.memTotalText
        color: Theme.widgetInactiveIconColor
        font.family: Theme.monoFontFamily
        font.pixelSize: Math.round(root.textSize() * 0.7)
      }
    }
  }

  onClicked: root.showLabel = !root.showLabel
}
