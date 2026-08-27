import QtQuick
import Quickshell

// The bar window. bspwm honors the dock strut natively (no WM patch): the
// panel claims 42px at the top and windows tile below it, gaps included.
PanelWindow {
    id: root

    property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Sys.barHeight + Sys.barMarginTop + Sys.barMarginBottom
    color: "transparent"
    visible: !Sys.isLocked && !Wm.isFullscreen

    Component { id: launcherComp; Launcher {} }
    Component { id: tagsComp; Tags {} }
    Component { id: titleComp; Title {} }
    Component { id: clockComp; Clock {} }
    Component { id: mediaComp; Media {} }
    Component { id: cpuComp; Cpu {} }
    Component { id: ramComp; Ram {} }
    Component { id: volumeComp; Volume {} }
    Component { id: brightnessComp; Brightness {} }
    Component { id: batteryComp; Battery {} }
    Component { id: screenshotComp; Screenshot {} }
    Component { id: bellComp; Bell {} }
    Component { id: clipboardComp; Clipboard {} }
    Component { id: controlCenterComp; ControlCenter {} }
    Component { id: trayComp; Tray {} }
    Component { id: powerButtonComp; PowerButton {} }

    function getComponent(id) {
        switch(id) {
            case "launcher": return launcherComp
            case "tags": return tagsComp
            case "title": return titleComp
            case "clock": return clockComp
            case "media": return mediaComp
            case "cpu": return cpuComp
            case "ram": return ramComp
            case "volume": return volumeComp
            case "brightness": return brightnessComp
            case "battery": return batteryComp
            case "screenshot": return screenshotComp
            case "bell": return bellComp
            case "clipboard": return clipboardComp
            case "control_center": return controlCenterComp
            case "tray": return trayComp
            case "power_button": return powerButtonComp
            default: return null
        }
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        anchors.topMargin: Sys.barMarginTop
        anchors.leftMargin: Sys.barMarginLeft
        anchors.rightMargin: Sys.barMarginRight
        anchors.bottomMargin: Sys.barMarginBottom

        radius: Sys.barRadius
        color: Sys.customBarBg
        border.width: 0
        border.color: Qt.alpha(Theme.accent, 0.35)

        Behavior on color { ColorAnimation { duration: 400 } }
        Behavior on border.color { ColorAnimation { duration: 400 } }

        Row {
            id: leftCluster
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: Sys.leftModules || []
                delegate: Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: root.getComponent(modelData)
                    visible: item ? item.visible : true
                }
            }
        }

        Row {
            id: centerCluster
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: Sys.centerModules || []
                delegate: Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: root.getComponent(modelData)
                    visible: item ? item.visible : true
                }
            }
        }     

        Row {
            id: rightCluster
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: Sys.rightModules || []
                delegate: Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: root.getComponent(modelData)
                    visible: item ? item.visible : true
                }
            }
        }
    }

    NotificationToast {
        anchorWindow: root
    }
}
