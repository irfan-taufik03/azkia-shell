import QtQuick
import Quickshell

BarModule {
    id: root
    active: popup ? popup.visible : false

    icon: ""
    iconColor: Theme.red

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Wm.openPowerMenu()
        } else {
            popup.visible = !popup.visible
        }
    }

    PowerPopup {
        id: popup
        anchorItem: root
    }
}
