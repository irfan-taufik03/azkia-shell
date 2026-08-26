<p align="center">
  <img src="azkia-shell/assets/azkia-shell-logo.svg" alt="Azkia Shell Logo" width="180">
</p>

<h1 align="center">Azkia Shell & BSPWM Installer</h1>

<p align="center">
  A complete, modern, multi-distro desktop setup featuring <b>BSPWM</b> and <b>Azkia Shell</b> (built with Quickshell & Qt6/QML).
</p>

<p align="center">
  <a href="https://buymeacoffee.com/irfan.taufik03" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="License: MIT"></a>
</p>

<p align="center">
  <video src="assets/azkia-shell-demo.mp4" controls width="100%"></video>
</p>

---

## 🚀 Features

- **Multi-Distro Support**: Works natively on **Debian / Ubuntu / Butterbian**, **Arch Linux / Manjaro / EndeavourOS**, and **Fedora / Nobara**.
- **Azkia Shell**: Modern bar, control center, launchers, system monitor, note manager, lockscreen, and popups.
- **Instant UI Settings**: Built-in graphical settings panel for real-time, instant customization of shell appearance, wallpapers, picom effects, and autolock timeouts.
- **Terminal Emulator**: Pre-configured with **WezTerm** (`Super + Return`).
- **Pre-configured GTK & Cursor Theme**: Automatically deploys and applies **Nordic-darker** GTK theme and **Sweet-cursors** cursor theme.
- **Window Management**: Window tiled/floating rules, mouse focus, keybindings via `sxhkd`.
- **Media & Audio Integration**: System audio popups (`pamixer`), media playback controls (`playerctl`), and visualizer (`cava`).
- **Power & System Control**: Lockscreen (`idle_daemon.py`, `lockscreen_auth.py`), power profiles (`power-profiles-daemon`), and wallpaper manager (`feh` & `wallpaper.py`).

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
2. **Installs System Packages**: Automatically installs `bspwm`, `sxhkd`, `picom`, `feh`, `cava`, `wezterm`, `python3-gi`, Qt6 libraries, etc.
3. **Installs Quickshell Engine**: Configures APT repositories (Debian/Ubuntu) or builds `quickshell-git` from AUR (Arch Linux).
4. **Deploys Dotfiles & Themes**: Copies configuration to `~/.config/bspwm/`, `~/.themes/Nordic-darker`, and `~/.icons/Sweet-cursors`.
5. **Applies Themes Automatically**: Configures GTK3/GTK4 settings and `index.theme` for instant visual application.
6. **Configures Environment**: Updates `$HOME` paths in `appearance.json` automatically.
7. **Enables System Services**: Enables `bluetooth.service`, `NetworkManager.service`, and `power-profiles-daemon`.
8. **Creates XSession Desktop Entry**: Adds `/usr/share/xsessions/bspwm.desktop` for your display manager.

---

## 📦 Distribution Package Mapping

| Component | Debian / Ubuntu (`apt`) | Arch Linux (`pacman` / `aur`) | Fedora (`dnf`) |
| :--- | :--- | :--- | :--- |
| **Window Manager** | `bspwm`, `sxhkd` | `bspwm`, `sxhkd` | `bspwm`, `sxhkd` |
| **Terminal Emulator** | `wezterm` | `wezterm` | `wezterm` |
| **Compositor & Wallpaper**| `picom`, `feh` | `picom`, `feh` | `picom`, `feh` |
| **Shell Toolkit** | `quickshell` | `quickshell-git` (AUR) | `quickshell` |
| **File Manager** | `thunar`, `thunar-archive-plugin` | `thunar`, `thunar-archive-plugin` | `thunar`, `thunar-archive-plugin` |
| **Audio & Media** | `pamixer`, `playerctl`, `cava` | `pamixer`, `playerctl`, `cava` | `pamixer`, `playerctl`, `cava` |
| **Brightness & Power** | `brightnessctl`, `upower`, `power-profiles-daemon` | `brightnessctl`, `upower`, `power-profiles-daemon` | `brightnessctl`, `upower`, `power-profiles-daemon` |
| **Bluetooth & Network** | `bluez`, `bluez-tools`, `network-manager` | `bluez`, `bluez-utils`, `networkmanager` | `bluez`, `bluez-tools`, `NetworkManager` |
| **GTK & Cursor Theme** | `Nordic-darker`, `Sweet-cursors` | `Nordic-darker`, `Sweet-cursors` | `Nordic-darker`, `Sweet-cursors` |

---

## ⌨️ Default Keybindings

- `Super + Return` : Open Terminal (`wezterm`)
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

