import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Window {
    id: root

    property var modelData
    title: "Settings"
    flags: Qt.Dialog
    width: 820
    height: 720
    color: Sys.customBarBg
    visible: false

    // Intercept closing (e.g. via bspc node -c / super + c) to hide window instead of destroying
    Component.onCompleted: {
        root.loadWallpapers()
        root.loadBspwmInfo()
        root.loadKeybindings()
    }

    property var sysInfoData: ({
        distro: "Linux",
        kernel: "-",
        wm: "BSPWM",
        shell: "Azkia Shell",
        host: "PC",
        cpu: "-",
        ram: "-",
        ram_str: "-",
        uptime: "-"
    })

    Process {
        id: sysFetchProc
        command: ["python3", Sys.scriptPath("sys_fetch.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.sysInfoData = JSON.parse(text)
                } catch (e) {}
            }
        }
    }

    function loadSysInfo() {
        sysFetchProc.running = false
        sysFetchProc.running = true
    }

    onVisibleChanged: {
        if (visible) {
            root.activeTab = "sysinfo"
            root.loadSysInfo()
            root.loadWallpapers()
            root.loadBspwmInfo()
            root.loadKeybindings()
        }
    }

    onClosing: (close) => {
        close.accepted = false
        root.visible = false
    }

    function toggle() {
        visible = !visible
        if (visible) {
            activeTab = "sysinfo"
            loadSysInfo()
            loadWallpapers()
            loadBspwmInfo()
            loadKeybindings()
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.toggle() }
        function open(): void {
            root.visible = true
            root.activeTab = "sysinfo"
            root.loadSysInfo()
            root.loadWallpapers()
            root.loadBspwmInfo()
            root.loadKeybindings()
        }
    }

    // Active Navigation Tab State
    property bool addModalOpen: false
    property string targetClusterKey: "left"
    property string targetClusterTitle: "Left Cluster"
    property string activeTab: "sysinfo" // options: sysinfo, appearance, theme, bar_style, module_pos, layout, keybindings, window_rules

    // Category Expand/Collapse State
    property bool catPersonalizationOpen: true
    property bool catBarOpen: true
    property bool catBspwmOpen: true

    // Data Holders
    property var wallpapersList: []
    property var bspwmData: ({ "gap": 8, "border": 2, "rules": [] })
    property var keybindingsList: []
    property var displayData: ({ "monitors": [], "primary": "eDP-1", "rotation": "normal", "supported_modes": [], "current_mode": "1920x1080", "current_scale": "100%" })
    property bool resDropdownOpen: false

    Process {
        id: displayGetProc
        command: ["python3", Sys.scriptPath("display_manager.py"), "--get"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length > 0) {
                    root.parseDisplayInfo(text)
                }
            }
        }
    }

    Process {
        id: displaySetProc
    }

    function loadDisplayInfo() {
        displayGetProc.running = false
        displayGetProc.running = true
    }

    function parseDisplayInfo(t) {
        try {
            let parsed = JSON.parse(t.trim())
            if (parsed && !parsed.error) {
                root.displayData = parsed
            }
        } catch(e) {}
    }

    function setResolution(res) {
        let mon = (root.displayData && root.displayData.primary) ? root.displayData.primary : "eDP-1"
        displaySetProc.command = ["python3", Sys.scriptPath("display_manager.py"), "--set-resolution", mon, res]
        displaySetProc.running = false
        displaySetProc.running = true
        let obj = root.displayData || {}
        obj.current_mode = res
        root.displayData = obj
    }

    function setRotation(rot) {
        let mon = (root.displayData && root.displayData.primary) ? root.displayData.primary : "eDP-1"
        displaySetProc.command = ["python3", Sys.scriptPath("display_manager.py"), "--set-rotation", mon, rot]
        displaySetProc.running = false
        displaySetProc.running = true
        let obj = root.displayData || {}
        obj.rotation = rot
        root.displayData = obj
    }

    function setScale(sc) {
        let mon = (root.displayData && root.displayData.primary) ? root.displayData.primary : "eDP-1"
        displaySetProc.command = ["python3", Sys.scriptPath("display_manager.py"), "--set-scale", mon, sc]
        displaySetProc.running = false
        displaySetProc.running = true
        let obj = root.displayData || {}
        obj.current_scale = sc
        root.displayData = obj
    }

    // Processes
    Process {
        id: bspwmSetProc
    }

    function setBspwmGap(val) {
        let v = Math.max(0, Math.min(40, Math.round(val)))
        let obj = root.bspwmData || {}
        obj.gap = v
        root.bspwmData = obj
        bspwmSetProc.command = ["python3", Sys.scriptPath("bspwm_editor.py"), "--set-gap", v.toString()]
        bspwmSetProc.running = false
        bspwmSetProc.running = true
    }

    function setBspwmBorder(val) {
        let v = Math.max(0, Math.min(10, Math.round(val)))
        let obj = root.bspwmData || {}
        obj.border = v
        root.bspwmData = obj
        bspwmSetProc.command = ["python3", Sys.scriptPath("bspwm_editor.py"), "--set-border", v.toString()]
        bspwmSetProc.running = false
        bspwmSetProc.running = true
    }

    function setPicomCornerRadiusUI(val) {
        let v = Math.max(0, Math.min(30, Math.round(val)))
        let obj = root.bspwmData || {}
        obj.corner_radius = v
        root.bspwmData = obj
    }

    function applyPicomCornerRadius() {
        let v = (root.bspwmData && root.bspwmData.corner_radius !== undefined) ? root.bspwmData.corner_radius : 12
        bspwmSetProc.command = ["python3", Sys.scriptPath("bspwm_editor.py"), "--set-corner-radius", v.toString()]
        bspwmSetProc.running = false
        bspwmSetProc.running = true
    }

