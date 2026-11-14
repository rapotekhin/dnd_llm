"""The game's runnable build: Windows by default, Linux by --linux.

    python tools/build_game.py            # build/release/<version>/BetweenTheRolls.exe with server.exe beside it
    python tools/build_game.py --linux    # build/release/<version>/linux/BetweenTheRolls.x86_64 with `server` beside it
                                          # and build/release/<version>/BetweenTheRolls-<version>-linux-x86_64.tar.gz

Takes the version from the root VERSION. The player starts the game: it runs the server (frozen by PyInstaller, its
libraries in server_lib/) on 127.0.0.1 with the player's own OpenRouter key from the settings (ADR-0014); no key or
token goes into the build, and the build checks that. Needs Godot's export templates of the editor's version in
%APPDATA%/Godot/export_templates/<version>.stable (the Windows files of the official .tpz, and its linux_*.x86_64 for
--linux) and uv. Ends by starting the build: the server alone, the game alone with no key, the game with a stub server.
A build that does not start fails here.

PyInstaller freezes only for the system it runs on, so on Windows the Linux half — freezing the server and starting
the build — runs in WSL (`--wsl`, Ubuntu by default) by this same script (`--in-wsl freeze|smoke`), with uv there
(~/.local/bin/uv) and uv's own Python (built on an old glibc), its environment on the Linux disk. The build must not
ask a glibc newer than MAX_GLIBC: a Linux of the last few years starts it.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tool_base import ROOT, godot as godot_path  # noqa: E402

WINDOWS = sys.platform == "win32"
SERVER = "server.exe" if WINDOWS else "server"  # the server of the system this script runs on
SERVER_LIB = "server_lib"
PLATFORMS = {  # preset of game/export_presets.cfg, the game's file, the server's file, the folder under the version
    "windows": {"preset": "Windows", "name": "BetweenTheRolls.exe", "server": "server.exe", "dir": ""},
    "linux": {"preset": "Linux", "name": "BetweenTheRolls.x86_64", "server": "server", "dir": "linux"},
}
MAX_GLIBC = (2, 35)  # Ubuntu 22.04, Debian 12 and newer
LINUX_VENV = "~/.cache/btr/server-venv"  # the freeze's environment in WSL: never the Windows llm_server/.venv
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


def run(args: list[str], timeout: int, env: dict[str, str] | None = None) -> tuple[int, str]:
    proc = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout, env=env)
    return proc.returncode, proc.stdout + proc.stderr


def uv() -> list[str]:
    path = shutil.which("uv") or next((str(p) for p in [Path.home() / ".local" / "bin" / "uv"] if p.exists()), None)
    return [path] if path else [sys.executable, "-m", "uv"]


def freeze_server(out: Path) -> str:
    """The server of this system and server_lib/ into `out`; returns what went wrong, or ""."""
    work = ROOT / "build" / ("server" if WINDOWS else "server-linux")
    shutil.rmtree(work, ignore_errors=True)
    entry, prompts = ROOT / "llm_server" / "server_entry.py", ROOT / "llm_server" / "src" / "llm_server" / "prompts"
    env = None
    if not WINDOWS:  # uv's own Python, not the system's: its glibc is old, so the build runs on older Linuxes
        env = {**os.environ, "UV_PROJECT_ENVIRONMENT": os.path.expanduser(LINUX_VENV), "UV_PYTHON_PREFERENCE": "only-managed"}
    code, log = run([*uv(), "run", "--project", str(ROOT / "llm_server"), "--group", "freeze", "python", "-m", "PyInstaller",
                     *FREEZE_ARGS, "--paths", str(entry.parent / "src"), "--add-data", f"{ROOT / 'VERSION'}{os.pathsep}.",
                     "--add-data", f"{prompts}{os.pathsep}llm_server/prompts", "--distpath", str(work / "dist"),
                     "--workpath", str(work / "work"), "--specpath", str(work), str(entry)], 1800, env)
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
    found = [f"{path.name}: a .env file" for path in folder.rglob(".env*")]
    for path in folder.rglob("*"):
        if path.is_file():
            data = path.read_bytes()
            found.extend(f"{path.name}: {name}" for name, value in values.items() if value in data)
    return found


def glibc_needed(folder: Path) -> tuple[int, int]:
    """The newest glibc any ELF file of the build asks for (its version needs, GLIBC_2.x)."""
    best = (0, 0)
    for path in folder.rglob("*"):
        if path.is_file() and path.read_bytes()[:4] == b"\x7fELF":
            for major, minor in re.findall(rb"GLIBC_(\d+)\.(\d+)", path.read_bytes()):
                best = max(best, (int(major), int(minor)))
    return best


def server_processes(exe: Path) -> int:
    if WINDOWS:
        _, log = run(["tasklist", "/FI", f"IMAGENAME eq {exe.name}", "/NH", "/FO", "CSV"], 30)
        return sum(exe.name in line for line in log.splitlines())
    count = 0
    for proc in Path("/proc").iterdir():
        try:
            count += proc.name.isdigit() and os.path.realpath(proc / "exe") == os.path.realpath(exe)
        except OSError:
            pass
    return count


def stub_env(home: str) -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if k not in SECRETS and not k.startswith("LLM_SERVER_")}
    env.update({"APPDATA": home, "XDG_DATA_HOME": home, "XDG_CONFIG_HOME": home, "LLM_SERVER_TURN_HANDLER": "stub"})
    return env


def listen_addresses(pid: int) -> list[str]:
    if WINDOWS:
        _, log = run(["netstat", "-ano", "-p", "TCP"], 30)
        return [parts[1] for parts in map(str.split, log.splitlines())
                if len(parts) == 5 and parts[3] == "LISTENING" and parts[4] == str(pid)]
    inodes = {os.readlink(fd)[8:-1] for fd in Path(f"/proc/{pid}/fd").iterdir() if os.readlink(fd).startswith("socket:[")}
    found = []
    for table in ("tcp", "tcp6"):
        for line in Path(f"/proc/{pid}/net/{table}").read_text().splitlines()[1:]:
            parts = line.split()
            if parts[3] == "0A" and parts[9] in inodes:  # LISTEN
                addr, port = parts[1].split(":")
                ip = ".".join(str(int(addr[i:i + 2], 16)) for i in (6, 4, 2, 0)) if table == "tcp" else f"[{addr}]"
                found.append(f"{ip}:{int(port, 16)}")
    return found


def smoke_server(exe: Path, version: str) -> list[str]:
    """The server alone, on the stub: it tells a port, answers with this version and listens only on this machine."""
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


def smoke_game(exe: Path, server: Path) -> list[str]:
    """A clean user folder of its own each time: first no key (no server runs), then the stub server."""
    before = server_processes(server)
    with tempfile.TemporaryDirectory() as home:
        bad, _ = smoke(exe, {k: v for k, v in stub_env(home).items() if k != "LLM_SERVER_TURN_HANDLER"}, SMOKE_FRAMES)
    if server_processes(server) != before:
        bad.append("a server runs without a key")
    with tempfile.TemporaryDirectory() as home:
        more, log = smoke(exe, stub_env(home), SERVER_FRAMES)
        bad += more
        if "Backend: READY" not in log:
            bad.append("the game did not reach its server")
        deadline = time.monotonic() + 10
        while server_processes(server) != before and time.monotonic() < deadline:
            time.sleep(0.1)  # the folder of the server's log goes only after the server does
    if server_processes(server) != before:
        bad.append("the server outlived the game")
    return bad


def smoke_all(folder: Path, name: str, version: str) -> list[str]:
    return smoke_server(folder / SERVER, version) + smoke_game(folder / name, folder / SERVER)


def wsl_path(path: Path) -> str:
    drive, rest = path.resolve().drive, path.resolve().as_posix()[2:]
    return str(PurePosixPath("/mnt", drive[0].lower()) / rest.lstrip("/"))


def in_wsl(distro: str, *args: str, timeout: int) -> tuple[int, str]:
    """This script's own step inside WSL, its output told back; a login shell so ~/.local/bin is on PATH."""
    line = " ".join(["python3", wsl_path(Path(__file__)), "--in-wsl", *args])
    return run(["wsl", "-d", distro, "--", "bash", "-lc", line], timeout)


