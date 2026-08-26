import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland

PanelWindow {
    id: root

    property var modelData
    screen: modelData

    width: screen ? screen.width : 1920
    height: screen ? screen.height : 1080

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    visible: false

    property bool isLocked: false
    property bool isAuthenticating: false
    property bool isError: false
    property string errorMessage: ""

    function toggle() {
        if (visible) {
            unlock()
        } else {
            lock()
        }
    }

    function lock() {
        Sys.isLocked = true
        visible = true
        isLocked = true
        isError = false
        passwordInput.text = ""
        focusTimer.count = 0
        focusTimer.restart()
    }

    function unlock() {
        Sys.isLocked = false
        visible = false
        isLocked = false
        isError = false
        passwordInput.text = ""
        Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--restore"])
    }

    IpcHandler {
        target: "lockscreen"
        function toggle(): void { root.toggle() }
        function lock(): void { root.lock() }
        function unlock(): void { root.unlock() }
    }

    onVisibleChanged: {
        if (visible) {
            focusTimer.count = 0
            focusTimer.restart()
        }
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: true
        property int count: 0
        onTriggered: {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--lockscreen"])
            passwordInput.forceActiveFocus()
            count++
            if (count >= 5) {
                stop()
            }
        }
    }

    // Solid Base Background to prevent transparency
    Rectangle {
        anchors.fill: parent
        color: Sys.customBarBg
    }

    // Full-screen Background MouseArea to redirect all clicks to password input focus
    MouseArea {
        anchors.fill: parent
        onClicked: {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--lockscreen"])
            passwordInput.forceActiveFocus()
        }
    }

    // Background Wallpaper Image
    Image {
        anchors.fill: parent
        source: root.visible ? (Sys.currentWallpaper !== "" ? Sys.currentWallpaper : "file://" + Sys.homeDir + "/.config/bspwm/wallpapers/Default.png") : ""
        sourceSize: Qt.size(root.width > 0 ? root.width : 1920, root.height > 0 ? root.height : 1080)
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        cache: false

        // Darkening Overlay Tint
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.bg, 0.35)
        }
    }

    // Time & Date Updates
    property var currentTime: new Date()
    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: root.currentTime = new Date()
    }

    // Main Container
    Item {
        anchors.fill: parent

        // Top Clock & Date Container (Shifted up to red box area)
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -270
            spacing: 2

            // Date (e.g. Monday, Aug 24)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.currentTime, "dddd, MMM d")
                color: Qt.alpha("#ffffff", 0.95)
                font.family: Theme.fontFamily
                font.pixelSize: 28
                font.weight: Font.Medium
            }

            // Time (e.g. 10:15)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.currentTime, "hh:mm")
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 124
                font.bold: true
            }
        }

        // Center Profile & Password Column
        Column {
            id: centerCol
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 70
            spacing: 24

            // Circular User Profile Avatar
            Item {
                width: 120
                height: 120
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    id: avatarBorder
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.accent

                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    // Avatar Image Container with Clipping
                    Item {
                        anchors.fill: parent
                        anchors.margins: 4

                        Item {
                            anchors.fill: parent

                            Image {
                                id: avatarImg
                                anchors.fill: parent
                                source: root.visible ? Sys.userAvatar : ""
                                sourceSize: Qt.size(120, 120)
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                asynchronous: true
                                cache: false
                                visible: false
                            }

                            Rectangle {
                                id: lockAvatarMask
                                anchors.fill: parent
                                radius: width / 2
                                color: "black"
                                visible: false
                                antialiasing: true
                            }

                            OpacityMask {
                                anchors.fill: parent
                                source: avatarImg
                                maskSource: lockAvatarMask
                                visible: avatarImg.status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: avatarImg.status !== Image.Ready
                                text: "󰀉"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 48
                            }
                        }
                    }
                }
            }

            // Password Bar Input Pill
            Rectangle {
                id: passwordBox
                width: 260
                height: 42
                radius: 21
                color: Theme.bg
                border.width: 2
                border.color: root.isError ? Theme.red : (passwordInput.activeFocus ? Theme.accent : Theme.border)
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on border.color { ColorAnimation { duration: 150 } }

                // Shake Animation on Auth Fail
                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: passwordBox; property: "anchors.horizontalCenterOffset"; to: -12; duration: 50 }
                    NumberAnimation { target: passwordBox; property: "anchors.horizontalCenterOffset"; to: 12; duration: 50 }
                    NumberAnimation { target: passwordBox; property: "anchors.horizontalCenterOffset"; to: -8; duration: 50 }
                    NumberAnimation { target: passwordBox; property: "anchors.horizontalCenterOffset"; to: 8; duration: 50 }
                    NumberAnimation { target: passwordBox; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 8

                    // Lock Icon
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isAuthenticating ? "󰔟" : (root.isError ? "󰅙" : "󰌾")
                        color: root.isError ? Theme.red : Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                    }

                    // Password Field
                    TextInput {
                        id: passwordInput
                        focus: true
                        selectByMouse: true
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 55
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        echoMode: TextInput.Password
                        clip: true

                        onTextChanged: {
                            if (root.isError) root.isError = false
                        }

                        Keys.onReturnPressed: root.attemptUnlock()
                        Keys.onEnterPressed: root.attemptUnlock()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isError ? "Incorrect password" : "Enter Password..."
                            color: root.isError ? Qt.alpha(Theme.red, 0.7) : Qt.alpha(Theme.fg, 0.40)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            visible: !passwordInput.text
                        }
                    }

                    // Unlock Button
                    Rectangle {
                        width: 24
                        height: 24
                        radius: 12
                        color: submitMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "󰅂"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: submitMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.attemptUnlock()
                        }
                    }
                }
            }
        }
    }

    // Process for Password Verification
    Process {
        id: authProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.isAuthenticating = false
                if (text.trim().includes("SUCCESS")) {
                    root.unlock()
                } else {
                    root.isError = true
                    passwordInput.text = ""
                    shakeAnim.start()
                    passwordInput.forceActiveFocus()
                }
            }
        }
    }

    function attemptUnlock() {
        if (isAuthenticating || passwordInput.text === "") return
        isAuthenticating = true
        isError = false
        authProc.command = ["python3", Sys.scriptPath("lockscreen_auth.py"), passwordInput.text]
        authProc.running = false
        authProc.running = true
    }
}
