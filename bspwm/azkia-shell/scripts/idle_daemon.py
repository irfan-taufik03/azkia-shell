#!/usr/bin/env python3
import time
import os
import sys
import subprocess
import json
import ctypes
import shutil
import threading
import fcntl

PID_LOCK_FILE = "/tmp/azkia_idle_daemon.lock"
STATE_FILE = "/tmp/azkia_lock_state"
CAFFEINE_FILE = "/tmp/azkia_caffeine_state"
LOG_FILE = "/tmp/azkia_idle_daemon.log"

def is_caffeine_active():
    if os.path.exists(CAFFEINE_FILE):
        try:
            with open(CAFFEINE_FILE, "r") as f:
                return f.read().strip() == "1"
        except Exception:
            pass
    return False

def log(msg):
    try:
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {msg}\n")
    except Exception:
        pass

def acquire_single_instance_lock():
    try:
        lock_fd = os.open(PID_LOCK_FILE, os.O_CREAT | os.O_RDWR)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return lock_fd
    except (BlockingIOError, OSError):
        # Another instance is already running
        sys.exit(0)

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
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XDefaultRootWindow.restype = ctypes.c_ulong
    x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    xss.XScreenSaverQueryInfo.restype = ctypes.c_int
    xss.XScreenSaverQueryInfo.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(XScreenSaverInfo)]
    display = x11.XOpenDisplay(None)
    root_win = x11.XDefaultRootWindow(display)
    info = XScreenSaverInfo()
    has_x11 = True
except Exception:
    has_x11 = False

def get_idle_sec():
    if has_x11 and display:
        try:
            xss.XScreenSaverQueryInfo(display, root_win, ctypes.byref(info))
            return info.idle / 1000.0
        except Exception:
            pass
    try:
        res = subprocess.run(['xprintidle'], capture_output=True, text=True, timeout=1)
        if res.returncode == 0 and res.stdout.strip().isdigit():
            return int(res.stdout.strip()) / 1000.0
    except Exception:
        pass
    return 0

_last_known_lock_state = False

def is_sys_locked():
    global _last_known_lock_state
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                val = f.read().strip()
                if val == "1":
                    _last_known_lock_state = True
                elif val == "0":
                    _last_known_lock_state = False
        except Exception:
            pass
    return _last_known_lock_state

def is_monitor_off():
    try:
        res = subprocess.run(['xset', 'q'], capture_output=True, text=True, timeout=0.5)
        for line in res.stdout.splitlines():
            line = line.strip()
            if 'Monitor is Off' in line or 'Monitor is Suspend' in line or 'Monitor is Standby' in line:
                return True
    except Exception:
        pass
    return False

def load_settings():
    config_path = os.path.expanduser("~/.config/bspwm/azkia-shell/appearance.json")
    defaults = {
        "autoLockEnabled": True,
        "autoLockTimeout": 180,  # 3 minutes
        "autoSleepTimeout": 120,  # 2 minutes after lock
        "autoSuspendEnabled": False,
        "autoSuspendTimeout": 600  # 10 minutes after sleep
    }
    if os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                data = json.load(f)
                defaults["autoLockEnabled"] = data.get("autoLockEnabled", True)
                defaults["autoLockTimeout"] = int(data.get("autoLockTimeout", 180))
                defaults["autoSleepTimeout"] = int(data.get("autoSleepTimeout", 120))
                defaults["autoSuspendEnabled"] = bool(data.get("autoSuspendEnabled", False))
                defaults["autoSuspendTimeout"] = int(data.get("autoSuspendTimeout", 600))
        except Exception:
            pass
    return defaults

def lock_screen():
    shell_dir = os.path.expanduser("~/.config/bspwm/azkia-shell")
    cmd = shutil.which("qs") or shutil.which("quickshell") or "/usr/bin/qs"
    subprocess.run([cmd, "ipc", "-p", shell_dir, "call", "lockscreen", "lock"], stderr=subprocess.DEVNULL)

