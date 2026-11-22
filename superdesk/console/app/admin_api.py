"""Admin REST API for the super控制台 web UI (/admin). Admin bearer token required."""
import json
import os
import re
import threading
import time
import uuid as uuidlib

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

from . import db, notify, policy, security
from .sd_api import WALL_DIR, client_ip, rate_limit

router = APIRouter(prefix="/api/admin")
admin = Depends(security.require_admin)
ONLINE_SECS = 60


def page(req: Request, sql: str, args=(), order="id DESC"):
    try:
        p = max(1, int(req.query_params.get("page", 1)))
        size = max(1, min(500, int(req.query_params.get("size", 50))))
    except ValueError:
        p, size = 1, 50
    total = db.one(f"SELECT COUNT(*) AS n FROM ({sql})", args)["n"]
    rows = db.all_(f"{sql} ORDER BY {order} LIMIT ? OFFSET ?", (*args, size, (p - 1) * size))
    return {"total": total, "page": p, "size": size, "data": rows}


def like(req: Request, key="q"):
    q = req.query_params.get(key, "").strip()
    return f"%{q}%" if q else None


# ---------------------------------------------------------------- auth
class LoginReq(BaseModel):
    username: str
    password: str


@router.post("/login")
def login(body: LoginReq, req: Request):
    rate_limit(req, "admin-login", 10)
    u = db.one("SELECT * FROM users WHERE name=?", (body.username,))
    if not u or not security.check_password(body.password, u["password_hash"]) or not u["is_admin"] or u["status"] != 1:
        db.event("login", f"控制台登录失败：{body.username}（{client_ip(req)}）")
        raise HTTPException(status_code=401, detail="用户名或密码错误，或不是管理员")
    tok = security.new_token(u["id"], "admin")
    db.event("login", f"{u['name']} 登录控制台（{client_ip(req)}）")
    return {"token": tok, "user": {"name": u["name"], "display_name": u["display_name"]}}


@router.get("/me")
def me(u=admin):
    return {"name": u["name"], "display_name": u["display_name"]}


@router.post("/logout")
def logout(req: Request, u=admin):
    db.run("DELETE FROM tokens WHERE token=?", (security.bearer(req.headers.get("authorization")),))
    return {"ok": True}


# ---------------------------------------------------------------- overview
@router.get("/overview")
def overview(u=admin):
    t = db.now()
    day = t - 86400
    return {
        "devices": db.one("SELECT COUNT(*) n FROM devices")["n"],
        "online": db.one("SELECT COUNT(*) n FROM devices WHERE last_seen>?", (t - ONLINE_SECS,))["n"],
        "active_sessions": db.one("SELECT COUNT(*) n FROM audit_conn WHERE authorized_at>0 AND closed_at=0 AND created_at>?",
                                  (t - 7 * 86400,))["n"],
        "conns_today": db.one("SELECT COUNT(*) n FROM audit_conn WHERE authorized_at>?", (day,))["n"],
        "help_open": db.one("SELECT COUNT(*) n FROM help_requests WHERE status='open'")["n"],
        "alarms_today": db.one("SELECT COUNT(*) n FROM audit_alarm WHERE created_at>?", (day,))["n"],
        "users": db.one("SELECT COUNT(*) n FROM users")["n"],
        "events": db.all_("SELECT * FROM events ORDER BY id DESC LIMIT 15"),
        "help": db.all_("SELECT * FROM help_requests WHERE status='open' ORDER BY id DESC LIMIT 10"),
        "now": t,
    }


@router.get("/events")
def events(req: Request, u=admin):
    return page(req, "SELECT * FROM events")


