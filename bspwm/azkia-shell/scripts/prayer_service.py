#!/usr/bin/env python3
"""
Azkia Shell - Prayer Time (Jadwal Shalat) Service
Fetches, caches, and calculates Indonesian prayer times using equran.id v2 API and IP geolocation.
"""

import sys
import os
import json
import datetime
import urllib.request
import urllib.parse
import time
import subprocess
import fcntl

USER_DIR = os.path.expanduser("~")
CONFIG_DIR = os.path.join(USER_DIR, ".config", "bspwm", "azkia-shell")
CONFIG_FILE = os.path.join(CONFIG_DIR, "prayer_config.json")
CACHE_DIR = os.path.join(USER_DIR, ".cache")
CACHE_FILE = os.path.join(CACHE_DIR, "azkia_prayer.json")
PROVINCES_CACHE = os.path.join(CACHE_DIR, "azkia_prayer_provinces.json")

# Mapping of English province names from ip-api to official Indonesian names
ENG_TO_ID_PROV = {
    "south sulawesi": "Sulawesi Selatan",
    "north sulawesi": "Sulawesi Utara",
    "central sulawesi": "Sulawesi Tengah",
    "southeast sulawesi": "Sulawesi Tenggara",
    "west sulawesi": "Sulawesi Barat",
    "gorontalo": "Gorontalo",
    "west java": "Jawa Barat",
    "central java": "Jawa Tengah",
    "east java": "Jawa Timur",
    "special capital region of jakarta": "DKI Jakarta",
    "jakarta": "DKI Jakarta",
    "dki jakarta": "DKI Jakarta",
    "special region of yogyakarta": "D.I. Yogyakarta",
    "yogyakarta": "D.I. Yogyakarta",
    "di yogyakarta": "D.I. Yogyakarta",
    "banten": "Banten",
    "bali": "Bali",
    "aceh": "Aceh",
    "north sumatra": "Sumatera Utara",
    "west sumatra": "Sumatera Barat",
    "south sumatra": "Sumatera Selatan",
    "riau": "Riau",
    "riau islands": "Kepulauan Riau",
    "jambi": "Jambi",
    "bengkulu": "Bengkulu",
    "lampung": "Lampung",
    "bangka belitung": "Kepulauan Bangka Belitung",
    "west kalimantan": "Kalimantan Barat",
    "central kalimantan": "Kalimantan Tengah",
    "south kalimantan": "Kalimantan Selatan",
    "east kalimantan": "Kalimantan Timur",
    "north kalimantan": "Kalimantan Utara",
    "west nusa tenggara": "Nusa Tenggara Barat",
    "east nusa tenggara": "Nusa Tenggara Timur",
    "maluku": "Maluku",
    "north maluku": "Maluku Utara",
    "papua": "Papua",
    "west papua": "Papua Barat"
}

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"auto_detect": True, "provinsi": "Sulawesi Selatan", "kabkota": "Kota Makassar"}

def save_config(cfg):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

def api_get_provinces():
    if os.path.exists(PROVINCES_CACHE):
        try:
            mtime = os.path.getmtime(PROVINCES_CACHE)
            if datetime.datetime.now().timestamp() - mtime < 86400 * 30: # 30 days
                with open(PROVINCES_CACHE, "r", encoding="utf-8") as f:
                    return json.load(f)
        except Exception:
            pass

    try:
        req = urllib.request.Request(
            "https://equran.id/api/v2/shalat/provinsi",
            headers={"User-Agent": "AzkiaShell/1.0"}
        )
        with urllib.request.urlopen(req, timeout=7) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("code") == 200:
                provinces = data.get("data", [])
                os.makedirs(CACHE_DIR, exist_ok=True)
                with open(PROVINCES_CACHE, "w", encoding="utf-8") as f:
                    json.dump(provinces, f, ensure_ascii=False)
                return provinces
    except Exception:
        pass
    return ["DKI Jakarta", "Jawa Barat", "Jawa Tengah", "Jawa Timur", "Sulawesi Selatan"]

