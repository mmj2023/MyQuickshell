import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtCore
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null
  readonly property bool expanded: SettingsData.notesExpanded
  readonly property bool searchVisible: SettingsData.notesSearchVisible
  readonly property bool optionsExpanded: SettingsData.notesOptionsExpanded
  readonly property bool markdownPreview: SettingsData.notesMarkdownPreview
  property string chooserInitialPath: ""
  property bool applyingNvimState: false
  property bool nvimCommandMode: false

  function closeNvimCommandMode() {
    NotesService.sendNvimInput("<Esc>")
    root.nvimCommandMode = false
    Qt.callLater(function() { noteEditor.forceActiveFocus() })
  }

  function executeNvimCommand() {
    const command = nvimCommandInput.text.trim()
    root.nvimCommandMode = false
    nvimCommandInput.clear()

    if (!command) {
      noteEditor.forceActiveFocus()
      return
    }

    const normalized = command.toLowerCase()
    if (/^(w|write)(!?)$/.test(normalized)) {
      if (!NotesService.saveAfterNvimSync())
        root.saveNote()
    } else if (/^(q|quit)(!?)$/.test(normalized)) {
      NotesService.closeDocument(NotesService.currentIndex)
    } else if (/^(qa|qall)(!?)$/.test(normalized)) {
      root.setNotesVisible(false)
    } else {
      NotesService.runNvimCommand(command)
    }
    Qt.callLater(function() {
      if (notesPopup.visible)
        noteEditor.forceActiveFocus()
    })
  }

  function keyForNvim(event) {
    const specialKeys = {}
    specialKeys[Qt.Key_Escape] = "Esc"
    specialKeys[Qt.Key_Return] = "CR"
    specialKeys[Qt.Key_Enter] = "CR"
    specialKeys[Qt.Key_Backspace] = "BS"
    specialKeys[Qt.Key_Delete] = "Del"
    specialKeys[Qt.Key_Tab] = "Tab"
    specialKeys[Qt.Key_Backtab] = "S-Tab"
    specialKeys[Qt.Key_Left] = "Left"
    specialKeys[Qt.Key_Right] = "Right"
    specialKeys[Qt.Key_Up] = "Up"
    specialKeys[Qt.Key_Down] = "Down"
    specialKeys[Qt.Key_Home] = "Home"
    specialKeys[Qt.Key_End] = "End"
    specialKeys[Qt.Key_PageUp] = "PageUp"
    specialKeys[Qt.Key_PageDown] = "PageDown"
    specialKeys[Qt.Key_Insert] = "Insert"
    specialKeys[Qt.Key_Space] = "Space"
    if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12)
      specialKeys[event.key] = "F" + (event.key - Qt.Key_F1 + 1)

    const keyName = specialKeys[event.key]
    const modifiers = event.modifiers
    const control = (modifiers & Qt.ControlModifier) !== 0
    const alt = (modifiers & Qt.AltModifier) !== 0
    const shift = (modifiers & Qt.ShiftModifier) !== 0

    if (keyName) {
      if ((keyName === "Tab" || keyName === "S-Tab") && shift && !control && !alt)
        return "<S-Tab>"
      if (keyName === "S-Tab" && !control && !alt)
        return "<S-Tab>"
      const prefixes = []
      if (control) prefixes.push("C")
      if (alt) prefixes.push("A")
      if (shift && keyName.length > 1) prefixes.push("S")
      return "<" + prefixes.concat(keyName).join("-") + ">"
    }

    if (control || alt) {
      let character = ""
      if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
        character = String.fromCharCode(event.key).toLowerCase()
      else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
        character = String.fromCharCode(event.key)
      else
        character = event.text
      if (!character)
        return ""
      const prefixes = []
      if (control) prefixes.push("C")
      if (alt) prefixes.push("A")
      if (shift) prefixes.push("S")
      return "<" + prefixes.concat(character).join("-") + ">"
    }

    return event.text || ""
  }

  function handleEditorKey(event) {
    const control = (event.modifiers & Qt.ControlModifier) !== 0
    if (NotesService.nvimAvailable && NotesService.nvimMode.startsWith("n")
        && event.text === ":") {
      root.nvimCommandMode = true
      nvimCommandInput.clear()
      Qt.callLater(function() { nvimCommandInput.forceActiveFocus() })
      event.accepted = true
      return
    }
    if (control && event.key === Qt.Key_S) {
      if (!NotesService.nvimAvailable || !NotesService.saveAfterNvimSync())
        root.saveNote()
      event.accepted = true
      return
    }

    if (!NotesService.nvimAvailable && control) {
      if (event.key === Qt.Key_O) {
        root.openNote()
        event.accepted = true
      } else if (event.key === Qt.Key_N) {
        root.newNote()
        event.accepted = true
      } else if (event.key === Qt.Key_F) {
        SettingsData.set("notesSearchVisible", true)
        event.accepted = true
        Qt.callLater(function() { searchField.forceActiveFocus() })
      } else if (event.key === Qt.Key_M) {
        SettingsData.set("notesMarkdownPreview", !root.markdownPreview)
        event.accepted = true
      }
      return
    }

    if (NotesService.nvimAvailable) {
      const keys = root.keyForNvim(event)
      if (keys) {
        NotesService.sendNvimInput(keys)
        event.accepted = true
      }
      return
    }

    if (event.key === Qt.Key_Escape)
      root.setNotesVisible(false)
  }

  function sendNvimCursor(position) {
    if (!NotesService.nvimAvailable || root.applyingNvimState)
      return
    const lines = noteEditor.text.split("\n")
    let remaining = position
    for (let row = 0; row < lines.length; row++) {
      if (remaining <= lines[row].length) {
        NotesService.setNvimCursor(row, Array.from(lines[row].slice(0, remaining)).length)
        return
      }
      remaining -= lines[row].length + 1
    }
    const lastRow = lines.length - 1
    NotesService.setNvimCursor(lastRow, Array.from(lines[lastRow]).length)
  }

  function openNote() {
    chooserInitialPath = NotesService.notesDirectory + "/"
    if (!NotesService.chooseFile(root, "open", chooserInitialPath))
      openDialog.open()
  }

  function saveNote() {
    if (!NotesService.currentDocument)
      return
    if (!NotesService.currentDocument.path) {
      const currentTitle = NotesService.currentDocument.title
      const fileName = currentTitle === qsTr("Untitled") ? "note.txt" : currentTitle
      chooserInitialPath = NotesService.notesDirectory + "/" + fileName
      if (!NotesService.chooseFile(root, "save", chooserInitialPath)) {
        saveDialog.currentFile = NotesService.urlForPath(chooserInitialPath)
        saveDialog.open()
      }
      return
    }
    NotesService.saveCurrent()
  }

  function fallbackToQtFileDialog(operation, initialPath) {
    if (operation === "open")
      openDialog.open()
    else if (operation === "save") {
      saveDialog.currentFile = NotesService.urlForPath(initialPath)
      saveDialog.open()
    }
  }

  function newNote() {
    NotesService.newDocument()
    noteEditor.forceActiveFocus()
  }

  function setAutoSave(enabled) {
    SettingsData.set("notesAutoSave", enabled)
    if (enabled && NotesService.currentDirty && NotesService.currentDocument
        && NotesService.currentDocument.path) {
      NotesService.saveCurrent()
    } else if (enabled && NotesService.currentDirty) {
      NotesService.startAutoSaveCurrent()
    }
  }

  function findNext() {
    const query = searchField.text
    if (!query)
      return
    if (NotesService.nvimAvailable) {
      const escapedQuery = query.replace(/</g, "<lt>").replace(/[\\/]/g, "\\$&")
      NotesService.sendNvimInput("<Esc>/" + escapedQuery + "\n")
      noteEditor.forceActiveFocus()
      return
    }
    const text = noteEditor.text
    let index = text.toLowerCase().indexOf(query.toLowerCase(), noteEditor.cursorPosition)
    if (index < 0)
      index = text.toLowerCase().indexOf(query.toLowerCase())
    if (index >= 0) {
      noteEditor.select(index, index + query.length)
      noteEditor.forceActiveFocus()
    }
  }

  content: Component {
    Item {
      implicitWidth: 24
      implicitHeight: root.widgetThickness

      DmsIcon {
        anchors.centerIn: parent
        name: "edit_note"
        size: root.iconSize(-4)
        color: notesPopup.visible ? Theme.primary : Theme.widgetIconColor
      }
    }

  }

  Connections {
    target: NotesService
    function onNvimSaveRequested() { root.saveNote() }
    function onNvimStateChanged(text, row, column, mode) {
      root.applyingNvimState = true
      Qt.callLater(function() {
        const lines = noteEditor.text.split("\n")
        const targetRow = Math.max(0, Math.min(row, lines.length - 1))
        let position = 0
        for (let index = 0; index < targetRow; index++)
          position += lines[index].length + 1
        position += Array.from(lines[targetRow]).slice(0, Math.max(0, column)).join("").length
        noteEditor.cursorPosition = position
        root.applyingNvimState = false
        editorFlickable.ensureCursorVisible()
      })
    }
    function onFileChooserFinished(requester, operation, exitCode, output, errorOutput) {
      if (requester !== root)
        return
      console.warn("Notes desktop and GTK choosers failed; using Qt Quick FileDialog:",
        String(errorOutput || "").trim() || ("exit status " + exitCode))
      root.fallbackToQtFileDialog(operation, root.chooserInitialPath)
    }
    function onToggleRequested(monitor) {
      if (monitor && Hyprland.monitorFor(root.parentScreen) !== monitor)
        return
      root.setNotesVisible(!notesPopup.visible)
    }
  }

  onClicked: root.setNotesVisible(!notesPopup.visible)

  function setNotesVisible(openVisible) {
    if (notesPopup.visible === openVisible)
      return
    if (openVisible) {
      notesPopup.visible = true
      NotesService.startNvimBackend()
      focusEditorTimer.restart()
    } else {
      notesPopup.visible = false
      focusEditorTimer.stop()
    }
  }

  function focusNotesInput() {
    if (!notesPopup.visible)
      return
    if (!NotesService.ready || !NotesService.sessionLoaded) {
      focusEditorTimer.restart()
      return
    }
    if (root.searchVisible)
      searchField.forceActiveFocus(Qt.PopupFocusReason)
    else if (!root.markdownPreview)
      noteEditor.forceActiveFocus(Qt.PopupFocusReason)
  }

  Timer {
    id: focusEditorTimer
    interval: 100
    repeat: false
    onTriggered: root.focusNotesInput()
  }

  Connections {
    target: NotesService
    function onReadyChanged() { root.focusNotesInput() }
    function onSessionLoadedChanged() { root.focusNotesInput() }
    function onCurrentIndexChanged() { root.focusNotesInput() }
  }

  PanelWindow {
    id: notesPopup

    readonly property real screenWidth: root.parentScreen ? root.parentScreen.width : Screen.width
    readonly property real screenHeight: root.parentScreen ? root.parentScreen.height : Screen.height

    screen: root.parentScreen
    anchors {
      top: true
      right: true
    }
    margins {
      top: Theme.spaceXS
      right: Theme.spaceS
    }
    visible: false
    focusable: visible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    surfaceFormat.opaque: false
    implicitWidth: Math.min(root.expanded ? 960 : 480, Math.max(1, screenWidth - 16))
    implicitHeight: Math.max(1, screenHeight - (root.barWindow ? root.barWindow.height : 0) - 16)

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.withAlpha(Theme.widgetBaseBackgroundColor, SettingsData.barWidgetTransparency)
      border.width: 1
      border.color: Theme.withAlpha(Theme.outline, 0.35)

      Column {
        anchors.fill: parent
        spacing: 0

        Row {
          id: headerRow
          width: parent.width
          height: 44
          spacing: 2

          Text {
            width: parent.width - 84
            height: parent.height
            leftPadding: 16
            text: qsTr("Notepad")
            color: Theme.widgetTextColor
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Theme.fontSizeMedium * 1.3)
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          Rectangle {
            width: 38
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.hoverRadius
            color: expandMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.14) : "transparent"

            DmsIcon {
              anchors.centerIn: parent
              name: root.expanded ? "close_fullscreen" : "open_in_full"
              size: 19
              color: Theme.widgetTextColor
            }

            MouseArea {
              id: expandMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: SettingsData.set("notesExpanded", !root.expanded)
            }
          }

          Rectangle {
            width: 38
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.hoverRadius
            color: closeMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.16) : "transparent"

            DmsIcon {
              anchors.centerIn: parent
              name: "close"
              size: 20
              color: closeMouse.containsMouse ? Theme.error : Theme.widgetTextColor
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setNotesVisible(false)
            }
          }
        }

        Rectangle {
          id: headerDivider
          width: parent.width
          height: 1
          color: Theme.withAlpha(Theme.outline, 0.3)
        }

        Row {
          id: tabsBar
          x: 16
          width: parent.width - 32
          height: 48
          spacing: 8

          Flickable {
            width: parent.width - 46
            height: parent.height
            contentWidth: tabsRow.implicitWidth
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
              id: tabsRow
              height: parent.height
              spacing: 8

              Repeater {
                model: NotesService.documents

                delegate: Rectangle {
                  id: noteTab
                  required property int index
                  required property var modelData

                  width: Math.max(130, Math.min(300, tabTitle.implicitWidth + 54))
                  height: 40
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Theme.cornerRadius
                  property bool hovered: tabMouse.containsMouse
                  color: NotesService.currentIndex === index
                    ? Theme.withAlpha(Theme.primary, 0.16)
                    : "transparent"
                  border.width: NotesService.currentIndex === index ? 0 : 1
                  border.color: Theme.withAlpha(Theme.outline, 0.2)

                  Text {
                    id: tabTitle
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 32
                    anchors.verticalCenter: parent.verticalCenter
                    text: (modelData.text !== modelData.savedText ? "● " : "")
                      + (modelData.title || qsTr("Untitled"))
                    color: NotesService.currentIndex === noteTab.index
                      ? Theme.primary : Theme.widgetInactiveIconColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideMiddle
                  }

                  MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotesService.selectDocument(noteTab.index)
                  }

                  Rectangle {
                    width: 20
                    height: 20
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.hoverRadius
                    visible: noteTab.hovered && NotesService.documents.length > 1
                    color: closeTabMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.15) : "transparent"
                    z: 2

                    DmsIcon {
                      anchors.centerIn: parent
                      name: "close"
                      size: 14
                      color: closeTabMouse.containsMouse ? Theme.error : Theme.widgetInactiveIconColor
                    }

                    MouseArea {
                      id: closeTabMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: NotesService.closeDocument(noteTab.index)
                    }
                  }
                }

              }
            }
          }

          Rectangle {
            width: 38
            height: 38
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.hoverRadius
            color: newMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.14) : "transparent"

            DmsIcon {
              anchors.centerIn: parent
              name: "add"
              size: 20
              color: Theme.widgetTextColor
            }

            MouseArea {
              id: newMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.newNote()
            }
          }
        }

        Rectangle {
          id: searchBar
          width: parent.width - 32
          height: root.searchVisible ? 44 : 0
          x: 16
          visible: root.searchVisible
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.65)

          Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            TextField {
              id: searchField
              width: parent.width - 80
              height: parent.height
              placeholderText: qsTr("Find in text")
              color: Theme.widgetTextColor
              placeholderTextColor: Theme.widgetInactiveIconColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
              background: Item {}
              onAccepted: root.findNext()
              Keys.onEscapePressed: {
                SettingsData.set("notesSearchVisible", false)
                noteEditor.forceActiveFocus()
              }
            }

            Rectangle {
              width: 32
              height: 32
              anchors.verticalCenter: parent.verticalCenter
              radius: Theme.hoverRadius
              color: findMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.15) : "transparent"

              DmsIcon {
                anchors.centerIn: parent
                name: "search"
                size: 18
                color: Theme.widgetInactiveIconColor
              }

              MouseArea {
                id: findMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.findNext()
              }
            }

            Rectangle {
              width: 32
              height: 32
              anchors.verticalCenter: parent.verticalCenter
              radius: Theme.hoverRadius
              color: closeSearchMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.15) : "transparent"

              DmsIcon {
                anchors.centerIn: parent
                name: "close"
                size: 18
                color: Theme.widgetInactiveIconColor
              }

              MouseArea {
                id: closeSearchMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  SettingsData.set("notesSearchVisible", false)
                  noteEditor.forceActiveFocus()
                }
              }
            }
          }
        }

        Row {
          id: optionsBar
          x: 16
          width: parent.width - 32
          height: root.optionsExpanded ? 44 : 0
          visible: root.optionsExpanded
          spacing: 8

          Rectangle {
            width: optionsText.implicitWidth + 32
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.hoverRadius
            color: SettingsData.notesShowLineNumbers
              ? Theme.withAlpha(Theme.primary, 0.16)
              : (lineNumberMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.1) : "transparent")

            Text {
              id: optionsText
              anchors.centerIn: parent
              text: SettingsData.notesShowLineNumbers
                ? qsTr("✓  Line numbers")
                : qsTr("Line numbers")
              color: Theme.widgetTextColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }

            MouseArea {
              id: lineNumberMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: SettingsData.set("notesShowLineNumbers", !SettingsData.notesShowLineNumbers)
            }
          }

          Rectangle {
            width: searchOptionsText.implicitWidth + 32
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.hoverRadius
            color: searchOptionsMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.1) : "transparent"

            Text {
              id: searchOptionsText
              anchors.centerIn: parent
              text: qsTr("Find in text")
              color: Theme.widgetTextColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSmall
            }

            MouseArea {
              id: searchOptionsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                SettingsData.set("notesSearchVisible", true)
                SettingsData.set("notesOptionsExpanded", false)
                Qt.callLater(function() { searchField.forceActiveFocus() })
              }
            }
          }
        }

        Rectangle {
          width: parent.width - 32
          height: Math.max(120, parent.height - headerRow.height - headerDivider.height
            - tabsBar.height - searchBar.height - optionsBar.height - actionBar.height - statusBar.height)
          x: 16
          radius: Theme.cornerRadius
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
          border.width: noteEditor.activeFocus ? 1 : 0
          border.color: Theme.primary
          clip: true

          Flickable {
            id: editorFlickable
            visible: !root.markdownPreview
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: editorRow.height
            flickableDirection: Flickable.VerticalFlick

            function ensureCursorVisible() {
              const cursor = noteEditor.cursorRectangle
              const visibleTop = contentY
              const visibleBottom = contentY + height
              if (cursor.y < visibleTop)
                contentY = Math.max(0, cursor.y)
              else if (cursor.y + cursor.height > visibleBottom)
                contentY = Math.max(0, Math.min(contentHeight - height, cursor.y + cursor.height - height))
            }

            Row {
              id: editorRow
              width: editorFlickable.width
              height: Math.max(editorFlickable.height, noteEditor.contentHeight + 24)
              spacing: 8

              Text {
                id: lineNumbers
                visible: SettingsData.notesShowLineNumbers
                width: visible ? 32 : 0
                height: parent.height
                topPadding: 8
                text: {
                  const count = Math.max(1, NotesService.currentText.split("\n").length)
                  return Array.from({ length: count }, (_, index) => String(index + 1)).join("\n")
                }
                color: Theme.widgetInactiveIconColor
                font.family: noteEditor.font.family
                font.pixelSize: noteEditor.font.pixelSize
                lineHeight: noteEditor.font.pixelSize * 1.35
                lineHeightMode: Text.FixedHeight
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignTop
              }

              TextArea {
                id: noteEditor
                width: parent.width - lineNumbers.width - parent.spacing
                height: parent.height
                text: NotesService.currentText
                enabled: NotesService.ready
                readOnly: NotesService.nvimAvailable
                cursorVisible: NotesService.nvimAvailable && activeFocus
                cursorDelegate: Rectangle {
                  width: NotesService.nvimMode.startsWith("n")
                    ? Math.max(2, noteEditor.font.pixelSize * 0.6)
                    : 2
                  height: NotesService.nvimMode.startsWith("n")
                    ? noteEditor.font.pixelSize * 1.35
                    : noteEditor.cursorRectangle.height
                  color: NotesService.nvimMode.startsWith("n")
                    ? Theme.withAlpha(Theme.primary, 0.55)
                    : Theme.primary
                }
                color: Theme.widgetTextColor
                placeholderText: qsTr("Start typing your notes here...")
                placeholderTextColor: Theme.widgetInactiveIconColor
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeMedium
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                selectByKeyboard: true
                textFormat: TextEdit.PlainText
                leftPadding: 4
                rightPadding: 8
                topPadding: 8
                bottomPadding: 8
                background: Item {}
                onTextChanged: NotesService.editCurrentText(text)
                onCursorPositionChanged: {
                  editorFlickable.ensureCursorVisible()
                  if (!root.applyingNvimState)
                    root.sendNvimCursor(cursorPosition)
                }
                onCursorRectangleChanged: editorFlickable.ensureCursorVisible()
                onContentHeightChanged: editorFlickable.ensureCursorVisible()

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.handleEditorKey(event)
              }
            }
          }

          Rectangle {
            id: nvimCommandBar
            visible: NotesService.nvimAvailable && root.nvimCommandMode && !root.markdownPreview
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.spaceS
            height: 36
            radius: Theme.hoverRadius
            color: Theme.withAlpha(Theme.widgetBaseBackgroundColor, SettingsData.barWidgetTransparency)
            border.width: 1
            border.color: Theme.primary
            z: 2

            Row {
              anchors.fill: parent
              anchors.leftMargin: Theme.spaceS
              anchors.rightMargin: Theme.spaceS
              spacing: Theme.spaceXS

              Text {
                height: parent.height
                text: ":"
                color: Theme.primary
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeMedium
                verticalAlignment: Text.AlignVCenter
              }

              TextInput {
                id: nvimCommandInput
                width: parent.width - Theme.spaceXL
                height: parent.height
                color: Theme.widgetTextColor
                selectionColor: Theme.withAlpha(Theme.primary, 0.3)
                selectedTextColor: Theme.widgetTextColor
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeMedium
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                clip: true
                onAccepted: root.executeNvimCommand()
                Keys.onEscapePressed: root.closeNvimCommandMode()
              }
            }
          }

          Flickable {
            id: previewFlickable
            visible: root.markdownPreview
            anchors.fill: parent
            anchors.margins: 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: markdownText.implicitHeight

            Text {
              id: markdownText
              width: previewFlickable.width
              text: NotesService.currentText
              textFormat: Text.MarkdownText
              color: Theme.widgetTextColor
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeMedium
              wrapMode: Text.Wrap
              linkColor: Theme.primary
              onLinkActivated: function(link) { Qt.openUrlExternally(link) }
            }
          }
        }

        Item {
          id: actionBar
          width: parent.width
          height: 64

          Item {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.rightMargin: 44
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2

              Repeater {
                model: [
                  { id: "save", label: qsTr("Save"), icon: "save" },
                  { id: "open", label: qsTr("Open"), icon: "folder_open" },
                  { id: "new", label: qsTr("New"), icon: "note_add" },
                  { id: "autosave", label: qsTr("Auto-save"), icon: "sync" },
                  { id: "preview", label: root.markdownPreview ? qsTr("Edit") : qsTr("Preview"), icon: root.markdownPreview ? "edit" : "visibility" }
                ]

                delegate: Rectangle {
                  id: actionButton
                  required property var modelData
                  readonly property bool hovered: actionMouse.containsMouse
                  width: actionLayout.implicitWidth + 12
                  height: 42
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Theme.hoverRadius
                  color: actionButton.modelData.id === "autosave" && SettingsData.notesAutoSave
                    ? Theme.withAlpha(Theme.primary, 0.16)
                    : (hovered ? Theme.withAlpha(Theme.primary, 0.13) : "transparent")

                  Row {
                    id: actionLayout
                    anchors.centerIn: parent
                    spacing: 4

                    DmsIcon {
                      anchors.verticalCenter: parent.verticalCenter
                      name: actionButton.modelData.icon
                      size: 20
                      color: actionButton.hovered ? Theme.primary : Theme.widgetInactiveIconColor
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: actionButton.modelData.id === "autosave" && SettingsData.notesAutoSave
                        ? actionButton.modelData.label + " ✓"
                        : actionButton.modelData.label
                      color: actionButton.modelData.id === "autosave" && SettingsData.notesAutoSave
                        ? Theme.primary : Theme.widgetTextColor
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSmall
                    }
                  }

                  MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (actionButton.modelData.id === "save")
                        root.saveNote()
                      else if (actionButton.modelData.id === "open")
                        root.openNote()
                      else if (actionButton.modelData.id === "autosave")
                        root.setAutoSave(!SettingsData.notesAutoSave)
                      else if (actionButton.modelData.id === "preview")
                        SettingsData.set("notesMarkdownPreview", !root.markdownPreview)
                      else
                        root.newNote()
                    }
                  }
                }
              }
            }

            Rectangle {
              width: 40
              height: 40
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              radius: Theme.hoverRadius
              color: moreMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.13) : "transparent"

              DmsIcon {
                anchors.centerIn: parent
                name: "more_horiz"
                size: 20
                color: Theme.widgetInactiveIconColor
              }

              MouseArea {
                id: moreMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SettingsData.set("notesOptionsExpanded", !root.optionsExpanded)
              }
            }
          }
        }

        Row {
          id: statusBar
          x: 16
          width: parent.width - 32
          height: 30
          spacing: 16

          Text {
            id: noteStats
            width: parent.width * 0.32
            height: parent.height
            text: NotesService.currentText.length === 0
              ? qsTr("Empty")
              : qsTr("%1 characters · %2 lines")
                .arg(NotesService.currentText.length)
                .arg(NotesService.currentText.split("\n").length)
            color: Theme.widgetInactiveIconColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          Text {
            width: 96
            height: parent.height
            text: NotesService.nvimAvailable
              ? "Neovim · " + NotesService.nvimMode
              : (NotesService.nvimStarting ? qsTr("Neovim…") : qsTr("TextArea"))
            color: NotesService.nvimAvailable ? Theme.primary : Theme.widgetInactiveIconColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          Text {
            width: parent.width - noteStats.width - 96 - parent.spacing * 2
            height: parent.height
            text: NotesService.error !== "" ? NotesService.error
              : (NotesService.nvimError !== "" && NotesService.nvimAvailable ? NotesService.nvimError
                : (NotesService.saving ? qsTr("Saving…")
                  : (NotesService.currentDirty ? qsTr("Unsaved changes")
                    : (NotesService.currentDocument && NotesService.currentDocument.path
                      ? qsTr("Saved") : qsTr("New note — use Save to choose a file"))))
              )
            color: NotesService.error !== "" || (NotesService.nvimError !== "" && NotesService.nvimAvailable)
              ? Theme.error
              : (NotesService.currentDirty ? Theme.warning : Theme.widgetInactiveIconColor)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
          }
        }
      }
    }
  }

  FileDialog {
    id: openDialog
    title: qsTr("Open note")
    fileMode: FileDialog.OpenFile
    currentFolder: NotesService.urlForPath(NotesService.notesDirectory + "/")
    nameFilters: [qsTr("Text files (*.txt *.md)"), qsTr("All files (*)")]
    onAccepted: NotesService.openFile(selectedFile)
  }

  FileDialog {
    id: saveDialog
    title: qsTr("Save note")
    fileMode: FileDialog.SaveFile
    currentFolder: NotesService.urlForPath(NotesService.notesDirectory + "/")
    currentFile: NotesService.urlForPath(NotesService.notesDirectory + "/note.txt")
    nameFilters: [qsTr("Text files (*.txt *.md)"), qsTr("All files (*)")]
    onAccepted: NotesService.saveCurrent(selectedFile)
  }
}
