import QtQuick
import Quickshell

// Flameshot launcher, same as the polybar setup.
BarModule {
    icon: "󰵝"
    iconColor: Theme.magenta
    onClicked: Quickshell.execDetached(["flameshot", "gui"])
}