def api_get_kabkota(provinsi):
    cache_path = os.path.join(CACHE_DIR, f"azkia_cities_{urllib.parse.quote(provinsi)}.json")
    if os.path.exists(cache_path):
        try:
            mtime = os.path.getmtime(cache_path)
            if datetime.datetime.now().timestamp() - mtime < 86400 * 15: # 15 days
                with open(cache_path, "r", encoding="utf-8") as f:
                    return json.load(f)
        except Exception:
            pass

    try:
        body = json.dumps({"provinsi": provinsi}).encode("utf-8")
        req = urllib.request.Request(
            "https://equran.id/api/v2/shalat/kabkota",
            data=body,
            headers={"Content-Type": "application/json", "User-Agent": "AzkiaShell/1.0"}
        )
        with urllib.request.urlopen(req, timeout=7) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("code") == 200:
                cities = data.get("data", [])
                os.makedirs(CACHE_DIR, exist_ok=True)
                with open(cache_path, "w", encoding="utf-8") as f:
                    json.dump(cities, f, ensure_ascii=False)
                return cities
    except Exception:
        pass
    return []

def api_fetch_schedule(provinsi, kabkota, month=None, year=None):
    now = datetime.datetime.now()
    if not month: month = now.month
    if not year: year = now.year

    body = json.dumps({
        "provinsi": provinsi,
        "kabkota": kabkota,
        "bulan": month,
        "tahun": year
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://equran.id/api/v2/shalat",
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "AzkiaShell/1.0"}
    )
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        if data.get("code") == 200:
            return data.get("data")
    return None

def detect_ip_location():
    try:
        req = urllib.request.Request(
            "http://ip-api.com/json",
            headers={"User-Agent": "AzkiaShell/1.0"}
        )
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("status") == "success":
                region_name = data.get("regionName", "").strip()
                city_name = data.get("city", "").strip()

                # Map region to Indonesian province
                prov = ENG_TO_ID_PROV.get(region_name.lower(), region_name)
                all_provs = api_get_provinces()

                matched_prov = None
                for p in all_provs:
                    if prov.lower() in p.lower() or p.lower() in prov.lower():
                        matched_prov = p
                        break
                if not matched_prov:
                    matched_prov = "Sulawesi Selatan"

                cities = api_get_kabkota(matched_prov)
                matched_city = None
                for c in cities:
                    if city_name.lower() in c.lower() or c.lower() in city_name.lower():
                        matched_city = c
                        break
                if not matched_city and cities:
                    matched_city = cities[0]
                elif not matched_city:
                    matched_city = "Kota Makassar"

                return matched_prov, matched_city
    except Exception:
        pass
    return "Sulawesi Selatan", "Kota Makassar"

def compute_prayer_stats(schedule_data, config):
    now = datetime.datetime.now()
    today_num = now.day
    jadwal = schedule_data.get("jadwal", [])

    today_item = next((d for d in jadwal if d.get("tanggal") == today_num), None)
    if not today_item and jadwal:
        today_item = jadwal[0]

    # Prayers in chronological sequence (5 Daily Prayers)
    prayer_keys = [
        {"id": "subuh", "name": "Fajr", "icon": "󰖔"},
        {"id": "dzuhur", "name": "Dhuhr", "icon": "󰖨"},
        {"id": "ashar", "name": "Asr", "icon": "󰖝"},
        {"id": "maghrib", "name": "Maghrib", "icon": "󰖚"},
        {"id": "isya", "name": "Isha", "icon": "󰖛"}
    ]

    prayers_list = []
    current_minutes = now.hour * 60 + now.minute

    next_prayer = None
    min_diff = 999999
    last_prayer = prayer_keys[-1]

    for p in prayer_keys:
        t_str = today_item.get(p["id"], "00:00")
        try:
            h, m = map(int, t_str.split(":"))
            p_minutes = h * 60 + m
        except Exception:
            p_minutes = 0

        diff = p_minutes - current_minutes
        is_passed = (diff <= 0)

        if 0 < diff < min_diff:
            min_diff = diff
            next_prayer = {
                "id": p["id"],
                "name": p["name"],
                "time": t_str,
                "diff_minutes": diff
            }

        if is_passed:
            last_prayer = p

        prayers_list.append({
            "id": p["id"],
            "name": p["name"],
            "icon": p["icon"],
            "time": t_str,
            "passed": is_passed
        })

    # If all prayers passed today, next prayer is tomorrow's Fajr
    if not next_prayer:
        first_prayer = prayers_list[0] # Fajr
        # Time remaining until tomorrow's first prayer
        try:
            h, m = map(int, first_prayer["time"].split(":"))
            diff = (24 * 60 - current_minutes) + (h * 60 + m)
        except Exception:
            diff = 300
        next_prayer = {
            "id": first_prayer["id"],
            "name": first_prayer["name"] + " (Tomorrow)",
            "time": first_prayer["time"],
            "diff_minutes": diff
        }

    # Format countdown string
    hours = next_prayer["diff_minutes"] // 60
    mins = next_prayer["diff_minutes"] % 60
    if hours > 0:
        countdown_str = f"{hours}h {mins}m remaining"
    else:
        countdown_str = f"{mins}m remaining"

    next_prayer["countdown"] = countdown_str

    return {
        "status": "success",
        "provinsi": schedule_data.get("provinsi"),
        "kabkota": schedule_data.get("kabkota"),
        "bulan_nama": schedule_data.get("bulan_nama"),
        "tahun": schedule_data.get("tahun"),
        "today": today_item,
        "prayers": prayers_list,
        "next_prayer": next_prayer,
        "current_prayer": last_prayer,
        "is_auto": config.get("auto_detect", True)
    }

