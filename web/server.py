#!/usr/bin/env python3
"""ZeroTier Moon web console — backend server (Python 3 standard library only).

Serves the static console in this folder AND a small JSON/action API:

  GET  /api/status                     live moon status (falls back to sample)
  GET  /api/actions/log                current update-job log + running flag
  POST /api/actions/update             pull from the repo + reinstall (auth)
  POST /api/actions/restart            restart the moon container       (auth)
  POST /api/members/<addr>/authorize   authorize/deauthorize a member   (auth)

Action endpoints (everything that changes state) require HTTP Basic Auth.
The password is WEB_ADMIN_PASSWORD in ../.env. If it is unset the server runs
READ-ONLY: status works, actions return 403. Username is "admin" (any value is
accepted — only the password is checked).

Run it with `zmoon web` (recommended) or directly:

    python3 web/server.py --host 0.0.0.0 --port 8088

No third-party packages. Works with the python3 shipped in DSM / BusyBox.
"""

import base64
import glob
import hmac
import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WEB_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(WEB_DIR)
SAMPLE = os.path.join(WEB_DIR, "status.sample.json")

# ── .env parsing (KEY=VALUE, no shell) ───────────────────────────────────────
def load_env():
    env = {}
    path = os.path.join(REPO_DIR, ".env")
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                env[k.strip()] = v.split("#", 1)[0].strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return env

ENV = load_env()
CONTAINER = ENV.get("CONTAINER_NAME", "zerotier-moon")
DATA_DIR = ENV.get("DATA_DIR", "/volume1/docker/zerotier")
NETWORK_ID = ENV.get("ZT_NETWORK_ID", "")
UPDATE_BRANCH = ENV.get("AUTO_UPDATE_BRANCH", "dev")
ADMIN_PASSWORD = os.environ.get("WEB_ADMIN_PASSWORD", ENV.get("WEB_ADMIN_PASSWORD", ""))

# Branch names: word chars, dots, slashes, dashes — but not a leading dash
# (would be read as a git flag) and no ".." path segments.
BRANCH_RE = re.compile(r"^(?!-)(?!.*\.\.)[\w./-]{1,100}$")

# ── update job (single background job, log streamed to a file) ───────────────
LOG_PATH = os.path.join(DATA_DIR, "webupdate.log")
_job_lock = threading.Lock()
_job = {"proc": None, "started": 0.0}

def job_running():
    p = _job["proc"]
    return p is not None and p.poll() is None

def start_update(branch):
    with _job_lock:
        if job_running():
            return False, "an update is already running"
        if not BRANCH_RE.match(branch):
            return False, "invalid branch name"
        os.makedirs(DATA_DIR, exist_ok=True)
        logf = open(LOG_PATH, "w")
        logf.write(f"=== zmoon web update — branch {branch} — {time.strftime('%Y-%m-%d %H:%M:%S')} ===\n")
        logf.flush()
        # Command is normally `update.sh --branch <branch>`. ZTMOON_UPDATE_CMD
        # overrides it (used by the test suite to exercise the streaming path
        # without running a real deploy); it is split on spaces, no shell.
        override = os.environ.get("ZTMOON_UPDATE_CMD", "")
        cmd = override.split() if override else ["bash", os.path.join(REPO_DIR, "update.sh"), "--branch", branch]
        _job["proc"] = subprocess.Popen(
            cmd, cwd=REPO_DIR, stdout=logf, stderr=subprocess.STDOUT,
        )
        logf.close()   # child holds its own copy; keeping ours leaks one fd per update
        _job["started"] = time.time()
        return True, "started"

def read_log():
    try:
        with open(LOG_PATH) as f:
            return f.read()
    except FileNotFoundError:
        return ""

# ── live status producer (best-effort; every source degrades gracefully) ─────
def run(cmd, timeout=8):
    try:
        out = subprocess.run(cmd, cwd=REPO_DIR, capture_output=True, text=True, timeout=timeout)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""

