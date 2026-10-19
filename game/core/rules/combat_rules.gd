class_name CombatRules
extends RefCounted
## Combat (roadmap v0.6.1, ADR-0010 §7): the engine runs the fight, the master narrates each round.
## - The field is 7 columns of 30 ft on a line (−edge … edge); the player starts at 0. Melee — the same column;
##   weapon and spell ranges are counted in columns (beyond the normal range — disadvantage); shooting with a foe
##   in your column — disadvantage; leaving a column with a foe in it without Disengage — an attack of
##   opportunity; an area spell covers one column.
## - Initiative order; on the player's turn: action + bonus action + one move (Dash — one more); attacks
##   (Extra Attack, off-hand with a light weapon), engine spells (attack roll or save, damage, healing), Dodge,
##   Disengage, Dash, features and items through FeatureUses / ItemRules.
## - Enemies are SRD monsters run by a simple engine AI: melee closes in, shooters keep the range, morale at half
##   HP — intelligent foes surrender, the rest flee off the field.
## - 0 HP of the player in combat: death saves by 5e. The end: victory, the player fled, captured (stable among
##   intelligent foes), dead. XP by CR of everyone defeated, loot — their gear and the encounter's loot.
## State — `s.combat` (empty when there is no fight). Pure: no nodes, randomness from `s.rng`.

const PLAYER := "p"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["combat"]


static func edge(data: Dictionary) -> int:
	return int(cfg(data)["edge"])


static func active(s: GameSession) -> bool:
	return not s.combat.is_empty()


static func fighter(s: GameSession, id: String) -> Dictionary:
	return s.combat.get("fighters", {}).get(id, {})


static func player(s: GameSession) -> Dictionary:
	return fighter(s, PLAYER)


## Enemy ids, all or only those still in the fight.
static func enemies(s: GameSession, only_active: bool = true) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.combat.get("order", []):
		var f := fighter(s, id)
		if f.get("side") == "enemy" and (not only_active or str(f.get("status")) == "active"):
			out.append(id)
	return out


static func current(s: GameSession) -> String:
	var order: Array = s.combat.get("order", [])
	return str(order[int(s.combat.get("turn", 0))]) if not order.is_empty() else ""


static func is_player_turn(s: GameSession) -> bool:
	return active(s) and current(s) == PLAYER and str(s.combat.get("outcome", "")).is_empty()


static func cols_between(a: Dictionary, b: Dictionary) -> int:
	return absi(int(a.get("col", 0)) - int(b.get("col", 0)))


static func range_cols(data: Dictionary, feet: int) -> int:
	return int(ceil(feet / float(cfg(data)["col_ft"]))) if feet > 0 else 0


## A word for an enemy's health (the player never sees numbers): a localization key.
static func health_key(f: Dictionary) -> String:
	match str(f.get("status", "active")):
		"dead":
			return "HEALTH_DEAD"
		"fled":
			return "HEALTH_FLED"
		"surrendered":
			return "HEALTH_SURRENDERED"
	var hp := int(f.get("hp", 0))
	var mx := maxi(1, int(f.get("max_hp", 1)))
	if hp >= mx:
		return "HEALTH_FULL"
	if hp * 2 > mx:
		return "HEALTH_HURT"
	if hp * 4 > mx:
		return "HEALTH_BLOODIED"
	return "HEALTH_NEAR_DEATH"


# --- dice -----------------------------------------------------------------------------------------


## "2d6+3" (or "1d8+MOD" with `mod`) → total; a critical doubles the dice.
static func roll_dice(rng: RandomNumberGenerator, expr: String, crit: bool = false, mod: int = 0) -> int:
	var e := expr.replace(" ", "").replace("MOD", str(mod))
	var total := 0
	var parts := e.replace("-", "+-").split("+", false)
	for p: String in parts:
		if p.contains("d"):
			var n := int(p.get_slice("d", 0)) if not p.get_slice("d", 0).is_empty() else 1
			var sides := int(p.get_slice("d", 1))
			for i in n * (2 if crit else 1):
				total += rng.randi_range(1, sides)
		else:
			total += int(p)
	return total


static func _d20(rng: RandomNumberGenerator, adv: bool, dis: bool) -> Array[int]:
	var rolls: Array[int] = [rng.randi_range(1, 20)]
	if adv != dis:
		rolls.append(rng.randi_range(1, 20))
	return rolls


static func _nat(rolls: Array[int], adv: bool, dis: bool) -> int:
	if rolls.size() == 1:
		return rolls[0]
	return rolls.max() if adv and not dis else rolls.min()


# --- setup ----------------------------------------------------------------------------------------


