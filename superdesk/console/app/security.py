"""Password hashing (PBKDF2, stdlib only) and bearer-token auth."""
import hashlib
import hmac
import os
import secrets

from fastapi import Header, HTTPException

from . import db

ITERATIONS = 200_000
TOKEN_TTL = 30 * 24 * 3600


def hash_password(pw: str) -> str:
    salt = secrets.token_hex(16)
    dk = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), ITERATIONS)
    return f"pbkdf2${ITERATIONS}${salt}${dk.hex()}"


def check_password(pw: str, stored: str) -> bool:
    try:
        _, it, salt, h = stored.split("$")
        dk = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), int(it))
        return hmac.compare_digest(dk.hex(), h)
    except (ValueError, TypeError):
        return False


def new_token(user_id: int, kind: str = "client", device_id: str = "", device_uuid: str = "") -> str:
    tok = secrets.token_urlsafe(32)
    t = db.now()
    db.run("INSERT INTO tokens(token, user_id, kind, device_id, device_uuid, created_at, expires_at, last_used)"
           " VALUES(?,?,?,?,?,?,?,?)", (tok, user_id, kind, device_id, device_uuid, t, t + TOKEN_TTL, t))
    return tok


def user_from_token(token: str):
    if not token:
        return None
    r = db.one("SELECT t.token, t.kind, t.device_id, t.expires_at, u.* FROM tokens t JOIN users u ON u.id=t.user_id"
               " WHERE t.token=?", (token,))
    if not r or r["expires_at"] < db.now() or r["status"] != 1:
        return None
    db.run("UPDATE tokens SET last_used=? WHERE token=?", (db.now(), token))
    return r


def bearer(authorization: str | None) -> str:
    if authorization and authorization.lower().startswith("bearer "):
        return authorization[7:].strip()
    return ""


def optional_user(authorization: str | None = Header(default=None)):
    return user_from_token(bearer(authorization))


def require_user(authorization: str | None = Header(default=None)):
    u = user_from_token(bearer(authorization))
    if not u:
        raise HTTPException(status_code=401, detail="Invalid token")
    return u


def require_admin(authorization: str | None = Header(default=None)):
    u = require_user(authorization)
    if not u["is_admin"]:
        raise HTTPException(status_code=403, detail="Admin only")
    return u


def ensure_bootstrap_admin():
    """Create the first admin from env (or a random password written to /data) if no user exists."""
    if db.one("SELECT id FROM users LIMIT 1"):
        return
    name = os.environ.get("SUPERDESK_ADMIN_USER", "admin")
    pw = os.environ.get("SUPERDESK_ADMIN_PASSWORD") or secrets.token_urlsafe(12)
    db.run("INSERT INTO users(name, display_name, password_hash, is_admin, status, created_at) VALUES(?,?,?,?,?,?)",
           (name, "管理员", hash_password(pw), 1, 1, db.now()))
    path = os.path.join(db.DATA_DIR, "initial-admin.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"user={name}\npassword={pw}\n")
    os.chmod(path, 0o600)
    db.event("system", f"已创建初始管理员 {name}（密码见服务器 data/console/initial-admin.txt）")
