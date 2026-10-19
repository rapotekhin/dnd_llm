# AGENTS.md

Shared instructions for any AI coding agent working in this repository (Claude Code, Cursor, etc.). This is the canonical source — both `CLAUDE.md` (Claude Code) and `.cursor/rules/` (Cursor) reference it.

## Project

**Between the Rolls** — single-player D&D 5e RPG with an LLM Dungeon Master, Russian-first: a Godot client + a Python LLM backend ([ADR-0007](docs/tech/adr/0007-godot-client-python-llm-backend.md), [roadmap](docs/production/roadmap.md)). The pygame prototype reached parity and was removed in v0.5.4 ([parity checklist](docs/production/parity-v031.md); it stays in git history up to v0.5.3).

| Folder | What | Status |
|---|---|---|
| `game/` | Godot 4.7 client (GDScript), [godot-client.md](docs/tech/godot-client.md) | real master (v0.4.1), 5e character (v0.5.0), world packs + start world «Сумеречная Марка» (v0.5.1), exploration: check locks, hidden things, long rest, map and journal (v0.5.2), dialogues and trade (v0.5.3), experience from quests and combat, level-up 1–5 (v0.5.4), 5e rules to the end: casting with slots, conditions, feature uses, short rest, consumables, 0 HP without death (v0.6.0), combat: SRD monsters, 7-column field, engine AI, death saves, combat screen (v0.6.1), combat details: surprise and sneaking, Hide, reinforcements, parley, hit hint, encounters in every Mark dungeon (v0.6.2), adventure systems: time of day, quests with steps, traps and caches, SRD magic items (v0.6.3), the captain's chain «Пепел над Маркой» with the finale and the menhir choice (v0.6.4), playtest-1 fixes: quest things, paid options, theft, waiting, condition spells, incapacitated foes, sneaking among people (v0.6.5), usability: rules texts under the lists, journal tabs, rich selectable chat, look / search buttons, inspecting foes (v0.6.6) |
| `llm_server/` | Python LLM backend (FastAPI, Pydantic AI, OpenRouter), own `uv` env, [README](llm_server/README.md) | agents over OpenRouter, protocol 0.10.0 (v0.6.5) |
| `contract/` | JSON Schema of the Godot ↔ backend protocol (generated) | all methods of protocol 0.10.0 |
| `tools/` | SRD import (`srd_import.py`, source in `tools/srd/source/`), pack validator, playtest and connectivity runners | |
| `infra/dev/` | Caddy in Docker for local `wss://` | dev only |
| `evals/` | golden LLM scenarios ([docs](docs/tech/golden-scenarios.md)) | 40 scenarios (39 runnable); runner `llm_server.golden` |
| `docs/` | design + tech docs, ADRs | live |

Decisions to follow in new code: [ADR-0007](docs/tech/adr/0007-godot-client-python-llm-backend.md) (who owns what), [ADR-0008](docs/tech/adr/0008-engine-decides-llm-narrates.md) (engine decides, LLM narrates), [ADR-0009](docs/tech/adr/0009-godot-backend-protocol.md) (protocol), [ADR-0010](docs/tech/adr/0010-game-decisions-worlds-tone-combat-death.md) (game decisions), [ADR-0011](docs/tech/adr/0011-default-master-model.md) (default model: change it only after golden scenarios with `--repeat 3` and a live playtest). Godot conventions follow the sibling project `C:\Code\hive_world_shop` (pure `core/`, seeded RNG, JSON saves with migrations, gdUnit4).

## Documentation

Full docs in [`docs/`](docs/). Use the **`docs_lookup`** skill/rule to navigate it before answering conceptual questions. Use **`docs_updater`** after meaningful code changes; **`release_notes_updater`** for player-facing changes; **`playtest`** to test the game live (see «Testing»); **`godot_conventions`** when writing GDScript in `game/`.

## Commands

Always activate `venv` as the Python interpreter before running any command.

```bash
source .\venv\Scripts\activate
```

```bash
pip install -r requirements-dev.txt           # pytest, pyyaml, jsonschema and uv for the root tests and the tools
python -m pytest                               # golden scenario format check (evals/)
```

Backend and Godot (details in [connectivity-spike.md](docs/tech/connectivity-spike.md)):

