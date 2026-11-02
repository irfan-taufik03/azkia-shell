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
    property bool isClosing: false

    function open() {
        if (isClosing) {
            exitAnim.stop()
            innerExitAnim.stop()
            isClosing = false
        }
        visible = true
    }

    function close() {
        if (!visible || isClosing) return
        isClosing = true
        exitAnim.restart()
        innerExitAnim.restart()
    }

    function toggle() {
        if (visible && !isClosing) {
            close()
        } else {
            open()
        }
    }

    default property alias content: inner.data

    visible: false
    color: "transparent"

    Shortcut {
        sequences: ["Escape"]
        enabled: root.visible && !root.isClosing
        onActivated: root.close()
    }

    mask: root.dismissOnClickOutside ? null : cardRegion

    Region {
        id: cardRegion
        item: card
    }

    anchor.item: anchorItem

    property var activeScreen: Quickshell.screens.length ? Quickshell.screens[0] : null

    function updateScreenAndCoords() {
        let s = null
        if (anchorItem && anchorItem.Window && anchorItem.Window.window && anchorItem.Window.window.screen) {
            s = anchorItem.Window.window.screen
        }
        if (!s && anchorItem) {
            const p = anchorItem.mapToGlobal(0, 0)
            for (let i = 0; i < Quickshell.screens.length; i++) {
                const sc = Quickshell.screens[i]
                if (p.x >= sc.x && p.x < sc.x + sc.width && p.y >= sc.y && p.y < sc.y + sc.height) {
                    s = sc
                    break
                }
            }
        }
        if (!s && Quickshell.screens.length) s = Quickshell.screens[0]
        activeScreen = s

        if (anchorItem && anchorItem.visible) {
            const p = anchorItem.mapToGlobal(0, 0)
            const sx = s ? s.x : 0
            const sy = s ? s.y : 0
            ax = p.x - sx
            ay = p.y - sy
        } else {
            ax = ((s ? s.width : root.width) / 2) - (cardWidth / 2)
            ay = Sys.barHeight || 36
        }
    }

    screen: activeScreen
    implicitWidth: activeScreen ? activeScreen.width : 1920
    implicitHeight: activeScreen ? activeScreen.height : 1080

    // Position popup catcher window to stretch over the active screen
    anchor.rect.x: -ax
    anchor.rect.y: -ay

    // anchor's screen-local position, captured at open time
    property real ax: 0
    property real ay: 0

    onVisibleChanged: {
        if (visible) {
            isClosing = false
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py")])
            updateScreenAndCoords()
            inner.forceActiveFocus()
            exitAnim.stop()
            innerExitAnim.stop()
            enterAnim.restart()
        } else {
            card.opacity = 0
            isClosing = false
            Quickshell.execDetached(["python3", Sys.scriptPath("x11_unfocus.py"), "--restore"])
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.dismissOnClickOutside) {
                root.close()
            }
        }
    }

    readonly property real shadowPadding: 32

    // Shadow proxy item: padded black shape so MultiEffect can render an expanded soft gaussian blur
    Item {
        id: shadowSource
        x: card.x - root.shadowPadding
        y: card.y - root.shadowPadding
        width: card.width + (root.shadowPadding * 2)
        height: card.height + (root.shadowPadding * 2)
        opacity: card.opacity
        scale: card.scale
        transformOrigin: card.transformOrigin
        transform: Translate { y: slide.y }
        visible: false
        layer.enabled: true

        readonly property real earRadius: Sys.barRadius || 12
        readonly property bool hasLeftEar: card.x >= (earRadius + (Sys.barMarginLeft || 4))
        readonly property bool hasRightEar: (card.x + card.width + earRadius) <= (root.width - (Sys.barMarginRight || 4))

        Item {
            x: root.shadowPadding
            y: root.shadowPadding
            width: card.width
            height: card.height

            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: "#000000"

                // Flat top so shadow doesn't bleed above the bar
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: shadowSource.earRadius
                    color: "#000000"
                }
            }

            // Left shadow concave ear
            Canvas {
                width: shadowSource.earRadius
                height: shadowSource.earRadius
                anchors.top: parent.top
                anchors.right: parent.left
                visible: shadowSource.hasLeftEar
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = "#000000";
                    ctx.beginPath();
                    ctx.moveTo(0, 0);
                    ctx.lineTo(width, 0);
                    ctx.lineTo(width, height);
                    ctx.arc(0, height, width, 0, -Math.PI / 2, true);
                    ctx.closePath();
                    ctx.fill();
                }
                Component.onCompleted: requestPaint()
            }

            // Right shadow concave ear
            Canvas {
                width: shadowSource.earRadius
                height: shadowSource.earRadius
                anchors.top: parent.top
                anchors.left: parent.right
                visible: shadowSource.hasRightEar
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = "#000000";
                    ctx.beginPath();
                    ctx.moveTo(0, 0);
                    ctx.lineTo(width, 0);
                    ctx.arc(width, height, width, -Math.PI / 2, Math.PI, true);
                    ctx.lineTo(0, 0);
                    ctx.closePath();
                    ctx.fill();
                }
                Component.onCompleted: requestPaint()
            }
        }
    }

    // Soft Caelestia-style QML drop shadow (clipped at card.y so top bar never gets darkened by shadow bleed)
    Item {
        x: 0
        y: card.y
        width: root.width
        height: root.height - card.y
        clip: true
        z: -1

        MultiEffect {
            source: shadowSource
            x: shadowSource.x
            y: shadowSource.y - card.y
            width: shadowSource.width
            height: shadowSource.height
            shadowEnabled: true
            shadowColor: "#50000000"
            shadowBlur: 1.0
            shadowVerticalOffset: 6
            shadowHorizontalOffset: 0
            shadowOpacity: card.opacity
            opacity: card.opacity
            scale: card.scale
            transformOrigin: card.transformOrigin
            transform: Translate { y: slide.y }
            visible: card.opacity > 0
        }
    }

    Rectangle {
        id: card
        opacity: 0
        scale: 1.0
        transformOrigin: root.alignRight ? Item.TopRight : Item.Top

        readonly property real edgeMargin: (Sys.barMarginRight || 8) + 2 * (Sys.barRadius || 12) + 4
        readonly property real leftEdgeMargin: (Sys.barMarginLeft || 8) + 2 * (Sys.barRadius || 12) + 4

        x: Math.round(root.alignRight
            ? root.width - width - card.edgeMargin
            : Math.min(Math.max(root.ax + (root.anchorItem?.width ?? 0) / 2 - width / 2, card.leftEdgeMargin),
                       root.width - width - card.edgeMargin))
        y: Math.round((Sys.barMarginTop || 0) + (Sys.barHeight || 36)) - 1

        transform: Translate { id: slide; y: 0 }

        ParallelAnimation {
            id: enterAnim
            NumberAnimation { target: slide; property: "y"; from: -20; to: 0
                              duration: 360; easing.type: Easing.OutExpo }
            NumberAnimation { target: card; property: "scale"; from: 0.90; to: 1.0
                              duration: 360; easing.type: Easing.OutExpo }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1
                              duration: 260; easing.type: Easing.OutCubic }
        }

        ParallelAnimation {
            id: exitAnim
            NumberAnimation { target: slide; property: "y"; from: slide.y; to: -20
                              duration: 240; easing.type: Easing.InCubic }
            NumberAnimation { target: card; property: "scale"; from: card.scale; to: 0.90
                              duration: 240; easing.type: Easing.InCubic }
            NumberAnimation { target: card; property: "opacity"; from: card.opacity; to: 0
                              duration: 200; easing.type: Easing.InCubic }
            onFinished: {
                if (root.isClosing) {
                    root.visible = false
                    root.isClosing = false
                }
            }
        }

        width: root.cardWidth
        height: root.cardHeight
        radius: 18
        color: "transparent"
        border.width: 0

        property color cardColor: Sys.customBarBg
        property color borderColor: Sys.customModuleBorder
        property real borderWidth: 1

        Behavior on cardColor { ColorAnimation { duration: 400 } }
        Behavior on borderColor { ColorAnimation { duration: 400 } }

        // Single unified canvas for the entire popout body AND concave ears:
        // Ensures 100% seamless vector stroke & fill with ZERO anti-aliasing seam artifacts
        Canvas {
            id: unifiedCanvas

            readonly property real earRadius: Sys.barRadius || 12
            readonly property bool hasLeftEar: card.x >= (earRadius + (Sys.barMarginLeft || 4))
            readonly property bool hasRightEar: (card.x + card.width + earRadius) <= (root.width - (Sys.barMarginRight || 4))
            readonly property real topOverlap: 2.0

            anchors.top: card.top
            anchors.topMargin: -topOverlap - 1
            anchors.left: card.left
            anchors.leftMargin: (hasLeftEar ? -earRadius : 0) - 1
            anchors.right: card.right
            anchors.rightMargin: (hasRightEar ? -earRadius : 0) - 1
            anchors.bottom: card.bottom
            anchors.bottomMargin: -3
            z: -1

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();

                var W = card.width;
                var H = card.height;
                var r = card.radius;
                var rad = earRadius;
                var overlap = topOverlap;

                var hasL = hasLeftEar;
                var hasR = hasRightEar;

                var p = 0.5;
                var off = 1.0;
                var xEarL = off + p;
                var xCardL = hasL ? off + rad + p : off + p;
                var xCardR = xCardL + W;
                var xEarR = xCardR + (hasR ? rad : 0);

                var yTop = off + p;
                var yBarBtm = off + overlap + p;
                var yArcBtm = off + overlap + rad + p;
                var yCardBtm = off + overlap + H + p;

                // 1. Solid background fill covering ears, top overlap, and card
                ctx.fillStyle = card.cardColor;
                ctx.beginPath();
                ctx.moveTo(xEarL - p, yTop - p);
                ctx.lineTo(xEarR + p, yTop - p);

                if (hasR) {
                    ctx.lineTo(xEarR + p, yBarBtm);
                    ctx.arc(xEarR, yArcBtm, rad, -Math.PI / 2, Math.PI, true);
                } else {
                    ctx.lineTo(xCardR, yBarBtm);
                }

                ctx.lineTo(xCardR, yCardBtm - r);
                ctx.arc(xCardR - r, yCardBtm - r, r, 0, Math.PI / 2, false);

                ctx.lineTo(xCardL + r, yCardBtm);
                ctx.arc(xCardL + r, yCardBtm - r, r, Math.PI / 2, Math.PI, false);

                if (hasL) {
                    ctx.lineTo(xCardL, yArcBtm);
                    ctx.arc(xEarL, yArcBtm, rad, 0, -Math.PI / 2, true);
                } else {
                    ctx.lineTo(xCardL, yBarBtm);
                }

                ctx.closePath();
                ctx.fill();

                // 2. Single continuous stroke around outer border (excluding top overlap)
                if (card.borderWidth > 0 && card.borderColor !== "transparent") {
                    ctx.strokeStyle = card.borderColor;
                    ctx.lineWidth = card.borderWidth;
                    ctx.beginPath();

                    if (hasL) {
                        ctx.moveTo(xEarL, yBarBtm);
                        ctx.arc(xEarL, yArcBtm, rad, -Math.PI / 2, 0, false);
                    } else {
                        ctx.moveTo(xCardL, yBarBtm);
                    }

                    ctx.lineTo(xCardL, yCardBtm - r);
                    ctx.arc(xCardL + r, yCardBtm - r, r, Math.PI, Math.PI / 2, true);

                    ctx.lineTo(xCardR - r, yCardBtm);
                    ctx.arc(xCardR - r, yCardBtm - r, r, Math.PI / 2, 0, true);

                    ctx.lineTo(xCardR, yArcBtm);

                    if (hasR) {
                        ctx.arc(xEarR, yArcBtm, rad, Math.PI, -Math.PI / 2, false);
                    }

                    ctx.stroke();
                }
            }

            Connections {
                target: card
                function onCardColorChanged() { unifiedCanvas.requestPaint(); }
                function onBorderColorChanged() { unifiedCanvas.requestPaint(); }
                function onWidthChanged() { unifiedCanvas.requestPaint(); }
                function onHeightChanged() { unifiedCanvas.requestPaint(); }
                function onXChanged() { unifiedCanvas.requestPaint(); }
            }
            Component.onCompleted: requestPaint()
        }

        // swallow card clicks so they don't fall through to the catcher
        MouseArea { anchors.fill: parent }

        Item {
            id: inner
            anchors.fill: parent
            anchors.margins: root.cardPadding
            focus: true
            Keys.onEscapePressed: root.close()

            scale: 1.0
            opacity: 1.0
            transformOrigin: root.alignRight ? Item.TopRight : Item.Top
            transform: Translate { id: innerSlide; y: 0 }

            Connections {
                target: root
                function onVisibleChanged() {
                    if (root.visible) {
                        inner.opacity = 0
                        inner.scale = 0.95
                        innerSlide.y = -10
                        innerEnterAnim.restart()
                    }
                }
            }

            SequentialAnimation {
                id: innerEnterAnim
                PauseAnimation { duration: 30 }
                ParallelAnimation {
                    NumberAnimation { target: innerSlide; property: "y"; from: -10; to: 0
                                      duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { target: inner; property: "scale"; from: 0.95; to: 1.0
                                      duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { target: inner; property: "opacity"; from: 0; to: 1
                                      duration: 250; easing.type: Easing.OutCubic }
                }
            }

            ParallelAnimation {
                id: innerExitAnim
                NumberAnimation { target: innerSlide; property: "y"; from: innerSlide.y; to: -10
                                  duration: 180; easing.type: Easing.InCubic }
                NumberAnimation { target: inner; property: "scale"; from: inner.scale; to: 0.95
                                  duration: 180; easing.type: Easing.InCubic }
                NumberAnimation { target: inner; property: "opacity"; from: inner.opacity; to: 0
                                  duration: 150; easing.type: Easing.InCubic }
            }
        }
    }
}
