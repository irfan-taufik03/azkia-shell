import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

ShellRoot {
    id: rootShell

    Variants {
        model: Quickshell.screens

        Window {
            id: root
            property var modelData
            readonly property var targetScreen: modelData

            title: "Azkia Greeter"
            flags: Qt.FramelessWindowHint
            color: GreeterTheme.bg
            visible: true

            x: targetScreen ? (targetScreen.x || 0) : 0
            y: targetScreen ? (targetScreen.y || 0) : 0
            width: targetScreen ? (targetScreen.width || 1920) : 1920
            height: targetScreen ? (targetScreen.height || 1080) : 1080

            Component.onCompleted: {
                root.requestActivate()
                passwordInput.forceActiveFocus()
            }

            onActiveChanged: {
                if (active && sessionPopup.opacity < 0.1) {
                    passwordInput.forceActiveFocus()
                }
            }

            Timer {
                id: autoFocusTimer
                interval: 50
                running: true
                repeat: true
                property int count: 0
                onTriggered: {
                    passwordInput.forceActiveFocus()
                    count++
                    if (count >= 10 || passwordInput.activeFocus) {
                        stop()
                    }
                }
            }

            Timer {
                id: refocusTimer
                interval: 20
                onTriggered: {
                    if (sessionPopup.opacity < 0.1) {
                        passwordInput.forceActiveFocus()
                    }
                }
            }

        property bool isAuthenticating: false
        property bool isError: false
        property string errorMessage: ""
        property var sessionsList: []
        property int selectedSessionIndex: 0

        readonly property var currentSession: (sessionsList && sessionsList.length > 0 && selectedSessionIndex >= 0 && selectedSessionIndex < sessionsList.length) 
            ? sessionsList[selectedSessionIndex] 
            : ({ name: "bspwm", exec: "bspwm", icon: "󰖲", type: "x11" })

        // Load sessions list on startup
        Process {
            id: sessionsFetchProc
            command: ["python3", GreeterTheme.configDir + "/scripts/greetd_backend.py", "--sessions"]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const parsed = JSON.parse(text)
                        if (parsed && parsed.length > 0) {
                            root.sessionsList = parsed
                            // Default to bspwm
                            for (let i = 0; i < parsed.length; i++) {
                                if (parsed[i].name.toLowerCase().includes("bspwm")) {
                                    root.selectedSessionIndex = i
                                    break
                                }
                            }
                        }
                    } catch (e) {}
                }
            }
        }

        // Live Clock Updates
        property var currentTime: new Date()
        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: root.currentTime = new Date()
        }

        // Solid Base Background
        Rectangle {
            anchors.fill: parent
            color: GreeterTheme.bg
        }

        // Background Wallpaper Image (Synced dynamically from Azkia Shell ~/.fehbg)
        Image {
            id: bgWallpaper
            anchors.fill: parent
            source: GreeterTheme.currentWallpaper
            sourceSize: Qt.size(root.width > 0 ? root.width : 1920, root.height > 0 ? root.height : 1080)
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
            cache: false

            // Darkening Overlay Tint
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(GreeterTheme.bg, 0.35)
            }
        }

        // Click outside closes session popup and refocuses password
        MouseArea {
            anchors.fill: parent
            onClicked: {
                sessionPopup.opacity = 0.0
                root.requestActivate()
                passwordInput.forceActiveFocus()
            }
        }

        // --- Main Center Container ---
        Item {
            id: mainContainer
            anchors.fill: parent
            focus: true

            Keys.forwardTo: [passwordInput]
            Keys.onPressed: (event) => {
                if (!passwordInput.activeFocus && sessionPopup.opacity < 0.1) {
                    passwordInput.forceActiveFocus()
                }
            }

            // Top Clock & Date Container (Identical to Lockscreen.qml)
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -270
                spacing: 2

                // Date (e.g. Monday, Aug 24)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(root.currentTime, "dddd, MMM d")
                    color: Qt.alpha("#ffffff", 0.95)
                    font.family: GreeterTheme.fontFamily
                    font.pixelSize: 28
                    font.weight: Font.Medium
                }

                // Time (e.g. 10:15)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(root.currentTime, "hh:mm")
                    color: "#ffffff"
                    font.family: GreeterTheme.fontFamily
                    font.pixelSize: 124
                    font.bold: true
                }
            }

            // Center Profile & Capsule Column
            Column {
                id: centerCol
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 70
                spacing: 24

                // Circular User Profile Avatar (120x120 matching Lockscreen.qml)
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
                        border.color: GreeterTheme.accent

                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        Item {
                            anchors.fill: parent
                            anchors.margins: 4

                            Image {
                                id: avatarImg
                                anchors.fill: parent
                                source: GreeterTheme.userAvatar
                                sourceSize: Qt.size(120, 120)
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                asynchronous: true
                                cache: false
                                visible: false
                            }

                            Rectangle {
                                id: avatarMask
                                anchors.fill: parent
                                radius: width / 2
                                color: "black"
                                visible: false
                                antialiasing: true
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
                                color: GreeterTheme.accent
                                font.family: GreeterTheme.fontFamily
                                font.pixelSize: 48
                            }
                        }
                    }
                }

                // --- GREETD CAPSULE (Session Selector + Password Input + Login) ---
                Item {
                    id: capsuleContainer
                    width: sessionBtn.width + passwordInput.width + 92
                    height: 42
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Session Selector Dropdown Card (Pops up above capsule)
                    Rectangle {
                        id: sessionPopup
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 10
                        anchors.left: parent.left
                        width: Math.max(260, capsuleContainer.width)
                        height: sessionCol.implicitHeight + 20
                        radius: 16
                        color: GreeterTheme.cardBg
                        border.width: 1
                        border.color: Qt.alpha(GreeterTheme.accent, 0.45)
                        opacity: 0.0
                        visible: opacity > 0.01
                        z: 50

                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        layer.enabled: opacity > 0.01
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: Qt.alpha("#000000", 0.65)
                            shadowBlur: 1.0
                            shadowVerticalOffset: 6
                        }

                        Column {
                            id: sessionCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            Text {
                                text: "Select Session"
                                font.family: GreeterTheme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: GreeterTheme.accent
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Repeater {
                                model: root.sessionsList

                                delegate: Rectangle {
                                    id: sessionItemCard
                                    width: sessionCol.width
                                    height: 32
                                    radius: sessionBtn.radius
                                    color: itemMa.containsMouse
                                        ? GreeterTheme.accent
                                        : (index === root.selectedSessionIndex ? Qt.alpha(GreeterTheme.accent, 0.22) : "transparent")
                                    border.width: (index === root.selectedSessionIndex && !itemMa.containsMouse) ? 1 : 0
                                    border.color: GreeterTheme.accent

                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    Item {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8

                                        Row {
                                            anchors.left: parent.left
                                            anchors.right: typeBadge.left
                                            anchors.rightMargin: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 8

                                            Text {
                                                text: modelData.icon || "󰍹"
                                                font.family: GreeterTheme.fontFamily
                                                font.pixelSize: 14
                                                color: itemMa.containsMouse
                                                    ? GreeterTheme.bg
                                                    : ((index === root.selectedSessionIndex) ? GreeterTheme.accent : GreeterTheme.fg)
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Text {
                                                text: modelData.name || "Session"
                                                font.family: GreeterTheme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: (index === root.selectedSessionIndex || itemMa.containsMouse)
                                                color: itemMa.containsMouse
                                                    ? GreeterTheme.bg
                                                    : ((index === root.selectedSessionIndex) ? "#ffffff" : GreeterTheme.fg)
                                                anchors.verticalCenter: parent.verticalCenter
                                                elide: Text.ElideRight
                                                width: parent.width - 24
                                            }
                                        }

                                        Rectangle {
                                            id: typeBadge
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: typeText.implicitWidth + 8
                                            height: 16
                                            radius: 4
                                            color: itemMa.containsMouse
                                                ? Qt.alpha(GreeterTheme.bg, 0.22)
                                                : Qt.alpha(GreeterTheme.fg, 0.1)

                                            Text {
                                                id: typeText
                                                anchors.centerIn: parent
                                                text: modelData.type || "x11"
                                                font.family: GreeterTheme.fontFamily
                                                font.pixelSize: 9
                                                font.bold: itemMa.containsMouse
                                                color: itemMa.containsMouse
                                                    ? GreeterTheme.bg
                                                    : Qt.alpha(GreeterTheme.fg, 0.7)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: itemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            root.selectedSessionIndex = index
                                            sessionPopup.opacity = 0.0
                                            passwordInput.forceActiveFocus()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Main Capsule Rectangle
                    Rectangle {
                        id: passwordBox
                        anchors.fill: parent
                        radius: GreeterTheme.cardRadius
                        color: GreeterTheme.bg
                        border.width: 1
                        border.color: root.isError ? GreeterTheme.red : (root.isAuthenticating ? GreeterTheme.accent : GreeterTheme.border)

                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        // Shake Animation on Error
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
                            anchors.leftMargin: 8
                            anchors.rightMargin: 10
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter

                            // 1. DE/WM Session Selector Pill Button
                            Rectangle {
                                id: sessionBtn
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(76, sessionBtnContent.implicitWidth + 16)
                                height: 28
                                radius: GreeterTheme.cardRadius - 4
                                color: sessionBtnMa.containsMouse ? Qt.alpha(GreeterTheme.accent, 0.22) : Qt.alpha(GreeterTheme.fg, 0.08)
                                border.width: sessionBtnMa.containsMouse ? 1 : 0
                                border.color: GreeterTheme.accent

                                Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                Row {
                                    id: sessionBtnContent
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Text {
                                        text: root.currentSession.icon || "󰖲"
                                        font.family: GreeterTheme.fontFamily
                                        font.pixelSize: 13
                                        color: GreeterTheme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: root.currentSession.name || "bspwm"
                                        font.family: GreeterTheme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: GreeterTheme.fg
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: "󰅀"
                                        font.family: GreeterTheme.fontFamily
                                        font.pixelSize: 10
                                        color: Qt.alpha(GreeterTheme.fg, 0.6)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: sessionBtnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        sessionPopup.opacity = (sessionPopup.opacity > 0.5 ? 0.0 : 1.0)
                                    }
                                }
                            }

                            // 2. Subtle Vertical Divider
                            Rectangle {
                                width: 1
                                height: 18
                                color: Qt.alpha(GreeterTheme.fg, 0.15)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // 3. Lock Status Icon / Animated Spinner
                            Item {
                                width: 16
                                height: 16
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    visible: !root.isAuthenticating
                                    text: root.isError ? "󰅙" : "󰌾"
                                    color: root.isError ? GreeterTheme.red : GreeterTheme.accent
                                    font.family: GreeterTheme.fontFamily
                                    font.pixelSize: 15
                                }

                                Text {
                                    id: spinnerIcon
                                    anchors.centerIn: parent
                                    visible: root.isAuthenticating
                                    text: "󰑮"
                                    color: GreeterTheme.accent
                                    font.family: GreeterTheme.fontFamily
                                    font.pixelSize: 15

                                    RotationAnimation on rotation {
                                        from: 0
                                        to: 360
                                        duration: 800
                                        loops: Animation.Infinite
                                        running: root.isAuthenticating
                                    }
                                }
                            }

                            // 4. Password Input Field
                            TextInput {
                                id: passwordInput
                                focus: true
                                selectByMouse: true
                                anchors.verticalCenter: parent.verticalCenter
                                width: 120
                                color: GreeterTheme.fg
                                selectionColor: GreeterTheme.accent
                                selectedTextColor: GreeterTheme.bg
                                font.family: GreeterTheme.fontFamily
                                font.pixelSize: 13
                                echoMode: TextInput.Password
                                clip: true

                                onTextChanged: {
                                    if (root.isError) root.isError = false
                                }

                                Keys.onReturnPressed: root.attemptLogin()
                                Keys.onEnterPressed: root.attemptLogin()

                                onActiveFocusChanged: {
                                    if (!activeFocus && sessionPopup.opacity < 0.1) {
                                        refocusTimer.restart()
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.isAuthenticating ? "Logging in..." : (root.isError ? (root.errorMessage || "Incorrect password") : "Enter Password...")
                                    color: root.isAuthenticating ? GreeterTheme.accent : (root.isError ? Qt.alpha(GreeterTheme.red, 0.8) : Qt.alpha(GreeterTheme.fg, 0.40))
                                    font.family: GreeterTheme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: root.isAuthenticating
                                    visible: !passwordInput.text || root.isAuthenticating
                                }
                            }

                            // 5. Submit / Login Button (matching Lockscreen.qml)
                            Rectangle {
                                width: 24
                                height: 24
                                radius: 12
                                color: root.isAuthenticating ? Qt.alpha(GreeterTheme.accent, 0.3) : (submitMa.containsMouse ? Qt.alpha(GreeterTheme.accent, 0.25) : "transparent")
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: root.isAuthenticating ? "󰔟" : "󰅂"
                                    color: GreeterTheme.accent
                                    font.family: GreeterTheme.fontFamily
                                    font.pixelSize: 14
                                }

                                MouseArea {
                                    id: submitMa
                                    anchors.fill: parent
                                    hoverEnabled: !root.isAuthenticating
                                    enabled: !root.isAuthenticating
                                    onClicked: root.attemptLogin()
                                }
                            }
                        }
                    }
                }

                // --- Power Buttons Row below Capsule with Tooltips ---
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16
                    z: 10

                    // Suspend Button
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 19
                        color: suspMa.containsMouse ? Qt.alpha(GreeterTheme.accent, 0.25) : Qt.alpha(GreeterTheme.bg, 0.65)
                        border.width: 1
                        border.color: suspMa.containsMouse ? GreeterTheme.accent : Qt.alpha(GreeterTheme.fg, 0.15)

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰤄"
                            font.family: GreeterTheme.fontFamily
                            font.pixelSize: 16
                            color: suspMa.containsMouse ? GreeterTheme.accent : GreeterTheme.fg
                        }

                        // Tooltip
                        Rectangle {
                            anchors.top: parent.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: suspTipText.implicitWidth + 14
                            height: 24
                            radius: 6
                            color: GreeterTheme.cardBg
                            border.width: 1
                            border.color: Qt.alpha(GreeterTheme.accent, 0.45)
                            opacity: suspMa.containsMouse ? 1.0 : 0.0
                            visible: opacity > 0.01
                            z: 100

                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            Text {
                                id: suspTipText
                                anchors.centerIn: parent
                                text: "Suspend"
                                font.family: GreeterTheme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: GreeterTheme.fg
                            }
                        }

                        MouseArea {
                            id: suspMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.execPower("suspend")
                        }
                    }

                    // Reboot Button
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 19
                        color: rebMa.containsMouse ? Qt.alpha(GreeterTheme.accent, 0.25) : Qt.alpha(GreeterTheme.bg, 0.65)
                        border.width: 1
                        border.color: rebMa.containsMouse ? GreeterTheme.accent : Qt.alpha(GreeterTheme.fg, 0.15)

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰜉"
                            font.family: GreeterTheme.fontFamily
                            font.pixelSize: 16
                            color: rebMa.containsMouse ? GreeterTheme.accent : GreeterTheme.fg
                        }

                        // Tooltip
                        Rectangle {
                            anchors.top: parent.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: rebTipText.implicitWidth + 14
                            height: 24
                            radius: 6
                            color: GreeterTheme.cardBg
                            border.width: 1
                            border.color: Qt.alpha(GreeterTheme.accent, 0.45)
                            opacity: rebMa.containsMouse ? 1.0 : 0.0
                            visible: opacity > 0.01
                            z: 100

                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            Text {
                                id: rebTipText
                                anchors.centerIn: parent
                                text: "Restart"
                                font.family: GreeterTheme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: GreeterTheme.fg
                            }
                        }

                        MouseArea {
                            id: rebMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.execPower("reboot")
                        }
                    }

                    // Shutdown Button
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 19
                        color: pwrMa.containsMouse ? Qt.alpha(GreeterTheme.red, 0.35) : Qt.alpha(GreeterTheme.bg, 0.65)
                        border.width: 1
                        border.color: pwrMa.containsMouse ? GreeterTheme.red : Qt.alpha(GreeterTheme.fg, 0.15)

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰐥"
                            font.family: GreeterTheme.fontFamily
                            font.pixelSize: 16
                            color: pwrMa.containsMouse ? GreeterTheme.red : GreeterTheme.fg
                        }

                        // Tooltip
                        Rectangle {
                            anchors.top: parent.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: pwrTipText.implicitWidth + 14
                            height: 24
                            radius: 6
                            color: GreeterTheme.cardBg
                            border.width: 1
                            border.color: Qt.alpha(GreeterTheme.red, 0.5)
                            opacity: pwrMa.containsMouse ? 1.0 : 0.0
                            visible: opacity > 0.01
                            z: 100

                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            Text {
                                id: pwrTipText
                                anchors.centerIn: parent
                                text: "Power Off"
                                font.family: GreeterTheme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: GreeterTheme.fg
                            }
                        }

                        MouseArea {
                            id: pwrMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.execPower("poweroff")
                        }
                    }
                }
            }
        }

        // --- Backend Authentication Process ---
        Process {
            id: loginProc
            stdout: StdioCollector {
                onStreamFinished: {
                    root.isAuthenticating = false
                    try {
                        const res = JSON.parse(text)
                        if (res.status === "success") {
                            if (res.mode === "preview") {
                                // Standalone Preview Notification
                                previewToast.show("Authenticated! (Preview Mode: Session " + root.currentSession.name + ")")
                                passwordInput.text = ""
                            } else {
                                // Greetd mode: greetd starts the session as soon as the greeter terminates
                                Qt.quit()
                            }
                        } else {
                            root.isError = true
                            root.errorMessage = res.message || "Authentication failed"
                            passwordInput.text = ""
                            shakeAnim.start()
                            passwordInput.forceActiveFocus()
                        }
                    } catch (e) {
                        root.isError = true
                        root.errorMessage = "Login error"
                        shakeAnim.start()
                    }
                }
            }
        }

        function attemptLogin() {
            if (isAuthenticating || passwordInput.text === "") return
            isAuthenticating = true
            isError = false
            sessionPopup.opacity = 0.0
            
            const sessionCmd = root.currentSession.exec || "bspwm"
            const sessionType = root.currentSession.type || "x11"
            const sessionName = root.currentSession.name || "bspwm"
            loginProc.command = [
                "python3", 
                GreeterTheme.configDir + "/scripts/greetd_backend.py", 
                "--login", 
                GreeterTheme.username, 
                passwordInput.text, 
                sessionCmd,
                sessionType,
                sessionName
            ]
            loginProc.running = false
            loginProc.running = true
        }

        function execPower(action) {
            let label = (action === "poweroff" ? "Power Off" : (action === "reboot" ? "Restart" : "Suspend"))
            if (previewToast) {
                previewToast.show("Executing " + label + "...")
            }

            // Execute detached directly via Quickshell to prevent event-loop stalls or process leaks
            Quickshell.execDetached([
                "python3",
                GreeterTheme.configDir + "/scripts/greetd_backend.py",
                "--power",
                action
            ])
        }

        // Preview Mode Toast Indicator
        Rectangle {
            id: previewToast
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 30
            anchors.horizontalCenter: parent.horizontalCenter
            width: toastText.implicitWidth + 30
            height: 36
            radius: 18
            color: Qt.alpha(GreeterTheme.bg, 0.95)
            border.width: 1
            border.color: GreeterTheme.accent
            opacity: 0.0
            visible: opacity > 0.01

            function show(msg) {
                toastText.text = msg
                opacity = 1.0
                toastTimer.restart()
            }

            Behavior on opacity { NumberAnimation { duration: 200 } }

            Text {
                id: toastText
                anchors.centerIn: parent
                font.family: GreeterTheme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: GreeterTheme.accent
            }

            Timer {
                id: toastTimer
                interval: 3000
                onTriggered: previewToast.opacity = 0.0
            }
        }
        }
    }
}
