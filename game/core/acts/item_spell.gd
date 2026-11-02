extends Act
## The spell of a scroll or a wand: the thing gives the spell, its DC and attack (a scroll — by the circle, DMG; a wand — its
## own); no slot is spent. A scroll beyond one's level asks for Arcana. `how.item`.


func title() -> String:
	return "Предмет с заклинанием"


func tab() -> String:
	return ""


func shown(_s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return Sheet.is_hero(f)


func cost(s: GameSession, data: Dictionary, _f: Dictionary, how: Dictionary) -> String:
	return CombatRules.spell_cost(data, str(ItemRules.consumable(data, str(how.get("item", "")), s.items).get("spell", "")))


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> String:
	var item := str(how.get("item", ""))
	var fx := ItemRules.consumable(data, item, s.items)
	if not Sheet.is_hero(f) or not fx.has("spell") or not ItemRules.can_use(s.character, data, s.items, item).is_empty():
		return "COMBAT_ITEM_CANT"
	var spell := str(fx["spell"])
	var sp: Dictionary = data["spells"].get(spell, {})
	if sp.has("heal_at_slot") or to.is_empty() or not CombatRules.is_engine_spell(data, spell):
		return ""
	var t := _foe(s, f, to)
	if t.is_empty():
		return "COMBAT_BAD_TARGET"
	if CombatRules._no_line(s, data, f, t) or CombatRules._blind_aim(s, data, spell, t, f):
		return "COMBAT_NO_LINE"
	return "COMBAT_OUT_OF_RANGE" if FightGrid.shown_dist(f, t) > maxi(1, FightGrid.squares_of(data, int(sp.get("range_ft", 0)))) else ""


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> Array[String]:
	var c := s.character
	var item := str(how["item"])
	var fx := ItemRules.consumable(data, item, s.items)
	var spell := str(fx["spell"])
	var level := int(fx.get("level", 1))
	var lines: Array[String] = ["%s: %s" % [c["name"], ItemRules.display_name(data["items"], s.items, item)]]
	lines.append_array(ItemRules.consume(c, data, s.items, item, s.rng))
	if bool(fx.get("scroll", false)):
		var read := ItemRules.read_scroll(s, data, spell, level)
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