## Starts a fight. `foes` = [{monster, count?, name?, desc?, col?, npc_id?}]; `source` = {encounter, room_from}.
## Returns the chat lines (who is here, the initiative order).
static func start(s: GameSession, data: Dictionary, foes: Array, source: Dictionary = {}) -> Array[String]:
	var mons: Dictionary = data["monsters"]
	var fighters := {}
	var c := s.character
	fighters[PLAYER] = {"id": PLAYER, "side": "player", "name": str(c.get("name", "")), "col": 0, "status": "active",
		"init": 0, "conditions": []}
	var n := 0
	var side := 1
	for spec: Dictionary in foes:
		var m: Dictionary = mons.get(str(spec.get("monster", "")), {})
		if m.is_empty():
			continue
		for i in int(spec.get("count", 1)):
			n += 1
			var ranged := (m["actions"] as Array).all(func(a: Dictionary) -> bool: return str(a.get("kind")) == "ranged")
			var col := int(spec["col"]) if spec.has("col") else side * int(cfg(data)["start_cols"]["ranged" if ranged else "melee"])
			side = -side
			var name := str(spec.get("name", m["name"]))
			if int(spec.get("count", 1)) > 1:
				name += " %d" % (i + 1)
			fighters["e%d" % n] = {"id": "e%d" % n, "side": "enemy", "monster": str(spec["monster"]), "name": name,
				"desc": str(spec.get("desc", "")), "hp": int(m["hp"]), "max_hp": int(m["hp"]), "ac": int(m["ac"]),
				"col": clampi(col, -edge(data), edge(data)), "status": "active", "conditions": [], "morale": false,
				"npc_id": str(spec.get("npc_id", ""))}
	s.combat = {"round": 1, "turn": 0, "fighters": fighters, "order": [], "log": [], "encounter": str(source.get("encounter", "")),
		"room_from": str(source.get("room_from", "")), "outcome": "", "death_saves": {"ok": 0, "fail": 0}, "loot": [], "xp": 0}
	# Initiative: d20 + DEX; ties — the higher DEX, then the player.
	var inits := []
	for id: String in fighters:
		var dex := CharacterRules.mod(int(c["abilities"]["dex"])) if id == PLAYER else CharacterRules.mod(int(mons[fighters[id]["monster"]]["abilities"]["dex"]))
		var roll := s.rng.randi_range(1, 20) + dex
		fighters[id]["init"] = roll
		inits.append([roll, dex, 1 if id == PLAYER else 0, id])
	inits.sort_custom(func(a: Array, b: Array) -> bool: return a.slice(0, 3) > b.slice(0, 3))
	s.combat["order"] = inits.map(func(x: Array) -> String: return str(x[3]))
	var names: Array = (s.combat["order"] as Array).map(func(id: String) -> String: return "%s %d" % [fighters[id]["name"], fighters[id]["init"]])
	var lines: Array[String] = ["Бой! Инициатива: " + ", ".join(names)]
	_begin_turn(s, data, lines)
	return lines


