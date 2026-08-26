#!/usr/bin/env python3
import subprocess
import json
import os

def get_storage_info():
    partitions = []
    try:
        # Run df in POSIX format (-P)
        cmd = ["df", "-h", "-P", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "squashfs"]
        out = subprocess.run(cmd, capture_output=True, text=True).stdout
        lines = out.strip().split("\n")

        root_device = None
        seen_devices = set()

        for line in lines[1:]:
            parts = line.split()
            if len(parts) >= 6:
                device = parts[0]
                size = parts[1]
                used = parts[2]
                avail = parts[3]
                use_str = parts[4].replace("%", "")
                mount = parts[5]

                try:
                    use_pct = int(use_str)
                except ValueError:
                    use_pct = 0

                # Root partition /
                if mount == "/":
                    root_device = device
                    seen_devices.add(device)
                    partitions.append({
                        "device": device,
                        "mount": mount,
                        "name": "Root (/)",
                        "size": size,
                        "used": used,
                        "avail": avail,
                        "usePct": use_pct
                    })
                # Other physical drive partitions or mounts (/dev/sd*, /dev/nvme*, /dev/mmcblk*, USB mounts)
                elif device != root_device and (
                    device.startswith("/dev/sd") or 
                    device.startswith("/dev/nvme") or 
                    device.startswith("/dev/mmc") or 
                    mount.startswith("/run/media") or 
                    mount.startswith("/media") or 
                    mount.startswith("/mnt")
                ):
                    if mount not in seen_devices:
                        seen_devices.add(mount)
                        # Clean label
                        label = mount
                        if mount.startswith("/run/media/"):
                            label = "USB (" + mount.split("/")[-1] + ")"
                        elif mount.startswith("/media/"):
                            label = "Media (" + mount.split("/")[-1] + ")"
                        elif mount.startswith("/mnt/"):
                            label = "Drive (" + mount.split("/")[-1] + ")"
                        else:
                            label = device

                        partitions.append({
                            "device": device,
                            "mount": mount,
                            "name": label,
                            "size": size,
                            "used": used,
                            "avail": avail,
                            "usePct": use_pct
                        })
    except Exception:
        pass

    print(json.dumps(partitions))

if __name__ == "__main__":
    get_storage_info()
