import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: 24

    readonly property var players: Mpris.players.values

    readonly property var activePlayer: {
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

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property bool active: dashPopup.visible
    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool pressed: mouseArea.pressed

    scale: pressed ? 0.95 : 1.0
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

    Timer {
        id: hoverTimer
        interval: 150
        repeat: false
    }

    onHoveredChanged: {
        if (root.hovered) hoverTimer.restart()
        else hoverTimer.stop()
    }

    PopupWindow {
        id: tooltipWindow

        anchor.item: root
        anchor.rect.x: Math.round((root.width - implicitWidth) / 2)
        anchor.rect.y: Math.round((Sys.barHeight - root.implicitHeight) / 2 + root.implicitHeight + 2)

        implicitWidth: tooltipText.implicitWidth + 24
        implicitHeight: tooltipText.implicitHeight + 14

        visible: root.hovered && !hoverTimer.running && (!dashPopup || !dashPopup.visible)
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Sys.customBarBg
            border.width: 1
            border.color: Sys.customModuleBorder
            radius: 10

            Text {
                id: tooltipText
                anchors.centerIn: parent
                text: "Dash"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }

    Row {
        id: row
        spacing: 6
        anchors.verticalCenter: parent.verticalCenter

        // Clock Sub-Pill
        Rectangle {
            height: 24
            implicitWidth: clockRow.implicitWidth + 16
            radius: 10
            color: root.active ? Qt.alpha(Theme.accent, 0.22)
                 : (root.hovered ? Sys.customModuleHoverBg : Sys.customModuleBg)
            border.width: 1
            border.color: root.active ? (root.hovered ? Theme.accentHover : Theme.accent) : (root.hovered ? Qt.alpha(Theme.fg, 0.25) : Sys.customModuleBorder)
            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                id: clockRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: Theme.red
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(clock.date, "h:mm AP")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.weight: Theme.fontWeight
                }
            }
        }

        // Date Sub-Pill
        Rectangle {
            height: 24
            implicitWidth: dateRow.implicitWidth + 16
            radius: 10
            color: root.active ? Qt.alpha(Theme.accent, 0.22)
                 : (root.hovered ? Sys.customModuleHoverBg : Sys.customModuleBg)
            border.width: 1
            border.color: root.active ? (root.hovered ? Theme.accentHover : Theme.accent) : (root.hovered ? Qt.alpha(Theme.fg, 0.25) : Sys.customModuleBorder)
            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                id: dateRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰃭"
                    color: Theme.blue
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(clock.date, "ddd MMM d")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.weight: Theme.fontWeight
                }
            }
        }
    }

    // Unified MouseArea spanning both pills
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                if (root.activePlayer && root.activePlayer.canTogglePlaying) {
                    root.activePlayer.togglePlaying()
                }
            } else {
                dashPopup.toggle()
            }
        }
    }

    DashPopup {
        id: dashPopup
        anchorItem: root
    }
}
