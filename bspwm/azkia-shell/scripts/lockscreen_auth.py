#!/usr/bin/env python3
import sys
import getpass
import subprocess

def check_password(password):
    if not password:
        return False
    username = getpass.getuser()

    # Try /usr/sbin/unix_chkpwd
    for chk in ["/usr/sbin/unix_chkpwd", "/sbin/unix_chkpwd", "unix_chkpwd"]:
        try:
            proc = subprocess.Popen([chk, username, "nullok"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            out, err = proc.communicate(input=(password + "\0").encode())
            if proc.returncode == 0:
                return True
        except Exception:
            pass

    # Try PAM via python pam module
    try:
        import pam
        p = pam.pam()
        if p.authenticate(username, password):
            return True
    except Exception:
        pass

    return False

if __name__ == "__main__":
    pwd = ""
    if len(sys.argv) > 1:
        pwd = sys.argv[1]
    else:
        pwd = sys.stdin.read().strip("\r\n")

    if check_password(pwd):
        print("SUCCESS")
        sys.exit(0)
    else:
        print("FAIL")
        sys.exit(1)
