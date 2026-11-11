"""Live playtest of the Godot client: llm_server (stub turn) + the real game with rendering + a scenario.

    python tools/godot_playtest.py              # game/tools/playtest/smoke.gd
    python tools/godot_playtest.py --scenario offline   # runs without llm_server
    python tools/godot_playtest.py --scenario live --real   # the real OpenRouter model (cents), key from .env
    python tools/godot_playtest.py --scenario embedded --real   # the build's server.exe started by the game (run build_game.py first)

Screenshots and report.txt land in build/playtest/<scenario>/. The game runs with --profile=agent, so the
author's saves and settings stay untouched. The token is generated here and never printed. The game's window runs on a
hidden desktop (tool_base.run_unseen): never over the author's screen; BTR_PLAYTEST_SHOW=1 to watch it.
Exit code: 0 = all steps OK, 1 = a step failed, 2 = setup problem.
"""

import argparse
import os
import secrets
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from connectivity_e2e import OUT, PORT, ROOT, server_port, start_server, stop_server  # noqa: E402
from tool_base import free_port, godot as godot_path, port_busy, run_unseen  # noqa: E402


def run_embedded(godot: str, real: bool, out_dir: Path) -> subprocess.CompletedProcess:
    """The game alone, in a user folder of its own: server.exe from the build, the key only in the profile's backend.cfg."""
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    server = ROOT / "build" / "release" / version / "server.exe"
    if not server.exists():
        sys.exit(f"no {server}: run tools/build_game.py first")
    env = {k: v for k, v in os.environ.items() if k != "OPENROUTER_API_KEY" and not k.startswith("LLM_SERVER_")}
    env["BTR_SERVER_EXE"] = str(server)
    with tempfile.TemporaryDirectory() as home:
        env["APPDATA"] = home
        profile = Path(home) / "Godot" / "app_userdata" / "Between the Rolls" / "profiles" / "agent"
        (profile / "saves").mkdir(parents=True)
        key = ""
        if real:
            from dotenv import dotenv_values  # not through this process's environment: the game gets the key from its file

            key = os.environ.get("OPENROUTER_API_KEY") or dotenv_values(ROOT / ".env").get("OPENROUTER_API_KEY", "")
            # the address of the days before the embedded server, as the author's own file has it: it must not stop the server
            (profile / "backend.cfg").write_text(f'[backend]\n\nurl="ws://127.0.0.1:8765/ws"\nopenrouter_key="{key}"\n', encoding="utf-8")
        else:
            env["LLM_SERVER_TURN_HANDLER"] = "stub"
        args = [godot, "--path", str(ROOT / "game"), "--script", "res://tools/playtest/embedded.gd", "--", "--profile=agent",
                f"--out={out_dir.as_posix()}", "--seed=42"]
        proc = run_unseen(args, env, 1800)
        time.sleep(1.0)  # the server's watch of its parent
        left = subprocess.run(["tasklist", "/FI", "IMAGENAME eq server.exe", "/NH"], capture_output=True, text=True).stdout
        print(f"server.exe after the game: {'ALIVE' if 'server.exe' in left else 'gone'}")
        logs = [f for f in (profile / "master").rglob("*") if f.is_file()]
        print(f"the server's files: {len(logs)}, with the key: {sum(bool(key) and key.encode() in f.read_bytes() for f in logs)}")
        log = profile / "master" / "server.log"
        (out_dir / "server.log").write_text(log.read_text(encoding="utf-8") if log.exists() else "", encoding="utf-8")
        if key and key in (proc.stdout + proc.stderr):
            print("the key is in the game's log")
        return proc


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # reports hold Russian text and arrows; Windows consoles default to cp1251
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", default="smoke")
    parser.add_argument("--no-server", action="store_true", help="do not start llm_server (implied by «offline»)")
    parser.add_argument("--real", action="store_true", help="llm_server with the real model instead of the stub turn")
    opts = parser.parse_args()
    with_server = not opts.no_server and opts.scenario not in ("offline", "embedded")

    godot = godot_path()
    if not Path(godot).exists():
        print(f"Godot not found: {godot} (set GODOT)")
        return 2
    port = 0  # the server's own, told once it is up (start_server)
    if not with_server:  # a port nobody listens on: «offline» must find no master there
        port = free_port(PORT)
        if port_busy(port):
            print(f"ports {PORT}–{port} are busy")
            return 2
    out_dir = ROOT / "build" / "playtest" / opts.scenario
    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in [out_dir / "report.txt", *out_dir.glob("*.png")]:  # a scenario that fails to compile must not show the old report
        stale.unlink(missing_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    subprocess.run([godot, "--headless", "--path", str(ROOT / "game"), "--import"], capture_output=True, timeout=300)

    token = secrets.token_urlsafe(32)
    server = start_server(token, "agent" if opts.real else "stub", 0) if with_server else None
    try:
        if server:
            port = server_port(server, 60) or 0
            if not port:
                print("llm_server did not start, see build/connectivity/llm_server.log")
                return 2
            print(f"llm_server on port {port}")
        if opts.scenario == "embedded":
            proc = run_embedded(godot, opts.real, out_dir)
        else:
            args = [godot, "--path", str(ROOT / "game"), "--script", f"res://tools/playtest/{opts.scenario}.gd", "--",
                    "--profile=agent", f"--out={out_dir.as_posix()}", f"--backend-url=ws://127.0.0.1:{port}/ws", "--seed=42"]
            env = {**os.environ, "BTR_BACKEND_TOKEN": token, "BTR_PLAYTEST_REAL": "1" if opts.real else ""}
            proc = run_unseen(args, env, 1800)
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
