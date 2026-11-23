"""super远程桌面 extensions used by our own client / scripts (no login: called from employee PCs)."""
import os
import re
import secrets
import time
from collections import defaultdict, deque

from fastapi import APIRouter, Header, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

from . import db, notify, security

router = APIRouter(prefix="/api/superdesk")

_hits: dict[str, deque] = defaultdict(deque)


def client_ip(req: Request) -> str:
    return req.headers.get("x-real-ip") or (req.client.host if req.client else "")


def rate_limit(req: Request, key: str, per_minute: int):
    ip = client_ip(req)
    q = _hits[f"{key}:{ip}"]
    t = time.time()
    while q and q[0] < t - 60:
        q.popleft()
    if len(q) >= per_minute:
        raise HTTPException(status_code=429, detail="请求太频繁，请稍后再试")
    q.append(t)


def clip(s, n=200):
    return str(s or "")[:n]


def connect_link(device_id: str) -> str:
    return f"superdesk://connection/new/{device_id}"


def touch_device(device_id: str, **fields):
    """Create the device row if needed and update the given non-empty fields."""
    if not device_id:
        return
    db.run("INSERT OR IGNORE INTO devices(id, created_at) VALUES(?, ?)", (device_id, db.now()))
    sets = {k: v for k, v in fields.items() if v not in (None, "")}
    if sets:
        cols = ", ".join(f"{k}=?" for k in sets)
        db.run(f"UPDATE devices SET {cols} WHERE id=?", (*sets.values(), device_id))


class HelpReq(BaseModel):
    id: str
    uuid: str = ""
    device_name: str = ""
    os: str = ""
    flavor: str = ""
    build: str = ""
    message: str = ""


@router.post("/help")
def help_request(body: HelpReq, req: Request):
    rate_limit(req, "help", 5)
    if not body.id.strip():
        return {"error": "缺少设备 ID"}
    dev_id = clip(body.id, 32)
    ip = client_ip(req)
    hid = db.run("INSERT INTO help_requests(device_id, device_name, os, message, ip, created_at) VALUES(?,?,?,?,?,?)",
                 (dev_id, clip(body.device_name, 100), clip(body.os, 100), clip(body.message, 500), ip, db.now()))
    touch_device(dev_id, hostname=clip(body.device_name, 100), flavor=clip(body.flavor, 20), build=clip(body.build, 20))
    dev = db.one("SELECT alias, group_name FROM devices WHERE id=?", (dev_id,)) or {}
    name = dev.get("alias") or body.device_name or dev_id
    lines = [f"电脑：{name}（{body.os}）", f"ID：{dev_id}"]
    if dev.get("group_name"):
        lines.append(f"分组：{dev['group_name']}")
    lines.append(f"问题：{body.message or '（未填写）'}")
    lines.append(f"一键连接：{connect_link(dev_id)}")
    notify.notify("help", f"🆘 员工请求远程协助 #{hid}", lines)
    db.event("help", f"{name}（{dev_id}）请求协助：{clip(body.message, 80)}")
    return {"ok": True, "ticket": hid}


class DeployReq(BaseModel):
    id: str = ""
    hostname: str = ""
    user: str = ""
    flavor: str = ""
    build: str = ""
    note: str = ""


@router.post("/deploy")
def deploy_report(body: DeployReq, req: Request):
    rate_limit(req, "deploy", 20)
    ip = client_ip(req)
    dev_id = clip(body.id, 32)
    db.run("INSERT INTO deploy_log(device_id, hostname, username, flavor, build, note, ip, created_at)"
           " VALUES(?,?,?,?,?,?,?,?)",
           (dev_id, clip(body.hostname, 100), clip(body.user, 100), clip(body.flavor, 20), clip(body.build, 20),
            clip(body.note, 200), ip, db.now()))
    touch_device(dev_id, hostname=clip(body.hostname, 100), username=clip(body.user, 100),
                 flavor=clip(body.flavor, 20), build=clip(body.build, 20), note=clip(body.note, 200))
    notify.notify("deploy", "🖥️ 新电脑完成部署",
                  [f"电脑：{body.hostname}", f"ID：{dev_id or '（未获取到）'}", f"版本：{body.flavor} {body.build}"])
    db.event("deploy", f"{body.hostname}（{dev_id}）部署完成：{body.flavor} {body.build}")
    return {"ok": True}


