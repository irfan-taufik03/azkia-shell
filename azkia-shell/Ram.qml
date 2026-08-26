import QtQuick
import Quickshell
import Quickshell.Io

BarModule {
    id: root

    property real memUsedGB: 0
    property real memPercent: 0

    active: popup.visible
    onClicked: popup.visible = !popup.visible

    SystemMonitorPopup {
        id: popup
        anchorItem: root
        defaultSort: "ram"
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

    component Seg: Row {
        property string icon
        property color iconColor
        property string value
        property color valueColor: Theme.fg
        spacing: 5
        anchors.verticalCenter: parent.verticalCenter

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.icon
            color: parent.iconColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            color: parent.valueColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: Theme.fontWeight
        }
    }

    Row {
        spacing: 15
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: 4
        rightPadding: 4

        Seg {
            icon: "󰍛"
            iconColor: Theme.magenta
            value: root.memUsedGB.toFixed(1) + "GB"
            valueColor: root.memPercent > 90 ? Theme.red : Theme.fg
        }
    }
}
