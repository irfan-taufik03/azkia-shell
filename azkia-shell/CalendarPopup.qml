import QtQuick
import Quickshell

// Month calendar popup anchored under the clock with 3 distinct cards:
// - Left Top Card: Live 24-hour Digital Clock (HH / mm)
// - Left Bottom Card: Date (Line 1: Short Month Name "MMM", Line 2: Day "dd")
// - Right Card: Full Interactive Month Calendar Grid
Popout {
    id: root

    property date shown: new Date()
    property date currentTime: new Date()

    cardWidth: 460
    cardHeight: 285

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.currentTime = new Date()
    }

    onVisibleChanged: {
        if (visible) {
            shown = new Date()
            currentTime = new Date()
        }
    }

    Row {
        anchors.fill: parent
        spacing: 12

        // ===== LEFT COLUMN: 2 CARDS STACKED VERTICALLY =====
        Column {
            width: 145
            height: parent.height
            spacing: 10

            // CARD 1 (LEFT TOP): DIGITAL CLOCK (HH / mm)
            Rectangle {
                width: parent.width
                height: 125
                radius: 10
                color: Sys.customModuleBg
                border.width: 1
                border.color: Sys.customModuleBorder

                Column {
                    anchors.centerIn: parent
                    spacing: -4

                    // Line 1: Hour (24h format)
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(root.currentTime, "HH")
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 42
                        font.bold: true
                    }

                    // Line 2: Minute
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(root.currentTime, "mm")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 42
                        font.bold: true
                    }
                }
            }

            // CARD 2 (LEFT BOTTOM): DATE (MMM / dd)
            Rectangle {
                width: parent.width
                height: parent.height - 125 - 10
                radius: 10
                color: Sys.customModuleBg
                border.width: 1
                border.color: Sys.customModuleBorder

                Column {
                    anchors.centerIn: parent
                    spacing: -4

                    // Line 1: Short Month Name (MMM e.g. "Aug")
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(root.currentTime, "MMM")
                        color: Theme.magenta
                        font.family: Theme.fontFamily
                        font.pixelSize: 38
                        font.bold: true
                    }

                    // Line 2: Day 2-digit number (dd e.g. "22")
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(root.currentTime, "dd")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 38
                        font.bold: true
                    }
                }
            }
        }

        // ===== RIGHT COLUMN: CARD 3 (CALENDAR GRID) =====
        Rectangle {
            width: parent.width - 145 - 12
            height: parent.height
            radius: 10
            color: Sys.customModuleBg
            border.width: 1
            border.color: Sys.customModuleBorder

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                // Header: ‹ Month Year ›
                Item {
                    width: parent.width
                    height: 26

                    Text {
                        id: prevBtn
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰅁"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shown = new Date(root.shown.getFullYear(), root.shown.getMonth() - 1, 1)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Qt.formatDate(root.shown, "MMMM yyyy")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shown = new Date()
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰅂"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shown = new Date(root.shown.getFullYear(), root.shown.getMonth() + 1, 1)
                        }
                    }
                }

                // Weekday Headers
                Row {
                    width: parent.width
                    Repeater {
                        model: 7
                        Text {
                            required property int index
                            width: parent.width / 7
                            text: Qt.locale().dayName((Qt.locale().firstDayOfWeek + index) % 7, Locale.ShortFormat)
                            color: Qt.alpha(Theme.fg, 0.45)
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // Day Grid
                Grid {
                    id: dayGrid
                    width: parent.width
                    columns: 7

                    Repeater {
                        model: 42

                        Item {
                            id: cell
                            required property int index
                            width: dayGrid.width / 7
                            height: 28

                            readonly property date cellDate: {
                                const first = new Date(root.shown.getFullYear(), root.shown.getMonth(), 1)
                                const offset = (first.getDay() - Qt.locale().firstDayOfWeek + 7) % 7
                                return new Date(first.getFullYear(), first.getMonth(), 1 - offset + index)
                            }
                            readonly property bool inMonth: cellDate.getMonth() === root.shown.getMonth()
                            readonly property bool isToday: {
                                const now = new Date()
                                return cellDate.getFullYear() === now.getFullYear()
                                    && cellDate.getMonth() === now.getMonth()
                                    && cellDate.getDate() === now.getDate()
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                radius: 7
                                color: cell.isToday ? Theme.selbg : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: cell.cellDate.getDate()
                                    color: cell.isToday ? Theme.selfg
                                         : cell.inMonth ? Theme.fg
                                         : Qt.alpha(Theme.fg, 0.22)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: cell.isToday
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
