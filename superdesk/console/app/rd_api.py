"""RustDesk-client-compatible API (what the client calls on its `api-server`).

Contract follows the RustDesk 1.5.3 client source; quirks that matter:
- audit posts and address-book changes succeed ONLY on HTTP 200 with an EMPTY body;
- /api/sysinfo answers the plain text SYSINFO_UPDATED;
- request bodies may arrive with a wrong Content-Type, so bodies are parsed by hand.
"""
import json
import os
import re
import uuid as uuidlib

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from fastapi.responses import JSONResponse, PlainTextResponse

from . import db, notify, policy, security
from .sd_api import client_ip, rate_limit, touch_device

router = APIRouter(prefix="/api")

def EMPTY_OK():
    return Response(status_code=200)


REC_DIR = os.path.join(db.DATA_DIR, "recordings")
MAX_RECORDING = 4 * 1024 ** 3  # 4 GB per file


async def body_json(req: Request, default=None):
    raw = await req.body()
    if not raw:
        return default if default is not None else {}
    try:
        return json.loads(raw)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid json")


def err(msg: str, status: int = 200):
    return JSONResponse({"error": msg}, status_code=status)


def user_json(u):
    return {"name": u["name"], "display_name": u["display_name"] or u["name"], "email": u["email"],
            "note": u["note"], "status": 1 if u["status"] == 1 else 0, "is_admin": bool(u["is_admin"]),
            "avatar": ""}


def paged(req: Request, rows):
    try:
        cur = max(1, int(req.query_params.get("current", 1)))
        size = max(1, min(1000, int(req.query_params.get("pageSize", 100))))
    except ValueError:
        cur, size = 1, 100
    return {"total": len(rows), "data": rows[(cur - 1) * size: cur * size]}


# ---------------------------------------------------------------- account
@router.api_route("/login-options", methods=["GET", "HEAD"])
def login_options():
    return []


@router.post("/login")
async def login(req: Request):
    rate_limit(req, "login", 10)
    b = await body_json(req)
    if b.get("type", "account") != "account":
        return err("不支持的登录方式")
    u = db.one("SELECT * FROM users WHERE name=?", (str(b.get("username", "")),))
    if not u or not security.check_password(str(b.get("password", "")), u["password_hash"]):
        db.event("login", f"登录失败：{b.get('username', '')}（{client_ip(req)}）")
        return err("用户名或密码错误")
    if u["status"] != 1:
        return err("账号已被禁用")
    dev_id, dev_uuid = str(b.get("id", ""))[:32], str(b.get("uuid", ""))[:128]
    tok = security.new_token(u["id"], "client", dev_id, dev_uuid)
    if dev_id:
        info = b.get("deviceInfo") or {}
        touch_device(dev_id, uuid=dev_uuid, hostname=str(info.get("name", ""))[:100])
        db.run("UPDATE devices SET user_id=? WHERE id=?", (u["id"], dev_id))
    db.event("login", f"{u['name']} 在设备 {dev_id or '?'} 登录客户端")
    return {"access_token": tok, "type": "access_token", "user": user_json(u)}


@router.post("/currentUser")
async def current_user(req: Request, authorization: str | None = Header(default=None)):
    u = security.user_from_token(security.bearer(authorization))
    if not u:
        return Response(status_code=401)
    b = await body_json(req)
    dev_id = str(b.get("id", ""))[:32]
    if dev_id:
        touch_device(dev_id)
        db.run("UPDATE devices SET user_id=? WHERE id=?", (u["id"], dev_id))
    return user_json(u)


@router.post("/logout")
async def logout(req: Request, authorization: str | None = Header(default=None)):
    tok = security.bearer(authorization)
    t = db.one("SELECT device_id FROM tokens WHERE token=?", (tok,))
    if t:
        db.run("DELETE FROM tokens WHERE token=?", (tok,))
        if t["device_id"]:
            db.run("UPDATE devices SET user_id=NULL WHERE id=?", (t["device_id"],))
    return {}


# ---------------------------------------------------------------- device sync
@router.post("/sysinfo")
async def sysinfo(req: Request):
    b = await body_json(req)
    dev_id = str(b.get("id", ""))[:32]
    if not dev_id:
        return PlainTextResponse("ID_NOT_FOUND")
    touch_device(dev_id, uuid=str(b.get("uuid", ""))[:128], hostname=str(b.get("hostname", ""))[:100],
                 username=str(b.get("username", ""))[:100], os=str(b.get("os", ""))[:200],
                 version=str(b.get("version", ""))[:20], cpu=str(b.get("cpu", ""))[:200],
                 memory=str(b.get("memory", ""))[:50], ip=client_ip(req),
                 sysinfo=json.dumps(b, ensure_ascii=False)[:8000])
    return PlainTextResponse("SYSINFO_UPDATED")


