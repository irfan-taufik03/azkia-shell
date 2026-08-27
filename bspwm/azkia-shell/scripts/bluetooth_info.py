#!/usr/bin/env python3
import sys
import json
import subprocess
import os

STATE_FILE = "/tmp/qs_bt_state.json"

def load_state():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_state(state):
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception:
        pass

def get_devices():
    devices = []
    seen = {}

    # 1. Get all paired devices first (ensures paired devices are always retrieved and pinned)
    try:
        out_paired = subprocess.run(["bluetoothctl", "devices", "Paired"], capture_output=True, text=True).stdout
        for line in out_paired.strip().split("\n"):
            parts = line.split(maxsplit=2)
            if len(parts) >= 3 and parts[0] == "Device":
                mac = parts[1]
                name = parts[2]
                seen[mac] = {"mac": mac, "name": name, "paired": True}
    except Exception:
        pass

    # 2. Get all devices (including scanned ones)
    try:
        out_all = subprocess.run(["bluetoothctl", "devices"], capture_output=True, text=True).stdout
        for line in out_all.strip().split("\n"):
            parts = line.split(maxsplit=2)
            if len(parts) >= 3 and parts[0] == "Device":
                mac = parts[1]
                name = parts[2]
                if mac not in seen:
                    seen[mac] = {"mac": mac, "name": name, "paired": False}
    except Exception:
        pass

    prev_state = load_state()
    curr_state = {}

    for mac, dev in seen.items():
        try:
            info = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True).stdout
            connected = "Connected: yes" in info
            paired = "Paired: yes" in info or dev["paired"]
            trusted = "Trusted: yes" in info

            # Ensure paired devices are trusted so BlueZ auto-connects them when active
            if paired and not trusted:
                subprocess.run(["bluetoothctl", "trust", mac], capture_output=True, text=True)

            dev["connected"] = connected
            dev["paired"] = paired
        except Exception:
            dev["connected"] = False

        curr_state[mac] = dev["connected"]

        # If device just became connected automatically or manually, send notification
        if dev["connected"] and not prev_state.get(mac, False):
            subprocess.run(["notify-send", "-a", "Bluetooth", "Bluetooth Connected", f"Connected to {dev['name']}"])

        devices.append(dev)

    save_state(curr_state)

    # Sort: Connected first, Paired second (pinned), Unpaired last
    devices.sort(key=lambda d: (0 if d["connected"] else (1 if d["paired"] else 2), d["name"].lower()))
    print(json.dumps(devices))

def connect_device(mac):
    if not mac:
        return
    try:
        info = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True).stdout
        name = mac
        for line in info.split("\n"):
            if "Name:" in line:
                name = line.split("Name:", 1)[1].strip()

        # Trust and connect
        subprocess.run(["bluetoothctl", "trust", mac], capture_output=True, text=True)
        subprocess.run(["bluetoothctl", "connect", mac], capture_output=True, text=True)
        subprocess.run(["notify-send", "-a", "Bluetooth", "Bluetooth Connected", f"Connected to {name}"])
    except Exception:
        pass

def disconnect_device(mac):
    if not mac:
        return
    try:
        info = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True).stdout
        name = mac
        for line in info.split("\n"):
            if "Name:" in line:
                name = line.split("Name:", 1)[1].strip()

        subprocess.run(["bluetoothctl", "disconnect", mac], capture_output=True, text=True)
        subprocess.run(["notify-send", "-a", "Bluetooth", "Bluetooth Disconnected", f"Disconnected from {name}"])
    except Exception:
        pass

def remove_device(mac):
    if not mac:
        return
    try:
        info = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True).stdout
        name = mac
        for line in info.split("\n"):
            if "Name:" in line:
                name = line.split("Name:", 1)[1].strip()

        subprocess.run(["bluetoothctl", "remove", mac], capture_output=True, text=True)
        subprocess.run(["notify-send", "-a", "Bluetooth", "Device Removed", f"Removed {name}"])
    except Exception:
        pass

if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--connect":
        connect_device(sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[1] == "--disconnect":
        disconnect_device(sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[1] == "--remove":
        remove_device(sys.argv[2])
    else:
        get_devices()
