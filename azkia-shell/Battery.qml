import QtQuick

// All system numbers, flat on the bar: cpu / ram / disk, plus battery on
// laptops (auto-hidden when no battery exists). Icons keep the slstatus
// color story — red / blue / yellow — pulled from the live theme.
// No pill background on purpose: boxes are for things you can click.
BarModule {
    id: root
    active: popup.visible
    onClicked: popup.visible = !popup.visible

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

    // one Row child so segment spacing is ours, not BarModule's tighter default
    Row {
        spacing: 15
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: 4
        rightPadding: 4

        Seg {
            visible: Sys.hasBattery
            icon: Sys.batteryCharging ? "󰂄"
                : Sys.battery < 15 ? "󰁻"
                : Sys.battery < 40 ? "󰁾"
                : Sys.battery < 80 ? "󰂁"
                : "󰁹"
            iconColor: Sys.batteryCharging ? Theme.green
                : Sys.battery < 15 ? Theme.red
                : Sys.battery < 40 ? Theme.yellow
                : Theme.green
            value: Math.round(Sys.battery) + "%"
            valueColor: !Sys.batteryCharging && Sys.battery < 15 ? Theme.red : Theme.fg
        }
    }

    BatteryPopup {
        id: popup
        anchorItem: root
    }
}
