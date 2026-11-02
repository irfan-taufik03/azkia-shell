#!/usr/bin/env python3
"""
Azkia Shell - Custom Polkit Authentication Agent Daemon
Native PolicyKit D-Bus Agent with Unix domain socket IPC for Azkia Shell QML UI.
"""

import os
import sys
import json
import socket
import select
import signal
import subprocess
import getpass
import pwd

# Ensure LD_PRELOAD does not break GLib / GObject by re-executing if present
if "LD_PRELOAD" in os.environ:
    clean_env = dict(os.environ)
    del clean_env["LD_PRELOAD"]
    os.execvpe(sys.executable, [sys.executable] + sys.argv, clean_env)

UID = os.getuid()
SOCKET_PATH = f"/tmp/azkia_polkit_{UID}.sock"
AGENT_INTERFACE = "org.freedesktop.PolicyKit1.AuthenticationAgent"
AGENT_PATH = "/org/freedesktop/PolicyKit1/AuthenticationAgent"

SHELL_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def get_helper_binary():
    candidates = [
        "/usr/lib/polkit-1/polkit-agent-helper-1",
        "/usr/libexec/polkit-agent-helper-1",
        "/usr/lib64/polkit-1/polkit-agent-helper-1",
    ]
    for c in candidates:
        if os.path.exists(c) and os.access(c, os.X_OK):
            return c
    return "/usr/lib/polkit-1/polkit-agent-helper-1"

def call_qs_ipc(*args):
    """Invoke Quickshell IPC to control PolkitDialog in Azkia Shell."""
    qs_bin = "qs"
    try:
        cmd = [qs_bin, "-p", SHELL_DIR, "ipc", "call", "--", "polkit"] + list(args)
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
    except Exception:
        try:
            cmd = ["quickshell", "-p", SHELL_DIR, "ipc", "call", "--", "polkit"] + list(args)
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
        except Exception:
            pass

def send_client_cmd(payload):
    """Client utility to send JSON payload to the running agent socket."""
    if not os.path.exists(SOCKET_PATH):
        print(json.dumps({"status": "error", "message": "Polkit agent daemon is not running"}))
        sys.exit(1)

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.connect(SOCKET_PATH)
        client.sendall(json.dumps(payload).encode("utf-8") + b"\n")
        response = b""
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            response += chunk
            if b"\n" in chunk:
                break
        print(response.decode("utf-8").strip())
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}))
        sys.exit(1)
    finally:
        client.close()