def screen_off():
    subprocess.run(["xset", "+dpms", "dpms", "force", "off"], stderr=subprocess.DEVNULL)

def suspend_system():
    log("Invoking systemctl suspend...")
    subprocess.run(["systemctl", "suspend"], stderr=subprocess.DEVNULL)

_cached_pw_active = False
_last_pw_check = 0.0

def is_media_or_call_active():
    """Inhibits auto-lock if Keep Awake is active, or fullscreen window, active MPRIS media playback, or meeting call is active."""
    if is_caffeine_active():
        return True
    global _cached_pw_active, _last_pw_check
    
    # 1. Check if any window is in fullscreen mode on the active desktop
    try:
        res = subprocess.run(['bspc', 'query', '-N', '-n', '.fullscreen.local'], capture_output=True, text=True, timeout=0.5)
        if res.returncode == 0 and res.stdout.strip():
            return True
    except Exception:
        pass

    # 2. Check if playerctl reports media is currently Playing (e.g. Spotify, YouTube, MPV, VLC)
    try:
        res = subprocess.run(['playerctl', 'status'], capture_output=True, text=True, timeout=0.5)
        if res.returncode == 0 and 'Playing' in res.stdout:
            return True
    except Exception:
        pass

    # 3. Check meeting apps
    dialog_apps = ['zoom', 'zoom.real', 'teams', 'skype', 'webex']
    for app in dialog_apps:
        try:
            p = subprocess.run(['pgrep', '-x', app], capture_output=True, text=True, timeout=0.3)
            if p.returncode == 0 and p.stdout.strip():
                return True
        except Exception:
            pass

    # 4. Check PipeWire active streams (cached every 5s to avoid high CPU load)
    now = time.time()
    if now - _last_pw_check > 5.0:
        _last_pw_check = now
        try:
            proc = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=1.0)
            if proc.returncode == 0 and proc.stdout:
                data = json.loads(proc.stdout)
                ignored_apps = ['quickshell', 'cava', 'python', 'python3', 'wireplumber', 'pipewire', 'pw-dump']
                active = False
                for item in data:
                    if item.get('type') == 'PipeWire:Interface:Node':
                        info = item.get('info', {})
                        state = info.get('state')
                        props = info.get('props', {})
                        media_class = props.get('media.class', '')
                        app_name = (props.get('application.name') or props.get('node.name') or '').lower()

                        if state == 'running' and not any(ign in app_name for ign in ignored_apps):
                            if media_class in ['Stream/Output/Audio', 'Stream/Input/Audio', 'Stream/Input/Video', 'Stream/Output/Video']:
                                active = True
                                break
                _cached_pw_active = active
        except Exception:
            _cached_pw_active = False

    return _cached_pw_active

def listen_sleep_signals():
    """Listens for systemd-logind PrepareForSleep(true) signals over system D-Bus."""
    while True:
        try:
            proc = subprocess.Popen(
                ['gdbus', 'monitor', '--system', '--dest', 'org.freedesktop.login1', '--object-path', '/org/freedesktop/login1'],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True
            )
            for line in proc.stdout:
                # Only lock when starting sleep (PrepareForSleep: true)
                if 'PrepareForSleep' in line and 'true' in line.lower():
                    if not is_caffeine_active():
                        lock_screen()
        except Exception:
            pass
        time.sleep(3)

