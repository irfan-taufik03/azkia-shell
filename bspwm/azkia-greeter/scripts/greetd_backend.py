#!/usr/bin/env python3
import os
import sys
import json
import socket
import struct
import getpass
import subprocess
import glob

def get_installed_sessions():
    sessions = []
    seen = set()

    # Scan X11 sessions
    for path in glob.glob("/usr/share/xsessions/*.desktop"):
        try:
            name, exec_cmd, comment = parse_desktop_file(path)
            if name and name.lower() not in seen:
                seen.add(name.lower())
                sessions.append({
                    "id": name.lower(),
                    "name": name,
                    "exec": exec_cmd,
                    "type": "x11",
                    "icon": get_session_icon(name)
                })
        except Exception:
            pass

    # Scan Wayland sessions
    for path in glob.glob("/usr/share/wayland-sessions/*.desktop"):
        try:
            name, exec_cmd, comment = parse_desktop_file(path)
            if name and name.lower() not in seen:
                seen.add(name.lower())
                sessions.append({
                    "id": name.lower(),
                    "name": name,
                    "exec": exec_cmd,
                    "type": "wayland",
                    "icon": get_session_icon(name)
                })
        except Exception:
            pass

    # Ensure bspwm is prioritized if present
    sessions.sort(key=lambda s: (0 if "bspwm" in s["name"].lower() else 1, s["name"].lower()))
    return sessions

def parse_desktop_file(filepath):
    name = ""
    exec_cmd = ""
    comment = ""
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        in_entry = False
        for line in f:
            line = line.strip()
            if line == "[Desktop Entry]":
                in_entry = True
                continue
            elif line.startswith("[") and in_entry:
                break
            if in_entry and "=" in line:
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip()
                if k == "Name" and not name:
                    name = v
                elif k == "Exec" and not exec_cmd:
                    exec_cmd = v
                elif k == "Comment" and not comment:
                    comment = v
    return name, exec_cmd, comment

def get_session_icon(name):
    low = name.lower()
    if "bspwm" in low:
        return "󰖲"
    elif "hyprland" in low:
        return "󰨡"
    elif "xfce" in low:
        return "󰣆"
    elif "gnome" in low:
        return "󰍹"
    elif "sway" in low:
        return "󰨡"
    elif "kde" in low or "plasma" in low:
        return "󰌧"
    elif "i3" in low:
        return "󰖲"
    return "󰍹"

class GreetdClient:
    def __init__(self):
        self.sock_path = os.environ.get("GREETD_SOCK")
        self.sock = None
        if self.sock_path and os.path.exists(self.sock_path):
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.settimeout(5.0)
                self.sock.connect(self.sock_path)
            except Exception:
                self.sock = None

    def _send(self, payload):
        if not self.sock:
            return None
        data = json.dumps(payload).encode("utf-8")
        header = struct.pack("=I", len(data))
        self.sock.sendall(header + data)

    def _recv(self):
        if not self.sock:
            return None
        header = self.sock.recv(4)
        if not header:
            return None
        length = struct.unpack("=I", header)[0]
        data = b""
        while len(data) < length:
            chunk = self.sock.recv(length - len(data))
            if not chunk:
                break
            data += chunk
        return json.loads(data.decode("utf-8"))

    def login(self, username, password, cmd, session_type=None, desktop_name=None):
        if not self.sock:
            # Standalone / Preview Mode: check via unix_chkpwd or PAM
            if check_local_auth(username, password):
                return {"status": "success", "mode": "preview", "message": "Preview Mode Auth OK"}
            else:
                return {"status": "error", "message": "Authentication failed"}

        try:
            # 1. Create session
            self._send({"type": "create_session", "username": username})
            res = self._recv()
            if not res or res.get("type") == "error":
                return {"status": "error", "message": res.get("description", "Failed to create session")}

            # 2. Handle authentication messages until success or error
            while res and res.get("type") == "auth_message":
                msg_type = res.get("auth_message_type", "secret")
                if msg_type in ["secret", "visible"]:
                    self._send({"type": "post_auth_message_response", "response": password})
                else:
                    self._send({"type": "post_auth_message_response"})
                res = self._recv()

            if not res or res.get("type") != "success":
                err_msg = res.get("description", "Incorrect password") if res else "Authentication failed"
                return {"status": "error", "message": err_msg}

            # 3. Detect session type and desktop name if not explicitly provided
            raw_cmd = cmd if isinstance(cmd, list) else cmd.split()
            cmd_str = " ".join(raw_cmd).lower() if isinstance(raw_cmd, list) else str(cmd).lower()

            if not session_type:
                if any(w in cmd_str for w in ["hyprland", "wayland", "sway", "river", "niri", "labwc"]):
                    session_type = "wayland"
                else:
                    session_type = "x11"

            if not desktop_name:
                if "bspwm" in cmd_str:
                    desktop_name = "bspwm"
                elif "hyprland" in cmd_str:
                    desktop_name = "Hyprland"
                elif "xfce" in cmd_str:
                    desktop_name = "XFCE"
                else:
                    desktop_name = "bspwm" if session_type == "x11" else "Wayland"

            # 4. Construct command line
            scripts_dir = os.path.dirname(os.path.abspath(__file__))
            wrapper_script = os.path.join(scripts_dir, "xsession_wrapper.sh")

            if session_type == "x11":
                # X11 window managers (bspwm, etc.) require an active Xorg server
                startx_bin = "/usr/bin/startx"
                if os.path.exists(startx_bin):
                    if os.path.exists(wrapper_script):
                        command_list = [startx_bin, wrapper_script] + raw_cmd
                    else:
                        command_list = [startx_bin, "/usr/bin/env"] + raw_cmd
                else:
                    command_list = raw_cmd
            else:
                # Wayland compositors (Hyprland, etc.) initialize KMS/DRM natively
                command_list = raw_cmd

            env = [
                f"XDG_SESSION_TYPE={session_type}",
                f"XDG_CURRENT_DESKTOP={desktop_name}",
                f"DESKTOP_SESSION={desktop_name.lower()}",
                f"XDG_SESSION_DESKTOP={desktop_name.lower()}"
            ]

            payload = {
                "type": "start_session",
                "cmd": command_list,
                "env": env
            }
            self._send(payload)
            res = self._recv()
            if not res or res.get("type") == "error":
                # Fallback without optional 'env' in case of strict/legacy greetd
                self._send({"type": "start_session", "cmd": command_list})
                res = self._recv()

            if res and res.get("type") == "success":
                return {"status": "success", "mode": "greetd"}
            else:
                return {"status": "error", "message": res.get("description", "Failed to start session")}
        except Exception as e:
            return {"status": "error", "message": str(e)}

