import QtQuick
import Quickshell
import Quickshell.Io

BarModule {
    id: root
    active: popup.visible || notePopup.visible

    icon: "󰨸"
    iconColor: Theme.yellow

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            notePopup.visible = !notePopup.visible
            if (notePopup.visible) popup.visible = false
        } else {
            popup.visible = !popup.visible
            if (popup.visible) notePopup.visible = false
        }
    }

    // Run python clipboard daemon continuously in background
    Process {
        id: daemonProc
        running: true
        command: ["python3", Sys.scriptPath("clip_daemon.py"), "--daemon"]
    }

    ClipboardPopup {
        id: popup
        anchorItem: root
    }

    NotePopup {
        id: notePopup
        anchorItem: root
    }
}
