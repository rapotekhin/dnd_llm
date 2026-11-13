class_name FoodRules
extends RefCounted
## Food (roadmap v0.7.25): a perishable (an item's `spoils_days`) carries when it was got on its copy (Thing: `got`), in
## the pack, a bag or a chest alike; past its days it turns into rules.needs.spoil_to. A dish's `meal` (rules.consumables)
## gives water and temporary HP on eating, its `adv_tag` a boon for a while.


static func spoils_days(data: Dictionary, session_items: Dictionary, id: String) -> int:
	return int(ItemRules.def_of(data["items"], session_items, ItemRules.real_id(id)).get("spoils_days", 0))


## Copies not dated yet were got now; `own_only` — only the things that wind down by their own `spoils_to` (the needs off).
static func sync(s: GameSession, data: Dictionary, own_only := false) -> void:
	var now := TimeRules.abs_minute(s)
	for h: Dictionary in Thing.holders(s.character):
		for id: String in Thing.store(h):
			if spoils_days(data, s.items, id) > 0 and (not own_only or ItemRules.def_of(data["items"], s.items, ItemRules.real_id(id)).has("spoils_to")):
				Thing.stamp(h, id, Thing.count(h, id), "got", now)


## The days a perishable has left before it spoils (its oldest copy); -1 when it does not spoil.
static func days_left(s: GameSession, data: Dictionary, id: String) -> int:
	var days := spoils_days(data, s.items, id)
	if days <= 0:
		return -1
	var list := Thing.states(s.character, id).filter(func(x: Dictionary) -> bool: return x.has("got"))
	if list.is_empty():
		return days
	return maxi(0, ceili((int(list[0]["got"]) + days * 1440 - TimeRules.abs_minute(s)) / 1440.0))


## Copies past their days spoil (with the needs on) into rules.needs.spoil_to; a thing with its own `spoils_to` (a tinker's
## clockwork winds down into its parts, v0.8.4.43.46) goes by its own days whatever the needs. Lines.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var food_to := str(data["rules"].get("needs", {}).get("spoil_to", "")) if NeedRules.on(s) else ""
	sync(s, data, food_to.is_empty())
	var c := s.character
	var now := TimeRules.abs_minute(s)
	var said: Dictionary = {}  # line → names
	for h: Dictionary in Thing.holders(c):
		for id: String in h.get("copies", {}).keys():
			var days := spoils_days(data, s.items, id)
			var def := ItemRules.def_of(data["items"], s.items, ItemRules.real_id(id))
			var to := str(def.get("spoils_to", food_to))
			if days <= 0 or to.is_empty():
				continue
			var limit := roundi(days * 1440 * PetRules.spoil_mult(s, data))  # v0.7.43: a cat beside
			var gone := 0
			for i in range(Thing.states(h, id).size() - 1, -1, -1):
				var st: Dictionary = Thing.states(h, id)[i]
				if st.has("got") and now - int(st["got"]) >= limit:
					Thing.drop_at(h, id, i)
					gone += 1
			if gone > 0:
				var line := str(def.get("spoils_line", "Испортилось"))
				if not said.has(line):
					said[line] = []
				(said[line] as Array).append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), gone])
				Thing.add(h, to, gone)
	if said.is_empty():
		return []
	CharacterRules.refresh(c, data, s.items)
	var out: Array[String] = []
	for line: String in said:
		out.append("%s: %s" % [line, ", ".join(said[line])])
	return out


## The hero's perishables fresh again, as just got (Purify Food and Drink, v0.8.4.26.2). Lines.
static func freshen(s: GameSession, data: Dictionary) -> Array[String]:
	var now := TimeRules.abs_minute(s)
	var n := 0
	for h: Dictionary in Thing.holders(s.character):
		for id: String in h.get("copies", {}).keys():
			if spoils_days(data, s.items, id) > 0:
				for st: Dictionary in Thing.states(h, id):
					if st.has("got"):
						st["got"] = now
						n += 1
	return ["еда свежая: %d" % n] if n > 0 else ["испорченной еды нет"] as Array[String]


## A dish eaten by `who` (already taken from its things): its temporary HP and boon, the hero's water (v0.8.4.15: the one
## who ate it gets them). Lines.
static func meal(s: GameSession, data: Dictionary, id: String, who: Dictionary = Sheet.HERO) -> Array[String]:
	var fx := ItemRules.consumable(data, id, s.items)
	if not fx.has("meal"):
		return []
	var m: Dictionary = fx["meal"]
	var c := Sheet.holder(s, who)
	var lines: Array[String] = []
	if int(m.get("water", 0)) > 0 and NeedRules.on(s) and Sheet.is_hero(who):
		NeedRules.set_value(s, data, "water", NeedRules.value(s, data, "water") + float(m["water"]))
	if Harm.shield(data, c, int(m.get("temp_hp", 0))):
		lines.append("временные хиты: %d" % int(m["temp_hp"]))
	if fx.has("adv_tag"):
		var d := ItemRules.def_of(data["items"], s.items, ItemRules.real_id(id))
		lines.append_array(ConditionRules.cure(s, data, fx, {"kind": "item", "id": ItemRules.real_id(id), "name": str(d.get("name", id))}, who))
	return lines


## A dish eaten by «Использовать»: the hero's food points, then the meal of whoever ate it. Lines.
## The order portions of `c`'s food are eaten in (v0.8.4.29.4, one key for the hero's «Поесть» and a follower's meal): what
## spoils first, then the cheapest; foul food last.
static func portions(s: GameSession, data: Dictionary, c: Dictionary) -> Array:
	var have := NeedRules.food_items(c, data)
	var foul: Dictionary = data["rules"].get("diseases", {}).get("foul_food", {})
	var ids: Array = have.keys()
	var key := func(id: Variant) -> int:
		return int(foul.has(id)) * 1000 + int(spoils_days(data, s.items, str(id)) <= 0) * 100 + int(have[id])
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return key.call(a) < key.call(b))
	return ids


static func eat_one(s: GameSession, data: Dictionary, id: String, who: Dictionary = Sheet.HERO, portions: int = 1, tell := true) -> Array[String]:
	var lines: Array[String] = []
	var food: Dictionary = data["rules"]["hero_effects"]["camp"]["food"]
	if NeedRules.on(s) and food.has(id) and Sheet.is_hero(who):
		var v := NeedRules.value(s, data, "food") + float(food[id]) * float(NeedRules.cfg(data)["food"]["points"]) * portions
		NeedRules.set_value(s, data, "food", v)
		if tell:
			lines.append("Еда %d/100" % roundi(NeedRules.value(s, data, "food")))
	lines.append_array(meal(s, data, id, who))
	var foul: Dictionary = data["rules"].get("diseases", {}).get("foul_food", {})
	if foul.has(id):
		lines.append_array(DiseaseRules.expose(s, data, str(foul[id]["disease"]), int(foul[id]["dc"]), "Дурная еда", str(who.get("id", Being.HERO))))
	return lines
