<p align="center">
  <img src="bspwm/azkia-shell/assets/azkia-shell-logo.svg" alt="Azkia Shell Logo" width="180">
</p>

<h1 align="center">Azkia Shell & BSPWM Installer</h1>

<p align="center">
  A complete, modern, multi-distro desktop setup featuring <b>BSPWM</b> and <b>Azkia Shell</b> (built with Quickshell & Qt6/QML).
</p>

<p align="center">
  <a href="https://buymeacoffee.com/irfan.taufik03" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="License: MIT"></a>
</p>

https://github.com/user-attachments/assets/9999e326-6924-4018-a8cf-8e15c73fdf69

---

## 🚀 Features

- **Multi-Distro Support**: Works natively on **Debian / Ubuntu / Linux Mint / Butterbian**, **Arch Linux / Manjaro / EndeavourOS**, and **Fedora / Nobara**.
- **Azkia Shell**: Modern bar, control center, unified launcher/dash, audio player, PDF viewer, window switcher, system monitor, and popups built with Quickshell & Qt6.
- **Native Polkit Integration**: Built-in PolicyKit Authentication Agent (`polkit_agent.py` & `PolkitDialog.qml`) replacing legacy external polkit agents with a sleek, themed graphical dialog.
- **Azkia Greeter**: Modern display manager frontend powered by `greetd` and Quickshell for an integrated login experience (`setup_greetd.sh`).
- **Pre-configured Nora & Casauna Themes**: Automatically deploys and applies **Nora-gtk-mauve** GTK theme, **casauna** icon theme, and **Sweet-cursors** cursor theme.
- **Window Management & Switcher**: BSPWM tiling/floating rules, display management (`display_setup.sh`), tag switcher, and responsive Alt+Tab task switcher.
- **Integrated Applications**: Built-in **Azkia Audio Player**, **Azkia PDF Viewer**, and **Azkia Settings** with dedicated desktop entries.
- **Terminal Emulator**: Pre-configured with **Kitty** (`Super + Return`).
- **Power & System Control**: Lockscreen (`idle_daemon.py`), power profiles (`power-profiles-daemon`), hourly health movement reminder, and wallpaper manager.

---

## 🛠️ Quick Installation

### Option 1: Git Clone (Recommended)

```bash
git clone https://github.com/irfan-taufik03/azkia-shell.git
cd azkia-shell
chmod +x install.sh
./install.sh
```

### Option 2: One-Line Installer

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/irfan-taufik03/azkia-shell/main/install.sh)"
```

### What the Installer Does:
1. **Auto-Detects Linux Distro**: Supports APT (Debian/Ubuntu/Mint), Pacman/AUR (Arch), and DNF (Fedora).
2. **Installs System Packages**: Automatically installs `bspwm`, `sxhkd`, `picom`, `feh`, `cava`, `kitty`, `python3-gi`, `python3-dbus`, `polkitd`, Qt6 libraries, etc.
3. **Installs Quickshell Engine**: Configures APT repositories (Debian/Ubuntu) or builds `quickshell-git` from AUR (Arch Linux).
4. **Deploys Dotfiles & Themes**: Copies configuration to `~/.config/bspwm/`, `~/.themes/Nora-gtk-mauve`, `~/.icons/casauna`, and `~/.icons/Sweet-cursors`.
5. **Applies Themes Automatically**: Configures GTK3/GTK4 settings and `index.theme` for instant visual application.
6. **Configures Environment**: Updates `$HOME` paths in `appearance.json` automatically.
7. **Enables System Services**: Enables `bluetooth.service`, `NetworkManager.service`, `power-profiles-daemon`, and hourly movement timer.
8. **Creates XSession Desktop Entry**: Adds `/usr/share/xsessions/bspwm.desktop` for your display manager.

---

## 📦 Distribution Package Mapping

| Component | Debian / Ubuntu (`apt`) | Arch Linux (`pacman` / `aur`) | Fedora (`dnf`) |
| :--- | :--- | :--- | :--- |
| **Window Manager** | `bspwm`, `sxhkd` | `bspwm`, `sxhkd` | `bspwm`, `sxhkd` |
| **Terminal Emulator** | `kitty` | `kitty` | `kitty` |
| **Compositor & Wallpaper**| `picom`, `feh` | `picom`, `feh` | `picom`, `feh` |
| **Shell Toolkit** | `quickshell` | `quickshell-git` (AUR) | `quickshell` |
| **File Manager** | `thunar`, `thunar-archive-plugin` | `thunar`, `thunar-archive-plugin` | `thunar`, `thunar-archive-plugin` |
| **Audio & Media** | `pamixer`, `playerctl`, `cava` | `pamixer`, `playerctl`, `cava` | `pamixer`, `playerctl`, `cava` |
| **Brightness & Power** | `brightnessctl`, `upower`, `power-profiles-daemon` | `brightnessctl`, `upower`, `power-profiles-daemon` | `brightnessctl`, `upower`, `power-profiles-daemon` |
| **Bluetooth & Network** | `bluez`, `bluez-tools`, `network-manager` | `bluez`, `bluez-utils`, `networkmanager` | `bluez`, `bluez-tools`, `NetworkManager` |
| **PolicyKit & D-Bus** | `python3-dbus`, `polkitd` | `python-dbus`, `polkit` | `python3-dbus`, `polkit` |
| **GTK & Icon Theme** | `Nora-gtk-mauve`, `casauna`, `Sweet-cursors` | `Nora-gtk-mauve`, `casauna`, `Sweet-cursors` | `Nora-gtk-mauve`, `casauna`, `Sweet-cursors` |

---

## ⌨️ Default Keybindings

- `Super + Return` : Open Terminal (`kitty`)
- `Super + Space` : Open Launcher
- `Super + X` : Open Power Menu
- `Super + M` : Open Media Player Popup
- `Super + L` : Lock Screen
- `Super + Shift + Return` : File Manager (`thunar`)
- `Super + C` : Close Focused Window
- `Super + Alt + R` : Reload BSPWM Config
- `Super + Escape` : Reload SXHKD Hotkeys

---

## 🏁 Starting the Session

1. Log out of your current session.
2. Select **BSPWM** from your Display Manager (LightDM, GDM, SDDM).
3. Or launch via console with `startx`.

---

## 🙏 Credits & Acknowledgements

- <b><a href="https://justaguy.dev/drew/bspwm-setup" target="_blank" rel="noopener noreferrer">Drew (Just A Guy Linux)</a></b> - Base BSPWM environment structure and initial setup code.
- <b><a href="https://github.com/AvengeMedia/danklinux" target="_blank" rel="noopener noreferrer">DMS (DankMaterialShell)</a></b> - UI/UX inspiration and Quickshell desktop environment concept.

---

## ☕ Support

If you enjoy using **Azkia Shell** and would like to support the development, feel free to buy me a coffee!

<a href="https://buymeacoffee.com/irfan.taufik03" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee"></a>

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.

