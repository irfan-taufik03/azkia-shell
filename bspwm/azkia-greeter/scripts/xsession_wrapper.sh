#!/usr/bin/env bash
# ====================================================================
# Azkia Greeter X11 Session Wrapper
# Mempersiapkan lingkungan desktop X11 lengkap saat login via greetd
# ====================================================================

export XDG_SESSION_TYPE="x11"

# 1. Muat profil sistem & pengguna jika ada
if [ -f /etc/profile ]; then
    . /etc/profile
fi
if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi
if [ -f "$HOME/.bash_profile" ]; then
    . "$HOME/.bash_profile"
fi

# 2. Muat skrip inisialisasi X11 sistem (xinitrc.d)
if [ -d /etc/X11/xinit/xinitrc.d ]; then
    for f in /etc/X11/xinit/xinitrc.d/*; do
        if [ -x "$f" ]; then
            . "$f"
        elif [ -f "$f" ]; then
            . "$f"
        fi
    done
fi

# 3. Pulihkan SHELL ke shell default user (fish) & sinkronisasi ke systemd --user / DBus
USER_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
if [ -n "$USER_SHELL" ] && [ -x "$USER_SHELL" ]; then
    export SHELL="$USER_SHELL"
fi

if command -v dbus-update-activation-environment &>/dev/null; then
    dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE SHELL 2>/dev/null || true
fi
if command -v systemctl &>/dev/null; then
    systemctl --user import-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE SHELL 2>/dev/null || true
fi

# 4. Eksekusi window manager / desktop session yang dipilih
if [ $# -gt 0 ]; then
    exec "$@"
elif [ -x "$HOME/.xinitrc" ]; then
    exec "$HOME/.xinitrc"
else
    exec bspwm
fi
