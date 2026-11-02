#!/usr/bin/env python3
import sys
import os
import shutil
import subprocess
import ctypes

def run_gtk3_native(title, is_dir_mode, filter_type="all", multiple=False):
    try:
        sys.setdlopenflags(os.RTLD_GLOBAL | os.RTLD_NOW)
        gtk = ctypes.CDLL('libgtk-3.so.0')
        glib = ctypes.CDLL('libglib-2.0.so.0')

        # Initialize GTK
        gtk.gtk_init.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        gtk.gtk_init.restype = None
        gtk.gtk_init(None, None)

        GTK_FILE_CHOOSER_ACTION_OPEN = 0
        GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER = 2
        GTK_RESPONSE_ACCEPT = -3
        GTK_RESPONSE_OK = -5
        GTK_RESPONSE_CANCEL = -6

        action = GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER if is_dir_mode else GTK_FILE_CHOOSER_ACTION_OPEN
        btn_label = b"_Select" if is_dir_mode else b"_Open"

        class GSList(ctypes.Structure):
            pass
        GSList._fields_ = [
            ('data', ctypes.c_void_p),
            ('next', ctypes.POINTER(GSList))
        ]

        gtk.gtk_file_chooser_dialog_new.argtypes = [
            ctypes.c_char_p, ctypes.c_void_p, ctypes.c_int,
            ctypes.c_char_p, ctypes.c_int,
            ctypes.c_char_p, ctypes.c_int,
            ctypes.c_void_p
        ]
        gtk.gtk_file_chooser_dialog_new.restype = ctypes.c_void_p

        gtk.gtk_dialog_run.argtypes = [ctypes.c_void_p]
        gtk.gtk_dialog_run.restype = ctypes.c_int

        gtk.gtk_widget_destroy.argtypes = [ctypes.c_void_p]
        gtk.gtk_widget_destroy.restype = None

        gtk.gtk_file_chooser_get_filename.argtypes = [ctypes.c_void_p]
        gtk.gtk_file_chooser_get_filename.restype = ctypes.c_void_p

        gtk.gtk_file_chooser_get_filenames.argtypes = [ctypes.c_void_p]
        gtk.gtk_file_chooser_get_filenames.restype = ctypes.POINTER(GSList)

        gtk.gtk_file_chooser_set_select_multiple.argtypes = [ctypes.c_void_p, ctypes.c_int]
        gtk.gtk_file_chooser_set_select_multiple.restype = None

        gtk.gtk_file_filter_new.argtypes = []
        gtk.gtk_file_filter_new.restype = ctypes.c_void_p

        gtk.gtk_file_filter_set_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        gtk.gtk_file_filter_set_name.restype = None

        gtk.gtk_file_filter_add_pattern.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        gtk.gtk_file_filter_add_pattern.restype = None

        gtk.gtk_file_filter_add_mime_type.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        gtk.gtk_file_filter_add_mime_type.restype = None

        gtk.gtk_file_chooser_add_filter.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        gtk.gtk_file_chooser_add_filter.restype = None

        gtk.gtk_events_pending.argtypes = []
        gtk.gtk_events_pending.restype = ctypes.c_int

        gtk.gtk_main_iteration.argtypes = []
        gtk.gtk_main_iteration.restype = ctypes.c_int

        glib.g_slist_free.argtypes = [ctypes.POINTER(GSList)]
        glib.g_slist_free.restype = None

        glib.g_free.argtypes = [ctypes.c_void_p]
        glib.g_free.restype = None

        dialog = gtk.gtk_file_chooser_dialog_new(
            title.encode('utf-8'),
            None,
            action,
            b"_Cancel",
            GTK_RESPONSE_CANCEL,
            btn_label,
            GTK_RESPONSE_ACCEPT,
            None
        )

        if multiple and not is_dir_mode:
            gtk.gtk_file_chooser_set_select_multiple(dialog, 1)

        if not is_dir_mode:
            if filter_type in ("document", "pdf"):
                filter_doc = gtk.gtk_file_filter_new()
                gtk.gtk_file_filter_set_name(filter_doc, b"PDF Documents (*.pdf)")
                for mime in [b"application/pdf", b"application/x-pdf", b"application/x-bzpdf", b"application/x-gzpdf"]:
                    gtk.gtk_file_filter_add_mime_type(filter_doc, mime)
                for pat in [b"*.pdf", b"*.PDF"]:
                    gtk.gtk_file_filter_add_pattern(filter_doc, pat)
                gtk.gtk_file_chooser_add_filter(dialog, filter_doc)
            elif filter_type == "audio":
                filter_audio = gtk.gtk_file_filter_new()
                gtk.gtk_file_filter_set_name(filter_audio, b"Audio files (*.mp3, *.flac, *.wav, *.m4a, *.ogg, *.opus)")
                for mime in [b"audio/mpeg", b"audio/mp3", b"audio/flac", b"audio/x-wav", b"audio/ogg", b"audio/aac", b"audio/m4a"]:
                    gtk.gtk_file_filter_add_mime_type(filter_audio, mime)
                for pat in [b"*.mp3", b"*.flac", b"*.wav", b"*.m4a", b"*.ogg", b"*.opus", b"*.MP3", b"*.FLAC", b"*.WAV", b"*.M4A", b"*.OGG", b"*.OPUS"]:
                    gtk.gtk_file_filter_add_pattern(filter_audio, pat)
                gtk.gtk_file_chooser_add_filter(dialog, filter_audio)
            elif filter_type == "image":
                filter_img = gtk.gtk_file_filter_new()
                gtk.gtk_file_filter_set_name(filter_img, b"Image files (*.png, *.jpg, *.jpeg, *.webp, *.svg)")
                for mime in [b"image/png", b"image/jpeg", b"image/webp", b"image/svg+xml"]:
                    gtk.gtk_file_filter_add_mime_type(filter_img, mime)
                for pat in [b"*.png", b"*.jpg", b"*.jpeg", b"*.webp", b"*.svg", b"*.PNG", b"*.JPG", b"*.JPEG", b"*.WEBP", b"*.SVG"]:
                    gtk.gtk_file_filter_add_pattern(filter_img, pat)
                gtk.gtk_file_chooser_add_filter(dialog, filter_img)

            filter_all = gtk.gtk_file_filter_new()
            gtk.gtk_file_filter_set_name(filter_all, b"All files (*.*)")
            gtk.gtk_file_filter_add_pattern(filter_all, b"*")
            gtk.gtk_file_chooser_add_filter(dialog, filter_all)

        response = gtk.gtk_dialog_run(dialog)
        results = []

        if response in (GTK_RESPONSE_ACCEPT, GTK_RESPONSE_OK):
            if multiple:
                slist = gtk.gtk_file_chooser_get_filenames(dialog)
                curr = slist
                while curr:
                    node = curr.contents
                    if node.data:
                        val = ctypes.cast(node.data, ctypes.c_char_p).value
                        if val:
                            results.append(val.decode('utf-8'))
                        glib.g_free(node.data)
                    curr = node.next
                if slist:
                    glib.g_slist_free(slist)
            else:
                filename_ptr = gtk.gtk_file_chooser_get_filename(dialog)
                if filename_ptr:
                    val = ctypes.cast(filename_ptr, ctypes.c_char_p).value
                    if val:
                        results.append(val.decode('utf-8'))
                    glib.g_free(filename_ptr)

        gtk.gtk_widget_destroy(dialog)
        while gtk.gtk_events_pending():
            gtk.gtk_main_iteration()

        if response in (GTK_RESPONSE_ACCEPT, GTK_RESPONSE_OK):
            return (True, results if multiple else (results[0] if results else None))
        else:
            # User cancelled or closed dialog cleanly
            return (True, None)
    except Exception:
        # Failed to load GTK or error running dialog
        return (False, None)

