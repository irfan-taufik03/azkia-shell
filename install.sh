#!/usr/bin/env bash
# ==============================================================================
# Azkia Shell & BSPWM Installer
# Supported Distributions:
#   - Debian / Butterbian / Ubuntu / Linux Mint / Pop!_OS (APT)
#   - Arch Linux / Manjaro / EndeavourOS (Pacman + AUR)
#   - Fedora / Nobara / RHEL (DNF)
# ==============================================================================

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper logging functions
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_banner() {
    echo -e "${PURPLE}"
    echo "  █████╗ ███████╗██╗  ██╗██╗ █████╗ ███████╗██╗  ██╗███████╗██╗     ██╗     "
    echo " ██╔══██╗╚══███╔╝██║ ██╔╝██║██╔══██╗██╔════╝██║  ██║██╔════╝██║     ██║     "
    echo " ███████║  ███╔╝ █████╔╝ ██║███████║███████╗███████║█████╗  ██║     ██║     "
    echo " ██╔══██║ ███╔╝  ██╔═██╗ ██║██╔══██║╚════██║██╔══██║██╔══╝  ██║     ██║     "
    echo " ██║  ██║███████╗██║  ██╗██║██║  ██║███████║██║  ██║███████╗███████╗███████╗"
    echo " ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝"
    echo -e "                   BSPWM & Quickshell Environment Installer${NC}\n"
}

check_root_or_sudo() {
    if [ "$EUID" -eq 0 ]; then
        SUDO_CMD=""
    else
        if command -v sudo &>/dev/null; then
            SUDO_CMD="sudo"
        else
            log_error "Privilege escalation tool (sudo) is required but not installed."
            exit 1
        fi
    fi
}

detect_distro() {
    DISTRO_TYPE="unknown"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME=$PRETTY_NAME
        DISTRO_ID=$ID
    else
        DISTRO_NAME="Unknown Linux"
        DISTRO_ID="unknown"
    fi

    log_info "Detected OS: $DISTRO_NAME"

    if command -v apt-get &>/dev/null; then
        DISTRO_TYPE="debian"
    elif command -v pacman &>/dev/null; then
        DISTRO_TYPE="arch"
    elif command -v dnf &>/dev/null; then
        DISTRO_TYPE="fedora"
    else
        log_error "Unsupported package manager. Only APT (Debian/Ubuntu), Pacman (Arch), and DNF (Fedora) are supported."
        exit 1
    fi
}

build_quickshell_from_source() {
    log_info "Building Quickshell automatically from source..."

    log_info "Installing build dependencies for Quickshell..."
    $SUDO_CMD apt install -y cmake ninja-build build-essential \
        qt6-base-dev qt6-declarative-dev qt6-wayland libwayland-dev \
        wayland-protocols libpipewire-0.3-dev libdbus-1-dev \
        libxkbcommon-dev pkg-config libqt6svg6-dev 2>/dev/null || true

    REAL_USER="${SUDO_USER:-$USER}"
    BUILD_DIR=$(mktemp -d)
    chmod 777 "$BUILD_DIR"

    log_info "Cloning Quickshell repository..."
    if git clone https://github.com/quickshell-mirror/quickshell.git "$BUILD_DIR"; then
        chown -R "$REAL_USER" "$BUILD_DIR" 2>/dev/null || true
        log_info "Compiling Quickshell binary with CMake & Ninja..."
        if (cd "$BUILD_DIR" && cmake -B build -GNinja -DCMAKE_BUILD_TYPE=Release && cmake --build build); then
            $SUDO_CMD cmake --install "$BUILD_DIR/build"
            log_success "Quickshell built and installed successfully from source!"
        else
            log_error "Failed to compile Quickshell from source."
        fi
    else
        log_error "Failed to clone Quickshell repository."
    fi

    rm -rf "$BUILD_DIR" 2>/dev/null || true
}

