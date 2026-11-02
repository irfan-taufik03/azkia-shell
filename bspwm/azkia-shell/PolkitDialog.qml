import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Window {
    id: root

    property var modelData
    readonly property var targetScreen: modelData

    title: "Azkia Polkit Authentication"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Dialog
    color: "transparent"
    visible: false

    x: targetScreen ? (targetScreen.x || 0) : 0
    y: targetScreen ? (targetScreen.y || 0) : 0
    width: targetScreen ? (targetScreen.width || 1920) : 1920
    height: targetScreen ? (targetScreen.height || 1080) : 1080

    // Authentication States
    property string targetUser: "vaan"
    property bool isAuthenticating: false
    property bool isError: false
    property string errorMessage: ""
    property bool showPassword: false

    function openDialog() {
        Sys.isPolkitActive = true
        isAuthenticating = false
        isError = false
        errorMessage = ""
        showPassword = false
        passwordInput.text = ""
        visible = true
        root.requestActivate()
        focusTimer.count = 0
        focusTimer.restart()
    }

    function closeDialog() {
        Sys.isPolkitActive = false
        visible = false
        isAuthenticating = false
        isError = false
        showPassword = false
        passwordInput.text = ""
    }

    function submit() {
        if (isAuthenticating || passwordInput.text === "") return
        isAuthenticating = true
        isError = false
        Quickshell.execDetached(["python3", Sys.scriptPath("polkit_agent.py"), "--submit", passwordInput.text])
    }

    function cancel() {
        Quickshell.execDetached(["python3", Sys.scriptPath("polkit_agent.py"), "--cancel"])
        closeDialog()
    }

    function shake() {
        shakeAnim.restart()
    }

    Timer {
        id: focusTimer
        property int count: 0
        interval: 50
        repeat: true
        onTriggered: {
            passwordInput.forceActiveFocus()
            count++
            if (count > 5) stop()
        }
    }

    // Global shortcut to cancel on Escape
    Shortcut {
        sequence: "Escape"
        onActivated: root.cancel()
    }

    IpcHandler {
        target: "polkit"
        function show(actionId: string, message: string, iconName: string, cookie: string, user: string): void {
            root.targetUser = user || Sys.username || "vaan"
            root.openDialog()
        }
        function openAuth(actionId: string, message: string, iconName: string, cookie: string, user: string): void {
            root.targetUser = user || Sys.username || "vaan"
            root.openDialog()
        }
        function success(): void {
            root.closeDialog()
        }
        function fail(msg: string): void {
            root.isAuthenticating = false
            root.isError = true
            root.errorMessage = msg || "Incorrect password"
            root.shake()
            passwordInput.text = ""
            passwordInput.forceActiveFocus()
        }
        function close(): void {
            root.closeDialog()
        }
    }

    onActiveChanged: {
        if (active && visible) {
            passwordInput.forceActiveFocus()
        }
    }

    // Dimmed Fullscreen Backdrop - Clicking outside automatically cancels
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)

        Behavior on color { ColorAnimation { duration: 150 } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancel()
        }
    }

    // Centered Dialog Card
    Rectangle {
        id: cardBox
        width: 320
        implicitHeight: cardContent.implicitHeight + 44
        anchors.centerIn: parent
        radius: Theme.cardRadius
        color: Sys.customBarBg
        border.width: 1
        border.color: root.isError ? Theme.red : Sys.customModuleBorder

        Behavior on border.color { ColorAnimation { duration: 150 } }

        // Shake Animation on Auth Fail
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: cardBox; property: "anchors.horizontalCenterOffset"; to: -14; duration: 40 }
            NumberAnimation { target: cardBox; property: "anchors.horizontalCenterOffset"; to: 14; duration: 40 }
            NumberAnimation { target: cardBox; property: "anchors.horizontalCenterOffset"; to: -10; duration: 40 }
            NumberAnimation { target: cardBox; property: "anchors.horizontalCenterOffset"; to: 10; duration: 40 }
            NumberAnimation { target: cardBox; property: "anchors.horizontalCenterOffset"; to: -5; duration: 40 }
            NumberAnimation { target: cardBox; property: "anchors.horizontalCenterOffset"; to: 5; duration: 40 }
            NumberAnimation { target: cardBox; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
        }

        // Prevent clicks inside card from cancelling
        MouseArea {
            anchors.fill: parent
            onClicked: passwordInput.forceActiveFocus()
        }

        Column {
            id: cardContent
            anchors.top: parent.top
            anchors.topMargin: 22
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.right: parent.right
            anchors.rightMargin: 22
            spacing: 16

            // 1. User Identity Group (Avatar + Username closely spaced)
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5

                // User Avatar Centered
                Item {
                    width: 68
                    height: 68
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Circular Border Ring
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: root.isError ? Theme.red : Theme.accent

                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Item {
                            anchors.fill: parent
                            anchors.margins: 3

                            Image {
                                id: avatarImg
                                anchors.fill: parent
                                source: Sys.userAvatar
                                sourceSize: Qt.size(64, 64)
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                visible: false
                            }

                            Rectangle {
                                id: avatarMask
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                            }

                            OpacityMask {
                                anchors.fill: parent
                                source: avatarImg
                                maskSource: avatarMask
                                visible: avatarImg.status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: avatarImg.status !== Image.Ready
                                text: "󰀉"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 32
                            }
                        }
                    }
                }

                // User Name Below Avatar
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.targetUser
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                }
            }

            // 3. Password Input Box (Exact Lockscreen Style)
            Rectangle {
                id: passwordBox
                width: parent.width
                height: 42
                radius: Theme.cardRadius
                color: Sys.customModuleBg
                border.width: 1
                border.color: root.isError ? Theme.red : Sys.customModuleBorder

                Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.bg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                        clip: true

                        onTextChanged: {
                            if (root.isError) root.isError = false
                        }

                        onAccepted: root.submit()
                        Keys.onReturnPressed: root.submit()
                        Keys.onEnterPressed: root.submit()
                        Keys.onEscapePressed: root.cancel()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isError ? (root.errorMessage || "Incorrect password") : "Enter Password..."
                            color: root.isError ? Qt.alpha(Theme.red, 0.7) : Qt.alpha(Theme.fg, 0.40)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            visible: !passwordInput.text
                        }
                    }

                    // Eye Icon (Show/Hide Password) styled like Lockscreen action button
                    Rectangle {
                        width: 24
                        height: 24
                        radius: 12
                        color: eyeMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: root.showPassword ? "󰈈" : "󰈉"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: eyeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showPassword = !root.showPassword
                        }
                    }
                }
            }

            // 4. Action Buttons Row: Cancel and Authenticate
            Row {
                width: parent.width
                spacing: 10

                // Cancel Button
                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 38
                    radius: Sys.moduleRadius
                    color: cancelMa.containsMouse ? Sys.customModuleHoverBg : Sys.customModuleBg
                    border.width: 1
                    border.color: Sys.customModuleBorder

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: cancelMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancel()
                    }
                }

                // Authenticate Button
                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 38
                    radius: Sys.moduleRadius
                    color: authMa.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                    opacity: (passwordInput.text === "" || root.isAuthenticating) ? 0.6 : 1.0

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isAuthenticating ? "󰔟" : "󰄬"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            color: Sys.customBarBg
                            font.bold: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isAuthenticating ? "Verifying..." : "Authenticate"
                            color: Sys.customBarBg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: authMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: passwordInput.text !== "" && !root.isAuthenticating
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}
