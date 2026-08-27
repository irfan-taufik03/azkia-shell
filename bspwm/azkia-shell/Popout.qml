import QtQuick
import QtQuick.Effects
import Quickshell

// Shared shell for every bar popup: a fullscreen transparent catcher window
// with the styled card anchored under its bar item. Clicking anywhere
// outside the card closes it; Escape too (when X grants the popup key
// focus). All popups use this, so chrome and behavior stay identical.
PopupWindow {
    id: root

    property Item anchorItem
    property real cardWidth: 300
    property real cardHeight: 300
    readonly property real cardPadding: 14
    // right-edge panel mode (control center) instead of centered-under-anchor
    property bool alignRight: false
    property bool dismissOnClickOutside: true

    default property alias content: inner.data

    visible: false
    color: "transparent"

    mask: root.dismissOnClickOutside ? null : cardRegion

    Region {
        id: cardRegion
        item: card
    }

    anchor.item: anchorItem
    // stretch the window over the whole screen so outside clicks land on it
    anchor.rect.x: anchorItem ? -anchorItem.mapToGlobal(0, 0).x : 0
    anchor.rect.y: anchorItem ? -anchorItem.mapToGlobal(0, 0).y : 0
    implicitWidth: Quickshell.screens.length ? Quickshell.screens[0].width : 1920
    implicitHeight: Quickshell.screens.length ? Quickshell.screens[0].height : 1080

    // anchor's global position, captured at open time — mapToGlobal in a
    // static binding evaluates before the item is mapped and returns 0
    property real ax: 0
    property real ay: 0

    onVisibleChanged: {
        if (visible) {
            if (anchorItem && anchorItem.visible) {
                const p = anchorItem.mapToGlobal(0, 0)
                ax = p.x
                ay = p.y
            } else {
                ax = (root.width / 2) - (cardWidth / 2)
                ay = Sys.barHeight || 36
            }
            inner.forceActiveFocus()
            enterAnim.restart()
        } else {
            card.opacity = 0
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.dismissOnClickOutside) {
                root.visible = false
            }
        }
    }

    // Shadow proxy item: simple black shape so MultiEffect never rasterizes/blurs the card's crisp text
    Rectangle {
        id: shadowSource
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius
        color: "#000000"
        visible: false
    }

    // Soft Gaussian Drop Shadow rendered behind the main card
    MultiEffect {
        source: shadowSource
        anchors.fill: shadowSource
        shadowEnabled: true
        shadowColor: "#60000000"
        shadowBlur: 0.6
        shadowVerticalOffset: 4
        shadowHorizontalOffset: 0
        opacity: card.opacity
        visible: card.visible && card.opacity > 0
    }

    Rectangle {
        id: card
        opacity: 0

        x: Math.round(root.alignRight ? root.width - width - 8
         : Math.min(Math.max(root.ax + (root.anchorItem?.width ?? 0) / 2 - width / 2, 8),
                    root.width - width - 8))
        y: Math.round(root.ay + (root.anchorItem?.height ?? 0) + 12)

        transform: Translate { id: slide; y: 0 }

        ParallelAnimation {
            id: enterAnim
            NumberAnimation { target: slide; property: "y"; from: -10; to: 0
                              duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1
                              duration: 160 }
        }
        width: root.cardWidth
        height: root.cardHeight
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        radius: 12
        color: Sys.customBarBg
        border.width: 0.5
        border.color: Theme.altbg

        Behavior on color { ColorAnimation { duration: 250 } }

        // swallow card clicks so they don't fall through to the catcher
        MouseArea { anchors.fill: parent }

        Item {
            id: inner
            anchors.fill: parent
            anchors.margins: root.cardPadding
            focus: true
            Keys.onEscapePressed: root.visible = false
        }
    }
}