def zt_info_and_peers():
    """info + listpeers in ONE docker exec — each exec costs 100-300ms on the NAS."""
    raw = run(["docker", "exec", CONTAINER, "sh", "-c",
               "zerotier-cli -j info; echo '---ZT-SEP---'; zerotier-cli -j listpeers"])
    info, peers = {}, []
    if raw and "---ZT-SEP---" in raw:
        a, _, b = raw.partition("---ZT-SEP---")
        try:
            info = json.loads(a) or {}
        except Exception:
            info = {}
        try:
            peers = json.loads(b) or []
        except Exception:
            peers = []
    return info, peers

def first_moon_id():
    for f in sorted(glob.glob(os.path.join(DATA_DIR, "zerotier-one", "moons.d", "*.moon"))):
        return os.path.basename(f)[:-5]
    return ""

# NETWORK_ID is interpolated into in-container shell commands. It comes from our
# own .env, but validating it keeps the string inert no matter what ends up there.
NETWORK_ID_RE = re.compile(r"^[0-9a-fA-F]{16}$")

def controller_network_and_members():
    """Network object + EVERY member detail in ONE docker exec.

    The naive version (one exec per member) cost 3+N execs per status call —
    measured 24 execs / 3.1s for 20 members. The container ships jq, so we walk
    the member list inside a single exec: first line is the network JSON, each
    following line is one member JSON tagged with its address.
    """
    if not NETWORK_ID_RE.match(NETWORK_ID):
        return None, {}
    script = (
        'TOK=$(cat /var/lib/zerotier-one/authtoken.secret); '
        f'BASE=http://localhost:9993/controller/network/{NETWORK_ID}; '
        'curl -s -H "X-ZT1-Auth: $TOK" "$BASE"; echo; '
        'for a in $(curl -s -H "X-ZT1-Auth: $TOK" "$BASE/member" | jq -r "keys[]" | head -200); do '
        '  curl -s -H "X-ZT1-Auth: $TOK" "$BASE/member/$a" | jq -c --arg a "$a" ". + {address: \\$a}"; '
        'done')
    raw = run(["docker", "exec", CONTAINER, "sh", "-c", script], timeout=20)
    if not raw:
        return None, {}
    lines = [ln for ln in raw.splitlines() if ln.strip()]
    net, members = None, {}
    for i, ln in enumerate(lines):
        try:
            obj = json.loads(ln)
        except Exception:
            continue
        if i == 0 and isinstance(obj, dict) and "address" not in obj:
            net = obj
        elif isinstance(obj, dict) and obj.get("address"):
            members[obj["address"]] = obj
    return net, members

