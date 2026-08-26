#!/usr/bin/env python3
import sys
import subprocess
import json
import re

def get_battery_info():
    info = {
        'percentage': 0,
        'state': 'Unknown',
        'health': '100%',
        'energy_full': '0 Wh',
        'energy_design': '0 Wh',
        'voltage': '0 V',
        'technology': 'Li-ion',
        'power_profile': 'balanced'
    }
    
    try:
        profile_out = subprocess.run(['powerprofilesctl', 'get'], capture_output=True, text=True).stdout.strip()
        if profile_out:
            info['power_profile'] = profile_out
    except Exception:
        pass

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
        subprocess.run(['powerprofilesctl', 'set', profile], check=True)
    except Exception:
        pass
    return get_battery_info()

if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--set-profile":
        print(json.dumps(set_profile(sys.argv[2])))
    else:
        print(json.dumps(get_battery_info()))
