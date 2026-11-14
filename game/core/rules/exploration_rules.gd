class_name ExplorationRules
extends RefCounted
## Exploration rules of the engine (ADR-0008 §2, ADR-0010 §6, roadmap v0.5.2):
## - a failed skill check is locked by «skill + target» (the room when no target) until a long rest; a repeat
##   returns the old result without a roll, unless the situation changed — a new source of advantage, or (big test,
##   v0.7.22.2-3) the state the check was rolled in: the hero's conditions and spells, the darkness of a look, the
##   listener's attitude and the charms on it (paralysis gone — the look is rolled again); a social check — also a
##   new argument of the player (`argument`, the master names it), not the same words ten times;
## - hidden things of a room (world.json `secrets`: id, dc, text, passive?, skill?) are noticed by passive Perception
##   on entering (unless `passive: false` — only a search finds it), or found by a successful search with total ≥ DC.
##   The search is one check, Perception (v0.8.4.44, the author: «Осмотреться» only describes, «Обыскать» finds both
##   what can be noticed and what is hidden): it finds any secret; a thing hidden for another skill (`skill` of
##   rules.quest_gen.hide_skills: a root in black water — Survival) is found by that skill too and never noticed in passing;
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

const SEARCH_SKILL := "perception"  ## the one search check (v0.8.4.44): «Обыскать» and the master's search
const SOCIAL_SKILLS: Array[String] = ["persuasion", "deception", "intimidation", "performance"]


## What the check depends on besides the dice (v0.7.22.3): a lock holds only while it is the same.
static func state_key(s: GameSession, data: Dictionary, params: Dictionary, listener: String = "") -> String:
	var c := s.character
	var conds: Array = (c.get("conditions", []) as Array).duplicate()
	conds.sort()
	var fx: Array = ConditionRules.effects(c).map(func(e: Dictionary) -> String: return str(e.get("source", {}).get("id", e.get("condition", ""))))
	fx.sort()
	var parts: Array[String] = [",".join(conds), ",".join(fx)]
	if str(params.get("skill", "")) == "perception":
		parts.append("dark" if TimeRules.dark(s, data) else "light")
	if not listener.is_empty():
		parts.append("%s:%d:%s" % [listener, s.attitude(listener), ",".join(SpellEffects.npc_spells(s, listener).map(func(e: Dictionary) -> String: return str(e["source"]["id"])))])
	return "|".join(parts)


static func lock_key(params: Dictionary, room_id: String) -> String:
	var target := str(params.get("target_id", "")) if params.get("target_id") != null else ""
	return "%s|%s" % [params.get("skill", ""), target if not target.is_empty() else room_id]


## The lock for these check params, or {} when the check may be rolled.
## `state` — state_key now ("" — not compared).
static func locked(s: GameSession, params: Dictionary, room_id: String, state: String = "") -> Dictionary:
	if params.get("skill") == null or str(params.get("skill", "")).is_empty():
		return {}
	var lock: Dictionary = s.locks.get(lock_key(params, room_id), {})
	if lock.is_empty():
		return {}
	var adv := str(params.get("advantage_reason", "")) if params.get("advantage_reason") != null else ""
	if not adv.is_empty() and not (lock.get("advantages", []) as Array).has(adv):
		return {}  # a new source of advantage changes the situation
	if not state.is_empty() and lock.has("state") and str(lock["state"]) != state:
		return {}  # the hero, the light or the listener changed (v0.7.22.3)
	var arg := _argument(params)
	if SOCIAL_SKILLS.has(str(params["skill"])) and not arg.is_empty() and not (lock.get("arguments", []) as Array).has(arg):
		return {}  # a new argument of the player (v0.7.22.3)
	return lock


static func _argument(params: Dictionary) -> String:
	return str(params.get("argument", "")).strip_edges().to_lower().left(120) if params.get("argument") != null else ""


