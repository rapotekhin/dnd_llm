"""The game's runnable Windows build: build/release/<version>/BetweenTheRolls.exe with the master's server beside it.

    python tools/build_game.py

Takes the version from the root VERSION. The player starts BetweenTheRolls.exe: it runs server.exe (frozen by
PyInstaller, its libraries in server_lib/) on 127.0.0.1 with the player's own OpenRouter key from the settings
(ADR-0014); no key or token goes into the build, and the build checks that. Needs Godot's export templates of the
editor's version in %APPDATA%/Godot/export_templates/<version>.stable (the Windows files of the official .tpz) and uv.
Ends by starting the build: the server alone, the game alone with no key, the game with a stub server. A build that
does not start fails here.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tool_base import ROOT, godot as godot_path  # noqa: E402

PRESET = "Windows"
NAME = "BetweenTheRolls.exe"
SERVER = "server.exe"
SERVER_LIB = "server_lib"
SMOKE_FRAMES = 300
SERVER_FRAMES = 1500  # headless runs them in a few seconds: enough for the server to come up and the client to connect
START_TIMEOUT_S = 60.0
BAD = ("SCRIPT ERROR", "Parse Error", "Failed to load", "Cannot open file")
SECRETS = ("OPENROUTER_API_KEY", "LLM_SERVER_TOKEN")
# One folder, not one file: a one-file build is two processes, and killing the first leaves the second alive.
FREEZE_ARGS = ["--noconfirm", "--onedir", "--log-level", "WARN", "--name", "server", "--contents-directory", SERVER_LIB,
               "--collect-submodules", "uvicorn", "--collect-data", "genai_prices", "--copy-metadata", "genai_prices",
               "--copy-metadata", "pydantic_ai_slim", "--copy-metadata", "opentelemetry-api", "--exclude-module", "tkinter",
               "--exclude-module", "pytest", "--exclude-module", "IPython", "--exclude-module", "setuptools"]


def run(args: list[str], timeout: int) -> tuple[int, str]:
    proc = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    return proc.returncode, proc.stdout + proc.stderr


def uv() -> list[str]:
    path = shutil.which("uv")
    return [path] if path else [sys.executable, "-m", "uv"]


def freeze_server(out: Path) -> str:
    """server.exe and server_lib/ into `out`; returns what went wrong, or ""."""
    work = ROOT / "build" / "server"
    shutil.rmtree(work, ignore_errors=True)
    entry, prompts = ROOT / "llm_server" / "server_entry.py", ROOT / "llm_server" / "src" / "llm_server" / "prompts"
    code, log = run([*uv(), "run", "--project", str(ROOT / "llm_server"), "--group", "freeze", "python", "-m", "PyInstaller",
                     *FREEZE_ARGS, "--paths", str(entry.parent / "src"), "--add-data", f"{ROOT / 'VERSION'};.",
                     "--add-data", f"{prompts};llm_server/prompts", "--distpath", str(work / "dist"),
                     "--workpath", str(work / "work"), "--specpath", str(work), str(entry)], 900)
    built = work / "dist" / "server"
    if code != 0 or not (built / SERVER).exists():
        return f"{log[-2000:]}\nfreezing failed, code {code}"
    shutil.rmtree(out / SERVER_LIB, ignore_errors=True)
    shutil.copytree(built / SERVER_LIB, out / SERVER_LIB)
    shutil.copy2(built / SERVER, out / SERVER)
    return ""


def secrets_in(folder: Path) -> list[str]:
    """Which files of the build hold a secret of the root .env, by the secret's name: the value is never printed."""
    values = {name: os.environ[name].encode() for name in SECRETS if os.environ.get(name)}
    env_file = ROOT / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            name, _, value = line.partition("=")
            if name.strip() in SECRETS and value.strip():
                values[name.strip()] = value.strip().strip("\"'").encode()
    found =[f"{path.name}: a .env file" for path in folder.rglob(".env*")]
    for path in folder.rglob("*"):
        if path.is_file():
            data = path.read_bytes()
            found.extend(f"{path.name}: {name}" for name, value in values.items() if value in data)
    return found


def server_processes() -> int:
    _, log = run(["tasklist", "/FI", f"IMAGENAME eq {SERVER}", "/NH", "/FO", "CSV"], 30)
    return sum(SERVER in line for line in log.splitlines())


