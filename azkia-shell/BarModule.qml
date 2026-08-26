import QtQuick

// Base pill for bar modules: optional nerd-font icon + label, hover feedback,
// click/scroll signals. Extra content can be added as children.
Rectangle {
    id: root

    property string icon: ""
    property string iconImage: ""
    property int iconImageSize: 18
    property color iconColor: Sys.customModuleIconColor
    // some glyphs (e.g. Font Logos ) are missing from JetBrainsMono NF here
    property string iconFont: Theme.fontFamily
    property string label: ""
    property color labelColor: Theme.fg
    property bool interactive: true
    property bool active: false
    property color bgColor: Sys.customModuleBg
    property color hoverBgColor: Sys.customModuleHoverBg
    property color activeBgColor: Sys.customModuleActiveBg
    readonly property bool hovered: mouse.containsMouse

    signal clicked(var mouse)
    signal scrolled(int dir)

    default property alias extraContent: row.data

    implicitHeight: 24
    implicitWidth: row.implicitWidth + 12
    radius: Sys.moduleRadius
    color: active ? root.activeBgColor
         : (mouse.containsMouse && interactive ? root.hoverBgColor : root.bgColor)
    border.width: 1
    border.color: active ? Theme.accent : (mouse.containsMouse && interactive ? Qt.alpha(Theme.fg, 0.25) : Sys.customModuleBorder)
    // tactile press feedback — slow-starting apps otherwise make a click
    // feel like it didn't register
    scale: mouse.pressed && interactive ? 0.9 : 1

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Item {
            visible: root.icon !== "" || root.iconImage !== ""

            width: root.iconImage !== "" ? root.iconImageSize : iconText.implicitWidth
            height: root.iconImage !== "" ? root.iconImageSize : 18

            Text {
                id: iconText

                visible: root.iconImage === "" && root.icon !== ""
                anchors.centerIn: parent

                text: root.icon
                color: root.iconColor
                font.family: root.iconFont
                font.pixelSize: Theme.iconSize

                Behavior on color {
                  ColorAnimation {
                    duration: 250
                  }
                }
            }

            Image {
                visible: root.iconImage !== ""
                anchors.centerIn: parent

                width: root.iconImageSize
                height: root.iconImageSize

                source: root.iconImage
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }

        Text {
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root.labelColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: Theme.fontWeight
            Behavior on color { ColorAnimation { duration: 250 } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: m => root.clicked(m)
        onWheel: w => root.scrolled(w.angleDelta.y > 0 ? 1 : -1)
    }
}
