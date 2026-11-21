"""Publish built clients to the server's download center (/download).

- picks the newest build per platform+flavor from dist/*.json (written by the build scripts)
- generates index.html (download page with Android QR code), latest.json (client update check),
  deploy scripts with the server URL filled in
- uploads everything to /opt/superdesk/download on the server and prunes old builds

Usage: python superdesk/scripts/publish.py [--notes "更新说明"] [--keep 3] [--dry-run]
"""
import argparse
import base64
import datetime
import hashlib
import html
import io
import json
import os
import re
import shutil
import sys
import time

import qrcode

sys.path.insert(0, os.path.dirname(__file__))
import sdssh  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DIST = os.path.join(ROOT, "dist")
STAGE = os.path.join(os.environ.get("SUPERDESK_HOME", r"D:\superdesk"), "publish", "download")
REMOTE = "/opt/superdesk/download"

LABELS = {
    "windows-full": ("Windows 完整版", "IT / 管理员使用：可以远程控制别人，也可以被控。"),
    "windows-helper": ("Windows 员工助手", "员工电脑使用：只能被远程协助，界面简洁，可一键“请求 IT 协助”。"),
    "android-full": ("Android 手机版", "手机 / 平板：可远程控制电脑，也可共享手机屏幕。"),
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def load_builds():
    builds = {}
    for name in os.listdir(DIST):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(DIST, name), encoding="utf-8-sig") as f:
            info = json.load(f)
        if not os.path.exists(os.path.join(DIST, info["file"])):
            continue
        if info["platform"] == "android" and info.get("abi", "arm64-v8a") != "arm64-v8a":
            key = f"android-{info['flavor']}-{info['abi']}"
        else:
            key = f"{info['platform']}-{info['flavor']}"
        if key not in builds or int(info["build"]) > int(builds[key]["build"]):
            builds[key] = info
    return builds


def qr_data_uri(text):
    img = qrcode.make(text, box_size=6, border=2)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def human(n):
    return f"{n / 1024 / 1024:.1f} MB"


def render_index(clients, server, notes):
    with open(os.path.join(ROOT, "flutter", "assets", "icon.svg"), encoding="utf-8") as f:
        logo = f.read()
    cards = []
    for key in ("windows-full", "windows-helper", "android-full"):
        c = clients.get(key)
        if not c:
            continue
        title, desc = LABELS[key]
        qr = ""
        if key.startswith("android"):
            qr = f'<img class="qr" alt="扫码下载" src="{qr_data_uri(server + c["url"])}"><div class="hint">手机扫码下载安装</div>'
        cards.append(f"""
      <section class="card">
        <h2>{html.escape(title)}</h2>
        <p class="desc">{html.escape(desc)}</p>
        {qr}
        <a class="btn" href="{html.escape(c['url'])}">下载 {html.escape(c['file'].rsplit('.', 1)[-1].upper())}</a>
        <dl>
          <dt>版本</dt><dd>{html.escape(c['version'])}（构建 {html.escape(c['build'])}）</dd>
          <dt>大小</dt><dd>{human(c['size'])}</dd>
          <dt>发布</dt><dd>{html.escape(c['published'])}</dd>
          <dt>SHA256</dt><dd class="hash">{html.escape(c['sha256'])}</dd>
        </dl>
      </section>""")
    notes_html = f'<p class="notes">更新说明：{html.escape(notes)}</p>' if notes else ""
    return f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>super远程桌面 下载中心</title>
