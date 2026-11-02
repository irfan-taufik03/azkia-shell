pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// bspwm state + control. `bspc subscribe report` streams every desktop /
// layout change (no WM patch needed — this is the interface bspwm was built
// around); the focused window title comes from a two-stage xprop spy, since
// bspc reports don't carry titles. Actions go straight through bspc.
Singleton {
    id: root

    property int seltags: 1
    property int occtags: 0
    property int urgtags: 0
    property int tagCount: 12
    property string title: ""
    property string activeWinId: ""
    property string wmClass: ""
    property string appName: ""
    property string appIconPath: ""

    // --- shared display mode (single source of truth for all monitors) ---
    property string displayMode: "off"

    function setDisplayMode(mode) {
        root.displayMode = mode
        Quickshell.execDetached([Theme.configDir + "/scripts/display_setup.sh", mode])
        Quickshell.execDetached(["notify-send", "-a", "Display", "Display Mode Updated", "Applied mode: " + mode.toUpperCase()])
    }

    function detectDisplayMode() {
        displayModeProc.running = false
        displayModeProc.running = true
    }

    // Read mode from state file on startup
    Component.onCompleted: detectDisplayMode()

    Process {
        id: displayModeProc
        running: false
        command: ["sh", "-c", "f=$HOME/.config/bspwm/display_mode; [ -f $f ] && cat $f || echo off"]
        stdout: StdioCollector {
            onStreamFinished: {
                const res = text.trim()
                if (res === "mirror" || res === "extend" || res === "off") {
                    root.displayMode = res
                }
            }
        }
    }

    // --- layout (scripts/layout engine on top of bspwm's native tiled/monocle) ---

    readonly property var layouts: ["tiled", "tall", "rtall", "wide", "rwide",
                                    "grid", "rgrid", "even", "monocle"]
    property string bspLayout: "-"      // scripts/layout get; "-" = never set
    property bool nativeMonocle: false  // report L flag fallback
    readonly property string layout: bspLayout !== "-" && bspLayout !== ""
        ? bspLayout : (nativeMonocle ? "monocle" : "tiled")

    function refreshLayout() {
        layoutGet.running = false
        layoutGet.running = true
    }

    Process {
        id: layoutGet
        command: [Theme.configDir + "/scripts/layout", "get"]
        running: true
        stdout: SplitParser {
            onRead: line => root.bspLayout = line.trim()
        }
    }

    property bool isFullscreen: false

    function checkFullscreen() {
        fullscreenCheck.running = false
        fullscreenCheck.running = true
    }

    Process {
        id: fullscreenCheck
        command: ["bspc", "query", "-N", "-n", ".fullscreen.local"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                root.isFullscreen = (line.trim().length > 0)
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.isFullscreen = false
            }
        }
    }

    // scripts/layout pokes this after every change it applies
    IpcHandler {
        target: "wm"
        function refreshLayout(): void { root.refreshLayout() }
    }

    // --- launcher: toggle on screen where mouse cursor is ---
    signal launcherToggleRequested(string screenName)

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            // Find which screen the mouse is on via xdotool
            launcherMouseProc.running = false
            launcherMouseProc.running = true
        }
    }

    Process {
        id: launcherMouseProc
        running: false
        command: [Theme.configDir + "/scripts/get_mouse_monitor.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                const screenName = text.trim()
                if (screenName) root.launcherToggleRequested(screenName)
            }
        }
    }

    Process {
        command: ["bspc", "subscribe", "report", "node_state"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("W")) {
                    root.parseReport(line)
                }
                root.checkFullscreen()
            }
        }
    }

    property var monitorMap: ({})

    function getSelTags(screenName) {
        if (screenName && monitorMap[screenName])
            return monitorMap[screenName].sel
        return seltags
    }

    function getOccTags(screenName) {
        if (screenName && monitorMap[screenName])
            return monitorMap[screenName].occ
        return occtags
    }

    function getUrgTags(screenName) {
        if (screenName && monitorMap[screenName])
            return monitorMap[screenName].urg
        return urgtags
    }

    // report format: W<Mname|mname>:<desktops...>:L<T|M>:T<..>:G<..>
    // desktop prefixes: O/F/U focused (occupied/free/urgent), o/f/u unfocused
    function parseReport(line) {
        if (!line.startsWith("W"))
            return
        let globalSel = 0, globalOcc = 0, globalUrg = 0
        let layout = ""
        let isMonFocused = false
        let currentMon = ""
        let newMap = {}

        for (const part of line.slice(1).split(":")) {
            if (part.length === 0)
                continue
            const c = part[0]
            if (c === "M" || c === "m") {
                currentMon = part.slice(1)
                isMonFocused = (c === "M")
                if (!newMap[currentMon]) {
                    newMap[currentMon] = { sel: 0, occ: 0, urg: 0 }
                }
            } else if ("OoFfUu".indexOf(c) !== -1 && currentMon !== "") {
                const dName = part.slice(1)
                const numStr = dName.replace("_ext", "")
                const idx = parseInt(numStr) - 1
                if (!isNaN(idx) && idx >= 0 && idx < 10) {
                    let st = newMap[currentMon]
                    if (!st) {
                        st = { sel: 0, occ: 0, urg: 0 }
                        newMap[currentMon] = st
                    }
                    if ("OFU".indexOf(c) !== -1) {
                        st.sel |= (1 << idx)
                        globalSel |= (1 << idx)
                    }
                    if (c === "O" || c === "o") {
                        st.occ |= (1 << idx)
                        globalOcc |= (1 << idx)
                    }
                    if (c === "U" || c === "u") {
                        st.urg |= (1 << idx)
                        globalUrg |= (1 << idx)
                    }
                }
            } else if (c === "L" && isMonFocused) {
                layout = part.slice(1)
            }
        }
        monitorMap = newMap
        seltags = globalSel
        occtags = globalOcc
        urgtags = globalUrg
        tagCount = 10
        nativeMonocle = layout === "M"
        // desktop focus changed or native layout flipped — re-read the engine
        refreshLayout()
    }

    // --- focused window info (title, class, icon) ---

    Timer {
        id: winInfoRestartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!windowInfoProc.running) {
                windowInfoProc.running = true
            }
        }
    }

    Process {
        id: windowInfoProc
        command: ["python3", Sys.scriptPath("window_info.py"), "--spy"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line)
                    root.title = data.title || ""
                    root.wmClass = data.class || ""
                    root.appName = data.name || data.class || ""
                    root.appIconPath = data.icon || ""
                } catch (e) {}
            }
        }
        onExited: (code, status) => {
            winInfoRestartTimer.restart()
        }
    }

    // --- actions ---

    function viewTag(i, screenName) {
        let args = [Theme.configDir + "/scripts/switch_tag.sh", (i + 1).toString(), "focus"]
        if (screenName) args.push(screenName)
        Quickshell.execDetached(args)
    }
    function toggleViewTag(i, screenName) { viewTag(i, screenName) }
    function sendToTag(i, screenName) {
        let args = [Theme.configDir + "/scripts/switch_tag.sh", (i + 1).toString(), "send"]
        if (screenName) args.push(screenName)
        Quickshell.execDetached(args)
    }
    function cycleTag(dir) {
        Quickshell.execDetached(["bspc", "desktop", "-f",
            (dir > 0 ? "next" : "prev") + ".occupied.local"])
    }
    function setLayout(name) { Quickshell.execDetached([Theme.configDir + "/scripts/layout", "set", name]) }
    function cycleLayout(dir) { Quickshell.execDetached([Theme.configDir + "/scripts/layout", dir > 0 ? "prev" : "next"]) }

    function openLauncher() {
        Quickshell.execDetached(["quickshell", "--path", Sys.configDir, "ipc", "call", "launcher", "toggle"])
    }
    function openPowerMenu() {
        Quickshell.execDetached(["quickshell", "--path", Sys.configDir, "ipc", "call", "power", "toggle"])
    }
}
