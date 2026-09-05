import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// CPU usage pill. Reads the shared SystemStatsService so all stats share one
// poller. Left click cycles the display format (percent vs a short label).
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null

  property bool showLabel: false

  content: Component {
    Item {
      implicitWidth: collapsedRow.visible ? collapsedRow.implicitWidth : expandedColumn.implicitWidth
      implicitHeight: collapsedRow.visible ? collapsedRow.implicitHeight : expandedColumn.implicitHeight

      Row {
        id: collapsedRow
        visible: !root.showLabel
        spacing: 4
        anchors.centerIn: parent

        DmsIcon {
          name: "memory"
          size: root.iconSize()
          color: root.usageColor()
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: Math.round(SystemStatsService.cpuUsage) + "%"
          color: Theme.widgetTextColor
          font.family: Theme.monoFontFamily
          font.pixelSize: root.textSize()
        }
      }

      Column {
        id: expandedColumn
        visible: root.showLabel
        spacing: 0
        anchors.centerIn: parent
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "CPU"
          color: Theme.widgetTextColor
          font.family: Theme.monoFontFamily
          font.pixelSize: root.textSize()
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Math.round(SystemStatsService.cpuUsage) + "%"
          color: Theme.widgetInactiveIconColor
          font.family: Theme.monoFontFamily
          font.pixelSize: Math.round(root.textSize() * 0.7)
        }
      }
    }
  }

  function usageColor() {
    return SystemStatsService.cpuUsage > 80 ? Theme.error
      : (SystemStatsService.cpuUsage > 60 ? Theme.warning : Theme.widgetIconColor)
  }

  onClicked: root.showLabel = !root.showLabel
}
