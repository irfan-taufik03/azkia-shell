import QtQuick
import Quickshell
import Quickshell.Widgets

PopupWindow {
    id: root

    property PanelWindow anchorWindow: null

    anchor.window: anchorWindow
    anchor.rect.x: (anchorWindow ? anchorWindow.width : 1920) - implicitWidth - 16
    anchor.rect.y: (anchorWindow ? anchorWindow.height : 40) + 12

    implicitWidth: 360
    implicitHeight: activeToasts.length > 0 ? toastCol.implicitHeight + 20 : 0
    visible: activeToasts.length > 0
    color: "transparent"

    property var activeToasts: []



    Connections {
        target: Sys
        function onNotificationReceived(notif) {
            if (Sys.dndOn) return

            const toastList = root.activeToasts.slice()
            toastList.unshift(notif)
            if (toastList.length > 4) toastList.pop()
            root.activeToasts = toastList
        }
    }

    function removeToast(id) {
        root.activeToasts = root.activeToasts.filter(t => t.id !== id)
    }

    Column {
        id: toastCol
        width: 360
        spacing: 8

        Repeater {
            model: root.activeToasts

            delegate: Rectangle {
                id: card
                width: 360
                height: Math.max(76, cardRow.implicitHeight + 24)
                radius: 12
                color: Sys.customBarBg
                border.width: 1
                border.color: Sys.customModuleBorder

                readonly property var toastData: modelData

                Timer {
                    id: dismissTimer
                    interval: 4500
                    running: !toastMa.containsMouse
                    onTriggered: root.removeToast(card.toastData.id)
                }

                MouseArea {
                    id: toastMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.removeToast(card.toastData.id)
                }

                Row {
                    id: cardRow
                    width: parent.width - 24
                    anchors.centerIn: parent
                    spacing: 12

                    // ================= LEFT COLUMN: LARGE APP ICON =================
                    Rectangle {
                        width: 56
                        height: 56
                        radius: 14
                        color: Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.12)
                        anchors.verticalCenter: parent.verticalCenter

                        IconImage {
                            id: iconImg
                            anchors.centerIn: parent
                            width: 40
                            height: 40
                            source: card.toastData.appIcon ? (card.toastData.appIcon.startsWith("/") || card.toastData.appIcon.startsWith("file://") ? card.toastData.appIcon : ("image://icon/" + card.toastData.appIcon)) : ""
                            visible: iconImg.status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: iconImg.status !== Image.Ready
                            text: "󰂚"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 28
                        }
                    }

                    // ================= RIGHT COLUMN: TITLE, BODY, TIME, CLOSE BUTTON =================
                    Column {
                        width: parent.width - 68
                        spacing: 3
                        anchors.verticalCenter: parent.verticalCenter

                        // Top Header Line: App Name (Left) & Time + Close X (Far Right)
                        Item {
                            width: parent.width
                            height: 18

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.toastData.appName
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, parent.width - 80)
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Text {
                                    text: card.toastData.time
                                    color: Qt.alpha(Theme.fg, 0.45)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                // Close X Button at Far Top-Right
                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: closeMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : "transparent"
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        color: closeMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.6)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: closeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.removeToast(card.toastData.id)
                                    }
                                }
                            }
                        }

                        // Summary / Title
                        Text {
                            width: parent.width
                            text: card.toastData.summary
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        // Body Text
                        Text {
                            width: parent.width
                            text: card.toastData.body
                            color: Qt.alpha(Theme.fg, 0.8)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            visible: card.toastData.body !== ""
                        }
                    }
                }
            }
        }
    }
}
