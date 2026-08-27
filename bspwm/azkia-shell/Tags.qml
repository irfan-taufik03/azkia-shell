import QtQuick

// 12 bspwm desktops wrapped in a standard BarModule pill:
// focused = wide accent pill (Theme.selbg),
// occupied = brighter pill cell (Qt.alpha(Theme.fg, 0.25)),
// default (empty) = bar background color (Theme.bg).
BarModule {
    id: root

    interactive: false
    bgColor: Sys.customModuleBg

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
                readonly property bool selected: (Wm.seltags & (1 << index)) !== 0
                readonly property bool occupied: (Wm.occtags & (1 << index)) !== 0
                readonly property bool urgent: (Wm.urgtags & (1 << index)) !== 0

                width: selected ? 35 : occupied ? 25 : 20
                height: 16
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                color: urgent ? Theme.red
                     : selected ? Theme.selbg
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
                    onClicked: m => {
                        if (m.button === Qt.MiddleButton)
                            Wm.sendToTag(tag.index)
                        else
                            Wm.viewTag(tag.index)
                    }
                    onWheel: w => Wm.cycleTag(w.angleDelta.y > 0 ? -1 : 1)
                }
            }
        }
    }
}
