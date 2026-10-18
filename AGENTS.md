# AGENTS.md

Shared instructions for any AI coding agent working in this repository (Claude Code, Cursor, etc.). This is the canonical source — both `CLAUDE.md` (Claude Code) and `.cursor/rules/` (Cursor) reference it.

## Project

**Between the Rolls** — single-player D&D 5e RPG with an LLM Dungeon Master, Russian-first. The project is **migrating** from a Pygame prototype to a Godot client + Python LLM backend ([ADR-0007](docs/tech/adr/0007-godot-client-python-llm-backend.md), roadmap M1 in [docs/production/roadmap.md](docs/production/roadmap.md)).

| Folder | What | Status |
|---|---|---|
| `legacy/` | Pygame prototype (v0.3.x): game, tests, scripts | frozen — only bug fixes until parity, then removed |
| `game/` | Godot 4.7 client (GDScript) | skeleton — v0.4.0 |
| `llm_server/` | Python LLM backend (FastAPI, Pydantic AI, OpenRouter) | skeleton — v0.4.1 |
| `contract/` | JSON Schema of the Godot ↔ backend protocol | skeleton — v0.4.1 |
| `evals/` | golden LLM scenarios ([docs](docs/tech/golden-scenarios.md)) | scenarios ready, runner in v0.4.2 |
| `docs/` | design + tech docs, ADRs | live |

Decisions to follow in new code: [ADR-0007](docs/tech/adr/0007-godot-client-python-llm-backend.md) (who owns what), [ADR-0008](docs/tech/adr/0008-engine-decides-llm-narrates.md) (engine decides, LLM narrates), [ADR-0009](docs/tech/adr/0009-godot-backend-protocol.md) (protocol), [ADR-0010](docs/tech/adr/0010-game-decisions-worlds-tone-combat-death.md) (game decisions). Godot conventions follow the sibling project `C:\Code\hive_world_shop` (pure `core/`, seeded RNG, JSON saves with migrations, gdUnit4).

## Documentation

Full docs in [`docs/`](docs/). Use the **`docs_lookup`** skill/rule to navigate it before answering conceptual questions. Use **`docs_updater`** after meaningful code changes; **`release_notes_updater`** for player-facing changes.

## Commands

Always activate `venv` as the Python interpreter before running any command.

```bash
source .\venv\Scripts\activate
```

```bash
python legacy/game/main.py                     # run the pygame prototype
pip install -r legacy/requirements-dev.txt     # pytest + deps for the legacy tests and evals format check
python -m pytest                               # legacy tests + evals format (needs legacy/game/dnd_5e_data on disk)
python -m pytest --cov=legacy/game/core --cov-report=term-missing  # optional coverage (requires pytest-cov)
```

`legacy/game/main.py` adds `legacy/game/`, `dnd-5e-core/` and `DnD-5th-Edition-API/` (repository root) to `sys.path`. Inside `legacy/game/`, imports are relative: `from core.game import Game`. `.env` stays at the repository root.

Pytest configuration: `pytest.ini` (`testpaths = legacy/tests evals`). There is no linter wired up.

**Version:** the project version lives in the root `VERSION` file. CI requires every PR to bump it and to update `RELEASE_NOTES.md`.

## Legacy structure (pygame)

```
legacy/
  game/
    main.py                          entry point
    core/
      game.py                        main loop, screen dispatch
      data/                          MainGameState (pickle saves)
      entities/                      Character, NPC, Location, Room, Item, Treasure
      gameplay/                      exploration, social_interaction, trade, combat (empty)
      gameplay/schemas/              Pydantic output schemas for LLM
      llm_engine/api_manager.py      OpenRouter key/balance, Pydantic AI model factory
      prompts/                       system prompts for each mode
      tools/                         LLM tools (RollDiceTool)
      builders/                      Character/Location/NPC/LevelUp builders
      settings/                      SettingsManager
    ui/screens/                      12 screens, all extend BaseScreen
    assets/ru/*.jsonl                start locations and NPCs
    dnd_5e_data/                     SRD JSON (source for the future Godot catalog)
    localization/                    loc.t("key") for translated strings
  tests/
    conftest.py                      pytest path setup + patched_game_state fixture
    helpers.py                       GameEquipment factory for trade/inventory tests
    _fakes.py                        FakeAgent / queue helpers for threaded loop tests
    test_regressions_v031.py         regressions for bugs B1–B19 (spec for the Godot port)
  scripts/                           localization check, SRD data update, Langfuse test
  notebooks/                         scratch notebooks
```

## Legacy conventions

- Screens extend `BaseScreen` and implement `handle_event() / update() / draw()`. Navigation is via return values handled in `Game._handle_screen_result()` — never wire screens directly to each other.
- Access global state as `core.data.game_state` (module attribute: it is replaced on new game and load, so do not bind it with `from core.data import game_state` at import time).
- LLM output is always Pydantic-typed (schemas in `legacy/game/core/gameplay/schemas/`). Don't parse free text.
- Game text, prompts, lore — Russian. Code identifiers — English.
- For new LLM agents use **Pydantic AI** (`pydantic_ai.Agent`) via `APIManager.get_pydantic_ai_model()`.

## Where to add things

| Task | Location |
|---|---|
| New feature | not in `legacy/` — in the Godot client or the backend per the roadmap |
| Bug fix in the prototype | `legacy/game/` + regression test in `legacy/tests/` |
| Protocol message / schema | Pydantic model in `llm_server/` → export to `contract/` (from v0.4.1) |
| Golden LLM scenario | `evals/golden/scenarios.yaml` + [format doc](docs/tech/golden-scenarios.md) |
| Architectural decision | new ADR in `docs/tech/adr/` |
| D&D rules content (races, classes, spells) | SRD JSON data; never hard-coded |
