"""Print the SUPERDESK_* build env (KEY=VALUE lines) for one client flavor.

Merges git-ignored secrets/superdesk.json (server) with superdesk/flavors.json (branding).
Usage: python make_build_env.py <flavor>
"""
import datetime
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# STUN servers reachable from mainland China (Google's is not); ICE uses them to find each
# side's public address for WebRTC P2P. Override with "ice_servers" in secrets/superdesk.json.
DEFAULT_ICE_SERVERS = ("stun:stun.miwifi.com:3478,stun:stun.chat.bilibili.com:3478,"
                       "stun:stun.hitv.com:3478,stun:stun.cloudflare.com:3478")


def merge(a, b):
    out = dict(a)
    for k, v in b.items():
        out[k] = merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


def server_config(s):
    host = s["server_host"]
    over = {"key": s["rs_pub_key"], "api-server": s["api_server"]}
    if s.get("p2p"):
        # Standard ports mapped 1:1 (TCP 21115-21117, UDP 21116): direct P2P, relay as fallback.
        over.update({"custom-rendezvous-server": host, "relay-server": host, "allow-websocket": "N"})
    else:
        # Single public port: WebSocket through the nginx gateway. Signalling (and the relay
        # fallback) go over that port; WebRTC then tries a direct UDP path between the two
        # devices (patched hbbs forwards the SDP offer/answer and ICE candidates).
        over.update({"custom-rendezvous-server": host, "relay-server": host,
                     "allow-websocket": "Y", "websocket-port": str(s["ws_port"])})
    default = {"enable-webrtc": "N" if s.get("webrtc") is False else "Y",
               "ice-servers": s.get("ice_servers", DEFAULT_ICE_SERVERS)}
    return {"override-settings": over, "default-settings": default}


def main():
    flavor = sys.argv[1] if len(sys.argv) > 1 else "full"
    secrets_path = os.path.join(ROOT, "secrets", "superdesk.json")
    if not os.path.exists(secrets_path):
        sys.exit(f"Missing {secrets_path} -- copy superdesk/config.example.json there and fill in your server.")
    with open(secrets_path, encoding="utf-8") as f:
        s = json.load(f)
    with open(os.path.join(ROOT, "superdesk", "flavors.json"), encoding="utf-8") as f:
        flavors = json.load(f)
    if flavor not in flavors:
        sys.exit(f"unknown flavor {flavor!r}, choose from {list(flavors)}")
    fl = flavors[flavor]
    cfg = merge(fl.get("client_config", {}), server_config(s))
    build = os.environ.get("SUPERDESK_BUILD") or datetime.datetime.now().strftime("%Y%m%d%H%M")
    # Read by the Flutter side (update check, help request) via mainGetOptionSync.
    cfg.setdefault("default-settings", {}).update(
        {"superdesk-flavor": flavor, "superdesk-build": build, "superdesk-display-name": fl["display_name"]})
    env = {
        "SUPERDESK_BUILD": build,
        "SUPERDESK_FLAVOR": flavor,
        "SUPERDESK_APP_NAME": fl["app_name"],
        "SUPERDESK_DISPLAY_NAME": fl["display_name"],
        "SUPERDESK_RENDEZVOUS_SERVER": s["server_host"],
        "SUPERDESK_RS_PUB_KEY": s["rs_pub_key"],
        "SUPERDESK_CONFIG": json.dumps(cfg, ensure_ascii=False, separators=(",", ":")),
    }
    sys.stdout.reconfigure(encoding="utf-8")
    for k, v in env.items():
        print(f"{k}={v}")


if __name__ == "__main__":
    main()