## Remembers a failed skill check (with the advantage it already used).
static func lock(s: GameSession, params: Dictionary, room_id: String, result: Dictionary, state: String = "") -> void:
	if params.get("skill") == null or bool(result.get("success", false)):
		return
	var key := lock_key(params, room_id)
	var prev: Dictionary = s.locks.get(key, {})
	var advantages: Array = (prev.get("advantages", []) as Array).duplicate()
	if params.get("advantage_reason") != null and not str(params["advantage_reason"]).is_empty():
		advantages.append(str(params["advantage_reason"]))
	var arguments: Array = (prev.get("arguments", []) as Array).duplicate()
	if not _argument(params).is_empty():
		arguments.append(_argument(params))
	var kept := result.duplicate()
	kept.erase("revealed")
	s.locks[key] = {"result": kept, "advantages": advantages, "arguments": arguments}
	if not state.is_empty():
		s.locks[key]["state"] = state


static func secrets(world: Dictionary, room_id: String) -> Array:
	return world["rooms"].get(room_id, {}).get("secrets", [])


## The hiding place not yet found that holds the thing `item_id` (a quest's thing, a cache): {room, secret} or {}. Such a
## thing comes only from finding it — not given by words (v0.7.38.5); `quest` — only a quest's own hiding place, whose
## thing is unique: it is not laid in the open by a furnishing either (v0.8.4.42.10).
static func hidden_place(s: GameSession, world: Dictionary, item_id: String, quest := false) -> Dictionary:
	for rid: String in world["rooms"]:
		for sec: Dictionary in secrets(world, rid):
			if quest and not sec.has("quest"):
				continue
			if (sec.get("loot", {}).get("items", {}) as Dictionary).has(item_id) and not Knows.has(s, Knows.SECRET, rid, str(sec["id"])):
				return {"room": rid, "secret": sec}
	return {}


static func _reveal(s: GameSession, room_id: String, secret: Dictionary) -> bool:
	return Knows.add(s, Knows.SECRET, room_id, str(secret["id"]))


## Sneaking (v0.6.2) costs 5 of passive Perception (PHB, a stealthy pace).
const SNEAK_PASSIVE_PENALTY := 5


## Moves the player into `room_id`: visited, passive Perception against the room's perception secrets.
## Returns the texts noticed just now.
## `penalty` — passive Perception lost (TimeRules.passive_penalty: sneaking, darkness); -1 — sneaking only.
static func enter_room(s: GameSession, world: Dictionary, room_id: String, penalty: int = -1) -> Array[String]:
	place(s, room_id)
	var out: Array[String] = []
	var passive := int(s.character.get("passive_perception", 10)) - (penalty if penalty >= 0 else (SNEAK_PASSIVE_PENALTY if s.sneaking else 0))
	for sec: Dictionary in secrets(world, room_id):
		if not on_square(sec) and noticed_passively(sec) and passive >= int(sec["dc"]) and _reveal(s, room_id, sec):
			out.append(str(sec["text"]))
	return out


## The hero is in `room_id` now and has been there (v0.8.4.29.4: one place for a step, a fight's way out, the law's prison).
static func place(s: GameSession, room_id: String) -> void:
	s.room_id = room_id
	if not s.visited.has(room_id):
		s.visited.append(room_id)


## A trap and a cache lie on a square (v0.8.3): passive Perception finds them on the way there, not at the door.
static func on_square(sec: Dictionary) -> bool:
	return sec.get("trap") is Dictionary or sec.has("loot")


