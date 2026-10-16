import json
import os
import shutil
import socket
import subprocess
import threading
import time

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from routes import nlp, websocket

PORT = int(os.environ.get("ISL_PORT", "8765"))

# --- OPTIONAL ADB USB TUNNEL --------------------------------------------------
# ISL_ADB_TUNNEL=auto (default): run `adb reverse` if adb is found, stay quiet otherwise.
# ISL_ADB_TUNNEL=0: never touch adb (cable-free / Wi-Fi mode).
ADB_MODE = os.environ.get("ISL_ADB_TUNNEL", "auto").lower()


def find_adb():
    found = shutil.which("adb")
    if found:
        return found
    for root in (os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"),
                 os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk")):
        if root and "%" not in root:
            cand = os.path.join(root, "platform-tools", "adb.exe" if os.name == "nt" else "adb")
            if os.path.isfile(cand):
                return cand
    return None


def keep_adb_alive(adb_path):
    """Keeps `adb reverse tcp:PORT tcp:PORT` in place; logs only on state changes."""
    tunnel_up = None
    while True:
        try:
            r = subprocess.run([adb_path, "reverse", f"tcp:{PORT}", f"tcp:{PORT}"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            ok = r.returncode == 0
        except Exception:
            ok = False
        if ok != tunnel_up:
            if ok:
                print(f"[ADB] USB tunnel active: phone 127.0.0.1:{PORT} -> laptop:{PORT}", flush=True)
            elif tunnel_up is not None:
                print("[ADB] USB tunnel down (no device on USB). Wi-Fi clients unaffected.", flush=True)
            tunnel_up = ok
        time.sleep(3)


def start_adb_tunnel():
    if ADB_MODE in ("0", "off", "false", "no"):
        print("[ADB] Tunnel disabled (ISL_ADB_TUNNEL=0).")
        return
    adb = find_adb()
    if not adb:
        print("[ADB] adb not found - USB tunnel skipped (Wi-Fi mode only).")
        return
    threading.Thread(target=keep_adb_alive, args=(adb,), daemon=True).start()


# --- NETWORK INFO -------------------------------------------------------------
def lan_ips():
    ips = []
    # Primary outbound interface (no packets are actually sent for UDP connect)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        ips.append(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips:
                ips.append(ip)
    except OSError:
        pass
    return [ip for ip in ips if not ip.startswith("127.") and not ip.startswith("169.254.")]


def interfaces():
    """[(adapter name, IPv4)] for every interface with an address. Windows:
    parsed from `ipconfig`; elsewhere / on failure: lan_ips() with no names."""
    out = []
    if os.name == "nt":
        try:
            txt = subprocess.run(["ipconfig"], capture_output=True, text=True, timeout=5).stdout
            name = "?"
            for line in txt.splitlines():
                if line and not line.startswith(" ") and line.rstrip().endswith(":"):
                    name = line.rstrip()[:-1].split(" adapter ", 1)[-1]
                elif "IPv4" in line and ":" in line:
                    ip = line.split(":", 1)[1].strip().split("(")[0].strip()
                    out.append((name, ip))
        except Exception:
            out = []
    if not out:
        out = [("", ip) for ip in lan_ips()]
    return [(n, ip) for n, ip in out if not ip.startswith(("127.", "169.254."))]


def is_tailscale(name, ip):
    """Tailscale uses the CGNAT range 100.64.0.0/10 (100.64.x.x - 100.127.x.x)."""
    try:
        a, b = (int(x) for x in ip.split(".")[:2])
    except ValueError:
        return False
    return "tailscale" in name.lower() or (a == 100 and 64 <= b <= 127)


def tailscale_dns_name():
    """This machine's MagicDNS name (e.g. laptop.tailXXXX.ts.net), or None."""
    exe = shutil.which("tailscale") or r"C:\Program Files\Tailscale\tailscale.exe"
    try:
        r = subprocess.run([exe, "status", "--json"], capture_output=True, timeout=3)
        # bytes + utf-8: device names can contain non-cp1252 characters
        name = json.loads(r.stdout.decode("utf-8", "replace")).get("Self", {}).get("DNSName", "")
        return name.rstrip(".") or None
    except Exception:
        return None


def print_banner():
    print("=" * 64)
    print(f" Ishara backend listening on 0.0.0.0:{PORT}")
    ifaces = interfaces()
    if ifaces:
        print(" Enter one of these in the app (Settings > BACKEND SERVER):")
        for name, ip in ifaces:
            tag = "  <- TAILSCALE" if is_tailscale(name, ip) else ""
            label = f"[{name}] " if name else ""
            print(f"   {label}{ip}:{PORT}    ->  ws://{ip}:{PORT}/   (test: http://{ip}:{PORT}/){tag}")
        if any(is_tailscale(n, ip) for n, ip in ifaces):
            dns = tailscale_dns_name()
            if dns:
                print(f"   [Tailscale MagicDNS] {dns}:{PORT}    ->  ws://{dns}:{PORT}/   "
                      f"(test: http://{dns}:{PORT}/)  <- TAILSCALE")
    else:
        print(" No LAN IP found - connect to Wi-Fi / phone hotspot.")
    print(f" USB (adb reverse): 127.0.0.1:{PORT}")
    print("=" * 64, flush=True)


app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_loaded": websocket.model is not None,
        "classes": websocket.classes,
        "time": time.time(),
    }


@app.get("/", response_class=HTMLResponse)
def index():
    # Same path as the WebSocket; plain HTTP GET gets this page so you can test
    # reachability from the phone's browser at http://<laptop-ip>:8765/
    ok = websocket.model is not None
    return f"""<!doctype html><html><head><meta name="viewport" content="width=device-width">
<title>Ishara backend</title></head><body style="font-family:sans-serif;padding:16px">
<h2>Ishara backend is reachable</h2>
<p>Model loaded: <b>{ok}</b> ({len(websocket.classes)} classes)</p>
<p>WebSocket: <code id="u"></code> &mdash; <span id="s">testing...</span></p>
<script>
var u = (location.protocol==='https:'?'wss://':'ws://') + location.host + '/';
document.getElementById('u').textContent = u;
try {{
  var ws = new WebSocket(u), t0;
  ws.onopen = function(){{ t0 = performance.now(); ws.send('{{"action":"ping"}}'); }};
  ws.onmessage = function(){{ document.getElementById('s').textContent =
      'OK, round trip ' + Math.round(performance.now()-t0) + ' ms'; ws.close(); }};
  ws.onerror = function(){{ document.getElementById('s').textContent = 'FAILED'; }};
}} catch(e) {{ document.getElementById('s').textContent = 'FAILED: ' + e; }}
</script></body></html>"""


app.include_router(nlp.router)
app.include_router(websocket.router)

if __name__ == "__main__":
    start_adb_tunnel()
    print_banner()
    uvicorn.run(app, host="0.0.0.0", port=PORT)
