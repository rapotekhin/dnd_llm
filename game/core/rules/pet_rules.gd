class_name PetRules
extends RefCounted
## Pets (roadmap v0.7.43). A beast of the SRD of a size and CR of rules.pets is tamed by Animal Handling against a DC
## by its CR: a wild one of the room (`state: wild` — the pack's room `beasts` or the master's `beast`) or a beaten one
## (a truce, surrendered). Food of its taste given at the taming — advantage. A tamed one is a creature `tame` of the
## hero (PropertyRules: it goes along, is fed each day, starves and leaves) with `pet: true`, the player's name and a
## closeness (`close`) grown by feeding it by hand and the master's `bond` with `creature_id`.
## What it gives is derived from its SRD template, a kind of rules.pets.kinds overrides it — each an engine effect:
## `help` — advantage on the hero's checks of those skills while it is beside him (keen senses);
## `fights` — it fights beside the hero (AllyRules through PropertyRules.fighting);
## `scout` — a flier flies over an exit not yet walked: the room behind it is known on the map with its danger;
## `spoil_mult` — food in the hero's things keeps that many times longer while it is beside him (a cat).
## Fallen in a fight it is gone for good (AllyRules), the line stays in the chronicle.

const WILD := "wild"
const SIZES := ["tiny", "small", "medium", "large", "huge", "gargantuan"]


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["pets"]


static func on(data: Dictionary) -> bool:
	return data["rules"].has("pets") and data["rules"].has("property")


## A beast of the SRD small and weak enough to tame.
static func tameable(data: Dictionary, monster: String) -> bool:
	if not on(data):
		return false
	var m: Dictionary = data["monsters"].get(monster, {})
	return str(m.get("type", "")) == "beast" and SIZES.find(str(m.get("size", ""))) >= 0 \
		and SIZES.find(str(m.get("size", ""))) <= SIZES.find(str(cfg(data)["max_size"])) and float(m.get("cr", 99)) <= float(cfg(data)["max_cr"])


## What a pet of this beast gives and eats: derived from the SRD, rules.pets.kinds over it. {} — not tameable.
static func kind(data: Dictionary, monster: String) -> Dictionary:
	if not tameable(data, monster):
		return {}
	var c := cfg(data)
	var m: Dictionary = data["monsters"][monster]
	var help: Array = []
	for t: Variant in m.get("traits", []):
		for sk: Variant in c["help_traits"].get(str((t as Dictionary).get("id", "")), []):
			if not help.has(str(sk)):
				help.append(str(sk))
	var size := str(m.get("size", "tiny"))
	var out := {"help": help, "fights": SIZES.find(size) >= SIZES.find(str(c["fights"]["min_size"])) and float(m.get("cr", 0)) >= float(c["fights"]["min_cr"]),
		"scout": int(m.get("fly", 0)) >= int(c["scout"]["min_fly"]), "spoil_mult": 1.0, "eats": c["eats_default"].duplicate(),
		"feed_cp_day": int(c["feed_cp_day"].get(size, 2))}
	out.merge(c["kinds"].get(monster, {}), true)
	out["text"] = abilities(data, out)
	return out


## «помогает: Внимательность, Выживание; дерётся рядом; разведка с воздуха» — what a kind gives, in words.
static func abilities(data: Dictionary, k: Dictionary) -> String:
	var bits: Array[String] = []
	if not (k.get("help", []) as Array).is_empty():
		bits.append("помогает: " + ", ".join((k["help"] as Array).map(func(sk: Variant) -> String: return CraftRules.tr_skill(data, str(sk)))))
	if bool(k.get("fights", false)):
		bits.append("дерётся рядом")
	if bool(k.get("scout", false)):
		bits.append("разведка с воздуха")
	if float(k.get("spoil_mult", 1.0)) > 1.0:
		bits.append("еда не портится дольше (×%s)" % str(k["spoil_mult"]))
	return "; ".join(bits) if not bits.is_empty() else "просто друг"


