class_name ExplorationRules
extends RefCounted
## Exploration rules of the engine (ADR-0008 §2, ADR-0010 §6, roadmap v0.5.2):
## - a failed skill check is locked by «skill + target» (the room when no target) until a long rest; a repeat
##   returns the old result without a roll, unless the situation changed — a new source of advantage;
## - hidden things of a room (world.json `secrets`: id, dc, text, skill perception | investigation) are noticed
##   by passive Perception on entering, or found by a successful search check with total ≥ DC (Investigation
##   finds any secret, Perception only the perception ones);
##   the master sees only what was noticed or found;
## - a long rest in a safe room (`safe.rest_cost_cp`) restores HP, spell slots, half the hit dice and feature
##   uses, ends conditions and concentration, clears the locks and starts a new day;
## - a short rest (v0.6.0) anywhere outside a conversation, rules.rest.short_rests_per_day a day: hit dice the
##   player chooses, short-rest feature uses, Pact Magic slots;
## - 0 HP outside combat (decision of v0.6.0): no death — the character comes to with 1 HP and the master tells
##   what it cost (kind downed). Death saves come with combat.
## - traps (v0.6.3): a secret with `trap` {guards: the exit it guards, disarm_dc, save {ability, dc}, damage,
##   damage_type, sprung_text}. Found like any secret — the player disarms it (Sleight of Hand, thieves' tools)
##   or goes around it (Acrobatics), both against disarm_dc, a failure springs it; not found — it springs on the
##   way out. A sprung or disarmed trap is spent (s.traps). Caches: a secret with `loot` {coins_cp, items} gives
##   it once when found (s.caches_taken).

const SEARCH_SKILLS: Array[String] = ["perception", "investigation"]


static func lock_key(params: Dictionary, room_id: String) -> String:
	var target := str(params.get("target_id", "")) if params.get("target_id") != null else ""
	return "%s|%s" % [params.get("skill", ""), target if not target.is_empty() else room_id]


## The lock for these check params, or {} when the check may be rolled.
static func locked(s: GameSession, params: Dictionary, room_id: String) -> Dictionary:
	if params.get("skill") == null or str(params.get("skill", "")).is_empty():
		return {}
	var lock: Dictionary = s.locks.get(lock_key(params, room_id), {})
	if lock.is_empty():
		return {}
	var adv := str(params.get("advantage_reason", "")) if params.get("advantage_reason") != null else ""
	if not adv.is_empty() and not (lock.get("advantages", []) as Array).has(adv):
		return {}  # a new source of advantage changes the situation
	return lock


## Remembers a failed skill check (with the advantage it already used).
static func lock(s: GameSession, params: Dictionary, room_id: String, result: Dictionary) -> void:
	if params.get("skill") == null or bool(result.get("success", false)):
		return
	var key := lock_key(params, room_id)
	var prev: Dictionary = s.locks.get(key, {})
	var advantages: Array = (prev.get("advantages", []) as Array).duplicate()
	if params.get("advantage_reason") != null and not str(params["advantage_reason"]).is_empty():
		advantages.append(str(params["advantage_reason"]))
	var kept := result.duplicate()
	kept.erase("revealed")
	s.locks[key] = {"result": kept, "advantages": advantages}


static func secrets(world: Dictionary, room_id: String) -> Array:
	return world["rooms"].get(room_id, {}).get("secrets", [])


static func _reveal(s: GameSession, room_id: String, secret: Dictionary) -> bool:
	var ids: Array = s.revealed.get(room_id, [])
	if ids.has(secret["id"]):
		return false
	ids.append(str(secret["id"]))
	s.revealed[room_id] = ids
	return true


## Sneaking (v0.6.2) costs 5 of passive Perception (PHB, a stealthy pace).
const SNEAK_PASSIVE_PENALTY := 5


