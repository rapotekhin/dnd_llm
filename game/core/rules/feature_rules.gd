class_name FeatureRules
extends RefCounted
## Class features and race traits in the engine (roadmap v0.7.10 «Правила 5e: особенности классов и черты рас»; the
## author: «как в Baldur's Gate 3»). Anybody with a class or a race has them (v0.8.4.9, ADR-0016): a fighter's record carries the
## hero's fields (`give_class`), the rules read its holder and `core/acts/feature.gd` is the one act. Only the hero is asked:
## - prompts of the hero's own turn (`s.combat.prompt`): Divine Smite after a melee hit (a slot to spend), the beast of
##   Wild Shape, Font of Magic; the player answers (GameState.combat_answer) or the policy decides;
## - reactions to a foe's hit (`reactions` / `apply_reaction`): Uncanny Dodge, Deflect Missiles, Cutting Words, Giant
##   Killer — asked when `s.settings.reactions` is "ask" (the engine stops the foe's turn, CombatRules.answer_reaction
##   goes on), used by themselves with "always", never with "never" (tests and the balance sim: "always"); the others answer
##   through `Acts.react`;
## - actions of the features tab (`actions`, `why`, `run`): Reckless Attack, Martial Arts and the ki techniques
##   (Flurry of Blows and the Open Hand variants, Patient Defense, Step of the Wind, Stunning Strike), Channel Divinity
##   (Turn Undead, Turn the Unholy, Sacred Weapon, Preserve Life), Wild Shape and its end, Font of Magic, the
##   dragonborn's Breath Weapon;
## - what a hit brings (`hit_extras`, `after_hit`): Colossus Slayer, Savage Attacks, Divine Smite, Stunning Strike,
##   Open Hand, Horde Breaker; Bardic Inspiration as a die the hero adds to a failed roll (house rule, ADR-0010 §6в);
## - metamagic (`metamagic` of the fighter), the rest of Rage (STR advantage, the end without attacks, heavy armour), Danger
##   Sense, Lucky, Dark One's Blessing (temporary HP).
## Data — rules.json `class_features`. Pure: randomness from s.rng.

const OPEN_HAND := ["topple", "push", "stagger"]


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["class_features"]


## What happens to a reaction or a prompt of `who`: "ask" (the player is asked), "always", "never".
static func policy(s: GameSession, who: Dictionary = Sheet.HERO) -> String:
	return str(s.settings.get("reactions", "always")) if Sheet.is_hero(who) else "always"


static func has(c: Dictionary, id: String) -> bool:
	return CharacterRules.has_feature(c, id)


static func level(c: Dictionary) -> int:
	return int(c.get("level", 1))


static func ab_mod(c: Dictionary, ab: String) -> int:
	return CharacterRules.mod(CharacterRules.ability(c, ab))


## The fight's own record of `who`.
static func _fighter(s: GameSession, who: Dictionary) -> Dictionary:
	return CombatRules.player(s) if Sheet.is_hero(who) else who


## What a fighter brings from its character: the class of the encounter or of the NPC, or of its template (`rules.combat.classed`),
## the traits of its race. The fields are the hero's, so whatever reads a holder reads this one too.
static func give_class(data: Dictionary, f: Dictionary, spec: Dictionary) -> void:
	var npc: Dictionary = data["world"]["npcs"].get(str(spec.get("npc_id", "")), {})
	var row: Dictionary = spec if spec.has("class") else npc if npc.has("class") else CombatRules.cfg(data)["classed"].get(str(f["monster"]), {})
	var m := Sheet.template(data, f)
	if row.has("class"):
		f["class"] = str(row["class"])
		f["subclass"] = str(row.get("subclass", ""))
		f["level"] = int(row.get("level", 1))
		var feats: Array = []
		for lv in range(1, int(f["level"]) + 1):
			feats.append_array(LevelUp.features_at(f, data, lv, str(f["subclass"])))
		f["features"] = feats
		if not m.has("spellcasting"):
			f["slots_max"] = CharacterRules.slots_max(f, data)
	var word := str(npc.get("race", "")).to_lower()
	for id: String in data["races"]["races"]:
		if not word.is_empty() and str(data["races"]["races"][id].get("name", "")).to_lower() == word:
			f["traits"] = CharacterBuilder.race_traits({"race": id}, data)
	if f.has("class") or f.has("traits"):
		f["abilities"] = (m["abilities"] as Dictionary).duplicate()


# --- rolls ---------------------------------------------------------------------------------------


## Bardic Inspiration the hero keeps (a house rule: in a solo game the bard inspires themself): the die, 0 when none.
static func inspiration_die(c: Dictionary) -> int:
	for e: Dictionary in ConditionRules.effects(c):
		if int(e.get("inspiration", 0)) > 0:
			return int(e["inspiration"])
	return 0


## A failed d20 roll gets the inspiration die (it is spent). Returns the bonus, 0 when there is none.
static func use_inspiration(s: GameSession, who: Dictionary = Sheet.HERO) -> int:
	var c := Sheet.holder(s, who)
	for e: Dictionary in ConditionRules.effects(c):
		if int(e.get("inspiration", 0)) > 0:
			ConditionRules.remove_effect(c, int(e["uid"]))
			return s.rng.randi_range(1, int(e["inspiration"]))
	return 0


# --- weapons --------------------------------------------------------------------------------------


## A monk weapon (5e): shortswords and simple melee weapons without two-handed or heavy; "" — unarmed.
static func monk_weapon(def: Dictionary) -> bool:
	var w: Dictionary = def.get("weapon", {})
	var props: Array = def.get("properties", [])
	if def.is_empty():
		return true
	if str(def.get("name_en", "")) == "Shortsword":
		return true
	return str(w.get("category", "")) == "simple" and str(w.get("range", "melee")) != "ranged" and not props.has("two_handed") and not props.has("heavy")


## The Martial Arts die of the monk's level, "" without the feature.
static func martial_die(c: Dictionary, data: Dictionary) -> String:
	if not has(c, "martial_arts"):
		return ""
	var ma: Dictionary = CharacterRules.level_row(c, data).get("class_specific", {}).get("martial_arts", {})
	return "%dd%d" % [int(ma.get("dice_count", 1)), int(ma.get("dice_value", 4))]


