import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtCore
import Quickshell
import qs.Common
import qs.Modules.Bar.Widgets
import qs.Services

BasePill {
  id: root

  property var barWindow: null
  property var parentScreen: null
  property bool expanded: false
  property bool searchVisible: false
  property bool optionsExpanded: false
  property bool markdownPreview: false
  property string chooserInitialPath: ""

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
    function onFileChooserFinished(requester, operation, exitCode, output, errorOutput) {
      if (requester !== root)
        return
      console.warn("Notes desktop and GTK choosers failed; using Qt Quick FileDialog:",
        String(errorOutput || "").trim() || ("exit status " + exitCode))
      root.fallbackToQtFileDialog(operation, root.chooserInitialPath)
    }
    function onToggleRequested() {
      root.setNotesVisible(!notesPopup.visible)
    }
  }

  onClicked: root.setNotesVisible(!notesPopup.visible)

  function setNotesVisible(openVisible) {
    if (notesPopup.visible === openVisible)
      return
    if (openVisible) {
      // Attach first (no grab); a deferred grab one event-loop pass later
      // fires after the attach completes, so the editor gets keyboard focus
      // on both click and keybind paths.
      notesPopup.visible = true
      Qt.callLater(function() {
        notesPopup.grabFocus = true
        noteEditor.forceActiveFocus()
      })
    } else {
      notesPopup.visible = false
    }
  }

  // IPC/keyboard toggles go through the plain PopupWindow here: grab-based
  // anchoring is what bar-click popups use, keep it consistent.
  PopupWindow {
    id: notesPopup

    readonly property real screenWidth: root.parentScreen ? root.parentScreen.width : Screen.width
    readonly property real screenHeight: root.parentScreen ? root.parentScreen.height : Screen.height

    anchor.window: root.barWindow
    anchor.rect.x: Math.max(8, screenWidth - implicitWidth - 8)
    anchor.rect.y: root.barWindow ? root.barWindow.height + Theme.spaceXS : Theme.spaceXS
    visible: false
    // Open without a grab (the only attach that succeeds from an IPC toggle),
    // then request the keyboard grab AFTER the attach completes -- a deferred
    // one event-loop pass, which PopupWindow 0.3 has no onOpened for.
    //
    // Known quirk (Wayland grab-popup input serial): a client-initiated toggle
    // carries no seat input serial, so after a fresh shell start the keyboard
    // grab is refused ("Failed to create grabbing popup ... parent window has
    // received input") until one real interaction -- clicking the bar button
    // once warms it up, after which every super+shift+n toggle works with
    // full typing focus for the rest of the session. Restarting resets it.
    grabFocus: false
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
              onClicked: root.expanded = !root.expanded
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
              onClicked: notesPopup.visible = false
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
                root.searchVisible = false
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
                  root.searchVisible = false
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
                root.searchVisible = true
                root.optionsExpanded = false
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

                Keys.onEscapePressed: notesPopup.visible = false
                Keys.onPressed: function(event) {
                  if (!(event.modifiers & Qt.ControlModifier))
                    return
                  if (event.key === Qt.Key_S) {
                    root.saveNote()
                    event.accepted = true
                  } else if (event.key === Qt.Key_O) {
                    root.openNote()
                    event.accepted = true
                  } else if (event.key === Qt.Key_N) {
                    root.newNote()
                    event.accepted = true
                  } else if (event.key === Qt.Key_F) {
                    root.searchVisible = true
                    event.accepted = true
                    Qt.callLater(function() { searchField.forceActiveFocus() })
                  } else if (event.key === Qt.Key_M) {
                    root.markdownPreview = !root.markdownPreview
                    event.accepted = true
                  }
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
                        root.markdownPreview = !root.markdownPreview
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
                onClicked: root.optionsExpanded = !root.optionsExpanded
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
            width: parent.width * 0.38
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
            width: parent.width - noteStats.width - parent.spacing
            height: parent.height
            text: NotesService.error !== "" ? NotesService.error
              : (NotesService.saving ? qsTr("Saving…")
                : (NotesService.currentDirty ? qsTr("Unsaved changes")
                  : (NotesService.currentDocument && NotesService.currentDocument.path
                    ? qsTr("Saved") : qsTr("New note — use Save to choose a file"))))
            color: NotesService.error !== "" ? Theme.error
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
