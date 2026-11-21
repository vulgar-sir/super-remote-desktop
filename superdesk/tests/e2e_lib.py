"""Helpers for end-to-end testing the Windows clients against the real server + console."""
import ctypes
import json
import os
import re
import sys
import time
import urllib.request

import pyautogui
import win32con
import win32gui
from PIL import ImageGrab

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ctypes.windll.user32.SetProcessDPIAware()
pyautogui.FAILSAFE = False
_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def secrets():
    with open(os.path.join(ROOT, "secrets", "superdesk.json"), encoding="utf-8") as f:
        s = json.load(f)
    with open(os.path.join(ROOT, "secrets", "console-admin.txt"), encoding="utf-8") as f:
        pw = [l.split("=", 1)[1].strip() for l in f if l.startswith("password=")][0]
    return s["api_server"].rstrip("/"), pw


class Console:
    def __init__(self):
        self.base, pw = secrets()
        self.token = self.call("POST", "/api/admin/login", {"username": "admin", "password": pw})["token"]

    def call(self, method, path, body=None):
        req = urllib.request.Request(self.base + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None)
        req.add_header("Content-Type", "application/json")
        if getattr(self, "token", None):
            req.add_header("Authorization", "Bearer " + self.token)
        with _opener.open(req, timeout=20) as r:
            raw = r.read()
        try:
            return json.loads(raw or b"{}")
        except ValueError:
            return raw.decode()


def windows(title_part):
    found = []

    def cb(h, _):
        if win32gui.IsWindowVisible(h) and title_part in win32gui.GetWindowText(h):
            found.append(h)
    win32gui.EnumWindows(cb, None)
    return found


def wait_window(title_part, timeout=90):
    end = time.time() + timeout
    while time.time() < end:
        w = windows(title_part)
        if w:
            return w[0]
        time.sleep(1)
    raise TimeoutError(f"window '{title_part}' did not appear")


def rect(h):
    return win32gui.GetWindowRect(h)


def focus(h):
    try:
        win32gui.ShowWindow(h, win32con.SW_RESTORE)
        win32gui.SetForegroundWindow(h)
    except Exception:  # noqa: BLE001 -- foreground lock; clicking still works
        pass
    time.sleep(0.5)


def shot(h, path):
    l, t, r, b = rect(h)
    ImageGrab.grab(bbox=(l, t, r, b), all_screens=True).save(path)
    return path


def click_rel(h, fx, fy):
    """Click at a fraction (fx, fy) of the window's size."""
    l, t, r, b = rect(h)
    pyautogui.click(l + int((r - l) * fx), t + int((b - t) * fy))
    time.sleep(0.6)


# --- connection transport (P2P vs relay) ------------------------------------------------------
# The client rotates its log on every start (one process per --connect), so search every log
# file under its log directory by timestamp instead of following one file.
CLIENT_LOG_DIR = os.path.join(os.environ.get("APPDATA", ""), "SuperDesk", "log")
_TRANSPORT = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\.\d+ [^\]]*\] .*used to establish (\w+) connection")


def client_transport(since):
    """Transport of the last session the full client established after epoch time `since`:
    "WebRTC" (P2P), "WebSocket"/"Relay" (through the server) or "" if none was logged."""
    found = []
    for base, _, files in os.walk(CLIENT_LOG_DIR):
        for name in files:
            path = os.path.join(base, name)
            if not name.endswith(".log") or os.path.getmtime(path) < since - 5:
                continue
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    m = _TRANSPORT.match(line)
                    if m and time.mktime(time.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")) >= since - 1:
                        found.append((m.group(1), m.group(2)))
    return max(found)[1] if found else ""


def gateway_kbytes(seconds):
    """KB that crossed the server's single public port (both directions) during `seconds`,
    counted by tcpdump on the server: a relayed session carries its video there, P2P does not."""
    sys.path.insert(0, os.path.join(ROOT, "superdesk", "scripts"))
    import sdssh
    with open(os.path.join(ROOT, "secrets", "superdesk.json"), encoding="utf-8") as f:
        port = int(json.load(f)["ws_port"])
    iface = os.environ.get("SUPERDESK_IFACE", "eth0")
    c = sdssh.connect()
    try:
        _, out, _ = c.exec_command(
            f"timeout {seconds} tcpdump -ni {iface} -q 'tcp port {port}' 2>/dev/null"
            " | awk '{s+=$NF} END {print int(s/1024)}'", timeout=seconds + 20)
        return int(out.read().decode().strip() or 0)
    finally:
        c.close()