Process {
        id: wallpaperProc
        command: ["python3", Sys.scriptPath("wallpaper.py"), "--dir", Sys.wallpaperDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpapersList = JSON.parse(text)
                } catch (e) {
                    root.wallpapersList = []
                }
            }
        }
    }

    Connections {
        target: Sys
        function onWallpaperDirChanged() {
            root.loadWallpapers()
        }
    }

    Process {
        id: bspwmProc
        command: ["python3", Sys.scriptPath("bspwm_editor.py"), "--get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.bspwmData = JSON.parse(text)
                } catch (e) {}
            }
        }
    }

    Process {
        id: sxhkdProc
        command: ["python3", Sys.scriptPath("sxhkd_editor.py"), "--get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.keybindingsList = JSON.parse(text)
                } catch (e) {
                    root.keybindingsList = []
                }
            }
        }
    }

    function loadWallpapers() { wallpaperProc.running = false; wallpaperProc.running = true }
    function loadBspwmInfo() { bspwmProc.running = false; bspwmProc.running = true }
    function loadKeybindings() { sxhkdProc.running = false; sxhkdProc.running = true }

    // Main Floating Window Rectangle (Matches Popout / CalendarPopup outer chrome)
    Rectangle {
        id: windowCard
        anchors.fill: parent
        color: Sys.customBarBg
        radius: 12
        border.width: 0.5
        border.color: Theme.altbg
        clip: true

        Behavior on color { ColorAnimation { duration: 200 } }

        // Window Header Bar
        Rectangle {
            id: headerBar
            width: parent.width
            height: 52
            color: "transparent"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰒓"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Settings"
                    color: Theme.fg
                    font.pixelSize: 18
                    font.bold: true
                }
            }

            // Close Window Button
            Rectangle {
                width: 34
                height: 34
                radius: 8
                color: closeMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : "transparent"
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    color: closeMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                }

                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.visible = false
                }
            }
        }

        // Main Content View Split (Sidebar + Right Content)
        Item {
            anchors.top: headerBar.bottom
            anchors.bottom: parent.bottom
            width: parent.width

            // ===== LEFT NAVIGATION SIDEBAR =====
            Rectangle {
                id: sidebar
                width: 220
                height: parent.height
                color: "transparent"

                Flickable {
                    id: sidebarFlick
                    anchors.fill: parent
                    anchors.margins: 8
                    contentHeight: sidebarCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: sidebarCol
                        width: sidebarFlick.width - 16
                        spacing: 12

                        // Profile Header Card (Clickable -> Opens System Info)
                        Rectangle {
                            width: parent.width
                            height: 64
                            radius: Sys.moduleRadius
                            color: profileCardMa.containsMouse ? Qt.alpha(Theme.accent, 0.20) : (root.activeTab === "sysinfo" ? Qt.alpha(Theme.accent, 0.12) : Sys.customModuleBg)
                            border.width: root.activeTab === "sysinfo" ? 1.5 : 1
                            border.color: root.activeTab === "sysinfo" ? Theme.accent : Qt.alpha(Theme.fg, 0.16)
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Row {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Item {
                                    width: 44
                                    height: 44

                                    Image {
                                        id: sideAvatarImg
                                        anchors.fill: parent
                                        source: Sys.userAvatar
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        mipmap: true
                                        visible: false
                                    }

                                    Rectangle {
                                        id: sideAvatarMask
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "black"
                                        visible: false
                                        antialiasing: true
                                    }

                                    OpacityMask {
                                        anchors.fill: parent
                                        source: sideAvatarImg
                                        maskSource: sideAvatarMask
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 1.5
                                        border.color: Theme.accent
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    Text {
                                        text: Sys.userName !== "" ? Sys.userName : "User"
                                        color: Theme.fg
                                        font.pixelSize: 14
                                        font.bold: true
                                    }

                                    Text {
                                        text: "Azkia Shell"
                                        color: root.activeTab === "sysinfo" ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            MouseArea {
                                id: profileCardMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeTab = "sysinfo"
                            }
                        }

                        // --- MENU 1: PERSONALIZATION ---
                        Column {
                            width: parent.width
                            spacing: 4

                            // Category Header Button
                            Rectangle {
                                width: parent.width
                                height: 38
                                radius: 8
                                color: catPersMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent"

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰸉"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 16
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Personalization"
                                            color: Theme.fg
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.catPersonalizationOpen ? "󰅀" : "󰅂"
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }
                                }

                                MouseArea {
                                    id: catPersMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.catPersonalizationOpen = !root.catPersonalizationOpen
                                }
                            }

                            // Submenus
                            Column {
                                width: parent.width
                                visible: root.catPersonalizationOpen
                                spacing: 3

                                // Appearance Submenu
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    radius: 6
                                    color: root.activeTab === "appearance" ? Qt.alpha(Theme.accent, 0.20) : (subWallMa.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent")
                                    border.width: root.activeTab === "appearance" ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.40)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 24
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰸉"
                                            color: root.activeTab === "appearance" ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Appearance"
                                            color: root.activeTab === "appearance" ? Theme.fg : Qt.alpha(Theme.fg, 0.8)
                                            font.pixelSize: 13
                                        }
                                    }

                                    MouseArea {
                                        id: subWallMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.activeTab = "appearance"
                                    }
                                }

                                // Theme & Colors Submenu
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    radius: 6
                                    color: root.activeTab === "theme" ? Qt.alpha(Theme.accent, 0.20) : (subThemeMa.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent")
                                    border.width: root.activeTab === "theme" ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.40)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 24
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰏘"
                                            color: root.activeTab === "theme" ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Theme & Colors"
                                            color: root.activeTab === "theme" ? Theme.fg : Qt.alpha(Theme.fg, 0.8)
                                            font.pixelSize: 13
                                        }
                                    }

                                    MouseArea {
                                        id: subThemeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.activeTab = "theme"
                                    }
                                }
                            }
                        }

                        // --- MENU 2: BAR ---
                        Column {
                            width: parent.width
                            spacing: 4

                            // Category Header Button
                            Rectangle {
                                width: parent.width
                                height: 38
                                radius: 8
                                color: catBarMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent"

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰅀"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 16
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Bar Settings"
                                            color: Theme.fg
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.catBarOpen ? "󰅀" : "󰅂"
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }
                                }

                                MouseArea {
                                    id: catBarMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.catBarOpen = !root.catBarOpen
                                }
                            }

                            // Submenus
                            Column {
                                width: parent.width
                                visible: root.catBarOpen
                                spacing: 3

                                // Bar Style Submenu
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    radius: 6
                                    color: root.activeTab === "bar_style" ? Qt.alpha(Theme.accent, 0.20) : (subBarStyleMa.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent")
                                    border.width: root.activeTab === "bar_style" ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.40)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 24
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰓡"
                                            color: root.activeTab === "bar_style" ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Bar Style"
                                            color: root.activeTab === "bar_style" ? Theme.fg : Qt.alpha(Theme.fg, 0.8)
                                            font.pixelSize: 13
                                        }
                                    }

                                    MouseArea {
                                        id: subBarStyleMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.activeTab = "bar_style"
                                    }
                                }

                                // Module Position Submenu
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    radius: 6
                                    color: root.activeTab === "module_pos" ? Qt.alpha(Theme.accent, 0.20) : (subModPosMa.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent")
                                    border.width: root.activeTab === "module_pos" ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.40)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 24
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰒅"
                                            color: root.activeTab === "module_pos" ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Module Position"
                                            color: root.activeTab === "module_pos" ? Theme.fg : Qt.alpha(Theme.fg, 0.8)
                                            font.pixelSize: 13
                                        }
                                    }

                                    MouseArea {
                                        id: subModPosMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.activeTab = "module_pos"
                                    }
                                }
                            }
                        }

                        // --- MENU 3: BSPWM ---
                        Column {
                            width: parent.width
                            spacing: 4

                            // Category Header Button
                            Rectangle {
                                width: parent.width
                                height: 38
                                radius: 8
                                color: catBspwmMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent"

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰍹"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 16
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "BSPWM"
                                            color: Theme.fg
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.catBspwmOpen ? "󰅀" : "󰅂"
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }
                                }

                                MouseArea {
                                    id: catBspwmMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.catBspwmOpen = !root.catBspwmOpen
                                }
                            }

                            // Submenus
                            Column {
                                width: parent.width
                                visible: root.catBspwmOpen
                                spacing: 3

                                // Layout Submenu
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    radius: 6
                                    color: root.activeTab === "layout" ? Qt.alpha(Theme.accent, 0.20) : (subLayoutMa.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent")
                                    border.width: root.activeTab === "layout" ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.40)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 24
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰘸"
                                            color: root.activeTab === "layout" ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Window Geometry"
                                            color: root.activeTab === "layout" ? Theme.fg : Qt.alpha(Theme.fg, 0.8)
                                            font.pixelSize: 13
                                        }
                                    }

                                    MouseArea {
                                        id: subLayoutMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            root.activeTab = "layout"
                                            root.loadBspwmInfo()
                                        }
                                    }
                                }

                                // Keybindings Submenu
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    radius: 6
                                    color: root.activeTab === "keybindings" ? Qt.alpha(Theme.accent, 0.20) : (subKeysMa.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent")
                                    border.width: root.activeTab === "keybindings" ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.40)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 24
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰌌"
                                            color: root.activeTab === "keybindings" ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Keybindings"
                                            color: root.activeTab === "keybindings" ? Theme.fg : Qt.alpha(Theme.fg, 0.8)
                                            font.pixelSize: 13
                                        }
                                    }

                                    MouseArea {
                                        id: subKeysMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            root.activeTab = "keybindings"
                                            root.loadKeybindings()
                                        }
                                    }
                                }

                                // Window Rules Submenu
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    radius: 6
                                    color: root.activeTab === "window_rules" ? Qt.alpha(Theme.accent, 0.20) : (subRulesMa.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent")
                                    border.width: root.activeTab === "window_rules" ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.40)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 24
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰖲"
                                            color: root.activeTab === "window_rules" ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Window Rules"
                                            color: root.activeTab === "window_rules" ? Theme.fg : Qt.alpha(Theme.fg, 0.8)
                                            font.pixelSize: 13
                                        }
                                    }

                                    MouseArea {
                                        id: subRulesMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            root.activeTab = "window_rules"
                                            root.loadBspwmInfo()
                                        }
                                    }
                                }
                            }
                        }

                        // --- MENU 4: DISPLAY (STANDALONE TOP-LEVEL MENU ABOVE AUTO LOCK) ---
                        Rectangle {
                            width: parent.width
                            height: 38
                            radius: 8
                            color: root.activeTab === "display" ? Qt.alpha(Theme.accent, 0.20) : (btnDisplayTopMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent")
                            border.width: root.activeTab === "display" ? 1 : 0
                            border.color: Qt.alpha(Theme.accent, 0.40)

                            Item {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰍹"
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 16
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Display"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                }
                            }

                            MouseArea {
                                id: btnDisplayTopMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeTab = "display"
                                    root.loadDisplayInfo()
                                }
                            }
                        }

                        // --- MENU 5: AUTO LOCK (STANDALONE TOP-LEVEL MENU AT BOTTOM) ---
                        Rectangle {
                            width: parent.width
                            height: 38
                            radius: 8
                            color: root.activeTab === "autolock" ? Qt.alpha(Theme.accent, 0.20) : (btnAutoLockTopMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent")
                            border.width: root.activeTab === "autolock" ? 1 : 0
                            border.color: Qt.alpha(Theme.accent, 0.40)

                            Item {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰌾"
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 16
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Auto Lock"
                                        color: Theme.fg
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                }
                            }

                            MouseArea {
                                id: btnAutoLockTopMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeTab = "autolock"
                            }
                        }
                    }
                }

                // Scrollbar Track (Outside Flickable so coordinate space is stationary)
                Item {
                    id: sidebarScrollTrack
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: 14

                    readonly property bool isScrolling: sidebarFlick.moving || sidebarFlick.flicking || sidebarFlick.dragging
                    readonly property bool showThumb: isScrolling || sbMa.containsMouse || sbMa.pressed

                    MouseArea {
                        id: sbMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeVerCursor

                        onPressed: (mouse) => updatePosition(mouse.y)
                        onPositionChanged: (mouse) => {
                            if (pressed) updatePosition(mouse.y)
                        }

                        function updatePosition(mouseY) {
                            const trackH = sidebarScrollTrack.height
                            const thumbH = sidebarScrollThumb.height
                            if (trackH <= thumbH) return
                            const maxThumbY = trackH - thumbH
                            const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                            const ratio = clampedY / maxThumbY
                            const maxContentY = sidebarFlick.contentHeight - sidebarFlick.height
                            if (maxContentY > 0) {
                                sidebarFlick.contentY = ratio * maxContentY
                            }
                        }
                    }

                    Rectangle {
                        id: sidebarScrollThumb
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        width: 8
                        height: 36
                        y: {
                            const maxContentY = sidebarFlick.contentHeight - sidebarFlick.height
                            const maxThumbY = sidebarScrollTrack.height - height
                            if (maxContentY > 0 && maxThumbY > 0) {
                                return Math.max(0, Math.min((sidebarFlick.contentY / maxContentY) * maxThumbY, maxThumbY))
                            }
                            return 0
                        }
                        radius: 4
                        color: sbMa.pressed ? Qt.alpha(Theme.accent, 0.7) : (sbMa.containsMouse ? Qt.alpha(Theme.fg, 0.40) : Qt.alpha(Theme.fg, 0.20))
                        opacity: (sidebarFlick.contentHeight > sidebarFlick.height && sidebarScrollTrack.showThumb) ? 1.0 : 0.0

                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            // ===== RIGHT CONTENT PANELS =====
            Item {
                anchors.left: sidebar.right
                anchors.right: parent.right
                height: parent.height

                // --- 0. SYSTEM INFO PANEL ---
                Item {
                    anchors.fill: parent
                    visible: root.activeTab === "sysinfo"

                    Flickable {
                        id: sysFlick
                        anchors.fill: parent
                        anchors.margins: 14
                        contentHeight: sysCol.height + 20
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: sysCol
                            width: sysFlick.width - 24
                            spacing: 16

                            // HEADER: LOGO + AZKIA SHELL BANNER (No Card Container)
                            Item {
                                width: parent.width
                                height: 100

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 20

                                    // Logo Box
                                    Rectangle {
                                        width: 84
                                        height: 84
                                        radius: 16
                                        color: Qt.alpha(Theme.accent, 0.12)
                                        border.width: 1.5
                                        border.color: Qt.alpha(Theme.accent, 0.5)
                                        anchors.verticalCenter: parent.verticalCenter
                                        clip: true

                                        Image {
                                            anchors.centerIn: parent
                                            width: 64
                                            height: 64
                                            source: Qt.resolvedUrl("assets/azkia-shell-logo.svg").toString()
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                            sourceSize: Qt.size(128, 128)

                                            Text {
                                                anchors.centerIn: parent
                                                visible: parent.status !== Image.Ready || parent.source == ""
                                                text: "󰣚"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 44
                                            }
                                        }
                                    }

                                    // Title & Info
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4

                                        Text {
                                            text: "Azkia Shell"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 24
                                            font.bold: true
                                        }

                                        Text {
                                            text: root.sysInfoData.distro !== "" ? root.sysInfoData.distro : "BSPWM Desktop Environment"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            text: "BSPWM Window Manager • Quickshell Engine"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }

                            // FASTFETCH DETAILS CARD
                            Rectangle {
                                width: parent.width
                                height: sysDetailsCol.height + 32
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Sys.customModuleBorder

                                Column {
                                    id: sysDetailsCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 12

                                    // Section Header
                                    Row {
                                        width: parent.width
                                        spacing: 8
                                        Text {
                                            text: "󰋖"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "System Overview"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: Qt.alpha(Theme.fg, 0.08)
                                    }

                                    // Detail Rows
                                    Column {
                                        width: parent.width
                                        spacing: 8

                                        Repeater {
                                            model: [
                                                { icon: "󰟀", label: "OS / Distro", value: root.sysInfoData.distro || "-" },
                                                { icon: "󰌢", label: "Host Model", value: root.sysInfoData.host || "-" },
                                                { icon: "󰌽", label: "Kernel", value: root.sysInfoData.kernel || "-" },
                                                { icon: "󰍹", label: "Window Manager", value: root.sysInfoData.wm || "BSPWM" },
                                                { icon: "󰞵", label: "Desktop Shell", value: root.sysInfoData.shell || "Azkia Shell" },
                                                { icon: "󰍛", label: "CPU", value: root.sysInfoData.cpu || "-" },
                                                { icon: "󰘚", label: "Memory (RAM)", value: root.sysInfoData.ram_str || root.sysInfoData.ram || "-" },
                                                { icon: "󰔟", label: "System Uptime", value: root.sysInfoData.uptime || "-" }
                                            ]

                                            Rectangle {
                                                required property var modelData
                                                width: parent.width
                                                height: 38
                                                radius: 8
                                                color: Qt.alpha(Theme.fg, 0.04)

                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    spacing: 12

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.icon
                                                        color: Theme.accent
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 16
                                                        width: 24
                                                    }

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.label
                                                        color: Qt.alpha(Theme.fg, 0.75)
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        font.bold: true
                                                        width: 140
                                                    }

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.value
                                                        color: Theme.fg
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        elide: Text.ElideRight
                                                        width: parent.width - 24 - 140 - 24
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- 1. APPEARANCE PANEL ---
                Item {
                    anchors.fill: parent
                    visible: root.activeTab === "appearance"

                    Process {
                        id: avatarPickerProc
                        command: ["python3", Sys.scriptPath("select_file.py"), "Select User Avatar Image"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                if (text && text.trim().length > 0) {
                                    Sys.setAvatar(text.trim())
                                }
                            }
                        }
                    }

                    Process {
                        id: logoPickerProc
                        command: ["python3", Sys.scriptPath("select_file.py"), "Select Launcher Logo PNG"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                if (text && text.trim().length > 0) {
                                    Sys.setLauncherLogo(text.trim())
                                }
                            }
                        }
                    }

                    Process {
                        id: wallDirPickerProc
                        command: ["python3", Sys.scriptPath("select_file.py"), "--dir", "Select Wallpaper Directory"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                if (text && text.trim().length > 0) {
                                    Sys.setWallpaperDir(text.trim())
                                }
                            }
                        }
                    }

                    Process {
                        id: colorPickerProc
                        property string targetSection: ""
                        command: ["python3", Sys.scriptPath("select_color.py"), "Select Color", "#ffffff"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                if (text && text.trim().length > 0) {
                                    let chosenColor = text.trim()
                                    if (colorPickerProc.targetSection === "bar_bg") {
                                        Sys.setCustomBarBg(chosenColor)
                                    } else if (colorPickerProc.targetSection === "module_bg") {
                                        Sys.setCustomModuleBg(chosenColor)
                                    } else if (colorPickerProc.targetSection === "module_hover_bg") {
                                        Sys.setCustomModuleHoverBg(chosenColor)
                                    } else if (colorPickerProc.targetSection === "module_active_bg") {
                                        Sys.setCustomModuleActiveBg(chosenColor)
                                    } else if (colorPickerProc.targetSection === "accent_color") {
                                        Sys.setCustomModuleIconColor(chosenColor)
                                    } else if (colorPickerProc.targetSection.startsWith("color_")) {
                                        let idx = parseInt(colorPickerProc.targetSection.replace("color_", ""))
                                        Sys.setCustomColor(idx, chosenColor)
                                    }
                                }
                            }
                        }

                        function openPicker(sectionName, currentColor) {
                            targetSection = sectionName
                            let colStr = currentColor ? currentColor.toString() : "#ffffff"
                            command = ["python3", Sys.scriptPath("select_color.py"), "Select Color", colStr]
                            running = true
                        }
                    }

                    Flickable {
                        id: wallFlick
                        anchors.fill: parent
                        anchors.margins: 14
                        contentHeight: wallCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: wallCol
                            width: wallFlick.width - 24
                            spacing: 16

                            // CARD 1: USER AVATAR SETTINGS
                            Rectangle {
                                width: parent.width
                                height: 86
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Sys.customModuleBorder

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 16

                                    // Avatar Preview
                                    Item {
                                        id: avatarPreviewBox
                                        width: 52
                                        height: 52
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter

                                        Image {
                                            id: prevAvatarImg
                                            anchors.fill: parent
                                            source: Sys.userAvatar
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            mipmap: true
                                            visible: false
                                        }

                                        Rectangle {
                                            id: prevAvatarMask
                                            anchors.fill: parent
                                            radius: width / 2
                                            color: "black"
                                            visible: false
                                            antialiasing: true
                                        }

                                        OpacityMask {
                                            anchors.fill: parent
                                            source: prevAvatarImg
                                            maskSource: prevAvatarMask
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: width / 2
                                            color: "transparent"
                                            border.width: 1.5
                                            border.color: Theme.accent
                                        }
                                    }

                                    // Action Buttons Row (declared first for anchoring)
                                    Row {
                                        id: avBtnRow
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        // Browse Image Button
                                        Rectangle {
                                            width: 105
                                            height: 34
                                            radius: 8
                                            color: btnAvBrowseMa.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.15)
                                            border.width: 1
                                            border.color: Theme.accent

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    text: "󰉏"
                                                    color: Theme.accent
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 14
                                                }

                                                Text {
                                                    text: "Browse..."
                                                    color: Theme.fg
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                }
                                            }

                                            MouseArea {
                                                id: btnAvBrowseMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    avatarPickerProc.running = false
                                                    avatarPickerProc.running = true
                                                }
                                            }
                                        }

                                        // Reset Default Button
                                        Rectangle {
                                            width: 70
                                            height: 34
                                            radius: 8
                                            color: btnAvResetMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.06)
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Reset"
                                                color: Qt.alpha(Theme.fg, 0.8)
                                                font.pixelSize: 12
                                            }

                                            MouseArea {
                                                id: btnAvResetMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setAvatar(Sys.defaultAvatar)
                                            }
                                        }
                                    }

                                    // Title & Subtitle Column (Anchored between Preview and Buttons)
                                    Column {
                                        anchors.left: avatarPreviewBox.right
                                        anchors.leftMargin: 16
                                        anchors.right: avBtnRow.left
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4

                                        Text {
                                            width: parent.width
                                            text: "User Avatar"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            text: "Choose a custom profile image across all components."
                                            color: Qt.alpha(Theme.fg, 0.6)
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            // CARD 2: LAUNCHER LOGO SETTINGS
                            Rectangle {
                                width: parent.width
                                implicitHeight: logoMainCol.height + 32
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Sys.customModuleBorder

                                Column {
                                    id: logoMainCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 14

                                    // Top Row: Logo Image & Browse/Reset
                                    Item {
                                        width: parent.width
                                        height: 52

                                        // Logo Preview Box
                                        Rectangle {
                                            id: logoPreviewBox
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 52
                                            height: 52
                                            radius: 10
                                            color: Theme.altbg
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)
                                            clip: true

                                            Image {
                                                anchors.centerIn: parent
                                                width: Math.min(44, Sys.launcherIconSize * 1.5)
                                                height: Math.min(44, Sys.launcherIconSize * 1.5)
                                                source: Sys.launcherLogo
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                mipmap: true
                                                sourceSize: Qt.size(72, 72)
                                            }
                                        }

                                        // Action Buttons Row
                                        Row {
                                            id: logoBtnRow
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 8

                                            // Browse Image Button
                                            Rectangle {
                                                width: 105
                                                height: 34
                                                radius: 8
                                                color: btnLogoBrowseMa.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.15)
                                                border.width: 1
                                                border.color: Theme.accent

                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 6

                                                    Text {
                                                        text: "󰉏"
                                                        color: Theme.accent
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 14
                                                    }

                                                    Text {
                                                        text: "Browse..."
                                                        color: Theme.fg
                                                        font.pixelSize: 12
                                                        font.bold: true
                                                    }
                                                }

                                                MouseArea {
                                                    id: btnLogoBrowseMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        logoPickerProc.running = false
                                                        logoPickerProc.running = true
                                                    }
                                                }
                                            }

                                            // Reset Default Button
                                            Rectangle {
                                                width: 70
                                                height: 34
                                                radius: 8
                                                color: btnLogoResetMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.06)
                                                border.width: 1
                                                border.color: Qt.alpha(Theme.fg, 0.15)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Reset"
                                                    color: Qt.alpha(Theme.fg, 0.8)
                                                    font.pixelSize: 12
                                                }

                                                MouseArea {
                                                    id: btnLogoResetMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Sys.setLauncherLogo(Sys.defaultLauncherLogo)
                                                }
                                            }
                                        }

                                        // Title & Subtitle Column
                                        Column {
                                            anchors.left: logoPreviewBox.right
                                            anchors.leftMargin: 16
                                            anchors.right: logoBtnRow.left
                                            anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 4

                                            Text {
                                                width: parent.width
                                                text: "Launcher Logo"
                                                color: Theme.fg
                                                font.pixelSize: 15
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                text: "Customize the icon image on the desktop launcher module."
                                                color: Qt.alpha(Theme.fg, 0.6)
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: Qt.alpha(Theme.fg, 0.08)
                                    }

                                    // Bottom Row: Launcher Icon Size Slider
                                    Column {
                                        width: parent.width
                                        spacing: 8

                                        Row {
                                            width: parent.width
                                            spacing: 8

                                            Text {
                                                text: "Launcher Icon Size"
                                                color: Theme.fg
                                                font.pixelSize: 14
                                                font.bold: true
                                            }

                                            Text {
                                                text: "• Adjust dimensions of the logo inside the top bar pill"
                                                color: Qt.alpha(Theme.fg, 0.5)
                                                font.pixelSize: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Row {
                                            width: parent.width
                                            spacing: 14

                                            Item {
                                                id: logoSizeTrack
                                                width: parent.width - 45 - 32 - 28
                                                height: 32
                                                anchors.verticalCenter: parent.verticalCenter

                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: parent.width
                                                    height: 6
                                                    radius: 3
                                                    color: Qt.alpha(Theme.fg, 0.15)

                                                    Rectangle {
                                                        width: parent.width * (Math.max(0, Math.min(24, Sys.launcherIconSize - 12)) / 24)
                                                        height: parent.height
                                                        radius: 3
                                                        color: Theme.accent
                                                    }

                                                    Rectangle {
                                                        x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(24, Sys.launcherIconSize - 12)) / 24)) - width / 2))
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 14
                                                        height: 14
                                                        radius: 7
                                                        color: Theme.accent
                                                        border.width: 2
                                                        border.color: Theme.bg
                                                    }
                                                }

                                                MouseArea {
                                                    id: logoSizeMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor

                                                    function updateVal(mouseX) {
                                                        const clampedX = Math.max(0, Math.min(logoSizeTrack.width, mouseX))
                                                        const pct = clampedX / logoSizeTrack.width
                                                        Sys.setLauncherIconSize(12 + pct * 24)
                                                    }

                                                    onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                    onClicked: mouse => updateVal(mouse.x)
                                                    onWheel: wheel => Sys.setLauncherIconSize(Sys.launcherIconSize + (wheel.angleDelta.y > 0 ? 1 : -1))
                                                }
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 45
                                                horizontalAlignment: Text.AlignRight
                                                text: Sys.launcherIconSize + " px"
                                                color: Theme.accent
                                                font.pixelSize: 14
                                                font.bold: true
                                            }

                                            Rectangle {
                                                width: 32
                                                height: 32
                                                radius: 16
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: logoSizeRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                                border.width: 1
                                                border.color: Qt.alpha(Theme.fg, 0.15)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰑐"
                                                    color: (Sys.launcherIconSize !== 21) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 15
                                                }

                                                MouseArea {
                                                    id: logoSizeRstMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Sys.setLauncherIconSize(21)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // CARD 3: COMBINED WALLPAPER SETTINGS CARD
                            Rectangle {
                                width: parent.width
                                implicitHeight: wallHeaderCol.height + wallGrid.height + 48
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Sys.customModuleBorder

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 16

                                    // Header Info Inside Same Card
                                    Column {
                                        id: wallHeaderCol
                                        width: parent.width
                                        spacing: 4

                                        Text {
                                            text: "Wallpaper Settings"
                                            color: Theme.fg
                                            font.pixelSize: 20
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Select a wallpaper to apply to the desktop and lockscreen instantly."
                                            color: Qt.alpha(Theme.fg, 0.6)
                                            font.pixelSize: 13
                                        }
                                    }

                                    // Wallpaper Directory Selector Row
                                    Rectangle {
                                        width: parent.width
                                        height: 52
                                        radius: 10
                                        color: Qt.alpha(Theme.fg, 0.04)
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.fg, 0.16)

                                        Item {
                                            anchors.fill: parent
                                            anchors.margins: 10

                                            Row {
                                                anchors.left: parent.left
                                                anchors.right: wallDirBtnRow.left
                                                anchors.rightMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 10

                                                Rectangle {
                                                    width: 32; height: 32; radius: 8
                                                    color: Qt.alpha(Theme.accent, 0.15)
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰉋"
                                                        color: Theme.accent
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 16
                                                    }
                                                }

                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 42
                                                    spacing: 2

                                                    Text {
                                                        text: "Wallpaper Folder"
                                                        color: Theme.fg
                                                        font.pixelSize: 12
                                                        font.bold: true
                                                    }

                                                    Text {
                                                        text: Sys.wallpaperDir
                                                        color: Qt.alpha(Theme.fg, 0.5)
                                                        font.pixelSize: 11
                                                        elide: Text.ElideMiddle
                                                        width: parent.width
                                                    }
                                                }
                                            }

                                            Row {
                                                id: wallDirBtnRow
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 8

                                                // Browse Directory Button
                                                Rectangle {
                                                    width: 95
                                                    height: 32
                                                    radius: 6
                                                    color: btnWallDirBrowseMa.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.15)
                                                    border.width: 1
                                                    border.color: Theme.accent

                                                    Row {
                                                        anchors.centerIn: parent
                                                        spacing: 6

                                                        Text {
                                                            text: "󰉏"
                                                            color: Theme.accent
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 13
                                                        }

                                                        Text {
                                                            text: "Browse..."
                                                            color: Theme.fg
                                                            font.pixelSize: 11
                                                            font.bold: true
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: btnWallDirBrowseMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: wallDirPickerProc.running = true
                                                    }
                                                }

                                                // Reset Directory Button
                                                Rectangle {
                                                    width: 65
                                                    height: 32
                                                    radius: 6
                                                    color: btnWallDirResetMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)
                                                    border.width: 1
                                                    border.color: Qt.alpha(Theme.fg, 0.15)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "Reset"
                                                        color: Theme.fg
                                                        font.pixelSize: 11
                                                        font.bold: true
                                                    }

                                                    MouseArea {
                                                        id: btnWallDirResetMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: Sys.resetWallpaperDir()
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Wallpaper Grid Inside Same Card (4 Columns)
                                    Grid {
                                        id: wallGrid
                                        width: parent.width
                                        columns: 4
                                        spacing: 12

                                        Repeater {
                                            model: root.wallpapersList

                                            delegate: Item {
                                                required property var modelData

                                                width: (parent.width - 36) / 4
                                                height: width * 0.65
                                                z: wallMa.containsMouse ? 10 : 1

                                                Rectangle {
                                                    id: thumbCard
                                                    anchors.centerIn: parent
                                                    width: parent.width - 6
                                                    height: parent.height - 6
                                                    radius: 10
                                                    clip: true
                                                    color: Qt.alpha(Theme.fg, 0.08)

                                                    scale: wallMa.pressed ? 0.93 : (wallMa.containsMouse ? 1.06 : 1.0)
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

                                                    border.width: ((modelData.name && Sys.currentWallpaper.endsWith(modelData.name)) || Sys.currentWallpaper === ("file://" + modelData.path) || wallMa.containsMouse) ? 3 : 0
                                                    border.color: Theme.accent
                                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                                    Image {
                                                        anchors.fill: parent
                                                        source: (root.visible && root.activeTab === "appearance" && modelData.path) ? "file://" + modelData.path : ""
                                                        fillMode: Image.PreserveAspectCrop
                                                        smooth: true
                                                        sourceSize: Qt.size(240, 160)
                                                        asynchronous: true
                                                        cache: false
                                                        opacity: wallMa.containsMouse ? 1.0 : 0.85
                                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                                    }

                                                    // Accent glow tint on hover
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: Qt.alpha(Theme.accent, 0.15)
                                                        visible: wallMa.containsMouse
                                                    }

                                                    // Active Checkmark Badge (Shown when pressed or currently selected)
                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 32
                                                        height: 32
                                                        radius: 16
                                                        color: Theme.accent
                                                        visible: wallMa.pressed || (modelData.name && Sys.currentWallpaper.endsWith(modelData.name)) || Sys.currentWallpaper === ("file://" + modelData.path)

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "󰄬"
                                                            color: Theme.bg
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 18
                                                            font.bold: true
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: wallMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: Sys.setWallpaper(modelData.path)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Scrollbar Track (Outside Flickable)
                    Item {
                        id: wallScrollTrack
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 14
                        width: 16

                        readonly property bool isScrolling: wallFlick.moving || wallFlick.flicking || wallFlick.dragging
                        readonly property bool showThumb: isScrolling || wallSbMa.containsMouse || wallSbMa.pressed

                        MouseArea {
                            id: wallSbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeVerCursor

                            onPressed: (mouse) => updatePosition(mouse.y)
                            onPositionChanged: (mouse) => {
                                if (pressed) updatePosition(mouse.y)
                            }

                            function updatePosition(mouseY) {
                                const trackH = wallScrollTrack.height
                                const thumbH = wallScrollThumb.height
                                if (trackH <= thumbH) return
                                const maxThumbY = trackH - thumbH
                                const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                                const ratio = clampedY / maxThumbY
                                const maxContentY = wallFlick.contentHeight - wallFlick.height
                                if (maxContentY > 0) {
                                    wallFlick.contentY = ratio * maxContentY
                                }
                            }
                        }

                        Rectangle {
                            id: wallScrollThumb
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            width: 8
                            height: 36
                            y: {
                                const maxContentY = wallFlick.contentHeight - wallFlick.height
                                const maxThumbY = wallScrollTrack.height - height
                                if (maxContentY > 0 && maxThumbY > 0) {
                                    return Math.max(0, Math.min((wallFlick.contentY / maxContentY) * maxThumbY, maxThumbY))
                                }
                                return 0
                            }
                            radius: 4
                            color: wallSbMa.pressed ? Qt.alpha(Theme.accent, 0.7) : (wallSbMa.containsMouse ? Qt.alpha(Theme.fg, 0.40) : Qt.alpha(Theme.fg, 0.20))
                            opacity: (wallFlick.contentHeight > wallFlick.height && wallScrollTrack.showThumb) ? 1.0 : 0.0

                            Behavior on opacity { NumberAnimation { duration: 250 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

                // --- 2. THEME & COLORS PANEL ---
                Item {
                    id: themePanel
                    anchors.fill: parent
                    visible: root.activeTab === "theme"

                    Flickable {
                        id: themeFlick
                        anchors.fill: parent
                        anchors.margins: 14
                        contentHeight: themeCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: themeCol
                            width: themeFlick.width - 24
                            spacing: 16

                            // Card 1: Bar Background Color Card
                            Rectangle {
                                width: parent.width
                                height: 68
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16

                                    Text {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Shell Background Color"
                                        color: Theme.fg
                                        font.pixelSize: 15
                                        font.bold: true
                                    }

                                    Row {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        // Color Swatch Circle
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: Sys.customBarBg
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.25)
                                        }

                                        // Pencil Button
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: barPenMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰏫"
                                                color: Theme.fg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: barPenMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: colorPickerProc.openPicker("bar_bg", Sys.customBarBg)
                                            }
                                        }

                                        // Reset Button
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: barRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.customBarBg != Theme.bg) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: barRstMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setCustomBarBg(Theme.bg)
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 2: Module Background Card
                            Rectangle {
                                width: parent.width
                                height: 68
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16

                                    Text {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Module & Card Background"
                                        color: Theme.fg
                                        font.pixelSize: 15
                                        font.bold: true
                                    }

                                    Row {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        // Color Swatch Circle
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: Sys.customModuleBg
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.25)
                                        }

                                        // Pencil Button
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: modPenMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰏫"
                                                color: Theme.fg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: modPenMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: colorPickerProc.openPicker("module_bg", Sys.customModuleBg)
                                            }
                                        }

                                        // Reset Button
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: modRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.customModuleBg != Qt.alpha(Theme.fg, 0.09)) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: modRstMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setCustomModuleBg(Qt.alpha(Theme.fg, 0.09))
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 3: Module Icon & Accent Color Card
                            Rectangle {
                                width: parent.width
                                height: accentCardCol.implicitHeight + 32
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    id: accentCardCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 14

                                    Text {
                                        text: "Module Icon & Accent Color"
                                        color: Theme.fg
                                        font.pixelSize: 15
                                        font.bold: true
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: 10

                                        readonly property var accentListModel: [
                                            { index: 1, name: "Color 1 (Accent)", defColor: "#c6a0f6", curColor: Sys.customColor1 },
                                            { index: 2, name: "Color 2", defColor: "#8aadf4", curColor: Sys.customColor2 },
                                            { index: 3, name: "Color 3", defColor: "#8bd5ca", curColor: Sys.customColor3 },
                                            { index: 4, name: "Color 4", defColor: "#a6da95", curColor: Sys.customColor4 },
                                            { index: 5, name: "Color 5", defColor: "#eed49f", curColor: Sys.customColor5 },
                                            { index: 6, name: "Color 6", defColor: "#f5a97f", curColor: Sys.customColor6 },
                                            { index: 7, name: "Color 7", defColor: "#ed8796", curColor: Sys.customColor7 }
                                        ]

                                        Repeater {
                                            model: parent.accentListModel
                                            delegate: Column {
                                                required property var modelData
                                                required property int index
                                                width: parent.width
                                                spacing: 10

                                                Item {
                                                    width: parent.width
                                                    height: 40

                                                    Text {
                                                        anchors.left: parent.left
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.name
                                                        color: Theme.fg
                                                        font.pixelSize: 14
                                                        font.bold: true
                                                    }

                                                    Row {
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 10

                                                        // Color Swatch Circle (Updates when color chosen)
                                                        Rectangle {
                                                            width: 32
                                                            height: 32
                                                            radius: 16
                                                            color: modelData.curColor
                                                            border.width: 1
                                                            border.color: Qt.alpha(Theme.fg, 0.25)
                                                        }

                                                        // Pencil Button
                                                        Rectangle {
                                                            width: 32
                                                            height: 32
                                                            radius: 16
                                                            color: rowPenMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                                            border.width: 1
                                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "󰏫"
                                                                color: Theme.fg
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 15
                                                            }

                                                            MouseArea {
                                                                id: rowPenMa
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: colorPickerProc.openPicker("color_" + modelData.index, modelData.curColor)
                                                            }
                                                        }

                                                        // Reset Button
                                                        Rectangle {
                                                            width: 32
                                                            height: 32
                                                            radius: 16
                                                            color: rowRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                                            border.width: 1
                                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "󰑐"
                                                                color: (modelData.curColor != modelData.defColor) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 15
                                                            }

                                                            MouseArea {
                                                                id: rowRstMa
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: Sys.setCustomColor(modelData.index, modelData.defColor)
                                                            }
                                                        }
                                                    }
                                                }

                                                Rectangle {
                                                    visible: index < 6
                                                    width: parent.width
                                                    height: 1
                                                    color: Qt.alpha(Theme.fg, 0.06)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Scrollbar Track for Theme & Colors Panel
                    Item {
                        id: themeScrollTrack
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 14
                        width: 16

                        readonly property bool isScrolling: themeFlick.moving || themeFlick.flicking || themeFlick.dragging
                        readonly property bool showThumb: isScrolling || themeSbMa.containsMouse || themeSbMa.pressed

                        MouseArea {
                            id: themeSbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeVerCursor

                            onPressed: (mouse) => updatePosition(mouse.y)
                            onPositionChanged: (mouse) => {
                                if (pressed) updatePosition(mouse.y)
                            }

                            function updatePosition(mouseY) {
                                const trackH = themeScrollTrack.height
                                const thumbH = themeScrollThumb.height
                                if (trackH <= thumbH) return
                                const maxThumbY = trackH - thumbH
                                const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                                const ratio = clampedY / maxThumbY
                                const maxContentY = themeFlick.contentHeight - themeFlick.height
                                if (maxContentY > 0) {
                                    themeFlick.contentY = ratio * maxContentY
                                }
                            }
                        }

                        Rectangle {
                            id: themeScrollThumb
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            width: 8
                            height: Math.max(36, (themeFlick.height / Math.max(1, themeFlick.contentHeight)) * themeScrollTrack.height)
                            y: {
                                const maxContentY = themeFlick.contentHeight - themeFlick.height
                                const maxThumbY = themeScrollTrack.height - height
                                if (maxContentY > 0 && maxThumbY > 0) {
                                    return Math.max(0, Math.min((themeFlick.contentY / maxContentY) * maxThumbY, maxThumbY))
                                }
                                return 0
                            }
                            radius: 4
                            color: themeSbMa.pressed ? Qt.alpha(Theme.accent, 0.7) : (themeSbMa.containsMouse ? Qt.alpha(Theme.fg, 0.40) : Qt.alpha(Theme.fg, 0.20))
                            opacity: (themeFlick.contentHeight > themeFlick.height && themeScrollTrack.showThumb) ? 1.0 : 0.0

                            Behavior on opacity { NumberAnimation { duration: 250 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

                // --- DISPLAY & SCALE PANEL ---
                Item {
                    id: displayPanel
                    anchors.fill: parent
                    visible: root.activeTab === "display"

                    Flickable {
                        id: displayFlick
                        anchors.fill: parent
                        anchors.margins: 14
                        contentHeight: displayCol.height + 20
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: displayCol
                            width: displayFlick.width - 24
                            spacing: 16

                            // CARD 1: DISPLAY OVERVIEW CARD
                            Rectangle {
                                width: parent.width
                                height: 96
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Sys.customModuleBorder

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 16

                                    Row {
                                        anchors.fill: parent
                                        spacing: 16

                                        // Monitor Icon Box
                                        Rectangle {
                                            width: 64
                                            height: 64
                                            radius: 12
                                            color: Qt.alpha(Theme.accent, 0.15)
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.accent, 0.4)
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰍹"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 32
                                            }
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 4

                                            Row {
                                                spacing: 8
                                                Text {
                                                    text: root.displayData.primary ? root.displayData.primary : "Active Display"
                                                    color: Theme.fg
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 16
                                                    font.bold: true
                                                }
                                                Rectangle {
                                                    width: priTxt.width + 12
                                                    height: 20
                                                    radius: 10
                                                    color: Qt.alpha(Theme.accent, 0.2)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text {
                                                        id: priTxt
                                                        anchors.centerIn: parent
                                                        text: "PRIMARY"
                                                        color: Theme.accent
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 9
                                                        font.bold: true
                                                    }
                                                }
                                            }

                                            Text {
                                                text: "Resolution: " + (root.displayData.current_mode || "1920x1080") + "  •  Scale: " + (root.displayData.current_scale || "100%") + "  •  Rotation: " + (root.displayData.rotation || "normal")
                                                color: Qt.alpha(Theme.fg, 0.6)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                            }
                                        }

                                        Item {
                                            width: displayCol.width - 350
                                            height: 1
                                        }

                                        // Refresh Button
                                        Rectangle {
                                            width: 38
                                            height: 38
                                            radius: 8
                                            color: refDispMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.06)
                                            anchors.verticalCenter: parent.verticalCenter
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.1)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 16
                                            }

                                            MouseArea {
                                                id: refDispMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.loadDisplayInfo()
                                            }
                                        }
                                    }
                                }
                            }

                            // CARD 2: DISPLAY RESOLUTION SELECTION (DROPDOWN)
                            Rectangle {
                                width: parent.width
                                height: resCol.height + 32
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Sys.customModuleBorder

                                Column {
                                    id: resCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 12

                                    Row {
                                        width: parent.width
                                        spacing: 8
                                        Text {
                                            text: "󰍹"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "Display Resolution"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Text {
                                        text: "Select a supported screen resolution for your monitor:"
                                        color: Qt.alpha(Theme.fg, 0.6)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                    }

                                    // Dropdown Box Container
                                    Column {
                                        width: Math.min(parent.width, 360)
                                        spacing: 6

                                        // Dropdown Selector Button
                                        Rectangle {
                                            width: parent.width
                                            height: 42
                                            radius: 8
                                            color: root.resDropdownOpen ? Qt.alpha(Theme.accent, 0.15) : (resBoxMa.containsMouse ? Qt.alpha(Theme.fg, 0.1) : Qt.alpha(Theme.fg, 0.05))
                                            border.width: root.resDropdownOpen ? 1.5 : 1
                                            border.color: root.resDropdownOpen ? Theme.accent : Qt.alpha(Theme.fg, 0.2)

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 10

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "󰘲"
                                                    color: Theme.accent
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 15
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: (root.displayData && root.displayData.current_mode) ? root.displayData.current_mode : "Select Resolution..."
                                                    color: Theme.fg
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: root.resDropdownOpen ? "󰅀" : "󰅂"
                                                    color: root.resDropdownOpen ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 14
                                                }
                                            }

                                            MouseArea {
                                                id: resBoxMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.resDropdownOpen = !root.resDropdownOpen
                                            }
                                        }

                                        // Dropdown Menu List Popup
                                        Rectangle {
                                            width: parent.width
                                            height: root.resDropdownOpen ? Math.min(220, resListCol.height + 12) : 0
                                            visible: height > 0
                                            clip: true
                                            radius: 8
                                            color: Sys.customModuleBg
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.accent, 0.3)

                                            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

                                            Flickable {
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                contentHeight: resListCol.height
                                                clip: true

                                                Column {
                                                    id: resListCol
                                                    width: parent.width
                                                    spacing: 4

                                                    Repeater {
                                                        model: (root.displayData && root.displayData.supported_modes && root.displayData.supported_modes.length > 0) ? root.displayData.supported_modes : ["1920x1080", "1680x1050", "1400x900", "1280x720", "1024x768", "800x600"]

                                                        Rectangle {
                                                            required property string modelData
                                                            width: parent.width
                                                            height: 34
                                                            radius: 6
                                                            readonly property bool isSelected: root.displayData.current_mode === modelData
                                                            color: isSelected ? Qt.alpha(Theme.accent, 0.22) : (resItemMenuMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent")

                                                            Row {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: 10
                                                                anchors.rightMargin: 10
                                                                spacing: 8

                                                                Text {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: isSelected ? "󰄬" : " "
                                                                    color: Theme.accent
                                                                    font.family: Theme.fontFamily
                                                                    font.pixelSize: 13
                                                                }

                                                                Text {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: modelData
                                                                    color: isSelected ? Theme.accent : Theme.fg
                                                                    font.family: Theme.fontFamily
                                                                    font.pixelSize: 12
                                                                    font.bold: isSelected
                                                                }
                                                            }

                                                            MouseArea {
                                                                id: resItemMenuMa
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    root.setResolution(modelData)
                                                                    root.resDropdownOpen = false
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // CARD 3: DISPLAY SCALING SELECTION
                            Rectangle {
                                width: parent.width
                                height: scaleCol.height + 32
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Sys.customModuleBorder

                                Column {
                                    id: scaleCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 12

                                    Row {
                                        width: parent.width
                                        spacing: 8
                                        Text {
                                            text: "󰁌"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "Scale"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Text {
                                        text: "Adjust global desktop scaling percentage:"
                                        color: Qt.alpha(Theme.fg, 0.6)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 12

                                        Repeater {
                                            model: ["100%", "115%", "125%", "150%"]

                                            Rectangle {
                                                required property string modelData
                                                width: (parent.width - 36) / 4
                                                height: 48
                                                radius: 8
                                                readonly property bool isSelected: (root.displayData.current_scale || "100%") === modelData
                                                color: isSelected ? Qt.alpha(Theme.accent, 0.25) : (scaleItemMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05))
                                                border.width: isSelected ? 1.5 : 1
                                                border.color: isSelected ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                                                Column {
                                                    anchors.centerIn: parent
                                                    spacing: 2
                                                    Text {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        text: modelData
                                                        color: isSelected ? Theme.accent : Theme.fg
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 14
                                                        font.bold: true
                                                    }
                                                    Text {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        text: modelData === "100%" ? "Standard" : (modelData === "115%" ? "Medium" : (modelData === "125%" ? "Large" : "Extra Large"))
                                                        color: isSelected ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                    }
                                                }

                                                MouseArea {
                                                    id: scaleItemMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.setScale(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // CARD 4: DISPLAY ROTATION
                            Rectangle {
                                width: parent.width
                                height: rotCol.height + 32
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Sys.customModuleBorder

                                Column {
                                    id: rotCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 12

                                    Row {
                                        width: parent.width
                                        spacing: 8
                                        Text {
                                            text: "󰑔"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "Screen & Window Rotation"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Text {
                                        text: "Rotate monitor orientation:"
                                        color: Qt.alpha(Theme.fg, 0.6)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 12

                                        Repeater {
                                            model: [
                                                { label: "Normal (0°)", key: "normal", rotAngle: 0 },
                                                { label: "Left (90°)", key: "left", rotAngle: 270 },
                                                { label: "Right (90°)", key: "right", rotAngle: 90 },
                                                { label: "Inverted (180°)", key: "inverted", rotAngle: 180 }
                                            ]

                                            Rectangle {
                                                required property var modelData
                                                width: (parent.width - 36) / 4
                                                height: 54
                                                radius: 8
                                                readonly property bool isSelected: (root.displayData.rotation || "normal") === modelData.key
                                                color: isSelected ? Qt.alpha(Theme.accent, 0.25) : (rotItemMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05))
                                                border.width: isSelected ? 1.5 : 1
                                                border.color: isSelected ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                                                Column {
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    Text {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        text: "󰍹"
                                                        color: isSelected ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 18
                                                        rotation: modelData.rotAngle
                                                        Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                                                    }

                                                    Text {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        text: modelData.label
                                                        color: isSelected ? Theme.accent : Theme.fg
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        font.bold: isSelected
                                                    }
                                                }

                                                MouseArea {
                                                    id: rotItemMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.setRotation(modelData.key)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- AUTO LOCK PANEL ---
                Item {
                    id: autoLockPanel
                    anchors.fill: parent
                    visible: root.activeTab === "autolock"

                    Flickable {
                        id: autoLockFlick
                        anchors.fill: parent
                        anchors.margins: 14
                        contentHeight: autoLockCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: autoLockCol
                            width: autoLockFlick.width - 24
                            spacing: 16

                            // CARD 1: TOGGLE AUTO LOCK
                            Rectangle {
                                width: parent.width
                                height: 74
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 12

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰌾"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 22
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            Text {
                                                text: "Enable Auto Lock"
                                                color: Theme.fg
                                                font.pixelSize: 15
                                                font.bold: true
                                            }

                                            Text {
                                                text: "Otomatis mengunci layar saat komputer tidak digunakan (inaktif)."
                                                color: Qt.alpha(Theme.fg, 0.5)
                                                font.pixelSize: 12
                                            }
                                        }
                                    }

                                    // Toggle Switch
                                    Rectangle {
                                        width: 44
                                        height: 24
                                        radius: 12
                                        color: Sys.autoLockEnabled ? Theme.accent : Qt.alpha(Theme.fg, 0.2)
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Rectangle {
                                            width: 18
                                            height: 18
                                            radius: 9
                                            color: "#ffffff"
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: Sys.autoLockEnabled ? 22 : 4
                                            Behavior on x { NumberAnimation { duration: 150 } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Sys.setAutoLockEnabled(!Sys.autoLockEnabled)
                                        }
                                    }
                                }
                            }

                            // CARD 2: LOCK AFTER SLIDER
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)
                                opacity: Sys.autoLockEnabled ? 1.0 : 0.4

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    // Header: Title & Subtitle
                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Lock After"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Durasi waktu inaktif sebelum layar dikunci otomatis"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    // Bottom Row: Slider, Value Text & Reset Button
                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        // Wide Slider Track
                                        Item {
                                            id: lockTimeoutTrack
                                            width: parent.width - 55 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * Math.max(0, Math.min(1.0, (Math.round(Sys.autoLockTimeout / 60) - 1) / 29))
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * Math.max(0, Math.min(1.0, (Math.round(Sys.autoLockTimeout / 60) - 1) / 29))) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: Sys.autoLockEnabled
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(lockTimeoutTrack.width, mouseX))
                                                    const pct = clampedX / lockTimeoutTrack.width
                                                    const mins = Math.max(1, Math.min(30, Math.round(1 + pct * 29)))
                                                    Sys.setAutoLockTimeout(mins * 60)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => {
                                                    let curMins = Math.round(Sys.autoLockTimeout / 60)
                                                    let nextMins = Math.max(1, Math.min(30, curMins + (wheel.angleDelta.y > 0 ? 1 : -1)))
                                                    Sys.setAutoLockTimeout(nextMins * 60)
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 55
                                            text: Math.round(Sys.autoLockTimeout / 60) + " Min"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                            horizontalAlignment: Text.AlignRight
                                        }

                                        // Reset Button
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: lockRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.autoLockTimeout !== 180) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: lockRstMa
                                                anchors.fill: parent
                                                enabled: Sys.autoLockEnabled
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setAutoLockTimeout(180)
                                            }
                                        }
                                    }
                                }
                            }

                            // CARD 3: SLEEP AFTER SLIDER
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)
                                opacity: Sys.autoLockEnabled ? 1.0 : 0.4

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    // Header: Title & Subtitle
                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Sleep After"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Durasi waktu setelah dikunci sebelum layar mati otomatis (sleep)"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    // Bottom Row: Slider, Value Text & Reset Button
                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        // Wide Slider Track
                                        Item {
                                            id: sleepTimeoutTrack
                                            width: parent.width - 55 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * Math.max(0, Math.min(1.0, (Math.round(Sys.autoSleepTimeout / 60) - 1) / 29))
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * Math.max(0, Math.min(1.0, (Math.round(Sys.autoSleepTimeout / 60) - 1) / 29))) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: Sys.autoLockEnabled
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(sleepTimeoutTrack.width, mouseX))
                                                    const pct = clampedX / sleepTimeoutTrack.width
                                                    const mins = Math.max(1, Math.min(30, Math.round(1 + pct * 29)))
                                                    Sys.setAutoSleepTimeout(mins * 60)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => {
                                                    let curMins = Math.round(Sys.autoSleepTimeout / 60)
                                                    let nextMins = Math.max(1, Math.min(30, curMins + (wheel.angleDelta.y > 0 ? 1 : -1)))
                                                    Sys.setAutoSleepTimeout(nextMins * 60)
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 55
                                            text: Math.round(Sys.autoSleepTimeout / 60) + " Min"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                            horizontalAlignment: Text.AlignRight
                                        }

                                        // Reset Button
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: sleepRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.autoSleepTimeout !== 120) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: sleepRstMa
                                                anchors.fill: parent
                                                enabled: Sys.autoLockEnabled
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setAutoSleepTimeout(120)
                                            }
                                        }
                                    }
                                }
                            }

                            // STANDALONE APPLY BUTTON
                            Item {
                                width: parent.width
                                height: 36

                                Rectangle {
                                    width: 100
                                    height: 34
                                    radius: 6
                                    color: applyBtnMa.containsMouse ? Qt.alpha(Theme.accent, 0.85) : Theme.accent
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰑐"
                                            color: Theme.bg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Apply"
                                            color: Theme.bg
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: applyBtnMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Sys.saveAppearance()
                                            Sys.restartShell()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

// --- 3. BAR STYLE PANEL ---
                Item {
                    anchors.fill: parent
                    visible: root.activeTab === "bar_style"

                    Flickable {
                        id: barFlick
                        anchors.fill: parent
                        anchors.margins: 14
                        contentHeight: barCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: barCol
                            width: barFlick.width - 24
                            spacing: 16

                            // Card 1: Bar Outer Corner Radius
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    // Header: Title & Subtitle
                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Bar Outer Corner Radius"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust outer corner rounding of the main top bar"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    // Bottom Row: Slider, Value Text & Reset Button
                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        // Wide Slider Track
                                        Item {
                                            id: barRadTrack
                                            width: parent.width - 45 - 32 - 28 // Leave space for text & reset button
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(24, Sys.barRadius)) / 24)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(24, Sys.barRadius)) / 24)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                id: barRadMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(barRadTrack.width, mouseX))
                                                    const pct = clampedX / barRadTrack.width
                                                    Sys.setBarRadius(pct * 24)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => Sys.setBarRadius(Sys.barRadius + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: Sys.barRadius + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: barRadRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.barRadius !== 12) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: barRadRstMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setBarRadius(12)
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 2: Module Pill Corner Radius
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    // Header: Title & Subtitle
                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Module Pill Corner Radius"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust corner rounding of individual bar modules"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    // Bottom Row: Slider, Value Text & Reset Button
                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        // Wide Slider Track
                                        Item {
                                            id: modRadTrack
                                            width: parent.width - 45 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(16, Sys.moduleRadius)) / 16)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(16, Sys.moduleRadius)) / 16)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                id: modRadMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(modRadTrack.width, mouseX))
                                                    const pct = clampedX / modRadTrack.width
                                                    Sys.setModuleRadius(pct * 16)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => Sys.setModuleRadius(Sys.moduleRadius + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: Sys.moduleRadius + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: modRadRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.moduleRadius !== 10) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: modRadRstMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setModuleRadius(10)
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 3: Bar Height
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    // Header: Title & Subtitle
                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Bar Height"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust total height of the top bar"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    // Bottom Row: Slider, Value Text & Reset Button
                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        // Wide Slider Track (Range 30 to 50)
                                        Item {
                                            id: barHTrack
                                            width: parent.width - 45 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(20, Sys.barHeight - 30)) / 20)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(20, Sys.barHeight - 30)) / 20)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                id: barHMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(barHTrack.width, mouseX))
                                                    const pct = clampedX / barHTrack.width
                                                    Sys.setBarHeight(30 + pct * 20)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => Sys.setBarHeight(Sys.barHeight + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: Sys.barHeight + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: barHRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.barHeight !== 34) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: barHRstMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setBarHeight(34)
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 4: Bar Margin Top
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Bar Margin Top"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust top margin space above the bar"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Item {
                                            id: barMTTrack
                                            width: parent.width - 45 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(30, Sys.barMarginTop)) / 30)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(30, Sys.barMarginTop)) / 30)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                id: barMTMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(barMTTrack.width, mouseX))
                                                    const pct = clampedX / barMTTrack.width
                                                    Sys.setBarMarginTop(pct * 30)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => Sys.setBarMarginTop(Sys.barMarginTop + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: Sys.barMarginTop + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: barMTRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.barMarginTop !== 5) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: barMTRstMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setBarMarginTop(5)
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 5: Bar Margin Bottom
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Bar Margin Bottom"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust bottom margin space below the bar"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Item {
                                            id: barMBTrack
                                            width: parent.width - 45 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(30, Sys.barMarginBottom)) / 30)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(30, Sys.barMarginBottom)) / 30)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                id: barMBMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(barMBTrack.width, mouseX))
                                                    const pct = clampedX / barMBTrack.width
                                                    Sys.setBarMarginBottom(pct * 30)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => Sys.setBarMarginBottom(Sys.barMarginBottom + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: Sys.barMarginBottom + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: barMBRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.barMarginBottom !== 0) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: barMBRstMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setBarMarginBottom(0)
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 6: Bar Margin Left
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Bar Margin Left"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust left margin offset of the bar"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Item {
                                            id: barMLTrack
                                            width: parent.width - 45 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(50, Sys.barMarginLeft)) / 50)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(50, Sys.barMarginLeft)) / 50)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                id: barMLMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(barMLTrack.width, mouseX))
                                                    const pct = clampedX / barMLTrack.width
                                                    Sys.setBarMarginLeft(pct * 50)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => Sys.setBarMarginLeft(Sys.barMarginLeft + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: Sys.barMarginLeft + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: barMLRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.barMarginLeft !== 8) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: barMLRstMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setBarMarginLeft(8)
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 7: Bar Margin Right
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Bar Margin Right"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust right margin offset of the bar"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Item {
                                            id: barMRTrack
                                            width: parent.width - 45 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(50, Sys.barMarginRight)) / 50)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(50, Sys.barMarginRight)) / 50)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                id: barMRMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(barMRTrack.width, mouseX))
                                                    const pct = clampedX / barMRTrack.width
                                                    Sys.setBarMarginRight(pct * 50)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => Sys.setBarMarginRight(Sys.barMarginRight + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: Sys.barMarginRight + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: barMRRstMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: (Sys.barMarginRight !== 8) ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                            }

                                            MouseArea {
                                                id: barMRRstMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Sys.setBarMarginRight(8)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Scrollbar Track for Bar Style Panel (Outside Flickable)
                    Item {
                        id: barScrollTrack
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 14
                        width: 16

                        readonly property bool isScrolling: barFlick.moving || barFlick.flicking || barFlick.dragging
                        readonly property bool showThumb: isScrolling || barSbMa.containsMouse || barSbMa.pressed

                        MouseArea {
                            id: barSbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeVerCursor

                            onPressed: (mouse) => updatePosition(mouse.y)
                            onPositionChanged: (mouse) => {
                                if (pressed) updatePosition(mouse.y)
                            }

                            function updatePosition(mouseY) {
                                const trackH = barScrollTrack.height
                                const thumbH = barScrollThumb.height
                                if (trackH <= thumbH) return
                                const maxThumbY = trackH - thumbH
                                const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                                const ratio = clampedY / maxThumbY
                                const maxContentY = barFlick.contentHeight - barFlick.height
                                if (maxContentY > 0) {
                                    barFlick.contentY = ratio * maxContentY
                                }
                            }
                        }

                        Rectangle {
                            id: barScrollThumb
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            width: 8
                            height: Math.max(36, (barFlick.height / Math.max(1, barFlick.contentHeight)) * barScrollTrack.height)
                            y: {
                                const maxContentY = barFlick.contentHeight - barFlick.height
                                const maxThumbY = barScrollTrack.height - height
                                if (maxContentY > 0 && maxThumbY > 0) {
                                    return Math.max(0, Math.min((barFlick.contentY / maxContentY) * maxThumbY, maxThumbY))
                                }
                                return 0
                            }
                            radius: 4
                            color: barSbMa.pressed ? Qt.alpha(Theme.accent, 0.7) : (barSbMa.containsMouse ? Qt.alpha(Theme.fg, 0.40) : Qt.alpha(Theme.fg, 0.20))
                            opacity: (barFlick.contentHeight > barFlick.height && barScrollTrack.showThumb) ? 1.0 : 0.0

                            Behavior on opacity { NumberAnimation { duration: 250 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

// --- 4. MODULE POSITION PANEL ---
                Item {
                    id: modPosPanel
                    anchors.fill: parent
                    visible: root.activeTab === "module_pos" || root.activeTab === "module_position"

                    Flickable {
                        id: modPosFlick
                        anchors.fill: parent
                        MouseArea { id: modPosFlickHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                        anchors.margins: 14
                        contentHeight: modPosCol.height + 28
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: modPosCol
                            width: modPosFlick.width - 24
                            spacing: 16

                            // Panel Header Action Bar
                            Rectangle {
                                width: parent.width
                                height: 56
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16

                                    Column {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2

                                        Text {
                                            text: "Module Cluster Position & Order"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Re-order or add modules into Left, Center, and Right clusters"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    // Reset Default Button
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 130
                                        height: 32
                                        radius: 16
                                        color: resetPosMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.fg, 0.15)

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Text {
                                                text: "󰑐"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14
                                            }

                                            Text {
                                                text: "Reset Default"
                                                color: Theme.fg
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                        }

                                        MouseArea {
                                            id: resetPosMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Sys.resetModulePositions()
                                        }
                                    }
                                }
                            }

                            // Component Delegate for Cluster Card
                            component ClusterCard: Rectangle {
                                id: cardComp
                                property string clusterKey: "left" // "left", "center", "right"
                                property string titleText: "Left Cluster"
                                property var moduleList: []

                                width: parent.width
                                height: colContent.height + 32
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    id: colContent
                                    width: parent.width - 32
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.topMargin: 16
                                    spacing: 12

                                    // Header of Cluster
                                    Row {
                                        width: parent.width
                                        spacing: 8

                                        Text {
                                            text: cardComp.titleText
                                            color: Theme.accent
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            height: 20
                                            width: countTxt.implicitWidth + 12
                                            radius: 10
                                            color: Qt.alpha(Theme.fg, 0.10)

                                            Text {
                                                id: countTxt
                                                anchors.centerIn: parent
                                                text: (cardComp.moduleList ? cardComp.moduleList.length : 0) + " modules"
                                                color: Qt.alpha(Theme.fg, 0.6)
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                        }
                                    }

                                    // Empty state message
                                    Text {
                                        visible: !cardComp.moduleList || cardComp.moduleList.length === 0
                                        text: "No modules in this cluster"
                                        color: Qt.alpha(Theme.fg, 0.4)
                                        font.pixelSize: 13
                                        font.italic: true
                                    }

                                    // List of Modules in Cluster
                                    Column {
                                        width: parent.width
                                        spacing: 8
                                        visible: cardComp.moduleList && cardComp.moduleList.length > 0

                                        Repeater {
                                            model: cardComp.moduleList || []

                                            delegate: Rectangle {
                                                required property string modelData
                                                required property int index

                                                width: parent.width
                                                height: 42
                                                radius: 8
                                                color: Qt.alpha(Theme.fg, 0.04)
                                                border.width: 1
                                                border.color: Qt.alpha(Theme.fg, 0.16)

                                                Item {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12

                                                    // Module Icon & Name
                                                    Row {
                                                        anchors.left: parent.left
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 10

                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: Sys.getModuleIcon(modelData)
                                                            color: Theme.accent
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 16
                                                        }

                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: Sys.getModuleName(modelData)
                                                            color: Theme.fg
                                                            font.pixelSize: 13
                                                            font.bold: true
                                                        }
                                                    }

                                                    // Action Control Buttons (Move Up, Move Down, Remove)
                                                    Row {
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 6

                                                        // Move Up Button
                                                        Rectangle {
                                                            width: 28; height: 28; radius: 6
                                                            color: (index > 0 && upMa.containsMouse) ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.06)
                                                            opacity: index > 0 ? 1.0 : 0.35

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "▲"
                                                                color: Theme.fg
                                                                font.pixelSize: 11
                                                            }

                                                            MouseArea {
                                                                id: upMa
                                                                anchors.fill: parent
                                                                hoverEnabled: index > 0
                                                                cursorShape: index > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                                onClicked: { if (index > 0) Sys.moveClusterModuleUp(cardComp.clusterKey, index) }
                                                            }
                                                        }

                                                        // Move Down Button
                                                        Rectangle {
                                                            width: 28; height: 28; radius: 6
                                                            color: (index < (cardComp.moduleList ? cardComp.moduleList.length - 1 : 0) && dnMa.containsMouse) ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.06)
                                                            opacity: index < (cardComp.moduleList ? cardComp.moduleList.length - 1 : 0) ? 1.0 : 0.35

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "▼"
                                                                color: Theme.fg
                                                                font.pixelSize: 11
                                                            }

                                                            MouseArea {
                                                                id: dnMa
                                                                anchors.fill: parent
                                                                hoverEnabled: index < (cardComp.moduleList ? cardComp.moduleList.length - 1 : 0)
                                                                cursorShape: index < (cardComp.moduleList ? cardComp.moduleList.length - 1 : 0) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                                onClicked: { if (index < (cardComp.moduleList ? cardComp.moduleList.length - 1 : 0)) Sys.moveClusterModuleDown(cardComp.clusterKey, index) }
                                                            }
                                                        }

                                                        // Separator
                                                        Rectangle {
                                                            width: 1; height: 18; color: Qt.alpha(Theme.fg, 0.15)
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }

                                                        // Remove Button
                                                        Rectangle {
                                                            width: 72; height: 28; radius: 6
                                                            color: rmMa.containsMouse ? Qt.alpha("#ed8796", 0.25) : Qt.alpha("#ed8796", 0.10)
                                                            border.width: 1
                                                            border.color: Qt.alpha("#ed8796", 0.40)

                                                            Row {
                                                                anchors.centerIn: parent
                                                                spacing: 4

                                                                Text {
                                                                    text: "󰅖"
                                                                    color: "#ed8796"
                                                                    font.family: Theme.fontFamily
                                                                    font.pixelSize: 13
                                                                }

                                                                Text {
                                                                    text: "Remove"
                                                                    color: "#ed8796"
                                                                    font.pixelSize: 11
                                                                    font.bold: true
                                                                }
                                                            }

                                                            MouseArea {
                                                                id: rmMa
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: Sys.removeClusterModule(cardComp.clusterKey, index)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Add Module Button for this Cluster (Clean 1 icon & text)
                                    Rectangle {
                                        width: parent.width
                                        height: 36
                                        radius: 8
                                        color: addClusterMa.containsMouse ? Qt.alpha(Theme.accent, 0.20) : Qt.alpha(Theme.fg, 0.05)
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.accent, 0.35)

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Text {
                                                text: "󰐕"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14
                                            }

                                            Text {
                                                text: "Add Module"
                                                color: Theme.accent
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                        }

                                        MouseArea {
                                            id: addClusterMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.targetClusterKey = cardComp.clusterKey
                                                root.targetClusterTitle = cardComp.titleText
                                                root.addModalOpen = true
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 1: Left Cluster
                            ClusterCard {
                                clusterKey: "left"
                                titleText: "Left Cluster"
                                moduleList: Sys.leftModules
                            }

                            // Card 2: Center Cluster
                            ClusterCard {
                                clusterKey: "center"
                                titleText: "Center Cluster"
                                moduleList: Sys.centerModules
                            }

                            // Card 3: Right Cluster
                            ClusterCard {
                                clusterKey: "right"
                                titleText: "Right Cluster"
                                moduleList: Sys.rightModules
                            }
                        }
                    }

 
                    // Scrollbar for Module Position Panel
                    Item {
                        id: modPosScrollTrack
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        width: 10
                        z: 100

                        readonly property bool isScrolling: modPosFlick.movingVertically || modPosFlick.moving || modPosFlick.flicking || modPosFlick.dragging
                        readonly property bool showThumb: isScrolling || modPosSbMa.containsMouse || modPosSbMa.pressed || modPosFlickHover.containsMouse


                        MouseArea {
                            id: modPosSbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeVerCursor
                            onPressed: (mouse) => updatePos(mouse.y)
                            onPositionChanged: (mouse) => { if (pressed) updatePos(mouse.y) }

                            function updatePos(mouseY) {
                                const trackH = modPosScrollTrack.height
                                const thumbH = modPosScrollThumb.height
                                if (trackH <= thumbH) return
                                const maxThumbY = trackH - thumbH
                                const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                                const ratio = clampedY / maxThumbY
                                const maxContentY = modPosFlick.contentHeight - modPosFlick.height
                                if (maxContentY > 0) modPosFlick.contentY = ratio * maxContentY
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 5
                            color: Qt.alpha(Theme.fg, modPosSbMa.containsMouse ? 0.08 : 0.04)
                            opacity: modPosScrollTrack.showThumb && (modPosFlick.contentHeight > modPosFlick.height) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        Rectangle {
                            id: modPosScrollThumb
                            width: modPosSbMa.containsMouse ? 8 : 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: width / 2
                            color: modPosSbMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.70)
                            opacity: modPosScrollTrack.showThumb && (modPosFlick.contentHeight > modPosFlick.height) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            y: {
                                const maxContentY = modPosFlick.contentHeight - modPosFlick.height
                                if (maxContentY <= 0) return 0
                                const ratio = Math.max(0, Math.min(modPosFlick.contentY / maxContentY, 1.0))
                                return ratio * (modPosScrollTrack.height - height)
                            }

                            height: {
                                if (modPosFlick.contentHeight <= 0) return 20
                                const ratio = modPosFlick.height / modPosFlick.contentHeight
                                return Math.max(30, Math.min(modPosScrollTrack.height * ratio, modPosScrollTrack.height - 10))
                            }
                        }
                    }

               }

// --- 5. BSPWM LAYOUT (GAPS & BORDER) PANEL ---
                Item {
                    id: bspwmGapsPanel
                    anchors.fill: parent
                    visible: root.activeTab === "layout"

                    Flickable {
                        id: bspwmGapsFlick
                        anchors.fill: parent
                        anchors.margins: 14
                        contentHeight: bspwmGapsCol.height + 28
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: bspwmGapsCol
                            width: bspwmGapsFlick.width - 24
                            spacing: 16

                            // Card 1: BSPWM Window Gap
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "BSPWM Window Gap"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust gap spacing between tiled windows in pixels"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Item {
                                            id: gapTrack
                                            width: parent.width - 45 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(40, (root.bspwmData ? root.bspwmData.gap : 8))) / 40)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(40, (root.bspwmData ? root.bspwmData.gap : 8))) / 40)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(gapTrack.width, mouseX))
                                                    const pct = clampedX / gapTrack.width
                                                    root.setBspwmGap(pct * 40)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => root.setBspwmGap((root.bspwmData ? root.bspwmData.gap : 8) + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: (root.bspwmData ? root.bspwmData.gap : 8) + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 32; height: 32; radius: 16
                                            color: resetGapMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14
                                            }

                                            MouseArea {
                                                id: resetGapMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.setBspwmGap(8)
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 2: BSPWM Window Border Width
                            Rectangle {
                                width: parent.width
                                height: 104
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "BSPWM Window Border Width"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust border thickness around windows in pixels"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Item {
                                            id: borderTrack
                                            width: parent.width - 45 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(10, (root.bspwmData ? root.bspwmData.border : 2))) / 10)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(10, (root.bspwmData ? root.bspwmData.border : 2))) / 10)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(borderTrack.width, mouseX))
                                                    const pct = clampedX / borderTrack.width
                                                    root.setBspwmBorder(pct * 10)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => root.setBspwmBorder((root.bspwmData ? root.bspwmData.border : 2) + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: (root.bspwmData ? root.bspwmData.border : 2) + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 32; height: 32; radius: 16
                                            color: resetBorderMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14
                                            }

                                            MouseArea {
                                                id: resetBorderMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.setBspwmBorder(2)
                                            }
                                        }
                                    }
                                }
                            }

                            // Card 3: Picom Window Corner Radius
                            Rectangle {
                                width: parent.width
                                height: 145
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 10

                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            text: "Picom Window Corner Radius"
                                            color: Theme.fg
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Adjust rounded corner radius of application windows in pixels"
                                            color: Qt.alpha(Theme.fg, 0.5)
                                            font.pixelSize: 12
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Item {
                                            id: cornerTrack
                                            width: parent.width - 45 - 32 - 28
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Qt.alpha(Theme.fg, 0.15)

                                                Rectangle {
                                                    width: parent.width * (Math.max(0, Math.min(30, (root.bspwmData ? (root.bspwmData.corner_radius !== undefined ? root.bspwmData.corner_radius : 12) : 12))) / 30)
                                                    height: parent.height
                                                    radius: 3
                                                    color: Theme.accent
                                                }

                                                Rectangle {
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (Math.max(0, Math.min(30, (root.bspwmData ? (root.bspwmData.corner_radius !== undefined ? root.bspwmData.corner_radius : 12) : 12))) / 30)) - width / 2))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.accent
                                                    border.width: 2
                                                    border.color: Theme.bg
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                function updateVal(mouseX) {
                                                    const clampedX = Math.max(0, Math.min(cornerTrack.width, mouseX))
                                                    const pct = clampedX / cornerTrack.width
                                                    root.setPicomCornerRadiusUI(pct * 30)
                                                }

                                                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                                                onClicked: mouse => updateVal(mouse.x)
                                                onWheel: wheel => root.setPicomCornerRadiusUI((root.bspwmData && root.bspwmData.corner_radius !== undefined ? root.bspwmData.corner_radius : 12) + (wheel.angleDelta.y > 0 ? 1 : -1))
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 45
                                            horizontalAlignment: Text.AlignRight
                                            text: (root.bspwmData && root.bspwmData.corner_radius !== undefined ? root.bspwmData.corner_radius : 12) + " px"
                                            color: Theme.accent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 32; height: 32; radius: 16
                                            color: resetCornerMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14
                                            }

                                            MouseArea {
                                                id: resetCornerMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.setPicomCornerRadiusUI(12)
                                            }
                                        }
                                    }

                                    // Apply Button Section
                                    Item {
                                        width: parent.width
                                        height: 30

                                        Rectangle {
                                            width: 90
                                            height: 28
                                            radius: 6
                                            color: applyPicomBtnMa.containsMouse ? Qt.alpha(Theme.accent, 0.85) : Theme.accent
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "󰄬"
                                                    color: Theme.bg
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "Apply"
                                                    color: Theme.bg
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                }
                                            }

                                            MouseArea {
                                                id: applyPicomBtnMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.applyPicomCornerRadius()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
// --- 6. KEYBINDINGS PANEL ---
                Item {
                    id: keybindingsPanel
                    anchors.fill: parent
                    visible: root.activeTab === "keybindings"

                    property string searchText: ""
                    property bool modalOpen: false
                    property bool isEditing: false
                    property string editOldHotkey: ""
                    property bool isRecordingHotkey: false
                    property bool appPickerOpen: false
                    property string appSearchText: ""
                    property var appPickerList: ({ "running": [], "installed": [] })

                    Process {
                        id: getAppsProc
                        command: ["python3", Sys.scriptPath("get_apps.py")]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                try {
                                    keybindingsPanel.appPickerList = JSON.parse(text)
                                } catch (e) {
                                    keybindingsPanel.appPickerList = { "running": [], "installed": [] }
                                }
                            }
                        }
                    }

                    function loadApps() {
                        getAppsProc.running = false
                        getAppsProc.running = true
                    }

                    function formatHotkeyEvent(event) {
                        let mods = []
                        if (event.modifiers & Qt.MetaModifier) mods.push("super")
                        if (event.modifiers & Qt.ControlModifier) mods.push("ctrl")
                        if (event.modifiers & Qt.AltModifier) mods.push("alt")
                        if (event.modifiers & Qt.ShiftModifier) mods.push("shift")

                        let k = event.key
                        if (k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta) {
                            return mods.length > 0 ? mods.join(" + ") : ""
                        }

                        let keyName = ""
                        if (k === Qt.Key_Space) keyName = "space"
                        else if (k === Qt.Key_Return) keyName = "Return"
                        else if (k === Qt.Key_Escape) keyName = "Escape"
                        else if (k === Qt.Key_Tab) keyName = "Tab"
                        else if (k === Qt.Key_BackSpace) keyName = "BackSpace"
                        else if (k === Qt.Key_Delete) keyName = "Delete"
                        else if (k === Qt.Key_Left) keyName = "Left"
                        else if (k === Qt.Key_Right) keyName = "Right"
                        else if (k === Qt.Key_Up) keyName = "Up"
                        else if (k === Qt.Key_Down) keyName = "Down"
                        else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32) keyName = event.text.toLowerCase()
                        else if (k >= Qt.Key_A && k <= Qt.Key_Z) keyName = String.fromCharCode(k + 32)
                        else if (k >= Qt.Key_0 && k <= Qt.Key_9) keyName = String.fromCharCode(k)
                        else keyName = event.text ? event.text.toLowerCase() : "key"

                        if (mods.length > 0) return mods.join(" + ") + " + " + keyName
                        return keyName
                    }

                    function formatSingleKey(event) {
                        let k = event.key
                        if (k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta) {
                            return ""
                        }

                        if (k === Qt.Key_Space) return "space"
                        if (k === Qt.Key_Return) return "Return"
                        if (k === Qt.Key_Escape) return "Escape"
                        if (k === Qt.Key_Tab) return "Tab"
                        if (k === Qt.Key_BackSpace) return "BackSpace"
                        if (k === Qt.Key_Delete) return "Delete"
                        if (k === Qt.Key_Left) return "Left"
                        if (k === Qt.Key_Right) return "Right"
                        if (k === Qt.Key_Up) return "Up"
                        if (k === Qt.Key_Down) return "Down"
                        if (k >= Qt.Key_F1 && k <= Qt.Key_F12) return "F" + (k - Qt.Key_F1 + 1)
                        if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32) return event.text.toLowerCase()
                        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k + 32)
                        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k)
                        return event.text ? event.text.toLowerCase() : ""
                    }

                    Process {
                        id: sxhkdActionProc
                        onExited: root.loadKeybindings()
                    }

                    function checkDuplicateHotkey(hotkeyStr) {
                        if (!hotkeyStr || !hotkeyStr.trim() || !root.keybindingsList) return null;
                        var targetNorm = hotkeyStr.trim().toLowerCase().split("+").map(function(s){ return s.trim(); }).join(" + ");
                        for (var i = 0; i < root.keybindingsList.length; i++) {
                            var item = root.keybindingsList[i];
                            if (!item || !item.hotkey) continue;
                            var existingNorm = item.hotkey.trim().toLowerCase().split("+").map(function(s){ return s.trim(); }).join(" + ");
                            if (keybindingsPanel.isEditing && keybindingsPanel.editOldHotkey) {
                                var oldNorm = keybindingsPanel.editOldHotkey.trim().toLowerCase().split("+").map(function(s){ return s.trim(); }).join(" + ");
                                if (existingNorm === oldNorm) continue;
                            }
                            if (targetNorm === existingNorm) {
                                return item;
                            }
                        }
                        return null;
                    }

                    function addKeybinding(hotkey, cmd, desc) {
                        if (!hotkey.trim() || !cmd.trim()) return
                        if (checkDuplicateHotkey(hotkey)) return
                        sxhkdActionProc.command = ["python3", Sys.scriptPath("sxhkd_editor.py"), "--add", "--hotkey", hotkey.trim(), "--cmd", cmd.trim(), "--desc", (desc || "").trim()]
                        sxhkdActionProc.running = false
                        sxhkdActionProc.running = true
                    }

                    function editKeybinding(oldH, newH, newC, desc) {
                        if (!oldH.trim() || !newH.trim() || !newC.trim()) return
                        if (checkDuplicateHotkey(newH)) return
                        sxhkdActionProc.command = ["python3", Sys.scriptPath("sxhkd_editor.py"), "--edit", "--old-hotkey", oldH.trim(), "--hotkey", newH.trim(), "--cmd", newC.trim(), "--desc", (desc || "").trim()]
                        sxhkdActionProc.running = false
                        sxhkdActionProc.running = true
                    }

                    function resetKeybindings() {
                        sxhkdActionProc.command = ["python3", Sys.scriptPath("sxhkd_editor.py"), "--reset"]
                        sxhkdActionProc.running = false
                        sxhkdActionProc.running = true
                    }

                    function deleteKeybinding(hotkey) {
                        if (!hotkey.trim()) return
                        sxhkdActionProc.command = ["python3", Sys.scriptPath("sxhkd_editor.py"), "--delete", "--hotkey", hotkey.trim()]
                        sxhkdActionProc.running = false
                        sxhkdActionProc.running = true
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14

                        // Header Row: Search Input + Add Button + Reset Button
                        Row {
                            width: parent.width
                            height: 38
                            spacing: 12

                            // Search Input Box
                            Rectangle {
                                width: parent.width - 152 - 38 - 12
                                height: parent.height
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: searchInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰍉"
                                        color: searchInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.4)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                    }

                                    TextInput {
                                        id: searchInput
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 24
                                        color: Theme.fg
                                        font.pixelSize: 13
                                        selectByMouse: true
                                        onTextChanged: keybindingsPanel.searchText = text.toLowerCase()

                                        Text {
                                            text: "Search keybindings..."
                                            color: Qt.alpha(Theme.fg, 0.35)
                                            font.pixelSize: 13
                                            visible: !searchInput.text
                                        }
                                    }
                                }
                            }

                            // + Add Keybinding Button
                            Rectangle {
                                width: 140
                                height: parent.height
                                radius: Sys.moduleRadius
                                color: addKbMa.containsMouse ? Qt.alpha(Theme.accent, 0.30) : Qt.alpha(Theme.accent, 0.18)
                                border.width: 1
                                border.color: Theme.accent

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: "󰐕"
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                    }

                                    Text {
                                        text: "Add Keybinding"
                                        color: Theme.accent
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    id: addKbMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        keybindingsPanel.isEditing = false
                                        keybindingsPanel.editOldHotkey = ""
                                        keybindingsPanel.isRecordingHotkey = false
                                        keybindingsPanel.appPickerOpen = false
                                        kbCmdInput.text = ""
                                        kbDescInput.text = ""
                                        modalBox.parseHotkey("")
                                        keybindingsPanel.loadApps()
                                        keybindingsPanel.modalOpen = true
                                    }
                                }
                            }

                            // Reset Button
                            Rectangle {
                                width: 38
                                height: parent.height
                                radius: Sys.moduleRadius
                                color: resetKbMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.15)

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰑐"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                }

                                MouseArea {
                                    id: resetKbMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: keybindingsPanel.resetKeybindings()
                                }
                            }
                        }

                        // List Container (Flickable)
                        Flickable {
                            id: kbFlick
                            width: parent.width
                            MouseArea { id: kbFlickHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                            height: parent.height - 52
                            contentHeight: kbCol.height + 20
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: kbCol
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: {
                                        if (!root.keybindingsList) return []
                                        if (!keybindingsPanel.searchText) return root.keybindingsList
                                        return root.keybindingsList.filter(item => {
                                            let h = (item.hotkey || "").toLowerCase()
                                            let c = (item.cmd || "").toLowerCase()
                                            let d = (item.desc || "").toLowerCase()
                                            return h.includes(keybindingsPanel.searchText) || c.includes(keybindingsPanel.searchText) || d.includes(keybindingsPanel.searchText)
                                        })
                                    }

                                    delegate: Rectangle {
                                        width: kbCol.width
                                        height: 58
                                        radius: Sys.moduleRadius
                                        color: Sys.customModuleBg
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.fg, 0.16)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 14
                                            spacing: 12

                                            // Hotkey Badge
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Math.max(130, hotkeyText.implicitWidth + 20)
                                                height: 28
                                                radius: 6
                                                color: Qt.alpha(Theme.accent, 0.14)
                                                border.width: 1
                                                border.color: Qt.alpha(Theme.accent, 0.3)

                                                Text {
                                                    id: hotkeyText
                                                    anchors.centerIn: parent
                                                    text: modelData.hotkey || ""
                                                    color: Theme.accent
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                }
                                            }

                                            // Description + Command Text Column
                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - Math.max(130, hotkeyText.implicitWidth + 20) - 80 - 24
                                                spacing: 2

                                                Text {
                                                    width: parent.width
                                                    text: modelData.desc || modelData.cmd || ""
                                                    color: Theme.fg
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    font.family: Theme.fontFamily
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: modelData.cmd || ""
                                                    color: Qt.alpha(Theme.fg, 0.55)
                                                    font.pixelSize: 10
                                                    font.family: "Monospace"
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            // Action Buttons (Edit & Remove)
                                            Row {
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 8

                                                // Edit Button
                                                Rectangle {
                                                    width: 32; height: 32; radius: 16
                                                    color: editMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.06)
                                                    border.width: 1
                                                    border.color: Qt.alpha(Theme.fg, 0.12)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰏫"
                                                        color: Theme.accent
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 13
                                                    }

                                                    MouseArea {
                                                        id: editMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            keybindingsPanel.isEditing = true
                                                            keybindingsPanel.editOldHotkey = modelData.hotkey
                                                            keybindingsPanel.isRecordingHotkey = false
                                                            keybindingsPanel.appPickerOpen = false
                                                            kbCmdInput.text = modelData.cmd || ""
                                                            kbDescInput.text = modelData.desc || ""
                                                            modalBox.parseHotkey(modelData.hotkey)
                                                            keybindingsPanel.loadApps()
                                                            keybindingsPanel.modalOpen = true
                                                        }
                                                    }
                                                }

                                                // Remove Button
                                                Rectangle {
                                                    width: 32; height: 32; radius: 16
                                                    color: delMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : Qt.alpha(Theme.fg, 0.06)
                                                    border.width: 1
                                                    border.color: Qt.alpha(Theme.fg, 0.12)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰆴"
                                                        color: delMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.6)
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 13
                                                    }

                                                    MouseArea {
                                                        id: delMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: keybindingsPanel.deleteKeybinding(modelData.hotkey)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    
                        // Scrollbar for Keybindings Panel
                        Item {
                            id: kbScrollTrack
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 4
                            width: 10
                            z: 100

                            readonly property bool isScrolling: kbFlick.movingVertically || kbFlick.moving || kbFlick.flicking || kbFlick.dragging
                            readonly property bool showThumb: isScrolling || kbSbMa.containsMouse || kbSbMa.pressed || kbFlickHover.containsMouse


                            MouseArea {
                                id: kbSbMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.SizeVerCursor
                                onPressed: (mouse) => updatePos(mouse.y)
                                onPositionChanged: (mouse) => { if (pressed) updatePos(mouse.y) }

                                function updatePos(mouseY) {
                                    const trackH = kbScrollTrack.height
                                    const thumbH = kbScrollThumb.height
                                    if (trackH <= thumbH) return
                                    const maxThumbY = trackH - thumbH
                                    const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                                    const ratio = clampedY / maxThumbY
                                    const maxContentY = kbFlick.contentHeight - kbFlick.height
                                    if (maxContentY > 0) kbFlick.contentY = ratio * maxContentY
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: Qt.alpha(Theme.fg, kbSbMa.containsMouse ? 0.08 : 0.04)
                                opacity: kbScrollTrack.showThumb && (kbFlick.contentHeight > kbFlick.height) ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }

                            Rectangle {
                                id: kbScrollThumb
                                width: kbSbMa.containsMouse ? 8 : 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                radius: width / 2
                                color: kbSbMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.70)
                                opacity: kbScrollTrack.showThumb && (kbFlick.contentHeight > kbFlick.height) ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                y: {
                                    const maxContentY = kbFlick.contentHeight - kbFlick.height
                                    if (maxContentY <= 0) return 0
                                    const ratio = Math.max(0, Math.min(kbFlick.contentY / maxContentY, 1.0))
                                    return ratio * (kbScrollTrack.height - height)
                                }

                                height: {
                                    if (kbFlick.contentHeight <= 0) return 20
                                    const ratio = kbFlick.height / kbFlick.contentHeight
                                    return Math.max(30, Math.min(kbScrollTrack.height * ratio, kbScrollTrack.height - 10))
                                }
                            }
                        }

// Modal Popup Overlay for Add / Edit Keybinding
                    Rectangle {
                        anchors.fill: parent
                        visible: keybindingsPanel.modalOpen
                        color: Qt.alpha("#000000", 0.65)
                        z: 999

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                keybindingsPanel.isRecordingHotkey = false
                                keybindingsPanel.appPickerOpen = false
                                keybindingsPanel.modalOpen = false
                            }
                        }

                        Rectangle {
                            id: modalBox
                            property bool modSuper: false
                            property bool modCtrl: false
                            property bool modAlt: false
                            property bool modShift: false

                            function updateFullHotkey() {
                                let mods = []
                                if (modSuper) mods.push("super")
                                if (modCtrl) mods.push("ctrl")
                                if (modAlt) mods.push("alt")
                                if (modShift) mods.push("shift")

                                let keyPart = typeof kbKeyInput !== "undefined" ? kbKeyInput.text.trim().toLowerCase() : ""
                                let full = ""
                                if (mods.length > 0 && keyPart.length > 0) {
                                    full = mods.join(" + ") + " + " + keyPart
                                } else if (mods.length > 0) {
                                    full = mods.join(" + ")
                                } else {
                                    full = keyPart
                                }

                                if (typeof kbHotkeyInput !== "undefined") {
                                    kbHotkeyInput.text = full
                                }
                                keybindingsPanel.checkDuplicateHotkey(full)
                            }

                            function parseHotkey(hotkeyStr) {
                                if (!hotkeyStr) {
                                    modSuper = false; modCtrl = false; modAlt = false; modShift = false;
                                    if (typeof kbKeyInput !== "undefined") kbKeyInput.text = "";
                                    updateFullHotkey();
                                    return;
                                }
                                let parts = hotkeyStr.split("+").map(s => s.trim().toLowerCase())
                                modSuper = parts.includes("super")
                                modCtrl = parts.includes("ctrl")
                                modAlt = parts.includes("alt")
                                modShift = parts.includes("shift")
                                
                                let keyParts = parts.filter(p => p !== "super" && p !== "ctrl" && p !== "alt" && p !== "shift")
                                if (typeof kbKeyInput !== "undefined") kbKeyInput.text = keyParts.join(" + ");
                                updateFullHotkey()
                            }

                            readonly property var duplicateItem: keybindingsPanel.checkDuplicateHotkey(kbHotkeyInput ? kbHotkeyInput.text : "")
                            readonly property bool isDuplicate: duplicateItem !== null

                            width: 480
                            height: keybindingsPanel.appPickerOpen ? 480 : (modalBox.isDuplicate ? 360 : 330)
                            anchors.centerIn: parent
                            radius: 12
                            color: Theme.bg
                            border.width: 1
                            border.color: modalBox.isDuplicate ? Theme.red : (keybindingsPanel.isRecordingHotkey ? Theme.accent : Qt.alpha(Theme.accent, 0.40))

                            Behavior on height { NumberAnimation { duration: 180 } }

                            // Key Press Recorder Listener Item
                            Item {
                                id: keyRecorderFocus
                                anchors.fill: parent
                                focus: keybindingsPanel.modalOpen && keybindingsPanel.isRecordingHotkey
                                
                                Keys.onPressed: (event) => {
                                    if (!keybindingsPanel.isRecordingHotkey) return
                                    let str = keybindingsPanel.formatHotkeyEvent(event)
                                    if (str !== "") {
                                        kbHotkeyInput.text = str
                                    }
                                    let k = event.key
                                    if (k === Qt.Key_Escape) {
                                        keybindingsPanel.isRecordingHotkey = false
                                        event.accepted = true
                                    } else if (k !== Qt.Key_Control && k !== Qt.Key_Shift && k !== Qt.Key_Alt && k !== Qt.Key_Meta) {
                                        keybindingsPanel.isRecordingHotkey = false
                                        event.accepted = true
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {}
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 12

                                Item {
                                    width: parent.width
                                    height: 24

                                    Text {
                                        text: keybindingsPanel.isEditing ? "Edit Keybinding" : "Add Keybinding"
                                        color: Theme.fg
                                        font.pixelSize: 16
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        width: 24; height: 24; radius: 12
                                        color: closeModalMa.containsMouse ? Qt.alpha(Theme.red, 0.2) : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            color: closeModalMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.5)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                        }

                                        MouseArea {
                                            id: closeModalMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                keybindingsPanel.isRecordingHotkey = false
                                                keybindingsPanel.appPickerOpen = false
                                                keybindingsPanel.modalOpen = false
                                            }
                                        }
                                    }
                                }

                                // Input 1: Modifier Selector Buttons + Key Input Box + Preview
                                Column {
                                    width: parent.width
                                    spacing: 6

                                    Item {
                                        width: parent.width
                                        height: 16

                                        Text {
                                            text: "Hotkey Modifiers & Key"
                                            color: Qt.alpha(Theme.fg, 0.6)
                                            font.pixelSize: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    // Row 1: Modifier Toggle Chips (Super, Ctrl, Alt, Shift)
                                    Row {
                                        spacing: 6

                                        // Super Toggle
                                        Rectangle {
                                            width: 62; height: 28; radius: 6
                                            color: modalBox.modSuper ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                            border.width: 1
                                            border.color: modalBox.modSuper ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Super"
                                                color: modalBox.modSuper ? Theme.accent : Theme.fg
                                                font.pixelSize: 11
                                                font.bold: modalBox.modSuper
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    modalBox.modSuper = !modalBox.modSuper
                                                    modalBox.updateFullHotkey()
                                                }
                                            }
                                        }

                                        // Ctrl Toggle
                                        Rectangle {
                                            width: 52; height: 28; radius: 6
                                            color: modalBox.modCtrl ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                            border.width: 1
                                            border.color: modalBox.modCtrl ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Ctrl"
                                                color: modalBox.modCtrl ? Theme.accent : Theme.fg
                                                font.pixelSize: 11
                                                font.bold: modalBox.modCtrl
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    modalBox.modCtrl = !modalBox.modCtrl
                                                    modalBox.updateFullHotkey()
                                                }
                                            }
                                        }

                                        // Alt Toggle
                                        Rectangle {
                                            width: 52; height: 28; radius: 6
                                            color: modalBox.modAlt ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                            border.width: 1
                                            border.color: modalBox.modAlt ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Alt"
                                                color: modalBox.modAlt ? Theme.accent : Theme.fg
                                                font.pixelSize: 11
                                                font.bold: modalBox.modAlt
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    modalBox.modAlt = !modalBox.modAlt
                                                    modalBox.updateFullHotkey()
                                                }
                                            }
                                        }

                                        // Shift Toggle
                                        Rectangle {
                                            width: 56; height: 28; radius: 6
                                            color: modalBox.modShift ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                            border.width: 1
                                            border.color: modalBox.modShift ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Shift"
                                                color: modalBox.modShift ? Theme.accent : Theme.fg
                                                font.pixelSize: 11
                                                font.bold: modalBox.modShift
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    modalBox.modShift = !modalBox.modShift
                                                    modalBox.updateFullHotkey()
                                                }
                                            }
                                        }
                                    }

                                    // Row 2: Key Input Box + Trash Clear Button
                                    Row {
                                        width: parent.width
                                        height: 34
                                        spacing: 8

                                        // Key Input Box
                                        Rectangle {
                                            width: parent.width - 38
                                            height: parent.height
                                            radius: 8
                                            color: Sys.customModuleBg
                                            border.width: 1
                                            border.color: modalBox.isDuplicate ? Theme.red : (kbKeyInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.15))

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 6

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "Key:"
                                                    color: Qt.alpha(Theme.fg, 0.5)
                                                    font.pixelSize: 12
                                                }

                                                TextInput {
                                                    id: kbKeyInput
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 45
                                                    color: modalBox.isDuplicate ? Theme.red : Theme.fg
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    selectByMouse: true
                                                    onTextChanged: modalBox.updateFullHotkey()

                                                    Keys.onPressed: (event) => {
                                                        let recordedKey = keybindingsPanel.formatSingleKey(event)
                                                        if (recordedKey !== "") {
                                                            kbKeyInput.text = recordedKey
                                                            event.accepted = true
                                                        }
                                                    }

                                                    Text {
                                                        text: "Press key (e.g. Return, space, Esc, Up...)"
                                                        color: Qt.alpha(Theme.fg, 0.35)
                                                        font.pixelSize: 12
                                                        visible: !kbKeyInput.text
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }

                                        // Trash / Reset Button
                                        Rectangle {
                                            width: 30; height: 34; radius: 7
                                            color: clearHotkeyMa.containsMouse ? Qt.alpha(Theme.red, 0.20) : Qt.alpha(Theme.fg, 0.08)
                                            border.width: 1
                                            border.color: clearHotkeyMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.15)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰆴"
                                                color: clearHotkeyMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.6)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                            }

                                            MouseArea {
                                                id: clearHotkeyMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    modalBox.modSuper = false
                                                    modalBox.modCtrl = false
                                                    modalBox.modAlt = false
                                                    modalBox.modShift = false
                                                    kbKeyInput.text = ""
                                                    modalBox.updateFullHotkey()
                                                }
                                            }
                                        }
                                    }

                                    // Full Generated Hotkey Preview & Hidden Actual Value Holder
                                    TextInput {
                                        id: kbHotkeyInput
                                        visible: false
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 24
                                        radius: 6
                                        color: modalBox.isDuplicate ? Qt.alpha(Theme.red, 0.12) : Qt.alpha(Theme.accent, 0.12)
                                        border.width: 1
                                        border.color: modalBox.isDuplicate ? Qt.alpha(Theme.red, 0.3) : Qt.alpha(Theme.accent, 0.3)
                                        visible: kbHotkeyInput.text.length > 0

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Text {
                                                text: "Hotkey Result:"
                                                color: Qt.alpha(Theme.fg, 0.65)
                                                font.pixelSize: 11
                                            }

                                            Text {
                                                text: kbHotkeyInput.text
                                                color: modalBox.isDuplicate ? Theme.red : Theme.accent
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                        }
                                    }

                                    // Duplicate Hotkey Warning Banner
                                    Rectangle {
                                        width: parent.width
                                        height: 28
                                        radius: 6
                                        color: Qt.alpha(Theme.red, 0.15)
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.red, 0.4)
                                        visible: modalBox.isDuplicate

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 6

                                            Text {
                                                text: "⚠️"
                                                font.pixelSize: 11
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Text {
                                                text: "Hotkey already bound to: " + (modalBox.duplicateItem ? ("\"" + (modalBox.duplicateItem.cmd || "") + "\"") : "")
                                                color: Theme.red
                                                font.pixelSize: 11
                                                font.bold: true
                                                anchors.verticalCenter: parent.verticalCenter
                                                elide: Text.ElideRight
                                                width: parent.width - 28
                                            }
                                        }
                                    }
                                }

                                // Input 2: Description (Optional)
                                Column {
                                    width: parent.width
                                    spacing: 4

                                    Item {
                                        width: parent.width
                                        height: 20

                                        Text {
                                            text: "Description (Optional)"
                                            color: Qt.alpha(Theme.fg, 0.6)
                                            font.pixelSize: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 34
                                        radius: 8
                                        color: Sys.customModuleBg
                                        border.width: 1
                                        border.color: kbDescInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                                        TextInput {
                                            id: kbDescInput
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            verticalAlignment: TextInput.AlignVCenter
                                            color: Theme.fg
                                            font.pixelSize: 12
                                            selectByMouse: true

                                            Text {
                                                text: "Description (e.g. Close Active Window)..."
                                                color: Qt.alpha(Theme.fg, 0.35)
                                                font.pixelSize: 12
                                                visible: !kbDescInput.text
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }

                                // Input 3: Command / Application (Auto Search & Picker)
                                Column {
                                    width: parent.width
                                    spacing: 4

                                    Item {
                                        width: parent.width
                                        height: 22

                                        Text {
                                            text: "Command / Application"
                                            color: Qt.alpha(Theme.fg, 0.6)
                                            font.pixelSize: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 36
                                        radius: 8
                                        color: Sys.customModuleBg
                                        border.width: 1
                                        border.color: kbCmdInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                                        TextInput {
                                            id: kbCmdInput
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            verticalAlignment: TextInput.AlignVCenter
                                            color: Theme.fg
                                            font.pixelSize: 12
                                            selectByMouse: true
                                            onActiveFocusChanged: {
                                                if (activeFocus) {
                                                    keybindingsPanel.appPickerOpen = true
                                                    keybindingsPanel.appSearchText = text.trim().toLowerCase()
                                                    keybindingsPanel.loadApps()
                                                }
                                            }
                                            onTextChanged: {
                                                keybindingsPanel.appSearchText = text.trim().toLowerCase()
                                                if (activeFocus) keybindingsPanel.appPickerOpen = true
                                            }

                                            Text {
                                                text: "Type application name or custom command (e.g. thorium-browser)..."
                                                color: Qt.alpha(Theme.fg, 0.35)
                                                font.pixelSize: 12
                                                visible: !kbCmdInput.text
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }

                                // Installed App Picker Dropdown Container
                                Rectangle {
                                    width: parent.width
                                    height: 180
                                    visible: keybindingsPanel.appPickerOpen
                                    radius: 8
                                    color: Sys.customModuleBg
                                    border.width: 1
                                    border.color: Qt.alpha(Theme.accent, 0.3)
                                    clip: true

                                    Flickable {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        contentHeight: appPickerCol.height
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        Column {
                                            id: appPickerCol
                                            width: parent.width - 6
                                            spacing: 4

                                            Repeater {
                                                model: {
                                                    let apps = keybindingsPanel.appPickerList.installed || []
                                                    if (!keybindingsPanel.appSearchText) return apps
                                                    return apps.filter(item => {
                                                        let n = (item.name || "").toLowerCase()
                                                        let c = (item.cmd || "").toLowerCase()
                                                        return n.includes(keybindingsPanel.appSearchText) || c.includes(keybindingsPanel.appSearchText)
                                                    })
                                                }
                                                delegate: Rectangle {
                                                    width: appPickerCol.width
                                                    height: 32
                                                    radius: 6
                                                    color: instAppMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.04)
                                                    border.width: 1
                                                    border.color: instAppMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.08)

                                                    Row {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        spacing: 8

                                                        Text {
                                                            text: "󰀻"
                                                            color: Theme.accent
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 12
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }

                                                        Text {
                                                            text: modelData.name || ""
                                                            color: Theme.fg
                                                            font.pixelSize: 12
                                                            font.bold: true
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            elide: Text.ElideRight
                                                            width: parent.width - 160
                                                        }

                                                        Text {
                                                            text: modelData.cmd || ""
                                                            color: Qt.alpha(Theme.fg, 0.5)
                                                            font.pixelSize: 11
                                                            font.family: "Monospace"
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            anchors.right: parent.right
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: instAppMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            kbCmdInput.text = modelData.cmd || ""
                                                            keybindingsPanel.appPickerOpen = false
                                                            modalBox.forceActiveFocus()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Modal Action Buttons
                                Row {
                                    anchors.right: parent.right
                                    spacing: 10

                                    // Cancel
                                    Rectangle {
                                        width: 80; height: 32; radius: 6
                                        color: cancelMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            color: Theme.fg
                                            font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: cancelMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                keybindingsPanel.isRecordingHotkey = false
                                                keybindingsPanel.appPickerOpen = false
                                                keybindingsPanel.modalOpen = false
                                            }
                                        }
                                    }

                                    // Save / Add
                                    Rectangle {
                                        width: 90; height: 32; radius: 6
                                        color: modalBox.isDuplicate ? Qt.alpha(Theme.fg, 0.1) : (saveMa.containsMouse ? Qt.alpha(Theme.accent, 0.85) : Theme.accent)
                                        opacity: modalBox.isDuplicate ? 0.5 : 1.0

                                        Text {
                                            anchors.centerIn: parent
                                            text: keybindingsPanel.isEditing ? "Save" : "Add"
                                            color: modalBox.isDuplicate ? Qt.alpha(Theme.fg, 0.4) : Theme.bg
                                            font.pixelSize: 12
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: saveMa
                                            anchors.fill: parent
                                            hoverEnabled: !modalBox.isDuplicate
                                            cursorShape: modalBox.isDuplicate ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                                            enabled: !modalBox.isDuplicate && kbHotkeyInput.text.trim().length > 0 && kbCmdInput.text.trim().length > 0
                                            onClicked: {
                                                if (keybindingsPanel.isEditing) {
                                                    keybindingsPanel.editKeybinding(keybindingsPanel.editOldHotkey, kbHotkeyInput.text, kbCmdInput.text, kbDescInput.text)
                                                } else {
                                                    keybindingsPanel.addKeybinding(kbHotkeyInput.text, kbCmdInput.text, kbDescInput.text)
                                                }
                                                keybindingsPanel.isRecordingHotkey = false
                                                keybindingsPanel.appPickerOpen = false
                                                keybindingsPanel.modalOpen = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

// --- 7. WINDOW RULES PANEL ---
                Item {
                    id: windowRulesPanel
                    anchors.fill: parent
                    visible: root.activeTab === "window_rules"

                    property string searchText: ""
                    property bool modalOpen: false
                    property bool isEditing: false
                    property string editOldClass: ""

                    Process {
                        id: ruleActionProc
                        onExited: root.loadBspwmInfo()
                    }

                    function addRule(appClass, opts) {
                        if (!appClass.trim()) return
                        ruleActionProc.command = ["python3", Sys.scriptPath("bspwm_editor.py"), "--add-rule", "--class", appClass.trim(), "--opts", opts.trim()]
                        ruleActionProc.running = false
                        ruleActionProc.running = true
                    }

                    function editRule(oldC, newC, newO) {
                        if (!oldC.trim() || !newC.trim()) return
                        ruleActionProc.command = ["python3", Sys.scriptPath("bspwm_editor.py"), "--edit-rule", "--old-class", oldC.trim(), "--class", newC.trim(), "--opts", newO.trim()]
                        ruleActionProc.running = false
                        ruleActionProc.running = true
                    }

                    function deleteRule(appClass) {
                        if (!appClass.trim()) return
                        ruleActionProc.command = ["python3", Sys.scriptPath("bspwm_editor.py"), "--delete-rule", "--class", appClass.trim()]
                        ruleActionProc.running = false
                        ruleActionProc.running = true
                    }

                    function resetRules() {
                        ruleActionProc.command = ["python3", Sys.scriptPath("bspwm_editor.py"), "--reset-rules"]
                        ruleActionProc.running = false
                        ruleActionProc.running = true
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14

                        // Header Row: Search Input + Add Button + Reset Button
                        Row {
                            width: parent.width
                            height: 38
                            spacing: 12

                            // Search Input Box
                            Rectangle {
                                width: parent.width - 152 - 38 - 12
                                height: parent.height
                                radius: Sys.moduleRadius
                                color: Sys.customModuleBg
                                border.width: 1
                                border.color: ruleSearchInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰍉"
                                        color: ruleSearchInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.4)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                    }

                                    TextInput {
                                        id: ruleSearchInput
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 24
                                        color: Theme.fg
                                        font.pixelSize: 13
                                        selectByMouse: true
                                        onTextChanged: windowRulesPanel.searchText = text.toLowerCase()

                                        Text {
                                            text: "Search window rules..."
                                            color: Qt.alpha(Theme.fg, 0.35)
                                            font.pixelSize: 13
                                            visible: !ruleSearchInput.text
                                        }
                                    }
                                }
                            }

                            // + Add Window Rule Button
                            Rectangle {
                                width: 140
                                height: parent.height
                                radius: Sys.moduleRadius
                                color: addRuleMa.containsMouse ? Qt.alpha(Theme.accent, 0.30) : Qt.alpha(Theme.accent, 0.18)
                                border.width: 1
                                border.color: Theme.accent

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: "󰐕"
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                    }

                                    Text {
                                        text: "Add Window Rule"
                                        color: Theme.accent
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    id: addRuleMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        windowRulesPanel.isEditing = false
                                        windowRulesPanel.editOldClass = ""
                                        keybindingsPanel.loadApps()
                                        ruleModalBox.parseRule("", "")
                                        windowRulesPanel.modalOpen = true
                                    }
                                }
                            }

                            // Reset Button
                            Rectangle {
                                width: 38
                                height: parent.height
                                radius: Sys.moduleRadius
                                color: resetRulesMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.15)

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰑐"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                }

                                MouseArea {
                                    id: resetRulesMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: windowRulesPanel.resetRules()
                                }
                            }
                        }

                        // List Container (Flickable)
                        Flickable {
                            id: rulesFlick
                            width: parent.width
                            MouseArea { id: rulesFlickHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                            height: parent.height - 52
                            contentHeight: rulesCol.height + 20
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: rulesCol
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: {
                                        if (!root.bspwmData || !root.bspwmData.rules) return []
                                        if (!windowRulesPanel.searchText) return root.bspwmData.rules
                                        return root.bspwmData.rules.filter(item => {
                                            let c = (item.class || "").toLowerCase()
                                            let o = (item.opts || "").toLowerCase()
                                            return c.includes(windowRulesPanel.searchText) || o.includes(windowRulesPanel.searchText)
                                        })
                                    }

                                    delegate: Rectangle {
                                        width: rulesCol.width
                                        height: 52
                                        radius: Sys.moduleRadius
                                        color: Sys.customModuleBg
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.fg, 0.16)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 14
                                            spacing: 12

                                            // App Class Badge
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Math.max(120, ruleClassText.implicitWidth + 20)
                                                height: 28
                                                radius: 6
                                                color: Qt.alpha(Theme.accent, 0.14)
                                                border.width: 1
                                                border.color: Qt.alpha(Theme.accent, 0.3)

                                                Text {
                                                    id: ruleClassText
                                                    anchors.centerIn: parent
                                                    text: modelData.class || ""
                                                    color: Theme.accent
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                }
                                            }

                                            // Options Text
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - Math.max(120, ruleClassText.implicitWidth + 20) - 80 - 24
                                                text: modelData.opts || "default"
                                                color: Qt.alpha(Theme.fg, 0.85)
                                                font.pixelSize: 12
                                                font.family: "Monospace"
                                                elide: Text.ElideRight
                                            }

                                            // Action Buttons (Edit & Remove)
                                            Row {
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 8

                                                // Edit Button
                                                Rectangle {
                                                    width: 32; height: 32; radius: 16
                                                    color: editRuleMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.06)
                                                    border.width: 1
                                                    border.color: Qt.alpha(Theme.fg, 0.12)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰏫"
                                                        color: Theme.accent
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 13
                                                    }

                                                    MouseArea {
                                                        id: editRuleMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            windowRulesPanel.isEditing = true
                                                            windowRulesPanel.editOldClass = modelData.class
                                                            keybindingsPanel.loadApps()
                                                            ruleModalBox.parseRule(modelData.class, modelData.opts)
                                                            windowRulesPanel.modalOpen = true
                                                        }
                                                    }
                                                }

                                                // Remove Button
                                                Rectangle {
                                                    width: 32; height: 32; radius: 16
                                                    color: delRuleMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : Qt.alpha(Theme.fg, 0.06)
                                                    border.width: 1
                                                    border.color: Qt.alpha(Theme.fg, 0.12)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰆴"
                                                        color: delRuleMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.6)
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 13
                                                    }

                                                    MouseArea {
                                                        id: delRuleMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: windowRulesPanel.deleteRule(modelData.class)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    
                        // Scrollbar for Window Rules Panel
                        Item {
                            id: rulesScrollTrack
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 4
                            width: 10
                            z: 100

                            readonly property bool isScrolling: rulesFlick.movingVertically || rulesFlick.moving || rulesFlick.flicking || rulesFlick.dragging
                            readonly property bool showThumb: isScrolling || rulesSbMa.containsMouse || rulesSbMa.pressed || rulesFlickHover.containsMouse


                            MouseArea {
                                id: rulesSbMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.SizeVerCursor
                                onPressed: (mouse) => updatePos(mouse.y)
                                onPositionChanged: (mouse) => { if (pressed) updatePos(mouse.y) }

                                function updatePos(mouseY) {
                                    const trackH = rulesScrollTrack.height
                                    const thumbH = rulesScrollThumb.height
                                    if (trackH <= thumbH) return
                                    const maxThumbY = trackH - thumbH
                                    const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                                    const ratio = clampedY / maxThumbY
                                    const maxContentY = rulesFlick.contentHeight - rulesFlick.height
                                    if (maxContentY > 0) rulesFlick.contentY = ratio * maxContentY
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: Qt.alpha(Theme.fg, rulesSbMa.containsMouse ? 0.08 : 0.04)
                                opacity: rulesScrollTrack.showThumb && (rulesFlick.contentHeight > rulesFlick.height) ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }

                            Rectangle {
                                id: rulesScrollThumb
                                width: rulesSbMa.containsMouse ? 8 : 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                radius: width / 2
                                color: rulesSbMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.70)
                                opacity: rulesScrollTrack.showThumb && (rulesFlick.contentHeight > rulesFlick.height) ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                y: {
                                    const maxContentY = rulesFlick.contentHeight - rulesFlick.height
                                    if (maxContentY <= 0) return 0
                                    const ratio = Math.max(0, Math.min(rulesFlick.contentY / maxContentY, 1.0))
                                    return ratio * (rulesScrollTrack.height - height)
                                }

                                height: {
                                    if (rulesFlick.contentHeight <= 0) return 20
                                    const ratio = rulesFlick.height / rulesFlick.contentHeight
                                    return Math.max(30, Math.min(rulesScrollTrack.height * ratio, rulesScrollTrack.height - 10))
                                }
                            }
                        }

// Modal Popup Overlay for Add / Edit Window Rule
                    Rectangle {
                        id: ruleModalOverlay
                        anchors.fill: parent
                        visible: windowRulesPanel.modalOpen
                        color: Qt.alpha("#000000", 0.65)
                        z: 999

                        MouseArea {
                            anchors.fill: parent
                            onClicked: windowRulesPanel.modalOpen = false
                        }

                        Rectangle {
                            id: ruleModalBox
                            width: 520
                            height: Math.min(parent.height - 40, 560)
                            anchors.centerIn: parent
                            radius: 12
                            color: Theme.bg
                            border.width: 1
                            border.color: Qt.alpha(Theme.accent, 0.40)

                            property bool ruleAppPickerOpen: false
                            property string ruleAppSearchText: ""

                            property string selState: "default"
                            property string selLayer: "default"
                            property string selFollow: "default"
                            property string selFocus: "default"
                            property string selDesktop: "default"
                            property string selManage: "default"
                            property string selSticky: "default"
                            property string selPrivate: "default"
                            property string selLocked: "default"
                            property string selMarked: "default"
                            property string selBorder: "default"
                            property string selCenter: "default"

                            function getFlag(prop) {
                                if (prop === "selManage") return selManage
                                if (prop === "selSticky") return selSticky
                                if (prop === "selPrivate") return selPrivate
                                if (prop === "selLocked") return selLocked
                                if (prop === "selMarked") return selMarked
                                if (prop === "selBorder") return selBorder
                                if (prop === "selCenter") return selCenter
                                return "default"
                            }

                            function setFlag(prop, val) {
                                if (prop === "selManage") selManage = val
                                else if (prop === "selSticky") selSticky = val
                                else if (prop === "selPrivate") selPrivate = val
                                else if (prop === "selLocked") selLocked = val
                                else if (prop === "selMarked") selMarked = val
                                else if (prop === "selBorder") selBorder = val
                                else if (prop === "selCenter") selCenter = val
                                updateFullOpts()
                            }

                            function updateFullOpts() {
                                let parts = []
                                if (selState !== "default") parts.push("state=" + selState)
                                if (selLayer !== "default") parts.push("layer=" + selLayer)
                                if (selFollow !== "default") parts.push("follow=" + selFollow)
                                if (selFocus !== "default") parts.push("focus=" + selFocus)
                                if (selDesktop !== "default") parts.push("desktop='" + selDesktop + "'")
                                if (selManage !== "default") parts.push("manage=" + selManage)
                                if (selSticky !== "default") parts.push("sticky=" + selSticky)
                                if (selPrivate !== "default") parts.push("private=" + selPrivate)
                                if (selLocked !== "default") parts.push("locked=" + selLocked)
                                if (selMarked !== "default") parts.push("marked=" + selMarked)
                                if (selBorder !== "default") parts.push("border=" + selBorder)
                                if (selCenter !== "default") parts.push("center=" + selCenter)
                                
                                return parts.join(" ")
                            }

                            function parseRule(rawClass, rawOpts) {
                                ruleAppPickerOpen = false
                                let parts = rawClass.split(":")
                                if (parts.length >= 3) {
                                    ruleClassInput.text = parts[0].trim()
                                    let t = parts.slice(2).join(":").trim()
                                    if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
                                        t = t.substring(1, t.length - 1)
                                    }
                                    ruleTitleInput.text = (t === "*") ? "" : t
                                } else {
                                    ruleClassInput.text = parts[0].trim()
                                    ruleTitleInput.text = ""
                                }

                                let opts = rawOpts || ""
                                
                                // State
                                let mState = opts.match(/\bstate=(floating|tiled|pseudo_tiled|fullscreen)\b/)
                                selState = mState ? mState[1] : "default"

                                // Layer
                                let mLayer = opts.match(/\blayer=(above|below|normal)\b/)
                                selLayer = mLayer ? mLayer[1] : "default"

                                // Follow
                                let mFollow = opts.match(/\bfollow=(on|off)\b/)
                                selFollow = mFollow ? mFollow[1] : "default"

                                // Focus
                                let mFocus = opts.match(/\bfocus=(on|off)\b/)
                                selFocus = mFocus ? mFocus[1] : "default"

                                // Desktop
                                let mDesk = opts.match(/desktop=['"]?(\^?\w+)['"]?/)
                                selDesktop = mDesk ? mDesk[1] : "default"

                                // Manage
                                let mManage = opts.match(/\bmanage=(on|off)\b/)
                                selManage = mManage ? mManage[1] : "default"

                                // Sticky
                                let mSticky = opts.match(/\bsticky=(on|off)\b/)
                                selSticky = mSticky ? mSticky[1] : "default"

                                // Private
                                let mPrivate = opts.match(/\bprivate=(on|off)\b/)
                                selPrivate = mPrivate ? mPrivate[1] : "default"

                                // Locked
                                let mLocked = opts.match(/\blocked=(on|off)\b/)
                                selLocked = mLocked ? mLocked[1] : "default"

                                // Marked
                                let mMarked = opts.match(/\bmarked=(on|off)\b/)
                                selMarked = mMarked ? mMarked[1] : "default"

                                // Border
                                let mBorder = opts.match(/\bborder=(on|off)\b/)
                                selBorder = mBorder ? mBorder[1] : "default"

                                // Center
                                let mCenter = opts.match(/\bcenter=(on|off)\b/)
                                selCenter = mCenter ? mCenter[1] : "default"
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {}
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 12

                                // Header
                                Item {
                                    width: parent.width
                                    height: 24

                                    Text {
                                        text: windowRulesPanel.isEditing ? "Edit Window Rule" : "Add Window Rule"
                                        color: Theme.fg
                                        font.pixelSize: 15
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        width: 24; height: 24; radius: 12
                                        color: closeRuleModalMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.06)
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: closeRuleModalMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: windowRulesPanel.modalOpen = false
                                        }
                                    }
                                }

                                // Scrollable Modal Body
                                Flickable {
                                    width: parent.width
                                    height: parent.height - 24 - 36 - 24
                                    contentHeight: modalBodyCol.height + 10
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds

                                    Column {
                                        id: modalBodyCol
                                        width: parent.width - 4
                                        spacing: 12

                                        // Row 1: App Class & Title
                                        Row {
                                            width: parent.width
                                            spacing: 10

                                            // App Class (with installed app search dropdown)
                                            Column {
                                                width: (parent.width - 10) / 2
                                                spacing: 4

                                                Text {
                                                    text: "App Class (Installed Apps Picker)"
                                                    color: Qt.alpha(Theme.fg, 0.6)
                                                    font.pixelSize: 11
                                                }

                                                Rectangle {
                                                    width: parent.width
                                                    height: 34
                                                    radius: 8
                                                    color: Sys.customModuleBg
                                                    border.width: 1
                                                    border.color: ruleClassInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                                                    TextInput {
                                                        id: ruleClassInput
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        color: Theme.fg
                                                        font.pixelSize: 12
                                                        selectByMouse: true
                                                        onActiveFocusChanged: {
                                                            if (activeFocus) {
                                                                ruleModalBox.ruleAppPickerOpen = true
                                                                ruleModalBox.ruleAppSearchText = text.trim().toLowerCase()
                                                                keybindingsPanel.loadApps()
                                                            }
                                                        }
                                                        onTextChanged: {
                                                            ruleModalBox.ruleAppSearchText = text.trim().toLowerCase()
                                                            if (activeFocus) ruleModalBox.ruleAppPickerOpen = true
                                                        }

                                                        Text {
                                                            text: "e.g. Thunar, firefox, Thorium..."
                                                            color: Qt.alpha(Theme.fg, 0.35)
                                                            font.pixelSize: 12
                                                            visible: !ruleClassInput.text
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                }
                                            }

                                            // Window Title (Optional)
                                            Column {
                                                width: (parent.width - 10) / 2
                                                spacing: 4

                                                Text {
                                                    text: "Window Title (Optional / Can be empty)"
                                                    color: Qt.alpha(Theme.fg, 0.6)
                                                    font.pixelSize: 11
                                                }

                                                Rectangle {
                                                    width: parent.width
                                                    height: 34
                                                    radius: 8
                                                    color: Sys.customModuleBg
                                                    border.width: 1
                                                    border.color: ruleTitleInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                                                    TextInput {
                                                        id: ruleTitleInput
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        color: Theme.fg
                                                        font.pixelSize: 12
                                                        selectByMouse: true

                                                        Text {
                                                            text: "e.g. Picture-in-Picture, Calculator..."
                                                            color: Qt.alpha(Theme.fg, 0.35)
                                                            font.pixelSize: 12
                                                            visible: !ruleTitleInput.text
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Installed App Dropdown for App Class
                                        Rectangle {
                                            width: parent.width
                                            height: 140
                                            visible: ruleModalBox.ruleAppPickerOpen
                                            radius: 8
                                            color: Sys.customModuleBg
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.accent, 0.3)
                                            clip: true

                                            Flickable {
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                contentHeight: ruleAppPickerCol.height
                                                clip: true

                                                Column {
                                                    id: ruleAppPickerCol
                                                    width: parent.width - 4
                                                    spacing: 3

                                                    Repeater {
                                                        model: {
                                                            let apps = keybindingsPanel.appPickerList.installed || []
                                                            if (!ruleModalBox.ruleAppSearchText) return apps
                                                            return apps.filter(item => {
                                                                let n = (item.name || "").toLowerCase()
                                                                let c = (item.cmd || "").toLowerCase()
                                                                return n.includes(ruleModalBox.ruleAppSearchText) || c.includes(ruleModalBox.ruleAppSearchText)
                                                            })
                                                        }
                                                        delegate: Rectangle {
                                                            width: ruleAppPickerCol.width
                                                            height: 28
                                                            radius: 5
                                                            color: ruleInstAppMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.04)

                                                            Row {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: 8
                                                                anchors.rightMargin: 8
                                                                spacing: 6

                                                                Text {
                                                                    text: "󰀻"
                                                                    color: Theme.accent
                                                                    font.family: Theme.fontFamily
                                                                    font.pixelSize: 11
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                }

                                                                Text {
                                                                    text: modelData.name || ""
                                                                    color: Theme.fg
                                                                    font.pixelSize: 11
                                                                    font.bold: true
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    elide: Text.ElideRight
                                                                    width: parent.width - 140
                                                                }

                                                                Text {
                                                                    text: modelData.cmd || ""
                                                                    color: Qt.alpha(Theme.fg, 0.5)
                                                                    font.pixelSize: 10
                                                                    font.family: "Monospace"
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    anchors.right: parent.right
                                                                    elide: Text.ElideRight
                                                                }
                                                            }

                                                            MouseArea {
                                                                id: ruleInstAppMa
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    let appName = modelData.name || modelData.cmd || ""
                                                                    ruleClassInput.text = appName
                                                                    ruleModalBox.ruleAppPickerOpen = false
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // --- State Selector ---
                                        Column {
                                            width: parent.width
                                            spacing: 4

                                            Text {
                                                text: "Window State"
                                                color: Qt.alpha(Theme.fg, 0.6)
                                                font.pixelSize: 11
                                            }

                                            Row {
                                                spacing: 6
                                                Repeater {
                                                    model: [
                                                        { label: "Default", val: "default" },
                                                        { label: "Floating", val: "floating" },
                                                        { label: "Tiled", val: "tiled" },
                                                        { label: "Pseudo Tiled", val: "pseudo_tiled" },
                                                        { label: "Fullscreen", val: "fullscreen" }
                                                    ]
                                                    delegate: Rectangle {
                                                        height: 26
                                                        width: stateTxt.implicitWidth + 16
                                                        radius: 6
                                                        color: ruleModalBox.selState === modelData.val ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.06)
                                                        border.width: 1
                                                        border.color: ruleModalBox.selState === modelData.val ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

                                                        Text {
                                                            id: stateTxt
                                                            anchors.centerIn: parent
                                                            text: modelData.label
                                                            color: ruleModalBox.selState === modelData.val ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                                            font.pixelSize: 11
                                                            font.bold: ruleModalBox.selState === modelData.val
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                ruleModalBox.selState = modelData.val
                                                                ruleModalBox.updateFullOpts()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // --- Layer Selector ---
                                        Column {
                                            width: parent.width
                                            spacing: 4

                                            Text {
                                                text: "Window Layer (Z-Index Level)"
                                                color: Qt.alpha(Theme.fg, 0.6)
                                                font.pixelSize: 11
                                            }

                                            Row {
                                                spacing: 6
                                                Repeater {
                                                    model: [
                                                        { label: "Default", val: "default" },
                                                        { label: "Above (On Top)", val: "above" },
                                                        { label: "Normal", val: "normal" },
                                                        { label: "Below", val: "below" }
                                                    ]
                                                    delegate: Rectangle {
                                                        height: 26
                                                        width: layerTxt.implicitWidth + 16
                                                        radius: 6
                                                        color: ruleModalBox.selLayer === modelData.val ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.06)
                                                        border.width: 1
                                                        border.color: ruleModalBox.selLayer === modelData.val ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

                                                        Text {
                                                            id: layerTxt
                                                            anchors.centerIn: parent
                                                            text: modelData.label
                                                            color: ruleModalBox.selLayer === modelData.val ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                                            font.pixelSize: 11
                                                            font.bold: ruleModalBox.selLayer === modelData.val
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                ruleModalBox.selLayer = modelData.val
                                                                ruleModalBox.updateFullOpts()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // --- Desktop Selector ---
                                        Column {
                                            width: parent.width
                                            spacing: 4

                                            Text {
                                                text: "Target Desktop / Workspace"
                                                color: Qt.alpha(Theme.fg, 0.6)
                                                font.pixelSize: 11
                                            }

                                            Flow {
                                                width: parent.width
                                                spacing: 5
                                                Repeater {
                                                    model: [
                                                        { label: "Default", val: "default" },
                                                        { label: "^1", val: "^1" }, { label: "^2", val: "^2" },
                                                        { label: "^3", val: "^3" }, { label: "^4", val: "^4" },
                                                        { label: "^5", val: "^5" }, { label: "^6", val: "^6" },
                                                        { label: "^7", val: "^7" }, { label: "^8", val: "^8" },
                                                        { label: "^9", val: "^9" }, { label: "^10", val: "^10" }
                                                    ]
                                                    delegate: Rectangle {
                                                        height: 24
                                                        width: deskTxt.implicitWidth + 14
                                                        radius: 5
                                                        color: ruleModalBox.selDesktop === modelData.val ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.06)
                                                        border.width: 1
                                                        border.color: ruleModalBox.selDesktop === modelData.val ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

                                                        Text {
                                                            id: deskTxt
                                                            anchors.centerIn: parent
                                                            text: modelData.label
                                                            color: ruleModalBox.selDesktop === modelData.val ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                                            font.pixelSize: 11
                                                            font.bold: ruleModalBox.selDesktop === modelData.val
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                ruleModalBox.selDesktop = modelData.val
                                                                ruleModalBox.updateFullOpts()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // --- Follow & Focus Switches ---
                                        Row {
                                            width: parent.width
                                            spacing: 12

                                            // Follow
                                            Column {
                                                width: (parent.width - 12) / 2
                                                spacing: 4

                                                Text {
                                                    text: "Follow (Switch to desktop)"
                                                    color: Qt.alpha(Theme.fg, 0.6)
                                                    font.pixelSize: 11
                                                }

                                                Row {
                                                    spacing: 4
                                                    Repeater {
                                                        model: [
                                                            { label: "Default", val: "default" },
                                                            { label: "On", val: "on" },
                                                            { label: "Off", val: "off" }
                                                        ]
                                                        delegate: Rectangle {
                                                            height: 24
                                                            width: (modalBodyCol.width / 2 - 8) / 3
                                                            radius: 5
                                                            color: ruleModalBox.selFollow === modelData.val ? (modelData.val === "off" ? Qt.alpha(Theme.red, 0.2) : Qt.alpha(Theme.accent, 0.22)) : Qt.alpha(Theme.fg, 0.06)
                                                            border.width: 1
                                                            border.color: ruleModalBox.selFollow === modelData.val ? (modelData.val === "off" ? Theme.red : Theme.accent) : Qt.alpha(Theme.fg, 0.12)

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData.label
                                                                color: ruleModalBox.selFollow === modelData.val ? (modelData.val === "off" ? Theme.red : Theme.accent) : Qt.alpha(Theme.fg, 0.7)
                                                                font.pixelSize: 11
                                                                font.bold: ruleModalBox.selFollow === modelData.val
                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    ruleModalBox.selFollow = modelData.val
                                                                    ruleModalBox.updateFullOpts()
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Focus
                                            Column {
                                                width: (parent.width - 12) / 2
                                                spacing: 4

                                                Text {
                                                    text: "Focus (Give input focus)"
                                                    color: Qt.alpha(Theme.fg, 0.6)
                                                    font.pixelSize: 11
                                                }

                                                Row {
                                                    spacing: 4
                                                    Repeater {
                                                        model: [
                                                            { label: "Default", val: "default" },
                                                            { label: "On", val: "on" },
                                                            { label: "Off", val: "off" }
                                                        ]
                                                        delegate: Rectangle {
                                                            height: 24
                                                            width: (modalBodyCol.width / 2 - 8) / 3
                                                            radius: 5
                                                            color: ruleModalBox.selFocus === modelData.val ? (modelData.val === "off" ? Qt.alpha(Theme.red, 0.2) : Qt.alpha(Theme.accent, 0.22)) : Qt.alpha(Theme.fg, 0.06)
                                                            border.width: 1
                                                            border.color: ruleModalBox.selFocus === modelData.val ? (modelData.val === "off" ? Theme.red : Theme.accent) : Qt.alpha(Theme.fg, 0.12)

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData.label
                                                                color: ruleModalBox.selFocus === modelData.val ? (modelData.val === "off" ? Theme.red : Theme.accent) : Qt.alpha(Theme.fg, 0.7)
                                                                font.pixelSize: 11
                                                                font.bold: ruleModalBox.selFocus === modelData.val
                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    ruleModalBox.selFocus = modelData.val
                                                                    ruleModalBox.updateFullOpts()
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // --- Grid of Flags (Manage, Sticky, Private, Locked, Marked, Border) ---
                                        Column {
                                            width: parent.width
                                            spacing: 6

                                            Text {
                                                text: "Other BSPWM Window Flags"
                                                color: Qt.alpha(Theme.fg, 0.6)
                                                font.pixelSize: 11
                                            }

                                            Grid {
                                                width: parent.width
                                                columns: 2
                                                columnSpacing: 10
                                                rowSpacing: 6

                                                Repeater {
                                                    model: [
                                                        { title: "Manage", prop: "selManage" },
                                                        { title: "Sticky", prop: "selSticky" },
                                                        { title: "Private", prop: "selPrivate" },
                                                        { title: "Locked", prop: "selLocked" },
                                                        { title: "Marked", prop: "selMarked" },
                                                        { title: "Border", prop: "selBorder" },
                                                        { title: "Center", prop: "selCenter" }
                                                    ]

                                                    delegate: Row {
                                                        id: flagRowItem
                                                        readonly property string flagPropName: modelData.prop
                                                        width: (modalBodyCol.width - 10) / 2
                                                        spacing: 6

                                                        Text {
                                                            width: 52
                                                            text: modelData.title
                                                            color: Qt.alpha(Theme.fg, 0.7)
                                                            font.pixelSize: 11
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }

                                                        Row {
                                                            spacing: 3
                                                            Repeater {
                                                                model: [
                                                                    { label: "Def", val: "default" },
                                                                    { label: "On", val: "on" },
                                                                    { label: "Off", val: "off" }
                                                                ]
                                                                delegate: Rectangle {
                                                                    height: 22
                                                                    width: 36
                                                                    radius: 4
                                                                    readonly property string curVal: ruleModalBox.getFlag(flagRowItem.flagPropName)
                                                                    color: curVal === modelData.val ? (modelData.val === "off" ? Qt.alpha(Theme.red, 0.2) : Qt.alpha(Theme.accent, 0.22)) : Qt.alpha(Theme.fg, 0.05)
                                                                    border.width: 1
                                                                    border.color: curVal === modelData.val ? (modelData.val === "off" ? Theme.red : Theme.accent) : Qt.alpha(Theme.fg, 0.1)

                                                                    Text {
                                                                        anchors.centerIn: parent
                                                                        text: modelData.label
                                                                        color: curVal === modelData.val ? (modelData.val === "off" ? Theme.red : Theme.accent) : Qt.alpha(Theme.fg, 0.6)
                                                                        font.pixelSize: 10
                                                                        font.bold: curVal === modelData.val
                                                                    }

                                                                    MouseArea {
                                                                        anchors.fill: parent
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: {
                                                                            ruleModalBox.setFlag(flagRowItem.flagPropName, modelData.val)
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Footer Action Buttons
                                Row {
                                    anchors.right: parent.right
                                    spacing: 10

                                    // Cancel
                                    Rectangle {
                                        width: 80; height: 32; radius: 6
                                        color: cancelRuleMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : Qt.alpha(Theme.fg, 0.08)

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            color: Theme.fg
                                            font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: cancelRuleMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: windowRulesPanel.modalOpen = false
                                        }
                                    }

                                    // Save / Add
                                    Rectangle {
                                        width: 90; height: 32; radius: 6
                                        color: saveRuleMa.containsMouse ? Qt.alpha(Theme.accent, 0.85) : Theme.accent

                                        Text {
                                            anchors.centerIn: parent
                                            text: windowRulesPanel.isEditing ? "Save" : "Add"
                                            color: Theme.bg
                                            font.pixelSize: 12
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: saveRuleMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                let baseClass = ruleClassInput.text.trim()
                                                if (!baseClass) return
                                                let titleStr = ruleTitleInput.text.trim()
                                                let fullClass = baseClass
                                                if (titleStr) {
                                                    fullClass = baseClass + ":*:" + (titleStr.includes(" ") ? ('"' + titleStr + '"') : titleStr)
                                                }
                                                let optsStr = ruleModalBox.updateFullOpts()

                                                if (windowRulesPanel.isEditing) {
                                                    windowRulesPanel.editRule(windowRulesPanel.editOldClass, fullClass, optsStr)
                                                } else {
                                                    windowRulesPanel.addRule(fullClass, optsStr)
                                                }
                                                windowRulesPanel.modalOpen = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

// --- ADD MODULE POPUP MODAL OVERLAY ---
        Rectangle {
            anchors.fill: parent
            visible: root.addModalOpen
            color: Qt.alpha("#000000", 0.65)
            z: 999

            // Close on clicking backdrop
            MouseArea {
                anchors.fill: parent
                onClicked: root.addModalOpen = false
            }

            // Modal Dialog Card
            Rectangle {
                width: 440
                height: Math.min(480, modalCol.height + 36)
                anchors.centerIn: parent
                radius: 12
                color: Theme.bg
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.40)

                // Prevent backdrop click-through
                MouseArea {
                    anchors.fill: parent
                    onClicked: {}
                }

                Column {
                    id: modalCol
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    spacing: 14

                    // Header Bar
                    Item {
                        width: parent.width
                        height: 28

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Add Module to " + root.targetClusterTitle
                            color: Theme.accent
                            font.pixelSize: 16
                            font.bold: true
                        }

                        // Close Button
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26; radius: 13
                            color: closeModMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                            }

                            MouseArea {
                                id: closeModMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.addModalOpen = false
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1
                        color: Qt.alpha(Theme.fg, 0.10)
                    }

                    // Subtitle
                    Text {
                        text: "Select any module to place into " + root.targetClusterTitle + ":"
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: 12
                    }

                    // Available Modules List
                    Flickable {
                        width: parent.width
                        height: Math.min(340, availListCol.height)
                        contentHeight: availListCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: availListCol
                            width: parent.width
                            spacing: 8

                            function getModulesForTarget() {
                                const targetKey = root.targetClusterKey
                                let targetList = []
                                if (targetKey === "left") targetList = Sys.leftModules || []
                                else if (targetKey === "center") targetList = Sys.centerModules || []
                                else if (targetKey === "right") targetList = Sys.rightModules || []

                                const all = Sys.allAvailableModules || []
                                return all.filter(id => targetList.indexOf(id) === -1)
                            }

                            Repeater {
                                model: availListCol.getModulesForTarget()

                                delegate: Rectangle {
                                    required property string modelData
                                    required property int index

                                    width: parent.width
                                    height: 44
                                    radius: 8
                                    color: Qt.alpha(Theme.fg, 0.04)
                                    border.width: 1
                                    border.color: Qt.alpha(Theme.fg, 0.16)

                                    Item {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12

                                        // Avatar Preview
                                        Item {
                                            id: avatarPreviewBox
                                            width: 52
                                            height: 52
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter

                                            Image {
                                                id: prevAvatarImg
                                                width: 52
                                                height: 52
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Row {
                                            anchors.left: avatarPreviewBox.right
                                            anchors.leftMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 10

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Sys.getModuleIcon(modelData)
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 16
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 1

                                                Text {
                                                    text: Sys.getModuleName(modelData)
                                                    color: Theme.fg
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }

                                                Text {
                                                    text: "Status: " + Sys.getModuleCluster(modelData)
                                                    color: Qt.alpha(Theme.fg, 0.45)
                                                    font.pixelSize: 10
                                                }
                                            }
                                        }

                                        // Add Button
                                        Rectangle {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 68
                                            height: 28
                                            radius: 6
                                            color: addPopMa.containsMouse ? Qt.alpha(Theme.accent, 0.35) : Qt.alpha(Theme.accent, 0.20)
                                            border.width: 1
                                            border.color: Theme.accent

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 4

                                                Text {
                                                    text: "󰐕"
                                                    color: Theme.accent
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                }

                                                Text {
                                                    text: "Add"
                                                    color: Theme.accent
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }
                                            }

                                            MouseArea {
                                                id: addPopMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Sys.addClusterModule(root.targetClusterKey, modelData)
                                                    root.addModalOpen = false
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
}
}

