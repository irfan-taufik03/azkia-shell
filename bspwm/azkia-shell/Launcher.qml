import QtQuick
import Quickshell

BarModule {
    id: root
    active: popup ? popup.visible : false

    iconImage: Sys.launcherLogo
    iconImageSize: Sys.launcherIconSize

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Wm.openLauncher()
        } else {
            popup.visible = !popup.visible
        }
    }

    LauncherPopup {
        id: popup
        anchorItem: root
    }
}
