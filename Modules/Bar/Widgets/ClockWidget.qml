import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

// Clock widget: bold time with a compact date, plus integrated weather display
// (weather icon + temp) beside the time reading, inspired by DMS.
// Clicking the clock opens the calendar overview; the weather indicator opens its forecast.
BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null

  Component.onCompleted: WeatherService.addRef()
  Component.onDestruction: WeatherService.removeRef()

  onClicked: {
    if (!root.barWindow)
      return
    const localPos = root.mapToItem(root.barWindow.contentItem, 0, 0)
    calendarOverview.toggle(
      localPos.x + root.width / 2,
      root.barWindow.height
    )
  }

  // Overlay popup instance for this screen/bar
  WeatherOverlay {
    id: weatherOverlay
    barWindow: root.barWindow
  }

  CalendarOverview {
    id: calendarOverview
    barWindow: root.barWindow
  }

  content: Component {
    Row {
      readonly property bool privacyActive: PrivacyService.activeIndicators.length > 0
      spacing: privacyActive ? Theme.spaceXXS : Theme.spaceS
      anchors.verticalCenter: parent.verticalCenter

      // Time + Date Column
      Column {
        spacing: 0
        anchors.verticalCenter: parent.verticalCenter

        Item {
          id: timeRow
          implicitWidth: dateRow.implicitWidth
          implicitHeight: Math.max(timeLabel.implicitHeight, Theme.iconSizeSmall)

          Text {
            id: timeLabel
            anchors.centerIn: parent
            text: ClockService.timeString
            color: Theme.widgetTextColor
            font.family: Theme.monoFontFamily
            font.pixelSize: root.textSize()
            font.bold: true
          }

          Item {
            id: wallpaperButton
            x: timeLabel.x + timeLabel.width + Theme.spaceXXS
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSizeSmall
            height: Theme.iconSizeSmall

            Rectangle {
              anchors.fill: parent
              anchors.topMargin: Theme.hoverVerticalInset
              anchors.bottomMargin: Theme.hoverVerticalInset
              radius: Theme.hoverRadius
              color: wallpaperButtonMouse.containsMouse
                ? Theme.withAlpha(Theme.primary, 0.12)
                : "transparent"
            }

            DmsIcon {
              anchors.centerIn: parent
              name: "wallpaper"
              size: root.iconSize(-3)
              color: Theme.widgetIconColor
            }

            MouseArea {
              id: wallpaperButtonMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: WallpaperService.openOverview(root.parentScreen)
            }
          }
        }

        Row {
          id: dateRow
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

      Item {
        id: privacyIndicator
        anchors.verticalCenter: parent.verticalCenter
        visible: activeIndicators.length > 0
        width: visible ? Theme.iconSizeSmall : 0
        height: root.widgetThickness
        readonly property var activeIndicators: PrivacyService.activeIndicators
        readonly property real statusIconSize: activeIndicators.length > 0
          ? Math.min(
            Theme.iconSizeSmall,
            (root.widgetThickness - Theme.spaceXXS * (activeIndicators.length - 1))
              / activeIndicators.length
          )
          : Theme.iconSizeSmall

        Column {
          anchors.centerIn: parent
          spacing: Theme.spaceXXS

          Repeater {
            model: privacyIndicator.activeIndicators

            delegate: Item {
              required property var modelData
              width: privacyIndicator.width
              height: privacyIndicator.statusIconSize

              DmsIcon {
                anchors.centerIn: parent
                name: modelData.name
                size: privacyIndicator.statusIconSize
                color: modelData.color
                filled: true
              }
            }
          }
        }
      }

      // Weather Indicator (Icon + Temp) - Clickable to open overview
      Item {
        id: weatherClickArea
        anchors.verticalCenter: parent.verticalCenter
        width: weatherRow.implicitWidth
          + (privacyIndicator.visible ? Theme.spaceXXS : Theme.spaceXS * 2)
        height: weatherRow.implicitHeight + Theme.hoverVerticalInset * 2

        Rectangle {
          anchors.fill: parent
          radius: Theme.hoverRadius
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
            if (!root.barWindow)
              return
            const localPos = weatherClickArea.mapToItem(root.barWindow.contentItem, 0, 0)
            weatherOverlay.toggle(
              localPos.x + weatherClickArea.width / 2,
              root.barWindow.height
            )
          }
        }
      }
    }
  }
}