# ---------------------------------------------------------------- devices
@router.get("/devices")
def devices(req: Request, u=admin):
    where, args = [], []
    q = like(req)
    if q:
        where.append("(d.id LIKE ? OR d.hostname LIKE ? OR d.alias LIKE ? OR d.username LIKE ? OR d.note LIKE ?)")
        args += [q] * 5
    if req.query_params.get("group") is not None and req.query_params.get("group") != "*":
        where.append("d.group_name=?")
        args.append(req.query_params.get("group"))
    if req.query_params.get("online") == "1":
        where.append("d.last_seen>?")
        args.append(db.now() - ONLINE_SECS)
    sql = ("SELECT d.id, d.hostname, d.username, d.os, d.version, d.cpu, d.memory, d.ip, d.group_name, d.alias, d.note,"
           " d.flavor, d.build, d.conns, d.last_seen, d.created_at, u.name AS login_user,"
           f" (d.last_seen > {db.now() - ONLINE_SECS}) AS online FROM devices d LEFT JOIN users u ON u.id=d.user_id"
           + (" WHERE " + " AND ".join(where) if where else ""))
    return page(req, sql, args, order="online DESC, last_seen DESC")


class DeviceUpd(BaseModel):
    alias: str | None = None
    note: str | None = None
    group_name: str | None = None


@router.put("/devices/{dev_id}")
def device_update(dev_id: str, body: DeviceUpd, u=admin):
    fields = {k: v for k, v in body.model_dump().items() if v is not None}
    if "group_name" in fields and fields["group_name"] and not db.one("SELECT 1 FROM groups WHERE name=?", (fields["group_name"],)):
        raise HTTPException(status_code=400, detail="分组不存在")
    if fields:
        db.run(f"UPDATE devices SET {', '.join(f'{k}=?' for k in fields)} WHERE id=?", (*fields.values(), dev_id))
        db.event("device", f"{u['name']} 修改设备 {dev_id}：{json.dumps(fields, ensure_ascii=False)}")
    return {"ok": True}


@router.delete("/devices/{dev_id}")
def device_delete(dev_id: str, u=admin):
    db.run("DELETE FROM devices WHERE id=?", (dev_id,))
    if re.fullmatch(r"[0-9A-Za-z_-]{1,32}", dev_id):
        try:
            os.remove(os.path.join(WALL_DIR, dev_id))
        except OSError:
            pass
    db.event("device", f"{u['name']} 删除设备记录 {dev_id}")
    return {"ok": True}


@router.post("/devices/{dev_id}/disconnect")
def device_disconnect(dev_id: str, u=admin):
    rows = db.all_("SELECT conn_id FROM audit_conn WHERE device_id=? AND closed_at=0 AND created_at>?",
                   (dev_id, db.now() - 7 * 86400))
    ids = [r["conn_id"] for r in rows]
    if not ids:
        raise HTTPException(status_code=400, detail="该设备当前没有进行中的连接")
    policy.request_disconnect(dev_id, ids)
    db.event("device", f"{u['name']} 强制断开 {dev_id} 的连接 {ids}")
    return {"ok": True, "conn_ids": ids}


@router.get("/devices/{dev_id}")
def device_detail(dev_id: str, u=admin):
    d = db.one("SELECT * FROM devices WHERE id=?", (dev_id,))
    if not d:
        raise HTTPException(status_code=404)
    d.pop("strategy_hash", None)
    d["online"] = d["last_seen"] > db.now() - ONLINE_SECS
    d["policy"] = policy.desired_options({**d, "strategy_hash": ""})
    d["recent_conns"] = db.all_("SELECT * FROM audit_conn WHERE device_id=? OR peer_id=? ORDER BY id DESC LIMIT 20",
                                (dev_id, dev_id))
    return d


# ---------------------------------------------------------------- groups & policies
class GroupReq(BaseModel):
    name: str
    note: str = ""
    work_hours_only: bool = False
    work_days: str = "1,2,3,4,5"
    work_start: str = "08:00"
    work_end: str = "19:00"
    approve_mode: str = ""
    record_sessions: bool = False
    company_only: bool = False
    extra_options: dict = {}


HM = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


def check_group(g: GroupReq):
    if not g.name.strip():
        raise HTTPException(status_code=400, detail="分组名不能为空")
    if not HM.match(g.work_start) or not HM.match(g.work_end):
        raise HTTPException(status_code=400, detail="时间格式应为 HH:MM")
    if g.approve_mode not in ("", "password", "click", "password-click"):
        raise HTTPException(status_code=400, detail="无效的验证方式")


