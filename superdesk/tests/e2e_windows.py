"""End-to-end test on a Windows machine: deploy script -> unattended connect -> audit -> policy.

WARNING: installs the helper as a Windows service on THIS machine (uninstalled at the end).
Needs: admin rights, a published helper build on the server, and an unpacked full client
(SUPERDESK_FULL_EXE, default D:\\superdesk\\test\\full\\SuperDesk.exe or rustdesk.exe) to connect from.

Usage: python superdesk/tests/e2e_windows.py
"""
import os
import secrets
import string
import subprocess
import sys
import time
import urllib.parse

import e2e_lib as e

HELPER = "SuperDeskHelper"
PF = os.environ.get("ProgramFiles", r"C:\Program Files")
INSTALLED = os.path.join(PF, HELPER, f"{HELPER}.exe")
FULL_EXE = os.environ.get("SUPERDESK_FULL_EXE") or next(
    (p for p in (r"D:\superdesk\test\full\SuperDesk.exe", r"D:\superdesk\test\full\rustdesk.exe") if os.path.exists(p)), "")
GROUP = "E2E策略测试"
GROUP_Q = urllib.parse.quote(GROUP)
fails = 0


def check(name, cond, detail=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f"  -> {detail}"), flush=True)
    fails += 0 if cond else 1


def ps51(cmd, timeout=900):
    exe = os.path.join(os.environ["SystemRoot"], r"System32\WindowsPowerShell\v1.0\powershell.exe")
    r = subprocess.run([exe, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd],
                       capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    return r.returncode, r.stdout + r.stderr


def latest_conn(c, device_id):
    rows = c.call("GET", f"/api/admin/audit/conn?size=5&q={device_id}")["data"]
    return rows[0] if rows else None


def connect_and_wait(c, device_id, password, expect_ok, seconds=40):
    before = latest_conn(c, device_id)
    before_id = before["id"] if before else 0
    subprocess.Popen([FULL_EXE, "--connect", device_id, "--password", password])
    end = time.time() + seconds
    while time.time() < end:
        time.sleep(2)
        a = latest_conn(c, device_id)
        if a and a["id"] > before_id and a["authorized_at"]:
            return a
    return None


def close_remote_windows():
    for h in e.windows("Remote Desktop"):
        e.win32gui.PostMessage(h, e.win32con.WM_CLOSE, 0, 0)


def main():
    c = e.Console()
    pw = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16))
    check("full client available", bool(FULL_EXE), FULL_EXE)

    # 1. deploy script, exactly as on an employee PC (Windows PowerShell 5.1, published one-liner)
    code, out = ps51(f"iwr {c.base}/download/deploy-superdesk.ps1 -OutFile $env:TEMP\\d.ps1 -UseBasicParsing; "
                     f"& $env:TEMP\\d.ps1 -Password '{pw}' -Note 'e2e'")
    print(out[-800:])
    check("deploy script succeeded", code == 0 and "部署完成" in out, out[-300:])
    dev_id = out.split("ID = ")[-1].strip().split()[0] if "ID = " in out else ""
    check("installed exe + service", os.path.exists(INSTALLED) and "RUNNING" in subprocess.run(
        ["sc", "query", HELPER], capture_output=True, text=True).stdout)
    deploys = c.call("GET", "/api/admin/deploy?size=3")["data"]
    check("deploy reported to console", any(d["device_id"] == dev_id and d["note"] == "e2e" for d in deploys), deploys[:1])

    # 2. unattended access with the fixed password
    t0 = time.time()
    a = connect_and_wait(c, dev_id, pw, True)
    check("unattended connect with fixed password (audited)", a is not None and a["type"] == 0)
    # 2a. P2P: signalling goes over the single port, the session itself over WebRTC
    typ = e.client_transport(t0)
    check("session runs P2P over WebRTC (not the relay)", typ == "WebRTC", typ or "no transport logged")
    kb = e.gateway_kbytes(8)
    check("video does not cross the server port (< 100 KB in 8 s; relayed ~450 KB)", kb < 100, f"{kb} KB")
    close_remote_windows()

    # 2b. re-deploy over the existing installation (upgrade path) must leave a working install
    code, out = ps51(f"iwr {c.base}/download/deploy-superdesk.ps1 -OutFile $env:TEMP\\d.ps1 -UseBasicParsing; "
                     f"& $env:TEMP\\d.ps1 -Password '{pw}' -Note 'e2e-redeploy'")
    check("re-deploy over existing install", code == 0 and "检测到已安装的旧版本" in out and f"ID = {dev_id}" in out, out[-300:])
    check("re-deploy kept librustdesk.dll", os.path.exists(os.path.join(PF, HELPER, "librustdesk.dll")))
    a = connect_and_wait(c, dev_id, pw, True)
    check("unattended connect after re-deploy", a is not None)
    time.sleep(3)
    close_remote_windows()

    # 3. policy: outside work hours nobody may connect
    try:
        c.call("POST", "/api/admin/groups", {"name": GROUP, "work_hours_only": True, "work_days": "1,2,3,4,5,6,7",
                                             "work_start": "00:00", "work_end": "00:01"})
    except Exception:  # noqa: BLE001 -- leftover from a previous run
        c.call("PUT", f"/api/admin/groups/{GROUP_Q}", {"name": GROUP, "work_hours_only": True, "work_days": "1,2,3,4,5,6,7",
                                                      "work_start": "00:00", "work_end": "00:01"})
    c.call("PUT", f"/api/admin/devices/{dev_id}", {"group_name": GROUP})
    time.sleep(25)  # heartbeat -> strategy
    a = connect_and_wait(c, dev_id, pw, False, seconds=25)
    check("connection blocked outside work hours", a is None)
    close_remote_windows()

    # 4. lift the policy -> allowed again
    c.call("PUT", f"/api/admin/devices/{dev_id}", {"group_name": ""})
    time.sleep(25)
    a = connect_and_wait(c, dev_id, pw, True)
    check("allowed again after leaving the group", a is not None)
    time.sleep(3)
    close_remote_windows()

    # 5. cleanup: uninstall the service, remove test data
    c.call("DELETE", f"/api/admin/groups/{GROUP_Q}")
    subprocess.run([INSTALLED, "--uninstall"], timeout=120)
    time.sleep(8)
    gone = "does not exist" in subprocess.run(["sc", "query", HELPER], capture_output=True, text=True).stdout \
        or subprocess.run(["sc", "query", HELPER], capture_output=True).returncode != 0
    check("uninstalled (service removed)", gone)
    print("\nALL PASSED" if not fails else f"\n{fails} FAILED")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
