"""SSH helper for the super远程桌面 server (deploy server files, publish downloads).

Credentials come from the git-ignored file in the repo root
    服务器地址----不准放入git仓库.txt   line 1: "<ip>:<ssh_port>   <user>   <password>   ..."
and are never printed.

Usage:
    python sdssh.py run "<shell command>"
    python sdssh.py put <local_file> <remote_path>
    python sdssh.py putdir <local_dir> <remote_dir>      (recursive, overwrites)
"""
import os
import re
import sys
import warnings

warnings.filterwarnings("ignore")
import paramiko  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SECRETS = os.path.join(ROOT, "服务器地址----不准放入git仓库.txt")
KNOWN_HOSTS = os.path.join(ROOT, "secrets", "known_hosts")


def load_creds():
    with open(SECRETS, encoding="utf-8") as f:
        first = f.readline()
    m = re.match(r"\s*([\w.\-]+):(\d+)\s+(\S+)\s+(\S+)", first)
    if not m:
        sys.exit("cannot parse line 1 of the server credentials file")
    return m.group(1), int(m.group(2)), m.group(3), m.group(4)


def connect():
    host, port, user, pw = load_creds()
    c = paramiko.SSHClient()
    os.makedirs(os.path.dirname(KNOWN_HOSTS), exist_ok=True)
    if os.path.exists(KNOWN_HOSTS):
        c.load_host_keys(KNOWN_HOSTS)
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, port=port, username=user, password=pw, timeout=20,
              allow_agent=False, look_for_keys=False)
    c.save_host_keys(KNOWN_HOSTS)
    return c


def run(c, cmd, timeout=3600):
    _, out, err = c.exec_command(cmd, timeout=timeout)
    for line in iter(out.readline, ""):
        print(line, end="")
    e = err.read().decode("utf-8", "replace")
    if e:
        print(e, end="", file=sys.stderr)
    return out.channel.recv_exit_status()


def _mkdirs(sftp, path):
    parts = path.rstrip("/").split("/")
    cur = ""
    for p in parts:
        if not p:
            cur = "/"
            continue
        cur = cur.rstrip("/") + "/" + p
        try:
            sftp.stat(cur)
        except IOError:
            sftp.mkdir(cur)


def put(c, local, remote):
    sftp = c.open_sftp()
    try:
        _mkdirs(sftp, os.path.dirname(remote))
        sftp.put(local, remote)
    finally:
        sftp.close()
    print(f"uploaded {os.path.basename(local)} -> {remote}")


def putdir(c, local, remote):
    sftp = c.open_sftp()
    try:
        for base, _, files in os.walk(local):
            rel = os.path.relpath(base, local).replace("\\", "/")
            rdir = remote if rel == "." else f"{remote}/{rel}"
            _mkdirs(sftp, rdir)
            for f in files:
                sftp.put(os.path.join(base, f), f"{rdir}/{f}")
                print(f"uploaded {rel}/{f}")
    finally:
        sftp.close()


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    c = connect()
    try:
        cmd = sys.argv[1]
        if cmd == "run":
            sys.exit(run(c, sys.argv[2]))
        elif cmd == "put":
            put(c, sys.argv[2], sys.argv[3])
        elif cmd == "putdir":
            putdir(c, sys.argv[2], sys.argv[3])
        else:
            sys.exit(__doc__)
    finally:
        c.close()


if __name__ == "__main__":
    main()