class HelloReq(BaseModel):
    id: str
    flavor: str = ""
    build: str = ""
    platform: str = ""


@router.post("/hello")
def hello(body: HelloReq, req: Request):
    """Client start-up report: which flavor/build runs on this device (device list column)."""
    rate_limit(req, "hello", 30)
    touch_device(clip(body.id, 32), flavor=clip(body.flavor, 20), build=clip(body.build, 20))
    return {"ok": True}


@router.get("/ping")
def ping():
    return {"ok": True, "time": db.now()}


class RegisterReq(BaseModel):
    username: str
    password: str
    display_name: str = ""


@router.post("/register")
def register(b: RegisterReq, req: Request):
    """Self-registration from the client login dialog (internal deployment: no approval step).
    Same rules as accounts created in the console; admins can switch it off in 通知与设置."""
    if str(db.get_setting("allow_register", True)).lower() in ("false", "0", ""):
        raise HTTPException(status_code=403, detail="管理员已关闭客户端注册，请联系管理员创建账号")
    rate_limit(req, "register", 3)
    name = b.username.strip()
    if not re.match(r"^[A-Za-z0-9_.@-]{2,32}$", name):
        raise HTTPException(status_code=400, detail="用户名只能用字母、数字和 _ . @ -，2–32 位")
    if len(b.password) < 8 or len(b.password) > 128:
        raise HTTPException(status_code=400, detail="密码至少 8 位")
    if db.one("SELECT 1 FROM users WHERE name=?", (name,)):
        raise HTTPException(status_code=400, detail="用户名已存在")
    db.run("INSERT INTO users(name, display_name, email, note, password_hash, is_admin, status, created_at)"
           " VALUES(?,?,?,?,?,?,?,?)",
           (name, clip(b.display_name, 64), "", "客户端注册", security.hash_password(b.password), 0, 1, db.now()))
    db.event("user", f"{name} 在客户端注册了账号（{client_ip(req)}）")
    return {"ok": True}


DEVICE_ID_RE = re.compile(r"[0-9A-Za-z_-]{1,32}")


@router.get("/notices")
def notices(req: Request, id: str = ""):
    """Announcements for the client's 消息中心 (bell). Only devices the console has seen get them."""
    rate_limit(req, "notices", 30)
    if not DEVICE_ID_RE.fullmatch(id) or not db.one("SELECT 1 FROM devices WHERE id=?", (id,)):
        raise HTTPException(status_code=403, detail="设备未登记")
    return db.all_("SELECT id, title, content, created_at FROM notices ORDER BY id DESC LIMIT 50")


WALL_DIR = os.path.join(db.DATA_DIR, "wallpapers")
MAX_WALLPAPER = 1 << 20
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
JPEG_MAGIC = b"\xff\xd8\xff"


@router.post("/wallpaper")
async def wallpaper_upload(req: Request, id: str = "", uuid: str = ""):
    """A device's desktop wallpaper thumbnail (PNG/JPEG), shown as its preview on other clients' device page.
    The uploader must be the device itself: id + uuid must match what its sysinfo reported."""
    rate_limit(req, "wallpaper", 6)
    dev = db.one("SELECT uuid FROM devices WHERE id=?", (id,)) if DEVICE_ID_RE.fullmatch(id) else None
    if not dev or not dev["uuid"] or dev["uuid"] != uuid:
        raise HTTPException(status_code=403, detail="设备未登记")
    data = await req.body()
    if not data or len(data) > MAX_WALLPAPER or not (data[:8] == PNG_MAGIC or data[:3] == JPEG_MAGIC):
        raise HTTPException(status_code=400, detail="图片无效")
    os.makedirs(WALL_DIR, exist_ok=True)
    path = os.path.join(WALL_DIR, id)
    with open(path + ".tmp", "wb") as f:
        f.write(data)
    os.replace(path + ".tmp", path)
    return {"ok": True}


