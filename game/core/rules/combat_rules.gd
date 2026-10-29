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
## - v0.7.8: the hero's conditions by 5e — prone (attacks with disadvantage, close foes with advantage, far ones with
##   disadvantage, «Встать» takes the move), grappled and restrained (speed 0, «Вырваться» — an action), blinded,
##   frightened (no step towards the source), charmed (no attack on the charmer), paralysed / stunned / unconscious /
##   petrified (the turn is skipped, foes hit with advantage, close hits on the paralysed and the unconscious are
##   critical), exhaustion; repeat saves at the end of the hero's turn; resistances and the concentration save on
##   damage (HeroDefense); invisible foes are where they were last seen until they strike (`seen_col`).
## - v0.7.9: monsters by 5e (MonsterRules) — the effects of their attacks on the hero, recharge, control before damage,
##   traits, casters, Parry; magic weapons pierce resistance to nonmagical attacks; foes immune to a condition do not
##   get it; beasts do not finish a downed hero either — left for dead, the hero comes to after the fight.
## - v0.7.10: class features and race traits (FeatureRules) — prompts of the hero's turn (`prompt`: Divine Smite,
##   Wild Shape, Font of Magic), reactions to a foe's hit (`pending`: the foe's turn stops until answer_reaction),
##   strikes of monks and frenzy, Extra Attack of every class, Improved Critical, Great Weapon Fighting, Lucky,
##   inspiration, temporary HP, Wild Shape, metamagic, darkness of the pack's rooms.
## State — `s.combat` (empty when there is no fight). Pure: no nodes, randomness from `s.rng`.

const PLAYER := "p"
## A foe with one of these loses its turn (v0.6.5, playtest-1: sleeping wolves bit).
const INCAPACITATING: Array[String] = ["unconscious", "paralyzed", "stunned", "incapacitated", "petrified"]


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


## Ally ids (v0.7.22.22, AllyRules), all or only those still in the fight.
static func allies(s: GameSession, only_active: bool = true) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.combat.get("fighters", {}):
		var f: Dictionary = s.combat["fighters"][id]
		if f.get("side") == "ally" and (not only_active or str(f.get("status")) == "active"):
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
		"unconscious":
			return "HEALTH_KNOCKED_OUT"
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


## The most a dice expression can give (Beacon of Hope's healing, v0.7.13.2).
static func max_dice(expr: String, mod: int = 0) -> int:
	var total := 0
	for p: String in expr.replace(" ", "").replace("MOD", str(mod)).replace("-", "+-").split("+", false):
		if p.contains("d"):
			total += (int(p.get_slice("d", 0)) if not p.get_slice("d", 0).is_empty() else 1) * int(p.get_slice("d", 1))
		else:
			total += int(p)
	return total


## "2d6+3" (or "1d8+MOD" with `mod`) → total; a critical doubles the dice.
static func roll_dice(rng: RandomNumberGenerator, expr: String, crit: bool = false, mod: int = 0) -> int:
	if expr.begins_with("E"):  # Empowered Spell: two rolls, the better (v0.7.10)
		return maxi(roll_dice(rng, expr.substr(1), crit, mod), roll_dice(rng, expr.substr(1), crit, mod))
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
		"next_id": 0, "incoming": [], "help": (source.get("help", {}) as Dictionary).duplicate(true), "parley_tried": [],
		"parley_ok": 0, "parley_fail": 0, "parley_hard": str(source.get("parley", "")) == "hard"}
	_add_foes(s, data, foes)
	_add_foes(s, data, AllyRules.joining(s, data, foes) + (source.get("allies", []) as Array) + AllyRules.summon_specs(s), 99, "ally")
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
	lines.append_array(_opening(s, source))
	_begin_turn(s, data, lines)
	return lines


## The fight began with the hero's own attack on an NPC (v0.7.7, as in BG3): the hero acts first and that NPC is
## caught off guard. `source.opening` {npc_id, unaware}; the strike itself is resolved by the caller. v0.7.22.16:
## `unaware` false — the NPC expected it (hostile, wary): the hero still acts first, but nobody is caught off guard.
static func _opening(s: GameSession, source: Dictionary) -> Array[String]:
	var npc := str(source.get("opening", {}).get("npc_id", ""))
	if npc.is_empty():
		return []
	for id: String in enemies(s):
		var f := fighter(s, id)
		if str(f.get("npc_id", "")) == npc:
			var order: Array = s.combat["order"]
			order.erase(PLAYER)
			order.push_front(PLAYER)
			if not bool(source.get("opening", {}).get("unaware", true)):
				return ["%s нападает первой очередью — %s ждал(а) этого" % [s.character.get("name", ""), f["name"]]]
			f["surprised"] = true
			return ["Удар без предупреждения: %s ходит первой очередью, %s не ждёт нападения" % [s.character.get("name", ""), f["name"]]]
	return []


## The fighter of an NPC of the scene, "" if not in the fight.
static func fighter_of_npc(s: GameSession, npc_id: String) -> String:
	for id: String in enemies(s):
		if str(fighter(s, id).get("npc_id", "")) == npc_id:
			return id
	return ""


static func _dex_of(s: GameSession, data: Dictionary, id: String) -> int:
	if id == PLAYER:
		return CharacterRules.mod(CharacterRules.ability(s.character, "dex"))
	return CharacterRules.mod(int(_monster(data, fighter(s, id))["abilities"]["dex"]))


## Adds fighters for `specs` [{monster, count?, name?, desc?, col?, npc_id?}]; `col_at` puts them all in one
## column (reinforcements at the edge). A name that is already in the fight gets the next number. Returns the ids.
static func _add_foes(s: GameSession, data: Dictionary, specs: Array, col_at: int = 99, side_name: String = "enemy") -> Array[String]:
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
			if side_name == "ally" and col_at == 99 and not spec.has("col"):
				col = int(player(s)["col"])  # allies start by the hero
			side = -side
			var name := base
			if count > 1 or same > 0:
				name += " %d" % (same + i + 1)
			var id := ("a%d" if side_name == "ally" else "e%d") % n
			fighters[id] = {"id": id, "side": side_name, "monster": str(spec["monster"]), "name": name, "base": base,
				"desc": str(spec.get("desc", "")), "hp": int(m["hp"]), "max_hp": int(m["hp"]), "ac": int(m["ac"]),
				"col": clampi(col, -edge(data), edge(data)), "status": "active", "conditions": [], "morale": false,
				"npc_id": str(spec.get("npc_id", "")), "by_hero": bool(spec.get("by_hero", false))}
			if spec.has("hp"):  # a creature of the room fought again keeps its wounds (v0.7.22.16, #21)
				fighters[id]["hp"] = clampi(int(spec["hp"]), 1, int(m["hp"]))
			if bool(spec.get("no_xp", false)):  # its XP was given for the fight that beat it
				fighters[id]["no_xp"] = true
			if bool(spec.get("law", false)):  # the law's guard: its captive is held, not bound (v0.7.22.17)
				fighters[id]["law"] = true
			for k: String in ["ally", "summon_id", "spell", "creature_id"]:  # v0.7.22.22: whose ally and from where
				if spec.has(k):
					fighters[id][k] = str(spec[k])
			if bool(spec.get("helper", false)):
				fighters[id]["helper"] = true
			if not str(spec.get("npc_id", "")).is_empty() and not TheftRules.lost_weapons(s, data, str(spec["npc_id"])).is_empty():
				fighters[id]["actions"] = TheftRules.armed_actions(s, data, str(spec["npc_id"]), m["actions"])  # big test #3 (v0.7.22.8)
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
	RollParts.note(s, TranslationServer.translate("SKILL_STEALTH"), rolls, nat, RollParts.cached(c, data, "skill", "stealth", s.items), int(c.get("skills", {}).get("stealth", 0)))
	return {"total": nat + int(c.get("skills", {}).get("stealth", 0)), "nat": nat, "note": note}


static func monster_passive(data: Dictionary, f: Dictionary) -> int:
	var m := _monster(data, f)
	return int(m.get("passive_perception", 10 + CharacterRules.mod(int(m["abilities"].get("wis", 10))))) + MonsterRules.passive_bonus(data, f)


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
		if source.has("stealth_total"):  # rolled at the door already (v0.7.22.12): the same roll decides
			roll = {"total": int(source["stealth_total"]), "note": ""}
		var unseen: Array[String] = []
		var seen: Array[String] = []
		for id: String in foes:
			var f := fighter(s, id)
			if int(roll["total"]) >= monster_passive(data, f) - ConditionRules.unseen_penalty(s.character, data):
				f["surprised"] = true
				unseen.append(str(f["name"]))
			else:
				seen.append(str(f["name"]))
		var line := ("%s нападает из укрытия" % who) if bool(source.get("from_hiding", false)) else "%s крадётся: Скрытность %d%s" % [who, int(roll["total"]), roll["note"]]
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
			s.combat["hero_surprised"] = true
			lines.append("Засада! Враги подкрались незаметно — %s пропускает первый ход" % who)
		else:
			lines.append("Засада, но %s вовремя замечает врагов (пассивная Внимательность %d)" % [who, passive])
	return lines


## The player's turn is skipped: at 0 HP (death saves instead), surprised in the first round or unable to act
## (paralysed, stunned, asleep, petrified, incapacitated — v0.7.8).
static func player_skips(s: GameSession) -> bool:
	return int(s.character.get("hp", 0)) <= 0 or bool(player(s).get("surprised", false)) or ConditionRules.incapacitated(s.character)


## The player can press buttons now.
static func player_can_act(s: GameSession) -> bool:
	return is_player_turn(s) and not player_skips(s)


