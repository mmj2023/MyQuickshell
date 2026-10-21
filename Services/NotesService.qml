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
  property int _pendingWrites: 0
  property string error: ""
  property bool ready: false
  property bool sessionLoaded: false
  property bool restoringSession: false
  readonly property var currentDocument: documents.length > currentIndex ? documents[currentIndex] : null
  readonly property string currentText: currentDocument ? currentDocument.text : ""
  readonly property bool currentDirty: currentDocument ? currentDocument.text !== currentDocument.savedText : false
  readonly property bool saving: _pendingWrites > 0

  signal fileChooserFinished(var requester, string operation, int exitCode, string output, string errorOutput)
  signal toggleRequested()

  onDocumentsChanged: scheduleSessionSave()
  onCurrentIndexChanged: scheduleSessionSave()

  IpcHandler {
    target: "notes"

    function toggle(): string {
      root.toggleRequested()
      return "Toggled MyQuickshell notes overlay"
    }
  }

  // Compositor-routed keybind (hyprctl dispatch global quickshell:notes):
  // Hyprland hands the keypress to Quickshell itself, satisfying the
  // popup's "parent window has received input" gate like a bar click does.
  GlobalShortcut {
    appid: "quickshell"
    name: "notes"
    description: "Toggle the MyQuickshell notes overlay"

    onPressed: root.toggleRequested()
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
  }

  function selectDocument(index) {
    if (index < 0 || index >= documents.length)
      return
    currentIndex = index
    error = ""
  }

  function closeDocument(index) {
    if (index < 0 || index >= documents.length)
      return
    if (documents[index].text !== documents[index].savedText) {
      error = qsTr("Save changes before closing this note.")
      return
    }
    const next = documents.slice()
    next.splice(index, 1)
    documents = next
    if (next.length === 0) {
      currentIndex = 0
      newDocument()
    } else if (currentIndex > index) {
      currentIndex--
    } else if (currentIndex >= next.length) {
      currentIndex = next.length - 1
    }
    error = ""
  }

  function editCurrentText(value) {
    const doc = currentDocument
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
    const doc = currentDocument
    if (!doc || !doc.text)
      return
    assignAutoSavePath(doc.id)
    saveDocument(doc.id)
  }

  function updateDocument(id, updates) {
    const next = documents.slice()
    const index = next.findIndex(doc => doc.id === id)
    if (index < 0)
      return
    next[index] = Object.assign({}, next[index], updates)
    documents = next
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
    return saveDocument(currentDocument ? currentDocument.id : -1, url)
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
    _pendingWrites++
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
      _pendingWrites--
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
    error = ""
  }

  function handleWrite(request) {
    _pendingWrites = Math.max(0, _pendingWrites - 1)
    updateDocument(request.documentId, {
      path: request.path,
      title: request.title,
      savedText: request.text
    })
    error = ""
  }

  function handleFileError(request, detail) {
    if (request.operation === "write")
      _pendingWrites = Math.max(0, _pendingWrites - 1)
    error = request.operation === "read"
      ? qsTr("Couldn't open the selected file.")
      : qsTr("Couldn't save the note.")
    console.error("NotesService file operation failed:", request.path, detail)
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
