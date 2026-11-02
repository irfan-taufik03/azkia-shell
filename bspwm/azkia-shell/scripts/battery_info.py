#!/usr/bin/env python3
import sys
import subprocess
import json
import re
import os
import glob

THRESHOLD_FILE = os.path.expanduser("~/.config/bspwm/azkia-shell/battery_threshold.json")

def get_conservation_path():
    candidates = [
        "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode",
        "/sys/devices/pci0000:00/0000:00:1f.0/PNP0C09:00/VPC2004:00/conservation_mode",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    matches = glob.glob("/sys/devices/**/conservation_mode", recursive=True)
    if matches and os.path.exists(matches[0]):
        return matches[0]
    return None

def get_conservation_mode():
    path = get_conservation_path()
    if path:
        try:
            with open(path, "r") as f:
                return f.read().strip() == "1"
        except Exception:
            pass
    return False

def set_conservation_mode(enable):
    path = get_conservation_path()
    val = "1" if str(enable).lower() in ["1", "true", "yes", "on"] else "0"
    if path:
        try:
            with open(path, "w") as f:
                f.write(val + "\n")
            return get_battery_info()
        except PermissionError:
            try:
                subprocess.run(["pkexec", "sh", "-c", f"echo {val} > {path}"], capture_output=True)
            except Exception:
                pass
        except Exception:
            pass
    return get_battery_info()

def get_charge_threshold():
    if os.path.exists(THRESHOLD_FILE):
        try:
            with open(THRESHOLD_FILE, "r") as f:
                data = json.load(f)
                return int(data.get("threshold", 100))
        except Exception:
            pass
    if get_conservation_mode():
        return 60
    return 100

def set_charge_threshold(thresh):
    try:
        t = int(thresh)
    except Exception:
        t = 100

    # 1. Hardware EC / Conservation mode (Lenovo IdeaPad)
    path = get_conservation_path()
    if path:
        cons_val = "1" if t == 60 else "0"
        try:
            with open(path, "w") as f:
                f.write(cons_val + "\n")
        except PermissionError:
            try:
                subprocess.run(["pkexec", "sh", "-c", f"echo {cons_val} > {path}"], capture_output=True)
            except Exception:
                pass
        except Exception:
            pass

    # 2. TLP Charge Thresholds
    tlp_bin = subprocess.run(["which", "tlp"], capture_output=True, text=True).stdout.strip()
    if tlp_bin and os.path.exists(tlp_bin):
        try:
            if t == 60:
                subprocess.run(["pkexec", tlp_bin, "setcharge", "55", "60"], capture_output=True)
            elif t == 80:
                subprocess.run(["pkexec", tlp_bin, "setcharge", "75", "80"], capture_output=True)
            else:
                subprocess.run(["pkexec", tlp_bin, "fullcharge"], capture_output=True)
        except Exception:
            pass

    # 3. Save state
    try:
        os.makedirs(os.path.dirname(THRESHOLD_FILE), exist_ok=True)
        with open(THRESHOLD_FILE, "w") as f:
            json.dump({"threshold": t}, f)
    except Exception:
        pass

    return get_battery_info()

def get_power_profile():
    try:
        profile_out = subprocess.run(['powerprofilesctl', 'get'], capture_output=True, text=True).stdout.strip()
        if profile_out and not profile_out.startswith("Traceback"):
            return profile_out
    except Exception:
        pass

    try:
        res = subprocess.run(['busctl', 'get-property', 'net.hadess.PowerProfiles', '/net/hadess/PowerProfiles', 'net.hadess.PowerProfiles', 'ActiveProfile'], capture_output=True, text=True)
        if res.returncode == 0:
            m = re.search(r'"([^"]+)"', res.stdout)
            if m:
                return m.group(1)
    except Exception:
        pass

    try:
        res = subprocess.run(['busctl', 'get-property', 'org.freedesktop.UPower.PowerProfiles', '/org/freedesktop/UPower/PowerProfiles', 'org.freedesktop.UPower.PowerProfiles', 'ActiveProfile'], capture_output=True, text=True)
        if res.returncode == 0:
            m = re.search(r'"([^"]+)"', res.stdout)
            if m:
                return m.group(1)
    except Exception:
        pass

    return 'balanced'

def get_bluetooth_devices_battery():
    devices = []
    seen_macs = set()

    # 1. From bluetoothctl paired devices
    try:
        out_paired = subprocess.run(["bluetoothctl", "devices", "Paired"], capture_output=True, text=True, timeout=1).stdout
        for line in out_paired.strip().split("\n"):
            parts = line.split(maxsplit=2)
            if len(parts) >= 3 and parts[0] == "Device":
                mac = parts[1]
                name = parts[2]
                info = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True, timeout=1).stdout
                if "Connected: yes" in info:
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

                    if battery is None:
                        # try upower
                        up_mac = mac.replace(":", "_")
                        up_out = subprocess.run(["upower", "-i", f"/org/freedesktop/UPower/devices/headphones_dev_{up_mac}"], capture_output=True, text=True, timeout=1).stdout
                        for l in up_out.split("\n"):
                            if "percentage:" in l:
                                m = re.search(r'(\d+)%', l)
                                if m:
                                    battery = int(m.group(1))

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

                    if battery is not None:
                        seen_macs.add(mac)
                        devices.append({
                            "name": name,
                            "mac": mac,
                            "percentage": battery,
                            "icon": icon,
                            "connected": True
                        })
    except Exception:
        pass

    # 2. From upower devices directly (if any missed)
    try:
        up_paths = subprocess.run(["upower", "-e"], capture_output=True, text=True, timeout=1).stdout
        for dev_path in up_paths.strip().split("\n"):
            dev_path = dev_path.strip()
            if any(k in dev_path for k in ["headphone", "headset", "mouse", "keyboard", "gaming", "bluetooth"]):
                up_info = subprocess.run(["upower", "-i", dev_path], capture_output=True, text=True, timeout=1).stdout
                model = "Wireless Device"
                perc = None
                native_path = ""
                for l in up_info.split("\n"):
                    l_str = l.strip()
                    if l_str.startswith("model:"):
                        model = l_str.split(":", 1)[1].strip()
                    elif l_str.startswith("percentage:"):
                        m = re.search(r'(\d+)%', l_str)
                        if m:
                            perc = int(m.group(1))
                    elif l_str.startswith("native-path:"):
                        native_path = l_str.split(":", 1)[1].strip()

                mac_match = re.search(r'dev_([0-9A-Fa-f_]+)', dev_path) or re.search(r'dev_([0-9A-Fa-f_]+)', native_path)
                mac_formatted = mac_match.group(1).replace("_", ":") if mac_match else ""

                if perc is not None and (not mac_formatted or mac_formatted not in seen_macs):
                    if mac_formatted: seen_macs.add(mac_formatted)
                    devices.append({
                        "name": model,
                        "mac": mac_formatted,
                        "percentage": perc,
                        "icon": "󰋋",
                        "connected": True
                    })
    except Exception:
        pass

    return devices