install_debian() {
    log_info "Setting up repositories and installing packages for Debian/Ubuntu/Linux Mint..."

    # Detect distro specifics and Ubuntu base codename
    IS_UBUNTU_BASED=false
    UBUNTU_CODENAME=""
    if [ -f /etc/os-release ]; then
        if grep -qi -E 'ubuntu|mint|pop' /etc/os-release; then
            IS_UBUNTU_BASED=true
        fi
        UBUNTU_CODENAME=$(grep -E '^UBUNTU_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    fi
    [ -z "$UBUNTU_CODENAME" ] && UBUNTU_CODENAME="noble"

    # Clean up obsolete butterrepo repository if it exists
    if [ -f /etc/apt/sources.list.d/butterrepo.list ]; then
        $SUDO_CMD rm -f /etc/apt/sources.list.d/butterrepo.list /usr/share/keyrings/butterrepo.gpg 2>/dev/null || true
    fi

    if [ "$IS_UBUNTU_BASED" = true ]; then
        # Remove Debian_13 OBS repository on Ubuntu/Mint as it causes Qt 6.8 dependency conflicts
        if [ -f /etc/apt/sources.list.d/home-AvengeMedia-danklinux.list ]; then
            log_info "Removing incompatible Debian_13 repository on Ubuntu/Mint base..."
            $SUDO_CMD rm -f /etc/apt/sources.list.d/home-AvengeMedia-danklinux.list /etc/apt/keyrings/home-AvengeMedia-danklinux.gpg 2>/dev/null || true
        fi

        # Try adding DankLinux PPA for Ubuntu/Mint
        if ! apt-cache show quickshell &>/dev/null; then
            log_info "Configuring DankLinux PPA for Ubuntu/Mint ($UBUNTU_CODENAME)..."
            $SUDO_CMD mkdir -p /etc/apt/keyrings

            if ! command -v add-apt-repository &>/dev/null; then
                $SUDO_CMD apt update -y && $SUDO_CMD apt install -y software-properties-common 2>/dev/null || true
            fi

            # Explicitly add PPA for $UBUNTU_CODENAME to fix Linux Mint codename mismatches
            if ! [ -f /etc/apt/sources.list.d/avengemedia-danklinux.list ]; then
                echo "deb [signed-by=/etc/apt/keyrings/avengemedia-danklinux.gpg] https://ppa.launchpadcontent.net/avengemedia/danklinux/ubuntu $UBUNTU_CODENAME main" | $SUDO_CMD tee /etc/apt/sources.list.d/avengemedia-danklinux.list >/dev/null 2>/dev/null || true
                curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x8c4656689d0bdad9920d3f23497eaecb6f4e1f73" | $SUDO_CMD gpg --dearmor -o /etc/apt/keyrings/avengemedia-danklinux.gpg 2>/dev/null || true
            fi

            if command -v add-apt-repository &>/dev/null; then
                $SUDO_CMD add-apt-repository -y ppa:avengemedia/danklinux 2>/dev/null || true
            fi
        fi
    else
        # For Debian 13 / testing / trixie
        if ! apt-cache show quickshell &>/dev/null; then
            log_info "Adding DankLinux repository for Debian..."
            $SUDO_CMD mkdir -p /etc/apt/keyrings
            if ! [ -f /etc/apt/sources.list.d/home-AvengeMedia-danklinux.list ]; then
                curl -fsSL "https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_13/Release.key" | $SUDO_CMD gpg --dearmor -o /etc/apt/keyrings/home-AvengeMedia-danklinux.gpg 2>/dev/null || true
                echo "deb [signed-by=/etc/apt/keyrings/home-AvengeMedia-danklinux.gpg arch=amd64] https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_13/ /" | $SUDO_CMD tee /etc/apt/sources.list.d/home-AvengeMedia-danklinux.list >/dev/null
            fi
        fi
    fi

    $SUDO_CMD apt update -y

    # Core system packages (excluding quickshell to prevent apt batch transaction failure)
    PACKAGES=(
        bspwm sxhkd picom feh thunar thunar-archive-plugin flameshot cava btop lxpolkit xfce4-power-manager kitty xfce4-terminal xterm fastfetch git
        xclip xdotool x11-utils x11-xserver-utils pamixer playerctl wireplumber pipewire-audio
        brightnessctl upower power-profiles-daemon bluez bluez-tools bluez-obexd libspa-0.2-bluetooth network-manager
        python3 python3-gi python3-gi-cairo gir1.2-gtk-3.0 libx11-6 libxss1
        libqt6qml6 libqt6quick6 libqt6quickcontrols2-6 libqt6svg6 qml6-module-qtquick-controls
        qml6-module-qtquick-layouts qml6-module-qtquick-templates qml6-module-qtquick-shapes
        qml6-module-qtquick-window qml6-module-qtsvg qml6-module-qt5compat-graphicaleffects qml6-module-qtquick-effects qt6-gtk-platformtheme qt6-style-kvantum qt6ct
        fonts-font-awesome fonts-noto-color-emoji fonts-inter fonts-roboto fonts-jetbrains-mono
    )

    VALID_PACKAGES=()
    for pkg in "${PACKAGES[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            VALID_PACKAGES+=("$pkg")
        else
            log_warn "Package '$pkg' is not available in APT repositories. Skipping..."
        fi
    done

    if [ ${#VALID_PACKAGES[@]} -gt 0 ]; then
        log_info "Installing core system packages..."
        $SUDO_CMD apt install -y "${VALID_PACKAGES[@]}"
    fi

    # Install Quickshell in an isolated step
    if ! command -v quickshell &>/dev/null && ! command -v qs &>/dev/null; then
        log_info "Installing Quickshell package..."
        if apt-cache show quickshell &>/dev/null; then
            $SUDO_CMD apt install -y quickshell 2>/dev/null || log_warn "Quickshell APT installation failed due to system dependency constraints."
        else
            log_warn "Quickshell package not found in current APT repositories."
        fi

        # Auto fallback: Compile from source if quickshell is still missing
        if ! command -v quickshell &>/dev/null && ! command -v qs &>/dev/null; then
            log_warn "Quickshell is not present via APT. Falling back to automatic source build..."
            build_quickshell_from_source
        fi
    fi
}

install_arch() {
    log_info "Installing packages for Arch Linux..."

    PACKAGES=(
        base-devel bspwm sxhkd picom feh thunar thunar-archive-plugin flameshot cava btop lxsession xfce4-power-manager kitty xfce4-terminal xterm fastfetch git
        xclip xdotool xorg-xprop xorg-xset xorg-xrandr xorg-xsetroot pamixer playerctl wireplumber pipewire-pulse
        brightnessctl upower power-profiles-daemon bluez bluez-utils networkmanager
        python python-gobject gtk3 libx11 libxss
        qt6-declarative qt6-svg qt6-5compat kvantum qt6ct
        ttf-font-awesome noto-fonts-emoji inter-font ttf-roboto ttf-jetbrains-mono
    )

    # Check if quickshell is available in pacman official repositories
    if pacman -Si quickshell &>/dev/null; then
        PACKAGES+=(quickshell)
    fi

    $SUDO_CMD pacman -S --needed --noconfirm "${PACKAGES[@]}"

    # Install Quickshell from AUR if not present
    if ! command -v quickshell &>/dev/null && ! command -v qs &>/dev/null; then
        log_info "Installing Quickshell from AUR..."
        REAL_USER="${SUDO_USER:-$USER}"
        if command -v yay &>/dev/null; then
            if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
                su "$SUDO_USER" -c "yay -S --needed --noconfirm quickshell" 2>/dev/null || su "$SUDO_USER" -c "yay -S --needed --noconfirm quickshell-git"
            else
                yay -S --needed --noconfirm quickshell 2>/dev/null || yay -S --needed --noconfirm quickshell-git
            fi
        elif command -v paru &>/dev/null; then
            if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
                su "$SUDO_USER" -c "paru -S --needed --noconfirm quickshell" 2>/dev/null || su "$SUDO_USER" -c "paru -S --needed --noconfirm quickshell-git"
            else
                paru -S --needed --noconfirm quickshell 2>/dev/null || paru -S --needed --noconfirm quickshell-git
            fi
        else
            log_info "No AUR helper found. Building quickshell-git manually..."
            BUILD_DIR=$(mktemp -d)
            chmod 777 "$BUILD_DIR"
            git clone https://aur.archlinux.org/quickshell-git.git "$BUILD_DIR"
            chown -R "$REAL_USER" "$BUILD_DIR" 2>/dev/null || true
            if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
                su "$SUDO_USER" -c "cd '$BUILD_DIR' && makepkg -si --noconfirm"
            else
                (cd "$BUILD_DIR" && makepkg -si --noconfirm)
            fi
            rm -rf "$BUILD_DIR"
        fi
    fi
}

install_fedora() {
    log_info "Installing packages for Fedora..."

    # Enable COPR repo for quickshell if available
    $SUDO_CMD dnf copr enable -y avengemedia/danklinux 2>/dev/null || true

    PACKAGES=(
        bspwm sxhkd picom feh thunar thunar-archive-plugin flameshot cava btop lxpolkit xfce4-power-manager kitty xfce4-terminal xterm fastfetch git
        xclip xdotool xprop xset xrandr xsetroot pamixer playerctl wireplumber pipewire pipewire-plugin-spa-bluetooth
        brightnessctl upower power-profiles-daemon bluez bluez-tools NetworkManager
        python3 python3-gobject gtk3 libX11 libXScrnSaver
        qt6-qtdeclarative qt6-qtsvg qt6-qt5compat kvantum-qt6 qt6ct
        fontawesome-fonts google-noto-emoji-fonts google-roboto-fonts jetbrains-mono-fonts
    )

    $SUDO_CMD dnf install -y "${PACKAGES[@]}"

    if ! command -v quickshell &>/dev/null && ! command -v qs &>/dev/null; then
        $SUDO_CMD dnf install -y quickshell 2>/dev/null || log_warn "Quickshell package not found in Fedora repos. Please install Quickshell manually."
    fi
}

install_dependencies() {
    case "$DISTRO_TYPE" in
        debian)
            install_debian
            ;;
        arch)
            install_arch
            ;;
        fedora)
            install_fedora
            ;;
        *)
            log_error "Unsupported Linux distribution."
            exit 1
            ;;
    esac
    log_success "All system dependencies installed successfully!"
}

