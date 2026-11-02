import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    IpcHandler {
        target: "battery"
        function toggle(): void { root.toggle() }
    }

    cardWidth: 440
    cardHeight: batCol.implicitHeight + (cardPadding * 2)

    property var batteryData: ({
        percentage: 0,
        state: "Unknown",
        health: "100%",
        energy_full: "0 Wh",
        energy_design: "0 Wh",
        voltage: "0 V",
        technology: "Li-ion",
        power_profile: "balanced",
        has_conservation: true,
        conservation_mode: false,
        charge_threshold: 100,
        bluetooth_devices: []
    })

    readonly property bool hasTwsDevices: !!(batteryData && batteryData.bluetooth_devices && batteryData.bluetooth_devices.length > 0)

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

    function setChargeThreshold(limit) {
        setBatThreshProc.command = ["python3", Sys.scriptPath("battery_info.py"), "--set-threshold", limit.toString()]
        setBatThreshProc.running = false
        setBatThreshProc.running = true
    }

    Process {
        id: setBatThreshProc
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
                radius: Theme.buttonRadius
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
                radius: 14
                color: Sys.customModuleBg
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.2)

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        width: 36
                        height: 36
                        radius: Theme.buttonRadius
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "󰂄"
                            color: Theme.bg
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
                radius: 14
                color: Sys.customModuleBg
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.2)

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        width: 36
                        height: 36
                        radius: Theme.buttonRadius
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "󰓅"
                            color: Theme.bg
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

        // Connected Wireless / TWS Devices (Automatically hidden when none connected)
        Text {
            visible: root.hasTwsDevices
            text: "Connected Wireless Devices"
            color: Theme.secondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: true
        }

        Repeater {
            model: root.hasTwsDevices ? root.batteryData.bluetooth_devices : []

            Rectangle {
                required property var modelData
                width: parent.width
                height: 56
                radius: 14
                color: Sys.customModuleBg
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.25)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    // Icon Badge (Left)
                    Rectangle {
                        width: 36
                        height: 36
                        radius: Theme.buttonRadius
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon || "󰋋"
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                        }
                    }

                    // Device Name & Status (Middle)
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        width: parent.width - 36 - 80 - 24

                        Text {
                            text: modelData.name || "Bluetooth Device"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: "Connected • Wireless Audio"
                            color: Theme.green
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    // Battery Percentage Badge (Right)
                    Row {
                        width: 80
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        layoutDirection: Qt.RightToLeft

                        Text {
                            text: modelData.percentage + "%"
                            color: (modelData.percentage <= 20) ? Theme.red : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: (modelData.percentage >= 80) ? "󰁹"
                                : (modelData.percentage >= 50) ? "󰂀"
                                : (modelData.percentage >= 20) ? "󰁾"
                                : "󰁻"
                            color: (modelData.percentage <= 20) ? Theme.red : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            anchors.verticalCenter: parent.verticalCenter
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
                radius: 14
                readonly property bool isActive: root.batteryData.power_profile === "power-saver"
                color: isActive ? Theme.accent : (saverMa.containsMouse ? Qt.alpha(Theme.fg, 0.10) : Qt.alpha(Theme.fg, 0.04))
                border.width: 1
                border.color: isActive ? Theme.accent : Qt.alpha(Theme.accent, 0.2)
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰌪"
                        color: modeSaver.isActive ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Power Saver"
                        color: modeSaver.isActive ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
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
                radius: 14
                readonly property bool isActive: root.batteryData.power_profile === "balanced"
                color: isActive ? Theme.accent : (balMa.containsMouse ? Qt.alpha(Theme.fg, 0.10) : Qt.alpha(Theme.fg, 0.04))
                border.width: 1
                border.color: isActive ? Theme.accent : Qt.alpha(Theme.accent, 0.2)
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰾅"
                        color: modeBal.isActive ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Balanced"
                        color: modeBal.isActive ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
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
                radius: 14
                readonly property bool isActive: root.batteryData.power_profile === "performance"
                color: isActive ? Theme.accent : (perfMa.containsMouse ? Qt.alpha(Theme.fg, 0.10) : Qt.alpha(Theme.fg, 0.04))
                border.width: 1
                border.color: isActive ? Theme.accent : Qt.alpha(Theme.accent, 0.2)
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰓅"
                        color: modePerf.isActive ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Performance"
                        color: modePerf.isActive ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
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

        // Battery Conservation Section Label
        Text {
            text: "Battery Conservation"
            color: Theme.secondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: true
        }

        // Conservation Card with Toggle Switch
        Rectangle {
            id: conservationCard
            width: parent.width
            height: 56
            radius: 14
            readonly property bool isEnabled: root.batteryData.conservation_mode || root.batteryData.charge_threshold === 60
            color: Sys.customModuleBg
            border.width: 1
            border.color: isEnabled ? Qt.alpha(Theme.accent, 0.35) : Sys.customModuleBorder
            Behavior on border.color { ColorAnimation { duration: 150 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                // Icon Badge
                Rectangle {
                    width: 36
                    height: 36
                    radius: Theme.buttonRadius
                    color: conservationCard.isEnabled ? Theme.accent : Qt.alpha(Theme.fg, 0.12)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󱈑"
                        color: conservationCard.isEnabled ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                // Title & Subtitle Texts
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    width: parent.width - 36 - 44 - 36 // minus icon, toggle, and margins

                    Text {
                        text: "Enable 60% Charge Limit"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                    }

                    Text {
                        text: conservationCard.isEnabled ? "Conservation active • Protects battery health" : "Disabled • Charges to 100% full capacity"
                        color: conservationCard.isEnabled ? Theme.green : Theme.secondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                // Toggle Switch
                Rectangle {
                    id: toggleTrack
                    width: 44
                    height: 24
                    radius: 12
                    color: conservationCard.isEnabled ? Theme.accent : Qt.alpha(Theme.fg, 0.2)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        id: toggleThumb
                        width: 18
                        height: 18
                        radius: 9
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        x: conservationCard.isEnabled ? 22 : 4
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setChargeThreshold(conservationCard.isEnabled ? 100 : 60)
            }
        }
    }
}