@router.post("/heartbeat")
async def heartbeat(req: Request):
    b = await body_json(req)
    dev_id = str(b.get("id", ""))[:32]
    if not dev_id:
        return {}
    conns = [int(c) for c in (b.get("conns") or []) if str(c).lstrip("-").isdigit()]
    touch_device(dev_id, uuid=str(b.get("uuid", ""))[:128], ip=client_ip(req))
    db.run("UPDATE devices SET last_seen=?, conns=? WHERE id=?", (db.now(), len(conns), dev_id))
    resp = {}
    dev = db.one("SELECT * FROM devices WHERE id=?", (dev_id,))
    if not dev["hostname"]:
        resp["sysinfo"] = True
    try:
        client_ts = int(b.get("modified_at") or 0)
    except (TypeError, ValueError):
        client_ts = 0
    st = policy.strategy_for(dev, client_ts)
    if st:
        opts, ts = st
        resp["strategy"] = {"config_options": opts, "extra": {}}
        resp["modified_at"] = ts
    kill = policy.pop_disconnects(dev_id, conns)
    if kill:
        resp["disconnect"] = kill
    return resp


# ---------------------------------------------------------------- address books
def personal_ab(user_id: int) -> str:
    r = db.one("SELECT guid FROM ab_profiles WHERE owner_id=? AND personal=1", (user_id,))
    if r:
        return r["guid"]
    guid = str(uuidlib.uuid4())
    db.run("INSERT INTO ab_profiles(guid, name, owner_id, personal, created_at) VALUES(?,?,?,1,?)",
           (guid, "My address book", user_id, db.now()))
    return guid


def ab_rule(u, guid: str) -> int:
    """0 none, 1 read, 2 read/write, 3 full control."""
    ab = db.one("SELECT * FROM ab_profiles WHERE guid=?", (guid,))
    if not ab:
        return 0
    if ab["owner_id"] == u["id"]:
        return 3
    if ab["personal"]:
        return 0
    if u["is_admin"]:
        return 3
    rules = db.all_("SELECT rule FROM ab_rules WHERE ab_guid=? AND (user_id IS NULL OR user_id=?)", (guid, u["id"]))
    return max([r["rule"] for r in rules], default=0)


def need_rule(u, guid: str, rule: int):
    if ab_rule(u, guid) < rule:
        raise HTTPException(status_code=403, detail="no permission")


@router.post("/ab/personal")
def ab_personal(u=Depends(security.require_user)):
    return {"guid": personal_ab(u["id"])}


@router.post("/ab/settings")
def ab_settings(u=Depends(security.require_user)):
    return {"max_peer_one_ab": 0}


@router.post("/ab/shared/profiles")
def ab_shared(req: Request, u=Depends(security.require_user)):
    out = []
    for ab in db.all_("SELECT a.*, u.name AS owner_name FROM ab_profiles a JOIN users u ON u.id=a.owner_id"
                      " WHERE a.personal=0 ORDER BY a.name"):
        rule = ab_rule(u, ab["guid"])
        if rule:
            out.append({"guid": ab["guid"], "name": ab["name"], "owner": ab["owner_name"], "note": ab["note"],
                        "rule": rule, "info": {}})
    return paged(req, out)


@router.post("/ab/peers")
def ab_peers(req: Request, u=Depends(security.require_user)):
    guid = req.query_params.get("ab", "")
    need_rule(u, guid, 1)
    rows = [json.loads(r["data"]) for r in db.all_("SELECT data FROM ab_peers WHERE ab_guid=? ORDER BY id", (guid,))]
    return paged(req, rows)


@router.post("/ab/tags/{guid}")
def ab_tags(guid: str, u=Depends(security.require_user)):
    need_rule(u, guid, 1)
    return [{"name": r["name"], "color": r["color"]} for r in
            db.all_("SELECT name, color FROM ab_tags WHERE ab_guid=? ORDER BY name", (guid,))]


PEER_FIELDS = {"id", "hash", "password", "username", "hostname", "platform", "alias", "tags", "note",
               "forceAlwaysRelay", "rdpPort", "rdpUsername", "loginName", "device_group_name", "same_server"}


def clean_peer(p: dict) -> dict:
    out = {k: v for k, v in p.items() if k in PEER_FIELDS}
    if not isinstance(out.get("tags", []), list):
        out["tags"] = []
    return out


