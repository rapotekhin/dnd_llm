class_name CombatRules
extends RefCounted
## Combat (roadmap v0.6.1, ADR-0010 §7): the engine runs the fight, the master narrates each round.
## - v0.8.4: the field is the map of the place on squares of 5 ft (FightGrid). Everyone stands where the fight found
##   them and takes the squares of its size. Melee — side by side, a reach of 10 ft — two squares; ranges in feet by
##   the lines between squares (beyond the normal range — disadvantage); shooting with a foe beside you — disadvantage;
##   leaving a foe's reach without Disengage — an attack of opportunity; an area covers the squares of its SRD shape.
## - Initiative order; on the player's turn: action + bonus action + speed in squares, split as the player likes (Dash —
##   as much again); attacks (Extra Attack, off-hand with a light weapon), engine spells (attack roll or save, damage,
##   healing), Dodge, Disengage, Dash, features and items through Stock / ItemRules.
## - Enemies are SRD monsters whose turn is found by a search over squares and acts (FightAI), morale at half HP —
##   intelligent foes surrender, the rest flee off the map.
## - 0 HP of the player in combat: death saves by 5e. The end: victory, the player fled, captured (stable among
##   intelligent foes), dead, truce (persuasion). XP by CR of everyone defeated, loot — their gear and the
##   encounter's loot.
## - v0.6.2: surprise (the player sneaks in — Stealth against each foe's passive Perception; a pack ambush — the
##   foes' Stealth against the player's), Hide in combat (not with a foe in your column; hidden — advantage, foes
##   attack with disadvantage; an attack or a spell reveals), reinforcements (pack waves, a foe calls for help,
##   the master's start_combat — all come by a way into the place at the start of a round), parley (Intimidation —
##   intelligent foes surrender or flee, Persuasion — truce; one try per skill), the hit hint before the click.
## - v0.7.8: the hero's conditions by 5e — prone (attacks with disadvantage, close foes with advantage, far ones with
##   disadvantage, «Встать» takes the move), grappled and restrained (speed 0, «Вырваться» — an action), blinded,
##   frightened (no step towards the source), charmed (no attack on the charmer), paralysed / stunned / unconscious /
##   petrified (the turn is skipped, foes hit with advantage, close hits on the paralysed and the unconscious are
##   critical), exhaustion; repeat saves at the end of the hero's turn; resistances and the concentration save on
##   damage (HeroDefense); invisible foes are where they were last seen until they strike (`seen_x`, `seen_y`).
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


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["combat"]


static func active(s: GameSession) -> bool:
	return not s.combat.is_empty()


static func fighter(s: GameSession, id: String) -> Dictionary:
	return s.beings.get(id, {}).get("fight", {})


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
	for id: String in s.combat.get("fighters", []):
		var f := fighter(s, id)
		if f.get("side") == "ally" and (not only_active or str(f.get("status")) == "active"):
			out.append(id)
	return out


static func current(s: GameSession) -> String:
	var order: Array = s.combat.get("order", [])
	return str(order[int(s.combat.get("turn", 0))]) if not order.is_empty() else ""


static func is_player_turn(s: GameSession) -> bool:
	return active(s) and current(s) == PLAYER and str(s.combat.get("outcome", "")).is_empty()


