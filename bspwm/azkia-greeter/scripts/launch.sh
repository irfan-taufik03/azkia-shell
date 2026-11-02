#!/usr/bin/env bash
# ====================================================================
# Azkia Greeter Launcher for greetd
# Universal multi-distro launcher
# ====================================================================

# Clean environment from user preload libraries to prevent SELinux denials in greeter
unset LD_PRELOAD

export XDG_CURRENT_DESKTOP="Azkia"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Detect quickshell binary across standard distro paths
QS_BIN=$(command -v qs 2>/dev/null || true)
if [ -z "$QS_BIN" ]; then
    for candidate in /usr/bin/qs /usr/local/bin/qs "$HOME/.local/bin/qs" "$HOME/.cargo/bin/qs"; do
        if [ -x "$candidate" ]; then
            QS_BIN="$candidate"
            break
        fi
    done
fi

if [ -z "$QS_BIN" ]; then
    echo "ERROR: quickshell (qs) binary not found!" >&2
    exit 1
fi

exec "$QS_BIN" -p "$DIR"
