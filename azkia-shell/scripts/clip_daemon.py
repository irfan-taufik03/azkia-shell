#!/usr/bin/env python3
import json
import os
import sys
import time
import hashlib
import subprocess
from datetime import datetime

CACHE_DIR = os.path.expanduser("~/.cache/azkia-shell/clipboard")
IMAGES_DIR = os.path.join(CACHE_DIR, "images")
HISTORY_FILE = os.path.join(CACHE_DIR, "history.json")
MAX_ITEMS = 20

os.makedirs(IMAGES_DIR, exist_ok=True)

def load_history():
    if os.path.exists(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []
    return []

def save_history(history):
    temp_file = HISTORY_FILE + ".tmp"
    with open(temp_file, "w", encoding="utf-8") as f:
        json.dump(history, f, ensure_ascii=False, indent=2)
    os.replace(temp_file, HISTORY_FILE)

def get_targets():
    try:
        res = subprocess.run(
            ["xclip", "-selection", "clipboard", "-target", "TARGETS", "-o"],
            capture_output=True,
            timeout=2
        )
        return res.stdout.decode("utf-8", errors="ignore").splitlines()
    except Exception:
        return []

def get_text():
    try:
        res = subprocess.run(
            ["xclip", "-selection", "clipboard", "-o"],
            capture_output=True,
            timeout=2
        )
        return res.stdout.decode("utf-8", errors="ignore")
    except Exception:
        return ""

def get_image_bytes():
    try:
        res = subprocess.run(
            ["xclip", "-selection", "clipboard", "-target", "image/png", "-o"],
            capture_output=True,
            timeout=2
        )
        return res.stdout
    except Exception:
        return b""

def copy_to_clipboard(item_id):
    history = load_history()
    for item in history:
        if item.get("id") == item_id:
            if item.get("type") == "text":
                text = item.get("full_text", "")
                p = subprocess.Popen(["xclip", "-selection", "clipboard"], stdin=subprocess.PIPE)
                p.communicate(input=text.encode("utf-8"))
                return True
            elif item.get("type") == "image":
                img_path = item.get("image_path", "")
                if os.path.exists(img_path):
                    p = subprocess.Popen(["xclip", "-selection", "clipboard", "-target", "image/png"], stdin=subprocess.PIPE)
                    with open(img_path, "rb") as f:
                        p.communicate(input=f.read())
                    return True
    return False

def delete_item(item_id):
    history = load_history()
    new_history = []
    for item in history:
        if item.get("id") == item_id:
            if item.get("type") == "image" and os.path.exists(item.get("image_path", "")):
                try:
                    os.remove(item["image_path"])
                except Exception:
                    pass
        else:
            new_history.append(item)
    save_history(new_history)

def clear_all():
    save_history([])
    for f in os.listdir(IMAGES_DIR):
        try:
            os.remove(os.path.join(IMAGES_DIR, f))
        except Exception:
            pass

def daemon_loop():
    last_hash = ""
    history = load_history()
    if history:
        last_hash = history[0].get("hash", "")

    while True:
        try:
            targets = get_targets()
            has_image = any("image" in t.lower() for t in targets)
            has_text = any("text" in t.lower() or "string" in t.lower() for t in targets)

            if has_image:
                img_bytes = get_image_bytes()
                if img_bytes and len(img_bytes) > 50:
                    h = hashlib.md5(img_bytes).hexdigest()
                    if h != last_hash:
                        last_hash = h
                        item_id = f"img_{int(time.time()*1000)}"
                        file_name = f"{item_id}.png"
                        file_path = os.path.join(IMAGES_DIR, file_name)
                        with open(file_path, "wb") as f:
                            f.write(img_bytes)

                        item = {
                            "id": item_id,
                            "type": "image",
                            "preview": f"Image ({len(img_bytes)//1024} KB)",
                            "image_path": file_path,
                            "hash": h,
                            "timestamp": datetime.now().strftime("%H:%M")
                        }
                        history = [x for x in load_history() if x.get("hash") != h]
                        history.insert(0, item)
                        history = history[:MAX_ITEMS]
                        save_history(history)
            elif has_text:
                txt = get_text()
                if txt and txt.strip():
                    h = hashlib.md5(txt.encode("utf-8")).hexdigest()
                    if h != last_hash:
                        last_hash = h
                        item_id = f"txt_{int(time.time()*1000)}"
                        preview_txt = txt.strip().replace("\n", " ")
                        if len(preview_txt) > 80:
                            preview_txt = preview_txt[:77] + "..."

                        item = {
                            "id": item_id,
                            "type": "text",
                            "preview": preview_txt,
                            "full_text": txt,
                            "hash": h,
                            "timestamp": datetime.now().strftime("%H:%M")
                        }
                        history = [x for x in load_history() if x.get("hash") != h]
                        history.insert(0, item)
                        history = history[:MAX_ITEMS]
                        save_history(history)

        except Exception as e:
            pass

        time.sleep(0.8)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "--get-json":
            print(json.dumps(load_history(), ensure_ascii=False))
        elif cmd == "--copy" and len(sys.argv) > 2:
            copy_to_clipboard(sys.argv[2])
        elif cmd == "--delete" and len(sys.argv) > 2:
            delete_item(sys.argv[2])
        elif cmd == "--clear":
            clear_all()
        elif cmd == "--daemon":
            daemon_loop()
    else:
        daemon_loop()