# ---------------------------------------------------------------------------
# Daemon implementation using dbus and GLib
# ---------------------------------------------------------------------------
class PolkitAgentDaemon:
    def __init__(self):
        import dbus
        import dbus.service
        import dbus.mainloop.glib
        from gi.repository import GLib

        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        self.dbus = dbus
        self.GLib = GLib

        self.system_bus = dbus.SystemBus()
        self.pending_auth = None
        self.helper_bin = get_helper_binary()

        # Stop competing agents like lxpolkit or xfce-polkit if running
        subprocess.run(["pkill", "-x", "lxpolkit"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "-x", "xfce-polkit"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        self.setup_dbus_agent()
        self.setup_socket_listener()
        self.register_with_authority()

    def setup_dbus_agent(self):
        dbus = self.dbus
        daemon = self

        class ExportedAgent(dbus.service.Object):
            @dbus.service.method(
                dbus_interface=AGENT_INTERFACE,
                in_signature="sssa{ss}sa(sa{sv})",
                out_signature="",
                async_callbacks=("dbus_return", "dbus_error")
            )
            def BeginAuthentication(self, action_id, message, icon_name, details, cookie, identities, dbus_return, dbus_error):
                daemon.handle_begin_auth(
                    str(action_id),
                    str(message),
                    str(icon_name),
                    dict(details),
                    str(cookie),
                    list(identities),
                    dbus_return,
                    dbus_error
                )

            @dbus.service.method(
                dbus_interface=AGENT_INTERFACE,
                in_signature="s",
                out_signature=""
            )
            def CancelAuthentication(self, cookie):
                daemon.handle_cancel_auth(str(cookie))

        self.agent_obj = ExportedAgent(self.system_bus, AGENT_PATH)

    def register_with_authority(self):
        # Determine current session ID
        session_id = os.environ.get("XDG_SESSION_ID")
        if not session_id:
            try:
                res = subprocess.run(["loginctl", "show-user", str(UID), "--property=Display"], capture_output=True, text=True)
                if res.returncode == 0 and "Display=" in res.stdout:
                    session_id = res.stdout.strip().split("=")[1].replace("session-", "")
            except Exception:
                pass
        if not session_id:
            session_id = "2"

        authority_obj = self.system_bus.get_object("org.freedesktop.PolicyKit1", "/org/freedesktop/PolicyKit1/Authority")
        self.authority = self.dbus.Interface(authority_obj, "org.freedesktop.PolicyKit1.Authority")

        subject = ("unix-session", {"session-id": session_id})
        self.subject = subject

        try:
            self.authority.RegisterAuthenticationAgent(subject, "en_US.UTF-8", AGENT_PATH)
            sys.stdout.write(f"[+] Azkia Polkit Agent registered on session {session_id}\n")
            sys.stdout.flush()
        except self.dbus.exceptions.DBusException as e:
            sys.stderr.write(f"[-] Failed to register Polkit agent: {e}\n")
            sys.stderr.flush()

    def setup_socket_listener(self):
        if os.path.exists(SOCKET_PATH):
            try:
                os.remove(SOCKET_PATH)
            except Exception:
                pass

        self.server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_sock.bind(SOCKET_PATH)
        os.chmod(SOCKET_PATH, 0o600)
        self.server_sock.listen(5)
        self.server_sock.setblocking(False)

        # Integrate socket reading into GLib MainLoop
        self.GLib.io_add_watch(self.server_sock.fileno(), self.GLib.IO_IN, self.on_socket_ready)

    def on_socket_ready(self, source, condition):
        try:
            conn, _ = self.server_sock.accept()
            conn.settimeout(5.0)
            data = b""
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
                if b"\n" in chunk:
                    break

            if data:
                req = json.loads(data.decode("utf-8").strip())
                res = self.handle_client_request(req)
                conn.sendall(json.dumps(res).encode("utf-8") + b"\n")
            conn.close()
        except Exception as e:
            pass
        return True

    def handle_begin_auth(self, action_id, message, icon_name, details, cookie, identities, ok_cb, err_cb):
        current_user = getpass.getuser()
        target_user = current_user
        
        # Check if current_user is among identities, otherwise pick first valid user
        found_current = False
        valid_users = []
        for ident in identities:
            kind, ident_details = ident
            if kind == "unix-user" and "uid" in ident_details:
                try:
                    u = pwd.getpwuid(int(ident_details["uid"])).pw_name
                    valid_users.append(u)
                    if u == current_user:
                        found_current = True
                except Exception:
                    pass
            elif kind == "unix-group":
                # If wheel group, current user in wheel is valid
                valid_users.append(current_user)
                found_current = True

        if found_current:
            target_user = current_user
        elif valid_users:
            target_user = valid_users[0]

        with open("/tmp/azkia_polkit.log", "a") as f:
            f.write(f"[AUTH] action={action_id} target={target_user} identities={identities}\n")

        # Cancel any previous dangling request if present
        if self.pending_auth and self.pending_auth.get("err"):
            try:
                self.pending_auth["err"](self.dbus.exceptions.DBusException("org.freedesktop.PolicyKit1.Error.Cancelled", "Superseded"))
            except Exception:
                pass

        self.pending_auth = {
            "action_id": action_id,
            "message": message,
            "icon_name": icon_name,
            "details": details,
            "cookie": cookie,
            "user": target_user,
            "ok": ok_cb,
            "err": err_cb
        }

        # Show Azkia Shell Polkit Dialog via IPC
        call_qs_ipc("show", action_id, message, icon_name, cookie, target_user)

    def handle_cancel_auth(self, cookie):
        if self.pending_auth and self.pending_auth.get("cookie") == cookie:
            call_qs_ipc("close")
            if self.pending_auth.get("err"):
                try:
                    self.pending_auth["err"](self.dbus.exceptions.DBusException("org.freedesktop.PolicyKit1.Error.Cancelled", "Cancelled by Polkit daemon"))
                except Exception:
                    pass
            self.pending_auth = None

    def handle_client_request(self, req):
        cmd = req.get("cmd")
        if cmd == "submit":
            password = req.get("password", "")
            return self.process_authentication(password)
        elif cmd == "cancel":
            return self.cancel_active_auth()
        elif cmd == "status":
            return {"status": "ok", "has_pending": self.pending_auth is not None}
        return {"status": "error", "message": f"Unknown command {cmd}"}

    def process_authentication(self, password):
        if not self.pending_auth:
            return {"status": "error", "message": "No authentication in progress"}

        user = self.pending_auth["user"]
        cookie = self.pending_auth["cookie"]

        try:
            pwd_clean = password.rstrip("\r\n") + "\n"
            proc = subprocess.Popen(
                [self.helper_bin, user, cookie],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            stdout, stderr = proc.communicate(input=pwd_clean, timeout=12)

            with open("/tmp/azkia_polkit.log", "a") as f:
                f.write(f"[SUBMIT] user={user} returncode={proc.returncode} stdout={stdout.strip()} stderr={stderr.strip()}\n")

            if proc.returncode == 0:
                # Success!
                call_qs_ipc("success")
                if self.pending_auth.get("ok"):
                    try:
                        self.pending_auth["ok"]()
                    except Exception:
                        pass
                self.pending_auth = None
                return {"status": "success"}
            else:
                # Wrong password or auth error
                call_qs_ipc("fail", "Incorrect password")
                return {"status": "fail", "message": "Authentication failed"}
        except Exception as e:
            with open("/tmp/azkia_polkit.log", "a") as f:
                f.write(f"[ERROR] {e}\n")
            call_qs_ipc("fail", str(e))
            return {"status": "error", "message": str(e)}

    def cancel_active_auth(self):
        if self.pending_auth:
            call_qs_ipc("close")
            if self.pending_auth.get("err"):
                try:
                    self.pending_auth["err"](self.dbus.exceptions.DBusException("org.freedesktop.PolicyKit1.Error.Cancelled", "Cancelled by user"))
                except Exception:
                    pass
            self.pending_auth = None
            return {"status": "cancelled"}
        return {"status": "ok"}

    def run(self):
        loop = self.GLib.MainLoop()

        def on_exit(signum, frame):
            try:
                if hasattr(self, "authority") and hasattr(self, "subject"):
                    self.authority.UnregisterAuthenticationAgent(self.subject, AGENT_PATH)
            except Exception:
                pass
            if os.path.exists(SOCKET_PATH):
                try:
                    os.remove(SOCKET_PATH)
                except Exception:
                    pass
            loop.quit()
            sys.exit(0)

        signal.signal(signal.SIGINT, on_exit)
        signal.signal(signal.SIGTERM, on_exit)

        loop.run()

# ---------------------------------------------------------------------------
# Main Entry Point
# ---------------------------------------------------------------------------
def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg == "--submit":
            pwd_input = sys.argv[2] if len(sys.argv) > 2 else ""
            send_client_cmd({"cmd": "submit", "password": pwd_input})
        elif arg == "--cancel":
            send_client_cmd({"cmd": "cancel"})
        elif arg == "--status":
            send_client_cmd({"cmd": "status"})
        elif arg == "--daemon":
            daemon = PolkitAgentDaemon()
            daemon.run()
        else:
            print("Usage: polkit_agent.py [--daemon|--submit <pwd>|--cancel|--status]")
    else:
        # Default behavior: run as daemon
        daemon = PolkitAgentDaemon()
        daemon.run()

if __name__ == "__main__":
    main()
