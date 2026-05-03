# AGENTS.md

Shared instructions for any AI coding agent working in this repository (Claude Code, Cursor, etc.). This is the canonical source — both `CLAUDE.md` (Claude Code) and `.cursor/rules/` (Cursor) reference it.

## Project

**Between the Rolls** — single-player D&D 5e RPG with an LLM Dungeon Master. Pygame UI, Python, Russian-first localization. Active code in `game/`. `app/` is legacy Streamlit (slated for deletion).

## Documentation

Full docs in [`docs/`](docs/). Use the **`docs_lookup`** skill/rule to navigate it before answering conceptual questions. Use **`docs_updater`** after meaningful code changes; **`release_notes_updater`** for player-facing changes.

## Commands

```bash
python game/main.py                  # run the game
```

`game/main.py` adds `game/`, `../dnd-5e-core/`, `../DnD-5th-Edition-API/` to `sys.path`. Inside `game/`, imports are relative: `from core.game import Game`.

There are no tests yet. There is no linter wired up.

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
    llm_engine/api_manager.py      OpenRouter client, default model hardcoded here
    prompts/                       system prompts for each mode
    tools/                         LLM tools (RollDiceTool, RuleDbLookupTool)
    builders/                      Character/Location/NPC/LevelUp builders
    settings/                      SettingsManager
  ui/screens/                      12 screens, all extend BaseScreen
  assets/ru/*.jsonl                start locations and NPCs
  localization/                    loc.t("key") for translated strings
```

## Conventions

- Screens extend `BaseScreen` and implement `handle_event() / update() / draw()`. Navigation is via return values handled in `Game._handle_screen_result()` — never wire screens directly to each other.
- Access global state with `from core.data import game_state`.
- LLM output is always Pydantic-typed (schemas in `game/core/gameplay/schemas/`). Don't parse free text.
- Game text, prompts, lore — Russian. Code identifiers — English.
- For new LLM agents use **Pydantic AI** (`pydantic_ai.Agent`). LangChain in `APIManager.generate_with_format` is legacy — don't extend it.

## Where to add things

| Task | Location |
|---|---|
| New screen | `game/ui/screens/` + register in `Game._init_screens()` |
| New gameplay mode | `game/core/gameplay/<mode>.py` + new screen + new prompts |
| New LLM tool | `game/core/tools/` + register via `@agent.tool_plain` in the right `_build_*_agent()` |
| New entity class | `game/core/entities/` (+ builder in `core/builders/` if complex) |
| D&D rules content (races, classes, spells) | NOT here — in the external `dnd-5e-core` repo |
