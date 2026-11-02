#!/usr/bin/env python3
import sys
import os
import re
import json
import time
import subprocess
import ctypes

CACHE_FILE = "/tmp/azkia_windows_cache.json"

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.append(SCRIPT_DIR)

try:
    from window_info import get_window_info
except ImportError:
    def get_window_info(wid):
        return {"title": "Window", "class": "Application", "icon": ""}

WIN_CACHE = {}
if os.path.exists(CACHE_FILE):
    try:
        with open(CACHE_FILE, "r") as f:
            WIN_CACHE = json.load(f)
    except Exception:
        WIN_CACHE = {}

def get_desktop_map():
    try:
        res = subprocess.run(["bspc", "query", "-T", "-m"], capture_output=True, text=True, timeout=0.3)
        tree = json.loads(res.stdout)
        win_map = {}
        def walk(node, d_name):
            if not node:
                return
            if "client" in node and node["client"]:
                win_map["0x%08x" % node["id"]] = d_name
            walk(node.get("firstChild"), d_name)
            walk(node.get("secondChild"), d_name)
        for d in tree.get("desktops", []):
            walk(d.get("root"), d.get("name"))
        return win_map
    except Exception:
        return {}

def get_open_windows():
    global WIN_CACHE
    try:
        # Get stacking order (bottom-to-top) from X11 root window
        res = subprocess.run(["xprop", "-root", "_NET_CLIENT_LIST_STACKING"], capture_output=True, text=True, timeout=0.3)
        wids_raw = re.findall(r"0x[0-9a-fA-F]+", res.stdout)
        wids = [f"0x{int(w, 16):08x}" for w in wids_raw]
        wids.reverse()  # Top-most (most recently focused) first
    except Exception:
        wids = []

    desktop_map = get_desktop_map()
    valid_wids = [w for w in wids if w in desktop_map]
    for b in desktop_map:
        if b not in valid_wids:
            valid_wids.append(b)

    try:
        focused_res = subprocess.run(["bspc", "query", "-N", "-n", "focused"], capture_output=True, text=True, timeout=0.2)
        focused_wid = focused_res.stdout.strip()
    except Exception:
        focused_wid = ""

    items = []
    cache_dirty = False
    new_cache = {}

    EXCLUDE_TITLES = {"task switcher", "window switcher", "azkia switcher", "azkiawindowswitcher", "lockscreen", "azkia lockscreen"}
    EXCLUDE_CLASSES = {"quickshell", "qs", "azkiaswitcher"}

    for wid in valid_wids:
        # Check cache first for fast 0ms response
        if wid in WIN_CACHE:
            item = WIN_CACHE[wid]
            t_low = (item.get("title") or "").lower().strip()
            c_low = (item.get("class") or "").lower().strip()
            if t_low in EXCLUDE_TITLES or c_low in EXCLUDE_CLASSES:
                continue

            if not item.get("name") or item.get("name") == ", " or item.get("class") == ", ":
                try:
                    info = get_window_info(wid)
                    item["class"] = info.get("class", item.get("class", ""))
                    item["name"] = info.get("name") or item.get("class") or item.get("title") or "Window"
                    item["icon"] = info.get("icon", item.get("icon", ""))
                    cache_dirty = True
                except Exception:
                    pass

            item["desktop"] = desktop_map.get(wid, "")
            item["is_focused"] = (wid == focused_wid)
            items.append(item)
            new_cache[wid] = item
        else:
            # New window, resolve info once
            try:
                info = get_window_info(wid)
                title = info.get("title", "") or info.get("class", "Window")
                wm_class = info.get("class", "")
                app_name = info.get("name", "") or wm_class or title or "Window"
                t_low = title.lower().strip()
                c_low = wm_class.lower().strip()
                if t_low in EXCLUDE_TITLES or c_low in EXCLUDE_CLASSES:
                    continue

                item = {
                    "id": wid,
                    "title": title,
                    "class": wm_class,
                    "name": app_name,
                    "icon": info.get("icon", ""),
                    "desktop": desktop_map.get(wid, ""),
                    "is_focused": (wid == focused_wid)
                }
                items.append(item)
                new_cache[wid] = item
                cache_dirty = True
            except Exception:
                continue

    if cache_dirty or len(new_cache) != len(WIN_CACHE):
        WIN_CACHE = new_cache
        try:
            with open(CACHE_FILE, "w") as f:
                json.dump(WIN_CACHE, f)
        except Exception:
            pass

    return items

def watch_alt_release():
    try:
        x11 = ctypes.cdll.LoadLibrary("libX11.so.6")
        x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x11.XOpenDisplay.restype = ctypes.c_void_p
        disp = x11.XOpenDisplay(None)
        if not disp:
            print("RELEASED", flush=True)
            return

        x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
        x11.XCloseDisplay.restype = ctypes.c_int

        x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x11.XKeysymToKeycode.restype = ctypes.c_ubyte
        alt_l = x11.XKeysymToKeycode(disp, 0xffe9)
        alt_r = x11.XKeysymToKeycode(disp, 0xffea)

        keys = (ctypes.c_ubyte * 32)()
        x11.XQueryKeymap.argtypes = [ctypes.c_void_p, ctypes.c_char_p]

        def is_pressed():
            x11.XQueryKeymap(disp, ctypes.cast(keys, ctypes.c_char_p))
            l = bool(keys[alt_l // 8] & (1 << (alt_l % 8))) if alt_l else False
            r = bool(keys[alt_r // 8] & (1 << (alt_r % 8))) if alt_r else False
            return l or r

        start_time = time.time()
        while True:
            if time.time() - start_time > 15.0:
                break
            if not is_pressed():
                break
            time.sleep(0.01)

        x11.XCloseDisplay(disp)
    except Exception:
        pass

    print("RELEASED", flush=True)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--watch-alt":
        watch_alt_release()
    elif len(sys.argv) > 1 and sys.argv[1] == "--focus" and len(sys.argv) > 2:
        subprocess.run(["bspc", "node", sys.argv[2], "-f"], capture_output=True)
    else:
        windows = get_open_windows()
        print(json.dumps(windows))
