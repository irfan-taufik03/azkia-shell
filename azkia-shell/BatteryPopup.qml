import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 380
    cardHeight: batCol.implicitHeight + (cardPadding * 2)

    property var batteryData: ({
        percentage: 0,
        state: "Unknown",
        health: "100%",
        energy_full: "0 Wh",
        energy_design: "0 Wh",
        voltage: "0 V",
        technology: "Li-ion",
        power_profile: "balanced"
    })

    onVisibleChanged: {
        if (visible) {
            batProc.running = false
            batProc.running = true
        }
    }

    Process {
        id: batProc
        command: ["python3", Sys.scriptPath("battery_info.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.batteryData = JSON.parse(text)
                } catch (e) {}
            }
        }
    }

    function setPowerProfile(profileName) {
        setBatProfileProc.command = ["python3", Sys.scriptPath("battery_info.py"), "--set-profile", profileName]
        setBatProfileProc.running = false
        setBatProfileProc.running = true
    }

    Process {
        id: setBatProfileProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.batteryData = JSON.parse(text)
                } catch (e) {}
            }
        }
    }

    Column {
        id: batCol
        width: parent.width
        spacing: 12

        // Header Row
        Row {
            width: parent.width
            height: 24

            Text {
                id: batHeadTxt
                text: "Battery & Power Mode"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Item { width: Math.max(10, parent.width - batHeadTxt.width - 34) }

            // Refresh Button
            Rectangle {
                width: 24
                height: 24
                radius: 12
                color: batRefreshMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    color: Theme.secondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                }

                MouseArea {
                    id: batRefreshMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: batProc.running = true
                }
            }
        }

        // Battery Stats Grid (2 Cards: Health & Battery Capacity Details)
        Row {
            width: parent.width
            spacing: 10

            // Card 1: Charge & Health
            Rectangle {
                width: (parent.width - 10) / 2
                height: 64
                radius: 12
                color: Sys.customModuleBg
                border.width: 1
                border.color: Sys.customModuleBorder

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        color: Qt.alpha(Theme.green, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "󰂄"
                            color: Theme.green
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: root.batteryData.percentage + "% (" + root.batteryData.state + ")"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }

                        Text {
                            text: "Health: " + root.batteryData.health
                            color: Theme.magenta
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                    }
                }
            }

            // Card 2: Energy & Voltage Specs
            Rectangle {
                width: (parent.width - 10) / 2
                height: 64
                radius: 12
                color: Sys.customModuleBg
                border.width: 1
                border.color: Sys.customModuleBorder

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        color: Qt.alpha(Theme.blue, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "󰓅"
                            color: Theme.blue
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: root.batteryData.energy_full + " / " + root.batteryData.energy_design
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }

                        Text {
                            text: root.batteryData.voltage + " • " + root.batteryData.technology
                            color: Theme.secondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
            }
        }

        // Power Profile Selection Label
        Text {
            text: "Select Power Mode"
            color: Theme.secondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: true
        }

        // 3 Power Mode Selector Buttons (Power Saver, Balanced, Performance)
        Row {
            width: parent.width
            spacing: 8

            // Mode 1: Power Saver
            Rectangle {
                id: modeSaver
                width: (parent.width - 16) / 3
                height: 40
                radius: 10
                readonly property bool isActive: root.batteryData.power_profile === "power-saver"
                color: isActive ? Qt.alpha(Theme.green, 0.25) : (saverMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : Qt.alpha(Theme.fg, 0.04))
                border.width: isActive ? 2 : 1
                border.color: isActive ? Theme.green : (saverMa.containsMouse ? Qt.alpha(Theme.green, 0.4) : Sys.customModuleBorder)
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰌪"
                        color: modeSaver.isActive ? Theme.green : Theme.secondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                    }

                    Text {
                        text: "Power Saver"
                        color: modeSaver.isActive ? Theme.fg : Theme.secondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: modeSaver.isActive
                    }
                }

                MouseArea {
                    id: saverMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setPowerProfile("power-saver")
                }
            }

            // Mode 2: Balanced
            Rectangle {
                id: modeBal
                width: (parent.width - 16) / 3
                height: 40
                radius: 10
                readonly property bool isActive: root.batteryData.power_profile === "balanced"
                color: isActive ? Qt.alpha(Theme.blue, 0.25) : (balMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : Qt.alpha(Theme.fg, 0.04))
                border.width: isActive ? 2 : 1
                border.color: isActive ? Theme.blue : (balMa.containsMouse ? Qt.alpha(Theme.blue, 0.4) : Sys.customModuleBorder)
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰾅"
                        color: modeBal.isActive ? Theme.blue : Theme.secondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                    }

                    Text {
                        text: "Balanced"
                        color: modeBal.isActive ? Theme.fg : Theme.secondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: modeBal.isActive
                    }
                }

                MouseArea {
                    id: balMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setPowerProfile("balanced")
                }
            }

            // Mode 3: Performance
            Rectangle {
                id: modePerf
                width: (parent.width - 16) / 3
                height: 40
                radius: 10
                readonly property bool isActive: root.batteryData.power_profile === "performance"
                color: isActive ? Qt.alpha(Theme.red, 0.25) : (perfMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : Qt.alpha(Theme.fg, 0.04))
                border.width: isActive ? 2 : 1
                border.color: isActive ? Theme.red : (perfMa.containsMouse ? Qt.alpha(Theme.red, 0.4) : Sys.customModuleBorder)
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰓅"
                        color: modePerf.isActive ? Theme.red : Theme.secondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                    }

                    Text {
                        text: "Performance"
                        color: modePerf.isActive ? Theme.fg : Theme.secondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: modePerf.isActive
                    }
                }

                MouseArea {
                    id: perfMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setPowerProfile("performance")
                }
            }
        }
    }
}
