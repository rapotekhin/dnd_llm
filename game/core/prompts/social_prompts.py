"""
Prompts for social interaction (NPC dialogue) mode.
"""
from __future__ import annotations

from typing import List, Any, TYPE_CHECKING

if TYPE_CHECKING:
    from core.data.game_state_base import MainGameState


# =======================
# SYSTEM PROMPT BUILDER
# =======================

NPC_SYSTEM_PROMPT_TEMPLATE = """
Ты — игровой движок D&D 5e, управляющий диалоговой сценой в настольной ролевой игре.

Твои задачи:
1. Генерировать реплики персонажа {npc_name} в соответствии с его характером и описанием.
2. Определять игровые события: когда нужна проверка характеристики, когда начинается
   конфликт, когда сцена завершается переходом в другой режим.

══════════════════════════════
ПРОФИЛЬ ПЕРСОНАЖА
Имя: {npc_name}
Раса: {npc_race}
Роль: {npc_role}
Описание: {npc_description}

══════════════════════════════
ПЕРСОНАЖ ИГРОКА
Имя: {player_name}
Раса: {player_race}
Класс: {player_class}
Уровень: {player_level}
Характеристики: {abilities}

══════════════════════════════
ТЕКУЩЕЕ МЕСТО
Локация: {location_name} ({location_type}/{location_subtype})
Комната: {room_name}
Описание: {room_description}

Связанные комнаты (id для change_current_room):
{connected_rooms_with_ids}

══════════════════════════════
ИНВЕНТАРЬ ПЕРСОНАЖА (краткий список)
{npc_inventory_summary}

══════════════════════════════
КВЕСТЫ, СВЯЗАННЫЕ С ПЕРСОНАЖЕМ
{quest_context}

══════════════════════════════
ИСТОРИЯ ВЗАИМОДЕЙСТВИЙ В ЛОКАЦИИ
{location_history_summary}

══════════════════════════════
ПРАВИЛА ГЕНЕРАЦИИ:
1. Реплики {npc_name} должны соответствовать его характеру из описания выше.
2. При харизматической проверке (убеждение, дипломатия) — вызывай roll_dice с CHA игрока.
3. При переходе к торговле → action = "trade" + metadata.npc_id = "{npc_id}".
4. При завершении диалога игроком → action = "exploration".
5. При переходе в другую комнату → action = "change_current_room" + metadata.room_id.
6. При начале конфликта с применением силы → action = "combat".
7. Пока диалог продолжается → action = "social".

ВАЖНО — формат для roll_dice:
- Всегда нотация кубиков: "1d20+<модификатор>", например "1d20+2".
- Не передавай название навыка ("Persuasion" и т.п.) — только число-модификатор.
- CHA игрока: {player_cha_mod}. Пример: roll_dice(expression="1d20{player_cha_mod_signed}", difficulty_class=12)
""".strip()


def get_npc_system_prompt(game_state: "MainGameState", npc_id: str) -> str:
    """Build the full NPC system prompt from live game state."""
    npc = game_state.npcs.get(npc_id) if game_state.npcs else None

    # ── NPC info ────────────────────────────────────────────────────────────
    npc_name  = getattr(npc, "name",        "???")    if npc else "???"
    npc_race  = getattr(npc, "race",        "Unknown") if npc else "Unknown"
    npc_role  = getattr(npc, "role",        "NPC")     if npc else "NPC"
    npc_desc  = getattr(npc, "description", "")        if npc else ""

    # NPC inventory summary
    npc_inv = getattr(npc, "inventory", []) if npc else []
    if npc_inv:
        inv_lines = [f"  - {getattr(i, 'name', str(i))}" for i in npc_inv[:15]]
        npc_inventory_summary = "\n".join(inv_lines)
    else:
        npc_inventory_summary = "  (пусто)"

    # ── Player info ──────────────────────────────────────────────────────────
    player = game_state.player
    player_name  = getattr(player, "name",       "Герой")   if player else "Герой"
    player_race  = getattr(player, "race",       "Unknown") if player else "Unknown"
    player_class = getattr(player, "class_type", "Unknown") if player else "Unknown"
    player_level = getattr(player, "level",      1)         if player else 1

    abilities_str = ""
    cha_mod = 0
    if player:
        try:
            ab = player.abilities
            cha_mod = ab.get_modifier("cha")
            abilities_str = ", ".join([
                f"STR {ab.str} ({ab.get_modifier('str'):+d})",
                f"DEX {ab.dex} ({ab.get_modifier('dex'):+d})",
                f"CON {ab.con} ({ab.get_modifier('con'):+d})",
                f"INT {ab.int} ({ab.get_modifier('int'):+d})",
                f"WIS {ab.wis} ({ab.get_modifier('wis'):+d})",
                f"CHA {ab.cha} ({cha_mod:+d})",
            ])
        except Exception:
            abilities_str = "(неизвестно)"

    # ── Location / room info ─────────────────────────────────────────────────
    room_id   = game_state.current_room_id
    loc_id    = game_state.current_location_id
    room      = game_state.rooms.get(room_id)     if room_id else None
    location  = game_state.locations.get(loc_id)  if loc_id  else None

    room_name = getattr(room,     "name",        "???") if room     else "???"
    room_desc = getattr(room,     "description", "")    if room     else ""
    loc_name  = getattr(location, "name",        "???") if location else "???"
    loc_type  = getattr(location, "type",        "")    if location else ""
    loc_sub   = getattr(location, "subtype",     "")    if location else ""
    loc_summary = getattr(location, "location_history_summary", "") if location else ""

    # Connected rooms with IDs
    connected_rooms_lines = []
    if room:
        for cid in getattr(room, "connections", []):
            cr = game_state.rooms.get(cid)
            if not cr:
                continue
            cr_loc_id = getattr(cr, "location_id", None)
            cl = game_state.locations.get(cr_loc_id) if cr_loc_id else None
            info = f" [{cl.name}]" if cl else ""
            connected_rooms_lines.append(f"  - {cr.name} (id: {cid}){info}")
    connected_rooms_with_ids = "\n".join(connected_rooms_lines) or "  (нет)"

    # Quest context (quests assigned to this NPC)
    quest_ids = getattr(npc, "quests", []) if npc else []
    quest_lines = []
    _quests_dict = getattr(game_state, "quests", None) or {}
    for qid in quest_ids:
        q = _quests_dict.get(qid) if _quests_dict else None
        if q:
            quest_lines.append(f"  - {getattr(q, 'name', qid)}: {getattr(q, 'description', '')[:80]}")
    quest_context = "\n".join(quest_lines) or "  (нет)"

    cha_mod_signed = f"{cha_mod:+d}" if cha_mod != 0 else ""

    return NPC_SYSTEM_PROMPT_TEMPLATE.format(
        npc_id=npc_id,
        npc_name=npc_name,
        npc_race=npc_race,
        npc_role=npc_role,
        npc_description=npc_desc,
        player_name=player_name,
        player_race=player_race,
        player_class=player_class,
        player_level=player_level,
        abilities=abilities_str,
        player_cha_mod=cha_mod,
        player_cha_mod_signed=cha_mod_signed,
        location_name=loc_name,
        location_type=loc_type,
        location_subtype=loc_sub,
        room_name=room_name,
        room_description=room_desc,
        connected_rooms_with_ids=connected_rooms_with_ids,
        npc_inventory_summary=npc_inventory_summary,
        quest_context=quest_context,
        location_history_summary=loc_summary or "(нет данных)",
    )


