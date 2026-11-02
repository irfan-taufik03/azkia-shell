#!/usr/bin/env python3
import json
import subprocess
import os

def get_app_name(comm, args):
    comm_lower = comm.lower()
    args_lower = args.lower()
    
    # 1. Known signature overrides
    if "floorp" in comm_lower or "floorp" in args_lower:
        return "Floorp"
    if "thorium" in comm_lower or "thorium" in args_lower:
        return "Thorium"
    if "firefox" in comm_lower or "firefox" in args_lower:
        return "Firefox"
    if "chrome" in comm_lower or "chrome" in args_lower:
        return "Google Chrome"
    if "chromium" in comm_lower or "chromium" in args_lower:
        return "Chromium"
    if "code" in comm_lower or "/code" in args_lower or "vscode" in args_lower:
        return "VS Code"
    if "antigravity" in comm_lower or "antigravity" in args_lower:
        return "Antigravity"
    if "quickshell" in comm_lower or "quickshell" in args_lower:
        return "Quickshell"
    if "azkia_audio_player" in comm_lower or "azkia_audio_player" in args_lower:
        return "Azkia Audio Player"
    if "discord" in comm_lower or "discord" in args_lower:
        return "Discord"
    if "spotify" in comm_lower or "spotify" in args_lower:
        return "Spotify"
    if "bspwm" in comm_lower:
        return "BSPWM"
    if "sxhkd" in comm_lower:
        return "SXHKD"
    if "polybar" in comm_lower:
        return "Polybar"
    if "pipewire" in comm_lower or "wireplumber" in comm_lower:
        return "PipeWire"
        
    # 2. If comm is a generic sub-process name, try to extract app name from args
    generic_names = ["web content", "webextensions", "rdd process", "privileged cont", "socket process", "utility process", "isolated web co", "gpu-process", "renderer", "zygote"]
    if any(gn in comm_lower for gn in generic_names):
        parts = args.split()
        for p in parts:
            if "/" in p and not p.startswith("-"):
                bname = os.path.basename(p)
                if bname.lower() not in ["python", "python3", "node", "sh", "bash", "exe"]:
                    return bname.capitalize() if bname.islower() else bname

    # 3. Fallback to comm basename, formatted nicely
    bname = os.path.basename(comm)
    if bname.islower() and len(bname) > 2:
        return bname.capitalize()
    return bname

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

    # Top processes using ps -eo pid,%cpu,rss,comm,args
    try:
        out = subprocess.check_output(
            ["ps", "-eo", "pid,%cpu,rss,comm,args", "--sort=-rss"],
            text=True
        )
        lines = out.strip().split("\n")[1:]
        
        grouped = {}
        for line in lines:
            parts = line.strip().split(None, 4)
            if len(parts) >= 4:
                pid, cpu_str, rss_str, comm = parts[0], parts[1], parts[2], parts[3]
                args = parts[4] if len(parts) >= 5 else comm
                
                try:
                    cpu_val = float(cpu_str)
                    rss_kb = int(rss_str)
                except ValueError:
                    continue
                
                app_name = get_app_name(comm, args)
                key = app_name.lower()
                
                if key not in grouped:
                    grouped[key] = {
                        "name": app_name,
                        "cpu": 0.0,
                        "rss_kb": 0,
                        "pids": [],
                        "count": 0
                    }
                
                grouped[key]["cpu"] += cpu_val
                grouped[key]["rss_kb"] += rss_kb
                grouped[key]["pids"].append(pid)
                grouped[key]["count"] += 1
        
        # Sort grouped processes by RAM (rss_kb) descending
        sorted_procs = sorted(grouped.values(), key=lambda x: x["rss_kb"], reverse=True)
        
        procs = []
        for item in sorted_procs:
            cpu_val = round(item["cpu"], 1)
            rss_mb = round(item["rss_kb"] / 1024, 1)
            if rss_mb <= 0.0 and cpu_val <= 0.0:
                continue

            if rss_mb >= 1024:
                ram_str = f"{round(rss_mb / 1024, 1)} GB"
            else:
                ram_str = f"{rss_mb} MB"
            
            pid_str = item["pids"][0] if item["count"] == 1 else f"{item['pids'][0]} ({item['count']})"

            procs.append({
                "pid": pid_str,
                "cpu": cpu_val,
                "rss_mb": rss_mb,
                "ram_str": ram_str,
                "name": item["name"]
            })
            
        data["top_processes"] = procs
    except Exception:
        pass

    print(json.dumps(data))

if __name__ == "__main__":
    get_sys_info()
