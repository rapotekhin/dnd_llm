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
##   intelligent foes), dead, truce (persuasion). XP by CR of everyone defeated, loot — their gear and the
##   encounter's loot.
## - v0.6.2: surprise (the player sneaks in — Stealth against each foe's passive Perception; a pack ambush — the
##   foes' Stealth against the player's), Hide in combat (not with a foe in your column; hidden — advantage, foes
##   attack with disadvantage; an attack or a spell reveals), reinforcements (pack waves, a foe calls for help,
##   the master's start_combat — all come at the edge column at the start of a round), parley (Intimidation —
##   intelligent foes surrender or flee, Persuasion — truce; one try per skill), the hit hint before the click.
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
		"truce":
			return "HEALTH_TRUCE"
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
## `source` may add (v0.6.2): sneak (the player sneaks in), ambush (the foes lie in wait), waves [{round, side,
## enemies}] and help {enemies, side, delay} of a pack encounter.
static func start(s: GameSession, data: Dictionary, foes: Array, source: Dictionary = {}) -> Array[String]:
	var c := s.character
	var fighters := {}
	fighters[PLAYER] = {"id": PLAYER, "side": "player", "name": str(c.get("name", "")), "col": 0, "status": "active",
		"init": 0, "conditions": []}
	s.combat = {"round": 1, "turn": 0, "fighters": fighters, "order": [], "log": [], "encounter": str(source.get("encounter", "")),
		"room_from": str(source.get("room_from", "")), "outcome": "", "death_saves": {"ok": 0, "fail": 0}, "loot": [], "xp": 0,
		"next_id": 0, "incoming": [], "help": (source.get("help", {}) as Dictionary).duplicate(true), "parley_tried": []}
	_add_foes(s, data, foes)
	for w: Dictionary in source.get("waves", []):
		add_incoming(s, data, w.get("enemies", []), int(w.get("round", 2)), str(w.get("side", "right")))
	# Initiative: d20 + DEX; ties — the higher DEX, then the player.
	var inits := []
	for id: String in fighters:
		var dex := _dex_of(s, data, id)
		var roll := s.rng.randi_range(1, 20) + dex
		fighters[id]["init"] = roll
		inits.append([roll, dex, 1 if id == PLAYER else 0, id])
	inits.sort_custom(func(a: Array, b: Array) -> bool: return a.slice(0, 3) > b.slice(0, 3))
	s.combat["order"] = inits.map(func(x: Array) -> String: return str(x[3]))
	var names: Array = (s.combat["order"] as Array).map(func(id: String) -> String: return "%s %d" % [fighters[id]["name"], fighters[id]["init"]])
	var lines: Array[String] = ["Бой! Инициатива: " + ", ".join(names)]
	lines.append_array(_surprise(s, data, source))
	_begin_turn(s, data, lines)
	return lines


static func _dex_of(s: GameSession, data: Dictionary, id: String) -> int:
	if id == PLAYER:
		return CharacterRules.mod(int(s.character["abilities"]["dex"]))
	return CharacterRules.mod(int(_monster(data, fighter(s, id))["abilities"]["dex"]))


## Adds fighters for `specs` [{monster, count?, name?, desc?, col?, npc_id?}]; `col_at` puts them all in one
## column (reinforcements at the edge). A name that is already in the fight gets the next number. Returns the ids.
static func _add_foes(s: GameSession, data: Dictionary, specs: Array, col_at: int = 99) -> Array[String]:
	var mons: Dictionary = data["monsters"]
	var fighters: Dictionary = s.combat["fighters"]
	var ids: Array[String] = []
	var side := 1
	for spec: Dictionary in specs:
		var m: Dictionary = mons.get(str(spec.get("monster", "")), {})
		if m.is_empty():
			continue
		var count := int(spec.get("count", 1))
		var base := str(spec.get("name", m["name"]))
		var same := fighters.values().filter(func(f: Dictionary) -> bool: return str(f.get("base", "")) == base).size()
		for i in count:
			var n := int(s.combat.get("next_id", 0)) + 1
			s.combat["next_id"] = n
			var ranged := (m["actions"] as Array).all(func(a: Dictionary) -> bool: return str(a.get("kind")) == "ranged")
			var col := col_at if col_at != 99 else (int(spec["col"]) if spec.has("col") else side * int(cfg(data)["start_cols"]["ranged" if ranged else "melee"]))
			side = -side
			var name := base
			if count > 1 or same > 0:
				name += " %d" % (same + i + 1)
			var id := "e%d" % n
			fighters[id] = {"id": id, "side": "enemy", "monster": str(spec["monster"]), "name": name, "base": base,
				"desc": str(spec.get("desc", "")), "hp": int(m["hp"]), "max_hp": int(m["hp"]), "ac": int(m["ac"]),
				"col": clampi(col, -edge(data), edge(data)), "status": "active", "conditions": [], "morale": false,
				"npc_id": str(spec.get("npc_id", ""))}
			ids.append(id)
	return ids