## Moves the player into `room_id`: visited, passive Perception against the room's perception secrets.
## Returns the texts noticed just now.
## `penalty` — passive Perception lost (TimeRules.passive_penalty: sneaking, darkness); -1 — sneaking only.
static func enter_room(s: GameSession, world: Dictionary, room_id: String, penalty: int = -1) -> Array[String]:
	s.room_id = room_id
	if not s.visited.has(room_id):
		s.visited.append(room_id)
	var out: Array[String] = []
	var passive := int(s.character.get("passive_perception", 10)) - (penalty if penalty >= 0 else (SNEAK_PASSIVE_PENALTY if s.sneaking else 0))
	for sec: Dictionary in secrets(world, room_id):
		if str(sec.get("skill", "perception")) == "perception" and passive >= int(sec["dc"]) and _reveal(s, room_id, sec):
			out.append(str(sec["text"]))
	return out


## A successful search check finds the room's secrets with DC ≤ total: Perception finds what can be noticed,
## Investigation (a thorough search) finds that too and also mechanisms and caches. Returns their texts.
static func active_reveal(s: GameSession, world: Dictionary, skill: String, total: int) -> Array[String]:
	var out: Array[String] = []
	if not SEARCH_SKILLS.has(skill):
		return out
	for sec: Dictionary in secrets(world, s.room_id):
		var needs := str(sec.get("skill", "perception"))
		if (needs == skill or skill == "investigation") and total >= int(sec["dc"]) and _reveal(s, s.room_id, sec):
			out.append(str(sec["text"]))
	return out


