import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 250
    cardHeight: 48

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

    Timer {
        interval: 500
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            brightnessGet.running = false
            brightnessGet.running = true
        }
    }

    function setBrightness(pct) {
        pct = Math.max(1, Math.min(100, Math.round(pct)))
        root.brightnessVal = pct
        Quickshell.execDetached(["brightnessctl", "s", pct + "%"])
    }

    function toggle() { visible = !visible }

    function showPopup() {
        visible = true
        hideTimer.restart()
    }

    function raiseBrightness(step = 5) {
        setBrightness(brightnessVal + step)
        showPopup()
    }

    function lowerBrightness(step = 5) {
        setBrightness(brightnessVal - step)
        showPopup()
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: root.visible = false
    }

    IpcHandler {
        target: "brightness"
        function toggle(): void { root.toggle() }
        function raise(): void { root.raiseBrightness(5) }
        function lower(): void { root.lowerBrightness(5) }
    }

    MouseArea {
        id: mainMa
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: mouse => {
            if (pressed) {
                const rect = brightTrackContainer.mapFromItem(mainMa, mouse.x, mouse.y)
                root.setBrightness((rect.x / brightTrackContainer.width) * 100)
            }
        }
        onClicked: mouse => {
            const rect = brightTrackContainer.mapFromItem(mainMa, mouse.x, mouse.y)
            root.setBrightness((rect.x / brightTrackContainer.width) * 100)
        }
        onWheel: wheel => {
            const step = wheel.angleDelta.y > 0 ? 5 : -5
            root.setBrightness(root.brightnessVal + step)
        }

        Row {
            id: mainRow
            anchors.fill: parent
            spacing: 10

            // Icon
            Text {
                id: brightIconText
                anchors.verticalCenter: parent.verticalCenter
                text: root.brightnessVal <= 25 ? "󰃜" : root.brightnessVal <= 65 ? "󰃞" : "󰃠"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 17
            }

            // Track Container
            Item {
                id: brightTrackContainer
                width: parent.width - brightIconText.width - brightPctText.width - (mainRow.spacing * 2)
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Qt.alpha(Theme.fg, 0.15)

                    Rectangle {
                        width: parent.width * (root.brightnessVal / 100)
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                    }

                    Rectangle {
                        x: Math.max(0, Math.min(parent.width - width, (parent.width * (root.brightnessVal / 100)) - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.accent
                        border.width: 2
                        border.color: Theme.bg
                    }
                }
            }

            // Percentage Label
            Text {
                id: brightPctText
                anchors.verticalCenter: parent.verticalCenter
                text: root.brightnessVal + "%"
                color: Qt.alpha(Theme.fg, 0.8)
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }
        }
    }
}
