import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Popout {
    id: root

    cardWidth: 420
    cardHeight: 410

    property real animPhase: 0

    Timer {
        id: waveTimer
        interval: 40
        running: root.visible && root.isPlaying
        repeat: true
        onTriggered: root.animPhase = (root.animPhase + 0.15) % (Math.PI * 2)
    }

    IpcHandler {
        target: "media"
        function toggle(): void { root.toggle() }
    }

    readonly property var players: Mpris.players.values

    property int selectedIndex: 0

    function autoSelectPlayer() {
        if (!players || players.length === 0) {
            selectedIndex = 0
            return
        }

        // Priority 1: Player that is currently playing
        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            if (p && (p.playbackState === MprisPlaybackState.Playing || p.playbackState === 1 || p.playbackState == "Playing")) {
                selectedIndex = i
                return
            }
        }

        // Priority 2: Last active player identity
        if (Sys.lastActivePlayerIdentity !== "") {
            for (let i = 0; i < players.length; i++) {
                const p = players[i]
                const id = p ? (p.identity || p.appName || "") : ""
                if (id === Sys.lastActivePlayerIdentity) {
                    selectedIndex = i
                    return
                }
            }
        }

        // Priority 3: Default to first player
        selectedIndex = 0
    }

    onVisibleChanged: {
        if (visible) autoSelectPlayer()
    }

    onPlayersChanged: autoSelectPlayer()

    readonly property var activePlayer: {
        if (!players || players.length === 0) return null
        if (selectedIndex >= 0 && selectedIndex < players.length)
            return players[selectedIndex]
        return players[0]
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

    onActivePlayerChanged: {
        if (activePlayer) {
            const id = activePlayer.identity || activePlayer.appName || ""
            if (id !== "" && Sys.lastActivePlayerIdentity !== id)
                Sys.lastActivePlayerIdentity = id
        }
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: -4
        spacing: 12

        // ================= PLAYER SELECTOR TABS (CENTERED - CLIPBOARD STYLE) =================
        Item {
            width: parent.width
            height: 50

            // Open Full Audio Player Window Button
            Rectangle {
                width: 30
                height: 30
                radius: Theme.buttonRadius
                color: openWinMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : "transparent"
                border.width: openWinMa.containsMouse ? 1 : 0
                border.color: Qt.alpha(Theme.accent, 0.3)
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                z: 10

                Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: "file://" + Sys.configDir + "/assets/azkia-audio-player-icons.svg"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                MouseArea {
                    id: openWinMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.visible = false
                        Quickshell.execDetached(["quickshell", "--path", Sys.configDir, "ipc", "call", "audioplayer", "open"])
                    }
                }
            }

            // Fallback Title Header when no players exist

            Row {
                anchors.centerIn: parent
                spacing: 8
                visible: root.players.length === 0

                Text {
                    text: "󰎈"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Media Players"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Player Tabs with Animated Underline (Same as ClipboardPopup)
            Row {
                anchors.centerIn: parent
                spacing: 24
                visible: root.players.length > 0

                Repeater {
                    model: root.players

                    Rectangle {
                        id: playerTabBtn
                        required property var modelData
                        required property int index

                        readonly property bool isActive: root.selectedIndex === index

                        width: Math.max(64, playerTabCol.implicitWidth + 14)
                        height: 50
                        color: "transparent"

                        Column {
                            id: playerTabCol
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: {
                                    const st = modelData.playbackState
                                    return (st === MprisPlaybackState.Playing || st === 1 || st == "Playing") ? "󰏤" : "󰐊"
                                }
                                color: isActive ? Theme.accent : (playerTabMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.45))
                                font.family: Theme.fontFamily
                                font.pixelSize: 16

                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Text {
                                id: playerLabel
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.identity || modelData.appName || "Player"
                                color: isActive ? Theme.accent : (playerTabMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.55))
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: isActive
                                elide: Text.ElideRight

                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        // Active Underline Indicator Bar
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: isActive ? playerTabCol.implicitWidth : 0
                            height: 2.5
                            radius: 1.25
                            color: Theme.accent
                            opacity: isActive ? 1.0 : 0.0

                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: playerTabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedIndex = index
                                const p = root.players[index]
                                const id = p ? (p.identity || p.appName || "") : ""
                                if (id !== "")
                                    Sys.lastActivePlayerIdentity = id
                            }
                        }
                    }
                }
            }
        }

        // ================= MEDIA CONTENT AREA WITH TAB SLIDE ANIMATION =================
        Item {
            id: tabSlideArea
            width: parent.width
            height: parent.height - 65
            clip: true

            property int prevIndex: 0

            function triggerSlide(targetIdx) {
                if (targetIdx === tabSlideArea.prevIndex) return;

                var dir = (targetIdx < tabSlideArea.prevIndex) ? -1 : 1
                tabSlideXAnim.from = dir * 50
                tabSlideAnim.restart()
                tabSlideArea.prevIndex = targetIdx
            }

            Connections {
                target: root
                function onVisibleChanged() {
                    if (root.visible) {
                        tabSlideXAnim.from = -40
                        tabSlideAnim.restart()
                        tabSlideArea.prevIndex = root.selectedIndex
                    }
                }
                function onSelectedIndexChanged() {
                    if (root.selectedIndex !== tabSlideArea.prevIndex) {
                        tabSlideArea.triggerSlide(root.selectedIndex)
                    }
                }
            }

            transform: Translate { id: tabSlide; x: 0 }

            ParallelAnimation {
                id: tabSlideAnim
                NumberAnimation { id: tabSlideXAnim; target: tabSlide; property: "x"; from: -40; to: 0; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: tabSlideArea; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }

            Column {
                width: parent.width
                spacing: 12

                // ================= COVER ART / THUMBNAIL AREA =================
                Item {
                    width: parent.width
                    height: 175

                    Rectangle {
                        id: albumCircle
                        width: 155
                        height: 155
                        radius: 77.5
                        anchors.centerIn: parent
                        color: Qt.alpha(Theme.fg, 0.06)
                        border.width: 2
                        border.color: root.isPlaying ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                        clip: true
                        layer.enabled: true

                        Behavior on border.color { ColorAnimation { duration: 300 } }

                        // Cover Image
                        Image {
                            id: coverImg
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            sourceSize: Qt.size(155, 155)
                            cache: false
                            source: root.visible ? root.activeArtUrl : ""
                        }

                        // Fallback Music Icon (shown if no cover thumbnail available)
                        Text {
                            anchors.centerIn: parent
                            text: "󰎈"
                            color: Qt.alpha(Theme.fg, 0.35)
                            font.family: Theme.fontFamily
                            font.pixelSize: 56
                            visible: coverImg.status !== Image.Ready || coverImg.source == ""
                        }
                    }
                }

                // ================= TRACK METADATA =================
                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.activePlayer && root.activePlayer.trackTitle ? root.activePlayer.trackTitle : "No Media Playing"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            if (!root.activePlayer) return "Select or play media"
                            const a = root.activePlayer.trackArtists
                            if (!a) return "Unknown Artist"
                            return Array.isArray(a) ? a.join(", ") : String(a)
                        }
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                // ================= EQUALIZER VISUALIZER =================
                Item {
                    width: parent.width
                    height: 22

                    Row {
                        anchors.centerIn: parent
                        spacing: 3
                        height: 20

                        Repeater {
                            model: 19
                            Rectangle {
                                required property int index
                                width: 3
                                height: {
                                    if (!root.isPlaying) return 3
                                    if (Sys.cavaValues && Sys.cavaValues.length > index) {
                                        let val = Sys.cavaValues[index]
                                        if (val > 0) {
                                            return Math.max(3, Math.min(20, Math.round(3 + (val / 100.0) * 17)))
                                        }
                                    }
                                    let centerDist = Math.abs(index - 9)
                                    let wave = (Math.sin(root.animPhase + index * 0.5) + 1.0) * 0.5
                                    let maxH = 20 - centerDist * 0.8
                                    return Math.max(3, Math.min(20, Math.round(3 + wave * (maxH - 3))))
                                }
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 1.5
                                color: root.isPlaying ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                                Behavior on height {
                                    NumberAnimation { duration: 50; easing.type: Easing.OutQuad }
                                }
                            }
                        }
                    }
                }

                // ================= CONTROLS =================
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 24

                    // Previous Button
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 19
                        color: prevMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05)

                        Text {
                            anchors.centerIn: parent
                            text: "󰒮"
                            color: root.activePlayer && root.activePlayer.canGoPrevious ? Theme.fg : Qt.alpha(Theme.fg, 0.3)
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: prevMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.activePlayer && root.activePlayer.canGoPrevious) root.activePlayer.previous()
                        }
                    }

                    // Play / Pause Button
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: Theme.accent

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
                            onClicked: {
                                if (root.activePlayer && root.activePlayer.canTogglePlaying)
                                    root.activePlayer.togglePlaying()
                            }
                        }
                    }

                    // Next Button
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 19
                        color: nextMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05)

                        Text {
                            anchors.centerIn: parent
                            text: "󰒭"
                            color: root.activePlayer && root.activePlayer.canGoNext ? Theme.fg : Qt.alpha(Theme.fg, 0.3)
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: nextMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.activePlayer && root.activePlayer.canGoNext) root.activePlayer.next()
                        }
                    }
                }
            }
        }
    }
}