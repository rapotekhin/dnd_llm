"""Export protocol models to contract/schema/*.json: `uv run python -m llm_server.contract`.

The files are generated, never edited by hand; a test fails when they drift from the models.
"""

import json
from pathlib import Path

from . import REPO_ROOT
from .protocol import CONTRACT_MODELS, PROTOCOL_VERSION

SCHEMA_DIR = REPO_ROOT / "contract" / "schema"


def render() -> dict[str, str]:
    files = {"protocol_version.json": _dump({"protocol_version": PROTOCOL_VERSION})}
    for name, model in CONTRACT_MODELS.items():
        files[f"{name}.json"] = _dump(model.model_json_schema())
    return files


def write(target: Path = SCHEMA_DIR) -> list[Path]:
    target.mkdir(parents=True, exist_ok=True)
    for stale in target.glob("*.json"):
        stale.unlink()
    written = []
    for name, text in render().items():
        path = target / name
        path.write_text(text, encoding="utf-8", newline="\n")
        written.append(path)
    return written


def _dump(data: object) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


if __name__ == "__main__":
    for path in write():
        print(path.relative_to(REPO_ROOT).as_posix())
