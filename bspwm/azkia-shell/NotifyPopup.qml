import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Popout {
    id: root

    cardWidth: 350
    cardHeight: 430

    function toggle() { visible = !visible }

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggle() }
    }

    property string searchText: ""
    property int selectedIndex: 0

    readonly property var filteredNotifications: {
        if (!root.searchText) return Sys.historyNotifications
        const q = root.searchText.toLowerCase()
        return Sys.historyNotifications.filter(n => {
            const text = ((n.appName || "") + " " + (n.summary || "") + " " + (n.body || "")).toLowerCase()
            return text.includes(q)
        })
    }

    onFilteredNotificationsChanged: root.selectedIndex = 0

    onVisibleChanged: {
        if (visible) {
            root.selectedIndex = 0
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
                    text: "󰂚"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Notifications"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Count Badge
                Rectangle {
                    height: 18
                    width: Math.max(18, countTxt.implicitWidth + 8)
                    radius: 9
                    color: Qt.alpha(Theme.accent, 0.2)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Sys.notifCount > 0

                    Text {
                        id: countTxt
                        anchors.centerIn: parent
                        text: Sys.notifCount
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            // DND & Clear Buttons
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // DND Toggle Button
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 24
                    width: dndRow.implicitWidth + 12
                    radius: 6
                    color: Sys.dndOn ? Qt.alpha(Theme.yellow, 0.25) : (dndMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.08))
                    border.width: 1
                    border.color: Sys.dndOn ? Theme.yellow : (dndMa.containsMouse ? Qt.alpha(Theme.yellow, 0.4) : Sys.customModuleBorder)

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: dndRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Sys.dndOn ? "󰪑" : "󰂜"
                            color: Sys.dndOn ? Theme.yellow : Qt.alpha(Theme.fg, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "DND"
                            color: Sys.dndOn ? Theme.yellow : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: Sys.dndOn
                        }
                    }

                    MouseArea {
                        id: dndMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Sys.toggleDnd()
                    }
                }

                // Clear All Button
                Rectangle {
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
                        onClicked: Sys.clearNotifications()
                    }
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
                        if (root.filteredNotifications.length > 0) {
                            root.selectedIndex = Math.min(root.filteredNotifications.length - 1, root.selectedIndex + 1)
                        }
                    }
                    Keys.onUpPressed: {
                        if (root.filteredNotifications.length > 0) {
                            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                        }
                    }
                    Keys.onDeletePressed: {
                        if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredNotifications.length) {
                            Sys.removeNotification(root.filteredNotifications[root.selectedIndex].id)
                        }
                    }
                    Keys.onBackPressed: event => {
                        if (searchInput.text === "" && root.selectedIndex >= 0 && root.selectedIndex < root.filteredNotifications.length) {
                            Sys.removeNotification(root.filteredNotifications[root.selectedIndex].id)
                        }
                    }

                    Text {
                        text: "Search notifications..."
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

                model: root.filteredNotifications

                // Empty state placeholder
                Item {
                    anchors.fill: parent
                    visible: root.filteredNotifications.length === 0

                    Column {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰂛"
                            color: Qt.alpha(Theme.fg, 0.25)
                            font.family: Theme.fontFamily
                            font.pixelSize: 28
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No notifications"
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
                    height: Math.max(54, contentCol.implicitHeight + 16)
                    radius: 8
                    color: index === root.selectedIndex ? Qt.alpha(Theme.accent, 0.25) : (itemMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Sys.customModuleBg)
                    border.width: 1
                    border.color: (index === root.selectedIndex || itemMa.containsMouse) ? Theme.accent : Sys.customModuleBorder

                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: itemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.selectedIndex = index
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10

                        // App Icon
                        Item {
                            width: 36
                            height: 36
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: Qt.alpha(Theme.accent, 0.15)

                                IconImage {
                                    id: iconImg
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    source: modelData.appIcon ? (modelData.appIcon.startsWith("/") || modelData.appIcon.startsWith("file://") ? modelData.appIcon : ("image://icon/" + modelData.appIcon)) : ""
                                    visible: iconImg.status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: iconImg.status !== Image.Ready
                                    text: "󰂚"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                }
                            }
                        }

                        // Content Column
                        Column {
                            id: contentCol
                            width: parent.width - 80
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            Row {
                                width: parent.width
                                spacing: 4

                                Text {
                                    text: modelData.appName || "App"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Text {
                                    text: "•"
                                    color: Qt.alpha(Theme.fg, 0.3)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }

                                Text {
                                    text: modelData.time || ""
                                    color: Qt.alpha(Theme.fg, 0.4)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }

                            Text {
                                width: parent.width
                                text: modelData.summary || ""
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: modelData.body !== ""
                                text: modelData.body || ""
                                color: Qt.alpha(Theme.fg, 0.7)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }
                        }

                        // Close Single Notification Button
                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            color: closeSingleMa.containsMouse ? Qt.alpha(Theme.red, 0.2) : "transparent"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: closeSingleMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.4)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: closeSingleMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: Sys.removeNotification(modelData.id)
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
