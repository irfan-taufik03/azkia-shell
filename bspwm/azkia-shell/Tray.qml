import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// StatusNotifierItem tray (SNI over DBus, works fine on X11).
// Left click activates, right click opens the item's menu.
Rectangle {
    id: root

    readonly property bool hasItems: trayRepeater.count > 0
    visible: true
    implicitWidth: hasItems ? Math.max(28, trayRow.implicitWidth + 12) : 28
    implicitHeight: 24
    radius: Sys.moduleRadius
    color: Sys.customModuleBg
    border.width: 1
    border.color: Sys.customModuleBorder

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: 4

        // Placeholder icon when no system tray items exist
        Item {
            width: 16
            height: 16
            visible: !root.hasItems
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: "󰍜"
                color: Qt.alpha(Theme.fg, 0.35)
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }

        Repeater {
            id: trayRepeater
            model: SystemTray.items

            MouseArea {
                id: trayItem
                required property SystemTrayItem modelData

                width: 24
                height: 24
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: trayItem.containsMouse ? Sys.customModuleHoverBg : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 16
                    source: trayItem.modelData.icon
                }

                QsMenuAnchor {
                    id: menuAnchor
                    menu: trayItem.modelData.menu
                    anchor.item: trayItem
                    anchor.rect.y: trayItem.height + 6
                }

                onClicked: m => {
                    if (m.button === Qt.LeftButton)
                        modelData.activate()
                    else if (m.button === Qt.MiddleButton)
                        modelData.secondaryActivate()
                    else if (modelData.hasMenu)
                        menuAnchor.open()
                }
            }
        }
    }
}
