"""The audit by pillar 6 «Движок — конструктор, а не список» (roadmap v0.7.16): where the engine and the prompts keep
a closed list of cases instead of a concept with data and a creation tool.

    python tools/concepts_audit.py         # → docs/production/concepts-audit.md (exit 1 while a finding has no decision)

What it looks for:
- `match` over string ids outside the 5e rules (pillar 2 keeps the SRD rules in code by design);
- dictionaries from ids to Russian text in the code — names and descriptions that belong to the data;
- Russian names and descriptions of world things written in the code;
- limits on content in the master's prompts: «только из сцены / из списка / из пакета …» — a guard of pillar 1 or a gap
  until the master has a creation tool.

Every finding is decided here, in DECISIONS, next to the plan: `concept` — a closed set of the engine's own operations
(the concept itself, fine), `data` — move to the data (the note says where and when), `5e` — a rule of 5e, `engine` —
the engine's plumbing (protocol, saves, journal), `gap` — a guard that stays until the master gets a creation tool (the
note names the version). The registry of concepts is docs/design/concepts.md.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "game" / "core"
PROMPTS = ROOT / "llm_server" / "src" / "llm_server" / "prompts"
OUT = ROOT / "docs" / "production" / "concepts-audit.md"

# The 5e rules (pillar 2): classes, spells, conditions, monsters, combat — code by the SRD, not world content.
RULES_5E = {"combat_rules.gd", "feature_rules.gd", "spell_effects.gd", "spell_rules.gd", "character_rules.gd",
            "character_builder.gd", "level_up.gd", "condition_rules.gd", "monster_rules.gd", "hero_defense.gd",
            "language_rules.gd", "background_rules.gd", "feature_uses.gd"}

VERDICT = {"concept": "понятие движка", "data": "**в данные**", "gap": "**пробел до инструмента**", "5e": "правило 5e",
           "engine": "служебное", "done": "сделано"}

# key → (verdict, note). Keys: "match:<file>:<func>", "dict:<file>:<func>", "text:<file>:<func>", "prompt:<file>:<the rule's bold title>".
DECISIONS: dict[str, tuple[str, str]] = {
    "match:effect_engine.gd:_plan": ("concept", "виды эффектов — словарь понятий движка, который знает мастер (протокол); новый вид — новое понятие"),
    "match:effect_engine.gd:_plan_on_foe": ("concept", "эффекты на врага в бою — те же понятия"),
    "match:effect_engine.gd:_apply_one": ("concept", "применение видов эффектов"),
    "match:game_session.gd:history": ("engine", "виды записей чата"),
    "match:lookup.gd:find": ("engine", "справка движка по видам"),
    "match:world_pack.gd:_merge": ("engine", "разделы пакета мира"),
    "match:crime_rules.gd:_ending": ("engine", "окончание по роду NPC (данные пакета)"),
    "match:crime_rules.gd:answer": ("concept", "ответ страже — три исхода понятия «задержание» (вергельд, колодки, сопротивление); сумма и сроки — rules.json"),
    "match:social_rules.gd:resistance": ("5e", "состязания 5e: против чего проверка (rules.social.contests)"),
    "match:social_rules.gd:_outcome": ("done", "v0.7.16: услуга — данные `rules.items.services` (операция движка + название), не код"),
    "match:trade_rules.gd:buy_service": ("done", "v0.7.16: услуга — операция движка из данных (`op`: identify, lift_curse, enchant)"),
    "match:theft_rules.gd:react": ("concept", "реакция пойманного вора — понятие с видами из шаблона (бой, лавка, стража); виды — rules.theft"),
    "dict:social_rules.gd:tr_service": ("done", "v0.7.16: названия услуг — `name` в rules.json"),
    "text:theft_rules.gd:react": ("done", "v0.7.16: стражник — из закона локации (`law.guard_name`, `law.guard_desc` пакета)"),
    "text:crime_rules.gd:answer": ("concept", "запасное имя стражи, если пакет не задал `guard_name`"),
    "text:crime_rules.gd:bodies_here": ("engine", "подпись тела убитого NPC на панели: «Тело: имя»"),
    "text:theft_rules.gd:pockets": ("engine", "монеты в карманах — понятие «кошель», не вещь мира"),
    "match:trade_rules.gd:targets": ("concept", "операции услуг движка (identify, lift_curse, enchant): услуга — данные над ними"),
    "match:world_pack.gd:_known": ("engine", "разделы SRD в пакете мира"),
    "match:container_rules.gd:lock_check": ("concept", "способы открыть замок — понятие движка (ключ, отмычки, сила); сложность — rules.containers"),
    "prompt:_rules.md.j2:Состояния героя — эффект `condition` по правилам 5e": ("5e", "длительности состояний 5e"),
    "prompt:_rules.md.j2:Предметы": ("concept", "новый предмет мастер создаёт сам (`give_item.item`) из словаря свойств — генерация полностью в v0.7.18"),
    "prompt:_rules.md.j2:Места — только из сцены": ("gap", "мастер не может создать место — до генерации мест v0.7.20; тогда — «нужно место по замыслу игрока → создай»"),
    "prompt:_rules.md.j2:Люди, задания и слухи — только из мира": ("gap", "людей мастер создаёт `create_npc` (v0.7.20); задания — до генерации v0.7.21"),
    "prompt:_rules.md.j2:Бой — только с теми, кто есть в сцене": ("concept", "встреча — понятие мира; создание встреч — с местами и заданиями (v0.7.20–v0.7.21)"),
    "prompt:_rules.md.j2:Всё вокруг — настоящие вещи": ("concept", "вещи комнаты мастер создаёт сам (`furnish` при первом входе)"),
}

MATCH = re.compile(r"^(\s*)match (.+):\s*$")
CASE = re.compile(r'^\s*"([a-z_]+)"(?:\s*,\s*"[a-z_]+")*\s*:')
FUNC = re.compile(r"^(?:static )?func (\w+)")
ID_DICT = re.compile(r'"(?!reason|summary|text|note|name|desc|description|why|title)[a-z_]+"\s*:\s*"[^"]*[а-яё][^"]*"\s*,\s*'
                     r'"(?!reason|summary|text|note|name|desc|description|why|title)[a-z_]+"\s*:\s*"[^"]*[а-яё]')
NAME_TEXT = re.compile(r'"(?:name|desc|description)"\s*:\s*"[А-ЯЁ]')
CLOSED = re.compile(r"(?:только|лишь)[^.\n]{0,60}?(?:из сцены|из списка|из пакета|по выходам|из мира|из каталога|кто есть в сцене)[^.\n]{0,40}")


def scan_code() -> list[dict]:
    out = []
    for path in sorted(CORE.rglob("*.gd")):
        if path.name in RULES_5E:
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        func = ""
        for i, line in enumerate(lines):
            f = FUNC.match(line)
            if f:
                func = f.group(1)
            m = MATCH.match(line)
            if m:
                indent = len(m.group(1).expandtabs(4))
                cases = []
                for nxt in lines[i + 1:]:
                    if nxt.strip() and len(nxt) - len(nxt.lstrip()) <= len(m.group(1)) and len(nxt.expandtabs(4)) - len(nxt.expandtabs(4).lstrip()) <= indent:
                        break
                    c = CASE.match(nxt)
                    if c and len(nxt.expandtabs(4)) - len(nxt.expandtabs(4).lstrip()) == indent + 4:
                        cases.append(c.group(1))
                if cases:
                    out.append({"key": f"match:{path.name}:{func}", "where": f"{path.relative_to(ROOT).as_posix()}:{i + 1}",
                                "what": "match по " + ", ".join(cases[:8]) + ("…" if len(cases) > 8 else "")})
            if ID_DICT.search(line) and not line.lstrip().startswith("#"):
                out.append({"key": f"dict:{path.name}:{func}", "where": f"{path.relative_to(ROOT).as_posix()}:{i + 1}",
                            "what": "словарь id → русский текст в коде"})
            if NAME_TEXT.search(line) and not line.lstrip().startswith("#"):
                out.append({"key": f"text:{path.name}:{func}", "where": f"{path.relative_to(ROOT).as_posix()}:{i + 1}",
                            "what": "имя или описание вещи мира в коде"})
    seen, uniq = set(), []
    for f in out:  # one row per key: the first place
        if f["key"] not in seen:
            seen.add(f["key"])
            uniq.append(f)
    return uniq


def scan_prompts() -> list[dict]:
    out = []
    for path in sorted(PROMPTS.glob("*.j2")):
        for i, line in enumerate(path.read_text(encoding="utf-8").splitlines()):
            rule = re.search(r"\*\*(.+?)\*\*", line)
            for m in CLOSED.finditer(line):
                text = m.group(0)
                out.append({"key": f"prompt:{path.name}:{rule.group(1).rstrip('.') if rule else i + 1}", "where": f"{path.relative_to(ROOT).as_posix()}:{i + 1}",
                            "what": "«" + (text[:110] + "…" if len(text) > 110 else text) + "»"})
    seen, uniq = set(), []
    for f in out:  # one row per rule
        if f["key"] not in seen:
            seen.add(f["key"])
            uniq.append(f)
    return uniq


def main() -> int:
    findings = scan_code() + scan_prompts()
    rows, open_ = [], 0
    for f in findings:
        verdict, note = DECISIONS.get(f["key"], ("", ""))
        if not verdict:
            open_ += 1
        rows.append(f"| `{f['where']}` | {f['what']} | {VERDICT.get(verdict, '**не разобрано**')} | {note} |")
    counts = {v: sum(1 for f in findings if DECISIONS.get(f["key"], ("",))[0] == v) for v in VERDICT}
    text = [
        "# Аудит по столпу 6",
        "",
        "Генерируется: `python tools/concepts_audit.py`. Столп — [«Движок — конструктор, а не список»](../vision/pillars.md#6-движок--конструктор-а-не-список); "
        "реестр понятий — [concepts.md](../design/concepts.md); план — [роадмап v0.7.16](roadmap.md#v0716--аудит-по-столпу-6-движок-конструктор). "
        "Ищет закрытые перечни случаев в коде вне правил 5e (они — столп 2) и в промптах мастера; решение по каждой находке — в `DECISIONS` инструмента.",
        "",
        f"Находок: {len(findings)} — " + ", ".join(f"{VERDICT[v]} {n}" for v, n in counts.items() if n) + (f", не разобрано {open_}" if open_ else "") + ".",
        f"Правила 5e вне аудита (столп 2): {', '.join(sorted(RULES_5E))}.",
        "",
        "| Где | Что | Решение | Почему |",
        "|---|---|---|---|",
        *rows,
        "",
    ]
    found = {f["key"] for f in findings}
    fixed = [f"- `{k}` — {note}" for k, (v, note) in DECISIONS.items() if v == "done" and k not in found]
    if fixed:
        text += ["## Исправлено", "", *fixed, ""]
    OUT.write_text("\n".join(text), encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(findings)} findings, {open_} without a decision")
    return 1 if open_ else 0


if __name__ == "__main__":
    sys.exit(main())
