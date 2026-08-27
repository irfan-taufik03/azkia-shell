#!/usr/bin/env python3
import os
import re
import json
import glob
import subprocess

def get_apps():
    running = []
    seen_running = set()
    try:
        wids = subprocess.run(['bspc', 'query', '-N', '-n', '.window'], capture_output=True, text=True).stdout.strip().split()
        for wid in wids:
            if not wid:
                continue
            try:
                xprop_out = subprocess.run(['xprop', '-id', wid, 'WM_CLASS', '_NET_WM_PID', '_NET_WM_NAME'], capture_output=True, text=True).stdout
                cls = ''
                title = ''
                pid = None
                for line in xprop_out.splitlines():
                    if 'WM_CLASS' in line:
                        m = re.findall(r'"([^"]+)"', line)
                        if m:
                            cls = m[-1]
                    elif '_NET_WM_NAME' in line:
                        m = re.search(r'= "(.*)"', line)
                        if m:
                            title = m.group(1)
                    elif '_NET_WM_PID' in line:
                        m = re.search(r'= (\d+)', line)
                        if m:
                            pid = m.group(1)
                
                cmd = ''
                if pid:
                    try:
                        with open(f'/proc/{pid}/cmdline', 'rb') as f:
                            raw = [x.decode('utf-8', errors='ignore') for x in f.read().split(b'\0') if x]
                            if raw:
                                exec_path = raw[0]
                                exec_name = os.path.basename(exec_path)
                                cmd = exec_name
                    except Exception:
                        pass
                if not cmd:
                    cmd = cls.lower()

                key = (cls.lower(), cmd.lower())
                if key not in seen_running and cls:
                    seen_running.add(key)
                    running.append({
                        'name': title if title else cls,
                        'class': cls,
                        'cmd': cmd
                    })
            except Exception:
                pass
    except Exception:
        pass

    def clean_command(cmd_str):
        if not cmd_str:
            return ""
        cmd_str = re.sub(r'%\w', '', cmd_str).strip()
        cmd_str = re.sub(r'\s+--\s*$', '', cmd_str).strip()
        standard_prefixes = ['/usr/bin/', '/bin/', '/usr/local/bin/', '/usr/games/']
        for prefix in standard_prefixes:
            if cmd_str.startswith(prefix):
                cmd_str = cmd_str[len(prefix):]
                break
        return cmd_str

    installed = []
    seen_installed = set()
    desktop_files = glob.glob('/usr/share/applications/*.desktop') + glob.glob(os.path.expanduser('~/.local/share/applications/*.desktop'))
    for df in desktop_files:
        try:
            name = ''
            exec_cmd = ''
            no_display = False
            with open(df, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if line == '[Desktop Entry]':
                        continue
                    if line.startswith('[') and line != '[Desktop Entry]':
                        break
                    if line.startswith('Name=') and not name:
                        name = line.split('=', 1)[1]
                    elif line.startswith('Exec=') and not exec_cmd:
                        exec_cmd = line.split('=', 1)[1]
                    elif line.startswith('NoDisplay=true'):
                        no_display = True
            if name and exec_cmd and not no_display:
                final_cmd = clean_command(exec_cmd)
                cmd_clean = final_cmd.split()[0] if final_cmd else ''
                exec_base = os.path.basename(cmd_clean).lower()
                if exec_base not in seen_installed and final_cmd:
                    seen_installed.add(exec_base)
                    installed.append({
                        'name': name,
                        'cmd': final_cmd
                    })
        except Exception:
            pass

    installed.sort(key=lambda x: x['name'].lower())
    return {'running': running, 'installed': installed}

if __name__ == '__main__':
    print(json.dumps(get_apps()))
