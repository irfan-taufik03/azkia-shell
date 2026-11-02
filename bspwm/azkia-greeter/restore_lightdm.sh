#!/usr/bin/env bash
set -e

# ====================================================================
# Rollback Script: Mengembalikan Display Manager ke Kondisi Semula
# Universal multi-distro
# ====================================================================

if [ "$EUID" -ne 0 ]; then
    echo "Harap jalankan skrip ini dengan hak akses sudo:"
    echo "  sudo bash $0"
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DM="lightdm"

if [ -f "$DIR/.previous_dm" ]; then
    SAVED_DM=$(cat "$DIR/.previous_dm" | tr -d '[:space:]')
    if [ -n "$SAVED_DM" ]; then
        TARGET_DM="$SAVED_DM"
    fi
fi

echo "==> Menonaktifkan greetd..."
if command -v systemctl &>/dev/null; then
    systemctl disable greetd 2>/dev/null || true
    echo "==> Mengaktifkan kembali $TARGET_DM..."
    systemctl enable "$TARGET_DM"
elif command -v rc-update &>/dev/null; then
    rc-update del greetd default 2>/dev/null || true
    echo "==> Mengaktifkan kembali $TARGET_DM..."
    rc-update add "$TARGET_DM" default 2>/dev/null || true
elif [ -d /etc/sv ]; then
    rm -f /var/service/greetd 2>/dev/null || true
    if [ -d "/etc/sv/$TARGET_DM" ]; then
        ln -s "/etc/sv/$TARGET_DM" /var/service/
    fi
fi

rm -f /etc/polkit-1/rules.d/40-azkia-greeter.rules 2>/dev/null || true

echo ""
echo "===================================================================="
echo " [SUKSES] Display Manager $TARGET_DM telah aktif kembali!"
echo " Sistem aman dan siap digunakan seperti semula."
echo "===================================================================="
