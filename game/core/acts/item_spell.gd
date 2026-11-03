extends Act
## The spell of a scroll or a wand: the thing gives the spell, its DC and attack (a scroll — by the circle, DMG; a wand — its
## own); no slot is spent. A scroll beyond one's level asks for Arcana. `how.item`. Anybody's (v0.8.4.10): the AI weighs it as
## the spell itself (Cast).


func title() -> String:
	return "Предмет с заклинанием"


func tab() -> String:
	return ""


func cost(s: GameSession, data: Dictionary, _f: Dictionary, how: Dictionary) -> String:
	return CombatRules.spell_cost(data, str(ItemRules.consumable(data, str(how.get("item", "")), s.items).get("spell", "")))


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> String:
	var item := str(how.get("item", ""))
	var fx := ItemRules.consumable(data, item, s.items)
	if not fx.has("spell") or not ItemRules.can_use(Sheet.holder(s, f), data, s.items, item).is_empty():
		return "COMBAT_ITEM_CANT"
	var spell := str(fx["spell"])
	if not data["spells"].has(spell) or not CombatRules.is_engine_spell(data, spell):
		return ""  # the master's to tell
	return str(Acts.one("cast").call("target_why", s, data, f, to, spell))


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> Array[String]:
	var c := Sheet.holder(s, f)
	var item := str(how["item"])
	var fx := ItemRules.consumable(data, item, s.items)
	var spell := str(fx["spell"])
	var level := int(fx.get("level", 1))
	var lines: Array[String] = ["%s: %s" % [f["name"] if not Sheet.is_hero(f) else c["name"], ItemRules.display_name(data["items"], s.items, item)]]
	lines.append_array(ItemRules.consume(c, data, s.items, item, s.rng))
	if bool(fx.get("scroll", false)):
		var read := ItemRules.read_scroll(s, data, spell, level, f)
		lines.append(str(read["line"]))
		if not bool(read["ok"]):
			return lines
	if spell == "identify":
		lines.append_array(ItemRules.identify(c, data, s.items))
		return lines
	var nums := ItemRules.scroll_numbers(data, level)
	var ab := str(c.get("spell_ability", ""))
	var by := {"dc": int(fx.get("dc", nums[0])), "attack": int(fx.get("attack", nums[1])), "ability": "int" if ab.is_empty() else ab}
	lines.append_array(ActionRules.cast(s, data, f, spell, level, to, by))
	f["hidden"] = false
	return lines


## A scroll or a wand of a spell the AI knows the worth of: Cast weighs it, the thing pays for it.
func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Sheet.is_hero(f) or SpellEffects.silenced(s, data, f):
		return out
	var me := Sheet.holder(s, f)
	var cast := Acts.one("cast")
	for item: String in ItemRules.belt(me, data, s.items):
		var fx := ItemRules.consumable(data, item, s.items)
		var spell := str(fx.get("spell", ""))
		if not data["spells"].has(spell) or not ItemRules.can_use(me, data, s.items, item).is_empty():
			continue
		var sp: Dictionary = data["spells"][spell]
		if SpellRules.long_cast(sp) or SpellEffects.spec(data, spell).has("reaction"):
			continue
		var how := {"item": item, "spell": spell, "slot": int(fx.get("level", sp.get("level", 1)))}
		if not CombatRules.short_of(f, cost(s, data, f, how), 1).is_empty():
			continue
		for o: Dictionary in cast.call("_ways", s, data, f, how, targets):
			o["act"] = id
			out.append(o)
	return out