def main():
    _lock_fd = acquire_single_instance_lock()
    log("idle_daemon started.")

    # Start background signal listener thread for system suspend / sleep
    t_login = threading.Thread(target=listen_sleep_signals, daemon=True)
    t_login.start()

    locked_start_time = None
    sleep_start_time = None
    screen_is_off = False
    suspended = False
    last_settings_check = 0.0
    last_loop_time = time.time()

    settings = load_settings()

    while True:
        time.sleep(1)
        now = time.time()
        idle_sec = get_idle_sec()

        # Check Keep Awake / Caffeine: inhibit auto-lock, screen off, and suspend
        if is_caffeine_active():
            locked_start_time = None
            sleep_start_time = None
            screen_is_off = False
            suspended = False
            last_loop_time = now
            continue

        # Suspend / Sleep resume detection (Wakeup watchdog)
        # If the gap between iterations is genuinely large (> 25s while sleep is 1s)
        # AND user was idle before/during suspend (idle_sec >= 10), lock screen.
        if (now - last_loop_time) > 25.0 and idle_sec >= 10.0:
            log("System resume from sleep/suspend detected via watchdog. Resetting timers.")
            lock_screen()
            sleep_start_time = None
            locked_start_time = now
            screen_is_off = False
            suspended = False
        last_loop_time = now

        if now - last_settings_check > 5.0:
            settings = load_settings()
            last_settings_check = now

        if not settings.get("autoLockEnabled", True):
            if locked_start_time is not None or screen_is_off:
                log("autoLockEnabled disabled in settings. Resetting state.")
            locked_start_time = None
            sleep_start_time = None
            screen_is_off = False
            suspended = False
            continue

        auto_lock_time = settings.get("autoLockTimeout", 180)
        auto_sleep_time = settings.get("autoSleepTimeout", 120)
        auto_suspend_enabled = settings.get("autoSuspendEnabled", False)
        auto_suspend_time = settings.get("autoSuspendTimeout", 600)

        sys_locked = is_sys_locked()

        # Trigger 1: Auto Lock after inactivity for >= auto_lock_time
        # Only check inhibitor if not already locked
        if not sys_locked:
            if is_media_or_call_active():
                # Inhibit auto-lock while media or meeting is active
                continue
            if idle_sec >= auto_lock_time:
                log(f"Auto-locking screen: idle_sec={idle_sec:.1f} >= {auto_lock_time}s")
                lock_screen()
                sys_locked = True
                global _last_known_lock_state
                _last_known_lock_state = True

        # Track locked state timing
        if sys_locked:
            if locked_start_time is None:
                locked_start_time = time.time()
                log(f"System locked detected. Auto-sleep scheduled in {auto_sleep_time}s")

            # Trigger 2: Auto Sleep after screen has been locked for >= auto_sleep_time
            time_locked = time.time() - locked_start_time
            if time_locked >= auto_sleep_time and not screen_is_off:
                screen_off()
                screen_is_off = True
                sleep_start_time = time.time()
                log(f"Screen turned off (sleep mode). Auto-suspend scheduled in {auto_suspend_time}s (enabled={auto_suspend_enabled})")

            # Check if screen woke up from sleep
            if screen_is_off and sleep_start_time is not None:
                time_in_sleep = time.time() - sleep_start_time
                # Grace period: ignore the first 4 seconds after turning screen off
                # because DPMS mode switch resets X11 idle counter temporarily
                if time_in_sleep > 4.0:
                    mon_off = is_monitor_off()
                    # If monitor is back On or user provided physical input (idle_sec < 3.0)
                    if not mon_off or idle_sec < 3.0:
                        log(f"Screen wake detected (mon_off={mon_off}, idle_sec={idle_sec:.1f}). Resuming locked screen.")
                        screen_is_off = False
                        sleep_start_time = None
                        locked_start_time = time.time()
                        suspended = False

            # Trigger 3: Auto Suspend after screen has been asleep (off) for >= auto_suspend_time
            if auto_suspend_enabled and screen_is_off and sleep_start_time is not None and not suspended:
                time_asleep = time.time() - sleep_start_time
                if time_asleep >= auto_suspend_time:
                    suspended = True
                    log(f"Auto Suspend triggered! (time_asleep={time_asleep:.1f}s >= {auto_suspend_time}s). Suspending system...")
                    suspend_system()
        else:
            if locked_start_time is not None or screen_is_off:
                log("System unlocked. Resetting timers.")
            locked_start_time = None
            sleep_start_time = None
            screen_is_off = False
            suspended = False

if __name__ == "__main__":
    main()


