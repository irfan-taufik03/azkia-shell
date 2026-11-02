#!/usr/bin/env python3
import sys
import os
import subprocess
import re
import ctypes
import json
import time

CACHE_FILE = "/tmp/azkia_notif_windows.json"

class XWMHints(ctypes.Structure):
    _fields_ = [
        ("flags", ctypes.c_long),
        ("input", ctypes.c_int),
        ("initial_state", ctypes.c_int),
        ("icon_pixmap", ctypes.c_ulong),
        ("icon_window", ctypes.c_ulong),
        ("icon_x", ctypes.c_int),
        ("icon_y", ctypes.c_int),
        ("icon_mask", ctypes.c_ulong),
        ("window_group", ctypes.c_ulong),
    ]

try:
    X11 = ctypes.cdll.LoadLibrary("libX11.so.6")
    X11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    X11.XOpenDisplay.restype = ctypes.c_void_p
    X11.XGetWMHints.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    X11.XGetWMHints.restype = ctypes.POINTER(XWMHints)
    X11.XSetWMHints.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(XWMHints)]
    X11.XSetWMHints.restype = ctypes.c_int
    X11.XFlush.argtypes = [ctypes.c_void_p]
    X11.XFree.argtypes = [ctypes.c_void_p]
    X11.XCloseDisplay.argtypes = [ctypes.c_void_p]
except Exception:
    X11 = None

XUrgencyHint = (1 << 8)

def set_window_urgent(nid):
    if not X11 or not nid:
        return False
    try:
        display = X11.XOpenDisplay(None)
        if not display:
            return False
        win_id = int(nid, 16) if isinstance(nid, str) else int(nid)
        hints_ptr = X11.XGetWMHints(display, win_id)
        if hints_ptr:
            hints = hints_ptr.contents
        else:
            hints = XWMHints()
            hints.flags = 0

        hints.flags |= XUrgencyHint
        X11.XSetWMHints(display, win_id, ctypes.byref(hints))
        X11.XFlush(display)
        if hints_ptr:
            X11.XFree(hints_ptr)
        X11.XCloseDisplay(display)
        return True
    except Exception:
        return False

def load_cache():
    if not os.path.exists(CACHE_FILE):
        return {}
    try:
        with open(CACHE_FILE, "r") as f:
            data = json.load(f)
            now = time.time()
            # Prune entries older than 6 hours
            return {k: v for k, v in data.items() if isinstance(v, dict) and (now - v.get("ts", 0) < 21600)}
    except Exception:
        return {}

def save_cache(cache):
    try:
        with open(CACHE_FILE, "w") as f:
            json.dump(cache, f)
    except Exception:
        pass

def cache_target_window(notif_id, wid, app_name=""):
    if not notif_id or not wid:
        return
    cache = load_cache()
    cache[str(notif_id)] = {
        "wid": wid,
        "app": app_name,
        "ts": time.time()
    }
    save_cache(cache)

def get_cached_window(notif_id):
    if not notif_id:
        return ""
    cache = load_cache()
    item = cache.get(str(notif_id))
    if isinstance(item, dict):
        return item.get("wid", "")
    return ""

def remove_cached_window(notif_id):
    if not notif_id:
        return
    cache = load_cache()
    s_id = str(notif_id)
    if s_id in cache:
        del cache[s_id]
        save_cache(cache)

def get_proc_ancestry(pid):
    ancestors = [pid]
    curr = pid
    while curr > 1:
        try:
            with open(f"/proc/{curr}/stat", "r") as f:
                ppid = int(f.read().split()[3])
            if ppid in ancestors or ppid <= 1:
                break
            ancestors.append(ppid)
            curr = ppid
        except Exception:
            break
    return ancestors

