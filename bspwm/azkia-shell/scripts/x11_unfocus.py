#!/usr/bin/env python3
import ctypes
import sys
import subprocess
import os

WID_FILE = "/tmp/qs_active_wid.txt"

def unfocus_all(is_lockscreen=False):
    # Save the currently focused BSPWM window node ONLY if WID_FILE does not exist yet!
    if not os.path.exists(WID_FILE):
        try:
            node = subprocess.run(['bspc', 'query', '-N', '-n', 'focused'], capture_output=True, text=True).stdout.strip()
            if node:
                with open(WID_FILE, 'w') as f:
                    f.write(node)
        except Exception:
            pass

    # Release X11 input focus and raise Lockscreen if requested
    try:
        x11 = ctypes.cdll.LoadLibrary('libX11.so.6')
        display = x11.XOpenDisplay(None)
        if display:
            root = x11.XDefaultRootWindow(display)
            
            if is_lockscreen:
                root_w = x11.XDisplayWidth(display, 0)
                root_h = x11.XDisplayHeight(display, 0)
                atom_pid = x11.XInternAtom(display, b'_NET_WM_PID', True)

                root_return = ctypes.c_ulong()
                parent_return = ctypes.c_ulong()
                children_return = ctypes.POINTER(ctypes.c_ulong)()
                nchildren_return = ctypes.c_uint()

                x11.XQueryTree(display, root, ctypes.byref(root_return), ctypes.byref(parent_return), ctypes.byref(children_return), ctypes.byref(nchildren_return))

                qs_pids = set()
                try:
                    p = subprocess.run(['pgrep', '-x', 'qs'], capture_output=True, text=True)
                    if p.stdout.strip():
                        qs_pids = {int(x) for x in p.stdout.strip().split()}
                except Exception:
                    pass

                for i in range(nchildren_return.value):
                    w = children_return[i]
                    actual_type = ctypes.c_ulong()
                    actual_format = ctypes.c_int()
                    nitems = ctypes.c_ulong()
                    bytes_after = ctypes.c_ulong()
                    prop = ctypes.POINTER(ctypes.c_ulong)()
                    if atom_pid:
                        res = x11.XGetWindowProperty(display, w, atom_pid, 0, 1, False, 6, ctypes.byref(actual_type), ctypes.byref(actual_format), ctypes.byref(nitems), ctypes.byref(bytes_after), ctypes.byref(prop))
                        if res == 0 and prop and nitems.value > 0:
                            w_pid = prop[0]
                            if w_pid in qs_pids:
                                r_win = ctypes.c_ulong()
                                wx = ctypes.c_int()
                                wy = ctypes.c_int()
                                ww = ctypes.c_uint()
                                wh = ctypes.c_uint()
                                bw = ctypes.c_uint()
                                dp = ctypes.c_uint()
                                x11.XGetGeometry(display, w, ctypes.byref(r_win), ctypes.byref(wx), ctypes.byref(wy), ctypes.byref(ww), ctypes.byref(wh), ctypes.byref(bw), ctypes.byref(dp))
                                # Only move/raise if window matches full screen dimensions (Lockscreen)
                                if ww.value >= root_w - 50 and wh.value >= root_h - 50:
                                    x11.XMoveResizeWindow(display, w, 0, 0, ww.value, wh.value)
                                    x11.XRaiseWindow(display, w)
                                    try:
                                        subprocess.run(['xdotool', 'windowraise', str(w)], capture_output=True)
                                    except Exception:
                                        pass

            x11.XSetInputFocus(display, 1, 1, 0)
            x11.XFlush(display)
            x11.XCloseDisplay(display)
    except Exception:
        pass

def restore_focus():
    saved_node = None
    if os.path.exists(WID_FILE):
        try:
            with open(WID_FILE, 'r') as f:
                saved_node = f.read().strip()
            os.remove(WID_FILE)
        except Exception:
            pass

    if saved_node:
        try:
            res = subprocess.run(['bspc', 'node', saved_node, '-f'], capture_output=True)
            if res.returncode != 0:
                subprocess.run(['xdotool', 'windowactivate', saved_node], capture_output=True)
        except Exception:
            pass
    pass

if __name__ == "__main__":
    if len(sys.argv) > 1:
        if sys.argv[1] == "--restore":
            restore_focus()
        elif sys.argv[1] == "--lockscreen":
            unfocus_all(is_lockscreen=True)
        else:
            unfocus_all(is_lockscreen=False)
    else:
        unfocus_all(is_lockscreen=False)
