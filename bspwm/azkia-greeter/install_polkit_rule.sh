#!/usr/bin/env bash
set -e

# ====================================================================
# Azkia Greeter - Polkit & Sudoers Permissions Installer for Power Actions
# Memberikan izin suspend, reboot, dan poweroff untuk sesi greetd
# ====================================================================

if [ "$EUID" -ne 0 ]; then
    if command -v pkexec &>/dev/null; then
        echo "[*] Meminta izin root melalui GUI/pkexec..."
        exec pkexec "$0" "$@"
    else
        echo "[-] Harap jalankan skrip ini dengan hak akses root/sudo:"
        echo "    sudo bash $0"
        exit 1
    fi
fi

CURRENT_USER="${SUDO_USER:-$USER}"
if [ "$CURRENT_USER" = "root" ]; then
    REAL_USER=$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "vaan")
    if [ "$REAL_USER" != "root" ]; then
        CURRENT_USER="$REAL_USER"
    fi
fi

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

# Pasang juga cadangan di /usr/share/polkit-1/rules.d/ jika ada
if [ -d /usr/share/polkit-1/rules.d ]; then
    echo "$RULE_CONTENT" > /usr/share/polkit-1/rules.d/40-azkia-greeter.rules
    chmod 644 /usr/share/polkit-1/rules.d/40-azkia-greeter.rules
fi

# Pasang juga aturan sudoers tanpa password sebagai lapisan fallback tangguh
echo "[*] Menyiapkan fallback sudoers di /etc/sudoers.d/40-azkia-greeter..."
mkdir -p /etc/sudoers.d
SUDOERS_FILE="/etc/sudoers.d/40-azkia-greeter"
cat << 'EOF' > "$SUDOERS_FILE"
# Azkia Greeter power management fallback
ALL ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot, /usr/bin/systemctl suspend, /usr/bin/loginctl poweroff, /usr/bin/loginctl reboot, /usr/bin/loginctl suspend, /usr/bin/poweroff, /usr/bin/reboot
EOF
chmod 440 "$SUDOERS_FILE"

if command -v visudo &>/dev/null; then
    if ! visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
        echo "[-] Konfigurasi sudoers tidak valid, menghapus..."
        rm -f "$SUDOERS_FILE"
    fi
fi

# Muat ulang / restart polkit service agar aturan baru segera aktif
if systemctl is-active --quiet polkit; then
    echo "[*] Memuat ulang Polkit..."
    systemctl restart polkit 2>/dev/null || true
fi

echo "[✓] Aturan Polkit dan Sudoers berhasil dipasang dan diaktifkan!"
echo "    Sesi greetd kini dapat melakukan Suspend, Restart, dan Power Off tanpa terhalang otentikasi."
