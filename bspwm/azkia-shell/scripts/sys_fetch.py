#!/usr/bin/env python3
import json
import os
import platform
import getpass

def read_val(path, ignore=("To be filled by O.E.M.", "Default string", "System Product Name")):
    try:
        with open(path) as f:
            v = f.read().strip()
            return v if v and v not in ignore else ""
    except Exception:
        return ""

def get_sys_fetch():
    # 1. Distro Name
    distro = "Linux"
    if os.path.exists("/etc/os-release"):
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    distro = line.split("=", 1)[1].strip("\"'\n")
                    break

    # 2. Host Model
    vendor = read_val("/sys/class/dmi/id/sys_vendor") or read_val("/sys/devices/virtual/dmi/id/sys_vendor")
    product = read_val("/sys/class/dmi/id/product_name") or read_val("/sys/devices/virtual/dmi/id/product_name")
    host = f"{vendor} {product}".strip() or platform.node() or "Linux PC"

    # 3. CPU Model
    cpu = "Unknown CPU"
    if os.path.exists("/proc/cpuinfo"):
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "model name" in line:
                    cpu = line.split(":", 1)[1].strip()
                    break

    # 4. Total RAM & Memory Usage
    ram_total = ram_str = "0 GB"
    if os.path.exists("/proc/meminfo"):
        try:
            mem = {}
            with open("/proc/meminfo") as f:
                for line in f:
                    p = line.split(":")
                    if len(p) == 2 and p[0].strip() in ("MemTotal", "MemAvailable"):
                        mem[p[0].strip()] = int(p[1].split()[0])
            total_kb, avail_kb = mem.get("MemTotal", 0), mem.get("MemAvailable", 0)
            total_gb = round(total_kb / 1048576, 1)
            used_gb = round((total_kb - avail_kb) / 1048576, 1)
            ram_total = f"{total_gb} GB"
            ram_str = f"{used_gb} GB / {total_gb} GB"
        except Exception:
            pass

    # 5. System Uptime
    uptime_str = uptime_full = ""
    if os.path.exists("/proc/uptime"):
        try:
            with open("/proc/uptime") as f:
                secs = float(f.read().split()[0])
            days, rem = divmod(int(secs), 86400)
            hrs, mins = divmod(rem, 3600)
            mins //= 60

            parts = []
            if days: parts.append(f"{days} {'day' if days == 1 else 'days'}")
            if hrs:  parts.append(f"{hrs} {'hour' if hrs == 1 else 'hours'}")
            if mins or not parts: parts.append(f"{mins} {'minute' if mins == 1 else 'minutes'}")
            uptime_full = ", ".join(parts)
            uptime_str = f"{days}d {hrs}h {mins}m" if days else (f"{hrs}h {mins}m" if hrs else f"{mins}m")
        except Exception:
            pass

    # 6. Current User
    try:
        current_user = getpass.getuser()
    except Exception:
        current_user = os.environ.get("USER", "vaan")

    res = {
        "user": current_user,
        "distro": distro,
        "kernel": platform.release(),
        "wm": "BSPWM",
        "shell": "Azkia Shell",
        "host": host,
        "cpu": cpu,
        "ram": ram_total,
        "ram_str": ram_str,
        "uptime": uptime_str,
        "uptime_full": uptime_full
    }
    print(json.dumps(res))

if __name__ == "__main__":
    get_sys_fetch()
