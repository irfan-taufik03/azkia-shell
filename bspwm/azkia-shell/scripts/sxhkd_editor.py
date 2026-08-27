#!/usr/bin/env python3
import sys
import os
import re
import json
import subprocess

SXHKD_PATH = os.path.expanduser("~/.config/bspwm/sxhkdrc")
SXHKD_DEFAULT_PATH = os.path.expanduser("~/.config/bspwm/sxhkdrc.default")

def reload_sxhkd():
    subprocess.run(["pkill", "-USR1", "-x", "sxhkd"], stderr=subprocess.DEVNULL)

def get_default_desc(hotkey, cmd):
    c = cmd.strip()
    h = hotkey.strip()

    exact_map = {
        "bspc node -c": "Close Active Window",
        "bspc query -N -n .window | xargs -r bspc node -k": "Kill Active Window",
        "bspc node -R 90": "Rotate Window Clockwise",
        "bspc node -R -90": "Rotate Window Counter-Clockwise",
        "bspc config window_gap 50": "Increase Window Gap",
        "bspc config window_gap 8": "Reset Window Gap",
        "bspc node -f last": "Focus Last Window",
        "bspc desktop -f next.local": "Focus Next Workspace",
        "bspc desktop -f prev.local": "Focus Previous Workspace",
        "bspc wm -r notify-send 'bspwm' 'Restarted'": "Restart BSPWM",
        "pkill -USR1 -x sxhkd notify-send 'sxhkd' 'Reloaded config'": "Reload SXHKD Config",
        "flameshot gui": "Screenshot (Select Area)",
        "flameshot screen": "Screenshot (Fullscreen)",
        "kitty": "Open Terminal (Kitty)",
        "thunar": "Open File Manager (Thunar)",
        "floorp": "Open Web Browser (Floorp)",
        "zen": "Open Zen Browser",
        "blueman-manager": "Open Bluetooth Manager",
        "thorium-browser": "Open Thorium Browser",
        "vivaldi": "Open Vivaldi Browser",
        "qgis": "Open QGIS",
        "kdenlive": "Open Kdenlive Video Editor",
        "obs": "Open OBS Studio",
        "inkscape": "Open Inkscape Vector Editor",
        "geany": "Open Geany Editor",
        "kitty -e btop": "Open System Monitor (Btop)",
        "mate-calc": "Open Calculator",
        "kitty -e nvim": "Open Neovim Editor",
        "xfce4-display-settings --minimal": "Display Settings",
        "bspcolorpicker": "Color Picker",
        "telegram-desktop": "Open Telegram Desktop",
        "xarchiver": "Open Archive Manager",
        "/usr/share/antigravity/antigravity": "Open Antigravity IDE",
    }
    if c in exact_map:
        return exact_map[c]

    if "ipc call launcher toggle" in c: return "App Launcher"
    if "ipc call power toggle" in c: return "Power Menu"
    if "ipc call media toggle" in c: return "Media Controls"
    if "ipc call lockscreen lock" in c: return "Lock Screen"
    if "ipc call volume raise" in c: return "Volume Up"
    if "ipc call volume lower" in c: return "Volume Down"
    if "ipc call volume mute" in c: return "Mute Volume"
    if "ipc call brightness raise" in c: return "Brightness Up"
    if "ipc call brightness lower" in c: return "Brightness Down"

    if "window-switcher.sh" in c: return "Window Switcher"
    if "picom-refresh.sh" in c: return "Refresh Picom Compositor"
    if "toggle-hidden.sh" in c: return "Toggle Hidden Window"
    if "xrandr" in c and "same-as" in c: return "Mirror Display"
    if "xrandr" in c and "right-of" in c: return "Extend Display"
    if "xrandr" in c and "--off" in c: return "Turn Off Display"
    if "deadbeef" in c: return "DeaDBeeF Music Player"
    if "ABDownloadManager" in c: return "AB Download Manager"
    if "com.rtosta.zapzap" in c: return "WhatsApp (ZapZap)"

    if "fullscreen" in c: return "Toggle Fullscreen Mode"
    if "floating" in c: return "Toggle Floating Mode"
    if "west,south,north,east" in c and "-f" in c: return "Focus Window (Direction)"
    if "west,south,north,east" in c and "-s" in c: return "Swap Window (Direction)"
    if "focused:^{1-9,10}" in c: return "Switch / Move to Workspace"

    first_word = c.split()[0] if c else "Command"
    return f"Run {first_word}"

