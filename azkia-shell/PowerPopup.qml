import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 350
    cardHeight: 360

    function toggle() { visible = !visible }

    IpcHandler {
        target: "power"
        function toggle(): void { root.toggle() }
    }

    property int selectedIndex: 0

    onVisibleChanged: {
        if (visible) {
            root.selectedIndex = 0
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py")])
            keyCatcher.forceActiveFocus()
        } else {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--restore"])
        }
    }

    function runAction(cmd) {
        root.visible = false
        Quickshell.execDetached(cmd)
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onDownPressed: {
            root.selectedIndex = Math.min(powerCol.powerOptions.length - 1, root.selectedIndex + 1)
        }
        Keys.onUpPressed: {
            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
        }
        Keys.onReturnPressed: {
            if (root.selectedIndex >= 0 && root.selectedIndex < powerCol.powerOptions.length) {
                root.runAction(powerCol.powerOptions[root.selectedIndex].cmd)
            }
        }
        Keys.onEnterPressed: {
            if (root.selectedIndex >= 0 && root.selectedIndex < powerCol.powerOptions.length) {
                root.runAction(powerCol.powerOptions[root.selectedIndex].cmd)
            }
        }

        Column {
            anchors.fill: parent
            spacing: 12

            // ===== HEADER =====
            Item {
                width: parent.width
                height: 32

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⏻"
                        color: Theme.red
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Power Menu"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                    }
                }
            }

            // ===== LIST ITEMS =====
            Column {
                id: powerCol
                width: parent.width
                spacing: 7

                readonly property var powerOptions: [
                    {
                        name: "Lock Screen",
                        desc: "Lock current session",
                        icon: "󰌾",
                        color: "#8bd5ca",
                        cmd: ["quickshell", "--path", Sys.configDir, "ipc", "call", "lockscreen", "lock"]
                    },
                    {
                        name: "Suspend",
                        desc: "Suspend system to RAM",
                        icon: "󰤄",
                        color: "#c6a0f6",
                        cmd: ["systemctl", "suspend"]
                    },
                    {
                        name: "Restart",
                        desc: "Reboot the system",
                        icon: "󰜉",
                        color: "#eed49f",
                        cmd: ["systemctl", "reboot"]
                    },
                    {
                        name: "Power Off",
                        desc: "Shut down the system",
                        icon: "󰐥",
                        color: "#ed8796",
                        cmd: ["systemctl", "poweroff"]
                    },
                    {
                        name: "Log Out",
                        desc: "End BSPWM session",
                        icon: "󰗽",
                        color: "#f5a97f",
                        cmd: ["bspc", "quit"]
                    }
                ]

                Repeater {
                    model: powerCol.powerOptions

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        width: parent.width
                        height: 50
                        radius: 10
                        color: index === root.selectedIndex ? Qt.alpha(modelData.color, 0.3) : (itemMa.containsMouse ? Qt.alpha(modelData.color, 0.22) : Sys.customModuleBg)
                        border.width: 1
                        border.color: (index === root.selectedIndex || itemMa.containsMouse) ? modelData.color : Sys.customModuleBorder

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 14

                            // Colored Icon Box
                            Rectangle {
                                width: 36
                                height: 36
                                radius: 8
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.alpha(modelData.color, 0.20)

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    color: modelData.color
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18
                                }
                            }

                            // Labels
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text: modelData.name
                                    color: index === root.selectedIndex ? modelData.color : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                Text {
                                    text: modelData.desc
                                    color: Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }

                        MouseArea {
                            id: itemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedIndex = index
                                root.runAction(modelData.cmd)
                            }
                        }
                    }
                }
            }
        }
    }
}
