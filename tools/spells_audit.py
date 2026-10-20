"""The audit of every spell a hero of levels 1–5 can cast (circles 0–3): what the engine does with it today and the
group it belongs to in the «spells by the rules» work (roadmap v0.7.7).

    python tools/spells_audit.py            # → docs/production/spells-audit.md

Status comes from the data: `rules.combat.engine_spells` (attack / save damage and healing), `condition_spells`,
`rules.invisibility.spells`; everything else only spends the slot and the concentration — the master narrates the
rest. Groups and the «checked» marks live here, next to the plan; mark a spell CHECKED once a test covers it.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "production" / "spells-audit.md"

GROUPS = {
    "buff": ("Защита и усиления героя", "числа листа и боя: КД, бонусы к атакам и спасброскам, урон, скорость, сопротивления, временные хиты"),
    "sustained": ("Длящийся урон и удары", "заклинание остаётся на поле или на оружии и бьёт каждый ход"),
    "control": ("Ослабление и контроль врагов", "помехи, состояния, зоны на поле, прерывание чужих заклинаний"),
    "restore": ("Лечение и спасение", "стабилизация, снятие состояний и проклятий, воскрешение, еда"),
    "summon": ("Призывы и спутники", "существа на поле боя или помощники вне боя — нужны союзники в бою (M4)"),
    "world": ("Мир и исследование", "вне боя: свет, иллюзии, замки, обнаружение, разговоры, перемещение — связь с проверками, секретами, выходами"),
}

ASSIGN = {
    "buff": "mage_armor shield shield_of_faith barkskin blur mirror_image sanctuary false_life aid heroism bless guidance resistance "
            "enhance_ability divine_favor magic_weapon hunters_mark longstrider expeditious_retreat jump haste protection_from_energy "
            "protection_from_poison protection_from_evil_and_good warding_bond beacon_of_hope true_strike darkvision see_invisibility "
            "spider_climb enlarge_reduce alter_self pass_without_trace blink fly gaseous_form water_breathing water_walk",
    "sustained": "shillelagh flame_blade flaming_sphere spiritual_weapon moonbeam branding_smite call_lightning spirit_guardians heat_metal "
                 "vampiric_touch hellish_rebuke spike_growth",
    "control": "bane faerie_fire ray_of_enfeeblement bestow_curse slow hypnotic_pattern web grease sleet_storm stinking_cloud fog_cloud "
               "darkness silence gust_of_wind wind_wall calm_emotions enthrall suggestion animal_friendship counterspell dispel_magic",
    "restore": "spare_the_dying lesser_restoration remove_curse revivify goodberry create_food_and_water purify_food_and_drink",
    "summon": "find_familiar find_steed conjure_animals animate_dead unseen_servant phantom_steed floating_disk animal_messenger",
    "world": "light dancing_lights daylight continual_flame mage_hand mending message minor_illusion prestidigitation thaumaturgy "
             "druidcraft silent_image major_image disguise_self illusory_script magic_mouth arcane_lock knock arcanists_magic_aura alarm "
             "glyph_of_warding tiny_hut rope_trick magic_circle nondetection meld_into_stone plant_growth levitate feather_fall misty_step "
             "identify detect_magic detect_evil_and_good detect_poison_and_disease detect_thoughts find_traps locate_object "
             "locate_animals_or_plants comprehend_languages tongues speak_with_animals speak_with_dead speak_with_plants augury "
             "clairvoyance zone_of_truth sending gentle_repose create_or_destroy_water",
}

# Spells a test already checks against the 5e rules (id → test). Fill in as the work goes.
CHECKED: dict[str, str] = {}


def main() -> int:
    spells = json.loads((ROOT / "game" / "data" / "srd" / "spells.json").read_text(encoding="utf-8"))
    rules = json.loads((ROOT / "game" / "data" / "rules.json").read_text(encoding="utf-8"))
    engine = set(rules["combat"]["engine_spells"])
    conditions = set(rules["combat"]["condition_spells"]) - {"_doc"}
    invisibility = set(rules.get("invisibility", {}).get("spells", {}))
    group_of = {sid: g for g, ids in ASSIGN.items() for sid in ids.split()}
    playable = {k: v for k, v in spells.items() if int(v.get("level", 0)) <= 3}

    def status(sid: str) -> str:
        if sid in engine:
            return "движок: урон / лечение"
        if sid in conditions:
            return "движок: состояния"
        if sid in invisibility:
            return "движок: невидимость"
        return "**только мастер**"

    unassigned = sorted(sid for sid in playable if status(sid) == "**только мастер**" and sid not in group_of)
    if unassigned:
        raise SystemExit(f"no group for: {', '.join(unassigned)}")
    counts = {"engine": sum(1 for s in playable if s in engine), "conditions": sum(1 for s in playable if s in conditions),
              "invisibility": sum(1 for s in playable if s in invisibility)}
    master = len(playable) - sum(counts.values())

    lines = [
        "# Аудит заклинаний (круги 0–3)",
        "",
        f"Генерируется: `python tools/spells_audit.py`. План — [роадмап v0.7.7](roadmap.md). Всего доступно героям 1–5 уровня: **{len(playable)}**; "
        f"движок разрешает {counts['engine']} (урон и лечение) + {counts['conditions']} (состояния) + {counts['invisibility']} (невидимость); "
        f"**{master} — только мастер**: ячейка и концентрация тратятся, остальное — лишь в рассказе.",
        "",
        "Группы плана:",
        "",
    ]
    for g, (title, what) in GROUPS.items():
        n = sum(1 for sid in playable if group_of.get(sid) == g and status(sid) == "**только мастер**")
        lines.append(f"- **{title}** ({n}) — {what}")
    lines += ["", "| Заклинание | id | Круг | Конц. | Сейчас | Группа | Проверено |", "|---|---|---|---|---|---|---|"]
    for sid, v in sorted(playable.items(), key=lambda kv: (int(kv[1].get("level", 0)), kv[1]["name"])):
        g = GROUPS[group_of[sid]][0] if sid in group_of else "—"
        lines.append(f"| {v['name']} | `{sid}` | {v.get('level', 0)} | {'да' if v.get('concentration') else ''} | {status(sid)} | {g} | {CHECKED.get(sid, '')} |")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(OUT, f"{len(playable)} spells, {master} master-only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
