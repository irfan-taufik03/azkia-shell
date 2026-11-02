import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    IpcHandler {
        target: "systemmonitor"
        function toggle(): void { root.toggle() }
    }

    cardWidth: 560
    cardHeight: 425

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
        spacing: 12

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
        }

        // ================= 1 ROW ENLARGED CIRCLES (CPU | MEMORY | SWAP) =================
        Row {
            width: parent.width
            height: 106

            // ----- 1. CPU CIRCLE -----
            Item {
                width: parent.width / 3
                height: parent.height

                Item {
                    width: 100
                    height: 100
                    anchors.centerIn: parent

                    Canvas {
                        id: cpuCanvas
                        anchors.fill: parent
                        property real val: Math.min(100, Math.max(0, Sys.cpu)) / 100
                        property color colorVal: Sys.cpu > 85 ? Theme.red : Theme.yellow
                        onValChanged: requestPaint()
                        onColorValChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var cx = width / 2
                            var cy = height / 2
                            var r = (width - 12) / 2
                            var start = -Math.PI / 2
                            var end = start + (val * 2 * Math.PI)

                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                            ctx.strokeStyle = Qt.alpha(Theme.fg, 0.1)
                            ctx.lineWidth = 6
                            ctx.stroke()

                            if (val > 0) {
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, start, end)
                                ctx.strokeStyle = colorVal
                                ctx.lineWidth = 7.5
                                ctx.lineCap = "round"
                                ctx.stroke()
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "CPU"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(Sys.cpu) + "%"
                            color: Sys.cpu > 85 ? Theme.red : Theme.yellow
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.cpuCount + " Cores"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }
                }
            }

            // ----- 2. RAM CIRCLE -----
            Item {
                width: parent.width / 3
                height: parent.height

                Item {
                    width: 100
                    height: 100
                    anchors.centerIn: parent

                    Canvas {
                        id: memCanvas
                        anchors.fill: parent
                        property real val: Math.min(100, Math.max(0, root.memPercent)) / 100
                        property color colorVal: root.memPercent > 85 ? Theme.red : Theme.accent
                        onValChanged: requestPaint()
                        onColorValChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var cx = width / 2
                            var cy = height / 2
                            var r = (width - 12) / 2
                            var start = -Math.PI / 2
                            var end = start + (val * 2 * Math.PI)

                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                            ctx.strokeStyle = Qt.alpha(Theme.fg, 0.1)
                            ctx.lineWidth = 6
                            ctx.stroke()

                            if (val > 0) {
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, start, end)
                                ctx.strokeStyle = colorVal
                                ctx.lineWidth = 7.5
                                ctx.lineCap = "round"
                                ctx.stroke()
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "RAM"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(root.memPercent) + "%"
                            color: root.memPercent > 85 ? Theme.red : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.memUsedGB.toFixed(1) + " / " + root.memTotalGB.toFixed(1) + " GB"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                    }
                }
            }

            // ----- 3. SWAP CIRCLE -----
            Item {
                width: parent.width / 3
                height: parent.height

                Item {
                    width: 100
                    height: 100
                    anchors.centerIn: parent

                    Canvas {
                        id: swapCanvas
                        anchors.fill: parent
                        property real val: Math.min(100, Math.max(0, root.swapPercent)) / 100
                        property color colorVal: root.swapPercent > 85 ? Theme.red : Theme.cyan
                        onValChanged: requestPaint()
                        onColorValChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var cx = width / 2
                            var cy = height / 2
                            var r = (width - 12) / 2
                            var start = -Math.PI / 2
                            var end = start + (val * 2 * Math.PI)

                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                            ctx.strokeStyle = Qt.alpha(Theme.fg, 0.1)
                            ctx.lineWidth = 6
                            ctx.stroke()

                            if (val > 0) {
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, start, end)
                                ctx.strokeStyle = colorVal
                                ctx.lineWidth = 7.5
                                ctx.lineCap = "round"
                                ctx.stroke()
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "SWAP"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(root.swapPercent) + "%"
                            color: Theme.cyan
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.swapUsedGB.toFixed(1) + " / " + root.swapTotalGB.toFixed(1) + " GB"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }

        // ================= PROCESSES TABLE =================
        Column {
            width: parent.width
            height: parent.height - 158
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
                        width: 60
                        radius: 14
                        color: root.sortBy === "cpu" ? Theme.yellow : (cpuMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05))
                        border.width: 0
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "CPU"
                            color: root.sortBy === "cpu" ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
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
                        width: 80
                        radius: 14
                        color: root.sortBy === "ram" ? Theme.accent : (ramMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.05))
                        border.width: 0
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "RAM"
                            color: root.sortBy === "ram" ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
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
                        width: 50
                        height: 24
                        Text {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
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
                        radius: 14
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

                            // CPU % Value
                            Item {
                                height: 22
                                width: 60
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                    text: (modelData.cpu || "0") + "%"
                                    color: root.sortBy === "cpu" ? Theme.yellow : Qt.alpha(Theme.fg, 0.8)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: root.sortBy === "cpu"
                                }
                            }

                            // RAM Usage Value (MB / GB)
                            Item {
                                height: 22
                                width: 80
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData.ram_str || "0 MB"
                                    color: root.sortBy === "ram" ? Theme.magenta : Qt.alpha(Theme.fg, 0.8)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: root.sortBy === "ram"
                                }
                            }

                            // PID Value
                            Item {
                                height: 22
                                width: 50
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData.pid || "-"
                                    color: Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                            // Spacer to align CPU, RAM, and PID with header row (matches 30px sort arrow pill)
                            Item {
                                height: 22
                                width: 30
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
