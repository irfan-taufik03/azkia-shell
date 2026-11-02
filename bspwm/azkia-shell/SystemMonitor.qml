import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: 24

    property real memUsedGB: 0
    property real memPercent: 0

    readonly property bool active: popup.visible
    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool pressed: mouseArea.pressed

    scale: pressed ? 0.95 : 1.0
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

    Timer {
        id: hoverTimer
        interval: 150
        repeat: false
    }

    onHoveredChanged: {
        if (root.hovered) hoverTimer.restart()
        else hoverTimer.stop()
    }

    PopupWindow {
        id: tooltipWindow

        anchor.item: root
        anchor.rect.x: Math.round((root.width - implicitWidth) / 2)
        anchor.rect.y: Math.round((Sys.barHeight - root.implicitHeight) / 2 + root.implicitHeight + 2)

        implicitWidth: tooltipText.implicitWidth + 24
        implicitHeight: tooltipText.implicitHeight + 14

        visible: root.hovered && !hoverTimer.running && (!popup || !popup.visible)
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Sys.customBarBg
            border.width: 1
            border.color: Sys.customModuleBorder
            radius: 10

            Text {
                id: tooltipText
                anchors.centerIn: parent
                text: "System Monitor"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        watchChanges: true
        onLoaded: parseMem()
        onFileChanged: reload()
    }

    function parseMem() {
        const text = meminfo.text()
        if (!text) return

        const totalMatch = text.match(/MemTotal:\s+(\d+)/)
        const availableMatch = text.match(/MemAvailable:\s+(\d+)/)

        if (totalMatch && availableMatch) {
            const totalKB = Number(totalMatch[1])
            const availableKB = Number(availableMatch[1])
            const usedKB = totalKB - availableKB

            root.memUsedGB = usedKB / 1048576
            root.memPercent = (usedKB / totalKB) * 100
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: meminfo.reload()
    }

    Row {
        id: row
        spacing: 6
        anchors.verticalCenter: parent.verticalCenter

        // CPU Sub-Pill
        Rectangle {
            height: 24
            implicitWidth: cpuRow.implicitWidth + 16
            radius: Sys.moduleRadius
            color: root.active ? Qt.alpha(Theme.accent, 0.22)
                 : (root.hovered ? Sys.customModuleHoverBg : Sys.customModuleBg)
            border.width: 1
            border.color: root.active ? Sys.customModuleBorder : (root.hovered ? Qt.alpha(Theme.fg, 0.25) : Sys.customModuleBorder)
            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                id: cpuRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰻠"
                    color: Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(Sys.cpu) + "%"
                    color: Sys.cpu > 90 ? Theme.red : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.weight: Theme.fontWeight
                }
            }
        }

        // RAM Sub-Pill
        Rectangle {
            height: 24
            implicitWidth: ramRow.implicitWidth + 16
            radius: Sys.moduleRadius
            color: root.active ? Qt.alpha(Theme.accent, 0.22)
                 : (root.hovered ? Sys.customModuleHoverBg : Sys.customModuleBg)
            border.width: 1
            border.color: root.active ? Sys.customModuleBorder : (root.hovered ? Qt.alpha(Theme.fg, 0.25) : Sys.customModuleBorder)
            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                id: ramRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍛"
                    color: Theme.magenta
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.memUsedGB.toFixed(1) + "GB"
                    color: root.memPercent > 90 ? Theme.red : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.weight: Theme.fontWeight
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.toggle()
    }

    SystemMonitorPopup {
        id: popup
        anchorItem: root
        defaultSort: "ram"
    }
}
