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

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { root.toggle() }
    }

    property string activeSubPanel: "" // "", "wifi", "bt", "sink", "source"

    onVisibleChanged: {
        if (!visible) {
            activeSubPanel = ""
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--restore"])
        } else {
            Wm.detectDisplayMode()
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
    property string connectingWifiSsid: ""
    property string disconnectingWifiSsid: ""

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

    Timer {
        id: wifiDisconnTimer
        interval: 1500
        onTriggered: {
            root.disconnectingWifiSsid = ""
            root.rescanWifi()
        }
    }

    Process {
        id: wifiConnectProc
        onExited: (exitCode, exitStatus) => {
            const failedSsid = root.connectingWifiSsid
            root.connectingWifiSsid = ""
            wifiConnectTimeoutTimer.stop()
            root.rescanWifi()
            if (exitCode !== 0 && failedSsid !== "") {
                Quickshell.execDetached(["notify-send", "-a", "Wi-Fi", "-i", "network-wireless-offline", "Connection Failed", "Failed to connect to " + failedSsid])
            }
            Sys.refreshNet()
        }
    }

    Timer {
        id: wifiConnectTimeoutTimer
        interval: 15000
        onTriggered: {
            if (root.connectingWifiSsid !== "") {
                const timedOutSsid = root.connectingWifiSsid
                root.connectingWifiSsid = ""
                wifiConnectProc.running = false
                Quickshell.execDetached(["notify-send", "-a", "Wi-Fi", "-i", "network-wireless-offline", "Connection Timeout", "Failed to connect to " + timedOutSsid + " (timeout)"])
            }
        }
    }

    function connectWifi(ssid, password) {
        root.connectingWifiSsid = ssid
        wifiConnectTimeoutTimer.restart()
        const escapedSsid = ssid.replace(/'/g, "'\\''")
        if (password) {
            const escapedPass = password.replace(/'/g, "'\\''")
            wifiConnectProc.command = ["sh", "-c", "nmcli con delete id '" + escapedSsid + "' 2>/dev/null; nmcli dev wifi connect '" + escapedSsid + "' password '" + escapedPass + "'"]
        } else {
            wifiConnectProc.command = ["sh", "-c", "nmcli con up id '" + escapedSsid + "' 2>/dev/null || nmcli dev wifi connect '" + escapedSsid + "'"]
        }
        wifiConnectProc.running = false
        wifiConnectProc.running = true
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
    property string connectingBtMac: ""
    property string disconnectingBtMac: ""
    property bool btScanning: false

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
        id: btDisconnTimer
        interval: 1500
        onTriggered: {
            root.disconnectingBtMac = ""
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

    Process {
        id: btScanProc
        command: ["bluetoothctl", "--timeout", "5", "scan", "on"]
        onExited: (exitCode, exitStatus) => {
            root.btScanning = false
            btProc.running = false
            btProc.running = true
        }
    }

    function scanBluetooth() {
        root.btScanning = true
        btScanProc.running = false
        btScanProc.running = true
        btProc.running = true
    }

    Process {
        id: btConnectProc
        onExited: (exitCode, exitStatus) => {
            root.connectingBtMac = ""
            btProc.running = false
            btProc.running = true
        }
    }

    Timer {
        id: btConnectTimeoutTimer
        interval: 15000
        onTriggered: {
            if (root.connectingBtMac !== "") {
                root.connectingBtMac = ""
                btConnectProc.running = false
            }
        }
    }

    function connectBluetooth(mac) {
        root.connectingBtMac = mac
        btConnectTimeoutTimer.restart()
        btConnectProc.command = ["python3", Sys.scriptPath("bluetooth_info.py"), "--connect", mac]
        btConnectProc.running = false
        btConnectProc.running = true
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
    property var storagePartitions: []
    property var rootPartition: null

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
        storageProc.running = true
    }

    onActiveSubPanelChanged: {
        if (activeSubPanel === "wifi") {
            wifiProc.running = true
            savedWifiProc.running = true
        }
        else if (activeSubPanel === "bt") btProc.running = true
        else if (activeSubPanel === "sink" || activeSubPanel === "source") audioDevProc.running = true
        else if (activeSubPanel === "storage") storageProc.running = true
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
                    radius: 14
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
                    radius: 14
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
                    radius: 14
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
                radius: 14
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
                radius: 14
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

        // Animated Toggle Switch with Settings Window Style
        component AnimatedToggleSwitch: Rectangle {
            id: switchRoot
            property bool checked: false
            signal toggled()

            width: 44
            height: 24
            radius: 12
            color: switchRoot.checked ? (switchMa.containsMouse ? Theme.accentHover : Theme.accent) : (switchMa.containsMouse ? Qt.alpha(Theme.fg, 0.28) : Qt.alpha(Theme.fg, 0.2))
            Behavior on color { ColorAnimation { duration: 150 } }

            // Sliding Thumb (Clean white circular knob)
            Rectangle {
                id: switchThumb
                width: 18
                height: 18
                radius: 9
                anchors.verticalCenter: parent.verticalCenter
                x: switchRoot.checked ? 22 : 4
                color: "#ffffff"

                Behavior on x { NumberAnimation { duration: 150 } }
            }

            MouseArea {
                id: switchMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: switchRoot.toggled()
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
            property bool hasIconToggle: false
            signal cardClicked()
            signal iconClicked()

            width: (mainCol.width - 10) / 2
            height: 58
            radius: 14
            color: cardMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg
            border.width: 1
            border.color: (cardMa.containsMouse || (cardRoot.hasIconToggle && cardIconMa.containsMouse)) ? Qt.alpha(Theme.accent, 0.4) : Sys.customModuleBorder

            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Rectangle {
                    id: iconBox
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38
                    radius: 14
                    color: cardRoot.active || cardRoot.expanded ? Theme.accent : Qt.alpha(Theme.accent, 0.45)
                    opacity: (cardRoot.hasIconToggle && cardIconMa.containsMouse) ? 0.8 : 1.0
                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        anchors.centerIn: parent
                        text: cardRoot.icon
                        color: Sys.customBarBg
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: cardIconMa
                        anchors.fill: parent
                        hoverEnabled: cardRoot.hasIconToggle
                        cursorShape: cardRoot.hasIconToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: cardRoot.hasIconToggle
                        onClicked: cardRoot.iconClicked()
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
                anchors.leftMargin: cardRoot.hasIconToggle ? 48 : 0
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
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
                subText: !Sys.wifiEnabled ? "Disabled" : (Sys.online ? "Connected" : "Disconnected")
                active: Sys.wifiEnabled && Sys.online
                expanded: root.activeSubPanel === "wifi"
                hasIconToggle: true
                onIconClicked: Sys.toggleWifi()
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "wifi") ? "" : "wifi"
            }

            ControlCard {
                icon: Sys.btEnabled ? "󰂯" : "󰂲"
                titleText: "Bluetooth"
                subText: !Sys.btEnabled ? "Disabled" : (() => {
                    const dev = (root.btDevices || []).find(d => d.connected)
                    if (dev) {
                        return dev.name + (dev.battery !== undefined && dev.battery !== null ? " • " + dev.battery + "%" : " (Connected)")
                    }
                    return Sys.btStatus !== "" ? Sys.btStatus : "Enabled"
                })()
                active: Sys.btEnabled
                expanded: root.activeSubPanel === "bt"
                hasIconToggle: true
                onIconClicked: Sys.toggleBluetooth()
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "bt") ? "" : "bt"
            }
        }

        // ================= SUB-PANEL SLOT 1 (WIFI or BLUETOOTH) =================
        // WiFi Sub-Panel
        Rectangle {
            id: wifiPanel
            width: parent.width
            readonly property real targetHeight: wifiCol.implicitHeight + 20
            readonly property bool isExpanded: root.activeSubPanel === "wifi"
            height: isExpanded ? targetHeight : 0
            implicitHeight: height
            visible: height > 0
            radius: 14
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)
            clip: true

            Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            transform: Translate { id: wifiSlide; y: 0 }

            onIsExpandedChanged: {
                if (isExpanded) {
                    wifiSlideAnim.restart()
                }
            }

            ParallelAnimation {
                id: wifiSlideAnim
                NumberAnimation { target: wifiSlide; property: "y"; from: -30; to: 0; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: wifiPanel; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }

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

                        // Wi-Fi On/Off Animated Toggle Switch
                        AnimatedToggleSwitch {
                            checked: Sys.wifiEnabled
                            onToggled: Sys.toggleWifi()
                        }

                        // Rescan Button
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 14
                            color: wifiRescanMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : Qt.alpha(Theme.fg, 0.08)
                            opacity: Sys.wifiEnabled ? 1.0 : 0.4

                            Text {
                                id: wifiRescanIcon
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: (root.wifiScanning || wifiProc.running) ? Theme.accent : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                RotationAnimator on rotation {
                                    running: (root.wifiScanning || wifiProc.running) && Sys.wifiEnabled
                                    from: 0
                                    to: 360
                                    loops: Animation.Infinite
                                    duration: 1000
                                }
                            }
                            MouseArea {
                                id: wifiRescanMa
                                anchors.fill: parent
                                enabled: Sys.wifiEnabled && !root.wifiScanning
                                hoverEnabled: enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.rescanWifi()
                            }
                        }

                        // Settings Button
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 14
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
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["nm-connection-editor"])
                            }
                        }
                    }
                }

                // Wi-Fi Disabled Message Banner
                Rectangle {
                    width: parent.width
                    height: 48
                    radius: 12
                    visible: !Sys.wifiEnabled
                    color: Qt.alpha(Theme.fg, 0.04)

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰤮"
                            color: Qt.alpha(Theme.fg, 0.4)
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Wi-Fi is turned off"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }

                // Networks List
                Flickable {
                    width: parent.width
                    visible: Sys.wifiEnabled
                    height: Math.min(244, wifiListCol.height)
                    contentHeight: wifiListCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: wifiListCol
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: root.wifiNetworks

                            Column {
                                required property var modelData
                                property bool showPass: false
                                readonly property bool isConnecting: root.connectingWifiSsid === modelData.ssid
                                readonly property bool isDisconnecting: root.disconnectingWifiSsid === modelData.ssid
                                width: parent.width
                                spacing: 4

                                function handleConnect() {
                                    if (modelData.inUse || isConnecting || isDisconnecting) return
                                    const isSaved = root.savedWifiList.includes(modelData.ssid)
                                    const isOpen = (modelData.security === "--" || modelData.security === "")
                                    if (isSaved || isOpen) {
                                        root.connectWifi(modelData.ssid)
                                        root.selectedWifiSsid = ""
                                    } else {
                                        root.selectedWifiSsid = (root.selectedWifiSsid === modelData.ssid ? "" : modelData.ssid)
                                    }
                                }

                                Rectangle {
                                    id: wifiItemRow
                                    width: parent.width
                                    height: 44
                                    radius: 14
                                    color: modelData.inUse ? Qt.alpha(Theme.accent, 0.18) : isConnecting ? Qt.alpha(Theme.accent, 0.12) : isDisconnecting ? Qt.alpha(Theme.red, 0.12) : cardItemMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : Qt.alpha(Theme.fg, 0.04)
                                    border.width: (modelData.inUse || isConnecting || isDisconnecting) ? 1 : 0
                                    border.color: isDisconnecting ? Qt.alpha(Theme.red, 0.6) : isConnecting ? Qt.alpha(Theme.accent, 0.6) : Qt.alpha(Theme.accent, 0.4)

                                    MouseArea {
                                        id: cardItemMa
                                        anchors.fill: parent
                                        hoverEnabled: !modelData.inUse && !isConnecting && !isDisconnecting
                                        cursorShape: (!modelData.inUse && !isConnecting && !isDisconnecting) ? Qt.PointingHandCursor : Qt.ArrowCursor
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
                                        radius: 14
                                        color: isDisconnecting ? Qt.alpha(Theme.red, 0.25) : (modelData.inUse || isConnecting) ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.06)

                                        Text {
                                            anchors.centerIn: parent
                                            text: isDisconnecting ? "󰑐" : isConnecting ? "󰑐" : (modelData.signal > 75 ? "󰤨" : modelData.signal > 50 ? "󰤥" : modelData.signal > 25 ? "󰤢" : "󰤟")
                                            color: isDisconnecting ? Theme.red : (modelData.inUse || isConnecting) ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                            RotationAnimator on rotation {
                                                running: isConnecting || isDisconnecting
                                                from: 0
                                                to: 360
                                                loops: Animation.Infinite
                                                duration: 900
                                            }
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
                                            width: isConnecting ? 84 : 62
                                            height: 26
                                            radius: 14
                                            color: modelData.inUse ? Qt.alpha(Theme.fg, 0.06) : connectMa.containsMouse ? Qt.alpha(Theme.accent, 0.35) : Qt.alpha(Theme.accent, 0.22)
                                            border.width: modelData.inUse ? 0 : 1
                                            border.color: Qt.alpha(Theme.accent, 0.4)
                                            opacity: (modelData.inUse || isDisconnecting) ? 0.4 : 1.0

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 4

                                                Text {
                                                    text: "󰑐"
                                                    color: Theme.accent
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    visible: isConnecting
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    RotationAnimator on rotation {
                                                        running: isConnecting
                                                        from: 0
                                                        to: 360
                                                        loops: Animation.Infinite
                                                        duration: 900
                                                    }
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: isConnecting ? "Connecting" : "Connect"
                                                    color: modelData.inUse ? Qt.alpha(Theme.fg, 0.5) : Theme.accent
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                }
                                            }

                                            MouseArea {
                                                id: connectMa
                                                anchors.fill: parent
                                                enabled: !modelData.inUse && !isConnecting && !isDisconnecting
                                                hoverEnabled: enabled
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: handleConnect()
                                            }
                                        }

                                        // Disconnect Button
                                        Rectangle {
                                            width: isDisconnecting ? 88 : 74
                                            height: 26
                                            radius: 14
                                            color: !modelData.inUse ? Qt.alpha(Theme.fg, 0.06) : isDisconnecting ? Qt.alpha(Theme.red, 0.35) : disconnMa.containsMouse ? Qt.alpha(Theme.red, 0.35) : Qt.alpha(Theme.red, 0.22)
                                            border.width: !modelData.inUse ? 0 : 1
                                            border.color: isDisconnecting ? Theme.red : Qt.alpha(Theme.red, 0.4)
                                            opacity: !modelData.inUse ? 0.4 : 1.0

                                            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 4

                                                Text {
                                                    text: "󰑐"
                                                    color: Theme.red
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    visible: isDisconnecting
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    RotationAnimator on rotation {
                                                        running: isDisconnecting
                                                        from: 0
                                                        to: 360
                                                        loops: Animation.Infinite
                                                        duration: 900
                                                    }
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: isDisconnecting ? "Disconnecting" : "Disconnect"
                                                    color: !modelData.inUse ? Qt.alpha(Theme.fg, 0.5) : Theme.red
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                }
                                            }

                                            MouseArea {
                                                id: disconnMa
                                                anchors.fill: parent
                                                enabled: modelData.inUse && !isDisconnecting
                                                hoverEnabled: enabled
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    root.disconnectingWifiSsid = modelData.ssid
                                                    Quickshell.execDetached(["sh", "-c", "nmcli dev disconnect $(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | grep ':wifi' | cut -d: -f1 | head -1) 2>/dev/null || nmcli con down id '" + modelData.ssid.replace(/'/g, "'\\''") + "'"])
                                                    wifiDisconnTimer.restart()
                                                    wifiRescanTimer.restart()
                                                    Sys.refreshNet()
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
                                            text: isConnecting ? "Connecting..." : isDisconnecting ? "Disconnecting..." : modelData.inUse ? ("Connected • " + modelData.signal + "%") : (root.savedWifiList.includes(modelData.ssid) ? "Saved • " : modelData.security !== "--" ? "Secured • " : "Open • ") + modelData.signal + "%"
                                            color: (modelData.inUse || isConnecting) ? Theme.accent : isDisconnecting ? Theme.red : Qt.alpha(Theme.fg, 0.5)
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
                                    radius: 14
                                    color: Qt.alpha(Theme.fg, 0.06)
                                    border.width: 1
                                    border.color: Qt.alpha(Theme.accent, 0.4)

                                    function submitPass() {
                                        const val = passInput.text.trim()
                                        if (val !== "") {
                                            root.connectWifi(modelData.ssid, val)
                                            passInput.text = ""
                                            root.selectedWifiSsid = ""
                                        }
                                    }

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
                                            selectionColor: Theme.accent
                                            selectedTextColor: Theme.bg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            clip: true
                                            selectByMouse: true

                                            onAccepted: passBox.submitPass()

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
                                            radius: 14
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
                                            radius: 14
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: arrowMa.containsMouse ? Theme.accentHover : Theme.accent

                                            Text {
                                                anchors.centerIn: parent
                                                text: isConnecting ? "󰑐" : "󰁔"
                                                color: Theme.bg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14
                                                font.bold: true
                                                RotationAnimator on rotation {
                                                    running: isConnecting
                                                    from: 0
                                                    to: 360
                                                    loops: Animation.Infinite
                                                    duration: 900
                                                }
                                            }

                                            MouseArea {
                                                id: arrowMa
                                                anchors.fill: parent
                                                enabled: !isConnecting
                                                hoverEnabled: enabled
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: passBox.submitPass()
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

        // Bluetooth Sub-Panel
        Rectangle {
            id: btPanel
            width: parent.width
            readonly property real targetHeight: btCol.implicitHeight + 20
            readonly property bool isExpanded: root.activeSubPanel === "bt"
            height: isExpanded ? targetHeight : 0
            implicitHeight: height
            visible: height > 0
            radius: 14
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)
            clip: true

            Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            transform: Translate { id: btSlide; y: 0 }

            onIsExpandedChanged: {
                if (isExpanded) {
                    btSlideAnim.restart()
                }
            }

            ParallelAnimation {
                id: btSlideAnim
                NumberAnimation { target: btSlide; property: "y"; from: -30; to: 0; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: btPanel; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }

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

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        // Bluetooth On/Off Animated Toggle Switch
                        AnimatedToggleSwitch {
                            checked: Sys.btEnabled
                            onToggled: Sys.toggleBluetooth()
                        }

                        // Scan Button
                        Rectangle {
                            height: 26
                            width: root.btScanning ? 75 : 65
                            radius: 14
                            color: btScanMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                            border.width: root.btScanning ? 1 : 0
                            border.color: Qt.alpha(Theme.accent, 0.4)
                            opacity: Sys.btEnabled ? 1.0 : 0.4

                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: root.btScanning ? "󰑐" : "󰂪"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    RotationAnimator on rotation {
                                        running: root.btScanning
                                        from: 0
                                        to: 360
                                        loops: Animation.Infinite
                                        duration: 900
                                    }
                                }
                                Text {
                                    text: root.btScanning ? "Scanning" : "Scan"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: btScanMa
                                anchors.fill: parent
                                enabled: Sys.btEnabled && !root.btScanning
                                hoverEnabled: enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.scanBluetooth()
                            }
                        }
                    }
                }

                // Bluetooth Disabled Message Banner
                Rectangle {
                    width: parent.width
                    height: 48
                    radius: 12
                    visible: !Sys.btEnabled
                    color: Qt.alpha(Theme.fg, 0.04)

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰂲"
                            color: Qt.alpha(Theme.fg, 0.4)
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Bluetooth is turned off"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }

                // Devices List
                Flickable {
                    width: parent.width
                    visible: Sys.btEnabled
                    height: Math.min(236, btListCol.height)
                    contentHeight: btListCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: btListCol
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: root.btDevices

                        Rectangle {
                            id: btItemRow
                            required property var modelData
                            readonly property bool isConnecting: root.connectingBtMac === modelData.mac
                            readonly property bool isDisconnecting: root.disconnectingBtMac === modelData.mac
                            width: parent.width
                            height: 44
                            radius: 14
                            color: modelData.connected ? Qt.alpha(Theme.accent, 0.18) : isConnecting ? Qt.alpha(Theme.accent, 0.12) : isDisconnecting ? Qt.alpha(Theme.red, 0.12) : Qt.alpha(Theme.fg, 0.04)
                            border.width: (modelData.connected || isConnecting || isDisconnecting) ? 1 : 0
                            border.color: isDisconnecting ? Qt.alpha(Theme.red, 0.6) : isConnecting ? Qt.alpha(Theme.accent, 0.6) : Qt.alpha(Theme.accent, 0.4)

                            // Icon Box (Left)
                            Rectangle {
                                id: btIconBox
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 30
                                radius: 14
                                color: isDisconnecting ? Qt.alpha(Theme.red, 0.25) : (modelData.connected || isConnecting) ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.06)

                                Text {
                                    anchors.centerIn: parent
                                    text: isDisconnecting ? "󰑐" : isConnecting ? "󰑐" : (modelData.icon ? modelData.icon : "󰋋")
                                    color: isDisconnecting ? Theme.red : (modelData.connected || isConnecting) ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    RotationAnimator on rotation {
                                        running: isConnecting || isDisconnecting
                                        from: 0
                                        to: 360
                                        loops: Animation.Infinite
                                        duration: 900
                                    }
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
                                    width: isConnecting ? 84 : 62
                                    height: 26
                                    radius: 14
                                    color: modelData.connected ? Qt.alpha(Theme.fg, 0.06) : connectBtMa.containsMouse ? Qt.alpha(Theme.accent, 0.35) : Qt.alpha(Theme.accent, 0.22)
                                    border.width: modelData.connected ? 0 : 1
                                    border.color: Qt.alpha(Theme.accent, 0.4)
                                    opacity: (modelData.connected || isDisconnecting) ? 0.4 : 1.0

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            text: "󰑐"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            visible: isConnecting
                                            anchors.verticalCenter: parent.verticalCenter
                                            RotationAnimator on rotation {
                                                running: isConnecting
                                                from: 0
                                                to: 360
                                                loops: Animation.Infinite
                                                duration: 900
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: isConnecting ? "Connecting" : "Connect"
                                            color: modelData.connected ? Qt.alpha(Theme.fg, 0.5) : Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: connectBtMa
                                        anchors.fill: parent
                                        enabled: !modelData.connected && !isConnecting && !isDisconnecting
                                        hoverEnabled: enabled
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.connectBluetooth(modelData.mac)
                                    }
                                }

                                // Disconnect Button
                                Rectangle {
                                    width: isDisconnecting ? 88 : 74
                                    height: 26
                                    radius: 14
                                    color: !modelData.connected ? Qt.alpha(Theme.fg, 0.06) : isDisconnecting ? Qt.alpha(Theme.red, 0.35) : disconnBtMa.containsMouse ? Qt.alpha(Theme.red, 0.35) : Qt.alpha(Theme.red, 0.22)
                                    border.width: !modelData.connected ? 0 : 1
                                    border.color: isDisconnecting ? Theme.red : Qt.alpha(Theme.red, 0.4)
                                    opacity: !modelData.connected ? 0.4 : 1.0

                                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            text: "󰑐"
                                            color: Theme.red
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            visible: isDisconnecting
                                            anchors.verticalCenter: parent.verticalCenter
                                            RotationAnimator on rotation {
                                                running: isDisconnecting
                                                from: 0
                                                to: 360
                                                loops: Animation.Infinite
                                                duration: 900
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: isDisconnecting ? "Disconnecting" : "Disconnect"
                                            color: !modelData.connected ? Qt.alpha(Theme.fg, 0.5) : Theme.red
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: disconnBtMa
                                        anchors.fill: parent
                                        enabled: modelData.connected && !isDisconnecting
                                        hoverEnabled: enabled
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            root.disconnectingBtMac = modelData.mac
                                            Quickshell.execDetached(["python3", Sys.scriptPath("bluetooth_info.py"), "--disconnect", modelData.mac])
                                            btDisconnTimer.restart()
                                            btRefreshTimer.restart()
                                        }
                                    }
                                }

                                // Remove / Unpair Button (Available for paired or previously connected devices)
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 14
                                    visible: modelData.paired || modelData.connected
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
                                    text: isConnecting ? "Connecting..." : isDisconnecting ? "Disconnecting..." : modelData.connected ? (modelData.battery !== undefined && modelData.battery !== null ? "Connected • " + modelData.battery + "%" : "Connected") : (modelData.paired ? "Paired" : "Disconnected")
                                    color: (isConnecting || modelData.connected) ? Theme.accent : isDisconnecting ? Theme.red : modelData.paired ? Qt.alpha(Theme.fg, 0.7) : Qt.alpha(Theme.fg, 0.4)
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
            readonly property real targetHeight: sinkCol.implicitHeight + 20
            readonly property bool isExpanded: root.activeSubPanel === "sink"
            height: isExpanded ? targetHeight : 0
            implicitHeight: height
            visible: height > 0
            radius: 14
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)
            clip: true

            Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            transform: Translate { id: sinkSlide; y: 0 }

            onIsExpandedChanged: {
                if (isExpanded) {
                    sinkSlideAnim.restart()
                }
            }

            ParallelAnimation {
                id: sinkSlideAnim
                NumberAnimation { target: sinkSlide; property: "y"; from: -30; to: 0; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: sinkPanel; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }

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
                        radius: 14
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
                Flickable {
                    width: parent.width
                    height: Math.min(236, sinkListCol.height)
                    contentHeight: sinkListCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: sinkListCol
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: root.audioSinksList

                        Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 44
                            radius: 14
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
                                radius: 14
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
                                radius: 14
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
            readonly property real targetHeight: sourceCol.implicitHeight + 20
            readonly property bool isExpanded: root.activeSubPanel === "source"
            height: isExpanded ? targetHeight : 0
            implicitHeight: height
            visible: height > 0
            radius: 14
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)
            clip: true

            Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            transform: Translate { id: sourceSlide; y: 0 }

            onIsExpandedChanged: {
                if (isExpanded) {
                    sourceSlideAnim.restart()
                }
            }

            ParallelAnimation {
                id: sourceSlideAnim
                NumberAnimation { target: sourceSlide; property: "y"; from: -30; to: 0; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: sourcePanel; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }

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
                        radius: 14
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
                    radius: 14
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
                Flickable {
                    width: parent.width
                    height: Math.min(236, sourceListCol.height)
                    contentHeight: sourceListCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: sourceListCol
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: root.audioSourcesList

                        Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 44
                            radius: 14
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
                                radius: 14
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
                                radius: 14
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
        }

        // ================= ROW 3: STORAGE & DISPLAY CARDS =================
        Row {
            width: parent.width
            spacing: 10

            ControlCard {
                icon: "󰋊"
                titleText: "Storage"
                subText: root.rootPartition ? (root.rootPartition.used + " / " + root.rootPartition.size + " (" + root.rootPartition.usePct + "%)") : (Sys.diskText !== "" ? Sys.diskText : (Sys.disk + "% used"))
                active: true
                expanded: root.activeSubPanel === "storage"
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "storage") ? "" : "storage"
            }

            ControlCard {
                icon: "󰍹"
                titleText: "Display"
                subText: Wm.displayMode === "mirror" ? "Mirror Mode" : (Wm.displayMode === "extend" ? "Extend Mode" : "Disconnected")
                active: true
                expanded: root.activeSubPanel === "display"
                onCardClicked: root.activeSubPanel = (root.activeSubPanel === "display") ? "" : "display"
            }
        }

        // ================= SUB-PANEL SLOT 3 (STORAGE PARTITIONS) =================
        Rectangle {
            id: storagePanel
            width: parent.width
            readonly property real targetHeight: storageCol.implicitHeight + 20
            readonly property bool isExpanded: root.activeSubPanel === "storage"
            height: isExpanded ? targetHeight : 0
            implicitHeight: height
            visible: height > 0
            radius: 14
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)
            clip: true

            Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            transform: Translate { id: storageSlide; y: 0 }

            onIsExpandedChanged: {
                if (isExpanded) {
                    storageSlideAnim.restart()
                }
            }

            ParallelAnimation {
                id: storageSlideAnim
                NumberAnimation { target: storageSlide; property: "y"; from: -30; to: 0; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: storagePanel; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }

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
                        radius: 14
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
                Flickable {
                    width: parent.width
                    height: Math.min(272, storageListCol.height)
                    contentHeight: storageListCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: storageListCol
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.storagePartitions

                        Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 48
                            radius: 14
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
        }

        // ================= SUB-PANEL SLOT 4 (DISPLAY) =================
        // Display / Projector Sub-Panel
        Rectangle {
            id: displayPanel
            width: parent.width
            readonly property real targetHeight: displayCol.implicitHeight + 20
            readonly property bool isExpanded: root.activeSubPanel === "display"
            height: isExpanded ? targetHeight : 0
            implicitHeight: height
            visible: height > 0
            radius: 14
            color: Qt.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.2)
            clip: true

            Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            transform: Translate { id: displaySlide; y: 0 }

            onIsExpandedChanged: {
                if (isExpanded) {
                    displaySlideAnim.restart()
                }
            }

            ParallelAnimation {
                id: displaySlideAnim
                NumberAnimation { target: displaySlide; property: "y"; from: -30; to: 0; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: displayPanel; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }

            Column {
                id: displayCol
                width: parent.width - 24
                x: 12
                y: 10
                spacing: 12

                // Header
                Row {
                    width: parent.width
                    height: 24

                    Text {
                        text: "Display / Projector Mode"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    text: "Select projection mode for external LCD / Projector:"
                    color: Theme.secondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                // 3 Mode Selector Buttons (Extend, Mirror, Disconnect)
                Row {
                    width: parent.width
                    spacing: 8

                    // Mode 1: Extend
                    Rectangle {
                        id: modeExtend
                        width: (parent.width - 16) / 3
                        height: 40
                        radius: 14
                        readonly property bool isActive: Wm.displayMode === "extend"
                        color: isActive ? Theme.accent : (extendMa.containsMouse ? Qt.alpha(Theme.fg, 0.10) : Qt.alpha(Theme.fg, 0.04))
                        border.width: 1
                        border.color: isActive ? Theme.accent : Qt.alpha(Theme.accent, 0.2)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "󰍹"
                                color: modeExtend.isActive ? Theme.bg : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Extend"
                                color: modeExtend.isActive ? Theme.bg : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: extendMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Wm.setDisplayMode("extend")
                        }
                    }

                    // Mode 2: Mirror
                    Rectangle {
                        id: modeMirror
                        width: (parent.width - 16) / 3
                        height: 40
                        radius: 14
                        readonly property bool isActive: Wm.displayMode === "mirror"
                        color: isActive ? Theme.accent : (mirrorMa.containsMouse ? Qt.alpha(Theme.fg, 0.10) : Qt.alpha(Theme.fg, 0.04))
                        border.width: 1
                        border.color: isActive ? Theme.accent : Qt.alpha(Theme.accent, 0.2)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "󰍺"
                                color: modeMirror.isActive ? Theme.bg : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Mirror"
                                color: modeMirror.isActive ? Theme.bg : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: mirrorMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Wm.setDisplayMode("mirror")
                        }
                    }

                    // Mode 3: Disconnect
                    Rectangle {
                        id: modeDisconn
                        width: (parent.width - 16) / 3
                        height: 40
                        radius: 14
                        readonly property bool isActive: Wm.displayMode === "off"
                        color: isActive ? Theme.accent : (disconnDisplayMa.containsMouse ? Qt.alpha(Theme.fg, 0.10) : Qt.alpha(Theme.fg, 0.04))
                        border.width: 1
                        border.color: isActive ? Theme.accent : Qt.alpha(Theme.accent, 0.2)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "󰍻"
                                color: modeDisconn.isActive ? Theme.bg : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Disconnect"
                                color: modeDisconn.isActive ? Theme.bg : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: disconnDisplayMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Wm.setDisplayMode("off")
                        }
                    }
                }
            }
        }


        // ================= ROW 5: DO NOT DISTURB & QUICK TOOLS (EYE PROTECTION & KEEP AWAKE) =================
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

            // Right Box: 2 Icon-Only Buttons for Eye Protection & Keep Awake
            Row {
                width: (parent.width - 10) / 2
                height: 58
                spacing: 10

                // Eye Protection Icon Button
                Rectangle {
                    id: eyeBtn
                    width: (parent.width - 10) / 2
                    height: 58
                    radius: 14
                    color: Sys.eyeProtectionOn ? Qt.alpha(Theme.accent, 0.25) : (eyeMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                    border.width: 1
                    border.color: Sys.eyeProtectionOn ? Theme.accent : (eyeMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Sys.customModuleBorder)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: eyeMa.containsMouse ? 6 : 0
                        text: "󰃠"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 120 } }
                    }

                    // Text-only Tooltip attached flush to top inside edge
                    Text {
                        id: eyeText
                        visible: eyeMa.containsMouse
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Eye Protection"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: eyeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Sys.toggleEyeProtection()
                    }
                }

                // Keep Awake Icon Button
                Rectangle {
                    id: cafBtn
                    width: (parent.width - 10) / 2
                    height: 58
                    radius: 14
                    color: Sys.caffeineOn ? Qt.alpha(Theme.accent, 0.25) : (cafMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                    border.width: 1
                    border.color: Sys.caffeineOn ? Theme.accent : (cafMa.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Sys.customModuleBorder)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: cafMa.containsMouse ? 6 : 0
                        text: "󰅶"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 120 } }
                    }

                    // Text-only Tooltip attached flush to top inside edge
                    Text {
                        id: cafText
                        visible: cafMa.containsMouse
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Keep Awake"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: cafMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Sys.toggleCaffeine()
                    }
                }
            }
        }
    }
}
