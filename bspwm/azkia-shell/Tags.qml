import QtQuick
import Quickshell

// 10 bspwm desktops wrapped in a standard BarModule pill:
// focused = wide accent pill (Theme.selbg),
// occupied = brighter pill cell (Qt.alpha(Theme.fg, 0.25)),
// default (empty) = bar background color (Theme.bg).
BarModule {
    id: root

    property string screenName: ""
    interactive: false
    bgColor: Sys.customModuleBg

    property int hoveredTagIndex: -1
    property var hoveredTagItem: null

    Timer {
        id: hoverTimer
        interval: 150
        repeat: false
    }

    PopupWindow {
        id: tooltipWindow

        anchor.item: root.hoveredTagItem ? root.hoveredTagItem : root
        anchor.rect.x: root.hoveredTagItem ? Math.round((root.hoveredTagItem.width - implicitWidth) / 2) : 0
        anchor.rect.y: Math.round((Sys.barHeight - root.implicitHeight) / 2 + root.implicitHeight + 2)

        implicitWidth: tooltipText.implicitWidth + 24
        implicitHeight: tooltipText.implicitHeight + 14

        visible: root.hoveredTagIndex !== -1 && !hoverTimer.running && root.hoveredTagItem !== null
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
                text: "Workspace " + (root.hoveredTagIndex + 1)
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }

    onScrolled: dir => Wm.cycleTag(dir > 0 ? -1 : 1)

    Row {
        id: tagRow
        spacing: 5
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: 2
        rightPadding: 2

        Repeater {
            model: Wm.tagCount

            Rectangle {
                id: tag
                required property int index
                readonly property bool selected: (Wm.getSelTags(root.screenName) & (1 << index)) !== 0
                readonly property bool occupied: (Wm.getOccTags(root.screenName) & (1 << index)) !== 0
                readonly property bool urgent: (Wm.getUrgTags(root.screenName) & (1 << index)) !== 0

                width: selected ? 35 : occupied ? 25 : urgent ? 25 : 20
                height: 16
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                color: urgent ? Theme.red
                     : selected ? (tagMouse.containsMouse ? Theme.accentHover : Theme.selbg)
                     : tagMouse.containsMouse ? Qt.alpha(Theme.fg, 0.50)
                     : occupied ? Qt.alpha(Theme.fg, 0.25)
                     : Qt.alpha(Theme.fg, 0.10)

                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 180 } }

                SequentialAnimation on opacity {
                    running: tag.urgent
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.5; duration: 500; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                }

                Text {
                    anchors.centerIn: parent
                    visible: true
                    text: tag.index + 1
                    color: tag.urgent ? Theme.bg
                         : tag.selected ? Theme.selfg
                         : tag.occupied ? Theme.fg
                         : Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    Behavior on color { ColorAnimation { duration: 180 } }
                }

                MouseArea {
                    id: tagMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onEntered: {
                        root.hoveredTagIndex = tag.index
                        root.hoveredTagItem = tag
                        if (!tooltipWindow.visible) {
                            hoverTimer.restart()
                        }
                    }
                    onExited: {
                        if (root.hoveredTagIndex === tag.index) {
                            hoverTimer.stop()
                            root.hoveredTagIndex = -1
                            root.hoveredTagItem = null
                        }
                    }
                    onClicked: m => {
                        if (m.button === Qt.MiddleButton)
                            Wm.sendToTag(tag.index, root.screenName)
                        else
                            Wm.viewTag(tag.index, root.screenName)
                    }
                    onWheel: w => Wm.cycleTag(w.angleDelta.y > 0 ? -1 : 1)
                }
            }
        }
    }
}