@router.get("/groups")
def groups(u=admin):
    rows = db.all_("SELECT g.*, (SELECT COUNT(*) FROM devices d WHERE d.group_name=g.name) AS devices FROM groups g ORDER BY name")
    for r in rows:
        r["extra_options"] = json.loads(r["extra_options"] or "{}")
    return rows


@router.post("/groups")
def group_create(g: GroupReq, u=admin):
    check_group(g)
    if db.one("SELECT 1 FROM groups WHERE name=?", (g.name,)):
        raise HTTPException(status_code=400, detail="分组已存在")
    db.run("INSERT INTO groups(name, note, work_hours_only, work_days, work_start, work_end, approve_mode, record_sessions,"
           " company_only, extra_options) VALUES(?,?,?,?,?,?,?,?,?,?)",
           (g.name.strip(), g.note, int(g.work_hours_only), g.work_days, g.work_start, g.work_end, g.approve_mode,
            int(g.record_sessions), int(g.company_only), json.dumps(g.extra_options, ensure_ascii=False)))
    db.event("group", f"{u['name']} 创建分组 {g.name}")
    return {"ok": True}


@router.put("/groups/{name}")
def group_update(name: str, g: GroupReq, u=admin):
    check_group(g)
    db.run("UPDATE groups SET name=?, note=?, work_hours_only=?, work_days=?, work_start=?, work_end=?, approve_mode=?,"
           " record_sessions=?, company_only=?, extra_options=? WHERE name=?",
           (g.name.strip(), g.note, int(g.work_hours_only), g.work_days, g.work_start, g.work_end, g.approve_mode,
            int(g.record_sessions), int(g.company_only), json.dumps(g.extra_options, ensure_ascii=False), name))
    if g.name.strip() != name:
        db.run("UPDATE devices SET group_name=? WHERE group_name=?", (g.name.strip(), name))
    db.event("group", f"{u['name']} 修改分组/策略 {name}")
    return {"ok": True}


@router.delete("/groups/{name}")
def group_delete(name: str, u=admin):
    db.run("DELETE FROM groups WHERE name=?", (name,))
    db.run("UPDATE devices SET group_name='' WHERE group_name=?", (name,))
    db.event("group", f"{u['name']} 删除分组 {name}")
    return {"ok": True}


# ---------------------------------------------------------------- users
class UserReq(BaseModel):
    name: str
    display_name: str = ""
    email: str = ""
    note: str = ""
    password: str = ""
    is_admin: bool = False
    status: int = 1


@router.get("/users")
def users(u=admin):
    return db.all_("SELECT u.id, u.name, u.display_name, u.email, u.note, u.is_admin, u.status, u.created_at,"
                   " (SELECT COUNT(*) FROM devices d WHERE d.user_id=u.id) AS devices FROM users u ORDER BY u.name")


@router.post("/users")
def user_create(b: UserReq, u=admin):
    if not re.match(r"^[A-Za-z0-9_.@-]{2,32}$", b.name):
        raise HTTPException(status_code=400, detail="用户名只能用字母、数字和 _ . @ -，2–32 位")
    if len(b.password) < 8:
        raise HTTPException(status_code=400, detail="密码至少 8 位")
    if db.one("SELECT 1 FROM users WHERE name=?", (b.name,)):
        raise HTTPException(status_code=400, detail="用户名已存在")
    db.run("INSERT INTO users(name, display_name, email, note, password_hash, is_admin, status, created_at) VALUES(?,?,?,?,?,?,?,?)",
           (b.name, b.display_name, b.email, b.note, security.hash_password(b.password), int(b.is_admin), b.status, db.now()))
    db.event("user", f"{u['name']} 创建用户 {b.name}")
    return {"ok": True}