<style>
  :root {{ --bg:#f4f6fb; --card:#fff; --text:#1d2433; --muted:#667085; --accent:#2f6bff; --line:#e4e8f0; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg:#11151d; --card:#1a202b; --text:#e6e9ef; --muted:#9aa4b5; --line:#2a3240; }} }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; font:15px/1.6 -apple-system,"Segoe UI","Microsoft YaHei",sans-serif; background:var(--bg); color:var(--text); }}
  header {{ display:flex; align-items:center; gap:14px; max-width:1040px; margin:0 auto; padding:32px 16px 8px; }}
  header svg {{ width:52px; height:52px; flex:none; }}
  h1 {{ font-size:24px; margin:0; }} header p {{ margin:2px 0 0; color:var(--muted); }}
  main {{ max-width:1040px; margin:0 auto; padding:16px; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:16px; }}
  .card {{ background:var(--card); border:1px solid var(--line); border-radius:14px; padding:20px; display:flex; flex-direction:column; }}
  .card h2 {{ font-size:18px; margin:0 0 4px; }} .desc {{ color:var(--muted); margin:0 0 14px; min-height:48px; }}
  .qr {{ width:168px; height:168px; align-self:center; border-radius:8px; background:#fff; }}
  .hint {{ text-align:center; color:var(--muted); font-size:13px; margin:4px 0 10px; }}
  .btn {{ display:block; text-align:center; background:var(--accent); color:#fff; text-decoration:none; padding:10px; border-radius:10px; font-weight:600; }}
  dl {{ display:grid; grid-template-columns:auto 1fr; gap:2px 12px; margin:14px 0 0; font-size:13px; }}
  dt {{ color:var(--muted); }} dd {{ margin:0; }} .hash {{ font-family:Consolas,monospace; font-size:11px; word-break:break-all; }}
  .notes {{ background:var(--card); border:1px solid var(--line); border-radius:10px; padding:10px 14px; }}
  .deploy {{ background:var(--card); border:1px solid var(--line); border-radius:14px; padding:20px; margin-top:16px; }}
  pre {{ background:var(--bg); border:1px solid var(--line); border-radius:8px; padding:10px; overflow-x:auto; font-size:13px; }}
  footer {{ max-width:1040px; margin:0 auto; padding:16px; color:var(--muted); font-size:12px; }}
  a {{ color:var(--accent); }}
</style></head>
<body>
<header>{logo}<div><h1>super远程桌面 下载中心</h1><p>公司内部远程协助工具，服务器自建，装好即用，无需任何设置。</p></div></header>
<main>
  {notes_html}
  <div class="grid">{''.join(cards)}
  </div>
  <section class="deploy">
    <h2>批量部署到公司电脑（IT 使用）</h2>
    <p>在目标电脑上以管理员身份运行，自动下载安装员工助手、注册为开机服务、设置固定密码，并把电脑名和 ID 上报到管理后台：</p>
    <pre>iwr {html.escape(server)}/download/deploy-superdesk.ps1 -OutFile $env:TEMP\\d.ps1; &amp; $env:TEMP\\d.ps1 -Password "公司统一密码"</pre>
    <p>或下载 <a href="deploy-superdesk.bat">deploy-superdesk.bat</a> + <a href="deploy-superdesk.ps1">deploy-superdesk.ps1</a>
       放在同一目录，右键“以管理员身份运行”。安装完整版加参数 <code>-Flavor full</code>。</p>
    <p>管理后台：<a href="/admin/">super控制台</a></p>
  </section>
</main>
<footer>基于开源项目 RustDesk（AGPL-3.0）二次开发 · 页面生成于 {datetime.datetime.now():%Y-%m-%d %H:%M}</footer>
</body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--notes", default="")
    ap.add_argument("--keep", type=int, default=3, help="builds kept per client on the server")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    with open(os.path.join(ROOT, "secrets", "superdesk.json"), encoding="utf-8") as f:
        server = json.load(f)["api_server"].rstrip("/")
    with open(os.path.join(ROOT, "superdesk", "flavors.json"), encoding="utf-8") as f:
        flavors = json.load(f)

    builds = load_builds()
    if not builds:
        sys.exit("dist/ has no builds -- run build-windows.ps1 / build-android.ps1 first")
    for _ in range(10):  # a just-copied exe can stay locked for a moment (antivirus scan)
        shutil.rmtree(STAGE, ignore_errors=True)
        if not os.path.exists(STAGE):
            break
        time.sleep(1)
    os.makedirs(STAGE)

    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    clients = {}
    for key, info in sorted(builds.items()):
        src = os.path.join(DIST, info["file"])
        shutil.copy2(src, os.path.join(STAGE, info["file"]))
        clients[key] = {
            "version": info["version"], "build": str(info["build"]), "file": info["file"],
            "url": f"/download/{info['file']}", "size": os.path.getsize(src), "sha256": sha256(src),
            "app_name": flavors[info["flavor"]]["app_name"], "published": now, "notes": args.notes,
        }
        print(f"{key:28} {info['file']}")

    with open(os.path.join(STAGE, "latest.json"), "w", encoding="utf-8") as f:
        json.dump({"updated": now, "clients": clients}, f, ensure_ascii=False, indent=2)
    with open(os.path.join(STAGE, "index.html"), "w", encoding="utf-8") as f:
        f.write(render_index(clients, server, args.notes))
    deploy_dir = os.path.join(ROOT, "superdesk", "deploy")
    with open(os.path.join(deploy_dir, "deploy-superdesk.ps1"), encoding="utf-8") as f:
        ps1 = f.read().replace("__SUPERDESK_SERVER__", server)
    with open(os.path.join(STAGE, "deploy-superdesk.ps1"), "w", encoding="utf-8-sig", newline="\r\n") as f:
        f.write(ps1)  # BOM: Windows PowerShell 5.1 needs it for non-ASCII scripts
    with open(os.path.join(deploy_dir, "deploy-superdesk.bat"), encoding="utf-8") as f:
        bat = f.read()
    with open(os.path.join(STAGE, "deploy-superdesk.bat"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(bat)

    if args.dry_run:
        print(f"dry run: staged in {STAGE}")
        return
    c = sdssh.connect()
    try:
        sdssh.putdir(c, STAGE, REMOTE)
        # Prune: keep the newest --keep builds of each client (by build number in the file name).
        sftp = c.open_sftp()
        files = [f for f in sftp.listdir(REMOTE) if f.endswith((".exe", ".apk"))]
        groups = {}
        for f in files:
            m = re.match(r"^([A-Za-z]+)-([\d.]+)-(\d{12})-(.+)$", f)  # App-ver-build-platform-arch.ext
            if m:
                groups.setdefault((m.group(1), m.group(4)), []).append((int(m.group(3)), f))
        for items in groups.values():
            for _, f in sorted(items, reverse=True)[args.keep:]:
                sftp.remove(f"{REMOTE}/{f}")
                print(f"pruned {f}")
        sftp.close()
    finally:
        c.close()
    print(f"published: {server}/download/")


if __name__ == "__main__":
    main()
