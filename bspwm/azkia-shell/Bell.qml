import QtQuick

// Notifications: bell icon on top bar, DND indicator, notification history
BarModule {
    id: root
    active: history.visible

    icon: Sys.dndOn ? "󰪑" : (Sys.notifCount > 0 ? "󰂚" : "󰂜")
    iconColor: Sys.dndOn ? Qt.alpha(Theme.yellow, 0.70) : (Sys.notifCount > 0 ? Theme.cyan : Theme.cyan)

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            Sys.toggleDnd()
        else
            history.visible = !history.visible
    }

    NotifyPopup {
        id: history
        anchorItem: root
    }
}
