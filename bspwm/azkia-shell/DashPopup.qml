import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

Popout {
    id: root

    cardWidth: 686
    cardHeight: 425

    property string currentTab: "dashboard" // "dashboard", "media", "performance", "wallpaper", "settings"

    function toggle(tab) {
        let targetTab = (tab && tab !== "settings") ? tab : "dashboard"
        if (visible && !isClosing) {
            if (tab && tab !== currentTab) {
                currentTab = targetTab
            } else {
                close()
            }
        } else {
            currentTab = targetTab
            open()
        }
    }

    IpcHandler {
        target: "dash"
        function toggle(): void { root.toggle("dashboard") }
    }

    IpcHandler {
        target: "calendar"
        function toggle(): void { root.toggle("dashboard") }
    }

    IpcHandler {
        target: "clock"
        function toggle(): void { root.toggle("dashboard") }
    }

    IpcHandler {
        target: "prayer"
        function toggle(): void { root.toggle("prayer") }
    }

    // Tooltip State & Helpers
    property string activeTooltipText: ""
    property var activeTooltipItem: null
    property real tooltipTargetX: 0
    property real tooltipTargetY: 0
    property bool tooltipVisible: false

    function updateTooltipPos() {
        let item = activeTooltipItem
        if (item && dashTooltipLayer) {
            let mx = (item.mouseX !== undefined && !isNaN(item.mouseX)) ? item.mouseX : item.width / 2
            let my = (item.mouseY !== undefined && !isNaN(item.mouseY)) ? item.mouseY : item.height / 2
            let pos = item.mapToItem(dashTooltipLayer, mx, my)
            tooltipTargetX = pos.x
            tooltipTargetY = pos.y
        }
    }

    Timer {
        id: dashTooltipTimer
        interval: 150
        repeat: false
        onTriggered: {
            root.updateTooltipPos()
            root.tooltipVisible = true
        }
    }

    function showTooltip(text, item) {
        if (!text) {
            hideTooltip()
            return
        }
        activeTooltipText = text
        activeTooltipItem = item
        updateTooltipPos()
        dashTooltipTimer.restart()
    }

    function hideTooltip() {
        dashTooltipTimer.stop()
        root.tooltipVisible = false
        activeTooltipText = ""
        activeTooltipItem = null
    }

    // ==========================================
    // TAB 1: DASHBOARD (CLOCK & CALENDAR & STATS) DATA & LOGIC
    // ==========================================
    property date shownDate: new Date()
    property date currentTime: new Date()

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var audioSink: Pipewire.defaultAudioSink?.audio ?? null
    readonly property bool sinkMuted: audioSink?.muted ?? false
    readonly property int sinkVolume: audioSink ? Math.round(audioSink.volume * 100) : 0

    function setVolume(vol) {
        if (audioSink) {
            audioSink.volume = Math.max(0, Math.min(1.5, vol / 100))
        }
    }

    property int brightnessVal: 50

    Process {
        id: brightnessGet
        command: ["brightnessctl", "-m"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(",")
                if (parts.length >= 4) {
                    const pct = parseInt(parts[3].replace("%", ""))
                    if (!isNaN(pct)) root.brightnessVal = pct
                }
            }
        }
    }

    function setBrightness(pct) {
        pct = Math.max(1, Math.min(100, Math.round(pct)))
        root.brightnessVal = pct
        Quickshell.execDetached(["brightnessctl", "s", pct + "%"])
    }

    function formatTime(s) {
        if (isNaN(s) || s < 0) return "0:00"
        let m = Math.floor(s / 60)
        let sec = Math.floor(s % 60)
        return m + ":" + (sec < 10 ? "0" : "") + sec
    }

    property var sysInfo: ({ user: "vaan", distro: "Linux", wm: "BSPWM", shell: "Azkia Shell", uptime: "0m", uptime_full: "" })

    Process {
        id: sysFetchProc
        command: ["python3", Sys.scriptPath("sys_fetch.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.sysInfo = JSON.parse(text)
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 1000
        running: root.visible && root.currentTab === "dashboard"
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.currentTime = new Date()
            brightnessGet.running = false
            brightnessGet.running = true
            sysFetchProc.running = false
            sysFetchProc.running = true
            sysProc.running = false
            sysProc.running = true
        }
    }

    // ==========================================
    // TAB 2: MEDIA DATA & LOGIC
    // ==========================================
    property real animPhase: 0

    Timer {
        id: waveTimer
        interval: 40
        running: root.visible && (root.currentTab === "dashboard" || root.currentTab === "media") && root.isPlaying
        repeat: true
        onTriggered: root.animPhase = (root.animPhase + 0.15) % (Math.PI * 2)
    }

    readonly property var players: Mpris.players.values
    property int selectedPlayerIndex: 0

    function autoSelectPlayer() {
        if (!players || players.length === 0) {
            selectedPlayerIndex = 0
            return
        }
        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            if (p && (p.playbackState === MprisPlaybackState.Playing || p.playbackState === 1 || p.playbackState == "Playing")) {
                selectedPlayerIndex = i
                return
            }
        }
        if (Sys.lastActivePlayerIdentity !== "") {
            for (let i = 0; i < players.length; i++) {
                const p = players[i]
                const id = p ? (p.identity || p.appName || "") : ""
                if (id === Sys.lastActivePlayerIdentity) {
                    selectedPlayerIndex = i
                    return
                }
            }
        }
        selectedPlayerIndex = 0
    }

    onPlayersChanged: autoSelectPlayer()

    property bool azkiaRepeatTrack: false
    property real currentTrackPosition: 0
    property real currentTrackDuration: 0

    Process {
        id: azkiaFetchStateProc
        command: ["python3", Sys.scriptPath("azkia_audio_player.py"), "--get-state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(text)
                    if (parsed) {
                        root.azkiaRepeatTrack = (parsed.repeat_track === true)
                        if (typeof parsed.position === "number") {
                            root.currentTrackPosition = parsed.position
                        }
                        if (typeof parsed.duration === "number") {
                            root.currentTrackDuration = parsed.duration
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        id: mediaPositionTimer
        interval: 1000
        running: root.visible && (root.currentTab === "media" || root.currentTab === "dashboard") && root.isPlaying
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.isAzkiaPlayer) {
                azkiaFetchStateProc.running = false
                azkiaFetchStateProc.running = true
            } else if (root.activePlayer) {
                // Advance position locally every second during active playback for Brave, Spotify, etc.
                let maxDur = root.displayDuration
                if (maxDur > 0 && root.currentTrackPosition < maxDur) {
                    root.currentTrackPosition = Math.min(maxDur, root.currentTrackPosition + 1)
                } else if (maxDur <= 0) {
                    root.currentTrackPosition += 1
                }
                // Sync duration if updated
                let curLen = root.activePlayer.length || 0
                if (curLen <= 0 && root.activePlayer.rawMetadata && root.activePlayer.rawMetadata["mpris:length"]) {
                    curLen = root.activePlayer.rawMetadata["mpris:length"] / 1000000.0
                }
                if (curLen > 0) root.currentTrackDuration = curLen
            }
        }
    }

    function togglePlayback() {
        if (root.isAzkiaPlayer || !root.activePlayer) {
            Quickshell.execDetached(["python3", Sys.scriptPath("azkia_audio_player.py"), "--toggle-play"])
            return
        }
        if (root.activePlayer.canTogglePlaying) {
            root.activePlayer.togglePlaying()
        } else if (typeof root.activePlayer.playPause === "function") {
            root.activePlayer.playPause()
        } else if (root.isPlaying) {
            if (root.activePlayer.canPause) root.activePlayer.pause()
            else if (typeof root.activePlayer.pause === "function") root.activePlayer.pause()
        } else {
            if (root.activePlayer.canPlay) root.activePlayer.play()
            else if (typeof root.activePlayer.play === "function") root.activePlayer.play()
        }
    }

    function playbackPrev() {
        if (root.isAzkiaPlayer || !root.activePlayer) {
            Quickshell.execDetached(["python3", Sys.scriptPath("azkia_audio_player.py"), "--prev"])
            return
        }
        if (root.activePlayer.canGoPrevious) root.activePlayer.previous()
        else if (typeof root.activePlayer.previous === "function") root.activePlayer.previous()
    }

    function playbackNext() {
        if (root.isAzkiaPlayer || !root.activePlayer) {
            Quickshell.execDetached(["python3", Sys.scriptPath("azkia_audio_player.py"), "--next"])
            return
        }
        if (root.activePlayer.canGoNext) root.activePlayer.next()
        else if (typeof root.activePlayer.next === "function") root.activePlayer.next()
    }

    function toggleRepeat() {
        if (root.isAzkiaPlayer) {
            root.azkiaRepeatTrack = !root.azkiaRepeatTrack
            Quickshell.execDetached(["python3", Sys.scriptPath("azkia_audio_player.py"), "--toggle-repeat"])
        } else if (root.activePlayer && typeof root.activePlayer.loopStatus !== "undefined") {
            let nextStatus = (root.activePlayer.loopStatus === "None" || !root.activePlayer.loopStatus) ? "Track" : "None"
            root.activePlayer.loopStatus = nextStatus
        }
    }

    readonly property bool isRepeatActive: {
        if (root.isAzkiaPlayer) return root.azkiaRepeatTrack
        if (!root.activePlayer) return false
        let ls = root.activePlayer.loopStatus
        return ls === "Track" || ls === "Playlist" || ls === 1 || ls === 2
    }

    readonly property real displayPosition: root.currentTrackPosition

    readonly property real displayDuration: {
        if (root.currentTrackDuration > 0) return root.currentTrackDuration
        if (root.activePlayer && typeof root.activePlayer.length !== "undefined" && root.activePlayer.length > 0)
            return root.activePlayer.length
        if (root.activePlayer && root.activePlayer.rawMetadata && root.activePlayer.rawMetadata["mpris:length"]) {
            return root.activePlayer.rawMetadata["mpris:length"] / 1000000.0
        }
        return 0
    }

    readonly property var activePlayer: {
        if (!players || players.length === 0) return null
        if (selectedPlayerIndex >= 0 && selectedPlayerIndex < players.length)
            return players[selectedPlayerIndex]
        return players[0]
    }

    Connections {
        target: root.activePlayer
        ignoreUnknownSignals: true
        function onTrackTitleChanged() {
            if (root.activePlayer && !root.isAzkiaPlayer) {
                let p = root.activePlayer.position || 0
                root.currentTrackPosition = p
                let d = root.activePlayer.length || 0
                if (d <= 0 && root.activePlayer.rawMetadata && root.activePlayer.rawMetadata["mpris:length"]) {
                    d = root.activePlayer.rawMetadata["mpris:length"] / 1000000.0
                }
                if (d > 0) root.currentTrackDuration = d
            }
        }
        function onPositionChanged() {
            if (root.activePlayer && !root.isAzkiaPlayer) {
                let p = root.activePlayer.position || 0
                if (Math.abs(p - root.currentTrackPosition) > 2) {
                    root.currentTrackPosition = p
                }
            }
        }
    }

    readonly property bool isPlaying: activePlayer !== null
        && (activePlayer.playbackState === MprisPlaybackState.Playing || activePlayer.playbackState === 1 || activePlayer.playbackState == "Playing")

    readonly property string activeArtUrl: {
        if (!activePlayer) return ""
        let art = activePlayer.trackArtUrl || ""
        if (art === "" || art.indexOf("noartwork") !== -1) {
            let url = activePlayer.trackUrl || activePlayer.url || ""
            if (!url && activePlayer.rawMetadata) {
                url = activePlayer.rawMetadata["xesam:url"] || ""
            }
            if (url) {
                let match = String(url).match(/(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})/)
                if (match && match[1]) {
                    return "https://img.youtube.com/vi/" + match[1] + "/hqdefault.jpg"
                }
            }
        }
        return art
    }

    readonly property bool isAzkiaPlayer: {
        if (!activePlayer) return true
        let id = (activePlayer.identity || activePlayer.appName || "").toLowerCase()
        return id.indexOf("azkia") !== -1
    }

    onActivePlayerChanged: {
        if (activePlayer) {
            const id = activePlayer.identity || activePlayer.appName || ""
            if (id !== "" && Sys.lastActivePlayerIdentity !== id)
                Sys.lastActivePlayerIdentity = id
        }
    }

    // ==========================================
    // TAB 3: PERFORMANCE DATA & LOGIC
    // ==========================================
    property int cpuCount: 1
    property real memTotalGB: 0
    property real memUsedGB: 0
    property real memPercent: 0
    property real swapTotalGB: 0
    property real swapUsedGB: 0
    property real swapPercent: 0
    property var rawProcesses: []
    property string defaultSort: "ram"
    property string sortBy: defaultSort
    property bool sortAscending: false

    readonly property var sortedProcesses: {
        const list = root.rawProcesses.slice()
        if (root.sortBy === "cpu") {
            list.sort((a, b) => root.sortAscending ? a.cpu - b.cpu : b.cpu - a.cpu)
        } else {
            list.sort((a, b) => root.sortAscending ? a.rss_mb - b.rss_mb : b.rss_mb - a.rss_mb)
        }
        return list
    }

    function cycleSort() {
        if (sortBy === "ram" && !sortAscending) {
            sortAscending = true
        } else if (sortBy === "ram" && sortAscending) {
            sortBy = "cpu"
            sortAscending = false
        } else if (sortBy === "cpu" && !sortAscending) {
            sortAscending = true
        } else {
            sortBy = "ram"
            sortAscending = false
        }
    }

    Timer {
        interval: 2000
        running: root.visible && (root.currentTab === "dashboard" || root.currentTab === "performance")
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            sysProc.running = false
            sysProc.running = true
        }
    }

    Process {
        id: sysProc
        command: ["python3", Sys.scriptPath("sys_monitor.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.cpuCount = data.cpu_count || 1
                    root.memTotalGB = data.mem_total_gb || 0
                    root.memUsedGB = data.mem_used_gb || 0
                    root.memPercent = data.mem_percent || 0
                    root.swapTotalGB = data.swap_total_gb || 0
                    root.swapUsedGB = data.swap_used_gb || 0
                    root.swapPercent = data.swap_percent || 0
                    root.rawProcesses = data.top_processes || []
                } catch (e) {}
            }
        }
    }

    // ==========================================
    // TAB 4: WALLPAPER DATA & LOGIC
    // ==========================================
    property var wallpapersList: []

    Process {
        id: wallpaperProc
        command: ["python3", Sys.scriptPath("wallpaper.py"), "--dir", Sys.wallpaperDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpapersList = JSON.parse(text)
                } catch (e) {
                    root.wallpapersList = []
                }
            }
        }
    }

    Process {
        id: wallDirPickerProc
        command: ["python3", Sys.scriptPath("select_file.py"), "--dir", "Select Wallpaper Directory"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length > 0) {
                    Sys.setWallpaperDir(text.trim())
                }
            }
        }
    }

    function loadWallpapers() {
        wallpaperProc.running = false
        wallpaperProc.running = true
    }

    Connections {
        target: Sys
        function onWallpaperDirChanged() {
            root.loadWallpapers()
        }
    }

    // Lifecycle
    onVisibleChanged: {
        if (visible) {
            if (!currentTab) currentTab = "dashboard"
            shownDate = new Date()
            currentTime = new Date()
            autoSelectPlayer()
            sysProc.running = false
            sysProc.running = true
            sysFetchProc.running = false
            sysFetchProc.running = true
            brightnessGet.running = false
            brightnessGet.running = true
            if (root.isAzkiaPlayer) {
                azkiaFetchStateProc.running = false
                azkiaFetchStateProc.running = true
            }
            if (currentTab === "performance") sysProc.running = true
            if (currentTab === "wallpaper") root.loadWallpapers()
        } else {
            currentTab = "dashboard"
            root.hideTooltip()
        }
    }

    onCurrentTabChanged: {
        root.hideTooltip()
        if (visible) {
            if (currentTab === "performance") sysProc.running = true
            if (currentTab === "wallpaper") root.loadWallpapers()
            if (currentTab === "media") autoSelectPlayer()
        }
    }

    // ==========================================
    // UI LAYOUT
    // ==========================================
    Column {
        anchors.fill: parent
        spacing: 8

        // ===== ROW 1: 5 TAB SELECTOR BAR (CLIPBOARD & NOTES STYLE) =====
        Item {
            width: parent.width
            height: 48

            Row {
                anchors.fill: parent
                spacing: 6

                // Tab List Model
                Repeater {
                    model: [
                        { id: "dashboard", title: "Dashboard", icon: "󰕮" },
                        { id: "media", title: "Media", icon: "󰎈" },
                        { id: "prayer", title: "Prayer Time", icon: "󱠧" },
                        { id: "performance", title: "Performance", icon: "󰻠" },
                        { id: "wallpaper", title: "Wallpaper", icon: "󰸉" },
                        { id: "settings", title: "Settings", icon: "󰒓" }
                    ]

                    Rectangle {
                        id: tabBtn
                        required property var modelData
                        required property int index

                        readonly property bool isActive: root.currentTab === modelData.id
                        readonly property bool isHovered: tabMa.containsMouse

                        width: (parent.width - 30) / 6
                        height: 48
                        radius: 11
                        color: isHovered ? Qt.alpha(Theme.fg, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Column {
                            id: tabCol
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tabBtn.modelData.icon
                                color: tabBtn.isActive ? (tabBtn.isHovered ? Theme.accentHover : Theme.accent) : (tabBtn.isHovered ? Theme.fg : Qt.alpha(Theme.fg, 0.55))
                                font.family: Theme.fontFamily
                                font.pixelSize: 20
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Text {
                                id: tabTxt
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tabBtn.modelData.title
                                color: tabBtn.isActive ? (tabBtn.isHovered ? Theme.accentHover : Theme.accent) : (tabBtn.isHovered ? Theme.fg : Qt.alpha(Theme.fg, 0.55))
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: tabBtn.isActive
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            // Active Underline Indicator Bar
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: 3
                                width: tabBtn.isActive ? tabTxt.implicitWidth + 8 : 0
                                radius: 1.5
                                color: (tabBtn.isActive && tabBtn.isHovered) ? Theme.accentHover : Theme.accent
                                opacity: tabBtn.isActive ? 1 : 0

                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (tabBtn.modelData.id === "settings") {
                                    root.close()
                                    Quickshell.execDetached(["quickshell", "--path", Sys.configDir, "ipc", "call", "settings", "open"])
                                } else {
                                    root.currentTab = tabBtn.modelData.id
                                }
                            }
                        }
                    }
                }
            }
        }

        // ===== TAB CONTENTS CONTAINER =====
        Item {
            width: parent.width
            height: parent.height - 56

            // ==========================================
            // TAB 1: DASHBOARD VIEW
            // ==========================================
            Item {
                anchors.fill: parent
                visible: root.currentTab === "dashboard"

                Row {
                    anchors.fill: parent
                    spacing: 10

                    // ================= COLUMN 1 (LEFT, width 110) =================
                    Column {
                        width: 108
                        height: parent.height
                        spacing: 10

                        // CARD 1: DIGITAL CLOCK & DATE
                        Rectangle {
                            width: parent.width
                            height: 160
                            radius: 14
                            color: Sys.customModuleBg
                            border.width: 1
                            border.color: Sys.customModuleBorder

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatTime(root.currentTime, "HH")
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 38
                                    font.bold: true
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatTime(root.currentTime, "mm")
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 38
                                    font.bold: true
                                }

                                Item {
                                    width: 1
                                    height: 8
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatDate(root.currentTime, "dddd")
                                    color: Theme.magenta
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatDate(root.currentTime, "MMM dd, yyyy")
                                    color: Qt.alpha(Theme.fg, 0.65)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // CARD 2: VOLUME & BRIGHTNESS VERTICAL SLIDERS
                        Rectangle {
                            width: parent.width
                            height: 170
                            radius: 14
                            color: Sys.customModuleBg
                            border.width: 1
                            border.color: Sys.customModuleBorder

                            Row {
                                anchors.centerIn: parent
                                spacing: 12

                                // Volume Slider
                                Column {
                                    spacing: 4
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.sinkVolume + "%"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    Rectangle {
                                        id: dshVolPill
                                        width: 30
                                        height: 105
                                        radius: 8
                                        color: Qt.alpha(Theme.fg, 0.08)
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.fg, 0.06)
                                        clip: true

                                        Rectangle {
                                            id: dshVolFill
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: Math.min(parent.height, Math.max(0, (root.sinkVolume / 100) * parent.height))
                                            radius: 8
                                            color: Theme.accent
                                            Behavior on height { NumberAnimation { duration: 100 } }
                                        }

                                        MouseArea {
                                            id: dshVolMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            function updateVol(mouseY) {
                                                const pct = Math.round(((height - mouseY) / height) * 100)
                                                root.setVolume(Math.max(0, Math.min(150, pct)))
                                            }
                                            onPressed: (mouse) => updateVol(mouse.y)
                                            onPositionChanged: (mouse) => {
                                                if (pressed) updateVol(mouse.y)
                                            }
                                            onEntered: root.showTooltip("Volume: " + root.sinkVolume + "%" + (root.sinkMuted ? " (Muted)" : ""), this)
                                            onExited: root.hideTooltip()
                                        }
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.sinkMuted ? "󰝟" : (root.sinkVolume > 50 ? "󰕾" : (root.sinkVolume > 0 ? "󰖀" : "󰕿"))
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 15

                                        MouseArea {
                                            id: dshVolIconMa
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.toggleMute()
                                            onEntered: root.showTooltip("Volume: " + root.sinkVolume + "%" + (root.sinkMuted ? " (Muted)" : ""), this)
                                            onExited: root.hideTooltip()
                                        }
                                    }
                                }

                                // Brightness Slider
                                Column {
                                    spacing: 4
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.brightnessVal + "%"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    Rectangle {
                                        id: dshBriPill
                                        width: 30
                                        height: 105
                                        radius: 8
                                        color: Qt.alpha(Theme.fg, 0.08)
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.fg, 0.06)
                                        clip: true

                                        Rectangle {
                                            id: dshBriFill
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: Math.min(parent.height, Math.max(0, (root.brightnessVal / 100) * parent.height))
                                            radius: 8
                                            color: Theme.yellow
                                            Behavior on height { NumberAnimation { duration: 100 } }
                                        }

                                        MouseArea {
                                            id: dshBriMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            function updateBri(mouseY) {
                                                const pct = Math.round(((height - mouseY) / height) * 100)
                                                root.setBrightness(Math.max(1, Math.min(100, pct)))
                                            }
                                            onPressed: (mouse) => updateBri(mouse.y)
                                            onPositionChanged: (mouse) => {
                                                if (pressed) updateBri(mouse.y)
                                            }
                                            onEntered: root.showTooltip("Brightness: " + root.brightnessVal + "%", this)
                                            onExited: root.hideTooltip()
                                        }
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "󰃠"
                                        color: Theme.yellow
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 15

                                        MouseArea {
                                            id: dshBriIconMa
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.ArrowCursor
                                            onEntered: root.showTooltip("Brightness: " + root.brightnessVal + "%", this)
                                            onExited: root.hideTooltip()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ================= COLUMN 2 (MIDDLE, width 310) =================
                    Column {
                        width: 310
                        height: parent.height
                        spacing: 10

                        // CARD 1: SYSTEM MONITOR 3 CIRCLE PROGRESS (CPU, RAM, SWAP)
                        Rectangle {
                            width: parent.width
                            height: 115
                            radius: 14
                            color: Sys.customModuleBg
                            border.width: 1
                            border.color: Sys.customModuleBorder

                            Row {
                                anchors.centerIn: parent
                                spacing: 12

                                // CPU GAUGE
                                Item {
                                    width: 82
                                    height: 86

                                    Canvas {
                                        id: dshCpuCanvas
                                        anchors.fill: parent
                                        property real val: Math.min(100, Math.max(0, Sys.cpu)) / 100
                                        property color colorVal: Sys.cpu > 85 ? Theme.red : Theme.yellow
                                        onValChanged: requestPaint()
                                        onColorValChanged: requestPaint()

                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            var cx = width / 2
                                            var cy = height / 2
                                            var r = (width - 12) / 2
                                            var start = -Math.PI / 2
                                            var end = start + (val * 2 * Math.PI)

                                            ctx.beginPath()
                                            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                            ctx.strokeStyle = Qt.alpha(Theme.fg, 0.1)
                                            ctx.lineWidth = 5.5
                                            ctx.stroke()

                                            if (val > 0) {
                                                ctx.beginPath()
                                                ctx.arc(cx, cy, r, start, end)
                                                ctx.strokeStyle = colorVal
                                                ctx.lineWidth = 7
                                                ctx.lineCap = "round"
                                                ctx.stroke()
                                            }
                                        }
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "CPU"
                                            color: Qt.alpha(Theme.fg, 0.75)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(Sys.cpu) + "%"
                                            color: Sys.cpu > 85 ? Theme.red : Theme.yellow
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: dshCpuMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.ArrowCursor
                                        onEntered: root.showTooltip("CPU: " + Math.round(Sys.cpu) + "%", this)
                                        onExited: root.hideTooltip()
                                    }
                                }

                                // RAM GAUGE
                                Item {
                                    width: 82
                                    height: 86

                                    Canvas {
                                        id: dshMemCanvas
                                        anchors.fill: parent
                                        property real val: Math.min(100, Math.max(0, root.memPercent)) / 100
                                        property color colorVal: root.memPercent > 85 ? Theme.red : Theme.accent
                                        onValChanged: requestPaint()
                                        onColorValChanged: requestPaint()

                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            var cx = width / 2
                                            var cy = height / 2
                                            var r = (width - 12) / 2
                                            var start = -Math.PI / 2
                                            var end = start + (val * 2 * Math.PI)

                                            ctx.beginPath()
                                            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                            ctx.strokeStyle = Qt.alpha(Theme.fg, 0.1)
                                            ctx.lineWidth = 5.5
                                            ctx.stroke()

                                            if (val > 0) {
                                                ctx.beginPath()
                                                ctx.arc(cx, cy, r, start, end)
                                                ctx.strokeStyle = colorVal
                                                ctx.lineWidth = 7
                                                ctx.lineCap = "round"
                                                ctx.stroke()
                                            }
                                        }
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "RAM"
                                            color: Qt.alpha(Theme.fg, 0.75)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(root.memPercent) + "%"
                                            color: root.memPercent > 85 ? Theme.red : Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: dshRamMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.ArrowCursor
                                        onEntered: {
                                            var u = Number(root.memUsedGB || 0).toFixed(1)
                                            var t = Number(root.memTotalGB || 0).toFixed(1)
                                            root.showTooltip("RAM: " + Math.round(root.memPercent) + "% (" + u + " GB / " + t + " GB)", this)
                                        }
                                        onExited: root.hideTooltip()
                                    }
                                }

                                // SWAP GAUGE
                                Item {
                                    width: 82
                                    height: 86

                                    Canvas {
                                        id: dshSwapCanvas
                                        anchors.fill: parent
                                        property real val: Math.min(100, Math.max(0, root.swapPercent)) / 100
                                        property color colorVal: root.swapPercent > 85 ? Theme.red : Theme.cyan
                                        onValChanged: requestPaint()
                                        onColorValChanged: requestPaint()

                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            var cx = width / 2
                                            var cy = height / 2
                                            var r = (width - 12) / 2
                                            var start = -Math.PI / 2
                                            var end = start + (val * 2 * Math.PI)

                                            ctx.beginPath()
                                            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                            ctx.strokeStyle = Qt.alpha(Theme.fg, 0.1)
                                            ctx.lineWidth = 5.5
                                            ctx.stroke()

                                            if (val > 0) {
                                                ctx.beginPath()
                                                ctx.arc(cx, cy, r, start, end)
                                                ctx.strokeStyle = colorVal
                                                ctx.lineWidth = 7
                                                ctx.lineCap = "round"
                                                ctx.stroke()
                                            }
                                        }
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "SWAP"
                                            color: Qt.alpha(Theme.fg, 0.75)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(root.swapPercent) + "%"
                                            color: root.swapPercent > 85 ? Theme.red : Theme.cyan
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: dshSwapMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.ArrowCursor
                                        onEntered: {
                                            if (root.swapTotalGB > 0) {
                                                var su = Number(root.swapUsedGB || 0).toFixed(1)
                                                var st = Number(root.swapTotalGB || 0).toFixed(1)
                                                root.showTooltip("SWAP: " + Math.round(root.swapPercent) + "% (" + su + " GB / " + st + " GB)", this)
                                            } else {
                                                root.showTooltip("SWAP: None", this)
                                            }
                                        }
                                        onExited: root.hideTooltip()
                                    }
                                }
                            }
                        }

                        // CARD 2: CALENDAR (5 ROWS COMPACT)
                        Rectangle {
                            width: parent.width
                            height: 215
                            radius: 14
                            color: Sys.customModuleBg
                            border.width: 1
                            border.color: Sys.customModuleBorder

                            function getDays() {
                                var year = root.shownDate.getFullYear()
                                var month = root.shownDate.getMonth()
                                var firstDay = new Date(year, month, 1).getDay()
                                var daysInMonth = new Date(year, month + 1, 0).getDate()
                                var daysInPrevMonth = new Date(year, month, 0).getDate()
                                var days = []

                                for (var i = firstDay - 1; i >= 0; i--) {
                                    days.push({ day: daysInPrevMonth - i, currentMonth: false })
                                }
                                for (var i = 1; i <= daysInMonth; i++) {
                                    days.push({ day: i, currentMonth: true })
                                }
                                var totalCells = 35
                                var nextDays = totalCells - days.length
                                for (var i = 1; i <= nextDays; i++) {
                                    days.push({ day: i, currentMonth: false })
                                }
                                return days.slice(0, 35)
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 4

                                // Month & Year Navigation
                                Item {
                                    width: parent.width
                                    height: 26

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 4
                                        text: Qt.formatDate(root.shownDate, "MMMM yyyy")
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                    }

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.right: parent.right
                                        spacing: 4

                                        Rectangle {
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: prevMonthMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰅁"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                            }

                                            MouseArea {
                                                id: prevMonthMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.shownDate = new Date(root.shownDate.getFullYear(), root.shownDate.getMonth() - 1, 1)
                                            }
                                        }

                                        Rectangle {
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: nextMonthMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰅂"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                            }

                                            MouseArea {
                                                id: nextMonthMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.shownDate = new Date(root.shownDate.getFullYear(), root.shownDate.getMonth() + 1, 1)
                                            }
                                        }
                                    }
                                }

                                // Day Names Header
                                Row {
                                    width: parent.width
                                    height: 18

                                    Repeater {
                                        model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                                        Item {
                                            width: parent.width / 7
                                            height: parent.height

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData
                                                color: Qt.alpha(Theme.fg, 0.5)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }
                                    }
                                }

                                // Days Grid (5 Rows x 7 Columns = 35 Cells)
                                Grid {
                                    width: parent.width
                                    columns: 7
                                    rows: 5
                                    spacing: 0

                                    Repeater {
                                        model: parent.parent.parent.getDays()

                                        Item {
                                            id: dayCellItem
                                            width: parent.width / 7
                                            height: 28

                                            readonly property bool isToday: {
                                                var now = root.currentTime
                                                return modelData.currentMonth &&
                                                       modelData.day === now.getDate() &&
                                                       root.shownDate.getMonth() === now.getMonth() &&
                                                       root.shownDate.getFullYear() === now.getFullYear()
                                            }

                                            Rectangle {
                                                id: dayCellBg
                                                anchors.centerIn: parent
                                                width: 24
                                                height: 24
                                                radius: 12
                                                color: {
                                                    if (dayCellItem.isToday) {
                                                        return dayCellMa.containsMouse ? Theme.accentHover : Theme.accent
                                                    } else {
                                                        return dayCellMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                                    }
                                                }
                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.day
                                                    color: {
                                                        if (dayCellItem.isToday) {
                                                            return Theme.bg
                                                        } else if (dayCellMa.containsMouse) {
                                                            return Theme.fg
                                                        } else {
                                                            return modelData.currentMonth ? Theme.fg : Qt.alpha(Theme.fg, 0.25)
                                                        }
                                                    }
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.bold: dayCellItem.isToday
                                                }
                                            }

                                            MouseArea {
                                                id: dayCellMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ================= COLUMN 3 (RIGHT, width 220) =================
                    Column {
                        width: 220
                        height: parent.height
                        spacing: 10

                        // CARD 1: USER AVATAR & SYSTEM SPECS
                        Rectangle {
                            width: parent.width
                            height: 85
                            radius: 14
                            color: Sys.customModuleBg
                            border.width: 1
                            border.color: Sys.customModuleBorder

                            Row {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 10

                                // Avatar Circle (Full size: 66x66)
                                Rectangle {
                                    id: dshAvatarWrapper
                                    width: 66
                                    height: 66
                                    radius: 33
                                    color: "transparent"
                                    border.width: 2.5
                                    border.color: Theme.accent
                                    anchors.verticalCenter: parent.verticalCenter

                                    Item {
                                        anchors.centerIn: parent
                                        width: 58
                                        height: 58

                                        Image {
                                            id: dshAvatarImg
                                            anchors.fill: parent
                                            source: root.visible ? Sys.userAvatar : ""
                                            sourceSize: Qt.size(58, 58)
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            asynchronous: true
                                            cache: false
                                            visible: false
                                        }

                                        Rectangle {
                                            id: dshAvatarMask
                                            anchors.fill: parent
                                            radius: 29
                                            color: "black"
                                            visible: false
                                            antialiasing: true
                                        }

                                        OpacityMask {
                                            anchors.fill: parent
                                            source: dshAvatarImg
                                            maskSource: dshAvatarMask
                                        }
                                    }

                                    MouseArea {
                                        id: dshAvatarMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.showTooltip("User : " + (root.sysInfo.user || Sys.userName || "User"), this)
                                        onExited: root.hideTooltip()
                                    }
                                }

                                // Specs List (Icons with distinct colors, with tooltips)
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 76
                                    spacing: 2.5

                                    // Distro
                                    Item {
                                        width: parent.width
                                        height: 16

                                        Row {
                                            spacing: 6
                                            width: parent.width
                                            anchors.verticalCenter: parent.verticalCenter
                                            Text {
                                                text: Sys.getDistroIcon(root.sysInfo ? root.sysInfo.distro : "")
                                                color: Sys.getDistroColor(root.sysInfo ? root.sysInfo.distro : "")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: (root.sysInfo.distro || "Fedora Linux").replace(/\s*\([^)]*\)/gi, "").trim()
                                                color: Theme.fg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.bold: true
                                                elide: Text.ElideRight
                                                width: parent.width - 20
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: dshDistroMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: root.showTooltip("Distro : " + (root.sysInfo.distro || "Linux"), this)
                                            onExited: root.hideTooltip()
                                        }
                                    }

                                    // WM
                                    Item {
                                        width: parent.width
                                        height: 16

                                        Row {
                                            spacing: 6
                                            width: parent.width
                                            anchors.verticalCenter: parent.verticalCenter
                                            Text {
                                                text: "󱂬"
                                                color: Theme.magenta
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: root.sysInfo.wm || "BSPWM"
                                                color: Qt.alpha(Theme.fg, 0.85)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.bold: true
                                                elide: Text.ElideRight
                                                width: parent.width - 20
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: dshWmMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: root.showTooltip("Window Manager : " + (root.sysInfo.wm || "BSPWM"), this)
                                            onExited: root.hideTooltip()
                                        }
                                    }

                                    // Shell
                                    Item {
                                        width: parent.width
                                        height: 16

                                        Row {
                                            spacing: 6
                                            width: parent.width
                                            anchors.verticalCenter: parent.verticalCenter
                                            Text {
                                                text: "󰒓"
                                                color: Theme.green
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: root.sysInfo.shell || "Azkia Shell"
                                                color: Qt.alpha(Theme.fg, 0.85)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.bold: true
                                                elide: Text.ElideRight
                                                width: parent.width - 20
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: dshShellMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: root.showTooltip("Desktop Shell : " + (root.sysInfo.shell || "Azkia Shell"), this)
                                            onExited: root.hideTooltip()
                                        }
                                    }

                                    // Uptime
                                    Item {
                                        width: parent.width
                                        height: 16

                                        Row {
                                            spacing: 6
                                            width: parent.width
                                            anchors.verticalCenter: parent.verticalCenter
                                            Text {
                                                text: "󰅐"
                                                color: Theme.yellow
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: root.sysInfo.uptime || "0m"
                                                color: Qt.alpha(Theme.fg, 0.85)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.bold: true
                                                elide: Text.ElideRight
                                                width: parent.width - 20
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: dshUptimeMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: root.showTooltip("Uptime : " + (root.sysInfo.uptime_full || root.sysInfo.uptime || "0m"), this)
                                            onExited: root.hideTooltip()
                                        }
                                    }
                                }
                            }
                        }

                        // CARD 2: MEDIA PLAYER (ALL CENTER ALIGNED)
                        Rectangle {
                            width: parent.width
                            height: 245
                            radius: 14
                            color: Sys.customModuleBg
                            border.width: 1
                            border.color: Sys.customModuleBorder

                            // Open Standalone Audio Player Window Button (Top-Right Inside Card - Only for Azkia Player)
                            Rectangle {
                                width: 22
                                height: 22
                                radius: 6
                                color: dshCardOpenPlayerMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                border.width: 1
                                border.color: Qt.alpha(Theme.accent, 0.3)
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 7
                                z: 20
                                visible: root.isAzkiaPlayer

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰉋"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: dshCardOpenPlayerMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.close()
                                        Quickshell.execDetached(["quickshell", "--path", Sys.configDir, "ipc", "call", "audioplayer", "open"])
                                    }
                                }
                            }

                            // 0. Audio Source (Player Identity) at the very top
                            Text {
                                id: dshMediaSourceText
                                anchors.top: parent.top
                                anchors.topMargin: 8
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.activePlayer ? (root.activePlayer.identity || root.activePlayer.appName || "Media") : "Azkia Audio Player"
                                color: Qt.alpha(Theme.fg, 0.55)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            // 1. Audio Equalizer Visualizer Bars (Exact Match to Media Tab)
                            Item {
                                anchors.top: dshMediaSourceText.bottom
                                anchors.bottom: dshMediaTrackInfoCol.top
                                anchors.left: parent.left
                                anchors.right: parent.right

                                Row {
                                    anchors.centerIn: parent
                                    height: 24
                                    spacing: 4

                                    Repeater {
                                        model: 22
                                        Rectangle {
                                            required property int index
                                            width: 4
                                            height: {
                                                if (!root.isPlaying) return 4
                                                if (Sys.cavaValues && Sys.cavaValues.length > index) {
                                                    let val = Sys.cavaValues[index]
                                                    if (val > 0) {
                                                        return Math.max(4, Math.min(24, Math.round(4 + (val / 100.0) * 20)))
                                                    }
                                                }
                                                let centerDist = Math.abs(index - 11)
                                                let wave = (Math.sin(root.animPhase + index * 0.45) + 1.0) * 0.5
                                                let maxH = 24 - centerDist * 0.6
                                                return Math.max(4, Math.min(24, Math.round(4 + wave * (maxH - 4))))
                                            }
                                            anchors.verticalCenter: parent.verticalCenter
                                            radius: 2
                                            color: Theme.accent

                                            Behavior on height {
                                                NumberAnimation { duration: 50; easing.type: Easing.OutQuad }
                                            }
                                        }
                                    }
                                }
                            }

                            // 2. Thumbnail, Track Title & Artist (Directly above progress bar)
                            Column {
                                id: dshMediaTrackInfoCol
                                anchors.bottom: dshMediaBottomControls.top
                                anchors.bottomMargin: 8
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 3

                                // Round Thumbnail (66x66)
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 66
                                    height: 66
                                    radius: 33
                                    color: "transparent"
                                    border.width: 2.5
                                    border.color: Theme.accent

                                    Item {
                                        anchors.centerIn: parent
                                        width: 58
                                        height: 58

                                        Image {
                                            id: dshMediaArtImg
                                            anchors.fill: parent
                                            source: root.activeArtUrl
                                            sourceSize: Qt.size(58, 58)
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            asynchronous: true
                                            visible: false
                                        }

                                        Rectangle {
                                            id: dshMediaArtMask
                                            anchors.fill: parent
                                            radius: 29
                                            color: "black"
                                            visible: false
                                            antialiasing: true
                                        }

                                        OpacityMask {
                                            anchors.fill: parent
                                            source: dshMediaArtImg
                                            maskSource: dshMediaArtMask
                                            visible: root.activeArtUrl !== ""
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰎈"
                                            color: Qt.alpha(Theme.accent, 0.6)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 24
                                            visible: root.activeArtUrl === ""
                                        }
                                    }
                                }

                                // Track Title (Centered)
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: (root.activePlayer && root.activePlayer.trackTitle) ? root.activePlayer.trackTitle : "No Media Playing"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                // Track Artist / Channel
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: (root.activePlayer && root.activePlayer.trackArtist) ? root.activePlayer.trackArtist : ""
                                    color: Qt.alpha(Theme.fg, 0.6)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }
                            }

                            // Bottom Section: Anchored Progress Bar & 3 Control Buttons
                            Column {
                                id: dshMediaBottomControls
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 8
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                // 4. Progress Bar & Timestamps
                                Row {
                                    width: parent.width
                                    spacing: 5
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Text {
                                        text: root.formatTime(root.displayPosition)
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        height: 4
                                        radius: 2
                                        width: parent.width - 64
                                        color: Qt.alpha(Theme.fg, 0.1)
                                        anchors.verticalCenter: parent.verticalCenter

                                        Rectangle {
                                            height: parent.height
                                            radius: 2
                                            width: (root.displayDuration > 0)
                                                ? Math.min(parent.width, Math.max(0, (root.displayPosition / root.displayDuration) * parent.width))
                                                : 0
                                            color: Theme.accent
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: (mouse) => {
                                                if (root.displayDuration > 0) {
                                                    let targetSec = (mouse.x / width) * root.displayDuration
                                                    if (root.isAzkiaPlayer) {
                                                        root.currentTrackPosition = targetSec
                                                        Quickshell.execDetached(["python3", Sys.scriptPath("azkia_audio_player.py"), "--seek", targetSec.toString()])
                                                    } else if (root.activePlayer && root.activePlayer.canSeek) {
                                                        root.activePlayer.position = targetSec
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: root.formatTime(root.displayDuration)
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                // 5. 3 Control Buttons (Centered & Fully Interactive)
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 14

                                    // Previous
                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: dshPrevMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.06)
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰒮"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                        }
                                        MouseArea {
                                            id: dshPrevMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.playbackPrev()
                                            onEntered: root.showTooltip("Previous Track", this)
                                            onExited: root.hideTooltip()
                                        }
                                    }

                                    // Play / Pause Circle Button
                                    Rectangle {
                                        width: 34
                                        height: 34
                                        radius: 17
                                        color: dshPlayMa.containsMouse ? Theme.accentHover : Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.isPlaying ? "󰏤" : "󰐊"
                                            color: Theme.bg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                            font.bold: true
                                        }
                                        MouseArea {
                                            id: dshPlayMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.togglePlayback()
                                            onEntered: root.showTooltip(root.isPlaying ? "Pause" : "Play", this)
                                            onExited: root.hideTooltip()
                                        }
                                    }

                                    // Next Track
                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: dshNextMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.06)
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰒭"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                        }
                                        MouseArea {
                                            id: dshNextMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.playbackNext()
                                            onEntered: root.showTooltip("Next Track", this)
                                            onExited: root.hideTooltip()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // TAB 2: MEDIA VIEW
            // ==========================================
            Item {
                anchors.fill: parent
                visible: root.currentTab === "media"

                Column {
                    anchors.fill: parent
                    spacing: 12

                    // Player Selection Sub-Bar
                    Item {
                        width: parent.width
                        height: 32

                        // Players Pills (Always visible)
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Repeater {
                                model: root.players.length > 0 ? root.players : [{ identity: "Azkia Audio Player" }]

                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property bool isCur: root.selectedPlayerIndex === index

                                    height: 28
                                    width: playerPillTxt.implicitWidth + 24
                                    radius: 14
                                    color: isCur ? Qt.alpha(Theme.accent, 0.25) : (pillMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05))
                                    border.width: 1
                                    border.color: isCur ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                                    Text {
                                        id: playerPillTxt
                                        anchors.centerIn: parent
                                        text: (modelData.identity || modelData.appName || "Player " + (index + 1))
                                        color: isCur ? Theme.accent : Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: isCur
                                    }

                                    MouseArea {
                                        id: pillMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedPlayerIndex = index

                                        ToolTip {
                                            id: pillTip
                                            visible: pillMa.containsMouse
                                            delay: 250
                                            text: "Switch to " + (modelData.identity || modelData.appName || "Player")
                                            contentItem: Text {
                                                text: pillTip.text
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

                    // Main Media Player Card (Matching Azkia Audio Player Style)
                    Rectangle {
                        width: parent.width
                        height: parent.height - 44
                        radius: 16
                        color: Sys.customModuleBg
                        border.width: 1
                        border.color: Sys.customModuleBorder

                        Row {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 20

                            // --- 1. CIRCULAR ALBUM ARTWORK ---
                            Item {
                                id: artCircleContainer
                                width: 190
                                height: 190
                                anchors.verticalCenter: parent.verticalCenter

                                // Base Background Circle
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Qt.alpha(Theme.fg, 0.08)
                                    antialiasing: true
                                }

                                // Cover Image
                                Image {
                                    id: coverImg
                                    anchors.fill: parent
                                    source: root.activeArtUrl
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                    asynchronous: true
                                    visible: false
                                }

                                // Mask Circle Shape
                                Rectangle {
                                    id: artMaskCircle
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "black"
                                    visible: false
                                    antialiasing: true
                                }

                                // Masked Circle Image
                                OpacityMask {
                                    anchors.fill: parent
                                    source: coverImg
                                    maskSource: artMaskCircle
                                    visible: root.activeArtUrl !== "" && coverImg.status === Image.Ready
                                }

                                // Fallback Music Icon
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰎈"
                                    color: Qt.alpha(Theme.fg, 0.35)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 64
                                    visible: root.activeArtUrl === "" || coverImg.status !== Image.Ready
                                }

                                // Accent Border Ring Overlay
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 2.5
                                    border.color: root.isPlaying ? Theme.accent : Qt.alpha(Theme.fg, 0.2)
                                    antialiasing: true

                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                }
                            }

                            // --- 2. RIGHT COLUMN: METADATA, VISUALIZER & CONTROLS ---
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - artCircleContainer.width - 20
                                spacing: 8

                                // Player Identity Badge & Playing Status
                                Row {
                                    spacing: 8

                                    Rectangle {
                                        height: 22
                                        width: playerChipText.implicitWidth + 16
                                        radius: 11
                                        color: Qt.alpha(Theme.accent, 0.22)
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.accent, 0.4)

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                text: "♪"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                            }
                                            Text {
                                                id: playerChipText
                                                text: root.activePlayer ? (root.activePlayer.identity || root.activePlayer.appName || "Media Player") : "Media Player"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4

                                        Rectangle {
                                            width: 6
                                            height: 6
                                            radius: 3
                                            color: root.isPlaying ? "#a6da95" : "#ed8796"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: root.isPlaying ? "• Playing" : "• Paused"
                                            color: root.isPlaying ? "#a6da95" : Qt.alpha(Theme.fg, 0.5)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // Track Title
                                Text {
                                    width: parent.width
                                    text: (root.activePlayer && root.activePlayer.trackTitle) ? root.activePlayer.trackTitle : "No Track Selected"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                // Artist / Album Subtitle
                                Text {
                                    width: parent.width
                                    text: {
                                        if (!root.activePlayer) return "Play music in browser or player"
                                        let artist = root.activePlayer.trackArtist || "Unknown Artist"
                                        let album = root.activePlayer.trackAlbum || ""
                                        return album ? (artist + " [" + album + "]") : artist
                                    }
                                    color: Qt.alpha(Theme.fg, 0.65)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }

                                // Audio Equalizer Visualizer Bars
                                Item {
                                    width: parent.width
                                    height: 28

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        height: 24

                                        Repeater {
                                            model: 22
                                            Rectangle {
                                                required property int index
                                                width: 4
                                                height: {
                                                    if (!root.isPlaying) return 4
                                                    if (Sys.cavaValues && Sys.cavaValues.length > index) {
                                                        let val = Sys.cavaValues[index]
                                                        if (val > 0) {
                                                            return Math.max(4, Math.min(24, Math.round(4 + (val / 100.0) * 20)))
                                                        }
                                                    }
                                                    let centerDist = Math.abs(index - 11)
                                                    let wave = (Math.sin(root.animPhase + index * 0.45) + 1.0) * 0.5
                                                    let maxH = 24 - centerDist * 0.6
                                                    return Math.max(4, Math.min(24, Math.round(4 + wave * (maxH - 4))))
                                                }
                                                anchors.verticalCenter: parent.verticalCenter
                                                radius: 2
                                                color: Theme.accent

                                                Behavior on height {
                                                    NumberAnimation { duration: 50; easing.type: Easing.OutQuad }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Track Progress Timeline Bar
                                Column {
                                    width: parent.width
                                    spacing: 4

                                    Item {
                                        width: parent.width
                                        height: 14

                                        Text {
                                            anchors.left: parent.left
                                            text: root.formatTime(root.displayPosition)
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }

                                        Text {
                                            anchors.right: parent.right
                                            text: root.formatTime(root.displayDuration)
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                    }

                                    // Interactive Progress Track Bar
                                    Rectangle {
                                        id: dshMediaProgressTrack
                                        width: parent.width
                                        height: (dshMediaTrackMa.containsMouse || dshMediaTrackMa.pressed) ? 7 : 5
                                        radius: height / 2
                                        color: Qt.alpha(Theme.fg, 0.15)

                                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }

                                        // Fill Track
                                        Rectangle {
                                            height: parent.height
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: {
                                                if (root.displayDuration <= 0) return 0
                                                let p = Math.min(1.0, Math.max(0.0, root.displayPosition / root.displayDuration))
                                                return parent.width * p
                                            }
                                            radius: height / 2
                                            color: (dshMediaTrackMa.containsMouse || dshMediaTrackMa.pressed) ? Theme.accentHover : Theme.accent
                                        }

                                        // Thumb Handle
                                        Rectangle {
                                            width: (dshMediaTrackMa.containsMouse || dshMediaTrackMa.pressed) ? 11 : 9
                                            height: width
                                            radius: width / 2
                                            color: Theme.accent
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: {
                                                if (root.displayDuration <= 0) return 0
                                                let p = Math.min(1.0, Math.max(0.0, root.displayPosition / root.displayDuration))
                                                return Math.max(0, Math.min(parent.width - width, parent.width * p - width / 2))
                                            }
                                        }

                                        MouseArea {
                                            id: dshMediaTrackMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => {
                                                if (root.displayDuration > 0) {
                                                    let targetSec = (mouse.x / width) * root.displayDuration
                                                    if (root.isAzkiaPlayer) {
                                                        root.currentTrackPosition = targetSec
                                                        Quickshell.execDetached(["python3", Sys.scriptPath("azkia_audio_player.py"), "--seek", targetSec.toString()])
                                                    } else if (root.activePlayer && root.activePlayer.canSeek) {
                                                        root.activePlayer.position = targetSec
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Bottom Controls Row: Playback Buttons (Left) + Repeat / Shuffle (Right)
                                Item {
                                    width: parent.width
                                    height: 44

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 12

                                        // Previous
                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: dshMediaPrevMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰒮"
                                                color: Theme.fg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14
                                            }
                                            MouseArea {
                                                id: dshMediaPrevMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.playbackPrev()

                                                ToolTip {
                                                    id: prevTip
                                                    visible: dshMediaPrevMa.containsMouse
                                                    delay: 200
                                                    text: "Previous Track"
                                                    contentItem: Text {
                                                        text: prevTip.text
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

                                        // Play / Pause Circle
                                        Rectangle {
                                            width: 44
                                            height: 44
                                            radius: 22
                                            color: dshMediaPlayMa.containsMouse ? Theme.accentHover : Theme.accent
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.isPlaying ? "󰏤" : "󰐊"
                                                color: Theme.bg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 18
                                                font.bold: true
                                            }
                                            MouseArea {
                                                id: dshMediaPlayMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.togglePlayback()

                                                ToolTip {
                                                    id: playTip
                                                    visible: dshMediaPlayMa.containsMouse
                                                    delay: 200
                                                    text: root.isPlaying ? "Pause" : "Play"
                                                    contentItem: Text {
                                                        text: playTip.text
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

                                        // Next
                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: dshMediaNextMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰒭"
                                                color: Theme.fg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14
                                            }
                                            MouseArea {
                                                id: dshMediaNextMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.playbackNext()

                                                ToolTip {
                                                    id: nextTip
                                                    visible: dshMediaNextMa.containsMouse
                                                    delay: 200
                                                    text: "Next Track"
                                                    contentItem: Text {
                                                        text: nextTip.text
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

                                        // Stop Button
                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: dshMediaStopMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰓛"
                                                color: Theme.fg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                            }
                                            MouseArea {
                                                id: dshMediaStopMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.activePlayer) {
                                                        if (root.activePlayer.canStop) root.activePlayer.stop()
                                                        else if (typeof root.activePlayer.stop === "function") root.activePlayer.stop()
                                                        else if (root.isPlaying) root.togglePlayback()
                                                    }
                                                }

                                                ToolTip {
                                                    id: stopTip
                                                    visible: dshMediaStopMa.containsMouse
                                                    delay: 200
                                                    text: "Stop Playback"
                                                    contentItem: Text {
                                                        text: stopTip.text
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

                                    // Right Controls: Open Folder & Repeat (Only visible for Azkia Audio Player)
                                    Row {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        visible: root.isAzkiaPlayer

                                        // Open Folder / Standalone Window Button
                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: dshMediaOpenAppMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰉋"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }
                                            MouseArea {
                                                id: dshMediaOpenAppMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.close()
                                                    Quickshell.execDetached(["quickshell", "--path", Sys.configDir, "ipc", "call", "audioplayer", "open"])
                                                }

                                                ToolTip {
                                                    id: openAppTip
                                                    visible: dshMediaOpenAppMa.containsMouse
                                                    delay: 200
                                                    text: "Open Azkia Audio Player"
                                                    contentItem: Text {
                                                        text: openAppTip.text
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

                                        // Repeat Button
                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: root.isRepeatActive ? Qt.alpha(Theme.accent, 0.25) : (dshMediaRepeatMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08))
                                            border.width: 1
                                            border.color: root.isRepeatActive ? Theme.accent : (dshMediaRepeatMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Qt.alpha(Theme.fg, 0.15))

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑖"
                                                color: root.isRepeatActive ? Theme.accent : Qt.alpha(Theme.fg, 0.65)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }
                                            MouseArea {
                                                id: dshMediaRepeatMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleRepeat()

                                                ToolTip {
                                                    id: repeatTip
                                                    visible: dshMediaRepeatMa.containsMouse
                                                    delay: 200
                                                    text: root.isRepeatActive ? "Repeat Track: On" : "Repeat Track: Off"
                                                    contentItem: Text {
                                                        text: repeatTip.text
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
                        }
                    }
                }
            }

            // ==========================================
            // TAB: PRAYER TIME VIEW (EQURAN.ID API)
            // ==========================================
            PrayerTimeView {
                id: prayerTimeView
                anchors.fill: parent
                visible: root.currentTab === "prayer"
                isTabActive: root.visible && root.currentTab === "prayer"
            }

            // ==========================================
            // TAB 3: PERFORMANCE (SYSTEM MONITOR) VIEW
            // ==========================================
            Item {
                anchors.fill: parent
                visible: root.currentTab === "performance"

                Column {
                    anchors.fill: parent
                    spacing: 12

                    // 1 ROW OF 3 ENLARGED CIRCLES (CPU | RAM | SWAP)
                    Row {
                        width: parent.width
                        height: 106

                        // 1. CPU CIRCLE
                        Item {
                            width: parent.width / 3
                            height: parent.height

                            Item {
                                width: 100
                                height: 100
                                anchors.centerIn: parent

                                Canvas {
                                    id: cpuCanvas
                                    anchors.fill: parent
                                    property real val: Math.min(100, Math.max(0, Sys.cpu)) / 100
                                    property color colorVal: Sys.cpu > 85 ? Theme.red : Theme.yellow
                                    onValChanged: requestPaint()
                                    onColorValChanged: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        var cx = width / 2
                                        var cy = height / 2
                                        var r = (width - 12) / 2
                                        var start = -Math.PI / 2
                                        var end = start + (val * 2 * Math.PI)

                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                        ctx.strokeStyle = Qt.alpha(Theme.fg, 0.1)
                                        ctx.lineWidth = 6
                                        ctx.stroke()

                                        if (val > 0) {
                                            ctx.beginPath()
                                            ctx.arc(cx, cy, r, start, end)
                                            ctx.strokeStyle = colorVal
                                            ctx.lineWidth = 7.5
                                            ctx.lineCap = "round"
                                            ctx.stroke()
                                        }
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "CPU"
                                        color: Qt.alpha(Theme.fg, 0.75)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Math.round(Sys.cpu) + "%"
                                        color: Sys.cpu > 85 ? Theme.red : Theme.yellow
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.cpuCount + " Cores"
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }

                        // 2. RAM CIRCLE
                        Item {
                            width: parent.width / 3
                            height: parent.height

                            Item {
                                width: 100
                                height: 100
                                anchors.centerIn: parent

                                Canvas {
                                    id: memCanvas
                                    anchors.fill: parent
                                    property real val: Math.min(100, Math.max(0, root.memPercent)) / 100
                                    property color colorVal: root.memPercent > 85 ? Theme.red : Theme.accent
                                    onValChanged: requestPaint()
                                    onColorValChanged: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        var cx = width / 2
                                        var cy = height / 2
                                        var r = (width - 12) / 2
                                        var start = -Math.PI / 2
                                        var end = start + (val * 2 * Math.PI)

                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                        ctx.strokeStyle = Qt.alpha(Theme.fg, 0.1)
                                        ctx.lineWidth = 6
                                        ctx.stroke()

                                        if (val > 0) {
                                            ctx.beginPath()
                                            ctx.arc(cx, cy, r, start, end)
                                            ctx.strokeStyle = colorVal
                                            ctx.lineWidth = 7.5
                                            ctx.lineCap = "round"
                                            ctx.stroke()
                                        }
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "RAM"
                                        color: Qt.alpha(Theme.fg, 0.75)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Math.round(root.memPercent) + "%"
                                        color: root.memPercent > 85 ? Theme.red : Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.memUsedGB.toFixed(1) + " / " + root.memTotalGB.toFixed(1) + " GB"
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                }
                            }
                        }

                        // 3. SWAP CIRCLE
                        Item {
                            width: parent.width / 3
                            height: parent.height

                            Item {
                                width: 100
                                height: 100
                                anchors.centerIn: parent

                                Canvas {
                                    id: swapCanvas
                                    anchors.fill: parent
                                    property real val: Math.min(100, Math.max(0, root.swapPercent)) / 100
                                    property color colorVal: root.swapPercent > 85 ? Theme.red : Theme.cyan
                                    onValChanged: requestPaint()
                                    onColorValChanged: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        var cx = width / 2
                                        var cy = height / 2
                                        var r = (width - 12) / 2
                                        var start = -Math.PI / 2
                                        var end = start + (val * 2 * Math.PI)

                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                        ctx.strokeStyle = Qt.alpha(Theme.fg, 0.1)
                                        ctx.lineWidth = 6
                                        ctx.stroke()

                                        if (val > 0) {
                                            ctx.beginPath()
                                            ctx.arc(cx, cy, r, start, end)
                                            ctx.strokeStyle = colorVal
                                            ctx.lineWidth = 7.5
                                            ctx.lineCap = "round"
                                            ctx.stroke()
                                        }
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "SWAP"
                                        color: Qt.alpha(Theme.fg, 0.75)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Math.round(root.swapPercent) + "%"
                                        color: Theme.cyan
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.swapUsedGB.toFixed(1) + " / " + root.swapTotalGB.toFixed(1) + " GB"
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                }
                            }
                        }
                    }

                    // PROCESSES TABLE (MATCHING SYSTEMMONITORPOPUP EXACTLY)
                    Column {
                        width: parent.width
                        height: parent.height - 124
                        spacing: 8

                        // Header & Interactive Sort Controls
                        Item {
                            width: parent.width
                            height: 28

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Process"
                                color: Qt.alpha(Theme.fg, 0.6)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                // CPU Sort Indicator Pill
                                Rectangle {
                                    height: 24
                                    width: 60
                                    radius: 14
                                    color: root.sortBy === "cpu" ? Theme.yellow : (cpuMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05))
                                    border.width: 0
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.fill: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "CPU"
                                        color: root.sortBy === "cpu" ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: cpuMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.sortBy !== "cpu") {
                                                root.sortBy = "cpu"
                                                dashProcListView.userScrollY = 0
                                                dashProcListView.contentY = 0
                                            }
                                        }
                                    }
                                }

                                // RAM Sort Indicator Pill
                                Rectangle {
                                    height: 24
                                    width: 80
                                    radius: 14
                                    color: root.sortBy === "ram" ? Theme.accent : (ramMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05))
                                    border.width: 0
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.fill: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "RAM"
                                        color: root.sortBy === "ram" ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: ramMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.sortBy !== "ram") {
                                                root.sortBy = "ram"
                                                dashProcListView.userScrollY = 0
                                                dashProcListView.contentY = 0
                                            }
                                        }
                                    }
                                }

                                // PID Column Header
                                Item {
                                    width: 50
                                    height: 24
                                    Text {
                                        anchors.fill: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "PID"
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }
                                }

                                // Sort Arrow Button Pill (↑ / ↓)
                                Rectangle {
                                    height: 24
                                    width: 30
                                    radius: 14
                                    color: arrowMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                    border.width: 1
                                    border.color: arrowMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.sortAscending ? "↑" : "↓"
                                        color: arrowMa.containsMouse ? Theme.accent : Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: arrowMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.sortAscending = !root.sortAscending
                                            dashProcListView.userScrollY = 0
                                            dashProcListView.contentY = 0
                                        }
                                    }
                                }
                            }
                        }

                        // Scrollable Process ListView
                        Item {
                            width: parent.width
                            height: parent.height - 36
                            clip: true

                            ListView {
                                id: dashProcListView
                                anchors.fill: parent
                                clip: true
                                spacing: 4
                                model: root.sortedProcesses

                                property real userScrollY: 0
                                onMovementEnded: userScrollY = contentY
                                onFlickEnded: userScrollY = contentY
                                onContentYChanged: {
                                    if (dashProcListView.moving || dashProcListView.flicking || dashProcListView.dragging) {
                                        dashProcListView.userScrollY = dashProcListView.contentY
                                    }
                                }
                                onModelChanged: {
                                    const targetY = dashProcListView.userScrollY
                                    if (targetY > 0) {
                                        Qt.callLater(() => {
                                            if (dashProcListView.contentHeight > dashProcListView.height) {
                                                dashProcListView.contentY = Math.min(targetY, dashProcListView.contentHeight - dashProcListView.height)
                                            }
                                        })
                                    }
                                }

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    width: dashProcListView.width
                                    height: 32
                                    radius: 8
                                    color: index % 2 === 0 ? Qt.alpha(Theme.fg, 0.04) : "transparent"

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        Text {
                                            text: "󰅟"
                                            color: Qt.alpha(Theme.fg, 0.4)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: modelData.name || "process"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            width: 240
                                        }
                                    }

                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        // CPU % Value
                                        Item {
                                            height: 22
                                            width: 60
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.fill: parent
                                                horizontalAlignment: Text.AlignRight
                                                verticalAlignment: Text.AlignVCenter
                                                text: (modelData.cpu || "0") + "%"
                                                color: root.sortBy === "cpu" ? Theme.yellow : Qt.alpha(Theme.fg, 0.8)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.bold: root.sortBy === "cpu"
                                            }
                                        }

                                        // RAM Usage Value (MB / GB)
                                        Item {
                                            height: 22
                                            width: 80
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.fill: parent
                                                horizontalAlignment: Text.AlignRight
                                                verticalAlignment: Text.AlignVCenter
                                                text: modelData.rss_mb >= 1024
                                                    ? (modelData.rss_mb / 1024).toFixed(1) + " GB"
                                                    : (modelData.rss_mb || 0).toFixed(0) + " MB"
                                                color: root.sortBy === "ram" ? Theme.accent : Qt.alpha(Theme.fg, 0.8)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.bold: root.sortBy === "ram"
                                            }
                                        }

                                        // PID Value
                                        Item {
                                            height: 22
                                            width: 50
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.fill: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                text: modelData.pid || ""
                                                color: Qt.alpha(Theme.fg, 0.45)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // TAB 4: WALLPAPER VIEW (CARDLESS & BOTTOM SELECTOR)
            // ==========================================
            Item {
                anchors.fill: parent
                visible: root.currentTab === "wallpaper"

                // 1. TOP: WALLPAPER GRID (FULL AREA, CARDLESS)
                Item {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: wallBottomBar.top
                    anchors.bottomMargin: 8

                        ScrollView {
                            anchors.fill: parent
                            clip: true

                            Grid {
                                width: parent.width
                                columns: 4
                                spacing: 10

                                Repeater {
                                    model: root.wallpapersList

                                    delegate: Item {
                                        required property var modelData

                                        width: (parent.width - 30) / 4
                                        height: width * 0.65

                                        Rectangle {
                                            id: wallThumbBox
                                            anchors.fill: parent
                                            radius: 12
                                            clip: true
                                            color: Qt.alpha(Theme.fg, 0.08)

                                            readonly property bool isCurWall: (modelData.name && Sys.currentWallpaper.endsWith(modelData.name)) || Sys.currentWallpaper === ("file://" + modelData.path)

                                            scale: wallItemMa.pressed ? 0.94 : (wallItemMa.containsMouse ? 1.05 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                            Item {
                                                id: wallImgWrapper
                                                anchors.fill: parent
                                                visible: false

                                                Image {
                                                    anchors.fill: parent
                                                    source: (root.visible && root.currentTab === "wallpaper" && modelData.path) ? "file://" + modelData.path : ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    sourceSize: Qt.size(240, 160)
                                                    asynchronous: true
                                                    cache: false
                                                    opacity: wallItemMa.containsMouse ? 1.0 : (wallThumbBox.isCurWall ? 0.95 : 0.85)
                                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                                }
                                            }

                                            Rectangle {
                                                id: wallImgMask
                                                anchors.fill: parent
                                                radius: 12
                                                visible: false
                                            }

                                            OpacityMask {
                                                anchors.fill: parent
                                                source: wallImgWrapper
                                                maskSource: wallImgMask
                                            }

                                            // Tint Overlay
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 12
                                                color: wallThumbBox.isCurWall ? Qt.alpha(Theme.accent, 0.15) : (wallItemMa.containsMouse ? Qt.alpha(Theme.accent, 0.08) : "transparent")
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            // Accent Border (Drawn ON TOP of image)
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 12
                                                color: "transparent"
                                                border.width: wallThumbBox.isCurWall ? 3 : (wallItemMa.containsMouse ? 2 : 0)
                                                border.color: Theme.accent
                                                Behavior on border.width { NumberAnimation { duration: 120 } }
                                            }

                                            // Checkmark badge when active
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 26; height: 26; radius: 13
                                                color: Theme.accent
                                                visible: wallThumbBox.isCurWall

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰄬"
                                                    color: Theme.bg
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                            }

                                            MouseArea {
                                                id: wallItemMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setWallpaper(modelData.path)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 2. BOTTOM: WALLPAPER DIRECTORY SELECTOR (CARDLESS / FLAT)
                    Item {
                        id: wallBottomBar
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 30

                        Row {
                            anchors.left: parent.left
                            anchors.right: dashWallBtnRow.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                text: "󰉋"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: Sys.wallpaperDir
                                color: Qt.alpha(Theme.fg, 0.7)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                                width: parent.width - 30
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            id: dashWallBtnRow
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            // Browse Button
                            Rectangle {
                                width: 92; height: 30; radius: 8
                                color: btnWallBrowseMa.containsMouse ? Theme.accentHover : Theme.accent

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰉏"
                                        color: Theme.bg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Browse"
                                        color: Theme.bg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    id: btnWallBrowseMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wallDirPickerProc.running = false
                                        wallDirPickerProc.running = true
                                    }
                                }
                            }

                            // Reset Button
                            Rectangle {
                                width: 60; height: 30; radius: 8
                                color: btnWallResetMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.06)
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.15)

                                Text {
                                    anchors.centerIn: parent
                                    text: "Reset"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                MouseArea {
                                    id: btnWallResetMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Sys.resetWallpaperDir()
                                }
                            }
                        }
                    }
                }
            }
        }

    // Global Dash In-Card Tooltip Layer
    Item {
        id: dashTooltipLayer
        anchors.fill: parent
        z: 999999

        Rectangle {
            id: globalDashTooltip
            visible: root.tooltipVisible && root.activeTooltipText !== ""
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            x: Math.max(8, Math.min(parent.width - width - 8, root.tooltipTargetX - width / 2))
            y: (root.tooltipTargetY - height - 12 < 6) ? (root.tooltipTargetY + 24) : (root.tooltipTargetY - height - 12)

            width: dashTooltipText.implicitWidth + 20
            height: dashTooltipText.implicitHeight + 12
            radius: 8
            color: Sys.customBarBg
            border.width: 1
            border.color: Sys.customModuleBorder

            Text {
                id: dashTooltipText
                anchors.centerIn: parent
                text: root.activeTooltipText
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }
        }
    }
}
