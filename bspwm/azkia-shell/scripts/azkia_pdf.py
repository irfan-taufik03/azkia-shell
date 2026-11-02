#!/usr/bin/env python3
import sys
import os
import json
import hashlib
import shutil
import subprocess
import threading
import datetime
from concurrent.futures import ProcessPoolExecutor

CACHE_DIR = "/tmp/azkia_pdf_cache"
STATE_FILE = os.path.expanduser("~/.config/bspwm/azkia-shell/azkia_pdf_state.json")

# Multi-resolution DPI per zoom bucket using PyMuPDF (MuPDF vector engine):
# Bucket 100: 180 DPI (for 40% - 135% zoom, ~1500px wide, 2x supersampled)
# Bucket 150: 240 DPI (for 135% - 185% zoom, ~2000px wide)
# Bucket 200: 300 DPI (for 185% - 235% zoom, ~2500px wide)
# Bucket 300: 380 DPI (for 235% - 300%+ zoom, ~3150px wide, razor-sharp vector clarity)
BUCKET_DPIS = {
    100: 180,
    150: 240,
    200: 300,
    300: 380
}

os.makedirs(CACHE_DIR, exist_ok=True)

def get_file_hash(path):
    return hashlib.md5(os.path.abspath(path).encode('utf-8')).hexdigest()[:12]

def get_max_workers():
    try:
        return min(16, max(4, os.cpu_count() or 4))
    except Exception:
        return 4

def get_dpi(bucket):
    try:
        b = int(bucket)
    except Exception:
        b = 100
    return BUCKET_DPIS.get(b, 180)

def extract_page_words(page):
    """Extract words and organize into natural spatial reading order."""
    try:
        raw_words = page.get_text("words")
        if not raw_words:
            return []
        
        # Group into lines by Y center to handle multi-column or misaligned blocks
        lines = []
        for w in raw_words:
            x0, y0, x1, y1, text, b, l, wn = w
            yc = (y0 + y1) / 2.0
            matched = False
            for line in lines:
                if abs(line["yc"] - yc) < 6.0:
                    line["words"].append(w)
                    line["yc"] = (line["yc"] * len(line["words"]) + yc) / (len(line["words"]) + 1)
                    matched = True
                    break
            if not matched:
                lines.append({"yc": yc, "words": [w]})
        
        # Sort lines vertically from top to bottom
        lines.sort(key=lambda l: l["yc"])
        
        ordered_words = []
        word_idx = 0
        for line_idx, line in enumerate(lines):
            # Sort words horizontally within line from left to right
            line["words"].sort(key=lambda w: w[0])
            for w in line["words"]:
                x0, y0, x1, y1, text, b, l, wn = w
                ordered_words.append({
                    "i": word_idx,
                    "x0": round(float(x0), 2),
                    "y0": round(float(y0), 2),
                    "x1": round(float(x1), 2),
                    "y1": round(float(y1), 2),
                    "text": str(text),
                    "line": line_idx
                })
                word_idx += 1
        return ordered_words
    except Exception:
        return []

def get_page_text(file_path, page_num):
    try:
        h = get_file_hash(file_path)
        doc_cache = os.path.join(CACHE_DIR, h)
        text_path = os.path.join(doc_cache, f"text_p{page_num}.json")
        if os.path.exists(text_path) and os.path.getsize(text_path) > 0:
            with open(text_path, "r", encoding="utf-8") as f:
                return json.load(f)
        
        import pymupdf
        doc = pymupdf.open(file_path)
        page_idx = int(page_num) - 1
        if page_idx < 0 or page_idx >= doc.page_count:
            doc.close()
            return []
        page = doc[page_idx]
        words = extract_page_words(page)
        doc.close()
        
        os.makedirs(doc_cache, exist_ok=True)
        tmp_path = f"{text_path}.{os.getpid()}_{page_num}.tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(words, f)
        os.replace(tmp_path, text_path)
        return words
    except Exception:
        return []

