#!/usr/bin/env python3
import sys
import os
import json
import glob
import time
import socket
import subprocess
import hashlib
import shutil
import fcntl
import signal
import threading

# Try importing dbus and GLib for MPRIS 2 D-Bus integration
glib_lib = None
CALLBACK_TYPE = None
try:
    import dbus
    import dbus.service
    import dbus.mainloop.glib
    import ctypes
    glib_lib = ctypes.CDLL("libglib-2.0.so.0")
    CALLBACK_TYPE = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)
    glib_lib.g_main_loop_new.restype = ctypes.c_void_p
    glib_lib.g_main_loop_new.argtypes = [ctypes.c_void_p, ctypes.c_int]
    glib_lib.g_main_loop_run.argtypes = [ctypes.c_void_p]
    glib_lib.g_main_loop_quit.argtypes = [ctypes.c_void_p]
    glib_lib.g_timeout_add.restype = ctypes.c_uint
    glib_lib.g_timeout_add.argtypes = [ctypes.c_uint, CALLBACK_TYPE, ctypes.c_void_p]
    DBUS_AVAILABLE = True
except Exception:
    DBUS_AVAILABLE = False

# Configuration paths
HOME_DIR = os.path.expanduser("~")
CONFIG_DIR = os.path.join(HOME_DIR, ".config", "bspwm", "azkia-shell")
STATE_FILE = os.path.join(CONFIG_DIR, "azkia_playlists.json")
ART_CACHE_DIR = "/tmp/azkia_art_cache"
MPV_SOCKET = "/tmp/azkia_mpv.sock"
MPV_LOCK = "/tmp/azkia_mpv.lock"
MPV_ACTION_LOCK = "/tmp/azkia_player_action.lock"

os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(ART_CACHE_DIR, exist_ok=True)

