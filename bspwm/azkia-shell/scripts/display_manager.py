#!/usr/bin/env python3
import sys
import subprocess
import json
import re

def get_display_info():
    try:
        proc = subprocess.run(['xrandr', '--query'], capture_output=True, text=True)
        if proc.returncode != 0:
            return {"error": "xrandr failed to query displays"}

        lines = proc.stdout.splitlines()
        monitors = []
        primary = ""
        current_mon = None
        modes_map = {}
        rotation_map = {}
        active_mode_map = {}

        for line in lines:
            # Match line: "eDP-1 connected primary 1920x1080+0+0 normal ..."
            # or "HDMI-1 connected 1920x1080+1920+0 left ..."
            m = re.match(r'^([A-Za-z0-9\-\_]+)\s+connected\s+(primary\s+)?(?:\d+x\d+\+\d+\+\d+\s+)?(normal|left|right|inverted)?', line)
            if m:
                mon_name = m.group(1)
                is_pri = bool(m.group(2))
                rot = m.group(3) or "normal"
                monitors.append(mon_name)
                current_mon = mon_name
                modes_map[mon_name] = []
                rotation_map[mon_name] = rot
                if is_pri or not primary:
                    primary = mon_name
                continue

            if current_mon:
                # Mode line: "   1920x1080     60.00*+  59.97  "
                mode_m = re.match(r'^\s+(\d+x\d+)\s+(.*)', line)
                if mode_m:
                    mode_str = mode_m.group(1)
                    flags = mode_m.group(2)
                    if mode_str not in modes_map[current_mon]:
                        modes_map[current_mon].append(mode_str)
                    if '*' in flags:
                        active_mode_map[current_mon] = mode_str

        active_mon = primary or (monitors[0] if monitors else "eDP-1")
        supported_modes = modes_map.get(active_mon, [])
        active_mode = active_mode_map.get(active_mon, supported_modes[0] if supported_modes else "1920x1080")

        return {
            "monitors": monitors,
            "primary": active_mon,
            "rotation": rotation_map.get(active_mon, "normal"),
            "supported_modes": supported_modes,
            "current_mode": active_mode,
            "current_scale": "100%"
        }
    except Exception as e:
        return {"error": str(e)}

def set_resolution(output, mode):
    try:
        proc = subprocess.run(['xrandr', '--output', output, '--mode', mode], capture_output=True, text=True)
        return {"success": proc.returncode == 0, "output": proc.stdout or proc.stderr}
    except Exception as e:
        return {"error": str(e)}

def set_rotation(output, rotation):
    try:
        proc = subprocess.run(['xrandr', '--output', output, '--rotate', rotation], capture_output=True, text=True)
        return {"success": proc.returncode == 0, "output": proc.stdout or proc.stderr}
    except Exception as e:
        return {"error": str(e)}

def set_scale(output, scale_str):
    # Scale values: 100%, 115%, 125%, 150%
    scale_map = {
        "100%": "1x1",
        "115%": "0.87x0.87",
        "125%": "0.8x0.8",
        "150%": "0.67x0.67"
    }
    scale_val = scale_map.get(scale_str, "1x1")
    try:
        proc = subprocess.run(['xrandr', '--output', output, '--scale', scale_val], capture_output=True, text=True)
        return {"success": proc.returncode == 0, "output": proc.stdout or proc.stderr}
    except Exception as e:
        return {"error": str(e)}

def main():
    if len(sys.argv) < 2:
        print(json.dumps(get_display_info()))
        return

    arg = sys.argv[1]
    if arg == "--get":
        print(json.dumps(get_display_info()))
    elif arg == "--set-resolution" and len(sys.argv) >= 4:
        print(json.dumps(set_resolution(sys.argv[2], sys.argv[3])))
    elif arg == "--set-rotation" and len(sys.argv) >= 4:
        print(json.dumps(set_rotation(sys.argv[2], sys.argv[3])))
    elif arg == "--set-scale" and len(sys.argv) >= 4:
        print(json.dumps(set_scale(sys.argv[2], sys.argv[3])))
    else:
        print(json.dumps({"error": "Invalid arguments"}))

if __name__ == "__main__":
    main()
