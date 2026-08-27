import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 480
    cardHeight: 390

    function toggle() { visible = !visible }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggle() }
    }

    property var apps: []
    property string searchText: ""
    property bool isGrid: false
    property int selectedIndex: 0

    readonly property var filteredApps: {
        if (!root.searchText) return root.apps
        const q = root.searchText.toLowerCase()
        return root.apps.filter(app => {
            const text = ((app.name || "") + " " + (app.comment || "") + " " + (app.exec || "")).toLowerCase()
            return text.includes(q)
        })
    }

    onFilteredAppsChanged: root.selectedIndex = 0

    // Fetch desktop apps list from python script
    Process {
        id: fetchProc
        command: ["python3", Sys.scriptPath("app_launcher.py"), "--get-json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.apps = JSON.parse(text)
                } catch (e) {
                    root.apps = []
                }
            }
        }
    }

    Component.onCompleted: fetchProc.running = true

    onVisibleChanged: {
        if (visible) {
            root.selectedIndex = 0
            if (root.apps.length === 0) {
                fetchProc.running = true
            }
            focusTimer.restart()
        } else {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--restore"])
            searchInput.text = ""
            root.searchText = ""
        }
    }

    Timer {
        id: focusTimer
        interval: 30
        onTriggered: {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py")])
            searchInput.forceActiveFocus()
        }
    }

    function launchApp(execCmd) {
        if (!execCmd) return
        Quickshell.execDetached(["python3", Sys.scriptPath("app_launcher.py"), "--launch", execCmd])
        root.visible = false
    }

    Column {
        anchors.fill: parent
        spacing: 10

        // ===== TOP BAR: SEARCH BAR + VIEW MODE BUTTONS =====
        Item {
            width: parent.width
            height: 32

            // Search Bar Input
            Rectangle {
                anchors.left: parent.left
                anchors.right: modeBtnRow.left
                anchors.rightMargin: 8
                height: 32
                radius: 8
                color: Qt.alpha(Theme.fg, 0.06)
                border.width: 1
                border.color: searchInput.activeFocus ? Theme.accent : Sys.customModuleBorder

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }

                    TextInput {
                        id: searchInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 25
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        clip: true
                        onTextChanged: root.searchText = text.toLowerCase().trim()

                        Keys.onDownPressed: {
                            if (root.filteredApps.length > 0) {
                                const step = root.isGrid ? 4 : 1
                                root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + step)
                            }
                        }
                        Keys.onUpPressed: {
                            if (root.filteredApps.length > 0) {
                                const step = root.isGrid ? 4 : 1
                                root.selectedIndex = Math.max(0, root.selectedIndex - step)
                            }
                        }
                        Keys.onRightPressed: {
                            if (root.isGrid && root.filteredApps.length > 0) {
                                root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + 1)
                            }
                        }
                        Keys.onLeftPressed: {
                            if (root.isGrid && root.filteredApps.length > 0) {
                                root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                            }
                        }
                        Keys.onReturnPressed: {
                            if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredApps.length) {
                                root.launchApp(root.filteredApps[root.selectedIndex].exec)
                            }
                        }
                        Keys.onEnterPressed: {
                            if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredApps.length) {
                                root.launchApp(root.filteredApps[root.selectedIndex].exec)
                            }
                        }

                        Text {
                            text: "Search applications..."
                            color: Qt.alpha(Theme.fg, 0.35)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            visible: !searchInput.text
                        }
                    }
                }
            }

            // View Mode Toggle Buttons (List & Grid)
            Row {
                id: modeBtnRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                // List View Button
                Rectangle {
                    width: 32
                    height: 32
                    radius: 8
                    color: !root.isGrid
                           ? Qt.alpha(Theme.accent, 0.25)
                           : listBtnMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.06)
                    border.width: 1
                    border.color: !root.isGrid ? Theme.accent : Sys.customModuleBorder

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: ""
                        color: !root.isGrid ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: listBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.isGrid = false
                            focusTimer.restart()
                        }
                    }
                }

                // Grid View Button
                Rectangle {
                    width: 32
                    height: 32
                    radius: 8
                    color: root.isGrid
                           ? Qt.alpha(Theme.accent, 0.25)
                           : gridBtnMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.06)
                    border.width: 1
                    border.color: root.isGrid ? Theme.accent : Sys.customModuleBorder

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰕰"
                        color: root.isGrid ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: gridBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.isGrid = true
                            focusTimer.restart()
                        }
                    }
                }
            }
        }

        // ===== VIEWS CONTAINER =====
        Item {
            width: parent.width
            height: parent.height - 42

            // ===== GRID VIEW MODE =====
            GridView {
                id: gridView
                anchors.fill: parent
                visible: root.isGrid
                clip: true
                cellWidth: 112
                cellHeight: 96
                currentIndex: root.selectedIndex

                model: root.filteredApps

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 8
                        color: index === root.selectedIndex ? Qt.alpha(Theme.accent, 0.25) : (gridItemMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                        border.width: 1
                        border.color: (index === root.selectedIndex || gridItemMa.containsMouse) ? Theme.accent : Sys.customModuleBorder

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            width: parent.width - 12

                            // Icon Container
                            Item {
                                width: 40
                                height: 40
                                anchors.horizontalCenter: parent.horizontalCenter

                                Image {
                                    anchors.fill: parent
                                    asynchronous: true
                                    sourceSize.width: 40
                                    sourceSize.height: 40
                                    visible: modelData && modelData.icon_path !== ""
                                    source: (modelData && modelData.icon_path) ? "file://" + modelData.icon_path : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    cache: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !modelData || modelData.icon_path === ""
                                    text: "󰀻"
                                    color: Theme.magenta
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 24
                                }
                            }

                            // App Name
                            Text {
                                width: parent.width
                                text: modelData ? modelData.name : ""
                                color: index === root.selectedIndex ? Theme.accent : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }
                        }

                        MouseArea {
                            id: gridItemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedIndex = index
                                root.launchApp(modelData ? modelData.exec : "")
                            }
                        }
                    }
                }
            }

            // ===== LIST VIEW MODE =====
            ListView {
                id: listView
                anchors.fill: parent
                visible: !root.isGrid
                clip: true
                spacing: 6
                currentIndex: root.selectedIndex

                model: root.filteredApps

                delegate: Rectangle {
                    id: listItemDelegate
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 48
                    radius: 8
                    color: index === root.selectedIndex ? Qt.alpha(Theme.accent, 0.25) : (listItemMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                    border.width: 1
                    border.color: (index === root.selectedIndex || listItemMa.containsMouse) ? Theme.accent : Sys.customModuleBorder

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        // Icon
                        Item {
                            width: 34
                            height: 34
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                sourceSize.width: 34
                                sourceSize.height: 34
                                visible: modelData && modelData.icon_path !== ""
                                source: (modelData && modelData.icon_path) ? "file://" + modelData.icon_path : ""
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                cache: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !modelData || modelData.icon_path === ""
                                text: "󰀻"
                                color: Theme.magenta
                                font.family: Theme.fontFamily
                                font.pixelSize: 20
                            }
                        }

                        // Content Column
                        Column {
                            width: parent.width - 56
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: modelData ? modelData.name : ""
                                color: index === root.selectedIndex ? Theme.accent : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: modelData && modelData.comment !== ""
                                text: modelData ? modelData.comment : ""
                                color: Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: listItemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedIndex = index
                            root.launchApp(modelData ? modelData.exec : "")
                        }
                    }
                }
            }

            // Floating Scrollbar Thumb
            Item {
                id: scrollTrack
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 20

                readonly property var activeView: root.isGrid ? gridView : listView
                readonly property bool isScrolling: activeView.moving || activeView.flicking || activeView.dragging
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
                        const v = scrollTrack.activeView
                        const trackH = scrollTrack.height
                        const thumbH = scrollThumb.height
                        if (trackH <= thumbH) return
                        const maxThumbY = trackH - thumbH
                        const clampedY = Math.max(0, Math.min(mouseY - thumbH / 2, maxThumbY))
                        const ratio = clampedY / maxThumbY
                        const maxContentY = v.contentHeight - v.height
                        if (maxContentY > 0) {
                            v.contentY = ratio * maxContentY
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
                        const v = scrollTrack.activeView
                        const maxContentY = v.contentHeight - v.height
                        const maxThumbY = scrollTrack.height - height
                        if (maxContentY > 0 && maxThumbY > 0) {
                            return Math.max(0, Math.min((v.contentY / maxContentY) * maxThumbY, maxThumbY))
                        }
                        return 0
                    }
                    radius: 5
                    color: scrollMa.pressed ? Qt.alpha(Theme.accent, 0.7) : (scrollMa.containsMouse ? Qt.alpha(Theme.fg, 0.40) : Qt.alpha(Theme.fg, 0.20))
                    opacity: (scrollTrack.activeView.contentHeight > scrollTrack.activeView.height && scrollTrack.showThumb) ? 1.0 : 0.0

                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
    }
}
