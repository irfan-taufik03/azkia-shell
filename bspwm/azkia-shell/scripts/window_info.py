#!/usr/bin/env python3
import sys
import os
import re
import json
import glob
import subprocess
import threading
import queue
import time
import configparser

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

    try:
        cfg = os.path.expanduser("~/.config/gtk-3.0/settings.ini")
        if os.path.exists(cfg):
            cp = configparser.ConfigParser()
            cp.read(cfg)
            return cp.get("Settings", "gtk-icon-theme-name", fallback="hicolor")
    except Exception:
        pass
    return "hicolor"

CURRENT_THEME = get_current_icon_theme()

ICON_PATH_CACHE = {}

def find_icon(name):
    if not name:
        return ""
    if os.path.isabs(name) and os.path.exists(name):
        return name
    if name in ICON_PATH_CACHE:
        return ICON_PATH_CACHE[name]
    
    search_dirs = [
        f"~/.icons/{CURRENT_THEME}",
        f"~/.local/share/icons/{CURRENT_THEME}",
        f"/usr/share/icons/{CURRENT_THEME}",
        "/usr/share/icons/hicolor",
        "/usr/share/pixmaps",
        "~/.icons",
        "~/.local/share/icons",
        "/usr/share/icons",
        "/var/lib/flatpak/exports/share/icons",
        "~/.local/share/flatpak/exports/share/icons",
    ]
    
    for d in search_dirs:
        exp = os.path.expanduser(d)
        if not os.path.isdir(exp):
            continue
        for ext in ["svg", "png", "xpm"]:
            for sub in ["apps/scalable", "scalable/apps", "48x48/apps", "apps/48x48", "apps/64x64", "apps", ""]:
                p = os.path.join(exp, sub, f"{name}.{ext}") if sub else os.path.join(exp, f"{name}.{ext}")
                if os.path.isfile(p):
                    ICON_PATH_CACHE[name] = p
                    return p
    ICON_PATH_CACHE[name] = ""
    return ""

DESKTOP_ENTRIES_CACHE = None