def render_mupdf(file_path, page_num, dpi, rot_val, out_path):
    """Render page using PyMuPDF vector engine with exact font rasterization."""
    try:
        import pymupdf
        doc = pymupdf.open(file_path)
        page_idx = page_num - 1
        if page_idx < 0 or page_idx >= doc.page_count:
            doc.close()
            return False
        page = doc[page_idx]
        scale = float(dpi) / 72.0
        mat = pymupdf.Matrix(scale, scale).prerotate(rot_val)
        pix = page.get_pixmap(matrix=mat, alpha=False, colorspace=pymupdf.csRGB)
        tmp_path = f"{out_path}.{os.getpid()}_{page_num}.tmp.png"
        pix.save(tmp_path)
        os.replace(tmp_path, out_path)

        # Cache text coordinates for interactive text selection
        doc_cache = os.path.dirname(out_path)
        text_path = os.path.join(doc_cache, f"text_p{page_num}.json")
        if not os.path.exists(text_path) or os.path.getsize(text_path) == 0:
            words = extract_page_words(page)
            tmp_text = f"{text_path}.{os.getpid()}_{page_num}.tmp"
            with open(tmp_text, "w", encoding="utf-8") as f:
                json.dump(words, f)
            os.replace(tmp_text, text_path)

        doc.close()
        return True
    except Exception:
        # Fallback to pdftoppm if pymupdf fails or is unavailable
        try:
            prefix = out_path[:-4] if out_path.endswith(".png") else out_path
            tmp_prefix = f"{prefix}.{os.getpid()}_{page_num}.tmp"
            cmd = ["pdftoppm", "-png", "-singlefile", "-r", str(dpi), "-f", str(page_num), "-l", str(page_num), file_path, tmp_prefix]
            res = subprocess.run(cmd, capture_output=True)
            tmp_png = tmp_prefix + ".png"
            if res.returncode == 0 and os.path.exists(tmp_png):
                os.replace(tmp_png, out_path)
                return True
        except Exception:
            pass
        return False

def _worker_render_page(args):
    file_path, page_num, rot_val, bucket, out_path = args
    text_path = os.path.join(os.path.dirname(out_path), f"text_p{page_num}.json")
    
    if os.path.exists(out_path) and os.path.getsize(out_path) > 0:
        if not os.path.exists(text_path) or os.path.getsize(text_path) == 0:
            try:
                import pymupdf
                doc = pymupdf.open(file_path)
                if page_num - 1 < doc.page_count:
                    words = extract_page_words(doc[page_num - 1])
                    tmp_text = f"{text_path}.{os.getpid()}_{page_num}.tmp"
                    with open(tmp_text, "w", encoding="utf-8") as f:
                        json.dump(words, f)
                    os.replace(tmp_text, text_path)
                doc.close()
            except Exception:
                pass
        return {"status": "ok", "page": page_num, "path": out_path, "cached": True}
    
    dpi = get_dpi(bucket)
    success = render_mupdf(file_path, page_num, dpi, rot_val, out_path)

    if success:
        return {"status": "ok", "page": page_num, "path": out_path, "cached": False}
    else:
        return {"error": f"Failed to render page {page_num}", "page": page_num}

def _worker_render_thumb(args):
    file_path, page_num, out_path = args
    if os.path.exists(out_path) and os.path.getsize(out_path) > 0:
        return {"status": "ok", "page": page_num, "path": out_path, "cached": True}
    try:
        import pymupdf
        doc = pymupdf.open(file_path)
        page_idx = page_num - 1
        if page_idx < 0 or page_idx >= doc.page_count:
            doc.close()
            return {"error": f"Invalid page {page_num}"}
        page = doc[page_idx]
        rect = page.rect
        zoom_val = 320.0 / max(100.0, float(rect.width))
        mat = pymupdf.Matrix(zoom_val, zoom_val)
        pix = page.get_pixmap(matrix=mat, alpha=False, colorspace=pymupdf.csRGB)
        
        tmp_path = f"{out_path}.{os.getpid()}_{page_num}.tmp.png"
        pix.save(tmp_path)
        os.replace(tmp_path, out_path)
        
        w, h = pix.width, pix.height
        doc.close()
        return {"status": "ok", "page": page_num, "path": out_path, "width": w, "height": h, "cached": False}
    except Exception as e:
        # Fallback to pdftoppm for thumbnail
        try:
            prefix = out_path[:-4] if out_path.endswith(".png") else out_path
            tmp_prefix = f"{prefix}.{os.getpid()}_{page_num}.tmp"
            cmd = ["pdftoppm", "-png", "-singlefile", "-scale-to-x", "320", "-scale-to-y", "-1", "-f", str(page_num), "-l", str(page_num), file_path, tmp_prefix]
            res = subprocess.run(cmd, capture_output=True)
            tmp_png = tmp_prefix + ".png"
            if res.returncode == 0 and os.path.exists(tmp_png):
                os.replace(tmp_png, out_path)
                return {"status": "ok", "page": page_num, "path": out_path, "cached": False}
        except Exception:
            pass
        return {"error": str(e), "page": page_num}

