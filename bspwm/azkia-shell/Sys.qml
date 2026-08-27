pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Lightweight system metrics: cpu/mem/disk on a 3s tick, network on 10s.
Singleton {
    id: root

    property bool isLocked: false
    property bool autoLockEnabled: true
    property int autoLockTimeout: 180
    property int autoSleepTimeout: 120
    property string currentWallpaper: ""

    // Dynamic Bar & Module Styling Properties
            property var leftModules: ["launcher", "tags", "title"]
    property var centerModules: ["clock", "media"]
    property var rightModules: ["cpu", "ram", "volume", "brightness", "battery", "screenshot", "bell", "clipboard", "control_center", "tray", "power_button"]
    property var allAvailableModules: ["launcher", "tags", "title", "clock", "media", "cpu", "ram", "volume", "brightness", "battery", "screenshot", "bell", "clipboard", "control_center", "tray", "power_button"]
    property int barRadius: 12
    property int moduleRadius: 10
    property int barHeight: 34
    property int launcherIconSize: 21
    property int barMarginTop: 5
    property int barMarginBottom: 0
    property int barMarginLeft: 8
    property int barMarginRight: 8

    onBarHeightChanged: root.updateBspwmPadding()
    onBarMarginTopChanged: root.updateBspwmPadding()
    onBarMarginBottomChanged: root.updateBspwmPadding()

    function updateBspwmPadding() {
        let totalTop = root.barHeight + root.barMarginTop + root.barMarginBottom
        Quickshell.execDetached(["bspc", "config", "top_padding", totalTop.toString()])
    }
    property color customBarBg: Theme.bg
    property color customModuleBg: Qt.alpha(Theme.fg, 0.09)
    property color customModuleHoverBg: Qt.alpha(Theme.fg, 0.20)
    property color customModuleActiveBg: Qt.alpha(Theme.accent, 0.22)
    property color customModuleBorder: Qt.alpha(Theme.fg, 0.18)
    property color customModuleIconColor: customColor1
    property color customColor1: "#c6a0f6"
    property color customColor2: "#8aadf4"
    property color customColor3: "#8bd5ca"
    property color customColor4: "#a6da95"
    property color customColor5: "#eed49f"
    property color customColor6: "#f5a97f"
    property color customColor7: "#ed8796"

    // Dynamic Paths & Helpers for Portability
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string defaultAvatar: Qt.resolvedUrl("assets/avatar.png").toString()
    readonly property string defaultLauncherLogo: Qt.resolvedUrl("assets/azkia-shell-logo.svg").toString()
    readonly property string defaultWallpaperDir: homeDir + "/.config/bspwm/wallpapers"

    function scriptPath(name) {
        return Qt.resolvedUrl("scripts/" + name).toString().replace("file://", "")
    }

    // Customizable Appearance Properties
    property string userAvatar: defaultAvatar
    property string launcherLogo: defaultLauncherLogo
    property string wallpaperDir: defaultWallpaperDir

    FileView {
        id: appearanceWatcher
        path: Qt.resolvedUrl("appearance.json").toString().replace("file://", "")
        watchChanges: true
        onTextChanged: root.parseAppearance()
        onLoaded: root.parseAppearance()
    }

    function parseAppearance() {
        try {
            const txt = (typeof appearanceWatcher.text === "function") ? appearanceWatcher.text() : (appearanceWatcher.text || "")
            if (!txt) return
            const data = JSON.parse(txt)
            if (data.userAvatar) root.userAvatar = data.userAvatar.replace("~", homeDir)
            if (data.launcherLogo) root.launcherLogo = data.launcherLogo.replace("~", homeDir)
            if (data.wallpaperDir) root.wallpaperDir = data.wallpaperDir.replace("~", homeDir)
            else root.wallpaperDir = defaultWallpaperDir
            if (data.barRadius !== undefined) root.barRadius = data.barRadius
            if (data.moduleRadius !== undefined) root.moduleRadius = data.moduleRadius
            if (data.barHeight !== undefined) root.barHeight = data.barHeight
            if (data.launcherIconSize !== undefined) root.launcherIconSize = data.launcherIconSize
            if (data.barMarginTop !== undefined) root.barMarginTop = data.barMarginTop
            if (data.barMarginBottom !== undefined) root.barMarginBottom = data.barMarginBottom
            if (data.barMarginLeft !== undefined) root.barMarginLeft = data.barMarginLeft
            if (data.barMarginRight !== undefined) root.barMarginRight = data.barMarginRight
            if (data.autoLockEnabled !== undefined) root.autoLockEnabled = data.autoLockEnabled
            if (data.autoLockTimeout !== undefined) root.autoLockTimeout = data.autoLockTimeout
            if (data.autoSleepTimeout !== undefined) root.autoSleepTimeout = data.autoSleepTimeout
            if (data.leftModules && Array.isArray(data.leftModules)) root.leftModules = data.leftModules
            if (data.centerModules && Array.isArray(data.centerModules)) root.centerModules = data.centerModules
            if (data.rightModules && Array.isArray(data.rightModules)) root.rightModules = data.rightModules
            if (data.customBarBg) root.customBarBg = data.customBarBg
            if (data.customModuleBg) root.customModuleBg = data.customModuleBg
            if (data.customModuleHoverBg) root.customModuleHoverBg = data.customModuleHoverBg
            if (data.customModuleActiveBg) root.customModuleActiveBg = data.customModuleActiveBg
            if (data.customModuleIconColor) root.customModuleIconColor = data.customModuleIconColor
            if (data.customColor1) root.customColor1 = data.customColor1
            if (data.customColor2) root.customColor2 = data.customColor2
            if (data.customColor3) root.customColor3 = data.customColor3
            if (data.customColor4) root.customColor4 = data.customColor4
            if (data.customColor5) root.customColor5 = data.customColor5
            if (data.customColor6) root.customColor6 = data.customColor6
            if (data.customColor7) root.customColor7 = data.customColor7
        } catch (e) {}
    }

    Process {
        id: saveAppearanceProc
    }

    Process {
        id: bspwmBorderProc
    }

    function updateBspwmBorderColor(col) {
        if (!col) return
        let hexStr = col.toString()
        bspwmBorderProc.command = ["python3", root.scriptPath("bspwm_editor.py"), "--set-border-color", hexStr]
        bspwmBorderProc.running = false
        bspwmBorderProc.running = true
    }


    function setAvatar(path) {
        if (!path) return
        let cleanPath = path.trim()
        if (!cleanPath.startsWith("file://") && !cleanPath.startsWith("http")) {
            cleanPath = "file://" + cleanPath
        }
        root.userAvatar = cleanPath
        root.saveAppearance()
    }

    function setLauncherLogo(path) {
        if (!path) return
        let cleanPath = path.trim()
        if (!cleanPath.startsWith("file://") && !cleanPath.startsWith("http")) {
            cleanPath = "file://" + cleanPath
        }
        root.launcherLogo = cleanPath
        root.saveAppearance()
    }

    function setWallpaperDir(path) {
        if (!path) return
        let cleanPath = path.trim()
        root.wallpaperDir = cleanPath
        root.saveAppearance()
    }

    function resetWallpaperDir() {
        root.wallpaperDir = defaultWallpaperDir
        root.saveAppearance()
    }

    function getModuleName(id) {
        const map = {
            "launcher": "Application Launcher",
            "tags": "Workspace Tags",
            "title": "Active Window Title",
            "clock": "Digital Clock",
            "media": "Media Player Widget",
            "cpu": "CPU Monitor",
            "ram": "RAM Monitor",
            "volume": "Volume Control",
            "brightness": "Brightness Control",
            "battery": "Battery Monitor",
            "screenshot": "Screenshot Tool",
            "bell": "Notification Bell",
            "clipboard": "Clipboard Manager",
            "control_center": "Control Center",
            "tray": "System Tray",
            "power_button": "Power Button"
        }
        return map[id] || id
    }

    function getModuleIcon(id) {
        const map = {
            "launcher": "󰍉",
            "tags": "󰏃",
            "title": "󰖲",
            "clock": "󰥔",
            "media": "󰎈",
            "cpu": "󰍛",
            "ram": "󰘚",
            "volume": "󰕾",
            "brightness": "󰃠",
            "battery": "󰁹",
            "screenshot": "󰄄",
            "bell": "󰂚",
            "clipboard": "󰅍",
            "control_center": "󰒓",
            "tray": "󰄨",
            "power_button": "󰐥"
        }
        return map[id] || "󰅍"
    }



    
        function setModules(left, center, right) {
        root.leftModules = left
        root.centerModules = center
        root.rightModules = right
        root.saveAppearance()
    }

    function resetModulePositions() {
        root.leftModules = ["launcher", "tags", "title"]
        root.centerModules = ["clock", "media"]
        root.rightModules = ["cpu", "ram", "volume", "brightness", "battery", "screenshot", "bell", "clipboard", "control_center", "tray", "power_button"]
        root.saveAppearance()
    }

    function moveClusterModuleUp(clusterKey, index) {
        let left = Array.from(root.leftModules)
        let center = Array.from(root.centerModules)
        let right = Array.from(root.rightModules)
        let arr = clusterKey === "left" ? left : (clusterKey === "center" ? center : right)
        if (index > 0 && index < arr.length) {
            let temp = arr[index]
            arr[index] = arr[index - 1]
            arr[index - 1] = temp
            root.setModules(left, center, right)
        }
    }

    function moveClusterModuleDown(clusterKey, index) {
        let left = Array.from(root.leftModules)
        let center = Array.from(root.centerModules)
        let right = Array.from(root.rightModules)
        let arr = clusterKey === "left" ? left : (clusterKey === "center" ? center : right)
        if (index >= 0 && index < arr.length - 1) {
            let temp = arr[index]
            arr[index] = arr[index + 1]
            arr[index + 1] = temp
            root.setModules(left, center, right)
        }
    }

    function removeClusterModule(clusterKey, index) {
        let left = Array.from(root.leftModules)
        let center = Array.from(root.centerModules)
        let right = Array.from(root.rightModules)
        let arr = clusterKey === "left" ? left : (clusterKey === "center" ? center : right)
        if (index >= 0 && index < arr.length) {
            arr.splice(index, 1)
            root.setModules(left, center, right)
        }
    }

        function getModuleCluster(id) {
        if ((root.leftModules || []).indexOf(id) !== -1) return "Left Cluster"
        if ((root.centerModules || []).indexOf(id) !== -1) return "Center Cluster"
        if ((root.rightModules || []).indexOf(id) !== -1) return "Right Cluster"
        return "Available"
    }

function addClusterModule(clusterKey, id) {
        let left = Array.from(root.leftModules)
        let center = Array.from(root.centerModules)
        let right = Array.from(root.rightModules)

        left = left.filter(item => item !== id)
        center = center.filter(item => item !== id)
        right = right.filter(item => item !== id)

        if (clusterKey === "left") left.push(id)
        else if (clusterKey === "center") center.push(id)
        else if (clusterKey === "right") right.push(id)

        root.setModules(left, center, right)
    }

function setBarRadius(val) {
        root.barRadius = Math.max(0, Math.min(24, Math.round(val)))
        root.saveAppearance()
    }

    function setModuleRadius(val) {
        root.moduleRadius = Math.max(0, Math.min(16, Math.round(val)))
        root.saveAppearance()
    }

    function setBarHeight(val) {
        root.barHeight = Math.max(30, Math.min(50, Math.round(val)))
        root.saveAppearance()
    }

    function setLauncherIconSize(val) {
        root.launcherIconSize = Math.max(12, Math.min(36, Math.round(val)))
        root.saveAppearance()
    }

    function setBarMarginTop(val) {
        root.barMarginTop = Math.max(0, Math.min(30, Math.round(val)))
        root.saveAppearance()
    }

    function setBarMarginBottom(val) {
        root.barMarginBottom = Math.max(0, Math.min(30, Math.round(val)))
        root.saveAppearance()
    }

    function setBarMarginLeft(val) {
        root.barMarginLeft = Math.max(0, Math.min(50, Math.round(val)))
        root.saveAppearance()
    }

    function setBarMarginRight(val) {
        root.barMarginRight = Math.max(0, Math.min(50, Math.round(val)))
        root.saveAppearance()
    }

    function setCustomBarBg(val) {
        root.customBarBg = val
        root.saveAppearance()
    }

    function setCustomModuleBg(val) {
        root.customModuleBg = val
        root.saveAppearance()
    }

    function setCustomModuleHoverBg(val) {
        root.customModuleHoverBg = val
        root.saveAppearance()
    }

    function setCustomModuleActiveBg(val) {
        root.customModuleActiveBg = val
        root.saveAppearance()
    }

    function setCustomColor(index, val) {
        if (index === 1) { root.customColor1 = val; root.customModuleIconColor = val; root.updateBspwmBorderColor(val); }
        else if (index === 2) root.customColor2 = val
        else if (index === 3) root.customColor3 = val
        else if (index === 4) root.customColor4 = val
        else if (index === 5) root.customColor5 = val
        else if (index === 6) root.customColor6 = val
        else if (index === 7) root.customColor7 = val
        root.saveAppearance()
    }

    function setAutoLockEnabled(val) {
        root.autoLockEnabled = val
        root.saveAppearance()
    }

    function setAutoLockTimeout(val) {
        root.autoLockTimeout = Math.max(30, Math.min(3600, Math.round(val)))
        root.saveAppearance()
    }

    function setAutoSleepTimeout(val) {
        root.autoSleepTimeout = Math.max(30, Math.min(3600, Math.round(val)))
        root.saveAppearance()
    }

    function saveAppearance() {
        const data = {
            userAvatar: root.userAvatar,
            launcherLogo: root.launcherLogo,
            wallpaperDir: root.wallpaperDir,
            barRadius: root.barRadius,
            moduleRadius: root.moduleRadius,
            barHeight: root.barHeight,
            launcherIconSize: root.launcherIconSize,
            barMarginTop: root.barMarginTop,
            barMarginBottom: root.barMarginBottom,
            barMarginLeft: root.barMarginLeft,
            barMarginRight: root.barMarginRight,
            autoLockEnabled: root.autoLockEnabled,
            autoLockTimeout: root.autoLockTimeout,
            autoSleepTimeout: root.autoSleepTimeout,
            leftModules: root.leftModules,
            centerModules: root.centerModules,
            rightModules: root.rightModules,
            customBarBg: root.customBarBg.toString(),
            customModuleBg: root.customModuleBg.toString(),
            customModuleHoverBg: root.customModuleHoverBg.toString(),
            customModuleActiveBg: root.customModuleActiveBg.toString(),
            customModuleIconColor: root.customModuleIconColor.toString(),
            customColor1: root.customColor1.toString(),
            customColor2: root.customColor2.toString(),
            customColor3: root.customColor3.toString(),
            customColor4: root.customColor4.toString(),
            customColor5: root.customColor5.toString(),
            customColor6: root.customColor6.toString(),
            customColor7: root.customColor7.toString()
        }
        const jsonStr = JSON.stringify(data)
        const jsonPath = Qt.resolvedUrl("appearance.json").toString().replace("file://", "")
        saveAppearanceProc.command = ["sh", "-c", `cat << 'EOF' > ${jsonPath}\n${jsonStr}\nEOF`]
        saveAppearanceProc.running = true
    }

    function restartShell() {
        Quickshell.execDetached(["bash", root.scriptPath("restart_shell.sh")])
    }

    FileView {
        id: fehbgWatcher
        path: homeDir + "/.fehbg"
        watchChanges: true
        onTextChanged: root.parseFehbg()
        onLoaded: root.parseFehbg()
    }

    function parseFehbg() {
        const txt = (typeof fehbgWatcher.text === "function") ? fehbgWatcher.text() : (fehbgWatcher.text || "")
        if (txt) {
            const m = txt.match(/'([^']+)'/) || txt.match(/"([^"]+)"/)
            if (m && m[1]) {
                let cleanPath = m[1].replace("~", homeDir)
                if (!cleanPath.startsWith("file://") && !cleanPath.startsWith("http")) {
                    cleanPath = "file://" + cleanPath
                }
                root.currentWallpaper = cleanPath
                return
            }
        }
        if (!root.currentWallpaper) {
            root.currentWallpaper = "file://" + homeDir + "/.config/bspwm/wallpapers/Default.png"
        }
    }

    function setWallpaper(filePath) {
        if (!filePath) return
        let rawPath = String(filePath).replace("file://", "")
        let cleanPath = rawPath.replace("~", homeDir)
        root.currentWallpaper = "file://" + cleanPath
        Quickshell.execDetached(["python3", Sys.scriptPath("wallpaper.py"), "--set", rawPath])
    }

    property real cpu: 0
    property real mem: 0
    property real disk: 0
    property string diskText: ""
    property string uptimeText: ""
    property string userName: ""
    property bool btEnabled: false
    property string btStatus: "No devices"
    property bool hasBattery: false
    property real battery: 0
    property bool batteryCharging: false
    property string netName: ""
    property string netType: ""
    property bool vpnOn: false
    property string vpnName: ""
    property string lastActivePlayerIdentity: ""
    property var cavaValues: []

    Process {
        id: cavaProc
        command: ["python3", root.scriptPath("cava_daemon.py")]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (Array.isArray(parsed)) {
                        root.cavaValues = parsed
                    }
                } catch(e) {}
            }
        }
    }

    readonly property string netIcon: vpnOn ? "󰦝"
                                    : netType.indexOf("wireless") !== -1 ? "󰤨"
                                    : netType.indexOf("ethernet") !== -1 ? "󰈀"
                                    : "󰤭"
    readonly property bool online: netName !== ""

    property var _prev: ({ idle: 0, total: 0 })

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statProc.running = true
    }

    Process {
        id: statProc
        command: ["sh", "-c",
            "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable)' /proc/meminfo; df -h / | tail -1; uptime -p; whoami; bluetoothctl show 2>/dev/null | grep 'Powered:'; " +
            "for b in /sys/class/power_supply/BAT*; do [ -r \"$b/capacity\" ] && echo \"BAT $(cat \"$b/capacity\") $(cat \"$b/status\")\" && break; done; true"]
        stdout: StdioCollector {
            onStreamFinished: root.parseStat(text)
        }
    }

    function parseStat(t) {
        const lines = t.trim().split("\n")
        let memTotal = 0, memAvail = 0, foundBattery = false
        for (const line of lines) {
            const l = line.trim()
            if (l.startsWith("cpu ")) {
                const f = l.split(/\s+/).slice(1).map(Number)
                const idle = f[3] + (f[4] || 0)
                const total = f.reduce((a, b) => a + b, 0)
                const dIdle = idle - _prev.idle
                const dTotal = total - _prev.total
                if (_prev.total > 0 && dTotal > 0)
                    cpu = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)))
                _prev = { idle: idle, total: total }
            } else if (l.startsWith("MemTotal:")) {
                memTotal = parseInt(l.split(/\s+/)[1])
            } else if (l.startsWith("MemAvailable:")) {
                memAvail = parseInt(l.split(/\s+/)[1])
            } else if (l.startsWith("BAT ")) {
                const parts = l.split(/\s+/)
                foundBattery = true
                battery = parseInt(parts[1])
                batteryCharging = parts[2] === "Charging"
            } else if (l.startsWith("up ")) {
                uptimeText = l
            } else if (l.includes("Powered:")) {
                btEnabled = l.includes("yes")
                btStatus = btEnabled ? "Enabled" : "Disabled"
            } else if (l.startsWith("/")) {
                // df output e.g. /dev/nvme0n1p2 238G 54G 181G 23% /
                const parts = l.split(/\s+/)
                if (parts.length >= 5) {
                    const used = parts[2]
                    const total = parts[1]
                    const pcent = parts[4]
                    diskText = used + " / " + total + " (" + pcent + ")"
                    disk = parseInt(pcent)
                }
            } else if (l.length > 0 && !l.includes(":") && !l.includes(" ")) {
                userName = l
            }
        }
        if (memTotal > 0)
            mem = 100 * (1 - memAvail / memTotal)
        hasBattery = foundBattery
    }

    function toggleBluetooth() {
        Quickshell.execDetached(["sh", "-c", "if bluetoothctl show | grep -q 'Powered: yes'; then bluetoothctl power off; else bluetoothctl power on; fi"])
        btRefresh.restart()
    }

    Timer {
        id: btRefresh
        interval: 500
        onTriggered: statProc.running = true
    }

    property bool capsOn: false
    property bool dndOn: false
    property var historyNotifications: []
    readonly property int notifCount: historyNotifications.length

    signal notificationReceived(var notifData)

    function addNotification(notif) {
        const icon = notif.appIcon || notif.image || ""
        const app = notif.appName || "Notification"
        const title = notif.summary || "Notification"
        const body = notif.body || ""
        const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })

        const item = {
            id: notif.id || (Date.now() + Math.random()),
            appName: app,
            appIcon: icon,
            summary: title,
            body: body,
            time: timeStr,
            timestamp: Date.now()
        }

        historyNotifications = [item, ...historyNotifications].slice(0, 15)
        notificationReceived(item)
    }

    function removeNotification(id) {
        historyNotifications = historyNotifications.filter(n => n.id !== id)
    }

    function clearNotifications() {
        historyNotifications = []
    }

    function toggleDnd() {
        dndOn = !dndOn
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: capsProc.running = true
    }

    Process {
        id: capsProc
        command: ["sh", "-c", "xset q | awk '/Caps Lock/{print $4}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                root.capsOn = lines[0] === "on"
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: netProc.running = true
    }

    // primary transport + vpn tracked separately: a vpn/wireguard/tun
    // connection rides ON a transport, it isn't one
    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"]
        stdout: StdioCollector {
            onStreamFinished: {
                let name = "", type = "", vName = "", vOn = false
                for (const line of text.trim().split("\n")) {
                    const i = line.lastIndexOf(":")
                    if (i <= 0)
                        continue
                    const n = line.slice(0, i), t = line.slice(i + 1)
                    if (t === "loopback")
                        continue
                    if (t === "vpn" || t === "wireguard" || t === "tun") {
                        vOn = true
                        vName = n
                    } else if (name === "") {
                        name = n
                        type = t
                    }
                }
                root.netName = name
                root.netType = type
                root.vpnOn = vOn
                root.vpnName = vName
            }
        }
    }

    onIsLockedChanged: root.syncLockState()

    function syncLockState() {
        updateLockStateProc.command = ["sh", "-c", "echo " + (isLocked ? "1" : "0") + " > /tmp/azkia_lock_state"]
        updateLockStateProc.running = false
        updateLockStateProc.running = true
    }

    Process {
        id: updateLockStateProc
    }

    Process {
        id: idleDaemonProc
        command: ["python3", Sys.scriptPath("idle_daemon.py")]
        running: true
    }

    Component.onCompleted: {
        root.parseFehbg()
        root.syncLockState()
        root.updateBspwmPadding()
    }
}
