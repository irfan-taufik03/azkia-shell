#!/usr/bin/env python3
import sys
import os
import re
import json
import glob
import subprocess
import threading
import queue
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk

def get_window_info(win_id):
    if not win_id or win_id == '0x0':
        return {'title': '', 'class': '', 'icon': ''}
    
    title = ''
    app_class = ''
    
    try:
        out = subprocess.run(['xprop', '-id', win_id, '_NET_WM_NAME', 'WM_NAME', 'WM_CLASS'], capture_output=True, text=True).stdout
        for line in out.split('\n'):
            if ('_NET_WM_NAME' in line or 'WM_NAME' in line) and not title:
                m = re.search(r'=\s*"(.*)"', line)
                if m:
                    title = m.group(1).replace('\\"', '"').replace('\\\\', '\\')
            elif 'WM_CLASS' in line and not app_class:
                matches = re.findall(r'"([^"]+)"', line)
                if matches:
                    app_class = matches[-1]
    except Exception:
        pass

    icon_path = ''
    if app_class:
        app_class_lower = app_class.lower()
        icon_name = app_class_lower

        desktop_files = glob.glob('/usr/share/applications/*.desktop') + glob.glob(os.path.expanduser('~/.local/share/applications/*.desktop'))
        for df in desktop_files:
            try:
                with open(df, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    if f'StartupWMClass={app_class}' in content or f'StartupWMClass={app_class_lower}' in content or app_class_lower in os.path.basename(df).lower():
                        for line in content.split('\n'):
                            if line.startswith('Icon='):
                                icon_name = line.split('=', 1)[1].strip()
                                break
                        break
            except Exception:
                pass

        theme = Gtk.IconTheme.get_default()
        icon_info = theme.lookup_icon(icon_name, 48, 0)
        if not icon_info and icon_name != app_class_lower:
            icon_info = theme.lookup_icon(app_class_lower, 48, 0)
        if icon_info:
            icon_path = icon_info.get_filename()

    return {'title': title, 'class': app_class, 'icon': icon_path}

def spy():
    root_cmd = ['stdbuf', '-oL', 'xprop', '-spy', '-root', '_NET_ACTIVE_WINDOW']
    root_proc = subprocess.Popen(root_cmd, stdout=subprocess.PIPE, text=True, bufsize=1)
    out_q = queue.Queue()

    def read_root():
        for line in iter(root_proc.stdout.readline, ''):
            m = re.search(r'window id # (0x[0-9a-fA-F]+)', line)
            win_id = m.group(1) if m else '0x0'
            out_q.put(('root', win_id))

    threading.Thread(target=read_root, daemon=True).start()

    current_win_id = None
    win_proc = None
    cached_info = {'title': '', 'class': '', 'icon': ''}

    def stop_win_proc():
        nonlocal win_proc
        if win_proc:
            try:
                win_proc.terminate()
                win_proc.wait(timeout=0.2)
            except Exception:
                pass
            win_proc = None

    while True:
        try:
            ev, val = out_q.get()
            if ev == 'root':
                win_id = val
                if win_id != current_win_id:
                    stop_win_proc()
                    current_win_id = win_id
                    if win_id and win_id != '0x0':
                        cached_info = get_window_info(win_id)
                        print(json.dumps(cached_info), flush=True)

                        win_cmd = ['stdbuf', '-oL', 'xprop', '-spy', '-id', win_id, '_NET_WM_NAME', 'WM_NAME']
                        win_proc = subprocess.Popen(
                            win_cmd,
                            stdout=subprocess.PIPE,
                            text=True,
                            bufsize=1
                        )

                        def read_win(wid, sub_p):
                            for wline in iter(sub_p.stdout.readline, ''):
                                if '_NET_WM_NAME' in wline or 'WM_NAME' in wline:
                                    m_t = re.search(r'=\s*"(.*)"', wline)
                                    if m_t:
                                        t_str = m_t.group(1).replace('\\"', '"').replace('\\\\', '\\')
                                        out_q.put(('title', (wid, t_str)))

                        threading.Thread(target=read_win, args=(win_id, win_proc), daemon=True).start()
                    else:
                        cached_info = {'title': '', 'class': '', 'icon': ''}
                        print(json.dumps(cached_info), flush=True)

            elif ev == 'title':
                wid, new_title = val
                if wid == current_win_id and new_title and new_title != cached_info.get('title'):
                    cached_info['title'] = new_title
                    print(json.dumps(cached_info), flush=True)
        except Exception:
            pass

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--spy":
        spy()
    elif len(sys.argv) > 1:
        print(json.dumps(get_window_info(sys.argv[1])))
    else:
        print(json.dumps({'title': '', 'class': '', 'icon': ''}))
