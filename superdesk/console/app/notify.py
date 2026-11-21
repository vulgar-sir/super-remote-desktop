"""Group-bot notifications: 企业微信 / 钉钉 / 飞书 webhooks (stdlib only, fire-and-forget)."""
import base64
import hashlib
import hmac
import json
import logging
import threading
import time
import urllib.parse
import urllib.request

from . import db

log = logging.getLogger("notify")

# Event kinds an admin can switch on/off in settings.
EVENTS = {
    "help": "员工请求协助",
    "conn": "有人连接了电脑",
    "deploy": "新电脑完成部署",
    "file": "远程文件传输",
    "alarm": "安全告警（密码错误过多等）",
}


def _post(url: str, payload: dict):
    data = json.dumps(payload, ensure_ascii=False).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json; charset=utf-8"})
    with urllib.request.urlopen(req, timeout=10) as r:
        body = r.read().decode("utf-8", "replace")
    return body


def _sign_dingtalk(url: str, secret: str) -> str:
    ts = str(int(time.time() * 1000))
    s = hmac.new(secret.encode(), f"{ts}\n{secret}".encode(), hashlib.sha256).digest()
    sign = urllib.parse.quote_plus(base64.b64encode(s))
    return f"{url}{'&' if '?' in url else '?'}timestamp={ts}&sign={sign}"


def _sign_feishu(secret: str):
    ts = str(int(time.time()))
    s = hmac.new(f"{ts}\n{secret}".encode(), b"", hashlib.sha256).digest()
    return ts, base64.b64encode(s).decode()


def send_one(kind: str, url: str, secret: str, title: str, lines: list[str]):
    text_md = f"**{title}**\n\n" + "\n".join(f"> {l}" if kind == "wecom" else f"- {l}" for l in lines)
    plain = title + "\n" + "\n".join(lines)
    if kind == "wecom":
        return _post(url, {"msgtype": "markdown", "markdown": {"content": text_md}})
    if kind == "dingtalk":
        if secret:
            url = _sign_dingtalk(url, secret)
        return _post(url, {"msgtype": "markdown", "markdown": {"title": title, "text": text_md}})
    if kind == "feishu":
        payload = {"msg_type": "text", "content": {"text": plain}}
        if secret:
            payload["timestamp"], payload["sign"] = _sign_feishu(secret)
        return _post(url, payload)
    raise ValueError(f"unknown webhook kind {kind}")


def webhooks():
    return db.get_setting("webhooks", [])


def notify(event: str, title: str, lines: list[str]):
    """Send to every enabled webhook subscribed to `event`, in a background thread."""
    targets = [w for w in webhooks() if w.get("enabled") and event in w.get("events", [])]
    if not targets:
        return

    def work():
        for w in targets:
            try:
                resp = send_one(w["kind"], w["url"], w.get("secret", ""), title, lines)
                log.info("webhook %s ok: %s", w.get("name"), resp[:200])
            except Exception as e:  # noqa: BLE001 -- never let a webhook break the API
                log.warning("webhook %s failed: %s", w.get("name"), e)
                db.event("webhook", f"通知发送失败（{w.get('name')}）：{e}")

    threading.Thread(target=work, daemon=True).start()