def format_size(size_bytes):
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    elif size_bytes < 1024 * 1024 * 1024:
        return f"{size_bytes / (1024 * 1024):.1f} MB"
    else:
        return f"{size_bytes / (1024 * 1024 * 1024):.1f} GB"

def format_time(timestamp):
    dt = datetime.datetime.fromtimestamp(timestamp)
    now = datetime.datetime.now()
    hm = dt.strftime("%H:%M")
    if dt.date() == now.date():
        return f"Hari ini {hm}"
    elif (now.date() - dt.date()).days == 1:
        return f"Kemarin {hm}"
    elif dt.year == now.year:
        months = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agt", "Sep", "Okt", "Nov", "Des"]
        return f"{dt.day} {months[dt.month - 1]} {hm}"
    else:
        months = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agt", "Sep", "Okt", "Nov", "Des"]
        return f"{dt.day} {months[dt.month - 1]} {dt.year}"

def load_state():
    raw_list = []
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, 'r') as f:
                data = json.load(f)
                raw_list = data.get("recents", [])
        except Exception:
            raw_list = []

    recents = []
    for item in raw_list:
        p = item.get("path") if isinstance(item, dict) else item
        if p and isinstance(p, str) and p not in recents:
            recents.append(p)

    # Also discover recent PDFs on the laptop from ~/.local/share/recently-used.xbel
    xbel_path = os.path.expanduser("~/.local/share/recently-used.xbel")
    if os.path.exists(xbel_path):
        try:
            import xml.etree.ElementTree as ET
            import urllib.parse
            tree = ET.parse(xbel_path)
            for bm in reversed(tree.getroot().findall(".//bookmark")):
                href = bm.get("href", "")
                if href.startswith("file://"):
                    p = urllib.parse.unquote(href[7:])
                    if p.lower().endswith(".pdf") and p not in recents:
                        recents.append(p)
        except Exception:
            pass

    # If recent count is less than 20, discover recently modified PDFs from Downloads and Documents
    if len(recents) < 20:
        candidates = []
        for folder in [os.path.expanduser("~/Downloads"), os.path.expanduser("~/Documents")]:
            if os.path.isdir(folder):
                try:
                    for entry in os.scandir(folder):
                        if entry.is_file() and entry.name.lower().endswith(".pdf"):
                            candidates.append((entry.stat().st_mtime, entry.path))
                except Exception:
                    pass
        candidates.sort(key=lambda x: x[0], reverse=True)
        for _, path in candidates:
            if path not in recents:
                recents.append(path)
            if len(recents) >= 25:
                break

    # STRICT: Absolutely only files that exist on the user's laptop!
    valid = [p for p in recents if os.path.isfile(p)]
    seen = set()
    dedup = []
    for p in valid:
        if p not in seen:
            seen.add(p)
            dedup.append(p)

    save_state({"recents": dedup[:50]})

    items = []
    home_dir = os.path.expanduser("~")
    for p in dedup[:50]:
        try:
            st = os.stat(p)
            folder = os.path.dirname(p)
            rel_folder = ("~" + folder[len(home_dir):]) if folder.startswith(home_dir) else folder
            items.append({
                "path": p,
                "name": os.path.basename(p),
                "size": format_size(st.st_size),
                "location": rel_folder,
                "time": format_time(st.st_mtime),
                "mtime": st.st_mtime
            })
        except Exception:
            pass

    return {"recents": items}

def save_state(state):
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        raw = state.get("recents", [])
        paths = []
        for item in raw:
            p = item.get("path") if isinstance(item, dict) else item
            if p and isinstance(p, str) and os.path.isfile(p) and p not in paths:
                paths.append(p)
        clean_state = {"recents": paths}
        with open(STATE_FILE, 'w') as f:
            json.dump(clean_state, f, indent=2)
    except Exception:
        pass

