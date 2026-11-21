"""Headless Android emulator for checking the APK UI on Windows (WHPX acceleration).

Downloads emulator / platform-tools / an Android 14 x86_64 system image (runs arm64 apps through
the image's ARM translation) from the Tencent mirror of the Android SDK repository.

Usage:
  python android_emu.py setup                 # once
  python android_emu.py start                 # boots in the background, waits for boot
  python android_emu.py install <apk>
  python android_emu.py shot <out.png>
  python android_emu.py tap <x> <y> | text <s> | key <code> | launch <package> | stop
"""
import os
import re
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

MIRROR = "https://mirrors.cloud.tencent.com/AndroidSDK/"
SDK = os.path.join(os.environ.get("SUPERDESK_HOME", r"D:\superdesk"), "tools", "android-sdk")
AVD_HOME = os.path.join(os.environ.get("SUPERDESK_HOME", r"D:\superdesk"), "tools", "avd")
AVD = "superdesk34"
API, TAG = "34", "google_apis"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
ENV = dict(os.environ, ANDROID_SDK_ROOT=SDK, ANDROID_HOME=SDK, ANDROID_AVD_HOME=AVD_HOME)
ADB = os.path.join(SDK, "platform-tools", "adb.exe")


def fetch(url, dest=None):
    with opener.open(url, timeout=600) as r:
        data = r.read()
    if dest:
        with open(dest, "wb") as f:
            f.write(data)
    return data


def archive_url(xml_url, path):
    """URL of the windows (or host-independent) archive of remotePackage `path`."""
    root = ET.fromstring(fetch(xml_url))
    for pkg in root.iter("remotePackage"):
        if pkg.get("path") != path or (pkg.find("channelRef") is not None and pkg.find("channelRef").get("ref") != "channel-0"):
            continue
        for arc in pkg.iter("archive"):
            host = arc.find("host-os")
            if host is None or host.text == "windows":
                return xml_url.rsplit("/", 1)[0] + "/" + arc.find("complete/url").text
    raise SystemExit(f"package {path} not found in {xml_url}")


def unzip_into(url, dest_dir, strip_top=True):
    tmp = os.path.join(SDK, "_dl.zip")
    print("download", url)
    fetch(url, tmp)
    with zipfile.ZipFile(tmp) as z:
        for m in z.infolist():
            name = m.filename.split("/", 1)[1] if strip_top and "/" in m.filename else m.filename
            if not name or m.is_dir():
                continue
            out = os.path.join(dest_dir, name)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with z.open(m) as src, open(out, "wb") as f:
                f.write(src.read())
    os.remove(tmp)


def setup():
    os.makedirs(SDK, exist_ok=True)
    repo = MIRROR + "repository2-3.xml"
    if not os.path.exists(os.path.join(SDK, "emulator", "emulator.exe")):
        unzip_into(archive_url(repo, "emulator"), os.path.join(SDK, "emulator"))
    if not os.path.exists(ADB):
        unzip_into(archive_url(repo, "platform-tools"), os.path.join(SDK, "platform-tools"))
    img_dir = os.path.join(SDK, "system-images", f"android-{API}", TAG, "x86_64")
    if not os.path.exists(os.path.join(img_dir, "system.img")):
        unzip_into(archive_url(MIRROR + f"sys-img/{TAG}/sys-img2-3.xml", f"system-images;android-{API};{TAG};x86_64"), img_dir)
    os.makedirs(os.path.join(SDK, "platforms"), exist_ok=True)  # emulator only checks it exists
    avd_dir = os.path.join(AVD_HOME, AVD + ".avd")
    os.makedirs(avd_dir, exist_ok=True)
    with open(os.path.join(AVD_HOME, AVD + ".ini"), "w") as f:
        f.write(f"avd.ini.encoding=UTF-8\npath={avd_dir}\ntarget=android-{API}\n")
    with open(os.path.join(avd_dir, "config.ini"), "w") as f:
        f.write("\n".join([
            "abi.type=x86_64", "hw.cpu.arch=x86_64", f"image.sysdir.1=system-images/android-{API}/{TAG}/x86_64/",
            f"tag.id={TAG}", "hw.lcd.width=1080", "hw.lcd.height=2340", "hw.lcd.density=440", "hw.ramSize=4096",
            "disk.dataPartition.size=6G", "hw.keyboard=yes", "hw.gpu.enabled=yes", "hw.gpu.mode=swiftshader_indirect",
            "hw.audioInput=no", "hw.audioOutput=no", "showDeviceFrame=no", "fastboot.forceColdBoot=yes", ""]))
    print("setup done:", SDK)


def adb(*args, check=True, capture=True):
    r = subprocess.run([ADB, *args], env=ENV, capture_output=capture)
    if check and r.returncode:
        raise SystemExit(f"adb {' '.join(args)} failed: {r.stderr.decode(errors='replace')}")
    return r.stdout


def start():
    emu = os.path.join(SDK, "emulator", "emulator.exe")
    log = open(os.path.join(SDK, "emulator.log"), "w")
    # SUPERDESK_EMU_MEMORY=2048 boots with less RAM than the AVD's 4096 MB (low-memory hosts)
    mem = ["-memory", os.environ["SUPERDESK_EMU_MEMORY"]] if os.environ.get("SUPERDESK_EMU_MEMORY") else []
    subprocess.Popen([emu, "-avd", AVD, "-no-window", "-no-audio", "-no-boot-anim", "-no-snapshot",
                      "-gpu", "swiftshader_indirect", "-accel", "on", *mem], env=ENV, stdout=log, stderr=subprocess.STDOUT,
                     creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
    adb("start-server")
    deadline = time.time() + 600
    while time.time() < deadline:
        out = subprocess.run([ADB, "shell", "getprop", "sys.boot_completed"], env=ENV, capture_output=True).stdout
        if out.strip() == b"1":
            adb("shell", "settings", "put", "global", "window_animation_scale", "0")
            adb("shell", "settings", "put", "global", "transition_animation_scale", "0")
            adb("shell", "input", "keyevent", "82")  # unlock
            print("booted")
            return
        time.sleep(5)
    raise SystemExit("emulator did not boot in 10 minutes (see emulator.log)")


def main():
    cmd = sys.argv[1]
    if cmd == "setup":
        setup()
    elif cmd == "start":
        start()
    elif cmd == "install":
        print(adb("install", "-r", "-g", sys.argv[2]).decode(errors="replace"))
    elif cmd == "shot":
        png = adb("exec-out", "screencap", "-p")
        with open(sys.argv[2], "wb") as f:
            f.write(png)
        print("saved", sys.argv[2])
    elif cmd == "tap":
        adb("shell", "input", "tap", sys.argv[2], sys.argv[3])
    elif cmd == "text":
        adb("shell", "input", "text", sys.argv[2].replace(" ", "%s"))
    elif cmd == "key":
        adb("shell", "input", "keyevent", sys.argv[2])
    elif cmd == "launch":
        adb("shell", "monkey", "-p", sys.argv[2], "-c", "android.intent.category.LAUNCHER", "1")
    elif cmd == "stop":
        adb("emu", "kill", check=False)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
