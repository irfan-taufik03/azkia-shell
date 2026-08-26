import QtQuick
import Quickshell

BarModule {
    id: root

    property string displayTitle: Wm.title
    property string appIconPath: Wm.appIconPath

    implicitWidth: contentRow.implicitWidth + 16

    Row {
        id: contentRow

        x: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // Application Desktop Icon Image
        Item {
            width: 17
            height: 17
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.fill: parent
                visible: root.appIconPath !== ""
                source: root.appIconPath !== "" ? "file://" + root.appIconPath : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                cache: true
            }

            Text {
                anchors.centerIn: parent
                visible: root.appIconPath === ""
                text: ""
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                verticalAlignment: Text.AlignVCenter
            }
        }

        Text {
            text: displayTitle.length > 35
                ? displayTitle.slice(0, 32) + "..."
                : (displayTitle !== "" ? displayTitle : "bspwm Desktop")

            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            verticalAlignment: Text.AlignVCenter
        }
    }

    interactive: false
}
