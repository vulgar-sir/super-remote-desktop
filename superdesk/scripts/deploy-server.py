"""Deploy / update the super远程桌面 server stack on the server (/opt/superdesk).

1. prepares rustdesk-server 1.1.16 source + superdesk/server/hbbs/tcp-register.patch and
   proto-webrtc.patch (patched hbbs: TCP/WebSocket registration, WebRTC P2P signalling)
2. uploads docker-compose.yml, nginx template, .env.example, console/, hbbs build context
3. docker compose up -d --build   (existing .env and data/ on the server are kept)

Usage: python superdesk/scripts/deploy-server.py [--no-build]
"""
import argparse
import io
import os
import subprocess
import sys
import tarfile

sys.path.insert(0, os.path.dirname(__file__))
import sdssh  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SD_HOME = os.environ.get("SUPERDESK_HOME", r"D:\superdesk")
HBBS_SRC = os.path.join(SD_HOME, "tools", "rustdesk-server")
HBBS_TAG = "1.1.16"
REMOTE = "/opt/superdesk"
PATCH = os.path.join(ROOT, "superdesk", "server", "hbbs", "tcp-register.patch")
PROTO_PATCH = os.path.join(ROOT, "superdesk", "server", "hbbs", "proto-webrtc.patch")
HBB_COMMON = os.path.join(HBBS_SRC, "libs", "hbb_common")


def git(*args, cwd=HBBS_SRC):
    subprocess.run(["git", *args], cwd=cwd, check=True)


def prepare_hbbs():
    if not os.path.isdir(os.path.join(HBBS_SRC, ".git")):
        git("clone", "--depth", "1", "--branch", HBBS_TAG, "--recurse-submodules", "--shallow-submodules",
            "https://github.com/rustdesk/rustdesk-server.git", HBBS_SRC, cwd=SD_HOME)
        git("config", "core.autocrlf", "false")
    git("checkout", "--", ".")
    git("submodule", "update", "--init", "--recursive")
    git("apply", PATCH)
    # The proto lives in the hbb_common submodule (LF checkout, like the parent).
    git("config", "core.autocrlf", "false", cwd=HBB_COMMON)
    git("checkout", "--", ".", cwd=HBB_COMMON)
    git("apply", PROTO_PATCH, cwd=HBB_COMMON)
    # Vendor all dependencies (some are git deps on GitHub, unreachable from the server).
    # Written next to the source (the repo tracks its own .cargo/config.toml); the Dockerfile
    # installs it as the global cargo config.
    cfg = os.path.join(HBBS_SRC, "vendor-config.toml")
    if not (os.path.isdir(os.path.join(HBBS_SRC, "vendor")) and os.path.exists(cfg)):
        out = subprocess.run(["cargo", "vendor", "--locked", "vendor"], cwd=HBBS_SRC, check=True,
                             capture_output=True, text=True).stdout
        with open(cfg, "w", encoding="utf-8") as f:
            f.write(out)


def tar_dir(src, skip_top=(), skip_any=(".git", "__pycache__")):
    """gzip tarball of src. skip_any: dir names skipped at any depth; skip_top: only at the top
    (vendored crates contain tests/ dirs that their checksums cover)."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for base, dirs, files in os.walk(src):
            top = os.path.abspath(base) == os.path.abspath(src)
            dirs[:] = [d for d in dirs if d not in skip_any and not (top and d in ("target", *skip_top))]
            for f in files:
                if f.endswith(".pyc"):  # keep db_v2.sqlite3: sqlx checks queries against it at build time
                    continue
                full = os.path.join(base, f)
                # Windows has no exec bit: mark everything executable (build scripts like
                # ./configure in vendored crates need it; content checksums are unaffected).
                tar.add(full, arcname=os.path.relpath(full, src).replace("\\", "/"),
                        filter=lambda ti: (setattr(ti, "mode", 0o755), ti)[1])
    return buf.getvalue()


def upload_tree(c, local_dir, remote_dir, name, skip_top=()):
    data = tar_dir(local_dir, skip_top=skip_top)
    tmp = os.path.join(SD_HOME, f"{name}.tgz")
    with open(tmp, "wb") as f:
        f.write(data)
    sdssh.put(c, tmp, f"/tmp/{name}.tgz")
    sdssh.run(c, f"rm -rf {remote_dir} && mkdir -p {remote_dir} && tar -xzf /tmp/{name}.tgz -C {remote_dir} && rm /tmp/{name}.tgz")
    os.remove(tmp)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-build", action="store_true")
    ap.add_argument("--console-only", action="store_true", help="only update and rebuild super控制台")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    if args.console_only:
        c = sdssh.connect()
        try:
            upload_tree(c, os.path.join(ROOT, "superdesk", "console"), f"{REMOTE}/console", "console", skip_top=("tests",))
            sys.exit(sdssh.run(c, f"cd {REMOTE} && docker compose up -d --build console 2>&1 | tail -3"))
        finally:
            c.close()

    prepare_hbbs()
    c = sdssh.connect()
    try:
        srv = os.path.join(ROOT, "superdesk", "server")
        for f in ("docker-compose.yml", "nginx.conf.template", ".env.example"):
            sdssh.put(c, os.path.join(srv, f), f"{REMOTE}/{f}")
        upload_tree(c, os.path.join(ROOT, "superdesk", "console"), f"{REMOTE}/console", "console", skip_top=("tests",))
        upload_tree(c, HBBS_SRC, f"{REMOTE}/hbbs-build", "hbbs-src")
        sdssh.put(c, os.path.join(srv, "hbbs", "Dockerfile"), f"{REMOTE}/hbbs-build/Dockerfile")
        sdssh.run(c, f"mkdir -p {REMOTE}/download {REMOTE}/data/console")
        if not args.no_build:
            code = sdssh.run(c, f"cd {REMOTE} && docker compose up -d --build 2>&1 | tail -15 && docker compose ps --format '{{{{.Name}}}} {{{{.Status}}}}'")
            sys.exit(code)
    finally:
        c.close()


if __name__ == "__main__":
    main()
