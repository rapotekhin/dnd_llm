"""Prompt templates (Jinja2, *.md.j2 next to this file). StrictUndefined: a missing variable is an error."""

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


def system_prompt(mode: str, snap: Snapshot, npc: SceneNpc | None, tone: str = DEFAULT_TONE) -> str:
    character: CharacterSheet | None = snap.character
    if snap.world is not None and snap.world.tone:
        tone = snap.world.tone
    context: dict[str, object] = {
        "mode": mode,
        "trade": snap.trade,
        "quests": snap.quests,
        "combat": snap.combat,
        "world": snap.world,
        "character": character,
        "coins": coins(character.gold_cp) if character else "",
        "scene": snap.scene,
        "summaries": snap.summaries,
        "limits": snap.limits,
        "tone": tone,
        "gender_rule": gender_rule(character.gender if character else "other"),
    }
    if mode == "exploration":
        return render("exploration.md.j2", **context)
    if mode == "combat":
        return render("combat.md.j2", **context)
    if npc is None:
        raise ValueError(f"mode {mode} needs an NPC")
    return render(f"{mode}.md.j2", npc=npc, npc_gender_rule=npc_gender_rule(npc.gender), **context)


def turn_prompt(mode: str, kind: str, player_input: str, snap: Snapshot, npc: SceneNpc | None) -> str:
    return render("turn.md.j2", mode=mode, kind=kind, input=player_input, history=snap.history,
                  room_name=snap.scene.room_name if snap.scene else "",
                  npc_name=npc.name if npc else "", world=snap.world)


def summary_prompt(kind: str, subject_id: str, previous: str, events: list[str]) -> str:
    return render("summary.md.j2", kind=kind, subject_id=subject_id, previous=previous, events=events)
