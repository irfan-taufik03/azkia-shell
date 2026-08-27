#!/bin/env python3
import sys
import os
import json
import time

DOCS_DIR = os.path.expanduser("~/Documents/azkia-shell-note")
DRAFTS_DIR = "/tmp/azkia_shell_note_drafts"
LEGACY_TEMP_FILE = "/tmp/azkia_note_draft.json"

def ensure_dirs():
    os.makedirs(DOCS_DIR, exist_ok=True)
    os.makedirs(DRAFTS_DIR, exist_ok=True)

def format_timestamp(mtime=None):
    if mtime is None:
        mtime = time.time()
    t = time.localtime(mtime)
    current_year = time.localtime().tm_year
    if t.tm_year == current_year:
        return time.strftime("%b %d, %H:%M", t)
    else:
        return time.strftime("%b %d %Y, %H:%M", t)

def list_notes():
    ensure_dirs()
    notes = []

    # 1. Draft Notes (from DRAFTS_DIR and LEGACY_TEMP_FILE)
    draft_files = []
    if os.path.exists(DRAFTS_DIR):
        for fname in os.listdir(DRAFTS_DIR):
            if fname.endswith(".json"):
                fpath = os.path.join(DRAFTS_DIR, fname)
                draft_files.append((fname, fpath))
    
    # Sort drafts by modification time descending
    draft_files.sort(key=lambda item: os.path.getmtime(item[1]), reverse=True)

    for fname, fpath in draft_files:
        try:
            mtime = os.path.getmtime(fpath)
            with open(fpath, "r", encoding="utf-8") as f:
                data = json.load(f)
            notes.append({
                "id": fname,
                "title": data.get("title", "Untitled Draft"),
                "content": data.get("content", ""),
                "isSaved": False,
                "filePath": fpath,
                "updatedAt": format_timestamp(mtime)
            })
        except Exception:
            pass

    # Check for legacy single temp file if it exists and hasn't been migrated
    if os.path.exists(LEGACY_TEMP_FILE):
        try:
            mtime = os.path.getmtime(LEGACY_TEMP_FILE)
            with open(LEGACY_TEMP_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            if data and (data.get("title") or data.get("content")):
                notes.append({
                    "id": "legacy_draft",
                    "title": data.get("title", "Untitled Draft"),
                    "content": data.get("content", ""),
                    "isSaved": False,
                    "filePath": LEGACY_TEMP_FILE,
                    "updatedAt": format_timestamp(mtime)
                })
        except Exception:
            pass

    # 2. Saved Notes (from DOCS_DIR)
    if os.path.exists(DOCS_DIR):
        files = []
        for fname in os.listdir(DOCS_DIR):
            fpath = os.path.join(DOCS_DIR, fname)
            if os.path.isfile(fpath) and (fname.endswith(".json") or fname.endswith(".txt")):
                files.append((fname, fpath))
        
        files.sort(key=lambda item: os.path.getmtime(item[1]), reverse=True)

        for fname, fpath in files:
            try:
                mtime = os.path.getmtime(fpath)
                time_str = format_timestamp(mtime)
                if fname.endswith(".json"):
                    with open(fpath, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    notes.append({
                        "id": fname,
                        "title": data.get("title", fname.replace(".json", "")),
                        "content": data.get("content", ""),
                        "isSaved": True,
                        "filePath": fpath,
                        "updatedAt": time_str
                    })
                else:
                    with open(fpath, "r", encoding="utf-8") as f:
                        content = f.read()
                    title = fname.replace(".txt", "").replace("_", " ")
                    notes.append({
                        "id": fname,
                        "title": title,
                        "content": content,
                        "isSaved": True,
                        "filePath": fpath,
                        "updatedAt": time_str
                    })
            except Exception:
                pass

    return notes

def save_draft(note_id, title, content):
    ensure_dirs()
    if note_id and note_id.startswith("draft_") and os.path.exists(os.path.join(DRAFTS_DIR, note_id)):
        fname = note_id
    elif note_id == "legacy_draft" and os.path.exists(LEGACY_TEMP_FILE):
        fname = note_id
    else:
        timestamp = int(time.time() * 1000)
        fname = f"draft_{timestamp}.json"

    fpath = LEGACY_TEMP_FILE if fname == "legacy_draft" else os.path.join(DRAFTS_DIR, fname)
    data = {
        "title": title or "Untitled Draft",
        "content": content or "",
        "updatedAt": format_timestamp()
    }
    with open(fpath, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    return {"status": "ok", "id": fname}

def save_note(note_id, title, content):
    ensure_dirs()
    safe_title = "".join(c for c in (title or "Note") if c.isalnum() or c in (" ", "_", "-")).strip()
    if not safe_title:
        safe_title = "note"

    if note_id and not note_id.startswith("draft") and os.path.exists(os.path.join(DOCS_DIR, note_id)):
        fname = note_id
    else:
        timestamp = int(time.time())
        fname = f"{safe_title.replace(' ', '_')}_{timestamp}.json"

    fpath = os.path.join(DOCS_DIR, fname)
    data = {
        "title": title or safe_title,
        "content": content or "",
        "updatedAt": format_timestamp()
    }
    with open(fpath, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    # Clear draft file if converted to permanent note
    if note_id:
        if note_id.startswith("draft_") and os.path.exists(os.path.join(DRAFTS_DIR, note_id)):
            try:
                os.remove(os.path.join(DRAFTS_DIR, note_id))
            except Exception:
                pass
        elif note_id == "legacy_draft" and os.path.exists(LEGACY_TEMP_FILE):
            try:
                os.remove(LEGACY_TEMP_FILE)
            except Exception:
                pass

    return {"status": "ok", "filePath": fpath, "id": fname}

def delete_note(note_id):
    if not note_id:
        return {"status": "ok"}

    if note_id.startswith("draft_"):
        fpath = os.path.join(DRAFTS_DIR, note_id)
        if os.path.exists(fpath):
            try:
                os.remove(fpath)
            except Exception:
                pass
    elif note_id == "legacy_draft":
        if os.path.exists(LEGACY_TEMP_FILE):
            try:
                os.remove(LEGACY_TEMP_FILE)
            except Exception:
                pass
    else:
        fpath = os.path.join(DOCS_DIR, note_id)
        if os.path.exists(fpath):
            try:
                os.remove(fpath)
            except Exception:
                pass
    return {"status": "ok"}

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "--list":
        print(json.dumps(list_notes()))
    elif sys.argv[1] == "--save-draft":
        note_id = ""
        title = ""
        content = ""
        for i in range(2, len(sys.argv)):
            if sys.argv[i] == "--id" and i + 1 < len(sys.argv):
                note_id = sys.argv[i + 1]
            elif sys.argv[i] == "--title" and i + 1 < len(sys.argv):
                title = sys.argv[i + 1]
            elif sys.argv[i] == "--content" and i + 1 < len(sys.argv):
                content = sys.argv[i + 1]
        res = save_draft(note_id, title, content)
        print(json.dumps(res))
    elif sys.argv[1] == "--save":
        note_id = ""
        title = ""
        content = ""
        for i in range(2, len(sys.argv)):
            if sys.argv[i] == "--id" and i + 1 < len(sys.argv):
                note_id = sys.argv[i + 1]
            elif sys.argv[i] == "--title" and i + 1 < len(sys.argv):
                title = sys.argv[i + 1]
            elif sys.argv[i] == "--content" and i + 1 < len(sys.argv):
                content = sys.argv[i + 1]
        res = save_note(note_id, title, content)
        print(json.dumps(res))
    elif sys.argv[1] == "--delete":
        note_id = ""
        for i in range(2, len(sys.argv)):
            if sys.argv[i] == "--id" and i + 1 < len(sys.argv):
                note_id = sys.argv[i + 1]
        res = delete_note(note_id)
        print(json.dumps(res))

if __name__ == "__main__":
    main()

