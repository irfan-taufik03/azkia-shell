import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Popout {
    id: root

    cardWidth: 250
    cardHeight: 48

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var audioSink: Pipewire.defaultAudioSink?.audio ?? null
    readonly property bool sinkMuted: audioSink?.muted ?? false
    readonly property int sinkVolume: audioSink ? Math.round(audioSink.volume * 100) : 0

    function toggle() { visible = !visible }

    function showPopup() {
        visible = true
        hideTimer.restart()
    }

    function raiseVolume(step = 0.05) {
        if (audioSink) {
            audioSink.muted = false
            audioSink.volume = Math.max(0, Math.min(1, audioSink.volume + step))
        }
        showPopup()
    }

    function lowerVolume(step = 0.05) {
        if (audioSink) {
            audioSink.muted = false
            audioSink.volume = Math.max(0, Math.min(1, audioSink.volume - step))
        }
        showPopup()
    }

    function toggleMute() {
        if (audioSink) {
            audioSink.muted = !audioSink.muted
        }
        showPopup()
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: root.visible = false
    }

    IpcHandler {
        target: "volume"
        function toggle(): void { root.toggle() }
        function raise(): void { root.raiseVolume(0.05) }
        function lower(): void { root.lowerVolume(0.05) }
        function mute(): void { root.toggleMute() }
    }

    MouseArea {
        id: mainMa
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: mouse => {
            if (pressed && root.audioSink) {
                const rect = volTrackContainer.mapFromItem(mainMa, mouse.x, mouse.y)
                root.audioSink.muted = false
                root.audioSink.volume = Math.max(0, Math.min(1, rect.x / volTrackContainer.width))
            }
        }
        onClicked: mouse => {
            if (root.audioSink) {
                const rect = volTrackContainer.mapFromItem(mainMa, mouse.x, mouse.y)
                root.audioSink.muted = false
                root.audioSink.volume = Math.max(0, Math.min(1, rect.x / volTrackContainer.width))
            }
        }
        onWheel: wheel => {
            if (root.audioSink) {
                const step = wheel.angleDelta.y > 0 ? 0.02 : -0.02
                root.audioSink.muted = false
                root.audioSink.volume = Math.max(0, Math.min(1, root.audioSink.volume + step))
            }
        }

        Row {
            id: mainRow
            anchors.fill: parent
            spacing: 10

            // Icon (clickable to toggle mute)
            Text {
                id: volIconText
                anchors.verticalCenter: parent.verticalCenter
                text: root.sinkMuted ? "󰝟" : root.sinkVolume < 30 ? "󰕿" : root.sinkVolume < 70 ? "󰖀" : "󰕾"
                color: root.sinkMuted ? Qt.alpha(Theme.fg, 0.4) : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 17

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: if (root.audioSink) root.audioSink.muted = !root.audioSink.muted
                }
            }

            // Track Container
            Item {
                id: volTrackContainer
                width: parent.width - volIconText.width - volPctText.width - (mainRow.spacing * 2)
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Qt.alpha(Theme.fg, 0.15)

                    Rectangle {
                        width: parent.width * (root.sinkVolume / 100)
                        height: parent.height
                        radius: 3
                        color: root.sinkMuted ? Qt.alpha(Theme.fg, 0.4) : Theme.accent
                    }

                    Rectangle {
                        x: Math.max(0, Math.min(parent.width - width, (parent.width * (root.sinkVolume / 100)) - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: root.sinkMuted ? Qt.alpha(Theme.fg, 0.6) : Theme.accent
                        border.width: 2
                        border.color: Theme.bg
                    }
                }
            }

            // Percentage Label
            Text {
                id: volPctText
                anchors.verticalCenter: parent.verticalCenter
                text: root.sinkMuted ? "Muted" : (root.sinkVolume + "%")
                color: root.sinkMuted ? Qt.alpha(Theme.fg, 0.4) : Qt.alpha(Theme.fg, 0.8)
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }
        }
    }
}
