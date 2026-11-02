#!/usr/bin/env python3
import sys
import os
import re
import shutil
import subprocess
import ctypes

class GdkRGBA(ctypes.Structure):
    _fields_ = [
        ('red', ctypes.c_double),
        ('green', ctypes.c_double),
        ('blue', ctypes.c_double),
        ('alpha', ctypes.c_double)
    ]

def parse_color(c):
    if not c:
        return None
    c = c.strip()
    if c.startswith('#'):
        return c
    m = re.match(r'rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)', c, re.I)
    if m:
        r, g, b = int(m.group(1)), int(m.group(2)), int(m.group(3))
        a = float(m.group(4)) if m.group(4) is not None else 1.0
        if a < 0.99:
            alpha_int = int(round(a * 255))
            return f"#{alpha_int:02x}{r:02x}{g:02x}{b:02x}"
        return f"#{r:02x}{g:02x}{b:02x}"
    return c

def run_gtk3_color(title, initial_color):
    try:
        sys.setdlopenflags(os.RTLD_GLOBAL | os.RTLD_NOW)
        gtk = ctypes.CDLL('libgtk-3.so.0')

        gtk.gtk_init.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        gtk.gtk_init.restype = None
        gtk.gtk_init(None, None)

        gtk.gtk_color_chooser_dialog_new.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
        gtk.gtk_color_chooser_dialog_new.restype = ctypes.c_void_p

        gtk.gtk_dialog_run.argtypes = [ctypes.c_void_p]
        gtk.gtk_dialog_run.restype = ctypes.c_int

        gtk.gtk_widget_destroy.argtypes = [ctypes.c_void_p]
        gtk.gtk_widget_destroy.restype = None

        gtk.gtk_color_chooser_get_rgba.argtypes = [ctypes.c_void_p, ctypes.POINTER(GdkRGBA)]
        gtk.gtk_color_chooser_get_rgba.restype = None

        gtk.gtk_color_chooser_set_rgba.argtypes = [ctypes.c_void_p, ctypes.POINTER(GdkRGBA)]
        gtk.gtk_color_chooser_set_rgba.restype = None

        gtk.gtk_color_chooser_set_use_alpha.argtypes = [ctypes.c_void_p, ctypes.c_int]
        gtk.gtk_color_chooser_set_use_alpha.restype = None

        gtk.gdk_rgba_parse.argtypes = [ctypes.POINTER(GdkRGBA), ctypes.c_char_p]
        gtk.gdk_rgba_parse.restype = ctypes.c_int

        gtk.gtk_events_pending.argtypes = []
        gtk.gtk_events_pending.restype = ctypes.c_int

        gtk.gtk_main_iteration.argtypes = []
        gtk.gtk_main_iteration.restype = ctypes.c_int

        dialog = gtk.gtk_color_chooser_dialog_new(title.encode('utf-8'), None)
        gtk.gtk_color_chooser_set_use_alpha(dialog, 1)

        if initial_color:
            rgba = GdkRGBA()
            if gtk.gdk_rgba_parse(ctypes.byref(rgba), initial_color.encode('utf-8')):
                gtk.gtk_color_chooser_set_rgba(dialog, ctypes.byref(rgba))

        response = gtk.gtk_dialog_run(dialog)
        selected_hex = None

        GTK_RESPONSE_OK = -5
        GTK_RESPONSE_ACCEPT = -3

        if response in (GTK_RESPONSE_OK, GTK_RESPONSE_ACCEPT):
            rgba = GdkRGBA()
            gtk.gtk_color_chooser_get_rgba(dialog, ctypes.byref(rgba))
            r = int(rgba.red * 255)
            g = int(rgba.green * 255)
            b = int(rgba.blue * 255)
            a = rgba.alpha
            if a < 0.99:
                alpha_int = int(round(a * 255))
                selected_hex = f"#{alpha_int:02x}{r:02x}{g:02x}{b:02x}"
            else:
                selected_hex = f"#{r:02x}{g:02x}{b:02x}"

        gtk.gtk_widget_destroy(dialog)
        while gtk.gtk_events_pending():
            gtk.gtk_main_iteration()

        if response in (GTK_RESPONSE_OK, GTK_RESPONSE_ACCEPT):
            return (True, selected_hex)
        else:
            return (True, None)
    except Exception:
        return (False, None)

def run_zenity(title, initial_color):
    try:
        cmd = ["zenity", "--color-selection", "--show-palette", f"--title={title}"]
        if initial_color:
            cmd.append(f"--color={initial_color}")
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode == 0:
            return (True, parse_color(res.stdout.strip()) if res.stdout.strip() else None)
        elif res.returncode == 1:
            return (True, None)
    except Exception:
        pass
    return (False, None)

def run_tkinter(title, initial_color):
    try:
        import tkinter as tk
        from tkinter import colorchooser
        root = tk.Tk()
        root.withdraw()
        root.attributes('-topmost', True)
        color = colorchooser.askcolor(color=initial_color, title=title)
        root.destroy()
        if color and color[1]:
            return (True, color[1])
        return (True, None)
    except Exception:
        return (False, None)

def main():
    title = sys.argv[1] if len(sys.argv) > 1 else "Select Color"
    initial_color = sys.argv[2] if len(sys.argv) > 2 else "#ffffff"

    # Priority 1: Native GTK3 Color Dialog
    handled, result = run_gtk3_color(title, initial_color)
    if handled:
        if result:
            print(result)
        return

    # Priority 2: Zenity
    if shutil.which("zenity"):
        handled, result = run_zenity(title, initial_color)
        if handled:
            if result:
                print(result)
            return

    # Priority 3: Tkinter
    handled, result = run_tkinter(title, initial_color)
    if handled and result:
        print(result)
        return

if __name__ == "__main__":
    main()