## Resets the economy of whoever's turn it is; the player at 0 HP rolls a death save instead.
static func _begin_turn(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var id := current(s)
	var f := fighter(s, id)
	f["dodging"] = false
	f["disengaged"] = false
	f["reacted"] = false  # the reaction comes back at the start of one's own turn (5e)
	if id == PLAYER:
		s.combat["economy"] = {"action": 1, "bonus": 1, "move": _move_cols(int(s.character.get("speed", 30)), data), "attacks": 0,
			"attacked": false, "sneak": false, "haste": 1 if SpellEffects.has(s.character, "haste") else 0}
		if bool(f.get("blinked", false)):  # Blink: back from the Ethereal Plane (v0.7.13.3)
			f["blinked"] = false
			lines.append("%s возвращается из эфира" % s.character["name"])
		if bool(s.character.get("lethargy", false)):  # Haste is over: a turn of lethargy
			s.character.erase("lethargy")
			s.combat["economy"] = {"action": 0, "bonus": 0, "move": 0, "attacks": 0, "attacked": false, "sneak": false, "haste": 0}
			lines.append("%s вялый после Ускорения — ход без действий и движения" % s.character["name"])
		s.combat.erase("reckless")  # Reckless Attack lasts until the hero's next turn
		var dropped := str(s.character.get("dropped", ""))
		if not dropped.is_empty() and not ConditionRules.incapacitated(s.character):  # Command «Брось!» (v0.7.22.4)
			s.character.erase("dropped")
			if str(s.character["equipped"].get("main_hand", "")).is_empty() and int(s.character["inventory"].get(dropped, 0)) > 0:
				s.character["equipped"]["main_hand"] = dropped
				CharacterRules.refresh(s.character, data, s.items)
				lines.append("%s поднимает %s" % [s.character["name"], ItemRules.display_name(data["items"], s.items, dropped)])
		lines.append_array(SpellEffects.turn_start(s, data))  # Heroism (v0.7.13.1)
		lines.append_array(SpellEffects.zones_expire(s))  # Grease (v0.7.13.6)
		SpellEffects.end_until_turn(s, data)  # Shield (v0.7.13.7)
		for eid: String in enemies(s):  # v0.7.13: riders that last until the start of the hero's next turn
			var o := fighter(s, eid)
			for k: String in ["slowed", "no_heal", "chilled"]:
				o.erase(k)


static func _move_cols(speed: int, data: Dictionary) -> int:
	if speed <= 0:
		return 0  # grappled, restrained, exhaustion 5 (v0.7.8)
	return maxi(1, speed / (int(cfg(data)["col_ft"]) * 2) + 1) if speed >= 60 else 1


# --- the player's actions ---------------------------------------------------------------------------


static func economy(s: GameSession) -> Dictionary:
	return s.combat.get("economy", {})


## The weapon attack of the character: {name, to_hit, dice, bonus, type, melee, range [normal, long] ft or [], light}.
static func weapon_profile(c: Dictionary, data: Dictionary, session_items: Dictionary, weapon_id: String, offhand: bool = false) -> Dictionary:
	if c.has("wild_shape"):  # a druid in a beast form fights with the beast's attack (v0.7.10)
		return FeatureRules.shape_profile(c, data)
	var str_mod := CharacterRules.mod(CharacterRules.ability(c, "str"))
	var dex_mod := CharacterRules.mod(CharacterRules.ability(c, "dex"))
	var prof := int(c.get("prof_bonus", 2))
	var martial := FeatureRules.martial_die(c, data)
	if weapon_id.is_empty():
		var umod := maxi(str_mod, dex_mod) if not martial.is_empty() else str_mod
		return {"name": "Безоружный удар", "to_hit": umod + prof, "hit_parts": [RollParts.part(RollParts.ability_name("str" if umod == str_mod else "dex"), umod), RollParts.part("владение", prof)], "dice": martial if not martial.is_empty() else "1", "bonus": umod,
			"type": "bludgeoning", "melee": true, "range": [], "light": false, "id": "", "magical": false, "silvered": false,
			"crit_min": FeatureRules.crit_min(c), "str_based": umod == str_mod}
	var def := ItemRules.def_of(data["items"], session_items, weapon_id)
	var w: Dictionary = def.get("weapon", {})
	var props: Array = def.get("properties", [])
	var ranged := str(w.get("range", "melee")) == "ranged"
	var monk := not martial.is_empty() and FeatureRules.monk_weapon(def) and not ranged
	var mod := dex_mod if ranged else (maxi(str_mod, dex_mod) if props.has("finesse") or monk else str_mod)
	var profs: Array = c.get("weapon_profs", [])
	var proficient := profs.has(str(w.get("category", ""))) or profs.has(weapon_id) or (FeatureRules.pact_blade(c) and not ranged)
	var to_hit := mod + (prof if proficient else 0)
	var hit_parts: Array[Dictionary] = [RollParts.part(RollParts.ability_name("dex" if mod == dex_mod and mod != str_mod else "str"), mod)]
	RollParts.add(hit_parts, "владение оружием", prof if proficient else 0)
	var dice := str(w.get("damage", "1d4"))
	if monk and CombatRules.dice_range(martial)[1] > CombatRules.dice_range(dice)[1]:
		dice = martial
	var eq: Dictionary = c.get("equipped", {})
	var bonus := mod
	if offhand and not _has_style(c, "two_weapon_fighting"):
		bonus = mini(0, mod)
	if ranged and _has_style(c, "archery"):
		to_hit += 2
		RollParts.add(hit_parts, "боевой стиль: стрельба", 2)
	if not ranged and not props.has("two_handed") and str(eq.get("off_hand", "")).is_empty() and _has_style(c, "dueling"):
		bonus += 2
	if w.has("versatile") and str(eq.get("shield", "")).is_empty() and str(eq.get("off_hand", "")).is_empty() and not offhand:
		dice = str(w["versatile"])
	var magic := ItemRules.plus(def, ["magic_plus"])  # a +N weapon (v0.6.3)
	to_hit += magic + CraftRules.quality_mod(def)
	RollParts.add(hit_parts, "магия оружия", magic)
	RollParts.add(hit_parts, "качество работы", CraftRules.quality_mod(def))
	bonus += magic
	var rng: Array = w.get("reach_ft", [])
	if rng.is_empty() and props.has("thrown"):
		rng = [20, 60]
	if not rng.is_empty():
		rng = [int(rng[0]), int(rng[1])]
	var two_hands := props.has("two_handed") or (w.has("versatile") and dice == str(w["versatile"]))
	var kind := ItemRules.real_id(str(def.get("base", weapon_id))) if not str(def.get("base", "")).is_empty() else ItemRules.real_id(weapon_id)
	if ranged and CharacterRules.item_prop(c, "ranged_damage_plus2") and kind in ["longbow", "shortbow"]:
		bonus += 2  # Bracers of Archery (v0.7.12)
	var ammo := str(ItemRules.cfg(data)["ammo"].get(ItemRules.real_id(weapon_id), ItemRules.cfg(data)["ammo"].get(kind, ""))) if props.has("ammunition") else ""
	return SpellEffects.weapon(c, {"name": str(def.get("name", weapon_id)), "to_hit": to_hit, "hit_parts": hit_parts, "dice": dice, "bonus": bonus,
		"type": str(w.get("damage_type", "bludgeoning")), "melee": not ranged, "range": rng, "light": props.has("light"), "id": weapon_id,
		"magical": magic > 0 or str(def.get("rarity", "common")) not in ["common", ""], "silvered": props.has("silvered"), "ammo": ammo,
		"heavy": props.has("heavy"), "reach": props.has("reach"),
		"gwf": not ranged and two_hands and FeatureRules.great_weapon(c), "crit_min": FeatureRules.crit_min(c), "str_based": mod == str_mod and not ranged}, kind)  # Shillelagh, Magic Weapon (v0.7.13.4)


## The hero's bare hands (the monk's Martial Arts die).
static func unarmed_profile(c: Dictionary, data: Dictionary) -> Dictionary:
	if c.has("wild_shape"):
		return FeatureRules.shape_profile(c, data)
	return weapon_profile(c, data, {}, "")


static func _has_style(c: Dictionary, style: String) -> bool:
	for f: Variant in c.get("features", []):
		if str(f).ends_with("fighting_style_" + style):
			return true
	return false


## "" when the player can attack `target` with this weapon now, otherwise the reason (a localization key).
static func can_attack(s: GameSession, data: Dictionary, target_id: String, offhand: bool = false, unarmed: bool = false) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	var e := economy(s)
	if offhand:  # as in BG3 (v0.7.22.3): no main-hand attack needed first, unless rules.combat.offhand_needs_attack
		if int(e.get("bonus", 0)) <= 0 or (bool(cfg(data).get("offhand_needs_attack", true)) and not bool(e.get("attacked", false))):
			return "COMBAT_NO_BONUS"
	elif int(e.get("attacks", 0)) <= 0 and int(e.get("action", 0)) <= 0 and int(e.get("haste", 0)) <= 0:
		return "COMBAT_NO_ACTION"
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active":
		return "COMBAT_BAD_TARGET"
	if charmed_by(s, t):
		return "COMBAT_CHARMED"
	var c := s.character
	var wid := "" if unarmed else str(c.get("equipped", {}).get("off_hand" if offhand else "main_hand", ""))  # fists (v0.7.22.11)
	var w := weapon_profile(c, data, s.items, wid, offhand)
	if not str(w.get("ammo", "")).is_empty() and int(c.get("inventory", {}).get(str(w["ammo"]), 0)) <= 0:
		return "COMBAT_NO_AMMO"  # v0.7.12: arrows and bolts are spent
	var d := absi(shown_col(t) - int(player(s)["col"]))
	if d == 0:
		return ""
	if (w["range"] as Array).is_empty():
		return "COMBAT_OUT_OF_REACH"
	if d * int(cfg(data)["col_ft"]) > int(w["range"][1]):
		return "COMBAT_OUT_OF_RANGE"
	return ""


## Frenzy (v0.7.8): a raging berserker may go into a frenzy — free; ends with the fight and a level of
## exhaustion (GameState.finish_combat).
static func can_frenzy(s: GameSession) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	if not CharacterRules.has_feature(s.character, "frenzy") or not bool(s.combat.get("raging", false)) or bool(s.combat.get("frenzy", false)):
		return "COMBAT_NO_FRENZY"
	return ""


static func frenzy(s: GameSession) -> Array[String]:
	s.combat["frenzy"] = true
	return ["%s впадает в неистовство: удар бонусным действием каждый ход, после боя — истощение" % s.character.get("name", "")]


## The frenzied hero's melee attack as a bonus action: the main weapon at a foe in the hero's column.
static func can_frenzy_attack(s: GameSession, data: Dictionary, target_id: String) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	if not bool(s.combat.get("frenzy", false)):
		return "COMBAT_NO_FRENZY"
	if int(economy(s).get("bonus", 0)) <= 0:
		return "COMBAT_NO_BONUS"
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active":
		return "COMBAT_BAD_TARGET"
	if absi(shown_col(t) - int(player(s)["col"])) != 0:
		return "COMBAT_OUT_OF_REACH"
	return ""


## A weapon attack of the player (can_attack first; a frenzy strike — can_frenzy_attack). Returns the lines.
static func player_attack(s: GameSession, data: Dictionary, target_id: String, offhand: bool = false, frenzied: bool = false, unarmed: bool = false) -> Array[String]:
	var c := s.character
	var e := economy(s)
	if frenzied:
		e["bonus"] = int(e["bonus"]) - 1
	elif offhand:
		e["bonus"] = int(e["bonus"]) - 1
	elif int(e.get("attacks", 0)) > 0:
		e["attacks"] = int(e["attacks"]) - 1
	elif int(e.get("action", 0)) <= 0 and int(e.get("haste", 0)) > 0:
		e["haste"] = 0  # Haste's action: one weapon attack (v0.7.13.3)
	else:
		e["action"] = int(e["action"]) - 1
		e["attacks"] = CharacterRules.extra_attacks(c, data)
	e["attacked"] = true
	var wid := "" if unarmed else str(c.get("equipped", {}).get("off_hand" if offhand else "main_hand", ""))
	var w := weapon_profile(c, data, s.items, wid, offhand)
	s.combat["melee_strike"] = bool(w.get("melee", false)) and cols_between(player(s), fighter(s, target_id)) == 0  # nonlethal needs a melee blow (5e)
	var lines := strike(s, data, target_id, w, {})
	s.combat.erase("melee_strike")
	spend_ammo(s, str(w.get("ammo", "")))
	return lines


## One arrow (bolt, bullet) is gone; half the spent come back after the fight (v0.7.12, PHB).
static func spend_ammo(s: GameSession, ammo: String) -> void:
	if ammo.is_empty():
		return
	var inv: Dictionary = s.character["inventory"]
	var left := int(inv.get(ammo, 0)) - 1
	if left > 0:
		inv[ammo] = left
	else:
		inv.erase(ammo)
	if not s.combat.has("ammo_spent"):
		s.combat["ammo_spent"] = {}
	s.combat["ammo_spent"][ammo] = int(s.combat["ammo_spent"].get(ammo, 0)) + 1


## One weapon attack of the hero with the profile `w`, its economy already paid (v0.7.10: monks' strikes and the
## features' attacks come here too). `opts` — stunning, open_hand, no_horde. Lines.
static func strike(s: GameSession, data: Dictionary, target_id: String, w: Dictionary, opts: Dictionary) -> Array[String]:
	var c := s.character
	var e := economy(s)
	s.combat["rage_kept"] = true
	var t := fighter(s, target_id)
	var broke := SpellEffects.break_sanctuary(c)  # v0.7.13.2
	if int(s.combat.get("sacred_weapon", 0)) > 0:
		w = w.duplicate()
		w["to_hit"] = int(w["to_hit"]) + maxi(1, FeatureRules.ab_mod(c, "cha"))
	if _missed_unseen(s, t):
		player(s)["hidden"] = false
		var miss: Array[String] = ["%s — %s: удар в пустоту, %s уже не там" % [c.get("name", ""), w["name"], t["name"]]]
		miss.append_array(ConditionRules.end_invisibility_on_attack(c, data))
		return miss
	var mods := _attack_mods(s, data, w, t)
	var adv := not (mods["adv"] as Array).is_empty()
	var dis := not (mods["dis"] as Array).is_empty()
	var lines: Array[String] = broke
	var bonus_dmg := _rage_bonus(s, data, w, t)
	var sneak := _sneak_dice(s, data, w, adv, dis, t)
	var auto_crit := cols_between(player(s), t) == 0 and (_has(t, "paralyzed") or _has(t, "unconscious"))
	var res := _attack(s, data, str(c.get("name", "")), w["name"], int(w["to_hit"]), adv, dis, t, str(w["dice"]), int(w["bonus"]) + bonus_dmg, str(w["type"]), lines, sneak, auto_crit, w)
	lines.append_array(ConditionRules.end_invisibility_on_attack(c, data))  # the attack is made unseen, then it ends
	t.erase("helped")
	if bool(res["hit"]) and not sneak.is_empty():
		e["sneak"] = true
	player(s)["hidden"] = false
	if bool(res["hit"]) and str(t.get("status")) == "active":
		var x := FeatureRules.hit_extras(s, data, w, t, bool(res["crit"]))
		if not str(x["dice"]).is_empty():
			var more := _resist(data, t, str(w["type"]), roll_dice(s.rng, str(x["dice"])), bool(w.get("magical", false)), bool(w.get("silvered", false)))
			lines.append("%s: ещё %d" % [", ".join(x["notes"]), more])
			_hurt_enemy(s, data, t, more, lines, str(w["type"]))
		_item_extras(s, data, w, t, bool(res["crit"]), lines)
		FeatureRules.after_hit(s, data, w, t, bool(res["crit"]), opts, lines)
	if not bool(opts.get("no_horde", false)) and FeatureRules.has(c, "hunters_prey_horde_breaker") and not bool(e.get("horde", false)):
		for id: String in enemies(s):
			var o := fighter(s, id)
			if id != target_id and int(o["col"]) == int(t["col"]) and absi(int(o["col"]) - int(player(s)["col"])) <= (0 if bool(w["melee"]) else 99):
				e["horde"] = true
				lines.append("Разрушитель орд: удар по %s" % o["name"])
				lines.append_array(strike(s, data, id, w, {"no_horde": true}))
				break
	return lines


## The extra damage of a hit by the weapon's properties (fire_damage — +1d6 fire, v0.7.12) and by a Potion of Growth.
static func _item_extras(s: GameSession, data: Dictionary, w: Dictionary, t: Dictionary, crit: bool, lines: Array[String]) -> void:
	for x: Dictionary in SpellEffects.hit_extras(s.character, t, str(w["type"])):  # Divine Favor, Hunter's Mark, Branding Smite (v0.7.13.4)
		if str(t.get("status")) != "active":
			break
		var add := _resist(data, t, str(x["type"]), roll_dice(s.rng, str(x["dice"]), crit), true, false)
		lines.append("%s: ещё %d (%s)" % [x["name"], add, data["misc"]["damage_types"].get(str(x["type"]), x["type"])])
		_hurt_enemy(s, data, t, add, lines, str(x["type"]))
		if bool(x.get("reveal", false)) and _has(t, "invisible"):
			_remove_condition(t, "invisible")
			lines.append("%s светится — невидимость спадает" % t["name"])
	var def := ItemRules.def_of(data["items"], s.items, str(w.get("id", "")))
	var dice := str(ItemRules.cfg(data)["element_dice"])
	for p: Variant in def.get("properties", []):
		var dtype := str(p).trim_suffix("_damage")
		if str(p).ends_with("_damage") and data["misc"]["damage_types"].has(dtype) and str(t.get("status")) == "active":
			var more := _resist(data, t, dtype, roll_dice(s.rng, dice, crit))
			lines.append("%s: ещё %d (%s)" % [def.get("name", ""), more, data["misc"]["damage_types"][dtype]])
			_hurt_enemy(s, data, t, more, lines, dtype)
	if ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return bool(e.get("enlarged", false))) and str(t.get("status")) == "active":
		var big := _resist(data, t, str(w["type"]), roll_dice(s.rng, "1d4", crit), bool(w.get("magical", false)), bool(w.get("silvered", false)))
		lines.append("увеличение: ещё %d" % big)
		_hurt_enemy(s, data, t, big, lines, str(w["type"]))


## Why a weapon attack at `t` has advantage or disadvantage now: {"adv": [reasons], "dis": [reasons]}.
static func _attack_mods(s: GameSession, data: Dictionary, w: Dictionary, t: Dictionary) -> Dictionary:
	var c := s.character
	var d := cols_between(player(s), t)
	var adv: Array[String] = []
	var dis: Array[String] = []
	if _has(t, "prone") and d == 0:
		adv.append("цель лежит")
	if ["paralyzed", "stunned", "unconscious", "restrained", "petrified"].any(func(x: String) -> bool: return _has(t, x)):
		adv.append("цель беспомощна")
	if bool(player(s).get("hidden", false)):
		adv.append("вы спрятаны")
	if ConditionRules.invisible(c, data):
		adv.append("вы невидимы")
	if _has(t, "blinded"):
		adv.append("цель ослеплена")
	if int(t.get("guided", 0)) > 0:
		adv.append("Направляющий снаряд")
	if SpellEffects.has_next_attack_adv(c):
		adv.append("Верный удар")
	if t.has("outlined"):
		adv.append("Огонь фей")
	if bool(t.get("helped", false)):
		adv.append("отвлекает союзник")  # the Help action of a familiar (v0.7.22.22)
	var fog_t := SpellEffects.obscured(s, int(t["col"]))  # Fog Cloud, Darkness (v0.7.13.6)
	var fog_me := SpellEffects.obscured(s, int(player(s)["col"]))
	if fog_t != fog_me:
		dis.append((fog_t if not fog_t.is_empty() else fog_me).to_lower())
	if _has(t, "prone") and d > 0:
		dis.append("цель лежит, а вы далеко")
	if bool(t.get("dodging", false)):
		dis.append("цель уклоняется")
	if bool(t.get("hidden", false)):
		dis.append("цель спряталась")
	if bool(t.get("reckless", false)) and bool(w["melee"]):
		adv.append("цель безрассудна")
	if bool(s.combat.get("reckless", false)) and bool(w["melee"]) and bool(w.get("str_based", true)):
		adv.append("безрассудная атака")
	if TimeRules.dark(s, data) and not MonsterRules.sees_in_dark(data, t):
		pass  # both sides are blind: it evens out (5e)
	elif TimeRules.dark(s, data):
		dis.append("темнота")
	if d > 0 and not (w["range"] as Array).is_empty() and d * int(cfg(data)["col_ft"]) > int(w["range"][0]):
		dis.append("дальше обычной дальности")
	if not bool(w["melee"]) and _foe_in_column(s, player(s)):
		dis.append("враг вплотную")
	if bool(w.get("heavy", false)) and (ItemRules.cfg(data)["small_races"] as Array).has(hero_size(s, data)):
		dis.append("тяжёлое оружие не по росту")  # v0.7.12, PHB
	dis.append_array(hero_attack_dis(s, data, t))
	return {"adv": adv, "dis": dis}


## Why the hero's own attack rolls (weapons and spells) have disadvantage now (v0.7.8).
static func hero_attack_dis(s: GameSession, data: Dictionary, t: Dictionary) -> Array[String]:
	var c := s.character
	var dis: Array[String] = []
	for pair: Array in [["poisoned", "вы отравлены"], ["frightened", "вы испуганы"], ["blinded", "вы ослеплены"],
			["prone", "вы лежите"], ["restrained", "вы опутаны"]]:
		if ConditionRules.has(c, str(pair[0])):
			dis.append(str(pair[1]))
	if ConditionRules.exhaustion(c) >= 3:
		dis.append("истощение")
	if _has(t, "invisible") and not SpellEffects.has(c, "see_invisible") and not t.has("outlined"):  # See Invisibility, Faerie Fire
		dis.append("цель невидима")
	return dis


## A foe can be targeted where the hero last saw it: an invisible one stays at `seen_col` until it strikes (v0.7.8).
static func shown_col(f: Dictionary) -> int:
	return int(f.get("seen_col", f["col"])) if _has(f, "invisible") else int(f["col"])


## The hero aims where an invisible foe was, and it is not there any more.
static func _missed_unseen(s: GameSession, t: Dictionary) -> bool:
	return _has(t, "invisible") and int(t.get("seen_col", t["col"])) != int(t["col"])


## The hero is charmed by this foe (the master's charm with `by`, or a monster's in v0.7.9): no attack on it (5e).
static func charmed_by(s: GameSession, t: Dictionary) -> bool:
	if not ConditionRules.has(s.character, "charmed"):
		return false
	var by := ConditionRules.caused_by(s.character, "charmed")
	return not by.is_empty() and (by == str(t.get("id", "")) or by == str(t.get("npc_id", "")))


static func _rage_bonus(s: GameSession, data: Dictionary, w: Dictionary, t: Dictionary) -> int:
	if cols_between(player(s), t) == 0 and bool(w["melee"]) and bool(s.combat.get("raging", false)):
		return int(CharacterRules.level_row(s.character, data).get("class_specific", {}).get("rage_damage_bonus", 2))
	return 0


## Sneak Attack dice once a turn: a finesse or ranged weapon with advantage and without disadvantage; "" otherwise.
## v0.7.22.22: an ally of the hero right beside the target is enough instead of advantage (5e).
static func _sneak_dice(s: GameSession, data: Dictionary, w: Dictionary, adv: bool, dis: bool, t: Dictionary = {}) -> String:
	var c := s.character
	var finesse_or_ranged: bool = not bool(w["melee"]) or (ItemRules.def_of(data["items"], s.items, str(w.get("id", ""))).get("properties", []) as Array).has("finesse")
	if CharacterRules.has_feature(c, "sneak_attack") and not bool(economy(s).get("sneak", false)) and not dis and finesse_or_ranged 			and (adv or (not t.is_empty() and allies(s).any(func(id: String) -> bool: return cols_between(fighter(s, id), t) == 0))):
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
		dice: String, bonus: int, dtype: String, lines: Array[String], extra_dice: String = "", auto_crit: bool = false, w: Dictionary = {}) -> Dictionary:
	if SpellEffects.take_next_attack_adv(s.character):  # True Strike (v0.7.13.1)
		adv = true
	var rolls := FeatureRules.hero_d20(s, adv, dis)  # the hero's roll: Lucky (v0.7.10)
	var nat := _nat(rolls, adv, dis)
	t.erase("guided")  # Guiding Bolt's light goes with the first attack roll (v0.7.13)
	var die := SpellEffects.hero_die(s, data, "attack")  # Bless (v0.7.13.1)
	to_hit += int(die["bonus"])
	var total := nat + to_hit
	var crit_min := int(w.get("crit_min", 20))
	var hit := nat >= crit_min or (nat != 1 and total >= int(t["ac"]))
	var mark := " (с преимуществом)" if adv and not dis else " (с помехой)" if dis and not adv else ""
	var line := "%s — %s по %s: %d%s%d = %d против КД %d%s%s" % [who, what, t["name"], nat, " + " if to_hit >= 0 else " − ", absi(to_hit), total, int(t["ac"]), mark,
		(" [%s]" % die["note"]) if not str(die["note"]).is_empty() else ""]
	if not hit and nat != 1:
		var insp := FeatureRules.use_inspiration(s)
		if insp > 0:
			total += insp
			hit = total >= int(t["ac"])
			line += " + вдохновение %d = %d" % [insp, total]
	if not hit:
		lines.append(line + " — промах")
		fx(s, str(t["id"]), "dodge")
		return {"hit": false, "damage": 0, "crit": false}
	var crit := nat >= crit_min or auto_crit
	if not crit and bool(w.get("melee", false)) and MonsterRules.parry(s, data, t, total, lines):  # v0.7.9
		lines.append(line + " — отбито")
		fx(s, str(t["id"]), "dodge")
		return {"hit": false, "damage": 0, "crit": false}
	if crit:
		fx(s, str(t["id"]), "crit")
	var dmg := maxi(1, (_roll_gwf(s.rng, dice, crit) if bool(w.get("gwf", false)) else roll_dice(s.rng, dice, crit)) + bonus)
	if not extra_dice.is_empty():
		dmg += roll_dice(s.rng, extra_dice, crit)
	dmg = _resist(data, t, dtype, dmg, bool(w.get("magical", true)) or w.is_empty(), bool(w.get("silvered", false)))
	lines.append(line + (" — КРИТ! " if crit else " — попадание, ") + "%d (%s)%s" % [dmg, str(data["misc"]["damage_types"].get(dtype, dtype)),
		", Скрытая атака" if not extra_dice.is_empty() else ""])
	_hurt_enemy(s, data, t, dmg, lines, dtype, crit)
	return {"hit": true, "damage": dmg, "crit": crit}


