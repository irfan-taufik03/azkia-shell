#!/usr/bin/env python3
import sys
import os
import json
import subprocess
import re

BSPWMRC_PATH = os.path.expanduser("~/.config/bspwm/bspwmrc")
BSPWMRC_DEFAULT_PATH = os.path.expanduser("~/.config/bspwm/bspwmrc.default")
PICOM_CONF_PATH = os.path.expanduser("~/.config/bspwm/picom.conf")

def get_bspwm_info():
    gap = 8
    border = 2
    corner_radius = 12

    try:
        res_gap = subprocess.run(["bspc", "config", "window_gap"], capture_output=True, text=True)
        if res_gap.returncode == 0 and res_gap.stdout.strip():
            gap = int(res_gap.stdout.strip())
    except Exception:
        pass

    try:
        res_border = subprocess.run(["bspc", "config", "border_width"], capture_output=True, text=True)
        if res_border.returncode == 0 and res_border.stdout.strip():
            border = int(res_border.stdout.strip())
    except Exception:
        pass

    if os.path.exists(PICOM_CONF_PATH):
        try:
            with open(PICOM_CONF_PATH, "r") as f:
                c = f.read()
            m = re.search(r'corner-radius\s*=\s*(\d+)', c)
            if m:
                corner_radius = int(m.group(1))
        except Exception:
            pass

    rules = []
    if os.path.exists(BSPWMRC_PATH):
        with open(BSPWMRC_PATH, "r") as f:
            lines = f.readlines()
        for idx, line in enumerate(lines):
            l = line.strip()
            if l.startswith("bspc rule -a"):
                content = l[len("bspc rule -a"):].strip()
                m = re.match(r'''^(?:'([^']+)'|"([^"]+)"|(\S+))\s*(.*)$''', content)
                if m:
                    app_class = m.group(1) or m.group(2) or m.group(3)
                    opts = m.group(4).strip()
                    rules.append({
                        "id": len(rules),
                        "class": app_class,
                        "opts": opts,
                        "fullLine": l
                    })

    return {
        "gap": gap,
        "border": border,
        "corner_radius": corner_radius,
        "rules": rules
    }

def set_gap(val):
    try:
        val_int = int(val)
        subprocess.run(["bspc", "config", "window_gap", str(val_int)])
        if os.path.exists(BSPWMRC_PATH):
            with open(BSPWMRC_PATH, "r") as f:
                content = f.read()
            new_content = re.sub(r'bspc\s+config\s+window_gap\s+\d+', f'bspc config window_gap {val_int}', content)
            with open(BSPWMRC_PATH, "w") as f:
                f.write(new_content)
    except Exception as e:
        print(f"Error setting gap: {e}", file=sys.stderr)

def set_border(val):
    try:
        val_int = int(val)
        subprocess.run(["bspc", "config", "border_width", str(val_int)])
        if os.path.exists(BSPWMRC_PATH):
            with open(BSPWMRC_PATH, "r") as f:
                content = f.read()
            new_content = re.sub(r'bspc\s+config\s+border_width\s+\d+', f'bspc config border_width {val_int}', content)
            with open(BSPWMRC_PATH, "w") as f:
                f.write(new_content)
    except Exception as e:
        print(f"Error setting border: {e}", file=sys.stderr)

def set_corner_radius(val):
    try:
        val_int = int(val)
        if os.path.exists(PICOM_CONF_PATH):
            with open(PICOM_CONF_PATH, "r") as f:
                content = f.read()
            new_content = re.sub(r'corner-radius\s*=\s*\d+;?', f'corner-radius = {val_int};', content)
            with open(PICOM_CONF_PATH, "w") as f:
                f.write(new_content)
            # Reload picom
            subprocess.run(["pkill", "-9", "picom"])
            subprocess.Popen(["picom", "--config", PICOM_CONF_PATH, "-b"])
            # Restart bspwm (quickshell will remain active)
            subprocess.run(["bspc", "wm", "-r"])
    except Exception as e:
        print(f"Error setting corner radius: {e}", file=sys.stderr)