@router.post("/ab/peer/add/{guid}")
async def ab_peer_add(guid: str, req: Request, u=Depends(security.require_user)):
    need_rule(u, guid, 2)
    p = clean_peer(await body_json(req))
    if not p.get("id"):
        return err("missing id")
    db.run("INSERT INTO ab_peers(ab_guid, id, data) VALUES(?,?,?) ON CONFLICT(ab_guid, id) DO UPDATE SET data=excluded.data",
           (guid, str(p["id"]), json.dumps(p, ensure_ascii=False)))
    return EMPTY_OK()


@router.put("/ab/peer/update/{guid}")
async def ab_peer_update(guid: str, req: Request, u=Depends(security.require_user)):
    need_rule(u, guid, 2)
    upd = clean_peer(await body_json(req))
    row = db.one("SELECT data FROM ab_peers WHERE ab_guid=? AND id=?", (guid, str(upd.get("id", ""))))
    if not row:
        return err("peer not found")
    p = json.loads(row["data"])
    p.update(upd)
    db.run("UPDATE ab_peers SET data=? WHERE ab_guid=? AND id=?", (json.dumps(p, ensure_ascii=False), guid, p["id"]))
    return EMPTY_OK()


@router.delete("/ab/peer/{guid}")
async def ab_peer_delete(guid: str, req: Request, u=Depends(security.require_user)):
    need_rule(u, guid, 2)
    for pid in await body_json(req, []):
        db.run("DELETE FROM ab_peers WHERE ab_guid=? AND id=?", (guid, str(pid)))
    return EMPTY_OK()


def _retag(guid: str, fn):
    for r in db.all_("SELECT id, data FROM ab_peers WHERE ab_guid=?", (guid,)):
        p = json.loads(r["data"])
        tags = p.get("tags") or []
        new = fn(tags)
        if new != tags:
            p["tags"] = new
            db.run("UPDATE ab_peers SET data=? WHERE ab_guid=? AND id=?", (json.dumps(p, ensure_ascii=False), guid, r["id"]))


@router.post("/ab/tag/add/{guid}")
async def ab_tag_add(guid: str, req: Request, u=Depends(security.require_user)):
    need_rule(u, guid, 2)
    b = await body_json(req)
    db.run("INSERT INTO ab_tags(ab_guid, name, color) VALUES(?,?,?) ON CONFLICT(ab_guid, name) DO UPDATE SET color=excluded.color",
           (guid, str(b.get("name", "")), int(b.get("color", 0))))
    return EMPTY_OK()


@router.put("/ab/tag/rename/{guid}")
async def ab_tag_rename(guid: str, req: Request, u=Depends(security.require_user)):
    need_rule(u, guid, 2)
    b = await body_json(req)
    old, new = str(b.get("old", "")), str(b.get("new", ""))
    db.run("UPDATE ab_tags SET name=? WHERE ab_guid=? AND name=?", (new, guid, old))
    _retag(guid, lambda tags: [new if t == old else t for t in tags])
    return EMPTY_OK()


@router.put("/ab/tag/update/{guid}")
async def ab_tag_update(guid: str, req: Request, u=Depends(security.require_user)):
    need_rule(u, guid, 2)
    b = await body_json(req)
    db.run("UPDATE ab_tags SET color=? WHERE ab_guid=? AND name=?", (int(b.get("color", 0)), guid, str(b.get("name", ""))))
    return EMPTY_OK()


@router.delete("/ab/tag/{guid}")
async def ab_tag_delete(guid: str, req: Request, u=Depends(security.require_user)):
    need_rule(u, guid, 2)
    names = [str(n) for n in await body_json(req, [])]
    for n in names:
        db.run("DELETE FROM ab_tags WHERE ab_guid=? AND name=?", (guid, n))
    _retag(guid, lambda tags: [t for t in tags if t not in names])
    return EMPTY_OK()


# ---------------------------------------------------------------- groups / users / peers
@router.get("/device-group/accessible")
def device_groups(req: Request, u=Depends(security.require_user)):
    return paged(req, [{"name": g["name"]} for g in db.all_("SELECT name FROM groups ORDER BY name")])


@router.get("/users")
def users(req: Request, u=Depends(security.require_user)):
    rows = db.all_("SELECT * FROM users WHERE status=1 ORDER BY name")
    return paged(req, [user_json(x) for x in rows])


@router.get("/peers")
def peers(req: Request, u=Depends(security.require_user)):
    rows = db.all_("SELECT d.*, u.name AS user_name, u.display_name AS user_display FROM devices d"
                   " LEFT JOIN users u ON u.id=d.user_id ORDER BY d.group_name, d.hostname")
    out = [{"id": d["id"], "info": {"username": d["username"], "os": d["os"], "device_name": d["alias"] or d["hostname"]},
            "status": 1, "user": d["user_name"] or "", "user_name": d["user_name"] or "",
            "device_group_name": d["group_name"], "note": d["note"]} for d in rows]
    return paged(req, out)