def stub_env(home: str) -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if k not in SECRETS and not k.startswith("LLM_SERVER_")}
    env.update({"APPDATA": home, "LLM_SERVER_TURN_HANDLER": "stub"})
    return env


def listen_addresses(pid: int) -> list[str]:
    _, log = run(["netstat", "-ano", "-p", "TCP"], 30)
    return [parts[1] for parts in map(str.split, log.splitlines()) if len(parts) == 5 and parts[3] == "LISTENING" and parts[4] == str(pid)]


def smoke_server(exe: Path, version: str) -> list[str]:
    """server.exe alone, on the stub: it tells a port, answers with this version and listens only on this machine."""
    with tempfile.TemporaryDirectory() as home:
        port_file = Path(home) / "port"
        env = {**stub_env(home), "LLM_SERVER_TOKEN": "t" * 32, "LLM_SERVER_PORT_FILE": str(port_file),
               "LLM_SERVER_LOG_FILE": str(Path(home) / "server.log"), "LLM_SERVER_DATA_DIR": str(Path(home) / "master")}
        proc = subprocess.Popen([str(exe)], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + START_TIMEOUT_S
            while not port_file.exists():
                if proc.poll() is not None or time.monotonic() > deadline:
                    return [f"the server did not start, exit {proc.poll()}"]
                time.sleep(0.05)
            port = int(port_file.read_text(encoding="ascii"))
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=5) as resp:
                health = json.load(resp)
            bad = [] if health.get("version") == version else [f"the server says version {health.get('version')}"]
            listening = listen_addresses(proc.pid)
            if not listening or any(not a.startswith("127.0.0.1:") for a in listening):
                bad.append(f"the server listens on {listening}")
            return bad
        finally:
            proc.kill()
            proc.wait()


def smoke(exe: Path, env: dict[str, str], frames: int) -> tuple[list[str], str]:
    """Starts the build without a window; returns the lines that went wrong and the whole log."""
    proc = subprocess.run([str(exe), "--headless", "--quit-after", str(frames)], env=env, capture_output=True,
                          text=True, encoding="utf-8", errors="replace", timeout=120)
    log = proc.stdout + proc.stderr
    bad = [line for line in log.splitlines() if any(word in line for word in BAD)]
    if proc.returncode != 0:
        bad.append(f"exit code {proc.returncode}")
    return bad, log


def smoke_game(exe: Path) -> list[str]:
    """A clean user folder of its own each time: first no key (no server runs), then the stub server."""
    before = server_processes()
    with tempfile.TemporaryDirectory() as home:
        bad, _ = smoke(exe, {k: v for k, v in stub_env(home).items() if k != "LLM_SERVER_TURN_HANDLER"}, SMOKE_FRAMES)
    if server_processes() != before:
        bad.append("a server runs without a key")
    with tempfile.TemporaryDirectory() as home:
        more, log = smoke(exe, stub_env(home), SERVER_FRAMES)
        bad += more
        if "Backend: READY" not in log:
            bad.append("the game did not reach its server")
        deadline = time.monotonic() + 10
        while server_processes() != before and time.monotonic() < deadline:
            time.sleep(0.1)  # the folder of the server's log goes only after the server does
    if server_processes() != before:
        bad.append("the server outlived the game")
    return bad


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    godot = godot_path()
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    out = ROOT / "build" / "release" / version / NAME
    out.parent.mkdir(parents=True, exist_ok=True)
    run([godot, "--headless", "--path", str(ROOT / "game"), "--import"], 300)
    code, log = run([godot, "--headless", "--path", str(ROOT / "game"), "--export-release", PRESET, str(out)], 600)
    if code != 0 or not out.exists():
        print(log[-2000:])
        print(f"export failed, code {code}")
        return 1
    problem = freeze_server(out.parent)
    if problem:
        print(problem)
        return 1
    leaked = secrets_in(out.parent)
    if leaked:
        shutil.rmtree(out.parent, ignore_errors=True)
        print("\n".join(leaked))
        print("secrets in the build: it is deleted")
        return 1
    bad = smoke_server(out.parent / SERVER, version) + smoke_game(out)
    if bad:
        print("\n".join(bad[:20]))
        print(f"the build does not start: {out}")
        return 1
    size = sum(path.stat().st_size for path in out.parent.rglob("*") if path.is_file())
    print(f"{out} — {size / 1e6:.0f} MB with the server, starts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
