import QtQuick
import QtQuick.Controls
import Quickshell
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
  property bool groupedMemory: false
  property bool showMemoryLabel: false
  property bool cpuHovered: false
  property bool memoryHovered: false
  property bool gpuExpanded: false
  property bool gpuTooltipHovered: false
  property string gpuTooltipText: ""
  property real gpuTooltipX: 0
  property real gpuTooltipY: 0

  function showGpuTooltip(item, text) {
    if (!root.barWindow)
      return
    root.gpuTooltipText = text
    const point = item.mapToItem(root.barWindow.contentItem, item.width / 2, item.height)
    const screenWidth = root.parentScreen ? root.parentScreen.width : root.barWindow.width
    const popupWidth = gpuTooltipPopup.implicitWidth
    root.gpuTooltipX = Math.max(16, Math.min(screenWidth - popupWidth - 16, point.x - popupWidth / 2))
    root.gpuTooltipY = Math.round(point.y + Theme.spaceXS)
    gpuTooltipDelay.restart()
  }

  function hideGpuTooltip() {
    root.gpuTooltipHovered = false
    gpuTooltipDelay.stop()
    gpuTooltipPopup.visible = false
  }

  content: Component {
    Item {
      implicitWidth: contentRow.implicitWidth
      implicitHeight: root.widgetThickness

      Row {
        id: contentRow
        height: parent.implicitHeight
        spacing: 8
        anchors.centerIn: parent

        Item {
          id: cpuSection
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: (root.showLabel ? cpuExpanded.implicitWidth : cpuCompact.implicitWidth)
            + Theme.spaceXS * 2
          implicitHeight: (root.showLabel ? cpuExpanded.implicitHeight : cpuCompact.implicitHeight)
            + Theme.hoverVerticalInset * 2
          width: implicitWidth
          height: Math.min(parent.height, implicitHeight)

          Row {
            id: cpuCompact
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
            id: cpuExpanded
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

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: root.cpuHovered = containsMouse
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton)
                root.openOverview("processor", cpuSection)
              else
                root.showLabel = !root.showLabel
            }
          }

          Rectangle {
            anchors.fill: parent
            radius: Theme.hoverRadius
            color: root.cpuHovered ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
            z: -1
          }
        }

        Rectangle {
          visible: root.groupedMemory
          width: 1
          height: Math.round(root.widgetThickness * 0.55)
          anchors.verticalCenter: parent.verticalCenter
          color: Theme.withAlpha(Theme.outline, 0.25)
        }

        Item {
          id: memorySection
          visible: root.groupedMemory
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: (root.showMemoryLabel ? memoryExpanded.implicitWidth : memoryCompact.implicitWidth)
            + Theme.spaceXS * 2
          implicitHeight: (root.showMemoryLabel ? memoryExpanded.implicitHeight : memoryCompact.implicitHeight)
            + Theme.hoverVerticalInset * 2
          width: implicitWidth
          height: Math.min(parent.height, implicitHeight)

          Row {
            id: memoryCompact
            visible: !root.showMemoryLabel
            spacing: 4
            anchors.centerIn: parent

            DmsIcon {
              name: "developer_board"
              size: root.iconSize()
              color: root.memoryColor()
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: Math.round(SystemStatsService.memoryUsage) + "%"
              color: Theme.widgetTextColor
              font.family: Theme.monoFontFamily
              font.pixelSize: root.textSize()
            }
          }

          Column {
            id: memoryExpanded
            visible: root.showMemoryLabel
            spacing: 0
            anchors.centerIn: parent

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "MEM"
              color: Theme.widgetTextColor
              font.family: Theme.monoFontFamily
              font.pixelSize: root.textSize()
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: SystemStatsService.memUsedText + "/" + SystemStatsService.memTotalText
              color: Theme.widgetInactiveIconColor
              font.family: Theme.monoFontFamily
              font.pixelSize: Math.round(root.textSize() * 0.7)
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: root.memoryHovered = containsMouse
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton)
                root.openOverview("memory", memorySection)
              else
                root.showMemoryLabel = !root.showMemoryLabel
            }
          }

          Rectangle {
            anchors.fill: parent
            radius: Theme.hoverRadius
            color: root.memoryHovered ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
            z: -1
          }
        }

        Repeater {
          model: SystemStatsService.gpus

          delegate: Item {
            required property var modelData
            implicitWidth: gpuContent.implicitWidth + Theme.spaceXS * 2
            implicitHeight: gpuContent.implicitHeight + Theme.hoverVerticalInset * 2
            width: implicitWidth
            height: Math.min(contentRow.height, implicitHeight)
            anchors.verticalCenter: contentRow.verticalCenter

            Rectangle {
              width: 1
              height: Math.round(root.widgetThickness * 0.55)
              anchors.verticalCenter: parent.verticalCenter
              color: Theme.withAlpha(Theme.outline, 0.25)
            }

            Column {
              id: gpuContent
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Row {
                id: gpuPrimaryRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 3
                height: Math.max(gpuIcon.size, gpuValue.implicitHeight)

                DmsIcon {
                  id: gpuIcon
                  name: "developer_board"
                  size: root.gpuExpanded ? root.iconSize() : Math.round(root.iconSize() * 0.85)
                  color: modelData.utilization >= 90 ? Theme.error : Theme.widgetIconColor
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: gpuValue
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.utilization >= 0
                    ? Math.round(modelData.utilization) + "%"
                    : "—"
                  color: modelData.utilization >= 90 ? Theme.error : Theme.widgetTextColor
                  font.family: Theme.monoFontFamily
                  font.pixelSize: root.gpuExpanded ? Math.round(root.textSize() * 0.8)
                    : root.textSize()
                  font.bold: true
                }
              }

              Text {
                id: gpuVramPercent
                visible: !root.gpuExpanded
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.memoryPercent >= 0
                  ? "VRAM " + Math.round(modelData.memoryPercent) + "%"
                  : "VRAM —"
                color: Theme.widgetInactiveIconColor
                font.family: Theme.monoFontFamily
                font.pixelSize: Math.max(9, Math.round(root.textSize() * 0.7))
              }

              Text {
                id: gpuVramDetails
                visible: root.gpuExpanded
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.memoryUsage >= 0 && modelData.memoryTotal > 0
                  ? Math.round(modelData.memoryUsage) + "/" + Math.round(modelData.memoryTotal) + " MiB"
                  : qsTr("VRAM —")
                color: Theme.widgetInactiveIconColor
                font.family: Theme.monoFontFamily
                font.pixelSize: Math.max(9, Math.round(root.textSize() * 0.55))
              }
            }

            Rectangle {
              anchors.fill: parent
              radius: Theme.hoverRadius
              color: gpuMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
              z: -1
            }

            MouseArea {
              id: gpuMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onEntered: {
                root.gpuTooltipHovered = true
                const memoryText = modelData.memoryUsage >= 0 && modelData.memoryTotal > 0
                  ? qsTr("%1 / %2 MiB VRAM")
                    .arg(Math.round(modelData.memoryUsage))
                    .arg(Math.round(modelData.memoryTotal))
                  : qsTr("VRAM unavailable")
                root.showGpuTooltip(parent,
                  modelData.name + " · "
                    + (modelData.utilization >= 0
                      ? qsTr("%1% GPU").arg(modelData.utilization.toFixed(1))
                      : qsTr("GPU utilization unavailable"))
                    + " · " + memoryText)
              }
              onExited: root.hideGpuTooltip()
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton)
                  root.openOverview("gpu")
                else
                  root.gpuExpanded = !root.gpuExpanded
              }
            }
          }
        }
      }
    }
  }

  property string overviewTab: "processor"
  property real overviewAnchorX: 0

  Timer {
    id: gpuTooltipDelay
    interval: 450
    repeat: false
    onTriggered: {
      if (root.gpuTooltipHovered)
        gpuTooltipPopup.visible = true
    }
  }

  PopupWindow {
    id: gpuTooltipPopup
    anchor.window: root.barWindow
    anchor.rect.x: root.gpuTooltipX
    anchor.rect.y: root.gpuTooltipY
    visible: false
    color: "transparent"
    implicitWidth: gpuTooltipText.implicitWidth + Theme.spaceL * 2
    implicitHeight: gpuTooltipText.implicitHeight + Theme.spaceM * 2

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.withAlpha(
        Theme.widgetBaseBackgroundColor,
        typeof SettingsData !== "undefined" ? SettingsData.barWidgetTransparency : 0.65
      )

      Text {
        id: gpuTooltipText
        anchors.centerIn: parent
        text: root.gpuTooltipText
        color: Theme.widgetTextColor
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize()
      }
    }
  }

  function openOverview(tab, sourceItem) {
    if (!root.groupedMemory || !root.barWindow)
      return
    overviewTab = tab
    const anchorItem = sourceItem || root
    const position = anchorItem.mapToItem(root.barWindow.contentItem,
      anchorItem.width / 2, anchorItem.height)
    overviewAnchorX = position.x
    processorMemoryOverview.visible = true
  }

  component UsageHistoryGraph: Canvas {
    property var values: []
    property color graphColor: Theme.primary

    onValuesChanged: requestPaint()
    onGraphColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      const context = getContext("2d")
      context.reset()
      context.clearRect(0, 0, width, height)
      if (!values || values.length < 2)
        return

      for (let row = 1; row <= 3; row++) {
        const y = height * row / 4
        context.strokeStyle = Theme.withAlpha(Theme.outline, 0.2)
        context.lineWidth = 1
        context.beginPath()
        context.moveTo(0, y)
        context.lineTo(width, y)
        context.stroke()
      }

      const gradient = context.createLinearGradient(0, 0, 0, height)
      gradient.addColorStop(0, Theme.withAlpha(graphColor, 0.28))
      gradient.addColorStop(1, Theme.withAlpha(graphColor, 0.015))
      context.beginPath()
      context.moveTo(0, height)
      for (let index = 0; index < values.length; index++) {
        const x = width * index / (values.length - 1)
        const value = Math.max(0, Math.min(100, Number(values[index]) || 0))
        const y = height - value / 100 * height * 0.88
        context.lineTo(x, y)
      }
      context.lineTo(width, height)
      context.closePath()
      context.fillStyle = gradient
      context.fill()

      context.beginPath()
      for (let index = 0; index < values.length; index++) {
        const x = width * index / (values.length - 1)
        const value = Math.max(0, Math.min(100, Number(values[index]) || 0))
        const y = height - value / 100 * height * 0.88
        index === 0 ? context.moveTo(x, y) : context.lineTo(x, y)
      }
      context.strokeStyle = Theme.withAlpha(graphColor, 0.95)
      context.lineWidth = 2
      context.lineJoin = "round"
      context.lineCap = "round"
      context.stroke()
    }
  }

  component GpuOverviewPage: Item {
    id: gpuOverviewPage

    function memoryText(megabytes) {
      if (megabytes < 0)
        return qsTr("Unavailable")
      return megabytes >= 1024
        ? (megabytes / 1024).toFixed(1) + " GiB"
        : megabytes.toFixed(0) + " MiB"
    }

    Column {
      anchors.fill: parent
      spacing: 10

      Row {
        width: parent.width
        height: 24
        spacing: 8

        DmsIcon {
          anchors.verticalCenter: parent.verticalCenter
          name: "videogame_asset"
          size: 18
          color: Theme.primary
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: qsTr("%1 graphics devices").arg(SystemStatsService.gpus.length)
          color: Theme.widgetTextColor
          font.pixelSize: 13
          font.weight: Font.Medium
        }

        Text {
          width: parent.width - 180
          anchors.verticalCenter: parent.verticalCenter
          text: qsTr("Metrics depend on driver support")
          color: Theme.widgetInactiveIconColor
          font.pixelSize: 10
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideRight
        }
      }

      Flickable {
        width: parent.width
        height: parent.height - 34
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: gpuCards.implicitHeight
        visible: SystemStatsService.gpus.length > 0
        ScrollBar.vertical: ScrollBar { }

        Column {
          id: gpuCards
          width: parent.width
          spacing: 10

          Repeater {
            model: SystemStatsService.gpus

            delegate: Rectangle {
              required property var modelData
              width: gpuCards.width
              implicitHeight: 210
              height: 210
              radius: Theme.cornerRadius
              color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)

              Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 7

                Row {
                  width: parent.width
                  spacing: 8

                  DmsIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "videogame_asset"
                    size: 20
                    color: modelData.utilization >= 90 ? Theme.warning : Theme.primary
                  }

                  Column {
                    width: parent.width - 68
                    spacing: 1

                    Text {
                      width: parent.width
                      text: modelData.name
                      color: Theme.widgetTextColor
                      font.pixelSize: 12
                      font.weight: Font.DemiBold
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: qsTr("%1 · %2 · %3").arg(modelData.vendor).arg(modelData.driver).arg(modelData.pciAddress)
                      color: Theme.widgetInactiveIconColor
                      font.pixelSize: 9
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.utilization >= 0
                      ? modelData.utilization.toFixed(1) + "%"
                      : "—"
                    color: modelData.utilization >= 90 ? Theme.warning : Theme.widgetTextColor
                    font.family: Theme.monoFontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                  }
                }

                Rectangle {
                  width: parent.width
                  height: 5
                  radius: 3
                  color: Theme.withAlpha(Theme.outline, 0.25)

                  Rectangle {
                    width: modelData.utilization >= 0
                      ? Math.max(modelData.utilization > 0 ? 1 : 0,
                        parent.width * Math.max(0, Math.min(100, modelData.utilization)) / 100) : 0
                    height: parent.height
                    radius: parent.radius
                    color: modelData.utilization >= 90 ? Theme.warning : Theme.primary
                  }
                }

                Row {
                  width: parent.width
                  spacing: 6

                  Text {
                    text: qsTr("VRAM")
                    color: Theme.widgetTextColor
                    font.pixelSize: 10
                    font.weight: Font.Medium
                  }

                  Text {
                    width: parent.width - 120
                    text: modelData.memoryPercent >= 0
                      ? gpuOverviewPage.memoryText(modelData.memoryUsage)
                        + " / " + gpuOverviewPage.memoryText(modelData.memoryTotal)
                      : qsTr("Unavailable")
                    color: Theme.widgetTextColor
                    font.family: Theme.monoFontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                  }

                  Text {
                    width: 48
                    text: modelData.memoryPercent >= 0
                      ? modelData.memoryPercent.toFixed(0) + "%" : "—"
                    color: Theme.widgetTextColor
                    font.family: Theme.monoFontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignRight
                  }
                }

                Rectangle {
                  width: parent.width
                  height: 5
                  radius: 3
                  color: Theme.withAlpha(Theme.outline, 0.25)

                  Rectangle {
                    width: modelData.memoryPercent >= 0
                      ? parent.width * Math.max(0, Math.min(100, modelData.memoryPercent)) / 100 : 0
                    height: parent.height
                    radius: parent.radius
                    color: Theme.secondary
                  }
                }

                Row {
                  width: parent.width
                  spacing: 6

                  Text {
                    text: qsTr("Memory controller")
                    color: Theme.widgetInactiveIconColor
                    font.pixelSize: 9
                  }

                  Text {
                    text: modelData.memoryControllerUtilization >= 0
                      ? modelData.memoryControllerUtilization.toFixed(1) + "%"
                      : qsTr("Unavailable")
                    color: Theme.widgetTextColor
                    font.family: Theme.monoFontFamily
                    font.pixelSize: 9
                  }
                }

                Rectangle {
                  width: parent.width
                  height: 4
                  radius: 2
                  color: Theme.withAlpha(Theme.outline, 0.25)

                  Rectangle {
                    width: modelData.memoryControllerUtilization >= 0
                      ? parent.width * Math.max(0, Math.min(100, modelData.memoryControllerUtilization)) / 100 : 0
                    height: parent.height
                    radius: parent.radius
                    color: Theme.secondary
                  }
                }

                Text {
                  width: parent.width
                  text: (modelData.temperature >= 0
                    ? qsTr("%1°C").arg(Math.round(modelData.temperature)) : qsTr("Temperature unavailable"))
                    + (modelData.power >= 0
                      ? " · " + modelData.power.toFixed(1) + " W" : "")
                    + (modelData.utilizationSource
                      ? " · " + modelData.utilizationSource : "")
                  color: Theme.widgetInactiveIconColor
                  font.pixelSize: 9
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: modelData.uuid
                    ? qsTr("UUID %1").arg(modelData.uuid)
                    : qsTr("PCI device %1").arg(modelData.pciAddress)
                  color: Theme.widgetInactiveIconColor
                  font.family: Theme.monoFontFamily
                  font.pixelSize: 8
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        height: parent.height - 34
        visible: SystemStatsService.gpus.length === 0

        Text {
          anchors.centerIn: parent
          text: SystemStatsService.gpuStatsError.length > 0
            ? SystemStatsService.gpuStatsError
            : qsTr("No graphics devices detected")
          color: Theme.widgetInactiveIconColor
          font.pixelSize: 12
        }
      }
    }
  }

  component ActiveGpuSummary: Item {
    id: activeGpuSummary

    readonly property var activeGpus: SystemStatsService.gpus.slice()
      .sort((first, second) => {
        const firstUsage = Number.isFinite(first.utilization) ? first.utilization : -1
        const secondUsage = Number.isFinite(second.utilization) ? second.utilization : -1
        return secondUsage - firstUsage
      })

    implicitHeight: SystemStatsService.gpus.length > 0 ? 40 : 0
    visible: SystemStatsService.gpus.length > 0

    Row {
      anchors.fill: parent
      spacing: 8

      DmsIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: "videogame_asset"
        size: 16
        color: Theme.primary
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: qsTr("GPU activity")
        color: Theme.widgetInactiveIconColor
        font.pixelSize: 10
      }

      Repeater {
        model: activeGpuSummary.activeGpus

        delegate: Rectangle {
          required property var modelData
          width: Math.max(90, (parent.width - 120) / Math.max(1, activeGpuSummary.activeGpus.length))
          height: 30
          anchors.verticalCenter: parent.verticalCenter
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.64)

          Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Text {
              width: parent.width - 42
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              color: Theme.widgetTextColor
              font.pixelSize: 9
              elide: Text.ElideRight
            }

            Text {
              width: 36
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.utilization >= 0
                ? modelData.utilization.toFixed(1) + "%"
                : "—"
              color: Theme.widgetTextColor
              font.family: Theme.monoFontFamily
              font.pixelSize: 9
              horizontalAlignment: Text.AlignRight
            }
          }
        }
      }
    }
  }

  component ProcessOverviewPage: Item {
    id: processPage

    property string searchText: ""
    property string processScope: "all"
    property string gpuFilter: "all"
    property bool showGpuFilterMenu: false
    property real minimumCpuPercent: 0
    property real minimumMemoryPercent: 0
    property string sortField: "cpu"
    property bool sortDescending: true
    property var contextProcess: null
    property real contextMenuX: 0
    property real contextMenuY: 0
    property bool showAllSignals: false
    property var confirmationProcess: null
    property string confirmationSignal: ""

    readonly property var cpuThresholds: [0, 1, 5, 10, 25, 50, 100]
    readonly property var memoryThresholds: [0, 1, 5, 10, 25, 50]

    function gpuFilterOptions() {
      return [{ id: "all", label: qsTr("All GPUs") }].concat(
        SystemStatsService.gpus.map(gpu => ({ id: gpu.pciAddress, label: gpu.name }))
      )
    }

    function gpuFilterLabel() {
      if (gpuFilter === "all")
        return qsTr("GPU: All")
      const gpu = SystemStatsService.gpus.find(item => item.pciAddress === gpuFilter)
      return gpu ? gpu.name : qsTr("GPU")
    }

    function fuzzyScore(needle, candidate) {
      const term = needle.toLowerCase()
      const text = candidate.toLowerCase()
      if (!term || !text)
        return term ? -1 : 0

      const exactIndex = text.indexOf(term)
      if (exactIndex >= 0)
        return 1000 - exactIndex * 4 - (text.length - term.length) * 0.1
      if (term.length === 1)
        return -1

      let cursor = 0
      let firstIndex = -1
      let previousIndex = -1
      let gaps = 0
      for (let index = 0; index < term.length; index++) {
        const found = text.indexOf(term[index], cursor)
        if (found < 0)
          return -1
        if (firstIndex < 0)
          firstIndex = found
        if (previousIndex >= 0)
          gaps += found - previousIndex - 1
        previousIndex = found
        cursor = found + 1
      }

      if (gaps > Math.max(2, term.length))
        return -1
      const wordStartBonus = firstIndex === 0 || /[\s/_.-]/.test(text[firstIndex - 1]) ? 30 : 0
      return 500 - firstIndex * 4 - gaps * 20 - (text.length - term.length) * 0.1 + wordStartBonus
    }

    function processSearchScore(process, query) {
      if (!query)
        return 0
      const candidates = [
        process.name.toLowerCase(),
        process.command.toLowerCase(),
        String(process.pid)
      ]
      let totalScore = 0
      for (const token of query.split(/\s+/).filter(Boolean)) {
        let bestScore = -1
        for (const candidate of candidates)
          bestScore = Math.max(bestScore, fuzzyScore(token, candidate))
        if (bestScore < 0)
          return -1
        totalScore += bestScore
      }
      return totalScore
    }

    function filteredProcesses() {
      const query = searchText.trim().toLowerCase()
      const rows = SystemStatsService.processes.map(process => ({
        process: process,
        relevance: processSearchScore(process, query)
      })).filter(result => {
        const process = result.process
        if (processScope === "user" && !process.isUser)
          return false
        if (processScope === "system" && process.isUser)
          return false
        if (minimumCpuPercent > 0 && process.cpu < minimumCpuPercent)
          return false
        if (minimumMemoryPercent > 0 && process.memoryPercent < minimumMemoryPercent)
          return false
        if (gpuFilter !== "all"
            && !(process.gpuPciAddresses || []).includes(gpuFilter))
          return false
        return result.relevance >= 0
      })
      rows.sort((a, b) => {
        if (query && a.relevance !== b.relevance)
          return b.relevance - a.relevance
        const first = a.process
        const second = b.process
        let comparison = 0
        if (sortField === "name")
          comparison = first.name.toLowerCase().localeCompare(second.name.toLowerCase())
        else
          comparison = Number(first[sortField]) - Number(second[sortField])
        return comparison === 0 ? first.pid - second.pid : comparison * (sortDescending ? -1 : 1)
      })
      return rows.map(result => result.process)
    }

    function cycleThreshold(kind) {
      if (kind === "cpu") {
        const currentIndex = cpuThresholds.indexOf(minimumCpuPercent)
        minimumCpuPercent = cpuThresholds[(currentIndex + 1) % cpuThresholds.length]
      } else if (kind === "memory") {
        const currentIndex = memoryThresholds.indexOf(minimumMemoryPercent)
        minimumMemoryPercent = memoryThresholds[(currentIndex + 1) % memoryThresholds.length]
      }
    }

    function sortBy(field) {
      if (sortField === field)
        sortDescending = !sortDescending
      else {
        sortField = field
        sortDescending = field !== "name"
      }
    }

    function openContextMenu(process, x, y) {
      contextProcess = process
      contextMenuX = x
      contextMenuY = y
      showAllSignals = false
    }

    function requestSignal(process, signal) {
      contextProcess = null
      if (signal !== "STOP" && signal !== "CONT") {
        confirmationProcess = process
        confirmationSignal = signal
        return
      }
      SystemStatsService.signalProcess(process.pid, signal)
    }

    function confirmSignal() {
      const process = confirmationProcess
      const signal = confirmationSignal
      confirmationProcess = null
      confirmationSignal = ""
      if (process)
        SystemStatsService.signalProcess(process.pid, signal)
    }

    function processMemoryText(memoryKB) {
      return memoryKB >= 1024 * 1024
        ? (memoryKB / (1024 * 1024)).toFixed(1) + " GiB"
        : (memoryKB / 1024).toFixed(0) + " MiB"
    }

    function menuSignals() {
      if (showAllSignals)
        return ["HUP", "INT", "QUIT", "KILL", "TERM", "STOP", "CONT", "TSTP",
          "TTIN", "TTOU", "USR1", "USR2", "ALRM", "ABRT", "PIPE", "CHLD",
          "WINCH", "URG", "XCPU", "XFSZ", "VTALRM", "PROF", "IO", "SYS",
          "TRAP", "FPE", "ILL", "BUS", "SEGV", "STKFLT", "PWR"]
      const signals = []
      if (contextProcess && !contextProcess.isPaused)
        signals.push("STOP")
      if (contextProcess && contextProcess.isPaused)
        signals.push("CONT")
      signals.push("TERM", "KILL", "HUP", "INT", "QUIT", "USR1", "USR2", "MORE")
      return signals
    }

    Connections {
      target: SystemStatsService

      function onGpusChanged() {
        if (processPage.gpuFilter !== "all"
            && !SystemStatsService.gpus.some(gpu => gpu.pciAddress === processPage.gpuFilter))
          processPage.gpuFilter = "all"
      }
    }

    Column {
      anchors.fill: parent
      spacing: 8

      Row {
        width: parent.width
        height: 62
        spacing: 8

        Repeater {
          model: [
            {
              "title": qsTr("PROCESSOR"),
              "value": SystemStatsService.cpuUsage.toFixed(1) + "%",
              "usage": SystemStatsService.cpuUsage,
              "color": SystemStatsService.cpuUsage >= 80 ? Theme.error : Theme.primary,
              "detail": qsTr("%1 logical processors").arg(SystemStatsService.cpuCoreCount)
            },
            {
              "title": qsTr("MEMORY"),
              "value": SystemStatsService.memoryUsage.toFixed(1) + "%",
              "usage": SystemStatsService.memoryUsage,
              "color": Theme.secondary,
              "detail": SystemStatsService.memUsedText + " / " + SystemStatsService.memTotalText
            }
          ]

          delegate: Rectangle {
            required property var modelData
            width: (parent.width - parent.spacing) / 2
            height: parent.height
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)

            Column {
              anchors.fill: parent
              anchors.margins: 10
              spacing: 4

              Row {
                width: parent.width
                spacing: 8

                Text {
                  text: modelData.title
                  color: Theme.widgetInactiveIconColor
                  font.pixelSize: 9
                  font.weight: Font.DemiBold
                }

                Text {
                  text: modelData.value
                  color: Theme.widgetTextColor
                  font.family: Theme.monoFontFamily
                  font.pixelSize: 12
                  font.weight: Font.DemiBold
                }

                Text {
                  width: parent.width - 105
                  text: modelData.detail
                  color: Theme.widgetInactiveIconColor
                  font.pixelSize: 9
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignRight
                }
              }

              Rectangle {
                width: parent.width
                height: 5
                radius: 3
                color: Theme.withAlpha(Theme.outline, 0.25)

                Rectangle {
                  width: parent.width * Math.max(0, Math.min(100, modelData.usage)) / 100
                  height: parent.height
                  radius: parent.radius
                  color: modelData.color
                }
              }
            }
          }
        }
      }

      ActiveGpuSummary {
        width: parent.width
      }

      Row {
        width: parent.width
        height: 36
        spacing: 5

        Rectangle {
          width: parent.width - 184
          height: parent.height
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
          border.width: processSearchInput.activeFocus ? 1 : 0
          border.color: Theme.withAlpha(Theme.primary, 0.55)

          DmsIcon {
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            size: 17
            color: Theme.widgetInactiveIconColor
          }

          TextInput {
            id: processSearchInput
            anchors.fill: parent
            anchors.leftMargin: 34
            anchors.rightMargin: 8
            color: Theme.widgetTextColor
            font.pixelSize: 12
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            clip: true
            onTextChanged: processPage.searchText = text
          }

          Text {
            anchors.fill: processSearchInput
            visible: processSearchInput.text.length === 0
            text: qsTr("Search processes")
            color: Theme.widgetInactiveIconColor
            font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            z: 1
          }

        }

        Repeater {
          model: [
            { "id": "all", "label": qsTr("All"), "width": 42 },
            { "id": "user", "label": qsTr("User"), "width": 52 },
            { "id": "system", "label": qsTr("System"), "width": 64 }
          ]

          delegate: Rectangle {
            required property var modelData
            width: modelData.width
            height: parent.height
            radius: Theme.hoverRadius
            color: processPage.processScope === modelData.id || scopeMouse.containsMouse
              ? Theme.withAlpha(Theme.primary, processPage.processScope === modelData.id ? 0.18 : 0.1)
              : Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
            border.width: processPage.processScope === modelData.id || scopeMouse.containsMouse ? 1 : 0
            border.color: Theme.withAlpha(Theme.primary, 0.45)

            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: processPage.processScope === modelData.id ? Theme.primary : Theme.widgetTextColor
              font.pixelSize: 10
              font.weight: processPage.processScope === modelData.id ? Font.DemiBold : Font.Normal
            }

            MouseArea {
              id: scopeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: processPage.processScope = modelData.id
            }
          }
        }
      }

      Row {
        width: parent.width
        height: 30
        spacing: 6

        Repeater {
          model: [
            { "type": "cpu", "label": qsTr("CPU ≥ %1%").arg(processPage.minimumCpuPercent), "active": processPage.minimumCpuPercent > 0 },
            { "type": "memory", "label": qsTr("MEM ≥ %1%").arg(processPage.minimumMemoryPercent), "active": processPage.minimumMemoryPercent > 0 }
          ]

          delegate: Rectangle {
            required property var modelData
            width: 92
            height: parent.height
            radius: Theme.hoverRadius
            color: modelData.active || usageFilterMouse.containsMouse
              ? Theme.withAlpha(Theme.primary, modelData.active ? 0.18 : 0.1)
              : Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
            border.width: modelData.active || usageFilterMouse.containsMouse ? 1 : 0
            border.color: Theme.withAlpha(Theme.primary, 0.45)

            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: modelData.active ? Theme.primary : Theme.widgetTextColor
              font.pixelSize: 10
              font.weight: modelData.active ? Font.DemiBold : Font.Normal
            }

            MouseArea {
              id: usageFilterMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: processPage.cycleThreshold(modelData.type)
            }

            ToolTip.visible: usageFilterMouse.containsMouse
            ToolTip.text: modelData.type === "cpu"
              ? qsTr("Click to cycle the minimum process CPU usage")
              : qsTr("Click to cycle the minimum process memory usage")
          }
        }

        Rectangle {
          id: gpuFilterButton
          width: 126
          height: parent.height
          radius: Theme.hoverRadius
          color: processPage.gpuFilter !== "all" || gpuFilterMouse.containsMouse
            ? Theme.withAlpha(Theme.primary, processPage.gpuFilter !== "all" ? 0.18 : 0.1)
            : Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
          border.width: processPage.gpuFilter !== "all" || gpuFilterMouse.containsMouse ? 1 : 0
          border.color: Theme.withAlpha(Theme.primary, 0.45)

          Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 4

            DmsIcon {
              anchors.verticalCenter: parent.verticalCenter
              name: "videogame_asset"
              size: 14
              color: processPage.gpuFilter !== "all" ? Theme.primary : Theme.widgetInactiveIconColor
            }

            Text {
              width: parent.width - 30
              anchors.verticalCenter: parent.verticalCenter
              text: processPage.gpuFilterLabel()
              color: processPage.gpuFilter !== "all" ? Theme.primary : Theme.widgetTextColor
              font.pixelSize: 10
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: gpuFilterMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: processPage.showGpuFilterMenu = !processPage.showGpuFilterMenu
          }
        }

        Text {
          width: parent.width - 92 * 2 - gpuFilterButton.width - parent.spacing * 3
          anchors.verticalCenter: parent.verticalCenter
          text: qsTr("%1 processes").arg(processPage.filteredProcesses().length)
          color: Theme.widgetInactiveIconColor
          font.pixelSize: 10
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideLeft
        }
      }

      Rectangle {
        width: parent.width
        height: SystemStatsService.processActionError ? 30 : 0
        visible: SystemStatsService.processActionError.length > 0
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.error, 0.14)

        Text {
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          verticalAlignment: Text.AlignVCenter
          text: SystemStatsService.processActionError
          color: Theme.error
          font.pixelSize: 10
          elide: Text.ElideRight
        }
      }

      Row {
        id: processTableHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 8
        anchors.rightMargin: 6
        height: 24
        spacing: 6

        Repeater {
          model: [
            { "field": "name", "label": qsTr("NAME"), "width": processTableHeader.width - 320 },
            { "field": "cpu", "label": qsTr("CPU"), "width": 42 },
            { "field": "memoryKB", "label": qsTr("MEMORY"), "width": 46 },
            { "field": "gpuUsage", "label": qsTr("GPU"), "width": 38 },
            { "field": "gpuMemoryMB", "label": qsTr("VRAM"), "width": 46 },
            { "field": "pid", "label": qsTr("PID"), "width": 38 },
            { "field": "", "label": qsTr("ACTIONS"), "width": 66 }
          ]

          delegate: Item {
            required property var modelData
            width: modelData.width
            height: parent.height

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              text: modelData.field && processPage.sortField === modelData.field
                ? modelData.label + (processPage.sortDescending ? " ↓" : " ↑")
                : modelData.label
              color: Theme.widgetInactiveIconColor
              font.pixelSize: 9
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              enabled: modelData.field.length > 0
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: processPage.sortBy(modelData.field)
            }
          }
        }
      }

      ListView {
        id: processListView
        width: parent.width
        height: parent.height - 62 - 40 - 36 - processTableHeader.height
          - 30 - parent.spacing * 6
          - (SystemStatsService.processActionError.length > 0 ? 30 : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: 4
        model: processPage.filteredProcesses()
        ScrollBar.vertical: ScrollBar { }

        delegate: Rectangle {
          required property var modelData
          property var processInfo: modelData
          width: processListView.width
          height: 48
          radius: Theme.cornerRadius
          color: processRowMouse.containsMouse
            ? Theme.withAlpha(Theme.surfaceContainerHigh, 0.88)
            : Theme.withAlpha(Theme.surfaceContainerHigh, 0.48)

          Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 5

            Column {
              width: processTableHeader.width - 320
              y: (parent.height - height) / 2
              spacing: 2

              Text {
                width: parent.width
                text: modelData.name
                color: Theme.widgetTextColor
                font.pixelSize: 11
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: modelData.fullCommand
                color: Theme.widgetInactiveIconColor
                font.pixelSize: 9
                elide: Text.ElideRight
              }
            }

            Text {
              width: 42
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              text: modelData.cpu.toFixed(1) + "%"
              color: modelData.cpu >= 80 ? Theme.warning : Theme.widgetTextColor
              font.family: Theme.monoFontFamily
              font.pixelSize: 10
              elide: Text.ElideRight
            }

            Column {
              width: 46
              y: (parent.height - height) / 2
              spacing: 1

              Text {
                text: processPage.processMemoryText(modelData.memoryKB)
                color: Theme.widgetTextColor
                font.family: Theme.monoFontFamily
                font.pixelSize: 9
              }

              Text {
                text: modelData.memoryPercent.toFixed(1) + "%"
                color: Theme.widgetInactiveIconColor
                font.family: Theme.monoFontFamily
                font.pixelSize: 8
              }
            }

            Text {
              id: processGpuUsage
              width: 38
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              text: modelData.gpuUsage === null ? "—" : modelData.gpuUsage.toFixed(0) + "%"
              color: modelData.gpuUsage >= 80 ? Theme.warning : Theme.widgetTextColor
              font.family: Theme.monoFontFamily
              font.pixelSize: 9
              elide: Text.ElideRight

              ToolTip.visible: processGpuMouse.containsMouse && modelData.gpuDetails.length > 0
              ToolTip.text: modelData.gpuDetails

              MouseArea {
                id: processGpuMouse
                anchors.fill: parent
                hoverEnabled: true
              }
            }

            Text {
              width: 46
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              text: modelData.gpuMemoryMB === null
                ? "—" : processPage.processMemoryText(modelData.gpuMemoryMB * 1024)
              color: Theme.widgetTextColor
              font.family: Theme.monoFontFamily
              font.pixelSize: 9
              elide: Text.ElideRight
            }

            Text {
              width: 38
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              text: modelData.pid
              color: Theme.widgetInactiveIconColor
              font.family: Theme.monoFontFamily
              font.pixelSize: 9
            }

            Row {
              width: 66
              height: parent.height
              spacing: 1

              Repeater {
                model: [
                  { "icon": processInfo.isPaused ? "play_arrow" : "pause", "signal": processInfo.isPaused ? "CONT" : "STOP" },
                  { "icon": "close", "signal": "TERM" },
                  { "icon": "more_vert", "signal": "MENU" }
                ]

                delegate: Rectangle {
                  required property var modelData
                  width: 21
                  height: 30
                  y: (parent.height - height) / 2
                  radius: 7
                  color: processActionMouse.containsMouse
                    ? Theme.withAlpha(modelData.signal === "TERM" ? Theme.error : Theme.primary, 0.16)
                    : "transparent"

                  DmsIcon {
                    anchors.centerIn: parent
                    name: modelData.icon
                    size: 15
                    color: processActionMouse.containsMouse
                      ? (modelData.signal === "TERM" ? Theme.error : Theme.primary)
                      : Theme.widgetInactiveIconColor
                  }

                  MouseArea {
                    id: processActionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (modelData.signal === "MENU") {
                        const position = parent.mapToItem(processPage, parent.width / 2, parent.height / 2)
                        processPage.openContextMenu(processInfo, position.x, position.y)
                      } else {
                        processPage.requestSignal(processInfo, modelData.signal)
                      }
                    }
                  }
                }
              }
            }
          }

          MouseArea {
            id: processRowMouse
            anchors.fill: parent
            z: 1
            hoverEnabled: true
            acceptedButtons: Qt.RightButton
            onClicked: function(mouse) {
              const position = mapToItem(processPage, mouse.x, mouse.y)
              processPage.openContextMenu(modelData, position.x, position.y)
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: processListView.count === 0
          text: SystemStatsService.processListError.length > 0
            ? SystemStatsService.processListError
            : SystemStatsService.processes.length === 0
            ? qsTr("Waiting for process data…")
            : qsTr("No matching processes")
          color: Theme.widgetInactiveIconColor
          font.pixelSize: 12
        }
      }
    }

    Rectangle {
      id: gpuFilterMenu
      visible: processPage.showGpuFilterMenu
      x: Math.max(8, Math.min(processPage.width - width - 8,
        gpuFilterButton.mapToItem(processPage, 0, 0).x))
      y: gpuFilterButton.mapToItem(processPage, 0, gpuFilterButton.height + 4).y
      width: 220
      height: Math.min(gpuFilterList.contentHeight + 12, 220)
      z: 8
      radius: Theme.cornerRadius
      color: Theme.surfaceContainerHigh
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.45)

      ListView {
        id: gpuFilterList
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: processPage.gpuFilterOptions()
        ScrollBar.vertical: ScrollBar { }

        delegate: Rectangle {
          required property var modelData
          width: gpuFilterList.width
          height: 32
          radius: Theme.hoverRadius
          color: processPage.gpuFilter === modelData.id || gpuFilterOptionMouse.containsMouse
            ? Theme.withAlpha(Theme.primary, processPage.gpuFilter === modelData.id ? 0.16 : 0.1)
            : "transparent"

          Text {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: Text.AlignVCenter
            text: modelData.label
            color: processPage.gpuFilter === modelData.id ? Theme.primary : Theme.widgetTextColor
            font.pixelSize: 10
            elide: Text.ElideRight
          }

          MouseArea {
            id: gpuFilterOptionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              processPage.gpuFilter = modelData.id
              processPage.showGpuFilterMenu = false
            }
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      visible: processPage.contextProcess !== null
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      z: 4
      onClicked: processPage.contextProcess = null
    }

    Rectangle {
      id: processContextMenu
      visible: processPage.contextProcess !== null && processPage.confirmationProcess === null
      width: 190
      height: Math.min((processPage.showAllSignals ? 32 : 9) * 30 + 12, processPage.height - 16)
      x: Math.max(8, Math.min(processPage.width - width - 8, processPage.contextMenuX))
      y: Math.max(8, Math.min(processPage.height - height - 8, processPage.contextMenuY))
      z: 5
      radius: Theme.cornerRadius
      color: Theme.surfaceContainerHigh
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.45)

      Flickable {
        id: processSignalsFlickable
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        contentHeight: processSignalsColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: processSignalsColumn
          width: processSignalsFlickable.width

          Repeater {
            model: processPage.menuSignals()

            delegate: Rectangle {
              required property string modelData
              width: processSignalsColumn.width
              height: 30
              radius: Theme.hoverRadius
              color: signalMenuMouse.containsMouse
                ? Theme.withAlpha(modelData === "KILL" || modelData === "TERM" ? Theme.error : Theme.primary, 0.14)
                : "transparent"

              Text {
                anchors.fill: parent
                anchors.leftMargin: 8
                verticalAlignment: Text.AlignVCenter
                text: modelData === "MORE" ? qsTr("All signals…")
                  : (modelData === "STOP" ? qsTr("Pause (SIGSTOP)")
                  : modelData === "CONT" ? qsTr("Continue (SIGCONT)")
                  : qsTr("Send SIG%1").arg(modelData))
                color: modelData === "KILL" || modelData === "TERM" ? Theme.error : Theme.widgetTextColor
                font.pixelSize: 11
              }

              MouseArea {
                id: signalMenuMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData === "MORE") {
                    processPage.showAllSignals = true
                  } else {
                    const target = processPage.contextProcess
                    processPage.contextProcess = null
                    processPage.requestSignal(target, modelData)
                  }
                }
              }
            }
          }

          Rectangle {
            width: processSignalsColumn.width
            height: 28
            visible: processPage.showAllSignals
            color: "transparent"

            Text {
              anchors.fill: parent
              anchors.leftMargin: 8
              verticalAlignment: Text.AlignVCenter
              text: qsTr("‹ Back to actions")
              color: Theme.primary
              font.pixelSize: 11
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: processPage.showAllSignals = false
            }
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: processPage.contextProcess = null
      }
    }

    Rectangle {
      visible: processPage.confirmationProcess !== null
      anchors.fill: parent
      z: 10
      color: "#99000000"

      MouseArea {
        anchors.fill: parent
      }

      Rectangle {
        width: Math.min(390, parent.width - 32)
        height: 164
        anchors.centerIn: parent
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.45)

        Column {
          anchors.fill: parent
          anchors.margins: 16
          spacing: 10

          Text {
            text: qsTr("Send SIG%1?").arg(processPage.confirmationSignal)
            color: Theme.widgetTextColor
            font.pixelSize: 15
            font.weight: Font.DemiBold
          }

          Text {
            width: parent.width
            text: processPage.confirmationProcess
              ? qsTr("This signal may stop or terminate %1 (PID %2).")
                .arg(processPage.confirmationProcess.name)
                .arg(processPage.confirmationProcess.pid)
              : ""
            color: Theme.widgetInactiveIconColor
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          Item {
            width: 1
            height: 1
          }

          Row {
            anchors.right: parent.right
            spacing: 8

            Rectangle {
              width: 76
              height: 30
              radius: Theme.cornerRadius
              color: Theme.withAlpha(Theme.surfaceContainer, 0.85)

              Text {
                anchors.centerIn: parent
                text: qsTr("Cancel")
                color: Theme.widgetTextColor
                font.pixelSize: 11
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  processPage.confirmationProcess = null
                  processPage.confirmationSignal = ""
                }
              }
            }

            Rectangle {
              width: 94
              height: 30
              radius: Theme.cornerRadius
              color: Theme.withAlpha(Theme.error, 0.2)

              Text {
                anchors.centerIn: parent
                text: qsTr("Send signal")
                color: Theme.error
                font.pixelSize: 11
                font.weight: Font.DemiBold
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: processPage.confirmSignal()
              }
            }
          }
        }
      }
    }
  }

  PopupWindow {
    id: processorMemoryOverview

    anchor.window: root.barWindow
    anchor.rect.x: Math.max(8, Math.min(
      (root.parentScreen ? root.parentScreen.width : Screen.width) - implicitWidth - 8,
      root.overviewAnchorX - implicitWidth / 2
    ))
    anchor.rect.y: root.barWindow ? root.barWindow.height + Theme.spaceXS : 0
    visible: false
    grabFocus: true
    color: "transparent"
    surfaceFormat.opaque: false
    implicitWidth: Math.max(360, Math.min(820, root.parentScreen ? root.parentScreen.width - 16 : 820))
    implicitHeight: Math.max(420, Math.min(720, root.parentScreen ? root.parentScreen.height - 64 : 720))
    property bool overviewRefHeld: false

    function syncOverviewReference() {
      if (visible && !overviewRefHeld) {
        overviewRefHeld = true
        SystemStatsService.addOverviewRef()
      } else if (!visible && overviewRefHeld) {
        overviewRefHeld = false
        SystemStatsService.removeOverviewRef()
      }
    }

    onVisibleChanged: syncOverviewReference()
    Component.onDestruction: {
      if (overviewRefHeld) {
        overviewRefHeld = false
        SystemStatsService.removeOverviewRef()
      }
    }

    Rectangle {
      anchors.fill: parent
      focus: true
      radius: Theme.cornerRadius
      color: Theme.withAlpha(Theme.widgetBaseBackgroundColor,
        typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.65)
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.35)

      Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Row {
          width: parent.width
          height: 38
          spacing: 10

          DmsIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "monitoring"
            size: 24
            color: Theme.primary
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 78
            spacing: 1

            Text {
              width: parent.width
              text: qsTr("System Monitor")
              color: Theme.widgetTextColor
              font.pixelSize: 16
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: SystemStatsService.cpuModel || qsTr("Processor and memory")
              color: Theme.widgetInactiveIconColor
              font.pixelSize: 11
              elide: Text.ElideRight
            }
          }

          Rectangle {
            width: 30
            height: 30
            radius: 15
            anchors.verticalCenter: parent.verticalCenter
            color: closeMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.16) : "transparent"

            DmsIcon {
              anchors.centerIn: parent
              name: "close"
              size: 18
              color: closeMouse.containsMouse ? Theme.error : Theme.widgetInactiveIconColor
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: processorMemoryOverview.visible = false
            }
          }
        }

        Row {
          width: parent.width
          height: 38
          spacing: 8

          Repeater {
            model: [
              { "id": "processor", "text": qsTr("Processor"), "icon": "memory" },
              { "id": "memory", "text": qsTr("Memory"), "icon": "developer_board" },
              { "id": "gpu", "text": qsTr("GPU"), "icon": "videogame_asset" },
              { "id": "processes", "text": qsTr("Processes"), "icon": "view_list" }
            ]

            delegate: Rectangle {
              required property var modelData
              required property int index

              width: (parent.width - parent.spacing * 3) / 4
              height: parent.height
              radius: Theme.cornerRadius
              color: root.overviewTab === modelData.id
                ? Theme.withAlpha(Theme.primary, 0.16)
                : overviewTabMouse.containsMouse
                  ? Theme.withAlpha(Theme.primary, 0.1)
                  : Theme.withAlpha(Theme.surfaceContainerHigh, 0.65)
              border.width: root.overviewTab === modelData.id || overviewTabMouse.containsMouse ? 1 : 0
              border.color: Theme.withAlpha(Theme.primary, 0.4)

              Row {
                anchors.centerIn: parent
                spacing: 4

                DmsIcon {
                  anchors.verticalCenter: parent.verticalCenter
                  name: modelData.icon
                  size: 15
                  color: root.overviewTab === modelData.id || overviewTabMouse.containsMouse
                    ? Theme.primary : Theme.widgetInactiveIconColor
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.text
                  color: root.overviewTab === modelData.id || overviewTabMouse.containsMouse
                    ? Theme.primary : Theme.widgetTextColor
                  font.pixelSize: 11
                  font.weight: root.overviewTab === modelData.id ? Font.DemiBold : Font.Normal
                }
              }

              MouseArea {
                id: overviewTabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.overviewTab = modelData.id
              }
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - 38 - 38 - parent.spacing * 2
          visible: root.overviewTab === "processor"

          Column {
            anchors.fill: parent
            spacing: 12

            Rectangle {
              width: parent.width
              height: 92
              radius: Theme.cornerRadius
              color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)

              Row {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                Item {
                  width: 64
                  height: 64
                  anchors.verticalCenter: parent.verticalCenter

                  Canvas {
                    anchors.fill: parent
                    property real usage: SystemStatsService.cpuUsage
                    onUsageChanged: requestPaint()
                    onPaint: {
                      const context = getContext("2d")
                      context.reset()
                      context.lineWidth = 5
                      context.lineCap = "round"
                      context.strokeStyle = Theme.withAlpha(Theme.outline, 0.3)
                      context.beginPath()
                      context.arc(width / 2, height / 2, 27, 0, Math.PI * 2)
                      context.stroke()
                      const accent = usage >= 80 ? Theme.error : usage >= 60 ? Theme.warning : Theme.primary
                      context.strokeStyle = accent
                      context.beginPath()
                      context.arc(width / 2, height / 2, 27, -Math.PI / 2,
                        -Math.PI / 2 + Math.PI * 2 * Math.max(0, Math.min(1, usage / 100)))
                      context.stroke()
                    }
                  }

                  DmsIcon {
                    anchors.centerIn: parent
                    name: "memory"
                    size: 24
                    color: SystemStatsService.cpuUsage >= 80 ? Theme.error
                      : (SystemStatsService.cpuUsage >= 60 ? Theme.warning : Theme.primary)
                  }
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 92
                  spacing: 2

                  Text {
                    text: SystemStatsService.cpuUsage.toFixed(1) + "%"
                    color: Theme.widgetTextColor
                    font.family: Theme.monoFontFamily
                    font.pixelSize: 25
                    font.weight: Font.DemiBold
                  }

                  Text {
                    width: parent.width
                    text: qsTr("Processor utilization")
                    color: Theme.widgetInactiveIconColor
                    font.pixelSize: 12
                    elide: Text.ElideRight
                  }
                }
              }
            }

            ActiveGpuSummary {
              width: parent.width
            }

            Rectangle {
              width: parent.width
              height: 164
              radius: Theme.cornerRadius
              color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)

              Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 5

                Item {
                  width: parent.width
                  height: 20

                  Text {
                    anchors.left: parent.left
                    text: qsTr("Processor usage")
                    color: Theme.widgetTextColor
                    font.pixelSize: 12
                    font.weight: Font.Medium
                  }

                  Text {
                    anchors.right: parent.right
                    text: qsTr("Last 60 seconds")
                    color: Theme.widgetInactiveIconColor
                    font.pixelSize: 10
                  }
                }

                UsageHistoryGraph {
                  width: parent.width
                  height: parent.height - 25
                  values: SystemStatsService.cpuHistory
                  graphColor: Theme.primary

                  Text {
                    anchors.centerIn: parent
                    visible: SystemStatsService.cpuHistory.length < 2
                    text: qsTr("Collecting processor samples…")
                    color: Theme.widgetInactiveIconColor
                    font.pixelSize: 11
                  }
                }
              }
            }

            Item {
              id: coreSummary
              width: parent.width
              height: 24

              Text {
                id: coreSummaryTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Logical processors")
                color: Theme.widgetTextColor
                font.pixelSize: 13
                font.weight: Font.Medium
              }

              Text {
                anchors.left: coreSummaryTitle.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("%1 cores").arg(SystemStatsService.cpuCoreCount)
                color: Theme.widgetInactiveIconColor
                font.pixelSize: 11
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: SystemStatsService.cpuTemperature > 0
                  ? qsTr("Temperature %1°C").arg(Math.round(SystemStatsService.cpuTemperature))
                  : qsTr("Temperature unavailable")
                color: SystemStatsService.cpuTemperature >= 85 ? Theme.error
                  : (SystemStatsService.cpuTemperature >= 70 ? Theme.warning : Theme.widgetInactiveIconColor)
                font.pixelSize: 11
              }
            }

            Flickable {
              width: parent.width
              height: Math.max(60, parent.height - 92 - 40 - 164 - 24 - parent.spacing * 4)
              contentHeight: coresGrid.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Grid {
                id: coresGrid
                width: parent.width
                columns: width >= 560 ? 4 : (width >= 380 ? 3 : 2)
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                  model: SystemStatsService.perCoreCpuUsage

                  delegate: Rectangle {
                    required property var modelData
                    width: (coresGrid.width - coresGrid.columnSpacing * (coresGrid.columns - 1)) / coresGrid.columns
                    height: 42
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.64)

                    Column {
                      anchors.fill: parent
                      anchors.margins: 7
                      spacing: 4

                      Item {
                        width: parent.width

                        Text {
                          anchors.left: parent.left
                          text: qsTr("Core %1").arg(modelData.index + 1)
                          color: Theme.widgetInactiveIconColor
                          font.pixelSize: 10
                        }

                        Text {
                          anchors.right: parent.right
                          text: Math.round(modelData.usage) + "%"
                          color: Theme.widgetTextColor
                          font.family: Theme.monoFontFamily
                          font.pixelSize: 10
                        }
                      }

                      Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.withAlpha(Theme.outline, 0.28)

                        Rectangle {
                          width: parent.width * Math.max(0, Math.min(100, modelData.usage)) / 100
                          height: parent.height
                          radius: parent.radius
                          color: modelData.usage >= 80 ? Theme.error
                            : (modelData.usage >= 60 ? Theme.warning : Theme.primary)
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - 38 - 38 - parent.spacing * 2
          visible: root.overviewTab === "memory"

          Column {
            anchors.fill: parent
            spacing: 12

            Rectangle {
              width: parent.width
              height: 92
              radius: Theme.cornerRadius
              color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)

              Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                DmsIcon {
                  anchors.verticalCenter: parent.verticalCenter
                  name: "developer_board"
                  size: 34
                  color: SystemStatsService.memoryUsage >= 90 ? Theme.error
                    : (SystemStatsService.memoryUsage >= 75 ? Theme.warning : Theme.secondary)
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 54
                  spacing: 2

                  Row {
                    width: parent.width
                    spacing: 8

                    Text {
                      text: SystemStatsService.memoryUsage.toFixed(1) + "%"
                      color: Theme.widgetTextColor
                      font.family: Theme.monoFontFamily
                      font.pixelSize: 24
                      font.weight: Font.DemiBold
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: SystemStatsService.memUsedText + " / " + SystemStatsService.memTotalText
                      color: Theme.widgetInactiveIconColor
                      font.family: Theme.monoFontFamily
                      font.pixelSize: 11
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    text: qsTr("Memory in use")
                    color: Theme.widgetInactiveIconColor
                    font.pixelSize: 12
                  }
                }
              }
            }

            ActiveGpuSummary {
              width: parent.width
            }

            Rectangle {
              width: parent.width
              height: 150
              radius: Theme.cornerRadius
              color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)

              Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 5

                Item {
                  width: parent.width
                  height: 20

                  Text {
                    anchors.left: parent.left
                    text: qsTr("Memory usage")
                    color: Theme.widgetTextColor
                    font.pixelSize: 12
                    font.weight: Font.Medium
                  }

                  Text {
                    anchors.right: parent.right
                    text: qsTr("Last 60 seconds")
                    color: Theme.widgetInactiveIconColor
                    font.pixelSize: 10
                  }
                }

                UsageHistoryGraph {
                  width: parent.width
                  height: parent.height - 25
                  values: SystemStatsService.memoryHistory
                  graphColor: Theme.secondary

                  Text {
                    anchors.centerIn: parent
                    visible: SystemStatsService.memoryHistory.length < 2
                    text: qsTr("Collecting memory samples…")
                    color: Theme.widgetInactiveIconColor
                    font.pixelSize: 11
                  }
                }
              }
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: 8
              rowSpacing: 8

              Repeater {
                model: [
                  { "label": qsTr("Available"), "value": SystemStatsService._fmtKB(SystemStatsService.memAvailableKB) },
                  { "label": qsTr("Free"), "value": SystemStatsService._fmtKB(SystemStatsService.memFreeKB) },
                  { "label": qsTr("Cached"), "value": SystemStatsService._fmtKB(SystemStatsService.memCachedKB) },
                  { "label": qsTr("Buffers"), "value": SystemStatsService._fmtKB(SystemStatsService.memBuffersKB) }
                ]

                delegate: Rectangle {
                  required property var modelData
                  width: (parent.width - parent.columnSpacing) / 2
                  height: 54
                  radius: Theme.cornerRadius
                  color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.64)

                  Column {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                      text: modelData.label
                      color: Theme.widgetInactiveIconColor
                      font.pixelSize: 10
                    }

                    Text {
                      text: modelData.value
                      color: Theme.widgetTextColor
                      font.family: Theme.monoFontFamily
                      font.pixelSize: 13
                      font.weight: Font.Medium
                    }
                  }
                }
              }
            }

            Rectangle {
              width: parent.width
              height: 62
              radius: Theme.cornerRadius
              color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.64)

              Item {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                DmsIcon {
                  x: 0
                  anchors.verticalCenter: parent.verticalCenter
                  name: "swap_horiz"
                  size: 20
                  color: Theme.primary
                }

                Column {
                  x: 28
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 76
                  spacing: 2

                  Text {
                    text: qsTr("Swap")
                    color: Theme.widgetTextColor
                    font.pixelSize: 12
                    font.weight: Font.Medium
                  }

                  Text {
                    text: SystemStatsService.swapTotalKB > 0
                      ? SystemStatsService._fmtKB(SystemStatsService.swapUsedKB) + " / " + SystemStatsService._fmtKB(SystemStatsService.swapTotalKB)
                      : qsTr("No swap configured")
                    color: Theme.widgetInactiveIconColor
                    font.family: Theme.monoFontFamily
                    font.pixelSize: 10
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.right: parent.right
                  width: 38
                  text: SystemStatsService.swapTotalKB > 0 ? Math.round(SystemStatsService.swapUsage) + "%" : ""
                  color: Theme.widgetTextColor
                  font.family: Theme.monoFontFamily
                  font.pixelSize: 14
                  font.weight: Font.Medium
                  horizontalAlignment: Text.AlignRight
                }
              }
            }
          }
        }

        GpuOverviewPage {
          width: parent.width
          height: parent.height - 38 - 38 - parent.spacing * 2
          visible: root.overviewTab === "gpu"
        }

        ProcessOverviewPage {
          width: parent.width
          height: parent.height - 38 - 38 - parent.spacing * 2
          visible: root.overviewTab === "processes"
        }
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          processorMemoryOverview.visible = false
          event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
          const tabs = ["processor", "memory", "gpu", "processes"]
          const direction = event.key === Qt.Key_Right ? 1 : -1
          const current = tabs.indexOf(root.overviewTab)
          root.overviewTab = tabs[(current + direction + tabs.length) % tabs.length]
          event.accepted = true
        }
      }
    }
  }

  function usageColor() {
    return SystemStatsService.cpuUsage > 80 ? Theme.error
      : (SystemStatsService.cpuUsage > 60 ? Theme.warning : Theme.widgetIconColor)
  }

  function memoryColor() {
    return SystemStatsService.memoryUsage > 90 ? Theme.error
      : (SystemStatsService.memoryUsage > 75 ? Theme.warning : Theme.widgetIconColor)
  }

  onClicked: {
    if (root.groupedMemory)
      root.openOverview("processes")
    else
      root.showLabel = !root.showLabel
  }
}
