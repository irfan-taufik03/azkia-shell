#!/usr/bin/env bash

# Environment fallback
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && [ -e "$XDG_RUNTIME_DIR/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

# Current hour (format 2 digits, e.g., 09:00, 10:00, 14:00)
CURRENT_TIME=$(date +"%H:00")

# Reminder message
TITLE="It's ${CURRENT_TIME} - Time to Move!"
MESSAGE="You've been active for an hour.\nStand up, stretch your body, rest your eyes, and stay hydrated!"

# Play subtle notification sound if available
if command -v canberra-gtk-play >/dev/null 2>&1; then
    canberra-gtk-play -i message 2>/dev/null &
fi

# Send desktop notification
notify-send \
    -a "Movement Reminder" \
    -t 10000 \
    -i "file://$HOME/.config/bspwm/assets/exercise.png" \
    -u normal \
    "$TITLE" \
    "$MESSAGE"
