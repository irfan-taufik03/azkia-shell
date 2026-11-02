import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Window {
    id: root

    property var modelData
    title: "Azkia PDF"
    width: 960
    height: 840
    minimumWidth: 700
    minimumHeight: 600
    color: Sys.customBarBg
    visible: false

    // State management
    property var tabs: []                  // [{ isHome, path, filename, page_count, current_page, zoom, rotation, current_img, total_pages }]
    property int activeTabIndex: -1
    property var recents: []
    property int focusedRecentIndex: 0
    property bool isFullscreen: false
    property bool isPresentation: false
    property bool sidebarVisible: true
    property bool toolbarVisible: true
    property bool findBarVisible: false
    property string searchQuery: ""
    property var searchResults: []
    property int currentSearchIndex: 0
    property int totalSearchMatches: 0
    property bool isLoadingPage: false
    property string thumbDir: ""
    property string fileHash: (activeDoc && activeDoc.file_hash) ? activeDoc.file_hash : ""
    property bool isProgrammaticScroll: false
    property int renderRevision: 0
    property real panOffsetX: 0

    // Explicit reactive properties
    property string currentImgPath: ""
    property int currentPage: 1
    property int totalPages: 1
    property real currentZoom: 1.25
    property int currentRotation: 0
    property int activeBucket: 100
    readonly property int targetBucket: root.currentZoom <= 1.35 ? 100 : (root.currentZoom <= 1.85 ? 150 : (root.currentZoom <= 2.35 ? 200 : 300))

    // Interaction Mode & Text Selection
    property string interactionMode: "pan" // "pan" (default) or "select"
    property int selectedPageNum: -1
    property int selectionStartIdx: -1
    property int selectionEndIdx: -1
    property string selectedText: ""
    property bool isSelecting: false
    readonly property bool hasSelection: selectedText.length > 0 && selectedPageNum > 0

    property real dragStartX: 0
    property real dragStartY: 0

    function clearSelection() {
        selectedPageNum = -1
        selectionStartIdx = -1
        selectionEndIdx = -1
        selectedText = ""
        isSelecting = false
    }

    function copySelectedText() {
        if (!selectedText || selectedText.length === 0) return
        Quickshell.execDetached(["python3", Sys.scriptPath("azkia_pdf.py"), "--copy-text", selectedText])
    }

    Timer {
        id: bucketRenderTimer
        interval: 150
        repeat: false
        onTriggered: {
            let doc = root.activeDoc
            if (!doc || doc.isHome || !doc.path) return
            renderDocProc.command = [
                "python3",
                Sys.scriptPath("azkia_pdf.py"),
                "--render-all-pages",
                doc.path,
                root.currentRotation.toString(),
                root.targetBucket.toString()
            ]
            renderDocProc.running = false
            renderDocProc.running = true
        }
    }

    onTargetBucketChanged: {
        bucketRenderTimer.restart()
    }

    readonly property var activeDoc: (activeTabIndex >= 0 && activeTabIndex < tabs.length) ? tabs[activeTabIndex] : null
    readonly property bool isHomeActive: (activeDoc === null)

    Component.onCompleted: {
        root.showHome()
    }

    onActiveChanged: {
        if (active) {
            windowCard.forceActiveFocus()
        }
    }

    onVisibleChanged: {
        if (visible) {
            windowCard.forceActiveFocus()
            loadSavedState()
            if (root.tabs.length === 0) {
                root.showHome()
            }
        }
    }

    function closeWindow() {
        if (root.isPresentation) {
            root.isPresentation = false
            return
        }
        root.tabs = []
        root.showHome()
        visible = false
    }

    onClosing: (close) => {
        close.accepted = false
        root.closeWindow()
    }

    function toggle() {
        if (visible) {
            root.closeWindow()
        } else {
            root.openWindow()
        }
    }

    function openWindow() {
        visible = true
        root.requestActivate()
        windowCard.forceActiveFocus()
        loadSavedState()
        if (root.tabs.length === 0) {
            root.showHome()
        }
    }

    // ================= IPC HANDLER =================
    IpcHandler {
        target: "pdf"
        function toggle(): void { root.toggle() }
        function open(): void { root.openWindow() }
        function showHome(): void {
            root.openWindow()
            root.showHome()
        }
        function openFile(filePath: string): void {
            root.openWindow()
            if (filePath && filePath.length > 0) {
                root.openDocument(filePath)
            }
        }
        function close(): void { root.closeWindow() }
    }

    IpcHandler {
        target: "azkiapdf"
        function toggle(): void { root.toggle() }
        function open(): void { root.openWindow() }
        function openFile(filePath: string): void {
            root.openWindow()
            if (filePath && filePath.length > 0) {
                root.openDocument(filePath)
            }
        }
        function close(): void { root.closeWindow() }
    }

    IpcHandler {
        target: "docviewer"
        function toggle(): void { root.toggle() }
        function open(): void { root.openWindow() }
        function openFile(filePath: string): void {
            root.openWindow()
            if (filePath && filePath.length > 0) {
                root.openDocument(filePath)
            }
        }
        function close(): void { root.closeWindow() }
    }

    // ================= SHORTCUTS =================
    Shortcut {
        sequences: ["Escape"]
        enabled: root.visible
        onActivated: {
            if (root.hasSelection) {
                root.clearSelection()
            } else if (root.isPresentation) {
                root.isPresentation = false
            } else if (root.findBarVisible) {
                root.findBarVisible = false
            } else if (root.isFullscreen) {
                root.toggleFullscreen()
            } else {
                root.closeWindow()
            }
        }
    }

    Shortcut {
        sequences: ["Ctrl+T"]
        enabled: root.visible
        onActivated: root.showHome()
    }

    Shortcut {
        sequences: ["Ctrl+O"]
        enabled: root.visible
        onActivated: root.openFileDialog()
    }

    Shortcut {
        sequences: ["Ctrl+W"]
        enabled: root.visible && root.activeTabIndex >= 0
        onActivated: root.closeTab(root.activeTabIndex)
    }

    Shortcut {
        sequences: ["Ctrl+F"]
        enabled: root.visible && !root.isHomeActive && root.activeDoc !== null
        onActivated: root.toggleFindBar()
    }

    Shortcut {
        sequences: ["Right", "PageDown", "Space"]
        enabled: root.visible && !root.isHomeActive && !pageInput.activeFocus && !searchInput.activeFocus
        onActivated: root.nextPage()
    }

    Shortcut {
        sequences: ["Left", "PageUp"]
        enabled: root.visible && !root.isHomeActive && !pageInput.activeFocus && !searchInput.activeFocus
        onActivated: root.prevPage()
    }

    // --- HOME RECENT FILES SHORTCUTS ---
    Shortcut {
        sequences: ["Down"]
        enabled: root.visible && root.isHomeActive && root.recents.length > 0
        onActivated: {
            if (root.focusedRecentIndex < root.recents.length - 1) {
                root.focusedRecentIndex++
            }
            if (typeof recentListView !== "undefined" && recentListView) {
                recentListView.positionViewAtIndex(root.focusedRecentIndex, ListView.Contain)
            }
        }
    }

    Shortcut {
        sequences: ["Up"]
        enabled: root.visible && root.isHomeActive && root.recents.length > 0
        onActivated: {
            if (root.focusedRecentIndex > 0) {
                root.focusedRecentIndex--
            }
            if (typeof recentListView !== "undefined" && recentListView) {
                recentListView.positionViewAtIndex(root.focusedRecentIndex, ListView.Contain)
            }
        }
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: root.visible && root.isHomeActive && root.recents.length > 0
        onActivated: {
            if (root.focusedRecentIndex >= 0 && root.focusedRecentIndex < root.recents.length) {
                let item = root.recents[root.focusedRecentIndex]
                let p = (typeof item === "object" && item.path) ? item.path : item
                root.openDocument(p)
            }
        }
    }

    Shortcut {
        sequences: ["Ctrl++", "Ctrl+="]
        enabled: root.visible && !root.isHomeActive
        onActivated: root.zoomIn()
    }

    Shortcut {
        sequences: ["Ctrl+-"]
        enabled: root.visible && !root.isHomeActive
        onActivated: root.zoomOut()
    }

    Shortcut {
        sequences: ["Ctrl+0"]
        enabled: root.visible && !root.isHomeActive
        onActivated: root.resetZoom()
    }

    Shortcut {
        sequences: ["Ctrl+C"]
        enabled: root.visible && root.hasSelection && !pageInput.activeFocus && !searchInput.activeFocus
        onActivated: root.copySelectedText()
    }

    Shortcut {
        sequences: ["Ctrl+R"]
        enabled: root.visible && !root.isHomeActive
        onActivated: root.rotateRight()
    }

    Shortcut {
        sequences: ["Ctrl+Shift+R"]
        enabled: root.visible && !root.isHomeActive
        onActivated: root.rotateLeft()
    }

    Shortcut {
        sequences: ["F11"]
        enabled: root.visible
        onActivated: root.toggleFullscreen()
    }

    Shortcut {
        sequences: ["Ctrl+H"]
        enabled: root.visible && !root.isHomeActive
        onActivated: root.toolbarVisible = !root.toolbarVisible
    }

    Shortcut {
        sequences: ["Ctrl+B", "F9"]
        enabled: root.visible && !root.isHomeActive && !pageInput.activeFocus && !searchInput.activeFocus
        onActivated: root.sidebarVisible = !root.sidebarVisible
    }

    Shortcut {
        sequences: ["F5", "P"]
        enabled: root.visible && !root.isHomeActive && root.activeDoc !== null && !pageInput.activeFocus && !searchInput.activeFocus
        onActivated: root.togglePresentation()
    }

    Shortcut {
        sequences: ["Ctrl+Tab"]
        enabled: root.visible && root.tabs.length > 1
        onActivated: {
            let next = (root.activeTabIndex + 1) % root.tabs.length
            root.switchTab(next)
        }
    }

    Shortcut {
        sequences: ["H"]
        enabled: root.visible && !root.isHomeActive && root.activeDoc !== null && !pageInput.activeFocus && !searchInput.activeFocus
        onActivated: {
            root.interactionMode = "pan"
            root.clearSelection()
        }
    }

    Shortcut {
        sequences: ["S", "V"]
        enabled: root.visible && !root.isHomeActive && root.activeDoc !== null && !pageInput.activeFocus && !searchInput.activeFocus
        onActivated: {
            root.interactionMode = "select"
        }
    }

    // ================= PROCESSES & ACTIONS =================
    Process {
        id: renderThumbsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let res = JSON.parse(text)
                    if (res && res.status === "ok") {
                        let doc = root.activeDoc
                        if (doc) {
                            doc.thumb_dir = res.thumb_dir || ""
                        }
                        root.thumbDir = res.thumb_dir || ""
                        root.renderRevision++
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: renderDocProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoadingPage = false
                root.activeBucket = root.targetBucket
                root.renderRevision++
            }
        }
    }

    Process {
        id: fileDialogProc
        command: ["python3", Sys.scriptPath("azkia_pdf.py"), "--select-file"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let res = JSON.parse(text)
                    if (res.action === "file_selected" && res.path) {
                        root.handleFileOpened(res.path, res.info)
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: docInfoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let info = JSON.parse(text)
                    if (info && !info.error) {
                        root.handleFileOpened(info.path, info)
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let res = JSON.parse(text)
                    if (res && res.results) {
                        root.searchResults = res.results
                        root.totalSearchMatches = res.total_matches || 0
                        root.currentSearchIndex = res.total_matches > 0 ? 1 : 0
                        if (res.results.length > 0) {
                            root.jumpToPage(res.results[0].page)
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: stateProc
        command: ["python3", Sys.scriptPath("azkia_pdf.py"), "--get-state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let st = JSON.parse(text)
                    if (st && st.recents) {
                        root.recents = st.recents
                        if (root.focusedRecentIndex >= root.recents.length) {
                            root.focusedRecentIndex = 0
                        }
                    }
                } catch (e) {}
            }
        }
    }

    function loadSavedState() {
        stateProc.command = ["python3", Sys.scriptPath("azkia_pdf.py"), "--get-state"]
        stateProc.running = false
        stateProc.running = true
    }

    function showHome() {
        root.activeTabIndex = -1
        root.currentPage = 0
        root.totalPages = 0
        root.currentZoom = 1.0
        root.currentRotation = 0
        root.activeBucket = 100
        root.currentImgPath = ""
        root.panOffsetX = 0
        root.isLoadingPage = false
        root.focusedRecentIndex = 0
        root.interactionMode = "pan"
        root.clearSelection()
        loadSavedState()
    }

    function ensureHomeTab() {
        if (root.tabs.length === 0) {
            root.showHome()
        }
    }

    function openFileDialog() {
        fileDialogProc.running = false
        fileDialogProc.running = true
    }

    function openDocument(filePath) {
        if (!filePath || filePath.length === 0) return
        docInfoProc.command = ["python3", Sys.scriptPath("azkia_pdf.py"), "--info", filePath]
        docInfoProc.running = false
        docInfoProc.running = true
    }

    function handleFileOpened(filePath, info) {
        let existingIdx = -1
        for (let i = 0; i < root.tabs.length; i++) {
            if (root.tabs[i].path === filePath) {
                existingIdx = i
                break
            }
        }

        if (existingIdx >= 0) {
            let doc = root.tabs[existingIdx]
            doc.page_count = info.page_count || doc.page_count || 1
            doc.pages = (info.pages && info.pages.length > 0) ? info.pages : doc.pages
            doc.current_img = info.initial_img || doc.current_img || ""
            doc.thumb_dir = info.thumb_dir || doc.thumb_dir || ""
            doc.file_hash = info.file_hash || doc.file_hash || ""
            let newTabs = root.tabs.slice()
            newTabs[existingIdx] = doc
            root.tabs = newTabs
            root.switchTab(existingIdx)

            renderDocProc.command = [
                "python3",
                Sys.scriptPath("azkia_pdf.py"),
                "--render-all-pages",
                filePath,
                (doc.rotation || 0).toString(),
                (root.activeBucket || 100).toString()
            ]
            renderDocProc.running = false
            renderDocProc.running = true

            renderThumbsProc.command = ["python3", Sys.scriptPath("azkia_pdf.py"), "--render-thumbs", filePath]
            renderThumbsProc.running = false
            renderThumbsProc.running = true
            return
        }

        let doc = {
            path: filePath,
            filename: info.filename || filePath.split('/').pop(),
            page_count: info.page_count || 1,
            current_page: 1,
            zoom: 1.25,
            rotation: 0,
            pages: info.pages || [],
            current_img: info.initial_img || "",
            thumb_dir: info.thumb_dir || "",
            file_hash: info.file_hash || ""
        }

        let newTabs = root.tabs.slice()
        newTabs.push(doc)
        root.tabs = newTabs
        root.activeBucket = 100
        root.switchTab(newTabs.length - 1)

        // Render all pages in parallel in background for crisp continuous reading
        renderDocProc.command = [
            "python3",
            Sys.scriptPath("azkia_pdf.py"),
            "--render-all-pages",
            filePath,
            "0",
            "100"
        ]
        renderDocProc.running = false
        renderDocProc.running = true

        // Render thumbnails in background
        renderThumbsProc.command = ["python3", Sys.scriptPath("azkia_pdf.py"), "--render-thumbs", filePath]
        renderThumbsProc.running = false
        renderThumbsProc.running = true
    }

    function switchTab(index) {
        if (index < 0 || index >= root.tabs.length) {
            showHome()
            return
        }
        root.activeTabIndex = index
        let doc = root.tabs[index]
        if (!doc) return

        root.currentPage = doc.current_page || 1
        root.totalPages = doc.page_count || 1
        root.currentZoom = doc.zoom || 1.25
        root.currentRotation = doc.rotation || 0
        root.thumbDir = doc.thumb_dir || ""
        root.currentImgPath = doc.current_img || ""

        if (!doc.thumb_dir && doc.path) {
            renderThumbsProc.command = ["python3", Sys.scriptPath("azkia_pdf.py"), "--render-thumbs", doc.path]
            renderThumbsProc.running = false
            renderThumbsProc.running = true
        }

        if (typeof pageListView !== "undefined" && pageListView) {
            pageListView.positionViewAtIndex(Math.max(0, (doc.current_page || 1) - 1), ListView.Beginning)
        }
    }

    function closeTab(index) {
        if (index < 0 || index >= root.tabs.length) return
        let wasActive = (root.activeTabIndex === index)
        let newTabs = root.tabs.slice()
        newTabs.splice(index, 1)
        root.tabs = newTabs

        if (newTabs.length === 0) {
            root.showHome()
        } else if (wasActive) {
            let nextIdx = Math.min(index, newTabs.length - 1)
            root.switchTab(nextIdx)
        } else if (root.activeTabIndex > index) {
            root.activeTabIndex--
        }
    }

    function nextPage() {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        if (root.currentPage < doc.page_count) {
            jumpToPage(root.currentPage + 1)
        }
    }

    function prevPage() {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        if (root.currentPage > 1) {
            jumpToPage(root.currentPage - 1)
        }
    }

    function jumpToPage(targetPage) {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        let p = Math.max(1, Math.min(doc.page_count, parseInt(targetPage) || 1))
        root.isProgrammaticScroll = true
        root.currentPage = p
        doc.current_page = p
        if (typeof pageListView !== "undefined" && pageListView) {
            pageListView.positionViewAtIndex(p - 1, ListView.Beginning)
        }
        resetProgScrollTimer.restart()
    }

    Timer {
        id: resetProgScrollTimer
        interval: 350
        repeat: false
        onTriggered: root.isProgrammaticScroll = false
    }

    function setZoom(newZoom) {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        let clamped = Math.round(Math.max(0.4, Math.min(3.0, newZoom)) * 100) / 100
        root.currentZoom = clamped
        doc.zoom = clamped
    }

    function zoomIn() {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        let newZoom = Math.min(3.0, Math.round(((doc.zoom || 1.25) + 0.25) * 100) / 100)
        root.currentZoom = newZoom
        doc.zoom = newZoom
    }

    function zoomOut() {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        let newZoom = Math.max(0.4, Math.round(((doc.zoom || 1.25) - 0.25) * 100) / 100)
        root.currentZoom = newZoom
        doc.zoom = newZoom
    }

    function resetZoom() {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        root.currentZoom = 1.0
        doc.zoom = 1.0
    }

    function fitWidth() {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        let availW = viewportCard.width - 60
        let baseW = 595.0
        if (doc.pages && doc.pages[doc.current_page - 1]) {
            baseW = doc.pages[doc.current_page - 1].width || 595.0
        }
        if (doc.rotation % 180 !== 0) {
            if (doc.pages && doc.pages[doc.current_page - 1]) {
                baseW = doc.pages[doc.current_page - 1].height || 842.0
            }
        }
        let calcZoom = Math.round(Math.max(0.4, Math.min(3.0, availW / baseW)) * 100) / 100
        root.currentZoom = calcZoom
        doc.zoom = calcZoom
    }

    function fitPage() {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        let availH = viewportCard.height - 40
        let baseH = 842.0
        if (doc.pages && doc.pages[doc.current_page - 1]) {
            baseH = doc.pages[doc.current_page - 1].height || 842.0
        }
        if (doc.rotation % 180 !== 0) {
            if (doc.pages && doc.pages[doc.current_page - 1]) {
                baseH = doc.pages[doc.current_page - 1].width || 595.0
            }
        }
        let calcZoom = Math.round(Math.max(0.3, Math.min(2.5, availH / baseH)) * 100) / 100
        root.currentZoom = calcZoom
        doc.zoom = calcZoom
    }

    function rotateRight() {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        let newRot = ((doc.rotation || 0) + 90) % 360
        doc.rotation = newRot
        root.currentRotation = newRot
        renderDocProc.command = [
            "python3",
            Sys.scriptPath("azkia_pdf.py"),
            "--render-all-pages",
            doc.path,
            newRot.toString(),
            root.targetBucket.toString()
        ]
        renderDocProc.running = false
        renderDocProc.running = true
    }

    function rotateLeft() {
        let doc = root.activeDoc
        if (!doc || doc.isHome) return
        let newRot = ((doc.rotation || 0) + 270) % 360
        doc.rotation = newRot
        root.currentRotation = newRot
        renderDocProc.command = [
            "python3",
            Sys.scriptPath("azkia_pdf.py"),
            "--render-all-pages",
            doc.path,
            newRot.toString(),
            root.targetBucket.toString()
        ]
        renderDocProc.running = false
        renderDocProc.running = true
    }

    function toggleFindBar() {
        if (root.isHomeActive) return
        root.findBarVisible = !root.findBarVisible
        if (root.findBarVisible) {
            searchInput.forceActiveFocus()
        } else {
            windowCard.forceActiveFocus()
        }
    }

    function executeSearch(query) {
        let doc = root.activeDoc
        if (!doc || doc.isHome || !query || query.trim() === "") {
            root.searchResults = []
            root.totalSearchMatches = 0
            return
        }
        root.searchQuery = query.trim()
        searchProc.command = ["python3", Sys.scriptPath("azkia_pdf.py"), "--search", doc.path, query.trim()]
        searchProc.running = false
        searchProc.running = true
    }

    function nextMatch() {
        if (root.searchResults.length === 0) return
        let nextIdx = (root.currentSearchIndex % root.searchResults.length)
        root.currentSearchIndex = nextIdx + 1
        root.jumpToPage(root.searchResults[nextIdx].page)
    }

    function prevMatch() {
        if (root.searchResults.length === 0) return
        let prevIdx = (root.currentSearchIndex - 2 + root.searchResults.length) % root.searchResults.length
        root.currentSearchIndex = prevIdx + 1
        root.jumpToPage(root.searchResults[prevIdx].page)
    }

    function toggleFullscreen() {
        root.isFullscreen = !root.isFullscreen
        if (root.isFullscreen) {
            root.visibility = Window.FullScreen
        } else {
            root.visibility = Window.Windowed
        }
    }

    function togglePresentation() {
        if (root.isHomeActive) return
        root.isPresentation = !root.isPresentation
        if (root.isPresentation) {
            root.visibility = Window.FullScreen
            fitPage()
        } else {
            if (!root.isFullscreen) {
                root.visibility = Window.Windowed
            }
        }
    }

    // ================= MAIN WINDOW CARD =================
    Rectangle {
        id: windowCard
        anchors.fill: parent
        color: Sys.customBarBg
        radius: root.isFullscreen || root.isPresentation ? 0 : Theme.windowRadius
        border.width: root.isFullscreen || root.isPresentation ? 0 : 0.5
        border.color: Theme.altbg
        clip: true
        focus: true

        TapHandler {
            onTapped: windowCard.forceActiveFocus()
        }

        DropArea {
            anchors.fill: parent
            onDropped: drop => {
                if (drop.hasUrls) {
                    for (let i = 0; i < drop.urls.length; i++) {
                        let path = drop.urls[i].toString()
                        if (path.startsWith("file://")) {
                            path = decodeURIComponent(path.substring(7))
                        }
                        root.openDocument(path)
                    }
                }
            }
        }

        // ================= 1. HEADER BAR (BAGIAN ATAS) =================
        Rectangle {
            id: headerBar
            width: parent.width
            height: 30
            anchors.top: parent.top
            anchors.topMargin: root.isPresentation ? 0 : 10
            color: "transparent"
            visible: !root.isPresentation

            // Left Header: Azkia PDF Button (Navigates to Home / Recent Files)
            Item {
                id: leftHeader
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 30
                width: leftHeaderRow.implicitWidth

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: -4
                    anchors.rightMargin: -4
                    radius: 8
                    color: homeBtnMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                }

                Row {
                    id: leftHeaderRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Azkia PDF SVG Icon
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        source: "file://" + Sys.configDir + "/assets/azkia-pdf.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    // Azkia PDF App Title
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Azkia PDF"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                    }
                }

                MouseArea {
                    id: homeBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showHome()
                }

                ToolTip {
                    visible: homeBtnMa.containsMouse
                    delay: 250
                    text: "Home & Recent Files (Ctrl+T)"
                    contentItem: Text {
                        text: "Home & Recent Files (Ctrl+T)"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: 11
                    }
                    background: Rectangle {
                        color: Qt.alpha(Theme.bg, 0.95)
                        border.color: Qt.alpha(Theme.fg, 0.2)
                        border.width: 1
                        radius: 6
                    }
                }
            }

            // --- DOCUMENT TABS ---
            Item {
                id: tabsContainer
                anchors.left: leftHeader.right
                anchors.leftMargin: 14
                anchors.right: windowControlsRow.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 30
                clip: true

                Flickable {
                    anchors.fill: parent
                    contentWidth: tabsRow.width
                    contentHeight: parent.height
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick

                    Row {
                        id: tabsRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Repeater {
                            model: root.tabs

                            Rectangle {
                                id: tabRect
                                required property var modelData
                                required property int index

                                readonly property bool isActive: root.activeTabIndex === index
                                readonly property int maxTabWidth: 230
                                readonly property int nonTextWidth: 62 // leftMargin(10) + icon(14) + spacing(6) + spacing(6) + close(18) + rightMargin(8)
                                readonly property int maxLabelWidth: maxTabWidth - nonTextWidth
                                readonly property int labelWidth: Math.min(maxLabelWidth, tabLabel.implicitWidth)

                                width: labelWidth + nonTextWidth
                                height: 30
                                radius: 10
                                color: isActive ? (tabMa.containsMouse ? Theme.accentHover : Theme.accent) : (tabMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.07))
                                border.width: 1
                                border.color: isActive ? (tabMa.containsMouse ? Theme.accentHover : Theme.accent) : (tabMa.containsMouse ? Qt.alpha(Theme.fg, 0.25) : Qt.alpha(Theme.fg, 0.12))

                                // Main Tab Click Area (underneath Row and Close button)
                                MouseArea {
                                    id: tabMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.switchTab(index)
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    z: 2

                                    // Document Icon
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰈔"
                                        color: isActive ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }

                                    // Tab Label
                                    Text {
                                        id: tabLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: tabRect.labelWidth
                                        text: modelData.filename || "PDF Document"
                                        color: isActive ? Theme.bg : Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideMiddle
                                    }

                                    // Close Tab Button (×)
                                    Rectangle {
                                        id: closeBtn
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: closeTabMa.containsMouse ? Qt.alpha(isActive ? Theme.bg : Theme.fg, 0.25) : "transparent"
                                        anchors.verticalCenter: parent.verticalCenter
                                        z: 10

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: isActive ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                                        }

                                        MouseArea {
                                            id: closeTabMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: (mouse) => {
                                                mouse.accepted = true
                                                root.closeTab(index)
                                            }
                                        }
                                    }
                                }

                                ToolTip {
                                    visible: tabMa.containsMouse && (tabLabel.implicitWidth > tabRect.maxLabelWidth)
                                    delay: 300
                                    text: modelData.filename || ""
                                    contentItem: Text {
                                        text: modelData.filename || ""
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    background: Rectangle {
                                        color: Qt.alpha(Theme.bg, 0.95)
                                        border.color: Qt.alpha(Theme.fg, 0.2)
                                        border.width: 1
                                        radius: 6
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Window Controls (Right side: Toggle Toolbar & Close)
            Row {
                id: windowControlsRow
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Toggle Toolbar button (Arrow up if show, arrow down if hide)
                Rectangle {
                    width: 30
                    height: 30
                    radius: Theme.buttonRadius
                    color: tbToggleMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : "transparent"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.isHomeActive && !root.isPresentation

                    Text {
                        anchors.centerIn: parent
                        text: root.toolbarVisible ? "󰅃" : "󰅀"
                        color: tbToggleMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                    }

                    MouseArea {
                        id: tbToggleMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toolbarVisible = !root.toolbarVisible
                    }

                    ToolTip {
                        visible: tbToggleMa.containsMouse
                        delay: 250
                        text: root.toolbarVisible ? "Hide Toolbar (Ctrl+H)" : "Show Toolbar (Ctrl+H)"
                        contentItem: Text {
                            text: tbToggleMa.containsMouse ? (root.toolbarVisible ? "Hide Toolbar (Ctrl+H)" : "Show Toolbar (Ctrl+H)") : ""
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: 11
                        }
                        background: Rectangle {
                            color: Qt.alpha(Theme.bg, 0.95)
                            border.color: Qt.alpha(Theme.fg, 0.2)
                            border.width: 1
                            radius: 6
                        }
                    }
                }

                // Close button
                Rectangle {
                    width: 30
                    height: 30
                    radius: Theme.buttonRadius
                    color: closeMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        color: closeMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeWindow()
                    }
                }
            }
        }


        // ================= MAIN CONTENT COLUMN =================
        Column {
            anchors.top: root.isPresentation ? parent.top : headerBar.bottom
            anchors.topMargin: root.isPresentation ? 0 : 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.isPresentation ? 0 : 12
            anchors.left: parent.left
            anchors.leftMargin: root.isPresentation ? 0 : 12
            anchors.right: parent.right
            anchors.rightMargin: root.isPresentation ? 0 : 12
            spacing: 12

            // ================= 2. CARD UNTUK TOOLBAR (Muncul saat aktif di dokumen PDF) =================
            Rectangle {
                id: toolbarCard
                width: parent.width
                height: 52
                radius: Theme.cardRadius
                color: Qt.alpha(Theme.fg, 0.05)
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.15)
                visible: !root.isPresentation && !root.isHomeActive && root.toolbarVisible

                // Left Toolbar Controls
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // 0. TOGGLE SIDEBAR (Thumbnails)
                    ToolbarButton {
                        iconText: ""
                        tooltipText: root.sidebarVisible ? "Hide Sidebar" : "Show Sidebar"
                        enabled: !root.isHomeActive && root.activeDoc !== null
                        onClicked: root.sidebarVisible = !root.sidebarVisible
                    }

                    ToolbarSeparator {}

                    // 1. OPEN FILE (nf-fa-folder_open_o)
                    ToolbarButton {
                        iconText: ""
                        tooltipText: "Open PDF / Document (Ctrl+O)"
                        onClicked: root.openFileDialog()
                    }

                    ToolbarSeparator {}

                    // 2. FIT PAGE (bagian kiri)
                    ToolbarButton {
                        isFitPageIcon: true
                        tooltipText: "Fit Entire Page"
                        enabled: !root.isHomeActive && root.activeDoc !== null
                        onClicked: root.fitPage()
                    }

                    // 3. FIT WIDTH (bagian kanan)
                    ToolbarButton {
                        isFitWidthIcon: true
                        tooltipText: "Fit Width"
                        enabled: !root.isHomeActive && root.activeDoc !== null
                        onClicked: root.fitWidth()
                    }

                    ToolbarSeparator {}

                    // 4. FIND
                    ToolbarButton {
                        iconText: "󰍉"
                        tooltipText: "Find in Document (Ctrl+F)"
                        isActive: root.findBarVisible
                        enabled: !root.isHomeActive && root.activeDoc !== null
                        onClicked: root.toggleFindBar()
                    }

                    // 5. ROTATE LEFT
                    ToolbarButton {
                        iconText: "󰑥"
                        tooltipText: "Rotate Left 90° (Ctrl+Shift+R)"
                        enabled: !root.isHomeActive && root.activeDoc !== null
                        onClicked: root.rotateLeft()
                    }

                    // 6. ROTATE RIGHT
                    ToolbarButton {
                        iconText: "󰑧"
                        tooltipText: "Rotate Right 90° (Ctrl+R)"
                        enabled: !root.isHomeActive && root.activeDoc !== null
                        onClicked: root.rotateRight()
                    }

                    ToolbarSeparator {}

                    // 7. TOOL MODE CARD (Pan & Select in 1 card)
                    Rectangle {
                        height: 34
                        width: toolModeRow.implicitWidth + 8
                        radius: 10
                        color: Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.12)
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: (!root.isHomeActive && root.activeDoc !== null) ? 1.0 : 0.35

                        Row {
                            id: toolModeRow
                            anchors.centerIn: parent
                            spacing: 4

                            // Pan Tool (Hand)
                            Rectangle {
                                width: panItemRow.implicitWidth + 14
                                height: 26
                                radius: 7
                                color: root.interactionMode === "pan" ? Theme.accent : (panToolMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent")
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    id: panItemRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: ""
                                        color: root.interactionMode === "pan" ? Theme.bg : (panToolMa.containsMouse ? Theme.accent : Theme.fg)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Pan"
                                        color: root.interactionMode === "pan" ? Theme.bg : (panToolMa.containsMouse ? Theme.accent : Theme.fg)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    id: panToolMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: (!root.isHomeActive && root.activeDoc !== null) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!root.isHomeActive && root.activeDoc !== null) {
                                            root.interactionMode = "pan"
                                            root.clearSelection()
                                        }
                                    }
                                }

                                ToolTip {
                                    visible: panToolMa.containsMouse
                                    delay: 250
                                    text: "Pan Mode (Drag to scroll)"
                                    contentItem: Text {
                                        text: "Pan Mode (Drag to scroll)"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    background: Rectangle {
                                        color: Qt.alpha(Theme.bg, 0.95)
                                        border.color: Qt.alpha(Theme.fg, 0.2)
                                        border.width: 1
                                        radius: 6
                                    }
                                }
                            }

                            // Select Tool (Text cursor)
                            Rectangle {
                                width: selectItemRow.implicitWidth + 14
                                height: 26
                                radius: 7
                                color: root.interactionMode === "select" ? Theme.accent : (selectToolMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent")
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    id: selectItemRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰅪"
                                        color: root.interactionMode === "select" ? Theme.bg : (selectToolMa.containsMouse ? Theme.accent : Theme.fg)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Select"
                                        color: root.interactionMode === "select" ? Theme.bg : (selectToolMa.containsMouse ? Theme.accent : Theme.fg)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    id: selectToolMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: (!root.isHomeActive && root.activeDoc !== null) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!root.isHomeActive && root.activeDoc !== null) {
                                            root.interactionMode = "select"
                                        }
                                    }
                                }

                                ToolTip {
                                    visible: selectToolMa.containsMouse
                                    delay: 250
                                    text: "Select Mode (Drag to select text)"
                                    contentItem: Text {
                                        text: "Select Mode (Drag to select text)"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    background: Rectangle {
                                        color: Qt.alpha(Theme.bg, 0.95)
                                        border.color: Qt.alpha(Theme.fg, 0.2)
                                        border.width: 1
                                        radius: 6
                                    }
                                }
                            }
                        }
                    }

                    ToolbarSeparator {}

                    // 7. ZOOM CONTROLS CARD (Zoom Out -> Slider Bar -> Zoom In -> Percentage)
                    Rectangle {
                        height: 34
                        width: zoomRow.implicitWidth + 18
                        radius: 10
                        color: Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.12)
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: (!root.isHomeActive && root.activeDoc !== null) ? 1.0 : 0.35

                        Row {
                            id: zoomRow
                            anchors.centerIn: parent
                            spacing: 6

                            // Zoom Out (-)
                            Rectangle {
                                width: 24
                                height: 24
                                radius: 6
                                color: zoomOutMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : "transparent"
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "-"
                                    color: zoomOutMa.containsMouse ? Theme.accent : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    font.bold: true
                                }

                                MouseArea {
                                    id: zoomOutMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: (!root.isHomeActive && root.activeDoc !== null) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!root.isHomeActive && root.activeDoc !== null) root.zoomOut()
                                    }
                                }

                                ToolTip {
                                    visible: zoomOutMa.containsMouse
                                    delay: 250
                                    text: "Zoom Out (Ctrl+-)"
                                    contentItem: Text {
                                        text: "Zoom Out (Ctrl+-)"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    background: Rectangle {
                                        color: Qt.alpha(Theme.bg, 0.95)
                                        border.color: Qt.alpha(Theme.fg, 0.2)
                                        border.width: 1
                                        radius: 6
                                    }
                                }
                            }

                            // Zoom Slider Track (Volume Bar Style)
                            Item {
                                width: 76
                                height: 24
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    id: zoomTrack
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: 5
                                    radius: 2.5
                                    color: Qt.alpha(Theme.fg, 0.18)

                                    Rectangle {
                                        width: Math.max(0, Math.min(parent.width, parent.width * Math.max(0.0, Math.min(1.0, (root.currentZoom - 0.4) / (3.0 - 0.4)))))
                                        height: parent.height
                                        radius: 2.5
                                        color: (zoomSliderMa.containsMouse || zoomSliderMa.pressed) ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                                    }

                                    Rectangle {
                                        x: Math.max(0, Math.min(parent.width - width, (parent.width * Math.max(0.0, Math.min(1.0, (root.currentZoom - 0.4) / (3.0 - 0.4)))) - width / 2))
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 11
                                        height: 11
                                        radius: 5.5
                                        color: zoomSliderMa.pressed ? Theme.accent : (zoomSliderMa.containsMouse ? Qt.lighter(Theme.fg, 1.2) : Theme.fg)
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.bg, 0.6)
                                    }
                                }

                                MouseArea {
                                    id: zoomSliderMa
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: (!root.isHomeActive && root.activeDoc !== null) ? Qt.PointingHandCursor : Qt.ArrowCursor

                                    function updateFromMouse(mouseX) {
                                        if (root.isHomeActive || !root.activeDoc) return
                                        let trackX = mouseX - 4
                                        let ratio = Math.max(0.0, Math.min(1.0, trackX / zoomTrack.width))
                                        let target = 0.4 + (ratio * (3.0 - 0.4))
                                        target = Math.round(target * 20) / 20
                                        root.setZoom(target)
                                    }

                                    onPressed: (mouse) => updateFromMouse(mouse.x)
                                    onPositionChanged: (mouse) => {
                                        if (pressed) updateFromMouse(mouse.x)
                                    }
                                }
                            }

                            // Zoom In (+)
                            Rectangle {
                                width: 24
                                height: 24
                                radius: 6
                                color: zoomInMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : "transparent"
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: zoomInMa.containsMouse ? Theme.accent : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    font.bold: true
                                }

                                MouseArea {
                                    id: zoomInMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: (!root.isHomeActive && root.activeDoc !== null) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!root.isHomeActive && root.activeDoc !== null) root.zoomIn()
                                    }
                                }

                                ToolTip {
                                    visible: zoomInMa.containsMouse
                                    delay: 250
                                    text: "Zoom In (Ctrl++)"
                                    contentItem: Text {
                                        text: "Zoom In (Ctrl++)"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    background: Rectangle {
                                        color: Qt.alpha(Theme.bg, 0.95)
                                        border.color: Qt.alpha(Theme.fg, 0.2)
                                        border.width: 1
                                        radius: 6
                                    }
                                }
                            }

                            // Percentage Label (Reset to 100% on click)
                            Rectangle {
                                width: Math.max(38, zoomPctText.implicitWidth + 8)
                                height: 24
                                radius: 6
                                color: zoomPctMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    id: zoomPctText
                                    anchors.centerIn: parent
                                    text: Math.round(root.currentZoom * 100) + "%"
                                    color: zoomPctMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.85)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                MouseArea {
                                    id: zoomPctMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: (!root.isHomeActive && root.activeDoc !== null) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!root.isHomeActive && root.activeDoc !== null) root.resetZoom()
                                    }
                                }

                                ToolTip {
                                    visible: zoomPctMa.containsMouse
                                    delay: 250
                                    text: "Reset Zoom to 100% (Ctrl+0)"
                                    contentItem: Text {
                                        text: "Reset Zoom to 100% (Ctrl+0)"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    background: Rectangle {
                                        color: Qt.alpha(Theme.bg, 0.95)
                                        border.color: Qt.alpha(Theme.fg, 0.2)
                                        border.width: 1
                                        radius: 6
                                    }
                                }
                            }
                        }
                    }
                }

                // Right Toolbar Controls (Presentation, Fullscreen, Page Navigation Card)
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // 12. PRESENTATION (Play icon)
                    ToolbarButton {
                        iconText: "󰐊"
                        tooltipText: "Presentation Mode (F5)"
                        enabled: !root.isHomeActive && root.activeDoc !== null
                        onClicked: root.togglePresentation()
                    }

                    // 13. FULLSCREEN
                    ToolbarButton {
                        iconText: root.isFullscreen ? "󰊔" : "󰊓"
                        tooltipText: "Toggle Fullscreen (F11)"
                        onClicked: root.toggleFullscreen()
                    }

                    ToolbarSeparator {}

                    // PAGE NAVIGATION CARD (Page -> Prev -> Current -> of Total -> Next)
                    Rectangle {
                        height: 34
                        width: pageNavRow.implicitWidth + 20
                        radius: 10
                        color: Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.12)
                        anchors.verticalCenter: parent.verticalCenter

                        Row {
                            id: pageNavRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "Page"
                                color: Qt.alpha(Theme.fg, 0.7)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Prev Page Button (←)
                            Rectangle {
                                width: 24
                                height: 24
                                radius: 6
                                color: prevPageMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : "transparent"
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: (!root.isHomeActive && root.activeDoc !== null && root.currentPage > 1) ? 1.0 : 0.35

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰁍"
                                    color: prevPageMa.containsMouse ? Theme.accent : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: prevPageMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: (!root.isHomeActive && root.activeDoc !== null && root.currentPage > 1) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!root.isHomeActive && root.activeDoc !== null && root.currentPage > 1) {
                                            root.prevPage()
                                        }
                                    }
                                }

                                ToolTip {
                                    visible: prevPageMa.containsMouse
                                    delay: 250
                                    text: "Previous Page (Left / PageUp)"
                                    contentItem: Text {
                                        text: "Previous Page (Left / PageUp)"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    background: Rectangle {
                                        color: Qt.alpha(Theme.bg, 0.95)
                                        border.color: Qt.alpha(Theme.fg, 0.2)
                                        border.width: 1
                                        radius: 6
                                    }
                                }
                            }

                            // Current Page Input Box
                            Rectangle {
                                width: Math.max(30, pageInput.implicitWidth + 12)
                                height: 24
                                radius: 6
                                color: Qt.alpha(Theme.bg, 0.6)
                                border.width: 1
                                border.color: pageInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.2)
                                anchors.verticalCenter: parent.verticalCenter

                                TextInput {
                                    id: pageInput
                                    anchors.centerIn: parent
                                    text: root.currentPage.toString()
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    horizontalAlignment: TextInput.AlignHCenter
                                    selectByMouse: true
                                    validator: IntValidator { bottom: 1; top: Math.max(1, root.totalPages) }
                                    onAccepted: {
                                        root.jumpToPage(parseInt(pageInput.text) || 1)
                                        windowCard.forceActiveFocus()
                                    }
                                }
                            }

                            Text {
                                text: "of " + root.totalPages
                                color: Qt.alpha(Theme.fg, 0.7)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Next Page Button (→)
                            Rectangle {
                                width: 24
                                height: 24
                                radius: 6
                                color: nextPageMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : "transparent"
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: (!root.isHomeActive && root.activeDoc !== null && root.currentPage < root.totalPages) ? 1.0 : 0.35

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰁔"
                                    color: nextPageMa.containsMouse ? Theme.accent : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: nextPageMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: (!root.isHomeActive && root.activeDoc !== null && root.currentPage < root.totalPages) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!root.isHomeActive && root.activeDoc !== null && root.currentPage < root.totalPages) {
                                            root.nextPage()
                                        }
                                    }
                                }

                                ToolTip {
                                    visible: nextPageMa.containsMouse
                                    delay: 250
                                    text: "Next Page (Right / PageDown)"
                                    contentItem: Text {
                                        text: "Next Page (Right / PageDown)"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    background: Rectangle {
                                        color: Qt.alpha(Theme.bg, 0.95)
                                        border.color: Qt.alpha(Theme.fg, 0.2)
                                        border.width: 1
                                        radius: 6
                                    }
                                }
                            }
                        }
                    }
                }
            }


            // ================= FIND BAR OVERLAY =================
            Rectangle {
                id: findBar
                width: parent.width
                height: 44
                radius: Theme.subCardRadius
                color: Qt.alpha(Theme.bg, 0.9)
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.4)
                visible: root.findBarVisible && !root.isPresentation && !root.isHomeActive

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "󰍉"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: 240
                        height: 30
                        radius: 8
                        color: Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: searchInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.2)
                        anchors.verticalCenter: parent.verticalCenter

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            selectByMouse: true
                            onTextChanged: root.executeSearch(text)
                            onAccepted: root.nextMatch()
                            Keys.onEscapePressed: {
                                root.findBarVisible = false
                                windowCard.forceActiveFocus()
                            }
                        }
                    }

                    Text {
                        text: root.totalSearchMatches > 0 ? (root.currentSearchIndex + " of " + root.totalSearchMatches + " matches") : (searchInput.text.length > 0 ? "No matches" : "")
                        color: Qt.alpha(Theme.fg, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    ToolbarButton {
                        iconText: "󰁍"
                        tooltipText: "Previous Match"
                        enabled: root.totalSearchMatches > 0
                        onClicked: root.prevMatch()
                    }

                    ToolbarButton {
                        iconText: "󰁔"
                        tooltipText: "Next Match"
                        enabled: root.totalSearchMatches > 0
                        onClicked: root.nextMatch()
                    }

                    Item { Layout.fillWidth: true; width: 10 }

                    ToolbarButton {
                        iconText: "󰅖"
                        tooltipText: "Close Find (Esc)"
                        onClicked: root.findBarVisible = false
                    }
                }
            }


            // ================= 3. DOCUMENT / SIDEBAR BODY CONTAINER =================
            Item {
                id: bodyContainer
                width: parent.width
                height: root.isPresentation ? parent.height : (root.isHomeActive ? (parent.height - (findBar.visible ? findBar.height + 12 : 0)) : (parent.height - (toolbarCard.visible ? toolbarCard.height + 12 : 0) - (findBar.visible ? findBar.height + 12 : 0)))

                // --- SIDEBAR CARD (PAGE THUMBNAILS) ---
                Rectangle {
                    id: sidebarCard
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    width: 200
                    radius: root.isPresentation ? 0 : Theme.cardRadius
                    color: root.isPresentation ? "#111217" : Qt.alpha(Theme.fg, 0.05)
                    border.width: root.isPresentation ? 0 : 1
                    border.color: root.isPresentation ? "transparent" : Qt.alpha(Theme.fg, 0.15)
                    visible: root.sidebarVisible && !root.isPresentation && !root.isHomeActive && root.activeDoc !== null
                    clip: true

                    // Sidebar Header
                    Rectangle {
                        id: thumbHeader
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 38
                        color: "transparent"

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                text: "󱒋"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Pages (" + root.totalPages + ")"
                                color: Qt.alpha(Theme.fg, 0.75)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Close sidebar button
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: 5
                            color: closeSbMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: closeSbMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            MouseArea {
                                id: closeSbMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sidebarVisible = false
                            }
                        }

                        // Bottom line under header
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Qt.alpha(Theme.fg, 0.08)
                        }
                    }

                    // Thumbnails ListView
                    ListView {
                        id: thumbListView
                        anchors.top: thumbHeader.bottom
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.totalPages

                        Timer {
                            id: thumbScrollTimer
                            interval: 1200
                            repeat: false
                        }

                        onContentYChanged: {
                            thumbScrollTimer.restart()
                        }

                        WheelHandler {
                            target: thumbListView
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                            onWheel: (event) => {
                                let deltaY = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y * 0.75)
                                let maxY = Math.max(0, thumbListView.contentHeight - thumbListView.height)
                                if (maxY > 0) {
                                    thumbListView.contentY = Math.max(0, Math.min(maxY, thumbListView.contentY - deltaY))
                                    thumbScrollTimer.restart()
                                    event.accepted = true
                                }
                            }
                        }

                        Connections {
                            target: root
                            function onCurrentPageChanged() {
                                if (root.currentPage > 0 && root.currentPage <= root.totalPages) {
                                    thumbListView.positionViewAtIndex(root.currentPage - 1, ListView.Contain)
                                }
                            }
                        }

                        delegate: Item {
                            id: thumbItem
                            readonly property int pageNum: index + 1
                            readonly property bool isCurrent: (pageNum === root.currentPage)
                            readonly property string thumbPath: (root.thumbDir !== "") ? ("file://" + root.thumbDir + "/thumb_p" + pageNum + ".png") : ((root.activeDoc && root.activeDoc.thumb_dir) ? ("file://" + root.activeDoc.thumb_dir + "/thumb_p" + pageNum + ".png") : "")

                            width: ListView.view.width
                            height: thumbCard.height + 22

                            Column {
                                anchors.fill: parent
                                spacing: 4
                                anchors.horizontalCenter: parent.horizontalCenter

                                // Thumbnail Card
                                Rectangle {
                                    id: thumbCard
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(parent.width, 148)
                                    height: Math.round(width * 1.35)
                                    radius: 6
                                    color: isCurrent ? Qt.alpha(Theme.accent, 0.12) : (thumbMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : Qt.alpha(Theme.fg, 0.03))
                                    border.width: isCurrent ? 2 : 1
                                    border.color: isCurrent ? Theme.accent : (thumbMa.containsMouse ? Qt.alpha(Theme.accent, 0.5) : Qt.alpha(Theme.fg, 0.15))

                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    // White page preview background
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width - 8
                                        height: parent.height - 8
                                        radius: 2
                                        color: "#ffffff"

                                        Image {
                                            id: thumbImg
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            source: {
                                                let rev = root.renderRevision
                                                return thumbItem.thumbPath
                                            }
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                            asynchronous: true
                                            cache: false

                                            onStatusChanged: {
                                                if (status === Image.Error && thumbRetryTimer) {
                                                    thumbRetryTimer.restart()
                                                }
                                            }

                                            Timer {
                                                id: thumbRetryTimer
                                                interval: 150
                                                repeat: false
                                                onTriggered: {
                                                    if (thumbImg.status !== Image.Ready) {
                                                        let s = thumbImg.source
                                                        thumbImg.source = ""
                                                        thumbImg.source = s
                                                    }
                                                }
                                            }

                                            Connections {
                                                target: root
                                                function onRenderRevisionChanged() {
                                                    if (thumbImg.status !== Image.Ready) {
                                                        let s = thumbImg.source
                                                        thumbImg.source = ""
                                                        thumbImg.source = s
                                                    }
                                                }
                                            }

                                            // Fallback while loading
                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰈔"
                                                color: Qt.alpha("#000000", 0.25)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 24
                                                visible: thumbImg.status !== Image.Ready
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: thumbMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.jumpToPage(thumbItem.pageNum)
                                        }
                                    }
                                }

                                // Page Number Pill
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: thumbItem.pageNum.toString()
                                    color: thumbItem.isCurrent ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: thumbItem.isCurrent
                                }
                            }
                        }
                    }

                    // Floating Scrollbar Thumb for Sidebar (Launcher style)
                    Item {
                        id: thumbScrollTrack
                        anchors.right: parent.right
                        anchors.top: thumbHeader.bottom
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 4
                        anchors.bottomMargin: 4
                        width: 16
                        z: 100

                        readonly property bool isScrolling: thumbScrollTimer.running || thumbListView.moving || thumbListView.flicking || thumbListView.dragging
                        readonly property bool showThumb: isScrolling || thumbScrollMa.containsMouse || thumbScrollMa.pressed

                        MouseArea {
                            id: thumbScrollMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeVerCursor

                            onPressed: (mouse) => updatePosition(mouse.y)
                            onPositionChanged: (mouse) => {
                                if (pressed) updatePosition(mouse.y)
                            }

                            function updatePosition(mouseY) {
                                const trackH = thumbScrollTrack.height
                                const thumbH = thumbScrollThumb.height
                                if (trackH <= thumbH) return
                                const maxThumbY = trackH - thumbH
                                const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                                const ratio = clampedY / maxThumbY
                                const maxContentY = thumbListView.contentHeight - thumbListView.height
                                if (maxContentY > 0) {
                                    thumbListView.contentY = ratio * maxContentY
                                    thumbScrollTimer.restart()
                                }
                            }
                        }

                        Rectangle {
                            id: thumbScrollThumb
                            anchors.right: parent.right
                            anchors.rightMargin: 3
                            width: (thumbScrollMa.containsMouse || thumbScrollMa.pressed) ? 8 : 5
                            height: {
                                if (thumbListView.contentHeight <= thumbListView.height) return 36
                                return Math.max(28, Math.min(thumbScrollTrack.height * (thumbListView.height / Math.max(1, thumbListView.contentHeight)), thumbScrollTrack.height - 16))
                            }
                            y: {
                                const maxContentY = thumbListView.contentHeight - thumbListView.height
                                const maxThumbY = thumbScrollTrack.height - height
                                if (maxContentY > 0 && maxThumbY > 0) {
                                    return Math.max(0, Math.min((thumbListView.contentY / maxContentY) * maxThumbY, maxThumbY))
                                }
                                return 0
                            }
                            radius: 3
                            color: (thumbScrollMa.pressed || thumbScrollMa.containsMouse || thumbScrollTrack.isScrolling) ? Theme.accent : Qt.alpha("#2a2b36", 0.75)
                            border.width: 1
                            border.color: (thumbScrollMa.pressed || thumbScrollMa.containsMouse || thumbScrollTrack.isScrolling) ? Theme.accent : Qt.alpha("#ffffff", 0.35)
                            opacity: (thumbListView.contentHeight > thumbListView.height) ? (thumbScrollTrack.showThumb ? 1.0 : 0.35) : 0.0

                            Behavior on width { NumberAnimation { duration: 120 } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

                // --- DOCUMENT VIEWPORT / HOME AREA ---
                Rectangle {
                    id: viewportCard
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: sidebarCard.visible ? sidebarCard.right : parent.left
                    anchors.leftMargin: sidebarCard.visible ? 12 : 0
                    anchors.right: parent.right
                    radius: root.isPresentation ? 0 : Theme.cardRadius
                    color: root.isPresentation ? "#111217" : Qt.alpha(Theme.fg, 0.05)
                    border.width: root.isPresentation ? 0 : 1
                    border.color: root.isPresentation ? "transparent" : Qt.alpha(Theme.fg, 0.15)
                    clip: true

                    // --- HOME / EMPTY STATE (WHEN ACTIVE TAB IS HOME OR NO DOCUMENT OPEN) ---
                    Flickable {
                        id: homeFlickable
                        anchors.fill: parent
                        visible: root.isHomeActive
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: Math.max(height, homeContentCol.implicitHeight + 48)

                        Column {
                            id: homeContentCol
                            width: Math.min(1280, parent.width - 64)
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.max(24, Math.round((homeFlickable.height - implicitHeight) / 2))
                            spacing: 16

                            // Top Hero Section
                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 10

                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 68
                                    height: 68
                                    source: "file://" + Sys.configDir + "/assets/azkia-pdf.svg"
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    opacity: 0.9
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Azkia PDF"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 22
                                    font.bold: true
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Open a PDF or supported document, or drag and drop files here"
                                    color: Qt.alpha(Theme.fg, 0.6)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 170
                                    height: 40
                                    radius: 14
                                    color: openDocBtnMa.containsMouse ? Theme.accentHover : Theme.accent
                                    border.width: 1
                                    border.color: openDocBtnMa.containsMouse ? Theme.accentHover : Theme.accent

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Text {
                                            text: ""
                                            color: Theme.bg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Open PDF"
                                            color: Theme.bg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: openDocBtnMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openFileDialog()
                                    }
                                }
                            }

                            // --- RECENT FILES CARD ---
                            Rectangle {
                                id: recentCard
                                width: parent.width
                                readonly property real colSizeWidth: 84
                                readonly property real colLocWidth: 280
                                readonly property real colTimeWidth: 125

                                implicitHeight: recentCol.implicitHeight + 24
                                height: implicitHeight
                                radius: Theme.cardRadius
                                color: Sys.customBarBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.12)
                                visible: root.recents.length > 0

                                Column {
                                    id: recentCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 12
                                    spacing: 8

                                    // Header inside Card
                                    Item {
                                        width: recentCol.width
                                        height: 24

                                        Row {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 8

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: ""
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.bold: true
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Recent Files"
                                                color: Theme.fg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                        }

                                        Rectangle {
                                            id: recentCountBadge
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: recentCountText.implicitWidth + 14
                                            height: 20
                                            radius: 10
                                            color: Qt.alpha(Theme.accent, 0.15)
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.accent, 0.3)

                                            Text {
                                                id: recentCountText
                                                anchors.centerIn: parent
                                                text: root.recents.length + " files"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }
                                    }

                                    // Divider Line
                                    Rectangle {
                                        width: recentCol.width
                                        height: 1
                                        color: Qt.alpha(Theme.fg, 0.07)
                                    }

                                    // Table Header: File Name, Size, Location, Time
                                    Rectangle {
                                        width: recentCol.width
                                        height: 26
                                        radius: 6
                                        color: Qt.alpha(Theme.fg, 0.03)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 18
                                            spacing: 8
                                            anchors.verticalCenter: parent.verticalCenter

                                            // File Name Header
                                            Item {
                                                width: parent.width - recentCard.colSizeWidth - recentCard.colLocWidth - recentCard.colTimeWidth - 24
                                                height: parent.height
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "File Name"
                                                    color: Qt.alpha(Theme.fg, 0.50)
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }
                                            }

                                            // Size Header
                                            Item {
                                                width: recentCard.colSizeWidth
                                                height: parent.height
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "Size"
                                                    color: Qt.alpha(Theme.fg, 0.50)
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }
                                            }

                                            // Location Header
                                            Item {
                                                width: recentCard.colLocWidth
                                                height: parent.height
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "Location"
                                                    color: Qt.alpha(Theme.fg, 0.50)
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }
                                            }

                                            // Time Header
                                            Item {
                                                width: recentCard.colTimeWidth
                                                height: parent.height
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "Time"
                                                    color: Qt.alpha(Theme.fg, 0.50)
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }
                                            }
                                        }
                                    }

                                    // List Container with Floating Scrollbar (matches Page Viewport)
                                    Item {
                                        id: recentListContainer
                                        width: recentCol.width
                                        height: Math.min(10, root.recents.length) * 40

                                        ListView {
                                            id: recentListView
                                            anchors.fill: parent
                                            clip: true
                                            boundsBehavior: Flickable.StopAtBounds
                                            model: root.recents
                                            spacing: 4
                                            onContentYChanged: recentScrollTimer.restart()

                                            delegate: Rectangle {
                                                id: recentItemDelegate
                                                required property var modelData
                                                required property int index

                                                readonly property string filePath: (typeof modelData === "object" && modelData.path) ? modelData.path : String(modelData)
                                                readonly property string fileName: (typeof modelData === "object" && modelData.name) ? modelData.name : filePath.split('/').pop()
                                                readonly property string fileSize: (typeof modelData === "object" && modelData.size) ? modelData.size : "-"
                                                readonly property string fileLocation: (typeof modelData === "object" && modelData.location) ? modelData.location : filePath.replace(/\/home\/[^\/]+/, "~")
                                                readonly property string fileTime: (typeof modelData === "object" && modelData.time) ? modelData.time : "-"

                                                readonly property bool isSelected: (root.focusedRecentIndex === index || recMa.containsMouse)

                                                width: recentListView.width
                                                height: 36
                                                radius: 8
                                                color: isSelected ? Theme.accent : (index % 2 === 0 ? Qt.alpha(Theme.fg, 0.02) : "transparent")
                                                border.width: 1
                                                border.color: isSelected ? Theme.accent : "transparent"

                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 18
                                                    spacing: 8
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    // 1. File Name Column
                                                    Row {
                                                        width: parent.width - recentCard.colSizeWidth - recentCard.colLocWidth - recentCard.colTimeWidth - 24
                                                        height: parent.height
                                                        spacing: 8
                                                        anchors.verticalCenter: parent.verticalCenter

                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "󰈔"
                                                            color: isSelected ? Theme.bg : Theme.accent
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 14
                                                        }

                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: parent.width - 24
                                                            text: fileName
                                                            color: isSelected ? Theme.bg : Theme.fg
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 12
                                                            font.bold: isSelected
                                                            elide: Text.ElideMiddle
                                                        }
                                                    }

                                                    // 2. Size Column
                                                    Item {
                                                        width: recentCard.colSizeWidth
                                                        height: parent.height
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: parent.width
                                                            text: fileSize
                                                            color: isSelected ? Qt.alpha(Theme.bg, 0.85) : Qt.alpha(Theme.fg, 0.60)
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            font.bold: isSelected
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    // 3. Location Column
                                                    Item {
                                                        width: recentCard.colLocWidth
                                                        height: parent.height
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: parent.width
                                                            text: fileLocation
                                                            color: isSelected ? Qt.alpha(Theme.bg, 0.80) : Qt.alpha(Theme.fg, 0.45)
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            elide: Text.ElideLeft
                                                        }
                                                    }

                                                    // 4. Time Column
                                                    Item {
                                                        width: recentCard.colTimeWidth
                                                        height: parent.height
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: parent.width
                                                            text: fileTime
                                                            color: isSelected ? Qt.alpha(Theme.bg, 0.80) : Qt.alpha(Theme.fg, 0.45)
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: recMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onEntered: {
                                                        root.focusedRecentIndex = index
                                                    }
                                                    onClicked: root.openDocument(filePath)
                                                    onWheel: (wheel) => {
                                                        wheel.accepted = false
                                                    }
                                                }
                                            }
                                        }

                                        // Floating Vertical Scrollbar Thumb for Recent List (Identical to Viewport Page Scrollbar)
                                        Item {
                                            id: recentVScrollTrack
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.topMargin: 2
                                            anchors.bottomMargin: 2
                                            width: 14
                                            z: 100
                                            visible: recentListView.contentHeight > recentListView.height

                                            readonly property bool isScrolling: recentScrollTimer.running || recentListView.moving || recentListView.flicking || recentListView.dragging
                                            readonly property bool showThumb: isScrolling || recentVScrollMa.containsMouse || recentVScrollMa.pressed

                                            MouseArea {
                                                id: recentVScrollMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.SizeVerCursor

                                                onPressed: (mouse) => updatePosition(mouse.y)
                                                onPositionChanged: (mouse) => {
                                                    if (pressed) updatePosition(mouse.y)
                                                }

                                                function updatePosition(mouseY) {
                                                    const trackH = recentVScrollTrack.height
                                                    const thumbH = recentVScrollThumb.height
                                                    if (trackH <= thumbH) return
                                                    const maxThumbY = trackH - thumbH
                                                    const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                                                    const ratio = clampedY / maxThumbY
                                                    const maxContentY = recentListView.contentHeight - recentListView.height
                                                    if (maxContentY > 0) {
                                                        recentListView.contentY = ratio * maxContentY
                                                        recentScrollTimer.restart()
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                id: recentVScrollThumb
                                                anchors.right: parent.right
                                                anchors.rightMargin: 1
                                                width: (recentVScrollMa.containsMouse || recentVScrollMa.pressed) ? 10 : 6
                                                height: {
                                                    if (recentListView.contentHeight <= recentListView.height) return 36
                                                    return Math.max(32, Math.min(recentVScrollTrack.height * (recentListView.height / Math.max(1, recentListView.contentHeight)), recentVScrollTrack.height - 16))
                                                }
                                                y: {
                                                    const maxContentY = recentListView.contentHeight - recentListView.height
                                                    const maxThumbY = recentVScrollTrack.height - height
                                                    if (maxContentY > 0 && maxThumbY > 0) {
                                                        return Math.max(0, Math.min((recentListView.contentY / maxContentY) * maxThumbY, maxThumbY))
                                                    }
                                                    return 0
                                                }
                                                radius: 4
                                                color: (recentVScrollMa.pressed || recentVScrollMa.containsMouse || recentVScrollTrack.isScrolling) ? Theme.accent : Qt.alpha("#2a2b36", 0.75)
                                                border.width: 1
                                                border.color: (recentVScrollMa.pressed || recentVScrollMa.containsMouse || recentVScrollTrack.isScrolling) ? Theme.accent : Qt.alpha("#ffffff", 0.35)
                                                opacity: recentVScrollTrack.showThumb ? 1.0 : 0.40

                                                Behavior on width { NumberAnimation { duration: 120 } }
                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                        }

                                        Timer {
                                            id: recentScrollTimer
                                            interval: 800
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // --- ACTIVE DOCUMENT CONTINUOUS VIEWPORT ---
                    ListView {
                        id: pageListView
                        anchors.fill: parent
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        visible: !root.isHomeActive && root.activeDoc !== null
                        spacing: 20
                        topMargin: 20
                        bottomMargin: 24
                        cacheBuffer: 6000
                        model: root.totalPages

                        Timer {
                            id: viewportScrollTimer
                            interval: 1200
                            repeat: false
                        }

                        // Synchronize current page dynamically as user scrolls continuously
                        onContentYChanged: {
                            viewportScrollTimer.restart()
                            if (!root.isHomeActive && root.activeDoc !== null && !root.isProgrammaticScroll && count > 0) {
                                let sampleY = contentY + height * 0.35
                                let idx = indexAt(width / 2, sampleY)
                                if (idx >= 0 && idx < count) {
                                    let pg = idx + 1
                                    if (pg !== root.currentPage) {
                                        root.currentPage = pg
                                        if (root.activeDoc) {
                                            root.activeDoc.current_page = pg
                                        }
                                    }
                                }
                            }
                        }

                        WheelHandler {
                            id: pageWheelHandler
                            target: pageListView
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                            onWheel: (event) => {
                                if (event.modifiers & Qt.ControlModifier) {
                                    if (event.angleDelta.y > 0) {
                                        root.zoomIn()
                                    } else if (event.angleDelta.y < 0) {
                                        root.zoomOut()
                                    }
                                    event.accepted = true
                                } else if ((event.modifiers & Qt.ShiftModifier) || event.angleDelta.x !== 0) {
                                    let maxPageW = Math.round(595.0 * root.currentZoom)
                                    if (root.activeDoc && root.activeDoc.pages && root.activeDoc.pages[root.currentPage - 1]) {
                                        maxPageW = Math.round(root.activeDoc.pages[root.currentPage - 1].width * root.currentZoom)
                                    }
                                    let maxPan = Math.max(0, (maxPageW - viewportCard.width + 40) / 2)
                                    if (maxPan > 0) {
                                        let deltaX = event.pixelDelta.x !== 0 ? event.pixelDelta.x : (event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y) * 0.85
                                        root.panOffsetX = Math.max(-maxPan, Math.min(maxPan, root.panOffsetX + deltaX))
                                        viewportScrollTimer.restart()
                                        event.accepted = true
                                    }
                                } else {
                                    let deltaY = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y * 0.85)
                                    let maxY = Math.max(0, pageListView.contentHeight - pageListView.height)
                                    if (maxY > 0) {
                                        pageListView.contentY = Math.max(0, Math.min(maxY, pageListView.contentY - deltaY))
                                        viewportScrollTimer.restart()
                                        event.accepted = true
                                    }
                                }
                            }
                        }

                        delegate: Item {
                            id: pageDelegate
                            readonly property int pageNum: index + 1
                            readonly property var pageMeta: (root.activeDoc && root.activeDoc.pages && root.activeDoc.pages[index]) ? root.activeDoc.pages[index] : null
                            readonly property real rawW: pageMeta ? pageMeta.width : 595.0
                            readonly property real rawH: pageMeta ? pageMeta.height : 842.0
                            readonly property bool isRotated90: (root.currentRotation % 180 !== 0)
                            readonly property real baseW: isRotated90 ? rawH : rawW
                            readonly property real baseH: isRotated90 ? rawW : rawH

                            readonly property real targetPageW: Math.round(baseW * root.currentZoom)
                            readonly property real targetPageH: Math.round(baseH * root.currentZoom)

                            property var pageWords: []
                            property var selectionRects: []
                            property var selectedWords: []

                            FileView {
                                id: textDataView
                                path: (root.activeDoc && root.fileHash) ? ("/tmp/azkia_pdf_cache/" + root.fileHash + "/text_p" + pageDelegate.pageNum + ".json") : ""
                                watchChanges: true
                                onLoaded: updateWords()
                                onTextChanged: updateWords()
                                function updateWords() {
                                    try {
                                        const raw = (typeof text === "function") ? text() : (text || "")
                                        if (raw && raw.length > 2) {
                                            pageDelegate.pageWords = JSON.parse(raw)
                                            pageDelegate.updateSelectionRects()
                                        }
                                    } catch(e) {}
                                }
                            }

                            Connections {
                                target: root
                                function onSelectedPageNumChanged() { pageDelegate.updateSelectionRects() }
                                function onSelectionStartIdxChanged() { pageDelegate.updateSelectionRects() }
                                function onSelectionEndIdxChanged() { pageDelegate.updateSelectionRects() }
                            }

                            function updateSelectionRects() {
                                if (root.selectedPageNum !== pageDelegate.pageNum || root.selectionStartIdx < 0 || root.selectionEndIdx < 0) {
                                    pageDelegate.selectionRects = []
                                    pageDelegate.selectedWords = []
                                    return
                                }
                                let words = pageDelegate.pageWords
                                if (!words || words.length === 0) {
                                    pageDelegate.selectionRects = []
                                    pageDelegate.selectedWords = []
                                    return
                                }
                                let scaleX = pageCard.width / pageDelegate.rawW
                                let scaleY = pageCard.height / pageDelegate.rawH
                                let minIdx = Math.min(root.selectionStartIdx, root.selectionEndIdx)
                                let maxIdx = Math.max(root.selectionStartIdx, root.selectionEndIdx)
                                let lineMap = {}
                                let selWords = []
                                for (let i = minIdx; i <= maxIdx && i < words.length; i++) {
                                    let w = words[i]
                                    let l = w.line
                                    let wx0 = w.x0 * scaleX
                                    let wx1 = w.x1 * scaleX
                                    let wy0 = w.y0 * scaleY
                                    let wy1 = w.y1 * scaleY
                                    if (!lineMap[l]) {
                                        lineMap[l] = { x: wx0, y: wy0, r: wx1, b: wy1 }
                                    } else {
                                        lineMap[l].x = Math.min(lineMap[l].x, wx0)
                                        lineMap[l].y = Math.min(lineMap[l].y, wy0)
                                        lineMap[l].r = Math.max(lineMap[l].r, wx1)
                                        lineMap[l].b = Math.max(lineMap[l].b, wy1)
                                    }
                                    selWords.push({
                                        text: w.text,
                                        x: Math.round(wx0),
                                        y: Math.round(wy0),
                                        w: Math.round(wx1 - wx0),
                                        h: Math.round(wy1 - wy0)
                                    })
                                }
                                let rects = []
                                for (let l in lineMap) {
                                    let box = lineMap[l]
                                    rects.push({
                                        x: Math.round(box.x - 1),
                                        y: Math.round(box.y - 1),
                                        w: Math.round((box.r - box.x) + 2),
                                        h: Math.round((box.b - box.y) + 2)
                                    })
                                }
                                pageDelegate.selectionRects = rects
                                pageDelegate.selectedWords = selWords
                            }

                            function findWordIndex(ptX, ptY, allowClosest) {
                                let words = pageDelegate.pageWords
                                if (!words || words.length === 0) return -1
                                for (let i = 0; i < words.length; i++) {
                                    let w = words[i]
                                    if (ptX >= w.x0 - 6 && ptX <= w.x1 + 6 && ptY >= w.y0 - 4 && ptY <= w.y1 + 4) {
                                        return i
                                    }
                                }
                                if (allowClosest === false) return -1
                                let bestIdx = -1
                                let bestDist = 1e9
                                for (let i = 0; i < words.length; i++) {
                                    let w = words[i]
                                    let cx = (w.x0 + w.x1) / 2
                                    let cy = (w.y0 + w.y1) / 2
                                    let dy = (ptY - cy) * 3.5
                                    let dx = (ptX - cx)
                                    let dist = dx * dx + dy * dy
                                    if (dist < bestDist) {
                                        bestDist = dist
                                        bestIdx = i
                                    }
                                }
                                return bestIdx
                            }

                            function finalizeSelection(mx, my) {
                                let words = pageDelegate.pageWords
                                if (!words || root.selectionStartIdx < 0 || root.selectionEndIdx < 0) {
                                    root.clearSelection()
                                    return
                                }
                                let minIdx = Math.min(root.selectionStartIdx, root.selectionEndIdx)
                                let maxIdx = Math.max(root.selectionStartIdx, root.selectionEndIdx)
                                let lines = []
                                let currLine = -1
                                let currWords = []
                                for (let i = minIdx; i <= maxIdx && i < words.length; i++) {
                                    let w = words[i]
                                    if (currLine !== -1 && w.line !== currLine) {
                                        lines.push(currWords.join(" "))
                                        currWords = []
                                    }
                                    currLine = w.line
                                    currWords.push(w.text)
                                }
                                if (currWords.length > 0) {
                                    lines.push(currWords.join(" "))
                                }
                                let fullText = lines.join("\n").trim()
                                if (fullText.length > 0) {
                                    root.selectedText = fullText
                                } else {
                                    root.clearSelection()
                                }
                            }

                            width: pageListView.width
                            height: targetPageH

                            // Page Card Container
                            Rectangle {
                                id: pageCard
                                x: Math.round((parent.width - width) / 2 + root.panOffsetX)
                                anchors.verticalCenter: parent.verticalCenter
                                width: pageDelegate.targetPageW
                                height: pageDelegate.targetPageH
                                radius: 2
                                color: "#ffffff"

                                // Drop Shadow under page
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    color: Qt.alpha("#000000", 0.35)
                                    anchors.margins: -4
                                    z: -1
                                }

                                // Thumbnail Preview as immediate vector backdrop
                                Image {
                                    id: thumbPreview
                                    anchors.fill: parent
                                    source: {
                                        if (!root.activeDoc || !root.fileHash) return ""
                                        let r = root.currentRotation
                                        let rev = root.renderRevision
                                        return "file:///tmp/azkia_pdf_cache/" + root.fileHash + "/p" + pageDelegate.pageNum + "_thumb_r" + r + ".png"
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: false
                                    asynchronous: true
                                    opacity: 0.85
                                }

                                // Rendered Page Image (Full High Resolution)
                                Image {
                                    id: pageImg
                                    anchors.fill: parent
                                    source: {
                                        if (!root.activeDoc || !root.fileHash) return ""
                                        let b = root.activeBucket
                                        let r = root.currentRotation
                                        let rev = root.renderRevision
                                        return "file:///tmp/azkia_pdf_cache/" + root.fileHash + "/p" + pageDelegate.pageNum + "_b" + b + "_r" + r + ".png"
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: false
                                    asynchronous: true
                                    cache: false

                                    onStatusChanged: {
                                        if (status === Image.Error && pageRetryTimer) {
                                            pageRetryTimer.restart()
                                        }
                                    }
                                }

                                Timer {
                                    id: pageRetryTimer
                                    interval: 150
                                    repeat: false
                                    onTriggered: {
                                        if (pageImg.status !== Image.Ready) {
                                            let s = pageImg.source
                                            pageImg.source = ""
                                            pageImg.source = s
                                        }
                                    }
                                }

                                Connections {
                                    target: root
                                    function onRenderRevisionChanged() {
                                        if (pageImg.status !== Image.Ready) {
                                            let s = pageImg.source
                                            pageImg.source = ""
                                            pageImg.source = s
                                        }
                                        if (thumbPreview.status !== Image.Ready) {
                                            let ts = thumbPreview.source
                                            thumbPreview.source = ""
                                            thumbPreview.source = ts
                                        }
                                    }
                                }

                                // Loading overlay ONLY if neither full-res nor thumbnail preview is ready
                                Rectangle {
                                    anchors.fill: parent
                                    color: Qt.alpha(Theme.bg, 0.15)
                                    visible: pageImg.status !== Image.Ready && thumbPreview.status !== Image.Ready

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "󰑐"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 22

                                            RotationAnimation on rotation {
                                                from: 0
                                                to: 360
                                                duration: 1000
                                                loops: Animation.Infinite
                                                running: pageImg.status !== Image.Ready && thumbPreview.status !== Image.Ready
                                            }
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "Page " + pageDelegate.pageNum
                                            color: Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }

                                // Hover Page Badge (Bottom Right Pill)
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 12
                                    width: pageNumBadgeText.implicitWidth + 16
                                    height: 22
                                    radius: 11
                                    color: Qt.alpha(Theme.bg, 0.8)
                                    border.width: 1
                                    border.color: Qt.alpha(Theme.fg, 0.15)
                                    opacity: pageCardMa.containsMouse ? 1.0 : 0.0

                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Text {
                                        id: pageNumBadgeText
                                        anchors.centerIn: parent
                                        text: pageDelegate.pageNum + " / " + root.totalPages
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }

                                // Selection Highlight Layer: Accent Background & Theme.bg Font Color
                                Item {
                                    id: selectionHighlightLayer
                                    anchors.fill: parent
                                    z: 10
                                    visible: root.selectedPageNum === pageDelegate.pageNum && pageDelegate.selectionRects.length > 0

                                    // 1. Solid Accent Background Rectangles per Line
                                    Repeater {
                                        model: pageDelegate.selectionRects
                                        Rectangle {
                                            x: modelData.x
                                            y: modelData.y
                                            width: modelData.w
                                            height: modelData.h
                                            color: Theme.accent
                                            radius: 2
                                        }
                                    }

                                    // 2. Text Overlay in Theme.bg Font Color
                                    Repeater {
                                        model: pageDelegate.selectedWords
                                        Text {
                                            x: modelData.x
                                            y: modelData.y
                                            width: modelData.w
                                            height: modelData.h
                                            text: modelData.text
                                            color: Theme.bg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Math.max(8, Math.round(modelData.h * 0.82))
                                            font.bold: true
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }
                                }

                                MouseArea {
                                    id: pageCardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: {
                                        if (root.interactionMode === "pan") {
                                            return pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        } else {
                                            return (pageDelegate.pageWords && pageDelegate.pageWords.length > 0) ? Qt.IBeamCursor : Qt.ArrowCursor
                                        }
                                    }
                                    z: 20

                                    onPressed: (mouse) => {
                                        if (mouse.button !== Qt.LeftButton) return
                                        if (root.interactionMode === "pan") {
                                            let pt = pageCard.mapToItem(viewportCard, mouse.x, mouse.y)
                                            root.dragStartX = pt.x
                                            root.dragStartY = pt.y
                                            return
                                        }
                                        let words = pageDelegate.pageWords
                                        if (!words || words.length === 0) {
                                            root.clearSelection()
                                            return
                                        }
                                        let scaleX = pageCard.width / pageDelegate.rawW
                                        let scaleY = pageCard.height / pageDelegate.rawH
                                        let ptX = mouse.x / scaleX
                                        let ptY = mouse.y / scaleY
                                        let idx = pageDelegate.findWordIndex(ptX, ptY, false)
                                        if (idx >= 0) {
                                            root.selectedPageNum = pageDelegate.pageNum
                                            root.selectionStartIdx = idx
                                            root.selectionEndIdx = idx
                                            root.isSelecting = true
                                            pageDelegate.updateSelectionRects()
                                        } else {
                                            root.clearSelection()
                                        }
                                    }

                                    onPositionChanged: (mouse) => {
                                        if (root.interactionMode === "pan") {
                                            if (pressed) {
                                                let pt = pageCard.mapToItem(viewportCard, mouse.x, mouse.y)
                                                let dx = pt.x - root.dragStartX
                                                let dy = pt.y - root.dragStartY
                                                root.dragStartX = pt.x
                                                root.dragStartY = pt.y
                                                let maxContentY = Math.max(0, pageListView.contentHeight - pageListView.height)
                                                pageListView.contentY = Math.max(0, Math.min(maxContentY, pageListView.contentY - dy))
                                                let maxPageW = Math.round(595.0 * root.currentZoom)
                                                if (root.activeDoc && root.activeDoc.pages && root.activeDoc.pages[root.currentPage - 1]) {
                                                    maxPageW = Math.round(root.activeDoc.pages[root.currentPage - 1].width * root.currentZoom)
                                                }
                                                let maxPan = Math.max(0, (maxPageW - viewportCard.width + 40) / 2)
                                                if (maxPan > 0) {
                                                    root.panOffsetX = Math.max(-maxPan, Math.min(maxPan, root.panOffsetX + dx))
                                                }
                                            }
                                            return
                                        }
                                        if (!root.isSelecting || root.selectedPageNum !== pageDelegate.pageNum) return
                                        let words = pageDelegate.pageWords
                                        if (!words || words.length === 0) return
                                        let scaleX = pageCard.width / pageDelegate.rawW
                                        let scaleY = pageCard.height / pageDelegate.rawH
                                        let ptX = mouse.x / scaleX
                                        let ptY = mouse.y / scaleY
                                        let idx = pageDelegate.findWordIndex(ptX, ptY, true)
                                        if (idx >= 0 && idx !== root.selectionEndIdx) {
                                            root.selectionEndIdx = idx
                                            pageDelegate.updateSelectionRects()
                                        }
                                    }

                                    onReleased: (mouse) => {
                                        if (root.interactionMode === "pan") return
                                        if (root.isSelecting && root.selectedPageNum === pageDelegate.pageNum) {
                                            root.isSelecting = false
                                            pageDelegate.finalizeSelection(mouse.x, mouse.y)
                                        }
                                    }

                                    onDoubleClicked: (mouse) => {
                                        if (root.interactionMode === "pan") return
                                        let words = pageDelegate.pageWords
                                        if (!words || words.length === 0) return
                                        let scaleX = pageCard.width / pageDelegate.rawW
                                        let scaleY = pageCard.height / pageDelegate.rawH
                                        let ptX = mouse.x / scaleX
                                        let ptY = mouse.y / scaleY
                                        let idx = pageDelegate.findWordIndex(ptX, ptY, false)
                                        if (idx >= 0) {
                                            root.selectedPageNum = pageDelegate.pageNum
                                            root.selectionStartIdx = idx
                                            root.selectionEndIdx = idx
                                            pageDelegate.updateSelectionRects()
                                            pageDelegate.finalizeSelection(mouse.x, mouse.y)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Floating Vertical Scrollbar Thumb for Viewport (Launcher style)
                    Item {
                        id: viewportVScrollTrack
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 4
                        anchors.bottomMargin: 4
                        width: 18
                        z: 100

                        readonly property bool isScrolling: viewportScrollTimer.running || pageListView.moving || pageListView.flicking || pageListView.dragging
                        readonly property bool showThumb: isScrolling || viewportVScrollMa.containsMouse || viewportVScrollMa.pressed

                        MouseArea {
                            id: viewportVScrollMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeVerCursor

                            onPressed: (mouse) => updatePosition(mouse.y)
                            onPositionChanged: (mouse) => {
                                if (pressed) updatePosition(mouse.y)
                            }

                            function updatePosition(mouseY) {
                                const trackH = viewportVScrollTrack.height
                                const thumbH = viewportVScrollThumb.height
                                if (trackH <= thumbH) return
                                const maxThumbY = trackH - thumbH
                                const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                                const ratio = clampedY / maxThumbY
                                const maxContentY = pageListView.contentHeight - pageListView.height
                                if (maxContentY > 0) {
                                    pageListView.contentY = ratio * maxContentY
                                    viewportScrollTimer.restart()
                                }
                            }
                        }

                        Rectangle {
                            id: viewportVScrollThumb
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            width: (viewportVScrollMa.containsMouse || viewportVScrollMa.pressed) ? 10 : 6
                            height: {
                                if (pageListView.contentHeight <= pageListView.height) return 36
                                return Math.max(32, Math.min(viewportVScrollTrack.height * (pageListView.height / Math.max(1, pageListView.contentHeight)), viewportVScrollTrack.height - 20))
                            }
                            y: {
                                const maxContentY = pageListView.contentHeight - pageListView.height
                                const maxThumbY = viewportVScrollTrack.height - height
                                if (maxContentY > 0 && maxThumbY > 0) {
                                    return Math.max(0, Math.min((pageListView.contentY / maxContentY) * maxThumbY, maxThumbY))
                                }
                                return 0
                            }
                            radius: 4
                            color: (viewportVScrollMa.pressed || viewportVScrollMa.containsMouse || viewportVScrollTrack.isScrolling) ? Theme.accent : Qt.alpha("#2a2b36", 0.75)
                            border.width: 1
                            border.color: (viewportVScrollMa.pressed || viewportVScrollMa.containsMouse || viewportVScrollTrack.isScrolling) ? Theme.accent : Qt.alpha("#ffffff", 0.35)
                            opacity: (!root.isHomeActive && root.activeDoc !== null && pageListView.contentHeight > pageListView.height) ? (viewportVScrollTrack.showThumb ? 1.0 : 0.40) : 0.0

                            Behavior on width { NumberAnimation { duration: 120 } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    // Floating Horizontal Scrollbar for Viewport (When zoomed in)
                    Item {
                        id: viewportHScrollTrack
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 6
                        anchors.rightMargin: 24
                        height: 18
                        z: 100

                        readonly property real maxPageW: {
                            if (!root.activeDoc || root.isHomeActive) return 0
                            let base = 595.0
                            if (root.activeDoc.pages && root.activeDoc.pages[root.currentPage - 1]) {
                                base = root.activeDoc.pages[root.currentPage - 1].width || 595.0
                            }
                            if (root.currentRotation % 180 !== 0) {
                                if (root.activeDoc.pages && root.activeDoc.pages[root.currentPage - 1]) {
                                    base = root.activeDoc.pages[root.currentPage - 1].height || 842.0
                                }
                            }
                            return Math.round(base * root.currentZoom)
                        }
                        readonly property bool isHorizScrollable: maxPageW > (viewportCard.width - 20)
                        readonly property real maxPan: Math.max(0, (maxPageW - viewportCard.width + 40) / 2)
                        readonly property bool showThumb: viewportScrollTimer.running || viewportHScrollMa.containsMouse || viewportHScrollMa.pressed

                        visible: isHorizScrollable && !root.isHomeActive && root.activeDoc !== null

                        MouseArea {
                            id: viewportHScrollMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeHorCursor

                            onPressed: (mouse) => updatePosition(mouse.x)
                            onPositionChanged: (mouse) => {
                                if (pressed) updatePosition(mouse.x)
                            }

                            function updatePosition(mouseX) {
                                const trackW = viewportHScrollTrack.width
                                const thumbW = viewportHScrollThumb.width
                                if (trackW <= thumbW || viewportHScrollTrack.maxPan <= 0) return
                                const maxThumbX = trackW - thumbW
                                const clampedX = Math.max(0, Math.min(mouseX - thumbW / 2, maxThumbX))
                                const ratio = (clampedX / maxThumbX) * 2.0 - 1.0 // -1.0 to +1.0
                                root.panOffsetX = -ratio * viewportHScrollTrack.maxPan
                                viewportScrollTimer.restart()
                            }
                        }

                        Rectangle {
                            id: viewportHScrollThumb
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            height: (viewportHScrollMa.containsMouse || viewportHScrollMa.pressed) ? 10 : 6
                            width: {
                                if (!viewportHScrollTrack.isHorizScrollable) return 36
                                return Math.max(32, Math.min(viewportHScrollTrack.width * (viewportCard.width / Math.max(1, viewportHScrollTrack.maxPageW)), viewportHScrollTrack.width - 20))
                            }
                            x: {
                                const trackW = viewportHScrollTrack.width
                                const thumbW = width
                                const maxThumbX = trackW - thumbW
                                if (maxThumbX > 0 && viewportHScrollTrack.maxPan > 0) {
                                    const ratio = 0.5 - (root.panOffsetX / (viewportHScrollTrack.maxPan * 2.0))
                                    return Math.max(0, Math.min(ratio * maxThumbX, maxThumbX))
                                }
                                return 0
                            }
                            radius: 4
                            color: (viewportHScrollMa.pressed || viewportHScrollMa.containsMouse || viewportScrollTimer.running) ? Theme.accent : Qt.alpha("#2a2b36", 0.75)
                            border.width: 1
                            border.color: (viewportHScrollMa.pressed || viewportHScrollMa.containsMouse || viewportScrollTimer.running) ? Theme.accent : Qt.alpha("#ffffff", 0.35)
                            opacity: viewportHScrollTrack.isHorizScrollable ? (viewportHScrollTrack.showThumb ? 1.0 : 0.40) : 0.0

                            Behavior on height { NumberAnimation { duration: 120 } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    // --- PRESENTATION FLOATING CONTROLS (AUTOHIDE) ---
                    Rectangle {
                        id: presControlBar
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 24
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 48
                        width: presRow.implicitWidth + 32
                        radius: 24
                        color: Qt.alpha(Theme.bg, 0.85)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.2)
                        visible: root.isPresentation

                        Row {
                            id: presRow
                            anchors.centerIn: parent
                            spacing: 12

                            ToolbarButton {
                                iconText: "󰁍"
                                tooltipText: "Prev Slide (Left / Space)"
                                onClicked: root.prevPage()
                            }

                            Text {
                                text: root.currentPage + " / " + root.totalPages
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            ToolbarButton {
                                iconText: "󰁔"
                                tooltipText: "Next Slide (Right)"
                                onClicked: root.nextPage()
                            }

                            ToolbarSeparator {}

                            ToolbarButton {
                                iconText: "󰅖"
                                tooltipText: "Exit Presentation (Esc)"
                                onClicked: root.togglePresentation()
                            }
                        }
                    }
                }
            }
        }
    }


    // ================= HELPER COMPONENTS =================

    // Separator Line
    component ToolbarSeparator: Rectangle {
        width: 1
        height: 24
        color: Qt.alpha(Theme.fg, 0.15)
        anchors.verticalCenter: parent.verticalCenter
    }

    // Fit Page Custom Vector Icon (Corner brackets around inner square)
    component FitPageIcon: Canvas {
        id: fpCanvas
        property color iconColor: Theme.fg
        width: 14
        height: 14
        anchors.centerIn: parent
        onIconColorChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = iconColor
            ctx.lineWidth = 1.25
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            let w = width, h = height
            let cLen = 2.8
            let pad = 0.8

            // TL Corner
            ctx.beginPath()
            ctx.moveTo(pad, pad + cLen)
            ctx.lineTo(pad, pad)
            ctx.lineTo(pad + cLen, pad)
            ctx.stroke()

            // TR Corner
            ctx.beginPath()
            ctx.moveTo(w - pad - cLen, pad)
            ctx.lineTo(w - pad, pad)
            ctx.lineTo(w - pad, pad + cLen)
            ctx.stroke()

            // BL Corner
            ctx.beginPath()
            ctx.moveTo(pad, h - pad - cLen)
            ctx.lineTo(pad, h - pad)
            ctx.lineTo(pad + cLen, h - pad)
            ctx.stroke()

            // BR Corner
            ctx.beginPath()
            ctx.moveTo(w - pad - cLen, h - pad)
            ctx.lineTo(w - pad, h - pad)
            ctx.lineTo(w - pad, h - pad - cLen)
            ctx.stroke()

            // Center Square
            let sqPad = 3.6
            ctx.strokeRect(sqPad, sqPad, w - sqPad * 2, h - sqPad * 2)
        }
    }

    // Fit Width Custom Vector Icon (Top arch frame + bottom double arrow)
    component FitWidthIcon: Canvas {
        id: fwCanvas
        property color iconColor: Theme.fg
        width: 14
        height: 14
        anchors.centerIn: parent
        onIconColorChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = iconColor
            ctx.fillStyle = iconColor
            ctx.lineWidth = 1.25
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            let w = width, h = height
            let pad = 1.2

            // Top Arch (open at bottom)
            let archH = 6.5
            ctx.beginPath()
            ctx.moveTo(pad, pad + archH)
            ctx.lineTo(pad, pad)
            ctx.lineTo(w - pad, pad)
            ctx.lineTo(w - pad, pad + archH)
            ctx.stroke()

            // Bottom Double Arrow Line
            let arrowY = h - pad - 1.0
            ctx.beginPath()
            ctx.moveTo(pad, arrowY)
            ctx.lineTo(w - pad, arrowY)
            ctx.stroke()

            // Left Arrow Head
            ctx.beginPath()
            ctx.moveTo(pad - 1.0, arrowY)
            ctx.lineTo(pad + 3.0, arrowY - 2.4)
            ctx.lineTo(pad + 3.0, arrowY + 2.4)
            ctx.closePath()
            ctx.fill()

            // Right Arrow Head
            ctx.beginPath()
            ctx.moveTo(w - pad + 1.0, arrowY)
            ctx.lineTo(w - pad - 3.0, arrowY - 2.4)
            ctx.lineTo(w - pad - 3.0, arrowY + 2.4)
            ctx.closePath()
            ctx.fill()
        }
    }

    // Generic Toolbar Icon Button with Tooltip
    component ToolbarButton: Rectangle {
        id: btnRoot
        property string iconText: ""
        property string tooltipText: ""
        property bool isActive: false
        property bool isTextButton: false
        property bool isFitPageIcon: false
        property bool isFitWidthIcon: false
        signal clicked()

        readonly property color currentIconColor: btnRoot.isActive ? Theme.bg : (btnMa.containsMouse ? Theme.accent : Theme.fg)

        width: isTextButton ? Math.max(46, btnLabel.implicitWidth + 14) : 34
        height: 34
        radius: Theme.buttonRadius
        anchors.verticalCenter: parent.verticalCenter
        color: isActive ? Theme.accent : (btnMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent")
        border.width: isActive ? 1 : 0
        border.color: isActive ? Theme.accent : "transparent"
        opacity: enabled ? 1.0 : 0.4

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: btnLabel
            anchors.centerIn: parent
            text: btnRoot.iconText
            color: btnRoot.currentIconColor
            font.family: Theme.fontFamily
            font.pixelSize: isTextButton ? 11 : 16
            font.bold: isTextButton
            visible: !btnRoot.isFitPageIcon && !btnRoot.isFitWidthIcon
        }

        FitPageIcon {
            visible: btnRoot.isFitPageIcon
            iconColor: btnRoot.currentIconColor
        }

        FitWidthIcon {
            visible: btnRoot.isFitWidthIcon
            iconColor: btnRoot.currentIconColor
        }

        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btnRoot.clicked()

            ToolTip {
                visible: btnMa.containsMouse && btnRoot.tooltipText.length > 0
                delay: 250
                text: btnRoot.tooltipText
                contentItem: Text {
                    text: btnRoot.tooltipText
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 11
                }
                background: Rectangle {
                    color: Qt.alpha(Theme.bg, 0.95)
                    border.color: Qt.alpha(Theme.fg, 0.2)
                    border.width: 1
                    radius: 6
                }
            }
        }
    }
}
