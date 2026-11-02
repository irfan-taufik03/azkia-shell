import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 360
    cardHeight: 410

    property string currentTab: "clipboard" // "clipboard" or "notes"

    function toggle(tab) {
        if (tab && currentTab !== tab) currentTab = tab
        if (visible && !isClosing) {
            close()
        } else {
            open()
        }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggle("clipboard") }
    }

    IpcHandler {
        target: "note"
        function toggle(): void { root.toggle("notes") }
    }

    // ==========================================
    // CLIPBOARD STATE & LOGIC
    // ==========================================
    property var historyItems: []
    property string searchText: ""
    property int selectedIndex: -1

    readonly property var filteredClips: {
        if (!root.searchText) return root.historyItems
        const q = root.searchText.toLowerCase()
        return root.historyItems.filter(item => {
            const text = (item.text || "").toLowerCase()
            return text.includes(q)
        })
    }

    onFilteredClipsChanged: root.selectedIndex = -1

    Process {
        id: fetchClipProc
        command: ["python3", Sys.scriptPath("clip_daemon.py"), "--get-json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    if (JSON.stringify(parsed) !== JSON.stringify(root.historyItems)) {
                        root.historyItems = parsed
                    }
                } catch (e) {
                    root.historyItems = []
                }
            }
        }
    }

    Timer {
        id: clipPollTimer
        interval: 1500
        running: root.visible && root.currentTab === "clipboard"
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchClipProc.running = true
    }

    function copyItem(itemId) {
        Quickshell.execDetached(["python3", Sys.scriptPath("clip_daemon.py"), "--copy", itemId])
        root.close()
    }

    function deleteClipItem(itemId) {
        Quickshell.execDetached(["python3", Sys.scriptPath("clip_daemon.py"), "--delete", itemId])
        fetchClipTimer.restart()
    }

    function clearAllClips() {
        Quickshell.execDetached(["python3", Sys.scriptPath("clip_daemon.py"), "--clear"])
        root.historyItems = []
    }

    Timer {
        id: fetchClipTimer
        interval: 300
        onTriggered: fetchClipProc.running = true
    }

    // ==========================================
    // NOTES STATE & LOGIC
    // ==========================================
    property string noteViewMode: "list" // "list" or "editor"
    property var notesList: []
    property var activeNote: null
    property int selectedNoteIndex: -1

    onNotesListChanged: {
        if (root.selectedNoteIndex >= root.notesList.length) {
            root.selectedNoteIndex = Math.max(-1, root.notesList.length - 1)
        }
    }

    function refreshNotes() {
        fetchNoteProc.running = false
        fetchNoteProc.running = true
    }

    function openNewNote() {
        activeNote = { id: "new", title: "", content: "", isSaved: false }
        titleInput.text = ""
        bodyInput.text = ""
        noteViewMode = "editor"
        root.resetUndoHistory()
        focusTimer.restart()
    }

    function openEditNote(note) {
        activeNote = note
        titleInput.text = note.title || ""
        bodyInput.text = note.content || ""
        noteViewMode = "editor"
        root.resetUndoHistory()
        focusTimer.restart()
    }

    function doSaveNote() {
        const noteId = (activeNote && activeNote.id !== "new") ? activeNote.id : ""
        saveNoteProc.command = ["python3", Sys.scriptPath("note_manager.py"), "--save", "--id", noteId, "--title", titleInput.text, "--content", bodyInput.text]
        saveNoteProc.running = false
        saveNoteProc.running = true
    }

    function doSaveDraft() {
        const noteId = (activeNote && activeNote.id !== "new") ? activeNote.id : ""
        saveDraftProc.command = ["python3", Sys.scriptPath("note_manager.py"), "--save-draft", "--id", noteId, "--title", titleInput.text, "--content", bodyInput.text]
        saveDraftProc.running = false
        saveDraftProc.running = true
    }

    function doDeleteNote(noteId) {
        deleteNoteProc.command = ["python3", Sys.scriptPath("note_manager.py"), "--delete", "--id", noteId]
        deleteNoteProc.running = false
        deleteNoteProc.running = true
    }

    // --- UNDO / REDO HISTORY FOR NOTES ---
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

    Process {
        id: fetchNoteProc
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

    Process {
        id: saveNoteProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.noteViewMode = "list"
                root.refreshNotes()
            }
        }
    }

    Process {
        id: saveDraftProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.noteViewMode = "list"
                root.refreshNotes()
            }
        }
    }

    Process {
        id: deleteNoteProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.noteViewMode === "editor") {
                    root.noteViewMode = "list"
                }
                root.refreshNotes()
            }
        }
    }

    // ==========================================
    // VISIBILITY & FOCUS LIFECYCLE
    // ==========================================
    onVisibleChanged: {
        if (visible) {
            if (currentTab === "clipboard") {
                root.selectedIndex = -1
                fetchClipProc.running = true
            } else {
                root.selectedNoteIndex = -1
                root.noteViewMode = "list"
                root.refreshNotes()
            }
            focusTimer.restart()
        } else {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--restore"])
            searchInput.text = ""
            root.searchText = ""
        }
    }

    onCurrentTabChanged: {
        if (visible) {
            if (currentTab === "clipboard") {
                root.selectedIndex = -1
                fetchClipProc.running = true
            } else {
                root.selectedNoteIndex = -1
                root.noteViewMode = "list"
                root.refreshNotes()
            }
            focusTimer.restart()
        }
    }

    Timer {
        id: focusTimer
        interval: 30
        onTriggered: {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py")])
            if (root.currentTab === "clipboard") {
                searchInput.forceActiveFocus()
            } else if (root.currentTab === "notes") {
                if (root.noteViewMode === "editor") {
                    if (titleInput.text === "") {
                        titleInput.forceActiveFocus()
                    } else {
                        bodyInput.forceActiveFocus()
                    }
                } else {
                    notesKeyCatcher.forceActiveFocus()
                }
            }
        }
    }

    // ==========================================
    // UI LAYOUT
    // ==========================================
    Item {
        anchors.fill: parent
        anchors.topMargin: -4

        // ===== ROW 1: TAB SELECTOR BAR =====
        Item {
            id: tabBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 52

            Row {
                anchors.fill: parent
                spacing: 8

                // Tab 1: Clipboard
                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 52
                    radius: 12
                    color: clipTabMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent"

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Column {
                        id: clipTabCol
                        anchors.centerIn: parent
                        spacing: 3

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰨸"
                            color: root.currentTab === "clipboard" ? Theme.accent : (clipTabMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.55))
                            font.family: Theme.fontFamily
                            font.pixelSize: 18

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            id: clipTxt
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Clipboard"
                            color: root.currentTab === "clipboard" ? Theme.accent : (clipTabMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.55))
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: root.currentTab === "clipboard"

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        // Active Underline Indicator Bar
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 3
                            width: root.currentTab === "clipboard" ? clipTxt.implicitWidth + 8 : 0
                            radius: 1.5
                            color: Theme.accent
                            opacity: root.currentTab === "clipboard" ? 1 : 0

                            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: clipTabMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = "clipboard"
                    }
                }

                // Tab 2: Notes
                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 52
                    radius: 12
                    color: noteTabMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent"

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Column {
                        id: noteTabCol
                        anchors.centerIn: parent
                        spacing: 3

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󱞁"
                            color: root.currentTab === "notes" ? Theme.accent : (noteTabMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.55))
                            font.family: Theme.fontFamily
                            font.pixelSize: 18

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            id: noteTxt
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Notes"
                            color: root.currentTab === "notes" ? Theme.accent : (noteTabMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.55))
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: root.currentTab === "notes"

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        // Active Underline Indicator Bar
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 3
                            width: root.currentTab === "notes" ? noteTxt.implicitWidth + 8 : 0
                            radius: 1.5
                            color: Theme.accent
                            opacity: root.currentTab === "notes" ? 1 : 0

                            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: noteTabMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = "notes"
                    }
                }
            }
        }

        // ===== CONTENT CONTAINER =====
        Item {
            id: contentContainer
            anchors.top: tabBar.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            // ==========================================
            // TAB 1: CLIPBOARD VIEW
            // ==========================================
            Column {
                id: clipView
                anchors.fill: parent
                spacing: 10
                visible: root.currentTab === "clipboard"

            transform: Translate { id: clipSlide; x: 0 }

            onVisibleChanged: {
                if (visible) {
                    clipSlideXAnim.from = -50
                    clipSlideAnim.restart()
                }
            }

            ParallelAnimation {
                id: clipSlideAnim
                NumberAnimation { id: clipSlideXAnim; target: clipSlide; property: "x"; from: -50; to: 0; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: clipView; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }

            // ===== ROW 2: SEARCH BAR & CLEAR BUTTON =====
            Row {
                width: parent.width
                height: 32
                spacing: 8

                // Search Input Box
                Rectangle {
                    width: parent.width - (clearBtn.visible ? clearBtn.width + 8 : 0)
                    height: 32
                    radius: 14
                    color: Qt.alpha(Theme.fg, 0.06)
                    border.width: 1
                    border.color: searchInput.activeFocus ? Theme.accent : Sys.customModuleBorder

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰍉"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }

                        TextInput {
                            id: searchInput
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 25
                            color: Theme.fg
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            clip: true
                            selectByMouse: true
                            onTextChanged: root.searchText = text.toLowerCase().trim()

                            Keys.onEscapePressed: root.close()

                            Keys.onDownPressed: {
                                if (root.filteredClips.length > 0) {
                                    if (root.selectedIndex < 0) {
                                        root.selectedIndex = 0
                                    } else {
                                        root.selectedIndex = Math.min(root.filteredClips.length - 1, root.selectedIndex + 1)
                                    }
                                }
                            }
                            Keys.onUpPressed: {
                                if (root.filteredClips.length > 0) {
                                    if (root.selectedIndex < 0) {
                                        root.selectedIndex = root.filteredClips.length - 1
                                    } else {
                                        root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                                    }
                                }
                            }
                            Keys.onReturnPressed: {
                                if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredClips.length) {
                                    root.copyItem(root.filteredClips[root.selectedIndex].id)
                                }
                            }
                            Keys.onEnterPressed: {
                                if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredClips.length) {
                                    root.copyItem(root.filteredClips[root.selectedIndex].id)
                                }
                            }
                            Keys.onDeletePressed: {
                                if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredClips.length) {
                                    root.deleteClipItem(root.filteredClips[root.selectedIndex].id)
                                }
                            }

                            Text {
                                text: "Search clipboard..."
                                color: Qt.alpha(Theme.fg, 0.35)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                visible: !searchInput.text
                            }
                        }
                    }
                }

                // Clear All Button
                Rectangle {
                    id: clearBtn
                    height: 32
                    width: clearRow.implicitWidth + 14
                    radius: 14
                    color: clearMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : Qt.alpha(Theme.fg, 0.08)
                    border.width: 1
                    border.color: clearMa.containsMouse ? Qt.alpha(Theme.red, 0.5) : Sys.customModuleBorder
                    visible: root.filteredClips.length > 0

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: clearRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: Theme.red
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clear"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: clearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearAllClips()
                    }
                }
            }

            // ===== CLIPBOARD LIST VIEW CONTAINER =====
            Item {
                width: parent.width
                height: parent.height - 42

                ListView {
                    id: listView
                    anchors.fill: parent
                    clip: true
                    spacing: 6
                    currentIndex: root.selectedIndex
                    model: root.filteredClips

                    // Empty state
                    Item {
                        anchors.fill: parent
                        visible: root.filteredClips.length === 0

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰨸"
                                color: Qt.alpha(Theme.fg, 0.25)
                                font.family: Theme.fontFamily
                                font.pixelSize: 28
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Clipboard is empty"
                                color: Qt.alpha(Theme.fg, 0.35)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }
                    }

                    delegate: Rectangle {
                        id: itemDelegate
                        required property var modelData
                        required property int index

                        readonly property bool isKeyboardSelected: (root.selectedIndex >= 0) && (index === root.selectedIndex)
                        readonly property bool isHovered: itemMa.containsMouse

                        width: ListView.view.width
                        height: Math.max(48, contentCol.implicitHeight + 16)
                        radius: 14
                        color: isKeyboardSelected ? Theme.accent : (isHovered ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                        border.width: 1
                        border.color: (isKeyboardSelected || isHovered) ? Theme.accent : Sys.customModuleBorder

                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        MouseArea {
                            id: itemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.selectedIndex = index
                                root.copyItem(modelData.id)
                            }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 6
                                color: isKeyboardSelected ? Sys.customBarBg : Qt.alpha(Theme.fg, 0.08)
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    id: imgPrev
                                    anchors.fill: parent
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                    mipmap: true
                                    sourceSize: Qt.size(64, 64)
                                    source: (modelData.type === "image" && modelData.image_path) ? "file://" + modelData.image_path : ""
                                    visible: false
                                }

                                Rectangle {
                                    id: imgMask
                                    anchors.fill: parent
                                    radius: 6
                                    color: "black"
                                    visible: false
                                    antialiasing: true
                                }

                                OpacityMask {
                                    anchors.fill: parent
                                    source: imgPrev
                                    maskSource: imgMask
                                    visible: modelData.type === "image" && imgPrev.status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.type === "image" ? "󰋩" : "󰅍"
                                    color: isKeyboardSelected ? Theme.accent : (modelData.type === "image" ? Theme.cyan : Qt.alpha(Theme.fg, 0.5))
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    visible: modelData.type !== "image" || imgPrev.status !== Image.Ready
                                }
                            }

                            Column {
                                id: contentCol
                                width: parent.width - 74
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Text {
                                    width: parent.width
                                    text: modelData.preview || modelData.text || "Empty"
                                    color: isKeyboardSelected ? Sys.customBarBg : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.time || ""
                                    color: isKeyboardSelected ? Qt.alpha(Sys.customBarBg, 0.75) : Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                color: deleteMa.containsMouse ? Qt.alpha(Theme.red, 0.2) : "transparent"
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: deleteMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.4)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    id: deleteMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.deleteClipItem(modelData.id)
                                }
                            }
                        }
                    }
                }

                // Scrollbar
                Item {
                    id: scrollTrack
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 20

                    readonly property bool isScrolling: listView.moving || listView.flicking || listView.dragging
                    readonly property bool showThumb: isScrolling || scrollMa.containsMouse || scrollMa.pressed

                    MouseArea {
                        id: scrollMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeVerCursor

                        onPressed: (mouse) => updatePosition(mouse.y)
                        onPositionChanged: (mouse) => {
                            if (pressed) updatePosition(mouse.y)
                        }

                        function updatePosition(mouseY) {
                            const trackH = scrollTrack.height
                            const thumbH = scrollThumb.height
                            if (trackH <= thumbH) return
                            const maxThumbY = trackH - thumbH
                            const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                            const ratio = clampedY / maxThumbY
                            const maxContentY = listView.contentHeight - listView.height
                            if (maxContentY > 0) {
                                listView.contentY = ratio * maxContentY
                            }
                        }
                    }

                    Rectangle {
                        id: scrollThumb
                        anchors.right: parent.right
                        anchors.rightMargin: 3
                        width: 10
                        height: 36
                        y: {
                            const maxContentY = listView.contentHeight - listView.height
                            const maxThumbY = scrollTrack.height - height
                            if (maxContentY > 0 && maxThumbY > 0) {
                                return Math.max(0, Math.min((listView.contentY / maxContentY) * maxThumbY, maxThumbY))
                            }
                            return 0
                        }
                        radius: 5
                        color: scrollMa.pressed ? Qt.alpha(Theme.accent, 0.7) : (scrollMa.containsMouse ? Qt.alpha(Theme.fg, 0.40) : Qt.alpha(Theme.fg, 0.20))
                        opacity: (listView.contentHeight > listView.height && scrollTrack.showThumb) ? 1.0 : 0.0

                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }
        }

        // ==========================================
        // TAB 2: NOTES VIEW
        // ==========================================
        Item {
            id: notesView
            anchors.fill: parent
            visible: root.currentTab === "notes"

            transform: Translate { id: noteSlide; x: 0 }

            onVisibleChanged: {
                if (visible) {
                    noteSlideXAnim.from = 50
                    noteSlideAnim.restart()
                }
            }

            ParallelAnimation {
                id: noteSlideAnim
                NumberAnimation { id: noteSlideXAnim; target: noteSlide; property: "x"; from: 50; to: 0; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: notesView; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }

            // ----- NOTES LIST VIEW -----
            Item {
                id: notesKeyCatcher
                anchors.fill: parent
                focus: true

                Keys.onDownPressed: {
                    if (root.notesList.length > 0) {
                        if (root.selectedNoteIndex < 0) {
                            root.selectedNoteIndex = 0
                        } else {
                            root.selectedNoteIndex = Math.min(root.notesList.length - 1, root.selectedNoteIndex + 1)
                        }
                    }
                }
                Keys.onUpPressed: {
                    if (root.notesList.length > 0) {
                        if (root.selectedNoteIndex < 0) {
                            root.selectedNoteIndex = root.notesList.length - 1
                        } else {
                            root.selectedNoteIndex = Math.max(0, root.selectedNoteIndex - 1)
                        }
                    }
                }
                Keys.onReturnPressed: {
                    if (root.selectedNoteIndex >= 0 && root.selectedNoteIndex < root.notesList.length) {
                        root.openEditNote(root.notesList[root.selectedNoteIndex])
                    }
                }
                Keys.onEnterPressed: {
                    if (root.selectedNoteIndex >= 0 && root.selectedNoteIndex < root.notesList.length) {
                        root.openEditNote(root.notesList[root.selectedNoteIndex])
                    }
                }
                Keys.onDeletePressed: {
                    if (root.selectedNoteIndex >= 0 && root.selectedNoteIndex < root.notesList.length) {
                        root.doDeleteNote(root.notesList[root.selectedNoteIndex].id)
                    }
                }
                Keys.onBackPressed: {
                    if (root.selectedNoteIndex >= 0 && root.selectedNoteIndex < root.notesList.length) {
                        root.doDeleteNote(root.notesList[root.selectedNoteIndex].id)
                    }
                }
            }

            Column {
                width: parent.width
                height: parent.height
                spacing: 8
                visible: root.noteViewMode === "list"

                // ROW 2: SUB-HEADER ("My Notes" + "+ Add Note" Button)
                Item {
                    width: parent.width
                    height: 32

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "My Notes"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 1
                            font.bold: true
                        }

                        Rectangle {
                            height: 18
                            width: Math.max(18, noteCountTxt.implicitWidth + 8)
                            radius: 9
                            color: Qt.alpha(Theme.accent, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.notesList.length > 0

                            Text {
                                id: noteCountTxt
                                anchors.centerIn: parent
                                text: root.notesList.length
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 32
                        width: addNoteRow.implicitWidth + 14
                        radius: 14
                        color: addNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: addNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.5) : Sys.customModuleBorder

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            id: addNoteRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "+"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Add Note"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
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
                }

                // CARDS LIST CONTAINER
                Rectangle {
                    width: parent.width
                    height: parent.height - 40
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

                        Connections {
                            target: root
                            function onSelectedNoteIndexChanged() {
                                const itemY = root.selectedNoteIndex * 88
                                if (itemY < listFlick.contentY) {
                                    listFlick.contentY = itemY
                                } else if (itemY + 82 > listFlick.contentY + listFlick.height) {
                                    listFlick.contentY = itemY + 82 - listFlick.height
                                }
                            }
                        }

                        Column {
                            id: cardsColumn
                            width: listFlick.width
                            spacing: 6

                            Repeater {
                                model: root.notesList

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    readonly property bool isKeyboardSelected: (root.selectedNoteIndex >= 0) && (index === root.selectedNoteIndex)
                                    readonly property bool isHovered: cardMa.containsMouse

                                    width: cardsColumn.width
                                    height: 82
                                    radius: 14
                                    color: isKeyboardSelected ? Theme.accent : (isHovered ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                                    border.width: 1
                                    border.color: (isKeyboardSelected || isHovered) ? Theme.accent : Sys.customModuleBorder

                                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                    MouseArea {
                                        id: cardMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                             root.selectedNoteIndex = index
                                             root.openEditNote(modelData)
                                        }
                                    }

                                    Column {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.right: delCardBtn.left
                                        anchors.leftMargin: 12
                                        anchors.topMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 5

                                        Row {
                                            width: parent.width
                                            spacing: 6

                                            Rectangle {
                                                height: 16
                                                width: badgeText.implicitWidth + 8
                                                radius: 8
                                                color: isKeyboardSelected ? Sys.customBarBg : (modelData.isSaved ? Qt.alpha(Theme.green, 0.18) : Qt.alpha(Theme.yellow, 0.22))
                                                border.width: 1
                                                border.color: isKeyboardSelected ? Sys.customBarBg : (modelData.isSaved ? Qt.alpha(Theme.green, 0.4) : Qt.alpha(Theme.yellow, 0.45))
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

                                            Text {
                                                text: modelData.title || "Untitled Note"
                                                color: isKeyboardSelected ? Sys.customBarBg : Theme.fg
                                                font.pixelSize: 12
                                                font.bold: true
                                                elide: Text.ElideRight
                                                width: parent.width - badgeText.implicitWidth - 8
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Text {
                                            text: modelData.content ? modelData.content.replace(/<[^>]*>/g, "").replace(/\n/g, " ") : "Empty note..."
                                            color: isKeyboardSelected ? Qt.alpha(Sys.customBarBg, 0.8) : Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                    }

                                    Rectangle {
                                        id: delCardBtn
                                        width: 24
                                        height: 24
                                        radius: 6
                                        color: Sys.customBarBg
                                        border.width: 1
                                        border.color: delCardMa.containsMouse ? Qt.alpha(Theme.red, 0.4) : Qt.alpha(Theme.accent, 0.2)
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.top: parent.top
                                        anchors.topMargin: 10

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰆴"
                                            color: delCardMa.containsMouse ? Theme.red : Theme.accent
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

                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 8
                                        spacing: 4

                                        Text {
                                            text: "󰃰"
                                            color: isKeyboardSelected ? Qt.alpha(Sys.customBarBg, 0.8) : Qt.alpha(Theme.fg, 0.6)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: modelData.updatedAt || ""
                                            color: isKeyboardSelected ? Sys.customBarBg : Qt.alpha(Theme.fg, 0.7)
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

            // ----- NOTE EDITOR -----
            Column {
                width: parent.width
                height: parent.height
                spacing: 6
                visible: root.noteViewMode === "editor"

                Row {
                    width: parent.width
                    height: 16
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
                    radius: 14
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
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.bg
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

                // Body Editor Box
                Rectangle {
                    width: parent.width
                    height: parent.height - 98
                    radius: 14
                    color: Sys.customModuleBg
                    border.width: 1
                    border.color: bodyInput.activeFocus ? Theme.accent : Sys.customModuleBorder
                    clip: true

                    Column {
                        anchors.fill: parent

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
                                    selectionColor: Theme.accent
                                    selectedTextColor: Theme.bg
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

                            // Scrollbar for Note Editor
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
                        radius: 14
                        color: saveBtnMa.containsMouse ? Qt.alpha(Theme.accent, 0.85) : Theme.accent

                        Row {
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰆓"
                                color: Theme.bg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Save"
                                color: Theme.bg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
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
                        radius: 14
                        color: draftBtnMa.containsMouse ? Qt.alpha(Theme.yellow, 0.25) : Qt.alpha(Theme.yellow, 0.15)
                        border.width: 1
                        border.color: Qt.alpha(Theme.yellow, 0.4)

                        Row {
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰏤"
                                color: Theme.yellow
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Draft"
                                color: Theme.yellow
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
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
                        radius: 14
                        color: cancelBtnMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.15)

                        Row {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Cancel"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: cancelBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.noteViewMode = "list"
                        }
                    }
                }
            }
        }
    }
}
}


