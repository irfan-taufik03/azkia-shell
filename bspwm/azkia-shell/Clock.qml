import QtQuick
import Quickshell

Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: 24

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property bool active: calendar.visible
    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool pressed: mouseArea.pressed

    scale: pressed ? 0.95 : 1.0
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

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
                 : (root.hovered ? Qt.alpha(Theme.fg, 0.18) : Sys.customModuleBg)
            border.width: 1
            border.color: root.active ? Theme.accent : (root.hovered ? Qt.alpha(Theme.fg, 0.25) : Sys.customModuleBorder)
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
                 : (root.hovered ? Qt.alpha(Theme.fg, 0.18) : Sys.customModuleBg)
            border.width: 1
            border.color: root.active ? Theme.accent : (root.hovered ? Qt.alpha(Theme.fg, 0.25) : Sys.customModuleBorder)
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
        cursorShape: Qt.PointingHandCursor
        onClicked: calendar.visible = !calendar.visible
    }

    CalendarPopup {
        id: calendar
        anchorItem: root
    }
}