def get_desktop_entries():
    global DESKTOP_ENTRIES_CACHE
    if DESKTOP_ENTRIES_CACHE is not None:
        return DESKTOP_ENTRIES_CACHE

    search_dirs = [
        os.path.expanduser("~/.config/bspwm/azkia-shell/applications"),
        os.path.expanduser("~/.local/share/applications"),
        "/usr/share/applications",
        "/usr/local/share/applications",
        "/var/lib/flatpak/exports/share/applications",
        os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
    ]
    xdg = os.environ.get("XDG_DATA_DIRS", "")
    for d in xdg.split(":"):
        if d:
            search_dirs.append(os.path.join(d, "applications"))
    
    files = []
    for d in search_dirs:
        if os.path.isdir(d):
            files.extend(glob.glob(os.path.join(d, "*.desktop")))
    
    files = list(set(files))
    entries = []
    for df in files:
        try:
            with open(df, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            icon_val = ""
            name_val = ""
            generic_val = ""
            startup_val = ""
            exec_val = ""
            in_entry = False
            for line in content.splitlines():
                line = line.strip()
                if line == "[Desktop Entry]":
                    in_entry = True
                    continue
                if line.startswith("[") and in_entry:
                    break
                if in_entry:
                    if line.startswith("Icon=") and not icon_val: icon_val = line.split("=", 1)[1].strip()
                    elif line.startswith("Name=") and not name_val: name_val = line.split("=", 1)[1].strip()
                    elif line.startswith("GenericName=") and not generic_val: generic_val = line.split("=", 1)[1].strip()
                    elif line.startswith("StartupWMClass=") and not startup_val: startup_val = line.split("=", 1)[1].strip()
                    elif line.startswith("Exec=") and not exec_val: exec_val = line.split("=", 1)[1].strip()

            if name_val or icon_val:
                base = os.path.splitext(os.path.basename(df))[0].lower()
                bin_name = ""
                if exec_val:
                    cmd0 = exec_val.split()[0]
                    bin_name = os.path.basename(cmd0).lower()
                entries.append({
                    "display_name": name_val or generic_val or base,
                    "icon": icon_val,
                    "name": name_val.lower(),
                    "generic": generic_val.lower(),
                    "startup": startup_val.lower(),
                    "binary": bin_name,
                    "base": base
                })
        except Exception:
            pass

    DESKTOP_ENTRIES_CACHE = entries
    return DESKTOP_ENTRIES_CACHE

APP_INFO_CACHE = {}

def get_app_info_for_window(classes, title):
    cache_key = (tuple(classes), title)
    if cache_key in APP_INFO_CACHE:
        return APP_INFO_CACHE[cache_key]

    title_l = (title or "").lower().strip()
    classes_l = [c.lower().strip() for c in classes if c]

    # Special handling for internal Azkia Shell windows (Quickshell windows without specific WM_CLASS)
    is_qs = any(c == "quickshell" for c in classes_l) or not classes_l
    if is_qs:
        if title_l == "settings" or "azkia settings" in title_l:
            p = find_icon(os.path.expanduser("~/.config/bspwm/azkia-shell/assets/azkia-settings-icons.svg"))
            res = ("Azkia Settings", p or "")
            APP_INFO_CACHE[cache_key] = res
            return res
        elif "azkia pdf" in title_l:
            p = find_icon(os.path.expanduser("~/.config/bspwm/azkia-shell/assets/azkia-pdf.svg"))
            res = ("Azkia PDF", p or "")
            APP_INFO_CACHE[cache_key] = res
            return res
        elif "azkia audio player" in title_l:
            p = find_icon(os.path.expanduser("~/.config/bspwm/azkia-shell/assets/azkia-audio-player-icons.svg"))
            res = ("Azkia Audio Player", p or "")
            APP_INFO_CACHE[cache_key] = res
            return res

    # Split title on common delimiters (" - ", " — ", " | ", " • ")
    title_parts = [p.strip() for p in re.split(r'\s+[-—–|•:]\s+', title_l) if p.strip()]
    last_title_part = title_parts[-1] if title_parts else title_l
    first_title_part = title_parts[0] if title_parts else title_l

    best_match = None
    best_score = 0

    entries = get_desktop_entries()
    for entry in entries:
        score = 0
        name_l = entry["name"]
        generic_l = entry.get("generic", "")
        startup_l = entry["startup"]
        base_l = entry["base"]
        binary_l = entry.get("binary", "")

        # 1. Exact match on WM_CLASS (Primary mechanism in X11)
        if startup_l and startup_l != "quickshell" and startup_l in classes_l:
            score = 100
        elif any(c and c != "quickshell" and (c == base_l or base_l == f"org.{c}" or base_l.endswith("." + c) or c.endswith("." + base_l)) for c in classes_l):
            score = 95
        elif binary_l and any(c and c == binary_l for c in classes_l):
            score = 90
        elif any(c and c != "quickshell" and c == name_l for c in classes_l):
            score = 88

        # 2. Match based on Window Title parts (exact match of app part or full title)
        elif name_l and (title_l == name_l or last_title_part == name_l or first_title_part == name_l):
            score = 85
        elif generic_l and (title_l == generic_l or last_title_part == generic_l):
            score = 80
        elif base_l and (last_title_part == base_l or title_l == base_l or last_title_part == base_l.replace("-", " ")):
            score = 75

        # 3. Whole-word match of app name in title (min length 4 to avoid substrings like 'et' matching 'settings')
        elif name_l and len(name_l) >= 4 and re.search(r'\b' + re.escape(name_l) + r'\b', title_l):
            score = 65
        elif startup_l and len(startup_l) >= 4 and startup_l != "quickshell" and re.search(r'\b' + re.escape(startup_l) + r'\b', title_l):
            score = 60
        elif base_l and len(base_l) >= 4 and re.search(r'\b' + re.escape(base_l) + r'\b', title_l):
            score = 55

        # 4. Fallback for classes matching desktop base
        elif any(c and len(c) >= 3 and c in base_l for c in classes_l):
            score = 40

        if score > best_score:
            best_score = score
            best_match = entry

    icon_path = ""
    app_name = ""
    if best_match:
        if best_match.get("icon"):
            icon_path = find_icon(best_match["icon"])
        app_name = best_match.get("display_name", "")

    if not icon_path:
        for c in classes_l:
            icon_path = find_icon(c)
            if icon_path:
                break

    if not app_name:
        raw_name = classes[-1] if classes else (title or "Window")
        app_name = raw_name

    res = (app_name, icon_path or "")
    APP_INFO_CACHE[cache_key] = res
    return res

def get_icon_for_window(classes, title):
    name, icon = get_app_info_for_window(classes, title)
    return icon


IGNORED_WINDOW_TYPES = {
    "_NET_WM_WINDOW_TYPE_UTILITY",
    "_NET_WM_WINDOW_TYPE_TOOLBAR",
    "_NET_WM_WINDOW_TYPE_TOOLTIP",
    "_NET_WM_WINDOW_TYPE_POPUP_MENU",
    "_NET_WM_WINDOW_TYPE_MENU",
    "_NET_WM_WINDOW_TYPE_NOTIFICATION",
    "_NET_WM_WINDOW_TYPE_DOCK",
    "_NET_WM_WINDOW_TYPE_DND",
}

ZOOM_OVERLAY_TITLES = {
    "annofloatbar",
    "annotation",
    "annotate",
    "menu window",
    "zoom_linux_float_video_window",
    "as_toolbar",
    "sharing toolbar",
    "annotoolbar",
}

def get_window_info(win_id, visited=None):
    if not win_id or win_id == "0x0":
        return {"title": "", "class": "", "name": "", "icon": "", "is_overlay": False}
    
    if visited is None:
        visited = set()
    if win_id in visited or len(visited) > 4:
        return {"title": "", "class": "", "name": "", "icon": "", "is_overlay": False}
    visited.add(win_id)

    title = ""
    classes = []
    window_type = ""
    transient_for = ""

    try:
        out = subprocess.run(
            ["xprop", "-id", win_id, "_NET_WM_NAME", "WM_NAME", "WM_CLASS", "_NET_WM_WINDOW_TYPE", "WM_TRANSIENT_FOR"],
            capture_output=True,
            text=True
        ).stdout
        for line in out.splitlines():
            if ("_NET_WM_NAME" in line or "WM_NAME" in line) and not title:
                m = re.search(r'=\s*"(.*)"', line)
                if m:
                    extracted = m.group(1).replace('\\"', '"').replace('\\\\', '\\')
                    if extracted.strip():
                        title = extracted
            elif "WM_CLASS" in line:
                matches = [m for m in re.findall(r'"([^"]*)"', line) if m.strip()]
                if matches:
                    classes = matches
            elif "_NET_WM_WINDOW_TYPE" in line:
                m_type = re.search(r'=\s*([A-Za-z0-9_]+)', line)
                if m_type:
                    window_type = m_type.group(1)
            elif "WM_TRANSIENT_FOR" in line:
                m_trans = re.search(r'window id # (0x[0-9a-fA-F]+)', line)
                if m_trans:
                    transient_for = m_trans.group(1)
    except Exception:
        pass

    app_class = classes[-1] if classes else ""
    is_zoom = app_class.lower() == "zoom"
    title_l = title.lower().strip()

    is_overlay = (
        window_type in IGNORED_WINDOW_TYPES
        or (is_zoom and (title_l in ZOOM_OVERLAY_TITLES or not title_l))
    )

    # If this is an overlay / transient subwindow and has a parent window, follow parent
    if (is_overlay or not title) and transient_for and transient_for != win_id and transient_for != "0x0":
        parent_info = get_window_info(transient_for, visited)
        if parent_info.get("title") or parent_info.get("class"):
            return parent_info

    app_name, icon_path = get_app_info_for_window(classes, title)
    return {
        "title": title,
        "class": app_class,
        "name": app_name or app_class or title or "Window",
        "icon": icon_path,
        "is_overlay": is_overlay
    }

def spy():
    root_cmd = ["stdbuf", "-oL", "xprop", "-spy", "-root", "_NET_ACTIVE_WINDOW"]
    root_proc = subprocess.Popen(root_cmd, stdout=subprocess.PIPE, text=True, bufsize=1)
    out_q = queue.Queue()

    def read_root():
        for line in iter(root_proc.stdout.readline, ""):
            m = re.search(r"window id # (0x[0-9a-fA-F]+)", line)
            win_id = m.group(1) if m else "0x0"
            out_q.put(("root", win_id))

    threading.Thread(target=read_root, daemon=True).start()

    current_win_id = None
    win_proc = None
    cached_info = {"title": "", "class": "", "name": "", "icon": ""}
    empty_reset_timer = None
    timer_lock = threading.Lock()

    def cancel_empty_timer():
        nonlocal empty_reset_timer
        with timer_lock:
            if empty_reset_timer:
                empty_reset_timer.cancel()
                empty_reset_timer = None

    def trigger_empty_reset():
        out_q.put(("empty_confirmed", "0x0"))

    def stop_win_proc():
        nonlocal win_proc
        if win_proc:
            try:
                win_proc.terminate()
                win_proc.wait(timeout=0.1)
            except Exception:
                pass
            win_proc = None

    while True:
        try:
            ev, val = out_q.get()

            if ev == "root":
                win_id = val
                if win_id == "0x0" or not win_id:
                    # Debounce 80ms: in case of rapid tab switches or transient focus shifts
                    cancel_empty_timer()
                    with timer_lock:
                        empty_reset_timer = threading.Timer(0.08, trigger_empty_reset)
                        empty_reset_timer.daemon = True
                        empty_reset_timer.start()
                    continue

                # Valid window ID received: cancel pending empty reset
                cancel_empty_timer()

                if win_id != current_win_id:
                    stop_win_proc()
                    current_win_id = win_id

                    info = get_window_info(win_id)

                    # If it is an overlay / annotation window and we already have a valid active app, keep current
                    if info.get("is_overlay") and cached_info.get("title"):
                        continue

                    # If title is empty but same application class (e.g., WPS tab switch in progress), keep previous title
                    if not info["title"] and cached_info.get("title") and info.get("class") and info["class"] == cached_info.get("class"):
                        info["title"] = cached_info["title"]

                    cached_info = {
                        "title": info["title"],
                        "class": info["class"],
                        "name": info.get("name", ""),
                        "icon": info["icon"]
                    }
                    print(json.dumps(cached_info), flush=True)

                    win_cmd = ["stdbuf", "-oL", "xprop", "-spy", "-id", win_id, "_NET_WM_NAME", "WM_NAME"]
                    win_proc = subprocess.Popen(
                        win_cmd,
                        stdout=subprocess.PIPE,
                        text=True,
                        bufsize=1
                    )

                    def read_win(wid, sub_p):
                        for wline in iter(sub_p.stdout.readline, ""):
                            if "_NET_WM_NAME" in wline or "WM_NAME" in wline:
                                m_t = re.search(r'=\s*"(.*)"', wline)
                                if m_t:
                                    t_str = m_t.group(1).replace('\\"', '"').replace('\\\\', '\\').strip()
                                    if t_str:  # Ignore transient empty titles
                                        out_q.put(("title", (wid, t_str)))

                    threading.Thread(target=read_win, args=(win_id, win_proc), daemon=True).start()

            elif ev == "empty_confirmed":
                stop_win_proc()
                current_win_id = "0x0"
                cached_info = {"title": "", "class": "", "name": "", "icon": ""}
                print(json.dumps(cached_info), flush=True)

            elif ev == "title":
                wid, new_title = val
                if wid == current_win_id and new_title and new_title != cached_info.get("title"):
                    cached_info["title"] = new_title
                    # Ensure name and icon are present if not already resolved
                    if not cached_info.get("icon") or not cached_info.get("name"):
                        app_name, icon_p = get_app_info_for_window([cached_info.get("class", "")], new_title)
                        cached_info["name"] = app_name
                        if not cached_info.get("icon"):
                            cached_info["icon"] = icon_p
                    print(json.dumps(cached_info), flush=True)

        except Exception:
            pass

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--spy":
        spy()
    elif len(sys.argv) > 1 and sys.argv[1]:
        print(json.dumps(get_window_info(sys.argv[1])))
    else:
        try:
            out = subprocess.run(["xprop", "-root", "_NET_ACTIVE_WINDOW"], capture_output=True, text=True).stdout
            m = re.search(r"window id # (0x[0-9a-fA-F]+)", out)
            win_id = m.group(1) if m else "0x0"
            info = get_window_info(win_id)
            print(json.dumps({"title": info["title"], "class": info["class"], "name": info["name"], "icon": info["icon"]}))
        except Exception:
            print(json.dumps({"title": "", "class": "", "name": "", "icon": ""}))
