#!/usr/bin/env bash
# Open Terminal helper with OpenGL/VM fallback support

if command -v kitty &>/dev/null; then
    # Try launching kitty. If it fails (e.g. OpenGL issue in VMs), fall back
    kitty "$@" 2>/tmp/kitty-err.log || {
        if command -v xfce4-terminal &>/dev/null; then
            xfce4-terminal "$@"
        elif command -v xterm &>/dev/null; then
            xterm "$@"
        elif command -v x-terminal-emulator &>/dev/null; then
            x-terminal-emulator "$@"
        fi
    }
elif command -v xfce4-terminal &>/dev/null; then
    xfce4-terminal "$@"
elif command -v xterm &>/dev/null; then
    xterm "$@"
elif command -v x-terminal-emulator &>/dev/null; then
    x-terminal-emulator "$@"
fi
