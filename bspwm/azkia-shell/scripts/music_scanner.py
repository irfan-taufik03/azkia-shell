#!/usr/bin/env python3
import sys
import os
import json
import subprocess
import glob

def get_audio_metadata(file_path):
    title = os.path.splitext(os.path.basename(file_path))[0]
    artist = "Unknown Artist"
    album = "Unknown Album"
    duration = 0

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
    except Exception:
        pass

    # Heuristic format fallback e.g. "Artist - Title"
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
        "filename": os.path.basename(file_path)
    }

def scan_music_dir(target_dir=None):
    if not target_dir:
        home = os.path.expanduser("~")
        target_dir = os.path.join(home, "Music")

    target_dir = os.path.expanduser(target_dir)

    extensions = ("*.mp3", "*.flac", "*.wav", "*.m4a", "*.ogg", "*.opus", "*.aac", "*.wma")
    audio_files = []

    if os.path.exists(target_dir):
        for ext in extensions:
            # Recursive scan
            audio_files.extend(glob.glob(os.path.join(target_dir, "**", ext), recursive=True))

    audio_files = sorted(list(set(audio_files)))
    tracks = []

    for f in audio_files:
        tracks.append(get_audio_metadata(f))

    print(json.dumps(tracks))

def play_file(file_path):
    if not os.path.exists(file_path):
        print(json.dumps({"error": "File not found"}))
        return

    # Delegate to the managed player so playback stays controllable (one mpv
    # instance via the IPC socket) instead of spawning an uncontrolled process.
    player = os.path.join(os.path.dirname(os.path.abspath(__file__)), "azkia_audio_player.py")
    try:
        subprocess.Popen(
            [sys.executable, player, "--open", file_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        print(json.dumps({"status": "playing", "path": file_path}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))

def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg == "--scan":
            scan_dir = sys.argv[2] if len(sys.argv) > 2 else None
            scan_music_dir(scan_dir)
        elif arg == "--play" and len(sys.argv) > 2:
            play_file(sys.argv[2])
        else:
            scan_music_dir()
    else:
        scan_music_dir()

if __name__ == "__main__":
    main()
