#!/usr/bin/env python3
import sys
import subprocess
import os
import time

WID_FILE = "/tmp/qs_active_wid.txt"


def get_qs_windows():
    """Find all Quickshell windows and return popup/dialog/lockscreen windows (excluding the dock bar)."""
    p = subprocess.run(['pgrep', '-x', 'qs'], capture_output=True, text=True)
    if not p.stdout.strip():
        p = subprocess.run(['pgrep', '-x', 'quickshell'], capture_output=True, text=True)
    
    if not p.stdout.strip():
        return []
    
    qs_pids = p.stdout.strip().split()
    all_wids = []
    for pid in qs_pids:
        res = subprocess.run(['xdotool', 'search', '--pid', pid], capture_output=True, text=True)
        if res.stdout.strip():
            all_wids.extend(res.stdout.strip().split())
    
    popups = []
    for wid in all_wids:
        prop = subprocess.run(['xprop', '-id', wid, '_NET_WM_WINDOW_TYPE'], capture_output=True, text=True).stdout
        # Exclude the persistent dock panel
        if '_NET_WM_WINDOW_TYPE_DOCK' not in prop:
            popups.append(wid)
            
    return popups

def unfocus_all(is_lockscreen=False):
    # Save the currently focused BSPWM window node ONLY if WID_FILE does not exist yet!
    if not os.path.exists(WID_FILE):
        try:
            node = subprocess.run(['bspc', 'query', '-N', '-n', 'focused'], capture_output=True, text=True).stdout.strip()
            if node:
                with open(WID_FILE, 'w') as f:
                    f.write(node)
        except Exception:
            pass

    # Find the quickshell popup or lockscreen window (retry up to 15 times / ~300ms)
    popup_wid = None
    if is_lockscreen:
        res = subprocess.run(['xdotool', 'search', '--name', 'Lockscreen'], capture_output=True, text=True).stdout.strip().split()
        if res:
            popup_wid = res[-1]

    if not popup_wid:
        for _ in range(15):
            popups = get_qs_windows()
            if popups:
                popup_wid = popups[-1]  # most recent mapped window
                break
            time.sleep(0.02)

    if popup_wid:
        try:
            if is_lockscreen:
                geom = subprocess.run(['xdotool', 'getdisplaygeometry'], capture_output=True, text=True).stdout.strip().split()
                if len(geom) == 2:
                    subprocess.run(['xdotool', 'windowmove', popup_wid, '0', '0'], capture_output=True)
                    subprocess.run(['xdotool', 'windowsize', popup_wid, geom[0], geom[1]], capture_output=True)

            subprocess.run(['xdotool', 'windowraise', popup_wid], capture_output=True)
            subprocess.run(['xdotool', 'windowfocus', popup_wid], capture_output=True)
        except Exception:
            pass
    else:
        # Fallback if no popup found: release focus so active window doesn't capture keystrokes
        try:
            subprocess.run(['xdotool', 'set_desktop', '-1'], capture_output=True)
        except Exception:
            pass

def restore_focus():
    saved_node = None
    if os.path.exists(WID_FILE):
        try:
            with open(WID_FILE, 'r') as f:
                saved_node = f.read().strip()
            os.remove(WID_FILE)
        except Exception:
            pass

    if saved_node:
        try:
            subprocess.run(['bspc', 'node', saved_node, '-f'], capture_output=True)
            subprocess.run(['xdotool', 'windowfocus', saved_node], capture_output=True)
        except Exception:
            pass

if __name__ == "__main__":
    if len(sys.argv) > 1:
        if sys.argv[1] == "--restore":
            restore_focus()
        elif sys.argv[1] == "--lockscreen":
            unfocus_all(is_lockscreen=True)
        else:
            unfocus_all(is_lockscreen=False)
    else:
        unfocus_all(is_lockscreen=False)
