class_name FeatureRules
extends RefCounted
## Class features and race traits in the engine (roadmap v0.7.10 «Правила 5e: особенности классов и черты рас»; the
## author: «как в Baldur's Gate 3»):
## - prompts of the hero's own turn (`s.combat.prompt`): Divine Smite after a melee hit (a slot to spend), the beast of
##   Wild Shape, Font of Magic; the player answers (GameState.combat_answer) or the policy decides;
## - reactions to a foe's hit (`reactions` / `apply_reaction`): Uncanny Dodge, Deflect Missiles, Cutting Words, Giant
##   Killer — asked when `s.settings.reactions` is "ask" (the engine stops the foe's turn, CombatRules.answer_reaction
##   goes on), used by themselves with "always", never with "never" (tests and the balance sim: "always");
## - actions of the features tab (`actions` / `can_act` / `act`): Reckless Attack, Martial Arts and the ki techniques
##   (Flurry of Blows and the Open Hand variants, Patient Defense, Step of the Wind, Stunning Strike), Channel Divinity
##   (Turn Undead, Turn the Unholy, Sacred Weapon, Preserve Life), Wild Shape and its end, Font of Magic, the
##   dragonborn's Breath Weapon;
## - what a hit brings (`hit_extras`, `after_hit`): Colossus Slayer, Savage Attacks, Divine Smite, Stunning Strike,
##   Open Hand, Horde Breaker; Bardic Inspiration as a die the hero adds to a failed roll (house rule, ADR-0010 §6в);
## - metamagic (`s.combat.metamagic`), the rest of Rage (STR advantage, the end without attacks, heavy armour), Danger
##   Sense, Lucky, Dark One's Blessing (temporary HP).
## Data — rules.json `class_features`. Pure: randomness from s.rng.

const OPEN_HAND := ["topple", "push", "stagger"]


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["class_features"]


## What happens to a reaction or a prompt: "ask" (the player is asked), "always", "never".
static func policy(s: GameSession) -> String:
	return str(s.settings.get("reactions", "always"))


static func has(c: Dictionary, id: String) -> bool:
	return CharacterRules.has_feature(c, id)


static func level(c: Dictionary) -> int:
	return int(c.get("level", 1))


static func ab_mod(c: Dictionary, ab: String) -> int:
	return CharacterRules.mod(CharacterRules.ability(c, ab))


# --- rolls ---------------------------------------------------------------------------------------


## Lucky (halfling): a natural 1 on a d20 of the hero is rolled again, once. Returns the roll and the note.
static func lucky(s: GameSession, roll: int) -> int:
	if roll == 1 and CharacterRules.has_trait(s.character, "lucky"):
		return s.rng.randi_range(1, 20)
	return roll


## The hero's d20s with advantage / disadvantage and Lucky.
static func hero_d20(s: GameSession, adv: bool, dis: bool) -> Array[int]:
	var rolls: Array[int] = [lucky(s, s.rng.randi_range(1, 20))]
	if adv != dis:
		rolls.append(lucky(s, s.rng.randi_range(1, 20)))
	return rolls


## Bardic Inspiration the hero keeps (a house rule: in a solo game the bard inspires themself): the die, 0 when none.
static func inspiration_die(c: Dictionary) -> int:
	for e: Dictionary in ConditionRules.effects(c):
		if int(e.get("inspiration", 0)) > 0:
			return int(e["inspiration"])
	return 0


## A failed d20 roll of the hero gets the inspiration die (it is spent). Returns the bonus, 0 when there is none.
static func use_inspiration(s: GameSession) -> int:
	var c := s.character
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


## Extra dice of a hero's weapon hit besides Sneak Attack: Colossus Slayer (once a turn on a wounded foe), Savage
## Attacks (a melee crit). {"dice": "1d8+1d10", "notes": [..]}.
static func hit_extras(s: GameSession, data: Dictionary, w: Dictionary, t: Dictionary, crit: bool) -> Dictionary:
	var c := s.character
	var dice: Array[String] = []
	var notes: Array[String] = []
	var e := CombatRules.economy(s)
	if has(c, "hunters_prey_colossus_slayer") and int(t.get("hp", 0)) < int(t.get("max_hp", 0)) and not bool(e.get("colossus", false)):
		e["colossus"] = true
		dice.append("1d8")
		notes.append("Убийца колоссов")
	if crit and bool(w.get("melee", false)) and CharacterRules.has_trait(c, "savage_attacks"):
		dice.append(str(w["dice"]).get_slice("+", 0).replace("2d", "1d"))
		notes.append("Свирепые атаки")
	return {"dice": "+".join(dice), "notes": notes}


