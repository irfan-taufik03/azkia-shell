import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default sink volume. Scroll to adjust, click to mute, right click for
// pavucontrol (floats via the bspwmrc rule).
BarModule {
    id: root
    active: popup.visible

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property bool muted: audio?.muted ?? false
    readonly property int volume: audio ? Math.round(audio.volume * 100) : 0

    icon: muted ? "󰝟" : volume < 25 ? "󰕿" : volume < 65 ? "󰖀" : "󰕾"
    iconColor: muted ? Qt.alpha(Theme.fg, 0.45) : Theme.blue
    // icon-only; the % appears while hovering (and while scrolling it)
    label: muted ? "--" : volume + "%"

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

        visible: root.hovered && !hoverTimer.running && (!popup || !popup.visible)
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
                text: "Volume"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            if (audio) audio.muted = !audio.muted
        } else {
            popup.toggle()
        }
    }
    onScrolled: dir => {
        if (audio) {
            audio.muted = false
            audio.volume = Math.max(0, Math.min(1, audio.volume + dir * 0.02))
        }
    }

    VolumePopup {
        id: popup
        anchorItem: root
    }
}