def ensure_daemon_running():
    if not DBUS_AVAILABLE:
        return
    try:
        bus = dbus.SessionBus()
        if not bus.name_has_owner("org.mpris.MediaPlayer2.azkia_audio_player"):
            script_path = os.path.abspath(__file__)
            subprocess.Popen(
                [sys.executable, script_path, "--daemon"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )
    except Exception:
        pass

def get_mpv_pids():
    pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == os.getpid():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                raw = f.read()
        except Exception:
            continue
        args = [p.decode("utf-8", "ignore") for p in raw.split(b"\0") if p]
        if not args or os.path.basename(args[0]) != "mpv":
            continue
        if any(a == f"--input-ipc-server={MPV_SOCKET}" for a in args):
            pids.append(pid)
    return pids

def socket_owner_pid():
    # The filesystem inode of the socket node differs from the socket inode
    # reported in /proc/net/unix and referenced by /proc/<pid>/fd.
    socket_inode = None
    try:
        with open("/proc/net/unix", "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and parts[-1] == MPV_SOCKET:
                    socket_inode = parts[-2]
                    break
    except Exception:
        return None
    if not socket_inode:
        return None

    target = f"socket:[{socket_inode}]"
    for pid in get_mpv_pids():
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except Exception:
            continue
        for fd in fds:
            try:
                link = os.readlink(os.path.join(fd_dir, fd))
            except Exception:
                continue
            if link == target:
                return pid
    return None

def kill_mpv_pids(pids, keep=None):
    for pid in pids:
        if pid == keep:
            continue
        try:
            os.kill(pid, signal.SIGTERM)
        except Exception:
            pass

def wait_mpv_pids_exit(pids, timeout=2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        remaining = [p for p in pids if os.path.exists(f"/proc/{p}")]
        if not remaining:
            return
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except Exception:
                pass

def socket_is_alive():
    if not os.path.exists(MPV_SOCKET):
        return False
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(MPV_SOCKET)
        s.close()
        return True
    except Exception:
        return False

def start_mpv_singleton():
    if not shutil.which("mpv"):
        try:
            subprocess.Popen(["notify-send", "-u", "critical", "-i", "audio-x-generic", "Azkia Audio Player", "Dependency 'mpv' tidak ditemukan. Harap install mpv."])
        except Exception:
            pass
        return False

    lock_fd = os.open(MPV_LOCK, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)

        # Another process may have started mpv while we waited for the lock.
        if socket_is_alive():
            pids = get_mpv_pids()
            if len(pids) > 1:
                # Extra instances are orphaned (their socket was unlinked) and
                # cannot be controlled; keep only the current socket owner.
                owner = socket_owner_pid()
                if owner in pids:
                    kill_mpv_pids(pids, keep=owner)
                    wait_mpv_pids_exit([p for p in pids if p != owner])
                    return True
                kill_mpv_pids(pids)
                wait_mpv_pids_exit(pids)
            else:
                return True

        # No reachable socket: clean up stale/orphaned instances and bind one
        # fresh mpv so exactly one controllable player exists.
        pids = get_mpv_pids()
        if pids or os.path.exists(MPV_SOCKET):
            kill_mpv_pids(pids)
            wait_mpv_pids_exit(pids)
            if os.path.exists(MPV_SOCKET):
                try:
                    os.remove(MPV_SOCKET)
                except Exception:
                    pass

        subprocess.Popen([
            "mpv", "--no-video", "--idle=yes", "--ao=pulse", "--audio-channels=stereo", "--volume=100", "--volume-max=100", "--volume-gain=0", "--replaygain=no", f"--input-ipc-server={MPV_SOCKET}"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        for _ in range(40):
            time.sleep(0.05)
            if socket_is_alive():
                return True
        return socket_is_alive()
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except Exception:
            pass
        try:
            os.close(lock_fd)
        except Exception:
            pass

def send_mpv_command(cmd_arr, auto_start=True):
    if auto_start:
        if not socket_is_alive():
            if not start_mpv_singleton():
                return None
    else:
        if not os.path.exists(MPV_SOCKET):
            return None

    ensure_daemon_running()

    # Retry transient failures (e.g. mpv busy) WITHOUT deleting the socket,
    # otherwise a live mpv gets orphaned and a second one is spawned later.
    for _ in range(4):
        s = None
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.5)
            s.connect(MPV_SOCKET)
            payload = json.dumps({"command": cmd_arr}) + "\n"
            s.sendall(payload.encode("utf-8"))
            data = s.recv(4096)
            s.close()
            if data:
                res = json.loads(data.decode("utf-8").split("\n")[0])
                return res.get("data", None)
            return None
        except Exception:
            if s is not None:
                try:
                    s.close()
                except Exception:
                    pass
            time.sleep(0.05)

    if auto_start and not socket_is_alive():
        # Still unreachable after retries: only then force a clean singleton.
        if start_mpv_singleton():
            return send_mpv_command(cmd_arr, auto_start=False)
    return None

_action_lock_state = threading.local()

def acquire_action_lock():
    depth = getattr(_action_lock_state, "depth", 0)
    if depth == 0:
        fd = os.open(MPV_ACTION_LOCK, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        _action_lock_state.fd = fd
    _action_lock_state.depth = depth + 1

def release_action_lock():
    depth = getattr(_action_lock_state, "depth", 1) - 1
    if depth <= 0:
        fd = getattr(_action_lock_state, "fd", None)
        if fd is not None:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            except Exception:
                pass
            try:
                os.close(fd)
            except Exception:
                pass
        _action_lock_state.fd = None
        depth = 0
    _action_lock_state.depth = depth

def with_action_lock(func):
    def wrapper(*args, **kwargs):
        acquire_action_lock()
        try:
            return func(*args, **kwargs)
        finally:
            release_action_lock()
    return wrapper

def get_audio_metadata(file_path):
    title = os.path.splitext(os.path.basename(file_path))[0]
    artist = "Unknown Artist"
    album = "Unknown Album"
    duration = 0
    art_path = ""

    try:
        import mutagen
        audio = mutagen.File(file_path, easy=True)
        if audio:
            if "title" in audio and audio["title"]:
                title = str(audio["title"][0])
            if "artist" in audio and audio["artist"]:
                artist = str(audio["artist"][0])
            if "album" in audio and audio["album"]:
                album = str(audio["album"][0])
            if hasattr(audio.info, "length"):
                duration = int(audio.info.length)

        # Extract Cover Art
        full_audio = mutagen.File(file_path)
        if full_audio:
            art_data = None
            if hasattr(full_audio, 'tags') and full_audio.tags:
                tags = full_audio.tags
                # ID3 APIC
                for k in tags.keys():
                    if k.startswith('APIC'):
                        art_data = tags[k].data
                        break
                # FLAC Picture
                if not art_data and hasattr(full_audio, 'pictures') and full_audio.pictures:
                    art_data = full_audio.pictures[0].data

            if art_data:
                h = hashlib.md5(file_path.encode('utf-8')).hexdigest()
                cached_art = os.path.join(ART_CACHE_DIR, f"{h}.jpg")
                if not os.path.exists(cached_art):
                    with open(cached_art, 'wb') as img_f:
                        img_f.write(art_data)
                art_path = "file://" + cached_art
    except Exception:
        pass

    if artist == "Unknown Artist" and " - " in title:
        parts = title.split(" - ", 1)
        artist = parts[0].strip()
        title = parts[1].strip()

    mins = duration // 60
    secs = duration % 60
    dur_str = f"{mins:02d}:{secs:02d}" if duration > 0 else "--:--"

    return {
        "title": title,
        "artist": artist,
        "album": album,
        "duration": duration,
        "duration_str": dur_str,
        "path": file_path,
        "filename": os.path.basename(file_path),
        "art": art_path
    }

def load_state():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                content = f.read().strip()
                if content:
                    parsed = json.loads(content)
                    if parsed and "playlists" in parsed and parsed["playlists"]:
                        return parsed
        except Exception:
            pass

    backup_file = STATE_FILE + ".bak"
    if os.path.exists(backup_file):
        try:
            with open(backup_file, "r") as f:
                content = f.read().strip()
                if content:
                    parsed = json.loads(content)
                    if parsed and "playlists" in parsed and parsed["playlists"]:
                        return parsed
        except Exception:
            pass

    # Default State
    state = {
        "active_playlist": "Playlist 1",
        "playlists": {
            "Playlist 1": []
        },
        "current_index": 0,
        "playback_state": "stopped",
        "position": 0,
        "duration": 0,
        "volume": 100,
        "repeat_track": False
    }

    # Initial scan of ~/Music into Playlist 1
    music_dir = os.path.join(HOME_DIR, "Music")
    if os.path.exists(music_dir):
        exts = ("*.mp3", "*.flac", "*.wav", "*.m4a", "*.ogg", "*.opus")
        files = []
        for ext in exts:
            files.extend(glob.glob(os.path.join(music_dir, "**", ext), recursive=True))
        files = sorted(list(set(files)))[:50] # initial batch
        for f in files:
            state["playlists"]["Playlist 1"].append(get_audio_metadata(f))

    save_state(state)
    return state

def save_state(state):
    try:
        tmp_file = STATE_FILE + ".tmp"
        with open(tmp_file, "w") as f:
            json.dump(state, f, indent=2)
        os.replace(tmp_file, STATE_FILE)

        backup_file = STATE_FILE + ".bak"
        tmp_bak = backup_file + ".tmp"
        with open(tmp_bak, "w") as f:
            json.dump(state, f, indent=2)
        os.replace(tmp_bak, backup_file)
    except Exception:
        pass

def get_system_volume():
    try:
        res = subprocess.check_output(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], text=True, stderr=subprocess.DEVNULL)
        parts = res.strip().split()
        if len(parts) >= 2 and parts[0] == "Volume:":
            vol_float = float(parts[1])
            return int(round(vol_float * 100))
    except Exception:
        pass
    try:
        res = subprocess.check_output(["pamixer", "--get-volume"], text=True, stderr=subprocess.DEVNULL)
        return int(res.strip())
    except Exception:
        pass
    return 100

def apply_effective_volume(state):
    send_mpv_command(["set_property", "volume-max", 100], auto_start=False)
    send_mpv_command(["set_property", "volume-gain", 0], auto_start=False)
    send_mpv_command(["set_property", "volume", 100], auto_start=False)
    return 100

def sync_mpv_state(state):
    if not os.path.exists(MPV_SOCKET):
        if state.get("playback_state") == "playing":
            state["playback_state"] = "paused"
            save_state(state)
        return state

    pos = send_mpv_command(["get_property", "time-pos"], auto_start=False)
    dur = send_mpv_command(["get_property", "duration"], auto_start=False)
    paused = send_mpv_command(["get_property", "pause"], auto_start=False)
    idle = send_mpv_command(["get_property", "idle-active"], auto_start=False)
    eof = send_mpv_command(["get_property", "eof-reached"], auto_start=False)

    if pos is not None and isinstance(pos, (int, float)):
        state["position"] = float(pos)
    if dur is not None and isinstance(dur, (int, float)):
        state["duration"] = float(dur)

    was_playing = state.get("playback_state") == "playing"
    repeat_tr = state.get("repeat_track", False)

    # Auto next track handling when track finishes and repeat is OFF
    is_finished = (eof is True) or (idle is True and was_playing and paused is not True)

    if is_finished and was_playing and not repeat_tr:
        next_track(state)
        save_state(state)
        return state

    if idle:
        state["playback_state"] = "stopped"
    elif paused is True:
        state["playback_state"] = "paused"
    elif paused is False:
        state["playback_state"] = "playing"

    if repeat_tr:
        send_mpv_command(["set_property", "loop-file", "inf"], auto_start=False)
    else:
        send_mpv_command(["set_property", "loop-file", "no"], auto_start=False)

    save_state(state)
    return state



def pause_other_mpris_players():
    if not DBUS_AVAILABLE:
        return
    try:
        bus = dbus.SessionBus()
        for name in bus.list_names():
            if name.startswith("org.mpris.MediaPlayer2.") and name != "org.mpris.MediaPlayer2.azkia_audio_player":
                try:
                    player_obj = bus.get_object(name, "/org/mpris/MediaPlayer2")
                    player_iface = dbus.Interface(player_obj, "org.mpris.MediaPlayer2.Player")
                    player_iface.Pause()
                except Exception:
                    pass
    except Exception:
        pass


@with_action_lock
def play_track(state, playlist_name, index, start_pos=None):
    playlists = state.get("playlists", {})
    if playlist_name not in playlists or not playlists[playlist_name]:
        for p_name, p_tracks in playlists.items():
            if p_tracks:
                playlist_name = p_name
                break

    if playlist_name not in playlists:
        return

    tracks = playlists[playlist_name]
    if not tracks:
        return

    if index < 0 or index >= len(tracks):
        index = 0

    track = tracks[index]
    path = track.get("path")
    if not path or not os.path.exists(path):
        return

    pause_other_mpris_players()

    pos_to_use = start_pos if (start_pos is not None and start_pos > 0) else 0

    state["now_playing_playlist"] = playlist_name
    state["now_playing_index"] = index
    state["active_playlist"] = playlist_name
    state["current_index"] = index
    state["playback_state"] = "playing"
    state["position"] = pos_to_use
    state["duration"] = track.get("duration", 0)

    if pos_to_use > 0:
        send_mpv_command(["loadfile", path, "replace", -1, f"start={pos_to_use}"])
    else:
        send_mpv_command(["loadfile", path, "replace"])

    send_mpv_command(["set_property", "pause", False])
    apply_effective_volume(state)
    repeat_tr = state.get("repeat_track", False)
    send_mpv_command(["set_property", "loop-file", "inf" if repeat_tr else "no"])
    save_state(state)


def toggle_play(state):
    if not os.path.exists(MPV_SOCKET):
        playlist_name = state.get("now_playing_playlist") or state.get("active_playlist", "Playlist 1")
        idx = state.get("now_playing_index", state.get("current_index", 0))
        saved_pos = state.get("position", 0)
        play_track(state, playlist_name, idx, start_pos=saved_pos)
        return

    idle = send_mpv_command(["get_property", "idle-active"], auto_start=False)
    paused = send_mpv_command(["get_property", "pause"], auto_start=False)
    path = send_mpv_command(["get_property", "path"], auto_start=False)

    if idle is True or not path or paused is None:
        playlist_name = state.get("now_playing_playlist") or state.get("active_playlist", "Playlist 1")
        idx = state.get("now_playing_index", state.get("current_index", 0))
        saved_pos = state.get("position", 0)
        play_track(state, playlist_name, idx, start_pos=saved_pos)
    elif paused is True:
        pause_other_mpris_players()
        send_mpv_command(["set_property", "pause", False])
        state["playback_state"] = "playing"
        save_state(state)
    else:
        send_mpv_command(["set_property", "pause", True])
        state["playback_state"] = "paused"
        save_state(state)


@with_action_lock
def next_track(state):
    pl = state.get("now_playing_playlist") or state.get("active_playlist", "Playlist 1")
    tracks = state.get("playlists", {}).get(pl, [])
    if not tracks:
        return
    curr = state.get("now_playing_index", state.get("current_index", 0))
    idx = (curr + 1) % len(tracks)
    play_track(state, pl, idx)

@with_action_lock
def prev_track(state):
    pl = state.get("now_playing_playlist") or state.get("active_playlist", "Playlist 1")
    tracks = state.get("playlists", {}).get(pl, [])
    if not tracks:
        return
    curr = state.get("now_playing_index", state.get("current_index", 0))
    idx = (curr - 1 + len(tracks)) % len(tracks)
    play_track(state, pl, idx)

def import_audio_files(state, playlist_name):
    script = os.path.join(os.path.dirname(__file__), "select_file.py")
    res = subprocess.run(
        [sys.executable, script, "--multiple", "Select Audio Files to Import"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    filenames = []
    if res.returncode == 0 and res.stdout.strip():
        filenames = [line.strip() for line in res.stdout.strip().split("\n") if line.strip()]

    if filenames:
        if playlist_name not in state["playlists"]:
            state["playlists"][playlist_name] = []
        for f in filenames:
            meta = get_audio_metadata(f)
            state["playlists"][playlist_name].append(meta)
        save_state(state)

def import_audio_dir(state, playlist_name):
    script = os.path.join(os.path.dirname(__file__), "select_file.py")
    res = subprocess.run(
        [sys.executable, script, "--dir", "Select Folder with Audio Files"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    folder = res.stdout.strip() if res.returncode == 0 and res.stdout.strip() else None

    if folder and os.path.exists(folder):
        if playlist_name not in state["playlists"]:
            state["playlists"][playlist_name] = []
        exts = ("*.mp3", "*.flac", "*.wav", "*.m4a", "*.ogg", "*.opus")
        files = []
        for ext in exts:
            files.extend(glob.glob(os.path.join(folder, "**", ext), recursive=True))
        files = sorted(list(set(files)))
        for f in files:
            meta = get_audio_metadata(f)
            state["playlists"][playlist_name].append(meta)
        save_state(state)

def add_playlist(state, name):
    if not name:
        return
    if name not in state["playlists"]:
        state["playlists"][name] = []
        state["active_playlist"] = name
        save_state(state)

def rename_playlist(state, old_name, new_name):
    if not new_name or old_name not in state["playlists"]:
        return
    if new_name == old_name:
        return
    new_playlists = {}
    for k, v in state["playlists"].items():
        if k == old_name:
            new_playlists[new_name] = v
        else:
            new_playlists[k] = v
    state["playlists"] = new_playlists
    if state.get("active_playlist") == old_name:
        state["active_playlist"] = new_name
    save_state(state)

def duplicate_playlist(state, name):
    if name not in state["playlists"]:
        return
    tracks = state["playlists"][name]
    new_name = f"{name} Copy"
    counter = 1
    while new_name in state["playlists"]:
        counter += 1
        new_name = f"{name} Copy {counter}"
    import copy
    state["playlists"][new_name] = copy.deepcopy(tracks)
    state["active_playlist"] = new_name
    save_state(state)

def delete_playlist(state, name):
    if name in state["playlists"]:
        if len(state["playlists"]) > 1:
            del state["playlists"][name]
            state["active_playlist"] = list(state["playlists"].keys())[0]
        else:
            state["playlists"][name] = []
        save_state(state)

def remove_track(state, playlist_name, index):
    if playlist_name in state["playlists"]:
        tracks = state["playlists"][playlist_name]
        if 0 <= index < len(tracks):
            tracks.pop(index)
            save_state(state)

if DBUS_AVAILABLE:
    class AzkiaMprisDaemon(dbus.service.Object):
        def __init__(self, bus):
            super().__init__(bus, "/org/mpris/MediaPlayer2")
            self.bus = bus
            self.last_metadata = ()
            self.last_status = ""
            self.last_volume = -1.0
            self.last_loop = ""

        @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
        def Get(self, interface_name, property_name):
            return self.GetAll(interface_name).get(property_name, "")

        @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface_name):
            if interface_name == "org.mpris.MediaPlayer2":
                return {
                    "CanQuit": dbus.Boolean(True, variant_level=1),
                    "CanRaise": dbus.Boolean(False, variant_level=1),
                    "HasTrackList": dbus.Boolean(False, variant_level=1),
                    "Identity": dbus.String("Azkia Audio Player", variant_level=1),
                    "DesktopEntry": dbus.String("azkia-audio-player", variant_level=1),
                    "SupportedUriSchemes": dbus.Array(["file"], signature="s", variant_level=1),
                    "SupportedMimeTypes": dbus.Array(["audio/mpeg", "audio/flac", "audio/wav", "audio/ogg", "audio/mp4"], signature="s", variant_level=1),
                }
            elif interface_name == "org.mpris.MediaPlayer2.Player":
                state = load_state()
                return self.get_player_properties(state)
            return {}

        @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv", out_signature="")
        def Set(self, interface_name, property_name, new_value):
            if interface_name == "org.mpris.MediaPlayer2.Player":
                state = load_state()
                if property_name == "Volume":
                    vol = int(float(new_value) * 100)
                    vol = max(0, min(100, vol))
                    state["volume"] = vol
                    apply_effective_volume(state)
                    save_state(state)
                elif property_name == "LoopStatus":
                    new_loop = (new_value == "Track")
                    state["repeat_track"] = new_loop
                    send_mpv_command(["set_property", "loop-file", "inf" if new_loop else "no"])
                    save_state(state)

        @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
        def PropertiesChanged(self, interface_name, changed_properties, invalidated_properties):
            pass

        def get_player_properties(self, state):
            status_map = {
                "playing": "Playing",
                "paused": "Paused",
                "stopped": "Stopped"
            }
            playback_status = status_map.get(state.get("playback_state"), "Stopped")
            repeat_tr = state.get("repeat_track", False)
            loop_status = "Track" if repeat_tr else "None"
            vol = float(state.get("volume", 100)) / 100.0

            now_pl = state.get("now_playing_playlist") or state.get("active_playlist", "Playlist 1")
            tracks = state.get("playlists", {}).get(now_pl, [])
            idx = state.get("now_playing_index", state.get("current_index", 0))

            track = tracks[idx] if (tracks and 0 <= idx < len(tracks)) else {}
            title = track.get("title", "No Media Playing") if track else "No Media Playing"
            artist = track.get("artist", "Unknown Artist") if track else ""
            album = track.get("album", "Unknown Album") if track else ""
            art = track.get("art", "") if track else ""
            duration = track.get("duration", 0) if track else 0
            if not duration:
                duration = state.get("duration", 0)

            metadata = {
                "mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/Track/0", variant_level=1),
                "xesam:title": dbus.String(title, variant_level=1),
                "xesam:artist": dbus.Array([artist] if artist else [], signature="s", variant_level=1),
                "xesam:album": dbus.String(album, variant_level=1),
                "mpris:length": dbus.Int64(int(duration * 1_000_000), variant_level=1),
            }
            if art:
                metadata["mpris:artUrl"] = dbus.String(art, variant_level=1)

            pos_us = int(state.get("position", 0) * 1_000_000)

            return {
                "PlaybackStatus": dbus.String(playback_status, variant_level=1),
                "LoopStatus": dbus.String(loop_status, variant_level=1),
                "Rate": dbus.Double(1.0, variant_level=1),
                "Shuffle": dbus.Boolean(False, variant_level=1),
                "Metadata": dbus.Dictionary(metadata, signature="sv", variant_level=1),
                "Volume": dbus.Double(vol, variant_level=1),
                "Position": dbus.Int64(pos_us, variant_level=1),
                "MinimumRate": dbus.Double(1.0, variant_level=1),
                "MaximumRate": dbus.Double(1.0, variant_level=1),
                "CanGoNext": dbus.Boolean(len(tracks) > 1, variant_level=1),
                "CanGoPrevious": dbus.Boolean(len(tracks) > 1, variant_level=1),
                "CanPlay": dbus.Boolean(bool(tracks), variant_level=1),
                "CanPause": dbus.Boolean(True, variant_level=1),
                "CanSeek": dbus.Boolean(True, variant_level=1),
                "CanControl": dbus.Boolean(True, variant_level=1),
            }

        # --- MPRIS 2 Player Methods ---
        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Next(self):
            state = load_state()
            next_track(state)

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Previous(self):
            state = load_state()
            prev_track(state)

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Pause(self):
            send_mpv_command(["set_property", "pause", True])
            state = load_state()
            state["playback_state"] = "paused"
            save_state(state)

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def PlayPause(self):
            state = load_state()
            toggle_play(state)

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Stop(self):
            send_mpv_command(["stop"])
            state = load_state()
            state["playback_state"] = "stopped"
            state["position"] = 0
            save_state(state)

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Play(self):
            state = load_state()
            if state.get("playback_state") == "stopped":
                toggle_play(state)
            else:
                send_mpv_command(["set_property", "pause", False])
                state["playback_state"] = "playing"
                save_state(state)

        @dbus.service.method("org.mpris.MediaPlayer2.Player", in_signature="x")
        def Seek(self, Offset):
            offset_secs = float(Offset) / 1_000_000.0
            send_mpv_command(["seek", offset_secs, "relative"])
            state = load_state()
            pos = send_mpv_command(["get_property", "time-pos"])
            if pos is not None:
                state["position"] = float(pos)
                save_state(state)

        @dbus.service.method("org.mpris.MediaPlayer2.Player", in_signature="ox")
        def SetPosition(self, TrackId, Position):
            target_secs = float(Position) / 1_000_000.0
            send_mpv_command(["set_property", "time-pos", target_secs])
            state = load_state()
            state["position"] = target_secs
            save_state(state)

        @dbus.service.method("org.mpris.MediaPlayer2.Player", in_signature="s")
        def OpenUri(self, Uri):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2")
        def Raise(self):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2")
        def Quit(self):
            send_mpv_command(["quit"])
            if os.path.exists(MPV_SOCKET):
                try:
                    os.remove(MPV_SOCKET)
                except Exception:
                    pass
            sys.exit(0)

        def poll_and_notify(self):
            state = load_state()
            state = sync_mpv_state(state)
            props = self.get_player_properties(state)

            changed = {}

            curr_status = str(props["PlaybackStatus"])
            if curr_status != self.last_status:
                changed["PlaybackStatus"] = props["PlaybackStatus"]
                self.last_status = curr_status

            curr_vol = float(props["Volume"])
            if abs(curr_vol - self.last_volume) > 0.001:
                changed["Volume"] = props["Volume"]
                self.last_volume = curr_vol

            curr_loop = str(props["LoopStatus"])
            if curr_loop != self.last_loop:
                changed["LoopStatus"] = props["LoopStatus"]
                self.last_loop = curr_loop

            curr_metadata = props["Metadata"]
            artists = curr_metadata.get("xesam:artist", [])
            artist_str = str(artists[0]) if artists else ""
            meta_tuple = (
                str(curr_metadata.get("xesam:title", "")),
                artist_str,
                str(curr_metadata.get("mpris:artUrl", "")),
                int(curr_metadata.get("mpris:length", 0))
            )
            if meta_tuple != self.last_metadata:
                changed["Metadata"] = curr_metadata
                self.last_metadata = meta_tuple

            if changed:
                self.PropertiesChanged("org.mpris.MediaPlayer2.Player", changed, [])

            return True

def run_daemon():
    if not DBUS_AVAILABLE or not glib_lib:
        sys.exit(1)
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    try:
        bus_name = dbus.service.BusName("org.mpris.MediaPlayer2.azkia_audio_player", bus, do_not_queue=True)
    except Exception:
        sys.exit(0)

    daemon = AzkiaMprisDaemon(bus)
    loop = glib_lib.g_main_loop_new(None, 0)

    def _poll_cb(user_data):
        try:
            daemon.poll_and_notify()
        except Exception:
            pass
        return 1

    cb = CALLBACK_TYPE(_poll_cb)
    glib_lib.g_timeout_add(300, cb, None)
    try:
        glib_lib.g_main_loop_run(loop)
    except KeyboardInterrupt:
        pass

def main():
    state = load_state()
    args = sys.argv[1:]

    if args and args[0] == "--daemon":
        run_daemon()
        return

    ensure_daemon_running()

    if not args or args[0] == "--get-state":
        state = sync_mpv_state(state)
        print(json.dumps(state))

    elif args[0] == "--play-track" and len(args) >= 3:
        pl_name = args[1]
        idx = int(args[2])
        play_track(state, pl_name, idx)
        print(json.dumps(load_state()))

    elif args[0] in ["--toggle-play", "--toggle"]:
        toggle_play(state)
        print(json.dumps(load_state()))

    elif args[0] == "--play":
        pause_other_mpris_players()
        if not os.path.exists(MPV_SOCKET):
            pl = state.get("now_playing_playlist") or state.get("active_playlist", "Playlist 1")
            idx = state.get("now_playing_index", state.get("current_index", 0))
            play_track(state, pl, idx, start_pos=state.get("position", 0))
        else:
            send_mpv_command(["set_property", "pause", False])
            state["playback_state"] = "playing"
            save_state(state)
        print(json.dumps(load_state()))

    elif args[0] == "--pause":
        send_mpv_command(["set_property", "pause", True])
        state["playback_state"] = "paused"
        save_state(state)
        print(json.dumps(load_state()))

    elif args[0] == "--next":
        next_track(state)
        print(json.dumps(load_state()))

    elif args[0] == "--prev":
        prev_track(state)
        print(json.dumps(load_state()))

    elif args[0] == "--import-files":
        pl_name = args[1] if len(args) > 1 else state.get("active_playlist", "Playlist 1")
        import_audio_files(state, pl_name)
        print(json.dumps(load_state()))

    elif args[0] == "--import-dir":
        pl_name = args[1] if len(args) > 1 else state.get("active_playlist", "Playlist 1")
        import_audio_dir(state, pl_name)
        print(json.dumps(load_state()))

    elif args[0] == "--add-playlist" and len(args) >= 2:
        add_playlist(state, args[1])
        print(json.dumps(load_state()))

    elif args[0] == "--rename-playlist" and len(args) >= 3:
        rename_playlist(state, args[1], args[2])
        print(json.dumps(load_state()))

    elif args[0] == "--duplicate-playlist" and len(args) >= 2:
        duplicate_playlist(state, args[1])
        print(json.dumps(load_state()))

    elif args[0] == "--delete-playlist" and len(args) >= 2:
        delete_playlist(state, args[1])
        print(json.dumps(load_state()))

    elif args[0] == "--remove-track" and len(args) >= 3:
        remove_track(state, args[1], int(args[2]))
        print(json.dumps(load_state()))

    elif args[0] == "--set-playlist" and len(args) >= 2:
        state["active_playlist"] = args[1]
        save_state(state)
        print(json.dumps(state))

    elif args[0] == "--seek" and len(args) >= 2:
        secs = float(args[1])
        send_mpv_command(["set_property", "time-pos", secs])
        state["position"] = secs
        save_state(state)
        print(json.dumps(state))

    elif args[0] == "--seek-relative" and len(args) >= 2:
        offset = float(args[1])
        send_mpv_command(["seek", offset, "relative"])
        pos = send_mpv_command(["get_property", "time-pos"])
        if pos is not None:
            state["position"] = float(pos)
        save_state(state)
        print(json.dumps(state))

    elif args[0] == "--stop":
        send_mpv_command(["stop"])
        state["playback_state"] = "stopped"
        state["position"] = 0
        save_state(state)
        print(json.dumps(state))

    elif args[0] in ["--open-files", "--open"] and len(args) >= 2:
        file_paths = args[1:]
        tracks = []
        for fp in file_paths:
            clean_path = fp[7:] if fp.startswith("file://") else fp
            clean_path = os.path.abspath(clean_path)
            if os.path.exists(clean_path):
                tracks.append(get_audio_metadata(clean_path))
        if tracks:
            state["playlists"]["Default"] = tracks
            state["active_playlist"] = "Default"
            state["now_playing_playlist"] = "Default"
            state["now_playing_index"] = 0
            state["current_index"] = 0
            play_track(state, "Default", 0)
            save_state(state)
            try:
                subprocess.Popen(["quickshell", "--path", os.path.expanduser("~/.config/bspwm/azkia-shell"), "ipc", "call", "audioplayer", "open"])
            except Exception:
                pass
        print(json.dumps(state))

    elif args[0] == "--quit" or args[0] == "--close":
        if os.path.exists(MPV_SOCKET):
            pos = send_mpv_command(["get_property", "time-pos"], auto_start=False)
            if pos is not None and isinstance(pos, (int, float)):
                state["position"] = float(pos)
            send_mpv_command(["quit"], auto_start=False)
            if os.path.exists(MPV_SOCKET):
                try:
                    os.remove(MPV_SOCKET)
                except Exception:
                    pass
        state["playback_state"] = "paused"
        if "Default" in state.get("playlists", {}):
            del state["playlists"]["Default"]
            keys = [k for k in state["playlists"].keys() if k != "Default"]
            fallback = keys[0] if keys else "Playlist 1"
            if state.get("active_playlist") == "Default":
                state["active_playlist"] = fallback
            if state.get("now_playing_playlist") == "Default":
                state["now_playing_playlist"] = fallback
                state["now_playing_index"] = 0
                state["current_index"] = 0
        save_state(state)
        print(json.dumps(state))

    elif args[0] == "--set-volume" and len(args) >= 2:
        vol = max(0, min(100, int(float(args[1]))))
        state["volume"] = vol
        apply_effective_volume(state)
        save_state(state)
        print(json.dumps(state))

    elif args[0] == "--toggle-repeat":
        cur = state.get("repeat_track", False)
        new_val = not cur
        state["repeat_track"] = new_val
        send_mpv_command(["set_property", "loop-file", "inf" if new_val else "no"])
        save_state(state)
        print(json.dumps(state))

if __name__ == "__main__":


    main()
