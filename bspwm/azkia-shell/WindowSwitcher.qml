import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Window {
    id: root

    property var modelData
    readonly property var targetScreen: modelData

    title: "Window Switcher"
    flags: Qt.Dialog
    color: "transparent"
    visible: false

    property var windowsList: []
    property int selectedIndex: 0
    property bool isSwitching: false
    property bool tooltipVisible: false

    readonly property int cardCount: (windowsList && windowsList.length > 0) ? windowsList.length : 2
    readonly property int idealContentWidth: (cardCount * 124) + (Math.max(0, cardCount - 1) * 14) + 36
    readonly property int maxAllowedWidth: targetScreen ? (targetScreen.width - 32) : 1888

    width: Math.min(maxAllowedWidth, Math.max(160, idealContentWidth))
    height: 172

    x: targetScreen ? ((targetScreen.width - width) / 2 + (targetScreen.x || 0)) : (1920 - width) / 2
    y: targetScreen ? ((targetScreen.height - height) / 2 + (targetScreen.y || 0)) : (1080 - height) / 2

    readonly property var currentWindow: (windowsList && windowsList.length > 0 && selectedIndex >= 0 && selectedIndex < windowsList.length) 
        ? windowsList[selectedIndex] 
        : null

    Component.onCompleted: {
        fetchProc.running = true
    }

    onActiveChanged: {
        if (active) {
            containerCard.forceActiveFocus()
        }
    }

    onSelectedIndexChanged: {
        tooltipVisible = false
        tooltipTimer.restart()
    }

    Timer {
        id: tooltipTimer
        interval: 100
        repeat: false
        onTriggered: {
            root.tooltipVisible = true
        }
    }

    onVisibleChanged: {
        if (visible) {
            root.requestActivate()
            containerCard.forceActiveFocus()
            tooltipVisible = false
            tooltipTimer.restart()
        } else {
            altWatchProc.running = false
            tooltipVisible = false
            tooltipTimer.stop()
            Quickshell.execDetached(["rm", "-f", "/dev/shm/azkia_switcher_active"])
        }
    }

    function advance(delta) {
        if (!visible) {
            if (delta < 0) prev()
            else next()
            return
        }
        if (windowsList.length > 0) {
            selectedIndex = (selectedIndex + delta + windowsList.length) % windowsList.length
            listView.positionViewAtIndex(selectedIndex, ListView.Contain)
        }
    }

    function next() {
        if (!visible) {
            if (windowsList.length === 0) {
                Quickshell.execDetached(["bspc", "node", "-f", "last"])
                fetchProc.running = true
                return
            }

            // Select previous window (index 1 in MRU) immediately
            if (windowsList.length > 1) {
                selectedIndex = 1
            } else {
                selectedIndex = 0
            }

            // POP UP IMMEDIATELY IN 0ms!
            root.visible = true
            root.requestActivate()
            containerCard.forceActiveFocus()
            listView.positionViewAtIndex(selectedIndex, ListView.Contain)

            // Start background Alt monitor (2ms C binary)
            altWatchProc.running = false
            altWatchProc.running = true
        } else {
            advance(1)
        }
    }

    function prev() {
        if (!visible) {
            if (windowsList.length === 0) {
                Quickshell.execDetached(["bspc", "node", "-f", "last"])
                fetchProc.running = true
                return
            }

            selectedIndex = (windowsList.length > 1) ? (windowsList.length - 1) : 0

            // POP UP IMMEDIATELY IN 0ms!
            root.visible = true
            root.requestActivate()
            containerCard.forceActiveFocus()
            listView.positionViewAtIndex(selectedIndex, ListView.Contain)

            altWatchProc.running = false
            altWatchProc.running = true
        } else {
            advance(-1)
        }
    }

    function confirmSwitch() {
        if (!visible) return
        root.visible = false
        altWatchProc.running = false
        Quickshell.execDetached(["rm", "-f", "/dev/shm/azkia_switcher_active"])
        
        const win = root.currentWindow
        if (win && win.id) {
            // Instant 1-3ms C execution directly into bspwm, same speed as super+Tab
            Quickshell.execDetached(["bspc", "node", win.id, "-f"])
        }

        // Refresh list for next time
        fetchProc.running = false
        fetchProc.running = true
    }

    function switchTo(wid) {
        if (!wid) return
        root.visible = false
        altWatchProc.running = false
        Quickshell.execDetached(["rm", "-f", "/dev/shm/azkia_switcher_active"])
        Quickshell.execDetached(["bspc", "node", wid, "-f"])
        fetchProc.running = false
        fetchProc.running = true
    }

    function closeWithoutSwitch() {
        root.visible = false
        altWatchProc.running = false
        Quickshell.execDetached(["rm", "-f", "/dev/shm/azkia_switcher_active"])
        fetchProc.running = false
        fetchProc.running = true
    }

    IpcHandler {
        target: "windowswitcher"
        function show(direction: string): void {
            if (direction === "prev") root.prev()
            else root.next()
        }
        function next(): void { root.next() }
        function prev(): void { root.prev() }
        function toggle(): void {
            if (root.visible) root.confirmSwitch()
            else root.next()
        }
        function confirm(): void { root.confirmSwitch() }
        function close(): void { root.closeWithoutSwitch() }
    }

    // Process to fetch open windows in background without blocking GUI
    Process {
        id: fetchProc
        command: ["python3", Sys.scriptPath("window_switcher.py")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    if (parsed.length > 0) {
                        root.windowsList = parsed
                    }
                } catch (e) {}
            }
        }
    }

    // Live subscriber to BSPWM window events (node_add, node_remove, node_focus, etc.)
    Process {
        id: bspcSubscriber
        command: ["bspc", "subscribe", "node"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (!root.visible) {
                    fetchDebounce.restart()
                }
            }
        }
    }

    Timer {
        id: fetchDebounce
        interval: 80
        repeat: false
        onTriggered: {
            fetchProc.running = false
            fetchProc.running = true
        }
    }

    // Process to monitor Alt key release and Tab key in background (ultra-fast 2ms C binary)
    Process {
        id: altWatchProc
        command: [Sys.configDir + "/bin/watch-alt"]
        running: false
        stdout: SplitParser {
            onRead: line => {
                const cmd = line.trim()
                if (cmd === "RELEASED") {
                    root.confirmSwitch()
                } else if (cmd === "NEXT") {
                    root.advance(1)
                } else if (cmd === "PREV") {
                    root.advance(-1)
                } else if (cmd === "CANCEL") {
                    root.closeWithoutSwitch()
                }
            }
        }
    }

    // Floating Switcher Container Card - EXACTLY matches SettingsWindow
    Rectangle {
        id: containerCard
        anchors.fill: parent
        radius: 20
        color: Sys.customBarBg
        border.width: 1
        border.color: Theme.altbg

        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Tab) {
                if (event.modifiers & Qt.ShiftModifier) {
                    root.prev()
                } else {
                    root.next()
                }
                event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                root.next()
                event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                root.prev()
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.confirmSwitch()
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                root.closeWithoutSwitch()
                event.accepted = true
            }
        }

        Keys.onReleased: (event) => {
            if (event.key === Qt.Key_Alt) {
                root.confirmSwitch()
                event.accepted = true
            }
        }

        // Drop shadow matching SettingsWindow (Picom-style natural window shadow)
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha("#000000", 0.55)
            shadowBlur: 1.1
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 8
        }

        // Horizontal Windows List - Margins are 18px everywhere (left, top, right, bottom)
        ListView {
            id: listView
            anchors.fill: parent
            anchors.margins: 18
            currentIndex: root.selectedIndex
            orientation: ListView.Horizontal
            spacing: 14
            clip: false
            model: root.windowsList
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: cardDelegate
                required property var modelData
                required property int index

                readonly property bool isSelected: (index === root.selectedIndex)
                readonly property bool isHovered: itemHover.containsMouse

                width: 124
                height: 136
                radius: 16
                color: isSelected 
                    ? Theme.accent 
                    : (isHovered ? Sys.customModuleHoverBg : Sys.customModuleBg)
                
                border.width: 1
                border.color: isSelected 
                    ? Theme.accentHover 
                    : (isHovered ? Qt.alpha(Theme.accent, 0.4) : Sys.customModuleBorder)

                // Desktop Workspace Badge (Top-right)
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    width: badgeText.implicitWidth + 12
                    height: 18
                    radius: 6
                    color: isSelected ? Qt.alpha(Theme.bg, 0.85) : Qt.alpha("#ffffff", 0.12)
                    visible: !!modelData.desktop

                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: modelData.desktop ? ("W - " + modelData.desktop) : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: isSelected ? Theme.accent : Theme.fg
                    }
                }

                // App Content Column
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    width: parent.width - 16

                    // App Icon (Enlarged)
                    Item {
                        width: 62
                        height: 62
                        anchors.horizontalCenter: parent.horizontalCenter

                        Image {
                            id: appImg
                            anchors.fill: parent
                            source: modelData.icon ? ("file://" + modelData.icon) : ""
                            sourceSize: Qt.size(62, 62)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            asynchronous: true
                            visible: status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !modelData.icon || appImg.status !== Image.Ready
                            text: "󰣆"
                            font.family: Theme.fontFamily
                            font.pixelSize: 44
                            color: isSelected ? Theme.bg : Theme.secondary
                        }
                    }

                    // App Name (matching launcher, e.g. WPS Spreadsheets, Brave, etc.)
                    Text {
                        width: parent.width
                        text: modelData.name || modelData.class || modelData.title || "Window"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: isSelected
                        color: isSelected ? Theme.bg : Theme.fg
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                // Native ToolTip showing full window title on active card
                ToolTip {
                    id: winToolTip
                    visible: isSelected && root.tooltipVisible
                    delay: 80
                    timeout: 0
                    y: parent.height + 8
                    x: Math.max(-cardDelegate.x + 10, Math.min(listView.width - cardDelegate.x - implicitWidth - 10, (parent.width - implicitWidth) / 2))
                    
                    text: {
                        let t = modelData.title || modelData.name || modelData.class || ""
                        if (modelData.desktop) {
                            t += " - Workspace " + modelData.desktop
                        }
                        return t
                    }
                    contentItem: Text {
                        text: winToolTip.text
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: 11
                    }
                    background: Rectangle {
                        color: Qt.alpha(Theme.bg, 0.96)
                        border.color: Qt.alpha(Theme.accent, 0.45)
                        border.width: 1
                        radius: 8
                    }
                }

                MouseArea {
                    id: itemHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.selectedIndex = index
                        root.switchTo(modelData.id)
                    }
                }
            }
        }
    }
}