def get_open_windows():
    windows = []
    try:
        res = subprocess.run(["bspc", "query", "-N", "-n", ".window"], capture_output=True, text=True, timeout=1.0)
        node_ids = [line.strip() for line in res.stdout.strip().split('\n') if line.strip()]
        
        # Get stacking order for recency bonus
        stacking_map = {}
        try:
            s_res = subprocess.run(["xprop", "-root", "_NET_CLIENT_LIST_STACKING"], capture_output=True, text=True, timeout=0.5)
            s_wids = re.findall(r"0x[0-9a-fA-F]+", s_res.stdout)
            for idx, sw in enumerate(s_wids):
                stacking_map[f"0x{int(sw, 16):08x}".lower()] = idx
        except Exception:
            pass

        for nid in node_ids:
            norm_nid = f"0x{int(nid, 16):08x}".lower()
            xprop_res = subprocess.run(
                ["xprop", "-id", nid, "WM_CLASS", "_NET_WM_PID", "_NET_WM_NAME", "WM_NAME", "WM_HINTS", "_NET_WM_USER_TIME"],
                capture_output=True, text=True, timeout=0.8
            )
            out = xprop_res.stdout

            classes = []
            if "WM_CLASS" in out:
                part = out.split("WM_CLASS")[1].split("\n")[0]
                classes = [c.lower() for c in re.findall(r'"([^"]*)"', part) if c.strip()]

            m_pid = re.search(r'_NET_WM_PID\(CARDINAL\) = (\d+)', out)
            pid = int(m_pid.group(1)) if m_pid else None

            m_name = re.search(r'_NET_WM_NAME\(UTF8_STRING\) = "([^"]*)"', out)
            if not m_name:
                m_name = re.search(r'WM_NAME\(STRING\) = "([^"]*)"', out)
            title = m_name.group(1) if m_name else ""

            m_utime = re.search(r'_NET_WM_USER_TIME\(CARDINAL\) = (\d+)', out)
            utime = int(m_utime.group(1)) if m_utime else 0

            is_urgent = False
            if "WM_HINTS" in out:
                hints_part = out.split("WM_HINTS")[1].split("\n")[0]
                if "urgency" in hints_part.lower():
                    is_urgent = True

            windows.append({
                "nid": nid,
                "norm_nid": norm_nid,
                "classes": classes,
                "pid": pid,
                "title": title,
                "user_time": utime,
                "is_urgent": is_urgent,
                "stack_rank": stacking_map.get(norm_nid, 0)
            })
    except Exception:
        pass
    return windows

def match_window(app_name="", desktop_entry="", summary="", body="", hints=None, windows=None):
    if windows is None:
        windows = get_open_windows()
    if not windows:
        return None

    if hints is None:
        hints = {}

    open_norm_map = {w["norm_nid"]: w for w in windows}

    # 1. Direct window ID in hints
    for k in ("window-id", "window_id", "wid", "x-kde-originating-window-id", "x-canonical-private-window-id"):
        if k in hints and hints[k]:
            val = hints[k]
            try:
                if isinstance(val, int) or (isinstance(val, str) and val.isdigit()):
                    norm = f"0x{int(val):08x}".lower()
                else:
                    norm = f"0x{int(str(val), 16):08x}".lower()
                if norm in open_norm_map:
                    return open_norm_map[norm]
            except Exception:
                pass

    # 2. Match by Process ID (PID)
    sender_pid = hints.get("sender-pid") or hints.get("pid")
    pid_candidates = []
    if sender_pid:
        try:
            s_pid = int(sender_pid)
            s_ancestry = set(get_proc_ancestry(s_pid))
            for w in windows:
                w_pid = w.get("pid")
                if w_pid:
                    if w_pid in s_ancestry or s_pid in get_proc_ancestry(w_pid):
                        pid_candidates.append(w)
        except Exception:
            pass

    if len(pid_candidates) == 1:
        return pid_candidates[0]

    # 3. Match by Application Name / Desktop Entry classes
    search_terms = set()
    if desktop_entry:
        search_terms.add(desktop_entry.lower())
    if app_name:
        search_terms.add(app_name.lower())
        search_terms.add(re.sub(r'[^a-zA-Z0-9]', '', app_name.lower()))
        first_word = app_name.split()[0].lower()
        if len(first_word) > 2:
            search_terms.add(first_word)

    class_candidates = []
    for w in windows:
        for term in search_terms:
            if not term:
                continue
            if any(term in c or c in term for c in w["classes"]):
                class_candidates.append(w)
                break

    candidates = pid_candidates if pid_candidates else class_candidates
    if not candidates:
        return None
    if len(candidates) == 1:
        return candidates[0]

    # 4. Score multiple candidate windows to find the exact sender
    text_corpus = (f"{summary} {body}").lower()
    words = [w for w in re.findall(r'[a-zA-Z0-9_-]{2,}', text_corpus) if len(w) >= 2]
    # Filter out extremely common filler words
    stop_words = {"the", "and", "for", "with", "from", "you", "your", "has", "have", "notification", "message", "in", "to", "at", "of", "on"}
    sig_words = [w for w in words if w not in stop_words]

    best_cand = None
    best_score = -99999999

    for w in candidates:
        score = 0
        w_title_l = w["title"].lower()

        # Urgency flag
        if w["is_urgent"]:
            score += 1000

        # Title keyword matches
        for word in sig_words:
            if word in w_title_l:
                score += 150

        # Exact summary/title substring overlap
        if summary and summary.lower() in w_title_l:
            score += 300

        # User time recency (window that had recent interaction)
        score += (w["user_time"] / 100000.0)

        # Stacking order recency
        score += (w.get("stack_rank", 0) * 5)

        if score > best_score:
            best_score = score
            best_cand = w

    return best_cand

