import QtQuick

Item {
  id: root

  property string name
  property real size: 20
  property color color: "white"
  property bool filled: false

  implicitWidth: Math.round(size)
  implicitHeight: Math.round(size)

  Text {
    id: icon
    anchors.fill: parent
    text: root.name
    color: root.color
    font.family: materialSymbolsFont.name || "Material Symbols Rounded"
    font.pixelSize: Math.round(root.size)
    font.weight: root.filled ? 500 : 400
    font.hintingPreference: Font.PreferNoHinting
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
    font.variableAxes: ({
      "FILL": root.filled ? 1 : 0,
      "GRAD": 0,
      "opsz": 24,
      "wght": root.filled ? 500 : 400
    })
  }

  FontLoader {
    id: materialSymbolsFont
    source: "/usr/share/fonts/ttf-material-symbols-variable/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf"
  }
}
