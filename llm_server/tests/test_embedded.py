"""The server a game starts by itself (ADR-0014): the port file, loopback only, the end with its parent."""

import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import pytest

from llm_server.config import Settings

TOKEN = "t" * 32
START_TIMEOUT_S = 60.0
PARENT = """
import os, subprocess, sys, time
env = {**os.environ, "LLM_SERVER_PARENT_PID": str(os.getpid())}
child = subprocess.Popen([sys.executable, "-m", "llm_server"], env=env, stdin=subprocess.DEVNULL)
print(child.pid, flush=True)
sys.stdin.readline()
os._exit(0)
"""


def _env(tmp_path: Path) -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if not k.startswith("LLM_SERVER_") and k != "OPENROUTER_API_KEY"}
    env.update({"LLM_SERVER_TOKEN": TOKEN, "LLM_SERVER_TURN_HANDLER": "stub", "LLM_SERVER_PORT_FILE": str(tmp_path / "port"),
                "LLM_SERVER_LOG_FILE": str(tmp_path / "server.log"), "LLM_SERVER_DATA_DIR": str(tmp_path / "data")})
    return env


def _wait_for_port(tmp_path: Path, parent: subprocess.Popen) -> int:
    deadline = time.monotonic() + START_TIMEOUT_S
    while time.monotonic() < deadline:
        if (tmp_path / "port").exists():
            return int((tmp_path / "port").read_text(encoding="ascii"))
        assert parent.poll() is None
        time.sleep(0.05)
    raise AssertionError((tmp_path / "server.log").read_text(encoding="utf-8"))


def _alive(pid: int) -> bool:
    if sys.platform != "win32":
        return Path(f"/proc/{pid}").exists()
    out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True).stdout
    return str(pid) in out


def test_embedded_settings_stay_on_this_machine(monkeypatch, tmp_path):
    monkeypatch.setenv("LLM_SERVER_TOKEN", TOKEN)
    monkeypatch.setenv("LLM_SERVER_TURN_HANDLER", "stub")
    monkeypatch.setenv("LLM_SERVER_HOST", "0.0.0.0")
    monkeypatch.setenv("LLM_SERVER_PORT_FILE", str(tmp_path / "port"))
    settings = Settings.from_env(load_env_file=False)
    assert settings.embedded
    assert settings.host == "127.0.0.1"


def test_server_tells_its_port_and_ends_with_its_parent(tmp_path):
    """Killed by nobody: the parent just leaves, as a crashed game does."""
    parent = subprocess.Popen([sys.executable, "-c", PARENT], env=_env(tmp_path), stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, text=True)
    pid = int(parent.stdout.readline())
    port = _wait_for_port(tmp_path, parent)
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=5) as resp:
        assert json.load(resp)["status"] == "ok"
    assert TOKEN not in (tmp_path / "server.log").read_text(encoding="utf-8")
    parent.stdin.write("\n")
    parent.stdin.flush()
    parent.wait(timeout=10)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and _alive(pid):
        time.sleep(0.1)
    assert not _alive(pid)


def test_rejected_key_is_an_exit_code_of_its_own(monkeypatch):
    from llm_server import __main__ as entry
    from llm_server.llm import catalog

    async def rejected(_key: str) -> float:
        raise catalog.KeyRejected

    monkeypatch.setattr(catalog, "check_openrouter_key", rejected)
    with pytest.raises(SystemExit) as exc:
        entry._check_key(Settings(token=TOKEN, port_file=Path("port")))
    assert exc.value.code == entry.EXIT_KEY_REJECTED


def test_no_answer_from_openrouter_does_not_stop_an_embedded_server(monkeypatch):
    from llm_server import __main__ as entry
    from llm_server.llm import catalog

    async def silent(_key: str) -> None:
        return None

    monkeypatch.setattr(catalog, "check_openrouter_key", silent)
    entry._check_key(Settings(token=TOKEN, port_file=Path("port")))
    with pytest.raises(SystemExit):
        entry._check_key(Settings(token=TOKEN))
