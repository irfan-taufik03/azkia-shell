import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

PopupWindow {
    id: root

    property PanelWindow anchorWindow: null

    anchor.window: anchorWindow
    anchor.rect.x: (anchorWindow && typeof anchorWindow.mapToGlobal === "function") ? -anchorWindow.mapToGlobal(0, 0).x : 0
    anchor.rect.y: (anchorWindow && typeof anchorWindow.mapToGlobal === "function") ? -anchorWindow.mapToGlobal(0, 0).y : 0

    implicitWidth: Quickshell.screens.length ? Quickshell.screens[0].width : 1920
    implicitHeight: Quickshell.screens.length ? Quickshell.screens[0].height : 1080
    visible: activeToasts.length > 0
    color: "transparent"

    mask: Region { item: cardArea }

    property var activeToasts: []

    Connections {
        target: Sys
        function onNotificationReceived(notif) {
            if (Sys.dndOn) return

            const toastList = root.activeToasts.slice()
            toastList.unshift(notif)
            if (toastList.length > 4) toastList.pop()
            root.activeToasts = toastList
        }
    }

    function removeToast(id) {
        root.activeToasts = root.activeToasts.filter(t => t.id !== id)
    }

    Item {
        id: cardArea
        x: card.x - root.shadowPadding
        y: card.y
        width: card.width + (root.shadowPadding * 2)
        height: card.height + root.shadowPadding + 16
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
        transform: Translate { y: toastSlide.y }
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
            transform: Translate { y: toastSlide.y }
            visible: card.opacity > 0
        }
    }

    Rectangle {
        id: card
        width: 360
        height: toastCol.implicitHeight + 24
        radius: 18
        color: "transparent"
        border.width: 0
        opacity: root.activeToasts.length > 0 ? 1 : 0

        property color cardColor: Sys.customBarBg
        property color borderColor: Sys.customModuleBorder
        property real borderWidth: 1

        readonly property real edgeMargin: (Sys.barMarginRight || 8) + 2 * (Sys.barRadius || 12) + 4

        x: Math.round(root.width - width - card.edgeMargin)
        y: Math.round((Sys.barMarginTop || 0) + (Sys.barHeight || 36)) - 1

        scale: 1.0
        transformOrigin: Item.TopRight
        transform: Translate { id: toastSlide; y: 0 }

        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        onVisibleChanged: {
            if (visible) {
                enterToastAnim.restart()
            }
        }

        ParallelAnimation {
            id: enterToastAnim
            NumberAnimation { target: toastSlide; property: "y"; from: -20; to: 0
                              duration: 360; easing.type: Easing.OutExpo }
            NumberAnimation { target: card; property: "scale"; from: 0.90; to: 1.0
                              duration: 360; easing.type: Easing.OutExpo }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1
                              duration: 260; easing.type: Easing.OutCubic }
        }

        Behavior on cardColor { ColorAnimation { duration: 400 } }
        Behavior on borderColor { ColorAnimation { duration: 400 } }

        // Single unified canvas for the entire toast body AND concave ears:
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

        // Content Column containing Toast Items
        Column {
            id: toastCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Repeater {
                model: root.activeToasts

                delegate: Rectangle {
                    id: itemCard
                    width: toastCol.width
                    height: Math.max(70, cardRow.implicitHeight + 20)
                    radius: 14
                    color: Qt.alpha(Theme.fg, 0.05)
                    border.width: 1
                    border.color: toastMa.containsMouse ? Theme.accent : Sys.customModuleBorder

                    scale: 1.0
                    transform: Translate { id: itemSlide; y: 0 }
                    Component.onCompleted: itemEnterAnim.restart()

                    ParallelAnimation {
                        id: itemEnterAnim
                        NumberAnimation { target: itemSlide; property: "y"; from: -14; to: 0
                                          duration: 240; easing.type: Easing.OutExpo }
                        NumberAnimation { target: itemCard; property: "scale"; from: 0.85; to: 1.0
                                          duration: 240; easing.type: Easing.OutExpo }
                        NumberAnimation { target: itemCard; property: "opacity"; from: 0; to: 1
                                          duration: 180 }
                    }

                    readonly property var toastData: modelData

                    readonly property bool isNetNotif: {
                        if (!toastData) return false
                        const app = String(toastData.appName || "").toLowerCase()
                        const sum = String(toastData.summary || "").toLowerCase()
                        return app === "wi-fi" || app === "wifi" || app === "network" || sum.includes("wi-fi") || sum.includes("wifi") || sum.includes("network")
                    }

                    readonly property bool isBtNotif: {
                        if (!toastData) return false
                        const app = String(toastData.appName || "").toLowerCase()
                        const sum = String(toastData.summary || "").toLowerCase()
                        return app === "bluetooth" || sum.includes("bluetooth")
                    }

                    readonly property bool isCaffeineNotif: {
                        if (!toastData) return false
                        const app = String(toastData.appName || "").toLowerCase()
                        const sum = String(toastData.summary || "").toLowerCase()
                        return app.includes("keep awake") || app.includes("caffeine") || sum.includes("keep awake") || sum.includes("caffeine")
                    }

                    readonly property bool isPrayerNotif: {
                        if (!toastData) return false
                        const app = String(toastData.appName || "").toLowerCase()
                        const sum = String(toastData.summary || "").toLowerCase()
                        return app.includes("shalat") || app.includes("prayer") || sum.includes("shalat") || sum.includes("prayer")
                    }

                    readonly property bool isEyeNotif: {
                        if (!toastData) return false
                        const app = String(toastData.appName || "").toLowerCase()
                        const sum = String(toastData.summary || "").toLowerCase()
                        return app.includes("eye protection") || app.includes("night light") || sum.includes("eye protection") || sum.includes("night light")
                    }

                    readonly property bool isSystemNotif: {
                        if (!toastData || isCaffeineNotif || isEyeNotif || isPrayerNotif) return false
                        const app = String(toastData.appName || "").toLowerCase()
                        return app === "system" || app === "azkia shell" || app === "display" || app === "bspwm" || app === "sxhkd" || app === "notification"
                    }

                    readonly property bool isNetConnected: {
                        if (!toastData) return false
                        const sum = String(toastData.summary || "").toLowerCase()
                        return sum.includes("connected") && !sum.includes("disconnected") && !sum.includes("failed") && !sum.includes("timeout")
                    }

                    readonly property bool isBtConnected: {
                        if (!toastData) return false
                        const sum = String(toastData.summary || "").toLowerCase()
                        return sum.includes("connected") && !sum.includes("disconnected") && !sum.includes("failed")
                    }

                    readonly property bool isCaffeineDisabled: isCaffeineNotif && (String(toastData.summary || "").toLowerCase().includes("disabled") || String(toastData.body || "").toLowerCase().includes("disabled"))

                    readonly property bool isEyeDisabled: isEyeNotif && (String(toastData.summary || "").toLowerCase().includes("disabled") || String(toastData.body || "").toLowerCase().includes("disabled"))

                    readonly property string netIconChar: {
                        if (isNetConnected) {
                            return (Sys.netIcon && Sys.netIcon !== "󰤮" && Sys.netIcon !== "󰤭") ? Sys.netIcon : "󰤨"
                        }
                        return "󰤭"
                    }

                    readonly property string btIconChar: isBtConnected ? "󰂯" : "󰂲"

                    readonly property bool hasValidAppIcon: !isNetNotif && !isBtNotif && !isCaffeineNotif && !isEyeNotif && !isPrayerNotif && !isSystemNotif && (iconImg.status === Image.Ready)

                    readonly property bool useAccentBadge: isNetNotif || isBtNotif || isCaffeineNotif || isEyeNotif || isPrayerNotif || isSystemNotif || !hasValidAppIcon

                    Timer {
                        id: dismissTimer
                        interval: {
                            if (!itemCard.toastData) return 4500
                            if (itemCard.toastData.appName === "Movement Reminder" || itemCard.isPrayerNotif || (itemCard.toastData.summary && (itemCard.toastData.summary.includes("Time to Move") || itemCard.toastData.summary.toLowerCase().includes("shalat")))) {
                                return 10000
                            }
                            if (itemCard.toastData.expireTimeout && itemCard.toastData.expireTimeout > 0) {
                                return itemCard.toastData.expireTimeout
                            }
                            return 4500
                        }
                        running: !toastMa.containsMouse
                        onTriggered: root.removeToast(itemCard.toastData.id)
                    }

                    MouseArea {
                        id: toastMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Sys.activateNotification(itemCard.toastData)
                            root.removeToast(itemCard.toastData.id)
                        }
                    }

                    Row {
                        id: cardRow
                        width: parent.width - 20
                        anchors.centerIn: parent
                        spacing: 10

                        // Icon Box (Accent badge style for Network, Bluetooth, Keep Awake, Eye Protection, Prayer, and System/Bell notifications)
                        Rectangle {
                            width: itemCard.useAccentBadge ? 42 : 44
                            height: itemCard.useAccentBadge ? 42 : 44
                            radius: itemCard.useAccentBadge ? 14 : 10
                            color: itemCard.useAccentBadge
                                ? (((itemCard.isNetNotif && !itemCard.isNetConnected) || 
                                    (itemCard.isBtNotif && !itemCard.isBtConnected) ||
                                    itemCard.isCaffeineDisabled ||
                                    itemCard.isEyeDisabled) ? Qt.alpha(Theme.accent, 0.45) : Theme.accent)
                                : Qt.alpha(Theme.accent, 0.15)
                            border.width: itemCard.useAccentBadge ? 0 : 1
                            border.color: Qt.alpha(Theme.accent, 0.25)
                            anchors.verticalCenter: parent.verticalCenter

                            // Accent Style Font Icon (Network, Bluetooth, Keep Awake, Eye Protection, Prayer, or System Bell)
                            Text {
                                anchors.centerIn: parent
                                visible: itemCard.useAccentBadge
                                text: {
                                    if (itemCard.isPrayerNotif) return "󱠧" 
                                    if (itemCard.isNetNotif) return itemCard.netIconChar
                                    if (itemCard.isBtNotif) return itemCard.btIconChar
                                    if (itemCard.isCaffeineNotif) return "󰅶"
                                    if (itemCard.isEyeNotif) return "󰃠"
                                    return "󰂚"
                                }
                                color: Sys.customBarBg
                                font.family: Theme.fontFamily
                                font.pixelSize: 20
                                font.bold: true
                            }

                            // Standard Application Icon
                            Image {
                                id: iconImg
                                anchors.centerIn: parent
                                width: 30
                                height: 30
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                source: {
                                    if (itemCard.isNetNotif || itemCard.isBtNotif || itemCard.isCaffeineNotif || itemCard.isEyeNotif || itemCard.isPrayerNotif || itemCard.isSystemNotif) return ""
                                    const icon = String(itemCard.toastData.appIcon || "")
                                    if (!icon) return ""
                                    if (icon.startsWith("file://")) return icon
                                    if (icon.startsWith("/")) return "file://" + icon
                                    if (icon.startsWith("image://")) return icon
                                    return "image://icon/" + icon
                                }
                                visible: itemCard.hasValidAppIcon
                            }
                        }

                        // Info Column
                        Column {
                            width: parent.width - 54
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            Item {
                                width: parent.width
                                height: 16

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: itemCard.toastData.appName
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: true
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, parent.width - 70)
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Text {
                                        text: itemCard.toastData.time
                                        color: Qt.alpha(Theme.fg, 0.45)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 3
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 8
                                        color: closeMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : "transparent"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            color: closeMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.6)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }

                                        MouseArea {
                                            id: closeMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.removeToast(itemCard.toastData.id)
                                        }
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: itemCard.toastData.summary
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: itemCard.toastData.body
                                color: Qt.alpha(Theme.fg, 0.8)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                visible: itemCard.toastData.body !== ""
                            }
                        }
                    }
                }
            }
        }
    }
}