def add_recent_file(file_path):
    if not file_path or not os.path.isfile(file_path):
        return
    state = load_state()
    recents = []
    for item in state.get("recents", []):
        p = item.get("path") if isinstance(item, dict) else item
        if p and p not in recents and os.path.isfile(p):
            recents.append(p)
    abs_path = os.path.abspath(file_path)
    if abs_path in recents:
        recents.remove(abs_path)
    recents.insert(0, abs_path)
    save_state({"recents": recents[:50]})

def open_file_dialog():
    try:
        script = os.path.join(os.path.dirname(__file__), "select_file.py")
        res = subprocess.run([sys.executable, script, "--mode", "file", "--title", "Open PDF / Document", "--filter", "document"], capture_output=True, text=True)
        return res.stdout.strip()
    except Exception:
        return ""

def render_page(file_path, page_num, rotation=0, bucket=100):
    try:
        page_idx = int(page_num) - 1
        rot_val = int(rotation) % 360
        b_val = int(bucket)

        h = get_file_hash(file_path)
        doc_cache = os.path.join(CACHE_DIR, h)
        os.makedirs(doc_cache, exist_ok=True)

        img_name = f"p{page_num}_b{b_val}_r{rot_val}.png"
        img_path = os.path.join(doc_cache, img_name)

        if os.path.exists(img_path) and os.path.getsize(img_path) > 0:
            return {
                "status": "ok",
                "page": page_num,
                "path": img_path,
                "cached": True
            }

        res = _worker_render_page((file_path, page_num, rot_val, b_val, img_path))
        return res
    except Exception as e:
        return {"error": str(e)}

def render_thumbnail(file_path, page_num):
    try:
        h = get_file_hash(file_path)
        doc_cache = os.path.join(CACHE_DIR, h, "thumbs")
        os.makedirs(doc_cache, exist_ok=True)

        img_path = os.path.join(doc_cache, f"thumb_p{page_num}.png")
        if os.path.exists(img_path) and os.path.getsize(img_path) > 0:
            return {
                "status": "ok",
                "page": page_num,
                "path": img_path,
                "cached": True
            }

        res = _worker_render_thumb((file_path, page_num, img_path))
        return res
    except Exception as e:
        return {"error": str(e)}

def get_pdf_total_pages(file_path):
    try:
        import pymupdf
        doc = pymupdf.open(file_path)
        cnt = doc.page_count
        doc.close()
        return cnt
    except Exception:
        pass
    try:
        res = subprocess.run(["pdfinfo", file_path], capture_output=True, text=True)
        for line in res.stdout.splitlines():
            if line.startswith("Pages:"):
                return int(line.split(":", 1)[1].strip())
    except Exception:
        pass
    return 1

def render_all_thumbnails(file_path):
    try:
        total = get_pdf_total_pages(file_path)

        h = get_file_hash(file_path)
        doc_cache = os.path.join(CACHE_DIR, h, "thumbs")
        os.makedirs(doc_cache, exist_ok=True)

        tasks = []
        for i in range(total):
            page_num = i + 1
            img_path = os.path.join(doc_cache, f"thumb_p{page_num}.png")
            tasks.append((file_path, page_num, img_path))

        with ProcessPoolExecutor(max_workers=get_max_workers()) as pool:
            results = list(pool.map(_worker_render_thumb, tasks))

        return {"status": "ok", "thumbnails": results, "thumb_dir": doc_cache, "total": total}
    except Exception as e:
        return {"error": str(e), "thumbnails": []}

def render_all_pages(file_path, rotation=0, bucket=100):
    try:
        rot_val = int(rotation) % 360
        b_val = int(bucket)

        total = get_pdf_total_pages(file_path)

        h = get_file_hash(file_path)
        doc_cache = os.path.join(CACHE_DIR, h)
        os.makedirs(doc_cache, exist_ok=True)

        tasks = []
        for i in range(total):
            page_num = i + 1
            img_name = f"p{page_num}_b{b_val}_r{rot_val}.png"
            img_path = os.path.join(doc_cache, img_name)
            tasks.append((file_path, page_num, rot_val, b_val, img_path))

        with ProcessPoolExecutor(max_workers=get_max_workers()) as pool:
            results = list(pool.map(_worker_render_page, tasks))

        return {"status": "ok", "pages": total, "rotation": rot_val, "bucket": b_val, "cache_dir": doc_cache}
    except Exception as e:
        return {"error": str(e)}