## The hero stands on `cell`: passive Perception against the traps and caches within `sight.notice` in view, what was found
## and is not emptied yet is taken. Lines.
static func notice(s: GameSession, data: Dictionary, map: Dictionary, cell: Vector2i) -> Array[String]:
	var lines: Array[String] = []
	var passive := Sheet.passive(s, data, Sheet.HERO)
	var reach := int(SightRules.cfg(data)["notice"])
	for sec: Dictionary in secrets(data["world"], s.room_id):
		if not on_square(sec) or not noticed_passively(sec) or passive < int(sec["dc"]) or is_found(s, s.room_id, sec) or s.traps.has(secret_key(s.room_id, sec)):
			continue
		var at := MapSpots.secret_cell(s, data, map, s.room_id, sec)
		if at.x >= 0 and WalkRules.distance(at, cell) <= reach and SightRules.line(map, data["layouts"], cell, at) and _reveal(s, s.room_id, sec):
			lines.append("Замечено: " + str(sec["text"]))
	lines.append_array(take_caches(s, data, s.room_id))
	return lines


## The live trap under the hero's feet that the hero does not know of, or {}.
static func trap_at(s: GameSession, data: Dictionary, map: Dictionary, cell: Vector2i) -> Dictionary:
	for sec: Dictionary in secrets(data["world"], s.room_id):
		if sec.get("trap") is Dictionary and not is_found(s, s.room_id, sec) and not s.traps.has(secret_key(s.room_id, sec)) \
				and MapSpots.secret_cell(s, data, map, s.room_id, sec) == cell:
			return sec
	return {}


## The last look before a trap on the way out, for a move that was no walk: passive Perception finds it. Its text or "".
static func approach(s: GameSession, data: Dictionary, room_id: String, sec: Dictionary) -> String:
	var passive := Sheet.passive(s, data, Sheet.HERO)
	if noticed_passively(sec) and passive >= int(sec["dc"]) and _reveal(s, room_id, sec):
		return str(sec["text"])
	return ""


## A successful search check finds the room's secrets with DC ≤ total (`found_by`). Returns their texts.
## A cache of the pack the engine gives itself (take_caches): the master is told so and gives nothing again — the server
## reads this mark (agents.CACHE_GIVEN, v0.8.4.41.1).
const CACHE_GIVEN := " (тайник: найденное движок уже выдал герою — не выдавай его снова)"


static func active_reveal(s: GameSession, world: Dictionary, skill: String, total: int) -> Array[String]:
	var out: Array[String] = []
	for sec: Dictionary in secrets(world, s.room_id):
		if found_by(sec, skill) and total >= int(sec["dc"]) and _reveal(s, s.room_id, sec):
			out.append(str(sec["text"]) + (CACHE_GIVEN if sec.has("loot") else ""))
	return out


## A secret passive Perception notices in passing: one not marked `passive: false` (only a search finds it) and hidden
## for no other skill.
static func noticed_passively(sec: Dictionary) -> bool:
	return bool(sec.get("passive", true)) and hidden_for(sec).is_empty()


## A check of `skill` finds `sec`: the search (Perception) finds any; a thing hidden for another skill — that skill too.
static func found_by(sec: Dictionary, skill: String) -> bool:
	return skill == SEARCH_SKILL or (not hidden_for(sec).is_empty() and hidden_for(sec) == skill)


## The skill a thing is hidden for besides the search (rules.quest_gen.hide_skills), "" — the search alone.
static func hidden_for(sec: Dictionary) -> String:
	var skill := str(sec.get("skill", ""))
	return "" if skill == SEARCH_SKILL else skill


# --- traps and caches (v0.6.3) ---------------------------------------------------------------------


static func secret_key(room_id: String, sec: Dictionary) -> String:
	return "%s:%s" % [room_id, sec["id"]]


static func is_found(s: GameSession, room_id: String, sec: Dictionary) -> bool:
	return Knows.has(s, Knows.SECRET, room_id, str(sec["id"]))


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


## The found live trap `id` of this room: its secret, {} — none.
static func found_trap(s: GameSession, world: Dictionary, room_id: String, id: String) -> Dictionary:
	for ft: Dictionary in found_traps(s, world, room_id):
		if str(ft["secret"]["id"]) == id:
			return ft["secret"]
	return {}


