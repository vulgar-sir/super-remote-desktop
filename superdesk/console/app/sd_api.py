"""super远程桌面 extensions used by our own client / scripts (no login: called from employee PCs)."""
import re
import time
from collections import defaultdict, deque

from fastapi import APIRouter, HTTPException, Request
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
