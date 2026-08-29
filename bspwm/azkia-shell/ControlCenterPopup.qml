import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Popout {
    id: root

    cardWidth: 540
    cardHeight: mainCol.implicitHeight + (cardPadding * 2)
    alignRight: true

    function toggle() { visible = !visible }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { root.toggle() }
    }

    property string activeSubPanel: "" // "", "wifi", "bt", "sink", "source"

    onVisibleChanged: {
        if (!visible) {
            activeSubPanel = ""
        }
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property var audioSink: Pipewire.defaultAudioSink?.audio ?? null
    readonly property var audioSource: Pipewire.defaultAudioSource?.audio ?? null

    readonly property bool sinkMuted: audioSink?.muted ?? false
    readonly property int sinkVolume: audioSink ? Math.round(audioSink.volume * 100) : 0

    readonly property bool sourceMuted: audioSource?.muted ?? false
    readonly property int sourceVolume: audioSource ? Math.round(audioSource.volume * 100) : 0

    property int brightnessVal: 50

    Process {
        id: brightnessGet
        command: ["brightnessctl", "-m"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(",")
                if (parts.length >= 4) {
                    const pct = parseInt(parts[3].replace("%", ""))
                    if (!isNaN(pct)) root.brightnessVal = pct
                }
            }
        }
    }

    Timer {
        interval: 600
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            brightnessGet.running = false
            brightnessGet.running = true
        }
    }

    function setBrightness(pct) {
        pct = Math.max(1, Math.min(100, Math.round(pct)))
        root.brightnessVal = pct
        Quickshell.execDetached(["brightnessctl", "s", pct + "%"])
    }

    // ================= NETWORK DATA PROCESS =================
    property var wifiNetworks: []
    property var savedWifiList: []
    property bool wifiScanning: false

    function rescanWifi() {
        root.wifiScanning = true
        Quickshell.execDetached(["nmcli", "dev", "wifi", "rescan"])
        wifiRescanTimer.restart()
    }

    Timer {
        id: wifiRescanTimer
        interval: 1500
        onTriggered: {
            wifiProc.running = false
            wifiProc.running = true
            savedWifiProc.running = false
            savedWifiProc.running = true
        }
    }

    Process {
        id: savedWifiProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const saved = []
                for (const line of lines) {
                    if (!line) continue
                    const parts = line.split(":")
                    if (parts.length >= 2 && parts[1].trim() === "802-11-wireless") {
                        saved.push(parts[0].trim())
                    }
                }
                root.savedWifiList = saved
            }
        }
    }

    Process {
        id: wifiProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanning = false
                const lines = text.trim().split("\n")
                const seen = {}
                for (const line of lines) {
                    if (!line) continue
                    const parts = line.split(":")
                    if (parts.length >= 3) {
                        const inUse = parts[0].trim() === "*"
                        const ssid = parts[1].trim()
                        const signal = parseInt(parts[2]) || 0
                        const security = parts.slice(3).join(":")

                        if (!ssid) continue

                        if (!seen[ssid] || inUse || signal > seen[ssid].signal) {
                            seen[ssid] = {
                                ssid: ssid,
                                signal: signal,
                                security: security,
                                inUse: inUse
                            }
                        }
                    }
                }
                const list = []
                for (const ssid in seen) {
                    list.push(seen[ssid])
                }
                list.sort((a, b) => (b.inUse ? 1 : 0) - (a.inUse ? 1 : 0) || b.signal - a.signal)
                root.wifiNetworks = list
            }
        }
    }
    Timer {
        interval: 4000
        running: root.visible && root.activeSubPanel === "wifi"
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            wifiProc.running = true
            savedWifiProc.running = true
        }
    }

    // ================= BLUETOOTH DATA PROCESS =================
    property var btDevices: []
    Process {
        id: btProc
        command: ["python3", Sys.scriptPath("bluetooth_info.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.btDevices = JSON.parse(text)
                } catch (e) {
                    root.btDevices = []
                }
            }
        }
    }
    Timer {
        id: btRefreshTimer
        interval: 1500
        onTriggered: {
            btProc.running = false
            btProc.running = true
        }
    }
    Timer {
        interval: 4000
        running: Sys.btEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!btProc.running) btProc.running = true
        }
    }

    // ================= AUDIO DEVICES (SINKS & SOURCES) PROCESS =================
    property var audioSinksList: []
    property var audioSourcesList: []

    Process {
        id: audioDevProc
        command: ["wpctl", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                let section = ""
                const sinks = [], sources = []
                for (const line of lines) {
                    if (line.includes("Sinks:")) { section = "sinks"; continue }
                    if (line.includes("Sources:")) { section = "sources"; continue }
                    if (line.includes("Filters:") || line.includes("Streams:") || line.includes("Devices:")) { section = ""; continue }

                    if (section === "sinks" || section === "sources") {
                        const match = line.match(/(\*?)\s*(\d+)\.\s+(.*?)\s+\[vol:/)
                        if (match) {
                            const item = {
                                id: match[2],
                                desc: match[3].trim(),
                                isDefault: match[1] === "*"
                            }
                            if (section === "sinks") sinks.push(item)
                            else sources.push(item)
                        }
                    }
                }
                root.audioSinksList = sinks
                root.audioSourcesList = sources
            }
        }
    }
    Timer {
        interval: 3000
        running: root.visible && (root.activeSubPanel === "sink" || root.activeSubPanel === "source")
        repeat: true
        triggeredOnStart: true
        onTriggered: audioDevProc.running = true
    }

    property string selectedWifiSsid: ""
    property var wallpapersList: []
    property var storagePartitions: []
    property var rootPartition: null
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

    function loadWallpapers() {
        wallpaperProc.running = false
        wallpaperProc.running = true
    }

    Connections {
        target: Sys
        function onWallpaperDirChanged() {
            root.loadWallpapers()
        }
    }

    Process {
        id: storageProc
        command: ["python3", Sys.scriptPath("storage_info.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text)
                    root.storagePartitions = list
                    root.rootPartition = list.find(p => p.mount === "/") || list[0] || null
                } catch (e) {
                    root.storagePartitions = []
                }
            }
        }
    }

    Component.onCompleted: {
        wifiProc.running = true
        savedWifiProc.running = true
        btProc.running = true
        wallpaperProc.running = true
        storageProc.running = true
        batProc.running = true
    }

    onActiveSubPanelChanged: {
        if (activeSubPanel === "wifi") {
            wifiProc.running = true
            savedWifiProc.running = true
        }
        else if (activeSubPanel === "bt") btProc.running = true
        else if (activeSubPanel === "sink" || activeSubPanel === "source") audioDevProc.running = true
        else if (activeSubPanel === "wallpaper") wallpaperProc.running = true
        else if (activeSubPanel === "storage") storageProc.running = true
        else if (activeSubPanel === "battery") batProc.running = true
    }

    Column {
        id: mainCol
        width: parent.width
        spacing: 12

        // ================= HEADER SECTION =================
        Item {
            width: parent.width
            height: 52

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                // Avatar image forced to circular (radius: width / 2)
                Item {
                    width: 48
                    height: 48

                    Image {
                        id: ccAvatarImg
                        anchors.fill: parent
                        source: root.visible ? Sys.userAvatar : ""
                        sourceSize: Qt.size(48, 48)
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        cache: false
                        visible: false
                    }

                    Rectangle {
                        id: ccAvatarMask
                        anchors.fill: parent
                        radius: width / 2
                        color: "black"
                        visible: false
                        antialiasing: true
                    }

                    OpacityMask {
                        anchors.fill: parent
                        source: ccAvatarImg
                        maskSource: ccAvatarMask
                        visible: ccAvatarImg.status === Image.Ready
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 1.5
                        border.color: Theme.accent
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: ccAvatarImg.status !== Image.Ready
                        text: "󰀉"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 24
                    }
                }

                // User Info
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: Sys.userName !== "" ? Sys.userName : "User"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Text {
                        text: Sys.uptimeText !== "" ? Sys.uptimeText : "up --"
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
            }

            // Quick Actions: Lock, Power, Settings
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Lock Button
                Rectangle {
                    width: 36
                    height: 36
                    radius: 8
                    color: lockMa.containsMouse ? Qt.alpha(Theme.accent, 0.20) : Sys.customModuleBg
                    border.width: 1
                    border.color: lockMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Sys.customModuleBorder
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰌾"
                        color: lockMa.containsMouse ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: lockMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.visible = false
                            Quickshell.execDetached(["quickshell", "--path", Sys.configDir, "ipc", "call", "lockscreen", "lock"])
                        }
                    }
                }

                // Power Button
                Rectangle {
                    width: 36
                    height: 36
                    radius: 8
                    color: pwrMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : Sys.customModuleBg
                    border.width: 1
                    border.color: pwrMa.containsMouse ? Qt.alpha(Theme.red, 0.5) : Sys.customModuleBorder
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰐥"
                        color: pwrMa.containsMouse ? Theme.red : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: pwrMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.visible = false
                            Quickshell.execDetached(["quickshell", "--path", Sys.configDir, "ipc", "call", "power", "toggle"])
                        }
                    }
                }

                // Settings Button
                Rectangle {
                    width: 36
                    height: 36
                    radius: 8
                    color: setMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Sys.customModuleBg
                    border.width: 1
                    border.color: setMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Sys.customModuleBorder
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒓"
                        color: setMa.containsMouse ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: setMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.visible = false
                            Quickshell.execDetached(["quickshell", "--path", Sys.configDir, "ipc", "call", "settings", "toggle"])
                        }
                    }
                }
            }
        }

        // ================= SLIDERS SECTION =================
        Row {
            width: parent.width
            height: 38
            spacing: 12

            // Volume Slider Component
            Rectangle {
                width: (parent.width - 12) / 2
                height: parent.height
                radius: 10
                color: volMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg
                border.width: 1
                border.color: volMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Sys.customModuleBorder
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    id: volRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        id: volIconText
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.sinkMuted ? "󰝟" : root.sinkVolume < 30 ? "󰕿" : root.sinkVolume < 70 ? "󰖀" : "󰕾"
                        color: root.sinkMuted ? Qt.alpha(Theme.fg, 0.4) : Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                    }

                    Item {
                        id: volTrackContainer
                        width: parent.width - volIconText.width - volPctText.width - (volRow.spacing * 2)
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Qt.alpha(Theme.fg, 0.15)

                            Rectangle {
                                width: parent.width * (root.sinkVolume / 100)
                                height: parent.height
                                radius: 3
                                color: root.sinkMuted ? Qt.alpha(Theme.fg, 0.4) : Theme.accent
                            }

                            Rectangle {
                                x: Math.max(0, Math.min(parent.width - width, (parent.width * (root.sinkVolume / 100)) - width / 2))
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                radius: 7
                                color: root.sinkMuted ? Qt.alpha(Theme.fg, 0.6) : Theme.accent
                                border.width: 2
                                border.color: Theme.bg
                            }
                        }
                    }

                    Text {
                        id: volPctText
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.sinkMuted ? "Muted" : (root.sinkVolume + "%")
                        color: root.sinkMuted ? Qt.alpha(Theme.fg, 0.4) : Qt.alpha(Theme.fg, 0.8)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                MouseArea {
                    id: volMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: mouse => {
                        if (pressed && root.audioSink) {
                            const rect = volTrackContainer.mapFromItem(volMa, mouse.x, mouse.y)
                            root.audioSink.muted = false
                            root.audioSink.volume = Math.max(0, Math.min(1, rect.x / volTrackContainer.width))
                        }
                    }
                    onClicked: mouse => {
                        if (root.audioSink) {
                            const rect = volTrackContainer.mapFromItem(volMa, mouse.x, mouse.y)
                            root.audioSink.muted = false
                            root.audioSink.volume = Math.max(0, Math.min(1, rect.x / volTrackContainer.width))
                        }
                    }
                    onWheel: wheel => {
                        if (root.audioSink) {
                            const step = wheel.angleDelta.y > 0 ? 0.02 : -0.02
                            root.audioSink.muted = false
                            root.audioSink.volume = Math.max(0, Math.min(1, root.audioSink.volume + step))
                        }
                    }
                }
            }

            // Brightness Slider Component
            Rectangle {
                width: (parent.width - 12) / 2
                height: parent.height
                radius: 10
                color: brightMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg
                border.width: 1
                border.color: brightMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Sys.customModuleBorder
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    id: brightRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        id: brightIconText
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.brightnessVal <= 25 ? "󰃜" : root.brightnessVal <= 65 ? "󰃞" : "󰃠"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                    }

                    Item {
                        id: brightTrackContainer
                        width: parent.width - brightIconText.width - brightPctText.width - (brightRow.spacing * 2)
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Qt.alpha(Theme.fg, 0.15)

                            Rectangle {
                                width: parent.width * (root.brightnessVal / 100)
                                height: parent.height
                                radius: 3
                                color: Theme.accent
                            }

                            Rectangle {
                                x: Math.max(0, Math.min(parent.width - width, (parent.width * (root.brightnessVal / 100)) - width / 2))
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                radius: 7
                                color: Theme.accent
                                border.width: 2
                                border.color: Theme.bg
                            }
                        }
                    }

                    Text {
                        id: brightPctText
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.brightnessVal + "%"
                        color: Qt.alpha(Theme.fg, 0.8)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                MouseArea {
                    id: brightMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: mouse => {
                        if (pressed) {
                            const rect = brightTrackContainer.mapFromItem(brightMa, mouse.x, mouse.y)
                            root.setBrightness((rect.x / brightTrackContainer.width) * 100)
                        }
                    }
                    onClicked: mouse => {
                        const rect = brightTrackContainer.mapFromItem(brightMa, mouse.x, mouse.y)
                        root.setBrightness((rect.x / brightTrackContainer.width) * 100)
                    }
                    onWheel: wheel => {
                        const step = wheel.angleDelta.y > 0 ? 5 : -5
                        root.setBrightness(root.brightnessVal + step)
                    }
                }
            }
        }

        // Helper Component for Cards
        component ControlCard: Rectangle {
            id: cardRoot
            property string icon: ""
            property string titleText: ""
            property string subText: ""
            property bool active: false
            property bool expanded: false
            signal cardClicked()

            width: (mainCol.width - 10) / 2
            height: 58
            radius: 12
            color: cardMa.containsMouse ? Qt.alpha(Theme.accent, 0.20) : (cardRoot.active || cardRoot.expanded ? Qt.alpha(Theme.fg, 0.14) : Sys.customModuleBg)
            border.width: 1
            border.color: cardRoot.expanded ? Qt.alpha(Theme.accent, 0.5) : (cardMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Sys.customModuleBorder)

            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38
                    radius: 8
                    color: cardRoot.active || cardRoot.expanded ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.06)
                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        anchors.centerIn: parent
                        text: cardRoot.icon
                        color: cardRoot.active || cardRoot.expanded ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 48
                    spacing: 2

                    Text {
                        width: parent.width
                        text: cardRoot.titleText
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: cardRoot.subText
                        color: cardRoot.active ? Qt.alpha(Theme.fg, 0.7) : Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }

            MouseArea {
                id: cardMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: cardRoot.cardClicked()
            }
        }

        // ================= ROW 1: WIFI & BLUETOOTH CARDS =================
        Row {
            width: parent.width
            spacing: 10

            ControlCard {
                icon: Sys.netIcon
                titleText: Sys.netName !== "" ? Sys.netName : "Wi-Fi"
                subText: Sys.online ? "Connected" : "Disconnected"
                active: Sys.online
                expanded: root.activeSubPanel === "wifi"
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "wifi") ? "" : "wifi"
            }

            ControlCard {
                icon: "󰂯"
                titleText: "Bluetooth"
                subText: Sys.btStatus !== "" ? Sys.btStatus : (Sys.btEnabled ? "Enabled" : "Disabled")
                active: Sys.btEnabled
                expanded: root.activeSubPanel === "bt"
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "bt") ? "" : "bt"
            }
        }

        // ================= SUB-PANEL SLOT 1 (WIFI or BLUETOOTH) =================
        // WiFi Sub-Panel
        Rectangle {
            id: wifiPanel
            width: parent.width
            implicitHeight: wifiCol.implicitHeight + 20
            visible: root.activeSubPanel === "wifi"
            radius: 16
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)

            Column {
                id: wifiCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 10

                // Header
                Item {
                    width: parent.width
                    height: 32

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Network"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Rectangle {
                            height: 26
                            width: 65
                            radius: 6
                            color: Qt.alpha(Theme.fg, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "Ethernet"
                                color: Qt.alpha(Theme.fg, 0.6)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }

                        Rectangle {
                            height: 26
                            width: 55
                            radius: 6
                            color: Qt.alpha(Theme.accent, 0.25)
                            border.width: 1
                            border.color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "✓ Wi-Fi"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        // Rescan Button
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 6
                            color: wifiRescanMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)

                            Text {
                                id: wifiRescanIcon
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: root.wifiScanning ? Theme.accent : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                RotationAnimator on rotation {
                                    running: root.wifiScanning
                                    from: 0
                                    to: 360
                                    loops: Animation.Infinite
                                    duration: 1000
                                }
                            }
                            MouseArea {
                                id: wifiRescanMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.rescanWifi()
                            }
                        }

                        // Settings Button
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 6
                            color: wifiGearMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)

                            Text {
                                anchors.centerIn: parent
                                text: "󰒓"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: wifiGearMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached(["nm-connection-editor"])
                            }
                        }
                    }
                }

                // Networks List
                Column {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: root.wifiNetworks

                        Column {
                            required property var modelData
                            property bool showPass: false
                            width: parent.width
                            spacing: 4

                            function handleConnect() {
                                if (modelData.inUse) return
                                const isSaved = root.savedWifiList.includes(modelData.ssid)
                                const isOpen = (modelData.security === "--" || modelData.security === "")
                                if (isSaved || isOpen) {
                                    const escaped = modelData.ssid.replace(/'/g, "'\\''")
                                    Quickshell.execDetached(["sh", "-c", "nmcli con up id '" + escaped + "' 2>/dev/null || nmcli dev wifi connect '" + escaped + "'"])
                                    Quickshell.execDetached(["notify-send", "-a", "Wi-Fi", "Wi-Fi Connected", "Connected to " + modelData.ssid])
                                    root.selectedWifiSsid = ""
                                    wifiRescanTimer.restart()
                                } else {
                                    root.selectedWifiSsid = (root.selectedWifiSsid === modelData.ssid ? "" : modelData.ssid)
                                }
                            }

                            Rectangle {
                                id: wifiItemRow
                                width: parent.width
                                height: 44
                                radius: 8
                                color: modelData.inUse ? Qt.alpha(Theme.accent, 0.18) : cardItemMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : Qt.alpha(Theme.fg, 0.04)
                                border.width: modelData.inUse ? 1 : 0
                                border.color: Qt.alpha(Theme.accent, 0.4)

                                MouseArea {
                                    id: cardItemMa
                                    anchors.fill: parent
                                    hoverEnabled: !modelData.inUse
                                    cursorShape: !modelData.inUse ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: handleConnect()
                                }

                                // Icon Box (Left)
                                Rectangle {
                                    id: wifiIconBox
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 30
                                    height: 30
                                    radius: 6
                                    color: modelData.inUse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.06)

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.signal > 75 ? "󰤨" : modelData.signal > 50 ? "󰤥" : modelData.signal > 25 ? "󰤢" : "󰤟"
                                        color: modelData.inUse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 15
                                    }
                                }

                                // Actions (Right): Connect & Disconnect Buttons
                                Row {
                                    id: wifiActionsRow
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    // Connect Button
                                    Rectangle {
                                        width: 62
                                        height: 26
                                        radius: 6
                                        color: modelData.inUse ? Qt.alpha(Theme.fg, 0.06) : connectMa.containsMouse ? Qt.alpha(Theme.accent, 0.35) : Qt.alpha(Theme.accent, 0.22)
                                        border.width: modelData.inUse ? 0 : 1
                                        border.color: Qt.alpha(Theme.accent, 0.4)
                                        opacity: modelData.inUse ? 0.4 : 1.0

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Connect"
                                            color: modelData.inUse ? Qt.alpha(Theme.fg, 0.5) : Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: connectMa
                                            anchors.fill: parent
                                            enabled: !modelData.inUse
                                            hoverEnabled: enabled
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: handleConnect()
                                        }
                                    }

                                    // Disconnect Button
                                    Rectangle {
                                        width: 74
                                        height: 26
                                        radius: 6
                                        color: !modelData.inUse ? Qt.alpha(Theme.fg, 0.06) : disconnMa.containsMouse ? Qt.alpha(Theme.red, 0.35) : Qt.alpha(Theme.red, 0.22)
                                        border.width: !modelData.inUse ? 0 : 1
                                        border.color: Qt.alpha(Theme.red, 0.4)
                                        opacity: !modelData.inUse ? 0.4 : 1.0

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Disconnect"
                                            color: !modelData.inUse ? Qt.alpha(Theme.fg, 0.5) : Theme.red
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: disconnMa
                                            anchors.fill: parent
                                            enabled: modelData.inUse
                                            hoverEnabled: enabled
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                Quickshell.execDetached(["sh", "-c", "nmcli dev disconnect wlan0 2>/dev/null || nmcli con down id '" + modelData.ssid.replace(/'/g, "'\\''") + "'"])
                                                Quickshell.execDetached(["notify-send", "-a", "Wi-Fi", "Wi-Fi Disconnected", "Disconnected from " + modelData.ssid])
                                                wifiRescanTimer.restart()
                                            }
                                        }
                                    }
                                }

                                // Text Column (Middle)
                                Column {
                                    anchors.left: wifiIconBox.right
                                    anchors.leftMargin: 10
                                    anchors.right: wifiActionsRow.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: modelData.ssid
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.inUse ? ("Connected • " + modelData.signal + "%") : (root.savedWifiList.includes(modelData.ssid) ? "Saved • " : modelData.security !== "--" ? "Secured • " : "Open • ") + modelData.signal + "%"
                                        color: modelData.inUse ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // In-Line Password Box
                            Rectangle {
                                id: passBox
                                width: parent.width
                                height: 38
                                visible: root.selectedWifiSsid === modelData.ssid && !modelData.inUse
                                radius: 8
                                color: Qt.alpha(Theme.fg, 0.06)
                                border.width: 1
                                border.color: Qt.alpha(Theme.accent, 0.4)

                                onVisibleChanged: {
                                    if (visible) {
                                        wifiPassFocusTimer.restart()
                                    }
                                }

                                Timer {
                                    id: wifiPassFocusTimer
                                    interval: 50
                                    onTriggered: {
                                        Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py")])
                                        passInput.forceActiveFocus()
                                    }
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 8

                                    // Lock Icon
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰌾"
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                    }

                                    // Password Text Input
                                    TextInput {
                                        id: passInput
                                        width: parent.width - 92
                                        anchors.verticalCenter: parent.verticalCenter
                                        echoMode: showPass ? TextInput.Normal : TextInput.Password
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        clip: true
                                        selectByMouse: true

                                        onAccepted: submitPass()

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: !passInput.text
                                            text: "Enter password..."
                                            color: Qt.alpha(Theme.fg, 0.4)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                    }

                                    // Eye Icon Button (Toggle Password Visibility)
                                    Rectangle {
                                        width: 26
                                        height: 26
                                        radius: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: eyeMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)

                                        Text {
                                            anchors.centerIn: parent
                                            text: showPass ? "󰈈" : "󰈉"
                                            color: showPass ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                        }

                                        MouseArea {
                                            id: eyeMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: showPass = !showPass
                                        }
                                    }

                                    // Arrow Icon Button (Replaces Join Button)
                                    Rectangle {
                                        width: 30
                                        height: 26
                                        radius: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: arrowMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.85)

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰁔"
                                            color: Theme.bg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: arrowMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: submitPass()
                                        }
                                    }

                                    function submitPass() {
                                        if (passInput.text && passInput.text.trim() !== "") {
                                            const escapedSsid = modelData.ssid.replace(/'/g, "'\\''")
                                            const escapedPass = passInput.text.trim().replace(/'/g, "'\\''")
                                            Quickshell.execDetached(["sh", "-c", "nmcli con delete id '" + escapedSsid + "' 2>/dev/null; nmcli dev wifi connect '" + escapedSsid + "' password '" + escapedPass + "'"])
                                            Quickshell.execDetached(["notify-send", "-a", "Wi-Fi", "Wi-Fi Connecting", "Connecting to " + modelData.ssid])
                                            passInput.text = ""
                                            root.selectedWifiSsid = ""
                                            wifiRescanTimer.restart()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Bluetooth Sub-Panel
        Rectangle {
            id: btPanel
            width: parent.width
            implicitHeight: btCol.implicitHeight + 20
            visible: root.activeSubPanel === "bt"
            radius: 16
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)

            Column {
                id: btCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 10

                // Header
                Item {
                    width: parent.width
                    height: 32

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bluetooth Settings"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 26
                        width: 65
                        radius: 6
                        color: btScanMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)

                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "󰂪"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            Text {
                                text: "Scan"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        MouseArea {
                            id: btScanMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                Quickshell.execDetached(["bluetoothctl", "--timeout", "5", "scan", "on"])
                                btProc.running = true
                            }
                        }
                    }
                }

                // Devices List
                Column {
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.btDevices

                        Rectangle {
                            id: btItemRow
                            required property var modelData
                            width: parent.width
                            height: 44
                            radius: 8
                            color: modelData.connected ? Qt.alpha(Theme.accent, 0.18) : Qt.alpha(Theme.fg, 0.04)
                            border.width: modelData.connected ? 1 : 0
                            border.color: Qt.alpha(Theme.accent, 0.4)

                            // Icon Box (Left)
                            Rectangle {
                                id: btIconBox
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 30
                                radius: 6
                                color: modelData.connected ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.06)

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰋋"
                                    color: modelData.connected ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                }
                            }

                            // Actions (Right): Connect, Disconnect & Remove Buttons
                            Row {
                                id: btActionsRow
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                // Connect Button
                                Rectangle {
                                    width: 62
                                    height: 26
                                    radius: 6
                                    color: modelData.connected ? Qt.alpha(Theme.fg, 0.06) : connectBtMa.containsMouse ? Qt.alpha(Theme.accent, 0.35) : Qt.alpha(Theme.accent, 0.22)
                                    border.width: modelData.connected ? 0 : 1
                                    border.color: Qt.alpha(Theme.accent, 0.4)
                                    opacity: modelData.connected ? 0.4 : 1.0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Connect"
                                        color: modelData.connected ? Qt.alpha(Theme.fg, 0.5) : Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: connectBtMa
                                        anchors.fill: parent
                                        enabled: !modelData.connected
                                        hoverEnabled: enabled
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            Quickshell.execDetached(["python3", Sys.scriptPath("bluetooth_info.py"), "--connect", modelData.mac])
                                            btRefreshTimer.restart()
                                        }
                                    }
                                }

                                // Disconnect Button
                                Rectangle {
                                    width: 74
                                    height: 26
                                    radius: 6
                                    color: !modelData.connected ? Qt.alpha(Theme.fg, 0.06) : disconnBtMa.containsMouse ? Qt.alpha(Theme.red, 0.35) : Qt.alpha(Theme.red, 0.22)
                                    border.width: !modelData.connected ? 0 : 1
                                    border.color: Qt.alpha(Theme.red, 0.4)
                                    opacity: !modelData.connected ? 0.4 : 1.0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Disconnect"
                                        color: !modelData.connected ? Qt.alpha(Theme.fg, 0.5) : Theme.red
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: disconnBtMa
                                        anchors.fill: parent
                                        enabled: modelData.connected
                                        hoverEnabled: enabled
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            Quickshell.execDetached(["python3", Sys.scriptPath("bluetooth_info.py"), "--disconnect", modelData.mac])
                                            btRefreshTimer.restart()
                                        }
                                    }
                                }

                                // Remove / Unpair Button (Only for paired devices)
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 6
                                    visible: modelData.paired
                                    color: removeBtMa.containsMouse ? Qt.alpha(Theme.red, 0.35) : Qt.alpha(Theme.fg, 0.08)
                                    border.width: 1
                                    border.color: Qt.alpha(Theme.red, 0.3)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰆴"
                                        color: removeBtMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.6)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }

                                    MouseArea {
                                        id: removeBtMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Quickshell.execDetached(["python3", Sys.scriptPath("bluetooth_info.py"), "--remove", modelData.mac])
                                            btRefreshTimer.restart()
                                        }
                                    }
                                }
                            }

                            // Text Column (Middle - Anchored safely between icon box and actions)
                            Column {
                                anchors.left: btIconBox.right
                                anchors.leftMargin: 10
                                anchors.right: btActionsRow.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: modelData.name
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.connected ? "Connected" : (modelData.paired ? "Paired" : "Disconnected")
                                    color: modelData.connected ? Theme.accent : modelData.paired ? Qt.alpha(Theme.fg, 0.7) : Qt.alpha(Theme.fg, 0.4)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================= ROW 2: AUDIO OUTPUT & MICROPHONE CARDS =================
        Row {
            width: parent.width
            spacing: 10

            ControlCard {
                icon: root.sinkMuted ? "󰝟" : "󰕾"
                titleText: root.audioSink?.description ? root.audioSink.description : "Audio Output"
                subText: root.sinkMuted ? "Muted" : root.sinkVolume + "%"
                active: !root.sinkMuted
                expanded: root.activeSubPanel === "sink"
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "sink") ? "" : "sink"
            }

            ControlCard {
                icon: root.sourceMuted ? "󰍭" : "󰍬"
                titleText: root.audioSource?.description ? root.audioSource.description : "Microphone"
                subText: root.sourceMuted ? "Muted" : root.sourceVolume + "%"
                active: !root.sourceMuted
                expanded: root.activeSubPanel === "source"
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "source") ? "" : "source"
            }
        }

        // ================= SUB-PANEL SLOT 2 (AUDIO DEVICES or INPUT DEVICES) =================
        // Audio Devices Sub-Panel (Sink / Output)
        Rectangle {
            id: sinkPanel
            width: parent.width
            implicitHeight: sinkCol.implicitHeight + 20
            visible: root.activeSubPanel === "sink"
            radius: 16
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)

            Column {
                id: sinkCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 10

                // Header
                Item {
                    width: parent.width
                    height: 32

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Audio Devices"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        radius: 6
                        color: sinkGearMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: "󰒓"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: sinkGearMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Quickshell.execDetached(["pavucontrol"])
                        }
                    }
                }

                // Devices List
                Column {
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.audioSinksList

                        Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 44
                            radius: 8
                            color: modelData.isDefault ? Qt.alpha(Theme.accent, 0.18)
                                 : sinkItemMa.containsMouse ? Qt.alpha(Theme.fg, 0.10)
                                 : Qt.alpha(Theme.fg, 0.04)
                            border.width: modelData.isDefault ? 1 : 0
                            border.color: Qt.alpha(Theme.accent, 0.4)

                            // Icon Box (Left)
                            Rectangle {
                                id: sinkIconBox
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 30
                                radius: 6
                                color: modelData.isDefault ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.06)

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰓃"
                                    color: modelData.isDefault ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                }
                            }

                            // Pin Button (Right)
                            Rectangle {
                                id: sinkPinBtn
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                height: 24
                                radius: 4
                                color: Qt.alpha(Theme.fg, 0.08)
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text { text: "󰤱"; color: Qt.alpha(Theme.fg, 0.6); font.family: Theme.fontFamily; font.pixelSize: 10 }
                                    Text { text: "Pin"; color: Qt.alpha(Theme.fg, 0.6); font.family: Theme.fontFamily; font.pixelSize: 9; font.bold: true }
                                }
                            }

                            // Text Column (Middle - Anchored safely between icon box and pin button)
                            Column {
                                anchors.left: sinkIconBox.right
                                anchors.leftMargin: 10
                                anchors.right: sinkPinBtn.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: modelData.desc
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.isDefault ? "Active" : "Available"
                                    color: modelData.isDefault ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: sinkItemMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    Quickshell.execDetached(["wpctl", "set-default", modelData.id])
                                    audioDevProc.running = true
                                }
                            }
                        }
                    }
                }

                Text {
                    text: "Playback"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }

        // Input Devices Sub-Panel (Source / Microphone)
        Rectangle {
            id: sourcePanel
            width: parent.width
            implicitHeight: sourceCol.implicitHeight + 20
            visible: root.activeSubPanel === "source"
            radius: 16
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)

            Column {
                id: sourceCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 10

                // Header
                Item {
                    width: parent.width
                    height: 32

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Input Devices"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        radius: 6
                        color: sourceGearMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: "󰒓"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: sourceGearMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Quickshell.execDetached(["pavucontrol"])
                        }
                    }
                }

                // Microphone Volume Slider
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 8
                    color: Qt.alpha(Theme.fg, 0.06)

                    Row {
                        id: micVolRow
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.sourceMuted ? "󰍭" : "󰍬"
                            color: root.sourceMuted ? Qt.alpha(Theme.fg, 0.4) : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 16

                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (root.audioSource) root.audioSource.muted = !root.audioSource.muted
                            }
                        }

                        Item {
                            id: micTrackContainer
                            width: parent.width - 90
                            height: parent.height
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Qt.alpha(Theme.fg, 0.15)

                                Rectangle {
                                    width: parent.width * (root.sourceVolume / 100)
                                    height: parent.height
                                    radius: 3
                                    color: root.sourceMuted ? Qt.alpha(Theme.fg, 0.4) : Theme.accent
                                }

                                Rectangle {
                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (root.sourceVolume / 100)) - width / 2))
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: root.sourceMuted ? Qt.alpha(Theme.fg, 0.6) : Theme.accent
                                    border.width: 2
                                    border.color: Theme.bg
                                }
                            }

                            MouseArea {
                                id: micTrackMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: mouse => {
                                    if (pressed && root.audioSource) {
                                        root.audioSource.muted = false
                                        root.audioSource.volume = Math.max(0, Math.min(1, mouse.x / width))
                                    }
                                }
                                onClicked: mouse => {
                                    if (root.audioSource) {
                                        root.audioSource.muted = false
                                        root.audioSource.volume = Math.max(0, Math.min(1, mouse.x / width))
                                    }
                                }
                                onWheel: wheel => {
                                    if (root.audioSource) {
                                        const step = wheel.angleDelta.y > 0 ? 0.02 : -0.02
                                        root.audioSource.muted = false
                                        root.audioSource.volume = Math.max(0, Math.min(1, root.audioSource.volume + step))
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.sourceMuted ? "Muted" : (root.sourceVolume + "%")
                            color: root.sourceMuted ? Qt.alpha(Theme.fg, 0.4) : Qt.alpha(Theme.fg, 0.8)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }

                // Input Devices List
                Column {
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.audioSourcesList

                        Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 44
                            radius: 8
                            color: modelData.isDefault ? Qt.alpha(Theme.accent, 0.18)
                                 : sourceItemMa.containsMouse ? Qt.alpha(Theme.fg, 0.10)
                                 : Qt.alpha(Theme.fg, 0.04)
                            border.width: modelData.isDefault ? 1 : 0
                            border.color: Qt.alpha(Theme.accent, 0.4)

                            // Icon Box (Left)
                            Rectangle {
                                id: sourceIconBox
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 30
                                radius: 6
                                color: modelData.isDefault ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.06)

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰍬"
                                    color: modelData.isDefault ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                }
                            }

                            // Pin Button (Right)
                            Rectangle {
                                id: sourcePinBtn
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                height: 24
                                radius: 4
                                color: Qt.alpha(Theme.fg, 0.08)
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text { text: "󰤱"; color: Qt.alpha(Theme.fg, 0.6); font.family: Theme.fontFamily; font.pixelSize: 10 }
                                    Text { text: "Pin"; color: Qt.alpha(Theme.fg, 0.6); font.family: Theme.fontFamily; font.pixelSize: 9; font.bold: true }
                                }
                            }

                            // Text Column (Middle - Anchored safely between icon box and pin button)
                            Column {
                                anchors.left: sourceIconBox.right
                                anchors.leftMargin: 10
                                anchors.right: sourcePinBtn.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: modelData.desc
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.isDefault ? "Active" : "Available"
                                    color: modelData.isDefault ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: sourceItemMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    Quickshell.execDetached(["wpctl", "set-default", modelData.id])
                                    audioDevProc.running = true
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================= ROW 3: BATTERY & STORAGE CARDS =================
        Row {
            width: parent.width
            spacing: 10

            ControlCard {
                icon: Sys.batteryCharging ? "󰂄" : Sys.battery > 80 ? "󰁹" : Sys.battery > 40 ? "󰁾" : "󰁼"
                titleText: "Battery"
                subText: Sys.hasBattery ? (Sys.battery + "% • " + (root.batteryData.power_profile ? (root.batteryData.power_profile.charAt(0).toUpperCase() + root.batteryData.power_profile.slice(1)) : (Sys.batteryCharging ? "Charging" : "Discharging"))) : "AC Power"
                active: Sys.hasBattery
                expanded: root.activeSubPanel === "battery"
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "battery") ? "" : "battery"
            }

            ControlCard {
                icon: "󰋊"
                titleText: "Storage"
                subText: root.rootPartition ? (root.rootPartition.used + " / " + root.rootPartition.size + " (" + root.rootPartition.usePct + "%)") : (Sys.diskText !== "" ? Sys.diskText : (Sys.disk + "% used"))
                active: true
                expanded: root.activeSubPanel === "storage"
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "storage") ? "" : "storage"
            }
        }

        // ================= SUB-PANEL SLOT 3 (BATTERY & POWER PROFILES) =================
        Rectangle {
            id: batteryPanel
            width: parent.width
            implicitHeight: batCol.implicitHeight + 20
            visible: root.activeSubPanel === "battery"
            radius: 16
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)

            Column {
                id: batCol
                width: parent.width - 24
                x: 12
                y: 10
                spacing: 12

                // Header
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
                        color: Qt.alpha(Theme.fg, 0.04)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.06)

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
                        color: Qt.alpha(Theme.fg, 0.04)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.06)

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
                        border.color: isActive ? Theme.green : Qt.alpha(Theme.fg, 0.08)
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
                        border.color: isActive ? Theme.blue : Qt.alpha(Theme.fg, 0.08)
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
                        border.color: isActive ? Theme.red : Qt.alpha(Theme.fg, 0.08)
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

        // ================= SUB-PANEL SLOT 3 (STORAGE PARTITIONS) =================
        Rectangle {
            id: storagePanel
            width: parent.width
            implicitHeight: storageCol.implicitHeight + 20
            visible: root.activeSubPanel === "storage"
            radius: 16
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)

            Column {
                id: storageCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 10

                // Header
                Item {
                    width: parent.width
                    height: 28

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Disk Partitions"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        radius: 6
                        color: storageRefreshMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: "󰑐"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: storageRefreshMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: storageProc.running = true
                        }
                    }
                }

                // Partition Items List
                Column {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.storagePartitions

                        Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 48
                            radius: 8
                            color: Qt.alpha(Theme.fg, 0.04)
                            border.width: 1
                            border.color: Qt.alpha(Theme.fg, 0.08)

                            Column {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                Item {
                                    width: parent.width
                                    height: 16

                                    Row {
                                        anchors.left: parent.left
                                        spacing: 6

                                        Text {
                                            text: "󰋊"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                        }

                                        Text {
                                            text: modelData.name + " (" + modelData.device + ")"
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        text: modelData.used + " / " + modelData.size + " (" + modelData.usePct + "%)"
                                        color: Qt.alpha(Theme.fg, 0.7)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                // Capacity Bar
                                Rectangle {
                                    width: parent.width
                                    height: 6
                                    radius: 3
                                    color: Qt.alpha(Theme.fg, 0.15)

                                    Rectangle {
                                        width: parent.width * Math.min(1.0, (modelData.usePct / 100))
                                        height: parent.height
                                        radius: 3
                                        color: modelData.usePct > 90 ? Theme.red : modelData.usePct > 75 ? Theme.yellow : Theme.accent
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================= ROW 4: DO NOT DISTURB & WALLPAPER CARDS =================
        Row {
            width: parent.width
            spacing: 10

            ControlCard {
                icon: Sys.dndOn ? "󰂛" : "󰂜"
                titleText: "Do Not Disturb"
                subText: Sys.dndOn ? "Notifications paused" : "Notifications active"
                active: Sys.dndOn
                onCardClicked: Sys.toggleDnd()
            }

            ControlCard {
                icon: "󰸉"
                titleText: "Wallpaper"
                subText: "Set Background"
                active: true
                expanded: root.activeSubPanel === "wallpaper"
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "wallpaper") ? "" : "wallpaper"
            }
        }

        // ================= SUB-PANEL SLOT 4 (WALLPAPER GRID) =================
        Rectangle {
            id: wallpaperPanel
            width: parent.width
            implicitHeight: wallpaperCol.implicitHeight + 20
            visible: root.activeSubPanel === "wallpaper"
            radius: 16
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)

            Column {
                id: wallpaperCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 10

                // Header
                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wallpapers"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }
                }

                // Grid of Wallpaper Thumbnails (4 Columns)
                GridView {
                    width: parent.width
                    height: 220
                    clip: true
                    cellWidth: 122
                    cellHeight: 88

                    model: root.wallpapersList

                    delegate: Item {
                        required property var modelData
                        width: 122
                        height: 88
                        z: wallMa.containsMouse ? 10 : 1

                        Rectangle {
                            id: thumbCard
                            anchors.centerIn: parent
                            width: 114
                            height: 80
                            radius: 10
                            clip: true
                            color: Qt.alpha(Theme.fg, 0.08)

                            scale: wallMa.pressed ? 0.93 : (wallMa.containsMouse ? 1.08 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

                            border.width: wallMa.containsMouse ? 3 : 0
                            border.color: Theme.accent
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Image {
                                anchors.fill: parent
                                source: (root.visible && root.activeSubPanel === "wallpaper" && modelData.path) ? "file://" + modelData.path : ""
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                sourceSize: Qt.size(228, 160)
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

                            // Click feedback checkmark badge
                            Rectangle {
                                anchors.centerIn: parent
                                width: 34
                                height: 34
                                radius: 17
                                color: Theme.accent
                                visible: wallMa.pressed

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰄬"
                                    color: Theme.bg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 20
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