```bash
uv sync --project llm_server && cd llm_server && uv run pytest && cd ..   # backend protocol + contract tests (own .venv; run from llm_server/)
uv run --project llm_server python -m llm_server.contract            # regenerate contract/schema/ after changing protocol models
uv run --project llm_server python -m llm_server.golden              # golden LLM scenarios on the real model + judge → build/evals/ (cents; --model, --only, --repeat)
python tools/connectivity_e2e.py                                      # Godot <-> Caddy wss:// <-> llm_server end to end (Docker; --no-proxy without it)
python tools/godot_playtest.py                                        # live Godot playtest (smoke) against llm_server, screenshots in build/playtest/ (takes the next free port when 8765 is busy)
python tools/godot_playtest.py --scenario offline                     # live Godot playtest without the server
python tools/godot_playtest.py --scenario live --real                 # live Godot playtest with the real OpenRouter model (cents)
python tools/godot_playtest.py --scenario creation --no-server        # character creation step by step, screenshots of every step
python tools/godot_playtest.py --scenario level_up                    # a wizard levels 1 → 3 by clicks
python tools/godot_playtest.py --scenario combat                      # the wolves on the woodcutters' trail, fought by the buttons (--real; GODOT_COMBAT_HP=1 to see death; GODOT_COMBAT_ROAD=1 — sneak, hit hint, parley on the outpost road)
python tools/godot_playtest.py --scenario adventure                   # Drogin's quest, the deadfall trap, the cache, night closes the trader (v0.6.3)
python tools/godot_playtest.py --scenario chain                      # the captain's chain by the buttons: parts, the burrow, the menhir choice (v0.6.4)
python tools/godot_playtest.py --scenario bot                         # bot player: 120 random steps on the stub master, session invariants (GODOT_BOT_STEPS, GODOT_BOT_SEED)
python tools/srd_import.py build                                      # tools/srd/source + tools/srd/ru.json → game/data/srd/ and the item catalog
uv run --project llm_server python tools/srd_import.py translate      # translate new SRD entries into tools/srd/ru.json (cents)
"$GODOT" --headless --path game -s res://tools/balance_sim.gd -- burrow_priest 3 60   # encounter balance on the engine: win rate per ready-made hero
uv run --project llm_server python tools/validate_data.py            # check world packs (also runs in backend pytest / CI)
```

`llm_server` reads the root `.env`: `LLM_SERVER_TOKEN`, `OPENROUTER_API_KEY`; `LLM_SERVER_TURN_HANDLER=stub` runs it without an LLM. The playtest and connectivity scripts start it themselves (stub unless `--real`). Deploying to a server: [docs/tech/deploy.md](docs/tech/deploy.md).

Godot binary: `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` (or env `GODOT`). In Git Bash: `GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"`.

```bash
"$GODOT" --headless --path game --import     # after adding scripts or editing strings.csv (registers class_name, builds translations)
"$GODOT" --path game --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode   # gdUnit4 (exit 0 = pass)
"$GODOT" --path game                         # run the game; saves in %APPDATA%/Godot/app_userdata/Between the Rolls/
```

Pytest configuration: `pytest.ini` (`testpaths = evals`); the backend has its own in `llm_server/`. There is no linter wired up.

## Testing

Green unit tests are **necessary but not enough**: the prototype's trade screen crash (B22) lived with all tests green. Before calling a gameplay/UI/prompt change done, run a **live playtest** following the **`playtest`** skill ([.claude/skills/playtest/SKILL.md](.claude/skills/playtest/SKILL.md)): gdUnit4 green, backend pytest green, then `python tools/godot_playtest.py` (and `--scenario offline` when connection handling changed, `--scenario live --real` after prompt or agent changes), then read `build/playtest/*/report.txt` and the screenshots. Prompt changes also get the golden scenarios (`--repeat 3` before conclusions: the model varies ±2 per run).

Never print or log keys from `.env`.

**Version:** the project version lives in the root `VERSION` file (and `config/version` in `game/project.godot`). CI requires every PR to bump it and to update `RELEASE_NOTES.md`.

## Conventions

- Game text, prompts, lore — Russian. Code identifiers and code comments — English.
- LLM output is always Pydantic-typed (`llm_server/src/llm_server/protocol.py`); don't parse free text. New agents use **Pydantic AI**.
- The engine decides, the LLM narrates (ADR-0008): any change of the world goes through an engine call (`engine.check`, `engine.validate` of an effect) or a deterministic button of the client. Experience is never an LLM effect: only combat and pack quests (`XpRules`).

## Where to add things

| Task | Location |
|---|---|
| Godot rule / state | `game/core/<domain>/` + gdUnit4 test in `game/test/` (skill `godot_conventions`) |
| Godot screen or overlay | `game/ui/screens/` or `game/ui/components/` (built in code), navigation via `EventBus.navigate` |
| Godot live scenario | `game/tools/playtest/<name>.gd` (base `playtest_base.gd`) |
| Protocol message / schema | Pydantic model in `llm_server/` → export to `contract/`, bump `PROTOCOL_VERSION` on both sides, ADR-0009 «Протокол X.Y» |
| Golden LLM scenario | `evals/golden/scenarios.yaml` + [format doc](docs/tech/golden-scenarios.md); run `python -m llm_server.golden` after prompt changes |
| Architectural decision | new ADR in `docs/tech/adr/` |
| World content (lore, places, NPCs, merchants, quests, ready-made characters) | a pack in `game/data/worlds/<id>/` ([format](docs/tech/godot-client.md#пакеты-миров)); never in code |
| D&D rules content (races, classes, spells) | `game/data/srd/` via `tools/srd_import.py` (Russian names in `tools/srd/ru.json`); never hard-coded |
| Character rule (bonus, AC, HP, creation step, level-up) | `game/core/character/` (`CharacterRules`, `CharacterBuilder`, `LevelUp`) + test in `game/test/core/` |
| Numbers of the engine (DC, prices, haggling, XP, rewards) | `game/data/rules.json` |