def build_status():
    info, raw_peers = zt_info_and_peers()
    moon_id = first_moon_id()
    online = bool(info.get("online"))
    status = {
        "generatedAt": int(time.time()),
        "moon": {
            "id": moon_id or info.get("address", ""),
            "subtitle": "DS918+ root anchor",
            "online": online,
            "version": info.get("version", ""),
            "uptimeSeconds": None,
            "endpoints": {
                "lan1": (ENV.get("LAN1_CONTAINER_IP", "") + "/9993") if ENV.get("LAN1_CONTAINER_IP") else "",
                "lan2": (ENV.get("LAN2_CONTAINER_IP", "") + "/9993") if ENV.get("LAN2_CONTAINER_IP") else "",
                "public": (ENV.get("ZT_PUBLIC_ENDPOINT", "") + "/9993") if ENV.get("ZT_PUBLIC_ENDPOINT") else "",
            },
        },
        "interfaces": [],
        "peers": [],
        "network": {"id": NETWORK_ID, "name": "", "ipPool": "", "routes": []},
        "members": [],
    }

    for n in ("1", "2"):
        ip = ENV.get(f"LAN{n}_CONTAINER_IP", "")
        sub = ENV.get(f"LAN{n}_SUBNET", "")
        if ip:
            status["interfaces"].append(
                {"name": f"eth{int(n)-1}", "ip": ip, "subnet": sub,
                 "gateway": ENV.get(f"LAN{n}_GATEWAY", ""), "up": online})

    for p in raw_peers:
        paths = [{"address": x.get("address", ""), "active": bool(x.get("active"))}
                 for x in p.get("paths", [])]
        status["peers"].append({
            "address": p.get("address", ""), "role": p.get("role", ""),
            "latencyMs": p.get("latency", -1), "version": p.get("version", "-"),
            "paths": paths, "lastSeenSeconds": None,
        })

    if NETWORK_ID:
        net, members = controller_network_and_members()
        if net:
            status["network"]["name"] = net.get("name", "")
            pools = net.get("ipAssignmentPools", [])
            if pools:
                status["network"]["ipPool"] = f"{pools[0].get('ipRangeStart','')}–{pools[0].get('ipRangeEnd','')}"
            status["network"]["routes"] = [
                {"target": r.get("target", ""), "via": r.get("via")} for r in net.get("routes", [])]
        for addr, m in members.items():
            status["members"].append({
                "address": addr, "name": m.get("name", ""),
                "authorized": bool(m.get("authorized")),
                "ipAssignments": m.get("ipAssignments", []),
                "online": None, "lastSeenSeconds": None,
            })
    return status

# ── status cache — single-flight with a short TTL ────────────────────────────
# One browser tab polling plus a couple of extra tabs must not multiply docker
# execs: everything within the TTL is served from cache, and concurrent misses
# collapse into ONE refresh (the lock makes followers wait, then hit the cache).
STATUS_TTL = 3.0
_status_cache = {"at": 0.0, "data": None}
_status_lock = threading.Lock()

def cached_status():
    now = time.monotonic()
    if _status_cache["data"] is not None and now - _status_cache["at"] < STATUS_TTL:
        return _status_cache["data"]
    with _status_lock:
        now = time.monotonic()   # re-check: another thread may have refreshed while we waited
        if _status_cache["data"] is not None and now - _status_cache["at"] < STATUS_TTL:
            return _status_cache["data"]
        data = build_status()
        _status_cache["data"] = data
        _status_cache["at"] = time.monotonic()
        return data

def status_payload(client_ip):
    """Live status if the moon answers; otherwise the committed sample.
    The heavy moon/controller data is cached; only the cheap per-request
    client section is computed here."""
    try:
        s = cached_status()
        if s["moon"]["id"] or s["peers"]:
            out = dict(s)
            client = {"address": "", "ip": client_ip, "online": None, "orbitedMoon": None}
            for m in s.get("members", []):
                if client_ip and client_ip in m.get("ipAssignments", []):
                    client.update({"address": m["address"], "online": True,
                                   "orbitedMoon": bool(s["moon"]["id"])})
                    break
            out["client"] = client
            return out
    except Exception:
        pass
    try:
        with open(SAMPLE) as f:
            return json.load(f)
    except Exception:
        return {"_sample": True, "moon": {"online": False}, "peers": [], "members": []}

def set_member_authorized(addr, authorized):
    if not NETWORK_ID:
        return False
    body = json.dumps({"authorized": bool(authorized)})
    raw = run([
        "docker", "exec", CONTAINER, "sh", "-c",
        f'curl -s -X POST -H "X-ZT1-Auth: $(cat /var/lib/zerotier-one/authtoken.secret)" '
        f'-d \'{body}\' http://localhost:9993/controller/network/{NETWORK_ID}/member/{addr}',
    ])
    return bool(raw)

def restart_container():
    out = subprocess.run(["docker", "restart", CONTAINER], capture_output=True, text=True)
    return out.returncode == 0

