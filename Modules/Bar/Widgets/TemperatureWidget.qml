import QtQuick
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

BasePill {
  id: root

  property bool showLabel: false

  content: Component {
    Item {
      implicitWidth: compactRow.visible ? compactRow.implicitWidth : expandedColumn.implicitWidth
      implicitHeight: compactRow.visible ? compactRow.implicitHeight : expandedColumn.implicitHeight

      Row {
        id: compactRow
        visible: !root.showLabel
        spacing: 4
        anchors.centerIn: parent

        DmsIcon {
          name: "device_thermostat"
          size: root.iconSize()
          color: root.temperatureColor()
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: root.temperatureText()
          color: Theme.widgetTextColor
          font.family: Theme.monoFontFamily
          font.pixelSize: root.textSize()
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Column {
        id: expandedColumn
        visible: root.showLabel
        spacing: 0
        anchors.centerIn: parent

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "TEMP"
          color: Theme.widgetTextColor
          font.family: Theme.monoFontFamily
          font.pixelSize: root.textSize()
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.temperatureText()
          color: Theme.widgetInactiveIconColor
          font.family: Theme.monoFontFamily
          font.pixelSize: Math.round(root.textSize() * 0.7)
        }
      }
    }
  }

  function temperatureText() {
    return SystemStatsService.cpuTemperature > 0
      ? Math.round(SystemStatsService.cpuTemperature) + "°"
      : "--°"
  }

  function temperatureColor() {
    return SystemStatsService.cpuTemperature > 85 ? Theme.error
      : (SystemStatsService.cpuTemperature > 69 ? Theme.warning : Theme.widgetIconColor)
  }

  onClicked: root.showLabel = !root.showLabel
}