# =======================
# GREETING AGENT
# =======================

def prompt_initial_greeting(npc_name: str) -> str:
    """User prompt for the greeting agent — asks for scene + opening line."""
    return (
        f"Опиши игровую сцену: персонаж игрока приближается к {npc_name}. "
        f"Затем сгенерируй первую реплику {npc_name} согласно его характеру."
    )


# =======================
# RESPONSE OPTIONS AGENT
# =======================

def prompt_generate_response_options(history: List[Any], last_npc_message: str) -> str:
    """Prompt for generating 2-4 suggested player responses."""
    return f"""
История диалога:
{_format_history(history)}

Последнее сообщение персонажа:
{last_npc_message}

Сгенерируй 2-4 варианта ответа для игрока с разными тональностями:
один нейтральный, один дружелюбный, один ведущий к торговле (если уместно),
один завершающий разговор.
""".strip()


# =======================
# RESOLUTION AGENT
# =======================

def get_social_resolution_instructions(npc_name: str, npc_id: str) -> str:
    """Instructions appended to the resolution agent system prompt."""
    return f"""
Инструкция разрешения хода:
1) При необходимости харизматической проверки — вызови roll_dice до формирования ответа.
2) Сгенерируй реплику {npc_name} согласно его характеру и контексту сцены.
3) Укажи следующее игровое действие.

Правила выбора action:
- Диалог продолжается → "social"
- Игрок запрашивает торговлю или персонаж предлагает товары → "trade" + metadata.npc_id = "{npc_id}"
- Силовой конфликт начинается → "combat"
- Игрок завершает разговор и уходит → "exploration"
- Игрок переходит в другую комнату → "change_current_room" + metadata.room_id

Ответь одним валидным JSON-объектом:
- "npc_reply" (string): реплика {npc_name}, соответствующая его характеру.
- "action" (string): "social" | "trade" | "exploration" | "combat" | "change_current_room"
- "question_to_player" (string | null): уточняющий вопрос если нужны детали; null — не нужно.
- "metadata" (object): {{"npc_id": "..." | null, "room_id": "..." | null}}

Примеры:
{{"npc_reply": "Приветствую! Чем могу помочь?", "action": "social", "question_to_player": null, "metadata": {{"npc_id": null, "room_id": null}}}}
{{"npc_reply": "Хорошо, посмотрим мой товар.", "action": "trade", "question_to_player": null, "metadata": {{"npc_id": "{npc_id}", "room_id": null}}}}
{{"npc_reply": "Удачи в пути, путник.", "action": "exploration", "question_to_player": null, "metadata": {{"npc_id": null, "room_id": null}}}}
""".strip()


def prompt_social_resolution(
    history: List[Any],
    last_npc_message: str,
    player_choice: str,
) -> str:
    """Full user prompt for the resolution agent."""
    return f"""
История диалога:
{_format_history(history)}

Последнее сообщение НПС:
{last_npc_message}

Игрок отвечает:
{player_choice}
""".strip()


# =======================
# SUMMARY AGENT
# =======================

def prompt_generate_social_summary(
    past_summary: str,
    session_history: List[str],
    npc_name: str,
    location_name: str,
) -> str:
    history_text = "\n".join(session_history) if session_history else "(нет данных)"
    return f"""
Ты — архивариус, составляющий краткие записи о событиях.

Локация: {location_name}
НПС: {npc_name}

Прошлое саммари (из предыдущих посещений):
{past_summary or "(пусто — первое посещение)"}

Новый диалог этого посещения:
{history_text}

Составь НОВОЕ краткое саммари (2-4 предложения), объединяющее прошлые записи и новый диалог.
Включай только важные факты: о чём договорились, что изменилось, что НПС рассказал.
Не упоминай механику (броски, проверки).
""".strip()


# =======================
# HELPERS
# =======================

def _format_history(history: List[Any]) -> str:
    if not history:
        return "(нет)"
    return "\n".join(str(h) for h in history)
