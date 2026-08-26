import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 560
    cardHeight: 510

    property int cpuCount: 1
    property real memTotalGB: 0
    property real memUsedGB: 0
    property real memPercent: 0

    property real swapTotalGB: 0
    property real swapUsedGB: 0
    property real swapPercent: 0

    property var rawProcesses: []
    property string defaultSort: "ram" // "ram" or "cpu"
    property string sortBy: defaultSort // "ram" or "cpu"
    property bool sortAscending: false // false = largest to smallest (↓), true = smallest to largest (↑)

    onVisibleChanged: {
        if (visible) {
            sortBy = defaultSort
            sortAscending = false
        }
    }

    readonly property var sortedProcesses: {
        const list = root.rawProcesses.slice()
        if (root.sortBy === "cpu") {
            list.sort((a, b) => root.sortAscending ? a.cpu - b.cpu : b.cpu - a.cpu)
        } else {
            list.sort((a, b) => root.sortAscending ? a.rss_mb - b.rss_mb : b.rss_mb - a.rss_mb)
        }
        return list
    }

    function cycleSort() {
        if (sortBy === "ram" && !sortAscending) {
            sortAscending = true // RAM ↑
        } else if (sortBy === "ram" && sortAscending) {
            sortBy = "cpu"
            sortAscending = false // CPU ↓
        } else if (sortBy === "cpu" && !sortAscending) {
            sortAscending = true // CPU ↑
        } else {
            sortBy = "ram"
            sortAscending = false // RAM ↓
        }
    }

    Timer {
        interval: 2000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: sysProc.running = true
    }

    Process {
        id: sysProc
        command: ["python3", Sys.scriptPath("sys_monitor.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.cpuCount = data.cpu_count || 1
                    root.memTotalGB = data.mem_total_gb || 0
                    root.memUsedGB = data.mem_used_gb || 0
                    root.memPercent = data.mem_percent || 0

                    root.swapTotalGB = data.swap_total_gb || 0
                    root.swapUsedGB = data.swap_used_gb || 0
                    root.swapPercent = data.swap_percent || 0

                    root.rawProcesses = data.top_processes || []
                } catch (e) {}
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 14

        // ================= HEADER =================
        Item {
            width: parent.width
            height: 28

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    text: "󰻠"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "System Monitor"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 3
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Close button
            Rectangle {
                width: 24
                height: 24
                radius: 12
                color: closeMa.containsMouse ? Qt.alpha(Theme.fg, 0.15) : "transparent"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: Qt.alpha(Theme.fg, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }

                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.visible = false
                }
            }
        }

        // ================= 1 ROW CARDS (CPU | MEMORY | SWAP) =================
        Row {
            width: parent.width
            spacing: 10

            // ----- 1. CPU CARD -----
            Rectangle {
                width: (parent.width - 20) / 3
                height: 75
                radius: 10
                color: Sys.customModuleBg
                border.width: 1
                border.color: Sys.customModuleBorder

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 18

                        Row {
                            spacing: 5
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: "󰻠"; color: Theme.yellow; font.family: Theme.fontFamily; font.pixelSize: 14 }
                            Text { text: "CPU"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.cpuCount + " cores"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    Text {
                        text: Math.round(Sys.cpu) + "%"
                        color: Sys.cpu > 85 ? Theme.red : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.alpha(Theme.fg, 0.1)

                        Rectangle {
                            height: parent.height
                            width: Math.round((Math.min(100, Math.max(0, Sys.cpu)) / 100) * parent.width)
                            radius: 2
                            color: Sys.cpu > 85 ? Theme.red : Theme.yellow
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }
                }
            }

            // ----- 2. MEMORY CARD -----
            Rectangle {
                width: (parent.width - 20) / 3
                height: 75
                radius: 10
                color: Sys.customModuleBg
                border.width: 1
                border.color: Sys.customModuleBorder

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 18

                        Row {
                            spacing: 5
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: "󰍛"; color: Theme.magenta; font.family: Theme.fontFamily; font.pixelSize: 14 }
                            Text { text: "Memory"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true }
                        }
                    }

                    Text {
                        text: root.memUsedGB.toFixed(1) + " GB / " + root.memTotalGB.toFixed(1) + " GB"
                        color: root.memPercent > 85 ? Theme.red : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.alpha(Theme.fg, 0.1)

                        Rectangle {
                            height: parent.height
                            width: Math.round((Math.min(100, Math.max(0, root.memPercent)) / 100) * parent.width)
                            radius: 2
                            color: root.memPercent > 85 ? Theme.red : Theme.magenta
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }
                }
            }

            // ----- 3. SWAP CARD -----
            Rectangle {
                width: (parent.width - 20) / 3
                height: 75
                radius: 10
                color: Sys.customModuleBg
                border.width: 1
                border.color: Sys.customModuleBorder

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 18

                        Row {
                            spacing: 5
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: "󰓡"; color: Theme.cyan; font.family: Theme.fontFamily; font.pixelSize: 14 }
                            Text { text: "SWAP"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true }
                        }
                    }

                    Text {
                        text: root.swapUsedGB.toFixed(1) + " GB / " + root.swapTotalGB.toFixed(1) + " GB"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.alpha(Theme.fg, 0.1)

                        Rectangle {
                            height: parent.height
                            width: Math.round((Math.min(100, Math.max(0, root.swapPercent)) / 100) * parent.width)
                            radius: 2
                            color: Theme.cyan
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }
                }
            }
        }

        // ================= PROCESSES TABLE =================
        Column {
            width: parent.width
            height: parent.height - 131
            spacing: 8

            // Header & Sort Controls
            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Process"
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                // Interactive Sort Headers (CPU / RAM / PID / Arrow Button)
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // CPU Sort Indicator Pill (Clicking switches to CPU sort)
                    Rectangle {
                        height: 24
                        width: 54
                        radius: 12
                        color: root.sortBy === "cpu" ? Qt.alpha(Theme.yellow, 0.25) : (cpuMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05))
                        border.width: root.sortBy === "cpu" ? 1 : 0
                        border.color: Theme.yellow
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "CPU"
                            color: root.sortBy === "cpu" ? Theme.yellow : Qt.alpha(Theme.fg, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: root.sortBy === "cpu"
                        }

                        MouseArea {
                            id: cpuMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.sortBy !== "cpu") {
                                    root.sortBy = "cpu"
                                    procListView.userScrollY = 0
                                    procListView.contentY = 0
                                }
                            }
                        }
                    }

                    // RAM Sort Indicator Pill (Clicking switches to RAM sort)
                    Rectangle {
                        height: 24
                        width: 64
                        radius: 12
                        color: root.sortBy === "ram" ? Qt.alpha(Theme.magenta, 0.25) : (ramMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05))
                        border.width: root.sortBy === "ram" ? 1 : 0
                        border.color: Theme.magenta
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "RAM"
                            color: root.sortBy === "ram" ? Theme.magenta : Qt.alpha(Theme.fg, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: root.sortBy === "ram"
                        }

                        MouseArea {
                            id: ramMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.sortBy !== "ram") {
                                    root.sortBy = "ram"
                                    procListView.userScrollY = 0
                                    procListView.contentY = 0
                                }
                            }
                        }
                    }

                    // PID Column Header
                    Item {
                        width: 48
                        height: 24
                        Text {
                            anchors.centerIn: parent
                            text: "PID"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    // Interactive Sort Arrow Button Pill (Clicking toggles Ascending ↑ / Descending ↓)
                    Rectangle {
                        height: 24
                        width: 30
                        radius: 12
                        color: arrowMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: arrowMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: root.sortAscending ? "↑" : "↓"
                            color: arrowMa.containsMouse ? Theme.accent : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                        }

                        MouseArea {
                            id: arrowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.sortAscending = !root.sortAscending
                                procListView.userScrollY = 0
                                procListView.contentY = 0
                            }
                        }
                    }
                }
            }

            // Scrollable Process ListView Container
            Item {
                width: parent.width
                height: parent.height - 36
                clip: true

                ListView {
                    id: procListView
                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: root.sortedProcesses

                    property real userScrollY: 0

                    onMovementEnded: userScrollY = contentY
                    onFlickEnded: userScrollY = contentY

                    onContentYChanged: {
                        if (procListView.moving || procListView.flicking || procListView.dragging) {
                            procListView.userScrollY = procListView.contentY
                        }
                    }

                    onModelChanged: {
                        const targetY = procListView.userScrollY
                        if (targetY > 0) {
                            Qt.callLater(() => {
                                if (procListView.contentHeight > procListView.height) {
                                    procListView.contentY = Math.min(targetY, procListView.contentHeight - procListView.height)
                                }
                            })
                        }
                    }

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        width: procListView.width
                        height: 32
                        radius: 8
                        color: index % 2 === 0 ? Qt.alpha(Theme.fg, 0.04) : "transparent"

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Text {
                                text: "󰅟"
                                color: Qt.alpha(Theme.fg, 0.4)
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.name || "process"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: 230
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            // CPU % Badge
                            Rectangle {
                                height: 22
                                width: 54
                                radius: 11
                                color: root.sortBy === "cpu" ? Qt.alpha(Theme.yellow, 0.2) : Qt.alpha(Theme.fg, 0.06)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: (modelData.cpu || "0") + "%"
                                    color: root.sortBy === "cpu" ? Theme.yellow : Qt.alpha(Theme.fg, 0.8)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: root.sortBy === "cpu"
                                }
                            }

                            // RAM Usage Badge (MB / GB)
                            Rectangle {
                                height: 22
                                width: 72
                                radius: 11
                                color: root.sortBy === "ram" ? Qt.alpha(Theme.magenta, 0.2) : Qt.alpha(Theme.fg, 0.06)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.ram_str || "0 MB"
                                    color: root.sortBy === "ram" ? Theme.magenta : Qt.alpha(Theme.fg, 0.8)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: root.sortBy === "ram"
                                }
                            }

                            // PID Badge
                            Rectangle {
                                height: 22
                                width: 48
                                radius: 11
                                color: Qt.alpha(Theme.fg, 0.04)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.pid || "-"
                                    color: Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }

                // Floating Scrollbar Thumb (No Track, Card-Colored Pill, Draggable on Press)
                Item {
                    id: scrollTrack
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 20

                    readonly property bool isScrolling: procListView.moving || procListView.flicking || procListView.dragging
                    readonly property bool showThumb: isScrolling || scrollMa.containsMouse || scrollMa.pressed

                    MouseArea {
                        id: scrollMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeVerCursor

                        onPressed: (mouse) => updatePosition(mouse.y)
                        onPositionChanged: (mouse) => {
                            if (pressed) updatePosition(mouse.y)
                        }

                        function updatePosition(mouseY) {
                            const trackH = scrollTrack.height
                            const thumbH = scrollThumb.height
                            if (trackH <= thumbH) return
                            const maxThumbY = trackH - thumbH
                            const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                            const ratio = clampedY / maxThumbY
                            const maxContentY = procListView.contentHeight - procListView.height
                            if (maxContentY > 0) {
                                procListView.contentY = ratio * maxContentY
                                procListView.userScrollY = procListView.contentY
                            }
                        }
                    }

                    Rectangle {
                        id: scrollThumb
                        anchors.right: parent.right
                        anchors.rightMargin: 3
                        width: 10
                        height: 36
                        y: {
                            const maxContentY = procListView.contentHeight - procListView.height
                            const maxThumbY = scrollTrack.height - height
                            if (maxContentY > 0 && maxThumbY > 0) {
                                return Math.max(0, Math.min((procListView.contentY / maxContentY) * maxThumbY, maxThumbY))
                            }
                            return 0
                        }
                        radius: 5
                        color: scrollMa.pressed ? Qt.alpha(Theme.accent, 0.7) : (scrollMa.containsMouse ? Qt.alpha(Theme.fg, 0.40) : Qt.alpha(Theme.fg, 0.20))
                        opacity: (procListView.contentHeight > procListView.height && scrollTrack.showThumb) ? 1.0 : 0.0

                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }
        }
    }
}
