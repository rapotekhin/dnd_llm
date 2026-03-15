# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Between the Rolls** — a D&D 5e RPG with an LLM-powered dungeon master, built on Pygame. The `app/` directory is a legacy Streamlit prototype; all active development happens in `game/`.

## Setup & Running

```bash
# Install Python dependencies
pip install -r requirements.txt

# Install external D&D rules packages (cloned as siblings of this repo)
git clone https://github.com/rapotekhin/dnd-5e-core
git clone https://github.com/rapotekhin/DnD-5th-Edition-API
cd dnd-5e-core && pip install -e .
cd ../DnD-5th-Edition-API && ./install.bat

# Create .env from template and add API keys
cp .env.example .env

# Run the game
python game/main.py
```

`game/main.py` adds `game/`, `dnd-5e-core/`, and `DnD-5th-Edition-API/` to `sys.path` at startup. Imports inside `game/` use paths relative to `game/` (e.g. `from core.game import Game`).

## Environment Variables

Required only for providers you use:

| Variable | Purpose |
|---|---|
| `OPENROUTER_API_KEY` | Primary LLM provider (free models available) |
| `OPENAI_API_KEY` | OpenAI GPT models |
| `GROK_API_KEY` | X.AI Grok models |
| `LMSTUDIO_API_BASE` | Local LM Studio (default: `http://localhost:1234/api/v0`) |
| `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY` | Optional LLM observability via Logfire |

## Architecture

### Game Loop & Screen Management (`game/core/game.py`)

`Game` initializes Pygame, `APIManager`, and `MainGameState`, then runs a 60-FPS event loop. Each frame: `handle_event()` → `update()` → `draw()` on the current screen. Screens return string commands or a `Character` object to `_handle_screen_result()`, which switches screens:

- Returning a string like `"inventory"`, `"map"`, `"character"` → `switch_screen()`
- Returning `"social:<npc_id>"` or `"trade:<npc_id>"` → configures the target screen then switches
- Returning a `Character` instance → stores in game state, navigates to `"main"`
- `"level_up"` → `LevelUpScreen` is created on demand (needs a live player)

### Global Game State (`game/core/data/`)

`MainGameState` is a singleton created in `Game.__init__` and exposed as `game_data.game_state`. All screens import it directly:

```python
from core.data import game_state
```

It holds: `player` (Character), `npcs` dict, `locations` dict, `quests` list, `treasures` dict, and current location/room info. `load_start_data()` populates NPCs and locations from JSONL assets.

Save/load uses pickle: `save_{1-10}.pkl` in `~/AppData/Local/DnD_LLM_Game/saves/` (Windows) or `~/.local/share/DnD_LLM_Game/saves/` (Linux).

### LLM Integration (`game/core/llm_engine/`)

`APIManager` wraps OpenRouter (default: Gemini 2.5 Flash Lite) via LangChain. Key method: `generate_with_format(prompt, output_schema)` returns a structured Pydantic model.

Gameplay modules use **Pydantic AI agents** with tools:
- `RollDiceTool` — rolls D&D dice (d4/d6/d8/d10/d12/d20/d100)
- `RuleDbLookupTool` — queries D&D 5e rules from the external package

Exploration data flow:
```
MainScreen → exploration.py (Pydantic AI agent) → APIManager → OpenRouter API
  → Tools (RollDiceTool, RuleDbLookupTool) → SceneDescription (Pydantic output) → MainScreen
```

### Gameplay Modules (`game/core/gameplay/`)

| Module | Responsibility |
|---|---|
| `exploration.py` | Pydantic AI agent for scene narration, dice rolls, rule lookups |
| `combat.py` | D&D 5e combat mechanics |
| `social.py` | NPC dialogue generation |
| `trade.py` | Item exchange with NPCs |

### UI Screens (`game/ui/screens/`)

13 screens, all receiving `pygame.Surface` in their constructor. Navigation is purely via return values from `handle_event()`. The largest screens (`character_creation_screen.py` ~112KB, `level_up_screen.py` ~58KB) handle complex D&D character building logic inline.

### Settings (`game/core/settings/`)

`SettingsManager` loads/saves a `GameSettings` dataclass to `settings.json` in the repo root. Defaults: 1280×720 windowed, Russian language. Changing resolution/fullscreen triggers `pygame.display.quit()` + reinit workaround.

### Localization (`game/localization/`)

Russian is the primary language. `loc.set_language()` is called at startup with the saved language setting. Use `loc.t("key")` for translated strings throughout the UI.

### D&D Data (`game/dnd_5e_data/`, external `dnd-5e-core`)

Static D&D 5e rules (races, classes, spells, feats, items) live in `dnd-5e-core` (external package). Start locations and NPCs are in `game/assets/ru/*.jsonl`.

## Key Conventions

- All screens inherit from a base class and implement `handle_event()`, `update()`, `draw()`
- Gameplay logic is kept separate from UI screens — screens call into `game/core/gameplay/` modules
- `from core.data import game_state` is the standard way to access shared state
- Pydantic models are used for all LLM-structured outputs and entity definitions
- Code comments and console output are in Russian