## The trap goes off: a save (half damage on success), damage to the character. The trap is spent. Lines.
static func spring_trap(s: GameSession, data: Dictionary, room_id: String, sec: Dictionary) -> Array[String]:
	var t: Dictionary = sec["trap"]
	s.traps[secret_key(room_id, sec)] = "sprung"
	var lines: Array[String] = ["Ловушка! " + str(t.get("sprung_text", sec["text"]))]
	var dmg := CombatRules.roll_dice(s.rng, str(t.get("damage", "1d6")))
	if t.has("save"):
		var r := Sheet.save(s, data, Sheet.HERO, str(t["save"]["ability"]), int(t["save"]["dc"]), str(t["save"].get("tag", "")))
		if bool(r["ok"]):
			dmg /= 2
		lines.append("Спасбросок " + str(r["text"]) + (", урон вдвое меньше" if bool(r["ok"]) else ""))
	Harm.typed(s, data, Sheet.HERO, dmg, str(t.get("damage_type", "")), lines)
	return lines


static func disarm_trap(s: GameSession, room_id: String, sec: Dictionary) -> void:
	s.traps[secret_key(room_id, sec)] = "disarmed"


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
			Ledger.add(s, int(loot["coins_cp"]), "exploration:take_caches")
			got.append(Money.format(int(loot["coins_cp"])))
		var items: Dictionary = loot.get("items", {})
		for id: String in items:
			var got_id := ItemRules.found(c, data, s.items, id, int(items[id]))  # magic comes unidentified (v0.7.12)
			got.append(ItemRules.display_name(data["items"], s.items, got_id) + (" ×%d" % int(items[id]) if int(items[id]) > 1 else ""))
		lines.append("Тайник: " + ", ".join(got))
	return lines


