pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common

Singleton {
  id: root

  readonly property string notesDirectory: localPath(StandardPaths.writableLocation(StandardPaths.DocumentsLocation)) + "/notes"
  readonly property string stateDirectory: localPath(StandardPaths.writableLocation(StandardPaths.GenericStateLocation)) + "/myquickshell"
  readonly property string legacyNotesPath: stateDirectory + "/notes.txt"
  readonly property string sessionPath: stateDirectory + "/notes-session.json"
  property var documents: []
  property int currentIndex: 0
  property int _nextId: 1
  property int _autoSaveDocumentId: -1
  property var _pendingWritesByDocument: ({})
  property var _pendingWritesByPath: ({})
  property var _documentWatchers: ({})
  property string error: ""
  property bool ready: false
  property bool sessionLoaded: false
  property bool restoringSession: false
  property bool nvimAvailable: false
  property bool nvimStarting: false
  property string nvimError: ""
  property string nvimMode: ""
  property string nvimShowcmd: ""
  property string nvimRecordingRegister: ""
  property string nvimCommandType: ""
  property int nvimRow: 0
  property var nvimEditorOptions: ({})
  property var nvimSearchHighlights: []
  property string nvimCommandLine: ""
  property string nvimSnapshotOperation: ""
  property int nvimCommandPosition: 0
  property string nvimCompletionQuery: ""
  property var nvimCompletionCandidates: []
  property int nvimCompletionIndex: -1
  property bool nvimCompletionVisible: false
  property int nvimHighlightLineLimit: 2000
  property int nvimHighlightChunkLines: 200
  property int _nvimRequestId: 0
  property int _nvimSelectionRequestId: 0
  property int _saveAfterNvimRequestId: 0
  property string _saveAfterNvimUrl: ""
  property bool _saveAfterNvimAutoSave: false
  property int _nvimCommandSubmitRequestId: 0
  property int _nvimRequestedDocumentId: -1
  property int _nvimActiveDocumentId: -1
  property string _nvimDocumentFilename: ""
  property string nvimText: ""
  property var nvimHighlights: []
  readonly property var currentDocument: documents.length > currentIndex ? documents[currentIndex] : null
  readonly property string currentText: nvimAvailable
    ? nvimText : (currentDocument ? currentDocument.text : "")
  readonly property bool currentDirty: currentDocument ? currentDocument.text !== currentDocument.savedText : false
  readonly property bool saving: currentDocument
    ? Number(_pendingWritesByDocument[currentDocument.id] || 0) > 0 : false

  signal fileChooserFinished(var requester, string operation, int exitCode, string output, string errorOutput)
  signal toggleRequested(var monitor)
  signal nvimStateChanged(string text, int row, int column, string mode,
    var selections, var cursors, var highlights)
  signal nvimCommandSubmitted(string commandLine, string commandType)
  signal nvimSaveRequested()

  onDocumentsChanged: {
    scheduleSessionSave()
    syncNvimDocumentMetadata()
    syncDocumentWatchers()
  }
  onCurrentIndexChanged: {
    scheduleSessionSave()
  }

  function startNvimBackend() {
    if (!nvimBridge.running && !nvimAvailable) {
      nvimStarting = true
      nvimError = ""
      clearNvimShowcmd()
      nvimBridge.running = true
    }
  }

  function clearNvimShowcmd() {
    nvimShowcmdClearTimer.stop()
    nvimShowcmd = ""
  }

  function sendNvimRequest(operation, values) {
    if (!nvimAvailable || !nvimBridge.running)
      return 0
    const request = Object.assign({ id: ++_nvimRequestId, operation: operation }, values || {})
    nvimBridge.write(JSON.stringify(request) + "\n")
    return request.id
  }

  function syncNvimDocument(document) {
    const doc = document || currentDocument
    if (!nvimAvailable || !doc)
      return
    const filename = doc.path || doc.title || ""
    if (doc.id !== _nvimRequestedDocumentId) {
      const requestId = sendNvimRequest(
        "select_document",
        { document_id: doc.id, text: doc.text, filename: filename })
      if (requestId) {
        _nvimRequestedDocumentId = doc.id
        _nvimDocumentFilename = filename
        _nvimSelectionRequestId = requestId
      }
    } else if (filename !== _nvimDocumentFilename) {
      _nvimDocumentFilename = filename
      sendNvimRequest("set_filetype", {
        document_id: doc.id, filename: filename, text: doc.text
      })
    }
  }

  function registerNvimDocuments() {
    if (!nvimAvailable || !documents.length || !currentDocument)
      return
    const requestId = sendNvimRequest("register_documents", {
      active_document_id: currentDocument.id,
      documents: documents.map(doc => ({
        document_id: doc.id,
        text: doc.text,
        filename: doc.path || doc.title || ""
      }))
    })
    if (requestId) {
      _nvimRequestedDocumentId = currentDocument.id
      _nvimDocumentFilename = currentDocument.path || currentDocument.title || ""
      _nvimSelectionRequestId = requestId
    }
  }

  function syncNvimDocumentMetadata() {
    const doc = currentDocument
    if (!nvimAvailable || !doc
        || (doc.id !== _nvimActiveDocumentId
          && doc.id !== _nvimRequestedDocumentId))
      return
    const filename = doc.path || doc.title || ""
    if (filename === _nvimDocumentFilename)
      return
    _nvimDocumentFilename = filename
    sendNvimRequest("set_filetype", {
      document_id: doc.id, filename: filename, text: doc.text
    })
  }

  function handleNvimBridgeMessage(line) {
    let message
    try {
      message = JSON.parse(String(line))
    } catch (error) {
      console.warn("NotesService received invalid Neovim bridge output:", String(line))
      return
    }

    if (message.type === "document_snapshot") {
      const documentIndex = documents.findIndex(doc => doc.id === Number(message.document_id))
      if (documentIndex < 0)
        return
      const document = documents[documentIndex]
      const text = String(message.text || "")
      updateDocument(document.id, { text: text, savedText: text })
      if (_nvimActiveDocumentId === document.id)
        nvimText = text
      return
    }
    if (message.type === "external_conflict") {
      const document = documents.find(doc => doc.id === Number(message.document_id))
      if (!document)
        return
      updateDocument(document.id, { savedText: String(message.text || "") })
      error = qsTr("This note changed on disk while it has unsaved edits.")
      return
    }
    if (message.type === "ready") {
      nvimStarting = false
      nvimAvailable = true
      nvimError = ""
      nvimHighlightLineLimit = Number(message.highlight_line_limit) || nvimHighlightLineLimit
      nvimHighlightChunkLines = Number(message.highlight_chunk_lines) || nvimHighlightChunkLines
      _nvimRequestedDocumentId = -1
      _nvimActiveDocumentId = -1
      _nvimDocumentFilename = ""
      registerNvimDocuments()
      return
    }
    if (message.type === "unavailable") {
      nvimStarting = false
      nvimAvailable = false
      clearNvimShowcmd()
      nvimError = message.message || qsTr("Neovim or its Python client is unavailable.")
      console.info("NotesService: using the built-in editor:", nvimError)
      return
    }
    if (message.type === "showcmd") {
      const value = String(message.value || "")
      if (value) {
        nvimShowcmdClearTimer.stop()
        nvimShowcmd = value
      } else if (nvimShowcmd !== "") {
        nvimShowcmdClearTimer.restart()
      }
      return
    }
    if (message.type === "showcmd_error") {
      clearNvimShowcmd()
      nvimError = qsTr("Neovim key display stopped: %1").arg(message.message || qsTr("unknown error"))
      console.warn("NotesService Neovim showcmd listener failed:", message.message || "Unknown error")
      return
    }
    if (message.type === "error") {
      if (Number(message.id) === _nvimCommandSubmitRequestId)
        _nvimCommandSubmitRequestId = 0
      if (Number(message.id) === _saveAfterNvimRequestId) {
        _saveAfterNvimRequestId = 0
        _saveAfterNvimUrl = ""
        _saveAfterNvimAutoSave = false
      }
      nvimError = message.message || qsTr("Neovim command failed.")
      console.warn("NotesService Neovim bridge error:", message.message || "Unknown error")
      return
    }
    if (message.type !== "snapshot")
      return

    if (Number(message.id) < _nvimSelectionRequestId
        && Number(message.id) !== _saveAfterNvimRequestId)
      return

    const documentId = Number(message.document_id)
    const documentIndex = documents.findIndex(doc => doc.id === documentId)
    if (documentIndex < 0)
      return
    _nvimActiveDocumentId = documentId
    const activeDocument = documents[documentIndex]
    _nvimDocumentFilename = activeDocument.path || activeDocument.title || ""
    nvimText = String(message.text || "")
    if (currentIndex !== documentIndex)
      currentIndex = documentIndex

    nvimMode = String(message.mode || "")
    nvimRecordingRegister = String(message.recording_register || "")
    nvimCommandType = String(message.command_type || "")
    nvimRow = Number(message.row) || 0
    nvimEditorOptions = message.editor_options || ({})
    if (!nvimEditorOptions.showcmd)
      clearNvimShowcmd()
    nvimSearchHighlights = message.search_highlights || []
    nvimSnapshotOperation = String(message.operation || "")
    nvimCommandLine = String(message.command_line || "")
    nvimCommandPosition = Number(message.command_position) || 0
    nvimCompletionQuery = String(message.completion_query || "")
    nvimCompletionCandidates = message.completion_candidates || []
    nvimCompletionIndex = Number(message.completion_index)
    nvimCompletionVisible = Boolean(message.completion_visible)
    nvimHighlights = message.highlights || []
    nvimError = ""
    nvimStateChanged(message.text, Number(message.row) || 0,
      Number(message.column) || 0, nvimMode, message.selections || [],
      message.cursors || [], nvimHighlights)
    const document = documents[documentIndex]
    if (message.text !== document.text)
      updateDocumentText(documentId, message.text)
    if (Number(message.id) === _nvimCommandSubmitRequestId) {
      _nvimCommandSubmitRequestId = 0
      nvimCommandSubmitted(nvimCommandLine, nvimCommandType)
    }
    if (Number(message.id) === _saveAfterNvimRequestId) {
      _saveAfterNvimRequestId = 0
      const saveUrl = _saveAfterNvimUrl
      const autoSave = _saveAfterNvimAutoSave
      _saveAfterNvimUrl = ""
      _saveAfterNvimAutoSave = false
      if (autoSave)
        startAutoSaveCurrentFromSnapshot()
      else if (saveUrl)
        saveDocument(documentId, saveUrl)
      else
        nvimSaveRequested()
    }
  }

  function sendNvimInput(keys, completionQuery) {
    const request = { keys: keys }
    if (completionQuery !== undefined)
      request.completion_query = completionQuery
    return sendNvimRequest("input", request)
  }

  function submitNvimCommandLine() {
    _nvimCommandSubmitRequestId = sendNvimRequest("command_state")
    return _nvimCommandSubmitRequestId !== 0
  }

  function addNvimCommandHistory(command) {
    sendNvimRequest("add_command_history", { command: command })
  }

  function setNvimCursor(row, column) {
    sendNvimRequest("set_cursor", { row: row, column: column })
  }

  function setNvimHighlightRange(startRow, endRow) {
    sendNvimRequest("set_highlight_range", {
      document_id: currentDocument ? currentDocument.id : -1,
      start_row: startRow, end_row: endRow
    })
  }

  function closeNvimDocument(documentId) {
    sendNvimRequest("close_document", { document_id: documentId })
  }

  function saveAfterNvimSync(url, autoSave) {
    const requestId = sendNvimRequest("sync")
    if (!requestId)
      return false
    _saveAfterNvimRequestId = requestId
    _saveAfterNvimUrl = url ? String(url) : ""
    _saveAfterNvimAutoSave = Boolean(autoSave)
    return true
  }

  Timer {
    id: nvimShowcmdClearTimer
    interval: 2000
    repeat: false
    onTriggered: root.nvimShowcmd = ""
  }

  property Process nvimBridge: Process {
    id: nvimBridge
    command: ["python3", "-u", Quickshell.shellDir + "/Services/NotesNvimBridge.py"]
    stdinEnabled: true

    stdout: SplitParser {
      onRead: data => root.handleNvimBridgeMessage(data)
    }
    stderr: SplitParser {
      onRead: data => console.warn("NotesService Neovim bridge:", String(data))
    }
    onExited: function(exitCode) {
      if (root.nvimStarting) {
        root.nvimStarting = false
        root.nvimAvailable = false
        root.clearNvimShowcmd()
        root.nvimError = qsTr("Neovim backend exited during startup (status %1).").arg(exitCode)
      } else if (root.nvimAvailable) {
        root.nvimAvailable = false
        root.clearNvimShowcmd()
        root.nvimError = qsTr("Neovim backend stopped (status %1); using the built-in editor.").arg(exitCode)
      }
    }
  }

  IpcHandler {
    target: "notes"

    function toggle(): string {
      root.toggleRequested(Hyprland.focusedMonitor)
      return "Toggled MyQuickshell notes overlay"
    }
  }

  // Allows Hyprland to toggle the overlay without depending on DMS.
  GlobalShortcut {
    appid: "quickshell"
    name: "notes"
    description: "Toggle the MyQuickshell notes overlay"

    onPressed: root.toggleRequested(Hyprland.focusedMonitor)
  }

  function localPath(url) {
    return String(url).replace(/^file:\/\//, "")
  }

  function pathFromUrl(url) {
    const value = String(url)
    if (!value.startsWith("file://"))
      return value
    return decodeURIComponent(value.replace(/^file:\/\//, ""))
  }

  function urlForPath(path) {
    return "file://" + encodeURI(path)
  }

  function chooseFile(requester, operation, initialPath) {
    return startChooserProcess(requester, operation, initialPath, true)
  }

  function chooserArguments(operation, initialPath, requestPortal) {
    const title = operation === "open" ? qsTr("Open note") : qsTr("Save note")
    const args = requestPortal
      ? ["env", "GTK_USE_PORTAL=1", "zenity", "--file-selection"]
      : ["zenity", "--file-selection"]
    args.push(
      "--title=" + title,
      "--filename=" + initialPath,
      "--file-filter=" + qsTr("Text files") + " | *.txt *.md",
      "--file-filter=" + qsTr("All files") + " | *"
    )
    if (operation === "save")
      args.splice(requestPortal ? 4 : 2, 0, "--save", "--confirm-overwrite")
    return args
  }

  function startChooserProcess(requester, operation, initialPath, requestPortal) {
    const process = chooserProcess.createObject(root, {
      requester: requester,
      operation: operation,
      stage: requestPortal ? "portal" : "gtk",
      initialPath: initialPath,
      command: chooserArguments(operation, initialPath, requestPortal)
    })
    if (!process) {
      console.error("NotesService could not create desktop file chooser process.")
      return false
    }
    process.running = true
    return true
  }

  function handleChooserResult(requester, operation, stage, initialPath, exitCode, output, errorOutput) {
    const selectedPath = String(output || "").trim()
    if (exitCode === 0 && selectedPath !== "") {
      if (operation === "open")
        openFile(urlForPath(selectedPath))
      else
        saveCurrent(urlForPath(selectedPath))
      return
    }
    if (exitCode === 1 && String(errorOutput || "").trim() === "")
      return

    if (stage === "portal") {
      if (!startChooserProcess(requester, operation, initialPath, false))
        fileChooserFinished(requester, operation, exitCode, output, errorOutput)
      return
    }
    console.warn("Notes GTK file chooser failed; using Qt Quick FileDialog:",
      String(errorOutput || "").trim() || ("exit status " + exitCode))
    fileChooserFinished(requester, operation, exitCode, output, errorOutput)
  }

  function newDocument() {
    const next = documents.slice()
    next.push({
      id: _nextId++,
      title: qsTr("Untitled"),
      path: "",
      text: "",
      savedText: ""
    })
    documents = next
    currentIndex = next.length - 1
    syncNvimDocument()
    error = ""
  }

  function scheduleSessionSave() {
    if (ready && sessionLoaded && !restoringSession)
      sessionSaveTimer.restart()
  }

  function saveSession() {
    if (!ready || !sessionLoaded || restoringSession)
      return
    const state = {
      version: 1,
      currentIndex: currentIndex,
      documents: documents.map(doc => ({
        title: doc.title,
        path: doc.path,
        text: doc.text,
        savedText: doc.savedText
      }))
    }
    sessionFile.setText(JSON.stringify(state))
  }

  function restoreSession(serialized) {
    let state = null
    try {
      state = serialized ? JSON.parse(serialized) : null
    } catch (e) {
      console.error("Failed to parse notes session:", e.message)
    }

    restoringSession = true
    const restored = []
    if (state && Array.isArray(state.documents)) {
      for (const item of state.documents) {
        if (!item || typeof item.text !== "string" || typeof item.path !== "string")
          continue
        const savedText = typeof item.savedText === "string" ? item.savedText : item.text
        restored.push({
          id: _nextId++,
          title: typeof item.title === "string" && item.title ? item.title : qsTr("Untitled"),
          path: item.path,
          text: item.text,
          savedText: savedText
        })
      }
    }
    documents = restored
    currentIndex = restored.length > 0
      ? Math.max(0, Math.min(restored.length - 1, Number(state.currentIndex) || 0))
      : 0
    restoringSession = false
    sessionLoaded = true

    if (restored.length === 0)
      loadDefaultNote()
    else if (nvimAvailable)
      registerNvimDocuments()
    else
      syncNvimDocument()
  }

  function selectDocument(index) {
    if (index < 0 || index >= documents.length)
      return
    if (nvimAvailable) {
      syncNvimDocument(documents[index])
    } else {
      currentIndex = index
    }
    error = ""
  }

  function closeDocument(index) {
    if (index < 0 || index >= documents.length)
      return
    if (documents[index].text !== documents[index].savedText) {
      error = qsTr("Save changes before closing this note.")
      return
    }
    if (nvimAvailable)
      closeNvimDocument(documents[index].id)
    const closedDocumentId = documents[index].id
    const next = documents.slice()
    next.splice(index, 1)
    documents = next
    const pending = Object.assign({}, _pendingWritesByDocument)
    delete pending[closedDocumentId]
    _pendingWritesByDocument = pending
    destroyDocumentWatcher(closedDocumentId)
    if (next.length === 0) {
      currentIndex = 0
      newDocument()
    } else if (currentIndex > index) {
      currentIndex--
    } else if (currentIndex >= next.length) {
      currentIndex = next.length - 1
    }
    syncNvimDocument()
    error = ""
  }

  function editCurrentText(value) {
    if (nvimAvailable || nvimStarting)
      return
    const doc = currentDocument
    if (doc)
      updateDocumentText(doc.id, value)
  }

  function updateDocumentText(documentId, value) {
    const doc = documents.find(item => item.id === documentId)
    if (!ready || !doc || value === doc.text)
      return
    updateDocument(doc.id, { text: value })
    if (SettingsData.notesAutoSave) {
      if (!doc.path && value.length > 0)
        assignAutoSavePath(doc.id)
      _autoSaveDocumentId = doc.id
      autoSaveTimer.restart()
    }
  }

  function assignAutoSavePath(documentId) {
    const doc = documents.find(item => item.id === documentId)
    if (!doc || doc.path || doc.text.length === 0)
      return
    const fileName = "note-" + Date.now() + "-" + _nextId + ".txt"
    updateDocument(documentId, {
      path: notesDirectory + "/" + fileName,
      title: fileName
    })
  }

  function startAutoSaveCurrent() {
    if (nvimAvailable && saveAfterNvimSync("", true))
      return true
    return startAutoSaveCurrentFromSnapshot()
  }

  function startAutoSaveCurrentFromSnapshot() {
    const doc = currentDocument
    if (!doc || !doc.text)
      return false
    assignAutoSavePath(doc.id)
    return saveDocument(doc.id)
  }

  function updateDocument(id, updates) {
    const next = documents.slice()
    const index = next.findIndex(doc => doc.id === id)
    if (index < 0)
      return
    next[index] = Object.assign({}, next[index], updates)
    documents = next
  }

  function adjustPendingWrite(mapName, key, delta) {
    const map = Object.assign({}, root[mapName])
    const count = Number(map[key] || 0) + delta
    if (count > 0)
      map[key] = count
    else
      delete map[key]
    root[mapName] = map
  }

  function syncDocumentWatchers() {
    for (const id of Object.keys(_documentWatchers)) {
      const document = documents.find(doc => String(doc.id) === id)
      const watcher = _documentWatchers[id]
      if (!document || !document.path) {
        watcher.destroy()
        delete _documentWatchers[id]
      } else if (watcher.path !== document.path) {
        watcher.destroy()
        delete _documentWatchers[id]
      }
    }
    for (const document of documents) {
      if (!document.path || _documentWatchers[String(document.id)])
        continue
      const watcher = documentWatcher.createObject(root, {
        documentId: document.id,
        initialized: false
      })
      if (!watcher)
        continue
      _documentWatchers[String(document.id)] = watcher
      watcher.path = document.path
    }
  }

  function destroyDocumentWatcher(documentId) {
    const key = String(documentId)
    const watcher = _documentWatchers[key]
    if (!watcher)
      return
    watcher.destroy()
    delete _documentWatchers[key]
  }

  function handleExternalFileChange(documentId, content) {
    const document = documents.find(doc => doc.id === documentId)
    if (!document || content === document.savedText)
      return
    if (Number(_pendingWritesByPath[document.path] || 0) > 0)
      return
    if (nvimAvailable) {
      if (sendNvimRequest("reload_document", {
          document_id: document.id,
          text: content,
          filename: document.path || document.title || ""
        }))
        return
    }
    if (document.text !== document.savedText) {
      updateDocument(document.id, { savedText: content })
      error = qsTr("This note changed on disk while it has unsaved edits.")
      return
    }
    updateDocument(document.id, { text: content, savedText: content })
  }

  function openFile(url) {
    if (!ready)
      return
    const path = pathFromUrl(url)
    if (!path)
      return
    const existingIndex = documents.findIndex(doc => doc.path === path)
    if (existingIndex >= 0) {
      selectDocument(existingIndex)
      return
    }
    error = ""
    const request = { operation: "read", path: path }
    const fileView = fileOperation.createObject(root, { request: request })
    if (!fileView) {
      error = qsTr("Couldn't open the selected file.")
      console.error("NotesService could not create a file reader for:", path)
      return
    }
    fileView.path = path
  }

  function loadDefaultNote() {
    const request = {
      operation: "default",
      path: root.notesDirectory + "/notes.txt"
    }
    const fileView = fileOperation.createObject(root, { request: request })
    if (!fileView) {
      error = qsTr("Couldn't load the default note.")
      console.error("NotesService could not create the default note reader.")
      return
    }
    fileView.path = request.path
  }

  function saveCurrent(url) {
    const doc = currentDocument
    if (!doc)
      return false
    if (nvimAvailable && saveAfterNvimSync(url, false))
      return true
    return saveDocument(doc.id, url)
  }

  function saveDocument(documentId, url) {
    const doc = documents.find(item => item.id === documentId)
    if (!ready || !doc)
      return false
    const path = url ? pathFromUrl(url) : doc.path
    if (!path)
      return false
    autoSaveTimer.stop()
    error = ""
    adjustPendingWrite("_pendingWritesByDocument", doc.id, 1)
    adjustPendingWrite("_pendingWritesByPath", path, 1)
    if (_autoSaveDocumentId === doc.id)
      _autoSaveDocumentId = -1
    const request = {
      operation: "write",
      documentId: doc.id,
      path: path,
      text: doc.text,
      title: path.split("/").pop()
    }
    const fileView = fileOperation.createObject(root, { request: request })
    if (!fileView) {
      finishWrite(request)
      error = qsTr("Couldn't save the note.")
      console.error("NotesService could not create a file writer for:", path)
      return false
    }
    fileView.path = path
    Qt.callLater(function() { fileView.setText(request.text) })
    return true
  }

  function handleRead(request, content) {
    const existingIndex = documents.findIndex(doc => doc.path === request.path)
    if (existingIndex >= 0) {
      selectDocument(existingIndex)
      return
    }
    const next = documents.slice()
    next.push({
      id: _nextId++,
      title: request.path.split("/").pop(),
      path: request.path,
      text: content || "",
      savedText: content || ""
    })
    documents = next
    currentIndex = next.length - 1
    syncNvimDocument()
    error = ""
  }

  function handleWrite(request) {
    finishWrite(request)
    updateDocument(request.documentId, {
      path: request.path,
      title: request.title,
      savedText: request.text
    })
    if (nvimAvailable && documents.some(doc => doc.id === request.documentId))
      sendNvimRequest("mark_saved", {
        document_id: request.documentId,
        text: request.text
      })
    error = ""
  }

  function handleFileError(request, detail) {
    if (request.operation === "write")
      finishWrite(request)
    error = request.operation === "read"
      ? qsTr("Couldn't open the selected file.")
      : qsTr("Couldn't save the note.")
    console.error("NotesService file operation failed:", request.path, detail)
  }

  function finishWrite(request) {
    if (request.finished)
      return
    request.finished = true
    adjustPendingWrite("_pendingWritesByDocument", request.documentId, -1)
    adjustPendingWrite("_pendingWritesByPath", request.path, -1)
  }

  Component {
    id: fileOperation

    FileView {
      property var request: ({})
      blockLoading: request.operation === "write"
      preload: request.operation === "read" || request.operation === "default"
      atomicWrites: true
      printErrors: true

      onLoaded: {
        if (request.operation === "read" || request.operation === "default") {
          root.handleRead(request, text() || "")
          destroy()
        }
      }

      onSaved: {
        root.handleWrite(request)
        destroy()
      }

      onLoadFailed: function(message) {
        if (request.operation === "default") {
          root.newDocument()
          destroy()
        } else {
          root.handleFileError(request, message)
          destroy()
        }
      }

      onSaveFailed: function(message) {
        root.handleFileError(request, message)
        destroy()
      }
    }
  }

  Component {
    id: documentWatcher

    FileView {
      property int documentId: -1
      property bool initialized: false
      watchChanges: true
      onLoaded: {
        if (initialized)
          root.handleExternalFileChange(documentId, text() || "")
        else
          initialized = true
      }
      onFileChanged: reload()
      onLoadFailed: function(message) {
        if (initialized)
          console.warn("NotesService could not reload externally changed note:", path, message)
        else
          initialized = true
      }
    }
  }

  Component {
    id: chooserProcess

    Process {
      property var requester: null
      property string operation: ""
      property string stage: ""
      property string initialPath: ""

      stdout: StdioCollector {
        id: chooserStdout
        waitForEnd: true
      }
      stderr: StdioCollector {
        id: chooserStderr
        waitForEnd: true
      }

      onExited: function(exitCode) {
        root.handleChooserResult(requester, operation, stage, initialPath, exitCode,
          chooserStdout.text, chooserStderr.text)
        destroy()
      }
    }
  }

  Process {
    id: directoryProcess
    command: [
      "sh", "-c",
      "mkdir -p \"$1\" \"$3\" || exit $?; if [ ! -e \"$1/notes.txt\" ] && [ -f \"$2\" ]; then cp -- \"$2\" \"$1/notes.txt\" || exit $?; fi; if [ ! -e \"$1/notes.txt\" ]; then touch \"$1/notes.txt\" || exit $?; fi",
      "myquickshell-notes", root.notesDirectory, root.legacyNotesPath, root.stateDirectory
    ]
    onExited: function(status) {
      if (status !== 0) {
        root.error = qsTr("Couldn't prepare ~/Documents/notes/.")
        console.error("NotesService failed to prepare notes directory; status:", status)
        return
      }
      root.ready = true
      sessionFile.path = root.sessionPath
    }
  }

  FileView {
    id: sessionFile
    path: ""
    atomicWrites: true

    onLoaded: root.restoreSession(text())
    onLoadFailed: function(message) {
      if (!root.sessionLoaded) {
        if (message)
          console.info("No saved notes session found; starting with the default note.")
        root.restoreSession("")
      }
    }
    onSaveFailed: function(message) {
      root.error = qsTr("Couldn't save the notes session.")
      console.error("NotesService failed to save session state:", message)
    }
  }

  Timer {
    id: sessionSaveTimer
    interval: 300
    repeat: false
    onTriggered: root.saveSession()
  }

  Timer {
    id: autoSaveTimer
    interval: 2000
    repeat: false
    onTriggered: {
      const document = root.documents.find(item => item.id === root._autoSaveDocumentId)
      root._autoSaveDocumentId = -1
      if (SettingsData.notesAutoSave && document && document.path && document.text !== document.savedText)
        root.saveDocument(document.id)
    }
  }

  Timer {
    interval: 300
    running: true
    triggeredOnStart: true
    repeat: false
    onTriggered: directoryProcess.running = true
  }
}