# --- what a hit brings ----------------------------------------------------------------------------


## After a hero's weapon hit: Stunning Strike, an Open Hand technique (opts), Divine Smite as a prompt (or by the policy),
## the rage kept up. Lines.
static func after_hit(s: GameSession, data: Dictionary, w: Dictionary, t: Dictionary, crit: bool, opts: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	if str(t.get("status")) != "active":
		return
	if bool(opts.get("stunning", false)) and FeatureUses.left(c, data, "ki") > 0:
		FeatureUses.use(c, data, "ki", 1, s.rng)
		var dc := ki_dc(c, data)
		var ok := CombatRules._monster_save(s, data, t, "con", dc)
		lines.append("Оглушающий удар: %s — спасбросок Тел против Сл %d — %s" % [t["name"], dc, "устоял" if ok else "ошеломлён"])
		if not ok and not CombatRules.immune_to(data, t, "stunned"):
			CombatRules._add_condition(t, "stunned", {"rounds": 1})
	var oh := str(opts.get("open_hand", ""))
	if not oh.is_empty():
		_open_hand(s, data, t, oh, lines)
	if bool(w.get("melee", false)) and has(c, "divine_smite") and not smite_slots(c).is_empty():
		var pol := policy(s)
		if pol == "ask":
			var options: Array[Dictionary] = []
			for lv: int in smite_slots(c):
				options.append({"id": "smite_%d" % lv, "label": "Кара ячейкой %d круга (%s)" % [lv, smite_dice(data, t, lv, crit).replace("d", "к")]})
			options.append({"id": "none", "label": "Не карать"})
			s.combat["prompt"] = {"kind": "smite", "target": str(t["id"]), "crit": crit, "options": options,
				"text": "Божественная кара: %s — удар попал." % t["name"]}
		elif pol == "always":
			lines.append_array(_smite(s, data, t, int(smite_slots(c)[0]), crit))


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
	if str(CombatRules._monster(data, t).get("type", "")) in ["undead", "fiend"]:
		n += 1
	return "%dd8" % (n * (2 if crit else 1))


static func _smite(s: GameSession, data: Dictionary, t: Dictionary, slot: int, crit: bool) -> Array[String]:
	var c := s.character
	var used: Array = (c.get("slots_used", [0, 0, 0, 0, 0]) as Array).duplicate()
	used[slot - 1] = int(used[slot - 1]) + 1
	c["slots_used"] = used
	var dmg := CombatRules._resist(data, t, "radiant", CombatRules.roll_dice(s.rng, smite_dice(data, t, slot, crit)))
	var lines: Array[String] = ["Божественная кара (ячейка %d круга): %d (излучение) по %s" % [slot, dmg, t["name"]]]
	CombatRules._hurt_enemy(s, data, t, dmg, lines, "radiant", crit)
	return lines


static func _open_hand(s: GameSession, data: Dictionary, t: Dictionary, how: String, lines: Array[String]) -> void:
	var dc := ki_dc(s.character, data)
	match how:
		"topple":
			var ok := CombatRules._monster_save(s, data, t, "dex", dc)
			if not ok and not CombatRules.immune_to(data, t, "prone"):
				CombatRules._hold(t, "prone")
			lines.append("Открытая ладонь: %s — Лов против Сл %d — %s" % [t["name"], dc, "устоял" if ok else "сбит с ног"])
		"push":
			var ok := CombatRules._monster_save(s, data, t, "str", dc)
			if not ok:
				var away := 1 if int(t["col"]) >= int(CombatRules.player(s)["col"]) else -1
				t["col"] = clampi(int(t["col"]) + away, -CombatRules.edge(data), CombatRules.edge(data))
			lines.append("Открытая ладонь: %s — Сил против Сл %d — %s" % [t["name"], dc, "устоял" if ok else "отброшен на 30 фт"])
		"stagger":
			t["reacted"] = true
			lines.append("Открытая ладонь: %s до конца хода без реакций" % t["name"])


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


## The reactions the hero can take to this hit of a foe: [{id, label}]. `hit` — the attack's context {total, ac, nat20}:
## the Shield's «мимо» is counted against the same roll and AC as the hit itself (v0.7.22.19, #31).
static func reactions(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, ranged: bool, dmg: int, hit: Dictionary = {}) -> Array[Dictionary]:
	var c := s.character
	var out: Array[Dictionary] = []
	if bool(CombatRules.player(s).get("reacted", false)) or ConditionRules.incapacitated(c) or int(c.get("hp", 0)) <= 0:
		return out
	var see := not ConditionRules.has(c, "blinded") and not CombatRules._has(f, "invisible")
	if has(c, "uncanny_dodge") and see and dmg > 0:
		out.append({"id": "uncanny_dodge", "label": "Невероятное уклонение: урон вдвое меньше"})
	if has(c, "deflect_missiles") and ranged and str(a.get("kind")) == "ranged" and dmg > 0:
		out.append({"id": "deflect_missiles", "label": "Отражение снарядов: урон −1к10 + %d" % (ab_mod(c, "dex") + level(c))})
	if CharacterRules.item_prop(c, "missile_snaring") and not has(c, "deflect_missiles") and ranged and str(a.get("kind")) == "ranged" and dmg > 0:
		out.append({"id": "missile_snaring", "label": "Перчатки ловли снарядов: урон −1к10 + %d" % ab_mod(c, "dex")})  # v0.7.12
	if has(c, "cutting_words") and FeatureUses.left(c, data, "bardic_inspiration") > 0 and see:
		out.append({"id": "cutting_words", "label": "Язвительные слова: −1к%d к броску атаки" % bardic_die(c, data)})
	out.append_array(SpellEffects.hit_reactions(s, data, {"total": int(hit.get("total", total_of(a, f))), "ac": int(hit.get("ac", c.get("ac", 10))),
		"nat20": bool(hit.get("nat20", false)), "dmg": dmg}))  # v0.7.13.7
	if has(c, "hunters_prey_giant_killer") and CombatRules.SIZES.find(str(CombatRules._monster(data, f).get("size", "medium"))) >= 3 \
			and CombatRules.cols_between(f, CombatRules.player(s)) == 0:
		out.append({"id": "giant_killer", "label": "Убийца великанов: удар в ответ"})
	return out


## The attack's total for the reactions' labels (CombatRules keeps it in the attack's context; 0 — unknown).
static func total_of(a: Dictionary, f: Dictionary) -> int:
	return int(f.get("last_total", 0))


static func bardic_die(c: Dictionary, data: Dictionary) -> int:
	return int(CharacterRules.level_row(c, data).get("class_specific", {}).get("bardic_inspiration_die", 6))


## Uses a reaction on a hit: `ctx` {hit, dmg, total, ac} changes; ctx.counter — a strike back follows. Lines.
static func apply_reaction(s: GameSession, data: Dictionary, f: Dictionary, id: String, ctx: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	CombatRules.player(s)["reacted"] = true
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
			FeatureUses.use(c, data, "bardic_inspiration", 1, s.rng)
			var cut := s.rng.randi_range(1, bardic_die(c, data))
			ctx["total"] = int(ctx["total"]) - cut
			var still := int(ctx["total"]) >= int(ctx["ac"]) and not bool(ctx.get("nat20", false))
			ctx["hit"] = still
			lines.append("%s: Язвительные слова — −%d, атака %s" % [c.get("name", ""), cut, "всё же попадает" if still else "мимо"])
		"giant_killer":
			ctx["counter"] = true


# --- buttons of the features tab --------------------------------------------------------------------


## The feature actions the hero has: [{id, name, cost: action | bonus | free, target: bool, tip}].
static func actions(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var c := s.character
	var out: Array[Dictionary] = []
	var add := func(id: String, name: String, cost: String, target: bool, tip: String) -> void:
		out.append({"id": id, "name": name, "cost": cost, "target": target, "tip": tip})
	if c.has("wild_shape"):
		add.call("revert", "Вернуть облик", "bonus", false, "Снова стать собой; хиты героя — какими были")
		return out
	for sa: Dictionary in SpellEffects.actions(s, data):  # v0.7.13.5: the spells that go on (the Spells tab draws them)
		out.append(sa)
	var blade := SpellEffects.blade_profile(c)  # v0.7.13.4: the spells' own buttons
	if not blade.is_empty():
		add.call("flame_blade", "%s: удар (%s)" % [blade["name"], str(blade["dice"]).replace("d", "к")], "action", true, "Рукопашная атака заклинанием огненным клинком")
	if SpellEffects.mark_free(s):
		add.call("move_mark", "Перенести метку охотника", "bonus", true, "Отмеченный враг пал — метка переходит на другого")
	if has(c, "reckless_attack"):
		add.call("reckless", "Безрассудная атака", "free", false, "Атаки Силой вплотную с преимуществом до конца хода, но и по вам — до вашего следующего хода")
	if has(c, "martial_arts"):
		add.call("martial_strike", "Удар бонусом (боевые искусства)", "bonus", true, "После действия «Атака»: безоружный удар бонусным действием")
	if has(c, "flurry_of_blows"):
		add.call("flurry", "Шквал ударов (1 ки)", "bonus", true, "После действия «Атака»: два безоружных удара")
		if has(c, "open_hand_technique"):
			for how: String in OPEN_HAND:
				add.call("flurry_" + how, "Шквал: " + {"topple": "сбить с ног", "push": "оттолкнуть", "stagger": "без реакций"}[how], "bonus", true,
					"Шквал ударов, и каждый удар — техника открытой ладони")
	if has(c, "patient_defense"):
		add.call("patient_defense", "Терпеливая оборона (1 ки)", "bonus", false, "Уклонение бонусным действием")
	if has(c, "step_of_the_wind"):
		add.call("step_disengage", "Шаг ветра: отход (1 ки)", "bonus", false, "Отход бонусным действием")
		add.call("step_dash", "Шаг ветра: рывок (1 ки)", "bonus", false, "Рывок бонусным действием")
	if has(c, "stunning_strike"):
		add.call("stunning", "Оглушающий удар (1 ки)", "action", true, "Атака; при попадании — спасбросок Тел, иначе цель ошеломлена до конца вашего следующего хода")
	if has(c, "channel_divinity_turn_undead"):
		add.call("turn_undead", "Изгнание нежити", "action", false, "Нежить в 30 фт: спасбросок Мдр, иначе бежит; слабую — уничтожает")
	if has(c, "channel_divinity_preserve_life"):
		add.call("preserve_life", "Сохранение жизни", "action", false, "Лечит до половины максимума хитов (5 × уровень)")
	if has(c, "channel_divinity_sacred_weapon"):
		add.call("sacred_weapon", "Священное оружие", "action", false, "+Хар к атакам оружием на минуту")
	if has(c, "channel_divinity_turn_the_unholy"):
		add.call("turn_unholy", "Изгнание нечестивых", "action", false, "Исчадия и нежить в 30 фт: спасбросок Мдр, иначе бегут")
	if FeatureUses.owned(c, data).has("wild_shape"):
		add.call("wild_shape", "Дикий облик", "action", false, "Облик зверя: его хиты, КД и атаки")
	if FeatureUses.owned(c, data).has("sorcery_points"):
		add.call("font", "Источник магии", "bonus", false, "Ячейка ↔ очки чародейства")
	if CharacterRules.has_trait(c, "breath_weapon"):
		add.call("breath", "Оружие дыхания", "action", true, breath_text(c, data))
	return out


## "" when the feature action can be taken now, otherwise a localization key.
static func can_act(s: GameSession, data: Dictionary, id: String, target_id: String = "") -> String:
	var c := s.character
	if not CombatRules.is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	var e := CombatRules.economy(s)
	var spec: Dictionary = {}
	for a: Dictionary in actions(s, data):
		if str(a["id"]) == id:
			spec = a
	if spec.is_empty():
		return "COMBAT_NO_FEATURE"
	var cost := str(spec["cost"])
	if cost != "free" and int(e.get(cost, 0)) <= 0:
		return "COMBAT_NO_ACTION" if cost == "action" else "COMBAT_NO_BONUS"
	if id.begins_with("spell_"):
		return SpellEffects.can_act(s, data, id, target_id)
	var ki := {"flurry": 1, "patient_defense": 1, "step_disengage": 1, "step_dash": 1, "stunning": 0}
	for how: String in OPEN_HAND:
		ki["flurry_" + how] = 1
	if ki.has(id) and FeatureUses.left(c, data, "ki") < int(ki[id]):
		return "COMBAT_NO_KI"
	if id in ["martial_strike", "flurry"] or id.begins_with("flurry_"):
		if not bool(e.get("attacked", false)):
			return "COMBAT_ATTACK_FIRST"
	if id == "reckless" and (bool(e.get("attacked", false)) or bool(s.combat.get("reckless", false))):
		return "COMBAT_RECKLESS_LATE"
	if id in ["turn_undead", "preserve_life", "sacred_weapon", "turn_unholy"] and FeatureUses.left(c, data, "channel_divinity") <= 0:
		return "COMBAT_NO_CHARGE"
	if id == "wild_shape" and FeatureUses.left(c, data, "wild_shape") <= 0:
		return "COMBAT_NO_CHARGE"
	if id == "breath" and bool(c.get("breath_used", false)):
		return "COMBAT_NO_CHARGE"
	if bool(spec["target"]):
		var t := CombatRules.fighter(s, target_id)
		if t.is_empty() or str(t.get("status")) != "active" or str(t.get("side")) != "enemy":
			return "COMBAT_BAD_TARGET"
		var reach := 0 if id != "breath" else (1 if breath_shape(c, data) == "line" else 0)
		if absi(CombatRules.shown_col(t) - int(CombatRules.player(s)["col"])) > reach:
			return "COMBAT_OUT_OF_REACH"
	return ""


## Takes a feature action (can_act first). Lines.
static func act(s: GameSession, data: Dictionary, id: String, target_id: String = "") -> Array[String]:
	var c := s.character
	var e := CombatRules.economy(s)
	var lines: Array[String] = []
	var spend := func(cost: String) -> void:
		if cost != "free":
			e[cost] = int(e[cost]) - 1
	if id.begins_with("spell_"):
		return SpellEffects.act(s, data, id, target_id)
	match id:
		"flame_blade":
			spend.call("action")
			lines.append_array(CombatRules.strike(s, data, target_id, SpellEffects.blade_profile(c), {}))
		"move_mark":
			spend.call("bonus")
			SpellEffects.mark(c, target_id)
			lines.append("Метка охотника переходит на %s" % CombatRules.fighter(s, target_id).get("name", ""))
		"reckless":
			s.combat["reckless"] = true
			lines.append("%s атакует безрассудно: с преимуществом, но и открывшись" % c.get("name", ""))
		"martial_strike":
			spend.call("bonus")
			lines.append_array(CombatRules.strike(s, data, target_id, CombatRules.unarmed_profile(c, data), {}))
		"flurry", "flurry_topple", "flurry_push", "flurry_stagger":
			spend.call("bonus")
			FeatureUses.use(c, data, "ki", 1, s.rng)
			var how := id.trim_prefix("flurry_") if id != "flurry" else ""
			lines.append("%s: шквал ударов" % c.get("name", ""))
			for i in 2:
				var t := CombatRules.fighter(s, target_id)
				if t.is_empty() or str(t.get("status")) != "active":
					break
				lines.append_array(CombatRules.strike(s, data, target_id, CombatRules.unarmed_profile(c, data), {"open_hand": how}))
		"patient_defense":
			spend.call("bonus")
			FeatureUses.use(c, data, "ki", 1, s.rng)
			CombatRules.player(s)["dodging"] = true
			lines.append("%s: терпеливая оборона — уклоняется" % c.get("name", ""))
		"step_disengage", "step_dash":
			spend.call("bonus")
			FeatureUses.use(c, data, "ki", 1, s.rng)
			if id == "step_disengage":
				CombatRules.player(s)["disengaged"] = true
			else:
				e["move"] = int(e.get("move", 0)) + CombatRules._move_cols(int(c.get("speed", 30)), data)
			lines.append("%s: шаг ветра — %s" % [c.get("name", ""), "отход" if id == "step_disengage" else "рывок"])
		"stunning":
			var wid := str(c.get("equipped", {}).get("main_hand", ""))
			var w := CombatRules.weapon_profile(c, data, s.items, wid)
			if CombatRules.cols_between(CombatRules.player(s), CombatRules.fighter(s, target_id)) > 0 or not bool(w["melee"]):
				w = CombatRules.unarmed_profile(c, data)
			if int(e.get("attacks", 0)) > 0:
				e["attacks"] = int(e["attacks"]) - 1
			else:
				e["action"] = int(e["action"]) - 1
				e["attacks"] = CharacterRules.extra_attacks(c, data)
			e["attacked"] = true
			lines.append_array(CombatRules.strike(s, data, target_id, w, {"stunning": true}))
		"turn_undead", "turn_unholy":
			spend.call("action")
			FeatureUses.use(c, data, "channel_divinity", 1, s.rng)
			lines.append_array(_turn(s, data, ["undead"] if id == "turn_undead" else ["undead", "fiend"], id == "turn_undead"))
		"preserve_life":
			spend.call("action")
			FeatureUses.use(c, data, "channel_divinity", 1, s.rng)
			var cap := int(c["max_hp"]) / 2
			var heal := mini(5 * level(c), maxi(0, cap - int(c["hp"])))
			c["hp"] = int(c["hp"]) + heal
			lines.append("Сохранение жизни: +%d HP" % heal)
		"sacred_weapon":
			spend.call("action")
			FeatureUses.use(c, data, "channel_divinity", 1, s.rng)
			s.combat["sacred_weapon"] = 10
			lines.append("Священное оружие: +%d к атакам оружием на минуту" % maxi(1, ab_mod(c, "cha")))
		"wild_shape":
			var options: Array[Dictionary] = []
			for mid: String in beasts(c, data):
				var m: Dictionary = data["monsters"][mid]
				options.append({"id": mid, "label": "%s (HP %d, КД %d)" % [m["name"], int(m["hp"]), int(m["ac"])]})
			options.append({"id": "none", "label": "Не превращаться"})
			s.combat["prompt"] = {"kind": "wild_shape", "options": options, "text": "Дикий облик: в кого превратиться?"}
		"revert":
			spend.call("bonus")
			lines.append_array(end_shape(s, data, 0))
		"font":
			var options := font_options(c, data)
			options.append({"id": "none", "label": "Ничего"})
			s.combat["prompt"] = {"kind": "font", "options": options, "text": "Источник магии: очков %d" % FeatureUses.left(c, data, "sorcery_points")}
		"breath":
			spend.call("action")
			lines.append_array(_breath(s, data, target_id))
	return lines


## Turn Undead / Turn the Unholy: every foe of those types within 30 ft saves WIS against the spell DC or flees for a
## minute; a cleric's Destroy Undead kills the weak ones. Lines.
static func _turn(s: GameSession, data: Dictionary, types: Array, destroy: bool) -> Array[String]:
	var c := s.character
	var dc := int(c.get("spell_dc", 8 + CharacterRules.prof_bonus(c, data) + ab_mod(c, "wis")))
	var destroy_cr := float(CharacterRules.level_row(c, data).get("class_specific", {}).get("destroy_undead_cr", 0)) if destroy else 0.0
	var lines: Array[String] = []
	var any := false
	for id: String in CombatRules.enemies(s):
		var f := CombatRules.fighter(s, id)
		var m := CombatRules._monster(data, f)
		if not types.has(str(m.get("type", ""))) or CombatRules.cols_between(f, CombatRules.player(s)) > 1:
			continue
		any = true
		if CombatRules._monster_save(s, data, f, "wis", dc, ["magic"]):
			lines.append("%s выдерживает (Мдр против Сл %d)" % [f["name"], dc])
			continue
		if destroy_cr > 0.0 and float(m.get("cr", 9)) <= destroy_cr:
			f["hp"] = 0
			f["status"] = "dead"
			lines.append("%s рассыпается прахом" % f["name"])
			continue
		f["fleeing"] = true
		CombatRules._add_condition(f, "frightened", {"rounds": 10})
		lines.append("%s изгнан и бежит" % f["name"])
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


static func _wild_shape(s: GameSession, data: Dictionary, mid: String) -> Array[String]:
	var c := s.character
	if not data["monsters"].has(mid):
		return []
	var e := CombatRules.economy(s)
	e["action"] = int(e.get("action", 0)) - 1
	FeatureUses.use(c, data, "wild_shape", 1, s.rng)
	var m: Dictionary = data["monsters"][mid]
	c["wild_shape"] = {"monster": mid, "hp": int(m["hp"]), "max_hp": int(m["hp"])}  # concentration holds through it (5e)
	CharacterRules.refresh(c, data, s.items)
	return ["%s принимает облик: %s (HP %d, КД %d)" % [c.get("name", ""), m["name"], int(m["hp"]), int(m["ac"])]]


## The beast form ends; `overflow` — damage past its hit points goes to the hero. Lines.
static func end_shape(s: GameSession, data: Dictionary, overflow: int) -> Array[String]:
	var c := s.character
	if not c.has("wild_shape"):
		return []
	var name := str(data["monsters"].get(str(c["wild_shape"]["monster"]), {}).get("name", ""))
	c.erase("wild_shape")
	CharacterRules.refresh(c, data, s.items)
	var lines: Array[String] = ["%s снова в своём облике (был: %s)" % [c.get("name", ""), name]]
	if overflow > 0:
		lines.append("урон сверх облика: %d" % overflow)
		c["hp"] = maxi(0, int(c["hp"]) - overflow)
	return lines


## Damage to a hero in a beast form goes to the form first. Returns what is left for the hero.
static func hurt_shape(s: GameSession, data: Dictionary, dmg: int, lines: Array[String]) -> int:
	var c := s.character
	if not c.has("wild_shape") or dmg <= 0:
		return dmg
	var ws: Dictionary = c["wild_shape"]
	ws["hp"] = int(ws["hp"]) - dmg
	if int(ws["hp"]) > 0:
		return 0
	var over := -int(ws["hp"])
	lines.append_array(end_shape(s, data, 0))
	return over


## The profile of the beast's best melee attack (for the attack button in a beast form).
static func shape_profile(c: Dictionary, data: Dictionary) -> Dictionary:
	var m: Dictionary = data["monsters"].get(str(c["wild_shape"]["monster"]), {})
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
	var points := FeatureUses.left(c, data, "sorcery_points")
	var costs: Dictionary = cfg(data)["font_of_magic"]["slot_cost"]
	for lv: String in costs:
		var used := int(c.get("slots_used", [0, 0, 0, 0, 0])[int(lv) - 1])
		if used > 0 and points >= int(costs[lv]):
			out.append({"id": "slot_" + lv, "label": "Ячейка %s круга за %d очк." % [lv, int(costs[lv])]})
	for lv in range(1, 6):
		if SpellRules.slots_left(c, lv) > 0 and int(c.get("resources_used", {}).get("sorcery_points", 0)) >= lv:
			out.append({"id": "points_%d" % lv, "label": "Ячейку %d круга — в %d очк." % [lv, lv]})
	return out


static func font_convert(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	var used: Dictionary = c.get("resources_used", {})
	var slots: Array = (c.get("slots_used", [0, 0, 0, 0, 0]) as Array).duplicate()
	if CombatRules.active(s):
		var e := CombatRules.economy(s)
		e["bonus"] = int(e.get("bonus", 0)) - 1
	if id.begins_with("slot_"):
		var lv := int(id.trim_prefix("slot_"))
		var cost := int(cfg(data)["font_of_magic"]["slot_cost"][str(lv)])
		used["sorcery_points"] = int(used.get("sorcery_points", 0)) + cost
		slots[lv - 1] = maxi(0, int(slots[lv - 1]) - 1)
		c["slots_used"] = slots
		c["resources_used"] = used
		return ["Источник магии: ячейка %d круга за %d очк." % [lv, cost]]
	var lv := int(id.trim_prefix("points_"))
	slots[lv - 1] = int(slots[lv - 1]) + 1
	used["sorcery_points"] = maxi(0, int(used.get("sorcery_points", 0)) - lv)
	c["slots_used"] = slots
	c["resources_used"] = used
	return ["Источник магии: ячейка %d круга стала %d очк." % [lv, lv]]


## The metamagic options of the sorcerer: [{id, name, cost}].
static func metamagic(c: Dictionary, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table: Dictionary = cfg(data)["metamagic"]
	for id: String in table:
		if has(c, "metamagic_" + id):
			out.append({"id": id, "name": str(table[id]["name"]), "cost": int(table[id]["cost"])})
	return out


## The active metamagic of the next cast ("" none) when the hero can pay it.
static func active_metamagic(s: GameSession, data: Dictionary) -> String:
	var id := str(s.combat.get("metamagic", ""))
	if id.is_empty() or not cfg(data)["metamagic"].has(id):
		return ""
	return id if FeatureUses.left(s.character, data, "sorcery_points") >= int(cfg(data)["metamagic"][id]["cost"]) else ""


static func pay_metamagic(s: GameSession, data: Dictionary) -> String:
	var id := active_metamagic(s, data)
	if not id.is_empty():
		FeatureUses.use(s.character, data, "sorcery_points", int(cfg(data)["metamagic"][id]["cost"]), s.rng)
		s.combat.erase("metamagic")
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


## The dragonborn's breath on the column of `target_id` (a line reaches one column away, a cone — the hero's own). Lines.
static func _breath(s: GameSession, data: Dictionary, target_id: String) -> Array[String]:
	var c := s.character
	c["breath_used"] = true
	var dtype := breath_type(c, data)
	var ab := "con" if dtype in ["cold", "poison"] else "dex"
	var dc := 8 + ab_mod(c, "con") + CharacterRules.prof_bonus(c, data)
	var dice := "%dd6" % (2 if level(c) < 6 else 3)
	var col := int(CombatRules.fighter(s, target_id)["col"])
	var full := CombatRules.roll_dice(s.rng, dice)
	var lines: Array[String] = ["%s выдыхает %s" % [c.get("name", ""), data["misc"]["damage_types"].get(dtype, dtype)]]
	for id: String in CombatRules.enemies(s):
		var f := CombatRules.fighter(s, id)
		if int(f["col"]) != col:
			continue
		var ok := CombatRules._monster_save(s, data, f, ab, dc)
		var dmg := CombatRules._resist(data, f, dtype, full / 2 if ok else full)
		lines.append("%s: %s против Сл %d — %s, %d" % [f["name"], CombatRules.ab_name(ab), dc, "успех" if ok else "провал", dmg])
		CombatRules._hurt_enemy(s, data, f, dmg, lines, dtype)
	return lines


# --- per turn ----------------------------------------------------------------------------------------


## The end of the hero's turn: a rage with no attack and no damage taken ends; Sacred Weapon runs down. Lines.
static func end_hero_turn(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	if bool(s.combat.get("raging", false)):
		if not bool(s.combat.get("rage_kept", false)):
			s.combat["raging"] = false
			lines.append("Ярость угасает: за ход ни удара, ни раны")
		s.combat["rage_kept"] = false
	if int(s.combat.get("sacred_weapon", 0)) > 0:
		s.combat["sacred_weapon"] = int(s.combat["sacred_weapon"]) - 1
	s.combat.erase("reckless_until")


## Dark One's Blessing: the hero drops a foe on their own turn — temporary HP (CHA + warlock level).
static func on_kill(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	if has(c, "dark_ones_blessing") and CombatRules.current(s) == CombatRules.PLAYER:
		var thp := maxi(1, ab_mod(c, "cha") + level(c))
		if thp > int(c.get("temp_hp", 0)):
			c["temp_hp"] = thp
			lines.append("Благословение Тёмного: %d временных хитов" % thp)
