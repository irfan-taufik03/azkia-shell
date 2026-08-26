import QtQuick
import Quickshell
import Quickshell.Io

BarModule {
    id: root
    active: popup.visible

    property int brightness: 0

    property string brightnessIcon: {
        if (brightness <= 20)
            return "󰃜"

        if (brightness <= 40)
            return "󰃝"

        if (brightness <= 60)
            return "󰃞"

        if (brightness <= 80)
            return "󰃟"

        return "󰃠"
    }

    function updateBrightness(line) {
        const parts = line.trim().split(",")

        // intel_backlight,backlight,1714,40%,4285
        //
        // [0] device
        // [1] class
        // [2] current
        // [3] percentage
        // [4] max

        if (parts.length < 5)
            return

        const percent = parseInt(parts[3].replace("%", ""))

        if (!isNaN(percent))
            root.brightness = percent
    }

    // Read brightness
    Process {
        id: brightnessGet

        command: [
            "brightnessctl",
            "-d",
            "intel_backlight",
            "-m"
        ]

        stdout: SplitParser {
            onRead: line => {
                root.updateBrightness(line)
            }
        }
    }

    // Poll brightness
    Timer {
        interval: 300
        running: true
        repeat: true

        onTriggered: {
            brightnessGet.running = false
            brightnessGet.running = true
        }
    }

    // Segment
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

            Behavior on color {
                ColorAnimation {
                    duration: 250
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter

            text: parent.value
            color: parent.valueColor

            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: Theme.fontWeight

            Behavior on color {
                ColorAnimation {
                    duration: 250
                }
            }
        }
    }

    onClicked: popup.visible = !popup.visible

    BrightnessPopup {
        id: popup
        anchorItem: root
    }

    Row {
        spacing: 15

        anchors.verticalCenter: parent.verticalCenter

        leftPadding: 4
        rightPadding: 4

        Seg {
            icon: root.brightnessIcon
            iconColor: Theme.red
            value: root.brightness + "%"
        }
    }
}
