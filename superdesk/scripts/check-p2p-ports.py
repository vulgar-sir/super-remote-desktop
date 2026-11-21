"""Check whether the standard RustDesk ports are really mapped to the server (needed for P2P mode).

P2P needs, on the server's public IP with the same port numbers inside and outside:
    TCP 21115 (NAT test), TCP+UDP 21116 (ID/rendezvous), TCP 21117 (relay)

A local "connect succeeded" proves nothing when a TUN-mode proxy (Clash etc.) is running: it completes
the TCP handshake itself. So every probe here is confirmed by tcpdump on the server's eth0 (via SSH),
with the known-mapped gateway port as a control.
If everything passes, set "p2p": true in secrets/superdesk.json and rebuild + publish the clients.

Usage: python superdesk/scripts/check-p2p-ports.py      (server needs tcpdump: apt install tcpdump)
"""
import json
import os
import socket
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(__file__))
import sdssh  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IFACE = os.environ.get("SUPERDESK_IFACE", "eth0")


def probe(host, port, proto) -> bool:
    c = sdssh.connect()
    seen = {}
    flt = f"tcp dst port {port} and tcp[tcpflags] & tcp-syn != 0" if proto == "tcp" else f"udp dst port {port}"

    def watch():
        _, out, _ = c.exec_command(f"timeout 8 tcpdump -ni {IFACE} -c 1 '{flt}' 2>/dev/null | head -1", timeout=20)
        seen["line"] = out.read().decode().strip()

    t = threading.Thread(target=watch)
    t.start()
    time.sleep(2)
    if proto == "tcp":
        try:
            socket.create_connection((host, port), timeout=4).close()
        except OSError:
            pass
    else:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        for _ in range(4):
            s.sendto(b"superdesk-p2p-check", (host, port))
            time.sleep(0.4)
        s.close()
    t.join()
    c.close()
    return bool(seen.get("line"))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    with open(os.path.join(ROOT, "secrets", "superdesk.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    host = cfg["server_host"]
    c = sdssh.connect()
    if sdssh.run(c, "command -v tcpdump >/dev/null") != 0:
        sys.exit("服务器未安装 tcpdump，请先执行：apt install -y tcpdump")
    c.close()
    if not probe(host, int(cfg["ws_port"]), "tcp"):
        sys.exit("对照组失败：网关端口的探测也没到达服务器，检测方法不可用（检查网卡名 SUPERDESK_IFACE）。")
    ok = True
    for port, proto, what in [(21115, "tcp", "NAT 测试"), (21116, "tcp", "ID 服务器"), (21116, "udp", "ID 服务器"),
                              (21117, "tcp", "中继")]:
        r = probe(host, port, proto)
        ok &= r
        print(f"{proto.upper()} {port}（{what}）：{'已映射' if r else '未映射'}")
    print("\n结论：" + ("端口均已映射，可在 secrets/superdesk.json 中设置 \"p2p\": true 后重新编译、发布客户端。"
                      if ok else "端口未全部映射，继续使用单端口 WebSocket 模式（全部走中继）。"
                                 "请在服务商处把 TCP 21115-21117、UDP 21116 按相同端口号映射到本机。"))


if __name__ == "__main__":
    main()