prepare_source_dir() {
    if [ -z "$SCRIPT_DIR" ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    fi

    if [ ! -d "$SCRIPT_DIR/bspwm" ]; then
        log_info "Source repository directory not found at $SCRIPT_DIR/bspwm."
        log_info "Cloning azkia-shell repository automatically..."

        if ! command -v git &>/dev/null; then
            log_info "Installing git..."
            case "$DISTRO_TYPE" in
                debian)
                    $SUDO_CMD apt update -y && $SUDO_CMD apt install -y git
                    ;;
                arch)
                    $SUDO_CMD pacman -S --needed --noconfirm git
                    ;;
                fedora)
                    $SUDO_CMD dnf install -y git
                    ;;
            esac
        fi

        TEMP_REPO_DIR=$(mktemp -d)
        log_info "Cloning repository to $TEMP_REPO_DIR..."
        git clone https://github.com/irfan-taufik03/azkia-shell.git "$TEMP_REPO_DIR"
        SCRIPT_DIR="$TEMP_REPO_DIR"
        trap 'rm -rf "$TEMP_REPO_DIR"' EXIT
    fi
}

deploy_config() {
    TARGET_DIR="$HOME/.config/bspwm"

    log_info "Deploying BSPWM and Azkia Shell configuration..."

    # Backup existing configuration if present
    if [ -d "$TARGET_DIR" ]; then
        BACKUP_DIR="${TARGET_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
        log_warn "Existing config found at $TARGET_DIR. Creating backup at $BACKUP_DIR..."
        mv "$TARGET_DIR" "$BACKUP_DIR"
    fi

    # Create target directory
    mkdir -p "$TARGET_DIR"

    # Copy files from repository bspwm/ directory to ~/.config/bspwm
    SRC_DIR="$SCRIPT_DIR/bspwm"
    if [ -d "$SRC_DIR" ]; then
        cp -r "$SRC_DIR"/* "$TARGET_DIR/"
    else
        log_error "Source bspwm directory not found at $SRC_DIR!"
        exit 1
    fi

    # Replace hardcoded home paths in appearance.json with current user's $HOME
    APPEARANCE_FILE="$TARGET_DIR/azkia-shell/appearance.json"
    if [ -f "$APPEARANCE_FILE" ]; then
        log_info "Configuring $APPEARANCE_FILE for user $USER..."
        sed -i "s|/home/[^/]*|$HOME|g" "$APPEARANCE_FILE"
    fi

    # Set executable permissions on scripts and config entry points
    log_info "Setting executable permissions..."
    chmod +x "$TARGET_DIR/bspwmrc"
    chmod +x "$TARGET_DIR/bspwmrc.default"
    chmod +x "$TARGET_DIR/scripts/"*.sh 2>/dev/null || true
    chmod +x "$TARGET_DIR/azkia-shell/scripts/"*.py 2>/dev/null || true
    chmod +x "$TARGET_DIR/azkia-shell/scripts/"*.sh 2>/dev/null || true

    # Deploy Kitty configuration to ~/.config/kitty/
    KITTY_TARGET="$HOME/.config/kitty"
    mkdir -p "$KITTY_TARGET"
    if [ -d "$SCRIPT_DIR/kitty" ]; then
        cp -r "$SCRIPT_DIR/kitty"/* "$KITTY_TARGET/"
        log_info "Deployed Kitty configuration to $KITTY_TARGET/kitty.conf"
    fi

    # Deploy Fastfetch configuration to ~/.config/fastfetch/
    FASTFETCH_TARGET="$HOME/.config/fastfetch"
    mkdir -p "$FASTFETCH_TARGET"
    if [ -d "$SCRIPT_DIR/fastfetch" ]; then
        cp -r "$SCRIPT_DIR/fastfetch"/* "$FASTFETCH_TARGET/"
        log_info "Deployed Fastfetch configuration to $FASTFETCH_TARGET/"
    fi

    # Replace hardcoded home paths in fastfetch config.jsonc
    FASTFETCH_CONF="$FASTFETCH_TARGET/config.jsonc"
    if [ -f "$FASTFETCH_CONF" ]; then
        sed -i "s|/home/[^/]*|$HOME|g" "$FASTFETCH_CONF"
    fi

    # Create default ~/.fehbg wallpaper script if not present
    if [ ! -f "$HOME/.fehbg" ] && [ -f "$TARGET_DIR/wallpapers/Default.png" ]; then
        log_info "Creating default ~/.fehbg wallpaper script..."
        echo '#!/bin/sh' > "$HOME/.fehbg"
        echo "feh --no-fehbg --bg-fill '$TARGET_DIR/wallpapers/Default.png'" >> "$HOME/.fehbg"
        chmod +x "$HOME/.fehbg"
    fi

    # Create helper symlink for qs -> quickshell in ~/.local/bin if needed
    mkdir -p "$HOME/.local/bin"
    if command -v quickshell &>/dev/null && ! command -v qs &>/dev/null; then
        log_info "Creating helper symlink for qs -> quickshell..."
        ln -sf "$(command -v quickshell)" "$HOME/.local/bin/qs"
    fi

    log_success "Configuration deployed to $TARGET_DIR successfully!"
}

deploy_fonts() {
    log_info "Deploying custom fonts to ~/.local/share/fonts/..."
    FONT_TARGET="$HOME/.local/share/fonts"

    mkdir -p "$FONT_TARGET"

    if [ -d "$SCRIPT_DIR/fonts" ]; then
        cp -r "$SCRIPT_DIR/fonts"/* "$FONT_TARGET/"
        log_success "Copied custom font files (Ubuntu Nerd Font, JetBrainsMono Nerd Font, FontAwesome, NotoColorEmoji) to $FONT_TARGET/"
    fi

    if command -v fc-cache &>/dev/null; then
        log_info "Updating font cache with fc-cache -f..."
        fc-cache -f "$FONT_TARGET" 2>/dev/null || true
    fi
}

setup_gtk_theme() {
    log_info "Deploying and applying Nordic-darker GTK theme and Sweet-cursors cursor..."

    # Create target theme & icon directories
    mkdir -p "$HOME/.themes" "$HOME/.icons" "$HOME/.local/share/themes" "$HOME/.local/share/icons"

    # Copy GTK Theme
    if [ -d "$SCRIPT_DIR/themes/Nordic-darker" ]; then
        cp -r "$SCRIPT_DIR/themes/Nordic-darker" "$HOME/.themes/"
        cp -r "$SCRIPT_DIR/themes/Nordic-darker" "$HOME/.local/share/themes/"
        log_success "Copied Nordic-darker theme to ~/.themes/ and ~/.local/share/themes/"
    fi

    # Copy Cursor Theme
    if [ -d "$SCRIPT_DIR/icons/Sweet-cursors" ]; then
        cp -r "$SCRIPT_DIR/icons/Sweet-cursors" "$HOME/.icons/"
        cp -r "$SCRIPT_DIR/icons/Sweet-cursors" "$HOME/.local/share/icons/"
        log_success "Copied Sweet-cursors to ~/.icons/ and ~/.local/share/icons/"
    fi

    # Apply via gsettings (if available)
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.desktop.interface gtk-theme "Nordic-darker" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface icon-theme "Nordic-darker" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface cursor-theme "Sweet-cursors" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
    fi

    # Write GTK 3 settings.ini
    mkdir -p "$HOME/.config/gtk-3.0"
    cat << 'EOF' > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Nordic-darker
gtk-icon-theme-name=Nordic-darker
gtk-cursor-theme-name=Sweet-cursors
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
EOF

    # Write GTK 4 settings.ini
    mkdir -p "$HOME/.config/gtk-4.0"
    cat << 'EOF' > "$HOME/.config/gtk-4.0/settings.ini"
[Settings]
gtk-theme-name=Nordic-darker
gtk-icon-theme-name=Nordic-darker
gtk-cursor-theme-name=Sweet-cursors
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
EOF

    # Write Default X11 cursor index.theme
    mkdir -p "$HOME/.icons/default"
    cat << 'EOF' > "$HOME/.icons/default/index.theme"
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=Sweet-cursors
EOF

    # Apply cursor immediately via xsetroot if running in X11
    if command -v xsetroot &>/dev/null && [ -n "$DISPLAY" ]; then
        xsetroot -cursor_name left_ptr 2>/dev/null || true
    fi

    log_success "Applied Nordic-darker GTK theme and Sweet-cursors cursor successfully!"
}

setup_xsessions() {
    log_info "Setting up Xsession desktop entry for BSPWM..."
    DESKTOP_ENTRY="/usr/share/xsessions/bspwm.desktop"

    if [ ! -f "$DESKTOP_ENTRY" ]; then
        log_info "Creating $DESKTOP_ENTRY..."
        $SUDO_CMD bash -c "cat << 'EOF' > $DESKTOP_ENTRY
[Desktop Entry]
Name=BSPWM
Comment=Binary Space Partitioning Window Manager
Exec=bspwm
Type=Application
DesktopNames=bspwm
EOF"
        log_success "Created $DESKTOP_ENTRY"
    fi

    # Also create ~/.xinitrc if user doesn't have one
    XINITRC="$HOME/.xinitrc"
    if [ ! -f "$XINITRC" ]; then
        log_info "Creating default $XINITRC..."
        echo "sxhkd &" > "$XINITRC"
        echo "exec bspwm" >> "$XINITRC"
        chmod +x "$XINITRC"
    fi
}

setup_display_manager() {
    log_info "Checking for an existing Display Manager (LightDM, GDM, SDDM, Ly, LXDM)..."

    if command -v lightdm &>/dev/null || \
       command -v gdm &>/dev/null || \
       command -v gdm3 &>/dev/null || \
       command -v sddm &>/dev/null || \
       command -v ly &>/dev/null || \
       command -v lxdm &>/dev/null || \
       systemctl is-enabled display-manager &>/dev/null 2>/dev/null; then
        log_success "Display Manager is already installed and configured."
        return 0
    fi

    log_warn "No Display Manager detected! Installing LightDM as default login manager..."

    case "$DISTRO_TYPE" in
        debian)
            $SUDO_CMD apt install -y lightdm lightdm-gtk-greeter 2>/dev/null || $SUDO_CMD apt install -y lightdm
            ;;
        arch)
            $SUDO_CMD pacman -S --needed --noconfirm lightdm lightdm-gtk-greeter
            ;;
        fedora)
            $SUDO_CMD dnf install -y lightdm lightdm-gtk-greeter
            ;;
    esac

    if command -v systemctl &>/dev/null; then
        log_info "Enabling LightDM system service..."
        $SUDO_CMD systemctl enable lightdm 2>/dev/null || true
        $SUDO_CMD systemctl set-default graphical.target 2>/dev/null || true
    fi

    log_success "LightDM Display Manager installed and enabled successfully!"
}

enable_services() {
    log_info "Enabling and starting system services (Bluetooth & NetworkManager)..."
    $SUDO_CMD systemctl enable --now bluetooth 2>/dev/null || true
    $SUDO_CMD systemctl enable --now NetworkManager 2>/dev/null || true
    $SUDO_CMD systemctl enable --now power-profiles-daemon 2>/dev/null || true
}

verify_installation() {
    echo -e "\n${PURPLE}====================================================${NC}"
    log_info "Verifying installed components..."

    ERRORS=0
    for cmd in bspwm sxhkd picom feh python3 pamixer brightnessctl playerctl bluetoothctl nmcli kitty fastfetch; do
        if command -v "$cmd" &>/dev/null; then
            echo -e "  [${GREEN}OK${NC}] Command '$cmd' is available."
        else
            echo -e "  [${RED}MISSING${NC}] Command '$cmd' was not found!"
            ERRORS=$((ERRORS + 1))
        fi
    done

    # Verify Quickshell binary (binary can be 'quickshell' or 'qs')
    if command -v quickshell &>/dev/null || command -v qs &>/dev/null; then
        echo -e "  [${GREEN}OK${NC}] Quickshell engine is available."
    else
        echo -e "  [${RED}MISSING${NC}] Quickshell binary (quickshell/qs) was not found!"
        ERRORS=$((ERRORS + 1))
    fi

    # Check Python GTK / X11 bindings
    if python3 -c "import gi; gi.require_version('Gtk', '3.0'); from gi.repository import Gtk; import ctypes; ctypes.cdll.LoadLibrary('libX11.so.6')" &>/dev/null; then
        echo -e "  [${GREEN}OK${NC}] Python GTK3 & libX11 bindings verified."
    else
        echo -e "  [${YELLOW}WARN${NC}] Python GTK3 or libX11 bindings check failed."
    fi

    if [ "$ERRORS" -eq 0 ]; then
        echo -e "\n${GREEN}✔ Azkia Shell & BSPWM Installation Completed Successfully!${NC}"
        echo -e "To start your new BSPWM environment:"
        echo -e "  1. Log out of your current session."
        echo -e "  2. Select 'BSPWM' from your Display Manager (LightDM/GDM/SDDM)."
        echo -e "  3. Or run 'startx' from a TTY.\n"
    else
        echo -e "\n${YELLOW}Installation completed with $ERRORS warning(s). Please review missing components above.${NC}\n"
    fi
}

main() {
    print_banner
    check_root_or_sudo
    detect_distro
    install_dependencies
    prepare_source_dir
    deploy_config
    deploy_fonts
    setup_gtk_theme
    setup_xsessions
    setup_display_manager
    enable_services
    verify_installation
}

main "$@"