## In the air and out of a blade's reach: one that flies and did not come down to strike.
static func airborne(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	var me := Sheet.holder(s, f)
	return Move.air(s, data, f) and not bool(f.get("swooped", false)) and not incapacitated(me) \
		and not ["prone", "grappled", "restrained"].any(func(x: String) -> bool: return ConditionRules.has(me, x))


## `a` reaches `t` with a blade of `reach` squares: beside it, not over a corner, a flyer only by another flyer.
static func blade_reaches(s: GameSession, data: Dictionary, a: Dictionary, t: Dictionary, reach: int = 1) -> bool:
	return FightGrid.can_touch(s, data, a, t, reach) and (not airborne(s, data, t) or airborne(s, data, a))


## The cover of `t` from `a`, for an attack or a Dexterity save; 0 beside it.
static func cover_of(s: GameSession, data: Dictionary, a: Dictionary, t: Dictionary) -> int:
	return FightGrid.cover(s, data, a, t)


## No aim at `t`: full cover. What is not seen can still be struck, by 5e with disadvantage (sight_mods).
static func _no_line(s: GameSession, data: Dictionary, a: Dictionary, t: Dictionary) -> bool:
	return FightGrid.cover(s, data, a, t) >= FightGrid.FULL_COVER


## A spell that asks for «a creature you can see» at one the caster does not see: blind, a Fog Cloud, invisible. A bolt goes by guess.
static func _blind_aim(s: GameSession, data: Dictionary, spell_id: String, t: Dictionary, me: Dictionary = {}) -> bool:
	var sp: Dictionary = data["spells"][spell_id]
	var a := player(s) if me.is_empty() else me
	if sp.has("area") and _unseen_by(s, a, t):
		return true  # an area goes on a square, not after its name
	return bool(sp.get("needs_sight", false)) and (not FightGrid.veiled(s, data, a, t).is_empty() or _unseen_by(s, a, t))


## Blows by sight, 5e: not seeing `t` is a disadvantage, not being seen by it an advantage, and in a Fog Cloud both cancel out.
## A blinded `t` gives its advantage by its condition. {"adv", "dis"} — reasons or "".
static func sight_mods(s: GameSession, data: Dictionary, a: Dictionary, t: Dictionary) -> Dictionary:
	return {"adv": ("" if FightGrid.blind(s, t) else FightGrid.veiled(s, data, t, a)).to_lower(), "dis": FightGrid.veiled(s, data, a, t).to_lower()}


## It sees nothing here (one road, v0.8.4.12): an unlit place, no darkvision, no light of its own and none carried on the
## field (the hero's lights it for everybody).
static func dark_for(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return TimeRules.dark(s, data, f)


## A shot beyond what it sees by in an unlit place (v0.8.4.1): past its darkvision or its light, at a target that carries
## no light of its own (a torch is a mark).
static func shot_in_dark(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary) -> bool:
	if not TimeRules.unlit(s, data) or SightRules.lit(s, data, t):
		return false
	return FightGrid.dist(f, t) > SightRules.reach(s, data, f)


static func _spell_squares(s: GameSession, data: Dictionary, spell_id: String, f: Dictionary = Sheet.HERO) -> int:
	return maxi(1, FightGrid.squares_of(data, spell_range(s, data, spell_id, f)))


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
	return dice_range(expr, mod)[1]


## A heal of an item or a resource as an array [dice, sides, plus or "level"] → a dice expression for `roll_dice`.
static func dice_of(h: Array, level: int = 1) -> String:
	var plus := level if str(h[2]) == "level" else int(h[2])
	return "%dd%d%s" % [int(h[0]), int(h[1]), ("+%d" % plus) if plus > 0 else ("%d" % plus) if plus < 0 else ""]


## The mean of a dice expression (the AI's worth, the arena's estimate).
static func dice_avg(expr: String, mod: int = 0) -> float:
	var r := dice_range(expr, mod)
	return (r[0] + r[1]) / 2.0


## "2d6+3" (or "1d8+MOD" with `mod`) → total; a critical doubles the dice; a die of `reroll` or less is rolled once more (Great
## Weapon Fighting: 2).
static func roll_dice(rng: RandomNumberGenerator, expr: String, crit: bool = false, mod: int = 0, reroll: int = 0) -> int:
	if expr.begins_with("E"):  # Empowered Spell "E<k>:<dice>": up to k dice below their middle rolled again (5e, v0.8.4.33)
		return _empowered_roll(rng, expr.substr(1).get_slice(":", 1) if expr.contains(":") else expr.substr(1),
			int(expr.substr(1).get_slice(":", 0)) if expr.contains(":") else 1, crit, mod, reroll)
	var e := expr.replace(" ", "").replace("MOD", str(mod))
	var total := 0
	var parts := e.replace("-", "+-").split("+", false)
	for p: String in parts:
		if p.contains("d"):
			var n := int(p.get_slice("d", 0)) if not p.get_slice("d", 0).is_empty() else 1
			var sides := int(p.get_slice("d", 1))
			for i in n * (2 if crit else 1):
				var r := rng.randi_range(1, sides)
				total += rng.randi_range(1, sides) if r <= reroll else r
		else:
			total += int(p)
	return total


static func _empowered_roll(rng: RandomNumberGenerator, expr: String, k: int, crit: bool, mod: int, reroll: int) -> int:
	var e := expr.replace(" ", "").replace("MOD", str(mod))
	var total := 0
	var dice: Array[Vector2i] = []  # (value, sides)
	for p: String in e.replace("-", "+-").split("+", false):
		if p.contains("d"):
			var n := int(p.get_slice("d", 0)) if not p.get_slice("d", 0).is_empty() else 1
			var sides := int(p.get_slice("d", 1))
			for i in n * (2 if crit else 1):
				var r := rng.randi_range(1, sides)
				dice.append(Vector2i(rng.randi_range(1, sides) if r <= reroll else r, sides))
		else:
			total += int(p)
	dice.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 2 - a.y < b.x * 2 - b.y)  # the worst against its die first
	for i in dice.size():
		if i < k and dice[i].x * 2 < dice[i].y + 1:
			dice[i].x = rng.randi_range(1, dice[i].y)
		total += dice[i].x
	return total


# --- setup ----------------------------------------------------------------------------------------


## Starts a fight. `foes` = [{monster, count?, name?, desc?, col?, npc_id?}]; `source` = {encounter, room_from}.
## Returns the chat lines (who is here, the initiative order).
## `source` may add (v0.6.2): sneak (the player sneaks in), ambush (the foes lie in wait), waves [{round, side,
## enemies}] and help {enemies, side, delay} of a pack encounter.
static func start(s: GameSession, data: Dictionary, foes: Array, source: Dictionary = {}) -> Array[String]:
	var c := s.character
	var fighters: Array = [PLAYER]
	Being.of(s, PLAYER)["fight"] = {"id": PLAYER, "side": "player", "name": str(c.get("name", "")), "status": "active",
		"init": 0, "conditions": [], "span": FightGrid.span_of(data, hero_size(s, data))}
	s.combat = {"round": 1, "turn": 0, "fighters": fighters, "order": [], "log": [], "encounter": str(source.get("encounter", "")),
		"room_from": str(source.get("room_from", "")), "outcome": "", "death_saves": {"ok": 0, "fail": 0}, "xp": 0,
		"incoming": [], "help": (source.get("help", {}) as Dictionary).duplicate(true), "parley_tried": [],
		"parley_ok": 0, "parley_fail": 0, "parley_hard": str(source.get("parley", "")) == "hard",
		"map": str(s.room_id), "room_start": str(s.room_id), "rev": 0, "zones": [], "doors": {}, "blocks": {}, "fires": {},
		"faction": str(source.get("faction", ""))}
	if source.has("field"):
		s.combat["field"] = (source["field"] as Dictionary).duplicate()
	if source.get("arena") is Dictionary:  # v0.7.45: a bout one to one by the arena's rule
		s.combat["arena"] = (source["arena"] as Dictionary).duplicate(true)
	var ring := ArenaRules.ring(s, data)  # v0.8.4.5: its sides and its crowd
	s.combat["crowd"] = ring.get("crowd", [])
	FightGrid.put(player(s), FightGrid.free_near(s, data, ring["hero"]) if ring.has("hero") else _hero_square(s, data))
	FightField.auras(s, data, player(s))  # what the hero wears lays around it (v0.8.4.35), as a monster's traits do
	var key := str(source.get("encounter", ""))
	if (not key.is_empty() or bool(source.get("on_map", false))) and not s.combat.has("field") and not s.combat.has("arena"):
		foes = MapSpots.on_lair(s, data, key, foes)  # the foes seen on the map keep their squares (v0.8.4.24)
	var own := FactionRules.own_heads(s, data, foes, str(source.get("encounter", "")))  # v0.7.63: the hero's look, a side of their own
	foes = foes.filter(func(f: Dictionary) -> bool: return not own.has(f))
	_add_foes(s, data, _on_square(foes, ring.get("foe", FightGrid.NONE)))
	if ArenaRules.watching(s):
		_add_foes(s, data, _on_square(source.get("allies", []), ring.get("ally", FightGrid.NONE)), FightGrid.NONE, "ally")
	elif not s.combat.has("arena"):
		_add_foes(s, data, own + AllyRules.joining(s, data, foes) + (source.get("allies", []) as Array) + AllyRules.summon_specs(s), FightGrid.NONE, "ally")
		AllyRules.buffs_into_fight(s, data)
	for w: Dictionary in source.get("waves", []):
		add_incoming(s, data, w.get("enemies", []), int(w.get("round", 2)), str(w.get("side", "right")))
	FightField.lay(s, data)
	# Initiative: a DEX check of anybody (initiative_of); ties — the higher DEX, then the player.
	var inits := []
	for id: String in fighters:
		var dex := _dex_of(s, data, id)
		var roll := initiative_of(s, data, id)
		fighter(s, id)["init"] = roll
		inits.append([roll, dex, 1 if id == PLAYER else 0, id])
	inits.sort_custom(func(a: Array, b: Array) -> bool: return a.slice(0, 3) > b.slice(0, 3))
	s.combat["order"] = inits.map(func(x: Array) -> String: return str(x[3]))
	if ArenaRules.watching(s):
		(s.combat["order"] as Array).erase(PLAYER)
	var names: Array = (s.combat["order"] as Array).map(func(id: String) -> String: return "%s %d" % [fighter(s, id)["name"], fighter(s, id)["init"]])
	var lines: Array[String] = ["Бой! Инициатива: " + ", ".join(names)]
	lines.append_array(_surprise(s, data, source))
	lines.append_array(_opening(s, source))
	_begin_turn(s, data, lines)
	return lines


static func _on_square(specs: Array, at: Vector2i) -> Array:
	if at == FightGrid.NONE:
		return specs
	return specs.map(func(spec: Dictionary) -> Dictionary:
		var out := spec.duplicate()
		out["x"] = at.x
		out["y"] = at.y
		return out)


## The fight began with the hero's own attack on an NPC (v0.7.7, as in BG3): the hero acts first and that NPC is
## caught off guard. `source.opening` {npc_id, unaware}; the strike itself is resolved by the caller. v0.7.22.16:
## `unaware` false — the NPC expected it (hostile, wary): the hero still acts first, but nobody is caught off guard.
static func _opening(s: GameSession, source: Dictionary) -> Array[String]:
	var npc := str(source.get("opening", {}).get("npc_id", ""))
	if npc.is_empty():
		return []
	for id: String in enemies(s):
		var f := fighter(s, id)
		if str(f.get("npc_id", "")) == npc or id == npc:  # a person, or a foe's own record (v0.8.4.30)
			var order: Array = s.combat["order"]
			order.erase(PLAYER)
			order.push_front(PLAYER)
			if not bool(source.get("opening", {}).get("unaware", true)):
				return ["%s нападает первой очередью — %s ждал(а) этого" % [s.character.get("name", ""), f["name"]]]
			f["surprised"] = true
			return ["Удар без предупреждения: %s ходит первой очередью, %s не ждёт нападения" % [s.character.get("name", ""), f["name"]]]
	return []


## The fighter of an NPC of the scene or of a foe's record (v0.8.4.30), "" if not in the fight.
static func fighter_of_npc(s: GameSession, npc_id: String) -> String:
	for id: String in enemies(s):
		if str(fighter(s, id).get("npc_id", "")) == npc_id or id == npc_id:
			return id
	return ""


static func _dex_of(s: GameSession, data: Dictionary, id: String) -> int:
	return Sheet.ability_mod(s, data, fighter(s, id), "dex")


## Where the hero stands: the walk's square, or the middle of an open field.
static func _hero_square(s: GameSession, data: Dictionary) -> Vector2i:
	if s.combat.has("field"):
		return Vector2i(int(s.combat["field"]["w"]) / 2, int(s.combat["field"]["h"]) / 2)
	return FightGrid.free_near(s, data, WalkRules.settle(s, data, FightGrid.map(s, data)))


## Where a fighter of `spec` appears: its own square, its person's square on the map, by the hero for an ally, else at
## the starting distance on a free square around the hero.
static func _square_of(s: GameSession, data: Dictionary, spec: Dictionary, f: Dictionary, ranged: bool, turn: int, ally: bool) -> Vector2i:
	var span := int(f["span"])
	if spec.has("x"):
		return FightGrid.free_near(s, data, Vector2i(int(spec["x"]), int(spec["y"])), span)
	var hero := FightGrid.cell(player(s))
	if ally:
		return FightGrid.free_near(s, data, hero, span)
	var spot := MapSpots.of_fighter(s, data, spec)
	if spot != FightGrid.NONE:
		return FightGrid.free_near(s, data, spot, span)
	if bool(spec.get("beside", false)):
		return FightGrid.free_near(s, data, hero, span)
	var far := int(FightGrid.cfg(data)["start"]["ranged" if ranged else "melee"])
	var d: Vector2i = FightGrid.CIRCLE[turn % FightGrid.CIRCLE.size()]
	return FightGrid.walked_off(s, data, hero, d, far, span, "" if s.combat.has("field") else str(s.room_id))


## Adds fighters for `specs` [{monster, count?, name?, desc?, x?, y?, npc_id?}]; `at` puts them all by one square
## (reinforcements by a way in). A name that is already in the fight gets the next number. Returns the ids.
static func _add_foes(s: GameSession, data: Dictionary, specs: Array, at: Vector2i = FightGrid.NONE, side_name: String = "enemy") -> Array[String]:
	var mons: Dictionary = data["monsters"]
	var fighters: Array = s.combat["fighters"]
	var ids: Array[String] = []
	var turn := 0
	for spec: Dictionary in specs:
		var m: Dictionary = mons.get(str(spec.get("monster", "")), {})
		if m.is_empty():
			continue
		var whose := str(spec.get("id", spec.get("npc_id", "")))  # a character of the game fights as itself (v0.7.62)
		var count := 1 if not whose.is_empty() else int(spec.get("count", 1))
		var base := str(spec.get("base", spec.get("name", m["name"])))
		var same := fighters.filter(func(id: String) -> bool: return str(fighter(s, id).get("base", "")) == base).size()
		for i in count:
			var ranged := (m["actions"] as Array).all(func(a: Dictionary) -> bool: return str(a.get("kind")) == "ranged")
			var name := str(spec.get("name", base))
			if not spec.has("base") and (count > 1 or same > 0):
				name += " %d" % (same + i + 1)
			var id := whose if not whose.is_empty() else str(Being.spawn(s, {"monster": str(spec["monster"]), "name": name, "base": base})["id"])
			var f := {"id": id, "side": side_name, "monster": str(spec["monster"]), "name": name, "base": base,
				"desc": str(spec.get("desc", "")), "hp": int(m["hp"]), "max_hp": int(m["hp"]), "ac": int(m["ac"]),
				"span": FightGrid.span_of(data, str(m.get("size", "medium"))), "status": "active", "conditions": [], "morale": false,
				"npc_id": str(spec.get("npc_id", "")), "by_hero": bool(spec.get("by_hero", false))}
			FightGrid.put(f, FightGrid.free_near(s, data, at, int(f["span"])) if at != FightGrid.NONE else _square_of(s, data, spec, f, ranged, turn, side_name == "ally"))
			turn += 1
			FeatureRules.give_class(data, f, spec)
			GrowthRules.apply(s, data, f)  # a person grown beside the hero (v0.8.4.11)
			Being.of(s, id)["fight"] = f
			fighters.append(id)
			_take_statuses(s, id, f)
			if spec.has("hp"):  # a creature of the room fought again keeps its wounds (v0.7.22.16, #21)
				f["hp"] = clampi(int(spec["hp"]), 1, int(f["max_hp"]))
			elif Being.view(s, id).has("hp"):  # the wounds of the last fight
				f["hp"] = clampi(int(Being.view(s, id)["hp"]), 1, int(f["max_hp"]))
			if spec.has("max_hp"):  # a fighter of the arena, made even with the other side (v0.8.4.5)
				f["max_hp"] = int(spec["max_hp"])
				f["hp"] = f["max_hp"]
			if bool(spec.get("no_xp", false)):  # its XP was given for the fight that beat it
				f["no_xp"] = true
			if bool(spec.get("law", false)):  # the law's guard: its captive is held, not bound (v0.7.22.17)
				f["law"] = true
			for k: String in ["ally", "summon_id", "spell", "creature_id", "called_by"]:  # v0.7.22.22: whose ally and from where
				if spec.has(k):
					f[k] = str(spec[k])
			if bool(spec.get("helper", false)):
				f["helper"] = true
			Sheet.refresh_max(s, data, f)  # v0.8.4.29.2: exhaustion 4, Aid, a drain — counted on it as on the hero
			Gear.arm(s, data, f, spec)  # what it has: its blows and its AC (v0.8.4.10)
			FightField.auras(s, data, f)  # what its traits lay around it (v0.8.4.27.1)
			ids.append(id)
	return ids


## A character fights with the statuses of its record: they are the fight's until it ends (v0.7.63).
static func _take_statuses(s: GameSession, id: String, f: Dictionary) -> void:
	var b := Being.view(s, id)
	for k: String in ["effects", "conditions", "next_effect"] + Rest.KEPT:
		if b.has(k):
			f[k] = b[k]
			b.erase(k)


## The statuses with an end in time or at a rest outlive the fight on the record; those of the moment do not.
static func _give_statuses(b: Dictionary, f: Dictionary) -> void:
	for k: String in Rest.KEPT:  # spent uses and exhaustion wait for its rest (v0.8.4.11)
		if f.has(k) and not (f[k] is Dictionary and (f[k] as Dictionary).is_empty()) and not (f[k] is int and int(f[k]) == 0):
			b[k] = f[k]
	var kept: Array = (f.get("effects", []) as Array).filter(func(e: Dictionary) -> bool: return not (e.get("ends", {}) as Dictionary).is_empty() or bool(e.get("keeps", false)))
	if kept.is_empty():
		return
	b["effects"] = kept
	b["next_effect"] = int(f.get("next_effect", 1))
	ConditionRules._sync(b)


## The fight is over (v0.7.62): the fighters are their records again. What stays in the world: people, the creatures of
## the rooms, the summoned, the heads of an encounter still standing and the captors, with their wounds and statuses.
## Those a fight made and did not keep are gone.
static func close(s: GameSession) -> void:
	var captors: Array = s.captive.get("foes", [])
	for id: String in s.combat.get("fighters", []):
		var b := Being.view(s, id)
		var f: Dictionary = b.get("fight", {})
		b.erase("fight")
		b.erase("was")
		ConditionRules.turn_comes(Sheet.holder(s, f if id != PLAYER else Sheet.HERO), "")  # what lasts until a turn is the fight's
		if id != PLAYER:
			_give_statuses(b, f)
		if b.has("creature") or b.has("summon") or (id != PLAYER and not str(f.get("npc_id", "")).is_empty()):
			if not str(f.get("npc_id", "")).is_empty():
				Gear.back(b, f)
			if b.is_empty():
				Being.forget(s, id)
		elif str(f.get("status")) == "active" and (b.has("encounter") or captors.has(id)):
			b["hp"] = int(f["hp"])
			Gear.back(b, f)
			if bool(f.get("no_xp", false)):
				b["no_xp"] = true
		elif id != PLAYER:
			Being.forget(s, id)
	s.combat = {}


# --- surprise and stealth (v0.6.2) -------------------------------------------------------------------


## A Stealth roll of anybody (Roll.check: armour, statuses, the dark, things). {total, nat, note}.
static func stealth_roll(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> Dictionary:
	var r := Roll.check(s, data, who, {"what": TranslationServer.translate("SKILL_STEALTH"), "skill": "stealth"})
	var adv: Array = r["adv"]
	var dis: Array = r["dis"]
	var note := ""
	if not dis.is_empty() and adv.is_empty():
		note = " (с помехой: %s)" % ", ".join(dis)
	elif not adv.is_empty() and dis.is_empty():
		note = " (с преимуществом: %s)" % ", ".join(adv)
	return {"total": int(r["total"]), "nat": int(r["nat"]), "note": note}


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
			if bool(WatchRules.against(s, data, [f], Sheet.HERO, int(roll["total"]))["ok"]):
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
		var passive := Sheet.passive(s, data, Sheet.HERO)
		var all_hidden: bool = source.get("hidden", true)
		if not source.has("hidden"):
			for id: String in foes:
				var f := fighter(s, id)
				if not bool(WatchRules.against(s, data, [Sheet.HERO], f, int(stealth_roll(s, data, f)["total"]))["ok"]):
					all_hidden = false
		if all_hidden:  # v0.8.4.29.1: the hero's whole side is caught, its companions too
			for id: String in friends_of(s, player(s)):
				fighter(s, id)["surprised"] = true
			s.combat["hero_surprised"] = true
			lines.append("Засада! Враги подкрались незаметно — %s%s пропускает первый ход" % [who, " и спутники" if not allies(s).is_empty() else ""])
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


## One of the hero's party the player moves in its turn as the hero (v0.8.4.43.11, as in BG3): a follower, its own beast, a
## creature it called — never an ally of the encounter nor the militia, never from the arena's fence. Only in the game's own
## fight (`drive`, GameState.start_combat): a test's or a balance run's fight keeps the AI.
static func driven(s: GameSession, f: Dictionary) -> bool:
	return bool(s.combat.get("drive", false)) and not Sheet.is_hero(f) and AllyRules.of_party(s, f) and not ArenaRules.watching(s)


## The fighter whose turn the player plays now: the hero, or one of its party it moves; {} — nobody's buttons now.
static func actor(s: GameSession) -> Dictionary:
	if player_can_act(s):
		return player(s)
	var f := fighter(s, current(s))
	return f if not f.is_empty() and driven(s, f) and can_act(s, f) else {}


## The start of anybody's turn, one road (v0.8.4.13): its points and reaction come back, what lasted until now goes, what
## it stands in or burns with strikes, a spell's after-effects and recharges. What it then does is its own: the player's
## buttons, the AI.
static func _begin_turn(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var id := current(s)
	var f := fighter(s, id)
	var me := Sheet.holder(s, f)
	var name := str(me.get("name", ""))
	f["dodging"] = false
	f["disengaged"] = false
	f["reacted"] = false  # the reaction comes back at the start of one's own turn (5e)
	f.erase("swooped")
	if not Sheet.is_hero(f):  # a status run out (Aid, a drain till a rest) takes its hit points back; the hero's sheet does it itself
		Sheet.refresh_max(s, data, f)
	f["points"] = fresh_points(s, data, f)
	for o: String in s.combat["order"]:  # Shield, Help and a spell's riders last until the start of `ends.turn`'s turn
		var h := Sheet.holder(s, fighter(s, o))
		if ConditionRules.turn_comes(h, id) and Sheet.is_hero(fighter(s, o)):
			CharacterRules.refresh(h, data, s.items)
	if str(f.get("status")) != "active":
		return
	FightField.auras(s, data, f)  # a thing put on or taken off since (v0.8.4.35)
	ItemRules.regenerate(s, data, f, lines)
	MonsterRules.start_turn(s, data, f, lines)  # recharges, once-a-turn extras, Reckless Attack lasts until now
	lines.append_array(SpellEffects.turn_start(s, data, f))  # Heroism (v0.7.13.1)
	_fire(s, data, f, lines)
	if bool(f.get("blinked", false)):  # Blink: back from the Ethereal Plane (v0.7.13.3)
		f["blinked"] = false
		lines.append("%s возвращается из эфира" % name)
	if bool(me.get("lethargy", false)):  # Haste is over: a turn of lethargy
		me.erase("lethargy")
		f["points"].merge({"action": 0, "bonus": 0, "move": 0, "haste": 0}, true)
		lines.append("%s вялый после Ускорения — ход без действий и движения" % name)
	var dropped := str(me.get("dropped", ""))
	if not dropped.is_empty() and not ConditionRules.incapacitated(me):  # Command «Брось!» (v0.7.22.4): picked up for nothing
		me.erase("dropped")
		var hands: Dictionary = me.get("equipped", {})
		if str(hands.get("main_hand", "")).is_empty() and int(me.get("inventory", {}).get(dropped, 0)) > 0:
			hands["main_hand"] = dropped
			CharacterRules.refresh(me, data, s.items)
			lines.append("%s поднимает %s" % [name, ItemRules.display_name(data["items"], s.items, dropped)])
	lines.append_array(SpellEffects.zone_tick(s, data, f, "start"))  # Moonbeam, Spirit Guardians (v0.7.13.5)
	Move.recount(s, data, f)  # a web that holds at the start of the turn
	if ConditionRules.has(me, "slowed_spell"):
		f["reacted"] = true  # Slow: no reactions
	if bool(f.get("retching", false)):  # Stinking Cloud (v0.7.13.6)
		f.erase("retching")
		f["points"].merge({"action": 0, "haste": 0}, true)
		lines.append("%s давится и теряет действие" % name)


# --- the player's actions ---------------------------------------------------------------------------


static func economy(s: GameSession) -> Dictionary:
	return player(s).get("points", {})


## What a turn gives any fighter: an action, a bonus action, its squares.
static func fresh_points(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	return {"action": 1, "bonus": 1, "move": Move.steps(s, data, f), "attacks": 0, "attacked": false, "sneak": false,
		"haste": 1 if SpellEffects.has(Sheet.holder(s, f), "haste") else 0}


## The points of `f` this turn.
static func points(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	if not f.has("points"):
		f["points"] = fresh_points(s, data, f)
	return f["points"]


## It is its turn and it can do something: awake, on the field, not caught by surprise.
static func can_act(s: GameSession, f: Dictionary) -> bool:
	if not active(s) or current(s) != str(f.get("id")) or not str(s.combat.get("outcome", "")).is_empty() or bool(f.get("surprised", false)):
		return false
	var me := Sheet.holder(s, f)
	return int(me.get("hp", 0)) > 0 and not ConditionRules.incapacitated(me) and (Sheet.is_hero(f) or str(f.get("status")) == "active")


## A key when `f` has not got the points, else "".
static func short_of(f: Dictionary, cost: String, n: int) -> String:
	var e: Dictionary = f.get("points", {})
	match cost:
		"action":
			return "COMBAT_NO_ACTION" if int(e.get("action", 0)) < n and int(e.get("haste", 0)) < n else ""
		"attack":
			return "COMBAT_NO_ACTION" if int(e.get("attacks", 0)) <= 0 and int(e.get("action", 0)) <= 0 and int(e.get("haste", 0)) <= 0 else ""
		"bonus":
			return "COMBAT_NO_BONUS" if int(e.get("bonus", 0)) < n else ""
		"move":
			return "COMBAT_NO_MOVE" if int(e.get("move", 0)) < n else ""
	return ""


## Takes the points; the action goes before Haste's.
static func pay(f: Dictionary, cost: String, n: int = 1) -> void:
	var e: Dictionary = f["points"]
	if cost == "action" and int(e.get("action", 0)) < n:
		cost = "haste"
	if e.has(cost):
		e[cost] = maxi(0, int(e[cost]) - n)


## One attack of the Attack action: the first takes the action and leaves the extra attacks; Haste's action is one attack.
static func pay_attack(s: GameSession, data: Dictionary, f: Dictionary) -> void:
	var e := points(s, data, f)
	if int(e.get("attacks", 0)) > 0:
		e["attacks"] = int(e["attacks"]) - 1
	elif int(e.get("action", 0)) <= 0 and int(e.get("haste", 0)) > 0:
		e["haste"] = 0
	else:
		e["action"] = int(e["action"]) - 1
		e["attacks"] = CharacterRules.extra_attacks(s.character, data) if Sheet.is_hero(f) else 0


## The weapon of the hero's hand: main, off, fists.
static func hand_profile(s: GameSession, data: Dictionary, hand: String) -> Dictionary:
	var c := s.character
	var eq: Dictionary = c.get("equipped", {})
	var wid := "" if hand == "fists" else CharacterRules.off_weapon(eq, data, s.items) if hand == "off" else str(eq.get("main_hand", ""))
	return weapon_profile(c, data, s.items, wid, hand == "off")


## The weapon attack of the character: {name, to_hit, dice, bonus, type, melee, range [normal, long] ft or [], light}.
static func weapon_profile(c: Dictionary, data: Dictionary, session_items: Dictionary, weapon_id: String, offhand: bool = false) -> Dictionary:
	if Guise.has_body(c):  # a druid in a beast form fights with the beast's attack (v0.7.10)
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
	var def := ItemRules.copy_def(data["items"], session_items, c, weapon_id, CharacterRules.hold_index(c, weapon_id, "off_hand" if offhand else "main_hand"))
	var w: Dictionary = def.get("weapon", {})
	var props: Array = def.get("properties", [])
	var ranged := str(w.get("range", "melee")) == "ranged"
	var kind := ItemRules.plain_of(data["items"], session_items, weapon_id)  # a fine storm longsword is a longsword
	var monk := not martial.is_empty() and FeatureRules.monk_weapon(def) and not ranged
	var mod := dex_mod if ranged else (maxi(str_mod, dex_mod) if props.has("finesse") or monk else str_mod)
	var proficient := weapon_proficient(c, w, kind) or FeatureRules.is_pact(c, weapon_id)  # the pact weapon alone (v0.8.4.33)
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
	var duel := not ranged and not props.has("two_handed") and CharacterRules.off_weapon(eq, data, session_items).is_empty() and _has_style(c, "dueling")
	if duel:  # one hand on it: a versatile weapon keeps its one-handed die (v0.8.4.33)
		bonus += 2
	elif w.has("versatile") and str(eq.get("off_hand", "")).is_empty() and not offhand:  # a weapon or a shield there holds the hand
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
	if ranged and CharacterRules.item_prop(c, "ranged_damage_plus2") and kind in ["longbow", "shortbow"]:
		bonus += 2  # Bracers of Archery (v0.7.12)
	var ammo := Gear.ammo_of(data, session_items, weapon_id)
	return SpellEffects.weapon(c, {"name": str(def.get("name", weapon_id)), "to_hit": to_hit, "hit_parts": hit_parts, "dice": dice, "bonus": bonus,
		"type": str(w.get("damage_type", "bludgeoning")), "melee": not ranged, "range": rng, "light": props.has("light"), "id": weapon_id,
		"magical": magic > 0 or str(def.get("rarity", "common")) not in ["common", ""], "silvered": props.has("silvered"), "ammo": ammo,
		"heavy": props.has("heavy"), "reach": props.has("reach"),
		"gwf": not ranged and two_hands and FeatureRules.great_weapon(c), "crit_min": FeatureRules.crit_min(c), "str_based": mod == str_mod and not ranged}, kind)  # Shillelagh, Magic Weapon (v0.7.13.4)


## The hero's bare hands (the monk's Martial Arts die).
## Whether `c` is proficient with the weapon of `def` (v0.8.4.29.3, one place): its category or itself among its proficiencies; a
## template with no list knows the weapons it carries.
static func weapon_proficient(c: Dictionary, def: Dictionary, weapon_id: String) -> bool:
	var profs: Array = c.get("weapon_profs", ["simple", "martial"] if not c.has("class") else [])
	return profs.has(str(def.get("category", ""))) or profs.has(weapon_id)


static func unarmed_profile(c: Dictionary, data: Dictionary) -> Dictionary:
	if Guise.has_body(c):
		return FeatureRules.shape_profile(c, data)
	return weapon_profile(c, data, {}, "")


static func _has_style(c: Dictionary, style: String) -> bool:
	return CharacterRules.style(c, style)


## What `fn` says with the other set in the hands: the buttons ask of a weapon put away.
static func as_stowed(s: GameSession, fn: Callable) -> Variant:
	CharacterRules.swap_hands(s.character)
	var out: Variant = fn.call()
	CharacterRules.swap_hands(s.character)
	return out


## An unseen foe where the hero last saw it: the hero swings there.
static func _as_seen(t: Dictionary) -> Dictionary:
	var out := t.duplicate()
	FightGrid.put(out, FightGrid.shown(t))
	return out



## Anybody aims where an invisible foe was (FightGrid.shown), and it is not there any more.
static func _missed_unseen(s: GameSession, t: Dictionary) -> bool:
	return _has(t, "invisible") and FightGrid.shown(t) != FightGrid.cell(t)


## The hero is charmed by this foe (the master's charm with `by`, or a monster's in v0.7.9): no attack on it (5e).
static func charmed_by(s: GameSession, f: Dictionary, t: Dictionary) -> bool:
	var me := Sheet.holder(s, f)
	if not ConditionRules.has(me, "charmed"):
		return false
	var by := ConditionRules.caused_by(me, "charmed")
	return not by.is_empty() and (by == str(t.get("id", "")) or by == str(t.get("npc_id", "")))


## A friend of `f` stands beside `t` and is up to something: Pack Tactics, Martial Advantage, Sneak Attack.
static func friend_beside(s: GameSession, f: Dictionary, t: Dictionary) -> bool:
	for id: String in friends_of(s, f):
		var o := fighter(s, id)
		if id != str(f.get("id")) and FightGrid.touching(o, t) and not ConditionRules.incapacitated(Sheet.holder(s, o)):
			return true
	return false


## A foe stands beside `f`: 5 ft, what makes a shot worse and a hiding place useless.
static func _foe_beside(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	for id: String in foes_of(s, f):
		var o := fighter(s, id)
		if FightGrid.touching(o, f) and not ConditionRules.does(Sheet.holder(s, o), data, "no_threat"):
			return true
	return false


## The hover text of a line of the fight's log (v0.7.49.4): kept with the fight under the line's start, found by
## the fight's log for a line that begins with it.
static func line_tip(s: GameSession, line: String, tip: String) -> void:
	var tips: Dictionary = s.combat.get("tips", {})
	tips[line] = tip
	s.combat["tips"] = tips


static func tip_for(s: GameSession, text: String) -> String:
	for line: String in s.combat.get("tips", {}):
		if text.begins_with(line):
			return str(s.combat["tips"][line])
	return ""


## Great Weapon Fighting: damage dice of 1 or 2 are rolled again, once.
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


## Engine spells (rules.combat.engine_spells): "" when castable at that target now, otherwise a reason.
## An attack, not a word (v0.7.22.16): a spell of the engine's that hurts (an attack roll or damage) or holds (a
## condition spell beyond a charm). Cast at an NPC out of a fight, it starts the fight.
static func hostile_spell(data: Dictionary, spell_id: String) -> bool:
	var sp: Dictionary = data["spells"].get(spell_id, {})
	if (cfg(data)["engine_spells"] as Array).has(spell_id) and (sp.has("attack") or sp.has("damage_at_slot") or sp.has("damage_at_level")):
		return true
	if SpellEffects.sustained(data, spell_id).has("cond"):
		return true  # a zone that holds: Web, Entangle, Grease
	var cs: Dictionary = cfg(data)["condition_spells"].get(spell_id, {}) if cfg(data)["condition_spells"].get(spell_id) is Dictionary else {}
	return not cs.is_empty() and (cs.get("conditions", []) as Array).any(func(x: Variant) -> bool: return str(x) != "charmed")


## An NPC who does not expect an attack (v0.7.22.16): not hostile and its attitude at least unaware_attitude.
static func npc_unaware(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return not SocialRules.refuses(s, data, npc_id) and s.attitude(npc_id) >= int(cfg(data)["unaware_attitude"])


static func is_engine_spell(data: Dictionary, spell_id: String) -> bool:
	return (cfg(data)["engine_spells"] as Array).has(spell_id) or cfg(data)["condition_spells"].has(spell_id) or cfg(data)["spell_targets"].has(spell_id) 		or not SpellEffects.spec(data, spell_id).is_empty()  # the buffs and curses of v0.7.13 resolve in the engine too


## The AC of a fighter now: its own, and what its statuses give or take.
static func ac_of(f: Dictionary) -> int:
	var ac := int(Guise.body(f).get("ac", f["ac"])) + ConditionRules.sum(f, "ac")
	for e: Dictionary in f.get("effects", []):
		if e.has("ac_min"):  # Barkskin, Mage Armor: the better of theirs and its own, read live (v0.8.4.15)
			ac = maxi(ac, int(e["ac_min"]))
	return ac + int(f.get("cover", 0))


static func _has(f: Dictionary, cond: String) -> bool:
	return (f.get("conditions", []) as Array).has(cond)


static func incapacitated(f: Dictionary) -> bool:
	return ConditionRules.incapacitated(f)


static func cond_name(data: Dictionary, cond: String) -> String:
	return ConditionRules.name_of(data, cond).to_lower()


## The conditions of a fighter with its turns left: «без сознания (9 р.)».
static func foe_conditions(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for cond: String in f.get("conditions", []):
		var left := -1
		for e: Dictionary in ConditionRules.effects_of(f, cond):
			if e.get("ends", {}).has("at"):
				left = int(e["ends"]["at"]) - ConditionRules.now(s) + (1 if _yet_to_act(s, f) else 0)
		out.append(cond_name(data, cond) + ((" (%d р.)" % left) if left >= 0 else ""))
	return out


## What the fight lays on `f` beside its statuses, for its portrait (v0.8.4.43.10): «hidden», «surprised», «raging»,
## «reckless», «dodging», «shape» (a beast's form), «sneaking» (out of a fight). A status of its record is `ConditionRules.shown`'s, not one of these.
static func marks(s: GameSession, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k: String in ["hidden", "surprised", "raging", "reckless", "dodging"]:
		if bool(f.get(k, false)):
			out.append(k)
	if Guise.has_body(Sheet.holder(s, f)):
		out.append("shape")
	if not active(s) and Sheet.is_hero(f) and s.sneaking:  # out of a fight the hero who sneaks says so (the author, 2026-11-13)
		out.append("sneaking")
	return out


## Its turn in this round is still ahead (or going on): a status counted in its turns ends a round sooner on the clock.
static func _yet_to_act(s: GameSession, f: Dictionary) -> bool:
	return (s.combat.get("order", []) as Array).find(str(f.get("id", ""))) >= int(s.combat.get("turn", 0))


## A status on anyone by a timer of its turns: `rounds` (none — until something ends it), `spell`, `save`, `tag` and `dc` of a
## repeat save at the end of its turn, `wake` — ends on damage, `item`, `name`, `by` — who laid it, the one casting by default.
## One condition is held once. Lines.
static func _add_condition(s: GameSession, data: Dictionary, f: Dictionary, cond: String, timer: Dictionary) -> Array[String]:
	var hero := Sheet.is_hero(f)
	var me := Sheet.holder(s, f)
	ConditionRules.remove(me, cond)
	var e := {"condition": cond, "by": str(timer.get("by", caster(s)["id"])), "source": {"kind": "spell" if timer.has("spell") else "engine", "id": str(timer.get("spell", "")), "name": str(timer.get("name", ""))}}
	if timer.has("rounds") and cond != "prone":
		e["ends"] = {"at": ConditionRules.now(s) + int(timer["rounds"]) - (1 if _yet_to_act(s, f) else 0)}
	elif hero and cond != "prone":
		e["ends"] = {"rest": "short"}
	if not str(timer.get("save", "")).is_empty():
		e["save"] = {"ability": str(timer["save"]), "dc": int(timer.get("dc", 10)), "tag": str(timer.get("tag", "magic")), "repeat": true,
			"once": bool(timer.get("once", false))}
		if timer.has("escalate"):  # one failed repeat save makes it worse: a basilisk's stone (v0.8.4.27.6), as a cockatrice's
			e["escalate"] = timer["escalate"]
	if bool(timer.get("wake", false)):
		e["wake"] = true
	if timer.has("item"):
		e["item"] = str(timer["item"])
	for k: String in ["escape_dc", "escape", "zone"]:  # held until broken by «Вырваться» (a net, a web), or until its zone is gone
		if timer.has(k):
			e[k] = timer[k]
	if bool(data["spells"].get(str(timer.get("spell", "")), {}).get("concentration", false)):
		e["conc"] = true
	var lines := ConditionRules.impose(s, data, e, f)
	if hero:
		CharacterRules.refresh(me, data, s.items)
	return lines


static func _remove_condition(f: Dictionary, cond: String) -> void:
	ConditionRules.remove(f, cond)


## Condition spells (rules.combat.condition_spells, v0.6.5), on anyone: a save against the caster's DC (or a pool of hit
## points — Sleep, Color Spray), conditions for rounds, a repeat save at the end of the target's turn, waking on damage; a
## concentration spell ends when the caster's concentration moves on.
static func _cast_condition(s: GameSession, data: Dictionary, spell_id: String, slot: int, target: Dictionary, lines: Array[String]) -> void:
	var sp: Dictionary = data["spells"][spell_id]
	var spec: Dictionary = cfg(data)["condition_spells"][spell_id]
	var name := str(sp["name"])
	var targets: Array[Dictionary] = []
	if bool(spec.get("area", false)) or sp.has("area"):
		targets = area_targets(s, data, sp, target)
	else:
		targets.append(target)
	var timer := {"rounds": int(spec.get("rounds", 10)) * (2 if str(s.combat.get("meta_now", "")) == "extended_spell" else 1), "spell": spell_id, "wake": bool(spec.get("ends_on_damage", false)),
		"save": str(sp["save"]["ability"]) if bool(spec.get("repeat_save", false)) and sp.has("save") else "", "dc": spell_dc(s)}
	if spec.has("pool"):  # Sleep, Color Spray: the weakest first while the pool lasts
		var conds: Array = spec["conditions"]
		var extra := maxi(0, slot - maxi(1, int(sp["level"])))
		var pool := roll_dice(s.rng, str(spec["pool"]))
		for i in extra:
			pool += roll_dice(s.rng, str(spec["pool_per_slot"]))
		lines.append("%s: пул %d хитов" % [name, pool])
		targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(Sheet.holder(s, a)["hp"]) < int(Sheet.holder(s, b)["hp"]))
		for t: Dictionary in targets:
			var it := Sheet.holder(s, t)
			if str(t["status"]) != "active" or conds.all(func(x: String) -> bool: return ConditionRules.has(it, x)) or not _resists(s, data, t, spec, conds, "magic").is_empty():
				continue
			if int(it["hp"]) > pool:
				lines.append("%s: %s устоял — хитов больше, чем осталось в пуле" % [name, t["name"]])
				break
			pool -= int(it["hp"])
			for cond: String in conds:
				lines.append_array(_add_condition(s, data, t, cond, timer))
			lines.append("%s: %s — %s" % [name, t["name"], ", ".join(conds.map(func(x: String) -> String: return cond_name(data, x)))])
		return
	for t: Dictionary in targets:
		if str(t["status"]) == "active":
			_condition_on(s, data, spell_id, spec, t, timer, lines)


## What a save against a spell of conditions is against: «charm,magic», for the traits that resist it.
static func _spell_tag(data: Dictionary, spell_id: String, conds: Array) -> String:
	return HeroDefense.cond_tags(data, conds, ["magic", "fighting"] if spell_id == "charm_person" else ["magic"])  # 5e: advantage when fought (v0.7.13)


## The spell's conditions try one target: a word of Command, what keeps them off, the save. Lines into `lines`.
static func _condition_on(s: GameSession, data: Dictionary, spell_id: String, spec: Dictionary, t: Dictionary, timer: Dictionary, lines: Array[String]) -> void:
	var sp: Dictionary = data["spells"][spell_id]
	var name := str(sp["name"])
	var word := MonsterRules._command_word(s, spec, t)
	var conds: Array = word.get("conditions", spec["conditions"])
	var said := " — «%s»" % word["word"] if not word.is_empty() else ""
	var tag := _spell_tag(data, spell_id, conds)
	var no := _resists(s, data, t, spec, conds, tag)
	if not no.is_empty():
		lines.append("%s: на %s не действует%s" % [name, t["name"], "" if no == "-" else " — " + no])
		return
	var ab := str(sp.get("save", {}).get("ability", spec.get("save", "dex")))  # Web asks of who is caught
	lines.append("%s%s: %s" % [name, said, t["name"]])
	var ok := Sheet.saved(s, data, t, ab, spell_dc(s), tag, _heighten(s), lines)
	AnimRules.outcome(s, t, "resist" if ok else "debuff")
	if ok:
		return
	lines.append("%s: %s" % [t["name"], ", ".join(conds.map(func(x: String) -> String: return cond_name(data, x)))])
	for cond: String in conds:
		lines.append_array(_add_condition(s, data, t, cond, timer.merged({"tag": tag}, true)))
	if bool(word.get("drop", false)):
		var it := Sheet.holder(s, t)
		var held := str(it["equipped"]["main_hand"])
		it["equipped"]["main_hand"] = ""
		it["dropped"] = held  # picked up at the start of its next turn it can act (a free interaction, 5e)
		CharacterRules.refresh(it, data, s.items)
		lines.append("%s роняет %s" % [t["name"], ItemRules.display_name(data["items"], s.items, held)])
	if int(word.get("flee", 0)) > 0:
		FightField.thrust(s, data, t, FightGrid.cell(t) - FightGrid.cell(caster(s)), FightGrid.squares_of(data, int(word["flee"])), lines)
		lines.append("%s бежит прочь" % t["name"])


## What keeps the conditions off `t`: "" none, «-» — it cannot get them, or what protects it.
static func _resists(s: GameSession, data: Dictionary, t: Dictionary, spec: Dictionary, conds: Array, tag: String) -> String:
	if not _can_be(s, data, t, spec):
		return "-"
	for cond: String in conds:  # Heroism, Steadfast, an elf and magical sleep: anybody's (v0.8.4.27.5)
		var why := HeroDefense.immune(s, data, t, cond, tag)
		if not why.is_empty():
			return why
	return ""


## Whether a foe can get the spell's conditions: creature types (`types`, `immune_types`), condition immunities,
## a minimum Intelligence (Hideous Laughter).
static func _can_be(s: GameSession, data: Dictionary, t: Dictionary, spec: Dictionary) -> bool:
	if Sheet.ability(s, data, t, "int") < int(spec.get("min_int", 0)):  # anybody's by its sheet (v0.8.4.29.3)
		return false
	if Sheet.is_hero(t):
		return true
	var m := Sheet.template(data, t)
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
	return not ((spec["conditions"] as Array).has("unconscious") and MonsterRules.sleep_immune(data, t))


## A concentration ended: what the spell of `by` left on anyone goes, its zones and its creatures.
static func end_spell(s: GameSession, data: Dictionary, spell_id: String, by: String = PLAYER) -> Array[String]:
	var lines: Array[String] = []
	if spell_id.is_empty() or not active(s):
		return lines
	lines.append_array(SpellEffects.end_on_fighters(s, data, spell_id, by))
	lines.append_array(SpellEffects.end_zones(s, spell_id, by))  # v0.7.13.5
	var hero := by == PLAYER
	var fall := str(SpellEffects.spec(data, spell_id).get("fall", ""))
	if hero and not fall.is_empty() and int(s.character.get("hp", 0)) > 0:  # Fly ends in the air (v0.7.63): the hero comes down
		_fall(s, data, player(s), spell_id, fall, lines)
	for id: String in enemies(s) + allies(s):  # v0.7.22.22: the creatures of a concentration spell go with it
		var a := fighter(s, id)
		if str(a.get("spell", "")) == spell_id and str(a.get("called_by", PLAYER)) == by and bool(data["spells"].get(spell_id, {}).get("concentration", false)):
			a["status"] = "gone"
			lines.append("%s исчезает — концентрация прервана" % a["name"])
	if not hero:
		return lines
	var on_others := allies(s, false).any(func(id: String) -> bool: return fighter(s, id).has("lethargy")) \
		or Being.with(s, "effects").any(func(id: String) -> bool: return (Being.view(s, id)["effects"] as Array).any(func(x: Dictionary) -> bool: return str(x.get("source", {}).get("id", "")) == spell_id))  # v0.7.50.1
	AllyRules.drop_buffs(s, spell_id)
	if spell_id == "haste" and not on_others:  # v0.7.13.3: a wave of lethargy
		s.character["lethargy"] = true
		lines.append("Ускорение кончилось — на ход накатывает вялость")
	return lines


## Anyone comes down from a height a spell held it at.
static func _fall(s: GameSession, data: Dictionary, f: Dictionary, spell_id: String, dice: String, lines: Array[String]) -> void:
	fall(s, data, f, dice, "падает с высоты", {"kind": "spell", "id": spell_id, "name": "падение"}, lines)


## Anybody falls (into a pit, from a height): `dice` of bludgeoning less what a reaction at the moment `fall` takes off
## (Slow Fall, v0.8.4.26.1), then prone if still up. `what` — the line's words, `source` — of the prone.
static func fall(s: GameSession, data: Dictionary, f: Dictionary, dice: String, what: String, source: Dictionary, lines: Array[String], type: String = "bludgeoning") -> void:
	var ctx := {"dmg": roll_dice(s.rng, dice), "cut": 0}
	Acts.react(s, data, f, "fall", ctx, lines)
	Harm.typed(s, data, f, maxi(0, int(ctx["dmg"]) - int(ctx["cut"])), type, lines, str(f["name"]) + " " + what + ": {hp} ({words})")
	if Attack.up(s, f):
		lines.append_array(ConditionRules.impose(s, data, {"condition": "prone", "ends": {"rest": "short"}, "source": source}, f))


static func spell_cost(data: Dictionary, spell_id: String) -> String:
	return "bonus" if str(data["spells"].get(spell_id, {}).get("casting_time", "")).contains("бонус") else "action"


## One invisible that `me` has no means to see.
static func _unseen_by(s: GameSession, me: Dictionary, t: Dictionary) -> bool:
	var it := Sheet.holder(s, t)
	return ConditionRules.has(it, "invisible") and not SpellEffects.has(Sheet.holder(s, me), "see_invisible") and not ConditionRules.has(it, "outlined")


## "" when the area of a spell can be laid on a square: in range and not behind total cover from the caster
## (FightGrid.reaches, the rule of a blow); a jump only to a free square it sees.
static func _can_aim(s: GameSession, data: Dictionary, spell_id: String, at: Vector2i, f: Dictionary) -> String:
	var jump := int(SpellEffects.spec(data, spell_id).get("teleport", 0))
	if jump > 0:  # Misty Step: a free square it sees
		var g := FightGrid.grid(s, data)
		if FightGrid.dist_to(f, at) > FightGrid.squares_of(data, jump):
			return "COMBAT_OUT_OF_RANGE"
		if FightGrid.bodies(s).has(at) or not FightGrid.walkable(g, at):
			return "COMBAT_BAD_TARGET"
		return "" if FightGrid.clear(g, FightGrid.cell(f), at) else "COMBAT_NO_LINE"
	if area_of(data, spell_id).is_empty() or data["spells"].get(spell_id, {}).has("attack"):
		return "COMBAT_BAD_TARGET"
	if from_self(data, spell_id):
		return ""
	if FightGrid.dist_to(f, at) > _spell_squares(s, data, spell_id, f):
		return "COMBAT_OUT_OF_RANGE"
	return "" if FightGrid.reaches(s, data, f, at) else "COMBAT_NO_LINE"


## The shape of a spell {type, size}, {} when it has none.
static func area_of(data: Dictionary, spell_id: String) -> Dictionary:
	return data["spells"].get(spell_id, {}).get("area", {})


## The area starts at the caster: a cone, a line, a cube of range Self.
static func from_self(data: Dictionary, spell_id: String) -> bool:
	return int(data["spells"].get(spell_id, {}).get("range_ft", 0)) <= 0


## "" when a spell of `f`'s side may land on `target_id`: itself, or one of its side in range; a fallen one only for a heal.
static func _can_friend(s: GameSession, data: Dictionary, spell_id: String, target_id: String, f: Dictionary) -> String:
	var fx := SpellEffects.spec(data, spell_id)
	if target_id == str(f["id"]):  # Warding Bond, Spare the Dying: on another (v0.8.4.26.3)
		return "COMBAT_BAD_TARGET" if bool(fx.get("other", false)) else ""
	var t := fighter(s, target_id)
	var fallen_ok := str(t.get("status")) == "down" and (fx.is_empty() or fx.has("stabilize"))
	var same := (str(t.get("side")) == "enemy") == (str(f.get("side")) == "enemy")
	if t.is_empty() or not same or not (str(t.get("status")) == "active" or fallen_ok) or (fx.has("stabilize") and not dying(s, t)):
		return "COMBAT_BAD_TARGET"
	if FightGrid.dist(f, t) > _spell_squares(s, data, spell_id, f):
		return "COMBAT_OUT_OF_RANGE"
	return "COMBAT_NO_LINE" if (_no_line(s, data, f, t) or _blind_aim(s, data, spell_id, t, f)) and FightGrid.dist(f, t) > 1 else ""


## A spell's range: Eldritch Spear (300 ft for Eldritch Blast), Distant Spell (double).
static func spell_range(s: GameSession, data: Dictionary, spell_id: String, f: Dictionary = Sheet.HERO) -> int:
	var ft := int(data["spells"].get(spell_id, {}).get("range_ft", 0))
	if spell_id == "eldritch_blast" and FeatureRules.has(Sheet.holder(s, f), "eldritch_invocation_eldritch_spear"):
		ft = 300
	if FeatureRules.active_metamagic(s, data, f) == "distant_spell":
		ft = int(FeatureRules.cfg(data)["metamagic"]["distant_spell"].get("touch_ft", 30)) if ft <= 5 else ft * 2  # a touch becomes 30 ft (5e)
	return ft


# --- items in a fight (v0.7.12) --------------------------------------------------------------------


## Throws the thing: a ranged attack — improvised (DEX, no proficiency, 20/60 ft) or the net's;
## on a hit its damage (only to `types` when given), burning, oil or the net's hold. Lines.
static func throw_item(s: GameSession, data: Dictionary, f: Dictionary, item_id: String, target_id: String) -> Array[String]:
	var c := Sheet.holder(s, f)
	points(s, data, f)["attacked"] = true
	var fx: Dictionary = ItemRules.consumable(data, item_id, s.items)["throw"]
	var name := ItemRules.display_name(data["items"], s.items, item_id)
	ItemRules.remove(c, item_id)
	if FightGrid.is_aim(target_id):
		var splashed: Array[String] = []
		FightField.splash(s, data, FightGrid.aim_of(target_id), fx, name, splashed, str(f.get("side", "player")), str(f.get("id", "")))
		if fx.has("effect"):
			LiquidRules.burst(s, data, f, FightGrid.aim_of(target_id), fx, name, splashed)
		return splashed
	var t := fighter(s, target_id)
	var dex := Sheet.ability_mod(s, data, f, "dex")
	var proficient := bool(fx.get("weapon", false)) and weapon_proficient(c, ItemRules.def_of(data["items"], s.items, item_id).get("weapon", {}), ItemRules.plain_of(data["items"], s.items, item_id))
	var to_hit := dex + (Sheet.prof(s, data, f) if proficient else 0)
	var near := int(fx.get("range", 20))
	var blow := {"name": name, "to_hit": to_hit, "pieces": [], "melee": false, "range": [near, 60 if bool(fx.get("improvised", false)) else near], "str_based": false}
	var lines: Array[String] = []
	var hit := bool(Attack.swing(s, data, f, t, blow, lines)["hit"])
	if not hit:
		return lines
	if fx.has("damage"):
		var types: Array = fx.get("types", [])
		if not types.is_empty() and not types.has(str(Sheet.template(data, t).get("type", ""))):
			lines.append("%s: на %s не действует" % [name, t["name"]])
		else:
			var dtype := str(fx["damage"][1])
			var dmg := Sheet.taken(s, data, t, dtype, roll_dice(s.rng, str(fx["damage"][0])))
			lines.append("%s: %d (%s)" % [name, dmg, data["misc"]["damage_types"].get(dtype, dtype)])
			Harm.take(s, data, t, dmg, lines, dtype, false, Sheet.is_hero(f))
	if fx.has("liquid") and Attack.up(s, t):  # what lies on it after: oil, alchemist's fire, water (v0.8.4.28.2)
		var lid := str(fx["liquid"])
		var holder := Sheet.holder(s, t)
		lines.append_array(LiquidRules.coat(s, data, holder, lid, name))
		if not LiquidRules.burning(s, holder).is_empty():
			FightField.kindle(s, data, FightGrid.body_at(FightGrid.cell(t), int(t.get("span", 1))), lines)
			lines.append("%s горит" % t["name"])
		elif LiquidRules.fire_plus(s, holder) > 0:
			lines.append("%s облит: %s — огонь возьмёт его сильнее" % [t["name"], LiquidRules.name_of(data, lid)])
	if fx.has("effect"):  # a made liquid (v0.8.4.28.5): its area around the one struck
		LiquidRules.burst(s, data, f, FightGrid.cell(t), fx, name, lines)
	if fx.has("condition") and Attack.up(s, t):
		if SIZES.find(str(Sheet.template(data, t).get("size", "medium"))) > SIZES.find(str(fx.get("max_size", "large"))):
			lines.append("%s слишком велик для сети" % t["name"])
		else:
			_add_condition(s, data, t, str(fx["condition"]), {"escape_dc": int(fx.get("escape_dc", 10)), "escape": ["athletics"], "item": item_id,
				"by": str(f.get("id", ""))})  # a net: until broken (5e), held by the thrower
			lines.append("%s: %s, вырваться — Сил Сл %d" % [t["name"], cond_name(data, str(fx["condition"])), int(fx.get("escape_dc", 10))])
	return lines


## Who casts now: the one `ActionRules.cast` named, the hero outside of it.
static func caster(s: GameSession) -> Dictionary:
	var me := fighter(s, str(s.combat.get("by", {}).get("caster", PLAYER)))
	return Sheet.HERO if me.is_empty() else me


## The level its cantrips grow by.
static func caster_level(s: GameSession) -> int:
	return int(s.combat.get("by", {}).get("level", s.character.get("level", 1)))


## The DC and the attack of the spell now: the caster's, the item's or the built ability's while it lands, the hero's otherwise.
static func spell_dc(s: GameSession) -> int:
	return int(s.combat.get("by", {}).get("dc", s.character.get("spell_dc", 10)))


static func spell_attack(s: GameSession) -> int:
	return int(s.combat.get("by", {}).get("attack", s.character.get("spell_attack", 0)))


## The ability of the spell now.
static func spell_ability(s: GameSession) -> String:
	return str(s.combat.get("by", {}).get("ability", s.character.get("spell_ability", "int")))


## A spell of damage at a foe of the caster: an attack, a save, an area, a volley.
static func _spell_damage(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String, lines: Array[String]) -> void:
	var me := caster(s)
	var by_hero := Sheet.is_hero(me)
	var sp: Dictionary = data["spells"][spell_id]
	var level := caster_level(s)
	lines.append_array(SpellEffects.end_on_attack(Sheet.holder(s, me)))  # a spell at a foe ends Sanctuary (v0.7.13.2)
	var dice := spell_dice(sp, slot, level)
	var t := aimed(s, target_id)
	if not t.is_empty():  # fire catches what burns, and any damage leaves its surface (v0.8.4.43.45)
		var touched: Array[Vector2i] = area_cells(s, data, sp, t) if sp.has("area") else FightGrid.body_at(FightGrid.cell(t), int(t.get("span", 1)))
		if str(sp.get("damage_type", "")) == "fire":
			FightField.kindle(s, data, touched, lines)
		FightField.react(s, data, str(sp.get("damage_type", "")), touched, me, lines)
	if not sp.has("area") and _missed_unseen(s, t):
		lines.append("%s: в пустоту — %s уже не там" % [sp["name"], t["name"]])
		return
	var targets: Array[Dictionary] = [t]
	if sp.has("area"):
		targets = _sculpted(s, data, sp, me, area_targets(s, data, sp, t), lines)
	var multi: Dictionary = cfg(data)["multi"].get(spell_id, {})
	var count := SpellEffects.count(data, spell_id, slot, level)
	var dtype := str(sp.get("damage_type", ""))
	var name := str(sp["name"])
	if by_hero and count > 1 and not sp.has("area") and bool(cfg(data).get("volley_one_by_one", false)):
		# As in BG3 (v0.7.22.4, big test #33): one dart or ray now, a target for each of the rest by the button.
		s.combat["volley"] = {"spell": spell_id, "slot": slot, "left": count - 1, "last": target_id}
		count = 1
	for i in count:
		if bool(s.combat.get("halt", false)) or (not sp.has("area") and str(t.get("status")) != "active"):
			break
		if bool(multi.get("auto_hit", false)) or sp.has("attack"):
			_bolt(s, data, spell_id, slot, t, dice, lines)
		elif sp.has("save"):
			var dmg_full := roll_dice(s.rng, _empowered(s, dice))
			for tg: Dictionary in targets:
				if str(tg.get("status")) != "active":
					continue
				var save_ab := str(sp["save"]["ability"])
				var dc := spell_dc(s)
				var opts := {"tag": "magic", "half": str(sp["save"]["success"]) == "half", "dis": _heighten(s)}
				if sp.has("area"):
					opts["from"] = _area_origin(s, data, sp, t)
				var sh := Harm.save_half(s, data, tg, save_ab, dc, [{"n": dmg_full, "type": dtype}], opts)
				var ok := bool(sh["ok"])
				var dmg := int(sh["damage"])
				AnimRules.outcome(s, tg, "impact" if dmg > 0 else "resist", dtype)
				lines.append(str(sh["save"]["line"]))
				lines.append("%s: %s — %d (%s)" % [name, tg["name"], dmg, data["misc"]["damage_types"].get(dtype, dtype)])
				if by_hero:
					_caught_friend(s, data, tg)
				if dmg > 0:
					Harm.take(s, data, tg, dmg, lines, dtype, false, by_hero)
				ActionRules.riders(s, data, spell_id, slot, tg, not ok, lines)


## One dart or ray of a spell (an auto hit or a spell attack) at `t`. Lines.
static func _bolt(s: GameSession, data: Dictionary, spell_id: String, slot: int, t: Dictionary, dice: String, lines: Array[String]) -> void:
	var me := caster(s)
	var by_hero := Sheet.is_hero(me)
	var c := Sheet.holder(s, me)
	var sp: Dictionary = data["spells"][spell_id]
	var dtype := str(sp.get("damage_type", ""))
	var name := str(sp["name"])
	if bool(cfg(data)["multi"].get(spell_id, {}).get("auto_hit", false)):
		AnimRules.result(s, data, AnimRules.spell_at(s, data, spell_id, me, t), t, "hit")  # a dart of its own (v0.8.4.23)
		var dmg := Sheet.taken(s, data, t, dtype, roll_dice(s.rng, _empowered(s, dice)))
		lines.append("%s: %d (%s) по %s" % [name, dmg, data["misc"]["damage_types"].get(dtype, dtype), t["name"]])
		Harm.take(s, data, t, dmg, lines, dtype, false, by_hero)
		return
	# v0.7.13: a spell attack has the advantages and disadvantages of any attack (prone, hidden, guided, dark…)
	var sres := Attack.swing(s, data, me, t, spell_blow(s, data, spell_id, _empowered(s, dice), me, t), lines)
	ActionRules.riders(s, data, spell_id, slot, t, bool(sres["hit"]), lines)
	var repel := bool(sres["hit"]) and spell_id == "eldritch_blast" and FeatureRules.has(c, "eldritch_invocation_repelling_blast")
	if repel and str(t.get("status")) == "active" and SIZES.find(Sheet.size(s, data, t)) <= 3:
		push_away(s, data, t, 10)
		lines.append("Отталкивающий заряд: %s отброшен на 10 фт" % t["name"])


## The blow of a spell attack of `me` at `t` (v0.8.4.29.3: the roll and the window build it alike): Agonizing Blast, Shocking Grasp
## on metal.
static func spell_blow(s: GameSession, data: Dictionary, spell_id: String, dice: String, me: Dictionary, t: Dictionary) -> Dictionary:
	var sp: Dictionary = data["spells"][spell_id]
	var c := Sheet.holder(s, me)
	var agonizing := maxi(0, FeatureRules.ab_mod(c, "cha")) if spell_id == "eldritch_blast" and FeatureRules.has(c, "eldritch_invocation_agonizing_blast") else 0
	var blow := Attack.of_spell(str(sp["name"]), spell_attack(s), dice, agonizing, str(sp.get("damage_type", "")), str(sp["attack"]) == "melee", int(sp.get("range_ft", 5)))
	blow["spell"] = spell_id  # its look is the spell's delivery (v0.8.4.23)
	if spell_id == "shocking_grasp" and _metal_armor(s, data, t):
		blow["adv"] = ["металлический доспех"]
	return blow


## What a healing spell gives at this slot, by the caster's numbers.
static func heal_roll(s: GameSession, data: Dictionary, spell_id: String, slot: int) -> int:
	var me := caster(s)
	return SpellRules.heal_points(data, Sheet.holder(s, me), spell_id, slot, Sheet.ability_mod(s, data, me, spell_ability(s)), s.rng)


## A healing spell lands on anyone in the fight: one who lay at 0 HP is back in it.
static func heal(s: GameSession, data: Dictionary, spell_id: String, slot: int, t: Dictionary, lines: Array[String]) -> void:
	var it := Sheet.holder(s, t)
	var before := int(it["hp"])
	if Harm.mend(s, data, t, heal_roll(s, data, spell_id, slot)) <= 0 and ConditionRules.does(it, data, "no_heal"):  # Chill Touch, a swarm
		lines.append("%s: раны не затягиваются" % t["name"])
		return
	AnimRules.outcome(s, t, "heal")
	lines.append("+%d HP" % (int(it["hp"]) - before) if Sheet.is_hero(t) and Sheet.is_hero(caster(s)) else "%s: +%d HP" % [t["name"], int(it["hp"]) - before])


## The targets left to pick after the first (v0.7.50.1): a volley with `picks`, none when nobody is left to pick.
static func _start_picks(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String) -> void:
	var left := SpellEffects.picks_count(data, spell_id, slot) - 1
	if left <= 0:
		return
	var first := PLAYER if target_id.is_empty() else target_id
	s.combat["volley"] = {"spell": spell_id, "slot": slot, "left": left, "last": first, "picks": [first]}
	if not _can_pick_more(s, data):
		s.combat.erase("volley")


## The side a volley's chosen targets are of: the spell's own, or that of the first target of a twinned one.
static func volley_side(data: Dictionary, v: Dictionary) -> String:
	return str(v.get("side", SpellEffects.picks_side(data, str(v.get("spell", "")))))


static func _can_pick_more(s: GameSession, data: Dictionary) -> bool:
	var ids: Array[String] = enemies(s)
	if volley_side(data, volley(s)) == "friend":
		ids = allies(s, false)
		ids.append(PLAYER)
	return ids.any(func(id: String) -> bool: return can_volley(s, data, id).is_empty())


## The spell of a volley with `picks` lands on the next chosen target.
static func _pick_shot(s: GameSession, data: Dictionary, v: Dictionary, target_id: String, lines: Array[String]) -> void:
	var spell_id := str(v["spell"])
	var slot := int(v["slot"])
	(v["picks"] as Array).append(target_id)
	if v.has("side"):  # the twin of a spell lands on its own way (v0.8.4.33)
		ActionRules.land(s, data, spell_id, slot, target_id, lines)
	elif SpellEffects.picks_side(data, spell_id) == "friend":
		if target_id != PLAYER or not Sheet.is_hero(caster(s)):
			SpellEffects.on_friend(s, data, spell_id, slot, fighter(s, target_id), lines)
		elif SpellEffects.self_spell(data, spell_id):
			lines.append_array(SpellEffects.apply_self(s, data, spell_id, slot))
		elif (data["rules"]["invisibility"]["spells"] as Dictionary).has(spell_id):
			s.character.erase("invisible_others")
		else:
			heal(s, data, spell_id, slot, player(s), lines)
	elif cfg(data)["condition_spells"].has(spell_id):
		_cast_condition(s, data, spell_id, slot, fighter(s, target_id), lines)
	elif not SpellEffects.curse(data, spell_id).is_empty():
		SpellEffects.cast_curse(s, data, spell_id, slot, fighter(s, target_id), lines)
	elif SpellEffects.foe_spell(data, spell_id):
		SpellEffects.curse_foes(s, data, spell_id, slot, fighter(s, target_id), lines)
	else:  # the second creature of Acid Splash
		var sp: Dictionary = data["spells"][spell_id]
		var t := fighter(s, target_id)
		var dtype := str(sp.get("damage_type", ""))
		var ok := Sheet.saved(s, data, t, str(sp["save"]["ability"]), spell_dc(s), "magic", false, lines)
		var dmg := 0 if ok else Sheet.taken(s, data, t, dtype, roll_dice(s.rng, _empowered(s, spell_dice(sp, slot, caster_level(s)))))
		lines.append("%s: %s — %d (%s)" % [sp["name"], t["name"], dmg, data["misc"]["damage_types"].get(dtype, dtype)])
		if dmg > 0:
			Harm.take(s, data, t, dmg, lines, dtype, false, Sheet.is_hero(caster(s)))


## The darts or rays left of the spell just cast (v0.7.22.4): {spell, slot, left, last} or {}; with `picks` (v0.7.50.1)
## — the chosen targets of a spell of rules.combat.spell_targets, each one once.
static func volley(s: GameSession) -> Dictionary:
	return s.combat.get("volley", {}) if s.combat.get("volley") is Dictionary else {}


## "" when the next dart or ray may fly at `target_id`, else the reason (a localization key).
static func can_volley(s: GameSession, data: Dictionary, target_id: String) -> String:
	var v := volley(s)
	if v.is_empty() or not is_player_turn(s):
		return "COMBAT_NO_VOLLEY"
	if v.has("picks"):
		if (v["picks"] as Array).has(target_id):
			return "COMBAT_PICKED"
		if volley_side(data, v) == "friend":
			return _can_friend(s, data, str(v["spell"]), target_id, player(s))
	var t := fighter(s, target_id)
	if t.is_empty() or str(t.get("status")) != "active" or str(t.get("side")) != "enemy":
		return "COMBAT_BAD_TARGET"
	if bool(SpellEffects.picks(data, str(v["spell"])).get("near", false)) and v.has("picks") and not FightGrid.touching(t, fighter(s, str(v["picks"][0]))):
		return "COMBAT_OUT_OF_RANGE"
	var sp: Dictionary = data["spells"][str(v["spell"])]
	if _no_line(s, data, player(s), t) or _blind_aim(s, data, str(v["spell"]), t, player(s)):
		return "COMBAT_NO_LINE"
	if FightGrid.dist(player(s), t) > maxi(1, FightGrid.squares_of(data, int(sp.get("range_ft", 0)))):
		return "COMBAT_OUT_OF_RANGE"
	return ""


## The next dart or ray at `target_id` (can_volley first). Lines.
static func volley_shot(s: GameSession, data: Dictionary, target_id: String) -> Array[String]:
	var v := volley(s)
	var lines: Array[String] = []
	var sp: Dictionary = data["spells"][str(v["spell"])]
	var t := fighter(s, target_id)
	if v.has("picks"):
		var scoped := v.has("by") and not s.combat.has("by")  # a twin lands with the numbers it was cast with
		if scoped:
			s.combat["by"] = v["by"]
		_pick_shot(s, data, v, target_id, lines)
		if scoped:
			s.combat.erase("by")
	else:
		_bolt(s, data, str(v["spell"]), int(v["slot"]), t, spell_dice(sp, int(v["slot"]), int(s.character.get("level", 1))), lines)
	v["left"] = int(v["left"]) - 1
	v["last"] = target_id
	if int(v["left"]) <= 0 or enemies(s).is_empty() or (v.has("picks") and not _can_pick_more(s, data)):
		s.combat.erase("volley")
	return lines


## The turn ends with darts left: they fly at the last target, or the nearest foe still standing. Lines.
static func volley_flush(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	while not volley(s).is_empty():
		var v := volley(s)
		if v.has("picks"):  # chosen targets are not picked for the hero
			s.combat.erase("volley")
			break
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


## What a target id means: a fighter, or the square of "@x,y" as {x, y, aim}.
static func aimed(s: GameSession, target_id: String) -> Dictionary:
	if not FightGrid.is_aim(target_id):
		return fighter(s, target_id)
	var at := FightGrid.aim_of(target_id)
	return {"x": at.x, "y": at.y, "aim": true, "id": target_id, "status": "active", "name": ""}


## The squares of a spell's area laid at a target or a square.
static func area_cells(s: GameSession, data: Dictionary, sp: Dictionary, t: Dictionary) -> Array[Vector2i]:
	var from_me := int(sp.get("range_ft", 0)) == 0
	return FightGrid.area(s, data, sp.get("area", {}), FightGrid.cell(caster(s)), _aim_square(s, t), from_me)


## The square of the body of `t` that the caster aims at.
static func _aim_square(s: GameSession, t: Dictionary) -> Vector2i:
	return FightGrid.cell(t) if bool(t.get("aim", false)) else FightGrid._facing(caster(s), t)[1]


## The point an area spreads from: its cover goes by it.
static func _area_origin(s: GameSession, data: Dictionary, sp: Dictionary, t: Dictionary) -> Vector2i:
	return FightGrid.cell(caster(s)) if int(sp.get("range_ft", 0)) == 0 else _aim_square(s, t)


## Who an area spell covers (v0.8.4): those standing on its squares. v0.7.50.1 (friendly fire, rules.combat.friendly_fire):
## an area does not pick sides — the caster's friends in it are caught, itself too, unless the area starts at it.
static func area_targets(s: GameSession, data: Dictionary, sp: Dictionary, t: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := caster(s)
	var field: Array[String] = foes_of(s, me)
	if bool(cfg(data)["friendly_fire"]["on"]):
		field.append_array(friends_of(s, me))
		if int(sp.get("range_ft", 0)) == 0:
			field.erase(str(me["id"]))
	var cells := area_cells(s, data, sp, t)
	for id: String in field:
		if FightGrid.in_cells(fighter(s, id), cells):
			out.append(fighter(s, id))
	return out


## The squares of a monster's breath or burst: `effect.area` {ft, type}, a cone unless it says otherwise.
static func monster_area(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, aim: Vector2i) -> Array[Vector2i]:
	var area: Dictionary = a.get("effect", {}).get("area", {})
	return FightGrid.area(s, data, {"type": str(area.get("type", "cone")), "size": int(area.get("ft", 5))}, FightGrid.cell(f), aim, true)


## A follower caught in the hero's area thinks worse of the hero.
## Sculpt Spells (rules.combat.friendly_fire.sculpt): the caster's own side out of the area of a spell of its school, as many
## as its row says by the spell's circle, the nearest first. The targets left.
static func _sculpted(s: GameSession, data: Dictionary, sp: Dictionary, me: Dictionary, targets: Array[Dictionary], lines: Array[String]) -> Array[Dictionary]:
	var row: Dictionary = cfg(data)["friendly_fire"].get("sculpt", {})
	if row.is_empty() or str(sp.get("school_id", "")) != str(row["school"]) or not FeatureRules.has(Sheet.holder(s, me), str(row["feature"])):
		return targets
	var mine := friends_of(s, me) + [str(me["id"])]
	var spared := targets.filter(func(x: Dictionary) -> bool: return mine.has(str(x["id"])))
	spared.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return FightGrid.dist(me, a) < FightGrid.dist(me, b))
	spared = spared.slice(0, int(row.get("base", 1)) + int(sp.get("level", 0)))
	if spared.is_empty():
		return targets
	lines.append("%s: %s — вне удара" % [data["classes"]["features"].get(str(row["feature"]), {}).get("name", row["feature"]), ", ".join(spared.map(func(x: Dictionary) -> String: return str(x["name"])))])
	var left: Array[Dictionary] = []
	for x: Dictionary in targets:
		if not spared.has(x):
			left.append(x)
	return left


static func _caught_friend(s: GameSession, data: Dictionary, t: Dictionary) -> void:
	var npc := str(t.get("npc_id", ""))
	if str(t.get("side")) == "ally" and not npc.is_empty():
		s.shift_attitude(npc, int(cfg(data)["friendly_fire"]["attitude"]), data)
		s.remember(npc, "герой задел меня своим заклинанием в бою")


## Acid Arrow's rider (v0.7.13): the second turn's acid on a hit, the splash on a miss.
static func _acid_rider(s: GameSession, data: Dictionary, slot: int, t: Dictionary, landed: bool, lines: Array[String]) -> void:
	if landed:
		t["acid"] = "%dd4" % (2 + maxi(0, slot - 2))
		return
	var half := Sheet.taken(s, data, t, "acid", roll_dice(s.rng, "%dd4" % (4 + maxi(0, slot - 2))) / 2)
	lines.append("Кислотная стрела: брызги — %d (кислота)" % half)
	Harm.take(s, data, t, half, lines, "acid", false, Sheet.is_hero(caster(s)))


## A fighter thrown `feet` straight away from the caster, until a wall or a body stops it.
static func push_away(s: GameSession, data: Dictionary, t: Dictionary, feet: int) -> void:
	FightField.thrust(s, data, t, (FightGrid.cell(t) - FightGrid.cell(caster(s))).sign(), FightGrid.squares_of(data, feet), [])


## One in metal armor (Shocking Grasp): what it wears, or its armor line, names mail, plate, scale, a breastplate or splint.
static func _metal_armor(s: GameSession, data: Dictionary, t: Dictionary) -> bool:
	var text := " ".join(Sheet.template(data, t).get("equipment", [])).to_lower()
	if Sheet.is_hero(t):
		text = str(CharacterRules.item_def(s.character, data, s.items, "armor").get("id", "")).to_lower()
	return ["mail", "plate", "chain", "splint", "breastplate"].any(func(x: String) -> bool: return text.contains(x))


static func ab_name(ab: String) -> String:
	return {"str": "Сил", "dex": "Лов", "con": "Тел", "int": "Инт", "wis": "Мдр", "cha": "Хар"}.get(ab, ab)


## Empowered Spell: the damage dice once more, the better roll counts (approximated as a dice expression «max of two»).
static func _empowered(s: GameSession, dice: String) -> String:
	if str(s.combat.get("meta_now", "")) != "empowered_spell":
		return dice
	return "E%d:%s" % [maxi(1, FeatureRules.ab_mod(Sheet.holder(s, caster(s)), "cha")), dice]


## Heightened Spell (5e): one target saves with disadvantage — the first that saves against the spell, then no more.
static func _heighten(s: GameSession) -> bool:
	if str(s.combat.get("meta_now", "")) != "heightened_spell":
		return false
	s.combat["meta_now"] = ""
	return true


static func spell_dice(sp: Dictionary, slot: int, level: int) -> String:
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


## The one `f` is frightened of, when it is on the field ({} otherwise); a foe's fear with no cause is of the hero.
static func fear_source(s: GameSession, f: Dictionary) -> Dictionary:
	var me := Sheet.holder(s, f)
	if not ConditionRules.has(me, "frightened"):
		return {}
	var by := ConditionRules.caused_by(me, "frightened")
	var o := fighter(s, by)
	if o.is_empty() and not by.is_empty():
		o = fighter(s, fighter_of_npc(s, by))
	if not o.is_empty() and (Sheet.is_hero(o) or str(o.get("status")) == "active"):
		return o
	return {} if Sheet.is_hero(f) else player(s)


## The reach of a foe's blade in squares: its longest melee action; a swarm's 0 ft — its own square (v0.8.4.27.1).
static func reach_of(data: Dictionary, f: Dictionary) -> int:
	var feet := -1
	for a: Dictionary in f.get("actions", Sheet.template(data, f).get("actions", [])):
		if str(a.get("kind")) == "melee":
			feet = maxi(feet, int(a.get("reach", 5)))
	return FightGrid.squares_of(data, feet if feet >= 0 else 5)


## The square of the hero's walk nearest to a foe, NONE when no step brings the hero closer.
static func closest_stop(s: GameSession, data: Dictionary, target_id: String) -> Vector2i:
	var t := fighter(s, target_id)
	var routes := Move.routes(s, data, player(s))
	var best := FightGrid.NONE
	var near := FightGrid.dist(player(s), t)
	var cost := 1 << 20
	for at: Vector2i in FightGrid.stops(s, data, player(s), routes):
		var d := FightGrid.dist_to(t, at)
		if d < near or d == near and best != FightGrid.NONE and int(routes[at][0]) < cost:
			near = d
			cost = int(routes[at][0])
			best = at
	return best


## The foes of `f`: the hero and its allies for a foe, the foes for them.
static func foes_of(s: GameSession, f: Dictionary) -> Array[String]:
	if str(f.get("side")) != "enemy":
		return enemies(s)
	var out := allies(s)
	if int(s.character.get("hp", 0)) > 0 and not ArenaRules.watching(s):
		out.push_front(PLAYER)
	return out


## Those on its side in the fight, itself among them.
static func friends_of(s: GameSession, f: Dictionary) -> Array[String]:
	if str(f.get("side")) == "enemy":
		return enemies(s)
	var out := allies(s)
	if int(s.character.get("hp", 0)) > 0:
		out.push_front(PLAYER)
	return out


## Its walk ends here: it fell, the hero is dead, a window waits.
static func stopped(s: GameSession, f: Dictionary) -> bool:
	if str(s.combat.get("outcome", "")) == "dead" or bool(s.combat.get("halt", false)):
		return true
	return int(s.character.get("hp", 0)) <= 0 if Sheet.is_hero(f) else str(f.get("status")) != "active"


## The reach of what it holds to strike with, in squares; 0 with nothing for arm's length.
static func blade_reach(s: GameSession, data: Dictionary, f: Dictionary) -> int:
	if Sheet.is_hero(f):
		var c := s.character
		var w := weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("main_hand", "")))
		return 0 if not bool(w["melee"]) else 2 if bool(w.get("reach", false)) else 1
	return reach_of(data, f) if not _best_action(data, f, "melee").is_empty() else 0


## `f` is about to step to `next`: every foe whose reach that leaves has its attack of opportunity.
static func leaving(s: GameSession, data: Dictionary, f: Dictionary, next: Vector2i, lines: Array[String]) -> void:
	if bool(f.get("disengaged", false)) or Sheet.has_trait(s, data, f, "flyby"):
		return
	var after := f.duplicate()
	FightGrid.put(after, next)
	for id: String in foes_of(s, f):
		var o := fighter(s, id)
		var r := blade_reach(s, data, o)
		if r > 0 and blade_reaches(s, data, o, f, r) and FightGrid.dist(o, after) > r and can_react(s, data, o, f):
			o["reacted"] = true
			lines.append("%s бьёт вдогонку" % Sheet.holder(s, o)["name"])
			_opportunity(s, data, o, f, lines)
			if stopped(s, f):
				return


static func _opportunity(s: GameSession, data: Dictionary, o: Dictionary, t: Dictionary, lines: Array[String]) -> void:
	Attack.swing(s, data, o, t, Attack.blade(s, data, o), lines)


# --- grapple and shove (v0.7.7) ---------------------------------------------------------------------------

const SIZES: Array[String] = ["tiny", "small", "medium", "large", "huge", "gargantuan"]


## "" when `f` may grapple or shove `to`: a foe at arm's length, at most one size larger. Else a key.
static func why_tussle(s: GameSession, data: Dictionary, f: Dictionary, to: String) -> String:
	if not foes_of(s, f).has(to):
		return "COMBAT_BAD_TARGET"
	var t := fighter(s, to)
	if not blade_reaches(s, data, f, t):
		return "COMBAT_OUT_OF_REACH"
	return "COMBAT_TOO_BIG" if _outsized(s, data, f, t) else ""


static func _outsized(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary) -> bool:
	return SIZES.find(Sheet.size(s, data, t)) > SIZES.find(Sheet.size(s, data, f)) + 1


## The better of its Athletics and Acrobatics.
static func _tussle_bonus(s: GameSession, data: Dictionary, t: Dictionary) -> int:
	return maxi(Sheet.skill(s, data, t, "athletics"), Sheet.skill(s, data, t, "acrobatics"))


## The better of `skills` for `who`: the first on a tie.
static func better(s: GameSession, data: Dictionary, who: Dictionary, skills: Array) -> String:
	var best := str(skills[0])
	for sk: Variant in skills:
		if Sheet.skill(s, data, who, str(sk)) > Sheet.skill(s, data, who, best):
			best = str(sk)
	return best


## A contest of two (5e), each on its own road (Roll.check: statuses, Lucky, the dark): `f` rolls `skill`, `t` the better
## of `against`; one who cannot act does not resist (0). {mine, theirs, won}: a tie goes to `f`, a failed one loses. A bard
## of either side may cut the other's check with Cutting Words (v0.8.4.43.46), lines in `lines`.
static func contest(s: GameSession, data: Dictionary, f: Dictionary, skill: String, t: Dictionary, against: Array, lines: Array[String] = []) -> Dictionary:
	var r := Roll.check(s, data, f, {"skill": skill, "quiet": true})
	var mine := int(r["total"])
	var theirs := 0
	var resists := not t.is_empty() and Attack.up(s, t) and not ConditionRules.incapacitated(Sheet.holder(s, t))
	if resists:
		theirs = int(Roll.check(s, data, t, {"skill": better(s, data, t, against), "quiet": true})["total"])
	if (r["fail"] as Array).is_empty():
		var cut := {"total": mine, "ac": theirs, "nat20": false, "hit": mine >= theirs, "what": "проверка"}
		if FeatureRules.cutting_words(s, data, f, cut, "roll", lines):
			mine = int(cut["total"])
		elif resists:
			cut = {"total": theirs, "ac": mine + 1, "nat20": false, "hit": theirs > mine, "what": "проверка"}
			if FeatureRules.cutting_words(s, data, t, cut, "roll", lines):
				theirs = int(cut["total"])
	return {"mine": mine, "theirs": theirs, "won": (r["fail"] as Array).is_empty() and mine >= theirs}


## The contest of a grapple or a shove: Athletics of `f` against the better of `t`, who does not resist when it cannot act (5e:
## it fails Str / Dex). `what` says the attempt, `cond` is what it lays; "" — nothing to be immune to. True when it won.
static func tussle(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, what: String, cond: String, lines: Array[String]) -> bool:
	var me := Sheet.holder(s, f)
	var it := Sheet.holder(s, t)
	points(s, data, f)["attacked"] = true
	f["rage_kept"] = true
	lines.append_array(ConditionRules.end_invisibility_on_attack(me, data))
	var words: Array[String] = []
	var c := contest(s, data, f, "athletics", t, ["athletics", "acrobatics"], words)
	var won := bool(c["won"])
	lines.append_array(words)
	lines.append("%s %s %s: Атлетика %d против %d — %s" % [me.get("name", ""), what, it.get("name", ""), int(c["mine"]), int(c["theirs"]), "успех" if won else "не выходит"])
	Harm.retort(s, data, f, t, true, lines)  # a hand on a hot body (Heated Body, v0.8.4.27.6)
	if won and not cond.is_empty() and immune_to(data, t, cond):
		lines.append("%s: на него это не действует" % it.get("name", ""))
		return false
	return won


## The AI's grapple or shove: one who thinks and is stronger than the target, and only one that is not down already.
static func tussle_offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary], act: String, weight: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cond := "grappled" if act == "grapple" else "prone"
	if Sheet.is_hero(f) or not _intelligent(data, f):
		return out
	var mine := Sheet.skill(s, data, f, "athletics")
	for t: Dictionary in targets:
		if not _outsized(s, data, f, t) and not ConditionRules.has(Sheet.holder(s, t), cond) and not immune_to(data, t, cond) and mine > _tussle_bonus(s, data, t):
			out.append({"act": act, "to": str(t["id"]), "how": {}, "t": t, "kind": "tussle", "touch": true, "far": 1, "power": weight})
	return out


## The foe cannot get this condition (its condition immunities, v0.7.9).
static func immune_to(data: Dictionary, t: Dictionary, cond: String) -> bool:
	return (Sheet.template(data, t).get("condition_immunities", []) as Array).has(cond)


static func hero_size(s: GameSession, data: Dictionary) -> String:
	return str(data["races"]["races"].get(str(s.character.get("race", "")), {}).get("size", "medium"))


## A condition with no timer: it lasts until something ends it (standing up, the hero walking off).
static func _hold(f: Dictionary, cond: String, by: String = "") -> void:
	if not _has(f, cond):
		var e := {"condition": cond, "source": {"kind": "engine", "name": ""}}
		if not by.is_empty():
			e["by"] = by
			e["hold"] = true  # ends with the one who holds
		ConditionRules.add_effect(f, e)
	if cond == "invisible":
		FightGrid.keep_seen(f)


## Grappled by `f` now: Grappler strikes it with advantage, Damage Transfer puts half its hurt on it (v0.8.4.27.5).
static func held_by(s: GameSession, f: Dictionary, t: Dictionary) -> bool:
	return ConditionRules.effects_of(Sheet.holder(s, t), "grappled").any(func(e: Dictionary) -> bool: return str(e.get("by", "")) == str(f.get("id")))


## The fighters `f` holds grappled now, up ones only.
static func held_of(s: GameSession, f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in s.combat.get("fighters", []):
		var t := fighter(s, id)
		if id != str(f.get("id")) and not t.is_empty() and Attack.up(s, t) and held_by(s, f, t):
			out.append(t)
	return out


## `r` can strike one who leaves it (5e, v0.7.7): its reaction is unspent this round, it can act (not incapacitated, paralysed,
## stunned, asleep), is not charmed and sees `t` (not blinded, `t` not invisible). A prone or restrained one still can. The hero
## may have told itself never to.
static func can_react(s: GameSession, data: Dictionary, r: Dictionary, t: Dictionary) -> bool:
	var me := Sheet.holder(s, r)
	if bool(r.get("reacted", false)) or ConditionRules.incapacitated(me) or ConditionRules.has(me, "charmed"):
		return false
	if (Sheet.is_hero(r) and int(me.get("hp", 0)) <= 0) or FeatureRules.policy(s, r, "opportunity") == "never":
		return false
	return FightGrid.veiled(s, data, r, t).is_empty() and not ConditionRules.invisible(Sheet.holder(s, t), data)


## The rest of the turn is skipped: next fighter (the UI plays the others one by one via next_actor()). Whoever's turn the
## player plays — the hero or one of its party (v0.8.4.43.11). Returns the lines of the turn's end and a new round's start
## (reinforcements arriving).
static func end_player_turn(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	_finish(s, data, fighter(s, current(s)), lines)
	return lines


## The end of anybody's turn, one road (v0.8.4.13): darts left fly, the AI's free acts, what burns it and what it stands in
## strike, Blink, a rage with nothing done goes, repeat saves and what ran out; then the next one's turn. Lines into `lines`.
static func _finish(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var me := Sheet.holder(s, f)
	if str(f.get("status")) == "active":
		lines.append_array(volley_flush(s, data))  # darts left fly at the last target (v0.7.22.4)
		if not Sheet.is_hero(f) and not driven(s, f) and Attack.up(s, f):
			FightAI.last(s, data, f, lines)
		ConditionRules.remove(me, "mocked")
		_burn(s, data, f, lines)
		lines.append_array(SpellEffects.zone_tick(s, data, f, "end"))  # Flaming Sphere (v0.7.13.5)
		if SpellEffects.has(me, "blink") and Attack.up(s, f):  # Blink (v0.7.13.3)
			var r := Roll.d20(s.rng)
			if r >= 11:
				f["blinked"] = true
				lines.append("Мерцание: %d — %s исчезает в эфире до своего хода" % [r, me.get("name", "")])
			else:
				lines.append("Мерцание: %d — остаётся здесь" % r)
		FeatureRules.end_turn(s, data, f, lines)
		lines.append_array(ConditionRules.end_of_turn(s, data, f))
	s.combat.erase("prompt")
	_check_end(s, data, lines)
	if str(s.combat["outcome"]).is_empty():
		_advance(s, data, lines)


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
		lines.append_array(SpellEffects.zones_expire(s))  # Grease (v0.7.13.6)
		_arrivals(s, data, lines)
	s.combat["turn"] = t
	_begin_turn(s, data, lines)


# --- reinforcements (v0.6.2) ---------------------------------------------------------------------


## Enemies who join later: they come by a way in on `side` at the start of round `at`.
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
	(s.combat["incoming"] as Array).append({"at": at, "side": side, "foes": specs, "names": names})


## XP of the enemies still fighting and on the way (the master's reinforcements stay within the level's budget).
## The foes in the fight and on their way, [{xp, count}] for DifficultyRules.weigh (v0.8.4.38).
static func foes_in_play(s: GameSession, data: Dictionary) -> Array:
	var out: Array = []
	for id: String in enemies(s):
		out.append({"xp": int(Sheet.template(data, fighter(s, id))["xp"]), "count": 1})
	for w: Dictionary in s.combat.get("incoming", []):
		if bool(w.get("ally", false)):
			continue
		out.append_array(DifficultyRules.of_monsters(data, w["foes"]))
	return out


static func _arrivals(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	FightField.round_starts(s, data, lines)
	var left: Array = []
	for w: Dictionary in s.combat.get("incoming", []):
		if int(w["at"]) > int(s.combat["round"]):
			left.append(w)
			continue
		var ids := _add_foes(s, data, w["foes"], Vector2i(int(w["x"]), int(w["y"])) if w.has("x") else FightGrid.way_in(s, data, str(w["side"])), "ally" if bool(w.get("ally", false)) else "enemy")
		for id: String in ids:
			_insert_initiative(s, data, id)
		lines.append("Подкрепление %s: %s" % ["слева" if str(w["side"]) == "left" else "справа",
			", ".join(ids.map(func(id: String) -> String: return str(fighter(s, id)["name"])))])
	s.combat["incoming"] = left


## Anybody's initiative (v0.8.4.29.2): a Dexterity check on the one road of Roll.check — Lucky, exhaustion and the statuses,
## the game's difficulty for the hero.
static func initiative_of(s: GameSession, data: Dictionary, id: String) -> int:
	return int(Roll.check(s, data, fighter(s, id), {"what": "Инициатива", "ability": "dex", "quiet": true, "about": "initiative"})["total"])


## A newcomer rolls initiative and takes its place in the order (called at the start of a round, turn 0).
static func _insert_initiative(s: GameSession, data: Dictionary, id: String) -> void:
	var f := fighter(s, id)
	f["init"] = initiative_of(s, data, id)
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
	var f := fighter(s, id)
	if id == PLAYER:
		if int(s.character["hp"]) <= 0:
			_death_save(s, data, f, lines)
		elif bool(f.get("surprised", false)):
			f.erase("surprised")
			lines.append("%s застигнут врасплох и не успевает ничего сделать" % s.character["name"])
		elif ConditionRules.incapacitated(s.character):
			lines.append("%s не может действовать: %s" % [s.character["name"], ", ".join((s.character["conditions"] as Array).filter(
				func(x: Variant) -> bool: return ConditionRules.INCAPACITATING.has(str(x))).map(func(x: Variant) -> String: return ConditionRules.name_of(data, str(x)).to_lower()))])
			if _held_for_good(s):
				s.combat["outcome"] = "arena_lost" if s.combat.has("arena") else "captured" if enemies(s).any(func(id: String) -> bool: return _intelligent(data, fighter(s, id))) else "dead"
				lines.append("%s не может больше сражаться" % s.character["name"])
		else:
			return lines
		_finish(s, data, f, lines)
		return lines
	if dying(s, f):  # one of the hero's side who fell rolls as the hero does (v0.8.4.26.3)
		_death_save(s, data, f, lines)
	elif str(f.get("status")) == "active":
		if bool(f.get("surprised", false)):
			f.erase("surprised")
			lines.append("%s застигнут врасплох и не успевает ничего сделать" % f["name"])
		elif incapacitated(f):
			lines.append("%s не может действовать: %s" % [f["name"], ", ".join(foe_conditions(s, data, f))])
			MonsterRules.release(s, data, f, lines)
		elif driven(s, f):  # the player's buttons, as the hero's (v0.8.4.43.11): `actor` is it
			return lines
		elif _has(f, "charmed"):
			lines.append("%s очарован и не нападает" % f["name"])
		elif str(f.get("side")) == "ally":
			if not _gives_up(s, data, f, lines):
				_ally_turn(s, data, f, lines)
		else:
			_enemy_turn(s, data, f, lines)
			if bool(s.combat.get("halt", false)):
				return lines  # answer_reaction finishes this turn
	_finish(s, data, f, lines)
	return lines


## Acid Arrow burns at the end of its next turn (v0.7.13).
static func _burn(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	if str(f.get("status")) == "active" and f.has("acid"):
		var acid := Sheet.taken(s, data, f, "acid", roll_dice(s.rng, str(f["acid"])))
		f.erase("acid")
		lines.append("%s: кислота жжёт — %d" % [f["name"], acid])
		Harm.take(s, data, f, acid, lines, "acid")


## The death saves of `f` (v0.8.4.26.3, one road): the hero's are the fight's, one of its side who fell keeps its own.
static func saves_of(s: GameSession, f: Dictionary) -> Dictionary:
	if Sheet.is_hero(f):
		return s.combat["death_saves"]
	if not f.has("death_saves"):
		f["death_saves"] = {"ok": 0, "fail": 0}
	return f["death_saves"]


## It lies at 0 HP and still rolls death saves: the hero, or a person of its side who fell (not a foe, not one called).
static func dying(s: GameSession, f: Dictionary) -> bool:
	var down := int(s.character.get("hp", 0)) <= 0 if Sheet.is_hero(f) else str(f.get("status")) == "down"
	return down and not bool(saves_of(s, f).get("stable", false))


## Who of `f`'s side lies dying now: the hero first.
static func dying_of(s: GameSession, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if str(f.get("side")) == "enemy":
		return out
	for id: String in [PLAYER] + allies(s, false):
		if dying(s, fighter(s, id)):
			out.append(id)
	return out


## It is stable at 0 HP (Spare the Dying, a Periapt of Wound Closure, three saves): no more death saves. Lines.
static func stabilize(s: GameSession, f: Dictionary, why: String, lines: Array[String]) -> void:
	saves_of(s, f)["stable"] = true
	lines.append("%s стабилизируется%s" % [Sheet.holder(s, f).get("name", ""), (" — " + why) if not why.is_empty() else ""])


## A death save of anybody who lies dying (5e): 20 — up with 1 HP, three successes — stable, three failures — dead.
static func _death_save(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	if not dying(s, f):
		return
	var ds := saves_of(s, f)
	var me := Sheet.holder(s, f)
	var name := str(me.get("name", ""))
	if Sheet.prop(s, data, f, "wound_closure"):  # Periapt of Wound Closure (v0.7.12)
		stabilize(s, f, "Амулет закрытия ран", lines)
		return
	var beacon := SpellEffects.hero_effects(me, "death_adv")  # Beacon of Hope (v0.7.13.2)
	var r := Sheet.save(s, data, f, "", 10, "death", false, {"adv_why": [] if beacon.is_empty() else [str(beacon[0].get("source", {}).get("name", ""))]})
	var roll := int(r["nat"])  # v0.8.4.29.2: a save on the one road — Bless, Lucky, Bardic Inspiration, the game's difficulty
	if roll == 20:
		me["hp"] = 1
		ConditionRules.remove(me, "unconscious")
		ds.merge({"ok": 0, "fail": 0}, true)
		if not Sheet.is_hero(f):
			f["status"] = "active"
		lines.append(str(r["line"]))
		lines.append("%s приходит в себя с 1 HP!" % name)
		return
	if bool(r["ok"]):
		ds["ok"] = int(ds["ok"]) + 1
	else:
		ds["fail"] = int(ds["fail"]) + (2 if roll == 1 else 1)
	lines.append(str(r["line"]))
	lines.append("%s: успехов %d, провалов %d" % [name, mini(3, int(ds["ok"])), mini(3, int(ds["fail"]))])
	if int(ds["fail"]) >= 3:
		_dies(s, f, lines)
	elif int(ds["ok"]) >= 3:
		stabilize(s, f, "", lines)


## A blow at one who lies at 0 HP: a failed death save, two for a critical one; it is no longer stable.
static func blow_at_fallen(s: GameSession, f: Dictionary, crit: bool, lines: Array[String]) -> void:
	var ds := saves_of(s, f)
	ds["fail"] = int(ds["fail"]) + (2 if crit else 1)
	ds["stable"] = false
	lines.append("%s: провал спасброска от смерти (%d из 3)" % [Sheet.holder(s, f).get("name", ""), mini(3, int(ds["fail"]))])
	if int(ds["fail"]) >= 3:
		_dies(s, f, lines)


## Three failed death saves: the hero's fight is over, one of its side is dead.
static func _dies(s: GameSession, f: Dictionary, lines: Array[String]) -> void:
	if Sheet.is_hero(f):
		s.combat["outcome"] = "dead"
		return
	f["status"] = "dead"
	lines.append("%s умирает" % f["name"])


# --- enemies --------------------------------------------------------------------------------------


static func _intelligent(data: Dictionary, f: Dictionary) -> bool:
	return Sheet.is_hero(f) or int(Sheet.template(data, f)["abilities"].get("int", 1)) >= int(cfg(data)["intelligent_int"])


static func _best_action(data: Dictionary, f: Dictionary, kind: String) -> Dictionary:
	var best := {}
	for a: Dictionary in Sheet.template(data, f)["actions"]:
		var ok := str(a.get("kind")) == kind or (kind == "ranged" and a.has("range"))
		if ok and (best.is_empty() or int(a.get("to_hit", 0)) > int(best.get("to_hit", 0))):
			best = a
	return best


static func _gives_up(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> bool:
	if Acts.one("surrender").worth(s, data, f) <= 0.0:
		return false
	lines.append_array(Acts.one("surrender").go(s, data, f))
	return true


## A burning coat (alchemist's fire, v0.7.12; a liquid's `coat.burns` since v0.8.4.28.2) on anybody: it burns at the start
## of its turn until a save of its `put_out` puts it out.
static func _fire(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var h := Sheet.holder(s, f)
	var dice := LiquidRules.burning(s, h)
	if dice.is_empty() or not Attack.up(s, f):
		return
	var out: Dictionary = LiquidRules.coat_on(s, h).get("put_out", {"ability": "dex", "dc": 10})
	var burn := Sheet.taken(s, data, f, "fire", roll_dice(s.rng, dice))
	lines.append("%s горит: %d (огонь)" % [f["name"], burn])
	Harm.take(s, data, f, burn, lines, "fire")
	if Attack.up(s, f) and Sheet.saved(s, data, f, str(out["ability"]), int(out["dc"]), "", false, lines):
		LiquidRules.uncoat(h)
		lines.append("%s сбивает пламя" % f["name"])


## A foe's own turn, its start already made (_begin_turn): morale, a call for help, flight, else the AI.
static func _enemy_turn(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var p := player(s)
	if not Attack.up(s, f):
		return
	if s.combat.has("arena"):  # v0.7.45: no flight from the ring; a bout to surrender ends when a side gives up
		if _gives_up(s, data, f, lines):
			return
		f["morale"] = true
	# Morale: once, at half HP or less.
	if not bool(f.get("morale", false)) and int(f["hp"]) * 2 <= int(f["max_hp"]):
		f["morale"] = true
		if not Sheet.saved(s, data, f, "wis", int(cfg(data)["morale_dc"]), "fear", false, lines):  # its own save: Brave, the statuses
			if _intelligent(data, f) and FightGrid.touching(f, p):
				lines.append_array(Acts.one("surrender").go(s, data, f))
				return
			f["fleeing"] = true
			lines.append("%s дрогнул и пытается бежать" % f["name"])
	if bool(f.get("fleeing", false)):
		MonsterRules.release(s, data, f, lines)
		FightAI.flee(s, data, f, lines)
		return
	var help: Dictionary = s.combat.get("help", {})
	if not help.is_empty() and not bool(s.combat.get("help_called", false)) and _intelligent(data, f) and int(s.character["hp"]) > 0 \
			and (int(f["hp"]) * 2 <= int(f["max_hp"]) or enemies(s, false).size() > enemies(s).size()):
		s.combat["help_called"] = true
		add_incoming(s, data, help.get("enemies", []), int(s.combat["round"]) + int(help.get("delay", cfg(data)["help_delay"])),
			str(help.get("side", "right")))
		lines.append("%s зовёт на помощь!" % f["name"])
		return
	FightAI.turn(s, data, f, lines)


## The caster steps through the air: to `to`, or as far from its foes as it can (Misty Step).
static func _teleport(s: GameSession, data: Dictionary, feet: int, to := FightGrid.NONE) -> Array[String]:
	var me := caster(s)
	var from := FightGrid.cell(me)
	var g := FightGrid.grid(s, data)
	var n := FightGrid.squares_of(data, feet)
	var occupied := FightGrid.bodies(s)
	var best := from if to == FightGrid.NONE else to
	var score := -1
	for y: int in range(from.y - n, from.y + n + 1) if to == FightGrid.NONE else []:
		for x: int in range(from.x - n, from.x + n + 1):
			var at := Vector2i(x, y)
			if occupied.has(at) or not FightGrid.walkable(g, at) or not FightGrid.clear(g, from, at):
				continue
			var near := 1 << 20
			for id: String in foes_of(s, me):
				near = mini(near, FightGrid.dist_to(fighter(s, id), at))
			if near > score:
				score = near
				best = at
	FightGrid.put(me, best)
	if Sheet.is_hero(me):
		FightField.note_walk(s, PLAYER, [FightGrid.tag(best)])
		FightField.hero_stands(s, data)
	return ["%s переносится серебристым туманом на %d фт" % [me["name"], WalkRules.distance(from, best) * int(FightGrid.cfg(data)["ft"])]]


## A reach weapon meets a foe on its way in (v0.7.12; v0.8.4.29.2: anybody's — the hero, a companion, a foe): the reaction of
## `defender`, whose blade reaches past arm's length, one blow at `mover` before it strikes.
static func _reach_strike(s: GameSession, data: Dictionary, mover: Dictionary, defender: Dictionary, lines: Array[String]) -> void:
	var me := Sheet.holder(s, defender)
	if bool(defender.get("reacted", false)) or ConditionRules.incapacitated(me) or int(me.get("hp", 0)) <= 0 or str(defender.get("status", "active")) != "active":
		return
	if blade_reach(s, data, defender) < 2:
		return
	var b := Attack.blade(s, data, defender)
	if b.is_empty():
		return
	defender["reacted"] = true
	lines.append("%s встречает %s на подходе — %s бьёт дальше (досягаемость)" % [me.get("name", ""), mover["name"], b.get("name", "")])
	Attack.swing(s, data, defender, mover, b, lines)


## A fighter that comes beside a hidden foe finds it, whoever either is (v0.8.4.15), or feels it in its web (v0.8.4.27.3).
static func _find_hidden(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	for id: String in foes_of(s, f):
		var o := fighter(s, id)
		if bool(o.get("hidden", false)) and (FightGrid.touching(f, o) or FightField.feels(s, data, f, o)):
			o["hidden"] = false
			lines.append("%s находит, где прячется %s" % [f["name"], Sheet.holder(s, o).get("name", "")])


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
		if choice == "none" or not SpellEffects.counter(s, data, f, str(ctx["how"]["spell"]), int(ctx["circle"]), lines):
			lines.append_array(Acts.one("cast").run(s, data, f, str(ctx["to"]), (ctx["how"] as Dictionary).merged({"asked": true}, true)))
		_finish(s, data, f, lines)
		return lines
	if choice != "none":
		FeatureRules.apply_reaction(s, data, player(s), f, choice, ctx, lines)
	var p := player(s)
	Attack.land(s, data, f, p, ctx["blow"], ctx, lines)
	var plan: Array = s.combat.get("resume_plan", [])
	s.combat.erase("resume_plan")
	while not plan.is_empty() and str(s.combat.get("outcome", "")).is_empty() and int(s.character.get("hp", 0)) > 0 and Attack.up(s, f):
		var name := str(plan.pop_front())
		for x: Dictionary in Sheet.template(data, f)["actions"]:
			if str(x["name_en"]) == name:
				Attack.one(s, data, f, p, x, lines)
				break
		if bool(s.combat.get("halt", false)):
			s.combat["resume_plan"] = plan
			return lines
	_finish(s, data, f, lines)
	return lines


## The hero cannot act and nothing will end it in the fight: no time limit and no repeat save (petrified for good).
static func _held_for_good(s: GameSession) -> bool:
	for cond: String in ConditionRules.INCAPACITATING:
		for e: Dictionary in ConditionRules.effects_of(s.character, cond):
			if e.get("ends", {}).has("at") or bool(e.get("save", {}).get("repeat", false)) or bool(e.get("wake", false)):
				return false
			if not e.get("ends", {}).has("at"):
				return true
	return false


# --- allies (v0.7.22.22, AllyRules) --------------------------------------------------------------


## Adds allies to the fight; `mid_fight` — summoned on a turn: each takes its initiative at once. Ids.
static func add_allies(s: GameSession, data: Dictionary, specs: Array, mid_fight: bool = false, side: String = "ally", at: Vector2i = FightGrid.NONE) -> Array[String]:
	var ids := _add_foes(s, data, specs, at, side)
	if mid_fight:
		for id: String in ids:
			_insert_initiative(s, data, id)
			if (s.combat["order"] as Array).find(id) <= int(s.combat["turn"]):
				s.combat["turn"] = int(s.combat["turn"]) + 1  # it came in before the one acting now: the turn stays
	return ids


## A spell calls its creatures to the side of `f`, not to the hero's: they live as long as this fight.
static func summon_for(s: GameSession, data: Dictionary, f: Dictionary, spell_id: String) -> Array[String]:
	var sp := AllyRules.summon_spec(data, spell_id, s.items)
	var mon := AllyRules.monster_of(s, sp, f)
	var m: Dictionary = data["monsters"].get(mon, {})
	if m.is_empty() or bool(sp.get("carrier", false)):
		return []
	var foe := str(f.get("side")) == "enemy"
	var specs: Array = []
	for i in int(sp.get("count", 1)):
		var spec := {"monster": mon, "spell": spell_id, "called_by": str(f["id"]), "no_xp": true, "helper": bool(sp.get("helper", false))}  # a familiar called in a fight helps, as one called before it (v0.8.4.43.11)
		if not foe:
			spec["ally"] = "summon"
		specs.append(spec)
	var ids := add_allies(s, data, specs, true, "enemy" if foe else "ally", FightGrid.cell(f))
	return ["%s: %s" % [AllyRules.source_name(data, spell_id, s.items), ", ".join(Array(ids).map(func(x: String) -> String: return str(fighter(s, x)["name"])))]]


## An ally's turn: a helper (a familiar) distracts the foe nearest the hero — the hero's next attack at it has
## advantage (the Help action); the rest go for the nearest foe in sight.
static func _ally_turn(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	if not Attack.up(s, f):
		return
	if bool(f.get("helper", false)):
		var target := {}
		var dist := 9999
		for id: String in enemies(s):
			var e := fighter(s, id)
			if not bool(e.get("hidden", false)) and not _has(e, "invisible") and FightGrid.dist(e, player(s)) < dist:
				dist = FightGrid.dist(e, player(s))
				target = e
		if target.is_empty():
			lines.append("%s не видит врага" % f["name"])
		elif FightAI.go_to(s, data, f, target, lines):
			lines.append_array(Acts.one("help").go(s, data, f, str(target["id"])))
		return
	FightAI.turn(s, data, f, lines)


# --- the end --------------------------------------------------------------------------------------


static func _check_end(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	if not str(s.combat.get("outcome", "")).is_empty():
		return
	if ArenaRules.watching(s):
		ArenaRules.watch_end(s, data, lines)
		return
	if enemies(s).is_empty() and not FightField.chased(s):
		if FightField.left_foes(s):  # those who ran after the hero are beaten, the others stay where they were
			s.combat["outcome"] = "player_fled"
			lines.append("%s уходит от погони" % s.character["name"])
			return
		var truce := enemies(s, false).any(func(id: String) -> bool: return str(fighter(s, id).get("status")) == "truce")
		s.combat["outcome"] = "truce" if truce else "victory"
		lines.append("Перемирие" if truce else "Победа!")
		return
	var ds: Dictionary = s.combat["death_saves"]
	if int(s.character["hp"]) <= 0 and bool(ds.get("stable", false)) and allies(s).is_empty():
		if s.combat.has("arena"):  # v0.7.45: the blood pit — the winner finishes the downed
			s.combat["outcome"] = "dead"
			lines.append("%s лежит на песке ямы — победитель добивает его" % s.character["name"])
		elif enemies(s).any(func(id: String) -> bool: return _intelligent(data, fighter(s, id))):
			s.combat["outcome"] = "captured"
			lines.append("%s остаётся лежать — враги берут его живым" % s.character["name"])
		else:  # v0.7.9: beasts leave a still body
			s.combat["outcome"] = "left"
			lines.append("%s остаётся лежать — звери теряют к нему интерес и уходят" % s.character["name"])


## The captors are the law's guard: the hero is held, as at an arrest, not bound in their place.
static func law_captors(s: GameSession) -> bool:
	return enemies(s).any(func(id: String) -> bool: return bool(fighter(s, id).get("law", false)))


## Checks the outcome after a player action (an enemy may have fallen). Returns the lines.
static func after_player_action(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	_check_end(s, data, lines)
	return lines


## XP of a won fight (a truce too — DMG: XP for overcoming the encounter): everyone defeated, fled, surrendered or
## at peace. Things are not given here (v0.8.4.4, the author): they stay on the foes (`spoils`, CreatureRules.after_fight).
static func results(s: GameSession, data: Dictionary) -> void:
	var xp := 0
	for id: String in enemies(s, false):
		var f := fighter(s, id)
		if str(f["status"]) != "active" and not bool(f.get("no_xp", false)):
			xp += int(Sheet.template(data, f)["xp"])
	s.combat["xp"] = xp if str(s.combat["outcome"]) in ["victory", "truce"] else 0


## What a beaten foe has on it, {item: qty}: what it has (Gear) and half of what it shot; of a dead one also the hide and the meat.
static func spoils(data: Dictionary, f: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var m := Sheet.template(data, f)
	var state := str(f["status"])
	if state == "dead" and CraftRules.hides(data, m) > 0:  # v0.7.24: the hide of a beast
		out["raw_hide"] = CraftRules.hides(data, m)
	if state == "dead" and CraftRules.meat(data, m) > 0:  # v0.7.25: meat for the fire
		out["raw_meat"] = CraftRules.meat(data, m)
	if not state in ["dead", "surrendered", "unconscious"]:
		return out
	var has: Dictionary = f.get("inventory", Gear.start(data, Sheet.template_id(data, f))["inventory"])  # what it has now (v0.8.4.10)
	for got: Dictionary in [has, Gear.shot_back(data, f, rng)]:
		for item: String in got:
			out[item] = int(out.get(item, 0)) + int(got[item])
	return out


## The snapshot block for the master: the field, health words, the log of the round, the outcome.
static func snapshot(s: GameSession, data: Dictionary) -> Dictionary:
	var foes: Array[Dictionary] = []
	var p := player(s)
	for id: String in enemies(s, false):
		var f := fighter(s, id)
		foes.append({"id": id, "name": f["name"], "monster": Sheet.template(data, f)["name"], "distance_ft": FightGrid.feet(data, f, p),
			"side": "left" if int(f["x"]) < int(p["x"]) else "right" if int(f["x"]) > int(p["x"]) else "same",
			"status": f["status"], "health": health_key(f).trim_prefix("HEALTH_").to_lower(), "description": f.get("desc", ""),
			"surprised": bool(f.get("surprised", false)), "conditions": foe_conditions(s, data, f),
			"speaks": LanguageRules.foe_speech(data, f), "understands_hero": LanguageRules.foe_understands(s.character, data, f)})
	var incoming: Array[Dictionary] = []
	for w: Dictionary in s.combat.get("incoming", []):
		incoming.append({"names": w["names"], "side": str(w["side"]),
			"in_rounds": maxi(0, int(w["at"]) - int(s.combat.get("round", 1)))})
	var friends: Array[Dictionary] = []
	for id: String in allies(s, false):  # v0.7.22.22
		var a := fighter(s, id)
		friends.append({"id": id, "name": a["name"], "monster": Sheet.template(data, a)["name"], "distance_ft": FightGrid.feet(data, a, p),
			"status": a["status"], "health": health_key(a).trim_prefix("HEALTH_").to_lower() if str(a["status"]) == "active" else str(a["status"]),
			"source": str(a.get("ally", "pack")), "npc_id": str(a.get("npc_id", ""))})
	return {"round": int(s.combat.get("round", 1)), "enemies": foes, "allies": friends, "outcome": str(s.combat.get("outcome", "")),
		"player_down": int(s.character.get("hp", 1)) <= 0, "player_hidden": bool(p.get("hidden", false)),
		"incoming": incoming, "log": s.combat.get("log", [])}


# --- parley (v0.6.2) ------------------------------------------------------------------------------


## DC of a parley (v0.7.5): base + the best WIS save and per_cr × the highest CR among intelligent foes, + hard for a
## pack encounter marked so (finales, fanatics); easier for every foe out of the fight and every one below half HP.
static func parley_dc(s: GameSession, data: Dictionary) -> int:
	var foes: Array = enemies(s).map(func(id: String) -> Dictionary: return fighter(s, id))
	return parley_dc_of(data, foes, enemies(s, false).size() - enemies(s).size(), bool(s.combat.get("parley_hard", false)))


## The parley DC against `foes` — fighters or an encounter's foes before the fight (v0.8.4.19: one formula): the wisest
## thinking foe and the strongest, easier by `out` beaten and the bloodied, harder for a hard parley.
static func parley_dc_of(data: Dictionary, foes: Array, out: int, hard: bool) -> int:
	var p: Dictionary = cfg(data)["parley"]
	var wis := -5
	var cr := 0.0
	var bloodied := 0
	for f: Dictionary in foes:
		if f.has("max_hp") and int(f.get("hp", 1)) * 2 < int(f["max_hp"]):
			bloodied += 1
		if _intelligent(data, f):
			var m := Sheet.template(data, f)
			wis = maxi(wis, int(m.get("saves", {}).get("wis", CharacterRules.mod(int(m.get("abilities", {}).get("wis", 10))))))
			cr = maxf(cr, float(m.get("cr", 0)))
	var dc := int(p["base_dc"]) + wis + int(p.get("per_cr", 0)) * int(floor(cr)) + int(p["per_defeated"]) * out + int(p.get("per_bloodied", 0)) * bloodied
	if hard:
		dc += int(p.get("hard", 0))
	return maxi(int(p["min_dc"]), dc)


static func is_parley_skill(data: Dictionary, skill: String) -> bool:
	return (cfg(data)["parley"]["skills"] as Array).has(skill)


## "" when a parley try can be made: intelligent foes are still fighting and they have not stopped listening.
static func can_parley(s: GameSession, data: Dictionary, skill: String) -> String:
	if not is_parley_skill(data, skill):
		return "COMBAT_NO_PARLEY"
	if skill == "animal_handling":  # v0.7.50: only beasts are calmed
		if not enemies(s).any(func(id: String) -> bool: return str(Sheet.template(data, fighter(s, id)).get("type", "")) == "beast"):
			return "COMBAT_NO_PARLEY"
	elif not enemies(s).any(func(id: String) -> bool: return _intelligent(data, fighter(s, id))):
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
## the outcome — Intimidation: intelligent foes surrender; Persuasion: truce; either way they stay (v0.7.50.1). Beasts
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
	if skill == "animal_handling":  # v0.7.50: the beasts stop; the friendship of beasts grows from here
		for id: String in enemies(s):
			var f := fighter(s, id)
			if str(Sheet.template(data, f).get("type", "")) == "beast":
				f["status"] = "truce"
				lines.append("%s отступает и успокаивается" % f["name"])
		lines.append_array(WorldEvent.standing(s, data, str(FactionRules.cfg(data)["by_type"]["beast"]), "calm", "звери успокоены"))
		return lines
	s.combat["parley_won"] = skill  # v0.7.50.1: they stay, the faction respects the hero (FactionRules.after_fight)
	for id: String in enemies(s):
		var f := fighter(s, id)
		if not _intelligent(data, f):
			continue
		if skill == "intimidation":
			f["status"] = "surrendered"
			lines.append("%s бросает оружие и сдаётся" % f["name"])
		else:
			f["status"] = "truce"
			lines.append("%s опускает оружие" % f["name"])
	return lines


# --- the hint before the click (v0.6.2) ----------------------------------------------------------


## Percent to hit with a d20 + to_hit against AC (natural 1 misses, 20 hits), with advantage or disadvantage.
static func hit_chance(to_hit: int, ac: int, adv: bool, dis: bool) -> int:
	return Roll.chance(to_hit, ac, adv, dis)


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
static func attack_preview(s: GameSession, data: Dictionary, target_id: String, offhand: bool = false, unarmed: bool = false, throw: bool = false) -> Dictionary:
	return blow_preview(s, data, player(s), target_id, {"hand": "off" if offhand else "fists" if unarmed else "", "throw": throw})


## A blow of anybody at `target_id` before the click (v0.8.4.43.11, one road): `how` as the act «Атака» takes it — a hand of
## one with hands, an action of its template; {chance, min, max, adv, dis, sneak}, {} with nothing to strike or a save's blow.
static func blow_preview(s: GameSession, data: Dictionary, f: Dictionary, target_id: String, how: Dictionary) -> Dictionary:
	var t := fighter(s, target_id)
	var b := Attack.way(s, data, f, how)
	if t.is_empty() or b.is_empty() or str((b.get("act", {}) as Dictionary).get("kind", "")) == "save":
		return {}
	var mods := Attack.odds(s, data, f, t, b)  # the roll's own reasons and cover (v0.8.4.29.3)
	var adv := not (mods["adv"] as Array).is_empty()
	var dis := not (mods["dis"] as Array).is_empty()
	var r: Array[int] = [0, 0]
	for p: Dictionary in b.get("pieces", []):
		var pr := dice_range(str(p["dice"]))
		r = [r[0] + pr[0], r[1] + pr[1]]
	var bonus := int(b.get("bonus", 0)) + FeatureRules.rage_bonus(s, data, f, b, t)
	var sneak := FeatureRules.sneak_dice(s, data, f, b, adv, dis, t)
	var sr: Array[int] = [0, 0]
	if not sneak.is_empty():
		sr = dice_range(sneak)
	return {"chance": int(mods["chance"]), "min": maxi(1, r[0] + bonus) + sr[0],
		"max": maxi(1, r[1] + bonus) + sr[1], "adv": mods["adv"], "dis": mods["dis"], "sneak": not sneak.is_empty()}


## An engine spell at `target_id` before the click: attack — the chance to hit; save — the chance the foe fails;
## {chance, save, half, min, max, count, adv, dis}; {} for spells without a target or not resolved by the engine.
static func cast_preview(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String) -> Dictionary:
	var sp: Dictionary = data["spells"].get(spell_id, {})
	var t := fighter(s, target_id)
	if sp.is_empty() or t.is_empty() or not is_engine_spell(data, spell_id):
		return {}
	if sp.has("heal_at_slot"):  # what it gives, as a blow says its damage (v0.8.4.43.8)
		var me := caster(s)
		var hr := SpellRules.heal_range(data, Sheet.holder(s, me), spell_id, maxi(slot, int(sp.get("level", 0))), Sheet.ability_mod(s, data, me, spell_ability(s)))
		return {"heal": true, "min": hr[0], "max": hr[1], "chance": 100, "adv": [], "dis": []}
	var cspec: Dictionary = cfg(data)["condition_spells"].get(spell_id, {})
	if not cspec.is_empty():
		var conds := ", ".join((cspec["conditions"] as Array).map(func(x: String) -> String: return cond_name(data, x)))
		if cspec.has("pool"):
			var pr := dice_range(str(cspec["pool"]))
			return {"pool": true, "min": pr[0], "max": pr[1], "condition": conds, "chance": 100, "adv": [], "dis": []}
		var sab := str(sp["save"]["ability"])
		var held := Roll.chance_of(s, data, t, {"save": sab, "dc": spell_dc(s), "tag": _spell_tag(data, spell_id, cspec["conditions"])})
		return {"save": true, "condition": conds, "chance": 100 - held, "adv": [], "dis": [], "immune": not _can_be(s, data, t, cspec)}
	var level := caster_level(s)
	var dice := spell_dice(sp, maxi(slot, int(sp.get("level", 0))), level)
	var r := dice_range(dice)
	var out := {"min": r[0], "max": r[1], "count": SpellEffects.count(data, spell_id, slot, level), "adv": [], "dis": [], "save": false, "half": false, "chance": 100}
	if bool(cfg(data)["multi"].get(spell_id, {}).get("auto_hit", false)):
		return out
	if sp.has("attack"):  # the roll's own blow, reasons and cover (v0.8.4.29.3)
		out.merge(Attack.odds(s, data, player(s), t, spell_blow(s, data, spell_id, dice, player(s), t)), true)
	elif sp.has("save"):
		out["save"] = true
		out["half"] = str(sp["save"]["success"]) == "half"
		out["chance"] = 100 - Roll.chance_of(s, data, t, {"save": str(sp["save"]["ability"]), "dc": spell_dc(s), "tag": "magic"})  # its own save
	return out


# --- inspect a foe (v0.6.6) ----------------------------------------------------------------------


## The knowledge skill for a creature type (rules.combat.lore_skills): Nature for beasts, Religion for the undead…
static func lore_skill(data: Dictionary, f: Dictionary) -> String:
	var lore: Dictionary = cfg(data)["lore_skills"]
	return str(lore.get(str(Sheet.template(data, f).get("type", "")), lore["_default"]))


## DC to know a creature: 10 + its challenge (rounded up).
static func lore_dc(data: Dictionary, f: Dictionary) -> int:
	return int(cfg(data)["lore_base_dc"]) + int(ceil(float(Sheet.template(data, f).get("cr", 0))))


## The hero looks a creature over (the act «Осмотреть» in a fight, a foe's menu before it, v0.8.4.30): a knowledge check by
## its kind; a success opens the kind's numbers for good.
static func look_over(s: GameSession, data: Dictionary, t: Dictionary) -> Array[String]:
	var skill := lore_skill(data, t)
	var dc := lore_dc(data, t)
	var r := Roll.hero(s, data, {"what": "Присмотреться", "skill": skill, "dc": dc, "target_id": str(t.get("id", ""))})  # Favored Enemy by its type
	if bool(r["ok"]):
		Knows.add(s, Knows.MONSTER, str(t.get("monster", Sheet.template_id(data, t))))
	return ["%s присматривается: %s — %s %d против Сл %d — %s" % [s.character["name"], CreatureCard.name_of(s, data, t),
		TranslationServer.translate("SKILL_" + skill.to_upper()), int(r["total"]), dc,
		"теперь ясно, на что способны такие враги" if bool(r["ok"]) else "ничего толкового"]]


## The hero knows what `f` is (the one road of knowledge, v0.8.4.41): a kind looked over (`Knows.MONSTER`), or one of its own
## side — the hero, an ally of a fight, a follower, a tamed beast — seen whole.
static func known(s: GameSession, f: Dictionary) -> bool:
	var id := str(f.get("npc_id", f.get("id", "")))
	var cr: Dictionary = f.get("creature", Being.view(s, id).get("creature", {}))
	return Sheet.is_hero(f) or str(f.get("side")) == "ally" or Being.follows(s, id) or str(cr.get("state", "")) == PropertyRules.TAME \
		or Knows.has(s, Knows.MONSTER, str(f.get("monster", "")))


## The card of a known kind as lines (a fight's hover): HP (this one's), AC, speed, attacks, resistances. "" for an unknown
## one. One reader with the window: CreatureCard.
static func monster_card(s: GameSession, data: Dictionary, f: Dictionary) -> String:
	return CreatureCard.text(s, data, f)

