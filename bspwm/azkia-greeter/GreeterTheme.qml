pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string homeDir: Quickshell.env("HOME") || "/home/vaan"
    readonly property string configDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")

    property color bg: "#2e3440"
    property color altbg: "#4c566a"
    property color fg: "#e5e9f0"
    property color accent: "#c6a0f6"
    property color red: "#ed8796"
    property color border: "#4c566a"
    property color cardBg: "#3b4252"
    property string currentWallpaper: "file://" + homeDir + "/.config/bspwm/wallpapers/Default.png"
    property string userAvatar: "file://" + homeDir + "/.config/bspwm/azkia-shell/assets/avatar.png"
    property string username: Quickshell.env("USER") || "vaan"
    readonly property string fontFamily: "Ubuntu Nerd Font"
    property int cardRadius: 14

    // Live monitor of Azkia Shell appearance settings
    FileView {
        id: appearanceFile
        path: root.homeDir + "/.config/bspwm/azkia-shell/appearance.json"
        watchChanges: true
        onTextChanged: root.reloadTheme()
        onLoaded: root.reloadTheme()
    }

    // Live monitor of current wallpaper from fehbg
    FileView {
        id: fehbgFile
        path: root.homeDir + "/.fehbg"
        watchChanges: true
        onTextChanged: root.reloadWallpaper()
        onLoaded: root.reloadWallpaper()
    }

    Component.onCompleted: {
        reloadTheme()
        reloadWallpaper()
    }

    function reloadTheme() {
        try {
            const txt = (typeof appearanceFile.text === "function") ? appearanceFile.text() : (appearanceFile.text || "")
            if (txt && txt.trim().length > 0) {
                const data = JSON.parse(txt)
                if (data.customBarBg) root.bg = data.customBarBg
                if (data.customModuleBg) root.cardBg = data.customModuleBg
                if (data.customModuleBorder) root.border = data.customModuleBorder
                if (data.customColor1) root.accent = data.customColor1
                if (data.userAvatar) root.userAvatar = data.userAvatar.replace("~", root.homeDir)
            }
        } catch (e) {}
    }

    function reloadWallpaper() {
        try {
            const txt = (typeof fehbgFile.text === "function") ? fehbgFile.text() : (fehbgFile.text || "")
            if (txt && txt.trim().length > 0) {
                const m = txt.match(/'([^']+)'/) || txt.match(/"([^"]+)"/)
                if (m && m[1]) {
                    let cleanPath = m[1].replace("~", root.homeDir)
                    if (!cleanPath.startsWith("file://") && !cleanPath.startsWith("http")) {
                        cleanPath = "file://" + cleanPath
                    }
                    root.currentWallpaper = cleanPath
                }
            }
        } catch (e) {}
    }
}
