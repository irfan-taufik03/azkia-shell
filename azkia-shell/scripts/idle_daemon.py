#!/usr/bin/env python3
import time
import os
import subprocess
import json
import ctypes

STATE_FILE = "/tmp/azkia_lock_state"

class XScreenSaverInfo(ctypes.Structure):
    _fields_ = [
        ('window', ctypes.c_ulong),
        ('state', ctypes.c_int),
        ('kind', ctypes.c_int),
        ('til_or_since', ctypes.c_ulong),
        ('idle', ctypes.c_ulong),
        ('event_mask', ctypes.c_ulong)
    ]

try:
    x11 = ctypes.cdll.LoadLibrary('libX11.so.6')
    xss = ctypes.cdll.LoadLibrary('libXss.so.1')
    display = x11.XOpenDisplay(None)
    root_win = x11.XDefaultRootWindow(display)
    info = XScreenSaverInfo()
    has_x11 = True
except Exception:
    has_x11 = False

def get_idle_sec():
    if not has_x11 or not display:
        return 0
    try:
        xss.XScreenSaverQueryInfo(display, root_win, ctypes.byref(info))
        return info.idle / 1000.0
    except Exception:
        return 0

def is_sys_locked():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                return f.read().strip() == "1"
        except Exception:
            pass
    return False

def load_settings():
    config_path = os.path.expanduser("~/.config/bspwm/azkia-shell/appearance.json")
    defaults = {
        "autoLockEnabled": True,
        "autoLockTimeout": 180,  # 3 minutes
        "autoSleepTimeout": 120   # 2 minutes after lock
    }
    if os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                data = json.load(f)
                defaults["autoLockEnabled"] = data.get("autoLockEnabled", True)
                defaults["autoLockTimeout"] = int(data.get("autoLockTimeout", 180))
                defaults["autoSleepTimeout"] = int(data.get("autoSleepTimeout", 120))
        except Exception:
            pass
    return defaults

def lock_screen():
    shell_dir = os.path.expanduser("~/.config/bspwm/azkia-shell")
    subprocess.run(["qs", "ipc", "-p", shell_dir, "call", "lockscreen", "lock"], stderr=subprocess.DEVNULL)

def screen_off():
    subprocess.run(["xset", "dpms", "force", "off"], stderr=subprocess.DEVNULL)

def is_media_or_call_active():
    """Inhibits auto-lock if fullscreen window, PipeWire audio/video stream, or Zoom is active."""
    # 1. Check if any window is in fullscreen mode on the active desktop
    try:
        res = subprocess.run(['bspc', 'query', '-N', '-n', '.fullscreen.local'], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            return True
    except Exception:
        pass

    # 2. Check PipeWire running audio/video streams via pw-dump
    try:
        proc = subprocess.run(['pw-dump'], capture_output=True, text=True)
        if proc.returncode == 0 and proc.stdout:
            data = json.loads(proc.stdout)
            for item in data:
                if item.get('type') == 'PipeWire:Interface:Node':
                    info = item.get('info', {})
                    state = info.get('state')
                    props = info.get('props', {})
                    media_class = props.get('media.class', '')
                    app_name = (props.get('application.name') or props.get('node.name') or '').lower()

                    if state == 'running' and 'quickshell' not in app_name:
                        if media_class in ['Stream/Output/Audio', 'Stream/Input/Audio', 'Stream/Input/Video', 'Stream/Output/Video']:
                            return True
    except Exception:
        pass

    # 3. Check for Zoom or meeting processes
    meeting_apps = ['zoom', 'zoom.real', 'teams', 'skype', 'webex']
    for app in meeting_apps:
        try:
            p = subprocess.run(['pgrep', '-x', app], capture_output=True, text=True)
            if p.returncode == 0 and p.stdout.strip():
                return True
        except Exception:
            pass

    return False

def main():
    locked_start_time = None
    screen_is_off = False
    last_settings_check = 0

    settings = load_settings()

    while True:
        time.sleep(2)
        now = time.time()

        if now - last_settings_check > 5:
            settings = load_settings()
            last_settings_check = now

        if not settings.get("autoLockEnabled", True):
            locked_start_time = None
            screen_is_off = False
            continue

        # Inhibit lockscreen if media, Zoom, or fullscreen window is active
        if is_media_or_call_active():
            locked_start_time = None
            screen_is_off = False
            continue

        idle_sec = get_idle_sec()
        auto_lock_time = settings.get("autoLockTimeout", 180)
        auto_sleep_time = settings.get("autoSleepTimeout", 120)

        sys_locked = is_sys_locked()

        # Trigger 1: Auto Lock after inactivity for >= auto_lock_time (default 180s = 3m)
        if idle_sec >= auto_lock_time and not sys_locked:
            lock_screen()
            sys_locked = True

        # Track locked state timing
        if sys_locked:
            if locked_start_time is None:
                locked_start_time = time.time()

            # Trigger 2: Auto Sleep after screen has been locked for >= auto_sleep_time (default 120s = 2m)
            time_locked = time.time() - locked_start_time
            if time_locked >= auto_sleep_time and not screen_is_off:
                screen_off()
                screen_is_off = True
        else:
            locked_start_time = None
            screen_is_off = False

if __name__ == "__main__":
    main()
