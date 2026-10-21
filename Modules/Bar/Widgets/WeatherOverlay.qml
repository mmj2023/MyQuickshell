import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Bar.Widgets

// Weather overview popup styled after DMS's weather dashboard.
PopupWindow {
  id: root

  property var barWindow: null
  property real anchorX: 0
  property real anchorY: 0

  anchor.window: root.barWindow
  anchor.rect.x: Math.max(Theme.spaceS, Math.min(
    (root.barWindow ? root.barWindow.width : Screen.width) - implicitWidth - Theme.spaceS,
    root.anchorX - implicitWidth / 2
  ))
  anchor.rect.y: root.anchorY + Theme.spaceXS
  visible: false
  grabFocus: true
  color: "transparent"
  surfaceFormat.opaque: false
  implicitWidth: Math.min(860, Math.max(380, Screen.width - Theme.spaceXL * 2))
  implicitHeight: column.implicitHeight + Theme.spaceL * 2 +
    (locationSuggestions.length > 0 ? Math.min(160, locationSuggestionList.contentHeight) + Theme.spaceL : 0)

  readonly property var locationSuggestions: WeatherService.locationSuggestions
  readonly property bool locationSearchPending: WeatherService.locationSearchPending
  readonly property var heroMetrics: [
    { icon: "humidity_low", label: qsTr("Humidity"), value: WeatherService.formatPercent(WeatherService.weather.humidity) },
    { icon: "air", label: qsTr("Wind"), value: WeatherService.formatSpeed(WeatherService.weather.wind) },
    { icon: "speed", label: qsTr("Pressure"), value: WeatherService.formatPressure(WeatherService.weather.pressure) },
    { icon: "rainy", label: qsTr("Precipitation"), value: WeatherService.formatPercent(WeatherService.weather.precipitationProbability) },
    { icon: "wb_twilight", label: qsTr("Sunrise"), value: WeatherService.weather.sunrise || "--" },
    { icon: "bedtime", label: qsTr("Sunset"), value: WeatherService.weather.sunset || "--" }
  ]

  onVisibleChanged: {
    if (visible) {
      WeatherService.addRef()
      Qt.callLater(function() { locInput.forceActiveFocus() })
    } else {
      WeatherService.removeRef()
      WeatherService.searchLocations("")
    }
  }

  function toggle(ax, ay) {
    anchorX = ax; anchorY = ay
    visible = !visible
  }

  function close() {
    visible = false
  }

  function searchLocations(query) {
    WeatherService.searchLocations(query)
  }

  function selectLocation(location) {
    if (!location || !Number.isFinite(Number(location.latitude)) ||
        !Number.isFinite(Number(location.longitude)))
      return
    WeatherService.searchLocations("")
    locInput.text = ""
    SettingsData.set("weatherCoordinates", location.latitude + "," + location.longitude)
    SettingsData.set("weatherLocation", location.name)
    WeatherService.updateLocation()
  }

  Rectangle {
    id: popupBg
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.withAlpha(
      Theme.widgetBaseBackgroundColor,
      typeof SettingsData !== "undefined" ? SettingsData.barWidgetTransparency : 0.65
    )
    border.width: 0

    Column {
      id: column
      anchors { left: parent.left; right: parent.right; top: parent.top }
      anchors.margins: Theme.spaceL
      spacing: Theme.spaceS

      // Current conditions and the six key weather readings.
      Rectangle {
        id: heroCard
        width: parent.width
        height: 148
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.6)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.18)

        Row {
          anchors.fill: parent
          anchors.margins: Theme.spaceL
          spacing: Theme.spaceL

          Row {
            width: heroCard.width * 0.38
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceL

            DmsIcon {
              anchors.verticalCenter: parent.verticalCenter
              name: WeatherService.weatherIcon(WeatherService.weather.wCode, WeatherService.weather.isDay)
              size: 48
              color: Theme.primary
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.spaceXS

              Text {
                text: WeatherService.currentTempText()
                color: Theme.surfaceText
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeMedium * 2.3
                font.weight: Font.Light
              }

              Text {
                text: WeatherService.weatherCondition(WeatherService.weather.wCode)
                color: Theme.withAlpha(Theme.surfaceText, 0.72)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
              }

              Text {
                text: qsTr("Feels Like %1").arg(WeatherService.formatTemp(WeatherService.weather.feelsLike))
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }

              Text {
                visible: text.length > 0
                text: [WeatherService.weather.city, WeatherService.weather.country].filter(Boolean).join(", ")
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
              }
            }
          }

          Grid {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            columns: 3
            columnSpacing: Theme.spaceXL
            rowSpacing: Theme.spaceS

            Repeater {
              model: root.heroMetrics

              delegate: Row {
                required property var modelData
                spacing: Theme.spaceXS

                DmsIcon {
                  name: modelData.icon
                  size: 16
                  color: Theme.withAlpha(Theme.surfaceText, 0.5)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  spacing: Theme.spaceXXS
                  Text {
                    text: modelData.label
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                  }
                  Text {
                    text: modelData.value
                    color: Theme.surfaceText
                    font.family: Theme.monoFontFamily
                    font.pixelSize: Theme.fontSizeMedium
                  }
                }
              }
            }
          }
        }
      }

      Rectangle {
        id: skyCard
        width: parent.width
        height: 76
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.25)

        Text {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: Theme.spaceS
          text: WeatherService.getCurrentSunTime(new Date())?.period || ""
          color: Theme.withAlpha(Theme.surfaceText, 0.62)
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall
        }

        Rectangle {
          visible: !!WeatherService.location
          height: 1
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Theme.spaceS
          anchors.rightMargin: Theme.spaceS
          color: Theme.withAlpha(Theme.outline, 0.2)
        }

        Shape {
          visible: !!WeatherService.location
          anchors.fill: parent
          anchors.margins: Theme.spaceS

          ShapePath {
            strokeColor: Theme.withAlpha(Theme.outline, 0.35)
            strokeWidth: 1
            fillColor: "transparent"
            PathPolyline {
              path: {
                const points = WeatherService.getEcliptic(new Date()) || []
                return points.map(point => Qt.point(
                  point.h * (skyCard.width - Theme.spaceS * 2),
                  (1 - point.v) * (skyCard.height - Theme.spaceS * 2) / 2
                ))
              }
            }
          }
        }

        Row {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: Theme.spaceL
          anchors.rightMargin: Theme.spaceL
          anchors.bottomMargin: Theme.spaceXS
          spacing: 0

          Repeater {
            model: ["E", "S", "W"]
            delegate: Text {
              required property string modelData
              width: parent.width / 3
              text: modelData
              color: Theme.primary
              font.family: Theme.monoFontFamily
              font.pixelSize: Theme.fontSizeSmall
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }

        DmsIcon {
          id: sunMarker
          property var position: WeatherService.getSkyArcPosition(new Date(), true)
          visible: !!position
          x: Theme.spaceS + (position?.h ?? 0) * (parent.width - Theme.spaceS * 2) - width / 2
          y: Theme.spaceS + (1 - (position?.v ?? 0)) * (parent.height - Theme.spaceS * 2) / 2 - height / 2
          name: "light_mode"
          size: 20
          color: Theme.primary
        }

        DmsIcon {
          id: moonMarker
          property var position: WeatherService.getSkyArcPosition(new Date(), false)
          visible: !!position
          x: Theme.spaceS + (position?.h ?? 0) * (parent.width - Theme.spaceS * 2) - width / 2
          y: Theme.spaceS + (1 - (position?.v ?? 0)) * (parent.height - Theme.spaceS * 2) / 2 - height / 2
          name: "bedtime"
          size: 16
          color: Theme.withAlpha(Theme.surfaceText, 0.7)

          ToolTip.visible: moonHover.containsMouse
          ToolTip.text: {
            const phase = WeatherService.getMoonPhase(new Date()).replace(/^moon_/, "").replace(/_/g, " ")
            return phase.charAt(0).toUpperCase() + phase.slice(1)
          }

          MouseArea {
            id: moonHover
            anchors.fill: parent
            hoverEnabled: true
          }
        }
      }

      // Forecast mode and actions.
      Row {
        id: forecastToolbar
        width: parent.width
        height: 36
        spacing: Theme.spaceS
        Repeater {
          model: [qsTr("Daily"), qsTr("Hourly")]
          Rectangle {
            width: 64
            height: 36
            radius: Theme.pillRadius
            color: (index === 0 ? !showHourly : showHourly) ? Theme.primary : "transparent"
            Text {
              anchors.centerIn: parent
              text: modelData
              color: (index === 0 ? !showHourly : showHourly) ? Theme.onPrimary : Theme.withAlpha(Theme.surfaceText, 0.6)
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: showHourly = index === 1
            }
          }
        }

        Item { width: Math.max(0, parent.width - 232); height: 1 }

        Rectangle {
          width: 36
          height: 36
          radius: Theme.pillRadius
          color: refreshMa.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
          DmsIcon {
            anchors.centerIn: parent
            name: "refresh"
            size: 20
            color: WeatherService.weather.loading ? Theme.primary : Theme.widgetInactiveIconColor
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
          width: 36
          height: 36
          radius: Theme.pillRadius
          color: closeMa.containsMouse ? Theme.withAlpha(Theme.error, 0.15) : "transparent"
          DmsIcon {
            anchors.centerIn: parent
            name: "close"
            size: 20
            color: closeMa.containsMouse ? Theme.error : Theme.widgetInactiveIconColor
          }
          MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close()
          }
        }
      }

      // ---- Forecast list ---------------------------------------------------
      Item {
        width: parent.width
        height: 148

        // Daily
        ListView {
          id: dailyList
          anchors.fill: parent
          visible: !showHourly
          orientation: ListView.Horizontal
          spacing: Theme.spaceXS
          clip: true
          model: WeatherService.weather.forecast

          delegate: WeatherForecastCard {
            width: (dailyList.width - Theme.spaceXS * 6) / 7
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
          spacing: Theme.spaceXS
          clip: true
          model: WeatherService.weather.hourlyForecast

          property int initialIndex: new Date().getHours()
          Component.onCompleted: positionViewAtIndex(initialIndex, ListView.SnapPosition)

          delegate: WeatherForecastCard {
            width: (hourlyList.width - Theme.spaceXS * 6) / 7
            height: hourlyList.height
            daily: false
            forecastData: modelData
            date: modelData?.rawTime ? new Date(modelData.rawTime) : null
          }
        }
      }

      // ---- Location settings row -------------------------------------------
      Rectangle {
        id: locationSettingsCard
        width: parent.width
        height: locRow.implicitHeight + 12
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.4)

        Row {
          id: locRow
          anchors { left: parent.left; right: parent.right; top: parent.top }
          anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.topMargin: 6
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
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.8)
            border.color: locInput.activeFocus ? Theme.withAlpha(Theme.primary, 0.6) : Theme.withAlpha(Theme.outline, 0.25)
            border.width: 1

            TextInput {
              id: locInput
              anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
              focus: true
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
              onTextChanged: root.searchLocations(text)
              onAccepted: applyLocation()
            }
          }

          Rectangle {
            width: 70; height: 26; radius: Theme.hoverRadius
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
            width: 60; height: 26; radius: Theme.hoverRadius
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

        Rectangle {
          id: suggestionsBackground
          x: 34
          y: locRow.height + 12
          width: locationSettingsCard.width - 190
          height: Math.min(160, locationSuggestionList.contentHeight) + 8
          radius: Theme.cornerRadius
          z: 10
          visible: root.locationSuggestions.length > 0
          opacity: root.locationSearchPending ? 0.72 : 1
          color: Theme.withAlpha(
            Theme.widgetBaseBackgroundColor,
            typeof SettingsData !== "undefined" ? SettingsData.barWidgetTransparency : 0.65
          )
          Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }

          ListView {
            id: locationSuggestionList
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            enabled: !root.locationSearchPending
            interactive: contentHeight > height
            model: root.locationSuggestions
            delegate: Rectangle {
              required property var modelData
              width: locationSuggestionList.width
              height: 32
              radius: Theme.hoverRadius
              color: suggestionMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"

              Text {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: [modelData.name, modelData.admin1, modelData.country].filter(Boolean).join(", ")
                color: Theme.surfaceText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }

              MouseArea {
                id: suggestionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectLocation(modelData)
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
