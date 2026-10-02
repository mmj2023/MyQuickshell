import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

Item {
  id: root

  signal closeRequested

  property real hue: 0.58
  property real saturation: 0.72
  property real value: 0.88
  property real alpha: 1
  property color selectedColor: Qt.hsva(hue, saturation, value, alpha)
  readonly property var paletteColors: [
    "#f44336", "#e91e63", "#9c27b0", "#673ab7", "#3f51b5", "#2196f3",
    "#03a9f4", "#00bcd4", "#009688", "#4caf50", "#8bc34a", "#cddc39",
    "#ffeb3b", "#ffc107", "#ff9800", "#ff5722", "#ffffff", "#9e9e9e",
    "#607d8b", "#212121"
  ]

  implicitWidth: 360
  implicitHeight: 520

  function parseColor(color) {
    const text = String(color || "").trim()
    if (/^#?[0-9a-f]{8}$/i.test(text)) {
      const hex = text.charAt(0) === "#" ? text.slice(1) : text
      const rgb = Qt.color("#" + hex.slice(0, 6))
      return Qt.rgba(rgb.r, rgb.g, rgb.b, parseInt(hex.slice(6, 8), 16) / 255)
    }
    return Qt.color(text)
  }

  function setColor(color) {
    const parsed = root.parseColor(color)
    root.hue = Math.max(0, parsed.hsvHue)
    root.saturation = parsed.hsvSaturation
    root.value = parsed.hsvValue
    root.alpha = parsed.a
  }

  function hexChannel(value) {
    return Math.round(value * 255).toString(16).padStart(2, "0")
  }

  function hexColor(color) {
    let hex = "#" + root.hexChannel(color.r) + root.hexChannel(color.g) + root.hexChannel(color.b)
    if (color.a < 1)
      hex += root.hexChannel(color.a)
    return hex
  }

  function applyHex(text) {
    const value = String(text || "").trim()
    if (!/^#?[0-9a-f]{6}([0-9a-f]{2})?$/i.test(value))
      return
    root.setColor(value.charAt(0) === "#" ? value : "#" + value)
  }

  onSelectedColorChanged: hexInput.text = root.hexColor(root.selectedColor)
  Component.onCompleted: {
    const recentColors = SettingsPanelService.recentColors
    root.setColor(recentColors.length > 0 ? recentColors[0] : Theme.primary)
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.withAlpha(
      Theme.widgetBaseBackgroundColor,
      typeof SettingsData !== "undefined" ? SettingsData.barWidgetTransparency : 0.65
    )
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.35)

    Flickable {
      anchors.fill: parent
      anchors.margins: 14
      contentHeight: pickerColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: pickerColumn
        width: parent.width
        spacing: 12

        Item {
          width: parent.width
          height: 28

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Choose color"
            color: Theme.widgetTextColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.DemiBold
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "×"
            color: Theme.widgetInactiveIconColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: root.closeRequested()
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 48
          radius: 8
          color: root.selectedColor
          border.width: 1
          border.color: Theme.withAlpha(Theme.outline, 0.4)
        }

        Rectangle {
          id: saturationValuePicker
          width: parent.width
          height: 160
          radius: 8
          color: Qt.hsva(root.hue, 1, 1, 1)
          clip: true

          Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "white" }
              GradientStop { position: 1; color: "transparent" }
            }
          }

          Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
              orientation: Gradient.Vertical
              GradientStop { position: 0; color: "transparent" }
              GradientStop { position: 1; color: "black" }
            }
          }

          Rectangle {
            x: Math.max(0, Math.min(saturationValuePicker.width - 14, root.saturation * saturationValuePicker.width - 7))
            y: Math.max(0, Math.min(saturationValuePicker.height - 14, (1 - root.value) * saturationValuePicker.height - 7))
            width: 14
            height: 14
            radius: 7
            color: "transparent"
            border.width: 2
            border.color: "white"
            z: 2
          }

          MouseArea {
            anchors.fill: parent
            onPressed: updateFromPosition(mouse.x, mouse.y)
            onPositionChanged: if (pressed) updateFromPosition(mouse.x, mouse.y)

            function updateFromPosition(x, y) {
              root.saturation = Math.max(0, Math.min(1, x / saturationValuePicker.width))
              root.value = 1 - Math.max(0, Math.min(1, y / saturationValuePicker.height))
            }
          }
        }

        Rectangle {
          id: huePicker
          width: parent.width
          height: 18
          radius: 9
          gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsva(0, 1, 1, 1) }
            GradientStop { position: 0.167; color: Qt.hsva(1 / 6, 1, 1, 1) }
            GradientStop { position: 0.333; color: Qt.hsva(2 / 6, 1, 1, 1) }
            GradientStop { position: 0.5; color: Qt.hsva(3 / 6, 1, 1, 1) }
            GradientStop { position: 0.667; color: Qt.hsva(4 / 6, 1, 1, 1) }
            GradientStop { position: 0.833; color: Qt.hsva(5 / 6, 1, 1, 1) }
            GradientStop { position: 1; color: Qt.hsva(1, 1, 1, 1) }
          }

          Rectangle {
            x: Math.max(0, Math.min(huePicker.width - 10, root.hue * huePicker.width - 5))
            y: -1
            width: 10
            height: 20
            radius: 5
            color: "white"
            border.width: 1
            border.color: Theme.outline
            z: 2
          }

          MouseArea {
            anchors.fill: parent
            onPressed: updateHue(mouse.x)
            onPositionChanged: if (pressed) updateHue(mouse.x)

            function updateHue(x) {
              root.hue = Math.max(0, Math.min(1, x / huePicker.width))
            }
          }
        }

        Row {
          width: parent.width
          height: 20

          Text {
            x: 0
            text: "Opacity"
            color: Theme.widgetInactiveIconColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
          }

          Text {
            x: parent.width - width
            text: Math.round(root.alpha * 100) + "%"
            color: Theme.widgetTextColor
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall
          }
        }

        Slider {
          width: parent.width
          height: 24
          from: 0
          to: 1
          value: root.alpha
          onMoved: root.alpha = value
        }

        Row {
          width: parent.width
          height: 36
          spacing: 6

          TextField {
            id: hexInput
            width: parent.width - copyColorButton.width - 6
            height: parent.height
            text: root.hexColor(root.selectedColor)
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.widgetTextColor
            selectByMouse: true
            onEditingFinished: root.applyHex(text)
            background: Rectangle {
              radius: 7
              color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.75)
              border.width: 1
              border.color: hexInput.activeFocus ? Theme.primary : Theme.outlineVariant
            }
          }

          Rectangle {
            id: copyColorButton
            width: 76
            height: parent.height
            radius: 7
            color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.75)
            border.width: 1
            border.color: Theme.outlineVariant

            Text {
              anchors.centerIn: parent
              text: "Copy"
              color: Theme.widgetTextColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: SettingsPanelService.copyColor(root.hexColor(root.selectedColor))
            }
          }
        }

        Row {
          width: parent.width
          spacing: 8

          Text {
            width: (parent.width - parent.spacing) / 2
            text: "RGB  " + Math.round(root.selectedColor.r * 255) + ", "
              + Math.round(root.selectedColor.g * 255) + ", "
              + Math.round(root.selectedColor.b * 255)
            color: Theme.widgetInactiveIconColor
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall - 1
            elide: Text.ElideRight
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.clipboardText = parent.text
            }
          }

          Text {
            width: (parent.width - parent.spacing) / 2
            text: "HSV  " + Math.round(root.hue * 360) + ", "
              + Math.round(root.saturation * 100) + ", " + Math.round(root.value * 100)
            color: Theme.widgetInactiveIconColor
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall - 1
            elide: Text.ElideRight
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.clipboardText = parent.text
            }
          }
        }

        Text {
          width: parent.width
          visible: SettingsPanelService.errorMessage !== ""
          text: SettingsPanelService.errorMessage
          color: Theme.error
          wrapMode: Text.Wrap
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall - 1
        }

        Rectangle {
          width: parent.width
          height: 38
          radius: 8
          color: Theme.withAlpha(Theme.primary, 0.16)
          border.width: 1
          border.color: Theme.withAlpha(Theme.primary, 0.4)

          Row {
            anchors.centerIn: parent
            spacing: 8

            DmsIcon {
              name: "colorize"
              size: 18
              color: Theme.primary
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Copy screen color"
              color: Theme.widgetTextColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: SettingsPanelService.colorPickerRunning ? Qt.ArrowCursor : Qt.PointingHandCursor
            enabled: !SettingsPanelService.colorPickerRunning
            onClicked: SettingsPanelService.pickColor()
          }
        }

        Text {
          width: parent.width
          text: "Recent colors"
          color: Theme.widgetInactiveIconColor
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall
          visible: SettingsPanelService.recentColors.length > 0
        }

        Flow {
          width: parent.width
          spacing: 5
          visible: SettingsPanelService.recentColors.length > 0

          Repeater {
            model: SettingsPanelService.recentColors.slice(0, 10)

            Rectangle {
              required property string modelData
              width: 26
              height: 26
              radius: 13
              color: root.parseColor(modelData)
              border.width: 1
              border.color: Theme.withAlpha(Theme.outline, 0.5)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setColor(parent.modelData)
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "Colors"
          color: Theme.widgetInactiveIconColor
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSmall
        }

        Grid {
          width: parent.width
          columns: 10
          spacing: 2

          Repeater {
            model: root.paletteColors

            Rectangle {
              required property string modelData
              width: (parent.width - 18) / 10
              height: 27
              radius: 5
              color: modelData
              border.width: 1
              border.color: Theme.withAlpha(Theme.outline, 0.35)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setColor(parent.modelData)
              }
            }
          }
        }
      }
    }
  }

  Connections {
    target: SettingsPanelService
    function onPickedColorChanged() {
      if (SettingsPanelService.pickedColor !== "")
        root.setColor(SettingsPanelService.pickedColor)
    }
  }
}
