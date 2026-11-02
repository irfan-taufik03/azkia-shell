#!/bin/bash
# Detect which monitor the mouse cursor is currently on
# Output: monitor name (e.g. eDP-1, HDMI-1)

X=$(xdotool getmouselocation 2>/dev/null | grep -oP 'x:\K[0-9]+')
Y=$(xdotool getmouselocation 2>/dev/null | grep -oP 'y:\K[0-9]+')

if [ -z "$X" ] || [ -z "$Y" ]; then
    bspc query -M -m focused --names 2>/dev/null
    exit 0
fi

found=""
while IFS=' ' read -r name w h x y; do
    [ -z "$name" ] && continue
    if [ "$X" -ge "$x" ] && [ "$X" -lt "$((x+w))" ] && \
       [ "$Y" -ge "$y" ] && [ "$Y" -lt "$((y+h))" ]; then
        found="$name"
        break
    fi
done < <(xrandr --query | awk '/connected/ && / [0-9]+x[0-9]+\+[0-9]+\+[0-9]+/{
    for(i=1;i<=NF;i++) if($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {
        split($i,a,"[x+]"); print $1,a[1],a[2],a[3],a[4]
    }
}')

if [ -z "$found" ]; then
    found=$(bspc query -M -m focused --names 2>/dev/null)
fi

echo "$found"
