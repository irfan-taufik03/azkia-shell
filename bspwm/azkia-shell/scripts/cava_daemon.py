#!/usr/bin/env python3
import os
import sys
import tempfile
import subprocess
import json
import signal

CONFIG_CONTENT = """
[general]
bars = 19
framerate = 30

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
bar_delimiter = 59
"""

def main():
    with tempfile.NamedTemporaryFile('w', delete=False, suffix='.conf') as f:
        f.write(CONFIG_CONTENT)
        config_path = f.name

    def cleanup(signum=None, frame=None):
        if os.path.exists(config_path):
            try:
                os.remove(config_path)
            except Exception:
                pass
        sys.exit(0)

    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    try:
        proc = subprocess.Popen(['cava', '-p', config_path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        while True:
            line = proc.stdout.readline()
            if not line:
                break
            parts = [int(x) for x in line.strip().split(';') if x.strip().isdigit()]
            if parts:
                print(json.dumps(parts), flush=True)
    except Exception as e:
        sys.stderr.write(str(e) + '\n')
    finally:
        cleanup()

if __name__ == "__main__":
    main()
