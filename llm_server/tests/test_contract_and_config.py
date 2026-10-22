import pytest

from llm_server import contract
from llm_server.config import ConfigError, Settings

from conftest import TOKEN


def test_contract_schemas_match_models():
    expected = contract.render()
    on_disk = {p.name: p.read_text(encoding="utf-8") for p in contract.SCHEMA_DIR.glob("*.json")}
    assert on_disk == expected, "contract/ is stale: run `uv run python -m llm_server.contract`"


def test_settings_repr_hides_token():
    assert TOKEN not in repr(Settings(token=TOKEN))


def test_settings_require_token(monkeypatch):
    monkeypatch.delenv("LLM_SERVER_TOKEN", raising=False)
    with pytest.raises(ConfigError):
        Settings.from_env(load_env_file=False)
    monkeypatch.setenv("LLM_SERVER_TOKEN", "short")
    with pytest.raises(ConfigError):
        Settings.from_env(load_env_file=False)


def test_godot_client_speaks_the_same_protocol_version():
    import re

    from llm_server import REPO_ROOT
    from llm_server.protocol import PROTOCOL_VERSION

    source = (REPO_ROOT / "game" / "core" / "net" / "backend_client.gd").read_text(encoding="utf-8")
    match = re.search(r'const PROTOCOL_VERSION := "([^"]+)"', source)
    assert match and match.group(1) == PROTOCOL_VERSION


def test_every_engine_method_the_tools_call_is_allowed():
    # v0.7.21.3: engine.find_quests was called by the master but not allowed — every quest turn failed
    import re

    from llm_server import REPO_ROOT
    from llm_server.session import ENGINE_METHODS

    called = set(re.findall(r'call_engine\("(engine\.[a-z_]+)"', (REPO_ROOT / "llm_server" / "src" / "llm_server" / "agents.py").read_text(encoding="utf-8")))
    assert called and called <= ENGINE_METHODS, called - ENGINE_METHODS
