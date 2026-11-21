"""Device access policy -> RustDesk heartbeat "strategy" (config options merged into the device).

Per device group:
  work_hours_only   outside work hours nobody may connect (id-whitelist that matches no one)
  company_only      only devices with a logged-in console account may connect (id-whitelist)
  approve_mode      password | click | password-click ('' = leave the device's own setting)
  record_sessions   record incoming sessions and upload them to the console
  extra_options     any other RustDesk option, pushed as-is

The client applies whatever strategy it receives and echoes `modified_at` back in later
heartbeats; until it does, the same strategy is re-sent. Keys we stop managing are cleared
with "" once.
"""
import datetime
import json
import os
import threading
from zoneinfo import ZoneInfo

from . import db

BLOCK_ALL = "superdesk-blocked-outside-work-hours"
NO_COMPANY_DEVICE = "superdesk-no-company-device"
TZ = os.environ.get("TZ", "Asia/Shanghai")

_disconnects: dict[str, set[int]] = {}
_lock = threading.Lock()


def in_work_hours(g, now: datetime.datetime | None = None) -> bool:
    now = now or datetime.datetime.now(ZoneInfo(TZ))
    days = {int(d) for d in str(g["work_days"]).replace("，", ",").split(",") if d.strip().isdigit()}
    if now.isoweekday() not in days:
        return False
    hm = now.strftime("%H:%M")
    return g["work_start"] <= hm < g["work_end"]


def company_ids() -> str:
    rows = db.all_("SELECT id FROM devices WHERE user_id IS NOT NULL AND last_seen > ?", (db.now() - 30 * 86400,))
    return ",".join(r["id"] for r in rows) or NO_COMPANY_DEVICE


def desired_options(dev) -> dict:
    g = db.one("SELECT * FROM groups WHERE name=?", (dev["group_name"],)) if dev["group_name"] else None
    if not g:
        return {}
    opts = {}
    # RustDesk: "password" | "click" | anything else = both (password or click-to-accept)
    if g["approve_mode"] in ("password", "click"):
        opts["approve-mode"] = g["approve_mode"]
    elif g["approve_mode"] == "password-click":
        opts["approve-mode"] = ""
    if g["record_sessions"]:
        opts["allow-auto-record-incoming"] = "Y"
        opts["superdesk-record-upload"] = "Y"
    if g["work_hours_only"] and not in_work_hours(g):
        opts["id-whitelist"] = BLOCK_ALL
    elif g["company_only"]:
        opts["id-whitelist"] = company_ids()
    try:
        extra = json.loads(g["extra_options"] or "{}")
    except ValueError:
        extra = {}
    if isinstance(extra, dict):
        opts.update({str(k): str(v) for k, v in extra.items()})
    return opts


def strategy_for(dev, client_ts: int):
    """Return (config_options, modified_at) to send, or None if the device is up to date."""
    try:
        state = json.loads(dev["strategy_hash"] or "{}")
    except ValueError:
        state = {}
    last_opts, last_ts, pending = state.get("opts", {}), state.get("ts", 0), state.get("pending")
    desired = desired_options(dev)
    if desired != last_opts:
        payload = dict(desired)
        for k in last_opts:
            if k not in desired:
                payload[k] = ""          # stop managing -> clear on the device
        ts = max(db.now(), last_ts + 1)
        db.run("UPDATE devices SET strategy_hash=? WHERE id=?",
               (json.dumps({"opts": desired, "ts": ts, "pending": payload}, ensure_ascii=False), dev["id"]))
        return (payload, ts) if payload else None
    if pending and last_ts and client_ts != last_ts:
        return pending, last_ts        # not acknowledged yet: send again
    return None


def request_disconnect(dev_id: str, conn_ids: list[int]):
    with _lock:
        _disconnects.setdefault(dev_id, set()).update(conn_ids)


def pop_disconnects(dev_id: str, alive: list[int]) -> list[int]:
    with _lock:
        want = _disconnects.get(dev_id)
        if not want:
            return []
        hit = [c for c in alive if c in want] if alive else []
        # forget requests whose connection is already gone
        _disconnects[dev_id] = {c for c in want if c in alive and c not in hit}
        return hit
