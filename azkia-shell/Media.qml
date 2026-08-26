import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

BarModule {
    id: root

    readonly property var players: Mpris.players.values

    readonly property var player: {
        if (!players || players.length === 0) return null

        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            if (p && (p.playbackState === MprisPlaybackState.Playing || p.playbackState === 1 || p.playbackState == "Playing"))
                return p
        }

        if (Sys.lastActivePlayerIdentity !== "") {
            for (let i = 0; i < players.length; i++) {
                const p = players[i]
                const id = p ? (p.identity || p.appName || "") : ""
                if (id === Sys.lastActivePlayerIdentity)
                    return p
            }
        }

        return players[0]
    }

    onPlayerChanged: {
        if (player) {
            const id = player.identity || player.appName || ""
            if (id !== "" && Sys.lastActivePlayerIdentity !== id)
                Sys.lastActivePlayerIdentity = id
        }
    }

    readonly property bool playing: player !== null
        && (player.playbackState === MprisPlaybackState.Playing || player.playbackState === 1 || player.playbackState == "Playing")

    visible: true

    // ===== ANIMATED EQUALIZER =====
    property real animPhase: 0

    Timer {
        id: waveTimer
        interval: 40
        running: root.visible && root.playing
        repeat: true
        onTriggered: root.animPhase = (root.animPhase + 0.15) % (Math.PI * 2)
    }

    // ===== UI =====
    Row {
        spacing: 8
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: 4
        rightPadding: 4

        // Equalizer container
        Item {
            width: eqRow.width
            height: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: root.playing

            Row {
                id: eqRow
                height: 14
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: 5
                    Rectangle {
                        required property int index
                        width: 3
                        height: {
                            if (!root.playing) return 3
                            if (Sys.cavaValues && Sys.cavaValues.length > 0) {
                                let sampleIdx = Math.floor(index * (Sys.cavaValues.length / 5.0))
                                let val = Sys.cavaValues[sampleIdx] || 0
                                if (val > 0) {
                                    return Math.max(3, Math.min(14, Math.round(3 + (val / 100.0) * 11)))
                                }
                            }
                            let wave = root.playing ? (Math.sin(root.animPhase + index * 0.9) + 1.0) * 0.5 : 0.2
                            return Math.max(3, Math.min(14, Math.round(3 + wave * 11)))
                        }
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 1.5
                        color: Theme.magenta

                        Behavior on height {
                            NumberAnimation { duration: 50; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }
        }

        // Play / Pause icon
        Text {
            text: root.playing ? "󰏤" : (root.player ? "󰐊" : "󰎈")
            color: Theme.magenta
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    active: popup.visible

    onClicked: mouse => {
        if (mouse && mouse.button === Qt.RightButton) {
            if (player && player.canTogglePlaying)
                player.togglePlaying()
        } else {
            popup.visible = !popup.visible
        }
    }

    MediaPopup {
        id: popup
        anchorItem: root
    }

    onScrolled: dir => {
        if (!player) return
        if (dir > 0 && player.canGoPrevious)
            player.previous()
        else if (dir < 0 && player.canGoNext)
            player.next()
    }
}
