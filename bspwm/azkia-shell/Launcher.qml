import QtQuick
import Quickshell

BarModule {
    id: root
    active: popup ? popup.visible : false

    // Screen this launcher belongs to (set by Bar.qml)
    property string screenName: ""

    iconImage: Sys.launcherLogo
    iconImageSize: Sys.launcherIconSize

    Timer {
        id: hoverTimer
        interval: 150
        repeat: false
    }

    onHoveredChanged: {
        if (root.hovered) hoverTimer.restart()
        else hoverTimer.stop()
    }

    // Respond to global IPC toggle only if the signal targets our screen
    Connections {
        target: Wm
        function onLauncherToggleRequested(screenName) {
            if (screenName && screenName === root.screenName) {
                popup.toggle()
            }
        }
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
                text: "Application Launcher"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Wm.openLauncher()
        } else {
            popup.toggle()
        }
    }

    LauncherPopup {
        id: popup
        anchorItem: root
    }
}
