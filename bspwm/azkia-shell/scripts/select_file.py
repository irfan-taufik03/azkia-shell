#!/usr/bin/env python3
import sys
import os
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk

def main():
    args = sys.argv[1:]
    is_dir_mode = False
    if "--dir" in args:
        is_dir_mode = True
        args.remove("--dir")

    title = args[0] if len(args) > 0 else ("Select Directory" if is_dir_mode else "Select Image")

    action = Gtk.FileChooserAction.SELECT_FOLDER if is_dir_mode else Gtk.FileChooserAction.OPEN
    btn_label = "_Select" if is_dir_mode else "_Open"

    try:
        dialog = Gtk.FileChooserNative.new(
            title,
            None,
            action,
            btn_label,
            "_Cancel"
        )
    except Exception:
        dialog = Gtk.FileChooserDialog(
            title=title,
            action=action
        )
        dialog.add_button(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL)
        dialog.add_button(Gtk.STOCK_OPEN, Gtk.ResponseType.ACCEPT)

    if not is_dir_mode:
        # Filter for image files
        filter_img = Gtk.FileFilter()
        filter_img.set_name("Image files (*.png, *.jpg, *.jpeg, *.webp, *.svg)")
        filter_img.add_mime_type("image/png")
        filter_img.add_mime_type("image/jpeg")
        filter_img.add_mime_type("image/webp")
        filter_img.add_mime_type("image/svg+xml")
        filter_img.add_pattern("*.png")
        filter_img.add_pattern("*.jpg")
        filter_img.add_pattern("*.jpeg")
        filter_img.add_pattern("*.webp")
        filter_img.add_pattern("*.svg")
        dialog.add_filter(filter_img)
        
        filter_all = Gtk.FileFilter()
        filter_all.set_name("All files")
        filter_all.add_pattern("*")
        dialog.add_filter(filter_all)

    response = dialog.run()
    if response == Gtk.ResponseType.ACCEPT or response == int(Gtk.ResponseType.ACCEPT):
        filename = dialog.get_filename()
        if filename:
            print(filename.strip())
    
    dialog.destroy()

if __name__ == "__main__":
    main()
