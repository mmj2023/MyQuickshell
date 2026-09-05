import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Modules.Bar

// The top bar. Instantiates one PanelWindow layer surface per screen via
// Variants over Quickshell.screens. The surface background follows
// barTransparency: at 0 (default) it is fully transparent so only the widget
// pills are visible; double-clicking the center of the bar toggles to a solid
// surface background and back (omarchy-style gesture).
Item {
  id: root

  readonly property int barTransparency: typeof SettingsData !== "undefined" ? (SettingsData.barTransparency || 0) : 0

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData
        screen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    property bool isTransparent: root.barTransparency === 0

    anchors {
      top: true
      left: true
      right: true
    }

    implicitHeight: Theme.barHeight + Theme.space2() * 2
    color: barWindow.isTransparent ? "transparent" : Theme.withAlpha(Theme.surfaceContainer, 1)
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Auto
    WlrLayershell.namespace: "mybar"
    WlrLayershell.layer: WlrLayer.Top

    // Center gesture area: double-click toggles bar transparency (omarchy-style).
    // Declared before the body so it sits behind the widgets in z, catching only
    // double-clicks on empty bar space and never stealing clicks from pills.
    MouseArea {
      id: centerGesture
      width: 160
      height: parent.height
      anchors.horizontalCenter: parent.horizontalCenter
      onDoubleClicked: barWindow.isTransparent = !barWindow.isTransparent
    }

    BarBody {
      anchors.fill: parent
      anchors.margins: Theme.space2()
      screen: barWindow.screen
      barWindow: barWindow
    }
  }
}
