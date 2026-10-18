"""End-to-end connectivity check: Godot ↔ (Caddy wss://) ↔ llm_server (M0 spike, ADR-0007/0009).

    python tools/connectivity_e2e.py            # direct ws:// and through Caddy wss:// (needs Docker)
    python tools/connectivity_e2e.py --no-proxy # direct ws:// only

Starts llm_server with a throwaway token, optionally the dev Caddy container, then runs the headless Godot
check (game/tools/connectivity_check.gd) for each case. The token is generated here and never printed.
Exit code 0 = all cases passed. Godot binary: env GODOT or the Steam install path.
"""

import argparse
import json
import os
import secrets
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INFRA = ROOT / "infra" / "dev"
CA_CERT = INFRA / "caddy-data" / "caddy" / "pki" / "authorities" / "local" / "root.crt"
OUT = ROOT / "build" / "connectivity"
DEFAULT_GODOT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PORT = 8765
PROXY_PORT = 8443


def wait_http(url: str, timeout: float, context: ssl.SSLContext | None = None) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2, context=context) as resp:
                if resp.status == 200:
                    return True
        except OSError:
            pass
        time.sleep(0.3)
    return False


def port_busy(port: int) -> bool:
    with socket.socket() as sock:
        return sock.connect_ex(("127.0.0.1", port)) == 0


def stop_server(proc: subprocess.Popen) -> None:
    # `uv run` spawns python as a child; on Windows terminate() kills only uv and leaves the server on the port.
    if os.name == "nt":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], capture_output=True)
    else:
        proc.terminate()
    proc.wait(timeout=10)


def start_server(token: str) -> subprocess.Popen:
    uv = shutil.which("uv")
    if not uv:
        sys.exit("uv not found: activate venv or install uv")
    env = {**os.environ, "LLM_SERVER_TOKEN": token, "LLM_SERVER_PORT": str(PORT)}
    env.pop("VIRTUAL_ENV", None)  # llm_server has its own uv environment
    # Docker reaches the host through host.docker.internal, which is not the loopback interface.
    env["LLM_SERVER_HOST"] = os.environ.get("LLM_SERVER_HOST", "127.0.0.1")
    log = open(OUT / "llm_server.log", "w", encoding="utf-8")
    return subprocess.Popen([uv, "run", "--project", str(ROOT / "llm_server"), "llm_server"],
                            cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)


def run_godot(godot: str, token: str, name: str, url: str, expect: str, ca: Path | None, idle_s: int = 0) -> dict:
    args = [godot, "--headless", "--path", str(ROOT / "game"), "--script", "res://tools/connectivity_check.gd",
            "--", f"--backend-url={url}", f"--expect={expect}", f"--idle-s={idle_s}"]
    if ca:
        args.append(f"--backend-ca={ca}")
    env = {**os.environ, "BTR_BACKEND_TOKEN": token}
    started = time.monotonic()
    proc = subprocess.run(args, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90 + idle_s)
    (OUT / f"godot_{name}.log").write_text(proc.stdout + proc.stderr, encoding="utf-8")
    result = {}
    for line in proc.stdout.splitlines():
        if line.startswith("RESULT "):
            result = json.loads(line[len("RESULT "):])
    result.update(case=name, exit=proc.returncode, wall_ms=int((time.monotonic() - started) * 1000))
    result["passed"] = proc.returncode == 0 and result.get("ok") is True
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-proxy", action="store_true", help="skip the Caddy wss:// cases")
    parser.add_argument("--quick", action="store_true", help="skip the 45 s idle case")
    parser.add_argument("--keep-proxy", action="store_true", help="leave the Caddy container running")
    opts = parser.parse_args()

    godot = os.environ.get("GODOT", DEFAULT_GODOT)
    if not Path(godot).exists():
        sys.exit(f"Godot not found: {godot} (set GODOT)")
    OUT.mkdir(parents=True, exist_ok=True)
    if not (ROOT / "game" / ".godot" / "global_script_class_cache.cfg").exists():
        subprocess.run([godot, "--headless", "--path", str(ROOT / "game"), "--import"], capture_output=True, timeout=180)

    if port_busy(PORT):
        sys.exit(f"port {PORT} is busy: stop the running llm_server first")
    token = secrets.token_urlsafe(32)
    bad_token = secrets.token_urlsafe(32)
    server = start_server(token)
    results: list[dict] = []
    compose = ["docker", "compose", "-f", str(INFRA / "compose.yaml")]
    try:
        if not wait_http(f"http://127.0.0.1:{PORT}/healthz", 30):
            print("llm_server did not start, see build/connectivity/llm_server.log")
            return 1
        direct = f"ws://127.0.0.1:{PORT}/ws"
        results.append(run_godot(godot, token, "ws_ok", direct, "ok", None))
        results.append(run_godot(godot, bad_token, "ws_bad_token", direct, "reject", None))

        if not opts.no_proxy:
            subprocess.run([*compose, "up", "-d"], check=True, capture_output=True)
            deadline = time.monotonic() + 30
            while not CA_CERT.exists() and time.monotonic() < deadline:
                time.sleep(0.3)
            ctx = ssl.create_default_context(cafile=str(CA_CERT)) if CA_CERT.exists() else None
            if ctx is None or not wait_http(f"https://localhost:{PROXY_PORT}/healthz", 30, ctx):
                print("Caddy did not come up (or cannot reach llm_server), see `docker compose logs`")
                return 1
            proxied = f"wss://localhost:{PROXY_PORT}/ws"
            results.append(run_godot(godot, token, "wss_ok", proxied, "ok", CA_CERT))
            results.append(run_godot(godot, bad_token, "wss_bad_token", proxied, "reject", CA_CERT))
            results.append(run_godot(godot, token, "wss_untrusted_ca", proxied, "reject", None))
            if not opts.quick:
                # Idle past one ping interval + ping timeout: pongs must flow through Caddy.
                results.append(run_godot(godot, token, "wss_idle_45s", proxied, "ok", CA_CERT, idle_s=45))
    finally:
        stop_server(server)
        if not opts.no_proxy and not opts.keep_proxy:
            subprocess.run([*compose, "down"], capture_output=True)

    print(f"{'case':<18} {'pass':<5} {'connect':>8} {'enter':>7} {'action':>7}  detail")
    for r in results:
        print(f"{r['case']:<18} {'yes' if r['passed'] else 'NO':<5} {r.get('connect_ms', '-'):>8} "
              f"{r.get('enter_ms', '-'):>7} {r.get('action_ms', '-'):>7}  {r.get('detail', 'no RESULT line')}")
    (OUT / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if results and all(r["passed"] for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