def get_doc_info(file_path):
    if not os.path.exists(file_path):
        return {"error": "File not found", "path": file_path}

    pages_info = []
    doc_count = 1
    doc_format = "PDF"
    doc_title = ""
    toc_list = []

    mupdf_success = False
    try:
        import pymupdf
        doc = pymupdf.open(file_path)
        for i in range(doc.page_count):
            try:
                page = doc[i]
                rect = page.rect
                pages_info.append({
                    "page": i + 1,
                    "width": float(rect.width),
                    "height": float(rect.height),
                    "aspect": float(rect.width / max(1.0, rect.height))
                })
            except Exception:
                pages_info.append({"page": i + 1, "width": 595.0, "height": 842.0, "aspect": 0.706})

        try:
            toc = doc.get_toc()
            for item in toc:
                if len(item) >= 3:
                    lvl, title, pg = item[0], item[1], item[2]
                    toc_list.append({"level": lvl, "title": title, "page": pg})
        except Exception:
            pass

        doc_count = doc.page_count
        doc_format = doc.metadata.get("format", "PDF") if doc.metadata else "PDF"
        doc_title = doc.metadata.get("title", "") if doc.metadata else ""
        doc.close()
        mupdf_success = True
    except Exception:
        mupdf_success = False

    if not mupdf_success:
        try:
            res = subprocess.run(["pdfinfo", file_path], capture_output=True, text=True)
            w, h = 595.0, 842.0
            for line in res.stdout.splitlines():
                if line.startswith("Pages:"):
                    doc_count = int(line.split(":", 1)[1].strip())
                elif line.startswith("Title:"):
                    doc_title = line.split(":", 1)[1].strip()
                elif line.startswith("Page size:"):
                    parts = line.split(":", 1)[1].strip().split()
                    if len(parts) >= 3 and parts[1] == "x":
                        try:
                            w, h = float(parts[0]), float(parts[2])
                        except Exception:
                            pass
            for i in range(doc_count):
                pages_info.append({
                    "page": i + 1,
                    "width": w,
                    "height": h,
                    "aspect": float(w / max(1.0, h))
                })
        except Exception as e:
            return {"error": str(e), "path": file_path}

    h = get_file_hash(file_path)
    doc_cache = os.path.join(CACHE_DIR, h)
    doc_thumbs_dir = os.path.join(doc_cache, "thumbs")
    os.makedirs(doc_thumbs_dir, exist_ok=True)

    # Pre-render first page immediately for zero-wait crisp display
    initial_img = ""
    try:
        p1_res = render_page(file_path, 1, 0, 100)
        if p1_res.get("status") == "ok":
            initial_img = p1_res.get("path", "")
    except Exception:
        pass

    # Pre-render first thumbnail immediately
    try:
        render_thumbnail(file_path, 1)
    except Exception:
        pass

    meta = {
        "path": os.path.abspath(file_path),
        "filename": os.path.basename(file_path),
        "page_count": doc_count,
        "pages": pages_info,
        "toc": toc_list,
        "initial_img": initial_img,
        "thumb_dir": doc_thumbs_dir,
        "file_hash": h,
        "format": doc_format,
        "title": doc_title
    }
    add_recent_file(file_path)
    return meta

def search_text(file_path, query):
    if not query or not os.path.exists(file_path):
        return {"results": [], "total_matches": 0}

    try:
        import pymupdf
        doc = pymupdf.open(file_path)
        results = []
        total_matches = 0

        for i in range(doc.page_count):
            page = doc[i]
            rects = page.search_for(query)
            if rects:
                total_matches += len(rects)
                rect_data = []
                for r in rects:
                    rect_data.append({
                        "x0": r.x0, "y0": r.y0,
                        "x1": r.x1, "y1": r.y1
                    })
                results.append({
                    "page": i + 1,
                    "count": len(rects),
                    "rects": rect_data
                })
        doc.close()

        return {
            "query": query,
            "total_matches": total_matches,
            "results": results
        }
    except Exception as e:
        return {"error": str(e), "results": [], "total_matches": 0}

