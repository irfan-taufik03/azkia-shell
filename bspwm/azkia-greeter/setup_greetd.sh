#!/usr/bin/env bash
set -e

# ====================================================================
# Azkia Greeter Universal Installer for greetd
# Mendukung berbagai distribusi Linux (Fedora, Arch, Debian, Ubuntu,
# openSUSE, Void, Alpine, dsb.)
# ====================================================================

# 1. Pastikan dijalankan sebagai root / sudo
if [ "$EUID" -ne 0 ]; then
    echo "[-] Harap jalankan skrip ini dengan hak akses root/sudo:"
    echo "    sudo bash $0"
    exit 1
fi

# 2. Deteksi user asli yang menjalankan sudo
CURRENT_USER="${SUDO_USER:-$USER}"
if [ "$CURRENT_USER" = "root" ]; then
    REAL_USER=$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "root")
    if [ "$REAL_USER" != "root" ]; then
        CURRENT_USER="$REAL_USER"
    fi
fi

USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
GREETER_DIR="$USER_HOME/.config/bspwm/azkia-greeter"

if [ ! -d "$GREETER_DIR" ]; then
    echo "[-] Direktori greeter tidak ditemukan di: $GREETER_DIR"
    exit 1
fi

# 3. Deteksi Distribusi Linux
DISTRO_NAME="Linux"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_NAME="${PRETTY_NAME:-$NAME}"
fi

echo "===================================================================="
echo "          Azkia Greeter Universal Installer (greetd)               "
echo "===================================================================="
echo "[+] Distribusi Terdeteksi : $DISTRO_NAME"
echo "[+] Pengguna             : $CURRENT_USER ($USER_HOME)"
echo "[+] Lokasi Greeter       : $GREETER_DIR"
echo "--------------------------------------------------------------------"

# 4. Deteksi Display Manager yang sedang aktif/terpasang untuk backup rollback
PREV_DM=""
if command -v systemctl &>/dev/null; then
    for dm in lightdm sddm gdm ly lxdm greetd; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
            if [ "$dm" != "greetd" ]; then
                PREV_DM="$dm"
                break
            fi
        fi
    done
fi
if [ -z "$PREV_DM" ]; then
    PREV_DM="lightdm"
fi
echo "$PREV_DM" > "$GREETER_DIR/.previous_dm"
echo "[+] Display Manager sebelumnya tersimpan: $PREV_DM"

# 5. Fungsi instalasi paket otomatis sesuai package manager distro
install_packages() {
    local pkgs=("$@")
    echo "[*] Menginstall dependensi: ${pkgs[*]} ..."

    if command -v pacman &>/dev/null; then
        # Arch Linux, Manjaro, EndeavourOS, ArcoLinux, Garuda
        pacman -Sy --noconfirm --needed "${pkgs[@]}"
    elif command -v dnf5 &>/dev/null; then
        # Fedora modern (dnf5)
        dnf5 install -y "${pkgs[@]}"
    elif command -v dnf &>/dev/null; then
        # Fedora, RHEL 8+, Alma, Rocky, CentOS Stream
        dnf install -y "${pkgs[@]}"
    elif command -v yum &>/dev/null; then
        # RHEL / CentOS legacy
        yum install -y "${pkgs[@]}"
    elif command -v apt-get &>/dev/null; then
        # Debian, Ubuntu, Linux Mint, Pop!_OS, Zorin, Kali
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y "${pkgs[@]}"
    elif command -v zypper &>/dev/null; then
        # openSUSE Tumbleweed & Leap
        zypper --non-interactive in -y "${pkgs[@]}"
    elif command -v xbps-install &>/dev/null; then
        # Void Linux
        xbps-install -Sy "${pkgs[@]}"
    elif command -v apk &>/dev/null; then
        # Alpine Linux
        apk add "${pkgs[@]}"
    elif command -v emerge &>/dev/null; then
        # Gentoo
        emerge --ask=n "${pkgs[@]}"
    elif command -v eopkg &>/dev/null; then
        # Solus
        eopkg install -y "${pkgs[@]}"
    else
        echo "[!] Package manager tidak dikenali secara otomatis."
        echo "    Harap install paket berikut secara manual jika belum ada: ${pkgs[*]}"
        return 1
    fi
}

# 6. Periksa dan install greetd jika belum terpasang
if ! command -v greetd &>/dev/null; then
    echo "[*] greetd belum terpasang di sistem. Memulai instalasi..."
    if command -v pacman &>/dev/null; then
        install_packages greetd xorg-xinit
    elif command -v apt-get &>/dev/null; then
        install_packages greetd xinit
    elif command -v dnf &>/dev/null || command -v dnf5 &>/dev/null; then
        install_packages greetd xorg-x11-xinit
    elif command -v zypper &>/dev/null; then
        install_packages greetd xinit
    elif command -v xbps-install &>/dev/null; then
        install_packages greetd xinit
    elif command -v apk &>/dev/null; then
        install_packages greetd xinit
    else
        install_packages greetd
    fi
else
    echo "[✓] greetd sudah terpasang di sistem."
fi

