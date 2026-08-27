import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Popout {
    id: root

    cardWidth: 420
    cardHeight: 435

    property real animPhase: 0

    Timer {
        id: waveTimer
        interval: 40
        running: root.visible && root.isPlaying
        repeat: true
        onTriggered: root.animPhase = (root.animPhase + 0.15) % (Math.PI * 2)
    }

    function toggle() { visible = !visible }

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
        spacing: 12

        // ================= HEADER =================
        RowLayout {
            width: parent.width
            height: 24

            Text {
                text: "󰎈  Media Players"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "󰅖"
                color: Qt.alpha(Theme.fg, 0.6)
                font.family: Theme.fontFamily
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.visible = false
                }
            }
        }

        // ================= PLAYER SELECTOR TABS (CENTER ALIGNED) =================
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 32
            spacing: 8
            visible: root.players.length > 0

            Repeater {
                model: root.players

                Rectangle {
                    required property var modelData
                    required property int index

                    width: Math.min(160, Math.max(110, (380 - (root.players.length - 1) * 8) / root.players.length))
                    height: 32
                    radius: 8
                    color: root.selectedIndex === index ? Theme.accent : Sys.customModuleBg
                    border.width: 1
                    border.color: root.selectedIndex === index ? Theme.accent : Qt.alpha(Theme.fg, 0.08)

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: {
                                const st = modelData.playbackState
                                return (st === MprisPlaybackState.Playing || st === 1 || st == "Playing") ? "󰏤" : "󰐊"
                            }
                            color: root.selectedIndex === index ? Theme.bg : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: modelData.identity || modelData.appName || "Player"
                            color: root.selectedIndex === index ? Theme.bg : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: root.selectedIndex === index
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
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

        // ================= COVER ART / THUMBNAIL AREA =================
        Item {
            width: parent.width
            height: 180

            Rectangle {
                id: albumCircle
                width: 160
                height: 160
                radius: 80
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
                    sourceSize: Qt.size(160, 160)
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