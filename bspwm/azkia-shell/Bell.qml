import QtQuick
import Quickshell

// Notifications: bell icon on top bar, DND indicator, notification history
BarModule {
    id: root
    active: history.visible

    icon: Sys.dndOn ? "󰪑" : (Sys.notifCount > 0 ? "󰂚" : "󰂜")
    iconColor: Sys.dndOn ? Qt.alpha(Theme.yellow, 0.70) : (Sys.notifCount > 0 ? Theme.cyan : Theme.cyan)

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

        visible: root.hovered && !hoverTimer.running && (!history || !history.visible)
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
                text: "Notifications"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            Sys.toggleDnd()
        else
            history.visible = !history.visible
    }

    NotifyPopup {
        id: history
        anchorItem: root
    }
}
