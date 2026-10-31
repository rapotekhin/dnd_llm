"""The game's runnable Windows build: build/release/<version>/BetweenTheRolls.exe, one file.

    python tools/build_game.py

Takes the version from the root VERSION. Only the game goes in: the master's server runs apart, and the game
takes its address and token from the settings. Needs Godot's export templates of the editor's version in
%APPDATA%/Godot/export_templates/<version>.stable (the Windows files of the official .tpz). Ends by starting the
build for a few seconds: a build that does not start fails here.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GODOT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PRESET = "Windows"
NAME = "BetweenTheRolls.exe"
SMOKE_FRAMES = 300
BAD = ("SCRIPT ERROR", "Parse Error", "Failed to load", "Cannot open file")


def run(args: list[str], timeout: int) -> tuple[int, str]:
    proc = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    return proc.returncode, proc.stdout + proc.stderr


def smoke(exe: Path) -> list[str]:
    """Starts the build without a window in a clean user folder of its own; returns the lines that went wrong."""
    with tempfile.TemporaryDirectory() as home:
        env = {**os.environ, "APPDATA": home}
        proc = subprocess.run([str(exe), "--headless", "--quit-after", str(SMOKE_FRAMES)], env=env, capture_output=True,
                              text=True, encoding="utf-8", errors="replace", timeout=120)
    log = proc.stdout + proc.stderr
    bad = [line for line in log.splitlines() if any(word in line for word in BAD)]
    if proc.returncode != 0:
        bad.append(f"exit code {proc.returncode}")
    return bad


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    godot = os.environ.get("GODOT", DEFAULT_GODOT)
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    out = ROOT / "build" / "release" / version / NAME
    out.parent.mkdir(parents=True, exist_ok=True)
    run([godot, "--headless", "--path", str(ROOT / "game"), "--import"], 300)
    code, log = run([godot, "--headless", "--path", str(ROOT / "game"), "--export-release", PRESET, str(out)], 600)
    if code != 0 or not out.exists():
        print(log[-2000:])
        print(f"export failed, code {code}")
        return 1
    bad = smoke(out)
    if bad:
        print("\n".join(bad[:20]))
        print(f"the build does not start: {out}")
        return 1
    print(f"{out} — {out.stat().st_size / 1e6:.0f} MB, starts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