def parse_sxhkdrc():
    if not os.path.exists(SXHKD_PATH):
        return []

    with open(SXHKD_PATH, "r") as f:
        lines = f.readlines()

    bindings = []
    i = 0
    last_comment = ""
    while i < len(lines):
        raw = lines[i].rstrip("\n")
        stripped = raw.strip()
        if stripped.startswith("#"):
            comment_text = stripped.lstrip("#").strip()
            if comment_text and comment_text.lower() != "custom keybinding":
                last_comment = comment_text
            i += 1
            continue

        if stripped and not lines[i].startswith("\t") and not lines[i].startswith("  "):
            hotkey = stripped
            cmd_line = ""
            if i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                if next_line and not next_line.startswith("#"):
                    cmd_line = next_line
                    i += 1
            if cmd_line:
                desc = last_comment if last_comment else get_default_desc(hotkey, cmd_line)
                bindings.append({
                    "id": len(bindings),
                    "hotkey": hotkey,
                    "cmd": cmd_line,
                    "desc": desc
                })
                last_comment = ""
        else:
            if not stripped:
                last_comment = ""
        i += 1
    return bindings

def add_binding(hotkey, cmd, desc=""):
    if not hotkey or not cmd:
        return
    comment_header = desc if desc else get_default_desc(hotkey, cmd)
    with open(SXHKD_PATH, "a") as f:
        f.write(f"\n\n# {comment_header}\n{hotkey}\n\t{cmd}\n")
    reload_sxhkd()

def edit_binding(old_hotkey, new_hotkey, new_cmd, desc=""):
    if not old_hotkey or not new_hotkey or not new_cmd:
        return
    if not os.path.exists(SXHKD_PATH):
        return
    with open(SXHKD_PATH, "r") as f:
        lines = f.readlines()

    comment_header = desc if desc else get_default_desc(new_hotkey, new_cmd)
    new_lines = []
    i = 0
    updated = False
    while i < len(lines):
        line = lines[i].strip()
        if not updated and line == old_hotkey:
            if new_lines and new_lines[-1].strip().startswith("#"):
                new_lines[-1] = f"# {comment_header}\n"
            else:
                new_lines.append(f"# {comment_header}\n")

            new_lines.append(f"{new_hotkey}\n")
            i += 1
            if i < len(lines) and (lines[i].startswith("\t") or lines[i].startswith("  ")):
                new_lines.append(f"\t{new_cmd}\n")
                i += 1
            else:
                new_lines.append(f"\t{new_cmd}\n")
            updated = True
            continue
        new_lines.append(lines[i])
        i += 1

    with open(SXHKD_PATH, "w") as f:
        f.writelines(new_lines)
    reload_sxhkd()

def delete_binding(hotkey):
    if not os.path.exists(SXHKD_PATH):
        return
    with open(SXHKD_PATH, "r") as f:
        lines = f.readlines()

    new_lines = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line == hotkey:
            if new_lines and new_lines[-1].strip().startswith("#"):
                new_lines.pop()
            i += 1
            if i < len(lines) and (lines[i].startswith("\t") or lines[i].startswith("  ")):
                i += 1
            continue
        new_lines.append(lines[i])
        i += 1

    with open(SXHKD_PATH, "w") as f:
        f.writelines(new_lines)
    reload_sxhkd()

def reset_sxhkdrc():
    if os.path.exists(SXHKD_DEFAULT_PATH):
        with open(SXHKD_DEFAULT_PATH, "r") as f:
            content = f.read()
        with open(SXHKD_PATH, "w") as f:
            f.write(content)
        reload_sxhkd()

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "--get":
        print(json.dumps(parse_sxhkdrc()))
    elif sys.argv[1] == "--add":
        hotkey = ""
        cmd = ""
        desc = ""
        for i in range(2, len(sys.argv)):
            if sys.argv[i] == "--hotkey" and i + 1 < len(sys.argv):
                hotkey = sys.argv[i + 1]
            elif sys.argv[i] == "--cmd" and i + 1 < len(sys.argv):
                cmd = sys.argv[i + 1]
            elif sys.argv[i] == "--desc" and i + 1 < len(sys.argv):
                desc = sys.argv[i + 1]
        add_binding(hotkey, cmd, desc)
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--edit":
        old_hotkey = ""
        new_hotkey = ""
        cmd = ""
        desc = ""
        for i in range(2, len(sys.argv)):
            if sys.argv[i] == "--old-hotkey" and i + 1 < len(sys.argv):
                old_hotkey = sys.argv[i + 1]
            elif sys.argv[i] == "--hotkey" and i + 1 < len(sys.argv):
                new_hotkey = sys.argv[i + 1]
            elif sys.argv[i] == "--cmd" and i + 1 < len(sys.argv):
                cmd = sys.argv[i + 1]
            elif sys.argv[i] == "--desc" and i + 1 < len(sys.argv):
                desc = sys.argv[i + 1]
        edit_binding(old_hotkey, new_hotkey, cmd, desc)
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--delete":
        hotkey = ""
        for i in range(2, len(sys.argv)):
            if sys.argv[i] == "--hotkey" and i + 1 < len(sys.argv):
                hotkey = sys.argv[i + 1]
        delete_binding(hotkey)
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--reset":
        reset_sxhkdrc()
        print(json.dumps({"status": "ok"}))

if __name__ == "__main__":
    main()