# --- surprise and stealth (v0.6.2) -------------------------------------------------------------------


## The player's Stealth roll: d20 + skill, disadvantage from armor (stealth_disadvantage) and conditions.
## {total, nat, note}.
static func stealth_roll(s: GameSession, data: Dictionary) -> Dictionary:
	var c := s.character
	var armor := ItemRules.def_of(data["items"], s.items, str(c.get("equipped", {}).get("armor", "")))
	var dis := bool(armor.get("armor", {}).get("stealth_disadvantage", false))
	var why: Array[String] = []
	if dis:
		why.append("доспех")
	var mods := ConditionRules.check_mods(c, data, {"skill": "stealth"})
	if not (mods["disadvantage"] as Array).is_empty():
		dis = true
		why.append("состояние")
	var boots := CharacterRules.carried_with(c, data, s.items, "stealth_advantage")
	var adv := not boots.is_empty()
	var rolls := _d20(s.rng, adv, dis)
	var nat := _nat(rolls, adv, dis)
	var note := ""
	if dis and not adv:
		note = " (с помехой: %s)" % ", ".join(why)
	elif adv and not dis:
		note = " (с преимуществом: %s)" % boots
	return {"total": nat + int(c.get("skills", {}).get("stealth", 0)), "nat": nat, "note": note}


static func monster_passive(data: Dictionary, f: Dictionary) -> int:
	var m := _monster(data, f)
	return int(m.get("passive_perception", 10 + CharacterRules.mod(int(m["abilities"].get("wis", 10)))))


static func _monster_stealth(data: Dictionary, f: Dictionary) -> int:
	var m := _monster(data, f)
	return int(m.get("skills", {}).get("stealth", CharacterRules.mod(int(m["abilities"].get("dex", 10)))))