def pack_linux(folder: Path, name: str, archive: Path) -> None:
    """A tar.gz with the executable bits Windows files lack: BetweenTheRolls/ with the game and the server runnable."""
    runnable = {name, PLATFORMS["linux"]["server"]}
    with tarfile.open(archive, "w:gz") as tar:
        for path in sorted(folder.rglob("*")):
            info = tar.gettarinfo(str(path), str(PurePosixPath("BetweenTheRolls", path.relative_to(folder).as_posix())))
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            if info.isdir():
                info.mode = 0o755
                tar.addfile(info)
            else:
                info.mode = 0o755 if path.name in runnable or path.read_bytes()[:4] == b"\x7fELF" else 0o644
                with path.open("rb") as handle:
                    tar.addfile(info, handle)


def build(platform: str, distro: str) -> int:
    spec = PLATFORMS[platform]
    linux_here = platform == "linux" and WINDOWS
    godot = godot_path()
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    folder = ROOT / "build" / "release" / version / spec["dir"]
    out = folder / spec["name"]
    if platform == "linux":
        shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True, exist_ok=True)
    run([godot, "--headless", "--path", str(ROOT / "game"), "--import"], 300)
    code, log = run([godot, "--headless", "--path", str(ROOT / "game"), "--export-release", spec["preset"], str(out)], 600)
    if code != 0 or not out.exists():
        print(log[-2000:])
        print(f"export failed, code {code}")
        return 1
    if linux_here:
        code, problem = in_wsl(distro, "freeze", wsl_path(folder), timeout=2400)
        problem = problem if code != 0 else ""
    else:
        problem = freeze_server(folder)
    if problem:
        print(problem)
        return 1
    leaked = secrets_in(folder)
    if leaked:
        shutil.rmtree(folder, ignore_errors=True)
        print("\n".join(leaked))
        print("secrets in the build: it is deleted")
        return 1
    if platform == "linux":
        glibc = glibc_needed(folder)
        if glibc > MAX_GLIBC:
            print(f"the build asks glibc {glibc[0]}.{glibc[1]}, newer than {MAX_GLIBC[0]}.{MAX_GLIBC[1]}")
            return 1
    if linux_here:
        code, said = in_wsl(distro, "smoke", wsl_path(folder), spec["name"], version, timeout=600)
        bad = [said.strip()] if code != 0 else []
    else:
        bad = smoke_all(folder, spec["name"], version)
    if bad:
        print("\n".join(bad[:20]))
        print(f"the build does not start: {out}")
        return 1
    size = sum(path.stat().st_size for path in folder.rglob("*") if path.is_file())
    print(f"{out} — {size / 1e6:.0f} MB with the server, starts")
    if platform == "linux":
        archive = folder.parent / f"BetweenTheRolls-{version}-linux-x86_64.tar.gz"
        pack_linux(folder, spec["name"], archive)
        print(f"{archive} — {archive.stat().st_size / 1e6:.0f} MB, glibc {glibc[0]}.{glibc[1]} or newer")
    return 0


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--linux", action="store_true", help="the Linux build (its server frozen in WSL on Windows)")
    parser.add_argument("--wsl", default="Ubuntu", help="the WSL distribution of the Linux half")
    parser.add_argument("--in-wsl", nargs="+", metavar="STEP", help=argparse.SUPPRESS)  # freeze <dir> | smoke <dir> <name> <version>
    args = parser.parse_args()
    if args.in_wsl:
        step, folder = args.in_wsl[0], Path(args.in_wsl[1])
        if step == "freeze":
            problem = freeze_server(folder)
            print(problem)
            return 1 if problem else 0
        bad = smoke_all(folder, args.in_wsl[2], args.in_wsl[3])
        print("\n".join(bad[:20]))
        return 1 if bad else 0
    return build("linux" if args.linux else "windows", args.wsl)


if __name__ == "__main__":
    sys.exit(main())
