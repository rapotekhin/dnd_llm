"""Prompt templates (Jinja2, *.md.j2 next to this file). StrictUndefined: a missing variable is an error."""

import re
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined

from ..protocol import CharacterSheet, Gender, SceneNpc, Snapshot

DEFAULT_TONE = "тёмное фэнтези с надеждой: мир суров, но в нём есть место смелости и доброте"

_ATTITUDE = {-3: "враждебно", -2: "неприязненно", -1: "настороженно", 0: "нейтрально", 1: "приветливо", 2: "дружески", 3: "как к близкому другу"}
_ROLES = {"player": "Игрок", "dm": "Мастер", "npc": "NPC"}


def attitude_word(value: int) -> str:
    return _ATTITUDE[max(-3, min(3, value))]


_ABILITIES = {"str": "Сил", "dex": "Лов", "con": "Тел", "int": "Инт", "wis": "Мдр", "cha": "Хар"}


def ability_name(key: str) -> str:
    return _ABILITIES.get(key, key)


STYLE_RULES = {
    "classic": "Классический: ровный серьёзный рассказчик. Сцена — 2–4 предложения, ответ на действие — 1–3, без лишних метафор.",
    "literary": "Литературный: образно и атмосферно — запахи, звуки, свет, точные метафоры. До 4 предложений, ритм неспешный, но без воды.",
    "dry": "Сухой: коротко и по делу — не больше 3 коротких предложений (строже общего лимита): что есть, кто есть, куда можно пойти. Без эпитетов и атмосферы.",
    "ironic": "Ироничный: лёгкая усмешка над штампами и ситуацией, но мир остаётся опасным, а NPC — живыми людьми. Не глумись над игроком.",
}
VIOLENCE_RULES = {
    "mild": "мягко: насилие и раны — без натурализма, одной фразой; смерть — за кадром",
    "medium": "умеренно: бой и раны описываются честно, но без смакования крови и увечий",
    "graphic": "жёстко — игрок выбрал это сам: раны, кровь, увечья, боль и смерть описывай прямо и натуралистично, конкретными телесными деталями; жестокость, которую игрок совершает или видит, показывай в кадре, не смягчай, не уводи за кадр и не морализируй (кроме того, что в линиях и вуалях)",
}


def summary_title(key: str) -> str:
    if key == "location":
        return "В этой локации"
    if key.startswith("dialogue:"):
        return f"Разговор с [{key.split(':', 1)[1]}]"
    return key


def gender_rule(gender: Gender) -> str:
    return {
        "female": "Персонаж игрока — женщина: обращайся в женском роде («ты вошла», «готова»).",
        "male": "Персонаж игрока — мужчина: обращайся в мужском роде («ты вошёл», «готов»).",
    }.get(gender, "Пол персонажа не указан: избегай родовых форм при обращении к игроку.")


def npc_gender_rule(gender: Gender) -> str:
    return {
        "female": "О себе NPC говорит в женском роде.",
        "male": "О себе NPC говорит в мужском роде.",
    }.get(gender, "")


def coins(cp: int) -> str:
    gp, rest = divmod(cp, 100)
    sp, cp_left = divmod(rest, 10)
    parts = [f"{gp} зм" if gp else "", f"{sp} см" if sp else "", f"{cp_left} мм" if cp_left else ""]
    return " ".join(p for p in parts if p) or "0 зм"


_env = Environment(
    loader=FileSystemLoader(Path(__file__).parent),
    undefined=StrictUndefined,
    trim_blocks=True,
    lstrip_blocks=True,
    keep_trailing_newline=False,
)
_env.globals.update(attitude_word=attitude_word, money=coins, summary_title=summary_title, ability_name=ability_name,
                    style_rule=lambda s: STYLE_RULES.get(s, STYLE_RULES["classic"]),
                    violence_rule=lambda v: VIOLENCE_RULES.get(v, VIOLENCE_RULES["medium"]), role_name=lambda r: _ROLES.get(r, r))


def render(name: str, **context: object) -> str:
    text = _env.get_template(name).render(**context)
    # Collapse the blank-line runs that conditional blocks leave behind.
    lines: list[str] = []
    for line in text.splitlines():
        if line.strip() or (lines and lines[-1].strip()):
            lines.append(line.rstrip())
    return "\n".join(lines).strip() + "\n"


# Rules of a topic (prompts/topics/<key>.md.j2, v0.7.20.4): out of the system prompt, read by the master with the tool
# `rules` when it needs them; the scene puts a topic in by itself when it is there (an open edge, a crime, a stranger).
# key -> (the line of the index: when to read it, the effect kinds the engine accepts only after it is read or shown).
TOPICS: dict[str, tuple[str, tuple[str, ...]]] = {
    "conditions": ("состояния героя: яд, страх, сон, паралич, путы, истощение; проверки зрения и слуха (`condition`)", ("condition",)),
    "spells": ("что заклинание сделало в мире: иллюзии, разговор со зверьми и мёртвыми, гадание; заклинание на себя", ()),
    "pay": ("покупка у не-торговца, плата за услугу или сведения, платный вариант (`option_costs`), ночлег", ()),
    "theft": ("кража из карманов: как её отыграть", ()),
    "items": ("новый предмет (`give_item.item`): жезлы, свитки, зелья, вещи с текстом; магические вещи, неопознанные и проклятые", ()),
    "places": ("новое место на открытом краю мира (`create_place`)", ("create_place",)),
    "crime": ("преступления героя: убитые, розыск, стража, признание (`crime_known`)", ("crime_known", "crime_release")),
    "social": ("что NPC даёт словами: скидка, услуга даром, тайна, идёт с героем, слава в поселении "
               "(`npc_discount`, `npc_favor`, `reveal_secret`, `npc_follow`, `reputation`)",
               ("npc_discount", "npc_favor", "reveal_secret", "npc_follow", "reputation")),
    "goals": ("замысел игрока, которого нет готовым; высокая цель; `missing_concept`", ()),
    "equip": ("надеть, снять, раздеться (`equip`)", ("equip",)),
    "invisible": ("невидимый герой", ()),
    "people": ("новый человек (`create_npc`)", ("create_npc",)),
    "quests": ("новое задание: NPC просит о помощи, игрок ищет работу (`create_quest`)", ("create_quest",)),
    "languages": ("NPC не понимает героя; языки", ()),
    "tools": ("действие инструментом: замок, травы, подделка, грим (`request_check` с `tool`)", ()),
    "background": ("предыстория героя и связь NPC с его прошлым", ()),
    "containers": ("сундуки, ящики, сумки героя, товары торговца в лавке: достать, положить, отпереть, оставить (`take_from`, `put_in`, `unlock`, `drop_item`)",
                   ("take_from", "put_in", "unlock", "drop_item")),
}


