import QtQuick

BarModule {
    id: root

    active: popup.visible
    onClicked: popup.visible = !popup.visible

    SystemMonitorPopup {
        id: popup
        anchorItem: root
        defaultSort: "cpu"
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
            Behavior on color { ColorAnimation { duration: 250 } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            color: parent.valueColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: Theme.fontWeight
            Behavior on color { ColorAnimation { duration: 250 } }
        }
    }

    Row {
        spacing: 15
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: 4
        rightPadding: 4

        Seg {
            icon: "󰻠"
            iconColor: Theme.yellow
            value: Math.round(Sys.cpu) + "%"
            valueColor: Sys.cpu > 90 ? Theme.red : Theme.fg
        }
    }
}
