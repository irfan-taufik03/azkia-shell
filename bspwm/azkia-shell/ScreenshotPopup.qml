import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 380
    cardHeight: 68

    IpcHandler {
        target: "screenshot"
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

    Timer {
        id: execTimer
        interval: 200
        repeat: false
        property var pendingCmd: []
        onTriggered: {
            if (pendingCmd && pendingCmd.length > 0) {
                Quickshell.execDetached(pendingCmd)
            }
        }
    }

    function runAction(cmd) {
        root.close()
        execTimer.pendingCmd = cmd
        execTimer.restart()
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: {
            if (shotRow.shotOptions.length > 0) {
                if (root.selectedIndex < 0) {
                    root.selectedIndex = 0
                } else {
                    root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                }
            }
        }
        Keys.onRightPressed: {
            if (shotRow.shotOptions.length > 0) {
                if (root.selectedIndex < 0) {
                    root.selectedIndex = 0
                } else {
                    root.selectedIndex = Math.min(shotRow.shotOptions.length - 1, root.selectedIndex + 1)
                }
            }
        }
        Keys.onReturnPressed: {
            if (root.selectedIndex >= 0 && root.selectedIndex < shotRow.shotOptions.length) {
                root.runAction(shotRow.shotOptions[root.selectedIndex].cmd)
            } else if (root.selectedIndex < 0 && shotRow.shotOptions.length > 0) {
                root.runAction(shotRow.shotOptions[0].cmd)
            }
        }
        Keys.onEnterPressed: {
            if (root.selectedIndex >= 0 && root.selectedIndex < shotRow.shotOptions.length) {
                root.runAction(shotRow.shotOptions[root.selectedIndex].cmd)
            } else if (root.selectedIndex < 0 && shotRow.shotOptions.length > 0) {
                root.runAction(shotRow.shotOptions[0].cmd)
            }
        }

        Row {
            id: shotRow
            anchors.centerIn: parent
            spacing: 10

            readonly property var shotOptions: [
                {
                    name: "Selection",
                    icon: "󰆞",
                    iconColor: Theme.magenta,
                    cmd: ["flameshot", "gui"]
                },
                {
                    name: "Screen",
                    icon: "󰍹",
                    iconColor: Theme.blue,
                    cmd: ["flameshot", "full"]
                },
                {
                    name: "Window",
                    icon: "󰖲",
                    iconColor: Theme.purple,
                    cmd: ["python3", Sys.scriptPath("screenshot_window.py")]
                }
            ]

            Repeater {
                model: shotRow.shotOptions

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool isKeyboardSelected: (root.selectedIndex >= 0) && (root.selectedIndex === index)
                    readonly property bool isHovered: itemMa.containsMouse

                    width: 110
                    height: 40
                    radius: 14
                    color: isKeyboardSelected ? Theme.accent : (isHovered ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                    border.width: 1
                    border.color: (isKeyboardSelected || isHovered) ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            color: isKeyboardSelected ? Sys.customBarBg : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 18

                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: isKeyboardSelected ? Sys.customBarBg : Qt.alpha(Theme.fg, 0.8)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true

                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
