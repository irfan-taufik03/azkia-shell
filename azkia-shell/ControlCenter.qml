import QtQuick

BarModule {
    id: root
    active: popup.visible

    icon: ""
    iconColor: Theme.blue
    label: ""

    onClicked: popup.visible = !popup.visible

    ControlCenterPopup {
        id: popup
        anchorItem: root
    }
}
