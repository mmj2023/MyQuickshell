import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services
import qs.Modules.Bar.Widgets

Item {
  id: root

  implicitWidth: 700
  implicitHeight: 410

  property bool live: true
  property bool showHourly: false
  property bool available: WeatherService.weather.available

  readonly property var heroMetrics: [
    { icon: "humidity_low", label: "Humidity", value: WeatherService.formatPercent(WeatherService.weather.humidity) },
    { icon: "air", label: "Wind", value: WeatherService.formatSpeed(WeatherService.weather.wind) },
    { icon: "speed", label: "Pressure", value: WeatherService.formatPressure(WeatherService.weather.pressure) },
    { icon: "rainy", label: "Precipitation", value: (WeatherService.weather.precipitationProbability ?? 0) + "%" },
    { icon: "wb_twilight", label: "Sunrise", value: WeatherService.weather.sunrise || "--" },
    { icon: "bedtime", label: "Sunset", value: WeatherService.weather.sunset || "--" }
  ]

  // Unavailable state
  Column {
    id: unavailableColumn
    anchors.centerIn: parent
    spacing: Theme.spacingL
    visible: !root.available

    DmsIcon {
      name: "cloud_off"
      size: Theme.iconSize * 2
      color: Theme.withAlpha(Theme.surfaceText, 0.5)
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: "No Weather Data Available"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeLarge || 16
      color: Theme.withAlpha(Theme.surfaceText, 0.7)
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Rectangle {
      width: 100; height: 32; radius: Theme.cornerRadius
      color: Theme.withAlpha(Theme.primary, 0.15)
      border.color: Theme.withAlpha(Theme.primary, 0.4)
      border.width: 1
      anchors.horizontalCenter: parent.horizontalCenter
      Text {
        anchors.centerIn: parent
        text: "Refresh"
        color: Theme.primary
        font.family: Theme.fontFamily
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: WeatherService.forceRefresh()
      }
    }
  }

  // Available state
  Column {
    id: mainColumn
    anchors.fill: parent
    visible: root.available
    spacing: Theme.spacingS

    // Hero Card
    Rectangle {
      id: heroCard
      width: parent.width
      height: heroContent.height + Theme.spacingL * 2
      radius: Theme.cornerRadius
      color: Theme.nestedSurface
      border.color: Theme.withAlpha(Theme.outline, 0.3)
      border.width: 1

      Column {
        id: heroContent
        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        spacing: Theme.spacingM

        Item {
          width: parent.width
          height: Math.max(heroLeft.height, heroMetricsGrid.height)

          Row {
            id: heroLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingL

            DmsIcon {
              id: weatherIcon
              name: WeatherService.weatherIcon(WeatherService.weather.wCode)
              size: 48
              color: Theme.primary
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: tempColumn
              spacing: Theme.spacingXS
              anchors.verticalCenter: parent.verticalCenter

              Row {
                spacing: Theme.spacingXS
                Text {
                  id: tempText
                  // text: (SettingsData.useFahrenheit ? WeatherService.weather.tempF : WeatherService.weather.temp) + "°"
                  text: (SettingsData.useFahrenheit ? WeatherService.weather.tempF : WeatherService.weather.temp)
                  // text: (SettingsData.useFahrenheit ? WeatherService.weather.tempF : WeatherService.weather.temp) + "\u00B0"
                  // font.family: Theme.monoFontFamily
                  font.family: [Theme.monoFontFamily, "Sans Serif"]
                  font.pixelSize: Theme.fontSizeXLarge ? (Theme.fontSizeXLarge + 8) : 28
                  color: Theme.surfaceText
                  font.weight: Font.Light
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  id: unitText
                  text: SettingsData.useFahrenheit ? "°F" : "°C"
                  // font.family: Theme.fontFamily
                  font.family: [Theme.monoFontFamily, "Sans Serif"]
                  font.pixelSize: Theme.fontSizeMedium
                  color: Theme.withAlpha(Theme.surfaceText, 0.7)
                  anchors.verticalCenter: parent.verticalCenter
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SettingsData.set("useFahrenheit", !SettingsData.useFahrenheit)
                  }
                }
              }

              Text {
                text: WeatherService.weatherCondition(WeatherService.weather.wCode)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.withAlpha(Theme.surfaceText, 0.7)
              }

              Text {
                property var feelsLike: SettingsData.useFahrenheit ? (WeatherService.weather.feelsLikeF || WeatherService.weather.tempF) : (WeatherService.weather.feelsLike || WeatherService.weather.temp)
                text: "Feels Like " + feelsLike + "°"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
              }

              Text {
                text: WeatherService.weather.city + (WeatherService.weather.country ? ", " + WeatherService.weather.country : "")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                visible: text.length > 0
              }
            }
          }

          Grid {
            id: heroMetricsGrid
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            columns: 3
            columnSpacing: Theme.spacingXL
            rowSpacing: Theme.spacingS

            Repeater {
              model: root.heroMetrics
              Row {
                spacing: Theme.spacingXS

                DmsIcon {
                  name: modelData.icon
                  size: 16
                  color: Theme.withAlpha(Theme.surfaceText, 0.5)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  spacing: 2
                  Text {
                    text: modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                  }
                  Text {
                    text: modelData.value
                    font.family: Theme.monoFontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                  }
                }
              }
            }
          }
        }
      }
    }

    // Sky arc section
    Item {
      id: skyDateRow
      width: parent.width
      height: 60

      Rectangle {
        id: skyBox
        anchors.fill: parent
        color: "transparent"

        property var sunTime: WeatherService.getCurrentSunTime(new Date())

        Text {
          text: skyBox.sunTime?.period ?? ""
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall
          color: Theme.withAlpha(Theme.surfaceText, 0.7)
          anchors.left: parent.left
          anchors.top: parent.top
        }

        // Sky curve
        Shape {
          anchors.fill: parent
          ShapePath {
            strokeColor: Theme.withAlpha(Theme.outline, 0.3)
            strokeWidth: 1
            fillColor: "transparent"
            PathPolyline {
              path: {
                const points = WeatherService.getEcliptic(new Date()) ?? []
                const out = []
                const w = skyBox.width
                const h = skyBox.height
                for (let i = 0; i < points.length; i++) {
                  out.push(Qt.point(points[i].h * w, points[i].v * -(h / 2) + h / 2))
                }
                return out
              }
            }
          }
        }

        // Horizon line & Compass markers
        Rectangle {
          height: 1
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          color: Theme.withAlpha(Theme.outline, 0.2)
        }

        Text {
          text: "S"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall
          color: Theme.primary
          anchors.centerIn: parent
        }
        Text {
          text: "W"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall
          color: Theme.primary
          x: parent.width * 0.75 - width/2
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: "E"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall
          color: Theme.primary
          x: parent.width * 0.25 - width/2
          anchors.verticalCenter: parent.verticalCenter
        }

        // Sun / Moon icons on arc
        DmsIcon {
          id: sunIcon
          name: "light_mode"
          size: 18
          color: Theme.primary
          visible: !!pos
          property var pos: WeatherService.getSkyArcPosition(new Date(), true)
          x: (pos?.h ?? 0) * skyBox.width - width/2
          y: (pos?.v ?? 0) * -(skyBox.height/2) + skyBox.height/2 - height/2
        }

        DmsIcon {
          id: moonIcon
          name: "bedtime"
          size: 16
          color: Theme.withAlpha(Theme.surfaceText, 0.7)
          visible: !!pos
          property var pos: WeatherService.getSkyArcPosition(new Date(), false)
          x: (pos?.h ?? 0) * skyBox.width - width/2
          y: (pos?.v ?? 0) * -(skyBox.height/2) + skyBox.height/2 - height/2
        }
      }
    }

    // Chips Row (Daily / Hourly switcher + Refresh)
    Item {
      id: chipsRow
      width: parent.width
      height: 32

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        Repeater {
          model: ["Daily", "Hourly"]
          Rectangle {
            width: 72; height: 26; radius: 13
            color: (index === 0 ? !root.showHourly : root.showHourly) ? Theme.primary : Theme.withAlpha(Theme.surfaceContainerHigh, 0.6)
            Text {
              anchors.centerIn: parent
              text: modelData
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
              color: (index === 0 ? !root.showHourly : root.showHourly) ? Theme.primaryText : Theme.surfaceText
              font.weight: (index === 0 ? !root.showHourly : root.showHourly) ? Font.Medium : Font.Normal
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showHourly = (index === 1)
            }
          }
        }
      }

      DmsIcon {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        name: "refresh"
        size: 20
        color: refreshTimer.running ? Theme.primary : Theme.withAlpha(Theme.surfaceText, 0.5)
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            WeatherService.forceRefresh()
            refreshTimer.restart()
          }
        }
        Timer { id: refreshTimer; interval: 1500 }
      }
    }

    // Forecast Cards List
    Item {
      width: parent.width
      height: 120

      ListView {
        id: dailyList
        anchors.fill: parent
        visible: !root.showHourly
        orientation: ListView.Horizontal
        spacing: Theme.spacingS
        clip: true
        model: WeatherService.weather.forecast

        delegate: WeatherForecastCard {
          width: Math.max(86, (dailyList.width - Theme.spacingS * 6) / 7)
          height: dailyList.height
          daily: true
          dense: true
          forecastData: modelData
          date: {
            const d = new Date()
            d.setDate(d.getDate() + index)
            return d
          }
        }
      }

      ListView {
        id: hourlyList
        anchors.fill: parent
        visible: root.showHourly
        orientation: ListView.Horizontal
        spacing: Theme.spacingS
        clip: true
        model: WeatherService.weather.hourlyForecast

        Component.onCompleted: positionViewAtIndex(new Date().getHours(), ListView.SnapPosition)

        delegate: WeatherForecastCard {
          width: 78
          height: hourlyList.height
          daily: false
          dense: true
          forecastData: modelData
          date: {
            const d = new Date()
            d.setHours(index)
            return d
          }
        }
      }
    }
  }
}