def check_local_auth(username, password):
    if not password:
        return False
    if not username:
        username = getpass.getuser()

    for chk in ["/usr/sbin/unix_chkpwd", "/sbin/unix_chkpwd", "unix_chkpwd"]:
        try:
            proc = subprocess.Popen([chk, username, "nullok"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            proc.communicate(input=(password + "\0").encode())
            if proc.returncode == 0:
                return True
        except Exception:
            pass

    try:
        import pam
        p = pam.pam()
        if p.authenticate(username, password):
            return True
    except Exception:
        pass

    return False

from datetime import datetime

def do_power_action(action):
    action = (action or "").lower().strip()
    cmds = []
    if action in ("poweroff", "shutdown"):
        cmds = [
            ["systemctl", "poweroff", "-i", "--no-ask-password"],
            ["systemctl", "poweroff"],
            ["loginctl", "poweroff", "--no-ask-password"],
            ["loginctl", "poweroff"],
            ["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PowerOff", "b", "false"],
            ["dbus-send", "--system", "--print-reply", "--dest=org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager.PowerOff", "boolean:false"],
            ["sudo", "-n", "systemctl", "poweroff", "-i"],
            ["sudo", "-n", "poweroff"],
        ]
    elif action in ("reboot", "restart"):
        cmds = [
            ["systemctl", "reboot", "-i", "--no-ask-password"],
            ["systemctl", "reboot"],
            ["loginctl", "reboot", "--no-ask-password"],
            ["loginctl", "reboot"],
            ["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "Reboot", "b", "false"],
            ["dbus-send", "--system", "--print-reply", "--dest=org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager.Reboot", "boolean:false"],
            ["sudo", "-n", "systemctl", "reboot", "-i"],
            ["sudo", "-n", "reboot"],
        ]
    elif action in ("suspend", "sleep"):
        cmds = [
            ["systemctl", "suspend", "-i", "--no-ask-password"],
            ["systemctl", "suspend"],
            ["loginctl", "suspend", "--no-ask-password"],
            ["loginctl", "suspend"],
            ["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "Suspend", "b", "false"],
            ["dbus-send", "--system", "--print-reply", "--dest=org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager.Suspend", "boolean:false"],
            ["sudo", "-n", "systemctl", "suspend", "-i"],
        ]
    else:
        return {"status": "error", "message": f"Unknown power action: {action}"}

    try:
        with open("/tmp/azkia_greeter_power.log", "a") as f:
            f.write(f"[{datetime.now()}] Action requested: {action}\n")
    except Exception:
        pass

    errors = []
    for c in cmds:
        try:
            res = subprocess.run(c, capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                try:
                    with open("/tmp/azkia_greeter_power.log", "a") as f:
                        f.write(f"[{datetime.now()}] Success with: {' '.join(c)}\n")
                except Exception:
                    pass
                return {"status": "success", "action": action, "cmd": c[0]}
            err = res.stderr.strip() if res.stderr else res.stdout.strip()
            if err:
                errors.append(f"{c[0]}: {err}")
        except Exception as e:
            errors.append(f"{c[0]}: {str(e)}")

    err_msg = "; ".join(errors[:2]) if errors else f"Failed to execute power action: {action}"
    try:
        with open("/tmp/azkia_greeter_power.log", "a") as f:
            f.write(f"[{datetime.now()}] Error: {err_msg}\n")
    except Exception:
        pass
    return {"status": "error", "message": err_msg}

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--sessions":
        sessions = get_installed_sessions()
        print(json.dumps(sessions))
    elif len(sys.argv) > 1 and sys.argv[1] == "--power":
        # Args: --power <action: poweroff|reboot|suspend>
        action = sys.argv[2] if len(sys.argv) > 2 else "poweroff"
        res = do_power_action(action)
        print(json.dumps(res))
    elif len(sys.argv) > 1 and sys.argv[1] == "--login":
        # Args: --login <username> <password> <exec_command> [session_type] [desktop_name]
        user = sys.argv[2] if len(sys.argv) > 2 else getpass.getuser()
        pwd = sys.argv[3] if len(sys.argv) > 3 else ""
        cmd = sys.argv[4] if len(sys.argv) > 4 else "bspwm"
        session_type = sys.argv[5] if len(sys.argv) > 5 else None
        desktop_name = sys.argv[6] if len(sys.argv) > 6 else None
        client = GreetdClient()
        result = client.login(user, pwd, cmd, session_type, desktop_name)
        print(json.dumps(result))
    else:
        print(json.dumps({"error": "Unknown command"}))
