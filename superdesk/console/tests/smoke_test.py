"""End-to-end smoke test for super控制台, speaking the RustDesk client protocol.

Usage: python smoke_test.py <base_url> <admin_user> <admin_password>
Creates (and cleans up) test users/devices/groups prefixed "smoke".
"""
import json
import sys
import urllib.error
import urllib.request

BASE, ADMIN, ADMIN_PW = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3]
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # never via local HTTP proxy
fails = 0


def call(method, path, body=None, token=None, raw=None, ctype="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", ctype)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with OPENER.open(req, timeout=15) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def check(name, cond, detail=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f"  -> {detail}"))
    fails += 0 if cond else 1


J = json.loads
DEV, DEV2 = "smoke100001", "smoke100002"

# --- admin login
s, b = call("POST", "/api/admin/login", {"username": ADMIN, "password": ADMIN_PW})
check("admin login", s == 200 and "token" in b, b)
AT = J(b)["token"]
call("POST", "/api/admin/users", {"name": "smokeuser", "password": "SmokePass123", "display_name": "冒烟测试"}, AT)

# --- device sync
s, b = call("POST", "/api/sysinfo", {"id": DEV, "uuid": "dXVpZA==", "hostname": "SMOKE-PC", "os": "windows / Windows 11 Pro",
                                     "username": "alice", "cpu": "x", "memory": "16GB", "version": "1.5.3"}, ctype="text/plain")
check("sysinfo plain text", s == 200 and b == "SYSINFO_UPDATED", b)
s, b = call("POST", "/api/heartbeat", {"id": DEV, "uuid": "dXVpZA==", "ver": 1005030, "modified_at": 0})
check("heartbeat no group -> no strategy", s == 200 and "strategy" not in J(b), b)

# --- client account
s, b = call("GET", "/api/login-options")
check("login-options array", s == 200 and J(b) == [], b)
s, b = call("POST", "/api/login", {"username": "smokeuser", "password": "wrong", "id": DEV2, "uuid": "x", "type": "account"})
check("login wrong password -> error", "error" in J(b), b)
s, b = call("POST", "/api/login", {"username": "smokeuser", "password": "SmokePass123", "id": DEV2, "uuid": "x",
                                   "type": "account", "deviceInfo": {"os": "windows", "type": "client", "name": "IT-PC"}})
d = J(b)
check("login ok", d.get("type") == "access_token" and d.get("access_token") and d["user"]["name"] == "smokeuser", b)
CT = d["access_token"]
s, b = call("POST", "/api/currentUser", {"id": DEV2, "uuid": "x"}, CT)
check("currentUser", s == 200 and J(b)["name"] == "smokeuser", b)
s, _ = call("POST", "/api/currentUser", {"id": DEV2}, "badtoken")
check("currentUser bad token -> 401", s == 401, s)

# --- address book (new mode)
s, b = call("POST", "/api/ab/personal", raw=b"", token=CT)
G = J(b).get("guid")
check("ab personal guid", s == 200 and G, b)
s, b = call("POST", "/api/ab/settings", raw=b"", token=CT)
check("ab settings", J(b).get("max_peer_one_ab") == 0, b)
s, b = call("POST", f"/api/ab/peer/add/{G}", {"id": DEV, "alias": "前台电脑", "tags": ["财务"]}, CT)
check("ab peer add -> 200 empty body", s == 200 and b == "", repr(b))
s, b = call("PUT", f"/api/ab/peer/update/{G}", {"id": DEV, "note": "二楼"}, CT)
check("ab peer update -> 200 empty body", s == 200 and b == "", repr(b))
s, b = call("POST", f"/api/ab/tag/add/{G}", {"name": "财务", "color": 4280391411}, CT)
check("ab tag add", s == 200 and b == "", repr(b))
s, b = call("PUT", f"/api/ab/tag/rename/{G}", {"old": "财务", "new": "财务部"}, CT)
s, b = call("POST", f"/api/ab/peers?current=1&pageSize=100&ab={G}", raw=b"", token=CT)
d = J(b)
check("ab peers paged + tag rename cascades", d["total"] == 1 and d["data"][0]["tags"] == ["财务部"] and d["data"][0]["note"] == "二楼", b)
s, b = call("POST", f"/api/ab/tags/{G}", raw=b"", token=CT)
check("ab tags array", J(b) == [{"name": "财务部", "color": 4280391411}], b)
s, b = call("POST", "/api/ab/shared/profiles?current=1&pageSize=100", raw=b"", token=CT)
check("shared profiles (none yet)", J(b)["total"] == 0, b)
s, b = call("POST", "/api/admin/address-books", {"name": "smoke共享", "rules": [{"user_id": None, "rule": 1}]}, AT)
s, b = call("POST", "/api/ab/shared/profiles?current=1&pageSize=100", raw=b"", token=CT)
d = J(b)
check("shared profile visible read-only", d["total"] == 1 and d["data"][0]["rule"] == 1, b)
SG = d["data"][0]["guid"]
s, b = call("POST", f"/api/ab/peer/add/{SG}", {"id": DEV}, CT)
check("read-only shared ab rejects write", s == 403, s)
s, b = call("DELETE", f"/api/ab/peer/{G}", [DEV], CT)
check("ab peer delete", s == 200 and b == "", repr(b))