static func crit_min(c: Dictionary) -> int:
	return 19 if has(c, "improved_critical") else 20


static func great_weapon(c: Dictionary) -> bool:
	for f: Variant in c.get("features", []):
		if str(f).ends_with("great_weapon_fighting"):
			return true
	return false


## A melee weapon of the Blade pact: the warlock is proficient with any.
static func pact_blade(c: Dictionary) -> bool:
	return has(c, "pact_of_the_blade")


## What `f`'s class does to a blow before the roll: Sacred Weapon, Rage, Sneak Attack, its critical range. A copy of `b`; `m` — the
## reasons of advantage and disadvantage of this blow.
static func armed(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary, m: Dictionary) -> Dictionary:
	var c := Sheet.holder(s, f)
	var out := b.duplicate()
	f["rage_kept"] = true
	if int(f.get("sacred_weapon", 0)) > 0:
		out["to_hit"] = int(b["to_hit"]) + maxi(1, ab_mod(c, "cha"))
	out["bonus"] = int(b.get("bonus", 0)) + rage_bonus(s, data, f, b, t)
	if not out.has("crit_min"):
		out["crit_min"] = crit_min(c)
	var sneak := sneak_dice(s, data, f, b, not (m["adv"] as Array).is_empty(), not (m["dis"] as Array).is_empty(), t)
	if not sneak.is_empty():
		out["extra"] = sneak
		out["extra_name"] = "Скрытая атака"
	return out


static func rage_bonus(s: GameSession, data: Dictionary, f: Dictionary, b: Dictionary, t: Dictionary) -> int:
	if not bool(b.get("melee", false)) or not bool(f.get("raging", false)) or FightGrid.dist(f, t) > maxi(1, int(b.get("reach", 1))):
		return 0
	return int(CharacterRules.level_row(Sheet.holder(s, f), data).get("class_specific", {}).get("rage_damage_bonus", 2))


## The dice of Sneak Attack on this blow, "" when it gives none. A template's own Sneak Attack is in `MonsterRules.extra_on_hit`.
static func sneak_dice(s: GameSession, data: Dictionary, f: Dictionary, b: Dictionary, adv: bool, dis: bool, t: Dictionary = {}) -> String:
	var c := Sheet.holder(s, f)
	if not has(c, "sneak_attack") or MonsterRules.has_trait(data, f, "sneak_attack_1/turn") or dis or bool(CombatRules.points(s, data, f).get("sneak", false)):
		return ""
	if not _finesse(s, data, b) or not (adv or (not t.is_empty() and CombatRules.friends_of(s, f).any(func(id: String) -> bool: return id != str(f["id"]) and FightGrid.touching(CombatRules.fighter(s, id), t)))):
		return ""
	var sa: Dictionary = CharacterRules.level_row(c, data).get("class_specific", {}).get("sneak_attack", {})
	return "%dd%d" % [int(sa.get("dice_count", 1)), int(sa.get("dice_value", 6))]


## A shot or a finesse weapon: of the hand, or the weapon a template's action is named after.
static func _finesse(s: GameSession, data: Dictionary, b: Dictionary) -> bool:
	if not bool(b.get("melee", false)):
		return true
	var id := str(b["act"].get("item", "")) if b.has("act") else str(b.get("id", ""))
	return (ItemRules.def_of(data["items"], s.items, id).get("properties", []) as Array).has("finesse")


## Extra dice of a weapon hit besides Sneak Attack: Colossus Slayer (once a turn on a wounded foe), Savage Attacks (a melee crit).
## {"dice": "1d8+1d10", "notes": [..]}.
static func hit_extras(s: GameSession, data: Dictionary, f: Dictionary, b: Dictionary, t: Dictionary, crit: bool) -> Dictionary:
	var c := Sheet.holder(s, f)
	var it := Sheet.holder(s, t)
	var dice: Array[String] = []
	var notes: Array[String] = []
	var e := CombatRules.points(s, data, f)
	if has(c, "hunters_prey_colossus_slayer") and int(it.get("hp", 0)) < int(it.get("max_hp", 0)) and not bool(e.get("colossus", false)):
		e["colossus"] = true
		dice.append("1d8")
		notes.append("Убийца колоссов")
	var pieces: Array = b.get("pieces", [])
	if crit and bool(b.get("melee", false)) and not pieces.is_empty() and Sheet.has_trait(s, data, f, "savage_attacks"):
		dice.append(str(pieces[0]["dice"]).get_slice("+", 0).replace("2d", "1d"))
		notes.append("Свирепые атаки")
	return {"dice": "+".join(dice), "notes": notes}


# --- what a hit brings ----------------------------------------------------------------------------


## After a weapon hit: Stunning Strike, an Open Hand technique (opts), Divine Smite as a prompt of the hero (or by the policy). Lines.
static func after_hit(s: GameSession, data: Dictionary, f: Dictionary, b: Dictionary, t: Dictionary, crit: bool, opts: Dictionary, lines: Array[String]) -> void:
	var c := Sheet.holder(s, f)
	var it := str(Sheet.holder(s, t).get("name", ""))
	if not Attack.up(s, t):
		return
	if bool(opts.get("stunning", false)) and Stock.left(c, data, "ki") > 0:
		Stock.use(c, data, "ki", 1, s.rng)
		var dc := ki_dc(c, data)
		var ok := Sheet.saved(s, data, t, "con", dc)
		lines.append("Оглушающий удар: %s — спасбросок Тел против Сл %d — %s" % [it, dc, "устоял" if ok else "ошеломлён"])
		if not ok and not CombatRules.immune_to(data, t, "stunned"):
			CombatRules._add_condition(s, data, t, "stunned", {"rounds": 1})
	var oh := str(opts.get("open_hand", ""))
	if not oh.is_empty():
		_open_hand(s, data, f, t, oh, lines)
	if bool(b.get("melee", false)) and has(c, "divine_smite") and not smite_slots(c).is_empty():
		var pol := policy(s, f)
		if pol == "ask":
			var options: Array[Dictionary] = []
			for lv: int in smite_slots(c):
				options.append({"id": "smite_%d" % lv, "label": "Кара ячейкой %d круга (%s)" % [lv, smite_dice(data, t, lv, crit).replace("d", "к")]})
			options.append({"id": "none", "label": "Не карать"})
			s.combat["prompt"] = {"kind": "smite", "target": str(t["id"]), "crit": crit, "options": options,
				"text": "Божественная кара: %s — удар попал." % it}
		elif pol == "always":
			lines.append_array(_smite(s, data, t, int(smite_slots(c)[0]), crit, f))