def get_complete_data(force_refresh=False):
    cfg = load_config()
    now = datetime.datetime.now()

    # Check cache first
    cached_data = None
    if not force_refresh and os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                c = json.load(f)
                if (c.get("bulan") == now.month and
                    c.get("tahun") == now.year and
                    c.get("provinsi") == cfg.get("provinsi") and
                    c.get("kabkota") == cfg.get("kabkota")):
                    cached_data = c
        except Exception:
            pass

    if cached_data:
        return compute_prayer_stats(cached_data, cfg)

    # If auto-detect is on and not set or force_refresh
    if cfg.get("auto_detect", True) and (force_refresh or not cfg.get("provinsi")):
        prov, city = detect_ip_location()
        cfg["provinsi"] = prov
        cfg["kabkota"] = city
        save_config(cfg)

    schedule = api_fetch_schedule(cfg["provinsi"], cfg["kabkota"], now.month, now.year)
    if schedule:
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(schedule, f, ensure_ascii=False)
        return compute_prayer_stats(schedule, cfg)
    elif cached_data:
        return compute_prayer_stats(cached_data, cfg)

    return {"status": "error", "message": "Gagal mengambil data jadwal shalat"}

DAEMON_LOCK_FILE = "/tmp/azkia_prayer_daemon.lock"
NOTIF_STATE_FILE = "/tmp/azkia_prayer_notifs.json"

def acquire_daemon_lock():
    try:
        lock_fd = os.open(DAEMON_LOCK_FILE, os.O_CREAT | os.O_RDWR)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return lock_fd
    except (BlockingIOError, OSError):
        sys.exit(0)

def send_prayer_notification(summary, body):
    try:
        subprocess.run([
            "notify-send",
            "-a", "Prayer Time",
            "-u", "normal",
            summary,
            body
        ], timeout=5)
    except Exception:
        pass

