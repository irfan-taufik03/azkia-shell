#!/usr/bin/env python3
import sys
import subprocess
import json
import re
import os

XRESOURCES_PATH = os.path.expanduser("~/.Xresources")

def get_current_dpi():
    try:
        proc = subprocess.run(['xrdb', '-query'], capture_output=True, text=True)
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                if 'Xft.dpi' in line:
                    parts = line.split(':')
                    if len(parts) >= 2:
                        return int(parts[1].strip())
    except Exception:
        pass
    return 96

def dpi_to_scale_str(dpi):
    if dpi >= 140:
        return "150%"
    elif dpi >= 118:
        return "125%"
    elif dpi >= 105:
        return "115%"
    else:
        return "100%"

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

        current_dpi = get_current_dpi()
        current_scale = dpi_to_scale_str(current_dpi)

        return {
            "monitors": monitors,
            "primary": active_mon,
            "rotation": rotation_map.get(active_mon, "normal"),
            "supported_modes": supported_modes,
            "current_mode": active_mode,
            "current_scale": current_scale,
            "current_dpi": current_dpi
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

def update_xresources_dpi(dpi):
    try:
        lines = []
        if os.path.exists(XRESOURCES_PATH):
            with open(XRESOURCES_PATH, 'r') as f:
                lines = f.readlines()
        
        new_lines = [l for l in lines if not l.strip().startswith('Xft.dpi:')]
        new_lines.append(f"Xft.dpi: {dpi}\n")

        with open(XRESOURCES_PATH, 'w') as f:
            f.writelines(new_lines)
    except Exception as e:
        pass

def set_scale(output, scale_str):
    dpi_map = {
        "100%": 96,
        "115%": 110,
        "125%": 120,
        "150%": 144
    }
    dpi = dpi_map.get(scale_str, 96)

    try:
        # 1. Reset xrandr canvas scaling to 1x1 with bilinear filter to prevent raster blur
        subprocess.run(['xrandr', '--output', output, '--scale', '1x1', '--filter', 'bilinear'], capture_output=True, text=True)
        
        # 2. Merge Xft.dpi into active X server resource manager (Vector DPI Scaling - Crisp & Sharp!)
        proc = subprocess.run(['xrdb', '-merge'], input=f"Xft.dpi: {dpi}\n", text=True, capture_output=True)

        # 3. Save to ~/.Xresources for persistence
        update_xresources_dpi(dpi)

        return {"success": True, "scale": scale_str, "dpi": dpi}
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
        print(json.argv if len(sys.argv) < 4 else json.dumps(set_rotation(sys.argv[2], sys.argv[3])))
    elif arg == "--set-scale" and len(sys.argv) >= 4:
        print(json.dumps(set_scale(sys.argv[2], sys.argv[3])))
    else:
        print(json.dumps({"error": "Invalid arguments"}))

if __name__ == "__main__":
    main()
