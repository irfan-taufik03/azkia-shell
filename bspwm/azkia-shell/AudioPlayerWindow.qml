import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Window {
    id: root

    property var modelData
    title: "Azkia Audio Player"
    flags: Qt.Dialog
    width: 700
    height: 749
    color: Sys.customBarBg
    visible: false

    onActiveChanged: {
        if (active) {
            windowCard.forceActiveFocus()
        }
    }

    onVisibleChanged: {
        if (visible) {
            windowCard.forceActiveFocus()
            root.usingKeyboardNav = false
            refreshState()
            autoScrollTimer.restart()
        }
    }

    property bool closeDialogOpen: false

    function requestCloseWindow() {
        if (root.isPlaying) {
            root.closeDialogOpen = true
        } else {
            root.quitAndClose()
        }
    }

    function quitAndClose() {
        root.closeDialogOpen = false
        runAction(["--quit"])
        visible = false
    }

    function closeToBackground() {
        root.closeDialogOpen = false
        visible = false
    }

    function closeWindow() {
        root.requestCloseWindow()
    }

    onClosing: (close) => {
        close.accepted = false
        root.requestCloseWindow()
    }

    function toggle() {
        visible = !visible
        if (visible) {
            refreshState()
            root.requestActivate()
            windowCard.forceActiveFocus()
        }
    }

    function open() {
        visible = true
        refreshState()
        root.requestActivate()
        windowCard.forceActiveFocus()
    }

    function seekForward() {
        let pos = root.playerState ? (root.playerState.position || 0) : 0
        let d = root.playerState ? root.playerState.duration : 0
        if (d <= 0 && root.currentTrack) d = root.currentTrack.duration || 0
        if (d > 0) {
            let target = Math.min(d, pos + 5)
            root.runAction(["--seek", target.toString()])
        }
    }

    function seekBackward() {
        let pos = root.playerState ? (root.playerState.position || 0) : 0
        if (pos > 0) {
            let target = Math.max(0, pos - 5)
            root.runAction(["--seek", target.toString()])
        }
    }

    IpcHandler {
        target: "audioplayer"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.requestCloseWindow() }
    }

    IpcHandler {
        target: "player"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
    }

    Shortcut {
        sequences: ["Escape"]
        enabled: root.visible
        onActivated: {
            if (root.closeDialogOpen) {
                root.closeDialogOpen = false
            } else if (root.renameDialogOpen) {
                root.renameDialogOpen = false
            } else if (root.playlistContextMenuOpen) {
                root.playlistContextMenuOpen = false
            } else {
                root.requestCloseWindow()
            }
        }
    }

    Shortcut {
        sequences: ["Space"]
        enabled: root.visible && !root.renameDialogOpen && !root.closeDialogOpen
        onActivated: root.togglePlay()
    }

    Shortcut {
        sequences: ["Left"]
        enabled: root.visible && !root.renameDialogOpen
        onActivated: root.seekBackward()
    }

    Shortcut {
        sequences: ["Right"]
        enabled: root.visible && !root.renameDialogOpen
        onActivated: root.seekForward()
    }

    property bool usingKeyboardNav: false
    property int focusedTrackIndex: 0

    onActivePlaylistNameChanged: {
        root.usingKeyboardNav = false
        if (root.nowPlayingPlaylistName === root.activePlaylistName) {
            root.focusedTrackIndex = root.currentTrackIndex
        } else {
            root.focusedTrackIndex = 0
        }
    }

    Shortcut {
        sequences: ["Up"]
        enabled: root.visible && !root.renameDialogOpen && !root.playlistContextMenuOpen
        onActivated: {
            root.usingKeyboardNav = true
            if (root.activePlaylistTracks && root.activePlaylistTracks.length > 0) {
                let nextIdx = Math.max(0, root.focusedTrackIndex - 1)
                root.focusedTrackIndex = nextIdx
                if (typeof trackListView !== "undefined" && trackListView) {
                    trackListView.positionViewAtIndex(nextIdx, ListView.Contain)
                }
            }
        }
    }

    Shortcut {
        sequences: ["Down"]
        enabled: root.visible && !root.renameDialogOpen && !root.playlistContextMenuOpen
        onActivated: {
            root.usingKeyboardNav = true
            if (root.activePlaylistTracks && root.activePlaylistTracks.length > 0) {
                let nextIdx = Math.min(root.activePlaylistTracks.length - 1, root.focusedTrackIndex + 1)
                root.focusedTrackIndex = nextIdx
                if (typeof trackListView !== "undefined" && trackListView) {
                    trackListView.positionViewAtIndex(nextIdx, ListView.Contain)
                }
            }
        }
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: root.visible && !root.renameDialogOpen && !root.playlistContextMenuOpen
        onActivated: {
            if (root.activePlaylistTracks && root.activePlaylistTracks.length > 0 && root.focusedTrackIndex >= 0 && root.focusedTrackIndex < root.activePlaylistTracks.length) {
                root.playTrack(root.activePlaylistName, root.focusedTrackIndex)
            }
        }
    }

    // Backend Player State Holder
    property var playerState: ({
        active_playlist: "Playlist 1",
        playlists: {
            "Playlist 1": [],
            "Playlist 2": []
        },
        current_index: 0,
        playback_state: "stopped",
        position: 0,
        duration: 0,
        volume: 100
    })

    readonly property string activePlaylistName: root.playerState ? (root.playerState.active_playlist || "Playlist 1") : "Playlist 1"
    readonly property string nowPlayingPlaylistName: root.playerState ? (root.playerState.now_playing_playlist || root.activePlaylistName) : root.activePlaylistName

    readonly property var playlistsList: {
        if (!root.playerState || !root.playerState.playlists) return ["Playlist 1", "Playlist 2"]
        return Object.keys(root.playerState.playlists)
    }

    readonly property var activePlaylistTracks: {
        if (!root.playerState || !root.playerState.playlists) return []
        return root.playerState.playlists[root.activePlaylistName] || []
    }

    readonly property var nowPlayingTracks: {
        if (!root.playerState || !root.playerState.playlists) return []
        return root.playerState.playlists[root.nowPlayingPlaylistName] || []
    }

    readonly property int currentTrackIndex: root.playerState ? (root.playerState.now_playing_index !== undefined ? root.playerState.now_playing_index : (root.playerState.current_index || 0)) : 0

    readonly property var currentTrack: {
        if (!nowPlayingTracks || nowPlayingTracks.length === 0) return null
        if (currentTrackIndex >= 0 && currentTrackIndex < nowPlayingTracks.length)
            return nowPlayingTracks[currentTrackIndex]
        return nowPlayingTracks[0]
    }

    readonly property bool isPlaying: root.playerState && root.playerState.playback_state === "playing"

    readonly property string activeArtUrl: currentTrack && currentTrack.art ? currentTrack.art : ""

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var systemAudio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property bool systemMuted: systemAudio?.muted ?? false
    readonly property int systemVolume: systemAudio ? Math.round(systemAudio.volume * 100) : 100

    function setVolume(vol) {
        if (systemAudio) {
            systemAudio.muted = false
            systemAudio.volume = Math.max(0, Math.min(1, Math.round(vol) / 100.0))
        }
    }

    readonly property bool repeatTrack: root.playerState ? (root.playerState.repeat_track === true) : false

    function toggleRepeat() {
        runAction(["--toggle-repeat"])
    }


    // Backend Processes & Sync
    Process {
        id: fetchStateProc
        command: ["python3", Sys.scriptPath("azkia_audio_player.py"), "--get-state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(text)
                    if (parsed && parsed.playlists) {
                        let isFirstLoad = !root.playerState || !root.playerState.now_playing_playlist
                        root.playerState = parsed
                        if (isFirstLoad) {
                            autoScrollTimer.restart()
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(text)
                    if (parsed && parsed.playlists) {
                        root.playerState = parsed
                    }
                } catch (e) {}
            }
        }
    }

    function refreshState() {
        fetchStateProc.running = false
        fetchStateProc.running = true
    }

    Timer {
        id: pollTimer
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: root.refreshState()
    }

    Timer {
        id: autoScrollTimer
        interval: 150
        repeat: false
        onTriggered: root.scrollToActiveTrack()
    }

    Process {
        id: seekProc
        command: ["python3", Sys.scriptPath("azkia_audio_player.py"), "--seek", "0"]
    }

    Timer {
        id: seekThrottleTimer
        interval: 40
        repeat: false
        property real seekTarget: 0
        onTriggered: {
            seekProc.command = ["python3", Sys.scriptPath("azkia_audio_player.py"), "--seek", seekTarget.toString()]
            seekProc.running = false
            seekProc.running = true
        }
    }

    function scrollToActiveTrack() {
        if (root.nowPlayingPlaylistName === root.activePlaylistName) {
            let idx = root.currentTrackIndex
            if (idx >= 0 && root.activePlaylistTracks && idx < root.activePlaylistTracks.length) {
                root.focusedTrackIndex = idx
                if (typeof trackListView !== "undefined" && trackListView) {
                    trackListView.positionViewAtIndex(idx, ListView.Beginning)
                }
            }
        } else {
            root.focusedTrackIndex = 0
            if (typeof trackListView !== "undefined" && trackListView) {
                trackListView.positionViewAtIndex(0, ListView.Beginning)
            }
        }
    }


    function runAction(args) {
        actionProc.command = ["python3", Sys.scriptPath("azkia_audio_player.py"), ...args]
        actionProc.running = false
        actionProc.running = true
    }

    function playTrack(plName, index) {
        runAction(["--play-track", plName, index.toString()])
    }

    function togglePlay() {
        runAction(["--toggle-play"])
    }

    function nextTrack() {
        runAction(["--next"])
    }

    function prevTrack() {
        runAction(["--prev"])
    }

    function stopTrack() {
        runAction(["--stop"])
    }

    function seekRelative(offset) {
        runAction(["--seek-relative", offset.toString()])
    }


    function setPlaylist(plName) {
        runAction(["--set-playlist", plName])
    }

    function importAudioFiles() {
        runAction(["--import-files", root.activePlaylistName])
    }

    function importAudioFolder() {
        runAction(["--import-dir", root.activePlaylistName])
    }

    function createPlaylist() {
        let count = 1
        let newName = "Playlist " + (root.playlistsList.length + 1)
        while (root.playlistsList.indexOf(newName) !== -1) {
            count++
            newName = "Playlist " + (root.playlistsList.length + count)
        }
        runAction(["--add-playlist", newName])
    }

    function renamePlaylist(oldName, newName) {
        if (!newName || newName.trim() === "" || newName === oldName) return
        runAction(["--rename-playlist", oldName, newName.trim()])
    }

    function duplicatePlaylist(plName) {
        runAction(["--duplicate-playlist", plName])
    }

    function deletePlaylist(plName) {
        runAction(["--delete-playlist", plName])
    }

    function removeTrack(index) {
        runAction(["--remove-track", root.activePlaylistName, index.toString()])
    }

    function formatTime(secs) {
        if (!secs || isNaN(secs) || secs <= 0) return "00:00"
        let s = Math.floor(secs)
        let m = Math.floor(s / 60)
        let rS = s % 60
        return (m < 10 ? "0" + m : m) + ":" + (rS < 10 ? "0" + rS : rS)
    }

    // Animation Phase Timer for Visualizer Fallback

    property real animPhase: 0
    Timer {
        id: waveTimer
        interval: 40
        running: root.visible && root.isPlaying
        repeat: true
        onTriggered: root.animPhase = (root.animPhase + 0.15) % (Math.PI * 2)
    }

    // Import Options Menu Popup
    property bool importMenuOpen: false

    // Context Menu & Rename Dialog State
    property bool playlistContextMenuOpen: false
    property string selectedPlaylistForMenu: ""
    property real menuPosX: 0
    property real menuPosY: 0

    property bool renameDialogOpen: false
    property string playlistToRename: ""

    onRenameDialogOpenChanged: {
        if (renameDialogOpen) {
            renameInput.forceActiveFocus()
        } else {
            windowCard.forceActiveFocus()
        }
    }

    // Main Floating Window Rectangle
    Rectangle {
        id: windowCard
        anchors.fill: parent
        color: Sys.customBarBg
        radius: Theme.windowRadius
        border.width: 0.5
        border.color: Theme.altbg
        clip: true
        focus: true

        TapHandler {
            onTapped: windowCard.forceActiveFocus()
        }

        Keys.onPressed: (event) => {
            if (root.renameDialogOpen) return;
            if (event.key === Qt.Key_Space) {
                root.togglePlay()
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                root.seekBackward()
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                root.seekForward()
                event.accepted = true
            }
        }

        Behavior on color { ColorAnimation { duration: 200 } }


        // ================= WINDOW HEADER BAR =================
        Rectangle {
            id: headerBar
            width: parent.width
            height: 52
            color: "transparent"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    source: "file://" + Sys.configDir + "/assets/azkia-audio-player-icons.svg"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Azkia Audio Player"
                    color: Theme.fg
                    font.pixelSize: 18
                    font.bold: true
                }
            }

            // Close Window Button
            Rectangle {
                width: 34
                height: 34
                radius: Theme.buttonRadius
                color: closeMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : "transparent"
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    color: closeMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
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


        // ================= MAIN CONTAINER COLUMN =================
        Column {
            anchors.top: headerBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.bottomMargin: 20
            spacing: 16

            // ================= 1. TOP CARD (NOW PLAYING) =================
            Rectangle {
                id: nowPlayingCard
                width: parent.width
                height: 230
                radius: 20
                color: Qt.alpha(Theme.fg, 0.05)
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.15)

                Row {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 24

                    // --- CIRCULAR ALBUM ARTWORK ---
                    Item {
                        id: artCircleContainer
                        width: 180
                        height: 180
                        anchors.verticalCenter: parent.verticalCenter

                        // Base Background Circle
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Qt.alpha(Theme.fg, 0.08)
                            antialiasing: true
                        }

                        // Source Image (invisible, used as source for OpacityMask)
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
                            visible: coverImg.status === Image.Ready && coverImg.source != ""
                        }

                        // Fallback Music Icon
                        Text {
                            anchors.centerIn: parent
                            text: "󰎈"
                            color: Qt.alpha(Theme.fg, 0.35)
                            font.family: Theme.fontFamily
                            font.pixelSize: 64
                            visible: coverImg.status !== Image.Ready || coverImg.source == ""
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


                    // --- RIGHT COLUMN: METADATA, VISUALIZER & CONTROLS ---
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 180 - 24
                        spacing: 10

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
                                        text: "Azkia Player"
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
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
                            text: root.currentTrack ? (root.currentTrack.title || root.currentTrack.filename) : "No Track Selected"
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
                                if (!root.currentTrack) return "Import audio files into playlist"
                                let artist = root.currentTrack.artist || "Unknown Artist"
                                let album = root.currentTrack.album
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
                            height: 32

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                height: 28

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
                                                    return Math.max(4, Math.min(28, Math.round(4 + (val / 100.0) * 24)))
                                                }
                                            }
                                            let centerDist = Math.abs(index - 11)
                                            let wave = (Math.sin(root.animPhase + index * 0.45) + 1.0) * 0.5
                                            let maxH = 28 - centerDist * 0.8
                                            return Math.max(4, Math.min(28, Math.round(4 + wave * (maxH - 4))))
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

                        // --- TRACK PROGRESS TIMELINE BAR ---
                        Column {
                            width: parent.width
                            spacing: 4

                            Item {
                                width: parent.width
                                height: 14

                                Text {
                                    anchors.left: parent.left
                                    text: {
                                        if (trackMa.pressed && trackProgressBar.width > 0) {
                                            let d = root.playerState ? root.playerState.duration : 0
                                            if (d <= 0 && root.currentTrack) d = root.currentTrack.duration || 0
                                            let pct = Math.max(0, Math.min(1, trackProgressBar.dragPositionX / trackProgressBar.width))
                                            return root.formatTime(pct * d)
                                        }
                                        return root.formatTime(root.playerState ? root.playerState.position : 0)
                                    }
                                    color: Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                Text {
                                    anchors.right: parent.right
                                    text: {
                                        let d = root.playerState ? root.playerState.duration : 0
                                        if (d <= 0 && root.currentTrack) d = root.currentTrack.duration || 0
                                        return root.formatTime(d)
                                    }
                                    color: Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                            // Interactive Progress Track Bar
                            Rectangle {
                                id: trackProgressBar
                                property real dragPositionX: 0
                                width: parent.width
                                height: (trackMa.containsMouse || trackMa.pressed) ? 8 : 5
                                radius: height / 2
                                color: Qt.alpha(Theme.fg, 0.15)

                                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }

                                Rectangle {
                                    height: (trackMa.containsMouse || trackMa.pressed) ? 12 : 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: {
                                        if (trackMa.pressed) {
                                            return Math.max(0, Math.min(trackProgressBar.width, trackProgressBar.dragPositionX))
                                        }
                                        let d = root.playerState ? root.playerState.duration : 0
                                        if (d <= 0 && root.currentTrack) d = root.currentTrack.duration || 0
                                        if (d <= 0) return 0
                                        let pos = root.playerState ? (root.playerState.position || 0) : 0
                                        let p = pos / d
                                        return Math.max(0, Math.min(parent.width, parent.width * p))
                                    }
                                    radius: height / 2
                                    color: (trackMa.containsMouse || trackMa.pressed) ? Theme.accentHover : Theme.accent

                                    Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }
                                }

                                MouseArea {
                                    id: trackMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => {
                                        trackProgressBar.dragPositionX = Math.max(0, Math.min(width, mouse.x))
                                        let d = root.playerState ? root.playerState.duration : 0
                                        if (d <= 0 && root.currentTrack) d = root.currentTrack.duration || 0
                                        if (d > 0) {
                                            let pct = Math.max(0, Math.min(1, mouse.x / width))
                                            let seekTarget = pct * d
                                            if (root.playerState) root.playerState.position = seekTarget
                                            seekThrottleTimer.seekTarget = seekTarget
                                            seekThrottleTimer.restart()
                                        }
                                    }
                                    onPositionChanged: mouse => {
                                        if (pressed) {
                                            trackProgressBar.dragPositionX = Math.max(0, Math.min(width, mouse.x))
                                            let d = root.playerState ? root.playerState.duration : 0
                                            if (d <= 0 && root.currentTrack) d = root.currentTrack.duration || 0
                                            if (d > 0) {
                                                let pct = Math.max(0, Math.min(1, mouse.x / width))
                                                let seekTarget = pct * d
                                                if (root.playerState) root.playerState.position = seekTarget
                                                seekThrottleTimer.seekTarget = seekTarget
                                                seekThrottleTimer.restart()
                                            }
                                        }
                                    }
                                    onReleased: mouse => {
                                        let d = root.playerState ? root.playerState.duration : 0
                                        if (d <= 0 && root.currentTrack) d = root.currentTrack.duration || 0
                                        if (d > 0) {
                                            let pct = Math.max(0, Math.min(1, mouse.x / width))
                                            let seekTarget = pct * d
                                            if (root.playerState) root.playerState.position = seekTarget
                                            seekThrottleTimer.stop()
                                            seekProc.command = ["python3", Sys.scriptPath("azkia_audio_player.py"), "--seek", seekTarget.toString()]
                                            seekProc.running = false
                                            seekProc.running = true
                                        }
                                    }
                                    onClicked: mouse => {
                                        let d = root.playerState ? root.playerState.duration : 0
                                        if (d <= 0 && root.currentTrack) d = root.currentTrack.duration || 0
                                        if (d > 0) {
                                            let pct = Math.max(0, Math.min(1, mouse.x / width))
                                            let seekTarget = pct * d
                                            if (root.playerState) root.playerState.position = seekTarget
                                            seekThrottleTimer.stop()
                                            seekProc.command = ["python3", Sys.scriptPath("azkia_audio_player.py"), "--seek", seekTarget.toString()]
                                            seekProc.running = false
                                            seekProc.running = true
                                        }
                                    }
                                }
                            }

                        }

                        // Bottom Controls Row: Playback Buttons (Left) + Repeat & Player Volume Slider (Right)
                        Item {
                            width: parent.width
                            height: 44

                            // Left: Playback Control Buttons (Prev, Play/Pause, Next, Stop)
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12
                                                              // 1. Previous Track Button
                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: prevMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                                    border.width: 1
                                    border.color: prevMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Qt.alpha(Theme.fg, 0.15)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒮"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 15
                                    }

                                    MouseArea {
                                        id: prevMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.prevTrack()

                                        ToolTip {
                                            id: prevTip
                                            visible: prevMa.containsMouse
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

                                // 2. Primary Play / Pause Accent Button
                                Rectangle {
                                    width: 44
                                    height: 44
                                    radius: 22
                                    color: playMa.containsMouse ? Theme.accentHover : Theme.accent
                                    border.width: 1
                                    border.color: playMa.containsMouse ? Theme.accentHover : Qt.alpha(Theme.fg, 0.2)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.isPlaying ? "󰏤" : "󰐊"
                                        color: Theme.bg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 20
                                    }

                                    MouseArea {
                                        id: playMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.togglePlay()

                                        ToolTip {
                                            id: playTip
                                            visible: playMa.containsMouse
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

                                // 3. Next Track Button
                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: nextMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                                    border.width: 1
                                    border.color: nextMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Qt.alpha(Theme.fg, 0.15)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒭"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 15
                                    }

                                    MouseArea {
                                        id: nextMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.nextTrack()

                                        ToolTip {
                                            id: nextTip
                                            visible: nextMa.containsMouse
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

                                // 4. Stop Button
                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: stopMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                    border.width: 1
                                    border.color: stopMa.containsMouse ? Qt.alpha(Theme.red, 0.5) : Qt.alpha(Theme.fg, 0.15)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰓛"
                                        color: stopMa.containsMouse ? Theme.red : Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 15
                                    }

                                    MouseArea {
                                        id: stopMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.stopTrack()

                                        ToolTip {
                                            id: stopTip
                                            visible: stopMa.containsMouse
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

                            // Right: Repeat Track Button (Far Right)
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 14

                                // Repeat Single Track Button (Far Right)
                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: root.repeatTrack ? Qt.alpha(Theme.accent, 0.25) : (repeatMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08))
                                    border.width: 1
                                    border.color: root.repeatTrack ? Theme.accent : (repeatMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Qt.alpha(Theme.fg, 0.15))
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰑖"
                                        color: root.repeatTrack ? Theme.accent : Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 16
                                    }

                                    MouseArea {
                                        id: repeatMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleRepeat()

                                        ToolTip {
                                            id: repeatTip
                                            visible: repeatMa.containsMouse
                                            delay: 200
                                            text: root.repeatTrack ? "Repeat Track: On" : "Repeat Track: Off"
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

            // ================= 2. BOTTOM CARD (PLAYLISTS & TRACK TABLE) =================
            Rectangle {
                id: playlistCard
                width: parent.width
                height: parent.height - 230 - 16
                radius: 20
                color: Qt.alpha(Theme.fg, 0.05)
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.15)

                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    // --- PLAYLIST TAB SELECTOR BAR + IMPORT BUTTON ---
                    Item {
                        width: parent.width
                        height: 40

                        Row {
                            anchors.left: parent.left
                            spacing: 12

                            Repeater {
                                model: root.playlistsList

                                Rectangle {
                                    required property string modelData

                                    readonly property bool isActive: root.activePlaylistName === modelData

                                    width: Math.max(120, plText.implicitWidth + 30)
                                    height: 40
                                    radius: 16
                                    color: isActive ? (plMa.containsMouse ? Theme.accentHover : Theme.accent) : (plMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.07))
                                    border.width: 1
                                    border.color: isActive ? (plMa.containsMouse ? Theme.accentHover : Theme.accent) : (plMa.containsMouse ? Qt.alpha(Theme.fg, 0.25) : Qt.alpha(Theme.fg, 0.12))

                                    Text {
                                        id: plText
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: isActive ? Theme.bg : Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: plMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.RightButton) {
                                                root.selectedPlaylistForMenu = modelData
                                                let pos = plMa.mapToItem(windowCard, mouse.x, mouse.y)
                                                root.menuPosX = Math.max(10, Math.min(pos.x - 100, windowCard.width - 210))
                                                root.menuPosY = Math.max(10, Math.min(pos.y - 155, windowCard.height - 170))
                                                root.playlistContextMenuOpen = true
                                            } else {
                                                root.setPlaylist(modelData)
                                                root.playlistContextMenuOpen = false
                                            }
                                        }
                                    }
                                }
                            }

                            // Plus / Add Empty Playlist Button
                            Rectangle {
                                width: 34
                                height: 34
                                radius: 17
                                color: plusMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                                border.width: 1
                                border.color: plusMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Qt.alpha(Theme.fg, 0.15)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "＋"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    font.bold: true
                                }

                                MouseArea {
                                    id: plusMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.createPlaylist()

                                    ToolTip {
                                        id: plusTip
                                        visible: plusMa.containsMouse
                                        delay: 200
                                        text: "Add Empty Playlist"
                                        contentItem: Text {
                                            text: plusTip.text
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

                        // --- RIGHT ALIGNED IMPORT BUTTONS ---
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            // Button: Import Audio Files
                            Rectangle {
                                width: 34
                                height: 34
                                radius: 17
                                color: importFilesMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                                border.width: 1
                                border.color: importFilesMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Qt.alpha(Theme.fg, 0.15)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰎈"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                }

                                MouseArea {
                                    id: importFilesMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.importAudioFiles()

                                    ToolTip {
                                        id: importFilesTip
                                        visible: importFilesMa.containsMouse
                                        delay: 200
                                        text: "Import Audio Files"
                                        contentItem: Text {
                                            text: importFilesTip.text
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

                            // Button: Import Audio Folder
                            Rectangle {
                                width: 34
                                height: 34
                                radius: 17
                                color: importFolderMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                                border.width: 1
                                border.color: importFolderMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Qt.alpha(Theme.fg, 0.15)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰉋"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                }

                                MouseArea {
                                    id: importFolderMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.importAudioFolder()

                                    ToolTip {
                                        id: importFolderTip
                                        visible: importFolderMa.containsMouse
                                        delay: 200
                                        text: "Import Audio Folder"
                                        contentItem: Text {
                                            text: importFolderTip.text
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

                    // --- TRACK TABLE SECTION (HEADERS + LISTVIEW) ---
                    Column {
                        width: parent.width
                        height: parent.height - 40 - 14
                        spacing: 6

                        // --- TRACK TABLE HEADERS ---
                        Item {
                            width: parent.width
                            height: 20

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 0

                                Text {
                                    width: 80
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Track No"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                Text {
                                    width: 220
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Artist/Album"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                Text {
                                    width: parent.width - 80 - 220 - 90
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Title"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                Text {
                                    width: 90
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Duration"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }

                        // --- TRACK LIST TABLE VIEW ---
                        ScrollView {
                            width: parent.width
                            height: parent.height - 20 - 6
                            clip: true

                        ScrollBar.vertical: ScrollBar {
                            id: vScrollBar
                            parent: parent
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 12
                            policy: ScrollBar.AsNeeded

                            background: Rectangle {
                                color: "transparent"
                            }

                            contentItem: Rectangle {
                                implicitWidth: 6
                                implicitHeight: 36
                                radius: 3
                                color: vScrollBar.pressed ? Qt.alpha(Theme.accent, 0.7) : (vScrollBar.hovered ? Qt.alpha(Theme.fg, 0.40) : Qt.alpha(Theme.fg, 0.20))
                                opacity: vScrollBar.active ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 250 } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        ListView {
                            id: trackListView
                            width: parent.width
                            model: root.activePlaylistTracks
                            spacing: 6

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                readonly property bool isSelectedTrack: root.nowPlayingPlaylistName === root.activePlaylistName && root.currentTrackIndex === index
                                readonly property bool isFocusedTrack: root.focusedTrackIndex === index
                                readonly property bool isHovered: rowMa.containsMouse && !root.usingKeyboardNav

                                width: ListView.view.width
                                height: 38
                                radius: 11
                                color: isSelectedTrack ? (isHovered ? Theme.accentHover : Theme.accent)
                                     : (isFocusedTrack ? Qt.alpha(Theme.accent, 0.18)
                                     : (isHovered ? Qt.alpha(Theme.accent, 0.14) : Qt.alpha(Theme.fg, 0.05)))
                                border.width: 1
                                border.color: isSelectedTrack ? (isHovered ? Theme.accentHover : Theme.accent)
                                            : (isFocusedTrack ? Theme.accent
                                            : (isHovered ? Qt.alpha(Theme.accent, 0.4) : Qt.alpha(Theme.fg, 0.08)))

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0

                                    // Track No
                                    Text {
                                        width: 80
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (index + 1 < 10 ? "0" : "") + (index + 1)
                                        color: isSelectedTrack ? Theme.bg : (isFocusedTrack ? Theme.accent : Qt.alpha(Theme.fg, 0.6))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: isSelectedTrack || isFocusedTrack
                                    }

                                    // Artist / Album
                                    Text {
                                        width: 220
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (modelData.artist || "Unknown Artist") + (modelData.album ? " / " + modelData.album : "")
                                        color: isSelectedTrack ? Qt.alpha(Theme.bg, 0.85) : (isFocusedTrack ? Theme.fg : Qt.alpha(Theme.fg, 0.75))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }

                                    // Title
                                    Text {
                                        width: parent.width - 80 - 220 - 90
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.title || modelData.filename || "Track"
                                        color: isSelectedTrack ? Theme.bg : (isFocusedTrack ? Theme.accent : Theme.fg)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    // Duration
                                    Text {
                                        width: 90
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.duration_str || "--:--"
                                        color: isSelectedTrack ? Theme.bg : (isFocusedTrack ? Theme.accent : Qt.alpha(Theme.fg, 0.6))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                MouseArea {
                                    id: rowMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPositionChanged: {
                                        if (root.usingKeyboardNav) {
                                            root.usingKeyboardNav = false
                                            root.focusedTrackIndex = index
                                        }
                                    }
                                    onEntered: {
                                        if (!root.usingKeyboardNav) {
                                            root.focusedTrackIndex = index
                                        }
                                    }
                                    onClicked: {
                                        root.usingKeyboardNav = false
                                        root.focusedTrackIndex = index
                                        root.playTrack(root.activePlaylistName, index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        }
        // --- CONTEXT MENU CATCHER (CLICK OUTSIDE TO CLOSE) ---
        MouseArea {
            id: contextMenuCatcher
            anchors.fill: parent
            enabled: root.playlistContextMenuOpen
            z: 99
            onClicked: root.playlistContextMenuOpen = false
        }

        // --- PLAYLIST CONTEXT MENU (RIGHT CLICK POPUP) ---
        Rectangle {
            id: playlistContextMenu
            width: 200
            height: 150
            radius: 14
            color: Sys.customBarBg
            border.width: 1
            border.color: Theme.accent
            x: root.menuPosX
            y: root.menuPosY
            visible: root.playlistContextMenuOpen
            z: 100

            Column {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                // Option 1: Rename Playlist
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 8
                    color: rMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        spacing: 8
                        Text { text: "󰏫"; color: Theme.accent; font.family: Theme.fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Rename Playlist"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    }

                    MouseArea {
                        id: rMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.playlistContextMenuOpen = false
                            root.playlistToRename = root.selectedPlaylistForMenu
                            renameInput.text = root.selectedPlaylistForMenu
                            root.renameDialogOpen = true
                        }
                    }
                }

                // Option 2: Duplicate Playlist
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 8
                    color: dupMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        spacing: 8
                        Text { text: "󰆏"; color: Theme.accent; font.family: Theme.fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Duplicate Playlist"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    }

                    MouseArea {
                        id: dupMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.playlistContextMenuOpen = false
                            root.duplicatePlaylist(root.selectedPlaylistForMenu)
                        }
                    }
                }

                // Option 3: Delete Playlist
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 8
                    color: delMa.containsMouse ? Qt.alpha(Theme.red, 0.2) : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        spacing: 8
                        Text { text: "󰩹"; color: Theme.red; font.family: Theme.fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Delete Playlist"; color: Theme.red; font.family: Theme.fontFamily; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    }

                    MouseArea {
                        id: delMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.playlistContextMenuOpen = false
                            root.deletePlaylist(root.selectedPlaylistForMenu)
                        }
                    }
                }

                // Option 4: Add New Playlist
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 8
                    color: addPlMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        spacing: 8
                        Text { text: "󰐕"; color: Theme.accent; font.family: Theme.fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Add New Playlist"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    }

                    MouseArea {
                        id: addPlMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.playlistContextMenuOpen = false
                            root.createPlaylist()
                        }
                    }
                }
            }
        }

        // --- RENAME PLAYLIST MODAL DIALOG ---
        Rectangle {
            id: renameModalBackdrop
            anchors.fill: parent
            color: Qt.alpha("black", 0.6)
            visible: root.renameDialogOpen
            z: 200

            MouseArea {
                anchors.fill: parent
                onClicked: root.renameDialogOpen = false
            }

            Rectangle {
                width: 340
                height: 150
                radius: 16
                color: Sys.customBarBg
                border.width: 1
                border.color: Theme.accent
                anchors.centerIn: parent

                MouseArea { anchors.fill: parent }

                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    Text {
                        text: "Rename Playlist"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Rectangle {
                        width: parent.width
                        height: 36
                        radius: 10
                        color: Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: renameInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.2)

                        TextInput {
                            id: renameInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            selectByMouse: true
                            onAccepted: {
                                root.renamePlaylist(root.playlistToRename, text)
                                root.renameDialogOpen = false
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 10

                        Rectangle {
                            width: 76
                            height: 30
                            radius: 8
                            color: cancelBtnMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                            border.width: 1
                            border.color: Qt.alpha(Theme.fg, 0.2)

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: cancelBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.renameDialogOpen = false
                            }
                        }

                        Rectangle {
                            width: 76
                            height: 30
                            radius: 8
                            color: saveBtnMa.containsMouse ? Theme.accentHover : Theme.accent
                            border.width: 1
                            border.color: saveBtnMa.containsMouse ? Theme.accentHover : Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "Save"
                                color: Theme.bg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                            }
                            MouseArea {
                                id: saveBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.renamePlaylist(root.playlistToRename, renameInput.text)
                                    root.renameDialogOpen = false
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- CLOSE CONFIRMATION MODAL DIALOG ---
        Rectangle {
            id: closeConfirmModalBackdrop
            anchors.fill: parent
            color: Qt.alpha("black", 0.65)
            visible: root.closeDialogOpen
            z: 300

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeDialogOpen = false
            }

            Rectangle {
                width: 440
                height: contentColumn.implicitHeight + 40
                radius: 18
                color: Sys.customBarBg
                border.width: 1
                border.color: Theme.accent
                anchors.centerIn: parent

                MouseArea { anchors.fill: parent }

                Column {
                    id: contentColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 16

                    // Title & Description
                    Column {
                        width: parent.width
                        spacing: 6

                        Row {
                            spacing: 8
                            Text {
                                text: "󰝚"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Close Azkia Audio Player"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Text {
                            text: "Audio is currently playing. Please choose an action:"
                            color: Qt.alpha(Theme.fg, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }

                    // Action Buttons Row
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10

                        // 1. Cancel
                        Rectangle {
                            width: 76
                            height: 34
                            radius: 9
                            color: cancelCloseMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                            border.width: 1
                            border.color: Qt.alpha(Theme.fg, 0.2)

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: cancelCloseMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeDialogOpen = false
                            }
                        }

                        // 2. Stop & Quit
                        Rectangle {
                            width: 130
                            height: 34
                            radius: 9
                            color: stopQuitMa.containsMouse ? Qt.alpha(Theme.red, 0.3) : Qt.alpha(Theme.red, 0.15)
                            border.width: 1
                            border.color: stopQuitMa.containsMouse ? Theme.red : Qt.alpha(Theme.red, 0.4)

                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "󰓛"
                                    color: Theme.red
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: "Stop & Close"
                                    color: Theme.red
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: stopQuitMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.quitAndClose()
                            }
                        }

                        // 3. Keep Playing in Background (DashPopup)
                        Rectangle {
                            width: 170
                            height: 34
                            radius: 9
                            color: keepPlayingMa.containsMouse ? Theme.accentHover : Theme.accent
                            border.width: 1
                            border.color: keepPlayingMa.containsMouse ? Theme.accentHover : Theme.accent

                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "󰎈"
                                    color: Theme.bg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                }
                                Text {
                                    text: "Continue in Dash"
                                    color: Theme.bg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: keepPlayingMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeToBackground()
                            }
                        }
                    }
                }
            }
        }
    }
}
