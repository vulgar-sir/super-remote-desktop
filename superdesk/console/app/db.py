"""SQLite storage for super控制台. One connection per call; WAL mode for concurrent readers."""
import json
import os
import sqlite3
import time
from contextlib import contextmanager

DATA_DIR = os.environ.get("SUPERDESK_DATA", "/data")
DB_PATH = os.path.join(DATA_DIR, "console.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL DEFAULT '',
    email TEXT NOT NULL DEFAULT '',
    note TEXT NOT NULL DEFAULT '',
    password_hash TEXT NOT NULL,
    is_admin INTEGER NOT NULL DEFAULT 0,
    status INTEGER NOT NULL DEFAULT 1,          -- 1 normal, 0 disabled
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
    token TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    kind TEXT NOT NULL DEFAULT 'client',        -- client | admin
    device_id TEXT NOT NULL DEFAULT '',
    device_uuid TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    last_used INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS groups (
    name TEXT PRIMARY KEY,
    note TEXT NOT NULL DEFAULT '',
    -- access policy (pushed to devices through the heartbeat "strategy")
    work_hours_only INTEGER NOT NULL DEFAULT 0,
    work_days TEXT NOT NULL DEFAULT '1,2,3,4,5',
    work_start TEXT NOT NULL DEFAULT '08:00',
    work_end TEXT NOT NULL DEFAULT '19:00',
    approve_mode TEXT NOT NULL DEFAULT '',      -- '' keep | password | click | password-click
    record_sessions INTEGER NOT NULL DEFAULT 0,
    company_only INTEGER NOT NULL DEFAULT 0,    -- only devices with a logged-in console account may connect
    extra_options TEXT NOT NULL DEFAULT '{}'    -- JSON {option: value} pushed as-is
);
CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,                        -- RustDesk ID
    uuid TEXT NOT NULL DEFAULT '',
    hostname TEXT NOT NULL DEFAULT '',
    username TEXT NOT NULL DEFAULT '',
    os TEXT NOT NULL DEFAULT '',
    version TEXT NOT NULL DEFAULT '',
    cpu TEXT NOT NULL DEFAULT '',
    memory TEXT NOT NULL DEFAULT '',
    ip TEXT NOT NULL DEFAULT '',
    sysinfo TEXT NOT NULL DEFAULT '{}',
    user_id INTEGER,                            -- console account logged in on this device
    group_name TEXT NOT NULL DEFAULT '',
    alias TEXT NOT NULL DEFAULT '',
    note TEXT NOT NULL DEFAULT '',
    flavor TEXT NOT NULL DEFAULT '',
    build TEXT NOT NULL DEFAULT '',
    conns INTEGER NOT NULL DEFAULT 0,
    last_seen INTEGER NOT NULL DEFAULT 0,
    strategy_hash TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS ab_profiles (
    guid TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id INTEGER NOT NULL,
    personal INTEGER NOT NULL DEFAULT 0,
    note TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS ab_rules (            -- shared address book permissions
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ab_guid TEXT NOT NULL,
    user_id INTEGER,                            -- NULL = everyone
    rule INTEGER NOT NULL DEFAULT 1             -- 1 read, 2 read/write, 3 full control
);
CREATE TABLE IF NOT EXISTS ab_peers (
    ab_guid TEXT NOT NULL,
    id TEXT NOT NULL,
    data TEXT NOT NULL DEFAULT '{}',            -- full peer JSON as the client sent it
    PRIMARY KEY (ab_guid, id)
);
CREATE TABLE IF NOT EXISTS ab_tags (
    ab_guid TEXT NOT NULL,
    name TEXT NOT NULL,
    color INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (ab_guid, name)
);
CREATE TABLE IF NOT EXISTS ab_legacy (
    user_id INTEGER PRIMARY KEY,
    data TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_conn (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL DEFAULT '',         -- controlled device
    peer_id TEXT NOT NULL DEFAULT '',           -- controlling side
    peer_name TEXT NOT NULL DEFAULT '',
    conn_id INTEGER NOT NULL DEFAULT 0,
    session_id TEXT NOT NULL DEFAULT '',
    uuid TEXT NOT NULL DEFAULT '',
    ip TEXT NOT NULL DEFAULT '',
    type INTEGER NOT NULL DEFAULT 0,
    note TEXT NOT NULL DEFAULT '',
    guid TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    authorized_at INTEGER NOT NULL DEFAULT 0,
    closed_at INTEGER NOT NULL DEFAULT 0,
    raw TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS audit_conn_key ON audit_conn(device_id, conn_id, session_id);
CREATE TABLE IF NOT EXISTS audit_file (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL DEFAULT '',
    peer_id TEXT NOT NULL DEFAULT '',
    path TEXT NOT NULL DEFAULT '',
    is_file INTEGER NOT NULL DEFAULT 0,
    type INTEGER NOT NULL DEFAULT 0,
    info TEXT NOT NULL DEFAULT '{}',
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_alarm (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL DEFAULT '',
    typ INTEGER NOT NULL DEFAULT 0,
    info TEXT NOT NULL DEFAULT '{}',
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS help_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    device_name TEXT NOT NULL DEFAULT '',
    os TEXT NOT NULL DEFAULT '',
    message TEXT NOT NULL DEFAULT '',
    ip TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open',        -- open | done
    handled_by TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    handled_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS deploy_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL DEFAULT '',
    hostname TEXT NOT NULL DEFAULT '',
    username TEXT NOT NULL DEFAULT '',
    flavor TEXT NOT NULL DEFAULT '',
    build TEXT NOT NULL DEFAULT '',
    note TEXT NOT NULL DEFAULT '',
    ip TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS recordings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL DEFAULT '',
    filename TEXT NOT NULL,
    path TEXT NOT NULL,
    size INTEGER NOT NULL DEFAULT 0,
    finished INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS events (              -- admin-visible operation log
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    text TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
"""


def now() -> int:
    return int(time.time())


@contextmanager
def conn():
    os.makedirs(DATA_DIR, exist_ok=True)
    c = sqlite3.connect(DB_PATH, timeout=30)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA foreign_keys=ON")
    try:
        yield c
        c.commit()
    finally:
        c.close()


def init():
    with conn() as c:
        c.execute("PRAGMA journal_mode=WAL")
        c.executescript(SCHEMA)


def all_(sql, args=()):
    with conn() as c:
        return [dict(r) for r in c.execute(sql, args).fetchall()]


def one(sql, args=()):
    with conn() as c:
        r = c.execute(sql, args).fetchone()
        return dict(r) if r else None


def run(sql, args=()):
    with conn() as c:
        cur = c.execute(sql, args)
        return cur.lastrowid


def get_setting(key, default=None):
    r = one("SELECT value FROM settings WHERE key=?", (key,))
    if r is None:
        return default
    try:
        return json.loads(r["value"])
    except ValueError:
        return default


def set_setting(key, value):
    run("INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (key, json.dumps(value, ensure_ascii=False)))


def event(kind, text):
    run("INSERT INTO events(kind, text, created_at) VALUES(?, ?, ?)", (kind, text, now()))