def focus_window(nid):
    if not nid:
        return False
    try:
        # Check current focused window to avoid unnecessary flicker
        f_res = subprocess.run(["bspc", "query", "-N", "-n", "focused"], capture_output=True, text=True, timeout=0.3)
        cur_focused = f_res.stdout.strip()
        if cur_focused and (cur_focused.lower() == nid.lower() or int(cur_focused, 16) == int(nid, 16)):
            return True

        # Unhide window in case it was hidden/minimized
        subprocess.run(["bspc", "node", nid, "-g", "hidden=off"], capture_output=True, timeout=0.3)

        # Switch desktop if the node is on an inactive desktop
        d_res = subprocess.run(["bspc", "query", "-D", "-n", nid], capture_output=True, text=True, timeout=0.3)
        desktop_id = d_res.stdout.strip()
        if desktop_id:
            subprocess.run(["bspc", "desktop", desktop_id, "-f"], capture_output=True, timeout=0.3)

        # Focus node
        res = subprocess.run(["bspc", "node", nid, "-f"], capture_output=True, text=True, timeout=0.5)
        return res.returncode == 0
    except Exception:
        return False

def launch_app(app_name, desktop_entry):
    candidates = []
    if desktop_entry:
        candidates.append(desktop_entry.lower())
    if app_name:
        candidates.append(app_name.lower())
        cleaned = re.sub(r'[^a-zA-Z0-9]', '', app_name.lower())
        candidates.append(cleaned)
        kebab = re.sub(r'\s+', '-', app_name.lower())
        candidates.append(kebab)

    if desktop_entry:
        try:
            res = subprocess.run(["gtk-launch", desktop_entry], capture_output=True)
            if res.returncode == 0:
                return True
        except Exception:
            pass

    for c in candidates:
        try:
            res = subprocess.run(["gtk-launch", c], capture_output=True)
            if res.returncode == 0:
                return True
        except Exception:
            pass

    for c in candidates:
        try:
            which_res = subprocess.run(["which", c], capture_output=True, text=True)
            if which_res.returncode == 0:
                subprocess.Popen([c], start_new_session=True)
                return True
        except Exception:
            pass

    return False

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    cmd = sys.argv[1]

    # Mode 1: Register notification and find/tag target window
    if cmd == "--register":
        # Usage: --register <notif_id> <app_name> <desktop_entry> <summary> <body> <hints_json>
        notif_id = sys.argv[2] if len(sys.argv) > 2 else ""
        app_name = sys.argv[3] if len(sys.argv) > 3 else ""
        desktop_entry = sys.argv[4] if len(sys.argv) > 4 else ""
        summary = sys.argv[5] if len(sys.argv) > 5 else ""
        body = sys.argv[6] if len(sys.argv) > 6 else ""
        hints_str = sys.argv[7] if len(sys.argv) > 7 else "{}"
        try:
            hints = json.loads(hints_str) if hints_str else {}
        except Exception:
            hints = {}

        target = match_window(app_name, desktop_entry, summary, body, hints)
        if target:
            target_wid = target["nid"]
            cache_target_window(notif_id, target_wid, app_name)
            set_window_urgent(target_wid)
        sys.exit(0)

    # Mode 2: Focus the specific window for this notification
    if cmd == "--focus":
        # Usage: --focus <notif_id> <app_name> <desktop_entry> [summary] [body] [hints_json] [target_wid]
        notif_id = sys.argv[2] if len(sys.argv) > 2 else ""
        app_name = sys.argv[3] if len(sys.argv) > 3 else ""
        desktop_entry = sys.argv[4] if len(sys.argv) > 4 else ""
        summary = sys.argv[5] if len(sys.argv) > 5 else ""
        body = sys.argv[6] if len(sys.argv) > 6 else ""
        hints_str = sys.argv[7] if len(sys.argv) > 7 else "{}"
        explicit_wid = sys.argv[8] if len(sys.argv) > 8 else ""
        try:
            hints = json.loads(hints_str) if hints_str else {}
        except Exception:
            hints = {}

        windows = get_open_windows()
        open_nids = {w["nid"].lower() for w in windows}
        open_ints = {int(w["nid"], 16) for w in windows}

        # 1. Try explicit_wid if provided and open
        if explicit_wid:
            try:
                int_id = int(explicit_wid, 16) if isinstance(explicit_wid, str) and explicit_wid.startswith("0x") else int(explicit_wid)
                if int_id in open_ints:
                    focus_window(explicit_wid)
                    remove_cached_window(notif_id)
                    sys.exit(0)
            except Exception:
                pass

        # 2. Try cached target window
        cached_wid = get_cached_window(notif_id)
        if cached_wid:
            try:
                int_id = int(cached_wid, 16)
                if int_id in open_ints:
                    focus_window(cached_wid)
                    remove_cached_window(notif_id)
                    sys.exit(0)
            except Exception:
                pass

        # 3. Fallback: match among currently open windows
        matched = match_window(app_name, desktop_entry, summary, body, hints, windows)
        if matched:
            focus_window(matched["nid"])
            remove_cached_window(notif_id)
            sys.exit(0)

        # 4. Fallback: launch application if no window is open
        launch_app(app_name, desktop_entry)
        remove_cached_window(notif_id)
        sys.exit(0)

    # Mode 3: Clean up cache entry
    if cmd == "--remove":
        notif_id = sys.argv[2] if len(sys.argv) > 2 else ""
        remove_cached_window(notif_id)
        sys.exit(0)

    # Mode 4: Legacy --set-urgent
    if cmd == "--set-urgent":
        args = sys.argv[2:]
        app_name = args[0] if len(args) > 0 else ""
        desktop_entry = args[1] if len(args) > 1 else ""
        matched = match_window(app_name, desktop_entry)
        if matched:
            set_window_urgent(matched["nid"])
        sys.exit(0)

    # Mode 5: Legacy default focus by app_name / desktop_entry
    app_name = sys.argv[1] if len(sys.argv) > 1 else ""
    desktop_entry = sys.argv[2] if len(sys.argv) > 2 else ""
    matched = match_window(app_name, desktop_entry)
    if matched:
        focus_window(matched["nid"])
    else:
        launch_app(app_name, desktop_entry)

if __name__ == "__main__":
    main()