# --- groups / users / peers
s, b = call("GET", "/api/users?current=1&pageSize=100&accessible=&status=1", token=CT)
check("users list", any(u["name"] == "smokeuser" for u in J(b)["data"]), b)
s, b = call("GET", "/api/peers?current=1&pageSize=100&accessible=&status=1", token=CT)
p = [x for x in J(b)["data"] if x["id"] == DEV]
check("peers list has device info", p and p[0]["info"]["device_name"] == "SMOKE-PC", b[:300])
s, b = call("GET", "/api/device-group/accessible?current=1&pageSize=100", token=CT)
check("device groups", s == 200 and "data" in J(b), b)

# --- audit
s, b = call("POST", "/api/audit/conn", {"id": DEV, "uuid": "u", "conn_id": 7, "session_id": 0, "action": "new", "ip": "1.2.3.4", "nonce": "n1"})
check("audit new -> empty body", s == 200 and b == "", repr(b))
s, b = call("POST", "/api/audit/conn", {"id": DEV, "uuid": "u", "conn_id": 7, "session_id": 99, "peer": [DEV2, "IT"], "type": 0, "primary_auth": 3, "nonce": "n2"})
check("audit authorized", s == 200 and b == "", repr(b))
s, b = call("POST", "/api/audit/conn", {"id": DEV, "uuid": "u", "conn_id": 7, "session_id": 99, "peer": [DEV2, "IT"], "type": 0, "nonce": "n2"})
check("audit duplicate nonce accepted", s == 200 and b == "", repr(b))
s, b = call("GET", f"/api/audit/conn/active?id={DEV}&session_id=99&conn_type=0", token=CT)
check("audit active guid is json string", s == 200 and isinstance(J(b), str), b)
s, b = call("PUT", "/api/audit", {"guid": J(b), "note": "修打印机"}, CT)
check("audit note", s == 200, b)
s, b = call("POST", "/api/audit/file", {"id": DEV, "uuid": "u", "peer_id": DEV2, "conn_id": 7, "type": 0, "path": "C:/a",
                                        "is_file": True, "info": json.dumps({"ip": "1.2.3.4", "name": "IT", "num": 1, "files": [["a.txt", 10]]}), "nonce": "n3"})
check("audit file", s == 200 and b == "", repr(b))
s, b = call("POST", "/api/audit/alarm", {"id": DEV, "uuid": "u", "typ": 1, "info": json.dumps({"ip": "5.6.7.8", "id": "x", "name": "y"}), "conn_id": 8, "nonce": "n4"})
check("audit alarm", s == 200 and b == "", repr(b))

# --- policy via heartbeat strategy + forced disconnect
s, b = call("POST", "/api/admin/groups", {"name": "smoke组", "approve_mode": "click", "record_sessions": True, "company_only": True}, AT)
check("create group", s == 200, b)
s, b = call("PUT", f"/api/admin/devices/{DEV}", {"group_name": "smoke组"}, AT)
call("POST", "/api/heartbeat", {"id": DEV2, "uuid": "x", "ver": 1005030})  # company device must be "seen"
s, b = call("POST", "/api/heartbeat", {"id": DEV, "uuid": "dXVpZA==", "ver": 1005030, "modified_at": 0, "conns": [7]})
d = J(b)
opts = d.get("strategy", {}).get("config_options", {})
check("strategy pushed", opts.get("approve-mode") == "click" and opts.get("allow-auto-record-incoming") == "Y"
      and opts.get("superdesk-record-upload") == "Y" and DEV2 in opts.get("id-whitelist", ""), b)