## Resets the economy of whoever's turn it is; the player at 0 HP rolls a death save instead.
static func _begin_turn(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var id := current(s)
	var f := fighter(s, id)
	f["dodging"] = false
	f["disengaged"] = false
	if id == PLAYER:
		s.combat["economy"] = {"action": 1, "bonus": 1, "move": _move_cols(int(s.character.get("speed", 30)), data), "attacks": 0,
			"attacked": false, "sneak": false}


static func _move_cols(speed: int, data: Dictionary) -> int:
	return maxi(1, speed / (int(cfg(data)["col_ft"]) * 2) + 1) if speed >= 60 else 1


# --- the player's actions ---------------------------------------------------------------------------


static func economy(s: GameSession) -> Dictionary:
	return s.combat.get("economy", {})


## The weapon attack of the character: {name, to_hit, dice, bonus, type, melee, range [normal, long] ft or [], light}.
static func weapon_profile(c: Dictionary, data: Dictionary, session_items: Dictionary, weapon_id: String, offhand: bool = false) -> Dictionary:
	var ab := c.get("abilities", {}) as Dictionary
	var str_mod := CharacterRules.mod(int(ab.get("str", 10)))
	var dex_mod := CharacterRules.mod(int(ab.get("dex", 10)))
	var prof := int(c.get("prof_bonus", 2))
	if weapon_id.is_empty():
		return {"name": "Безоружный удар", "to_hit": str_mod + prof, "dice": "1", "bonus": str_mod, "type": "bludgeoning",
			"melee": true, "range": [], "light": false, "id": ""}
	var def := ItemRules.def_of(data["items"], session_items, weapon_id)
	var w: Dictionary = def.get("weapon", {})
	var props: Array = def.get("properties", [])
	var ranged := str(w.get("range", "melee")) == "ranged"
	var mod := dex_mod if ranged else (maxi(str_mod, dex_mod) if props.has("finesse") else str_mod)
	var profs: Array = c.get("weapon_profs", [])
	var proficient := profs.has(str(w.get("category", ""))) or profs.has(weapon_id)
	var to_hit := mod + (prof if proficient else 0)
	var dice := str(w.get("damage", "1d4"))
	var eq: Dictionary = c.get("equipped", {})
	var bonus := mod
	if offhand and not _has_style(c, "two_weapon_fighting"):
		bonus = mini(0, mod)
	if ranged and _has_style(c, "archery"):
		to_hit += 2
	if not ranged and not props.has("two_handed") and str(eq.get("off_hand", "")).is_empty() and _has_style(c, "dueling"):
		bonus += 2
	if w.has("versatile") and str(eq.get("shield", "")).is_empty() and str(eq.get("off_hand", "")).is_empty() and not offhand:
		dice = str(w["versatile"])
	var rng: Array = w.get("reach_ft", [])
	if rng.is_empty() and props.has("thrown"):
		rng = [20, 60]
	if not rng.is_empty():
		rng = [int(rng[0]), int(rng[1])]
	return {"name": str(def.get("name", weapon_id)), "to_hit": to_hit, "dice": dice, "bonus": bonus,
		"type": str(w.get("damage_type", "bludgeoning")), "melee": not ranged, "range": rng, "light": props.has("light"), "id": weapon_id}


static func _has_style(c: Dictionary, style: String) -> bool:
	for f: Variant in c.get("features", []):
		if str(f).ends_with("fighting_style_" + style):
			return true
	return false


## "" when the player can attack `target` with this weapon now, otherwise the reason (a localization key).
static func can_attack(s: GameSession, data: Dictionary, target_id: String, offhand: bool = false) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	var e := economy(s)
	if offhand:
		if int(e.get("bonus", 0)) <= 0 or not bool(e.get("attacked", false)):
			return "COMBAT_NO_BONUS"
	elif int(e.get("attacks", 0)) <= 0 and int(e.get("action", 0)) <= 0:
		return "COMBAT_NO_ACTION"
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active":
		return "COMBAT_BAD_TARGET"
	var c := s.character
	var wid := str(c.get("equipped", {}).get("off_hand" if offhand else "main_hand", ""))
	var w := weapon_profile(c, data, s.items, wid, offhand)
	var d := cols_between(player(s), t)
	if d == 0:
		return ""
	if (w["range"] as Array).is_empty():
		return "COMBAT_OUT_OF_REACH"
	if d * int(cfg(data)["col_ft"]) > int(w["range"][1]):
		return "COMBAT_OUT_OF_RANGE"
	return ""


## A weapon attack of the player (can_attack first). Returns the lines.
static func player_attack(s: GameSession, data: Dictionary, target_id: String, offhand: bool = false) -> Array[String]:
	var c := s.character
	var e := economy(s)
	if offhand:
		e["bonus"] = int(e["bonus"]) - 1
	elif int(e.get("attacks", 0)) > 0:
		e["attacks"] = int(e["attacks"]) - 1
	else:
		e["action"] = int(e["action"]) - 1
		var extra := int(CharacterRules.level_row(c, data).get("class_specific", {}).get("extra_attacks", 0))
		e["attacks"] = extra
	e["attacked"] = true
	var wid := str(c.get("equipped", {}).get("off_hand" if offhand else "main_hand", ""))
	var w := weapon_profile(c, data, s.items, wid, offhand)
	var t := fighter(s, target_id)
	var d := cols_between(player(s), t)
	var ranged_use := d > 0
	var adv := _target_disabled(t) and not ranged_use or bool(player(s).get("hidden", false))
	var dis := bool(t.get("dodging", false)) or (ranged_use and d * int(cfg(data)["col_ft"]) > int(w["range"][0])) \
		or (not bool(w["melee"]) and _foe_in_column(s, player(s))) or ConditionRules.has(c, "poisoned") or ConditionRules.has(c, "frightened")
	var lines: Array[String] = []
	var bonus_dmg := 0
	if not ranged_use and bool(w["melee"]) and bool(s.combat.get("raging", false)):
		bonus_dmg += int(CharacterRules.level_row(c, data).get("class_specific", {}).get("rage_damage_bonus", 2))
	var sneak := ""
	var finesse_or_ranged: bool = not bool(w["melee"]) or (ItemRules.def_of(data["items"], s.items, wid).get("properties", []) as Array).has("finesse")
	if CharacterRules.has_feature(c, "sneak_attack") and not bool(e.get("sneak", false)) and adv and not dis and finesse_or_ranged:
		var sa: Dictionary = CharacterRules.level_row(c, data).get("class_specific", {}).get("sneak_attack", {})
		sneak = "%dd%d" % [int(sa.get("dice_count", 1)), int(sa.get("dice_value", 6))]
	var res := _attack(s, data, str(c.get("name", "")), w["name"], int(w["to_hit"]), adv, dis, t, str(w["dice"]), int(w["bonus"]) + bonus_dmg, str(w["type"]), lines, sneak)
	if bool(res["hit"]) and not sneak.is_empty():
		e["sneak"] = true
	player(s)["hidden"] = false
	return lines


static func _target_disabled(t: Dictionary) -> bool:
	for cnd: String in ["prone", "paralyzed", "stunned", "unconscious", "restrained"]:
		if (t.get("conditions", []) as Array).has(cnd):
			return true
	return false


static func _foe_in_column(s: GameSession, f: Dictionary) -> bool:
	var side := str(f.get("side"))
	for id: String in s.combat["order"]:
		var o := fighter(s, id)
		if str(o.get("side")) != side and str(o.get("status")) == "active" and int(o["col"]) == int(f["col"]) and not _target_disabled(o):
			return true
	return false


## One attack roll against an enemy and its damage; adds the line. {"hit", "damage"}.
static func _attack(s: GameSession, data: Dictionary, who: String, what: String, to_hit: int, adv: bool, dis: bool, t: Dictionary,
		dice: String, bonus: int, dtype: String, lines: Array[String], extra_dice: String = "") -> Dictionary:
	var rolls := _d20(s.rng, adv, dis)
	var nat := _nat(rolls, adv, dis)
	var total := nat + to_hit
	var hit := nat == 20 or (nat != 1 and total >= int(t["ac"]))
	var mark := " (с преимуществом)" if adv and not dis else " (с помехой)" if dis and not adv else ""
	var line := "%s — %s по %s: %d%s%d = %d против КД %d%s" % [who, what, t["name"], nat, " + " if to_hit >= 0 else " − ", absi(to_hit), total, int(t["ac"]), mark]
	if not hit:
		lines.append(line + " — промах")
		return {"hit": false, "damage": 0}
	var crit := nat == 20
	var dmg := maxi(1, roll_dice(s.rng, dice, crit) + bonus)
	if not extra_dice.is_empty():
		dmg += roll_dice(s.rng, extra_dice, crit)
	dmg = _resist(data, t, dtype, dmg)
	lines.append(line + (" — КРИТ! " if crit else " — попадание, ") + "%d (%s)%s" % [dmg, str(data["misc"]["damage_types"].get(dtype, dtype)),
		", Скрытая атака" if not extra_dice.is_empty() else ""])
	_hurt_enemy(s, data, t, dmg, lines)
	return {"hit": true, "damage": dmg}


static func _resist(data: Dictionary, t: Dictionary, dtype: String, dmg: int) -> int:
	var m: Dictionary = data["monsters"].get(str(t.get("monster", "")), {})
	var has := func(list: String) -> bool:
		for x: Variant in m.get(list, []):
			if str(x).to_lower().contains(dtype):
				return true
		return false
	if has.call("immunities"):
		return 0
	if has.call("resistances"):
		return dmg / 2
	if has.call("vulnerabilities"):
		return dmg * 2
	return dmg


## Damage to an enemy: 0 HP — down (dead); half HP — a morale check on its next turn.
static func _hurt_enemy(s: GameSession, data: Dictionary, t: Dictionary, dmg: int, lines: Array[String]) -> void:
	t["hp"] = maxi(0, int(t["hp"]) - dmg)
	if int(t["hp"]) == 0:
		t["status"] = "dead"
		lines.append("%s повержен" % t["name"])


## Engine spells (rules.combat.engine_spells): "" when castable at that target now, otherwise a reason.
static func is_engine_spell(data: Dictionary, spell_id: String) -> bool:
	return (cfg(data)["engine_spells"] as Array).has(spell_id)


static func spell_cost(data: Dictionary, spell_id: String) -> String:
	return "bonus" if str(data["spells"].get(spell_id, {}).get("casting_time", "")).contains("бонус") else "action"


static func can_cast(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	var cost := spell_cost(data, spell_id)
	if int(economy(s).get(cost, 0)) <= 0:
		return "COMBAT_NO_ACTION" if cost == "action" else "COMBAT_NO_BONUS"
	var chk := SpellRules.check(s.character, data, spell_id, slot)
	if chk.has("reason"):
		return str(chk["reason"])
	var sp: Dictionary = data["spells"][spell_id]
	if sp.has("heal_at_slot") or target_id.is_empty():
		return ""
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active" or str(t.get("side")) != "enemy":
		return "COMBAT_BAD_TARGET"
	if cols_between(player(s), t) > range_cols(data, int(sp.get("range_ft", 0))):
		return "COMBAT_OUT_OF_RANGE"
	return ""


## Casts a spell in combat (can_cast first): the slot, then attack rolls or saves, damage or healing. Lines.
static func player_cast(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String) -> Array[String]:
	var c := s.character
	var sp: Dictionary = data["spells"][spell_id]
	var e := economy(s)
	var cost := spell_cost(data, spell_id)
	e[cost] = int(e[cost]) - 1
	var chk := SpellRules.check(c, data, spell_id, slot)
	var lines: Array[String] = SpellRules.cast(c, data, chk["spell_id"], int(chk["slot"]))
	slot = int(chk["slot"])
	var level := int(c.get("level", 1))
	var ab := CharacterRules.mod(int(c["abilities"].get(str(c.get("spell_ability", "int")), 10)))
	if sp.has("heal_at_slot"):
		var heal := roll_dice(s.rng, str(sp["heal_at_slot"].get(str(maxi(1, slot)), "1d8+MOD")), false, ab)
		var before := int(c["hp"])
		c["hp"] = mini(int(c["max_hp"]), before + heal)
		lines.append("+%d HP" % (int(c["hp"]) - before))
		return lines
	if not is_engine_spell(data, spell_id) or target_id.is_empty():
		return lines
	var dice := _spell_dice(sp, slot, level)
	var t := fighter(s, target_id)
	var targets: Array[Dictionary] = [t]
	if sp.has("area"):
		targets = []
		var col := int(player(s)["col"]) if int(sp.get("range_ft", 0)) == 0 else int(t["col"])
		for id: String in enemies(s):
			if int(fighter(s, id)["col"]) == col:
				targets.append(fighter(s, id))
	var multi: Dictionary = cfg(data)["multi"].get(spell_id, {})
	var count := 1
	if multi.has("base"):
		count = int(multi["base"]) + int(multi.get("per_slot", 0)) * maxi(0, slot - maxi(1, int(sp["level"])))
	elif multi.has("by_level"):
		for k: String in multi["by_level"]:
			if level >= int(k):
				count = int(multi["by_level"][k])
	var dtype := str(sp.get("damage_type", ""))
	var name := str(sp["name"])
	for i in count:
		if not sp.has("area") and str(t.get("status")) != "active":
			break
		if bool(multi.get("auto_hit", false)):
			var dmg := _resist(data, t, dtype, roll_dice(s.rng, dice))
			lines.append("%s: %d (%s) по %s" % [name, dmg, data["misc"]["damage_types"].get(dtype, dtype), t["name"]])
			_hurt_enemy(s, data, t, dmg, lines)
		elif sp.has("attack"):
			var dis: bool = (str(sp["attack"]) == "ranged" and _foe_in_column(s, player(s))) or bool(t.get("dodging", false))
			_attack(s, data, str(c["name"]), name, int(c.get("spell_attack", 0)), false, dis, t, dice, 0, dtype, lines)
		elif sp.has("save"):
			var dmg_full := roll_dice(s.rng, dice)
			for tg: Dictionary in targets:
				if str(tg.get("status")) != "active":
					continue
				var ok := _monster_save(s, data, tg, str(sp["save"]["ability"]), int(c.get("spell_dc", 10)))
				var dmg := dmg_full / 2 if ok and str(sp["save"]["success"]) == "half" else (0 if ok else dmg_full)
				dmg = _resist(data, tg, dtype, dmg)
				lines.append("%s: %s — спасбросок %s против Сл %d %s, %d (%s)" % [name, tg["name"], ab_name(str(sp["save"]["ability"])),
					int(c.get("spell_dc", 10)), "успех" if ok else "провал", dmg, data["misc"]["damage_types"].get(dtype, dtype)])
				if dmg > 0:
					_hurt_enemy(s, data, tg, dmg, lines)
	return lines


static func ab_name(ab: String) -> String:
	return {"str": "Сил", "dex": "Лов", "con": "Тел", "int": "Инт", "wis": "Мдр", "cha": "Хар"}.get(ab, ab)


static func _spell_dice(sp: Dictionary, slot: int, level: int) -> String:
	if sp.has("damage_at_slot"):
		return str(sp["damage_at_slot"].get(str(maxi(slot, int(sp["level"]))), sp["damage_at_slot"].values()[0]))
	var best := "1d6"
	if sp.has("damage_at_level"):
		var keys: Array = (sp["damage_at_level"] as Dictionary).keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
		for k: Variant in keys:
			if level >= int(k):
				best = str(sp["damage_at_level"][k])
	return best


static func _monster_save(s: GameSession, data: Dictionary, t: Dictionary, ab: String, dc: int) -> bool:
	var m: Dictionary = data["monsters"][t["monster"]]
	var bonus := int(m["saves"].get(ab, CharacterRules.mod(int(m["abilities"].get(ab, 10)))))
	var roll := s.rng.randi_range(1, 20)
	if ab in ["str", "dex"] and _target_disabled(t) and not (t["conditions"] as Array).has("prone"):
		return false
	return roll != 1 and (roll == 20 or roll + bonus >= dc)


## Dodge / Disengage / Dash (an action; Disengage is a bonus action with Cunning Action or Nimble Escape).
static func player_simple(s: GameSession, data: Dictionary, what: String) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	var e := economy(s)
	var cost := "action"
	if what == "disengage" and CharacterRules.has_feature(s.character, "cunning_action") and int(e.get("bonus", 0)) > 0:
		cost = "bonus"
	if what == "dash" and CharacterRules.has_feature(s.character, "cunning_action") and int(e.get("bonus", 0)) > 0 and int(e.get("action", 0)) <= 0:
		cost = "bonus"
	if int(e.get(cost, 0)) <= 0:
		return "COMBAT_NO_ACTION" if cost == "action" else "COMBAT_NO_BONUS"
	e[cost] = int(e[cost]) - 1
	var p := player(s)
	match what:
		"dodge":
			p["dodging"] = true
		"disengage":
			p["disengaged"] = true
		"dash":
			e["move"] = int(e["move"]) + _move_cols(int(s.character.get("speed", 30)), data)
	return ""


## "" when the player can step one column in `dir` (−1 / +1) — off the edge means fleeing the fight.
static func can_move(s: GameSession, data: Dictionary, dir: int) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	if int(economy(s).get("move", 0)) <= 0:
		return "COMBAT_NO_MOVE"
	if absi(dir) != 1:
		return "COMBAT_BAD_MOVE"
	return ""


## Steps the player (can_move first): attacks of opportunity from foes left behind, fleeing off the edge. Lines.
static func player_move(s: GameSession, data: Dictionary, dir: int) -> Array[String]:
	var e := economy(s)
	e["move"] = int(e["move"]) - 1
	var p := player(s)
	var lines: Array[String] = []
	if not bool(p.get("disengaged", false)):
		for id: String in enemies(s):
			var f := fighter(s, id)
			if int(f["col"]) == int(p["col"]) and not _target_disabled(f):
				var act := _best_action(data, f, "melee")
				if not act.is_empty():
					lines.append("%s бьёт вдогонку" % f["name"])
					_enemy_attack(s, data, f, act, lines)
	if str(s.combat.get("outcome", "")) == "dead" or int(s.character["hp"]) <= 0:
		return lines
	var to := int(p["col"]) + dir
	if absi(to) > edge(data):
		s.combat["outcome"] = "player_fled"
		lines.append("%s выходит из боя" % s.character["name"])
		return lines
	p["col"] = to
	lines.append("%s: шаг на %d фт %s" % [s.character["name"], int(cfg(data)["col_ft"]), "вправо" if dir > 0 else "влево"])
	return lines


## The rest of the turn is skipped: next fighter. Returns the lines of the turns that follow
## until it is the player's turn again or the fight ends — the UI plays them one by one via next_actor().
static func end_player_turn(s: GameSession, data: Dictionary) -> void:
	_advance(s, data)


static func _advance(s: GameSession, data: Dictionary) -> void:
	var order: Array = s.combat["order"]
	var t := int(s.combat["turn"]) + 1
	if t >= order.size():
		t = 0
		s.combat["round"] = int(s.combat["round"]) + 1
		s.combat["round_ended"] = true
		s.combat.erase("raging_rounds")
	s.combat["turn"] = t
	var tmp: Array[String] = []
	_begin_turn(s, data, tmp)


## Runs the turn of the current non-player fighter (the AI) or the player's death save, then moves the turn on.
## Returns the lines. The UI calls it with a pause until is_player_turn() or an outcome.
static func next_actor(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var id := current(s)
	if id == PLAYER:
		if int(s.character["hp"]) <= 0:
			_death_save(s, lines)
			_check_end(s, data, lines)
			if str(s.combat["outcome"]).is_empty():
				_advance(s, data)
		return lines
	var f := fighter(s, id)
	if str(f.get("status")) == "active":
		_enemy_turn(s, data, f, lines)
	_check_end(s, data, lines)
	if str(s.combat["outcome"]).is_empty():
		_advance(s, data)
	return lines


static func _death_save(s: GameSession, lines: Array[String]) -> void:
	var ds: Dictionary = s.combat["death_saves"]
	if bool(ds.get("stable", false)):
		return
	var roll := s.rng.randi_range(1, 20)
	if roll == 20:
		s.character["hp"] = 1
		ConditionRules.remove(s.character, "unconscious")
		s.combat["death_saves"] = {"ok": 0, "fail": 0}
		lines.append("%s: спасбросок от смерти 20 — приходит в себя с 1 HP!" % s.character["name"])
		return
	if roll >= 10:
		ds["ok"] = int(ds["ok"]) + 1
	else:
		ds["fail"] = int(ds["fail"]) + (2 if roll == 1 else 1)
	lines.append("%s: спасбросок от смерти %d — успехов %d, провалов %d" % [s.character["name"], roll, mini(3, int(ds["ok"])), mini(3, int(ds["fail"]))])
	if int(ds["fail"]) >= 3:
		s.combat["outcome"] = "dead"
	elif int(ds["ok"]) >= 3:
		ds["stable"] = true
		lines.append("%s стабилизируется" % s.character["name"])


# --- enemies --------------------------------------------------------------------------------------


static func _monster(data: Dictionary, f: Dictionary) -> Dictionary:
	return data["monsters"][f["monster"]]


static func _intelligent(data: Dictionary, f: Dictionary) -> bool:
	return int(_monster(data, f)["abilities"].get("int", 1)) >= int(cfg(data)["intelligent_int"])


static func _best_action(data: Dictionary, f: Dictionary, kind: String) -> Dictionary:
	var best := {}
	for a: Dictionary in _monster(data, f)["actions"]:
		var ok := str(a.get("kind")) == kind or (kind == "ranged" and a.has("range"))
		if ok and (best.is_empty() or int(a.get("to_hit", 0)) > int(best.get("to_hit", 0))):
			best = a
	return best


static func _enemy_turn(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	f["dodging"] = false
	var p := player(s)
	var m := _monster(data, f)
	# Morale: once, at half HP or less.
	if not bool(f.get("morale", false)) and int(f["hp"]) * 2 <= int(f["max_hp"]):
		f["morale"] = true
		var wis := int(m["saves"].get("wis", CharacterRules.mod(int(m["abilities"].get("wis", 10)))))
		if s.rng.randi_range(1, 20) + wis < int(cfg(data)["morale_dc"]):
			if _intelligent(data, f) and int(f["col"]) == int(p["col"]):
				f["status"] = "surrendered"
				lines.append("%s бросает оружие и сдаётся" % f["name"])
				return
			f["fleeing"] = true
			lines.append("%s дрогнул и пытается бежать" % f["name"])
	var steps := _move_cols(int(m.get("speed", 30)), data)
	if bool(f.get("fleeing", false)):
		var dir := 1 if int(f["col"]) >= int(p["col"]) else -1
		for i in steps:
			if int(f["col"]) == int(p["col"]) and int(s.character["hp"]) > 0:
				var wid := str(s.character.get("equipped", {}).get("main_hand", ""))
				var w := weapon_profile(s.character, data, s.items, wid)
				if bool(w["melee"]):
					lines.append("%s бьёт вдогонку" % s.character["name"])
					_attack(s, data, str(s.character["name"]), w["name"], int(w["to_hit"]), false, false, f, str(w["dice"]), int(w["bonus"]), str(w["type"]), lines)
					if str(f["status"]) != "active":
						return
			var to := int(f["col"]) + dir
			if absi(to) > edge(data):
				f["status"] = "fled"
				lines.append("%s сбежал" % f["name"])
				return
			f["col"] = to
		return
	var down := int(s.character["hp"]) <= 0
	if down and _intelligent(data, f):
		lines.append("%s не добивает упавшего" % f["name"])
		return
	var melee := _best_action(data, f, "melee")
	var ranged := _best_action(data, f, "ranged")
	var save_act := {}
	for a: Dictionary in m["actions"]:
		if str(a.get("kind")) == "save":
			save_act = a
	var d := cols_between(f, p)
	if d == 0 and not melee.is_empty():
		_enemy_attack_full(s, data, f, melee, lines)
		return
	if not ranged.is_empty() and d > 0 and d * int(cfg(data)["col_ft"]) <= int(ranged["range"][1]):
		_enemy_attack_full(s, data, f, ranged, lines)
		return
	if d == 0 and melee.is_empty() and not ranged.is_empty():
		var away := 1 if int(f["col"]) >= 0 else -1
		if absi(int(f["col"]) + away) > edge(data):
			away = -away
		f["col"] = int(f["col"]) + away
		lines.append("%s отходит на расстояние выстрела" % f["name"])
		_enemy_attack_full(s, data, f, ranged, lines)
		return
	# Close in: a move, then attack if in reach or in range, else Dash (one more move).
	var dir := 1 if int(p["col"]) > int(f["col"]) else -1
	var moved := 0
	while moved < steps and cols_between(f, p) > 0:
		f["col"] = int(f["col"]) + dir
		moved += 1
	if cols_between(f, p) == 0 and not melee.is_empty():
		lines.append("%s сближается вплотную" % f["name"])
		_enemy_attack_full(s, data, f, melee, lines)
		return
	if not ranged.is_empty() and cols_between(f, p) * int(cfg(data)["col_ft"]) <= int(ranged["range"][1]):
		_enemy_attack_full(s, data, f, ranged, lines)
		return
	if cols_between(f, p) == 0 and not save_act.is_empty():
		_enemy_attack(s, data, f, save_act, lines)
		return
	while moved < steps * 2 and cols_between(f, p) > 0:
		f["col"] = int(f["col"]) + dir
		moved += 1
	lines.append("%s бежит ближе" % f["name"] if cols_between(f, p) > 0 else "%s сближается вплотную" % f["name"])


## The full attack of a monster: Multiattack when it has one for this kind of action.
static func _enemy_attack_full(s: GameSession, data: Dictionary, f: Dictionary, act: Dictionary, lines: Array[String]) -> void:
	var m := _monster(data, f)
	var seq: Array = m.get("multiattack", [])
	var by_en := {}
	for a: Dictionary in m["actions"]:
		by_en[str(a["name_en"])] = a
	var plan: Array[Dictionary] = []
	for x: Dictionary in seq:
		var a: Dictionary = by_en.get(str(x["action"]), {})
		if not a.is_empty() and (str(a.get("kind")) == str(act.get("kind")) or (str(act.get("kind")) == "ranged" and a.has("range"))):
			for i in int(x["count"]):
				plan.append(a)
	if plan.is_empty():
		plan.append(act)
	for a: Dictionary in plan:
		if int(s.character["hp"]) <= 0 and _intelligent(data, f):
			return
		if str(s.combat.get("outcome", "")) == "dead":
			return
		_enemy_attack(s, data, f, a, lines)


static func _enemy_attack(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	var p := player(s)
	var dtypes: Dictionary = data["misc"]["damage_types"]
	if str(a.get("kind")) == "save":
		var sv: Dictionary = a["save"]
		var ab := str(sv["ability"])
		var roll := s.rng.randi_range(1, 20)
		var ok := roll != 1 and (roll == 20 or roll + int(c["saves"].get(ab, 0)) >= int(sv["dc"]))
		var full := 0
		for d: Dictionary in a["damage"]:
			full += roll_dice(s.rng, str(d["dice"]))
		var dmg := full / 2 if ok and str(sv["success"]) == "half" else (0 if ok else full)
		lines.append("%s — %s: спасбросок %s %d против Сл %d — %s, %d урона" % [f["name"], a["name"], ab_name(ab), roll + int(c["saves"].get(ab, 0)),
			int(sv["dc"]), "успех" if ok else "провал", dmg])
		_hurt_player(s, data, dmg, false, lines)
		return
	var d := cols_between(f, p)
	var ranged_use := d > 0
	var adv := (_target_disabled_player(c) and not ranged_use) or (_has_trait(data, f, "pack_tactics") and _ally_near_player(s, f))
	var dis := bool(p.get("dodging", false)) and int(c["hp"]) > 0 or (ranged_use and a.has("range") and d * int(cfg(data)["col_ft"]) > int(a["range"][0])) \
		or (str(a.get("kind")) == "ranged" and d == 0) or (f["conditions"] as Array).has("poisoned")
	var rolls := _d20(s.rng, adv, dis)
	var nat := _nat(rolls, adv, dis)
	var total := nat + int(a.get("to_hit", 0))
	var ac := int(c.get("ac", 10))
	var hit := nat == 20 or (nat != 1 and total >= ac)
	var mark := " (с преимуществом)" if adv and not dis else " (с помехой)" if dis and not adv else ""
	var line := "%s — %s: %d + %d = %d против КД %d%s" % [f["name"], a["name"], nat, int(a.get("to_hit", 0)), total, ac, mark]
	if not hit:
		lines.append(line + " — промах")
		return
	var crit := nat == 20 or (int(c["hp"]) <= 0 and not ranged_use)
	var dmg := 0
	var types: Array[String] = []
	for dd: Dictionary in a["damage"]:
		dmg += roll_dice(s.rng, str(dd["dice"]), crit)
		types.append(str(dtypes.get(str(dd["type"]), dd["type"])))
	dmg = maxi(1, dmg)
	lines.append(line + (" — КРИТ! " if crit else " — попадание, ") + "%d (%s)" % [dmg, ", ".join(types)])
	_hurt_player(s, data, dmg, crit, lines)


static func _target_disabled_player(c: Dictionary) -> bool:
	for cnd: String in ["prone", "paralyzed", "stunned", "unconscious", "restrained"]:
		if ConditionRules.has(c, cnd):
			return true
	return int(c.get("hp", 1)) <= 0


static func _has_trait(data: Dictionary, f: Dictionary, trait_id: String) -> bool:
	return (_monster(data, f)["traits"] as Array).any(func(t: Dictionary) -> bool: return str(t["id"]) == trait_id)


static func _ally_near_player(s: GameSession, f: Dictionary) -> bool:
	for id: String in enemies(s):
		if id != str(f["id"]) and int(fighter(s, id)["col"]) == int(player(s)["col"]):
			return true
	return false


## Damage to the player: 0 HP — unconscious and death saves; hits at 0 HP — failed saves; massive damage — death.
static func _hurt_player(s: GameSession, data: Dictionary, dmg: int, crit: bool, lines: Array[String]) -> void:
	var c := s.character
	if dmg <= 0:
		return
	var ds: Dictionary = s.combat["death_saves"]
	if int(c["hp"]) <= 0:
		ds["fail"] = int(ds["fail"]) + (2 if crit else 1)
		ds["stable"] = false
		lines.append("%s: провал спасброска от смерти (%d из 3)" % [c["name"], mini(3, int(ds["fail"]))])
		if int(ds["fail"]) >= 3:
			s.combat["outcome"] = "dead"
		return
	var left := int(c["hp"]) - dmg
	if left > 0:
		c["hp"] = left
		return
	c["hp"] = 0
	if -left >= int(c["max_hp"]):
		s.combat["outcome"] = "dead"
		lines.append("%s погибает на месте" % c["name"])
		return
	ConditionRules.add(c, "unconscious", "long_rest")
	c["concentration"] = ""
	s.combat["death_saves"] = {"ok": 0, "fail": 0}
	s.combat.erase("raging")
	lines.append("%s падает без сознания" % c["name"])


# --- the end --------------------------------------------------------------------------------------


static func _check_end(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	if not str(s.combat.get("outcome", "")).is_empty():
		return
	if enemies(s).is_empty():
		s.combat["outcome"] = "victory"
		lines.append("Победа!")
		return
	var ds: Dictionary = s.combat["death_saves"]
	if int(s.character["hp"]) <= 0 and bool(ds.get("stable", false)) \
			and enemies(s).all(func(id: String) -> bool: return _intelligent(data, fighter(s, id))):
		s.combat["outcome"] = "captured"
		lines.append("%s остаётся лежать — враги берут его живым" % s.character["name"])


## Checks the outcome after a player action (an enemy may have fallen). Returns the lines.
static func after_player_action(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	_check_end(s, data, lines)
	return lines


## XP of a won fight: everyone defeated, fled or surrendered; loot — gear of the defeated and surrendered and the
## encounter's loot. Fills s.combat.xp / loot [{item_id, qty}] / coins_cp.
static func results(s: GameSession, data: Dictionary, encounter_loot: Dictionary) -> void:
	var xp := 0
	var loot := {}
	for id: String in enemies(s, false):
		var f := fighter(s, id)
		var m := _monster(data, f)
		if str(f["status"]) != "active":
			xp += int(m["xp"])
		if str(f["status"]) in ["dead", "surrendered"]:
			for item: Variant in m.get("equipment", []):
				if data["items"]["catalog"].has(str(item)):
					loot[str(item)] = int(loot.get(str(item), 0)) + 1
	for item: String in encounter_loot.get("items", {}):
		loot[item] = int(loot.get(item, 0)) + int(encounter_loot["items"][item])
	s.combat["xp"] = xp if str(s.combat["outcome"]) == "victory" else 0
	s.combat["coins_cp"] = int(encounter_loot.get("coins_cp", 0)) if str(s.combat["outcome"]) == "victory" else 0
	var list: Array = []
	if str(s.combat["outcome"]) == "victory":
		for item: String in loot:
			list.append({"item_id": item, "qty": int(loot[item])})
	s.combat["loot"] = list


## The snapshot block for the master: the field, health words, the log of the round, the outcome.
static func snapshot(s: GameSession, data: Dictionary) -> Dictionary:
	var foes: Array[Dictionary] = []
	var p := player(s)
	for id: String in enemies(s, false):
		var f := fighter(s, id)
		foes.append({"id": id, "name": f["name"], "monster": _monster(data, f)["name"], "distance_ft": cols_between(f, p) * int(cfg(data)["col_ft"]),
			"side": "left" if int(f["col"]) < int(p["col"]) else "right" if int(f["col"]) > int(p["col"]) else "same",
			"status": f["status"], "health": health_key(f).trim_prefix("HEALTH_").to_lower(), "description": f.get("desc", "")})
	return {"round": int(s.combat.get("round", 1)), "enemies": foes, "outcome": str(s.combat.get("outcome", "")),
		"player_down": int(s.character.get("hp", 1)) <= 0, "log": s.combat.get("log", [])}
