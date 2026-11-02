#!/usr/bin/env python3
import subprocess
import re
import sys

def main():
    try:
        # Prompt user to click a target window
        p = subprocess.run(["xdotool", "selectwindow"], capture_output=True, text=True)
        wid_out = p.stdout.strip()
        if not wid_out or p.returncode != 0:
            sys.exit(0)
            
        # Get window geometry using xdotool
        geom_out = subprocess.check_output(["xdotool", "getwindowgeometry", "--shell", wid_out], text=True)
        props = {}
        for line in geom_out.strip().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                props[k.strip()] = v.strip()
        
        x = props.get("X")
        y = props.get("Y")
        w = props.get("WIDTH")
        h = props.get("HEIGHT")
        
        if x is not None and y is not None and w is not None and h is not None:
            region = f"{w}x{h}+{x}+{y}"
            subprocess.Popen(["flameshot", "gui", "--region", region])
    except Exception as e:
        # Fallback to xwininfo if available
        try:
            info = subprocess.check_output(["xwininfo", "-id", wid_out], text=True)
            x = re.search(r"Absolute upper-left X:\s+(-?\d+)", info)
            y = re.search(r"Absolute upper-left Y:\s+(-?\d+)", info)
            w = re.search(r"Width:\s+(\d+)", info)
            h = re.search(r"Height:\s+(\d+)", info)
            if x and y and w and h:
                region = f"{w.group(1)}x{h.group(1)}+{x.group(1)}+{y.group(1)}"
                subprocess.Popen(["flameshot", "gui", "--region", region])
        except Exception as err:
            print(f"Error selecting window: {e} / {err}", file=sys.stderr)

if __name__ == "__main__":
    main()

