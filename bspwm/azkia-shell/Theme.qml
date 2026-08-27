pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live palette sourced from the bspwm theme switcher. The switcher rewrites
// polybar/colors.ini (and colors.sh) in place on every switch, so watching
// that file re-colors the bar with no restart — polybar itself can be
// retired without breaking this. Defaults are github_dark placeholders.
//
// The polybar palette is smaller than dwm's xresources+ANSI set, so the
// semantic names below collapse onto it: red→alert, yellow→primary,
// blue/green/cyan/magenta→secondary. Cohesive by construction.
Singleton {
    id: root

    // config root = parent of the running quickshell dir, derived rather
    // than hardcoded so vendored copies (openbox etc.) need no path edits
    readonly property string configDir: {
        let sd = String(Quickshell.shellDir ?? "")
        if (sd.startsWith("file://"))
            sd = sd.slice(7)
        return sd.substring(0, sd.lastIndexOf("/"))
    }

    property color bg: "#2e3440"
    property color altbg: "#3b4252"
    property color fg: "#e5e9f0"
    property color border: "#bd93f9"
    property color primary: "#bd93f9"
    property color secondary: "#8b949e"
    property color alert: "#ed8796"
    property color disabled: "#4c566a"

    readonly property color accent: Sys.customColor1
    readonly property color selbg: accent
    readonly property color selfg: bg
    readonly property color red: Sys.customColor7
    readonly property color yellow: Sys.customColor5
    readonly property color blue: Sys.customColor2
    readonly property color green: Sys.customColor4
    readonly property color cyan: Sys.customColor3
    readonly property color magenta: Sys.customColor1
    readonly property color peach: Sys.customColor6

    readonly property string fontFamily: "Ubuntu Nerd Font"
    readonly property int fontWeight: Font.Bold
    readonly property int fontSize: 13
    readonly property int iconSize: 15

    FileView {
        path: root.configDir + "/polybar/colors.ini"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseIni(text())
    }

    function parseIni(t) {
        const map = {}
        for (const line of t.split("\n")) {
            const m = line.match(/^\s*([A-Za-z-]+)\s*=\s*(#[0-9a-fA-F]{3,8})/)
            if (m)
                map[m[1]] = m[2]
        }
        if (map["background"]) bg = map["background"]
        if (map["background-alt"]) altbg = map["background-alt"]
        if (map["foreground"]) fg = map["foreground"]
        if (map["border"]) border = map["border"]
        if (map["primary"]) primary = map["primary"]
        if (map["secondary"]) secondary = map["secondary"]
        if (map["alert"]) alert = map["alert"]
        if (map["disabled"]) disabled = map["disabled"]
    }
}