# 7. Periksa xinit (dibutuhkan untuk menjalankan server X11 mandiri pada greetd)
if ! command -v xinit &>/dev/null; then
    echo "[*] xinit belum terpasang. Memasang xinit..."
    if command -v pacman &>/dev/null; then
        install_packages xorg-xinit
    elif command -v dnf &>/dev/null || command -v dnf5 &>/dev/null; then
        install_packages xorg-x11-xinit
    else
        install_packages xinit
    fi
else
    echo "[✓] xinit sudah terpasang di sistem."
fi

# 8. Periksa quickshell (qs)
if ! su - "$CURRENT_USER" -c "command -v qs" &>/dev/null && [ ! -x "/usr/bin/qs" ] && [ ! -x "/usr/local/bin/qs" ]; then
    echo "[!] PERINGATAN: quickshell ('qs') belum terdeteksi di PATH $CURRENT_USER."
    echo "    Pastikan Quickshell sudah terinstall agar antarmuka greeter dapat tampil."
else
    echo "[✓] quickshell terverifikasi."
fi

# 9. Konfigurasi /etc/greetd/config.toml
mkdir -p /etc/greetd

if [ -f /etc/greetd/config.toml ]; then
    BACKUP_FILE="/etc/greetd/config.toml.bak_$(date +%Y%m%d_%H%M%S)"
    echo "[*] Membuat cadangan konfigurasi greetd lama ke: $BACKUP_FILE"
    cp -v /etc/greetd/config.toml "$BACKUP_FILE"
fi

echo "[*] Menulis konfigurasi /etc/greetd/config.toml..."
cat << EOF > /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "xinit /usr/bin/bash $GREETER_DIR/scripts/launch.sh -- :0"
user = "$CURRENT_USER"
EOF

chmod 644 /etc/greetd/config.toml

# 10. Konfigurasi Polkit & Sudoers rule untuk suspend, reboot, dan poweroff di greetd
echo "[*] Memasang aturan Polkit di /etc/polkit-1/rules.d/40-azkia-greeter.rules..."
mkdir -p /etc/polkit-1/rules.d /usr/share/polkit-1/rules.d

RULE_CONTENT='polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.login1.") == 0 ||
        action.id.indexOf("org.freedesktop.consolekit.system.") == 0 ||
        action.id.indexOf("org.freedesktop.upower.") == 0 ||
        action.id.indexOf("org.freedesktop.udisks2.") == 0) {
        if (subject.user == "'"$CURRENT_USER"'" ||
            subject.user == "greeter" ||
            subject.user == "greetd" ||
            subject.user == "vaan" ||
            subject.isInGroup("wheel")) {
            return polkit.Result.YES;
        }
    }
});'

echo "$RULE_CONTENT" > /etc/polkit-1/rules.d/40-azkia-greeter.rules
chmod 644 /etc/polkit-1/rules.d/40-azkia-greeter.rules

if [ -d /usr/share/polkit-1/rules.d ]; then
    echo "$RULE_CONTENT" > /usr/share/polkit-1/rules.d/40-azkia-greeter.rules
    chmod 644 /usr/share/polkit-1/rules.d/40-azkia-greeter.rules
fi

echo "[*] Memasang fallback Sudoers di /etc/sudoers.d/40-azkia-greeter..."
mkdir -p /etc/sudoers.d
SUDOERS_FILE="/etc/sudoers.d/40-azkia-greeter"
cat << 'EOF' > "$SUDOERS_FILE"
# Azkia Greeter power management fallback
ALL ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot, /usr/bin/systemctl suspend, /usr/bin/loginctl poweroff, /usr/bin/loginctl reboot, /usr/bin/loginctl suspend, /usr/bin/poweroff, /usr/bin/reboot
EOF
chmod 440 "$SUDOERS_FILE"

if command -v visudo &>/dev/null; then
    if ! visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
        rm -f "$SUDOERS_FILE"
    fi
fi

if systemctl is-active --quiet polkit; then
    systemctl restart polkit 2>/dev/null || true
fi

# 11. Berikan izin eksekusi pada skrip
chmod +x "$GREETER_DIR/scripts/launch.sh"
chmod +x "$GREETER_DIR/scripts/greetd_backend.py"
chmod +x "$GREETER_DIR/scripts/xsession_wrapper.sh"
chmod +x "$GREETER_DIR/install_polkit_rule.sh"
chmod +x "$GREETER_DIR/test_preview.sh"
chmod +x "$GREETER_DIR/restore_lightdm.sh"

echo "===================================================================="
echo " [SUKSES] Konfigurasi greetd untuk Azkia Greeter berhasil dipasang! "
echo "===================================================================="
echo ""
echo "Perintah untuk mengaktifkan greetd di sistem Anda:"
if command -v systemctl &>/dev/null; then
    echo "  sudo systemctl disable $PREV_DM"
    echo "  sudo systemctl enable greetd"
elif command -v rc-update &>/dev/null; then
    echo "  sudo rc-update del $PREV_DM default"
    echo "  sudo rc-update add greetd default"
elif [ -d /etc/sv ]; then
    echo "  sudo rm -f /var/service/$PREV_DM"
    echo "  sudo ln -s /etc/sv/greetd /var/service/"
fi
echo ""
echo "Jika sewaktu-waktu ingin kembali ke Display Manager sebelumnya ($PREV_DM):"
echo "  sudo bash $GREETER_DIR/restore_lightdm.sh"
echo "===================================================================="