def run_zenity(title, is_dir_mode, filter_type="all", multiple=False):
    try:
        cmd = ["zenity", "--file-selection", f"--title={title}"]
        if is_dir_mode:
            cmd.append("--directory")
        elif filter_type in ("document", "pdf"):
            cmd.append("--file-filter=PDF Documents (*.pdf) | *.pdf *.PDF")
            cmd.append("--file-filter=All files | *")
        elif filter_type == "audio":
            cmd.append("--file-filter=Audio files (*.mp3, *.flac, *.wav, *.m4a, *.ogg, *.opus) | *.mp3 *.flac *.wav *.m4a *.ogg *.opus *.MP3 *.FLAC *.WAV *.M4A *.OGG *.OPUS")
            cmd.append("--file-filter=All files | *")
        elif filter_type == "image":
            cmd.append("--file-filter=Image files (*.png, *.jpg, *.jpeg, *.webp, *.svg) | *.png *.jpg *.jpeg *.webp *.svg *.PNG *.JPG *.JPEG *.WEBP *.SVG")
            cmd.append("--file-filter=All files | *")
        else:
            cmd.append("--file-filter=All files | *")

        if multiple:
            cmd.append("--multiple")
            cmd.append("--separator=\n")

        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode == 0:
            out = res.stdout.strip()
            if out:
                return (True, [line.strip() for line in out.split("\n") if line.strip()] if multiple else out)
            return (True, None)
        elif res.returncode == 1:
            # User clicked Cancel
            return (True, None)
    except Exception:
        pass
    return (False, None)

