import QtQuick
import Quickshell

BarModule {
    id: root
    active: popup.visible

    icon: ""
    iconColor: Theme.blue
    label: ""

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
                text: "Control Center"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }

    onClicked: popup.toggle()

    ControlCenterPopup {
        id: popup
        anchorItem: root
    }
}