@router.put("/users/{uid}")
def user_update(uid: int, b: UserReq, u=admin):
    if uid == u["id"] and (not b.is_admin or b.status != 1):
        raise HTTPException(status_code=400, detail="不能取消自己的管理员权限或禁用自己")
    db.run("UPDATE users SET display_name=?, email=?, note=?, is_admin=?, status=? WHERE id=?",
           (b.display_name, b.email, b.note, int(b.is_admin), b.status, uid))
    if b.password:
        if len(b.password) < 8:
            raise HTTPException(status_code=400, detail="密码至少 8 位")
        db.run("UPDATE users SET password_hash=? WHERE id=?", (security.hash_password(b.password), uid))
        db.run("DELETE FROM tokens WHERE user_id=?", (uid,))
    if b.status != 1:
        db.run("DELETE FROM tokens WHERE user_id=?", (uid,))
    db.event("user", f"{u['name']} 修改用户 #{uid}")
    return {"ok": True}


@router.delete("/users/{uid}")
def user_delete(uid: int, u=admin):
    if uid == u["id"]:
        raise HTTPException(status_code=400, detail="不能删除自己")
    db.run("DELETE FROM tokens WHERE user_id=?", (uid,))
    db.run("UPDATE devices SET user_id=NULL WHERE user_id=?", (uid,))
    for ab in db.all_("SELECT guid FROM ab_profiles WHERE owner_id=?", (uid,)):
        for t in ("ab_peers", "ab_tags", "ab_rules"):
            db.run(f"DELETE FROM {t} WHERE ab_guid=?", (ab["guid"],))
    db.run("DELETE FROM ab_profiles WHERE owner_id=?", (uid,))
    db.run("DELETE FROM users WHERE id=?", (uid,))
    db.event("user", f"{u['name']} 删除用户 #{uid}")
    return {"ok": True}


# ---------------------------------------------------------------- shared address books
class AbReq(BaseModel):
    name: str
    note: str = ""
    rules: list[dict] = []   # [{user_id: int|null(=所有人), rule: 1|2|3}]


@router.get("/address-books")
def abs_list(u=admin):
    rows = db.all_("SELECT a.*, u.name AS owner_name, (SELECT COUNT(*) FROM ab_peers p WHERE p.ab_guid=a.guid) AS peers"
                   " FROM ab_profiles a JOIN users u ON u.id=a.owner_id ORDER BY a.personal, a.name")
    for r in rows:
        r["rules"] = db.all_("SELECT user_id, rule FROM ab_rules WHERE ab_guid=?", (r["guid"],))
    return rows


def _save_rules(guid, rules):
    db.run("DELETE FROM ab_rules WHERE ab_guid=?", (guid,))
    for r in rules:
        rule = int(r.get("rule", 1))
        if rule in (1, 2, 3):
            db.run("INSERT INTO ab_rules(ab_guid, user_id, rule) VALUES(?,?,?)", (guid, r.get("user_id"), rule))


@router.post("/address-books")
def ab_create(b: AbReq, u=admin):
    guid = str(uuidlib.uuid4())
    db.run("INSERT INTO ab_profiles(guid, name, owner_id, personal, note, created_at) VALUES(?,?,?,0,?,?)",
           (guid, b.name.strip() or "共享通讯录", u["id"], b.note, db.now()))
    _save_rules(guid, b.rules)
    db.event("ab", f"{u['name']} 创建共享通讯录 {b.name}")
    return {"ok": True, "guid": guid}


@router.put("/address-books/{guid}")
def ab_update(guid: str, b: AbReq, u=admin):
    db.run("UPDATE ab_profiles SET name=?, note=? WHERE guid=? AND personal=0", (b.name.strip(), b.note, guid))
    _save_rules(guid, b.rules)
    return {"ok": True}


@router.delete("/address-books/{guid}")
def ab_delete(guid: str, u=admin):
    for t in ("ab_peers", "ab_tags", "ab_rules"):
        db.run(f"DELETE FROM {t} WHERE ab_guid=?", (guid,))
    db.run("DELETE FROM ab_profiles WHERE guid=? AND personal=0", (guid,))
    db.event("ab", f"{u['name']} 删除共享通讯录 {guid}")
    return {"ok": True}


@router.get("/address-books/{guid}/peers")
def ab_peers(guid: str, u=admin):
    return [json.loads(r["data"]) for r in db.all_("SELECT data FROM ab_peers WHERE ab_guid=? ORDER BY id", (guid,))]


