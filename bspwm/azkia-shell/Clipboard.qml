import QtQuick
import Quickshell
import Quickshell.Io

BarModule {
    id: root
    active: popup.visible

    icon: "󰨸"
    iconColor: Theme.yellow

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
                text: "Clipboard & Notes"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            if (!popup.visible) {
                popup.currentTab = "notes"
                popup.open()
            } else if (popup.currentTab === "notes") {
                popup.close()
            } else {
                popup.currentTab = "notes"
            }
        } else {
            if (!popup.visible) {
                popup.currentTab = "clipboard"
                popup.open()
            } else if (popup.currentTab === "clipboard") {
                popup.close()
            } else {
                popup.currentTab = "clipboard"
            }
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
}
