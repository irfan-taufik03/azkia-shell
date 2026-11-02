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
    visible: !Sys.isLocked && (!Wm.isFullscreen || Sys.isPolkitActive)

    Component { id: launcherComp; Launcher { screenName: root.modelData ? root.modelData.name : "" } }
    Component { id: tagsComp; Tags { screenName: root.modelData ? root.modelData.name : "" } }
    Component { id: titleComp; Title {} }
    Component { id: clockComp; Dash {} }
    Component { id: mediaComp; Media {} }
    Component { id: systemMonitorComp; SystemMonitor {} }
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
            case "dash": return clockComp
            case "media": return mediaComp
            case "system_monitor": return systemMonitorComp
            case "cpu": return systemMonitorComp
            case "ram": return systemMonitorComp
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
        x: Sys.barMarginLeft
        y: Sys.barMarginTop
        width: root.width - Sys.barMarginLeft - Sys.barMarginRight
        height: Sys.barHeight

        radius: Sys.barRadius
        color: Sys.customBarBg
        border.width: 1
        border.color: Sys.customModuleBorder

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

        // Dimming overlay when Polkit dialog is active (redup tanpa tembus pandang)
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "#000000"
            opacity: Sys.isPolkitActive ? 0.35 : 0.0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }

    NotificationToast {
        anchorWindow: root
    }
}
