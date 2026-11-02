#!/usr/bin/env python3
import sys
import json
import subprocess
import os
import re


STATE_FILE = "/tmp/qs_bt_state.json"
HISTORY_FILE = "/tmp/qs_bt_history.json"

def load_json(path):
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {} if "state" in path else []

def save_json(path, data):
    try:
        with open(path, "w") as f:
            json.dump(data, f)
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

    prev_state = load_json(STATE_FILE)
    history_list = load_json(HISTORY_FILE)
    if not isinstance(history_list, list):
        history_list = []
    history_set = set(history_list)
    curr_state = {}

    for mac, dev in seen.items():
        try:
            info = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True).stdout
            connected = "Connected: yes" in info
            paired = "Paired: yes" in info or dev["paired"]
            trusted = "Trusted: yes" in info

            # Extract battery percentage if available
            battery = None
            for l in info.split("\n"):
                l_str = l.strip()
                if "Battery Percentage:" in l_str:
                    m = re.search(r'\((\d+)\)', l_str) or re.search(r'Battery Percentage:\s*(\d+)', l_str)
                    if m:
                        try:
                            battery = int(m.group(1))
                        except Exception:
                            pass

            # Fallback to upower for battery percentage if not found in bluetoothctl
            if connected and battery is None:
                try:
                    up_mac = mac.replace(":", "_")
                    up_out = subprocess.run(["upower", "-i", f"/org/freedesktop/UPower/devices/headphones_dev_{up_mac}"], capture_output=True, text=True).stdout
                    for l in up_out.split("\n"):
                        if "percentage:" in l:
                            m = re.search(r'(\d+)%', l)
                            if m:
                                battery = int(m.group(1))
                except Exception:
                    pass

            icon = "󰋋"
            if "Icon:" in info:
                for l in info.split("\n"):
                    if l.strip().startswith("Icon:"):
                        icon_type = l.strip().split("Icon:", 1)[1].strip().lower()
                        if "head" in icon_type or "audio" in icon_type or "ear" in icon_type or "sound" in icon_type: icon = "󰋋"
                        elif "mouse" in icon_type: icon = "󰍽"
                        elif "keyboard" in icon_type: icon = "󰌌"
                        elif "gaming" in icon_type or "gamepad" in icon_type: icon = "󰊴"
                        elif "phone" in icon_type: icon = "󰏲"
                        else: icon = "󰋋"

            # If device is connected, paired or trusted, remember it in history
            if connected or paired or trusted:
                history_set.add(mac)

            is_remembered = paired or (mac in history_set) or trusted

            # Ensure paired/remembered devices are trusted so BlueZ auto-connects them when active
            if is_remembered and not trusted:
                subprocess.run(["bluetoothctl", "trust", mac], capture_output=True, text=True)

            dev["connected"] = connected
            dev["paired"] = is_remembered
            dev["battery"] = battery
            dev["icon"] = icon
        except Exception:
            dev["connected"] = False
            dev["paired"] = dev["paired"] or (mac in history_set)
            dev["battery"] = None
            dev["icon"] = "󰋋"

        curr_state[mac] = dev["connected"]

        # If device just became connected automatically or manually, send notification
        if dev["connected"] and not prev_state.get(mac, False):
            subprocess.run(["notify-send", "-a", "Bluetooth", "Bluetooth Connected", f"Connected to {dev['name']}"])

        # If device just became disconnected automatically or manually, send notification
        if not dev["connected"] and prev_state.get(mac, False):
            subprocess.run(["notify-send", "-a", "Bluetooth", "Bluetooth Disconnected", f"Disconnected from {dev['name']}"])

        devices.append(dev)

    # Check for any device that was connected in prev_state but missing from current devices
    for old_mac, was_connected in prev_state.items():
        if was_connected and old_mac not in curr_state:
            curr_state[old_mac] = False
            dev_name = old_mac
            try:
                info = subprocess.run(["bluetoothctl", "info", old_mac], capture_output=True, text=True).stdout
                for line in info.split("\n"):
                    if "Name:" in line:
                        dev_name = line.split("Name:", 1)[1].strip()
            except Exception:
                pass
            subprocess.run(["notify-send", "-a", "Bluetooth", "Bluetooth Disconnected", f"Disconnected from {dev_name}"])

    save_json(STATE_FILE, curr_state)
    save_json(HISTORY_FILE, list(history_set))

    # Sort: Connected first, Paired second (pinned), Unpaired last
    devices.sort(key=lambda d: (0 if d["connected"] else (1 if d["paired"] else 2), d["name"].lower()))
    print(json.dumps(devices))

def connect_device(mac):
    if not mac:
        return
    # Add to history upon connect attempt
    history_list = load_json(HISTORY_FILE)
    if not isinstance(history_list, list):
        history_list = []
    if mac not in history_list:
        history_list.append(mac)
        save_json(HISTORY_FILE, history_list)

    try:
        info = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True).stdout
        name = mac
        for line in info.split("\n"):
            if "Name:" in line:
                name = line.split("Name:", 1)[1].strip()

        # Trust and connect
        subprocess.run(["bluetoothctl", "trust", mac], capture_output=True, text=True)
        subprocess.run(["bluetoothctl", "connect", mac], capture_output=True, text=True)

        check_info = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True).stdout
        if "Connected: yes" in check_info:
            st = load_json(STATE_FILE)
            st[mac] = True
            save_json(STATE_FILE, st)
            subprocess.run(["notify-send", "-a", "Bluetooth", "Bluetooth Connected", f"Connected to {name}"])
        else:
            subprocess.run(["notify-send", "-a", "Bluetooth", "Connection Failed", f"Failed to connect to {name}"])
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
        st = load_json(STATE_FILE)
        st[mac] = False
        save_json(STATE_FILE, st)
        subprocess.run(["notify-send", "-a", "Bluetooth", "Bluetooth Disconnected", f"Disconnected from {name}"])
    except Exception:
        pass

def remove_device(mac):
    if not mac:
        return
    # Remove from history
    history_list = load_json(HISTORY_FILE)
    if isinstance(history_list, list) and mac in history_list:
        history_list.remove(mac)
        save_json(HISTORY_FILE, history_list)

    try:
        info = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True).stdout
        name = mac
        for line in info.split("\n"):
            if "Name:" in line:
                name = line.split("Name:", 1)[1].strip()

        subprocess.run(["bluetoothctl", "remove", mac], capture_output=True, text=True)
        st = load_json(STATE_FILE)
        if mac in st:
            del st[mac]
            save_json(STATE_FILE, st)
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
