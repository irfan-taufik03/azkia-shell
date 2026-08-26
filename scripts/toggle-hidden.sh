#!/bin/bash

STATE="$XDG_RUNTIME_DIR/bspwm-hidden-node"

if [ -f "$STATE" ]; then
    node=$(cat "$STATE")

    if bspc query -N -n "$node" >/dev/null 2>&1; then
        bspc node "$node" -g hidden=off
        bspc node "$node" -f
        rm -f "$STATE"
        exit 0
    fi
fi

node=$(bspc query -N -n focused)

if [ -n "$node" ]; then
    echo "$node" > "$STATE"
    bspc node "$node" -g hidden=on
fi
