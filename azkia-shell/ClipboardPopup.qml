import QtQuick
import Quickshell
import Quickshell.Io

Popout {
    id: root

    cardWidth: 350
    cardHeight: 430

    function toggle() { visible = !visible }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggle() }
    }

    property var historyItems: []
    property string searchText: ""
    property int selectedIndex: 0

    readonly property var filteredClips: {
        if (!root.searchText) return root.historyItems
        const q = root.searchText.toLowerCase()
        return root.historyItems.filter(item => {
            const text = (item.text || "").toLowerCase()
            return text.includes(q)
        })
    }

    onFilteredClipsChanged: root.selectedIndex = 0

    // Read history from python script
    Process {
        id: fetchProc
        command: ["python3", Sys.scriptPath("clip_daemon.py"), "--get-json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    if (JSON.stringify(parsed) !== JSON.stringify(root.historyItems)) {
                        root.historyItems = parsed
                    }
                } catch (e) {
                    root.historyItems = []
                }
            }
        }
    }

    Timer {
        interval: 1500
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchProc.running = true
    }

    onVisibleChanged: {
        if (visible) {
            root.selectedIndex = 0
            fetchProc.running = true
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

    function copyItem(itemId) {
        Quickshell.execDetached(["python3", Sys.scriptPath("clip_daemon.py"), "--copy", itemId])
        root.visible = false
    }

    function deleteItem(itemId) {
        Quickshell.execDetached(["python3", Sys.scriptPath("clip_daemon.py"), "--delete", itemId])
        fetchTimer.restart()
    }

    function clearAll() {
        Quickshell.execDetached(["python3", Sys.scriptPath("clip_daemon.py"), "--clear"])
        root.historyItems = []
    }

    Timer {
        id: fetchTimer
        interval: 300
        onTriggered: fetchProc.running = true
    }

    Column {
        anchors.fill: parent
        spacing: 10

        // ===== HEADER =====
        Item {
            width: parent.width
            height: 28

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰨸"
                    color: Theme.magenta
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Clipboard History"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }

                // Count Badge
                Rectangle {
                    height: 18
                    width: Math.max(18, countTxt.implicitWidth + 8)
                    radius: 9
                    color: Qt.alpha(Theme.magenta, 0.2)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.filteredClips.length > 0

                    Text {
                        id: countTxt
                        anchors.centerIn: parent
                        text: root.filteredClips.length
                        color: Theme.magenta
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            // Clear All Button
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 24
                width: clearRow.implicitWidth + 12
                radius: 6
                color: clearMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : Qt.alpha(Theme.fg, 0.08)
                border.width: 1
                border.color: clearMa.containsMouse ? Qt.alpha(Theme.red, 0.5) : Sys.customModuleBorder

                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    id: clearRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        color: Theme.red
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Clear"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: clearMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.clearAll()
                }
            }
        }

        // ===== SEARCH BAR =====
        Rectangle {
            width: parent.width
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
                        if (root.filteredClips.length > 0) {
                            root.selectedIndex = Math.min(root.filteredClips.length - 1, root.selectedIndex + 1)
                        }
                    }
                    Keys.onUpPressed: {
                        if (root.filteredClips.length > 0) {
                            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                        }
                    }
                    Keys.onReturnPressed: {
                        if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredClips.length) {
                            root.copyItem(root.filteredClips[root.selectedIndex].id)
                        }
                    }
                    Keys.onEnterPressed: {
                        if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredClips.length) {
                            root.copyItem(root.filteredClips[root.selectedIndex].id)
                        }
                    }
                    Keys.onDeletePressed: {
                        if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredClips.length) {
                            root.deleteItem(root.filteredClips[root.selectedIndex].id)
                        }
                    }

                    Text {
                        text: "Search clipboard..."
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        visible: !searchInput.text
                    }
                }
            }
        }

        // ===== LIST VIEW CONTAINER =====
        Item {
            width: parent.width
            height: parent.height - 80

            ListView {
                id: listView
                anchors.fill: parent
                clip: true
                spacing: 6
                currentIndex: root.selectedIndex

                model: root.filteredClips

                // Empty state
                Item {
                    anchors.fill: parent
                    visible: root.filteredClips.length === 0

                    Column {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰨸"
                            color: Qt.alpha(Theme.fg, 0.25)
                            font.family: Theme.fontFamily
                            font.pixelSize: 28
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Clipboard is empty"
                            color: Qt.alpha(Theme.fg, 0.35)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }

                delegate: Rectangle {
                    id: itemDelegate
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: Math.max(48, contentCol.implicitHeight + 16)
                    radius: 8
                    color: index === root.selectedIndex ? Qt.alpha(Theme.accent, 0.25) : (itemMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                    border.width: 1
                    border.color: (index === root.selectedIndex || itemMa.containsMouse) ? Theme.accent : Sys.customModuleBorder

                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: itemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.selectedIndex = index
                            root.copyItem(modelData.id)
                        }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        // Left Container (Thumbnail Preview or Icon)
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 6
                            color: Qt.alpha(Theme.fg, 0.08)
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            layer.enabled: true

                            Image {
                                id: imgPrev
                                anchors.fill: parent
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                mipmap: true
                                sourceSize: Qt.size(64, 64)
                                source: (modelData.type === "image" && modelData.image_path) ? "file://" + modelData.image_path : ""
                            }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.type === "image" ? "󰋩" : "󰅍"
                                color: modelData.type === "image" ? Theme.cyan : Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                visible: modelData.type !== "image" || imgPrev.status !== Image.Ready
                            }
                        }

                        // Text Content Column
                        Column {
                            id: contentCol
                            width: parent.width - 74
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                width: parent.width
                                text: modelData.preview || modelData.text || "Empty"
                                color: index === root.selectedIndex ? Theme.accent : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }

                            Text {
                                width: parent.width
                                text: modelData.time || ""
                                color: Qt.alpha(Theme.fg, 0.4)
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                            }
                        }

                        // Delete Item Button
                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            color: deleteMa.containsMouse ? Qt.alpha(Theme.red, 0.2) : "transparent"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: deleteMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.4)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: deleteMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.deleteItem(modelData.id)
                            }
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

                readonly property bool isScrolling: listView.moving || listView.flicking || listView.dragging
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
                        const maxContentY = listView.contentHeight - listView.height
                        if (maxContentY > 0) {
                            listView.contentY = ratio * maxContentY
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
                        const maxContentY = listView.contentHeight - listView.height
                        const maxThumbY = scrollTrack.height - height
                        if (maxContentY > 0 && maxThumbY > 0) {
                            return Math.max(0, Math.min((listView.contentY / maxContentY) * maxThumbY, maxThumbY))
                        }
                        return 0
                    }
                    radius: 5
                    color: scrollMa.pressed ? Qt.alpha(Theme.accent, 0.7) : (scrollMa.containsMouse ? Qt.alpha(Theme.fg, 0.40) : Qt.alpha(Theme.fg, 0.20))
                    opacity: (listView.contentHeight > listView.height && scrollTrack.showThumb) ? 1.0 : 0.0

                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
    }
}