## Exits of a room the player can take now: a room's `closed_exits` {room_id: {when, text}} opens an exit only when
## its fact is true (QuestRules.met; v0.6.4 — the burrow under the hollow).
static func open_exits(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var closed: Dictionary = world["rooms"].get(room_id, {}).get("closed_exits", {})
	for e: Variant in world["rooms"].get(room_id, {}).get("exits", []):
		var lock: Dictionary = closed.get(str(e), {})
		if lock.is_empty() or QuestRules.met(s, lock["when"]):
			out.append(str(e))
	return out


# --- traps and caches (v0.6.3) ---------------------------------------------------------------------


static func secret_key(room_id: String, sec: Dictionary) -> String:
	return "%s:%s" % [room_id, sec["id"]]


static func is_found(s: GameSession, room_id: String, sec: Dictionary) -> bool:
	return (s.revealed.get(room_id, []) as Array).has(str(sec["id"]))


## The live trap of `room_id` that guards the exit to `to`, or {}.
static func trap_on_exit(s: GameSession, world: Dictionary, room_id: String, to: String) -> Dictionary:
	for sec: Dictionary in secrets(world, room_id):
		var t: Variant = sec.get("trap")
		if t is Dictionary and str(t.get("guards", "")) == to and not s.traps.has(secret_key(room_id, sec)):
			return sec
	return {}


## Live traps of this room the player has found: [{secret, to}].
static func found_traps(s: GameSession, world: Dictionary, room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sec: Dictionary in secrets(world, room_id):
		if sec.get("trap") is Dictionary and is_found(s, room_id, sec) and not s.traps.has(secret_key(room_id, sec)):
			out.append({"secret": sec, "to": str(sec["trap"]["guards"])})
	return out


## The trap goes off: a save (half damage on success), damage to the character. The trap is spent. Lines.
static func spring_trap(s: GameSession, data: Dictionary, room_id: String, sec: Dictionary) -> Array[String]:
	var t: Dictionary = sec["trap"]
	var c := s.character
	s.traps[secret_key(room_id, sec)] = "sprung"
	var lines: Array[String] = ["Ловушка! " + str(t.get("sprung_text", sec["text"]))]
	var dmg := CombatRules.roll_dice(s.rng, str(t.get("damage", "1d6")))
	if t.has("save"):
		var r := HeroDefense.save(s, data, str(t["save"]["ability"]), int(t["save"]["dc"]), str(t["save"].get("tag", "")))
		if bool(r["ok"]):
			dmg /= 2
		lines.append("Спасбросок " + str(r["text"]) + (", урон вдвое меньше" if bool(r["ok"]) else ""))
	var adj := HeroDefense.adjust(s, data, str(t.get("damage_type", "")), dmg)
	dmg = int(adj["damage"])
	c["hp"] = maxi(0, int(c["hp"]) - dmg)
	lines.append("−%d HP (%s%s)" % [dmg, data["misc"]["damage_types"].get(str(t.get("damage_type", "")), t.get("damage_type", "")),
		(", " + str(adj["note"])) if not str(adj["note"]).is_empty() else ""])
	lines.append_array(HeroDefense.after_damage(s, data, dmg))
	HeroDefense.relentless(s, data, lines)
	return lines


static func disarm_trap(s: GameSession, room_id: String, sec: Dictionary) -> void:
	s.traps[secret_key(room_id, sec)] = "disarmed"


## The bonus to disarm: Sleight of Hand, or DEX + proficiency with thieves' tools; without the tools in the pack —
## disadvantage. {bonus, disadvantage_reason}.
static func disarm_bonus(c: Dictionary) -> Dictionary:
	var bonus := int(c.get("skills", {}).get("sleight_of_hand", 0))
	var has_tools := int(c.get("inventory", {}).get("thieves_tools", 0)) > 0
	if has_tools and (c.get("tools", []) as Array).has("thieves_tools"):
		bonus = maxi(bonus, CharacterRules.mod(int(c["abilities"].get("dex", 10))) + int(c.get("prof_bonus", 2)))
	return {"bonus": bonus, "disadvantage_reason": "" if has_tools else "нет воровских инструментов"}


## Caches found in this room and not emptied yet give their loot. Lines.
static func take_caches(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var lines: Array[String] = []
	var c := s.character
	for sec: Dictionary in secrets(data["world"], room_id):
		var key := secret_key(room_id, sec)
		if not sec.has("loot") or not is_found(s, room_id, sec) or s.caches_taken.has(key):
			continue
		s.caches_taken.append(key)
		var loot: Dictionary = sec["loot"]
		var got: Array[String] = []
		if int(loot.get("coins_cp", 0)) > 0:
			c["gold_cp"] = int(c.get("gold_cp", 0)) + int(loot["coins_cp"])
			got.append(Money.format(int(loot["coins_cp"])))
		var items: Dictionary = loot.get("items", {})
		for id: String in items:
			c["inventory"][id] = int(c["inventory"].get(id, 0)) + int(items[id])
			got.append(ItemRules.display_name(data["items"], s.items, id) + (" ×%d" % int(items[id]) if int(items[id]) > 1 else ""))
		lines.append("Тайник: " + ", ".join(got))
	return lines


## What the player already noticed or found in a room (for the snapshot and the journal).
static func found_texts(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = s.revealed.get(room_id, [])
	for sec: Dictionary in secrets(world, room_id):
		if ids.has(sec["id"]):
			out.append(str(sec["text"]))
	return out


## {"cost_cp": n} when a long rest is possible in this room, {} otherwise.
static func rest_place(world: Dictionary, room_id: String) -> Dictionary:
	var safe: Variant = world["rooms"].get(room_id, {}).get("safe")
	if not (safe is Dictionary):
		return {}
	return {"cost_cp": int(safe.get("rest_cost_cp", 0))}


## "" when the character can take a long rest here now, otherwise a localization key.
static func can_rest(s: GameSession, world: Dictionary) -> String:
	var place := rest_place(world, s.room_id)
	if place.is_empty():
		return "REST_NOT_SAFE"
	if s.in_conversation():
		return "REST_IN_CONVERSATION"
	if int(s.character.get("gold_cp", 0)) < int(place["cost_cp"]):
		return "REST_NO_MONEY"
	return ""


## A camp (v0.7.8, the author: «a long rest with supplies from the pack, as in Baldur's Gate»): a long rest anywhere
## outside a conversation and a fight, not where a fight of the world still waits, for rules.hero_effects.camp.need
## points of food from the pack. "" or a localization key.
static func can_camp(s: GameSession, data: Dictionary) -> String:
	if s.in_conversation() or CombatRules.active(s):
		return "REST_IN_CONVERSATION"
	var enc: Dictionary = data["world"]["rooms"].get(s.room_id, {}).get("encounter", {})
	if not enc.is_empty() and not s.encounters_done.has(str(enc.get("id", ""))):
		return "REST_DANGER"
	if camp_points(data, camp_food(s.character, data)) < camp_need(data):
		return "REST_NO_FOOD"
	return ""


static func camp_need(data: Dictionary) -> int:
	return int(data["rules"]["hero_effects"]["camp"]["need"])


## The food the hero carries: {item_id: qty} of the items rules.hero_effects.camp.food knows.
static func camp_food(c: Dictionary, data: Dictionary) -> Dictionary:
	var food: Dictionary = data["rules"]["hero_effects"]["camp"]["food"]
	var out := {}
	for id: String in c.get("inventory", {}):
		if food.has(id) and int(c["inventory"][id]) > 0:
			out[id] = int(c["inventory"][id])
	return out


static func camp_points(data: Dictionary, supplies: Dictionary) -> int:
	var food: Dictionary = data["rules"]["hero_effects"]["camp"]["food"]
	var n := 0
	for id: String in supplies:
		n += int(food.get(id, 0)) * int(supplies[id])
	return n


## The supplies picked by default: the cheapest food first until the need is met (bread before rations).
static func camp_default(c: Dictionary, data: Dictionary) -> Dictionary:
	var food: Dictionary = data["rules"]["hero_effects"]["camp"]["food"]
	var have := camp_food(c, data)
	var ids: Array = have.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return int(food[a]) < int(food[b]))
	var out := {}
	var left := camp_need(data)
	for id: Variant in ids:
		while left > 0 and int(out.get(id, 0)) < int(have[id]):
			out[id] = int(out.get(id, 0)) + 1
			left -= int(food[id])
	return out


## "" when these supplies feed a camp: the hero has them and they make the need, otherwise a localization key.
static func camp_error(s: GameSession, data: Dictionary, supplies: Dictionary) -> String:
	var why := can_camp(s, data)
	if not why.is_empty():
		return why
	var have := camp_food(s.character, data)
	for id: String in supplies:
		if int(supplies[id]) < 0 or int(supplies[id]) > int(have.get(id, 0)):
			return "REST_BAD_SUPPLIES"
	return "" if camp_points(data, supplies) >= camp_need(data) else "REST_NO_FOOD"


## Applies a long rest; returns the effect lines for the chat. An inn (can_rest first) takes its price; a camp
## (`supplies`, camp_error first) eats the food. `data` = Catalog.data.
static func long_rest(s: GameSession, data: Dictionary, supplies: Dictionary = {}) -> Array[String]:
	var c := s.character
	var cost := int(rest_place(data["world"], s.room_id).get("cost_cp", 0)) if supplies.is_empty() else 0
	var lines: Array[String] = ["Долгий отдых" if supplies.is_empty() else "Долгий отдых в лагере"]
	if cost > 0:
		c["gold_cp"] = int(c["gold_cp"]) - cost
		lines.append("−" + Money.format(cost))
	var eaten: Array[String] = []
	for id: String in supplies:
		var n := int(supplies[id])
		if n <= 0:
			continue
		var left := int(c["inventory"].get(id, 0)) - n
		if left > 0:
			c["inventory"][id] = left
		else:
			(c["inventory"] as Dictionary).erase(id)
		eaten.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), n])
	if not eaten.is_empty():
		lines.append("съедено: " + ", ".join(eaten))
	c["hp"] = int(c.get("max_hp", c.get("hp", 1)))
	lines.append("HP %d/%d" % [c["hp"], c["max_hp"]])
	c["slots_used"] = [0, 0, 0, 0, 0]
	var level := int(c.get("level", 1))
	c["hit_dice_used"] = maxi(0, int(c.get("hit_dice_used", 0)) - maxi(1, level / 2))
	if not s.locks.is_empty():
		lines.append("можно снова пробовать проваленное")
	s.locks.clear()
	FeatureUses.recharge_all(c, data, "long")
	lines.append_array(_rest_ends(c, data, "long"))
	s.short_rests = 0
	s.day += 1
	return lines


