#!/usr/bin/env python3
import os
import sys
import glob
import json
import configparser
import subprocess

def get_current_icon_theme():
    try:
        res = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
            capture_output=True, text=True, timeout=1
        )
        theme = res.stdout.strip().strip("'\"")
        if theme:
            return theme
    except Exception:
        pass

    gtk3_ini = os.path.expanduser("~/.config/gtk-3.0/settings.ini")
    if os.path.exists(gtk3_ini):
        try:
            with open(gtk3_ini, "r") as f:
                for line in f:
                    if "gtk-icon-theme-name" in line:
                        return line.split("=")[1].strip()
        except Exception:
            pass
    return "hicolor"

ICON_CACHE = {}

def find_icon(icon_name, current_theme):
    if not icon_name:
        return ""
    if os.path.isabs(icon_name) and os.path.exists(icon_name):
        return icon_name

    cache_key = f"{current_theme}:{icon_name}"
    if cache_key in ICON_CACHE:
        return ICON_CACHE[cache_key]

    search_dirs = [
        f"/usr/share/icons/{current_theme}",
        f"/usr/share/icons/{current_theme.capitalize()}",
        f"/usr/share/icons/{current_theme.lower()}",
        os.path.expanduser(f"~/.icons/{current_theme}"),
        os.path.expanduser(f"~/.local/share/icons/{current_theme}"),
        "/usr/share/icons/hicolor",
        "/usr/share/pixmaps"
    ]

    extensions = [".png", ".svg", ".xpm"]

    for d in search_dirs:
        if not os.path.exists(d):
            continue
        for root, dirs, files in os.walk(d):
            for ext in extensions:
                target = icon_name + ext
                if target in files:
                    full_path = os.path.join(root, target)
                    ICON_CACHE[cache_key] = full_path
                    return full_path

    for d in search_dirs:
        if not os.path.exists(d):
            continue
        for root, dirs, files in os.walk(d):
            if icon_name in files:
                full_path = os.path.join(root, icon_name)
                ICON_CACHE[cache_key] = full_path
                return full_path

    ICON_CACHE[cache_key] = ""
    return ""

def scan_apps():
    theme = get_current_icon_theme()
    dirs = [
        "/usr/share/applications",
        os.path.expanduser("~/.local/share/applications"),
        "/var/lib/flatpak/exports/share/applications"
    ]

    apps_map = {}

    for d in dirs:
        if not os.path.exists(d):
            continue
        for f in glob.glob(os.path.join(d, "*.desktop")):
            cfg = configparser.ConfigParser(interpolation=None)
            try:
                cfg.read(f, encoding="utf-8")
                if "Desktop Entry" in cfg:
                    sec = cfg["Desktop Entry"]
                    if sec.getboolean("NoDisplay", False):
                        continue
                    name = sec.get("Name", "")
                    exec_cmd = sec.get("Exec", "")
                    icon_name = sec.get("Icon", "")
                    comment = sec.get("Comment", "")

                    if name and exec_cmd:
                        clean_exec = " ".join([w for w in exec_cmd.split() if not w.startswith("%")])
                        icon_path = find_icon(icon_name, theme)

                        app_id = os.path.basename(f)
                        apps_map[name.lower()] = {
                            "id": app_id,
                            "name": name,
                            "exec": clean_exec,
                            "icon": icon_name,
                            "icon_path": icon_path,
                            "comment": comment
                        }
            except Exception:
                pass

    sorted_apps = sorted(list(apps_map.values()), key=lambda x: x["name"].lower())
    return sorted_apps

def launch_app(exec_cmd):
    if exec_cmd:
        subprocess.Popen(exec_cmd, shell=True, start_new_session=True)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "--get-json":
            print(json.dumps(scan_apps(), ensure_ascii=False))
        elif cmd == "--launch" and len(sys.argv) > 2:
            launch_app(sys.argv[2])
    else:
        print(json.dumps(scan_apps(), ensure_ascii=False))