TS = d.get("modified_at")
s, b = call("POST", "/api/heartbeat", {"id": DEV, "ver": 1005030, "modified_at": 0, "conns": [7]})
check("strategy re-sent until acknowledged", J(b).get("modified_at") == TS, b)
s, b = call("POST", "/api/heartbeat", {"id": DEV, "ver": 1005030, "modified_at": TS, "conns": [7]})
check("no strategy once acknowledged", "strategy" not in J(b), b)
s, b = call("POST", f"/api/admin/devices/{DEV}/disconnect", {}, AT)
check("admin disconnect", s == 200 and 7 in J(b)["conn_ids"], b)
s, b = call("POST", "/api/heartbeat", {"id": DEV, "ver": 1005030, "modified_at": TS, "conns": [7]})
check("heartbeat delivers disconnect", J(b).get("disconnect") == [7], b)
s, b = call("PUT", f"/api/admin/devices/{DEV}", {"group_name": ""}, AT)
s, b = call("POST", "/api/heartbeat", {"id": DEV, "ver": 1005030, "modified_at": TS})
opts = J(b).get("strategy", {}).get("config_options", {})
check("leaving group clears managed options", opts and all(v == "" for v in opts.values()), b)
s, b = call("POST", "/api/audit/conn", {"id": DEV, "uuid": "u", "conn_id": 7, "action": "close", "nonce": "n5"})

# --- recordings
fname = f"incoming_{DEV}_20261122101010123_display0_vp9.webm"
s, b = call("POST", f"/api/record?type=new&file={fname}", raw=b"")
check("record new", s == 200 and "error" not in b, b)
s, b = call("POST", f"/api/record?type=part&file={fname}&offset=0&length=8", raw=b"ABCDEFGH", ctype="application/octet-stream")
s, b = call("POST", f"/api/record?type=tail&file={fname}&offset=0&length=2", raw=b"xy", ctype="application/octet-stream")
check("record part+tail", s == 200 and "error" not in b, b)
s, b = call("POST", "/api/record?type=new&file=../../etc/passwd", raw=b"")
check("record rejects path traversal", "error" in b, b)
s, b = call("GET", "/api/admin/recordings", token=AT)
rec = [r for r in J(b)["data"] if r["filename"] == fname]
check("recording listed + finished", rec and rec[0]["finished"] == 1 and rec[0]["size"] == 8, b[:300])
check("recording device id parsed", rec and rec[0]["device_id"] == DEV, rec and rec[0]["device_id"])
s, b = call("GET", f"/api/admin/recordings/{rec[0]['id']}/file?token={AT}")
check("recording download content", b == "xyCDEFGH", repr(b))

# --- superdesk extensions
s, b = call("POST", "/api/superdesk/help", {"id": DEV, "device_name": "SMOKE-PC", "os": "windows", "message": "打印机坏了"})
check("help request", J(b).get("ok") is True, b)
s, b = call("POST", "/api/superdesk/deploy", {"id": DEV, "hostname": "SMOKE-PC", "user": "it", "flavor": "helper", "build": "202611220000"})
check("deploy report", J(b).get("ok") is True, b)
s, b = call("POST", "/api/superdesk/hello", {"id": DEV, "flavor": "helper", "build": "202611221200", "platform": "windows"})
dev = [x for x in J(call("GET", "/api/admin/devices?q=" + DEV, token=AT)[1])["data"] if x["id"] == DEV]
check("hello records flavor/build", dev and dev[0]["flavor"] == "helper" and dev[0]["build"] == "202611221200", dev)
s, b = call("GET", "/api/admin/overview", token=AT)
d = J(b)
check("admin overview", d["help_open"] >= 1 and d["devices"] >= 2, b[:300])
for path in ["/api/admin/audit/conn", "/api/admin/audit/file", "/api/admin/audit/alarm", "/api/admin/help", "/api/admin/deploy",
             "/api/admin/events", "/api/admin/devices", "/api/admin/settings", "/api/admin/users", "/api/admin/groups",
             "/api/admin/address-books"]:
    s, b = call("GET", path, token=AT)
    check(f"admin GET {path}", s == 200, b[:200])
s, b = call("GET", "/api/admin/overview", token=CT)
check("non-admin token rejected", s == 403, s)
s, b = call("GET", "/admin/")
check("admin UI served", s == 200 and "super控制台" in b, b[:100])

# --- cleanup
call("POST", "/api/logout", {"id": DEV2}, CT)
for hreq in J(call("GET", "/api/admin/help?status=open&size=100", token=AT)[1])["data"]:
    if hreq["device_id"] == DEV:
        call("POST", f"/api/admin/help/{hreq['id']}/done", {}, AT)
for dev in (DEV, DEV2):
    call("DELETE", f"/api/admin/devices/{dev}", token=AT)
call("DELETE", f"/api/admin/recordings/{rec[0]['id']}", token=AT)
call("DELETE", "/api/admin/groups/" + urllib.request.quote("smoke组"), token=AT)
call("DELETE", f"/api/admin/address-books/{SG}", token=AT)
for u in J(call("GET", "/api/admin/users", token=AT)[1]):
    if u["name"] == "smokeuser":
        call("DELETE", f"/api/admin/users/{u['id']}", token=AT)
print(f"\n{'ALL PASSED' if not fails else f'{fails} FAILED'}")
sys.exit(1 if fails else 0)
