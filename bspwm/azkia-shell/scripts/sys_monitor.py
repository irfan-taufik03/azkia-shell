#!/usr/bin/env python3
import json
import subprocess
import os

def get_sys_info():
    data = {
        "cpu_count": os.cpu_count() or 1,
        "mem_total_gb": 0.0,
        "mem_used_gb": 0.0,
        "mem_percent": 0.0,
        "swap_total_gb": 0.0,
        "swap_used_gb": 0.0,
        "swap_percent": 0.0,
        "top_processes": []
    }

    # Memory & Swap info from /proc/meminfo
    try:
        with open("/proc/meminfo", "r") as f:
            mem = {}
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    k = parts[0].strip()
                    v = parts[1].strip().split()[0]
                    mem[k] = int(v)
            total = mem.get("MemTotal", 1)
            avail = mem.get("MemAvailable", 0)
            used = total - avail
            data["mem_total_gb"] = round(total / (1024 * 1024), 1)
            data["mem_used_gb"] = round(used / (1024 * 1024), 1)
            data["mem_percent"] = round((used / total) * 100, 1)

            stotal = mem.get("SwapTotal", 0)
            sfree = mem.get("SwapFree", 0)
            sused = stotal - sfree
            data["swap_total_gb"] = round(stotal / (1024 * 1024), 1)
            data["swap_used_gb"] = round(sused / (1024 * 1024), 1)
            data["swap_percent"] = round((sused / stotal) * 100, 1) if stotal > 0 else 0.0
    except Exception:
        pass

    # Top processes using ps -eo pid,%cpu,rss,comm
    try:
        out = subprocess.check_output(
            ["ps", "-eo", "pid,%cpu,rss,comm", "--sort=-rss"],
            text=True
        )
        lines = out.strip().split("\n")[1:101]
        procs = []
        for line in lines:
            parts = line.strip().split(None, 3)
            if len(parts) == 4:
                pid, cpu_str, rss_str, name = parts
                name = os.path.basename(name)
                cpu_val = round(float(cpu_str), 1)
                rss_kb = int(rss_str)
                rss_mb = round(rss_kb / 1024, 1)
                if rss_mb >= 1024:
                    ram_str = f"{round(rss_mb / 1024, 1)} GB"
                else:
                    ram_str = f"{rss_mb} MB"

                procs.append({
                    "pid": pid,
                    "cpu": cpu_val,
                    "rss_mb": rss_mb,
                    "ram_str": ram_str,
                    "name": name
                })
        data["top_processes"] = procs
    except Exception:
        pass

    print(json.dumps(data))

if __name__ == "__main__":
    get_sys_info()