def open_in_azkia_shell(files):
    import urllib.parse
    import time
    shell_path = os.path.expanduser("~/.config/bspwm/azkia-shell")

    valid_files = []
    for f in files:
        if not f:
            continue
        p = str(f).strip()
        if p.startswith("file://"):
            p = p[7:]
        p = urllib.parse.unquote(p)
        abs_p = os.path.abspath(p)
        if os.path.exists(abs_p):
            valid_files.append(abs_p)

    if not valid_files:
        res = subprocess.run(["qs", "-p", shell_path, "ipc", "call", "pdf", "open"], capture_output=True)
        if res.returncode != 0:
            subprocess.Popen(["quickshell", "--path", shell_path])
        return

    for vf in valid_files:
        res = subprocess.run(["qs", "-p", shell_path, "ipc", "call", "pdf", "openFile", vf], capture_output=True)
        if res.returncode != 0:
            subprocess.Popen(["quickshell", "--path", shell_path])
            time.sleep(0.6)
            subprocess.Popen(["qs", "-p", shell_path, "ipc", "call", "pdf", "openFile", vf])

def main():
    args = sys.argv[1:]
    if not args:
        open_in_azkia_shell([])
        return

    cmd = args[0]

    if cmd == "--select-file":
        chosen = open_file_dialog()
        if chosen:
            info = get_doc_info(chosen)
            print(json.dumps({"action": "file_selected", "path": chosen, "info": info}))
        else:
            print(json.dumps({"action": "cancelled"}))

    elif cmd == "--info" and len(args) >= 2:
        info = get_doc_info(args[1])
        print(json.dumps(info))

    elif cmd == "--render-page" and len(args) >= 3:
        file_path = args[1]
        page_num = int(args[2])
        rot = int(args[3]) if len(args) >= 4 else 0
        bucket = int(args[4]) if len(args) >= 5 else 100
        res = render_page(file_path, page_num, rot, bucket)
        print(json.dumps(res))

    elif cmd == "--render-all-pages" and len(args) >= 2:
        file_path = args[1]
        rot = int(args[2]) if len(args) >= 3 else 0
        bucket = int(args[3]) if len(args) >= 4 else 100
        res = render_all_pages(file_path, rot, bucket)
        print(json.dumps(res))

    elif cmd == "--render-thumbs" and len(args) >= 2:
        file_path = args[1]
        res = render_all_thumbnails(file_path)
        print(json.dumps(res))

    elif cmd == "--render-thumb" and len(args) >= 3:
        file_path = args[1]
        page_num = int(args[2])
        res = render_thumbnail(file_path, page_num)
        print(json.dumps(res))

    elif cmd == "--get-page-text" and len(args) >= 3:
        file_path = args[1]
        page_num = int(args[2])
        res = get_page_text(file_path, page_num)
        print(json.dumps(res))

    elif cmd == "--copy-text" and len(args) >= 2:
        text = args[1]
        try:
            p = subprocess.Popen(["xclip", "-selection", "clipboard"], stdin=subprocess.PIPE)
            p.communicate(input=text.encode("utf-8"))
        except Exception:
            try:
                p = subprocess.Popen(["xsel", "-b", "-i"], stdin=subprocess.PIPE)
                p.communicate(input=text.encode("utf-8"))
            except Exception:
                pass
        print(json.dumps({"status": "ok"}))

    elif cmd == "--search" and len(args) >= 3:
        file_path = args[1]
        query = args[2]
        res = search_text(file_path, query)
        print(json.dumps(res))

    elif cmd == "--get-state":
        st = load_state()
        print(json.dumps(st))

    elif cmd == "--save-state" and len(args) >= 2:
        try:
            st = json.loads(args[1])
            save_state(st)
            print(json.dumps({"status": "ok"}))
        except Exception as e:
            print(json.dumps({"error": str(e)}))

    elif cmd.startswith("-"):
        print(json.dumps({"error": f"Unknown command {cmd}"}))

    else:
        open_in_azkia_shell(args)

if __name__ == "__main__":
    main()
