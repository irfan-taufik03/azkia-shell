#!/usr/bin/env python3
import os
import sys
import json
import subprocess

VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
DEFAULT_DIR = os.path.expanduser("~/.config/bspwm/wallpapers")

def get_wallpapers(target_dir=None):
    d = os.path.expanduser(target_dir) if target_dir and os.path.isdir(os.path.expanduser(target_dir)) else DEFAULT_DIR
    result, seen = [], set()
    if os.path.isdir(d):
        for root, _, files in os.walk(d):
            for f in sorted(files):
                if os.path.splitext(f)[1].lower() in VALID_EXTS:
                    p = os.path.join(root, f)
                    if p not in seen:
                        seen.add(p)
                        result.append({"name": f, "path": p})
    print(json.dumps(result))

def set_wallpaper(path):
    if not path or not os.path.exists(path):
        return
    try:
        subprocess.run(["feh", "--bg-fill", path], check=True)
    except Exception:
        pass

    fehbg = os.path.expanduser("~/.fehbg")
    try:
        with open(fehbg, "w") as f:
            f.write(f"#!/bin/sh\nfeh --bg-fill '{path}'\n")
        os.chmod(fehbg, 0o755)
    except Exception:
        pass

    bspwmrc = os.path.expanduser("~/.config/bspwm/bspwmrc")
    try:
        if os.path.exists(bspwmrc):
            with open(bspwmrc, "r+") as f:
                if "~/.fehbg" not in f.read():
                    f.write("\n# Restore wallpaper on boot\n[ -f ~/.fehbg ] && ~/.fehbg &\n")
    except Exception:
        pass

if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) >= 2 and args[0] == "--set":
        set_wallpaper(args[1])
    elif len(args) >= 2 and args[0] == "--dir":
        get_wallpapers(args[1])
    else:
        get_wallpapers()