# ── HTTP handler ─────────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    server_version = "ztmoon/1.0"

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _authed(self):
        if not ADMIN_PASSWORD:
            return False  # read-only mode: no password set → actions disabled
        hdr = self.headers.get("Authorization", "")
        if not hdr.startswith("Basic "):
            return False
        try:
            _, pw = base64.b64decode(hdr[6:]).decode().split(":", 1)
        except Exception:
            return False
        return hmac.compare_digest(pw, ADMIN_PASSWORD)

    def _require_auth(self):
        if self._authed():
            return True
        if not ADMIN_PASSWORD:
            self._send(403, {"error": "actions disabled — set WEB_ADMIN_PASSWORD in .env"})
            return False
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="ZeroTier Moon admin"')
        self.end_headers()
        return False

    def _client_ip(self):
        return self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()

    # ---- GET: API + static ----
    def do_GET(self):
        if self.path.split("?")[0] == "/api/status":
            return self._send(200, status_payload(self._client_ip()))
        if self.path.split("?")[0] == "/api/actions/log":
            return self._send(200, {"running": job_running(), "log": read_log()})
        if self.path.startswith("/api/"):
            return self._send(404, {"error": "not found"})
        return self._serve_static()

    def _serve_static(self):
        rel = self.path.split("?")[0].lstrip("/") or "index.html"
        full = os.path.normpath(os.path.join(WEB_DIR, rel))
        # Confine to WEB_DIR — the separator stops a sibling like web-notes/ passing.
        if (full != WEB_DIR and not full.startswith(WEB_DIR + os.sep)) or not os.path.isfile(full):
            self.send_error(404)
            return
        ctype = {
            ".html": "text/html", ".css": "text/css", ".js": "text/javascript",
            ".json": "application/json", ".svg": "image/svg+xml",
        }.get(os.path.splitext(full)[1], "application/octet-stream")
        with open(full, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # ---- POST: actions (auth-gated) ----
    def do_POST(self):
        path = self.path.split("?")[0]
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b""

        # Require a JSON content type. A cross-site form POST can only send
        # simple content types, so this blocks CSRF against the action endpoints
        # even if the browser has cached the Basic-Auth credentials.
        ctype = self.headers.get("Content-Type", "").split(";")[0].strip()
        if ctype != "application/json":
            return self._send(415, {"error": "Content-Type must be application/json"})
        try:
            body = json.loads(raw) if raw else {}
        except Exception:
            body = {}

        if not self._require_auth():
            return

        if path == "/api/actions/update":
            branch = body.get("branch") or UPDATE_BRANCH
            started, msg = start_update(branch)
            return self._send(200 if started else 409, {"started": started, "message": msg, "branch": branch})

        if path == "/api/actions/restart":
            ok = restart_container()
            _status_cache["at"] = 0.0   # next status read reflects the restart
            return self._send(200, {"ok": ok})

        m = re.match(r"^/api/members/([0-9a-fA-F]{10})/authorize$", path)
        if m:
            ok = set_member_authorized(m.group(1), bool(body.get("authorized")))
            if ok:
                _status_cache["at"] = 0.0   # don't serve pre-toggle member state
            return self._send(200 if ok else 502, {"ok": ok})

        return self._send(404, {"error": "not found"})

    def log_message(self, *a):  # quieter logs
        sys.stderr.write("%s - %s\n" % (self.address_string(), a[0] % a[1:]))

def main():
    host, port = "0.0.0.0", 8088
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == "--host" and i + 1 < len(args):
            host = args[i + 1]
        if a == "--port" and i + 1 < len(args):
            port = int(args[i + 1])
    mode = "ADMIN (actions enabled)" if ADMIN_PASSWORD else "READ-ONLY (set WEB_ADMIN_PASSWORD to enable actions)"
    print(f"ZeroTier Moon console → http://{host}:{port}   [{mode}]")
    print(f"  repo={REPO_DIR}  container={CONTAINER}  branch={UPDATE_BRANCH}")
    ThreadingHTTPServer((host, port), Handler).serve_forever()

if __name__ == "__main__":
    main()
