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

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            if (audio) audio.muted = !audio.muted
        } else {
            popup.visible = !popup.visible
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
