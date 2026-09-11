import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Clock widget: bold time with a compact date. Binds to the shared ClockService
// so every bar/screen shares one ticking timer.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null
  content: Component {
    Column {
      spacing: 0

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
  }
}
