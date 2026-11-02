#!/usr/bin/env python3
import subprocess
import json

def get_storage_info():
    partitions = []
    try:
        cmd = ["df", "-h", "-P", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "squashfs"]
        out = subprocess.run(cmd, capture_output=True, text=True).stdout
        seen_devices = set()

        for line in out.strip().splitlines()[1:]:
            parts = line.split()
            if len(parts) < 6:
                continue
            device, size, used, avail, use_str, mount = parts[:6]
            pct = use_str.rstrip("%")
            use_pct = int(pct) if pct.isdigit() else 0

            if mount == "/":
                seen_devices.add(device)
                label = "Root (/)"
            elif device.startswith(("/dev/sd", "/dev/nvme", "/dev/mmc")) or mount.startswith(("/run/media", "/media", "/mnt")):
                if mount in seen_devices:
                    continue
                seen_devices.add(mount)
                suffix = mount.rsplit("/", 1)[-1]
                if mount.startswith("/run/media/"): label = f"USB ({suffix})"
                elif mount.startswith("/media/"):    label = f"Media ({suffix})"
                elif mount.startswith("/mnt/"):      label = f"Drive ({suffix})"
                else:                                label = device
            else:
                continue

            partitions.append({
                "device": device, "mount": mount, "name": label,
                "size": size, "used": used, "avail": avail, "usePct": use_pct
            })
    except Exception:
        pass

    print(json.dumps(partitions))

if __name__ == "__main__":
    get_storage_info()