def load_notif_state():
    if os.path.exists(NOTIF_STATE_FILE):
        try:
            with open(NOTIF_STATE_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_notif_state(state):
    try:
        with open(NOTIF_STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception:
        pass

def run_daemon():
    acquire_daemon_lock()
    notif_state = load_notif_state()

    while True:
        try:
            now = datetime.datetime.now()
            today_str = now.strftime("%Y-%m-%d")

            # Reset state on a new day
            if notif_state.get("_date") != today_str:
                notif_state = {"_date": today_str}
                save_notif_state(notif_state)

            data = get_complete_data(force_refresh=False)
            prayers = data.get("prayers", [])
            current_total_sec = now.hour * 3600 + now.minute * 60 + now.second

            for p in prayers:
                p_id = p.get("id")
                p_name = p.get("name")
                t_str = p.get("time", "00:00")
                try:
                    h, m = map(int, t_str.split(":"))
                    p_total_sec = h * 3600 + m * 60
                except Exception:
                    continue

                diff_sec = p_total_sec - current_total_sec

                stage_15 = f"{p_id}_15m"
                stage_5 = f"{p_id}_5m"
                stage_3 = f"{p_id}_3m"
                stage_0 = f"{p_id}_0m"

                # 1. 15 Minutes Before Prayer Time
                if 840 <= diff_sec <= 910 and stage_15 not in notif_state:
                    notif_state[stage_15] = True
                    save_notif_state(notif_state)
                    send_prayer_notification(
                        f"Prayer Reminder: 15 Minutes to {p_name}",
                        f"{p_name} prayer time is at {t_str} (in 15 minutes). Time to move and prepare for prayer."
                    )

                # 2. 5 Minutes Before Prayer Time
                elif 240 <= diff_sec <= 310 and stage_5 not in notif_state:
                    notif_state[stage_5] = True
                    save_notif_state(notif_state)
                    send_prayer_notification(
                        f"Prayer Alert: 5 Minutes Left",
                        f"5 minutes remaining until {p_name} ({t_str}). Time to move to the prayer area."
                    )

                # 3. 3 Minutes Before Prayer Time
                elif 120 <= diff_sec <= 190 and stage_3 not in notif_state:
                    notif_state[stage_3] = True
                    save_notif_state(notif_state)
                    send_prayer_notification(
                        f"Prayer Alert: 3 Minutes Left",
                        f"3 minutes remaining until {p_name} ({t_str}). Please wrap up your activity and get ready to pray."
                    )

                # 4. When Prayer Time Arrives (0 Minutes)
                elif -30 <= diff_sec <= 45 and stage_0 not in notif_state:
                    notif_state[stage_0] = True
                    save_notif_state(notif_state)
                    send_prayer_notification(
                        f"Time for {p_name} Prayer!",
                        f"It is now time for {p_name} prayer ({t_str}). Let us pause and move to pray."
                    )

        except Exception:
            pass

        time.sleep(15)

# ---------------------------------------------------------------------------
# CLI Handling
# ---------------------------------------------------------------------------
def main():
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "--daemon":
            run_daemon()
        elif cmd == "--test-notif":
            stage = sys.argv[2] if len(sys.argv) > 2 else "15m"
            if stage == "15m":
                send_prayer_notification(
                    "Prayer Reminder: 15 Minutes to Maghrib",
                    "Maghrib prayer time is at 17:58 (in 15 minutes). Time to move and prepare for prayer."
                )
            elif stage == "5m":
                send_prayer_notification(
                    "Prayer Alert: 5 Minutes Left",
                    "5 minutes remaining until Maghrib (17:58). Time to move to the prayer area."
                )
            elif stage == "3m":
                send_prayer_notification(
                    "Prayer Alert: 3 Minutes Left",
                    "3 minutes remaining until Maghrib (17:58). Please wrap up your activity and get ready to pray."
                )
            else:
                send_prayer_notification(
                    "Time for Maghrib Prayer!",
                    "It is now time for Maghrib prayer (17:58). Let us pause and move to pray."
                )
            print("Notification sent")
        elif cmd == "--get-data":
            res = get_complete_data(force_refresh=False)
            print(json.dumps(res, ensure_ascii=False))
        elif cmd == "--refresh":
            res = get_complete_data(force_refresh=True)
            print(json.dumps(res, ensure_ascii=False))
        elif cmd == "--auto-detect":
            prov, city = detect_ip_location()
            cfg = {"auto_detect": True, "provinsi": prov, "kabkota": city}
            save_config(cfg)
            res = get_complete_data(force_refresh=True)
            print(json.dumps(res, ensure_ascii=False))
        elif cmd == "--set-location":
            if len(sys.argv) >= 4:
                prov = sys.argv[2]
                city = sys.argv[3]
                cfg = {"auto_detect": False, "provinsi": prov, "kabkota": city}
                save_config(cfg)
                res = get_complete_data(force_refresh=True)
                print(json.dumps(res, ensure_ascii=False))
            else:
                print(json.dumps({"status": "error", "message": "Usage: --set-location <provinsi> <kabkota>"}))
        elif cmd == "--get-provinces":
            provs = api_get_provinces()
            print(json.dumps(provs, ensure_ascii=False))
        elif cmd == "--get-cities":
            prov = sys.argv[2] if len(sys.argv) > 2 else "DKI Jakarta"
            cities = api_get_kabkota(prov)
            print(json.dumps(cities, ensure_ascii=False))
        else:
            print(json.dumps({"status": "error", "message": f"Unknown command {cmd}"}))
    else:
        res = get_complete_data(force_refresh=False)
        print(json.dumps(res, ensure_ascii=False))

if __name__ == "__main__":
    main()