@router.post("/address-books/{guid}/peers")
def ab_peers_add(guid: str, body: dict, u=admin):
    """Bulk add devices: {"ids": [...], "tags": [...]} -- uses console device info for names."""
    for dev_id in body.get("ids", []):
        d = db.one("SELECT * FROM devices WHERE id=?", (str(dev_id),)) or {}
        p = {"id": str(dev_id), "alias": d.get("alias") or d.get("hostname", ""), "hostname": d.get("hostname", ""),
             "username": d.get("username", ""), "platform": (d.get("os") or "").split(" / ")[0], "tags": body.get("tags", [])}
        db.run("INSERT INTO ab_peers(ab_guid, id, data) VALUES(?,?,?) ON CONFLICT(ab_guid, id) DO UPDATE SET data=excluded.data",
               (guid, p["id"], json.dumps(p, ensure_ascii=False)))
    return {"ok": True}


# ---------------------------------------------------------------- audit / help / deploy
@router.get("/audit/conn")
def audit_conn(req: Request, u=admin):
    q = like(req)
    sql = "SELECT a.*, d.hostname, d.alias FROM audit_conn a LEFT JOIN devices d ON d.id=a.device_id"
    args = []
    if q:
        sql += " WHERE a.device_id LIKE ? OR a.peer_id LIKE ? OR a.peer_name LIKE ? OR d.hostname LIKE ? OR a.ip LIKE ? OR a.note LIKE ?"
        args = [q] * 6
    return page(req, sql, args, order="a.id DESC")


@router.get("/audit/file")
def audit_file(req: Request, u=admin):
    q = like(req)
    sql = "SELECT f.*, d.hostname, d.alias FROM audit_file f LEFT JOIN devices d ON d.id=f.device_id"
    args = []
    if q:
        sql += " WHERE f.device_id LIKE ? OR f.peer_id LIKE ? OR f.path LIKE ? OR f.info LIKE ?"
        args = [q] * 4
    return page(req, sql, args, order="f.id DESC")


@router.get("/audit/alarm")
def audit_alarm(req: Request, u=admin):
    return page(req, "SELECT a.*, d.hostname, d.alias FROM audit_alarm a LEFT JOIN devices d ON d.id=a.device_id",
                order="a.id DESC")


@router.get("/help")
def help_list(req: Request, u=admin):
    st = req.query_params.get("status", "")
    if st:
        return page(req, "SELECT * FROM help_requests WHERE status=?", (st,))
    return page(req, "SELECT * FROM help_requests")


@router.post("/help/{hid}/done")
def help_done(hid: int, u=admin):
    db.run("UPDATE help_requests SET status='done', handled_by=?, handled_at=? WHERE id=?", (u["name"], db.now(), hid))
    return {"ok": True}


@router.get("/deploy")
def deploy_list(req: Request, u=admin):
    return page(req, "SELECT * FROM deploy_log")


# ---------------------------------------------------------------- recordings
@router.get("/recordings")
def recordings(req: Request, u=admin):
    q = like(req)
    sql = "SELECT r.id, r.device_id, r.filename, r.size, r.finished, r.created_at, r.updated_at, d.hostname, d.alias" \
          " FROM recordings r LEFT JOIN devices d ON d.id=r.device_id"
    args = []
    if q:
        sql += " WHERE r.device_id LIKE ? OR r.filename LIKE ? OR d.hostname LIKE ?"
        args = [q] * 3
    return page(req, sql, args, order="r.id DESC")


def admin_from_query(token: str = Query(default="")):
    u = security.user_from_token(token)
    if not u or not u["is_admin"]:
        raise HTTPException(status_code=401)
    return u


@router.get("/recordings/{rid}/file")
def recording_file(rid: int, u=Depends(admin_from_query)):
    r = db.one("SELECT * FROM recordings WHERE id=?", (rid,))
    if not r or not os.path.exists(r["path"]):
        raise HTTPException(status_code=404)
    media = "video/webm" if r["filename"].endswith(".webm") else "video/mp4"
    return FileResponse(r["path"], media_type=media, filename=r["filename"])