## Great Weapon Fighting: damage dice of 1 or 2 are rolled again, once.
static func _roll_gwf(rng: RandomNumberGenerator, expr: String, crit: bool) -> int:
	var total := 0
	for p: String in expr.replace(" ", "").replace("-", "+-").split("+", false):
		if p.contains("d"):
			var n := int(p.get_slice("d", 0)) if not p.get_slice("d", 0).is_empty() else 1
			var sides := int(p.get_slice("d", 1))
			for i in n * (2 if crit else 1):
				var r := rng.randi_range(1, sides)
				total += rng.randi_range(1, sides) if r <= 2 else r
		else:
			total += int(p)
	return total


## Resistance, immunity or vulnerability of a foe. «…from nonmagical attacks» does not hold against a magic weapon or a
## spell (`magical`), «…that aren't silvered» — against silver (v0.7.9).
static func _resist(data: Dictionary, t: Dictionary, dtype: String, dmg: int, magical: bool = true, silvered: bool = false) -> int:
	var m: Dictionary = data["monsters"].get(str(t.get("monster", "")), {})
	var has := func(list: String) -> bool:
		for x: Variant in m.get(list, []):
			var text := str(x).to_lower()
			if not text.contains(dtype):
				continue
			if text.contains("nonmagical") and magical:
				continue
			if text.contains("silvered") and silvered:
				continue
			return true
		return false
	if has.call("immunities"):
		return 0
	if has.call("resistances"):
		return dmg / 2
	if has.call("vulnerabilities"):
		return dmg * 2
	return dmg


## Damage to an enemy: 0 HP — down (dead), unless a trait keeps it up (v0.7.9); half HP — a morale check on its next
## turn; a hit breaks its concentration on a failed save; a dead one bursts and lets go of the hero.
## A moment of the fight for the screen to show (v0.7.22.14, CombatFx): what HP and states do not tell — a miss
## dodged, a critical hit. {who: fighter id or PLAYER, kind}; the screen takes them and clears the list.
static func fx(s: GameSession, who: String, kind: String) -> void:
	var list: Array = s.combat.get("fx", [])
	list.append({"who": who, "kind": kind})
	s.combat["fx"] = list


static func take_fx(s: GameSession) -> Array:
	var list: Array = s.combat.get("fx", [])
	s.combat.erase("fx")
	return list


static func _hurt_enemy(s: GameSession, data: Dictionary, t: Dictionary, dmg: int, lines: Array[String], dtype: String = "", crit: bool = false, by_hero: bool = true) -> void:
	if dtype == "fire" and t.has("oiled") and dmg > 0:  # oil on the foe catches (v0.7.12)
		var more := _resist(data, t, "fire", int(t["oiled"]))
		t.erase("oiled")
		dmg += more
		lines.append("%s: масло вспыхивает, ещё %d" % [t["name"], more])
	if dmg >= int(t["hp"]) and int(t["hp"]) > 0 and MonsterRules.survives(s, data, t, dmg, dtype, crit, lines):
		t["hp"] = 1
		return
	t["hp"] = maxi(0, int(t["hp"]) - dmg)
	MonsterRules.concentration_check(s, data, t, dmg, lines)
	for cond: String in (t.get("timers", {}) as Dictionary).keys():
		if bool(t["timers"][cond].get("wake", false)) and int(t["hp"]) > 0:
			_remove_condition(t, cond)
			lines.append("%s приходит в себя от удара" % t["name"] if cond == "unconscious" else "%s: %s проходит от удара" % [t["name"], cond_name(data, cond)])
	if int(t["hp"]) == 0 and by_hero and bool(s.combat.get("nonlethal", false)) and bool(s.combat.get("melee_strike", false)):
		t["status"] = "unconscious"  # 5e: a melee blow at 0 HP may knock out instead of killing (v0.7.22.11, big test #44)
		lines.append("%s оглушён и падает без сознания" % t["name"])
		return
	if int(t["hp"]) == 0:
		t["status"] = "dead"
		lines.append("%s повержен" % t["name"])
		if by_hero:
			FeatureRules.on_kill(s, data, lines)
		MonsterRules.release(s, data, t, lines)
		MonsterRules.death_burst(s, data, t, lines)


## Engine spells (rules.combat.engine_spells): "" when castable at that target now, otherwise a reason.
## An attack, not a word (v0.7.22.16): a spell of the engine's that hurts (an attack roll or damage) or holds (a
## condition spell beyond a charm). Cast at an NPC out of a fight, it starts the fight.
static func hostile_spell(data: Dictionary, spell_id: String) -> bool:
	var sp: Dictionary = data["spells"].get(spell_id, {})
	if (cfg(data)["engine_spells"] as Array).has(spell_id) and (sp.has("attack") or sp.has("damage_at_slot") or sp.has("damage_at_level")):
		return true
	var cs: Dictionary = cfg(data)["condition_spells"].get(spell_id, {}) if cfg(data)["condition_spells"].get(spell_id) is Dictionary else {}
	return not cs.is_empty() and (cs.get("conditions", []) as Array).any(func(x: Variant) -> bool: return str(x) != "charmed")