def run_tkinter(title, is_dir_mode, filter_type="all", multiple=False):
    try:
        import tkinter as tk
        from tkinter import filedialog
        root = tk.Tk()
        root.withdraw()
        root.attributes('-topmost', True)
        if is_dir_mode:
            path = filedialog.askdirectory(title=title)
            root.destroy()
            return (True, path if path else None)
        else:
            if filter_type in ("document", "pdf"):
                filetypes = [
                    ("PDF Documents", "*.pdf *.PDF"),
                    ("All files", "*.*")
                ]
            elif filter_type == "audio":
                filetypes = [
                    ("Audio files", "*.mp3 *.flac *.wav *.m4a *.ogg *.opus *.MP3 *.FLAC *.WAV *.M4A *.OGG *.OPUS"),
                    ("All files", "*.*")
                ]
            elif filter_type == "image":
                filetypes = [
                    ("Image files", "*.png *.jpg *.jpeg *.webp *.svg *.PNG *.JPG *.JPEG *.WEBP *.SVG"),
                    ("All files", "*.*")
                ]
            else:
                filetypes = [("All files", "*.*")]

            if multiple:
                paths = filedialog.askopenfilenames(title=title, filetypes=filetypes)
                root.destroy()
                return (True, list(paths) if paths else None)
            else:
                path = filedialog.askopenfilename(title=title, filetypes=filetypes)
                root.destroy()
                return (True, path if path else None)
    except Exception:
        return (False, None)

def main():
    args = sys.argv[1:]
    is_dir_mode = False
    multiple = False
    filter_type = ""
    title = ""

    i = 0
    clean_args = []
    while i < len(args):
        arg = args[i]
        if arg == "--dir":
            is_dir_mode = True
        elif arg == "--multiple":
            multiple = True
        elif arg == "--mode" and i + 1 < len(args):
            i += 1
            if args[i].lower() in ("dir", "directory", "folder"):
                is_dir_mode = True
            elif args[i].lower() in ("file", "files"):
                is_dir_mode = False
        elif arg == "--filter" and i + 1 < len(args):
            i += 1
            filter_type = args[i].lower()
        elif arg == "--title" and i + 1 < len(args):
            i += 1
            title = args[i]
        elif not arg.startswith("--"):
            clean_args.append(arg)
        i += 1

    if not title and clean_args:
        title = clean_args[0]
    if not title:
        title = "Select Directory" if is_dir_mode else "Select File"

    # Infer filter_type if not explicitly passed
    if not filter_type and not is_dir_mode:
        t_lower = title.lower()
        if "pdf" in t_lower or "document" in t_lower or "buku" in t_lower:
            filter_type = "document"
        elif "audio" in t_lower or "music" in t_lower or "song" in t_lower or "lagu" in t_lower:
            filter_type = "audio"
        elif "avatar" in t_lower or "logo" in t_lower or "wallpaper" in t_lower or "image" in t_lower or "picture" in t_lower or "foto" in t_lower:
            filter_type = "image"
        else:
            filter_type = "image"

    # Priority 1: Native GTK 3 File Chooser Dialog
    handled, result = run_gtk3_native(title, is_dir_mode, filter_type=filter_type, multiple=multiple)
    if handled:
        if result is not None:
            if multiple and isinstance(result, list):
                for item in result:
                    print(item)
            else:
                print(result)
        return

    # Priority 2: Zenity fallback
    if shutil.which("zenity"):
        handled, result = run_zenity(title, is_dir_mode, filter_type=filter_type, multiple=multiple)
        if handled:
            if result is not None:
                if multiple and isinstance(result, list):
                    for item in result:
                        print(item)
                else:
                    print(result)
            return

    # Priority 3: Tkinter fallback
    handled, result = run_tkinter(title, is_dir_mode, filter_type=filter_type, multiple=multiple)
    if handled and result is not None:
        if multiple and isinstance(result, list):
            for item in result:
                print(item)
        else:
            print(result)
        return

if __name__ == "__main__":
    main()
