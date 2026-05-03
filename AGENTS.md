# AGENTS.md

Shared instructions for any AI coding agent working in this repository (Claude Code, Cursor, etc.). This is the canonical source — both `CLAUDE.md` (Claude Code) and `.cursor/rules/` (Cursor) reference it.

## Project

**Between the Rolls** — single-player D&D 5e RPG with an LLM Dungeon Master. Pygame UI, Python, Russian-first localization. Active code in `game/`.

## Documentation

Full docs in [`docs/`](docs/). Use the **`docs_lookup`** skill/rule to navigate it before answering conceptual questions. Use **`docs_updater`** after meaningful code changes; **`release_notes_updater`** for player-facing changes.

## Commands

```bash
python game/main.py                  # run the game
pip install -r requirements-dev.txt # pytest + deps for exploration import tests
python -m pytest                     # run tests (needs game/dnd_5e_data JSON on disk)
```

`game/main.py` adds `game/`, `../dnd-5e-core/`, `../DnD-5th-Edition-API/` to `sys.path`. Inside `game/`, imports are relative: `from core.game import Game`.

Pytest configuration: `pytest.ini`, tests under `tests/` (see `requirements-dev.txt`). There is no linter wired up.

## Structure

```
game/
  main.py                          entry point
  core/
    game.py                        main loop, screen dispatch
    data/                          MainGameState (singleton, pickle saves)
    entities/                      Character, NPC, Location, Room, Item, Treasure
    gameplay/                      exploration, social_interaction, trade, combat (empty)
    gameplay/schemas/              Pydantic output schemas for LLM
    llm_engine/api_manager.py      OpenRouter key/balance, Pydantic AI model factory
    prompts/                       system prompts for each mode
    tools/                         LLM tools (RollDiceTool, RuleDbLookupTool)
    builders/                      Character/Location/NPC/LevelUp builders
    settings/                      SettingsManager
  ui/screens/                      12 screens, all extend BaseScreen
  assets/ru/*.jsonl                start locations and NPCs
  localization/                    loc.t("key") for translated strings
tests/
  conftest.py                      pytest path setup + patched_game_state fixture
  helpers.py                       GameEquipment factory for trade/inventory tests
```

## Conventions

- Screens extend `BaseScreen` and implement `handle_event() / update() / draw()`. Navigation is via return values handled in `Game._handle_screen_result()` — never wire screens directly to each other.
- Access global state with `from core.data import game_state`.
- LLM output is always Pydantic-typed (schemas in `game/core/gameplay/schemas/`). Don't parse free text.
- Game text, prompts, lore — Russian. Code identifiers — English.
- For new LLM agents use **Pydantic AI** (`pydantic_ai.Agent`). OpenRouter и модель настраиваются через `APIManager.get_pydantic_ai_model()`.

## Where to add things

| Task | Location |
|---|---|
| New screen | `game/ui/screens/` + register in `Game._init_screens()` |
| New gameplay mode | `game/core/gameplay/<mode>.py` + new screen + new prompts |
| New LLM tool | `game/core/tools/` + register via `@agent.tool_plain` in the right `_build_*_agent()` |
| New entity class | `game/core/entities/` (+ builder in `core/builders/` if complex) |
| D&D rules content (races, classes, spells) | NOT here — in the external `dnd-5e-core` repo |
