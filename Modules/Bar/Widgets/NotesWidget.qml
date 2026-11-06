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
  property bool nvimCommandSubmitting: false
  property var nvimCursors: []
  property var nvimSelections: []
  property var nvimSelectionRects: []
  property var nvimHighlights: []
  property string nvimDisplayText: ""
  property string nvimDisplaySourceText: ""
  property string nvimDisplayHighlightKey: ""
  property var nvimLineStarts: [0]
  property string lastNvimHighlightRange: ""
  property bool preservingNvimViewport: false

  function closeNvimCommandMode() {
    NotesService.sendNvimInput("<Esc>")
    root.nvimCommandMode = false
    Qt.callLater(function() { noteEditor.forceActiveFocus() })
  }

  function executeNvimCommand(commandText) {
    const command = commandText.trim()
    root.nvimCommandSubmitting = false
    root.nvimCommandMode = false

    if (!command) {
      NotesService.sendNvimInput("<CR>")
    } else {
      const normalized = command.toLowerCase()
      if (/^(w|write)(!?)$/.test(normalized)) {
        NotesService.addNvimCommandHistory(command)
        NotesService.sendNvimInput("<Esc>")
        if (!NotesService.saveAfterNvimSync())
          root.saveNoteFromSnapshot()
      } else if (/^(q|quit)(!?)$/.test(normalized)) {
        NotesService.addNvimCommandHistory(command)
        NotesService.sendNvimInput("<Esc>")
        NotesService.closeDocument(NotesService.currentIndex)
      } else if (/^(qa|qall)(!?)$/.test(normalized)) {
        NotesService.addNvimCommandHistory(command)
        NotesService.sendNvimInput("<Esc>")
        root.setNotesVisible(false)
      } else {
        NotesService.sendNvimInput("<CR>")
      }
    }
    Qt.callLater(function() {
      if (notesPopup.visible)
        noteEditor.forceActiveFocus()
    })
  }

  function handleNvimCommandKey(event) {
    if (root.nvimCommandSubmitting) {
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape) {
      root.closeNvimCommandMode()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.nvimCommandSubmitting = NotesService.submitNvimCommandLine()
      event.accepted = true
      return
    }
    const keys = root.keyForNvim(event)
    if (keys) {
      if (keys === "<Tab>" || keys === "<S-Tab>") {
        const query = NotesService.nvimCompletionVisible
          ? NotesService.nvimCompletionQuery
          : NotesService.nvimCommandLine.slice(0, NotesService.nvimCommandPosition)
        NotesService.sendNvimInput(keys, query)
      } else {
        NotesService.sendNvimInput(keys)
      }
    }
    event.accepted = true
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
    if (NotesService.nvimStarting) {
      event.accepted = true
      return
    }
    const control = (event.modifiers & Qt.ControlModifier) !== 0
    if (NotesService.nvimAvailable
        && (NotesService.nvimMode.startsWith("n")
          || NotesService.nvimMode.startsWith("v")
          || NotesService.nvimMode.startsWith("V")
          || NotesService.nvimMode.startsWith("\u0016"))
        && event.text === ":") {
      root.nvimCommandMode = true
      NotesService.sendNvimInput(":")
      Qt.callLater(function() { nvimCommandInput.forceActiveFocus() })
      event.accepted = true
      return
    }
    if (control && event.key === Qt.Key_S) {
      if (!NotesService.nvimAvailable || !NotesService.saveAfterNvimSync())
        root.saveNoteFromSnapshot()
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
    const lines = root.editorPlainText().split("\n")
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

  function nvimModeUsesBlockCursor() {
    const mode = NotesService.nvimMode
    return mode.startsWith("n") || mode.startsWith("v") || mode.startsWith("V")
      || mode.startsWith("\u0016") || mode.startsWith("s") || mode.startsWith("S")
  }

  function nvimModeLabel(mode) {
    if (mode.startsWith("i")) return qsTr("Insert")
    if (mode.startsWith("R")) return qsTr("Replace")
    if (mode.startsWith("v")) return qsTr("Visual")
    if (mode.startsWith("V")) return qsTr("Visual Line")
    if (mode.startsWith("\u0016")) return qsTr("Visual Block")
    if (mode.startsWith("s")) return qsTr("Select")
    if (mode.startsWith("S")) return qsTr("Select Line")
    if (mode.startsWith("r")) return qsTr("Replace Char")
    if (mode.startsWith("c")) return qsTr("Command")
    if (mode.startsWith("n")) return qsTr("Normal")
    return mode
  }

  function nvimCharacterWidth(character) {
    selectionMetrics.text = character
    return selectionMetrics.advanceWidth
  }

  function nvimHighlightRole(group) {
    const name = String(group || "").toLowerCase()
    if (name.includes("error")) return "error"
    if (name.includes("comment")) return "comment"
    if (name.includes("string") || name.includes("character")) return "string"
    if (name.includes("number") || name.includes("boolean")
        || name.includes("constant")) return "constant"
    if (name.includes("function") || name.includes("method")
        || name.includes("constructor")) return "function"
    if (name.includes("keyword") || name.includes("statement")
        || name.includes("conditional") || name.includes("repeat")
        || name.includes("exception") || name.includes("heading")
        || name.includes("strong")) return "keyword"
    if (name.includes("type") || name.includes("class")
        || name.includes("interface") || name.includes("structure")) return "type"
    if (name.includes("preproc") || name.includes("attribute")
        || name.includes("special") || name.includes("markup.link")) return "special"
    return "text"
  }

  function nvimHighlightColor(role) {
    switch (role) {
    case "error": return Theme.error
    case "comment": return Theme.widgetInactiveIconColor
    case "string": return Theme.tertiary
    case "constant":
    case "type": return Theme.secondary
    case "function":
    case "keyword": return Theme.primary
    case "special": return Theme.warning
    default: return Theme.widgetTextColor
    }
  }

  function editorPlainText() {
    return NotesService.nvimAvailable ? NotesService.currentText : noteEditor.text
  }

  function updateNvimLineStarts(text) {
    const starts = [0]
    let newline = -1
    while ((newline = text.indexOf("\n", newline + 1)) >= 0)
      starts.push(newline + 1)
    root.nvimLineStarts = starts
  }

  function nvimLineForPosition(position) {
    const starts = root.nvimLineStarts
    let low = 0
    let high = starts.length
    while (low < high) {
      const middle = Math.floor((low + high) / 2)
      if (starts[middle] <= position)
        low = middle + 1
      else
        high = middle
    }
    return Math.max(0, low - 1)
  }

  function syncNvimHighlightRange() {
    if (!NotesService.nvimAvailable || !notesPopup.visible || root.markdownPreview
        || !NotesService.currentDocument
        || root.nvimLineStarts.length <= NotesService.nvimHighlightLineLimit)
      return

    const top = editorFlickable.contentY + noteEditor.topPadding
    const bottom = Math.min(noteEditor.height,
      editorFlickable.contentY + editorFlickable.height)
    const firstPosition = Math.max(0, noteEditor.positionAt(noteEditor.leftPadding, top))
    const lastPosition = Math.max(firstPosition,
      noteEditor.positionAt(noteEditor.leftPadding, bottom))
    const firstVisibleRow = root.nvimLineForPosition(firstPosition)
    const lastVisibleRow = root.nvimLineForPosition(lastPosition)
    const chunkSize = NotesService.nvimHighlightChunkLines
    const startRow = Math.floor(firstVisibleRow / chunkSize) * chunkSize
    const endRow = Math.min(root.nvimLineStarts.length,
      Math.max(startRow + chunkSize,
        Math.ceil((lastVisibleRow + 1) / chunkSize) * chunkSize))
    const rangeKey = NotesService.currentDocument.id + ":" + startRow + ":" + endRow
    if (rangeKey === root.lastNvimHighlightRange)
      return
    root.lastNvimHighlightRange = rangeKey
    NotesService.setNvimHighlightRange(startRow, endRow)
  }

  function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }

  function buildNvimRichText(text, highlights) {
    const lines = String(text).split("\n")
    const groups = lines.map(line =>
      Array.from(line, () => ""))
    for (const highlight of highlights || []) {
      const row = Math.max(0, Math.min(Number(highlight.row) || 0, lines.length - 1))
      const start = Math.max(0, Number(highlight.start_column) || 0)
      const end = Math.min(groups[row].length,
        Math.max(start, Number(highlight.end_column) || 0))
      for (let column = start; column < end; column++)
        groups[row][column] = String(highlight.group || "")
    }

    let markup = "<pre style=\"margin:0; white-space:pre-wrap; font-family:'"
      + root.escapeHtml(noteEditor.font.family) + "'; font-size:"
      + noteEditor.font.pixelSize + "px;\">"
    for (let row = 0; row < lines.length; row++) {
      const characters = Array.from(lines[row])
      let column = 0
      while (column < characters.length) {
        const role = root.nvimHighlightRole(groups[row][column])
        let end = column + 1
        while (end < characters.length
            && root.nvimHighlightRole(groups[row][end]) === role)
          end++
        const color = root.nvimHighlightColor(role).toString()
        markup += "<span style=\"color:" + color + "\">"
          + root.escapeHtml(characters.slice(column, end).join(""))
          + "</span>"
        column = end
      }
      if (row < lines.length - 1)
        markup += "\n"
    }
    return markup + "</pre>"
  }

  function editorTextPosition(row, column) {
    const lines = root.editorPlainText().split("\n")
    const targetRow = Math.max(0, Math.min(row, lines.length - 1))
    let position = 0
    for (let index = 0; index < targetRow; index++)
      position += lines[index].length + 1
    return position + Array.from(lines[targetRow])
      .slice(0, Math.max(0, column)).join("").length
  }

  function appendNvimSelectionRect(rects, x, y, width, height) {
    if (width <= 0 || height <= 0)
      return
    const last = rects.length ? rects[rects.length - 1] : null
    if (last && Math.abs(last.y - y) < 0.5
        && Math.abs(last.x + last.width - x) < 0.5) {
      rects[rects.length - 1] = {
        x: last.x, y: last.y, width: last.width + width,
        height: Math.max(last.height, height)
      }
    } else {
      rects.push({ x: x, y: y, width: width, height: height })
    }
  }

  function buildNvimSelectionRects(selections) {
    const rects = []
    const lines = root.editorPlainText().split("\n")
    const rightEdge = noteEditor.width - noteEditor.rightPadding
    const cellWidth = Math.max(1, root.nvimCharacterWidth(" "))

    for (const selection of selections || []) {
      const row = Math.max(0, Math.min(selection.row, lines.length - 1))
      const chars = Array.from(lines[row])
      const start = Math.max(0, Math.min(selection.start_column, chars.length))
      const end = Math.max(start, Math.min(selection.end_column, chars.length))
      const lineStart = editorTextPosition(row, start)

      for (let column = start; column < end; column++) {
        const selectedCharacter = chars[column]
        const position = editorTextPosition(row, column)
        const rect = noteEditor.positionToRectangle(position)
        const nextRect = noteEditor.positionToRectangle(
          position + selectedCharacter.length)
        const width = Math.abs(rect.y - nextRect.y) < 0.5
          && nextRect.x > rect.x
          ? nextRect.x - rect.x
          : Math.max(1, root.nvimCharacterWidth(selectedCharacter))
        root.appendNvimSelectionRect(rects, rect.x, rect.y, width, rect.height)

        if (selection.fill_to_end
            && (column + 1 === end
                || Math.abs(rect.y - nextRect.y) >= 0.5)) {
          root.appendNvimSelectionRect(rects, rect.x + width, rect.y,
            Math.max(0, rightEdge - rect.x - width), rect.height)
        }
      }

      if (selection.kind === "line") {
        const endRect = noteEditor.positionToRectangle(
          editorTextPosition(row, chars.length))
        root.appendNvimSelectionRect(rects, endRect.x, endRect.y,
          Math.max(0, rightEdge - endRect.x), endRect.height)
      } else if (selection.kind === "block"
          && selection.end_column > chars.length) {
        const virtualStart = Math.max(selection.start_column, chars.length)
        const rect = noteEditor.positionToRectangle(
          editorTextPosition(row, chars.length))
        const x = rect.x + (virtualStart - chars.length) * cellWidth
        root.appendNvimSelectionRect(rects, x, rect.y,
          (selection.end_column - virtualStart) * cellWidth, rect.height)
      } else if (selection.fill_to_end && start === end) {
        const rect = noteEditor.positionToRectangle(lineStart)
        root.appendNvimSelectionRect(rects, rect.x, rect.y,
          Math.max(0, rightEdge - rect.x), rect.height)
      }
    }
    return rects
  }

  function openNote() {
    chooserInitialPath = NotesService.notesDirectory + "/"
    if (!NotesService.chooseFile(root, "open", chooserInitialPath))
      openDialog.open()
  }

  function saveNote() {
    if (NotesService.nvimAvailable && NotesService.saveAfterNvimSync())
      return
    root.saveNoteFromSnapshot()
  }

  function saveNoteFromSnapshot() {
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
    NotesService.saveDocument(NotesService.currentDocument.id)
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
    const text = root.editorPlainText()
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

  TextMetrics {
    id: selectionMetrics
    font: noteEditor.font
  }

  Timer {
    id: nvimHighlightRangeTimer
    interval: 50
    repeat: false
    onTriggered: root.syncNvimHighlightRange()
  }

  Connections {
    target: NotesService
    function onNvimSaveRequested() { root.saveNoteFromSnapshot() }
    function onNvimCommandSubmitted(commandLine) {
      root.executeNvimCommand(commandLine)
    }
    function onNvimAvailableChanged() {
      if (!NotesService.nvimAvailable) {
        root.nvimCommandMode = false
        root.nvimCommandSubmitting = false
        root.lastNvimHighlightRange = ""
      }
    }
    function onCurrentIndexChanged() {
      root.lastNvimHighlightRange = ""
      nvimHighlightRangeTimer.restart()
    }
    function onNvimErrorChanged() {
      if (NotesService.nvimError !== "")
        root.nvimCommandSubmitting = false
    }
    function onNvimStateChanged(text, row, column, mode, selections, cursors, highlights) {
      if (!String(mode).startsWith("c") && root.nvimCommandMode
          && !root.nvimCommandSubmitting) {
        root.nvimCommandMode = false
        Qt.callLater(function() { noteEditor.forceActiveFocus() })
      }
      root.applyingNvimState = true
      root.nvimCursors = cursors || []
      root.nvimSelections = selections || []
      const sourceText = String(text)
      const nextHighlights = highlights || []
      const highlightKey = JSON.stringify(nextHighlights)
      const textChanged = root.nvimDisplaySourceText !== sourceText
      const preserveViewport = !textChanged
        && NotesService.nvimSnapshotOperation === "set_highlight_range"
      const previousContentY = editorFlickable.contentY
      root.preservingNvimViewport = preserveViewport
      if (textChanged) {
        root.nvimDisplaySourceText = sourceText
        root.updateNvimLineStarts(sourceText)
      }
      if (textChanged || root.nvimDisplayHighlightKey !== highlightKey) {
        root.nvimHighlights = nextHighlights
        root.nvimDisplayHighlightKey = highlightKey
        root.nvimDisplayText = root.buildNvimRichText(sourceText, nextHighlights)
      }
      Qt.callLater(function() {
        noteEditor.cursorPosition = root.editorTextPosition(row, column)
        root.nvimSelectionRects =
          root.buildNvimSelectionRects(root.nvimSelections)
        if (preserveViewport)
          editorFlickable.contentY = previousContentY
        else
          editorFlickable.ensureCursorVisible()
        root.preservingNvimViewport = false
        root.applyingNvimState = false
        nvimHighlightRangeTimer.restart()
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
            onContentYChanged: nvimHighlightRangeTimer.restart()
            onContentHeightChanged: nvimHighlightRangeTimer.restart()
            onHeightChanged: nvimHighlightRangeTimer.restart()
            onVisibleChanged: {
              if (visible)
                nvimHighlightRangeTimer.restart()
            }

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
                text: NotesService.nvimAvailable
                  ? root.nvimDisplayText : NotesService.currentText
                enabled: NotesService.ready && !NotesService.nvimStarting
                readOnly: NotesService.nvimAvailable
                cursorVisible: NotesService.nvimAvailable && activeFocus
                cursorDelegate: Rectangle {
                  width: root.nvimModeUsesBlockCursor()
                    ? Math.max(2, noteEditor.font.pixelSize * 0.6)
                    : 2
                  height: root.nvimModeUsesBlockCursor()
                    ? noteEditor.font.pixelSize * 1.35
                    : noteEditor.cursorRectangle.height
                  color: root.nvimModeUsesBlockCursor()
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
                textFormat: NotesService.nvimAvailable
                  ? TextEdit.RichText : TextEdit.PlainText
                leftPadding: 4
                rightPadding: 8
                topPadding: 8
                bottomPadding: 8
                background: Item {
                  clip: true
                  Repeater {
                    model: root.nvimSelectionRects
                    delegate: Rectangle {
                      visible: NotesService.nvimAvailable
                      x: modelData.x
                      y: modelData.y
                      width: modelData.width
                      height: modelData.height
                      color: Theme.withAlpha(Theme.primary, 0.3)
                    }
                  }
                }
                Repeater {
                  model: root.nvimCursors
                  delegate: Rectangle {
                    readonly property int textPosition:
                      root.editorTextPosition(modelData.row, modelData.column)
                    readonly property rect cursorRect:
                      noteEditor.positionToRectangle(textPosition)
                    visible: NotesService.nvimAvailable && noteEditor.activeFocus
                    x: cursorRect.x
                    y: cursorRect.y
                    width: root.nvimModeUsesBlockCursor()
                      ? Math.max(2, noteEditor.font.pixelSize * 0.6)
                      : 2
                    height: root.nvimModeUsesBlockCursor()
                      ? cursorRect.height
                      : noteEditor.cursorRectangle.height
                    color: root.nvimModeUsesBlockCursor()
                      ? Theme.withAlpha(Theme.primary, 0.55)
                      : Theme.primary
                  }
                }
                onTextChanged: {
                  if (!NotesService.nvimAvailable)
                    NotesService.editCurrentText(text)
                }
                onCursorPositionChanged: {
                  editorFlickable.ensureCursorVisible()
                  if (!root.applyingNvimState)
                    root.sendNvimCursor(cursorPosition)
                }
                onCursorRectangleChanged: {
                  if (!root.preservingNvimViewport)
                    editorFlickable.ensureCursorVisible()
                }
                onContentHeightChanged: editorFlickable.ensureCursorVisible()
                onWidthChanged: Qt.callLater(function() {
                  root.nvimSelectionRects =
                    root.buildNvimSelectionRects(root.nvimSelections)
                  nvimHighlightRangeTimer.restart()
                })
                onHeightChanged: nvimHighlightRangeTimer.restart()

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
                text: NotesService.nvimCommandLine
                cursorPosition: NotesService.nvimCommandPosition
                readOnly: true
                color: Theme.widgetTextColor
                selectionColor: Theme.withAlpha(Theme.primary, 0.3)
                selectedTextColor: Theme.widgetTextColor
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeMedium
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                clip: true
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.handleNvimCommandKey(event)
              }
            }
          }

          Rectangle {
            id: nvimCompletionMenu
            visible: NotesService.nvimAvailable && root.nvimCommandMode
              && !root.markdownPreview && NotesService.nvimCompletionVisible
              && NotesService.nvimCompletionCandidates.length > 0
            x: nvimCommandBar.x
            width: Math.min(nvimCommandBar.width, 360)
            height: Math.min(NotesService.nvimCompletionCandidates.length * 26, 182)
            anchors.bottom: nvimCommandBar.top
            anchors.bottomMargin: Theme.spaceXS
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, 0.35)
            clip: true
            z: 3

            ListView {
              id: nvimCompletionList
              anchors.fill: parent
              anchors.margins: Theme.spaceXS
              model: NotesService.nvimCompletionCandidates
              currentIndex: NotesService.nvimCompletionIndex
              highlightFollowsCurrentItem: false
              clip: true
              onCurrentIndexChanged: {
                if (currentIndex >= 0)
                  positionViewAtIndex(currentIndex, ListView.Contain)
              }

              delegate: Rectangle {
                required property string modelData
                required property int index
                width: nvimCompletionList.width
                height: 26
                radius: Theme.hoverRadius
                color: index === nvimCompletionList.currentIndex
                  ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"

                Text {
                  anchors.fill: parent
                  anchors.leftMargin: Theme.spaceS
                  anchors.rightMargin: Theme.spaceS
                  text: modelData
                  color: Theme.surfaceText
                  font.family: Theme.monoFontFamily
                  font.pixelSize: Theme.fontSizeSmall
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                }
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
            id: nvimModeStatus
            width: implicitWidth
            height: parent.height
            text: NotesService.nvimAvailable
              ? "Neovim · " + (root.nvimCommandMode
                ? qsTr("Command") : root.nvimModeLabel(NotesService.nvimMode))
              : (NotesService.nvimStarting ? qsTr("Neovim…") : qsTr("TextArea"))
            color: NotesService.nvimAvailable ? Theme.primary : Theme.widgetInactiveIconColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            verticalAlignment: Text.AlignVCenter
          }

          Text {
            width: parent.width - noteStats.width - nvimModeStatus.width - parent.spacing * 2
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
