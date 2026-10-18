"""Live playtest of the Godot client: llm_server (stub turn) + the real game with rendering + a scenario.

    python tools/godot_playtest.py              # game/tools/playtest/smoke.gd
    python tools/godot_playtest.py --scenario offline   # runs without llm_server
    python tools/godot_playtest.py --scenario live --real   # the real OpenRouter model (cents), key from .env

Screenshots and report.txt land in build/playtest/<scenario>/. The game runs with --profile=agent, so the
author's saves and settings stay untouched. The token is generated here and never printed.
Exit code: 0 = all steps OK, 1 = a step failed, 2 = setup problem.
"""

import argparse
import os
import secrets
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from connectivity_e2e import DEFAULT_GODOT, OUT, PORT, ROOT, port_busy, start_server, stop_server, wait_http  # noqa: E402


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # reports hold Russian text and arrows; Windows consoles default to cp1251
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", default="smoke")
    parser.add_argument("--no-server", action="store_true", help="do not start llm_server (implied by «offline»)")
    parser.add_argument("--real", action="store_true", help="llm_server with the real model instead of the stub turn")
    opts = parser.parse_args()
    with_server = not opts.no_server and opts.scenario != "offline"

    godot = os.environ.get("GODOT", DEFAULT_GODOT)
    if not Path(godot).exists():
        print(f"Godot not found: {godot} (set GODOT)")
        return 2
    if port_busy(PORT):
        print(f"port {PORT} is busy: stop the running llm_server first")
        return 2
    out_dir = ROOT / "build" / "playtest" / opts.scenario
    out_dir.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    subprocess.run([godot, "--headless", "--path", str(ROOT / "game"), "--import"], capture_output=True, timeout=300)

    token = secrets.token_urlsafe(32)
    server = start_server(token, "agent" if opts.real else "stub") if with_server else None
    try:
        if server and not wait_http(f"http://127.0.0.1:{PORT}/healthz", 60):
            print("llm_server did not start, see build/connectivity/llm_server.log")
            return 2
        args = [godot, "--path", str(ROOT / "game"), "--script", f"res://tools/playtest/{opts.scenario}.gd", "--",
                "--profile=agent", f"--out={out_dir.as_posix()}", f"--backend-url=ws://127.0.0.1:{PORT}/ws", "--seed=42"]
        env = {**os.environ, "BTR_BACKEND_TOKEN": token}
        proc = subprocess.run(args, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
        (out_dir / "godot.log").write_text(proc.stdout + proc.stderr, encoding="utf-8")
    finally:
        if server:
            stop_server(server)

    report = out_dir / "report.txt"
    print(report.read_text(encoding="utf-8") if report.exists() else "no report.txt — see godot.log")
    errors = [line for line in (proc.stdout + proc.stderr).splitlines() if "SCRIPT ERROR" in line or line.startswith("ERROR")]
    if errors:
        print("Godot errors:\n  " + "\n  ".join(errors[:20]))
    print(f"out: {out_dir}")
    return 1 if proc.returncode != 0 or errors else 0


if __name__ == "__main__":
    sys.exit(main())
