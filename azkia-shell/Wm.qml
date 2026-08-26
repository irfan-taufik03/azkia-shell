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
    property string appIconPath: ""

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

    // report format: W<Mname|mname>:<desktops...>:L<T|M>:T<..>:G<..>
    // desktop prefixes: O/F/U focused (occupied/free/urgent), o/f/u unfocused
    function parseReport(line) {
        if (!line.startsWith("W"))
            return
        let sel = 0, occ = 0, urg = 0, count = 0
        let layout = ""
        let monitorFocused = false
        for (const part of line.slice(1).split(":")) {
            if (part.length === 0)
                continue
            const c = part[0]
            if (c === "M" || c === "m") {
                monitorFocused = (c === "M")
            } else if ("OoFfUu".indexOf(c) !== -1) {
                const i = count++
                if ("OFU".indexOf(c) !== -1)
                    sel |= 1 << i
                if (c === "O" || c === "o")
                    occ |= 1 << i
                if (c === "U" || c === "u")
                    urg |= 1 << i
            } else if (c === "L" && monitorFocused) {
                layout = part.slice(1)
            }
        }
        seltags = sel
        occtags = occ
        urgtags = urg
        tagCount = count
        nativeMonocle = layout === "M"
        // desktop focus changed or native layout flipped — re-read the engine
        refreshLayout()
    }

    // --- focused window info (title, class, icon) ---

    Process {
        command: ["python3", Sys.scriptPath("window_info.py"), "--spy"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line)
                    root.title = data.title || ""
                    root.wmClass = data.class || ""
                    root.appIconPath = data.icon || ""
                } catch (e) {}
            }
        }
    }

    // --- actions ---

    function viewTag(i) { Quickshell.execDetached(["bspc", "desktop", "-f", "^" + (i + 1)]) }
    function toggleViewTag(i) { viewTag(i) }
    function sendToTag(i) { Quickshell.execDetached(["bspc", "node", "-d", "^" + (i + 1)]) }
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