## What the player already noticed or found in a room (for the snapshot and the journal).
static func found_texts(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var ids := Knows.under(s, Knows.SECRET, room_id)
	for sec: Dictionary in secrets(world, room_id):
		if ids.has(str(sec["id"])):
			out.append(str(sec["text"]))
	return out


## A room the master already described today, entered again (v0.7.22.20, #8): one line of the engine — «Снова Зал
## таверны. Здесь: Бруно, Мира» — instead of a master's turn. "" when the master should describe it: the first visit
## of the day, a room still to furnish.
static func again_line(s: GameSession, data: Dictionary, room_id: String) -> String:
	if int(s.described.get(room_id, -1)) != s.day or PropRules.needs_furnish(s, room_id):
		return ""
	var world := WorldView.new(data["world"])
	var lines: Array = data["world"].get("revisit", data["rules"]["revisit"]["lines"])
	if lines.is_empty():
		return ""
	var place := str(world.room(room_id).get("name", room_id))
	var line := str(lines[absi(hash(room_id + str(s.minute))) % lines.size()]).format({"place": place})
	var who: Array = s.npcs_here(world.world, room_id).map(func(id: String) -> String: return str(world.npc_name(id)))
	for c: Dictionary in CreatureRules.here(s, room_id):
		who.append(str(c["name"]))
	return line + (" Здесь: %s." % ", ".join(who) if not who.is_empty() else "")


## {"cost_cp": n} when a long rest is possible in this room, {} otherwise.
## With the session and the data (v0.7.11) a background may make it free: an acolyte in a temple of the pack (even
## where nobody rents rooms), an entertainer after a show.
static func rest_place(world: Dictionary, room_id: String, s: GameSession = null, data: Dictionary = {}) -> Dictionary:
	var room: Dictionary = SceneRules.room(s, world, room_id)  # a variant may make it safe (v0.7.14.1)
	var free := s != null and not data.is_empty() and BackgroundRules.free_rest(s, data, room_id)
	var safe: Variant = room.get("safe")
	if s != null and not data.is_empty() and data["rules"].has("property") and not PropertyRules.bed_at(s, data, room_id).is_empty():
		return {"cost_cp": 0, "free": true, "own": true}  # v0.7.39.5: one's own bed, in any room of the place
	if s != null and not data.is_empty() and data["rules"].has("underworld") and not OrgRules.hideout_of(s, data, room_id, "rest").is_empty():
		return {"cost_cp": 0, "free": true}  # v0.7.33: the hideout's cots
	if s != null and not data.is_empty() and not BondRules.host(s, data, room_id).is_empty():  # v0.7.31: a friend's bed
		return {"cost_cp": 0, "free": true, "host": BondRules.host(s, data, room_id)}
	if s != null and not data.is_empty() and FaithRules.shelter(s, data, room_id):  # v0.7.49: the shrine's bed
		return {"cost_cp": 0, "free": true}
	if not (safe is Dictionary):
		return {"cost_cp": 0, "free": true} if free and SceneRules.tags(s, world, room_id).has("temple") else {}
	return {"cost_cp": 0 if free else int(safe.get("rest_cost_cp", 0)), "free": free}


## "" when the character can take a long rest here now, otherwise a localization key.
static func can_rest(s: GameSession, world: Dictionary, data: Dictionary = {}) -> String:
	var place := rest_place(world, s.room_id, s, data)
	if place.is_empty():
		return "REST_NOT_SAFE"
	if s.in_conversation():
		return "REST_IN_CONVERSATION"
	if int(place["cost_cp"]) > 0 and not data.is_empty() and CrimeRules.wanted_at(s, data, s.room_id):
		return "REST_WANTED"  # v0.7.22.18 (#30): no paid bed for the wanted
	if Ledger.balance(s) < int(place["cost_cp"]):
		return "REST_NO_MONEY"
	return ""


## A camp (v0.7.8, the author: «a long rest with supplies from the pack, as in Baldur's Gate»): a long rest anywhere
## outside a conversation and a fight, not where a fight of the world still waits, for rules.hero_effects.camp.need
## points of food from the pack. "" or a localization key.
static func can_camp(s: GameSession, data: Dictionary) -> String:
	if s.in_conversation() or CombatRules.active(s):
		return "REST_IN_CONVERSATION"
	if not EncounterRules.live(s, data, s.room_id).is_empty():
		return "REST_DANGER"
	if camp_points(data, camp_food(s.character, data)) < camp_need(data) and not BackgroundRules.can_forage(s, data):
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
	if supplies.has("forage"):  # an outlander finds food (v0.7.11)
		return "" if BackgroundRules.can_forage(s, data) else "REST_NO_FOOD"
	var have := camp_food(s.character, data)
	for id: String in supplies:
		if int(supplies[id]) < 0 or int(supplies[id]) > int(have.get(id, 0)):
			return "REST_BAD_SUPPLIES"
	return "" if camp_points(data, supplies) >= camp_need(data) else "REST_NO_FOOD"


## Applies a long rest; returns the effect lines for the chat. An inn (can_rest first) takes its price; a camp
## (`supplies`, camp_error first) eats the food. `data` = Catalog.data.
static func long_rest(s: GameSession, data: Dictionary, supplies: Dictionary = {}) -> Array[String]:
	var c := s.character
	var began := TimeRules.abs_minute(s)
	var cost := int(rest_place(data["world"], s.room_id, s, data).get("cost_cp", 0)) if supplies.is_empty() else 0
	var lines: Array[String] = ["Долгий отдых" if supplies.is_empty() else "Долгий отдых в лагере"]
	c["may_prepare"] = SpellRules.prepares(c, data)
	if cost > 0:
		Ledger.add(s, -cost, "exploration:long_rest")
		lines.append("−" + Money.format(cost))
	var camp_supplies := supplies.duplicate()
	var eaten: Array[String] = []
	var meal_points := camp_need(data) if supplies.has("forage") else camp_points(data, supplies)
	if supplies.has("forage"):
		c["foraged_day"] = s.day
		lines.append("еду нашёл сам — ягоды, коренья, силки")
		supplies = {}
	for id: String in supplies:
		var n := int(supplies[id])
		if n <= 0:
			continue
		ItemRules.remove(c, id, n)
		eaten.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), n])
	if not eaten.is_empty():
		lines.append("съедено: " + ", ".join(eaten))
	lines.append_array(NeedRules.rest_meal(s, data, meal_points, meal_points == 0 and supplies.is_empty()))
	var gone := Rest.long(s, data, Being.HERO)  # the hero's own, as anybody's (v0.8.4.11)
	lines.append("HP %d/%d" % [c["hp"], c["max_hp"]])
	if not s.locks.is_empty():
		lines.append("можно снова пробовать проваленное")
	s.locks.clear()
	lines.append_array(gone)
	lines.append_array(Rest.company(s, data, "long"))  # who walks with it rests with it; the world rests by its nights
	lines.append_array(ItemRules.dawn(c, data, s.items, s.rng))  # charges come back at dawn (v0.7.12)
	if not camp_supplies.is_empty():
		lines.append_array(WeatherRules.camp(s, data))  # a downpour soaks the camp, the cold and the heat (v0.7.46)
	s.short_rests = 0
	s.reward_spent = 0  # a new budget of the master's rewards (v0.7.14.3)
	s.magic_given = 0  # and of its magic things (v0.7.22.2)
	lines.append_array(TimeRules.sleep(s, data, began))  # the night passes for the world too (v0.8.4.17)
	return lines