static func ki_dc(c: Dictionary, data: Dictionary) -> int:
	return 8 + CharacterRules.prof_bonus(c, data) + ab_mod(c, "wis")


static func smite_slots(c: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for lv in range(1, 6):
		if SpellRules.slots_left(c, lv) > 0:
			out.append(lv)
	return out


static func smite_dice(data: Dictionary, t: Dictionary, slot: int, crit: bool) -> String:
	var n := mini(5, 1 + slot)
	if str(Sheet.template(data, t).get("type", "")) in ["undead", "fiend"]:
		n += 1
	return "%dd8" % (n * (2 if crit else 1))


static func _smite(s: GameSession, data: Dictionary, t: Dictionary, slot: int, crit: bool, who: Dictionary = Sheet.HERO) -> Array[String]:
	Stock.spend(Sheet.holder(s, who), "slot_%d" % slot)
	var dmg := Sheet.taken(s, data, t, "radiant", CombatRules.roll_dice(s.rng, smite_dice(data, t, slot, crit)))
	var lines: Array[String] = ["Божественная кара (ячейка %d круга): %d (излучение) по %s" % [slot, dmg, Sheet.holder(s, t).get("name", "")]]
	Harm.take(s, data, t, dmg, lines, "radiant", crit, Sheet.is_hero(who))
	return lines


static func _open_hand(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, how: String, lines: Array[String]) -> void:
	var dc := ki_dc(Sheet.holder(s, f), data)
	var it := str(Sheet.holder(s, t).get("name", ""))
	match how:
		"topple":
			var ok := Sheet.saved(s, data, t, "dex", dc)
			if not ok and not CombatRules.immune_to(data, t, "prone"):
				CombatRules._hold(t, "prone")
			lines.append("Открытая ладонь: %s — Лов против Сл %d — %s" % [it, dc, "устоял" if ok else "сбит с ног"])
		"push":
			var ok := Sheet.saved(s, data, t, "str", dc)
			if not ok:
				CombatRules.push_away(s, data, t, 15)
			lines.append("Открытая ладонь: %s — Сил против Сл %d — %s" % [it, dc, "устоял" if ok else "отброшен на 15 фт"])
		"stagger":
			t["reacted"] = true
			lines.append("Открытая ладонь: %s до конца хода без реакций" % it)


## The answer to a prompt of the hero's turn. Lines.
static func answer_prompt(s: GameSession, data: Dictionary, choice: String) -> Array[String]:
	var p: Dictionary = s.combat.get("prompt", {})
	s.combat.erase("prompt")
	if p.is_empty() or choice == "none":
		return []
	match str(p["kind"]):
		"smite":
			var t := CombatRules.fighter(s, str(p["target"]))
			if t.is_empty() or str(t.get("status")) != "active":
				return []
			return _smite(s, data, t, int(choice.trim_prefix("smite_")), bool(p.get("crit", false)))
		"wild_shape":
			return _wild_shape(s, data, choice)
		"font":
			return font_convert(s, data, choice)
	return []


# --- reactions ------------------------------------------------------------------------------------


## The reactions `t` can take to this hit of `f`: [{id, label}]. `hit` — the attack's context {total, ac, nat20}: the Shield's «мимо»
## is counted against the same roll and AC as the hit itself (v0.7.22.19, #31). `t` other than the hero casts through `react.gd`.
static func reactions(s: GameSession, data: Dictionary, t: Dictionary, f: Dictionary, a: Dictionary, ranged: bool, dmg: int, hit: Dictionary = {}) -> Array[Dictionary]:
	var c := Sheet.holder(s, t)
	var out: Array[Dictionary] = []
	if bool(t.get("reacted", false)) or ConditionRules.incapacitated(c) or int(c.get("hp", 0)) <= 0:
		return out
	var see := not ConditionRules.has(c, "blinded") and not ConditionRules.invisible(Sheet.holder(s, f), data)
	var shot := ranged and str(a.get("kind", "ranged")) == "ranged" and dmg > 0
	if has(c, "uncanny_dodge") and see and dmg > 0:
		out.append({"id": "uncanny_dodge", "label": "Невероятное уклонение: урон вдвое меньше"})
	if has(c, "deflect_missiles") and shot:
		out.append({"id": "deflect_missiles", "label": "Отражение снарядов: урон −1к10 + %d" % (ab_mod(c, "dex") + level(c))})
	if Sheet.prop(s, data, t, "missile_snaring") and not has(c, "deflect_missiles") and shot:
		out.append({"id": "missile_snaring", "label": "Перчатки ловли снарядов: урон −1к10 + %d" % ab_mod(c, "dex")})  # v0.7.12
	if has(c, "cutting_words") and Stock.left(c, data, "bardic_inspiration") > 0 and see:
		out.append({"id": "cutting_words", "label": "Язвительные слова: −1к%d к броску атаки" % bardic_die(c, data)})
	if Sheet.is_hero(t):
		out.append_array(SpellEffects.hit_reactions(s, data, {"total": int(hit.get("total", int(f.get("last_total", 0)))), "ac": int(hit.get("ac", c.get("ac", 10))),
			"nat20": bool(hit.get("nat20", false)), "dmg": dmg}))  # v0.7.13.7
	if has(c, "hunters_prey_giant_killer") and CombatRules.SIZES.find(Sheet.size(s, data, f)) >= 3 and FightGrid.touching(f, t):
		out.append({"id": "giant_killer", "label": "Убийца великанов: удар в ответ"})
	return out


static func bardic_die(c: Dictionary, data: Dictionary) -> int:
	return int(CharacterRules.level_row(c, data).get("class_specific", {}).get("bardic_inspiration_die", 6))


## `t` uses its reaction on a hit of `f`: `ctx` {hit, dmg, total, ac} changes; ctx.counter — a strike back follows. Lines.
static func apply_reaction(s: GameSession, data: Dictionary, t: Dictionary, f: Dictionary, id: String, ctx: Dictionary, lines: Array[String]) -> void:
	var c := Sheet.holder(s, t)
	t["reacted"] = true
	if id.begins_with("spell_"):  # Shield, Hellish Rebuke (v0.7.13.7)
		SpellEffects.apply_hit_reaction(s, data, f, id, ctx, lines)
		return
	match id:
		"uncanny_dodge":
			ctx["dmg"] = int(ctx["dmg"]) / 2
			lines.append("%s: Невероятное уклонение — урон вдвое меньше" % c.get("name", ""))
		"deflect_missiles":
			var cut := s.rng.randi_range(1, 10) + ab_mod(c, "dex") + level(c)
			ctx["dmg"] = maxi(0, int(ctx["dmg"]) - cut)
			lines.append("%s: Отражение снарядов — урон −%d" % [c.get("name", ""), cut])
		"missile_snaring":
			var snag := s.rng.randi_range(1, 10) + ab_mod(c, "dex")
			ctx["dmg"] = maxi(0, int(ctx["dmg"]) - snag)
			lines.append("%s ловит снаряд перчатками — урон −%d" % [c.get("name", ""), snag])
		"cutting_words":
			Stock.use(c, data, "bardic_inspiration", 1, s.rng)
			var cut := s.rng.randi_range(1, bardic_die(c, data))
			ctx["total"] = int(ctx["total"]) - cut
			var still := int(ctx["total"]) >= int(ctx["ac"]) and not bool(ctx.get("nat20", false))
			ctx["hit"] = still
			lines.append("%s: Язвительные слова — −%d, атака %s" % [c.get("name", ""), cut, "всё же попадает" if still else "мимо"])
		"giant_killer":
			ctx["counter"] = true


# --- buttons of the features tab --------------------------------------------------------------------


## The feature actions `who` has: [{id, name, cost: action | bonus | free, target: bool, tip}].
static func actions(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> Array[Dictionary]:
	var c := Sheet.holder(s, who)
	var hero := Sheet.is_hero(who)
	var out: Array[Dictionary] = []
	var add := func(id: String, name: String, cost: String, target: bool, tip: String) -> void:
		out.append({"id": id, "name": name, "cost": cost, "target": target, "tip": tip})
	if Guise.has_body(c):
		add.call("revert", "Вернуть облик", "bonus", false, "Снова стать собой; хиты героя — какими были")
		return out
	for sa: Dictionary in SpellEffects.actions(s, data, who):  # v0.7.13.5: the spells that go on (the Spells tab draws them)
		out.append(sa)
	if hero:
		var blade := SpellEffects.blade_profile(c)  # v0.7.13.4: the spells' own buttons
		if not blade.is_empty():
			add.call("flame_blade", "%s: удар (%s)" % [blade["name"], str(blade["dice"]).replace("d", "к")], "action", true, "Рукопашная атака заклинанием огненным клинком")
		if SpellEffects.mark_free(s):
			add.call("move_mark", "Перенести метку охотника", "bonus", true, "Отмеченный враг пал — метка переходит на другого")
	var table := rows(data)
	for id: String in table:
		if id.begins_with("_"):
			continue
		var a: Dictionary = table[id]
		if _holds(c, data, a):
			add.call(id, str(a["name"]), str(a["cost"]), bool(a.get("target", false)), breath_text(c, data) if id == "breath" else str(a.get("tip", "")))
	return out


## The rows of rules.feature_actions.
static func rows(data: Dictionary) -> Dictionary:
	return data["rules"]["feature_actions"]


## It has what the row asks: all its features, its resource, its trait.
static func _holds(c: Dictionary, data: Dictionary, a: Dictionary) -> bool:
	for f: Variant in a.get("features", []):
		if not has(c, str(f)):
			return false
	if a.has("stock") and not Stock.owned(c, data).has(str(a["stock"])):
		return false
	return not a.has("trait") or CharacterRules.has_trait(c, str(a["trait"]))


## What the act takes when it is taken: a row with `spend` false and a spell going on pay by themselves.
static func price(data: Dictionary, id: String) -> String:
	var row: Dictionary = rows(data).get(id, {})
	if id.begins_with("spell_") or not bool(row.get("spend", true)):
		return "free"
	return str(row.get("cost", {"flame_blade": "action"}.get(id, "bonus")))


## The resources `f` can use in a fight by a press: [id].
static func stocks(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in Stock.owned(Sheet.holder(s, f), data):
		if str(Stock.table(data)[id].get("combat_cost", "action")) != "never":
			out.append(id)
	return out


## "" when it has what the row spends, otherwise a key.
static func payable(s: GameSession, data: Dictionary, f: Dictionary, id: String) -> String:
	var c := Sheet.holder(s, f)
	var pay: Dictionary = rows(data).get(id, {}).get("pay", {})
	if not pay.is_empty() and Stock.left(c, data, str(pay["id"])) < int(pay["n"]):
		return "COMBAT_NO_KI" if str(pay["id"]) == "ki" else "COMBAT_NO_CHARGE"
	return "COMBAT_NO_CHARGE" if id == "breath" and bool(c.get("breath_used", false)) else ""


## "" when `f` can take the feature action now, otherwise a localization key.
static func why(s: GameSession, data: Dictionary, f: Dictionary, id: String, target_id: String = "") -> String:
	var c := Sheet.holder(s, f)
	var e := CombatRules.points(s, data, f)
	var spec: Dictionary = {}
	for a: Dictionary in actions(s, data, f):
		if str(a["id"]) == id:
			spec = a
	if spec.is_empty():
		return "COMBAT_NO_FEATURE"
	var short := CombatRules.short_of(f, str(spec["cost"]), 1)
	if not short.is_empty():
		return short
	if id.begins_with("spell_"):
		return Acts.one("sustain").can(s, data, f, target_id, {"spell": id.trim_prefix("spell_")})
	var row: Dictionary = rows(data).get(id, {})
	var stop := payable(s, data, f, id)
	if not stop.is_empty():
		return stop
	if bool(row.get("dark", false)) and SightRules.in_dark(s, data, f).is_empty():
		return "COMBAT_NEEDS_DARK"
	if bool(row.get("after_attack", false)) and not bool(e.get("attacked", false)):
		return "COMBAT_ATTACK_FIRST"
	if bool(row.get("before_attack", false)) and (bool(e.get("attacked", false)) or bool(f.get(id, false))):
		return "COMBAT_RECKLESS_LATE"
	if id == "breath":  # a cone or a line laid towards a square or a body, as an area spell (v0.8.4.24)
		var at := CombatRules.aimed(s, target_id)
		if at.is_empty() or FightGrid.cell(at) == FightGrid.cell(f):
			return "COMBAT_BAD_TARGET"
		return "COMBAT_OUT_OF_REACH" if FightGrid.shown_dist(f, at) > FightGrid.squares_of(data, aim_ft(s, data, f, id)) else ""
	if bool(spec["target"]):
		var t := CombatRules.fighter(s, target_id) if CombatRules.foes_of(s, f).has(target_id) else {}
		if t.is_empty() or not Attack.up(s, t):
			return "COMBAT_BAD_TARGET"
		if FightGrid.shown_dist(f, t) > 1:
			return "COMBAT_OUT_OF_REACH"
	return ""


## Takes a feature action (the act has paid its points). Lines.
static func run(s: GameSession, data: Dictionary, f: Dictionary, id: String, target_id: String = "") -> Array[String]:
	var c := Sheet.holder(s, f)
	var lines: Array[String] = []
	if id.begins_with("spell_"):
		return Acts.one("sustain").go(s, data, f, target_id, {"spell": id.trim_prefix("spell_")})
	var row: Dictionary = rows(data).get(id, {})
	var pay: Dictionary = row.get("pay", {})
	if not pay.is_empty() and not bool(pay.get("check_only", false)):
		Stock.use(c, data, str(pay["id"]), int(pay["n"]), s.rng)
	_hook(s, data, f, str(row.get("hook", id)) if row.is_empty() or row.has("hook") else "", target_id, lines)
	for fx: Dictionary in row.get("effects", []):
		_do(s, data, f, fx, target_id, lines)
	return lines


## "" when `f` can use the resource in a fight now, otherwise a key or a reason.
static func why_stock(s: GameSession, data: Dictionary, f: Dictionary, id: String) -> String:
	var c := Sheet.holder(s, f)
	var spec: Dictionary = Stock.table(data).get(id, {})
	if str(spec.get("combat_cost", "action")) == "never":
		return "COMBAT_FEATURE_TAB"
	var stop := Stock.can_use(c, data, id, 1)
	if not stop.is_empty():
		return stop
	if spec.has("no_armor") and str(CharacterRules.item_def(c, data, s.items, "armor").get("armor", {}).get("category", "")) == str(spec["no_armor"]):
		return "COMBAT_RAGE_ARMOR"
	return "COMBAT_NO_CHARGE" if bool(f.get(str(spec.get("in_fight", {}).get("stance", "")), false)) else ""


## Uses the resource: what `in_fight` of its row gives, what `on_use` gives anywhere. Lines.
static func use_stock(s: GameSession, data: Dictionary, f: Dictionary, id: String) -> Array[String]:
	var c := Sheet.holder(s, f)
	var e := CombatRules.points(s, data, f)
	var fx: Dictionary = Stock.table(data)[id].get("in_fight", {})
	for k: String in fx.get("points", {}):
		e[k] = int(e.get(k, 0)) + int(fx["points"][k])
	if fx.has("stance"):
		f[str(fx["stance"])] = true
	var lines := Stock.use(c, data, id, 1, s.rng, s)
	if not Sheet.is_hero(f) and not lines.is_empty():
		lines[0] = "%s: %s" % [f["name"], lines[0]]
	return lines


## One effect of a feature's action.
static func _do(s: GameSession, data: Dictionary, f: Dictionary, fx: Dictionary, target_id: String, lines: Array[String]) -> void:
	var c := Sheet.holder(s, f)
	match str(fx["kind"]):
		"strike":
			var b := Attack.of_weapon(CombatRules.unarmed_profile(c, data)).merged({"opts": fx.get("opts", {})}, true)
			for i in int(fx.get("times", 1)):
				var t := CombatRules.fighter(s, target_id)
				if t.is_empty() or not Attack.up(s, t):
					break
				Attack.swing(s, data, f, t, b, lines)
		"stance":
			f[str(fx["key"])] = true
		"status":  # One with Shadows (v0.8.4.26.1)
			var st: Dictionary = (fx["status"] as Dictionary).duplicate(true)
			st["source"] = {"kind": "feature", "name": str(fx.get("name", ""))}
			lines.append_array(ConditionRules.impose(s, data, st, f))
		"dash":
			var e := CombatRules.points(s, data, f)
			e["move"] = int(e.get("move", 0)) + Move.steps(s, data, f)
		"for":
			f[str(fx["key"])] = fx["value"]
		"line":
			lines.append(str(fx["text"]) % c.get("name", ""))
		"turn":
			lines.append_array(_turn(s, data, f, fx["types"], (fx.get("destroy", []) as Array).any(func(x: Variant) -> bool: return has(c, str(x)))))
		"heal_half":
			var heal := mini(5 * level(c), maxi(0, int(c["max_hp"]) / 2 - int(c["hp"])))
			c["hp"] = int(c["hp"]) + heal
			lines.append("Сохранение жизни: +%d HP" % heal)
		"hook":
			_hook(s, data, f, str(fx["id"]), target_id, lines)


## What stays code: a button of a spell, a prompt, a blow with its own road. The AI picks where the hero is asked.
static func _hook(s: GameSession, data: Dictionary, f: Dictionary, id: String, target_id: String, lines: Array[String]) -> void:
	var c := Sheet.holder(s, f)
	var hero := Sheet.is_hero(f)
	var e := CombatRules.points(s, data, f)
	match id:
		"flame_blade":
			Attack.swing(s, data, f, CombatRules.fighter(s, target_id), Attack.of_weapon(SpellEffects.blade_profile(c)), lines)
		"move_mark":
			SpellEffects.mark(c, target_id)
			lines.append("Метка охотника переходит на %s" % CombatRules.fighter(s, target_id).get("name", ""))
		"stunning":
			var t := CombatRules.fighter(s, target_id)
			var b := Attack.blade(s, data, f)
			if b.is_empty() or not bool(b["melee"]) or not FightGrid.touching(f, t):
				b = Attack.of_weapon(CombatRules.unarmed_profile(c, data))
			CombatRules.pay_attack(s, data, f)
			e["attacked"] = true
			Attack.swing(s, data, f, t, b.merged({"opts": {"stunning": true}}, true), lines)
		"sacred_line":
			lines.append("Священное оружие: +%d к атакам оружием на минуту" % maxi(1, ab_mod(c, "cha")))
		"wild_shape":
			if not hero:
				lines.append_array(_wild_shape(s, data, beasts(c, data)[0], f))
				return
			var options: Array[Dictionary] = []
			for mid: String in beasts(c, data):
				var m: Dictionary = data["monsters"][mid]
				options.append({"id": mid, "label": "%s (HP %d, КД %d)" % [m["name"], int(m["hp"]), int(m["ac"])]})
			options.append({"id": "none", "label": "Не превращаться"})
			s.combat["prompt"] = {"kind": "wild_shape", "options": options, "text": "Дикий облик: в кого превратиться?"}
		"revert":
			lines.append_array(end_shape(s, data, 0, f))
		"font":
			if hero:
				var options := font_options(c, data)
				options.append({"id": "none", "label": "Ничего"})
				s.combat["prompt"] = {"kind": "font", "options": options, "text": "Источник магии: очков %d" % Stock.left(c, data, "sorcery_points")}
		"breath":
			lines.append_array(_breath(s, data, f, target_id))


## Turn Undead / Turn the Unholy: every foe of those types within 30 ft saves WIS against the spell DC or flees for a
## minute; a cleric's Destroy Undead kills the weak ones. Lines.
static func _turn(s: GameSession, data: Dictionary, f: Dictionary, types: Array, destroy: bool) -> Array[String]:
	var c := Sheet.holder(s, f)
	var dc := int(c.get("spell_dc", 8 + CharacterRules.prof_bonus(c, data) + ab_mod(c, "wis")))
	var destroy_cr := float(CharacterRules.level_row(c, data).get("class_specific", {}).get("destroy_undead_cr", 0)) if destroy else 0.0
	var lines: Array[String] = []
	var any := false
	for id: String in CombatRules.foes_of(s, f):
		var t := CombatRules.fighter(s, id)
		var m := Sheet.template(data, t)
		if not types.has(str(m.get("type", ""))) or FightGrid.feet(data, t, f) > 30:
			continue
		any = true
		if Sheet.saved(s, data, t, "wis", dc, "magic"):
			lines.append("%s выдерживает (Мдр против Сл %d)" % [t["name"], dc])
			continue
		if destroy_cr > 0.0 and float(m.get("cr", 9)) <= destroy_cr:
			t["hp"] = 0
			t["status"] = "dead"
			lines.append("%s рассыпается прахом" % t["name"])
			continue
		t["fleeing"] = true
		CombatRules._add_condition(s, data, t, "frightened", {"rounds": 10})
		lines.append("%s изгнан и бежит" % t["name"])
	if not any:
		lines.append("Рядом нет тех, на кого это действует")
	return lines


# --- Wild Shape -----------------------------------------------------------------------------------


## The beasts the druid can become now: CR within the level, no flying (and no swimming before level 4).
static func beasts(c: Dictionary, data: Dictionary) -> Array[String]:
	var row: Dictionary = CharacterRules.level_row(c, data).get("class_specific", {})
	var max_cr := float(row.get("wild_shape_max_cr", 0.25))
	var out: Array[String] = []
	for mid: String in data["monsters"]:
		var m: Dictionary = data["monsters"][mid]
		if str(m.get("type", "")) != "beast" or float(m.get("cr", 9)) > max_cr or int(m.get("fly", 0)) > 0:
			continue
		if int(m.get("swim", 0)) > 0 and not bool(row.get("wild_shape_swim", false)):
			continue
		if not (m["actions"] as Array).any(func(a: Dictionary) -> bool: return str(a.get("kind")) == "melee"):
			continue
		out.append(mid)
	out.sort_custom(func(a: String, b: String) -> bool:
		return float(data["monsters"][a]["cr"]) > float(data["monsters"][b]["cr"]) or float(data["monsters"][a]["cr"]) == float(data["monsters"][b]["cr"]) \
			and int(data["monsters"][a]["hp"]) > int(data["monsters"][b]["hp"]))
	return out.slice(0, 12)


static func _wild_shape(s: GameSession, data: Dictionary, mid: String, who: Dictionary = Sheet.HERO) -> Array[String]:
	var c := Sheet.holder(s, who)
	if not data["monsters"].has(mid):
		return []
	CombatRules.pay(_fighter(s, who), "action")
	Stock.use(c, data, "wild_shape", 1, s.rng)
	var m: Dictionary = data["monsters"][mid]
	Guise.wear(c, {"monster": mid, "hp": int(m["hp"]), "max_hp": int(m["hp"]), "ac": int(m["ac"])}, {"kind": "feature", "id": "wild_shape", "name": "Дикий облик: " + str(m["name"])})  # concentration holds through it (5e)
	if Sheet.is_hero(who):
		CharacterRules.refresh(c, data, s.items)
	return ["%s принимает облик: %s (HP %d, КД %d)" % [c.get("name", ""), m["name"], int(m["hp"]), int(m["ac"])]]


## The beast form ends; `overflow` — damage past its hit points goes to the character. Lines.
static func end_shape(s: GameSession, data: Dictionary, overflow: int, who: Dictionary = Sheet.HERO) -> Array[String]:
	var c := Sheet.holder(s, who)
	if not Guise.has_body(c):
		return []
	var name := str(data["monsters"].get(str(Guise.body(c)["monster"]), {}).get("name", ""))
	Guise.take_off(c)
	if Sheet.is_hero(who):
		CharacterRules.refresh(c, data, s.items)
	var lines: Array[String] = ["%s снова в своём облике (был: %s)" % [c.get("name", ""), name]]
	if overflow > 0:
		lines.append("урон сверх облика: %d" % overflow)
		c["hp"] = maxi(0, int(c["hp"]) - overflow)
	return lines


## Damage to one in a beast form goes to the form first. Returns what is left for the character.
static func hurt_shape(s: GameSession, data: Dictionary, dmg: int, lines: Array[String], who: Dictionary = Sheet.HERO) -> int:
	var c := Sheet.holder(s, who)
	if not Guise.has_body(c) or dmg <= 0:
		return dmg
	var ws: Dictionary = Guise.body(c)
	ws["hp"] = int(ws["hp"]) - dmg
	if int(ws["hp"]) > 0:
		return 0
	var over := -int(ws["hp"])
	lines.append_array(end_shape(s, data, 0, who))
	return over


## The profile of the beast's best melee attack (for the attack button in a beast form).
static func shape_profile(c: Dictionary, data: Dictionary) -> Dictionary:
	var m: Dictionary = data["monsters"].get(str(Guise.body(c)["monster"]), {})
	var best := {}
	for a: Dictionary in m.get("actions", []):
		if str(a.get("kind")) == "melee" and (best.is_empty() or int(a.get("to_hit", 0)) > int(best.get("to_hit", 0))):
			best = a
	var dmg: Dictionary = (best.get("damage", [{"dice": "1d4", "type": "bludgeoning"}]) as Array)[0]
	var dice := str(dmg["dice"])
	var bonus := 0
	if dice.contains("+"):
		bonus = int(dice.get_slice("+", 1))
		dice = dice.get_slice("+", 0)
	return {"name": "%s (%s)" % [best.get("name", "Удар"), m.get("name", "")], "to_hit": int(best.get("to_hit", 0)), "dice": dice, "bonus": bonus,
		"type": str(dmg["type"]), "melee": true, "range": [], "light": false, "id": "", "magical": false, "silvered": false, "beast": true}


# --- Font of Magic and metamagic ---------------------------------------------------------------------


## Options of Font of Magic now: a used slot back for points, a slot for points.
static func font_options(c: Dictionary, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var points := Stock.left(c, data, "sorcery_points")
	var font: Dictionary = cfg(data)["font_of_magic"]
	var costs: Dictionary = font["slot_cost"]
	for lv: String in costs:
		if has(c, str(font.get("create_with", ""))) and Stock.spent(c, "slot_" + lv) > 0 and points >= int(costs[lv]):
			out.append({"id": "slot_" + lv, "label": "Ячейка %s круга за %d очк." % [lv, int(costs[lv])]})
	for lv in range(1, 6):
		if has(c, str(font.get("convert_with", ""))) and SpellRules.slots_left(c, lv) > 0 and Stock.spent(c, "sorcery_points") >= lv:
			out.append({"id": "points_%d" % lv, "label": "Ячейку %d круга — в %d очк." % [lv, lv]})
	return out


static func font_convert(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	if CombatRules.active(s):
		var e := CombatRules.economy(s)
		e["bonus"] = int(e.get("bonus", 0)) - 1
	if id.begins_with("slot_"):
		var lv := int(id.trim_prefix("slot_"))
		var cost := int(cfg(data)["font_of_magic"]["slot_cost"][str(lv)])
		Stock.spend(c, "sorcery_points", cost)
		Stock.give(c, "slot_%d" % lv)
		return ["Источник магии: ячейка %d круга за %d очк." % [lv, cost]]
	var lv := int(id.trim_prefix("points_"))
	Stock.spend(c, "slot_%d" % lv)
	Stock.give(c, "sorcery_points", lv)
	return ["Источник магии: ячейка %d круга стала %d очк." % [lv, lv]]


## The metamagic options of the sorcerer: [{id, name, cost}].
static func metamagic(c: Dictionary, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table: Dictionary = cfg(data)["metamagic"]
	for id: String in table:
		if has(c, "metamagic_" + id):
			out.append({"id": id, "name": str(table[id]["name"]), "cost": int(table[id]["cost"])})
	return out


## The active metamagic of the next cast ("" none) when `who` can pay it.
static func active_metamagic(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> String:
	if not CombatRules.active(s):
		return ""
	var id := str(_fighter(s, who).get("metamagic", ""))
	if id.is_empty() or not cfg(data)["metamagic"].has(id):
		return ""
	return id if Stock.left(Sheet.holder(s, who), data, "sorcery_points") >= int(cfg(data)["metamagic"][id]["cost"]) else ""


## Pays the metamagic of this cast. One who is not the hero uses the cheapest it has. The id or "".
static func pay_metamagic(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> String:
	var c := Sheet.holder(s, who)
	if not Sheet.is_hero(who):
		var best := 1 << 20
		for m: Dictionary in metamagic(c, data):
			if int(m["cost"]) < best:
				best = int(m["cost"])
				who["metamagic"] = str(m["id"])
	var id := active_metamagic(s, data, who)
	if not id.is_empty():
		Stock.use(c, data, "sorcery_points", int(cfg(data)["metamagic"][id]["cost"]), s.rng)
	_fighter(s, who).erase("metamagic")
	return id


# --- dragonborn ------------------------------------------------------------------------------------


static func breath_type(c: Dictionary, data: Dictionary) -> String:
	for t: Variant in c.get("traits", []):
		var dt := str(data["races"]["traits"].get(str(t), {}).get("damage_type", ""))
		if str(t).begins_with("draconic_ancestry_") and not dt.is_empty():
			return dt
	return "fire"


static func breath_shape(c: Dictionary, data: Dictionary) -> String:
	for t: Variant in c.get("traits", []):
		var color := str(t).trim_prefix("draconic_ancestry_")
		if str(t).begins_with("draconic_ancestry_"):
			return "line" if color in ["black", "blue", "brass", "bronze", "copper"] else "cone"
	return "cone"


static func breath_text(c: Dictionary, data: Dictionary) -> String:
	return "%s, %s; спасбросок %s Сл %d; раз за короткий отдых" % [
		"линия 30 фт" if breath_shape(c, data) == "line" else "конус 15 фт", data["misc"]["damage_types"].get(breath_type(c, data), ""),
		"Тел" if breath_type(c, data) in ["cold", "poison"] else "Лов", 8 + ab_mod(c, "con") + CharacterRules.prof_bonus(c, data)]


## The shape of the dragonborn's breath by 5e.
static func _breath_area(c: Dictionary, data: Dictionary) -> Dictionary:
	return {"type": "line", "size": 30} if breath_shape(c, data) == "line" else {"type": "cone", "size": 15}


## The act is laid on a square as an area (its row's `aims`): the button aims it as an area spell.
static func aims(data: Dictionary, id: String) -> bool:
	return bool(rows(data).get(id, {}).get("aims", false))


## How far an aimed act reaches, feet.
static func aim_ft(s: GameSession, data: Dictionary, f: Dictionary, id: String) -> int:
	return int(_breath_area(Sheet.holder(s, f), data)["size"]) if id == "breath" else 0


## The squares an aimed act covers at `target_id`.
static func aim_cells(s: GameSession, data: Dictionary, f: Dictionary, id: String, target_id: String) -> Array[Vector2i]:
	return breath_cells(s, data, f, target_id) if id == "breath" else [] as Array[Vector2i]


## The squares of the breath of `f` towards `target_id` — a square ("@x,y") or a body, as an area spell is aimed (v0.8.4.24).
static func breath_cells(s: GameSession, data: Dictionary, f: Dictionary, target_id: String) -> Array[Vector2i]:
	var t := CombatRules.aimed(s, target_id)
	if t.is_empty():
		return []
	var aim := FightGrid.cell(t) if bool(t.get("aim", false)) else FightGrid._facing(f, t)[1]
	return FightGrid.area(s, data, _breath_area(Sheet.holder(s, f), data), FightGrid.cell(f), aim, true)


## Who the breath of `f` catches at `target_id`: every creature in its squares but the breather, foes and friends alike (5e).
static func breath_caught(s: GameSession, data: Dictionary, f: Dictionary, target_id: String) -> Array[Dictionary]:
	var cells := breath_cells(s, data, f, target_id)
	var out: Array[Dictionary] = []
	var field := CombatRules.foes_of(s, f)
	if bool(CombatRules.cfg(data)["friendly_fire"]["on"]):
		field.append_array(CombatRules.friends_of(s, f))
	for id: String in field:
		var t := CombatRules.fighter(s, id)
		if id != str(f["id"]) and Attack.up(s, t) and FightGrid.in_cells(t, cells):
			out.append(t)
	return out


## The dragonborn's breath towards `target_id`: its shape from the breather, on who stands there. Lines.
static func _breath(s: GameSession, data: Dictionary, f: Dictionary, target_id: String) -> Array[String]:
	var c := Sheet.holder(s, f)
	c["breath_used"] = true
	var dtype := breath_type(c, data)
	var ab := "con" if dtype in ["cold", "poison"] else "dex"
	var dc := 8 + ab_mod(c, "con") + CharacterRules.prof_bonus(c, data)
	var dice := "%dd6" % (2 if level(c) < 6 else 3)
	var cells := breath_cells(s, data, f, target_id)
	AnimRules.emit(s, {"by": str(f["id"]), "act": "cast", "anim": breath_shape(c, data), "dtype": dtype, "result": "hit", "cells": FightGrid.pack_cells(cells)})
	var full := CombatRules.roll_dice(s.rng, dice)
	var lines: Array[String] = ["%s выдыхает %s (%s)" % [c.get("name", ""), data["misc"]["damage_types"].get(dtype, dtype), dice.replace("d", "к")]]
	for t: Dictionary in breath_caught(s, data, f, target_id):
		var ok := Sheet.saved(s, data, t, ab, dc)
		var dmg := Sheet.taken(s, data, t, dtype, full / 2 if ok else full)
		AnimRules.outcome(s, t, "impact" if dmg > 0 else "resist", dtype)
		lines.append("%s: %s против Сл %d — %s, %d" % [Sheet.holder(s, t).get("name", ""), CombatRules.ab_name(ab), dc, "успех" if ok else "провал", dmg])
		if Sheet.is_hero(f):
			CombatRules._caught_friend(s, data, t)
		Harm.take(s, data, t, dmg, lines, dtype, false, Sheet.is_hero(f))
	if lines.size() == 1:
		lines.append("Никого не задело")
	return lines


# --- per turn ----------------------------------------------------------------------------------------


## The end of a turn: a rage with no attack and no damage taken ends; Sacred Weapon runs down. Lines.
static func end_turn(s: GameSession, f: Dictionary, lines: Array[String]) -> void:
	if bool(f.get("raging", false)):
		if not bool(f.get("rage_kept", false)):
			f["raging"] = false
			lines.append(("" if Sheet.is_hero(f) else "%s: " % f["name"]) + "Ярость угасает: за ход ни удара, ни раны")
		f["rage_kept"] = false
	if int(f.get("sacred_weapon", 0)) > 0:
		f["sacred_weapon"] = int(f["sacred_weapon"]) - 1


## Dark One's Blessing: one who drops a foe on its own turn gets temporary HP (CHA + warlock level).
static func on_kill(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var c := Sheet.holder(s, CombatRules.fighter(s, CombatRules.current(s)))
	if has(c, "dark_ones_blessing"):
		var thp := maxi(1, ab_mod(c, "cha") + level(c))
		if Harm.shield(data, c, thp):
			lines.append("Благословение Тёмного: %d временных хитов" % thp)
