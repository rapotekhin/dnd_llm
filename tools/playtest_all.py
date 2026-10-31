"""A pack of live playtests at once: one import, one stub llm_server, several games side by side.

    python tools/playtest_all.py                     # every scenario of the stub master, 6 games at a time
    python tools/playtest_all.py --only smoke,combat --jobs 2
    python tools/playtest_all.py --slow              # real time: animations and timers as a player sees them

A game gets its own profile (agent-<scenario>), so scenarios do not wipe each other's saves. Without --slow the game
time runs off the frames (--fixed-fps) and the frames are not held back: timers and tweens end in a blink. Reports stay
in build/playtest/<scenario>/. The real master and the scenarios that need Forge go through tools/godot_playtest.py.
"""

import argparse
import concurrent.futures
import os
import secrets
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from connectivity_e2e import DEFAULT_GODOT, OUT, PORT, ROOT, port_busy, start_server, stop_server, wait_http  # noqa: E402

SCENARIOS = ROOT / "game" / "tools" / "playtest"
NEEDS_MORE = {"playtest_base", "live", "attach", "pack_only", "unseen", "providers", "image_prompts"}  # the real master or Forge
NO_SERVER = {"offline", "preview", "creation"}
FAST = ["--fixed-fps", "60", "--disable-vsync"]


def run_one(godot: str, name: str, port: int, token: str, slow: bool) -> dict:
    out_dir = ROOT / "build" / "playtest" / name
    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in [out_dir / "report.txt", *out_dir.glob("*.png")]:
        stale.unlink(missing_ok=True)
    backend = PORT + 999 if name in NO_SERVER else port  # nobody listens there
    args = [godot, "--path", str(ROOT / "game"), *([] if slow else FAST), "--script", f"res://tools/playtest/{name}.gd", "--",
            f"--profile=agent-{name}", f"--out={out_dir.as_posix()}", f"--backend-url=ws://127.0.0.1:{backend}/ws", "--seed=42"]
    env = {**os.environ, "BTR_BACKEND_TOKEN": token, "BTR_PLAYTEST_REAL": ""}
    start = time.monotonic()
    try:
        proc = subprocess.run(args, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
        log = proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as exc:
        log = f"{exc.stdout or ''}\n{exc.stderr or ''}\nTIMEOUT"
    (out_dir / "godot.log").write_text(log, encoding="utf-8")
    report = out_dir / "report.txt"
    last = report.read_text(encoding="utf-8").strip().splitlines()[-1] if report.exists() else "no report"
    fails = [line for line in report.read_text(encoding="utf-8").splitlines() if line.startswith("FAIL")] if report.exists() else []
    return {"name": name, "ok": last == "RESULT OK", "last": last, "fails": fails, "seconds": time.monotonic() - start,
            "errors": sum("SCRIPT ERROR" in line for line in log.splitlines()),
            "standins": sum("res://ui/" in line and ": no " in line for line in log.splitlines())}


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--only", default="", help="scenarios separated by commas")
    parser.add_argument("--slow", action="store_true", help="real time instead of the game time running off the frames")
    opts = parser.parse_args()
    godot = os.environ.get("GODOT", DEFAULT_GODOT)
    names = [n for n in opts.only.split(",") if n] or sorted(p.stem for p in SCENARIOS.glob("*.gd") if p.stem not in NEEDS_MORE)

    started = time.monotonic()
    subprocess.run([godot, "--headless", "--path", str(ROOT / "game"), "--import"], capture_output=True, timeout=300)
    print(f"import {time.monotonic() - started:.0f} s")
    port = PORT
    while port_busy(port) and port < PORT + 300:
        port += 1
    OUT.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(32)
    os.environ["LLM_SERVER_MAX_TURNS"] = str(opts.jobs)  # the server's default is one turn at a time: the games would get SERVER_BUSY
    server = start_server(token, "stub", port)
    results = []
    try:
        if not wait_http(f"http://127.0.0.1:{port}/healthz", 60):
            print("llm_server did not start, see build/connectivity/llm_server.log")
            return 2
        print(f"server {time.monotonic() - started:.0f} s")
        with concurrent.futures.ThreadPoolExecutor(opts.jobs) as pool:
            for f in concurrent.futures.as_completed([pool.submit(run_one, godot, n, port, token, opts.slow) for n in names]):
                r = f.result()
                results.append(r)
                mark = "ok  " if r["ok"] and not r["errors"] and not r["standins"] else "FAIL"
                print(f"{mark} {r['name']:<18} {r['seconds']:5.0f} s  errors={r['errors']} standins={r['standins']} [{len(results)}/{len(names)}]", flush=True)
    finally:
        stop_server(server)

    bad = [r for r in results if not r["ok"] or r["errors"] or r["standins"]]
    print(f"\n{len(results) - len(bad)} of {len(results)} green in {time.monotonic() - started:.0f} s")
    for r in sorted(bad, key=lambda x: x["name"]):
        print(f"  {r['name']}: {r['last']}, errors={r['errors']}, standins={r['standins']}")
        for line in r["fails"][:5]:
            print(f"    {line[:150]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