@router.delete("/recordings/{rid}")
def recording_delete(rid: int, u=admin):
    r = db.one("SELECT * FROM recordings WHERE id=?", (rid,))
    if r:
        try:
            os.remove(r["path"])
        except OSError:
            pass
        db.run("DELETE FROM recordings WHERE id=?", (rid,))
        db.event("recording", f"{u['name']} 删除录屏 {r['filename']}")
    return {"ok": True}


# ---------------------------------------------------------------- settings / notifications
DEFAULT_SETTINGS = {"webhooks": [], "recording_retention_days": 30, "audit_retention_days": 365, "allow_register": True}


@router.get("/settings")
def settings(u=admin):
    return {k: db.get_setting(k, v) for k, v in DEFAULT_SETTINGS.items()} | {"notify_events": notify.EVENTS}


class SettingsReq(BaseModel):
    webhooks: list[dict] = []
    recording_retention_days: int = 30
    audit_retention_days: int = 365
    allow_register: bool = True


@router.put("/settings")
def settings_save(b: SettingsReq, u=admin):
    for w in b.webhooks:
        if w.get("kind") not in ("wecom", "dingtalk", "feishu") or not str(w.get("url", "")).startswith("https://"):
            raise HTTPException(status_code=400, detail="通知渠道必须是企业微信/钉钉/飞书，且地址以 https:// 开头")
    db.set_setting("webhooks", b.webhooks)
    db.set_setting("recording_retention_days", max(1, b.recording_retention_days))
    db.set_setting("audit_retention_days", max(7, b.audit_retention_days))
    db.set_setting("allow_register", bool(b.allow_register))
    db.event("settings", f"{u['name']} 修改了系统设置")
    return {"ok": True}


@router.post("/webhooks/test")
def webhook_test(w: dict, u=admin):
    try:
        resp = notify.send_one(w.get("kind", ""), w.get("url", ""), w.get("secret", ""), "✅ super远程桌面 通知测试",
                               [f"来自 super控制台，操作人：{u['name']}", "收到这条消息说明配置正确。"])
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"发送失败：{e}")
    return {"ok": True, "response": resp[:500]}


# ---------------------------------------------------------------- retention (background)
def _cleanup_once():
    t = db.now()
    rec_days = int(db.get_setting("recording_retention_days", 30))
    for r in db.all_("SELECT id, path FROM recordings WHERE created_at<?", (t - rec_days * 86400,)):
        try:
            os.remove(r["path"])
        except OSError:
            pass
        db.run("DELETE FROM recordings WHERE id=?", (r["id"],))
    audit_days = int(db.get_setting("audit_retention_days", 365))
    cut = t - audit_days * 86400
    for tbl in ("audit_conn", "audit_file", "audit_alarm", "events", "help_requests", "deploy_log"):
        db.run(f"DELETE FROM {tbl} WHERE created_at<?", (cut,))
    db.run("DELETE FROM tokens WHERE expires_at<?", (t,))


def start_cleanup_thread():
    def loop():
        while True:
            try:
                _cleanup_once()
            except Exception as e:  # noqa: BLE001
                db.event("system", f"定期清理失败：{e}")
            time.sleep(6 * 3600)

    threading.Thread(target=loop, daemon=True).start()


# ---------------------------------------------------------------- notices (client 消息中心)
class NoticeReq(BaseModel):
    title: str
    content: str = ""


@router.get("/notices")
def notices_list(u=admin):
    return db.all_("SELECT * FROM notices ORDER BY id DESC LIMIT 200")


@router.post("/notices")
def notice_create(b: NoticeReq, u=admin):
    title = b.title.strip()[:100]
    if not title:
        raise HTTPException(status_code=400, detail="请填写标题")
    nid = db.run("INSERT INTO notices(title, content, created_by, created_at) VALUES(?,?,?,?)",
                 (title, b.content.strip()[:5000], u["name"], db.now()))
    db.event("notice", f"{u['name']} 发布了公告：{title}")
    return {"ok": True, "id": nid}


@router.delete("/notices/{nid}")
def notice_delete(nid: int, u=admin):
    db.run("DELETE FROM notices WHERE id=?", (nid,))
    db.event("notice", f"{u['name']} 删除了公告 #{nid}")
    return {"ok": True}
