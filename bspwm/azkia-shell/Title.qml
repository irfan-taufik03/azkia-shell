import QtQuick
import Quickshell

BarModule {
    id: root

    property string displayTitle: Wm.title
    property string appIconPath: Wm.appIconPath
    interactive: true

    iconImage: root.appIconPath !== ""
        ? "file://" + root.appIconPath
        : "file://" + Sys.configDir + "/assets/azkia-shell-icons.svg"
    iconImageSize: 17

    label: displayTitle.length > 36
        ? displayTitle.slice(0, 33) + "..."
        : (displayTitle !== "" ? displayTitle : "Azkia Shell")

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
        anchor.rect.x: 30
        anchor.rect.y: Math.round((Sys.barHeight - root.implicitHeight) / 2 + root.implicitHeight + 2)

        implicitWidth: tooltipText.implicitWidth + 24
        implicitHeight: tooltipText.implicitHeight + 14

        visible: root.hovered && !hoverTimer.running && (root.displayTitle !== "" || Wm.title !== "")
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
                text: root.displayTitle !== "" ? root.displayTitle : "Azkia Shell"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }
}