def get_battery_info():
    info = {
        'percentage': 0,
        'state': 'Unknown',
        'health': '100%',
        'energy_full': '0 Wh',
        'energy_design': '0 Wh',
        'voltage': '0 V',
        'technology': 'Li-ion',
        'power_profile': get_power_profile(),
        'has_conservation': get_conservation_path() is not None,
        'conservation_mode': get_conservation_mode(),
        'charge_threshold': get_charge_threshold(),
        'bluetooth_devices': get_bluetooth_devices_battery()
    }

    try:
        upower_path = subprocess.run(['upower', '-e'], capture_output=True, text=True).stdout
        bat_device = ''
        for line in upower_path.split('\n'):
            if 'battery' in line:
                bat_device = line.strip()
                break
        
        if bat_device:
            out = subprocess.run(['upower', '-i', bat_device], capture_output=True, text=True).stdout
            efull = None
            edesign = None
            for line in out.split('\n'):
                line = line.strip()
                if line.startswith('percentage:'):
                    m = re.search(r'(\d+)', line)
                    if m: info['percentage'] = int(m.group(1))
                elif line.startswith('state:'):
                    info['state'] = line.split(':', 1)[1].strip()
                elif line.startswith('capacity:'):
                    cap_val = line.split(':', 1)[1].strip()
                    m = re.search(r'([\d\.]+)', cap_val)
                    if m:
                        info['health'] = f"{round(float(m.group(1)), 1)}%"
                    else:
                        info['health'] = cap_val
                elif line.startswith('energy-full:'):
                    efull_val = line.split(':', 1)[1].strip()
                    info['energy_full'] = efull_val
                    m = re.search(r'([\d\.]+)', efull_val)
                    if m: efull = float(m.group(1))
                elif line.startswith('energy-full-design:'):
                    edesign_val = line.split(':', 1)[1].strip()
                    info['energy_design'] = edesign_val
                    m = re.search(r'([\d\.]+)', edesign_val)
                    if m: edesign = float(m.group(1))
                elif line.startswith('voltage:'):
                    info['voltage'] = line.split(':', 1)[1].strip()
                elif line.startswith('technology:'):
                    info['technology'] = line.split(':', 1)[1].strip()

            if efull and edesign and edesign > 0 and info['health'] == '100%':
                info['health'] = f"{round((efull / edesign) * 100, 1)}%"
    except Exception:
        pass

    return info

def set_profile(profile):
    try:
        res = subprocess.run(['powerprofilesctl', 'set', profile], capture_output=True)
        if res.returncode == 0:
            return get_battery_info()
    except Exception:
        pass

    try:
        res = subprocess.run(['busctl', 'set-property', 'net.hadess.PowerProfiles', '/net/hadess/PowerProfiles', 'net.hadess.PowerProfiles', 'ActiveProfile', 's', profile], capture_output=True)
        if res.returncode == 0:
            return get_battery_info()
    except Exception:
        pass

    try:
        subprocess.run(['busctl', 'set-property', 'org.freedesktop.UPower.PowerProfiles', '/org/freedesktop/UPower/PowerProfiles', 'org.freedesktop.UPower.PowerProfiles', 'ActiveProfile', 's', profile], capture_output=True)
    except Exception:
        pass

    return get_battery_info()

if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--set-profile":
        print(json.dumps(set_profile(sys.argv[2])))
    elif len(sys.argv) > 2 and sys.argv[1] == "--set-conservation":
        print(json.dumps(set_conservation_mode(sys.argv[2])))
    elif len(sys.argv) > 2 and sys.argv[1] == "--set-threshold":
        print(json.dumps(set_charge_threshold(sys.argv[2])))
    else:
        print(json.dumps(get_battery_info()))
