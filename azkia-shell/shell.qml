//@ pragma UseQApplication
import Quickshell
import Quickshell.Services.Notifications

ShellRoot {
    NotificationServer {
        id: notifServer
        onNotification: notif => {
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
}