## Surprise at the start (5e): a sneaking player rolls Stealth once — every foe whose passive Perception it meets is
## surprised (all of them — the player starts hidden); a pack ambush — each foe rolls Stealth against the player's
## passive Perception, and only when every one of them beats it the player is surprised.
static func _surprise(s: GameSession, data: Dictionary, source: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var who := str(s.character.get("name", ""))
	var foes := enemies(s)
	if foes.is_empty():
		return lines
	if bool(source.get("sneak", false)):
		var roll := stealth_roll(s, data)
		var unseen: Array[String] = []
		var seen: Array[String] = []
		for id: String in foes:
			var f := fighter(s, id)
			if int(roll["total"]) >= monster_passive(data, f):
				f["surprised"] = true
				unseen.append(str(f["name"]))
			else:
				seen.append(str(f["name"]))
		var line := "%s крадётся: Скрытность %d%s" % [who, int(roll["total"]), roll["note"]]
		if not unseen.is_empty():
			line += " — застигнуты врасплох: " + ", ".join(unseen)
		if not seen.is_empty():
			line += ("; " if not unseen.is_empty() else " — ") + "замечают: " + ", ".join(seen)
		lines.append(line)
		if seen.is_empty():
			player(s)["hidden"] = true
			lines.append("Враги не знают, где %s" % who)
	elif bool(source.get("ambush", false)):
		var passive := int(s.character.get("passive_perception", 10))
		var all_hidden := true
		for id: String in foes:
			if s.rng.randi_range(1, 20) + _monster_stealth(data, fighter(s, id)) < passive:
				all_hidden = false
		if all_hidden:
			player(s)["surprised"] = true
			lines.append("Засада! Враги подкрались незаметно — %s пропускает первый ход" % who)
		else:
			lines.append("Засада, но %s вовремя замечает врагов (пассивная Внимательность %d)" % [who, passive])
	return lines


## The player's turn is skipped: at 0 HP (death saves instead) or surprised in the first round.
static func player_skips(s: GameSession) -> bool:
	return int(s.character.get("hp", 0)) <= 0 or bool(player(s).get("surprised", false))


## The player can press buttons now.
static func player_can_act(s: GameSession) -> bool:
	return is_player_turn(s) and not player_skips(s)


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
	var magic := ItemRules.plus(def, ["magic_plus"])  # a +N weapon (v0.6.3)
	to_hit += magic
	bonus += magic
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
	var mods := _attack_mods(s, data, w, t)
	var adv := not (mods["adv"] as Array).is_empty()
	var dis := not (mods["dis"] as Array).is_empty()
	var lines: Array[String] = []
	var bonus_dmg := _rage_bonus(s, data, w, t)
	var sneak := _sneak_dice(s, data, w, adv, dis)
	var res := _attack(s, data, str(c.get("name", "")), w["name"], int(w["to_hit"]), adv, dis, t, str(w["dice"]), int(w["bonus"]) + bonus_dmg, str(w["type"]), lines, sneak)
	if bool(res["hit"]) and not sneak.is_empty():
		e["sneak"] = true
	player(s)["hidden"] = false
	return lines


## Why a weapon attack at `t` has advantage or disadvantage now: {"adv": [reasons], "dis": [reasons]}.
static func _attack_mods(s: GameSession, data: Dictionary, w: Dictionary, t: Dictionary) -> Dictionary:
	var c := s.character
	var d := cols_between(player(s), t)
	var adv: Array[String] = []
	var dis: Array[String] = []
	if _target_disabled(t) and d == 0:
		adv.append("цель беспомощна")
	if bool(player(s).get("hidden", false)):
		adv.append("вы спрятаны")
	if bool(t.get("dodging", false)):
		dis.append("цель уклоняется")
	if d > 0 and not (w["range"] as Array).is_empty() and d * int(cfg(data)["col_ft"]) > int(w["range"][0]):
		dis.append("дальше обычной дальности")
	if not bool(w["melee"]) and _foe_in_column(s, player(s)):
		dis.append("враг вплотную")
	if ConditionRules.has(c, "poisoned"):
		dis.append("вы отравлены")
	if ConditionRules.has(c, "frightened"):
		dis.append("вы испуганы")
	return {"adv": adv, "dis": dis}


static func _rage_bonus(s: GameSession, data: Dictionary, w: Dictionary, t: Dictionary) -> int:
	if cols_between(player(s), t) == 0 and bool(w["melee"]) and bool(s.combat.get("raging", false)):
		return int(CharacterRules.level_row(s.character, data).get("class_specific", {}).get("rage_damage_bonus", 2))
	return 0


## Sneak Attack dice once a turn: a finesse or ranged weapon with advantage and without disadvantage; "" otherwise.
static func _sneak_dice(s: GameSession, data: Dictionary, w: Dictionary, adv: bool, dis: bool) -> String:
	var c := s.character
	var finesse_or_ranged: bool = not bool(w["melee"]) or (ItemRules.def_of(data["items"], s.items, str(w.get("id", ""))).get("properties", []) as Array).has("finesse")
	if CharacterRules.has_feature(c, "sneak_attack") and not bool(economy(s).get("sneak", false)) and adv and not dis and finesse_or_ranged:
		var sa: Dictionary = CharacterRules.level_row(c, data).get("class_specific", {}).get("sneak_attack", {})
		return "%dd%d" % [int(sa.get("dice_count", 1)), int(sa.get("dice_value", 6))]
	return ""


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
	var lines := _player_cast(s, data, spell_id, slot, target_id)
	player(s)["hidden"] = false  # casting gives the player away
	return lines


static func _player_cast(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String) -> Array[String]:
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
			_attack(s, data, str(c["name"]), name, int(c.get("spell_attack", 0)), bool(player(s).get("hidden", false)), dis, t, dice, 0, dtype, lines)
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


## Hide (v0.6.2): an action (a bonus action with Cunning Action); not with a foe in the player's column.
static func can_hide(s: GameSession, data: Dictionary) -> String:
	if not player_can_act(s):
		return "COMBAT_NOT_YOUR_TURN"
	if bool(player(s).get("hidden", false)):
		return "COMBAT_ALREADY_HIDDEN"
	if _foe_in_column(s, player(s)):
		return "COMBAT_HIDE_SEEN"
	var cost := _hide_cost(s)
	if int(economy(s).get(cost, 0)) <= 0:
		return "COMBAT_NO_ACTION" if cost == "action" else "COMBAT_NO_BONUS"
	return ""


static func _hide_cost(s: GameSession) -> String:
	return "bonus" if CharacterRules.has_feature(s.character, "cunning_action") and int(economy(s).get("bonus", 0)) > 0 else "action"


## Stealth against the best passive Perception of the foes still fighting (can_hide first). Lines.
static func player_hide(s: GameSession, data: Dictionary) -> Array[String]:
	var e := economy(s)
	var cost := _hide_cost(s)
	e[cost] = int(e[cost]) - 1
	var roll := stealth_roll(s, data)
	var best := 0
	for id: String in enemies(s):
		best = maxi(best, monster_passive(data, fighter(s, id)))
	var ok := int(roll["total"]) >= best
	if ok:
		player(s)["hidden"] = true
	return ["%s прячется: Скрытность %d%s против Внимательности %d — %s" % [s.character["name"], int(roll["total"]), roll["note"], best,
		"враги теряют из виду" if ok else "враги всё видят"]]


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


## The rest of the turn is skipped: next fighter (the UI plays the others one by one via next_actor()).
## Returns the lines of a new round's start (reinforcements arriving).
static func end_player_turn(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	_advance(s, data, lines)
	return lines


static func _advance(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var order: Array = s.combat["order"]
	var t := int(s.combat["turn"]) + 1
	if t >= order.size():
		t = 0
		s.combat["round"] = int(s.combat["round"]) + 1
		s.combat["round_ended"] = true
		s.combat.erase("raging_rounds")
		for id: String in order:
			fighter(s, id).erase("surprised")  # surprise lasts the first round only
		s.combat["turn"] = 0
		_arrivals(s, data, lines)
	s.combat["turn"] = t
	_begin_turn(s, data, lines)


# --- reinforcements (v0.6.2) ---------------------------------------------------------------------


## Enemies who join later: grey at the edge column on `side` until they arrive at the start of round `at`.
static func add_incoming(s: GameSession, data: Dictionary, foes: Array, at: int, side: String) -> void:
	var names: Array = []
	var specs: Array = []
	for spec: Variant in foes:
		if not (spec is Dictionary) or not data["monsters"].has(str(spec.get("monster", ""))):
			continue
		var m: Dictionary = data["monsters"][spec["monster"]]
		var n := int(spec.get("count", 1))
		names.append(str(spec.get("name", m["name"])) + (" ×%d" % n if n > 1 else ""))
		specs.append((spec as Dictionary).duplicate(true))
	if specs.is_empty():
		return
	(s.combat["incoming"] as Array).append({"at": at, "col": edge(data) * (-1 if side == "left" else 1), "foes": specs, "names": names})


## XP of the enemies still fighting and on the way (the master's reinforcements stay within the level's budget).
static func xp_in_play(s: GameSession, data: Dictionary) -> int:
	var xp := 0
	for id: String in enemies(s):
		xp += int(_monster(data, fighter(s, id))["xp"])
	for w: Dictionary in s.combat.get("incoming", []):
		for spec: Dictionary in w["foes"]:
			xp += int(data["monsters"][spec["monster"]]["xp"]) * int(spec.get("count", 1))
	return xp


static func _arrivals(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var left: Array = []
	for w: Dictionary in s.combat.get("incoming", []):
		if int(w["at"]) > int(s.combat["round"]):
			left.append(w)
			continue
		var ids := _add_foes(s, data, w["foes"], int(w["col"]))
		for id: String in ids:
			_insert_initiative(s, data, id)
		lines.append("Подкрепление %s: %s" % ["слева" if int(w["col"]) < 0 else "справа",
			", ".join(ids.map(func(id: String) -> String: return str(fighter(s, id)["name"])))])
	s.combat["incoming"] = left


## A newcomer rolls initiative and takes its place in the order (called at the start of a round, turn 0).
static func _insert_initiative(s: GameSession, data: Dictionary, id: String) -> void:
	var f := fighter(s, id)
	f["init"] = s.rng.randi_range(1, 20) + _dex_of(s, data, id)
	var order: Array = s.combat["order"]
	var at := order.size()
	for i in order.size():
		if int(fighter(s, str(order[i]))["init"]) < int(f["init"]):
			at = i
			break
	order.insert(at, id)


## Runs the turn of the current non-player fighter (the AI) or the player's death save, then moves the turn on.
## Returns the lines. The UI calls it with a pause until is_player_turn() or an outcome.
static func next_actor(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var id := current(s)
	if id == PLAYER:
		if int(s.character["hp"]) <= 0:
			_death_save(s, lines)
		elif bool(player(s).get("surprised", false)):
			player(s).erase("surprised")
			lines.append("%s застигнут врасплох и не успевает ничего сделать" % s.character["name"])
		else:
			return lines
		_check_end(s, data, lines)
		if str(s.combat["outcome"]).is_empty():
			_advance(s, data, lines)
		return lines
	var f := fighter(s, id)
	if str(f.get("status")) == "active":
		if bool(f.get("surprised", false)):
			f.erase("surprised")
			lines.append("%s застигнут врасплох и не успевает ничего сделать" % f["name"])
		else:
			_enemy_turn(s, data, f, lines)
	_check_end(s, data, lines)
	if str(s.combat["outcome"]).is_empty():
		_advance(s, data, lines)
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
	var help: Dictionary = s.combat.get("help", {})
	if not help.is_empty() and not bool(s.combat.get("help_called", false)) and _intelligent(data, f) and int(s.character["hp"]) > 0 \
			and (int(f["hp"]) * 2 <= int(f["max_hp"]) or enemies(s, false).size() > enemies(s).size()):
		s.combat["help_called"] = true
		add_incoming(s, data, help.get("enemies", []), int(s.combat["round"]) + int(help.get("delay", cfg(data)["help_delay"])),
			str(help.get("side", "right")))
		lines.append("%s зовёт на помощь!" % f["name"])
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
	_find_hidden(s, f, lines)
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
	_find_hidden(s, f, lines)
	lines.append("%s бежит ближе" % f["name"] if cols_between(f, p) > 0 else "%s сближается вплотную" % f["name"])


## A foe that comes into the hidden player's column finds them.
static func _find_hidden(s: GameSession, f: Dictionary, lines: Array[String]) -> void:
	var p := player(s)
	if bool(p.get("hidden", false)) and cols_between(f, p) == 0:
		p["hidden"] = false
		lines.append("%s находит, где прячется %s" % [f["name"], s.character["name"]])


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
		or (str(a.get("kind")) == "ranged" and d == 0) or (f["conditions"] as Array).has("poisoned") or bool(p.get("hidden", false))
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
		var truce := enemies(s, false).any(func(id: String) -> bool: return str(fighter(s, id).get("status")) == "truce")
		s.combat["outcome"] = "truce" if truce else "victory"
		lines.append("Перемирие" if truce else "Победа!")
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


## XP of a won fight (a truce too — DMG: XP for overcoming the encounter): everyone defeated, fled, surrendered or
## at peace; loot — gear of the defeated and surrendered; the encounter's loot and coins — only for a victory.
## Fills s.combat.xp / loot [{item_id, qty}] / coins_cp.
static func results(s: GameSession, data: Dictionary, encounter_loot: Dictionary) -> void:
	var won := str(s.combat["outcome"]) in ["victory", "truce"]
	var victory := str(s.combat["outcome"]) == "victory"
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
	if victory:
		for item: String in encounter_loot.get("items", {}):
			loot[item] = int(loot.get(item, 0)) + int(encounter_loot["items"][item])
	s.combat["xp"] = xp if won else 0
	s.combat["coins_cp"] = int(encounter_loot.get("coins_cp", 0)) if victory else 0
	var list: Array = []
	if won:
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
			"status": f["status"], "health": health_key(f).trim_prefix("HEALTH_").to_lower(), "description": f.get("desc", ""),
			"surprised": bool(f.get("surprised", false))})
	var incoming: Array[Dictionary] = []
	for w: Dictionary in s.combat.get("incoming", []):
		incoming.append({"names": w["names"], "side": "left" if int(w["col"]) < 0 else "right",
			"in_rounds": maxi(0, int(w["at"]) - int(s.combat.get("round", 1)))})
	return {"round": int(s.combat.get("round", 1)), "enemies": foes, "outcome": str(s.combat.get("outcome", "")),
		"player_down": int(s.character.get("hp", 1)) <= 0, "player_hidden": bool(p.get("hidden", false)),
		"incoming": incoming, "log": s.combat.get("log", [])}


# --- parley (v0.6.2) ------------------------------------------------------------------------------


## DC of a parley: base + the best WIS save among intelligent foes, easier for every foe already out of the fight.
static func parley_dc(s: GameSession, data: Dictionary) -> int:
	var p: Dictionary = cfg(data)["parley"]
	var wis := -5
	for id: String in enemies(s):
		var f := fighter(s, id)
		if _intelligent(data, f):
			var m := _monster(data, f)
			wis = maxi(wis, int(m["saves"].get("wis", CharacterRules.mod(int(m["abilities"].get("wis", 10))))))
	var out := enemies(s, false).size() - enemies(s).size()
	return maxi(int(p["min_dc"]), int(p["base_dc"]) + wis + int(p["per_defeated"]) * out)


static func is_parley_skill(data: Dictionary, skill: String) -> bool:
	return (cfg(data)["parley"]["skills"] as Array).has(skill)


## "" when a parley with this skill can be tried: intelligent foes are still fighting, this skill not tried yet.
static func can_parley(s: GameSession, data: Dictionary, skill: String) -> String:
	if not is_parley_skill(data, skill):
		return "COMBAT_NO_PARLEY"
	if not enemies(s).any(func(id: String) -> bool: return _intelligent(data, fighter(s, id))):
		return "COMBAT_NO_PARLEY"
	if (s.combat.get("parley_tried", []) as Array).has(skill):
		return "COMBAT_PARLEY_TRIED"
	return ""


## The outcome of a parley check: Intimidation — intelligent foes next to the player surrender, the rest flee;
## Persuasion — they lower their weapons (truce). Beasts fight on. Lines.
static func parley_apply(s: GameSession, data: Dictionary, skill: String, success: bool) -> Array[String]:
	(s.combat["parley_tried"] as Array).append(skill)
	var lines: Array[String] = []
	if not success:
		lines.append("Враги не слушают — бой продолжается")
		return lines
	var pcol := int(player(s)["col"])
	for id: String in enemies(s):
		var f := fighter(s, id)
		if not _intelligent(data, f):
			continue
		if skill == "intimidation":
			if int(f["col"]) == pcol:
				f["status"] = "surrendered"
				lines.append("%s бросает оружие и сдаётся" % f["name"])
			else:
				f["status"] = "fled"
				lines.append("%s бежит с поля боя" % f["name"])
		else:
			f["status"] = "truce"
			lines.append("%s опускает оружие" % f["name"])
	return lines


# --- the hint before the click (v0.6.2) ----------------------------------------------------------


## Percent to hit with a d20 + to_hit against AC (natural 1 misses, 20 hits), with advantage or disadvantage.
static func hit_chance(to_hit: int, ac: int, adv: bool, dis: bool) -> int:
	var need := clampi(ac - to_hit, 2, 20)
	var p := (21 - need) / 20.0
	if adv and not dis:
		p = 1.0 - (1.0 - p) * (1.0 - p)
	elif dis and not adv:
		p = p * p
	return roundi(p * 100.0)


## [min, max] of a dice expression like "2d6+3".
static func dice_range(expr: String, mod: int = 0) -> Array[int]:
	var e := expr.replace(" ", "").replace("MOD", str(mod))
	var lo := 0
	var hi := 0
	for part: String in e.replace("-", "+-").split("+", false):
		if part.contains("d"):
			var n := int(part.get_slice("d", 0)) if not part.get_slice("d", 0).is_empty() else 1
			lo += n
			hi += n * int(part.get_slice("d", 1))
		else:
			lo += int(part)
			hi += int(part)
	return [lo, hi]


## A weapon attack at `target_id` before the click: {chance, min, max, adv: [reasons], dis: [reasons]}. AC stays
## hidden: only the percent.
static func attack_preview(s: GameSession, data: Dictionary, target_id: String, offhand: bool = false) -> Dictionary:
	var c := s.character
	var t := fighter(s, target_id)
	if t.is_empty():
		return {}
	var w := weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("off_hand" if offhand else "main_hand", "")), offhand)
	var mods := _attack_mods(s, data, w, t)
	var adv := not (mods["adv"] as Array).is_empty()
	var dis := not (mods["dis"] as Array).is_empty()
	var r := dice_range(str(w["dice"]))
	var bonus := int(w["bonus"]) + _rage_bonus(s, data, w, t)
	var sneak := _sneak_dice(s, data, w, adv, dis)
	var sr: Array[int] = [0, 0]
	if not sneak.is_empty():
		sr = dice_range(sneak)
	return {"chance": hit_chance(int(w["to_hit"]), int(t["ac"]), adv, dis), "min": maxi(1, r[0] + bonus) + sr[0],
		"max": maxi(1, r[1] + bonus) + sr[1], "adv": mods["adv"], "dis": mods["dis"], "sneak": not sneak.is_empty()}


## An engine spell at `target_id` before the click: attack — the chance to hit; save — the chance the foe fails;
## {chance, save, half, min, max, count, adv, dis}; {} for spells without a target or not resolved by the engine.
static func cast_preview(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String) -> Dictionary:
	var sp: Dictionary = data["spells"].get(spell_id, {})
	var t := fighter(s, target_id)
	if sp.is_empty() or t.is_empty() or sp.has("heal_at_slot") or not is_engine_spell(data, spell_id):
		return {}
	var c := s.character
	var level := int(c.get("level", 1))
	var r := dice_range(_spell_dice(sp, maxi(slot, int(sp.get("level", 0))), level))
	var multi: Dictionary = cfg(data)["multi"].get(spell_id, {})
	var count := 1
	if multi.has("base"):
		count = int(multi["base"]) + int(multi.get("per_slot", 0)) * maxi(0, slot - maxi(1, int(sp["level"])))
	elif multi.has("by_level"):
		for k: String in multi["by_level"]:
			if level >= int(k):
				count = int(multi["by_level"][k])
	var out := {"min": r[0], "max": r[1], "count": count, "adv": [], "dis": [], "save": false, "half": false, "chance": 100}
	if bool(multi.get("auto_hit", false)):
		return out
	if sp.has("attack"):
		var adv: Array[String] = []
		if bool(player(s).get("hidden", false)):
			adv.append("вы спрятаны")
		var dis: Array[String] = []
		if str(sp["attack"]) == "ranged" and _foe_in_column(s, player(s)):
			dis.append("враг вплотную")
		if bool(t.get("dodging", false)):
			dis.append("цель уклоняется")
		out["adv"] = adv
		out["dis"] = dis
		out["chance"] = hit_chance(int(c.get("spell_attack", 0)), int(t["ac"]), not adv.is_empty(), not dis.is_empty())
	elif sp.has("save"):
		var ab := str(sp["save"]["ability"])
		var m := _monster(data, t)
		var bonus := int(m["saves"].get(ab, CharacterRules.mod(int(m["abilities"].get(ab, 10)))))
		out["save"] = true
		out["half"] = str(sp["save"]["success"]) == "half"
		if ab in ["str", "dex"] and _target_disabled(t) and not (t["conditions"] as Array).has("prone"):
			out["chance"] = 100
		else:
			out["chance"] = 100 - hit_chance(bonus, int(c.get("spell_dc", 10)), false, false)
	return out