## Hit dice the character can spend now.
static func hit_dice_left(c: Dictionary) -> int:
	return maxi(0, int(c.get("level", 1)) - Stock.spent(c, "hit_dice"))


## "" when a short rest is possible now, otherwise a localization key.
static func can_short_rest(s: GameSession, data: Dictionary) -> String:
	if s.in_conversation():
		return "REST_IN_CONVERSATION"
	if s.short_rests >= int(data["rules"]["rest"]["short_rests_per_day"]):
		return "REST_SHORT_LIMIT"
	return ""


## What one hit die of the hero heals: {die, con, mult} (Periapt of Wound Closure: twice as much, v0.7.12).
## The HP `dice` hit dice are likely to give back now (the short rest window): their mean, no more than the wounds.
static func short_rest_expect(s: GameSession, data: Dictionary, dice: int) -> int:
	var c := s.character
	var hd := Rest.hit_die(s, data, Sheet.HERO)
	return mini(int(c["max_hp"]) - int(c["hp"]), roundi(dice * maxf(0.0, int(hd["die"]) / 2.0 + 0.5 + int(hd["con"])) * int(hd["mult"])))


## A short rest (an hour): spends up to `dice` hit dice (each die + CON, at least 0), gives back short-rest feature
## uses and Pact Magic slots, ends short-rest conditions. Returns the chat lines.
static func short_rest(s: GameSession, data: Dictionary, dice: int, rng: RandomNumberGenerator) -> Array[String]:
	var c := s.character
	var lines: Array[String] = ["Короткий отдых"]
	var n := clampi(dice, 0, hit_dice_left(c))
	var pact := Stock.recharge(c, data, "slot_1") == "short"
	lines.append_array(Rest.short(s, data, Being.HERO, n, Rest.song(s, data)))  # the one rest of anybody (v0.8.4.29.4)
	if pact:
		lines.append("ячейки договора восстановлены")
	lines.append_array(Rest.company(s, data, "short", maxi(1, n)))
	lines.append_array(ItemRules.identify(c, data, s.items))  # an hour with the things names them (v0.7.12)
	s.short_rests += 1
	return lines


## 0 HP outside combat (decision of v0.6.0): no death. The character comes to with 1 HP, the conversation ends,
## concentration breaks. Returns the chat lines; the master tells what it cost (kind downed).
static func knock_out(s: GameSession) -> Array[String]:
	var c := s.character
	c["hp"] = 1
	c["concentration"] = ""
	c["concentration_ends"] = -1
	return ["Без сознания", "очнулся с 1 HP"]