## Hit dice the character can spend now.
static func hit_dice_left(c: Dictionary) -> int:
	return maxi(0, int(c.get("level", 1)) - int(c.get("hit_dice_used", 0)))


## "" when a short rest is possible now, otherwise a localization key.
static func can_short_rest(s: GameSession, data: Dictionary) -> String:
	if s.in_conversation():
		return "REST_IN_CONVERSATION"
	if s.short_rests >= int(data["rules"]["rest"]["short_rests_per_day"]):
		return "REST_SHORT_LIMIT"
	return ""


## A short rest (an hour): spends up to `dice` hit dice (each die + CON, at least 0), gives back short-rest feature
## uses and Pact Magic slots, ends short-rest conditions. Returns the chat lines.
static func short_rest(s: GameSession, data: Dictionary, dice: int, rng: RandomNumberGenerator) -> Array[String]:
	var c := s.character
	var lines: Array[String] = ["Короткий отдых"]
	var n := clampi(dice, 0, hit_dice_left(c))
	if n > 0:
		var die := int(CharacterRules.class_def(c, data).get("hit_die", 8))
		var con := CharacterRules.mod(int(c["abilities"].get("con", 10)))
		var healed := 0
		for i in n:
			healed += maxi(0, rng.randi_range(1, die) + con)
		var before := int(c["hp"])
		c["hp"] = mini(int(c["max_hp"]), before + healed)
		c["hit_dice_used"] = int(c.get("hit_dice_used", 0)) + n
		lines.append("кости хитов: %d (к%d) — +%d HP" % [n, die, int(c["hp"]) - before])
	FeatureUses.recharge_all(c, data, "short")
	for f: Variant in data["rules"]["rest"]["short_rest_slot_features"]:
		if CharacterRules.has_feature(c, str(f)):
			c["slots_used"] = [0, 0, 0, 0, 0]
			lines.append("ячейки договора восстановлены")
	lines.append_array(_rest_ends(c, data, "short"))
	s.short_rests += 1
	return lines


## Conditions and concentration a rest ends; a long rest also takes all exhaustion away (decision of the author,
## v0.7.8, ADR-0010) and gives Relentless Endurance back. Returns the lines.
static func _rest_ends(c: Dictionary, data: Dictionary, rest: String) -> Array[String]:
	var lines: Array[String] = []
	var gone := ConditionRules.clear_on_rest(c, rest)
	if not gone.is_empty():
		lines.append("прошло: " + ", ".join(gone.map(func(id: String) -> String: return ConditionRules.name_of(data, id))))
	if not str(c.get("concentration", "")).is_empty():
		c["concentration"] = ""
		c["concentration_ends"] = -1
	if rest == "long":
		if ConditionRules.exhaustion(c) > 0:
			lines.append("истощение снято")
		c["exhaustion"] = 0
		c["relentless_used"] = false
	return lines


## 0 HP outside combat (decision of v0.6.0): no death. The character comes to with 1 HP, the conversation ends,
## concentration breaks. Returns the chat lines; the master tells what it cost (kind downed).
static func knock_out(s: GameSession) -> Array[String]:
	var c := s.character
	c["hp"] = 1
	c["concentration"] = ""
	c["concentration_ends"] = -1
	return ["Без сознания", "очнулся с 1 HP"]
