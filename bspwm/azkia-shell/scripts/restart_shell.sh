#!/bin/bash
export QML_DISABLE_DISTANCEFIELD=1
nohup bash -c "export QML_DISABLE_DISTANCEFIELD=1; pkill -9 -x qs 2>/dev/null; sleep 0.5; QML_DISABLE_DISTANCEFIELD=1 qs -p '$HOME/.config/bspwm/azkia-shell' -d -n >/dev/null 2>&1" >/dev/null 2>&1 &

