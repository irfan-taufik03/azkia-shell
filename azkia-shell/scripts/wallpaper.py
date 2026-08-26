#!/usr/bin/env python3
import os
import sys
import json
import subprocess

WALLPAPER_DIRS = [
    os.path.expanduser("~/.config/bspwm/wallpapers")
]
VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp"}

def get_wallpapers(target_dir=None):
    result = []
    seen = set()

    dirs_to_check = []
    if target_dir:
        expanded = os.path.expanduser(target_dir)
        if os.path.exists(expanded):
            dirs_to_check.append(expanded)
    
    if not dirs_to_check:
        dirs_to_check = WALLPAPER_DIRS

    for d in dirs_to_check:
        if not os.path.exists(d):
            continue
        try:
            for root, _, files in os.walk(d):
                for f in sorted(files):
                    ext = os.path.splitext(f)[1].lower()
                    if ext in VALID_EXTS:
                        full_path = os.path.join(root, f)
                        if full_path not in seen:
                            seen.add(full_path)
                            result.append({
                                "name": f,
                                "path": full_path
                            })
        except Exception:
            pass

    print(json.dumps(result))

def set_wallpaper(path):
    if not path or not os.path.exists(path):
        return

    # Set wallpaper immediately via feh
    try:
        subprocess.run(["feh", "--bg-fill", path], check=True)
    except Exception:
        pass

    # Save to ~/.fehbg for persistence across reboots
    fehbg_path = os.path.expanduser("~/.fehbg")
    content = f"#!/bin/sh\nfeh --bg-fill '{path}'\n"
    try:
        with open(fehbg_path, "w") as f:
            f.write(content)
        os.chmod(fehbg_path, 0o755)
    except Exception:
        pass

    # Ensure bspwmrc restores fehbg on boot
    bspwmrc_path = os.path.expanduser("~/.config/bspwm/bspwmrc")
    if os.path.exists(bspwmrc_path):
        try:
            with open(bspwmrc_path, "r") as f:
                bsp_content = f.read()
            if "~/.fehbg" not in bsp_content:
                with open(bspwmrc_path, "a") as f:
                    f.write("\n# Restore wallpaper on boot\n[ -f ~/.fehbg ] && ~/.fehbg &\n")
        except Exception:
            pass

    # Desktop notification
    filename = os.path.basename(path)
    try:
        subprocess.run(["notify-send", "-i", "preferences-desktop-wallpaper", "Wallpaper Changed", f"Applied: {filename}"])
    except Exception:
        pass

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--set" and len(sys.argv) > 2:
        set_wallpaper(sys.argv[2])
    elif len(sys.argv) > 1 and sys.argv[1] == "--dir" and len(sys.argv) > 2:
        get_wallpapers(sys.argv[2])
    else:
        get_wallpapers()
