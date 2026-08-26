import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 350
    cardHeight: 430
    dismissOnClickOutside: viewMode === "list"

    function toggle() { visible = !visible }

    IpcHandler {
        target: "note"
        function toggle(): void { root.toggle() }
    }

    property string viewMode: "list" // "list" or "editor"
    property var notesList: []
    property var activeNote: null

    function refreshNotes() {
        fetchProc.running = false
        fetchProc.running = true
    }

    function openNewNote() {
        activeNote = { id: "new", title: "", content: "", isSaved: false }
        titleInput.text = ""
        bodyInput.text = ""
        viewMode = "editor"
        root.resetUndoHistory()
        focusTimer.restart()
    }

    function openEditNote(note) {
        activeNote = note
        titleInput.text = note.title || ""
        bodyInput.text = note.content || ""
        viewMode = "editor"
        root.resetUndoHistory()
        focusTimer.restart()
    }

    function doSaveNote() {
        const noteId = (activeNote && activeNote.id !== "new") ? activeNote.id : ""
        saveProc.command = ["python3", Sys.scriptPath("note_manager.py"), "--save", "--id", noteId, "--title", titleInput.text, "--content", bodyInput.text]
        saveProc.running = false
        saveProc.running = true
    }

    function doSaveDraft() {
        const noteId = (activeNote && activeNote.id !== "new") ? activeNote.id : ""
        saveDraftProc.command = ["python3", Sys.scriptPath("note_manager.py"), "--save-draft", "--id", noteId, "--title", titleInput.text, "--content", bodyInput.text]
        saveDraftProc.running = false
        saveDraftProc.running = true
    }

    function doDeleteNote(noteId) {
        deleteProc.command = ["python3", Sys.scriptPath("note_manager.py"), "--delete", "--id", noteId]
        deleteProc.running = false
        deleteProc.running = true
    }

    // --- UNDO / REDO HISTORY SYSTEM ---
    property var undoStack: []
    property var redoStack: []
    property string lastSavedText: ""
    property int lastSavedCursor: 0
    property bool isUndoRedoAction: false

    Timer {
        id: undoTimer
        interval: 500
        repeat: false
        onTriggered: root.snapshotCurrentState()
    }

    function snapshotCurrentState() {
        if (isUndoRedoAction) return
        const currentText = bodyInput.text
        if (currentText !== lastSavedText) {
            undoStack.push({ text: lastSavedText, cursor: lastSavedCursor })
            if (undoStack.length > 50) undoStack.shift()
            redoStack = []
            lastSavedText = currentText
            lastSavedCursor = bodyInput.cursorPosition
        }
    }

    function resetUndoHistory() {
        undoStack = []
        redoStack = []
        lastSavedText = bodyInput.text
        lastSavedCursor = bodyInput.cursorPosition
    }

    function doUndo() {
        if (undoStack.length === 0) return
        isUndoRedoAction = true
        redoStack.push({ text: bodyInput.text, cursor: bodyInput.cursorPosition })
        const state = undoStack.pop()
        bodyInput.text = state.text
        const targetCursor = Math.max(0, Math.min(state.cursor, bodyInput.text.length))
        bodyInput.cursorPosition = targetCursor
        lastSavedText = bodyInput.text
        lastSavedCursor = targetCursor
        isUndoRedoAction = false
        bodyInput.forceActiveFocus()
    }

    function doRedo() {
        if (redoStack.length === 0) return
        isUndoRedoAction = true
        undoStack.push({ text: bodyInput.text, cursor: bodyInput.cursorPosition })
        const state = redoStack.pop()
        bodyInput.text = state.text
        const targetCursor = Math.max(0, Math.min(state.cursor, bodyInput.text.length))
        bodyInput.cursorPosition = targetCursor
        lastSavedText = bodyInput.text
        lastSavedCursor = targetCursor
        isUndoRedoAction = false
        bodyInput.forceActiveFocus()
    }

    // Timer to release X11 focus and steal active input for NotePopup
    Timer {
        id: focusTimer
        interval: 30
        onTriggered: {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py")])
            if (root.viewMode === "editor") {
                if (titleInput.text === "") {
                    titleInput.forceActiveFocus()
                } else {
                    bodyInput.forceActiveFocus()
                }
            }
        }
    }

    // Fetch notes process
    Process {
        id: fetchProc
        command: ["python3", Sys.scriptPath("note_manager.py"), "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    if (Array.isArray(parsed)) {
                        root.notesList = parsed
                    }
                } catch (e) {
                    root.notesList = []
                }
            }
        }
    }

    // Save permanent note process
    Process {
        id: saveProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.viewMode = "list"
                root.refreshNotes()
            }
        }
    }

    // Save temporary draft process
    Process {
        id: saveDraftProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.viewMode = "list"
                root.refreshNotes()
            }
        }
    }

    // Delete note process
    Process {
        id: deleteProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.viewMode === "editor") {
                    root.viewMode = "list"
                }
                root.refreshNotes()
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            root.viewMode = "list"
            root.refreshNotes()
            focusTimer.restart()
        } else {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--restore"])
        }
    }

    Column {
        anchors.fill: parent
        spacing: 10

        // ================= HEADER =================
        Row {
            width: parent.width
            height: 28

            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: "󱞁"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Note"
                    color: Theme.fg
                    font.pixelSize: 15
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Close button
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24; radius: 12
                color: closeMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: Qt.alpha(Theme.fg, 0.7)
                    font.pixelSize: 12
                }

                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.visible = false
                }
            }
        }

        // ================= VIEW 1: NOTES LIST =================
        Column {
            width: parent.width
            height: parent.height - 38
            spacing: 8
            visible: root.viewMode === "list"

            // "+ Add Note" Button (Centered compact button)
            Rectangle {
                width: 105
                height: 30
                radius: 8
                color: addNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.85) : Theme.accent
                anchors.horizontalCenter: parent.horizontalCenter

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: "+"
                        color: Theme.bg
                        font.pixelSize: 14
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Add Note"
                        color: Theme.bg
                        font.pixelSize: 11
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: addNoteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openNewNote()
                }
            }

            // List of Notes (Cards)
            Rectangle {
                width: parent.width
                height: parent.height - 38
                radius: Sys.moduleRadius
                color: "transparent"
                clip: true

                // Empty state if no notes exist
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: root.notesList.length === 0

                    Text {
                        text: "󱞁"
                        color: Qt.alpha(Theme.fg, 0.3)
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "No notes yet. Click Add Note!"
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.pixelSize: 11
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                Flickable {
                    id: listFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: cardsColumn.height
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: cardsColumn
                        width: listFlick.width
                        spacing: 6

                        Repeater {
                            model: root.notesList

                            delegate: Rectangle {
                                width: cardsColumn.width
                                height: 70
                                radius: 8
                                color: cardMa.containsMouse ? Qt.alpha(Theme.accent, 0.12) : Sys.customModuleBg
                                border.width: 1
                                border.color: cardMa.containsMouse ? Theme.accent : Sys.customModuleBorder

                                MouseArea {
                                    id: cardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openEditNote(modelData)
                                }

                                // Main Content Column
                                Column {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.right: delCardBtn.left
                                    anchors.margins: 10
                                    anchors.rightMargin: 8
                                    spacing: 4

                                    Row {
                                        width: parent.width
                                        spacing: 6

                                        // Status Badge Pill
                                        Rectangle {
                                            height: 16
                                            width: badgeText.implicitWidth + 8
                                            radius: 8
                                            color: modelData.isSaved ? Qt.alpha(Theme.green, 0.18) : Qt.alpha(Theme.yellow, 0.22)
                                            border.width: 1
                                            border.color: modelData.isSaved ? Qt.alpha(Theme.green, 0.4) : Qt.alpha(Theme.yellow, 0.45)
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                id: badgeText
                                                anchors.centerIn: parent
                                                text: modelData.isSaved ? "Saved" : "Draft"
                                                color: modelData.isSaved ? Theme.green : Theme.yellow
                                                font.pixelSize: 9
                                                font.bold: true
                                            }
                                        }

                                        // Note Title
                                        Text {
                                            text: modelData.title || "Untitled Note"
                                            color: Theme.fg
                                            font.pixelSize: 12
                                            font.bold: true
                                            elide: Text.ElideRight
                                            width: parent.width - badgeText.implicitWidth - 8
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    // Content snippet preview
                                    Text {
                                        text: modelData.content ? modelData.content.replace(/<[^>]*>/g, "").replace(/\n/g, " ") : "Empty note..."
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }

                                // Delete / Remove Button (Vertically centered in middle right)
                                Rectangle {
                                    id: delCardBtn
                                    width: 24
                                    height: 24
                                    radius: 6
                                    color: delCardMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : Qt.alpha(Theme.fg, 0.06)
                                    border.width: 1
                                    border.color: delCardMa.containsMouse ? Qt.alpha(Theme.red, 0.4) : Qt.alpha(Theme.fg, 0.12)
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰆴"
                                        color: delCardMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.6)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: delCardMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.doDeleteNote(modelData.id)
                                    }
                                }

                                // Date & Time text (Bottom Right aligned with right edge)
                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 6
                                    spacing: 3

                                    Text {
                                        text: "󰃰"
                                        color: Qt.alpha(Theme.fg, 0.35)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: modelData.updatedAt || ""
                                        color: Qt.alpha(Theme.fg, 0.4)
                                        font.pixelSize: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================= VIEW 2: NOTE EDITOR =================
        Column {
            width: parent.width
            height: parent.height - 38
            spacing: 6
            visible: root.viewMode === "editor"

            // Date & Time info bar at top
            Row {
                width: parent.width
                spacing: 6

                Text {
                    text: "󰃰"
                    color: Qt.alpha(Theme.fg, 0.4)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: (root.activeNote && root.activeNote.updatedAt) ? root.activeNote.updatedAt : "New Note"
                    color: Qt.alpha(Theme.fg, 0.4)
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Title Input Box
            Rectangle {
                width: parent.width
                height: 34
                radius: Sys.moduleRadius
                color: Sys.customModuleBg
                border.width: 1
                border.color: titleInput.activeFocus ? Theme.accent : Sys.customModuleBorder

                TextInput {
                    id: titleInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Theme.fontFamily
                    selectByMouse: true
                    renderType: Text.NativeRendering

                    Keys.onTabPressed: event => {
                        bodyInput.forceActiveFocus()
                        event.accepted = true
                    }

                    Text {
                        text: "Note Title (e.g. Today's Plan)..."
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        visible: !titleInput.text
                        anchors.verticalCenter: parent.verticalCenter
                        renderType: Text.NativeRendering
                    }
                }
            }

            // Body Editor Box WITH INTEGRATED BOTTOM TOOLBAR (No overlay)
            Rectangle {
                width: parent.width
                height: parent.height - 94
                radius: Sys.moduleRadius
                color: Sys.customModuleBg
                border.width: 1
                border.color: bodyInput.activeFocus ? Theme.accent : Sys.customModuleBorder
                clip: true

                Column {
                    anchors.fill: parent

                    // 1. Text Area Flickable
                    Rectangle {
                        width: parent.width
                        height: parent.height
                        color: "transparent"
                        clip: true

                        Flickable {
                            id: bodyFlick
                            anchors.fill: parent
                            anchors.margins: 8
                            contentWidth: width
                            contentHeight: Math.max(height, bodyInput.implicitHeight + 16)
                            boundsBehavior: Flickable.StopAtBounds

                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                onClicked: {
                                    bodyInput.forceActiveFocus()
                                    bodyInput.cursorPosition = bodyInput.length
                                }
                            }

                            TextEdit {
                                id: bodyInput
                                width: bodyFlick.width
                                height: Math.max(bodyFlick.height - 16, implicitHeight)
                                color: Theme.fg
                                font.pixelSize: 13
                                font.family: Theme.fontFamily
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                textFormat: TextEdit.PlainText
                                renderType: Text.NativeRendering

                                onTextChanged: {
                                    if (!root.isUndoRedoAction) {
                                        undoTimer.restart()
                                    }
                                }

                                Keys.onPressed: event => {
                                    if (event.modifiers & Qt.ControlModifier) {
                                        if (event.key === Qt.Key_Z) {
                                            if (event.modifiers & Qt.ShiftModifier) {
                                                root.doRedo()
                                            } else {
                                                root.doUndo()
                                            }
                                            event.accepted = true
                                            return
                                        }
                                        if (event.key === Qt.Key_Y) {
                                            root.doRedo()
                                            event.accepted = true
                                            return
                                        }
                                    }
                                }

                                Text {
                                    text: "Type your note here..."
                                    color: Qt.alpha(Theme.fg, 0.35)
                                    font.pixelSize: 13
                                    visible: !bodyInput.text
                                }
                            }
                        }

                        // Scrollbar for Note Editor inside text area
                        Item {
                            id: noteScrollTrack
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 2
                            width: 6

                            readonly property bool showThumb: bodyFlick.contentHeight > bodyFlick.height

                            Rectangle {
                                id: noteScrollThumb
                                width: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                radius: 2
                                color: Qt.alpha(Theme.accent, 0.6)
                                opacity: noteScrollTrack.showThumb ? 1.0 : 0.0

                                y: {
                                    const maxContentY = bodyFlick.contentHeight - bodyFlick.height
                                    if (maxContentY <= 0) return 0
                                    const ratio = Math.max(0, Math.min(bodyFlick.contentY / maxContentY, 1.0))
                                    return ratio * (noteScrollTrack.height - height)
                                }

                                height: {
                                    if (bodyFlick.contentHeight <= 0) return 20
                                    const ratio = bodyFlick.height / bodyFlick.contentHeight
                                    return Math.max(20, Math.min(noteScrollTrack.height * ratio, noteScrollTrack.height - 6))
                                }
                            }
                        }
                    }
                }
            }

            // 3 BUTTONS FOOTER: Save, Draft, Cancel
            Row {
                width: parent.width
                height: 30
                spacing: 6

                // 1. SAVE BUTTON
                Rectangle {
                    width: (parent.width - 12) / 3
                    height: 30
                    radius: 6
                    color: saveBtnMa.containsMouse ? Qt.alpha(Theme.accent, 0.85) : Theme.accent

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "󰆓"
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }

                        Text {
                            text: "Save"
                            color: Theme.bg
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: saveBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.doSaveNote()
                    }
                }

                // 2. DRAFT BUTTON
                Rectangle {
                    width: (parent.width - 12) / 3
                    height: 30
                    radius: 6
                    color: draftBtnMa.containsMouse ? Qt.alpha(Theme.yellow, 0.25) : Qt.alpha(Theme.yellow, 0.15)
                    border.width: 1
                    border.color: Qt.alpha(Theme.yellow, 0.4)

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "󰏤"
                            color: Theme.yellow
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }

                        Text {
                            text: "Draft"
                            color: Theme.yellow
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: draftBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.doSaveDraft()
                    }
                }

                // 3. CANCEL BUTTON
                Rectangle {
                    width: (parent.width - 12) / 3
                    height: 30
                    radius: 6
                    color: cancelBtnMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                    border.width: 1
                    border.color: Qt.alpha(Theme.fg, 0.15)

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "Cancel"
                            color: Theme.fg
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: cancelBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewMode = "list"
                    }
                }
            }
        }
    }
}
