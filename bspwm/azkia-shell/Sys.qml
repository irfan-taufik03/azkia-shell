pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Lightweight system metrics: cpu/mem/disk on a 3s tick, network on 10s.
Singleton {
    id: root

    property bool isLocked: false
    property bool isPolkitActive: false
    property bool autoLockEnabled: true
    property int autoLockTimeout: 180
    property int autoSleepTimeout: 120
    property bool autoSuspendEnabled: false
    property int autoSuspendTimeout: 600
    property string currentWallpaper: ""


    // Dynamic Bar & Module Styling Properties
            property var leftModules: ["launcher", "tags", "title"]
    property var centerModules: ["clock"]
    property var rightModules: ["system_monitor", "volume", "brightness", "battery", "screenshot", "bell", "clipboard", "control_center", "tray", "power_button"]
    property var allAvailableModules: ["launcher", "tags", "title", "clock", "media", "system_monitor", "volume", "brightness", "battery", "screenshot", "bell", "clipboard", "control_center", "tray", "power_button"]
    property int barRadius: 13
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
    property color customModuleBg: "#3b4252"
    property color customModuleHoverBg: "#454d60"
    property color customModuleActiveBg: Qt.alpha(Theme.accent, 0.22)
    property color customModuleBorder: Theme.altbg
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
            if (data.autoSuspendEnabled !== undefined) root.autoSuspendEnabled = data.autoSuspendEnabled
            if (data.autoSuspendTimeout !== undefined) root.autoSuspendTimeout = data.autoSuspendTimeout
            if (data.leftModules && Array.isArray(data.leftModules)) root.leftModules = data.leftModules
            if (data.centerModules && Array.isArray(data.centerModules)) root.centerModules = data.centerModules
            if (data.rightModules && Array.isArray(data.rightModules)) root.rightModules = data.rightModules
            if (data.customBarBg) root.customBarBg = data.customBarBg
            if (data.customModuleBg) root.customModuleBg = data.customModuleBg
            if (data.customModuleHoverBg) root.customModuleHoverBg = data.customModuleHoverBg
            if (data.customModuleActiveBg) root.customModuleActiveBg = data.customModuleActiveBg
            if (data.customModuleBorder) root.customModuleBorder = data.customModuleBorder
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
            "clock": "Dash",
            "dash": "Dash",
            "media": "Media Player Widget",
            "system_monitor": "System Monitor",
            "cpu": "System Monitor",
            "ram": "System Monitor",
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
            "system_monitor": "󰻠",
            "cpu": "󰻠",
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
        root.centerModules = ["clock"]
        root.rightModules = ["cpu", "volume", "brightness", "battery", "screenshot", "bell", "clipboard", "control_center", "tray", "power_button"]
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

    function setAutoSuspendEnabled(val) {
        root.autoSuspendEnabled = val
        root.saveAppearance()
    }

    function setAutoSuspendTimeout(val) {
        root.autoSuspendTimeout = Math.max(60, Math.min(7200, Math.round(val)))
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
            autoSuspendEnabled: root.autoSuspendEnabled,
            autoSuspendTimeout: root.autoSuspendTimeout,
            leftModules: root.leftModules,
            centerModules: root.centerModules,
            rightModules: root.rightModules,
            customBarBg: root.customBarBg.toString(),
            customModuleBg: root.customModuleBg.toString(),
            customModuleHoverBg: root.customModuleHoverBg.toString(),
            customModuleActiveBg: root.customModuleActiveBg.toString(),
            customModuleBorder: root.customModuleBorder.toString(),
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
    property real swap: 0
    property string diskText: ""
    property string uptimeText: ""
    property string userName: ""
    property string distroName: "Linux"

    readonly property var distroMap: [
        { key: "fedora",   name: "Fedora",       icon: "\uf30a", color: "#51a2da" },
        { key: "debian",   name: "Debian",       icon: "\uf306", color: "#bd93f9" },
        { key: "cachy",    name: "CachyOS",      icon: "\uf303", color: "#00d084" },
        { key: "arch",     name: "Arch Linux",   icon: "\uf303", color: "#1793d1" },
        { key: "ubuntu",   name: "Ubuntu",       icon: "\uf31b", color: "#e95420" },
        { key: "manjaro",  name: "Manjaro",      icon: "\uf312", color: "#35bf5c" },
        { key: "mint",     name: "Linux Mint",   icon: "\uf30e", color: "#87cf3e" },
        { key: "nixos",    name: "NixOS",        icon: "\uf313", color: "#7ebae4" },
        { key: "gentoo",   name: "Gentoo",       icon: "\uf30d", color: "#bd93f9" },
        { key: "suse",     name: "openSUSE",     icon: "\uf314", color: "#73ba25" },
        { key: "pop",      name: "Pop!_OS",      icon: "\uf32a", color: "#48b9c7" },
        { key: "void",     name: "Void Linux",   icon: "\uf32e", color: "#478061" },
        { key: "kali",     name: "Kali Linux",   icon: "\uf327", color: "#557cda" },
        { key: "alpine",   name: "Alpine Linux", icon: "\uf300", color: "#0d597f" }
    ]

    function _getDistroEntry(raw) {
        if (!raw) return null
        const d = raw.toLowerCase()
        return distroMap.find(item => d.includes(item.key)) || null
    }

    function getShortDistro(raw) {
        const entry = _getDistroEntry(raw)
        if (entry) return entry.name
        return raw ? raw.split(/\s+GNU\/Linux|\s+\d|\s+\(/i)[0].trim() || "Linux" : "Linux"
    }

    function getDistroIcon(raw) {
        const entry = _getDistroEntry(raw)
        return entry ? entry.icon : "\uf17c"
    }

    function getDistroColor(raw) {
        const entry = _getDistroEntry(raw)
        return entry ? entry.color : "#51a2da"
    }

    function formatUptime(raw) {
        if (!raw) return "0m"
        return raw.replace(/^up\s+/, "")
                  .replace(/ hours?/, "h")
                  .replace(/ minutes?/, "m")
                  .replace(/ days?/, "d")
                  .replace(/,/g, "")
    }

    property bool btEnabled: false
    property string btStatus: "No devices"
    property bool wifiEnabled: true
    property bool hasBattery: false
    property real battery: 0
    property bool batteryCharging: false
    property string netName: ""
    property string netType: ""
    property string wifiName: ""
    property string _lastWifiName: ""
    property bool _wifiInitialized: false
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

    readonly property string netIcon: !wifiEnabled && (netType === "" || netType.indexOf("wireless") !== -1) ? "󰤮"
                                    : vpnOn ? "󰦝"
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
            "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree)' /proc/meminfo; df -h / | tail -1; uptime -p; whoami; grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null; bluetoothctl show 2>/dev/null | grep 'Powered:'; echo \"WIFI:$(nmcli radio wifi 2>/dev/null)\"; " +
            "for b in /sys/class/power_supply/BAT*; do [ -r \"$b/capacity\" ] && echo \"BAT $(cat \"$b/capacity\") $(cat \"$b/status\")\" && break; done; true"]
        stdout: StdioCollector {
            onStreamFinished: root.parseStat(text)
        }
    }

    function parseStat(t) {
        const lines = t.trim().split("\n")
        let memTotal = 0, memAvail = 0, swapTotal = 0, swapFree = 0, foundBattery = false
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
            } else if (l.startsWith("SwapTotal:")) {
                swapTotal = parseInt(l.split(/\s+/)[1])
            } else if (l.startsWith("SwapFree:")) {
                swapFree = parseInt(l.split(/\s+/)[1])
            } else if (l.startsWith("BAT ")) {
                const parts = l.split(/\s+/)
                foundBattery = true
                battery = parseInt(parts[1])
                batteryCharging = parts[2] === "Charging"
            } else if (l.startsWith("up ")) {
                uptimeText = l
            } else if (l.startsWith("PRETTY_NAME=")) {
                const parts = l.split("=")
                if (parts.length >= 2) {
                    const raw = parts[1].replace(/"/g, "").replace(/'/g, "")
                    distroName = getShortDistro(raw)
                }
            } else if (l.includes("Powered:")) {
                btEnabled = l.includes("yes")
                btStatus = btEnabled ? "Enabled" : "Disabled"
            } else if (l.startsWith("WIFI:")) {
                wifiEnabled = l.includes("enabled")
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
        if (swapTotal > 0)
            swap = 100 * (1 - swapFree / swapTotal)
        else
            swap = 0
        hasBattery = foundBattery
    }

    function toggleBluetooth() {
        Quickshell.execDetached(["sh", "-c", "if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then bluetoothctl power off; else bluetoothctl power on; fi"])
        btRefresh.restart()
    }

    Timer {
        id: btRefresh
        interval: 600
        onTriggered: {
            statProc.running = false
            statProc.running = true
        }
    }

    function toggleWifi() {
        Quickshell.execDetached(["sh", "-c", "if [ \"$(nmcli radio wifi 2>/dev/null)\" = \"enabled\" ]; then nmcli radio wifi off; else nmcli radio wifi on; fi"])
        wifiRefresh.restart()
    }

    Timer {
        id: wifiRefresh
        interval: 600
        onTriggered: {
            statProc.running = false
            statProc.running = true
            netProc.running = false
            netProc.running = true
        }
    }

    property bool capsOn: false
    property bool dndOn: false
    property bool caffeineOn: false
    property bool eyeProtectionOn: false
    property var historyNotifications: []
    readonly property int notifCount: historyNotifications.length

    signal notificationReceived(var notifData)

    function addNotification(notif) {
        const icon = notif.appIcon || notif.image || ""
        const app = notif.appName || "Notification"
        const title = notif.summary || "Notification"
        const body = notif.body || ""
        const desktopEntry = notif.desktopEntry || ""
        const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        const hintsObj = notif.hints || {}
        const notifId = (notif.id !== undefined && notif.id !== null) ? notif.id.toString() : (Date.now() + Math.random()).toString()

        let directWid = ""
        if (hintsObj["window-id"] || hintsObj["window_id"] || hintsObj["wid"] || hintsObj["x-kde-originating-window-id"] || hintsObj["x-canonical-private-window-id"]) {
            const rawWid = hintsObj["window-id"] || hintsObj["window_id"] || hintsObj["wid"] || hintsObj["x-kde-originating-window-id"] || hintsObj["x-canonical-private-window-id"]
            directWid = String(rawWid)
        }

        const expireTimeout = (typeof notif.expireTimeout === "number" && notif.expireTimeout > 0)
            ? notif.expireTimeout
            : ((typeof notif.timeout === "number" && notif.timeout > 0) ? notif.timeout : 0)

        const item = {
            id: notifId,
            appName: app,
            appIcon: icon,
            summary: title,
            body: body,
            desktopEntry: desktopEntry,
            time: timeStr,
            timestamp: Date.now(),
            expireTimeout: expireTimeout,
            hints: hintsObj,
            targetWid: directWid,
            _notifRef: notif
        }

        historyNotifications = [item, ...historyNotifications].slice(0, 15)
        notificationReceived(item)

        Quickshell.execDetached([
            "python3", root.scriptPath("open_notif_app.py"),
            "--register",
            notifId,
            app,
            desktopEntry,
            title,
            body,
            JSON.stringify(hintsObj)
        ])
    }

    function activateNotification(notifItem) {
        if (!notifItem) return
        
        try {
            if (notifItem._notifRef) {
                const notif = notifItem._notifRef
                const acts = notif.actions
                let invoked = false
                if (acts && acts.length > 0) {
                    for (let i = 0; i < acts.length; i++) {
                        const act = acts[i]
                        if (act && (act.identifier === "default" || act.id === "default")) {
                            if (typeof act.invoke === "function") {
                                act.invoke()
                                invoked = true
                            }
                            break
                        }
                    }
                    if (!invoked && acts[0] && typeof acts[0].invoke === "function") {
                        acts[0].invoke()
                        invoked = true
                    }
                }
            }
        } catch(e) {}

        const notifId = (notifItem.id !== undefined && notifItem.id !== null) ? notifItem.id.toString() : ""
        const appName = notifItem.appName || ""
        const desktopEntry = notifItem.desktopEntry || ""
        const summary = notifItem.summary || ""
        const body = notifItem.body || ""
        const hintsStr = JSON.stringify(notifItem.hints || {})
        if (appName.toLowerCase().includes("shalat") || summary.toLowerCase().includes("shalat")) {
            Quickshell.execDetached(["qs", "-p", root.configDir, "ipc", "call", "prayer", "toggle"])
            root.removeNotification(notifItem.id)
            return
        }

        Quickshell.execDetached([
            "python3", root.scriptPath("open_notif_app.py"),
            "--focus",
            notifId,
            appName,
            desktopEntry,
            summary,
            body,
            hintsStr,
            targetWid
        ])

        root.removeNotification(notifItem.id)
    }

    function removeNotification(id) {
        const notif = historyNotifications.find(n => n.id === id)
        if (notif && notif._notifRef) {
            try {
                if (typeof notif._notifRef.dismiss === "function") {
                    notif._notifRef.dismiss()
                } else {
                    notif._notifRef.tracked = false
                }
            } catch(e) {}
        }
        if (id !== undefined && id !== null) {
            Quickshell.execDetached(["python3", root.scriptPath("open_notif_app.py"), "--remove", id.toString()])
        }
        historyNotifications = historyNotifications.filter(n => n.id !== id)
    }

    function clearNotifications() {
        historyNotifications = []
    }

    function toggleDnd() {
        dndOn = !dndOn
    }

    function toggleCaffeine() {
        caffeineOn = !caffeineOn
        if (caffeineOn) {
            Quickshell.execDetached(["notify-send", "-a", "Azkia Shell", "Keep Awake Enabled", "Screen sleep & auto-lock suspended."])
        } else {
            Quickshell.execDetached(["notify-send", "-a", "Azkia Shell", "Keep Awake Disabled", "Normal power management resumed."])
        }
    }

    function toggleEyeProtection() {
        eyeProtectionOn = !eyeProtectionOn
        if (eyeProtectionOn) {
            Quickshell.execDetached(["sh", "-c", "for mon in $(xrandr --query | awk '/ connected/{print $1}'); do xrandr --output $mon --gamma 1.0:0.85:0.7; done"])
            Quickshell.execDetached(["notify-send", "-a", "Azkia Shell", "Eye Protection Enabled", "Warm color filter activated."])
        } else {
            Quickshell.execDetached(["sh", "-c", "for mon in $(xrandr --query | awk '/ connected/{print $1}'); do xrandr --output $mon --gamma 1.0:1.0:1.0; done"])
            Quickshell.execDetached(["notify-send", "-a", "Azkia Shell", "Eye Protection Disabled", "Normal color profile restored."])
        }
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

    function refreshNet() {
        netProc.running = false
        netProc.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshNet()
    }

    Process {
        id: netMonitorProc
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                netDebounceTimer.restart()
            }
        }
        onExited: (code, status) => {
            netMonitorRestartTimer.restart()
        }
    }

    Timer {
        id: netDebounceTimer
        interval: 400
        repeat: false
        onTriggered: root.refreshNet()
    }

    Timer {
        id: netMonitorRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            netMonitorProc.running = false
            netMonitorProc.running = true
        }
    }

    // primary transport + vpn tracked separately: a vpn/wireguard/tun
    // connection rides ON a transport, it isn't one
    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"]
        stdout: StdioCollector {
            onStreamFinished: {
                let name = "", type = "", vName = "", vOn = false
                let activeWifi = ""
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
                    if (t === "802-11-wireless" || t === "wifi" || t.indexOf("wireless") !== -1) {
                        activeWifi = n
                    }
                }
                root.netName = name
                root.netType = type
                root.vpnOn = vOn
                root.vpnName = vName
                root.wifiName = activeWifi

                if (!root._wifiInitialized) {
                    root._lastWifiName = activeWifi
                    root._wifiInitialized = true
                } else {
                    if (activeWifi !== "" && activeWifi !== root._lastWifiName) {
                        Quickshell.execDetached(["notify-send", "-a", "Wi-Fi", "-i", "network-wireless-connected", "Wi-Fi Connected", "Connected to " + activeWifi])
                        root._lastWifiName = activeWifi
                    } else if (activeWifi === "" && root._lastWifiName !== "") {
                        Quickshell.execDetached(["notify-send", "-a", "Wi-Fi", "-i", "network-wireless-disconnected", "Wi-Fi Disconnected", "Disconnected from " + root._lastWifiName])
                        root._lastWifiName = ""
                    }
                }
            }
        }
    }

    onIsLockedChanged: root.syncLockState()

    function syncLockState() {
        updateLockStateProc.command = ["sh", "-c", "echo " + (isLocked ? "1" : "0") + " > /tmp/azkia_lock_state"]
        updateLockStateProc.running = false
        updateLockStateProc.running = true
    }

    onCaffeineOnChanged: root.syncCaffeineState()

    function syncCaffeineState() {
        if (caffeineOn) {
            Quickshell.execDetached(["sh", "-c", "echo 1 > /tmp/azkia_caffeine_state; xset s off -dpms; systemd-inhibit --what=idle:sleep:shutdown --who='Azkia Shell' --why='Keep Awake' sleep infinity & echo $! > /tmp/azkia_caffeine_inhibit.pid"])
        } else {
            Quickshell.execDetached(["sh", "-c", "echo 0 > /tmp/azkia_caffeine_state; xset s on +dpms; if [ -f /tmp/azkia_caffeine_inhibit.pid ]; then kill $(cat /tmp/azkia_caffeine_inhibit.pid) 2>/dev/null; rm -f /tmp/azkia_caffeine_inhibit.pid; fi; pkill -f 'Keep Awake' 2>/dev/null"])
        }
    }

    Process {
        id: updateLockStateProc
    }

    Process {
        id: idleDaemonProc
        command: ["python3", Sys.scriptPath("idle_daemon.py")]
        running: true
        onExited: (code, status) => {
            idleRestartTimer.restart()
        }
    }

    Timer {
        id: idleRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            idleDaemonProc.running = false
            idleDaemonProc.running = true
        }
    }

    Process {
        id: prayerDaemonProc
        command: ["python3", Sys.scriptPath("prayer_service.py"), "--daemon"]
        running: true
        onExited: (code, status) => {
            prayerRestartTimer.restart()
        }
    }

    Timer {
        id: prayerRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            prayerDaemonProc.running = false
            prayerDaemonProc.running = true
        }
    }

    Process {
        id: audioPlayerDaemonProc
        command: ["python3", Sys.scriptPath("azkia_audio_player.py"), "--daemon"]
        running: true
        onExited: (code, status) => {
            audioRestartTimer.restart()
        }
    }

    Timer {
        id: audioRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            audioPlayerDaemonProc.running = false
            audioPlayerDaemonProc.running = true
        }
    }

    Process {
        id: polkitAgentProc
        command: ["python3", Sys.scriptPath("polkit_agent.py"), "--daemon"]
        running: true
        onExited: (code, status) => {
            polkitRestartTimer.restart()
        }
    }

    Timer {
        id: polkitRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            polkitAgentProc.running = false
            polkitAgentProc.running = true
        }
    }

    Component.onCompleted: {
        root.parseFehbg()
        root.syncLockState()
        root.syncCaffeineState()
        root.updateBspwmPadding()
    }
}
