import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Bar.Widgets

// Weather overview popup. Opened by ClockWidget when the user clicks the temp.
// Positioned above the bar. Contains current conditions, metrics, 7-day and
// hourly forecast lists, and an inline location settings row.
FloatingWindow {
  id: root

  property var barWindow: null
  property real anchorX: 0   // global X of click point
  property real anchorY: 0   // top of bar (global)

  visible: false
  implicitWidth: 520
  implicitHeight: column.implicitHeight + 32

  // Re-position whenever the window becomes visible or anchor changes
  onVisibleChanged: if (visible) _reposition()
  onAnchorXChanged: _reposition()
  onAnchorYChanged: _reposition()

  function _reposition() {
    const wx = Math.max(8, Math.min(anchorX - implicitWidth/2, (Screen.width||1920) - implicitWidth - 8))
    x = wx
    y = anchorY - implicitHeight - 4
  }

  function toggle(ax, ay) {
    anchorX = ax; anchorY = ay
    visible = !visible
    if (visible) WeatherService.addRef()
    else WeatherService.removeRef()
  }


  // Close when clicking outside
  MouseArea {
    anchors.fill: parent
    propagateComposedEvents: true
    onPressed: function(e) { e.accepted = false }
  }

  Rectangle {
    id: popupBg
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.surfaceContainer, 0.95)
    border.color: Theme.withAlpha(Theme.outline, 0.3)
    border.width: 1

    Column {
      id: column
      anchors { left: parent.left; right: parent.right; top: parent.top }
      anchors.margins: 16
      spacing: 12

      // ---- Header: icon + temp + condition + location -----------------------
      Item {
        width: parent.width
        height: heroRow.implicitHeight

        Row {
          id: heroRow
          spacing: 12
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter

          // Weather icon via DmsIcon
          DmsIcon {
            width: 40; height: 40
            size: 36
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
            name: WeatherService.weatherIcon(WeatherService.weather.wCode, WeatherService.weather.isDay)
          }

          Column {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter
            Row {
              spacing: 6
              Text {
                text: WeatherService.currentTempText()
                color: Theme.surfaceText
                font.family: Theme.monoFontFamily
                font.pixelSize: Math.round(Theme.fontSizeMedium * 1.6)
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: WeatherService.weather.feelsLike !== WeatherService.weather.temp
                  ? "feels " + WeatherService.formatTemp(WeatherService.weather.feelsLike) : ""
                visible: text !== ""
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Text {
              text: WeatherService.weatherCondition(WeatherService.weather.wCode)
              color: Theme.withAlpha(Theme.surfaceText, 0.7)
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }
            Text {
              text: WeatherService.weather.city + (WeatherService.weather.country ? ", " + WeatherService.weather.country : "")
              visible: WeatherService.weather.city !== ""
              color: Theme.withAlpha(Theme.surfaceText, 0.5)
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall - 1
            }
          }
        }

        // Header actions (refresh + close)
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4

          Rectangle {
            width: 28; height: 28; radius: 14
            color: refreshMa.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
            DmsIcon {
              anchors.centerIn: parent
              name: "refresh"
              size: 18
              color: Theme.withAlpha(Theme.surfaceText, 0.6)
            }
            MouseArea {
              id: refreshMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: WeatherService.forceRefresh()
            }
          }

          Rectangle {
            width: 28; height: 28; radius: 14
            color: closeMa.containsMouse ? Theme.withAlpha(Theme.error, 0.15) : "transparent"
            DmsIcon {
              anchors.centerIn: parent
              name: "close"
              size: 18
              color: closeMa.containsMouse ? Theme.error : Theme.withAlpha(Theme.surfaceText, 0.6)
            }
            MouseArea {
              id: closeMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggle(root.anchorX, root.anchorY)
            }
          }
        }
      }

      // ---- Metrics row ------------------------------------------------------
      Rectangle {
        width: parent.width
        height: metricsRow.implicitHeight + 16
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.6)

        Row {
          id: metricsRow
          anchors.centerIn: parent
          spacing: 0

          Repeater {
            model: [
              {label:"Humidity",    value:WeatherService.weather.humidity+"%"},
              {label:"Wind",        value:WeatherService.formatSpeed(WeatherService.weather.wind)},
              {label:"Pressure",    value:WeatherService.formatPressure(WeatherService.weather.pressure)},
              {label:"Rain",        value:WeatherService.weather.precipitationProbability+"%"},
              {label:"Sunrise",     value:WeatherService.weather.sunrise},
              {label:"Sunset",      value:WeatherService.weather.sunset}
            ]

            Column {
              spacing: 2
              width: 520 / 6 - 6
              leftPadding: 4; rightPadding: 4

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.label
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall - 1
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.value
                color: Theme.surfaceText
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
              }
            }
          }
        }
      }

      // ---- Forecast tab switcher -------------------------------------------
      Row {
        spacing: 8
        Repeater {
          model: ["Daily", "Hourly"]
          Rectangle {
            width: 72; height: 24; radius: 12
            color: (index===0 ? !showHourly : showHourly) ? Theme.withAlpha(Theme.primary, 0.15) : "transparent"
            border.color: (index===0 ? !showHourly : showHourly) ? Theme.withAlpha(Theme.primary, 0.4) : Theme.withAlpha(Theme.outline, 0.2)
            border.width: 1
            Text {
              anchors.centerIn: parent
              text: modelData
              color: (index===0 ? !showHourly : showHourly) ? Theme.primary : Theme.withAlpha(Theme.surfaceText, 0.6)
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: showHourly = (index===1)
            }
          }
        }
      }

      // ---- Forecast list ---------------------------------------------------
      Item {
        width: parent.width
        height: 110

        // Daily
        ListView {
          id: dailyList
          anchors.fill: parent
          visible: !showHourly
          orientation: ListView.Horizontal
          spacing: 6
          clip: true
          model: WeatherService.weather.forecast

          delegate: WeatherForecastCard {
            width: (dailyList.width - 6*6) / 7
            height: dailyList.height
            daily: true
            forecastData: modelData
            date: { const d=new Date(); d.setDate(d.getDate()+index); return d }
          }
        }

        // Hourly
        ListView {
          id: hourlyList
          anchors.fill: parent
          visible: showHourly
          orientation: ListView.Horizontal
          spacing: 6
          clip: true
          model: WeatherService.weather.hourlyForecast

          property int initialIndex: new Date().getHours()
          Component.onCompleted: positionViewAtIndex(initialIndex, ListView.SnapPosition)

          delegate: WeatherForecastCard {
            width: (hourlyList.width - 6*9) / 10
            height: hourlyList.height
            daily: false
            forecastData: modelData
            date: { const d=new Date(); d.setHours(index); return d }
          }
        }
      }

      // ---- Location settings row -------------------------------------------
      Rectangle {
        width: parent.width
        height: locRow.implicitHeight + 12
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.4)

        Row {
          id: locRow
          anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
          anchors.leftMargin: 10; anchors.rightMargin: 10
          spacing: 8

          DmsIcon {
            name: "location_on"
            size: 16
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
          }

          Rectangle {
            width: parent.width - 170
            height: 26
            radius: 6
            color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.8)
            border.color: locInput.activeFocus ? Theme.withAlpha(Theme.primary, 0.6) : Theme.withAlpha(Theme.outline, 0.25)
            border.width: 1

            TextInput {
              id: locInput
              anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
              verticalAlignment: TextInput.AlignVCenter
              color: Theme.surfaceText
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
              property string placeholderText: "City name or lat,lon"
              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: !locInput.activeFocus && locInput.text === ""
                text: locInput.placeholderText
                color: Theme.withAlpha(Theme.surfaceText, 0.35)
                font: locInput.font
              }
              onAccepted: applyLocation()
            }
          }

          Rectangle {
            width: 70; height: 26; radius: 6
            color: applyMa.containsMouse ? Theme.withAlpha(Theme.primary, 0.2) : Theme.withAlpha(Theme.primary, 0.1)
            border.color: Theme.withAlpha(Theme.primary, 0.4)
            border.width: 1
            Text {
              anchors.centerIn: parent
              text: "Set"
              color: Theme.primary
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea {
              id: applyMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: applyLocation()
            }
          }

          Rectangle {
            width: 60; height: 26; radius: 6
            color: autoMa.containsMouse ? Theme.withAlpha(Theme.secondary, 0.2) : Theme.withAlpha(Theme.secondary, 0.1)
            border.color: Theme.withAlpha(Theme.secondary, 0.4)
            border.width: 1
            Text {
              anchors.centerIn: parent
              text: "Auto IP"
              color: Theme.secondary
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall - 1
            }
            MouseArea {
              id: autoMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (typeof SettingsData !== "undefined") {
                  SettingsData.set("weatherLocation", "")
                  SettingsData.set("weatherCoordinates", "")
                }
                WeatherService.location = null
                WeatherService.forceRefresh()
              }
            }
          }
        }
      }

      // Error text
      Text {
        visible: WeatherService.lastFetchError !== "" && !WeatherService.weather.available
        text: WeatherService.lastFetchError
        color: Theme.withAlpha(Theme.error, 0.8)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall - 1
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }
  }

  property bool showHourly: false

  function applyLocation() {
    const txt = locInput.text.trim()
    if (!txt) return
    const parts = txt.split(",")
    if (parts.length === 2 && !isNaN(parseFloat(parts[0])) && !isNaN(parseFloat(parts[1]))) {
      SettingsData.set("weatherCoordinates", txt)
      SettingsData.set("weatherLocation", "")
    } else {
      SettingsData.set("weatherLocation", txt)
      SettingsData.set("weatherCoordinates", "")
    }
    locInput.text = ""
    WeatherService.forceRefresh()
  }

  Component.onCompleted: {
    if (typeof SettingsData !== "undefined") {
      const c = SettingsData.weatherCoordinates || ""
      const l = SettingsData.weatherLocation || ""
      locInput.placeholderText = (c || l) ? (c || l) : "City name or lat,lon"
    }
  }
}
