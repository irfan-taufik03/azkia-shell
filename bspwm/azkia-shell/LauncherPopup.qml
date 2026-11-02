import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 480
    cardHeight: 390



    property var apps: []
    property string searchText: ""
    property bool isGrid: false
    property int selectedIndex: -1

    readonly property var filteredApps: {
        if (!root.searchText) return root.apps
        const q = root.searchText.toLowerCase()
        return root.apps.filter(app => {
            const text = ((app.name || "") + " " + (app.comment || "") + " " + (app.exec || "")).toLowerCase()
            return text.includes(q)
        })
    }

    onFilteredAppsChanged: {
        root.selectedIndex = -1
        if (gridView) gridView.contentY = 0
        if (listView) listView.contentY = 0
    }

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
            root.selectedIndex = -1
            if (gridView) gridView.contentY = 0
            if (listView) listView.contentY = 0
            fetchProc.running = false
            fetchProc.running = true
            focusTimer.restart()
        } else {
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--restore"])
            searchInput.text = ""
            root.searchText = ""
            if (gridView) gridView.contentY = 0
            if (listView) listView.contentY = 0
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
            id: topBar
            width: parent.width
            height: 32
            z: 20

            // Search Bar Input
            Rectangle {
                anchors.left: parent.left
                anchors.right: modeBtnRow.left
                anchors.rightMargin: 8
                height: 32
                radius: 12
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
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.bg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        selectByMouse: true
                        clip: true
                        onTextChanged: root.searchText = text.toLowerCase().trim()

                        Keys.onEscapePressed: root.close()

                        Keys.onDownPressed: {
                            if (root.filteredApps.length > 0) {
                                const step = root.isGrid ? 4 : 1
                                if (root.selectedIndex < 0) {
                                    root.selectedIndex = 0
                                } else {
                                    root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + step)
                                }
                            }
                        }
                        Keys.onUpPressed: {
                            if (root.filteredApps.length > 0) {
                                const step = root.isGrid ? 4 : 1
                                if (root.selectedIndex < 0) {
                                    root.selectedIndex = root.filteredApps.length - 1
                                } else {
                                    root.selectedIndex = Math.max(0, root.selectedIndex - step)
                                }
                            }
                        }
                        Keys.onRightPressed: {
                            if (root.isGrid && root.filteredApps.length > 0) {
                                if (root.selectedIndex < 0) {
                                    root.selectedIndex = 0
                                } else {
                                    root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + 1)
                                }
                            }
                        }
                        Keys.onLeftPressed: {
                            if (root.isGrid && root.filteredApps.length > 0) {
                                if (root.selectedIndex < 0) {
                                    root.selectedIndex = 0
                                } else {
                                    root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                                }
                            }
                        }
                        Keys.onReturnPressed: {
                            if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredApps.length) {
                                root.launchApp(root.filteredApps[root.selectedIndex].exec)
                            } else if (root.selectedIndex < 0 && root.filteredApps.length > 0) {
                                root.launchApp(root.filteredApps[0].exec)
                            }
                        }
                        Keys.onEnterPressed: {
                            if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredApps.length) {
                                root.launchApp(root.filteredApps[root.selectedIndex].exec)
                            } else if (root.selectedIndex < 0 && root.filteredApps.length > 0) {
                                root.launchApp(root.filteredApps[0].exec)
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

                Timer {
                    id: modeTooltipTimer
                    interval: 150
                    repeat: false
                }

                // List View Button
                Rectangle {
                    id: listBtn
                    width: 32
                    height: 32
                    radius: 10
                    color: !root.isGrid
                           ? (listBtnMa.containsMouse ? Theme.accentHover : Theme.accent)
                           : listBtnMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.06)
                    border.width: 1
                    border.color: !root.isGrid ? (listBtnMa.containsMouse ? Theme.accentHover : Theme.accent) : Sys.customModuleBorder

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: ""
                        color: !root.isGrid ? Sys.customBarBg : Qt.alpha(Theme.fg, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: listBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (!gridTooltip.visible) modeTooltipTimer.restart()
                        }
                        onExited: modeTooltipTimer.stop()
                        onClicked: {
                            root.isGrid = false
                            focusTimer.restart()
                        }
                    }

                    Rectangle {
                        id: listTooltip
                        anchors.top: parent.bottom
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: listTooltipText.implicitWidth + 24
                        height: listTooltipText.implicitHeight + 14
                        color: Sys.customBarBg
                        border.width: 1
                        border.color: Sys.customModuleBorder
                        radius: 10
                        z: 999
                        visible: listBtnMa.containsMouse && !modeTooltipTimer.running

                        Text {
                            id: listTooltipText
                            anchors.centerIn: parent
                            text: "List View"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                    }
                }

                // Grid View Button
                Rectangle {
                    id: gridBtn
                    width: 32
                    height: 32
                    radius: 10
                    color: root.isGrid
                           ? (gridBtnMa.containsMouse ? Theme.accentHover : Theme.accent)
                           : gridBtnMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.06)
                    border.width: 1
                    border.color: root.isGrid ? (gridBtnMa.containsMouse ? Theme.accentHover : Theme.accent) : Sys.customModuleBorder

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰕰"
                        color: root.isGrid ? Sys.customBarBg : Qt.alpha(Theme.fg, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: gridBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (!listTooltip.visible) modeTooltipTimer.restart()
                        }
                        onExited: modeTooltipTimer.stop()
                        onClicked: {
                            root.isGrid = true
                            focusTimer.restart()
                        }
                    }

                    Rectangle {
                        id: gridTooltip
                        anchors.top: parent.bottom
                        anchors.topMargin: 8
                        anchors.right: parent.right
                        width: gridTooltipText.implicitWidth + 24
                        height: gridTooltipText.implicitHeight + 14
                        color: Sys.customBarBg
                        border.width: 1
                        border.color: Sys.customModuleBorder
                        radius: 10
                        z: 999
                        visible: gridBtnMa.containsMouse && !modeTooltipTimer.running

                        Text {
                            id: gridTooltipText
                            anchors.centerIn: parent
                            text: "Grid View"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
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

                transform: Translate { id: gridSlide; x: 0 }

                onVisibleChanged: {
                    if (visible) {
                        gridSlideXAnim.from = 50
                        gridSlideAnim.restart()
                    }
                }

                ParallelAnimation {
                    id: gridSlideAnim
                    NumberAnimation { id: gridSlideXAnim; target: gridSlide; property: "x"; from: 50; to: 0; duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { target: gridView; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
                }

                model: root.filteredApps

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight

                    readonly property bool isKeyboardSelected: (root.selectedIndex >= 0) && (index === root.selectedIndex)
                    readonly property bool isHovered: gridItemMa.containsMouse

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 14
                        color: isKeyboardSelected ? (isHovered ? Theme.accentHover : Theme.accent) : (isHovered ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                        border.width: 1
                        border.color: isKeyboardSelected ? (isHovered ? Theme.accentHover : Theme.accent) : (isHovered ? Theme.accent : Sys.customModuleBorder)

                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

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
                                    color: isKeyboardSelected ? Sys.customBarBg : Theme.magenta
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 24
                                }
                            }

                            // App Name
                            Text {
                                width: parent.width
                                text: modelData ? modelData.name : ""
                                color: isKeyboardSelected ? Sys.customBarBg : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: false
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap

                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
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

                transform: Translate { id: listSlide; x: 0 }

                onVisibleChanged: {
                    if (visible) {
                        listSlideXAnim.from = -50
                        listSlideAnim.restart()
                    }
                }

                ParallelAnimation {
                    id: listSlideAnim
                    NumberAnimation { id: listSlideXAnim; target: listSlide; property: "x"; from: -50; to: 0; duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { target: listView; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
                }

                model: root.filteredApps

                delegate: Rectangle {
                    id: listItemDelegate
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 48
                    radius: 14

                    readonly property bool isKeyboardSelected: (root.selectedIndex >= 0) && (index === root.selectedIndex)
                    readonly property bool isHovered: listItemMa.containsMouse

                    color: isKeyboardSelected ? (isHovered ? Theme.accentHover : Theme.accent) : (isHovered ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                    border.width: 1
                    border.color: isKeyboardSelected ? (isHovered ? Theme.accentHover : Theme.accent) : (isHovered ? Theme.accent : Sys.customModuleBorder)

                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

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
                                color: isKeyboardSelected ? Sys.customBarBg : Theme.magenta
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
                                color: isKeyboardSelected ? Sys.customBarBg : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                elide: Text.ElideRight

                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }

                            Text {
                                width: parent.width
                                visible: modelData && modelData.comment !== ""
                                text: modelData ? modelData.comment : ""
                                color: isKeyboardSelected ? Qt.alpha(Sys.customBarBg, 0.75) : Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight

                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
