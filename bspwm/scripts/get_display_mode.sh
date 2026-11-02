#!/bin/bash
# Read saved display mode from state file (written by display_setup.sh)

MODE_FILE="$HOME/.config/bspwm/display_mode"

if [ -f "$MODE_FILE" ]; then
    mode=$(cat "$MODE_FILE" | tr -d '[:space:]')
    case "$mode" in
        mirror|extend|off)
            echo "$mode"
            exit 0
            ;;
    esac
fi

# Fallback: auto-detect from bspwm monitor count
pri=$(xrandr --query | awk '/ primary/{print $1}')
[ -z "$pri" ] && pri=$(xrandr --query | awk '/ connected/{print $1}' | head -n1)
sec=$(xrandr --query | awk -v p="$pri" '/ connected/{if ($1 != p) {print $1; exit}}')

if [ -z "$sec" ]; then
    echo "off"
elif bspc query -M --names 2>/dev/null | grep -q "^$sec$"; then
    echo "extend"
else
    echo "mirror"
fi