# ---------------------------------------------------------------- audit
_seen_nonces: dict[str, int] = {}


def dup_nonce(b: dict) -> bool:
    n = str(b.get("nonce", ""))
    if not n:
        return False
    t = db.now()
    for k in [k for k, v in _seen_nonces.items() if v < t - 300]:
        _seen_nonces.pop(k, None)
    if n in _seen_nonces:
        return True
    _seen_nonces[n] = t
    return False


CONN_TYPES = {0: "远程控制", 1: "文件传输", 2: "端口转发/RDP", 3: "查看摄像头", 4: "远程终端"}
AUTH_TYPES = {1: "被控端点击接受", 2: "临时密码", 3: "固定密码", 4: "切换控制方向"}


def device_label(dev_id: str) -> str:
    d = db.one("SELECT alias, hostname FROM devices WHERE id=?", (dev_id,))
    name = (d and (d["alias"] or d["hostname"])) or ""
    return f"{name}（{dev_id}）" if name else dev_id


@router.post("/audit/conn")
async def audit_conn(req: Request):
    b = await body_json(req)
    if dup_nonce(b):
        return EMPTY_OK()
    t = db.now()
    dev_id = str(b.get("id", ""))[:32]
    if "conn_id" not in b:
        # note from the controlling side: {id: <remote peer>, session_id, note}
        db.run("UPDATE audit_conn SET note=? WHERE id=(SELECT id FROM audit_conn WHERE device_id=? AND session_id=?"
               " ORDER BY id DESC LIMIT 1)", (str(b.get("note", ""))[:1000], dev_id, str(b.get("session_id", ""))))
        return EMPTY_OK()
    conn_id = int(b.get("conn_id") or 0)
    action = b.get("action")
    if action == "new":
        db.run("INSERT INTO audit_conn(device_id, conn_id, uuid, ip, created_at, raw) VALUES(?,?,?,?,?,?)",
               (dev_id, conn_id, str(b.get("uuid", ""))[:128], str(b.get("ip", ""))[:64], t,
                json.dumps(b, ensure_ascii=False)[:4000]))
    elif action == "close":
        db.run("UPDATE audit_conn SET closed_at=? WHERE id=(SELECT id FROM audit_conn WHERE device_id=? AND conn_id=?"
               " AND closed_at=0 ORDER BY id DESC LIMIT 1)", (t, dev_id, conn_id))
    elif "peer" in b:
        peer = b.get("peer") or ["", ""]
        peer_id, peer_name = str(peer[0])[:32], str(peer[1] if len(peer) > 1 else "")[:100]
        typ = int(b.get("type") or 0)
        row = db.one("SELECT id FROM audit_conn WHERE device_id=? AND conn_id=? AND closed_at=0 ORDER BY id DESC LIMIT 1",
                     (dev_id, conn_id))
        if not row:
            row = {"id": db.run("INSERT INTO audit_conn(device_id, conn_id, created_at) VALUES(?,?,?)", (dev_id, conn_id, t))}
        db.run("UPDATE audit_conn SET peer_id=?, peer_name=?, type=?, session_id=?, authorized_at=?, raw=? WHERE id=?",
               (peer_id, peer_name, typ, str(b.get("session_id", "")), t, json.dumps(b, ensure_ascii=False)[:4000], row["id"]))
        how = AUTH_TYPES.get(int(b.get("primary_auth") or 0), "")
        notify.notify("conn", "🔗 远程连接已建立", [
            f"控制方：{peer_name or '?'}（{peer_id}）", f"被控电脑：{device_label(dev_id)}",
            f"类型：{CONN_TYPES.get(typ, typ)}" + (f"，验证：{how}" if how else "")])
    return EMPTY_OK()


@router.post("/audit/file")
async def audit_file(req: Request):
    b = await body_json(req)
    if dup_nonce(b):
        return EMPTY_OK()
    dev_id = str(b.get("id", ""))[:32]
    info = b.get("info") or "{}"
    db.run("INSERT INTO audit_file(device_id, peer_id, path, is_file, type, info, created_at) VALUES(?,?,?,?,?,?,?)",
           (dev_id, str(b.get("peer_id", ""))[:32], str(b.get("path", ""))[:1000], 1 if b.get("is_file") else 0,
            int(b.get("type") or 0), info if isinstance(info, str) else json.dumps(info, ensure_ascii=False), db.now()))
    try:
        parsed = json.loads(info) if isinstance(info, str) else info
        files = (parsed.get("files") or []) if isinstance(parsed, dict) else []
    except ValueError:
        files = []
    notify.notify("file", "📁 远程文件传输", [
        f"电脑：{device_label(dev_id)}", f"对方：{b.get('peer_id', '')}",
        f"方向：{'被控端发出' if int(b.get('type') or 0) == 0 else '被控端接收'}",
        f"路径：{b.get('path', '') or '剪贴板'}", f"文件：{', '.join(str(f[0]) for f in files[:5]) or '-'}"])
    return EMPTY_OK()


