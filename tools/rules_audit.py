"""The audit of the 5e rules a hero of levels 1–5 meets: what the engine does with each thing today (roadmap series
«Правила 5e», v0.7.8–v0.7.13). Conditions, damage to the hero, monsters, class features, race traits, languages and
backgrounds, items, spells.

    python tools/rules_audit.py            # → docs/production/rules-audit.md

Counts come from the data (game/data, the SRD source in tools/srd/source); the statuses live here, next to the plan,
and are set by reading the engine (game/core). Change a status when a version makes the thing work, and fill in
CHECKED once a test covers it against the 5e rules.
"""

import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "game" / "data"
SRD = ROOT / "tools" / "srd" / "source" / "2014"
OUT = ROOT / "docs" / "production" / "rules-audit.md"
MAX_MONSTER_CR = 3  # as tools/srd_import.py

STATUS = {
    "engine": "движок",
    "partial": "частично",
    "creation": "при создании",
    "master": "**только мастер**",
    "none": "**нет нигде**",
}
MISSING = ("master", "none")

# Spells (v0.7.13): groups of the master-only ones.
SPELL_GROUPS = {
    "buff": ("Защита и усиления героя", "числа листа и боя: КД, бонусы к атакам и спасброскам, урон, скорость, сопротивления, временные хиты"),
    "sustained": ("Длящийся урон и удары", "заклинание остаётся на поле или на оружии и бьёт каждый ход"),
    "control": ("Ослабление и контроль врагов", "помехи, состояния, зоны на поле, прерывание чужих заклинаний"),
    "restore": ("Лечение и спасение", "стабилизация, снятие состояний и проклятий, воскрешение, еда"),
    "summon": ("Призывы и спутники", "существа на поле боя или помощники вне боя — нужны союзники в бою (M4)"),
    "world": ("Мир и исследование", "вне боя: свет, иллюзии, замки, обнаружение, разговоры, перемещение — связь с проверками, секретами, выходами"),
}
SPELL_ASSIGN = {
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

# Conditions (v0.7.8): checks outside combat, on the hero in combat, on a foe in combat, who lays it on the hero.
CONDITIONS = {
    "blinded": ("да (v0.7.8): провал Внимательности, Анализа и проверок со зрением", "да: помеха своим атакам, преимущество врагам",
                "да: преимущество по нему, помеха ему", "мастер эффектом со спасброском; монстры — v0.7.9"),
    "charmed": ("мастер решает о социальных проверках", "да: не нападает на очаровавшего (`by`)", "да: очарованный враг не атакует",
                "мастер эффектом со спасброском (эльф — с преимуществом)"),
    "deafened": ("да: провал проверок со слухом (`sense: hearing`)", "да: ничего не меняет в бою по 5e", "нет: враги не глохнут",
                 "мастер эффектом со спасброском"),
    "exhaustion": ("да: 6 степеней — помеха, скорость, помеха атакам и спасброскам, хиты, смерть", "да: те же степени", "нет",
                   "движок: марш больше 8 ч, сутки без сна, Неистовство; мастер — степенью; долгий отдых снимает всё"),
    "frightened": ("помеха проверкам", "да: помеха атакам; шаг к источнику (`by`) запрещён", "да: держится подальше, помеха",
                   "мастер эффектом со спасброском (полурослик — с преимуществом)"),
    "grappled": ("мастер решает о проверке", "да: скорость 0, «Вырваться» — действие", "да: не двигается", "мастер эффектом; атаки монстров — v0.7.9"),
    "incapacitated": ("да: проверки идут, мастер решает (v0.7.8)", "да: ход пропускается, концентрация прерывается", "да: пропускает ход",
                      "мастер эффектом; вне боя — только на время, движок его проматывает"),
    "invisible": ("да (v0.7.5): скрытность, кражи, голос", "да: преимущество, помеха по нему", "да (v0.7.8): там, где видели в последний раз, пока не ударит",
                  "заклинание"),
    "paralyzed": ("автопровал проверок, спасбросков Силы и Ловкости", "да: ход пропускается, преимущество врагам, авто-крит вплотную",
                  "да: авто-крит вплотную", "мастер эффектом со спасброском; упырь — v0.7.9"),
    "petrified": ("автопровал", "да: ход пропускается, сопротивление всему; навсегда — бой проигран", "нет",
                  "монстры — v0.7.9; мастер — только на время"),
    "poisoned": ("помеха проверкам", "да: помеха атакам", "да: помеха атакам",
                 "мастер эффектом со спасброском (дварф — с преимуществом); Противоядие снимает и даёт преимущество на час; яды монстров — v0.7.9"),
    "prone": ("мастер решает", "да: помеха своим атакам, преимущество ближним, помеха дальним; «Встать» — всё перемещение", "да: встаёт за ход",
              "мастер эффектом; без сознания — сам; волк — v0.7.9"),
    "restrained": ("помеха спасброскам Ловкости", "да: скорость 0, помеха своим атакам, преимущество врагам; «Вырваться» при `escape_dc`", "да",
                   "мастер эффектом; паутина и сети — v0.7.9"),
    "stunned": ("автопровал спасбросков Силы и Ловкости", "да: ход пропускается, преимущество врагам", "да", "мастер эффектом со спасброском"),
    "unconscious": ("автопровал", "да: 0 HP — спасброски от смерти; сон — ход пропускается, авто-крит вплотную, будит удар (`wake`)",
                    "да: просыпается от урона", "движок: 0 HP; мастер — сон на время (эльф магией не засыпает)"),
}
EXTRA_CONDITION_NAMES: dict[str, str] = {}
CONDITION_DURATIONS = ("у героя (v0.7.8) — эффект с источником и концом по игровым часам (раунд … 8 часов), до отдыха или до снятия, "
                       "повторный спасбросок в конце хода; у врага — раунды и повторный спасбросок (заклинания движка)")

# Damage to the hero (v0.7.8): every source of resistance a level 1–5 hero can have.
HERO_DAMAGE = [
    ("Сопротивление урону", "дварф (яд), тифлинг (огонь), драконорождённый (по предку), ярость (дробящий, колющий, рубящий), предметы `resist_*`, "
     "«Защита от яда», окаменение; «Защита от энергии» — v0.7.13 (нужен выбор стихии)", "engine"),
    ("Преимущество на спасброски", "дварф против яда, эльф и полуэльф против очарования, гном против магии (Инт, Мдр, Хар), полурослик против испуга, "
     "Противоядие; тег спасброска — у мастера обязателен", "engine"),
    ("Иммунитет к состоянию", "эльф — магический сон", "engine"),
    ("Ноль хитов", "без сознания, спасброски от смерти, мгновенная смерть от урона ≥ максимума", "engine"),
    ("Непреклонность полуорка", "1 хит вместо 0 раз за долгий отдых", "engine"),
    ("Концентрация", "спасбросок Телосложения от урона (Сл 10 или половина), конец по длительности, недееспособность, отдых", "engine"),
    ("Истощение", "марш, сутки без сна, Неистовство берсерка, мастер; голод и холод — с припасами и погодой", "engine"),
]

# Monster traits (v0.7.9): what the engine does with each (combat_rules.gd, monster_rules.gd) or why it stays with
# the master. Every trait of the imported monsters must be here.
_E = "engine"
_M = "master"
_FIELD = "передвижение и чувства, которых нет на линейном поле боя: мастер описывает в сцене"
_WATER = "вода и дыхание: поле боя их не знает, мастер в сцене"
_HIDE = "маскировка вне боя: мастер в сцене; засады встреч задаёт пакет"
_MIND = "речь, телепатия, облики: социальное и сюжетное — мастер"
_LIGHT = "свет: мастер в сцене (тьма — из времени суток)"
MONSTER_TRAITS = {
    "pack_tactics": (_E, "преимущество, когда союзник рядом с героем"),
    **{k: (_E, "+5 к пассивной Внимательности против скрытности героя") for k in
       ["keen_hearing", "keen_hearing_and_sight", "keen_hearing_and_smell", "keen_senses", "keen_sight", "keen_sight_and_smell", "keen_smell"]},
    "charge": (_E, "после сближения — лишний урон и спасбросок Силы против падения"),
    "pounce": (_E, "после сближения — спасбросок против падения и укус лежачего бонусом"),
    "trampling_charge": (_E, "после сближения — спасбросок против падения и удар лежачего бонусом"),
    "blood_frenzy": (_E, "преимущество по раненому герою"),
    "magic_resistance": (_E, "преимущество на спасброски от заклинаний героя"),
    "sunlight_sensitivity": (_E, "помеха на атаки днём вне помещений (`indoor` в пакете)"),
    "sunlight_weakness": (_E, "помеха на атаки днём вне помещений"),
    "reckless": (_E, "преимущество своим атакам вплотную и герою по нему"),
    "relentless": (_E, "раз за бой 1 HP вместо 0 от слабого удара"),
    "undead_fortitude": (_E, "спасбросок Тел 5 + урон — 1 HP вместо 0 (не от излучения и крита)"),
    "death_burst": (_E, "смерть рядом с героем — спасбросок, урон или ослепление"),
    "flyby": (_E, "герой не бьёт вдогонку, когда он улетает"),
    "nimble_escape": (_E, "вне досягаемости героя прячется бонусом — помеха по нему, преимущество его атаке"),
    "surprise_attack": (_E, "лишний урон в первом раунде по застигнутому герою"),
    "ambusher": (_E, "преимущество в первом раунде по застигнутому герою"),
    "martial_advantage": (_E, "лишний урон раз в ход, когда союзник рядом с героем"),
    "sneak_attack_1/turn": (_E, "лишний урон раз в ход с преимуществом или при союзнике рядом"),
    "aggressive": (_E, "лишнее движение к герою бонусом"),
    "dark_devotion": (_E, "преимущество на спасброски от очарования и страха"),
    "fey_ancestry": (_E, "преимущество против очарования, магический сон не действует"),
    "gnome_cunning": (_E, "преимущество на спасброски Инт, Мдр, Хар от магии"),
    "brave": (_E, "преимущество на спасброски от страха"),
    "duergar_resilience": (_E, "преимущество против заклинаний, яда, очарования и паралича"),
    "spellcasting": (_E, "заклинания, которые движок разрешает за героя, — ячейками; прочие не колдует"),
    "innate_spellcasting": (_E, "то же, с использованиями в день"),
    "brute": (_E, "лишняя кость урона уже в атаках SRD"),
    "amphibious": (_M, _WATER), "water_breathing": (_M, _WATER), "hold_breath": (_M, _WATER),
    "limited_amphibiousness": (_M, _WATER), "underwater_camouflage": (_M, _WATER),
    "false_appearance": (_M, _HIDE), "false_appearance_object_form_only": (_M, _HIDE), "stone_camouflage": (_M, _HIDE),
    "snow_camouflage": (_M, _HIDE), "shadow_stealth": (_M, _HIDE), "transparent": (_M, _HIDE),
    "spider_climb": (_M, _FIELD), "web_walker": (_M, _FIELD), "web_sense": (_M, _FIELD), "echolocation": (_M, _FIELD),
    "devils_sight": (_M, _FIELD), "blind_senses": (_M, _FIELD), "iron_scent": (_M, _FIELD), "labyrinthine_recall": (_M, _FIELD),
    "sure_footed": (_M, _FIELD), "standing_leap": (_M, _FIELD), "running_leap": (_M, _FIELD), "tree_stride": (_M, _FIELD),
    "ethereal_jaunt": (_M, _FIELD), "incorporeal_movement": (_M, _FIELD), "amorphous": (_M, _FIELD), "beast_of_burden": (_M, _FIELD),
    "shapechanger": (_M, _MIND), "mimicry": (_M, _MIND), "speak_with_beasts_and_plants": (_M, _MIND), "telepathic_bond": (_M, _MIND),
    "limited_telepathy": (_M, _MIND), "shark_telepathy": (_M, _MIND), "divine_eminence": (_M, _MIND),
    "illumination": (_M, _LIGHT), "ignited_illumination": (_M, _LIGHT), "variable_illumination": (_M, _LIGHT),
    "swarm": (_M, "рой бьётся как одно существо; сжатие и лечение роя — мастер"),
    "rampage": (_M, "соло-герой: после его падения кусать больше некого"),
    "antimagic_susceptibility": (_M, "антимагии в игре нет"),
    "steadfast": (_M, "не бывает испуган, пока видит союзника — мастер (страх на монстров накладывает только он и «Страх»)"),
    "two_headed": (_M, "преимущество на Внимательность и спасброски от части состояний — мастер"),
    "ooze_cube": (_M, "куб поглощает — мастер (решение v0.7.9)"),
    "adhesive_object_form_only": (_M, "прилипание в облике предмета — мастер"),
    "corrode_metal": (_M, "портит оружие и доспехи — предметы, v0.7.12"), "rust_metal": (_M, "портит оружие и доспехи — предметы, v0.7.12"),
    "heated_body": (_M, "жар при касании — мастер"), "heated_weapons": (_M, "раскалённое оружие — лишний урон в атаках SRD уже есть"),
    "stench": (_M, "вонь вокруг — отравление по сцене, мастер"),
    "petrifying_gaze": (_M, "взгляд окаменения (класс опасности выше боя v0.7.9) — мастер"),
    "aberrant_ground": (_M, "трудная местность — мастер"), "gibbering": (_M, "бормотание сводит с ума — мастер"),
    "consume_life": (_M, "поглощение жизни умирающих — мастер"), "ephemeral": (_M, "эфемерность — мастер"),
    "tail_spike_regrowth": (_M, "шипы отрастают за отдых — вне боя"), "confer_fire_resistance": (_M, "дарит сопротивление союзникам — их нет"),
    "grappler": (_M, "преимущество по схваченному — соло: мастер"), "turn_defiance": (_M, "против Изгнания нежити — v0.7.10"),
    "hellish_rejuvenation": (_M, "возрождение через сутки — сюжет мастера"), "cunning_action": (_M, "хитрое действие — ИИ движка его не использует, мастер"),
    "damage_transfer": (_M, "переносит урон на схваченного — мастер"), "horrific_appearance": (_M, "ужасный облик — страх по сцене, мастер"),
}

# Class features of levels 1–5 (classes and subclasses). Not listed — master only.
_creation = ("spellcasting_bard spellcasting_cleric spellcasting_druid spellcasting_paladin spellcasting_ranger spellcasting_sorcerer "
             "spellcasting_wizard bard_expertise_1 rogue_expertise_1 bonus_cantrip bonus_proficiency arcane_tradition bard_college divine_domain "
             "druid_circle martial_archetype monastic_tradition otherworldly_patron primal_path ranger_archetype roguish_archetype sacred_oath "
             "sorcerous_origin barbarian_ability_score_improvement_1 bard_ability_score_improvement_1 cleric_ability_score_improvement_1 "
             "druid_ability_score_improvement_1 fighter_ability_score_improvement_1 monk_ability_score_improvement_1 "
             "paladin_ability_score_improvement_1 ranger_ability_score_improvement_1 rogue_ability_score_improvement_1 "
             "sorcerer_ability_score_improvement_1 warlock_ability_score_improvement_1 wizard_ability_score_improvement_1")
FEATURES = {
    **{f: ("creation", "выбор при создании или повышении уровня") for f in _creation.split()},
    "barbarian_unarmored_defense": ("engine", "КД"), "monk_unarmored_defense": ("engine", "КД"), "draconic_resilience": ("engine", "КД и хиты"),
    "jack_of_all_trades": ("engine", "половина бонуса к проверкам"), "sneak_attack": ("engine", "бой"), "cunning_action": ("engine", "бонусное действие в бою"),
    "extra_attack_1": ("engine", "бой"), "barbarian_extra_attack": ("engine", "бой"), "monk_extra_attack": ("engine", "бой"),
    "paladin_extra_attack": ("engine", "бой"), "ranger_extra_attack": ("engine", "бой"), "pact_magic": ("engine", "ячейки на коротком отдыхе"),
    "second_wind": ("engine", "лечение"), "lay_on_hands": ("engine", "лечение"), "font_of_inspiration": ("engine", "восстановление на коротком отдыхе"),
    "fighter_fighting_style": ("partial", "работают стрельба, защита, дуэлянт, бой двумя оружиями; нет — большое оружие, защита союзника"),
    "ranger_fighting_style": ("partial", "работают стрельба, защита, дуэлянт, бой двумя оружиями"),
    "paladin_fighting_style": ("partial", "работают защита и дуэлянт; нет — большое оружие, защита союзника"),
    "rage": ("partial", "бонус к урону, сопротивление оружию (v0.7.8); нет — преимущества на Силу, конца ярости без атак"),
    "frenzy": ("engine", "удар бонусным действием в ярости, после боя — истощение (v0.7.8)"),
    "action_surge_1_use": ("partial", "заряд тратится; лишнее действие — проверить"),
    "bardic_inspiration_d6": ("partial", "заряд тратится, кость к броску не добавляется"),
    "bardic_inspiration_d8": ("partial", "заряд тратится, кость к броску не добавляется"),
    "channel_divinity": ("partial", "заряд тратится, действие — у мастера"), "channel_divinity_1_rest": ("partial", "заряд тратится, действие — у мастера"),
    "wild_shape_cr_1_4_or_below_no_flying_or_swim_speed": ("partial", "заряд тратится, облика зверя в движке нет"),
    "wild_shape_cr_1_2_or_below_no_flying_speed": ("partial", "заряд тратится, облика зверя в движке нет"),
    "ki": ("partial", "очки тратятся, приёмы (Шквал, Терпеливая оборона, Шаг ветра, Оглушающий удар) — у мастера"),
    "divine_sense": ("partial", "заряд тратится, действие — у мастера"), "font_of_magic": ("partial", "очки тратятся, обмен на ячейки — у мастера"),
    "arcane_recovery": ("partial", "заряд тратится, ячейки — проверить"),
}

# Race traits.
TRAITS = {
    "darkvision": ("engine", "ночью вне освещённых мест; в бою и подземельях — нет"), "dwarven_toughness": ("engine", "хиты"),
    "infernal_legacy": ("engine", "заговор; заклинания 3–5 уровня — проверить"), "menacing": ("creation", "навык"), "keen_senses": ("creation", "навык"),
    "skill_versatility": ("creation", "навыки"), "dwarven_combat_training": ("creation", "владение оружием"), "elf_weapon_training": ("creation", "владение оружием"),
    "tool_proficiency": ("creation", "инструмент"), "tinker": ("partial", "инструмент; устройства — у мастера"), "high_elf_cantrip": ("creation", "заговор"),
    "extra_language": ("creation", "язык (сам язык ни на что не влияет)"),
    "draconic_ancestry": ("partial", "сопротивление по предку (v0.7.8); оружие дыхания — v0.7.10"),
    "damage_resistance": ("engine", "сопротивление по драконьему предку (v0.7.8)"),
    "dwarven_resilience": ("engine", "сопротивление яду, преимущество на спасброски от яда (v0.7.8)"),
    "hellish_resistance": ("engine", "сопротивление огню (v0.7.8)"),
    "fey_ancestry": ("engine", "преимущество против очарования, магический сон не действует (v0.7.8)"),
    "gnome_cunning": ("engine", "преимущество на спасброски Инт, Мдр, Хар против магии (v0.7.8)"),
    "brave": ("engine", "преимущество на спасброски от страха (v0.7.8)"),
    "relentless_endurance": ("engine", "1 хит вместо 0 раз за долгий отдых (v0.7.8)"),
}
TRAITS.update({f"draconic_ancestry_{c}": TRAITS["draconic_ancestry"] for c in
               "white silver red green gold copper bronze brass blue black".split()})

# Item properties (items.json `properties`): what the engine reads.
ITEM_PROPS = {
    "finesse": ("engine", "Сила или Ловкость, Скрытая атака"), "light": ("engine", "второе оружие"), "two_handed": ("engine", "без щита"),
    "versatile": ("engine", "двумя руками"), "thrown": ("engine", "метание"), "heavy": ("partial", "кражи; помеха маленьким расам — нет"),
    "reach": ("partial", "поле по колонкам 30 футов — досягаемость 10 футов ничего не меняет"), "ammunition": ("none", "стрелы и болты не тратятся"),
    "silvered": ("none", "сопротивление оборотней не снимается"), "magic_plus1": ("engine", "атака и урон"), "magic_plus2": ("engine", "атака и урон"),
    "magic_plus3": ("engine", "атака и урон"), "ac_plus1": ("engine", "КД"), "ac_plus2": ("engine", "КД"), "saves_plus1": ("engine", "спасброски"),
    "stealth_advantage": ("engine", "Скрытность"), "light_source": ("engine", "ночь"), "healing": ("engine", "зелья лечения"),
    "fire_damage": ("none", "лишний урон огнём (Алхимический огонь — нет и броска)"), "cold_damage": ("none", "лишний урон"),
    "lightning_damage": ("none", "лишний урон"), "radiant_damage": ("none", "лишний урон (Святая вода — нет и броска)"),
    "necrotic_damage": ("none", "лишний урон"), "poison_damage": ("none", "лишний урон"),
    "resist_fire": ("engine", "сопротивление огню, пока вещь надета или при себе (v0.7.8)"), "resist_cold": ("engine", "сопротивление холоду (v0.7.8)"),
    "resist_poison": ("engine", "сопротивление яду (v0.7.8)"), "cursed": ("none", "проклятие ни на что не влияет"),
}

# Languages, backgrounds, tools (v0.7.11).
SOCIAL = [
    ("Языки героя", "выбираются при создании и лежат в листе; мастеру не передаются, движок их не читает", "none"),
    ("Языки NPC и монстров", "в пакете у NPC языков нет; у монстров SRD они есть в источнике, но при импорте отброшены", "none"),
    ("Разговор без общего языка", "сейчас с кем угодно говорят на всеобщем: гоблин понимает и поддаётся убеждению", "none"),
    ("Особенность предыстории", "«Убежище верующих», «Военный чин», «Связь с преступным миром» и др. — только текст в листе", "master"),
    ("Владение инструментами", "выбираются при создании; проверка движка берёт только навык или спасбросок — воровские инструменты для замка ничего не дают", "none"),
    ("Воровской жаргон, Друидический", "тайные языки — нигде", "none"),
]

# Things a test checks against the 5e rules: id → test. Fill in as the work goes.
CHECKED: dict[str, str] = {
    **{c: "test_conditions_v078.gd" for c in ["blinded", "charmed", "deafened", "exhaustion", "frightened", "grappled", "incapacitated",
                                               "invisible", "paralyzed", "petrified", "prone", "unconscious"]},
    "poisoned": "test_conditions_v078.gd, test_rules_v060.gd",
    **{t: "test_conditions_v078.gd" for t in ["damage_resistance", "dwarven_resilience", "hellish_resistance", "fey_ancestry", "gnome_cunning",
                                               "brave", "relentless_endurance", "frenzy"]},
    "resist_fire": "test_conditions_v078.gd", "resist_cold": "test_conditions_v078.gd", "resist_poison": "test_conditions_v078.gd",
}


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def mark(status: str) -> str:
    return STATUS[status]


def class_features(classes: dict) -> dict[str, list[str]]:
    """Feature id → the classes and subclasses that get it at levels 1–5."""
    out: dict[str, list[str]] = {}
    for cid, c in classes["classes"].items():
        for lvl, row in c["levels"].items():
            if int(lvl) <= 5:
                for f in row.get("features", []):
                    out.setdefault(f, []).append(c["name"])
    for sid, s in classes["subclasses"].items():
        for lvl, fl in (s.get("features") or {}).items():
            if int(lvl) <= 5:
                for f in fl:
                    out.setdefault(f, []).append(s.get("name", sid))
    return out


def engine_riders(monsters: dict) -> tuple[list[tuple[str, str, str, str]], int, int, int]:
    """Attack effects of the imported monsters (v0.7.9): rows (monster, action, what, status) and how many monsters have
    one in the engine, at the master on purpose."""
    rows = []
    engine = master = 0
    for mid, m in sorted(monsters.items(), key=lambda kv: kv[1]["name"]):
        e = ms = False
        for a in m["actions"]:
            fx = a.get("effect", {})
            what = ", ".join(x for x in [
                fx.get("condition", ""), ("+ " + fx["also"]) if fx.get("also") else "",
                ("урон " + fx["damage"]["dice"] + " " + fx["damage"]["type"]) if fx.get("damage") else "",
                ("спасбросок " + fx["save"]["ability"] + " " + str(fx["save"]["dc"])) if fx.get("save") else "",
                ("вырваться " + str(fx["escape_dc"])) if fx.get("escape_dc") else "", "повтор" if fx.get("repeat") else "",
                "высасывание" if fx.get("drain") else "", "паралич при 0 HP" if fx.get("zero_hp_paralyzed") else "",
                ("перезарядка " + str(a["recharge"])) if a.get("recharge") else ""] if x)
            if a.get("master_effect"):
                rows.append((m["name"], a["name"], a["master_effect"], "master"))
                ms = True
            elif fx.get("condition") or fx.get("damage") or fx.get("drain") or fx.get("zero_hp_paralyzed"):
                rows.append((m["name"], a["name"], what, "engine"))
                e = True
        engine += e
        master += ms and not e
    riders_json = load(ROOT / "tools" / "srd" / "riders.json")
    seen = {(r[0], r[1]) for r in rows}
    for key, spec in riders_json.items():  # actions the engine does not take at all (swallow, rust): the reason stays
        if not isinstance(spec, dict) or not spec.get("master"):
            continue
        mid, action = key.split(":", 1)
        m = monsters.get(mid.replace("-", "_"))
        if m and not any(a["name_en"] == action for a in m["actions"]):
            rows.append((m["name"], action, spec["master"], "master"))
            master += 1
    return rows, engine, master, len(rows)


def monster_riders() -> tuple[Counter, int, int, int, int]:
    """Attack riders (conditions, extra save damage) of the imported monsters, spellcasters, reactions — SRD source."""
    cond = re.compile(r"\b(poisoned|paralyzed|prone|grappled|restrained|frightened|charmed|stunned|blinded|incapacitated|unconscious|petrified)\b")
    riders: Counter = Counter()
    with_riders = casters = reactions = n = 0
    for p in sorted((SRD / "monsters").glob("*.json")):
        m = load(p)
        if m["challenge_rating"] > MAX_MONSTER_CR:
            continue
        n += 1
        hit = False
        for a in m.get("actions", []):
            d = a.get("desc", "")
            if a.get("attack_bonus") is None:
                continue
            found = set(cond.findall(d))
            if found or "saving throw" in d:
                hit = True
                riders.update(found or {"extra_save_damage"})
        with_riders += hit
        names = [t["name"] for t in m.get("special_abilities", [])] + [a["name"] for a in m.get("actions", [])]
        casters += any("Spellcasting" in x for x in names)
        reactions += bool(m.get("reactions"))
    return riders, with_riders, casters, reactions, n


def main() -> int:
    rules = load(DATA / "rules.json")
    classes = load(DATA / "srd" / "classes.json")
    races = load(DATA / "srd" / "races.json")
    monsters = load(DATA / "srd" / "monsters.json")
    spells = load(DATA / "srd" / "spells.json")
    backgrounds = load(DATA / "srd" / "backgrounds.json")
    items = load(DATA / "items.json")

    feats = class_features(classes)
    unknown = [f for f in FEATURES if f not in classes["features"]] + [t for t in TRAITS if t not in races["traits"]] \
        + [p for p in ITEM_PROPS if p not in items["properties"]] + [p for p in items["properties"] if p not in ITEM_PROPS]
    if unknown:
        raise SystemExit(f"stale ids in rules_audit.py: {', '.join(unknown)}")

    summary: list[tuple[str, int, int, int]] = []  # title, total, works (engine + creation), missing
    out: list[str] = []

    def section(title: str, version: str, rows: list[tuple[str, ...]], header: list[str], note: str = "") -> None:
        out.extend(["", f"## {title}", "", f"План — [роадмап {version}](roadmap.md#правила-5e)." + (f" {note}" if note else ""), ""])
        out.append("| " + " | ".join(header) + " |")
        out.append("|" + "---|" * len(header))
        out.extend("| " + " | ".join(r) + " |" for r in rows)

    # Conditions.
    srd_conditions = sorted(load(SRD / "conditions.json")["results"], key=lambda c: c["index"])
    rows = []
    for c in srd_conditions:
        cid = c["index"]
        name = str(rules["conditions"].get(cid, EXTRA_CONDITION_NAMES.get(cid, c["name"]))).split(":")[0]
        rows.append((name, f"`{cid}`", *CONDITIONS[cid]))
    section("Состояния", "v0.7.8", rows, ["Состояние", "id", "Вне боя: проверки", "Бой: на герое", "Бой: на враге", "Кто накладывает на героя"],
            f"Длительность: {CONDITION_DURATIONS}.")
    summary.append(("Состояния (15 по SRD)", len(rows), sum(1 for r in CONDITIONS.values() if r[1].startswith("да")), sum(1 for r in CONDITIONS.values() if r[1] == "нет")))

    section("Урон по герою", "v0.7.8", [(a, b, mark(s)) for a, b, s in HERO_DAMAGE], ["Что", "Источники", "Сейчас"])
    summary.append(("Урон по герою", len(HERO_DAMAGE), sum(1 for *_, s in HERO_DAMAGE if s == "engine"), sum(1 for *_, s in HERO_DAMAGE if s in MISSING)))

    # Monsters.
    riders, with_riders, casters, reactions, n_src = monster_riders()
    traits = Counter(t["id"] for m in monsters.values() for t in m["traits"])
    names = {t["id"]: t["name"] for m in monsters.values() for t in m["traits"]}
    stale = [t for t in traits if t not in MONSTER_TRAITS]
    if stale:
        raise SystemExit(f"monster traits without a status in rules_audit.py: {', '.join(stale)}")
    rows = [(names[t], f"`{t}`", str(k), mark(MONSTER_TRAITS[t][0]), MONSTER_TRAITS[t][1], CHECKED.get(t, "")) for t, k in traits.most_common()]
    r_rows, r_engine, r_master, r_count = engine_riders(monsters)
    with_casting = sum(1 for m in monsters.values() if m.get("spellcasting"))
    with_parry = sum(1 for m in monsters.values() if any(r.get("ac") for r in m.get("reactions", [])))
    section("Монстры", "v0.7.9", rows, ["Особенность", "id", "Монстров", "Сейчас", "Что именно", "Проверено"],
            f"В движке {len(monsters)} монстров (класс опасности ≤ {MAX_MONSTER_CR}; в источнике SRD таких {n_src}). "
            f"Эффекты атак (v0.7.9, разбор текста SRD и `tools/srd/riders.json`): у {r_engine} монстров — в движке, у {r_master} — осознанно у мастера; "
            f"в источнике эффекты есть у {with_riders}. Колдующих монстров {with_casting} (в источнике {casters}): заклинания, которые движок "
            f"разрешает за героя, — с ячейками и использованиями. Реакции: Парирование у {with_parry} (в источнике реакции у {reactions}; "
            f"прочие — M4). Языки монстров — в данных, для v0.7.11. Особенностей {len(traits)} видов:")
    out.append("")
    out.append("### Эффекты атак монстров")
    out.append("")
    out.append("| Монстр | Действие | Что | Сейчас |")
    out.append("|---|---|---|---|")
    out.extend(f"| {a} | {b} | {c} | {mark(d)} |" for a, b, c, d in r_rows)
    st = Counter(MONSTER_TRAITS[t][0] for t in traits)
    summary.append(("Особенности монстров", len(traits), st["engine"], st["master"] + st["none"]))
    summary.append(("Эффекты атак монстров", r_count, sum(1 for *_, d in r_rows if d == "engine"), sum(1 for *_, d in r_rows if d != "engine")))

    # Class features.
    rows = []
    for f in sorted(feats, key=lambda x: classes["features"][x]["name"]):
        st, what = FEATURES.get(f, ("master", ""))
        rows.append((classes["features"][f]["name"], f"`{f}`", ", ".join(sorted(set(feats[f]))), mark(st), what, CHECKED.get(f, "")))
    section("Особенности классов (1–5 уровень)", "v0.7.10", rows, ["Особенность", "id", "Класс", "Сейчас", "Что именно", "Проверено"])
    st = Counter(FEATURES.get(f, ("master",))[0] for f in feats)
    summary.append(("Особенности классов", len(feats), st["engine"] + st["creation"], st["master"] + st["none"]))

    # Race traits.
    rows = []
    for t, d in sorted(races["traits"].items(), key=lambda kv: kv[1]["name"]):
        s, what = TRAITS.get(t, ("master", ""))
        rows.append((d["name"], f"`{t}`", mark(s), what, CHECKED.get(t, "")))
    section("Черты рас", "v0.7.10", rows, ["Черта", "id", "Сейчас", "Что именно", "Проверено"])
    st = Counter(TRAITS.get(t, ("master",))[0] for t in races["traits"])
    summary.append(("Черты рас", len(races["traits"]), st["engine"] + st["creation"], st["master"] + st["none"]))

    # Languages, backgrounds, tools.
    bg = ", ".join(f"{b['name']} — «{b['feature']['name']}»" for b in backgrounds.values())
    section("Языки, предыстории, инструменты", "v0.7.11", [(a, b, mark(s)) for a, b, s in SOCIAL], ["Что", "Сейчас", ""],
            f"Особенности предысторий: {bg}.")
    summary.append(("Языки, предыстории, инструменты", len(SOCIAL), 0, sum(1 for *_, s in SOCIAL if s in MISSING)))

    # Items.
    cat = items["catalog"]
    with_prop = Counter(p for v in cat.values() for p in v.get("properties", []))
    magic = sum(1 for v in cat.values() if v.get("rarity") and v["rarity"] != "common")
    srd_magic = len(load(SRD / "magic-items.json")["results"])
    rows = [(f"`{p}`", str(items["properties"][p]), str(with_prop.get(p, 0)), mark(ITEM_PROPS[p][0]), ITEM_PROPS[p][1]) for p in items["properties"]]
    section("Предметы", "v0.7.12", rows, ["Свойство", "Очки редкости", "Предметов в каталоге", "Сейчас", "Что именно"],
            f"В каталоге {len(cat)} предметов, магических {magic} (оружие и доспехи +1, Плащ защиты, Сапоги эльфов, зелья) из {srd_magic} магических предметов SRD. "
            "Свойства — и словарь предметов, которые создаёт мастер: за свойство «нет нигде» он платит очки редкости, а предмет ничего не делает.")
    st = Counter(v[0] for v in ITEM_PROPS.values())
    summary.append(("Свойства предметов", len(ITEM_PROPS), st["engine"], st["none"]))

    # Spells.
    engine = set(rules["combat"]["engine_spells"])
    conditions = set(rules["combat"]["condition_spells"]) - {"_doc"}
    invisibility = set(rules.get("invisibility", {}).get("spells", {}))
    group_of = {sid: g for g, ids in SPELL_ASSIGN.items() for sid in ids.split()}
    playable = {k: v for k, v in spells.items() if int(v.get("level", 0)) <= 3}

    def spell_status(sid: str) -> str:
        if sid in engine:
            return "движок: урон / лечение"
        if sid in conditions:
            return "движок: состояния"
        if sid in invisibility:
            return "движок: невидимость"
        return STATUS["master"]

    unassigned = sorted(sid for sid in playable if spell_status(sid) == STATUS["master"] and sid not in group_of)
    if unassigned:
        raise SystemExit(f"no group for: {', '.join(unassigned)}")
    master = sum(1 for sid in playable if spell_status(sid) == STATUS["master"])
    groups = "; ".join(f"{SPELL_GROUPS[g][0]} — {sum(1 for sid in playable if group_of.get(sid) == g and spell_status(sid) == STATUS['master'])}"
                       for g in SPELL_GROUPS)
    rows = []
    for sid, v in sorted(playable.items(), key=lambda kv: (int(kv[1].get("level", 0)), kv[1]["name"])):
        g = SPELL_GROUPS[group_of[sid]][0] if sid in group_of else "—"
        rows.append((v["name"], f"`{sid}`", str(v.get("level", 0)), "да" if v.get("concentration") else "", spell_status(sid), g, CHECKED.get(sid, "")))
    section("Заклинания (круги 0–3)", "v0.7.13", rows, ["Заклинание", "id", "Круг", "Конц.", "Сейчас", "Группа", "Проверено"],
            f"Доступно героям 1–5 уровня {len(playable)}; движок разрешает {len(playable) - master}; **{master} — только мастер**: ячейка и "
            f"концентрация тратятся, остальное — лишь в рассказе. По группам: {groups}.")
    summary.append(("Заклинания", len(playable), len(playable) - master, master))

    head = [
        "# Аудит правил 5e",
        "",
        "Генерируется: `python tools/rules_audit.py`. План — серия версий [«Правила 5e»](roadmap.md#правила-5e) (v0.7.8–v0.7.13). "
        "Числа — из данных; статусы — по чтению движка (`game/core`), их правят в `tools/rules_audit.py` вместе с работой.",
        "",
        "Статусы: **движок** — правило считает движок; **при создании** — выдаётся при создании или повышении уровня (навык, владение, заговор); "
        "**частично** — что-то работает, что именно — в колонке; **только мастер** — существует лишь в рассказе; **нет нигде** — ни движок, ни мастер этого не знают.",
        "",
        "| Что | Всего | Работает | Только мастер или нет нигде |",
        "|---|---|---|---|",
        *[f"| {t} | {n} | {w} | {m} |" for t, n, w, m in summary],
    ]
    OUT.write_text("\n".join(head + out) + "\n", encoding="utf-8")
    print(OUT)
    for t, n, w, m in summary:
        print(f"  {t}: {n} total, {w} work, {m} missing")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
