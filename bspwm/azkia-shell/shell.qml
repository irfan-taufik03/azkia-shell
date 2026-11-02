//@ pragma UseQApplication
import Quickshell
import Quickshell.Services.Notifications

ShellRoot {
    NotificationServer {
        id: notifServer
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        actionIconsSupported: true
        persistenceSupported: true
        extraHints: [
            "sender-pid",
            "window-id",
            "x-kde-originating-window-id",
            "x-canonical-private-window-id",
            "desktop-entry"
        ]
        onNotification: notif => {
            notif.tracked = true
            Sys.addNotification(notif)
        }
    }

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    Variants {
        model: Quickshell.screens
        Lockscreen {
            modelData: modelData
        }
    }

    Variants {
        model: Quickshell.screens
        SettingsWindow {
            modelData: modelData
        }
    }

    Variants {
        model: Quickshell.screens
        AudioPlayerWindow {
            modelData: modelData
        }
    }

    Variants {
        model: Quickshell.screens
        PdfWindow {
            modelData: modelData
        }
    }

    Variants {
        model: Quickshell.screens
        WindowSwitcher {
            modelData: modelData
        }
    }

    Variants {
        model: Quickshell.screens
        PolkitDialog {
            modelData: modelData
        }
    }
}