## The hero's pets in a room ("" — anywhere).
static func pets(s: GameSession, room_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cr: Dictionary in PropertyRules.animals(s):
		if bool(cr.get("pet", false)) and (room_id.is_empty() or PropertyRules.room_of(s, str(cr["id"])) == room_id):
			out.append(cr)
	return out


## The pets beside the hero: led or standing in his room.
static func beside(s: GameSession) -> Array[Dictionary]:
	return pets(s, s.room_id)


static func _here(s: GameSession, cid: String) -> Dictionary:
	return CreatureRules.find(s, s.room_id, cid)


# --- taming ---------------------------------------------------------------------------------------------------------


static func dc(data: Dictionary, cr: Dictionary) -> int:
	var d: Dictionary = cfg(data)["dc"]
	return int(d["base"]) + roundi(float(data["monsters"][str(cr["monster"])].get("cr", 0)) * float(d["per_cr"])) + int(d["state"].get(str(cr["state"]), 0))


## Taste groups the beast eats ↔ the hero's things: [item id] he could give it.
static func foods(s: GameSession, data: Dictionary, monster: String) -> Array[String]:
	var out: Array[String] = []
	var eats: Array = kind(data, monster).get("eats", [])
	for id: String in s.character.get("inventory", {}):
		for t: Variant in eats:
			var g: Dictionary = cfg(data)["tastes"].get(str(t), {})
			if (g.get("ids", []) as Array).has(id) and not out.has(id):
				out.append(id)
	return out


## "" or why this creature of the room cannot be tamed now (a key).
static func tame_why(s: GameSession, data: Dictionary, cid: String) -> String:
	var cr := _here(s, cid)
	if cr.is_empty():
		return "CREATURE_NONE"
	if not tameable(data, str(cr["monster"])) or not str(cr.get("npc_id", "")).is_empty():
		return "PET_NOT_TAMEABLE"
	if not str(cr["state"]) in [WILD, "truce", "surrendered"]:
		return "PET_NOT_NOW"
	if CreatureRules.foreign(cr):
		return "PET_FOREIGN"
	if int(cr.get("tame_day", -1)) == s.day:
		return "PET_TRIED_TODAY"
	return ""


## The taming roll (tame_why first; the caller passes the minutes). `food` — a thing of its taste given (advantage).
## {lines, ok}.
static func tame(s: GameSession, data: Dictionary, cid: String, food: String) -> Dictionary:
	var cr := _here(s, cid)
	var skill := str(cfg(data)["skill"])
	var given := not food.is_empty() and foods(s, data, str(cr["monster"])).has(food)
	if given:
		ItemRules._remove_one(s.character, food)
	var mods := ConditionRules.check_mods(s.character, data, {"skill": skill})
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := FeatureRules.hero_d20(s, given, dis)
	var nat: int = rolls.max() if given and not dis else rolls.min() if dis and not given else rolls[0]
	var b := int(s.character.get("skills", {}).get(skill, 0)) + DifficultyRules.bonus(s, data)
	var d := dc(data, cr)
	var parts := RollParts.skill(s, data, skill)
	RollParts.note(s, "Приручение", rolls, nat, parts, b, d)
	var ok := nat == 20 or (nat != 1 and nat + b >= d)
	var lines: Array[String] = ["Приручение: %s %d + %d = %d против Сл %d%s — %s" % [CraftRules.tr_skill(data, skill), nat, b, nat + b, d,
		" (угощение: %s)" % ItemRules.display_name(data["items"], s.items, food) if given else "", "успех" if ok else "провал"]]
	cr["tame_day"] = s.day
	if ok:
		for k: String in ["bound", "waiting"]:
			cr.erase(k)
		cr.merge({"state": PropertyRules.TAME, "owner": OwnerRules.HERO, "led": true, "pet": true, "close": 1 + (1 if given else 0),
			"fed_day": s.day, "since": TimeRules.abs_minute(s), "xp_given": true}, true)
		lines.append("%s — теперь ваш питомец: идёт с вами; имя — в окне «Питомец»" % cr["name"])
		lines.append_array(FactionRules.on_source(s, data, str(FactionRules.cfg(data)["by_type"]["beast"]), "tame", "приручён зверь"))  # v0.7.50
	elif nat + b <= d - int(cfg(data)["flee_margin"]) or nat == 1:
		(s.creatures[s.room_id] as Array).erase(cr)
		lines.append("%s шарахается и убегает" % cr["name"])
	else:
		lines.append("%s не подпускает — завтра можно снова" % cr["name"])
	return {"lines": lines, "ok": ok}


# --- care -----------------------------------------------------------------------------------------------------------


static func pet_why(s: GameSession, cid: String) -> String:
	var cr := _here(s, cid)
	return "CREATURE_NONE" if cr.is_empty() or not bool(cr.get("pet", false)) else ""


static func rename(s: GameSession, cid: String, name: String) -> Array[String]:
	var cr := _here(s, cid)
	var old := str(cr["name"])
	cr["name"] = name.strip_edges().left(30)
	cr["named"] = true
	return ["%s теперь зовут: %s" % [old, cr["name"]]]


## "" or why the pet would not take this thing from the hand now.
static func feed_why(s: GameSession, data: Dictionary, cid: String, food: String) -> String:
	var why := pet_why(s, cid)
	if not why.is_empty():
		return why
	var cr := _here(s, cid)
	if not foods(s, data, str(cr["monster"])).has(food):
		return "PET_NOT_ITS_FOOD"
	if int(cr.get("hand_day", -1)) == s.day:
		return "PET_FED_TODAY"
	return ""


## Fed by hand once a day: the day's meal and closer by close.feed.
static func feed(s: GameSession, data: Dictionary, cid: String, food: String) -> Array[String]:
	var cr := _here(s, cid)
	ItemRules._remove_one(s.character, food)
	cr["hand_day"] = s.day
	cr["fed_day"] = s.day
	cr["hungry"] = 0
	var before := int(cr.get("close", 0))
	cr["close"] = mini(int(cfg(data)["close"]["max"]), before + int(cfg(data)["close"]["feed"]))
	return ["%s ест с руки: %s%s" % [cr["name"], ItemRules.display_name(data["items"], s.items, food),
		" — близость %d" % int(cr["close"]) if int(cr["close"]) > before else ""]]


## The day's meal of a pet beside the hero from his things of its taste (PropertyRules._animals asks first). true — eaten.
static func eat(s: GameSession, data: Dictionary, cr: Dictionary) -> bool:
	if not bool(cr.get("pet", false)) or PropertyRules.room_of(s, str(cr["id"])) != s.room_id:
		return false
	var f := foods(s, data, str(cr["monster"]))
	if f.is_empty():
		return false
	ItemRules._remove_one(s.character, f[0])
	return true


## Days of hunger a pet bears before it leaves: rules.property.starve_days and a day for each close.stay_per.
static func starve_days(data: Dictionary, cr: Dictionary) -> int:
	var base := int(data["rules"]["property"]["starve_days"])
	if not bool(cr.get("pet", false)):
		return base
	return base + int(cr.get("close", 0)) / maxi(1, int(cfg(data)["close"]["stay_per"]))


# --- what it gives --------------------------------------------------------------------------------------------------


## The pet beside the hero that helps a check of `skill`: its name (the advantage's reason) or "".
static func helper(s: GameSession, data: Dictionary, skill: String) -> String:
	if not on(data) or skill.is_empty():
		return ""
	for cr: Dictionary in beside(s):
		if int(cr.get("close", 0)) >= int(cfg(data)["close"]["help_from"]) and (kind(data, str(cr["monster"])).get("help", []) as Array).has(skill):
			return "помощь: %s" % cr["name"]
	return ""


## How many times longer food keeps in the hero's things: the best pet beside him.
static func spoil_mult(s: GameSession, data: Dictionary) -> float:
	var m := 1.0
	if not on(data):
		return m
	for cr: Dictionary in beside(s):
		m = maxf(m, float(kind(data, str(cr["monster"])).get("spoil_mult", 1.0)))
	return m


## The rooms behind the exits of the hero's room not yet walked or scouted.
static func scout_targets(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var scouted: Array = s.character.get("scouted", [])
	for e: String in ExplorationRules.open_exits(s, data["world"], s.room_id):
		if not s.visited.has(e) and not scouted.has(e) and data["world"]["rooms"].has(e):
			out.append(e)
	return out


static func scout_why(s: GameSession, data: Dictionary, cid: String, room: String) -> String:
	var why := pet_why(s, cid)
	if not why.is_empty():
		return why
	var cr := _here(s, cid)
	if not bool(kind(data, str(cr["monster"])).get("scout", false)):
		return "PET_NO_SCOUT"
	if int(cr.get("scout_day", -1)) == s.day and int(cr.get("scouts", 0)) >= int(cfg(data)["scout"]["per_day"]):
		return "PET_SCOUT_TIRED"
	if not scout_targets(s, data).has(room):
		return "PET_SCOUT_NO_WAY"
	return ""


## The flier over `room`: the room known on the map (c.scouted), who is there and the danger. Lines.
static func scout(s: GameSession, data: Dictionary, cid: String, room: String) -> Array[String]:
	var cr := _here(s, cid)
	if int(cr.get("scout_day", -1)) != s.day:
		cr["scout_day"] = s.day
		cr["scouts"] = 0
	cr["scouts"] = int(cr["scouts"]) + 1
	var scouted: Array = s.character.get("scouted", [])
	scouted.append(room)
	s.character["scouted"] = scouted
	var world := WorldView.new(data["world"])
	var seen: Array[String] = []
	var enc: Dictionary = world.room(room).get("encounter", {})
	if not enc.is_empty() and not s.encounters_done.has(str(enc.get("id", ""))):
		seen.append("опасность — " + ", ".join((enc.get("enemies", []) as Array).map(func(e: Variant) -> String:
			var en: Dictionary = e
			return "%s%s" % [en.get("name", data["monsters"].get(str(en.get("monster", "")), {}).get("name", "?")), " ×%d" % int(en["count"]) if int(en.get("count", 1)) > 1 else ""])))
	var people: Array = s.npcs_here(data["world"], room).map(func(n: String) -> String: return str(world.npc(n).get("name", n)))
	if not people.is_empty():
		seen.append("люди: " + ", ".join(people))
	var beasts: Array = CreatureRules.here(s, room).map(func(c: Variant) -> String: return str((c as Dictionary)["name"]))
	if not beasts.is_empty():
		seen.append("звери: " + ", ".join(beasts))
	return ["%s облетает «%s» и возвращается: %s" % [cr["name"], world.room(room).get("name", room), "; ".join(seen) if not seen.is_empty() else "тихо, никого"]]


# --- the world's beasts ---------------------------------------------------------------------------------------------


static func _wild(s: GameSession, data: Dictionary, room: String, monster: String, cause: String) -> Dictionary:
	s.creature_counter += 1
	var m: Dictionary = data["monsters"][monster]
	var cr := {"id": "c%d" % s.creature_counter, "name": str(m["name"]), "monster": monster, "state": WILD, "bound": false, "led": false,
		"since": TimeRules.abs_minute(s), "hp": int(m["hp"]), "max_hp": int(m["hp"]), "xp_given": false}
	if not cause.is_empty():
		cr["cause"] = cause
	var list: Array = s.creatures.get(room, [])
	list.append(cr)
	s.creatures[room] = list
	return cr


## A pack room's `beasts` (wild ones to tame) come once, on the first visit. Lines — none (they are on the panel).
static func seed(s: GameSession, data: Dictionary, room: String) -> void:
	if not on(data):
		return
	var gen := WorldGen.generated(s)
	var done: Array = gen.get("beasts_seeded", [])
	if done.has(room):
		return
	var list: Array = WorldView.new(data["world"]).room(room).get("beasts", [])
	if list.is_empty():
		return
	done.append(room)
	gen["beasts_seeded"] = done
	for m: Variant in list:
		if tameable(data, str(m)):
			_wild(s, data, room, str(m), "")


## The master's `beast`: a wild beast to tame appears in the scene for a cause. {plan, summary} or {reason}.
static func plan_beast(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var monster := str(e.get("monster", ""))
	if not tameable(data, monster):
		return {"reason": "monster — зверь SRD (type beast) размером до %s и CR до %s" % [cfg(data)["max_size"], cfg(data)["max_cr"]]}
	var cause := str(e.get("cause", "")).strip_edges() if e.get("cause") != null else ""
	if cause.length() < 8:
		return {"reason": "нужна cause — откуда зверь в этом месте (от 8 знаков)"}
	var room := str(e.get("room_id", "")) if e.get("room_id") != null and not str(e.get("room_id", "")).is_empty() else s.room_id
	if room != s.room_id:
		return {"reason": "зверь появляется только в сцене героя"}
	var gen := WorldGen.generated(s)
	if int(gen.get("beast_day", -1)) == s.day and int(gen.get("beasts_today", 0)) >= int(cfg(data)["make"]["per_day"]):
		return {"reason": "сегодня зверей для приручения уже хватит — завтра"}
	if WorldView.new(data["world"]).room(room).get("indoor", false) and SIZES.find(str(data["monsters"][monster].get("size", ""))) > SIZES.find("small"):
		return {"reason": "крупный зверь под крышей — только снаружи"}
	return {"plan": {"monster": monster, "room": room, "cause": cause.left(80)}, "summary": "Здесь: %s — можно приручить" % data["monsters"][monster]["name"]}


static func apply_beast(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	if int(gen.get("beast_day", -1)) != s.day:
		gen["beast_day"] = s.day
		gen["beasts_today"] = 0
	gen["beasts_today"] = int(gen["beasts_today"]) + 1
	var cr := _wild(s, data, str(plan["room"]), str(plan["monster"]), str(plan["cause"]))
	return ["Здесь %s — дикий, но не нападает (кнопка «Приручить»)" % cr["name"]]


## The master's `bond` with a pet of the scene: closeness ±close.scene_max, once a day. {plan, summary} or {reason}.
static func plan_bond(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var cid := str(e.get("creature_id", ""))
	var cr := _here(s, cid)
	if cr.is_empty() or not bool(cr.get("pet", false)):
		return {"reason": "creature_id — питомец героя в сцене"}
	var delta := int(e.get("delta", 0)) if e.get("delta") != null else 0
	var mx := int(cfg(data)["close"]["scene_max"])
	if delta == 0 or absi(delta) > mx:
		return {"reason": "delta питомцу — от −%d до +%d, не 0" % [mx, mx]}
	if int(cr.get("bond_day", -1)) == s.day:
		return {"reason": "сцена с %s сегодня уже была — завтра" % cr["name"]}
	var why := str(e.get("reason", "")).strip_edges() if e.get("reason") != null else ""
	if why.is_empty():
		return {"reason": "нужно reason — чем сцена сблизила или оттолкнула"}
	return {"plan": {"creature_id": cid, "delta": delta, "reason": why.left(80)}, "summary": "%s: близость %+d (%s)" % [cr["name"], delta, why.left(80)]}


static func apply_bond(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var cr := _here(s, str(plan["creature_id"]))
	if cr.is_empty():
		return []
	cr["bond_day"] = s.day
	cr["close"] = clampi(int(cr.get("close", 0)) + int(plan["delta"]), 0, int(cfg(data)["close"]["max"]))
	return ["%s — близость %d" % [cr["name"], int(cr["close"])]]


# --- words ----------------------------------------------------------------------------------------------------------


## «Рыжик (Кошка) — близость 3 из 10; помогает: Внимательность; голоден 1 дн.» — for the panel and the master.
static func text(data: Dictionary, cr: Dictionary) -> String:
	var k := kind(data, str(cr["monster"]))
	var bits: Array[String] = ["близость %d из %d" % [int(cr.get("close", 0)), int(cfg(data)["close"]["max"])], str(k.get("text", ""))]
	if int(cr.get("hungry", 0)) > 0:
		bits.append("голоден %d дн. (уйдёт после %d)" % [int(cr["hungry"]), starve_days(data, cr)])
	var kind_name := str(data["monsters"].get(str(cr["monster"]), {}).get("name", ""))
	return "%s%s — %s" % [cr["name"], " (%s)" % kind_name if bool(cr.get("named", false)) else "", "; ".join(bits)]