def set_border_color(color_hex):
    try:
        if not color_hex.startswith("#"):
            color_hex = "#" + color_hex
        subprocess.run(["bspc", "config", "focused_border_color", color_hex])
        subprocess.run(["bspc", "config", "active_border_color", color_hex])
        if os.path.exists(BSPWMRC_PATH):
            with open(BSPWMRC_PATH, "r") as f:
                content = f.read()
            new_content = re.sub(r'bspc\s+config\s+focused_border_color\s+["\']?#[0-9a-fA-F]{3,8}["\']?', f'bspc config focused_border_color "{color_hex}"', content)
            new_content = re.sub(r'bspc\s+config\s+active_border_color\s+["\']?#[0-9a-fA-F]{3,8}["\']?', f'bspc config active_border_color "{color_hex}"', content)
            with open(BSPWMRC_PATH, "w") as f:
                f.write(new_content)
    except Exception as e:
        print(f"Error setting border color: {e}", file=sys.stderr)

def add_rule(app_class, opts=""):
    if not app_class:
        return
    full_cmd = f"bspc rule -a {app_class} {opts}".strip()
    subprocess.run(full_cmd, shell=True)

    if os.path.exists(BSPWMRC_PATH):
        with open(BSPWMRC_PATH, "a") as f:
            f.write("\n" + full_cmd)

def edit_rule(old_class, new_class, new_opts):
    if not old_class or not new_class:
        return
    if not os.path.exists(BSPWMRC_PATH):
        return
    with open(BSPWMRC_PATH, "r") as f:
        lines = f.readlines()

    new_lines = []
    updated = False
    for line in lines:
        l = line.strip()
        if not updated and l.startswith("bspc rule -a") and old_class in l:
            new_lines.append(f"bspc rule -a {new_class} {new_opts}\n".strip() + "\n")
            updated = True
        else:
            new_lines.append(line)

    with open(BSPWMRC_PATH, "w") as f:
        f.writelines(new_lines)
    subprocess.run(f"bspc rule -a {new_class} {new_opts}".strip(), shell=True)

def delete_rule(app_class):
    if not os.path.exists(BSPWMRC_PATH):
        return
    with open(BSPWMRC_PATH, "r") as f:
        lines = f.readlines()

    new_lines = [l for l in lines if not (l.strip().startswith("bspc rule -a") and app_class in l)]
    with open(BSPWMRC_PATH, "w") as f:
        f.writelines(new_lines)
    subprocess.run(["bspc", "rule", "-r", app_class])

def reset_rules():
    if os.path.exists(BSPWMRC_DEFAULT_PATH):
        with open(BSPWMRC_DEFAULT_PATH, "r") as f:
            content = f.read()
        with open(BSPWMRC_PATH, "w") as f:
            f.write(content)
        subprocess.run(["bspc", "rule", "-r", "*:*"])
        subprocess.run(["bash", BSPWMRC_PATH])

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "--get":
        print(json.dumps(get_bspwm_info()))
    elif sys.argv[1] == "--set-gap":
        if len(sys.argv) > 2:
            set_gap(sys.argv[2])
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--set-border":
        if len(sys.argv) > 2:
            set_border(sys.argv[2])
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--set-corner-radius":
        if len(sys.argv) > 2:
            set_corner_radius(sys.argv[2])
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--set-border-color":
        if len(sys.argv) > 2:
            set_border_color(sys.argv[2])
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--add-rule":
        app_class = ""
        opts = ""
        for i in range(2, len(sys.argv)):
            if sys.argv[i] == "--class" and i + 1 < len(sys.argv):
                app_class = sys.argv[i + 1]
            elif sys.argv[i] == "--opts" and i + 1 < len(sys.argv):
                opts = sys.argv[i + 1]
        add_rule(app_class, opts)
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--edit-rule":
        old_class = ""
        new_class = ""
        opts = ""
        for i in range(2, len(sys.argv)):
            if sys.argv[i] == "--old-class" and i + 1 < len(sys.argv):
                old_class = sys.argv[i + 1]
            elif sys.argv[i] == "--class" and i + 1 < len(sys.argv):
                new_class = sys.argv[i + 1]
            elif sys.argv[i] == "--opts" and i + 1 < len(sys.argv):
                opts = sys.argv[i + 1]
        edit_rule(old_class, new_class, opts)
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--delete-rule":
        app_class = ""
        for i in range(2, len(sys.argv)):
            if sys.argv[i] == "--class" and i + 1 < len(sys.argv):
                app_class = sys.argv[i + 1]
        delete_rule(app_class)
        print(json.dumps({"status": "ok"}))
    elif sys.argv[1] == "--reset-rules":
        reset_rules()
        print(json.dumps({"status": "ok"}))

if __name__ == "__main__":
    main()
