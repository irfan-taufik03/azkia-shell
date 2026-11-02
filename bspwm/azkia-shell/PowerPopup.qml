import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 350
    cardHeight: 360

    IpcHandler {
        target: "power"
        function toggle(): void { root.toggle() }
    }

    property int selectedIndex: -1

    onVisibleChanged: {
        if (visible) {
            root.selectedIndex = -1
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
            if (powerCol.powerOptions.length > 0) {
                if (root.selectedIndex < 0) {
                    root.selectedIndex = 0
                } else {
                    root.selectedIndex = Math.min(powerCol.powerOptions.length - 1, root.selectedIndex + 1)
                }
            }
        }
        Keys.onUpPressed: {
            if (powerCol.powerOptions.length > 0) {
                if (root.selectedIndex < 0) {
                    root.selectedIndex = powerCol.powerOptions.length - 1
                } else {
                    root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                }
            }
        }
        Keys.onReturnPressed: {
            if (root.selectedIndex >= 0 && root.selectedIndex < powerCol.powerOptions.length) {
                root.runAction(powerCol.powerOptions[root.selectedIndex].cmd)
            } else if (root.selectedIndex < 0 && powerCol.powerOptions.length > 0) {
                root.runAction(powerCol.powerOptions[0].cmd)
            }
        }
        Keys.onEnterPressed: {
            if (root.selectedIndex >= 0 && root.selectedIndex < powerCol.powerOptions.length) {
                root.runAction(powerCol.powerOptions[root.selectedIndex].cmd)
            } else if (root.selectedIndex < 0 && powerCol.powerOptions.length > 0) {
                root.runAction(powerCol.powerOptions[0].cmd)
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
                        cmd: ["sh", "-c", "qs -p " + Sys.configDir + " ipc call lockscreen lock; systemctl suspend"]
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

                        readonly property bool isKeyboardSelected: (root.selectedIndex >= 0) && (index === root.selectedIndex)
                        readonly property bool isHovered: itemMa.containsMouse

                        width: parent.width
                        height: 50
                        radius: 14
                        color: isKeyboardSelected ? Theme.accent : (isHovered ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                        border.width: 1
                        border.color: (isKeyboardSelected || isHovered) ? Theme.accent : Sys.customModuleBorder

                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 12
                            spacing: 14

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon
                                color: isKeyboardSelected ? Sys.customBarBg : modelData.color
                                font.family: Theme.fontFamily
                                font.pixelSize: 20

                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }

                            // Labels
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text: modelData.name
                                    color: isKeyboardSelected ? Sys.customBarBg : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true

                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                }

                                Text {
                                    text: modelData.desc
                                    color: isKeyboardSelected ? Qt.alpha(Sys.customBarBg, 0.75) : Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10

                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