ALARMS = {0: "IP 白名单拦截", 1: "密码错误超过 30 次", 2: "1 分钟内密码错误超过 6 次", 6: "IPv6 前缀拦截",
          7: "终端登录退避", 8: "终端登录并发", 9: "会话越权", 10: "ID 白名单拦截"}


@router.post("/audit/alarm")
async def audit_alarm(req: Request):
    b = await body_json(req)
    if dup_nonce(b):
        return EMPTY_OK()
    dev_id = str(b.get("id", ""))[:32]
    typ = int(b.get("typ") or 0)
    info = b.get("info") or "{}"
    db.run("INSERT INTO audit_alarm(device_id, typ, info, created_at) VALUES(?,?,?,?)",
           (dev_id, typ, info if isinstance(info, str) else json.dumps(info, ensure_ascii=False), db.now()))
    try:
        d = json.loads(info) if isinstance(info, str) else info
    except ValueError:
        d = {}
    if not isinstance(d, dict):
        d = {}
    notify.notify("alarm", "⚠️ 安全告警", [f"电脑：{device_label(dev_id)}", f"类型：{ALARMS.get(typ, typ)}",
                                          f"来源：{d.get('id', '')} {d.get('name', '')} {d.get('ip', '')}".strip()])
    return EMPTY_OK()


@router.get("/audit/conn/active")
def audit_active(req: Request, u=Depends(security.require_user)):
    dev_id = req.query_params.get("id", "")
    sid = req.query_params.get("session_id", "")
    row = db.one("SELECT id, guid FROM audit_conn WHERE device_id=? AND session_id=? ORDER BY id DESC LIMIT 1", (dev_id, sid))
    if not row:
        raise HTTPException(status_code=404)
    guid = row["guid"] or str(uuidlib.uuid4())
    if not row["guid"]:
        db.run("UPDATE audit_conn SET guid=? WHERE id=?", (guid, row["id"]))
    return guid


@router.put("/audit")
async def audit_note(req: Request, u=Depends(security.require_user)):
    b = await body_json(req)
    db.run("UPDATE audit_conn SET note=? WHERE guid=?", (str(b.get("note", ""))[:1000], str(b.get("guid", ""))))
    return {}


# ---------------------------------------------------------------- session recordings
# incoming_<id>_<YYYYmmddHHMMSS + 3-digit ms>_<display|camera><n>_<codec>.<ext>  (scrap/record.rs)
SAFE_FILE = re.compile(r"^(incoming|outgoing)_([A-Za-z0-9@.-]{1,64})_(\d{17})_[A-Za-z0-9_.-]{1,60}\.(webm|mp4)$")


@router.post("/record")
async def record(req: Request):
    q = req.query_params
    name = q.get("file", "")
    m = SAFE_FILE.match(name)
    if not m:
        return {"error": "bad file name"}
    dev_id = m.group(2).split("@")[0]
    path = os.path.join(REC_DIR, dev_id, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    typ = q.get("type")
    t = db.now()
    if typ == "new":
        open(path, "wb").close()
        db.run("INSERT INTO recordings(device_id, filename, path, created_at, updated_at) VALUES(?,?,?,?,?)",
               (dev_id, name, path, t, t))
        return {}
    if not os.path.exists(path):
        return {"error": "unknown file"}
    if typ in ("part", "tail"):
        data = await req.body()
        try:
            offset = int(q.get("offset", 0))
        except ValueError:
            return {"error": "bad offset"}
        if offset < 0 or offset + len(data) > MAX_RECORDING:
            return {"error": "file too large"}
        with open(path, "r+b") as f:
            f.seek(offset)
            f.write(data)
        size = os.path.getsize(path)
        db.run("UPDATE recordings SET size=?, updated_at=?, finished=? WHERE path=?",
               (size, t, 1 if typ == "tail" else 0, path))
        return {}
    if typ == "remove":
        os.remove(path)
        db.run("DELETE FROM recordings WHERE path=?", (path,))
        return {}
    return {"error": "bad type"}
