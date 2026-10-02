import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Clock widget: bold time with a compact date, plus integrated weather display
// (weather icon + temp) beside the time reading, inspired by DMS.
// Clicking the weather indicator toggles the WeatherOverlay overview popup.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null

  Component.onCompleted: WeatherService.addRef()
  Component.onDestruction: WeatherService.removeRef()

  // Overlay popup instance for this screen/bar
  WeatherOverlay {
    id: weatherOverlay
    barWindow: root.barWindow
  }

  content: Component {
    Row {
      spacing: 8
      anchors.verticalCenter: parent.verticalCenter

      // Time + Date Column
      Column {
        spacing: 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ClockService.timeString
          color: Theme.widgetTextColor
          font.family: Theme.monoFontFamily
          font.pixelSize: root.textSize()
          font.bold: true
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 6

          Text {
            text: ClockService.dateString
            color: Theme.widgetInactiveIconColor
            font.family: Theme.monoFontFamily
            font.pixelSize: Math.round(root.textSize() * 0.7)
          }

          Text {
            text: ClockService.weekdayString
            color: Theme.widgetInactiveIconColor
            font.family: Theme.monoFontFamily
            font.pixelSize: Math.round(root.textSize() * 0.7)
          }
        }
      }

      // Divider between Clock and Weather
      Rectangle {
        width: 1
        height: Math.round(root.widgetThickness * 0.55)
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.withAlpha(Theme.outline, 0.25)
      }

      // Weather Indicator (Icon + Temp) - Clickable to open overview
      Item {
        id: weatherClickArea
        anchors.verticalCenter: parent.verticalCenter
        width: weatherRow.implicitWidth + 8
        height: weatherRow.implicitHeight + 6

        Rectangle {
          anchors.fill: parent
          radius: 6
          color: weatherMa.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
        }

        Row {
          id: weatherRow
          anchors.centerIn: parent
          spacing: 4

          DmsIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: WeatherService.weatherIcon(WeatherService.weather.wCode, WeatherService.weather.isDay)
            size: Math.round(root.textSize() * 0.9)
            color: Theme.widgetIconColor
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherService.currentTempText()
            color: Theme.widgetTextColor
            font.family: Theme.monoFontFamily
            font.pixelSize: Math.round(root.textSize() * 0.85)
            font.bold: true
          }
        }

        MouseArea {
          id: weatherMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            var globalPos = weatherClickArea.mapToGlobal(0, 0)
            var centerX = globalPos.x + weatherClickArea.width / 2
            var topY = globalPos.y
            weatherOverlay.toggle(centerX, topY)
          }
        }
      }
    }
  }
}