# Topics of a scene, not of a conversation: out of the index while the hero talks (still readable by `rules`).
SCENE_TOPICS = {"places", "containers", "equip", "tools", "invisible"}
BOARD = re.compile(r"доск|объявлен|листк|столб с", re.IGNORECASE)


def auto_topics(mode: str, snap: Snapshot) -> list[str]:
    """Topics the scene needs now: they go into the system prompt whole."""
    scene, character = snap.scene, snap.character
    out: list[str] = []
    # conditions come often and by words in a scene (v0.7.20.4 goldens); a conversation keeps only its own topic —
    # the NPC's prompt grew to 28k characters with conditions, payment and quests in it (the author's trace, v0.7.21.3)
    if mode in ("exploration", "combat") or (character and character.conditions):
        out.append("conditions")
    if mode in ("social", "trade"):
        out.append("social")
    if scene and scene.open_edges:
        out.append("places")
    if snap.crimes:
        out.append("crime")
    if character and any("невидим" in c for c in character.conditions):
        out.append("invisible")
    if scene and any(not n.understands_hero for n in scene.npcs):
        out.append("languages")
    if scene and any(n.tie for n in scene.npcs):
        out.append("background")
    if scene and any(p.container for p in scene.props):
        out.append("containers")
    if scene and any(BOARD.search(p.name) for p in scene.props):  # work is asked at a board (v0.7.21.2)
        out.append("quests")
    return [t for t in TOPICS if t in out]


def topic_for(kind: str) -> str:
    """The topic whose rules an effect kind needs ("" — none)."""
    return next((k for k, (_, kinds) in TOPICS.items() if kind in kinds), "")


def topic_text(key: str) -> str:
    return render(f"topics/{key}.md.j2")


def system_prompt(mode: str, snap: Snapshot, npc: SceneNpc | None, tone: str = DEFAULT_TONE) -> str:
    character: CharacterSheet | None = snap.character
    if snap.world is not None and snap.world.tone:
        tone = snap.world.tone
    context: dict[str, object] = {
        "mode": mode,
        "trade": snap.trade,
        "quests": snap.quests,
        "combat": snap.combat,
        "crimes": snap.crimes,
        "world": snap.world,
        "character": character,
        "coins": coins(character.gold_cp) if character else "",
        "reward_left": coins(character.reward_left_cp) if character and character.reward_left_cp is not None else "",
        "scene": snap.scene,
        "summaries": snap.summaries,
        "limits": snap.limits,
        "tone": tone,
        "gender_rule": gender_rule(character.gender if character else "other"),
    }
    shown = auto_topics(mode, snap)
    context["auto_topics"] = shown
    scene_only = SCENE_TOPICS if mode in ("social", "trade") else set()  # a conversation does not search or carry
    context["topic_index"] = [(k, v[0]) for k, v in TOPICS.items() if k not in shown and k not in scene_only]
    if mode == "exploration":
        return render("exploration.md.j2", **context)
    if mode == "combat":
        return render("combat.md.j2", **context)
    if npc is None:
        raise ValueError(f"mode {mode} needs an NPC")
    return render(f"{mode}.md.j2", npc=npc, npc_gender_rule=npc_gender_rule(npc.gender), **context)


def short_prompt(mode: str, snap: Snapshot, npc: SceneNpc | None, tone: str = DEFAULT_TONE) -> str:
    """The short system prompt of the router (v0.7.20.4): only words, the scene in brief."""
    if snap.world is not None and snap.world.tone:
        tone = snap.world.tone
    character = snap.character
    return render("short.md.j2", mode=mode, npc=npc if mode != "exploration" else None, scene=snap.scene, world=snap.world,
                  character=character, tone=tone, gender_rule=gender_rule(character.gender if character else "other"),
                  npc_gender_rule=npc_gender_rule(npc.gender) if npc else "")


def turn_prompt(mode: str, kind: str, player_input: str, snap: Snapshot, npc: SceneNpc | None) -> str:
    return render("turn.md.j2", mode=mode, kind=kind, input=player_input, history=snap.history,
                  room_name=snap.scene.room_name if snap.scene else "",
                  npc_name=npc.name if npc else "", world=snap.world)


def summary_prompt(kind: str, subject_id: str, previous: str, events: list[str]) -> str:
    return render("summary.md.j2", kind=kind, subject_id=subject_id, previous=previous, events=events)
