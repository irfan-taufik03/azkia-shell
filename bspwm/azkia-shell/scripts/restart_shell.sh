#!/bin/bash
export DISPLAY="${DISPLAY:-:0}"
export QML_DISABLE_DISTANCEFIELD=1
killall -9 quickshell qs 2>/dev/null
pkill -9 -f quickshell 2>/dev/null
pkill -9 -f "qs -p" 2>/dev/null
pkill -9 -f "azkia-shell/scripts/(idle_daemon|azkia_audio_player|clip_daemon|cava_daemon|polkit_agent|prayer_service)\.py" 2>/dev/null
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
sleep 0.6
DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" qs -p "$HOME/.config/bspwm/azkia-shell" -d

