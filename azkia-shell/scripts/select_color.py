#!/usr/bin/env python3
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk

def main():
    title = sys.argv[1] if len(sys.argv) > 1 else "Select Color"
    initial_color = sys.argv[2] if len(sys.argv) > 2 else "#ffffff"

    dialog = Gtk.ColorChooserDialog(title=title)
    dialog.set_use_alpha(True)
    dialog.set_property("show-editor", True)

    if initial_color:
        rgba = Gdk.RGBA()
        if rgba.parse(initial_color):
            dialog.set_rgba(rgba)

    response = dialog.run()
    if response == Gtk.ResponseType.OK or response == int(Gtk.ResponseType.OK):
        rgba = dialog.get_rgba()
        r = int(rgba.red * 255)
        g = int(rgba.green * 255)
        b = int(rgba.blue * 255)
        a = rgba.alpha
        if a < 0.99:
            alpha_int = int(a * 255)
            print(f"#{alpha_int:02x}{r:02x}{g:02x}{b:02x}")
        else:
            print(f"#{r:02x}{g:02x}{b:02x}")

    dialog.destroy()

if __name__ == "__main__":
    main()
