"""Check the WeCom / DingTalk / Feishu webhook payloads against a local mock server.

Usage: python superdesk/console/tests/test_notify.py
"""
import base64
import hashlib
import hmac
import json
import os
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
os.environ.setdefault("SUPERDESK_DATA", os.path.join(os.environ.get("TEMP", "/tmp"), "sd-notify-test"))
from app import notify  # noqa: E402

got = []


class H(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        body = self.rfile.read(int(self.headers["Content-Length"]))
        got.append((self.path, json.loads(body)))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"errcode":0}')

    def log_message(self, *a):
        pass


srv = HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{srv.server_port}"
lines = ["电脑：财务-01（windows）", "ID：123456789", "问题：打印机坏了"]
fails = 0


def check(name, cond, detail=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" -> {detail}"))
    fails += 0 if cond else 1


notify.send_one("wecom", base + "/wecom?key=k", "", "🆘 员工请求远程协助", lines)
p, b = got[-1]
check("wecom markdown", b["msgtype"] == "markdown" and "打印机坏了" in b["markdown"]["content"], b)

notify.send_one("dingtalk", base + "/ding?access_token=t", "SECdemo", "🆘 员工请求远程协助", lines)
p, b = got[-1]
q = urllib.parse.parse_qs(urllib.parse.urlparse(p).query)
ts = q["timestamp"][0]
expect = base64.b64encode(hmac.new(b"SECdemo", f"{ts}\nSECdemo".encode(), hashlib.sha256).digest()).decode()
check("dingtalk signed url", q["sign"][0] == expect and q["access_token"][0] == "t", p)
check("dingtalk markdown", b["msgtype"] == "markdown" and b["markdown"]["title"].endswith("远程协助"), b)

notify.send_one("feishu", base + "/feishu", "fs-secret", "🆘 员工请求远程协助", lines)
p, b = got[-1]
expect = base64.b64encode(hmac.new(f"{b['timestamp']}\nfs-secret".encode(), b"", hashlib.sha256).digest()).decode()
check("feishu signed text", b["msg_type"] == "text" and b["sign"] == expect and "打印机坏了" in b["content"]["text"], b)

srv.shutdown()
print("\nALL PASSED" if not fails else f"\n{fails} FAILED")
sys.exit(1 if fails else 0)
