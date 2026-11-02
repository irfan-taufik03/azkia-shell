#!/bin/bash
# Script to manage display modes, wallpapers, and preserve open windows across monitors

MODE="${1:-auto}"
MODE_FILE="$HOME/.config/bspwm/display_mode"

pri=$(xrandr --query | awk '/ primary/{print $1}')
if [ -z "$pri" ]; then
    pri=$(xrandr --query | awk '/ connected/{print $1}' | head -n1)
fi

sec=$(xrandr --query | awk '/ connected/{if ($1 != "'"$pri"'") print $1}' | head -n1)

# Apply xrandr configuration
if [ -n "$sec" ] && [ "$sec" != "$pri" ]; then
    case "$MODE" in
        extend)
            xrandr --output "$sec" --auto --right-of "$pri"
            echo "extend" > "$MODE_FILE"
            ;;
        mirror)
            xrandr --output "$sec" --auto --same-as "$pri"
            echo "mirror" > "$MODE_FILE"
            ;;
        off)
            xrandr --output "$sec" --off
            xrandr --output "$pri" --auto
            echo "off" > "$MODE_FILE"
            ;;
        auto)
            xrandr --output "$pri" --auto
            echo "off" > "$MODE_FILE"
            ;;
    esac
else
    xrandr --output "$pri" --auto
    echo "off" > "$MODE_FILE"
fi

active_xrandr_sec=$(xrandr --query | awk '/ connected/{if ($1 != "'"$pri"'") print $1}' | head -n1)

if [ -n "$active_xrandr_sec" ] && [ "$MODE" = "extend" ]; then
    # EXTEND MODE: Assign 1..10 to primary and 1_ext..10_ext to secondary
    bspc monitor "$pri" -d 1 2 3 4 5 6 7 8 9 10
    bspc monitor "$sec" -d 1_ext 2_ext 3_ext 4_ext 5_ext 6_ext 7_ext 8_ext 9_ext 10_ext
else
    # MIRROR MODE / OFF / SINGLE MONITOR:
    # Safely transfer all open windows (nodes) on secondary extended desktops to primary desktops
    for d in 1_ext 2_ext 3_ext 4_ext 5_ext 6_ext 7_ext 8_ext 9_ext 10_ext; do
        if bspc query -D -d "$d" >/dev/null 2>&1; then
            target_d=$(echo "$d" | sed 's/_ext//')
            for node in $(bspc query -N -d "$d"); do
                bspc node "$node" -d "$target_d" 2>/dev/null || true
            done
        fi
    done

    # Remove secondary monitor from bspwm management if present
    if [ -n "$sec" ] && bspc query -M --names | grep -q "^$sec$"; then
        bspc monitor "$sec" -r 2>/dev/null || true
    fi

    # Assign all 10 desktops (1..10) to primary
    bspc monitor "$pri" -d 1 2 3 4 5 6 7 8 9 10
fi

# Cleanup non-standard desktops
for d in $(bspc query -D --names); do
    case "$d" in
        1|2|3|4|5|6|7|8|9|10|1_ext|2_ext|3_ext|4_ext|5_ext|6_ext|7_ext|8_ext|9_ext|10_ext) ;;
        *) bspc desktop "$d" -r 2>/dev/null ;;
    esac
done

# Restore wallpaper across all active displays
if [ -f ~/.fehbg ]; then
    ~/.fehbg &
fi
