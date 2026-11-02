#!/bin/bash
# Independent tag switcher script: switches desktop on targeted/mouse monitor ONLY

TAG="$1"
ACTION="${2:-focus}"
SCREEN_TARGET="$3"

if [ -z "$TAG" ]; then
    exit 0
fi

pri_mon=$(xrandr --query | awk '/ primary/{print $1}')
if [ -z "$pri_mon" ]; then
    pri_mon=$(xrandr --query | awk '/ connected/{print $1}' | head -n1)
fi

target_mon="$SCREEN_TARGET"

# If no target screen explicitly passed, locate screen via mouse position (xdotool)
if [ -z "$target_mon" ]; then
    eval $(xdotool getmouselocation --shell 2>/dev/null)
    if [ -n "$X" ] && [ -n "$Y" ]; then
        while read -r name w h x y; do
            if [ "$X" -ge "$x" ] && [ "$X" -lt "$((x + w))" ] && [ "$Y" -ge "$y" ] && [ "$Y" -lt "$((y + h))" ]; then
                target_mon="$name"
                break
            fi
        done < <(xrandr --query | awk '/ connected/{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {split($i,a,"[x+]"); print $1, a[1], a[2], a[3], a[4]}}')
    fi
fi

# Fallback to focused monitor in bspwm
if [ -z "$target_mon" ]; then
    target_mon=$(bspc query -M -m focused --names 2>/dev/null)
fi

# Determine desktop name: primary monitor uses 1..10, secondary monitor uses 1_ext..10_ext
if [ "$target_mon" = "$pri_mon" ] || [ -z "$target_mon" ]; then
    dest_desktop="$TAG"
else
    if bspc query -D -d "${TAG}_ext" >/dev/null 2>&1; then
        dest_desktop="${TAG}_ext"
    else
        dest_desktop="$TAG"
    fi
fi

if [ "$ACTION" = "send" ]; then
    bspc node -d "$dest_desktop" --follow
else
    # 1. Explicitly focus the target monitor first so bspwm updates window mapping and focus
    if [ -n "$target_mon" ]; then
        bspc monitor "$target_mon" -f 2>/dev/null
    fi
    # 2. Focus the destination desktop on that monitor
    bspc desktop "$dest_desktop" -f 2>/dev/null
fi