## An NPC who does not expect an attack (v0.7.22.16): not hostile and its attitude at least unaware_attitude.
static func npc_unaware(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return not SocialRules.refuses(s, data, npc_id) and s.attitude(npc_id) >= int(cfg(data)["unaware_attitude"])


static func is_engine_spell(data: Dictionary, spell_id: String) -> bool:
	return (cfg(data)["engine_spells"] as Array).has(spell_id) or cfg(data)["condition_spells"].has(spell_id) 		or not SpellEffects.spec(data, spell_id).is_empty()  # the buffs and curses of v0.7.13 resolve in the engine too


static func _has(f: Dictionary, cond: String) -> bool:
	return (f.get("conditions", []) as Array).has(cond)


static func incapacitated(f: Dictionary) -> bool:
	return INCAPACITATING.any(func(x: String) -> bool: return _has(f, x))


static func cond_name(data: Dictionary, cond: String) -> String:
	return str(data["rules"]["conditions"].get(cond, cond)).get_slice(":", 0).to_lower()


## The conditions of a foe with the rounds left: «без сознания (9 р.)».
static func foe_conditions(data: Dictionary, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var timers: Dictionary = f.get("timers", {})
	for cond: String in f.get("conditions", []):
		var t: Dictionary = timers.get(cond, {})
		out.append(cond_name(data, cond) + ((" (%d р.)" % int(t["rounds"])) if not t.is_empty() else ""))
	return out


static func _add_condition(f: Dictionary, cond: String, timer: Dictionary) -> void:
	if not _has(f, cond):
		(f["conditions"] as Array).append(cond)
	if cond == "invisible":
		f["seen_col"] = int(f["col"])
	var timers: Dictionary = f.get("timers", {})
	timers[cond] = timer
	f["timers"] = timers


static func _remove_condition(f: Dictionary, cond: String) -> void:
	(f.get("conditions", []) as Array).erase(cond)
	(f.get("timers", {}) as Dictionary).erase(cond)


## Condition spells of the engine (rules.combat.condition_spells, v0.6.5): a save against the spell DC (or a pool of
## hit points — Sleep, Color Spray), conditions for rounds, a repeat save at the end of the foe's turn, waking on
## damage; a concentration spell ends when the player's concentration moves on.
static func _cast_condition(s: GameSession, data: Dictionary, spell_id: String, slot: int, target: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	var sp: Dictionary = data["spells"][spell_id]
	var spec: Dictionary = cfg(data)["condition_spells"][spell_id]
	var name := str(sp["name"])
	var targets: Array[Dictionary] = []
	if bool(spec.get("area", false)) or sp.has("area"):
		var col := int(player(s)["col"]) if int(sp.get("range_ft", 0)) == 0 else int(target["col"])
		for id: String in enemies(s):
			if int(fighter(s, id)["col"]) == col:
				targets.append(fighter(s, id))
	else:
		targets.append(target)
	var conds: Array = spec["conditions"]
	var timer := {"rounds": int(spec.get("rounds", 10)) * (2 if str(s.combat.get("meta_now", "")) == "extended_spell" else 1), "spell": spell_id, "wake": bool(spec.get("ends_on_damage", false)),
		"save": str(sp["save"]["ability"]) if bool(spec.get("repeat_save", false)) and sp.has("save") else "", "dc": int(c.get("spell_dc", 10))}
	if spec.has("pool"):  # Sleep, Color Spray: the weakest first while the pool lasts
		var extra := maxi(0, slot - maxi(1, int(sp["level"])))
		var pool := roll_dice(s.rng, str(spec["pool"]))
		for i in extra:
			pool += roll_dice(s.rng, str(spec["pool_per_slot"]))
		lines.append("%s: пул %d хитов" % [name, pool])
		targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["hp"]) < int(b["hp"]))
		for t: Dictionary in targets:
			if str(t["status"]) != "active" or conds.all(func(x: String) -> bool: return _has(t, x)) or not _can_be(data, t, spec):
				continue
			if int(t["hp"]) > pool:
				lines.append("%s: %s устоял — хитов больше, чем осталось в пуле" % [name, t["name"]])
				break
			pool -= int(t["hp"])
			for cond: String in conds:
				_add_condition(t, cond, timer.duplicate())
			lines.append("%s: %s — %s" % [name, t["name"], ", ".join(conds.map(func(x: String) -> String: return cond_name(data, x)))])
		return
	for t: Dictionary in targets:
		if str(t["status"]) != "active":
			continue
		if not _can_be(data, t, spec):
			lines.append("%s: на %s не действует" % [name, t["name"]])
			continue
		var ab := str(sp["save"]["ability"])
		var tags: Array = ["magic"]
		if spell_id == "charm_person":
			tags.append("fighting")  # 5e: advantage when you or your companions are fighting it (v0.7.13)
		if conds.has("charmed"):
			tags.append("charm")
		if conds.has("frightened"):
			tags.append("fear")
		if conds.has("paralyzed"):
			tags.append("paralysis")
		var ok := _monster_save(s, data, t, ab, int(c.get("spell_dc", 10)), tags, str(s.combat.get("meta_now", "")) == "heightened_spell")
		lines.append("%s: %s — спасбросок %s против Сл %d %s" % [name, t["name"], ab_name(ab), int(c.get("spell_dc", 10)),
			"успех" if ok else "провал — " + ", ".join(conds.map(func(x: String) -> String: return cond_name(data, x)))])
		if not ok:
			for cond: String in conds:
				_add_condition(t, cond, timer.duplicate())


## Whether a foe can get the spell's conditions: creature types (`types`, `immune_types`), condition immunities,
## a minimum Intelligence (Hideous Laughter).
static func _can_be(data: Dictionary, t: Dictionary, spec: Dictionary) -> bool:
	var m := _monster(data, t)
	var kind := str(m.get("type", ""))
	if spec.has("types") and not (spec["types"] as Array).has(kind):
		return false
	if (spec.get("immune_types", []) as Array).has(kind):
		return false
	for cond: String in spec["conditions"]:
		if (m.get("condition_immunities", []) as Array).has(cond):
			return false
	if spec.has("immune_condition") and (m.get("condition_immunities", []) as Array).has(str(spec["immune_condition"])):
		return false
	if (spec["conditions"] as Array).has("unconscious") and MonsterRules.sleep_immune(data, t):
		return false
	return int(m["abilities"].get("int", 10)) >= int(spec.get("min_int", 0))


## The end of a foe's turn: rounds run down, a repeat save may shake a condition off. Lines.
static func _tick_conditions(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var timers: Dictionary = f.get("timers", {})
	for cond: String in timers.keys():
		var t: Dictionary = timers[cond]
		if not str(t.get("save", "")).is_empty() and _monster_save(s, data, f, str(t["save"]), int(t["dc"])):
			_remove_condition(f, cond)
			lines.append("%s стряхивает: %s" % [f["name"], cond_name(data, cond)])
			continue
		t["rounds"] = int(t["rounds"]) - 1
		if int(t["rounds"]) <= 0:
			_remove_condition(f, cond)
			lines.append("%s: %s проходит" % [f["name"], cond_name(data, cond)])


## The player's concentration spell ended: its conditions leave every foe.
static func end_spell(s: GameSession, data: Dictionary, spell_id: String) -> Array[String]:
	var lines: Array[String] = []
	if spell_id.is_empty() or not active(s):
		return lines
	lines.append_array(SpellEffects.end_on_foes(s, spell_id))
	lines.append_array(SpellEffects.end_zones(s, spell_id))  # v0.7.13.5
	lines.append_array(SpellEffects.end_curses(s, spell_id))  # v0.7.13.6
	for id: String in allies(s):  # v0.7.22.22: the creatures of a concentration spell go with it
		var a := fighter(s, id)
		if str(a.get("spell", "")) == spell_id and bool(data["spells"].get(spell_id, {}).get("concentration", false)):
			a["status"] = "gone"
			lines.append("%s исчезает — концентрация прервана" % a["name"])
	if spell_id == "haste":  # v0.7.13.3: a wave of lethargy
		s.character["lethargy"] = true
		lines.append("Ускорение кончилось — на ход накатывает вялость")
	for id: String in enemies(s):
		var f := fighter(s, id)
		for cond: String in (f.get("timers", {}) as Dictionary).keys():
			if str(f["timers"][cond].get("spell", "")) == spell_id:
				_remove_condition(f, cond)
				lines.append("%s: %s проходит — концентрация прервана" % [f["name"], cond_name(data, cond)])
	return lines


static func spell_cost(data: Dictionary, spell_id: String) -> String:
	return "bonus" if str(data["spells"].get(spell_id, {}).get("casting_time", "")).contains("бонус") else "action"


static func can_cast(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	if s.character.has("wild_shape"):
		return "COMBAT_WILD_SHAPE"
	var cost := spell_cost(data, spell_id)
	if FeatureRules.active_metamagic(s, data) == "quickened_spell":
		cost = "bonus"
	if int(economy(s).get(cost, 0)) <= 0:
		return "COMBAT_NO_ACTION" if cost == "action" else "COMBAT_NO_BONUS"
	var chk := SpellRules.check(s.character, data, spell_id, slot)
	if chk.has("reason"):
		return str(chk["reason"])
	var sp: Dictionary = data["spells"][spell_id]
	if SpellRules.long_cast(sp):
		return "COMBAT_SPELL_TOO_LONG"  # v0.7.13: minutes to cast — not in a fight (Prayer of Healing)
	if SpellEffects.spec(data, spell_id).has("reaction"):
		return "COMBAT_REACTION_SPELL"  # Shield, Counterspell: cast in the window of a foe's turn (v0.7.13.7)
	if (sp.get("components", []) as Array).has("V") and SpellEffects.silenced(s, int(player(s)["col"])):
		return "COMBAT_SILENCED"  # v0.7.13.6
	if sp.has("heal_at_slot") or target_id.is_empty():
		return ""
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active" or str(t.get("side")) != "enemy":
		return "COMBAT_BAD_TARGET"
	if charmed_by(s, t) and (sp.has("attack") or sp.has("save") or is_engine_spell(data, spell_id)):
		return "COMBAT_CHARMED"
	if absi(shown_col(t) - int(player(s)["col"])) > range_cols(data, spell_range(s, data, spell_id)):
		return "COMBAT_OUT_OF_RANGE"
	return ""


## A spell's range for the hero: Eldritch Spear (300 ft for Eldritch Blast), Distant Spell (double).
static func spell_range(s: GameSession, data: Dictionary, spell_id: String) -> int:
	var ft := int(data["spells"].get(spell_id, {}).get("range_ft", 0))
	if spell_id == "eldritch_blast" and FeatureRules.has(s.character, "eldritch_invocation_eldritch_spear"):
		ft = 300
	if FeatureRules.active_metamagic(s, data) == "distant_spell":
		ft *= 2
	return ft


# --- items in a fight (v0.7.12) --------------------------------------------------------------------


## A flask or a net thrown at a foe (rules.consumables `throw`): "" or a localization key.
static func can_throw(s: GameSession, data: Dictionary, item_id: String, target_id: String) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	var fx: Dictionary = ItemRules.consumable(data, item_id, s.items).get("throw", {})
	if fx.is_empty() or int(s.character.get("inventory", {}).get(item_id, 0)) <= 0:
		return "COMBAT_ITEM_CANT"
	if int(economy(s).get("action", 0)) <= 0 and int(economy(s).get("attacks", 0)) <= 0:
		return "COMBAT_NO_ACTION"
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active" or str(t.get("side")) != "enemy":
		return "COMBAT_BAD_TARGET"
	var far := 60 if bool(fx.get("improvised", false)) else int(fx.get("range", 15))
	if absi(shown_col(t) - int(player(s)["col"])) * int(cfg(data)["col_ft"]) > far:
		return "COMBAT_OUT_OF_RANGE"
	return ""


## Throws the thing (can_throw first): a ranged attack — improvised (DEX, no proficiency, 20/60 ft) or the net's;
## on a hit its damage (only to `types` when given), burning, oil or the net's hold. Lines.
static func throw_item(s: GameSession, data: Dictionary, item_id: String, target_id: String) -> Array[String]:
	var c := s.character
	var e := economy(s)
	if int(e.get("attacks", 0)) > 0:
		e["attacks"] = int(e["attacks"]) - 1
	else:
		e["action"] = int(e["action"]) - 1
		e["attacks"] = CharacterRules.extra_attacks(c, data)
	e["attacked"] = true
	var fx: Dictionary = ItemRules.consumable(data, item_id, s.items)["throw"]
	var name := ItemRules.display_name(data["items"], s.items, item_id)
	ItemRules._remove_one(c, item_id)
	var t := fighter(s, target_id)
	var dex := CharacterRules.mod(CharacterRules.ability(c, "dex"))
	var proficient := bool(fx.get("weapon", false)) and ((c.get("weapon_profs", []) as Array).has("martial") or (c.get("weapon_profs", []) as Array).has(item_id))
	var to_hit := dex + (int(c.get("prof_bonus", 2)) if proficient else 0)
	var near := int(fx.get("range", 20))
	var w := {"melee": false, "range": [near, 60 if bool(fx.get("improvised", false)) else near], "id": "", "name": name, "str_based": false}
	var mods := _attack_mods(s, data, w, t)
	var adv := not (mods["adv"] as Array).is_empty()
	var dis := not (mods["dis"] as Array).is_empty()
	var lines: Array[String] = []
	var rolls := FeatureRules.hero_d20(s, adv, dis)
	var nat := _nat(rolls, adv, dis)
	var total := nat + to_hit
	var hit := nat == 20 or (nat != 1 and total >= int(t["ac"]))
	var mark := " (с преимуществом)" if adv and not dis else " (с помехой)" if dis and not adv else ""
	lines.append("%s бросает %s в %s: %d%s%d = %d против КД %d%s — %s" % [c["name"], name, t["name"], nat, " + " if to_hit >= 0 else " − ",
		absi(to_hit), total, int(t["ac"]), mark, "попадание" if hit else "промах"])
	player(s)["hidden"] = false
	lines.append_array(ConditionRules.end_invisibility_on_attack(c, data))
	if not hit:
		return lines
	if fx.has("damage"):
		var types: Array = fx.get("types", [])
		if not types.is_empty() and not types.has(str(_monster(data, t).get("type", ""))):
			lines.append("%s: на %s не действует" % [name, t["name"]])
		else:
			var dtype := str(fx["damage"][1])
			var dmg := _resist(data, t, dtype, roll_dice(s.rng, str(fx["damage"][0]), nat == 20))
			lines.append("%s: %d (%s)" % [name, dmg, data["misc"]["damage_types"].get(dtype, dtype)])
			_hurt_enemy(s, data, t, dmg, lines, dtype)
	if fx.has("burning") and str(t.get("status")) == "active":
		t["burning"] = str(fx["burning"])
		lines.append("%s горит" % t["name"])
	if fx.has("oiled") and str(t.get("status")) == "active":
		t["oiled"] = int(fx["oiled"])
		lines.append("%s облит маслом — огонь возьмёт его сильнее" % t["name"])
	if fx.has("condition") and str(t.get("status")) == "active":
		if SIZES.find(str(_monster(data, t).get("size", "medium"))) > SIZES.find(str(fx.get("max_size", "large"))):
			lines.append("%s слишком велик для сети" % t["name"])
		else:
			_add_condition(t, str(fx["condition"]), {"rounds": 10, "save": "str", "dc": int(fx.get("escape_dc", 10)), "item": item_id})
			lines.append("%s: %s, вырваться — Сил Сл %d" % [t["name"], cond_name(data, str(fx["condition"])), int(fx.get("escape_dc", 10))])
	return lines


## The spell of an item (a scroll, a wand) in a fight: "" or a localization key. `target_id` as for a spell.
static func can_item_spell(s: GameSession, data: Dictionary, item_id: String, target_id: String) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	var fx := ItemRules.consumable(data, item_id, s.items)
	if not fx.has("spell") or not ItemRules.can_use(s.character, data, s.items, item_id).is_empty():
		return "COMBAT_ITEM_CANT"
	if int(economy(s).get("action", 0)) <= 0:
		return "COMBAT_NO_ACTION"
	var sp_id := str(fx["spell"])
	var sp: Dictionary = data["spells"].get(sp_id, {})
	if sp.has("heal_at_slot") or target_id.is_empty() or not is_engine_spell(data, sp_id):
		return ""
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active" or str(t.get("side")) != "enemy":
		return "COMBAT_BAD_TARGET"
	if absi(shown_col(t) - int(player(s)["col"])) > range_cols(data, int(sp.get("range_ft", 0))):
		return "COMBAT_OUT_OF_RANGE"
	return ""


## Casts the item's spell (can_item_spell first): the item gives the spell, its DC and attack (a scroll — by the
## circle, DMG; a wand — its own); no slot of the hero's is spent. A scroll beyond the hero asks for Arcana. Lines.
static func item_spell(s: GameSession, data: Dictionary, item_id: String, target_id: String) -> Array[String]:
	var c := s.character
	var fx := ItemRules.consumable(data, item_id, s.items)
	var sp_id := str(fx["spell"])
	var level := int(fx.get("level", 1))
	var name := ItemRules.display_name(data["items"], s.items, item_id)
	var lines: Array[String] = ["%s: %s" % [c["name"], name]]
	lines.append_array(ItemRules.consume(c, data, s.items, item_id, s.rng))
	if bool(fx.get("scroll", false)):
		var read := ItemRules.read_scroll(c, data, sp_id, level, s.rng)
		lines.append(str(read["line"]))
		if not bool(read["ok"]):
			economy(s)["action"] = int(economy(s)["action"]) - 1
			return lines
	if sp_id == "identify":
		economy(s)["action"] = int(economy(s)["action"]) - 1
		lines.append_array(ItemRules.identify(c, data, s.items))
		return lines
	var nums := ItemRules.scroll_numbers(data, level)
	var keep := {}
	for k: String in ["spell_dc", "spell_attack", "spell_ability", "spells", "slots_max", "slots_used"]:
		keep[k] = c[k].duplicate() if c.get(k) is Dictionary or c.get(k) is Array else c.get(k)
	c["spell_dc"] = int(fx.get("dc", nums[0]))
	c["spell_attack"] = int(fx.get("attack", nums[1]))
	if str(c.get("spell_ability", "")).is_empty():
		c["spell_ability"] = "int"
	var spells: Dictionary = (c.get("spells", {}) as Dictionary).duplicate(true)
	var always: Array = spells.get("always", [])
	always.append(sp_id)
	spells["always"] = always
	c["spells"] = spells
	if level > 0:
		var mx: Array = (c.get("slots_max", [0, 0, 0, 0, 0]) as Array).duplicate()
		mx[level - 1] = int(mx[level - 1]) + 1
		c["slots_max"] = mx
	var cast := _player_cast(s, data, sp_id, level, target_id)
	if not cast.is_empty() and str(cast[0]).begins_with("Заклинание"):
		cast[0] = "Заклинание: %s" % data["spells"][sp_id]["name"]
	lines.append_array(cast)
	for k: String in keep:
		if keep[k] == null:
			c.erase(k)
		else:
			c[k] = keep[k]
	player(s)["hidden"] = false
	return lines


## Casts a spell in combat (can_cast first): the slot, then attack rolls or saves, damage or healing. Lines.
static func player_cast(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String) -> Array[String]:
	fx(s, target_id if not target_id.is_empty() else PLAYER, "spell")  # v0.7.22.14
	var lines := _player_cast(s, data, spell_id, slot, target_id)
	player(s)["hidden"] = false  # casting gives the player away
	return lines


static func _player_cast(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String) -> Array[String]:
	var c := s.character
	var sp: Dictionary = data["spells"][spell_id]
	var e := economy(s)
	var cost := spell_cost(data, spell_id)
	var meta := FeatureRules.pay_metamagic(s, data)
	if meta == "quickened_spell":
		cost = "bonus"
	e[cost] = int(e[cost]) - 1
	s.combat["meta_now"] = meta
	var chk := SpellRules.check(c, data, spell_id, slot)
	var held := str(c.get("concentration", ""))
	var lines: Array[String] = SpellRules.cast(c, data, chk["spell_id"], int(chk["slot"]), s, target_id.is_empty())
	slot = int(chk["slot"])
	if held != str(c.get("concentration", "")):
		lines.append_array(end_spell(s, data, held))
	if not AllyRules.summon_spec(data, spell_id).is_empty():  # v0.7.22.22: the summoned fight on the hero's side
		lines.append_array(AllyRules.summon(s, data, spell_id))
		return lines
	if cfg(data)["condition_spells"].has(spell_id) and not target_id.is_empty():
		_cast_condition(s, data, spell_id, slot, fighter(s, target_id), lines)
		return lines
	if bool(SpellEffects.spec(data, spell_id).get("dispel", false)):  # Dispel Magic (v0.7.13.7)
		lines.append_array(SpellEffects.dispel(s, data, target_id))
		return lines
	if not SpellEffects.curse(data, spell_id).is_empty() and not target_id.is_empty():  # v0.7.13.6: Faerie Fire, Slow…
		SpellEffects.cast_curse(s, data, spell_id, slot, fighter(s, target_id), lines)
		return lines
	if not SpellEffects.sustained(data, spell_id).is_empty():  # v0.7.13.5: zones and strikes each turn
		SpellEffects.start_sustained(s, data, spell_id, slot, target_id, lines)
		return lines
	if bool(SpellEffects.spec(data, spell_id).get("foe_target", false)):  # Hunter's Mark (v0.7.13.4)
		lines.append_array(SpellEffects.apply_self(s, data, spell_id, slot))
		if not target_id.is_empty():
			SpellEffects.mark(c, target_id)
			lines.append("%s отмечен" % fighter(s, target_id)["name"])
		return lines
	if int(SpellEffects.spec(data, spell_id).get("teleport", 0)) > 0:  # Misty Step (v0.7.13.3)
		lines.append_array(_teleport(s, data, int(SpellEffects.spec(data, spell_id)["teleport"])))
		return lines
	if SpellEffects.foe_spell(data, spell_id) and not target_id.is_empty():  # Bane (v0.7.13.1)
		SpellEffects.curse_foes(s, data, spell_id, slot, fighter(s, target_id), lines)
		return lines
	var level := int(c.get("level", 1))
	var ab := CharacterRules.mod(CharacterRules.ability(c, str(c.get("spell_ability", "int"))))
	if sp.has("heal_at_slot"):
		var heal_expr := str(sp["heal_at_slot"].get(str(maxi(1, slot)), "1d8+MOD"))
		var heal := max_dice(heal_expr, ab) if SpellEffects.max_heal(c) else roll_dice(s.rng, heal_expr, false, ab)
		if FeatureRules.has(c, "disciple_of_life") and slot > 0:
			heal += 2 + slot  # Disciple of Life
		var before := int(c["hp"])
		c["hp"] = mini(int(c["max_hp"]), before + heal)
		lines.append("+%d HP" % (int(c["hp"]) - before))
		return lines
	if not is_engine_spell(data, spell_id) or target_id.is_empty():
		return lines
	lines.append_array(SpellEffects.break_sanctuary(c))  # a spell at a foe ends Sanctuary (v0.7.13.2)
	var dice := _spell_dice(sp, slot, level)
	var t := fighter(s, target_id)
	if not sp.has("area") and _missed_unseen(s, t):
		lines.append("%s: в пустоту — %s уже не там" % [sp["name"], t["name"]])
		return lines
	var targets: Array[Dictionary] = [t]
	if sp.has("area"):
		targets = area_targets(s, data, sp, t)
	elif spell_id == "acid_splash":  # v0.7.13: a second creature within 5 ft of the first
		for id: String in enemies(s):
			if id != str(t["id"]) and int(fighter(s, id)["col"]) == int(t["col"]):
				targets.append(fighter(s, id))
				break
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
	if count > 1 and not sp.has("area") and bool(cfg(data).get("volley_one_by_one", false)):
		# As in BG3 (v0.7.22.4, big test #33): one dart or ray now, a target for each of the rest by the button.
		s.combat["volley"] = {"spell": spell_id, "slot": slot, "left": count - 1, "last": target_id}
		count = 1
	for i in count:
		if not sp.has("area") and str(t.get("status")) != "active":
			break
		if bool(multi.get("auto_hit", false)) or sp.has("attack"):
			_bolt(s, data, spell_id, slot, t, dice, lines)
		elif sp.has("save"):
			var dmg_full := roll_dice(s.rng, _empowered(s, dice))
			for tg: Dictionary in targets:
				if str(tg.get("status")) != "active":
					continue
				var ok := _monster_save(s, data, tg, str(sp["save"]["ability"]), int(c.get("spell_dc", 10)), ["magic"], str(s.combat.get("meta_now", "")) == "heightened_spell")
				var dmg := dmg_full / 2 if ok and str(sp["save"]["success"]) == "half" else (0 if ok else dmg_full)
				dmg = _resist(data, tg, dtype, dmg)
				lines.append("%s: %s — спасбросок %s против Сл %d %s, %d (%s)" % [name, tg["name"], ab_name(str(sp["save"]["ability"])),
					int(c.get("spell_dc", 10)), "успех" if ok else "провал", dmg, data["misc"]["damage_types"].get(dtype, dtype)])
				if dmg > 0:
					_hurt_enemy(s, data, tg, dmg, lines)
				_spell_rider(s, data, spell_id, slot, tg, not ok, lines)
	return lines


## One dart or ray of a spell (an auto hit or a spell attack) at `t`. Lines.
static func _bolt(s: GameSession, data: Dictionary, spell_id: String, slot: int, t: Dictionary, dice: String, lines: Array[String]) -> void:
	var c := s.character
	var sp: Dictionary = data["spells"][spell_id]
	var dtype := str(sp.get("damage_type", ""))
	var name := str(sp["name"])
	if bool(cfg(data)["multi"].get(spell_id, {}).get("auto_hit", false)):
		var dmg := _resist(data, t, dtype, roll_dice(s.rng, _empowered(s, dice)))
		lines.append("%s: %d (%s) по %s" % [name, dmg, data["misc"]["damage_types"].get(dtype, dtype), t["name"]])
		_hurt_enemy(s, data, t, dmg, lines)
		return
	# v0.7.13: a spell attack has the advantages and disadvantages of any attack (prone, hidden, guided, dark…)
	var probe := {"melee": str(sp["attack"]) == "melee", "range": [int(sp.get("range_ft", 5)), int(sp.get("range_ft", 5))], "id": "",
		"name": name, "str_based": false}
	var mods := _attack_mods(s, data, probe, t)
	if spell_id == "shocking_grasp" and _metal_armor(data, t):
		(mods["adv"] as Array).append("металлический доспех")
	var dis := not (mods["dis"] as Array).is_empty()
	var adv := not (mods["adv"] as Array).is_empty()
	var agonizing := maxi(0, FeatureRules.ab_mod(c, "cha")) if spell_id == "eldritch_blast" and FeatureRules.has(c, "eldritch_invocation_agonizing_blast") else 0
	var sres := _attack(s, data, str(c["name"]), name, int(c.get("spell_attack", 0)), adv, dis, t,
		_empowered(s, dice), agonizing, dtype, lines)
	_spell_rider(s, data, spell_id, slot, t, bool(sres["hit"]), lines)
	var repel := bool(sres["hit"]) and spell_id == "eldritch_blast" and FeatureRules.has(c, "eldritch_invocation_repelling_blast")
	if repel and str(t.get("status")) == "active" and SIZES.find(str(_monster(data, t).get("size", "medium"))) <= 3:
		var away := 1 if int(t["col"]) >= int(player(s)["col"]) else -1
		t["col"] = clampi(int(t["col"]) + away, -edge(data), edge(data))
		lines.append("Отталкивающий заряд: %s отброшен на 30 фт" % t["name"])


## The darts or rays left of the spell just cast (v0.7.22.4): {spell, slot, left, last} or {}.
static func volley(s: GameSession) -> Dictionary:
	return s.combat.get("volley", {}) if s.combat.get("volley") is Dictionary else {}


## "" when the next dart or ray may fly at `target_id`, else the reason (a localization key).
static func can_volley(s: GameSession, data: Dictionary, target_id: String) -> String:
	var v := volley(s)
	if v.is_empty() or not is_player_turn(s):
		return "COMBAT_NO_VOLLEY"
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active":
		return "COMBAT_BAD_TARGET"
	var sp: Dictionary = data["spells"][str(v["spell"])]
	if cols_between(player(s), t) > range_cols(data, int(sp.get("range_ft", 0))):
		return "COMBAT_OUT_OF_RANGE"
	return ""


## The next dart or ray at `target_id` (can_volley first). Lines.
static func volley_shot(s: GameSession, data: Dictionary, target_id: String) -> Array[String]:
	var v := volley(s)
	var lines: Array[String] = []
	var sp: Dictionary = data["spells"][str(v["spell"])]
	var t := fighter(s, target_id)
	_bolt(s, data, str(v["spell"]), int(v["slot"]), t, _spell_dice(sp, int(v["slot"]), int(s.character.get("level", 1))), lines)
	v["left"] = int(v["left"]) - 1
	v["last"] = target_id
	if int(v["left"]) <= 0 or enemies(s).is_empty():
		s.combat.erase("volley")
	return lines


## The turn ends with darts left: they fly at the last target, or the nearest foe still standing. Lines.
static func volley_flush(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	while not volley(s).is_empty():
		var v := volley(s)
		var to := str(v["last"])
		if not can_volley(s, data, to).is_empty():
			to = ""
			for id: String in enemies(s):
				if can_volley(s, data, id).is_empty():
					to = id
					break
		if to.is_empty():
			s.combat.erase("volley")
			break
		lines.append_array(volley_shot(s, data, to))
	return lines


## Who an area spell covers (v0.7.13): a cone, a cube or a sphere — one column (the hero's for those from self, the
## target's otherwise); a line (Lightning Bolt, 100 ft) — every column from the hero towards the target within it.
static func area_targets(s: GameSession, data: Dictionary, sp: Dictionary, t: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := int(player(s)["col"])
	var area: Dictionary = sp.get("area", {})
	if str(area.get("type", "")) == "line":
		var dir := signi(int(t["col"]) - me)
		var reach := int(area.get("size", 30)) / int(cfg(data)["col_ft"])
		for id: String in enemies(s):
			var col := int(fighter(s, id)["col"])
			var along := (col - me) * dir if dir != 0 else (0 if col == me else -1)
			if along >= 0 and along <= reach and (dir != 0 or col == me):
				out.append(fighter(s, id))
		return out
	var col := me if int(sp.get("range_ft", 0)) == 0 else int(t["col"])
	for id: String in enemies(s):
		if int(fighter(s, id)["col"]) == col:
			out.append(fighter(s, id))
	return out


## The riders of the engine's spells by 5e (v0.7.13): what lasts after the hit or the failed save.
static func _spell_rider(s: GameSession, data: Dictionary, spell_id: String, slot: int, t: Dictionary, landed: bool, lines: Array[String]) -> void:
	if str(t.get("status")) != "active":
		return
	match spell_id:
		"guiding_bolt":
			if landed:
				t["guided"] = 2  # the next attack roll against it has advantage, until the end of the hero's next turn
				lines.append("%s светится — следующая атака по нему с преимуществом" % t["name"])
		"vicious_mockery":
			if landed:
				t["mocked"] = true
				lines.append("%s сбит с толку — его следующая атака с помехой" % t["name"])
		"ray_of_frost":
			if landed:
				t["slowed"] = 10
				lines.append("%s скован холодом: скорость −10 фт" % t["name"])
		"chill_touch":
			if landed:
				t["no_heal"] = true
				if str(_monster(data, t).get("type", "")) == "undead":
					t["chilled"] = true
					lines.append("%s: нежить бьёт героя с помехой" % t["name"])
		"shocking_grasp":
			if landed:
				t["reacted"] = true
				lines.append("%s не может ответить реакцией" % t["name"])
		"acid_arrow":
			var more := "%dd4" % (2 + maxi(0, slot - 2))
			if landed:
				t["acid"] = more
			else:
				var half := _resist(data, t, "acid", roll_dice(s.rng, "%dd4" % (4 + maxi(0, slot - 2))) / 2)
				lines.append("Кислотная стрела: брызги — %d (кислота)" % half)
				_hurt_enemy(s, data, t, half, lines, "acid")
		"thunderwave":
			if landed and SIZES.find(str(_monster(data, t).get("size", "medium"))) <= 3:
				lines.append("%s отброшен на 10 фт" % t["name"])  # within the 30-ft column of the field


## A foe in metal armor (Shocking Grasp): its armor line names mail, plate, scale, a breastplate or splint.
static func _metal_armor(data: Dictionary, t: Dictionary) -> bool:
	var text := " ".join(_monster(data, t).get("equipment", [])).to_lower()
	return ["mail", "plate", "chain", "splint", "breastplate"].any(func(x: String) -> bool: return text.contains(x))


static func ab_name(ab: String) -> String:
	return {"str": "Сил", "dex": "Лов", "con": "Тел", "int": "Инт", "wis": "Мдр", "cha": "Хар"}.get(ab, ab)


## Empowered Spell: the damage dice once more, the better roll counts (approximated as a dice expression «max of two»).
static func _empowered(s: GameSession, dice: String) -> String:
	return dice if str(s.combat.get("meta_now", "")) != "empowered_spell" else "E" + dice


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


## A monster's save; `tags` — what it is against (magic, charm, fear…) for the advantages of its traits (v0.7.9).
static func _monster_save(s: GameSession, data: Dictionary, t: Dictionary, ab: String, dc: int, tags: Array = [], disadv: bool = false) -> bool:
	var m: Dictionary = data["monsters"][t["monster"]]
	var bonus := int(m["saves"].get(ab, CharacterRules.mod(int(m["abilities"].get(ab, 10)))))
	var roll := s.rng.randi_range(1, 20)
	var adv := MonsterRules.save_advantage(data, t, ab, tags)
	if adv and not disadv:
		roll = maxi(roll, s.rng.randi_range(1, 20))
	elif disadv and not adv:  # Heightened Spell (v0.7.10)
		roll = mini(roll, s.rng.randi_range(1, 20))
	if ab in ["str", "dex"] and _target_disabled(t) and not (t["conditions"] as Array).has("prone"):
		return false
	bonus -= int(SpellEffects.foe_die(s, t)["minus"])  # Bane (v0.7.13.1)
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
	if what == "dash" and SpellEffects.has(s.character, "bonus_dash") and int(e.get("bonus", 0)) > 0 and int(e.get("action", 0)) <= 0:
		cost = "bonus"  # Expeditious Retreat (v0.7.13.3)
	if cost == "action" and int(e.get("action", 0)) <= 0 and int(e.get("haste", 0)) > 0:
		cost = "haste"  # Haste's action
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
	if _foe_in_column(s, player(s)) and not _hides_behind(s, data):
		return "COMBAT_HIDE_SEEN"
	var cost := _hide_cost(s)
	if int(economy(s).get(cost, 0)) <= 0:
		return "COMBAT_NO_ACTION" if cost == "action" else "COMBAT_NO_BONUS"
	return ""


## Naturally Stealthy (lightfoot halfling): hides behind a foe at least one size larger.
static func _hides_behind(s: GameSession, data: Dictionary) -> bool:
	if not CharacterRules.has_trait(s.character, "naturally_stealthy"):
		return false
	for id: String in enemies(s):
		var f := fighter(s, id)
		if int(f["col"]) == int(player(s)["col"]) and SIZES.find(str(_monster(data, f).get("size", "medium"))) > SIZES.find(hero_size(s, data)):
			return true
	return false


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
		best = maxi(best, monster_passive(data, fighter(s, id)) - ConditionRules.unseen_penalty(s.character, data))
	var ok := int(roll["total"]) >= best
	if ok:
		player(s)["hidden"] = true
	return ["%s прячется: Скрытность %d%s против Внимательности %d — %s" % [s.character["name"], int(roll["total"]), roll["note"], best,
		"враги теряют из виду" if ok else "враги всё видят"]]


## "" when the player can step one column in `dir` (−1 / +1) — off the edge means fleeing the fight.
static func can_move(s: GameSession, data: Dictionary, dir: int) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	var c := s.character
	if int(c.get("speed", 30)) <= 0:
		return "COMBAT_NO_SPEED"
	if ConditionRules.has(c, "prone"):
		return "COMBAT_PRONE"
	if int(economy(s).get("move", 0)) <= 0:
		return "COMBAT_NO_MOVE"
	if absi(dir) != 1:
		return "COMBAT_BAD_MOVE"
	var src := fear_source(s)
	if not src.is_empty() and absi(int(player(s)["col"]) + dir - int(src["col"])) < absi(int(player(s)["col"]) - int(src["col"])):
		return "COMBAT_FRIGHTENED"
	return ""


## The foe the hero is frightened of, when it is on the field ({} otherwise).
static func fear_source(s: GameSession) -> Dictionary:
	if not ConditionRules.has(s.character, "frightened"):
		return {}
	var by := ConditionRules.caused_by(s.character, "frightened")
	if by.is_empty():
		return {}
	var f := fighter(s, by)
	if f.is_empty():
		f = fighter(s, fighter_of_npc(s, by))
	return f if not f.is_empty() and str(f.get("status")) == "active" else {}


## «Встать» (v0.7.8, decision of the author): standing up takes the whole move of the turn. "" or a key.
static func can_stand(s: GameSession) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	if not ConditionRules.has(s.character, "prone"):
		return "COMBAT_NOT_PRONE"
	if int(s.character.get("speed", 30)) <= 0 or int(economy(s).get("move", 0)) <= 0:
		return "COMBAT_NO_MOVE"
	return ""


static func stand(s: GameSession) -> Array[String]:
	economy(s)["move"] = 0
	ConditionRules.remove(s.character, "prone")
	return ["%s поднимается на ноги" % s.character.get("name", "")]


## «Вырваться» (v0.7.8): grappled, or restrained by something with a DC to break (a net, a web) — an action.
static func can_escape(s: GameSession) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	if _hold_on_hero(s).is_empty():
		return "COMBAT_NOT_HELD"
	if int(economy(s).get("action", 0)) <= 0:
		return "COMBAT_NO_ACTION"
	return ""


## The effect that holds the hero and can be broken: grappled (by a fighter or a DC), restrained with escape_dc.
static func _hold_on_hero(s: GameSession) -> Dictionary:
	for cond: String in ["grappled", "restrained"]:
		for e: Dictionary in ConditionRules.effects_of(s.character, cond):
			if cond == "grappled" or e.has("escape_dc"):
				return e
	return {}


## Athletics or Acrobatics (the better) against the hold's DC or the grappler's Athletics (5e). Lines.
static func escape(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var e := economy(s)
	e["action"] = int(e["action"]) - 1
	var hold := _hold_on_hero(s)
	var skill := "athletics" if int(c["skills"].get("athletics", 0)) >= int(c["skills"].get("acrobatics", 0)) else "acrobatics"
	var mods := ConditionRules.check_mods(c, data, {"skill": skill})
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var mine := _nat(_d20(s.rng, false, dis), false, dis) + int(c["skills"].get(skill, 0))
	var dc := int(hold.get("escape_dc", 0))
	var against := "Сл %d" % dc
	if dc <= 0:
		var g := fighter(s, str(hold.get("by", "")))
		if g.is_empty():
			g = fighter(s, fighter_of_npc(s, str(hold.get("by", ""))))
		var m: Dictionary = _monster(data, g) if not g.is_empty() else {}
		var bonus := int(m.get("skills", {}).get("athletics", CharacterRules.mod(int(m.get("abilities", {}).get("str", 10))))) if not m.is_empty() else 0
		dc = s.rng.randi_range(1, 20) + bonus
		against = "%d (%s)" % [dc, g.get("name", "хватка")]
	var ok := (mods["auto_fail"] as Array).is_empty() and mine >= dc
	var what := ConditionRules.name_of(data, str(hold.get("condition", ""))).to_lower()
	if ok:
		ConditionRules.remove_effect(c, int(hold["uid"]))
		CharacterRules.refresh(c, data, s.items)
		e["move"] = _move_cols(int(c.get("speed", 30)), data)
	return ["%s вырывается: %s %d против %s — %s" % [c.get("name", ""), "Атлетика" if skill == "athletics" else "Акробатика", mine, against,
		("больше не " + what) if ok else "не выходит"]]


## Steps the player (can_move first): attacks of opportunity from foes left behind, fleeing off the edge. Lines.
static func player_move(s: GameSession, data: Dictionary, dir: int) -> Array[String]:
	var e := economy(s)
	e["move"] = int(e["move"]) - 1
	var p := player(s)
	var lines: Array[String] = []
	if not bool(p.get("disengaged", false)):
		for id: String in enemies(s):
			var f := fighter(s, id)
			if int(f["col"]) == int(p["col"]) and can_react(s, data, f):
				var act := _best_action(data, f, "melee")
				if not act.is_empty():
					f["reacted"] = true
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
	_release_grapples(s, lines)
	return lines


# --- grapple and shove (v0.7.7) ---------------------------------------------------------------------------

const SIZES: Array[String] = ["tiny", "small", "medium", "large", "huge", "gargantuan"]


## "" when the hero can grapple or shove `target_id` now (instead of one attack of the Attack action, 5e), else a
## localization key: the hero's turn, an attack left, the foe right next to the hero and at most one size larger.
static func can_grapple(s: GameSession, data: Dictionary, target_id: String) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	var e := economy(s)
	if int(e.get("attacks", 0)) <= 0 and int(e.get("action", 0)) <= 0:
		return "COMBAT_NO_ACTION"
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active" or str(t.get("side")) != "enemy":
		return "COMBAT_BAD_TARGET"
	if cols_between(player(s), t) != 0:
		return "COMBAT_OUT_OF_REACH"
	if SIZES.find(str(_monster(data, t).get("size", "medium"))) > SIZES.find(hero_size(s, data)) + 1:
		return "COMBAT_TOO_BIG"
	return ""


## The foe cannot get this condition (its condition immunities, v0.7.9).
static func immune_to(data: Dictionary, t: Dictionary, cond: String) -> bool:
	return (_monster(data, t).get("condition_immunities", []) as Array).has(cond)


static func hero_size(s: GameSession, data: Dictionary) -> String:
	return str(data["races"]["races"].get(str(s.character.get("race", "")), {}).get("size", "medium"))


## Grapple (`shove` false: the foe is «схвачен», its speed 0, until the hero walks off) or shove (the foe falls
## «лежит ничком»): the hero's Athletics against the foe's better of Athletics and Acrobatics (can_grapple first).
## Takes one attack of the Attack action. Returns the lines.
static func grapple(s: GameSession, data: Dictionary, target_id: String, shove: bool) -> Array[String]:
	var c := s.character
	var e := economy(s)
	if int(e.get("attacks", 0)) > 0:
		e["attacks"] = int(e["attacks"]) - 1
	else:
		e["action"] = int(e["action"]) - 1
		e["attacks"] = CharacterRules.extra_attacks(c, data)
	e["attacked"] = true
	s.combat["rage_kept"] = true
	var t := fighter(s, target_id)
	var mods := ConditionRules.check_mods(c, data, {"skill": "athletics"})
	var lines: Array[String] = []
	lines.append_array(ConditionRules.end_invisibility_on_attack(c, data))
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := _d20(s.rng, false, dis)
	var mine := _nat(rolls, false, dis) + int(c.get("skills", {}).get("athletics", 0))
	var m := _monster(data, t)
	var sk: Dictionary = m.get("skills", {})
	var ab: Dictionary = m.get("abilities", {})
	var theirs_bonus := maxi(int(sk.get("athletics", CharacterRules.mod(int(ab.get("str", 10))))), int(sk.get("acrobatics", CharacterRules.mod(int(ab.get("dex", 10))))))
	var auto_lose := incapacitated(t)  # a foe that cannot act does not resist (5e: it fails Str / Dex)
	var theirs := 0 if auto_lose else s.rng.randi_range(1, 20) + theirs_bonus
	var won := not (mods["auto_fail"] as Array).size() > 0 and mine >= theirs
	var what := "толкает, чтобы сбить с ног" if shove else "пытается схватить"
	lines.append("%s %s %s: Атлетика %d против %d — %s" % [c.get("name", ""), what, t["name"], mine, theirs, "успех" if won else "не выходит"])
	if won and immune_to(data, t, "prone" if shove else "grappled"):
		lines.append("%s: на него это не действует" % t["name"])
	elif won:
		if shove:
			_hold(t, "prone")
			lines.append("%s падает" % t["name"])
		else:
			_hold(t, "grappled")
			t["grappled_by_player"] = true
			lines.append("%s схвачен: не может отойти" % t["name"])
	return lines


## A condition with no timer: it lasts until something ends it (standing up, the hero walking off).
static func _hold(f: Dictionary, cond: String) -> void:
	if not _has(f, cond):
		(f["conditions"] as Array).append(cond)
	if cond == "invisible":
		f["seen_col"] = int(f["col"])


## The hero walked off: the foes the hero held are free (Lines).
static func _release_grapples(s: GameSession, lines: Array[String]) -> void:
	for id: String in enemies(s):
		var f := fighter(s, id)
		if bool(f.get("grappled_by_player", false)):
			f.erase("grappled_by_player")
			_remove_condition(f, "grappled")
			lines.append("%s больше не схвачен" % f["name"])


## A foe can strike the leaving hero (5e, v0.7.7): its reaction is unspent this round, it can act (not
## incapacitated, paralysed, stunned, asleep), is not charmed by the hero and sees the hero (not blinded, the hero
## not invisible). A prone or restrained foe still can.
static func can_react(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return not bool(f.get("reacted", false)) and not incapacitated(f) and not _has(f, "charmed") and not _has(f, "blinded") \
		and not ConditionRules.invisible(s.character, data)


## The rest of the turn is skipped: next fighter (the UI plays the others one by one via next_actor()).
## Returns the lines of a new round's start (reinforcements arriving).
static func end_player_turn(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = volley_flush(s, data)  # darts left fly at the last target (v0.7.22.4)
	lines.append_array(ConditionRules.end_of_turn(s, data))
	if SpellEffects.has(s.character, "blink"):  # Blink (v0.7.13.3)
		var r := s.rng.randi_range(1, 20)
		if r >= 11:
			player(s)["blinked"] = true
			lines.append("Мерцание: %d — %s исчезает в эфире до своего хода" % [r, s.character["name"]])
		else:
			lines.append("Мерцание: %d — остаётся здесь" % r)
	for eid: String in enemies(s):  # Guiding Bolt lasts until the end of the hero's next turn (v0.7.13)
		var o := fighter(s, eid)
		if o.has("guided"):
			o["guided"] = int(o["guided"]) - 1
			if int(o["guided"]) <= 0:
				o.erase("guided")
	FeatureRules.end_hero_turn(s, data, lines)
	s.combat.erase("prompt")
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
			_death_save(s, data, lines)
		elif bool(player(s).get("surprised", false)):
			player(s).erase("surprised")
			lines.append("%s застигнут врасплох и не успевает ничего сделать" % s.character["name"])
		elif ConditionRules.incapacitated(s.character):
			lines.append("%s не может действовать: %s" % [s.character["name"], ", ".join((s.character["conditions"] as Array).filter(
				func(x: Variant) -> bool: return ConditionRules.INCAPACITATING.has(str(x))).map(func(x: Variant) -> String: return ConditionRules.name_of(data, str(x)).to_lower()))])
			lines.append_array(ConditionRules.end_of_turn(s, data))
			if _held_for_good(s):
				s.combat["outcome"] = "captured" if enemies(s).any(func(id: String) -> bool: return _intelligent(data, fighter(s, id))) else "dead"
				lines.append("%s не может больше сражаться" % s.character["name"])
		else:
			return lines
		_check_end(s, data, lines)
		if str(s.combat["outcome"]).is_empty():
			_advance(s, data, lines)
		return lines
	var f := fighter(s, id)
	if str(f.get("side")) == "ally":
		if str(f.get("status")) == "active":
			if incapacitated(f):
				lines.append("%s не может действовать: %s" % [f["name"], ", ".join(foe_conditions(data, f))])
			elif not bool(f.get("surprised", false)):
				if _has(f, "prone"):
					_remove_condition(f, "prone")
					lines.append("%s поднимается на ноги" % f["name"])
				_ally_turn(s, data, f, lines)
			f.erase("surprised")
			_tick_conditions(s, data, f, lines)
		_check_end(s, data, lines)
		if str(s.combat["outcome"]).is_empty():
			_advance(s, data, lines)
		return lines
	if str(f.get("status")) == "active":
		if bool(f.get("surprised", false)):
			f.erase("surprised")
			lines.append("%s застигнут врасплох и не успевает ничего сделать" % f["name"])
		elif incapacitated(f):
			lines.append("%s не может действовать: %s" % [f["name"], ", ".join(foe_conditions(data, f))])
			MonsterRules.release(s, data, f, lines)
		elif _has(f, "charmed"):
			lines.append("%s очарован и не нападает" % f["name"])
		else:
			if _has(f, "prone"):
				_remove_condition(f, "prone")
				lines.append("%s поднимается на ноги" % f["name"])
			_enemy_turn(s, data, f, lines)
			if bool(s.combat.get("halt", false)):
				return lines  # answer_reaction finishes this turn
			MonsterRules.end_turn(s, data, f, lines)
		_tick_conditions(s, data, f, lines)
	_check_end(s, data, lines)
	if str(s.combat["outcome"]).is_empty():
		_advance(s, data, lines)
	return lines


## The rest of a foe's turn after its attacks (also after a reaction prompt). Lines.
static func _end_actor(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	f.erase("mocked")
	if str(f.get("status")) == "active" and f.has("acid"):  # Acid Arrow burns at the end of the foe's next turn (v0.7.13)
		var acid := _resist(data, f, "acid", roll_dice(s.rng, str(f["acid"])))
		f.erase("acid")
		lines.append("%s: кислота жжёт — %d" % [f["name"], acid])
		_hurt_enemy(s, data, f, acid, lines, "acid")
	if str(f.get("status")) == "active":
		lines.append_array(SpellEffects.zone_tick(s, data, f, "end"))  # Flaming Sphere (v0.7.13.5)
	if str(f.get("status")) == "active":
		lines.append_array(SpellEffects.curse_saves(s, data, f))  # v0.7.13.6
	if str(f.get("status")) == "active":
		MonsterRules.end_turn(s, data, f, lines)
		_tick_conditions(s, data, f, lines)
	_check_end(s, data, lines)
	if str(s.combat["outcome"]).is_empty():
		_advance(s, data, lines)


static func _death_save(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var ds: Dictionary = s.combat["death_saves"]
	if bool(ds.get("stable", false)):
		return
	if CharacterRules.item_prop(s.character, "wound_closure"):  # Periapt of Wound Closure (v0.7.12)
		ds["stable"] = true
		lines.append("%s стабилизируется — Амулет закрытия ран" % s.character["name"])
		return
	var roll := s.rng.randi_range(1, 20)
	if not SpellEffects.hero_effects(s.character, "death_adv").is_empty():  # Beacon of Hope (v0.7.13.2)
		roll = maxi(roll, s.rng.randi_range(1, 20))
	if roll == 20:
		s.character["hp"] = 1
		ConditionRules.remove(s.character, "unconscious")
		s.combat["death_saves"] = {"ok": 0, "fail": 0}
		lines.append("%s: спасбросок от смерти 20 — приходит в себя с 1 HP!" % s.character["name"])
		return
	if roll + DifficultyRules.bonus(s, data) >= 10:
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
	if f.has("actions"):  # a fighter that lost its weapon (v0.7.22.8)
		var m: Dictionary = (data["monsters"][f["monster"]] as Dictionary).duplicate()
		m["actions"] = f["actions"]
		return m
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
	MonsterRules.start_turn(s, data, f, lines)
	lines.append_array(SpellEffects.zone_tick(s, data, f, "start"))  # Moonbeam, Spirit Guardians (v0.7.13.5)
	if str(f["status"]) != "active":
		return
	if f.has("slowed_spell"):
		f["reacted"] = true  # Slow: no reactions
	if bool(f.get("retching", false)):  # Stinking Cloud (v0.7.13.6)
		f.erase("retching")
		lines.append("%s давится и пропускает ход" % f["name"])
		return
	if f.has("burning"):  # alchemist's fire (v0.7.12): burns until a DEX save DC 10 puts it out
		var burn := _resist(data, f, "fire", roll_dice(s.rng, str(f["burning"])))
		lines.append("%s горит: %d (огонь)" % [f["name"], burn])
		_hurt_enemy(s, data, f, burn, lines, "fire")
		if str(f["status"]) != "active":
			return
		if _monster_save(s, data, f, "dex", 10):
			f.erase("burning")
			lines.append("%s сбивает пламя" % f["name"])
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
	var steps := _move_cols(int(m.get("speed", 30)) - int(f.get("slowed", 0)), data)
	if (SpellEffects.slowed(s, f) or f.has("slowed_spell")) and steps > 0:  # a slowing zone or Slow: half the way
		steps = maxi(1, steps / 2) if int(m.get("speed", 30)) >= 60 else 0 if s.rng.randi_range(0, 1) == 0 else 1
	if _has(f, "restrained") or _has(f, "grappled"):
		steps = 0
	if bool(f.get("fleeing", false)):
		MonsterRules.release(s, data, f, lines)
		var dir := 1 if int(f["col"]) >= int(p["col"]) else -1
		for i in steps:
			if int(f["col"]) == int(p["col"]) and int(s.character["hp"]) > 0 and not MonsterRules.has_trait(data, f, "flyby") \
					and not ConditionRules.incapacitated(s.character):
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
	var aim := _foe_target(s, f)
	if aim != PLAYER and not aim.is_empty():  # v0.7.22.22: an ally of the hero is nearer (or the hero is down)
		if int(s.character["hp"]) > 0 and MonsterRules.cast_turn(s, data, f, lines):
			return
		_creature_turn(s, data, f, fighter(s, aim), lines)
		return
	var down := int(s.character["hp"]) <= 0
	if down:  # v0.7.9: beasts do not finish the downed hero either — they lose interest
		lines.append(("%s не добивает упавшего" if _intelligent(data, f) else "%s теряет интерес к упавшему") % f["name"])
		return
	var d := cols_between(f, p)
	if MonsterRules.cast_turn(s, data, f, lines):
		return
	var special := MonsterRules.save_action(s, data, f, d)
	if not special.is_empty():
		_enemy_attack(s, data, f, special, lines)
		return
	var melee := MonsterRules.pick(s, data, f, "melee")
	var ranged := MonsterRules.pick(s, data, f, "ranged")
	if SpellEffects.has(s.character, "flying") and not MonsterRules.flies(data, f):  # Fly (v0.7.13.3): only what reaches the air
		if not ranged.is_empty() and d * int(cfg(data)["col_ft"]) <= int(ranged["range"][1]):
			_enemy_attack_full(s, data, f, ranged, lines)
		elif not ranged.is_empty():
			var to_hero := 1 if int(p["col"]) > int(f["col"]) else -1
			f["col"] = int(f["col"]) + to_hero
			lines.append("%s подходит на выстрел" % f["name"])
		else:
			lines.append("%s не достаёт летящего героя" % f["name"])
		return
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
	# Close in: a move, then attack if in reach or in range, else Dash (one more move). A frightened foe keeps away.
	if _has(f, "frightened"):
		steps = 0
	elif steps > 0 and MonsterRules.has_trait(data, f, "aggressive"):
		steps += 1  # Aggressive: a bonus move towards the hero
	var dir := 1 if int(p["col"]) > int(f["col"]) else -1
	var moved := 0
	while moved < steps and cols_between(f, p) > 0:
		f["col"] = int(f["col"]) + dir
		moved += 1
		lines.append_array(SpellEffects.zone_tick(s, data, f, "enter"))  # v0.7.13.5
		if str(f["status"]) != "active":
			return
	f["moved"] = moved
	_find_hidden(s, f, lines)
	if cols_between(f, p) == 0 and not melee.is_empty():
		lines.append("%s сближается вплотную" % f["name"])
		if moved > 0:
			_reach_strike(s, data, f, lines)
			if str(f["status"]) != "active":
				return
		_enemy_attack_full(s, data, f, melee, lines)
		return
	if not ranged.is_empty() and cols_between(f, p) * int(cfg(data)["col_ft"]) <= int(ranged["range"][1]):
		_enemy_attack_full(s, data, f, ranged, lines)
		return
	while moved < steps * 2 and cols_between(f, p) > 0 and steps > 0:
		f["col"] = int(f["col"]) + dir
		moved += 1
		lines.append_array(SpellEffects.zone_tick(s, data, f, "enter"))
		if str(f["status"]) != "active":
			return
	_find_hidden(s, f, lines)
	lines.append("%s бежит ближе" % f["name"] if cols_between(f, p) > 0 else "%s сближается вплотную" % f["name"])


## Misty Step: `cols` columns away from the nearest foe, no opportunity attacks (v0.7.13.3). Lines.
static func _teleport(s: GameSession, data: Dictionary, cols: int) -> Array[String]:
	var p := player(s)
	var nearest := 99
	var dir := 1
	for id: String in enemies(s):
		var f := fighter(s, id)
		var dd := absi(int(f["col"]) - int(p["col"]))
		if dd < nearest:
			nearest = dd
			dir = -1 if int(f["col"]) >= int(p["col"]) else 1
	var to := clampi(int(p["col"]) + dir * cols, -edge(data), edge(data))
	if to == int(p["col"]):
		to = clampi(int(p["col"]) - dir * cols, -edge(data), edge(data))
	p["col"] = to
	return ["%s переносится серебристым туманом на %d фт" % [s.character["name"], cols * int(cfg(data)["col_ft"])]]


## A reach weapon meets a foe on its way in (v0.7.12): the hero's reaction, one attack before the foe strikes.
static func _reach_strike(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	var wid := str(c.get("equipped", {}).get("main_hand", ""))
	if wid.is_empty() or bool(player(s).get("reacted", false)) or ConditionRules.incapacitated(c) or int(c.get("hp", 0)) <= 0:
		return
	var w := weapon_profile(c, data, s.items, wid)
	if not bool(w.get("reach", false)) or not bool(w["melee"]):
		return
	player(s)["reacted"] = true
	lines.append("%s встречает %s на подходе — %s бьёт дальше (досягаемость)" % [c["name"], f["name"], w["name"]])
	_attack(s, data, str(c["name"]), w["name"], int(w["to_hit"]), false, false, f, str(w["dice"]), int(w["bonus"]), str(w["type"]), lines, "", false, w)


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
	if str(act.get("kind")) == "melee" and cols_between(f, player(s)) > 0:
		seq = []  # a throw of a melee weapon is one attack: Multiattack counts melee strikes (v0.7.22.19, #13)
	for x: Dictionary in seq:
		var a: Dictionary = by_en.get(str(x["action"]), {})
		if not a.is_empty() and (str(a.get("kind")) == str(act.get("kind")) or (str(act.get("kind")) == "ranged" and a.has("range"))):
			for i in int(x["count"]):
				plan.append(a)
	if plan.is_empty():
		plan.append(act)
	if f.has("slowed_spell"):  # Slow: one attack (v0.7.13.6)
		plan = [plan[0]]
	for i in plan.size():
		if int(s.character["hp"]) <= 0:
			return  # nobody finishes the downed hero (v0.7.9)
		if str(s.combat.get("outcome", "")) == "dead":
			return
		_enemy_attack(s, data, f, plan[i], lines)
		if bool(s.combat.get("halt", false)):  # the hero is asked about a reaction: the rest of the attacks wait
			var rest: Array = []
			for b: Dictionary in plan.slice(i + 1):
				rest.append(str(b["name_en"]))
			s.combat["resume_plan"] = rest
			return


static func _enemy_attack(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	var p := player(s)
	var dtypes: Dictionary = data["misc"]["damage_types"]
	MonsterRules.spend(f, a)
	if str(a.get("kind")) == "save":
		var sv: Dictionary = a["save"]
		var ab := str(sv["ability"])
		var tag := MonsterRules.tag_of(a.get("effect", {}), a)
		if tag.is_empty() and (a["damage"] as Array).any(func(d: Dictionary) -> bool: return str(d.get("type", "")) == "poison"):
			tag = "poison"
		var r := HeroDefense.save(s, data, ab, int(sv["dc"]), tag)
		var ok := bool(r["ok"])
		var dmg := 0
		var notes: Array[String] = []
		for d: Dictionary in a["damage"]:
			var part := roll_dice(s.rng, str(d["dice"]))
			part = part / 2 if ok and str(sv["success"]) == "half" else (0 if ok else part)
			var adj := HeroDefense.adjust(s, data, str(d.get("type", "")), part)
			dmg += int(adj["damage"])
			if not str(adj["note"]).is_empty() and not notes.has(str(adj["note"])):
				notes.append(str(adj["note"]))
		if (a["damage"] as Array).is_empty():
			lines.append("%s — %s: спасбросок %s" % [f["name"], a["name"], r["text"]])
		else:
			lines.append("%s — %s: спасбросок %s, %d урона%s" % [f["name"], a["name"], r["text"], dmg, (" (%s)" % ", ".join(notes)) if not notes.is_empty() else ""])
			_hurt_player(s, data, dmg, false, lines)
		if not bool(r["ok"]) and a.has("effect"):
			MonsterRules.apply_effect(s, data, f, a, dmg, lines, {"ok": false, "dc": int(sv["dc"]), "total": int(r["total"])})
		return
	var d := cols_between(f, p)
	var ranged_use := d > 0
	if ranged_use and str(a.get("kind")) == "melee" and a.has("range"):  # thrown: out of the hand for the fight (v0.7.22.19)
		var gone: Array = f.get("thrown", [])
		gone.append(str(a.get("name_en", "")))
		f["thrown"] = gone
	if _has(f, "invisible"):
		f["seen_col"] = int(f["col"])  # a strike gives an invisible foe away
	var helpless := ["paralyzed", "stunned", "unconscious", "restrained", "petrified"].any(func(x: String) -> bool: return ConditionRules.has(c, x))
	var tm := MonsterRules.attack_mods(s, data, f, a)
	f["hidden"] = false  # an attack gives a hidden foe away
	var adv := (_target_disabled_player(c) and not ranged_use) or helpless or (_has_trait(data, f, "pack_tactics") and _ally_near_player(s, f)) \
		or ConditionRules.has(c, "blinded") or (_has(f, "invisible") and not SpellEffects.has(c, "see_invisible")) or not (tm["adv"] as Array).is_empty() or bool(s.combat.get("reckless", false)) \
		or (TimeRules.dark(s, data) and MonsterRules.sees_in_dark(data, f))
	var dis := bool(p.get("dodging", false)) and int(c["hp"]) > 0 and not ConditionRules.incapacitated(c) \
		or (ranged_use and a.has("range") and d * int(cfg(data)["col_ft"]) > int(a["range"][0])) \
		or (str(a.get("kind")) == "ranged" and d == 0) or (f["conditions"] as Array).has("poisoned") or bool(p.get("hidden", false)) \
		or (ConditionRules.invisible(c, data) and not _has(f, "invisible")) or (ranged_use and ConditionRules.has(c, "prone")) \
		or ["blinded", "restrained", "frightened", "prone"].any(func(x: String) -> bool: return _has(f, x)) or not (tm["dis"] as Array).is_empty() \
		or bool(f.get("mocked", false)) or bool(f.get("chilled", false)) or not SpellEffects.attack_dis(s, data, f).is_empty() \
		or f.has("cursed_dis") or SpellEffects.obscured(s, int(f["col"])) != SpellEffects.obscured(s, int(p["col"]))
	f.erase("mocked")  # Vicious Mockery: only the next attack roll (v0.7.13)
	if bool(p.get("blinked", false)):  # Blink (v0.7.13.3)
		lines.append("%s бьёт в пустоту — героя нет на этом плане" % f["name"])
		return
	if ranged_use and a.has("range") and not SpellEffects.wall_between(s, int(f["col"]), int(p["col"])).is_empty():
		lines.append("%s — %s: снаряд сносит Стена ветра" % [f["name"], a["name"]])  # v0.7.13.6
		return
	var held := SpellEffects.sanctuary_holds(s, data, f)  # Sanctuary (v0.7.13.2)
	if not held.is_empty():
		lines.append(held)
		return
	var rolls := _d20(s.rng, adv, dis)
	var nat := _nat(rolls, adv, dis)
	var bane := SpellEffects.foe_die(s, f)  # Bane (v0.7.13.1)
	var total := nat + int(a.get("to_hit", 0)) - int(bane["minus"])
	var ac := int(c.get("ac", 10))
	var hit := nat == 20 or (nat != 1 and total >= ac)
	var mark := " (с преимуществом)" if adv and not dis else " (с помехой)" if dis and not adv else ""
	var line := "%s — %s: %d + %d%s = %d против КД %d%s" % [f["name"], a["name"], nat, int(a.get("to_hit", 0)), bane["note"], total, ac, mark]
	if not hit:
		lines.append(line + " — промах")
		fx(s, PLAYER, "dodge")
		return
	var guard := SpellEffects.against_attack(s, data, f, total, hit)  # Mirror Image (v0.7.13.2)
	if not str(guard["stop"]).is_empty():
		lines.append(line + " — " + str(guard["stop"]))
		return
	if c.has("wild_shape"):
		ac = int(c.get("ac", 10))  # the beast's AC is the sheet's while in the form
	var crit := nat == 20 or (not ranged_use and (int(c["hp"]) <= 0 or ConditionRules.has(c, "paralyzed") or ConditionRules.has(c, "unconscious")))
	if crit and CharacterRules.item_prop(c, "no_crit"):
		crit = false  # adamantine armor: a critical hit is a normal one (v0.7.12)
		line += " (адамантин: не крит)"
	var dmg := 0
	var types: Array[String] = []
	var notes: Array[String] = []
	var first := true
	var extra := MonsterRules.extra_on_hit(s, data, f, a, adv and not dis, dis and not adv, crit)
	if int(extra["damage"]) > 0:
		var adj_x := HeroDefense.adjust(s, data, str((a["damage"] as Array)[0].get("type", "")) if not (a["damage"] as Array).is_empty() else "", int(extra["damage"]))
		dmg += int(adj_x["damage"])
		notes.append_array(extra["notes"])
	for dd: Dictionary in a["damage"]:
		var part := roll_dice(s.rng, str(dd["dice"]), crit)
		if first:
			part = maxi(1, part)
			first = false
		var adj := HeroDefense.adjust(s, data, str(dd["type"]), part)
		dmg += int(adj["damage"])
		types.append(str(dtypes.get(str(dd["type"]), dd["type"])))
		if not str(adj["note"]).is_empty() and not notes.has(str(adj["note"])):
			notes.append(str(adj["note"]))
	if f.has("enfeebled") and str(a.get("kind")) in ["melee", "ranged"]:  # Ray of Enfeeblement (v0.7.13.6)
		dmg /= 2
		notes.append("ослаблен")
	var ctx := {"foe": str(f["id"]), "action": str(a.get("name_en", "")), "line": line, "crit": crit, "dmg": dmg, "types": types, "notes": notes,
		"prone": extra["prone"], "hit": true, "total": total, "ac": ac, "nat20": nat == 20}
	f["last_total"] = total  # for the labels of the reaction spells (v0.7.13.7)
	var rx := FeatureRules.reactions(s, data, f, a, ranged_use, dmg, ctx)  # v0.7.10: the hero's reaction
	if not rx.is_empty():
		var pol := FeatureRules.policy(s)
		if pol == "ask" and current(s) == str(f["id"]):
			ctx["options"] = rx
			s.combat["pending"] = ctx
			s.combat["halt"] = true
			return
		if pol != "never":
			FeatureRules.apply_reaction(s, data, f, str(rx[0]["id"]), ctx, lines)
	_land_hit(s, data, f, a, ctx, lines)


## A foe's hit lands (after the hero's reaction, if any): damage, a charge's fall, the effect of the attack, a pounce,
## Giant Killer's strike back. Lines.
static func _land_hit(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, ctx: Dictionary, lines: Array[String]) -> void:
	var dmg := int(ctx["dmg"])
	var crit := bool(ctx["crit"])
	var line := str(ctx["line"])
	if not bool(ctx["hit"]):
		lines.append(line + " — промах")
		fx(s, PLAYER, "dodge")
	elif (a["damage"] as Array).is_empty():
		lines.append(line + " — попадание")
	else:
		var notes: Array = ctx["notes"]
		lines.append(line + (" — КРИТ! " if crit else " — попадание, ") + "%d (%s)%s" % [dmg, ", ".join(ctx["types"]), (", " + ", ".join(notes)) if not notes.is_empty() else ""])
		if crit:
			fx(s, PLAYER, "crit")
		_hurt_player(s, data, dmg, crit, lines)
	if str(s.combat.get("outcome", "")) == "dead":
		return
	if bool(ctx["hit"]):
		var pounce := MonsterRules.charge_prone(s, data, f, ctx["prone"], lines)
		MonsterRules.apply_effect(s, data, f, a, dmg, lines)
		if pounce:  # a pounce: one bite at the prone hero as a bonus action
			for b: Dictionary in _monster(data, f)["actions"]:
				if str(b.get("name_en", "")) == "Bite" and str(b.get("kind")) == "melee":
					lines.append("%s кусает упавшего" % f["name"])
					_enemy_attack(s, data, f, b, lines)
					break
	if int(ctx.get("rebuke", 0)) > 0 and str(f.get("status")) == "active":  # Hellish Rebuke (v0.7.13.7)
		SpellEffects.rebuke(s, data, f, int(ctx["rebuke"]), lines)
	if bool(ctx.get("counter", false)) and str(f.get("status")) == "active" and int(s.character.get("hp", 0)) > 0:
		var w := weapon_profile(s.character, data, s.items, str(s.character.get("equipped", {}).get("main_hand", "")))
		lines.append("%s: Убийца великанов — удар в ответ" % s.character.get("name", ""))
		lines.append_array(strike(s, data, str(f["id"]), w, {"no_horde": true}))


## The player answered the reaction prompt: `choice` — a reaction id or "none". The foe's turn goes on. Lines.
static func answer_reaction(s: GameSession, data: Dictionary, choice: String) -> Array[String]:
	var ctx: Dictionary = s.combat.get("pending", {})
	s.combat.erase("pending")
	s.combat.erase("halt")
	var lines: Array[String] = []
	if ctx.is_empty():
		return lines
	var f := fighter(s, str(ctx["foe"]))
	if str(ctx.get("kind", "")) == "counter":  # a foe's spell waits for Counterspell (v0.7.13.7)
		if choice == "none" or not SpellEffects.counter(s, data, f, str(ctx["option"]["id"]), int(ctx["circle"]), lines):
			MonsterRules._cast(s, data, f, ctx["option"], lines, true)
		_end_actor(s, data, f, lines)
		return lines
	var a := {}
	for x: Dictionary in _monster(data, f)["actions"]:
		if str(x["name_en"]) == str(ctx["action"]):
			a = x
	if choice != "none":
		FeatureRules.apply_reaction(s, data, f, choice, ctx, lines)
	_land_hit(s, data, f, a, ctx, lines)
	var plan: Array = s.combat.get("resume_plan", [])
	s.combat.erase("resume_plan")
	while not plan.is_empty() and str(s.combat.get("outcome", "")).is_empty() and int(s.character.get("hp", 0)) > 0:
		var name := str(plan.pop_front())
		for x: Dictionary in _monster(data, f)["actions"]:
			if str(x["name_en"]) == name:
				_enemy_attack(s, data, f, x, lines)
				break
		if bool(s.combat.get("halt", false)):
			s.combat["resume_plan"] = plan
			return lines
	_end_actor(s, data, f, lines)
	return lines


static func _target_disabled_player(c: Dictionary) -> bool:
	for cnd: String in ["prone", "paralyzed", "stunned", "unconscious", "restrained", "petrified"]:
		if ConditionRules.has(c, cnd):
			return true
	return int(c.get("hp", 1)) <= 0


## The hero cannot act and nothing will end it in the fight: no time limit and no repeat save (petrified for good).
static func _held_for_good(s: GameSession) -> bool:
	for cond: String in ConditionRules.INCAPACITATING:
		for e: Dictionary in ConditionRules.effects_of(s.character, cond):
			if e.get("ends", {}).has("at") or bool(e.get("save", {}).get("repeat", false)) or bool(e.get("wake", false)):
				return false
			if not e.get("ends", {}).has("at"):
				return true
	return false


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
	s.combat["rage_kept"] = true
	dmg = HeroDefense.absorb(c, dmg, lines)  # temporary HP (v0.7.10)
	dmg = FeatureRules.hurt_shape(s, data, dmg, lines)  # a beast form takes it first
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
		lines.append_array(HeroDefense.after_damage(s, data, dmg))
		return
	c["hp"] = 0
	if -left >= int(c["max_hp"]):
		s.combat["outcome"] = "dead"
		lines.append("%s погибает на месте" % c["name"])
		return
	if HeroDefense.relentless(s, data, lines):
		lines.append_array(HeroDefense.after_damage(s, data, dmg))
		return
	lines.append_array(ConditionRules.impose(s, data, {"condition": "unconscious", "ends": {"rest": "long"}, "source": {"kind": "engine", "name": "0 HP"}}))
	s.combat["death_saves"] = {"ok": 0, "fail": 0}
	s.combat.erase("raging")
	lines.append("%s падает без сознания" % c["name"])


# --- allies (v0.7.22.22, AllyRules) --------------------------------------------------------------


## Adds allies to the fight; `mid_fight` — summoned on a turn: each takes its initiative at once. Ids.
static func add_allies(s: GameSession, data: Dictionary, specs: Array, mid_fight: bool = false) -> Array[String]:
	var ids := _add_foes(s, data, specs, 99, "ally")
	if mid_fight:
		for id: String in ids:
			_insert_initiative(s, data, id)
			if (s.combat["order"] as Array).find(id) <= int(s.combat["turn"]):
				s.combat["turn"] = int(s.combat["turn"]) + 1  # it came in before the one acting now: the turn stays
	return ids


## Whom a foe goes for: the nearest of the hero (standing) and the hero's allies, a tie — the hero; a hidden or
## invisible hero only when no ally is there. "" — nobody to strike.
static func _foe_target(s: GameSession, f: Dictionary) -> String:
	var best := ""
	var dist := 999
	if int(s.character.get("hp", 0)) > 0:
		best = PLAYER
		dist = cols_between(f, player(s))
		if bool(player(s).get("hidden", false)) or ConditionRules.has(s.character, "invisible"):
			dist += 99
	for id: String in allies(s):
		var d := cols_between(f, fighter(s, id))
		if d < dist:
			best = id
			dist = d
	return best


## An ally's turn: a helper (a familiar) distracts the foe nearest the hero — the hero's next attack at it has
## advantage (the Help action); the rest go for the nearest foe in sight.
static func _ally_turn(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var p := player(s)
	var target := {}
	var dist := 9999
	for id: String in enemies(s):
		var e := fighter(s, id)
		if bool(e.get("hidden", false)) or _has(e, "invisible"):
			continue
		var d := cols_between(f, e) * 100 + cols_between(e, p)  # the nearest to the ally, then to the hero
		if bool(f.get("helper", false)):
			d = cols_between(e, p)
		if d < dist:
			dist = d
			target = e
	if target.is_empty():
		lines.append("%s не видит врага" % f["name"])
		return
	if bool(f.get("helper", false)):
		f["col"] = int(target["col"])
		target["helped"] = true
		lines.append("%s кружит у %s и отвлекает — следующая атака героя по нему с преимуществом" % [f["name"], target["name"]])
		return
	_creature_turn(s, data, f, target, lines)


## A plain attack of a creature of the kind (the best to-hit with damage; a thrown weapon not thrown yet). {} when none.
static func _pick_plain(data: Dictionary, f: Dictionary, kind: String) -> Dictionary:
	var best := {}
	for a: Dictionary in _monster(data, f)["actions"]:
		var ok := str(a.get("kind")) == kind or (kind == "ranged" and a.has("range"))
		if not ok or (a.get("damage", []) as Array).is_empty() or not MonsterRules.available(f, a):
			continue
		if kind == "ranged" and str(a.get("kind")) == "melee" and (f.get("thrown", []) as Array).has(str(a.get("name_en", ""))):
			continue
		if best.is_empty() or int(a.get("to_hit", 0)) > int(best.get("to_hit", 0)):
			best = a
	return best


static func _reaches(data: Dictionary, f: Dictionary, t: Dictionary, ranged: Dictionary) -> bool:
	var d := cols_between(f, t)
	return not ranged.is_empty() and d > 0 and d * int(cfg(data)["col_ft"]) <= int(ranged["range"][1])


## One creature fights another (an ally and a foe, either way): a shooter shoots when it reaches, the rest close in —
## a move, then the full attack; out of reach after the move — Dash.
static func _creature_turn(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, lines: Array[String]) -> void:
	var m := _monster(data, f)
	var steps := _move_cols(int(m.get("speed", 30)) - int(f.get("slowed", 0)), data)
	if _has(f, "restrained") or _has(f, "grappled") or _has(f, "frightened"):
		steps = 0
	var melee := _pick_plain(data, f, "melee")
	var ranged := _pick_plain(data, f, "ranged")
	if cols_between(f, t) == 0 and not melee.is_empty():
		_creature_full(s, data, f, melee, t, lines)
		return
	if _reaches(data, f, t, ranged) and (melee.is_empty() or cols_between(f, t) > steps):
		_creature_full(s, data, f, ranged, t, lines)
		return
	var dir := 1 if int(t["col"]) > int(f["col"]) else -1
	var moved := 0
	while moved < steps and cols_between(f, t) > 0:
		f["col"] = int(f["col"]) + dir
		moved += 1
	if cols_between(f, t) == 0 and not melee.is_empty():
		lines.append("%s сближается с %s" % [f["name"], t["name"]])
		_creature_full(s, data, f, melee, t, lines)
		return
	if _reaches(data, f, t, ranged):
		_creature_full(s, data, f, ranged, t, lines)
		return
	while moved < steps * 2 and cols_between(f, t) > 0:
		f["col"] = int(f["col"]) + dir
		moved += 1
	if moved > 0:
		lines.append("%s бежит к %s" % [f["name"], t["name"]])


## The full attack of a creature at another (Multiattack of the same kind).
static func _creature_full(s: GameSession, data: Dictionary, f: Dictionary, act: Dictionary, t: Dictionary, lines: Array[String]) -> void:
	var m := _monster(data, f)
	var by_en := {}
	for a: Dictionary in m["actions"]:
		by_en[str(a["name_en"])] = a
	var kind := "melee" if str(act.get("kind")) == "melee" and cols_between(f, t) == 0 else "ranged"
	var plan: Array[Dictionary] = []
	for x: Dictionary in m.get("multiattack", []):
		var a: Dictionary = by_en.get(str(x["action"]), {})
		if not a.is_empty() and str(a.get("kind")) == kind and not (a.get("damage", []) as Array).is_empty():
			for i in int(x["count"]):
				plan.append(a)
	if plan.is_empty():
		plan.append(act)
	for a: Dictionary in plan:
		if str(t.get("status")) != "active":
			return
		_creature_attack(s, data, f, a, t, lines)


## One attack roll of a creature against another creature of the field, and its damage.
static func _creature_attack(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, t: Dictionary, lines: Array[String]) -> void:
	var d := cols_between(f, t)
	var ranged_use := d > 0
	if ranged_use and str(a.get("kind")) == "melee" and a.has("range"):  # a thrown weapon is out of the hand
		var gone: Array = f.get("thrown", [])
		gone.append(str(a.get("name_en", "")))
		f["thrown"] = gone
	f["hidden"] = false
	var adv := incapacitated(t) or (_has(t, "prone") and not ranged_use) or _has(t, "restrained") or _has(t, "blinded") or _has(f, "invisible")
	var dis := (ranged_use and a.has("range") and d * int(cfg(data)["col_ft"]) > int(a["range"][0])) or (str(a.get("kind")) == "ranged" and d == 0) \
		or ["poisoned", "blinded", "restrained", "frightened", "prone"].any(func(x: String) -> bool: return _has(f, x)) \
		or (ranged_use and _has(t, "prone")) or bool(t.get("dodging", false))
	var rolls := _d20(s.rng, adv, dis)
	var nat := _nat(rolls, adv, dis)
	var total := nat + int(a.get("to_hit", 0))
	var hit := nat == 20 or (nat != 1 and total >= int(t["ac"]))
	var mark := " (с преимуществом)" if adv and not dis else " (с помехой)" if dis and not adv else ""
	var line := "%s — %s по %s: %d + %d = %d против КД %d%s" % [f["name"], a["name"], t["name"], nat, int(a.get("to_hit", 0)), total, int(t["ac"]), mark]
	if not hit:
		lines.append(line + " — промах")
		fx(s, str(t["id"]), "dodge")
		return
	var crit := nat == 20 or (not ranged_use and (_has(t, "paralyzed") or _has(t, "unconscious")))
	var dmg := 0
	var dtype := ""
	var dtypes: Dictionary = data["misc"]["damage_types"]
	var types: Array[String] = []
	for dd: Dictionary in a["damage"]:
		dmg += _resist(data, t, str(dd["type"]), maxi(1, roll_dice(s.rng, str(dd["dice"]), crit)), false)
		if dtype.is_empty():
			dtype = str(dd["type"])
		types.append(str(dtypes.get(str(dd["type"]), dd["type"])))
	lines.append(line + (" — КРИТ! " if crit else " — попадание, ") + "%d (%s)" % [dmg, ", ".join(types)])
	if crit:
		fx(s, str(t["id"]), "crit")
	if str(t.get("side")) == "ally":
		_hurt_ally(s, t, dmg, lines)
	else:
		_hurt_enemy(s, data, t, dmg, lines, dtype, crit, false)


## Damage to an ally: 0 HP — a follower or a pack ally falls unconscious («down»), a summoned creature vanishes.
static func _hurt_ally(s: GameSession, t: Dictionary, dmg: int, lines: Array[String]) -> void:
	t["hp"] = maxi(0, int(t["hp"]) - dmg)
	if int(t["hp"]) > 0:
		return
	if str(t.get("ally", "")) == "summon":
		t["status"] = "gone"
		lines.append("%s развеивается" % t["name"])
	else:
		t["status"] = "down"
		lines.append("%s падает без сознания" % t["name"])


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
	if int(s.character["hp"]) <= 0 and bool(ds.get("stable", false)) and allies(s).is_empty():
		if enemies(s).any(func(id: String) -> bool: return _intelligent(data, fighter(s, id))):
			s.combat["outcome"] = "captured"
			lines.append("%s остаётся лежать — враги берут его живым" % s.character["name"])
		else:  # v0.7.9: beasts leave a still body
			s.combat["outcome"] = "left"
			lines.append("%s остаётся лежать — звери теряют к нему интерес и уходят" % s.character["name"])


## «Сдаться» (v0.7.22.17, #12): on the hero's turn, while a thinking foe still fights. "" or a key.
static func can_surrender(s: GameSession, data: Dictionary) -> String:
	if not is_player_turn(s):
		return "COMBAT_NOT_YOUR_TURN"
	if not enemies(s).any(func(id: String) -> bool: return _intelligent(data, fighter(s, id))):
		return "COMBAT_NO_SURRENDER"
	return ""


## The hero throws down the weapon: the fight ends at once — the captive of the foes (or held by the law). Lines.
static func surrender(s: GameSession) -> Array[String]:
	s.combat["outcome"] = "captured"
	s.combat["surrendered"] = true
	return ["%s бросает оружие и сдаётся" % s.character.get("name", "")]


## The captors are the law's guard: the hero is held, as at an arrest, not bound in their place.
static func law_captors(s: GameSession) -> bool:
	return enemies(s).any(func(id: String) -> bool: return bool(fighter(s, id).get("law", false)))


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
		if str(f["status"]) != "active" and not bool(f.get("no_xp", false)):
			xp += int(m["xp"])
		if str(f["status"]) == "dead" and CraftRules.hides(data, m) > 0:  # v0.7.24: the hide of a beast
			loot["raw_hide"] = int(loot.get("raw_hide", 0)) + CraftRules.hides(data, m)
		if str(f["status"]) == "dead" and CraftRules.meat(data, m) > 0:  # v0.7.25: meat for the fire
			loot["raw_meat"] = int(loot.get("raw_meat", 0)) + CraftRules.meat(data, m)
		if str(f["status"]) in ["dead", "surrendered", "unconscious"]:
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
			"surprised": bool(f.get("surprised", false)), "conditions": foe_conditions(data, f),
			"speaks": LanguageRules.foe_speech(data, f), "understands_hero": LanguageRules.foe_understands(s.character, data, f)})
	var incoming: Array[Dictionary] = []
	for w: Dictionary in s.combat.get("incoming", []):
		incoming.append({"names": w["names"], "side": "left" if int(w["col"]) < 0 else "right",
			"in_rounds": maxi(0, int(w["at"]) - int(s.combat.get("round", 1)))})
	var friends: Array[Dictionary] = []
	for id: String in allies(s, false):  # v0.7.22.22
		var a := fighter(s, id)
		friends.append({"id": id, "name": a["name"], "monster": _monster(data, a)["name"], "distance_ft": cols_between(a, p) * int(cfg(data)["col_ft"]),
			"status": a["status"], "health": health_key(a).trim_prefix("HEALTH_").to_lower() if str(a["status"]) == "active" else str(a["status"]),
			"source": str(a.get("ally", "pack")), "npc_id": str(a.get("npc_id", ""))})
	return {"round": int(s.combat.get("round", 1)), "enemies": foes, "allies": friends, "outcome": str(s.combat.get("outcome", "")),
		"player_down": int(s.character.get("hp", 1)) <= 0, "player_hidden": bool(p.get("hidden", false)),
		"incoming": incoming, "log": s.combat.get("log", [])}


# --- parley (v0.6.2) ------------------------------------------------------------------------------


## DC of a parley (v0.7.5): base + the best WIS save and per_cr × the highest CR among intelligent foes, + hard for a
## pack encounter marked so (finales, fanatics); easier for every foe out of the fight and every one below half HP.
static func parley_dc(s: GameSession, data: Dictionary) -> int:
	var p: Dictionary = cfg(data)["parley"]
	var wis := -5
	var cr := 0.0
	var bloodied := 0
	for id: String in enemies(s):
		var f := fighter(s, id)
		if int(f.get("hp", 1)) * 2 < int(f.get("max_hp", 1)):
			bloodied += 1
		if _intelligent(data, f):
			var m := _monster(data, f)
			wis = maxi(wis, int(m["saves"].get("wis", CharacterRules.mod(int(m["abilities"].get("wis", 10))))))
			cr = maxf(cr, float(m.get("cr", 0)))
	var out := enemies(s, false).size() - enemies(s).size()
	var dc := int(p["base_dc"]) + wis + int(p.get("per_cr", 0)) * int(floor(cr)) + int(p["per_defeated"]) * out + int(p.get("per_bloodied", 0)) * bloodied
	if bool(s.combat.get("parley_hard", false)):
		dc += int(p.get("hard", 0))
	return maxi(int(p["min_dc"]), dc)


static func is_parley_skill(data: Dictionary, skill: String) -> bool:
	return (cfg(data)["parley"]["skills"] as Array).has(skill)


## "" when a parley try can be made: intelligent foes are still fighting and they have not stopped listening.
static func can_parley(s: GameSession, data: Dictionary, skill: String) -> String:
	if not is_parley_skill(data, skill):
		return "COMBAT_NO_PARLEY"
	if not enemies(s).any(func(id: String) -> bool: return _intelligent(data, fighter(s, id))):
		return "COMBAT_NO_PARLEY"
	if skill == "persuasion" and not parley_understood(s, data):
		return "COMBAT_NO_LANGUAGE"  # v0.7.11: nobody understands the hero's words
	if int(s.combat.get("parley_fail", 0)) >= int(cfg(data)["parley"].get("failures", 2)):
		return "COMBAT_PARLEY_REFUSED"
	return ""


## Whether one of the intelligent foes still fighting understands the hero (a common tongue, telepathy, a spell).
static func parley_understood(s: GameSession, data: Dictionary) -> bool:
	return enemies(s).any(func(id: String) -> bool:
		return _intelligent(data, fighter(s, id)) and LanguageRules.foe_understands(s.character, data, fighter(s, id)))


## The parley so far for the button and the master: «успехов 1 из 3, провалов 0 из 2, Сл 17».
static func parley_progress(s: GameSession, data: Dictionary) -> String:
	var p: Dictionary = cfg(data)["parley"]
	return "успехов %d из %d, провалов %d из %d, Сл %d" % [int(s.combat.get("parley_ok", 0)), int(p.get("successes", 3)),
		int(s.combat.get("parley_fail", 0)), int(p.get("failures", 2)), parley_dc(s, data)]


## One try of the parley challenge (v0.7.5): `successes` before `failures` win; the skill of the deciding success sets
## the outcome — Intimidation: intelligent foes next to the player surrender, the rest flee; Persuasion: truce. Beasts
## fight on. Lines.
static func parley_apply(s: GameSession, data: Dictionary, skill: String, success: bool) -> Array[String]:
	var p: Dictionary = cfg(data)["parley"]
	(s.combat["parley_tried"] as Array).append(skill)
	var lines: Array[String] = []
	if not success:
		s.combat["parley_fail"] = int(s.combat.get("parley_fail", 0)) + 1
		if int(s.combat["parley_fail"]) >= int(p.get("failures", 2)):
			lines.append("Враги больше не станут слушать — только бой")
		else:
			lines.append("Враги не слушают (%s)" % parley_progress(s, data))
		return lines
	s.combat["parley_ok"] = int(s.combat.get("parley_ok", 0)) + 1
	if int(s.combat["parley_ok"]) < int(p.get("successes", 3)):
		lines.append("Враги колеблются (%s)" % parley_progress(s, data))
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
static func attack_preview(s: GameSession, data: Dictionary, target_id: String, offhand: bool = false, unarmed: bool = false) -> Dictionary:
	var c := s.character
	var t := fighter(s, target_id)
	if t.is_empty():
		return {}
	var w := weapon_profile(c, data, s.items, "" if unarmed else str(c.get("equipped", {}).get("off_hand" if offhand else "main_hand", "")), offhand)
	var mods := _attack_mods(s, data, w, t)
	var adv := not (mods["adv"] as Array).is_empty()
	var dis := not (mods["dis"] as Array).is_empty()
	var r := dice_range(str(w["dice"]))
	var bonus := int(w["bonus"]) + _rage_bonus(s, data, w, t)
	var sneak := _sneak_dice(s, data, w, adv, dis, t)
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
	var cspec: Dictionary = cfg(data)["condition_spells"].get(spell_id, {})
	if not cspec.is_empty():
		var conds := ", ".join((cspec["conditions"] as Array).map(func(x: String) -> String: return cond_name(data, x)))
		if cspec.has("pool"):
			var pr := dice_range(str(cspec["pool"]))
			return {"pool": true, "min": pr[0], "max": pr[1], "condition": conds, "chance": 100, "adv": [], "dis": []}
		var sab := str(sp["save"]["ability"])
		var tm := _monster(data, t)
		var sbonus := int(tm["saves"].get(sab, CharacterRules.mod(int(tm["abilities"].get(sab, 10)))))
		return {"save": true, "condition": conds, "chance": 100 - hit_chance(sbonus, int(s.character.get("spell_dc", 10)), false, false),
			"adv": [], "dis": [], "immune": not _can_be(data, t, cspec)}
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


# --- inspect a foe (v0.6.6) ----------------------------------------------------------------------


## The knowledge skill for a creature type (rules.combat.lore_skills): Nature for beasts, Religion for the undead…
static func lore_skill(data: Dictionary, f: Dictionary) -> String:
	var lore: Dictionary = cfg(data)["lore_skills"]
	return str(lore.get(str(_monster(data, f).get("type", "")), lore["_default"]))


## DC to know a creature: 10 + its challenge (rounded up).
static func lore_dc(data: Dictionary, f: Dictionary) -> int:
	return int(cfg(data)["lore_base_dc"]) + int(ceil(float(_monster(data, f).get("cr", 0))))


static func known(s: GameSession, f: Dictionary) -> bool:
	return s.known_monsters.has(str(f.get("monster", ""))) or str(f.get("side")) == "ally"  # one's own side is known


## "" when the player can inspect `target_id` now: a bonus action on an active foe of an unknown kind.
static func can_inspect(s: GameSession, data: Dictionary, target_id: String) -> String:
	if not player_can_act(s):
		return "COMBAT_NOT_YOUR_TURN"
	if int(economy(s).get("bonus", 0)) <= 0:
		return "COMBAT_NO_BONUS"
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active" or str(t.get("side")) != "enemy":
		return "COMBAT_BAD_TARGET"
	if known(s, t):
		return "COMBAT_ALREADY_KNOWN"
	return ""


## Inspect a foe (can_inspect first): the knowledge check; success — the kind is known for good. Lines.
static func player_inspect(s: GameSession, data: Dictionary, target_id: String) -> Array[String]:
	var e := economy(s)
	e["bonus"] = int(e["bonus"]) - 1
	var t := fighter(s, target_id)
	var skill := lore_skill(data, t)
	var dc := lore_dc(data, t)
	var favored := FeatureRules.has(s.character, "favored_enemy_" + str(_monster(data, t).get("type", "")))  # Favored Enemy (v0.7.10)
	var roll := _nat(FeatureRules.hero_d20(s, favored, false), favored, false)
	var total := roll + int(s.character.get("skills", {}).get(skill, 0)) + DifficultyRules.bonus(s, data)  # v0.7.20.4
	var ok := roll != 1 and (roll == 20 or total >= dc)
	if ok:
		s.known_monsters.append(str(t["monster"]))
	return ["%s присматривается: %s — %s %d против Сл %d — %s" % [s.character["name"], t["name"], TranslationServer.translate("SKILL_" + skill.to_upper()),
		total, dc, "теперь ясно, на что способны такие враги" if ok else "ничего толкового"]]


## The card of a known kind: HP (this one's), AC, speed, attacks, resistances. "" for an unknown one.
static func monster_card(s: GameSession, data: Dictionary, f: Dictionary) -> String:
	if not known(s, f):
		return ""
	var m := _monster(data, f)
	var dtypes: Dictionary = data["misc"]["damage_types"]
	var lines: Array[String] = ["%s · HP %d/%d · КД %d · скорость %d фт" % [m["name"], int(f["hp"]), int(f["max_hp"]), int(m["ac"]), int(m.get("speed", 30))]]
	for a: Dictionary in m["actions"]:
		var dmg: Array[String] = []
		for d: Dictionary in a.get("damage", []):
			dmg.append("%s %s" % [str(d["dice"]).replace("d", "к"), dtypes.get(str(d["type"]), d["type"])])
		var fx := MonsterRules.effect_text(data, a)  # v0.7.9: what it does besides the damage
		if a.has("save"):
			lines.append("%s: спасбросок %s Сл %d%s%s" % [a["name"], ab_name(str(a["save"]["ability"])), int(a["save"]["dc"]),
				(", " + ", ".join(dmg)) if not dmg.is_empty() else "", ("; " + fx) if not fx.is_empty() else ""])
		else:
			lines.append("%s: %+d%s%s" % [a["name"], int(a.get("to_hit", 0)), (", " + ", ".join(dmg)) if not dmg.is_empty() else "",
				("; " + fx) if not fx.is_empty() else ""])
	var sc: Dictionary = m.get("spellcasting", {})
	if not sc.is_empty():
		var names: Array = []
		for x: Dictionary in sc["spells"]:
			if data["spells"].has(str(x["id"])):
				names.append(str(data["spells"][str(x["id"])]["name"]) + (" (%d/день)" % int(x["per_day"]) if x.has("per_day") else ""))
		lines.append("Заклинания (Сл %d): %s" % [int(sc.get("dc", 10)), ", ".join(names)])
		var full: Dictionary = sc.get("slots", {})
		if not full.is_empty():  # what is left of its slots (big test #21, v0.7.22.4)
			var left: Dictionary = f.get("slots", full)
			lines.append("Ячейки: " + " · ".join(full.keys().map(func(k: Variant) -> String: return "%s круг %d/%d" % [k, int(left.get(k, 0)), int(full[k])])))
	for r: Dictionary in m.get("reactions", []):
		if r.has("ac"):
			lines.append("Реакция: парирование (+%d КД против удара вплотную)" % int(r["ac"]))
	for key: String in ["resistances", "immunities", "vulnerabilities", "condition_immunities"]:
		var list: Array = m.get(key, [])
		if not list.is_empty():
			lines.append("%s: %s" % [{"resistances": "Сопротивление", "immunities": "Иммунитет", "vulnerabilities": "Уязвимость",
				"condition_immunities": "Не бывает"}[key], ", ".join(list.map(func(x: Variant) -> String:
					return ConditionRules.name_of(data, str(x)).to_lower() if key == "condition_immunities" else str(dtypes.get(str(x), x))))])
	for tr_: Dictionary in m.get("traits", []):
		lines.append("%s: %s" % [tr_["name"], str(tr_.get("desc", "")).left(160)])
	return "\n".join(lines)

