#!/usr/bin/env python3
import json
import os
import platform
import subprocess

def get_sys_fetch():
    # 1. Distro Name
    distro = "Linux"
    if os.path.exists("/etc/os-release"):
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    distro = line.split("=", 1)[1].strip("\"'\n")
                    break

    # 2. Kernel Version
    kernel = platform.release()

    # 3. Window Manager
    wm = "BSPWM"

    # 4. Desktop Shell
    shell = "Azkia Shell"

    # 5. Host Model
    vendor = ""
    product = ""
    for p in ["/sys/class/dmi/id/sys_vendor", "/sys/devices/virtual/dmi/id/sys_vendor"]:
        if os.path.exists(p):
            try:
                with open(p) as f:
                    v = f.read().strip()
                    if v and v not in ["To be filled by O.E.M.", "Default string"]:
                        vendor = v
                        break
            except: pass

    for p in ["/sys/class/dmi/id/product_name", "/sys/devices/virtual/dmi/id/product_name"]:
        if os.path.exists(p):
            try:
                with open(p) as f:
                    val = f.read().strip()
                    if val and val not in ["To be filled by O.E.M.", "Default string", "System Product Name"]:
                        product = val
                        break
            except: pass

    host = f"{vendor} {product}".strip()
    if not host:
        host = platform.node() or "Linux PC"

    # 6. CPU Model
    cpu = "Unknown CPU"
    if os.path.exists("/proc/cpuinfo"):
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "model name" in line:
                    cpu = line.split(":", 1)[1].strip()
                    break

    # 7. Total RAM & Memory Usage
    ram_total = "0 GB"
    ram_used = "0 GB"
    ram_str = "0 GB"
    if os.path.exists("/proc/meminfo"):
        try:
            with open("/proc/meminfo") as f:
                mem = {}
                for line in f:
                    parts = line.split(":")
                    if len(parts) == 2:
                        k = parts[0].strip()
                        v = parts[1].strip().split()[0]
                        mem[k] = int(v)
                total_kb = mem.get("MemTotal", 0)
                avail_kb = mem.get("MemAvailable", 0)
                used_kb = total_kb - avail_kb
                
                total_gb = round(total_kb / (1024 * 1024), 1)
                used_gb = round(used_kb / (1024 * 1024), 1)
                
                ram_total = f"{total_gb} GB"
                ram_used = f"{used_gb} GB"
                ram_str = f"{used_gb} GB / {total_gb} GB"
        except: pass

    # 8. System Uptime
    uptime_str = ""
    if os.path.exists("/proc/uptime"):
        try:
            with open("/proc/uptime") as f:
                secs = float(f.read().split()[0])
                hrs = int(secs // 3600)
                mins = int((secs % 3600) // 60)
                if hrs > 0:
                    uptime_str = f"{hrs}h {mins}m"
                else:
                    uptime_str = f"{mins}m"
        except: pass

    res = {
        "distro": distro,
        "kernel": kernel,
        "wm": wm,
        "shell": shell,
        "host": host,
        "cpu": cpu,
        "ram": ram_total,
        "ram_str": ram_str,
        "uptime": uptime_str
    }

    print(json.dumps(res))

if __name__ == "__main__":
    get_sys_fetch()