@router.get("/wallpaper/{device_id}")
def wallpaper_get(device_id: str, authorization: str | None = Header(default=None)):
    """Wallpaper thumbnail of a device, for clients logged in to a console account."""
    if not security.user_from_token(security.bearer(authorization)):
        raise HTTPException(status_code=401, detail="请先登录")
    path = os.path.join(WALL_DIR, device_id)
    if not DEVICE_ID_RE.fullmatch(device_id) or not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="没有壁纸")
    with open(path, "rb") as f:
        png = f.read(8) == PNG_MAGIC
    return FileResponse(path, media_type="image/png" if png else "image/jpeg",
                        headers={"Cache-Control": "private, max-age=600"})


# ---------------------------------------------------------------- 同账号免密
TICKET_TTL = 60


def _dev_label(dev_id: str) -> str:
    d = db.one("SELECT alias, hostname FROM devices WHERE id=?", (dev_id,))
    name = (d and (d["alias"] or d["hostname"])) or ""
    return f"{name}（{dev_id}）" if name else dev_id


class TicketReq(BaseModel):
    id: str
    target: str


@router.post("/same-account/ticket")
def same_account_ticket(b: TicketReq, req: Request, authorization: str | None = Header(default=None)):
    """A signed-in client wants to connect to `target` without its password. Allowed only when the token
    was issued to device `id` and `target` is signed in to the same account. The ticket is single-use,
    expires in a minute, and the target checks it through /same-account/verify."""
    rate_limit(req, "sa-ticket", 60)
    u = security.user_from_token(security.bearer(authorization))
    if not u or u["kind"] != "client":
        raise HTTPException(status_code=401, detail="Invalid token")
    me, target = clip(b.id, 32), clip(b.target, 32)
    if not me or me != u["device_id"] or not target or target == me:
        raise HTTPException(status_code=403, detail="not allowed")
    d = db.one("SELECT user_id FROM devices WHERE id=?", (target,))
    if not d or d["user_id"] != u["id"]:
        raise HTTPException(status_code=403, detail="not the same account")
    t = db.now()
    db.run("DELETE FROM sd_tickets WHERE created_at<?", (t - TICKET_TTL,))
    ticket = secrets.token_urlsafe(32)
    db.run("INSERT INTO sd_tickets(ticket, user_id, from_id, target_id, created_at) VALUES(?,?,?,?,?)",
           (ticket, u["id"], me, target, t))
    return {"ticket": ticket, "expires_in": TICKET_TTL}


class VerifyReq(BaseModel):
    ticket: str
    id: str      # the device being connected to (the caller)
    peer: str    # the connecting device, as its login request names it


@router.post("/same-account/verify")
def same_account_verify(b: VerifyReq, req: Request):
    """Called by the device being connected to. The ticket is consumed whatever the outcome; it passes
    only for this pair of devices, within its lifetime, while the target is still signed in to the
    account that asked for it."""
    rate_limit(req, "sa-verify", 60)
    ticket = clip(b.ticket, 100)
    r = db.one("SELECT * FROM sd_tickets WHERE ticket=?", (ticket,)) if ticket else None
    if r:
        db.run("DELETE FROM sd_tickets WHERE ticket=?", (ticket,))
    target, peer = clip(b.id, 32), clip(b.peer, 32)
    d = db.one("SELECT d.user_id, u.name, u.status FROM devices d JOIN users u ON u.id=d.user_id WHERE d.id=?",
               (target,))
    ok = bool(r and d and r["created_at"] >= db.now() - TICKET_TTL and r["target_id"] == target
              and r["from_id"] == peer and d["user_id"] == r["user_id"] and d["status"] == 1)
    if ok:
        db.event("connect", f"{d['name']}：{_dev_label(peer)} 以同账号身份免密连接 {_dev_label(target)}")
    return {"ok": ok}
