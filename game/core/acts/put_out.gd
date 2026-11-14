extends Act
## «Потушить» (v0.8.4.43.54, as in 5e and BG3): an action and a check of its row's ability against its DC, and the statuses whose
## row is put out by this act (`out.act`: burning) are gone, with a coat that burns. Anybody's: the hero, a companion, a foe.


func title() -> String:
	return "Потушить"


func tip() -> String:
	return "Действие: проверка Ловкости — сбить пламя с себя"


func order() -> int:
	return 28


func shown(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return not _row(s, data, f).is_empty()


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	return "COMBAT_NOT_BURNING" if _row(s, data, f).is_empty() else ""


## The `out` of the first status on `f` this act puts out, {} — none.
func _row(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var me := Sheet.holder(s, f)
	for id: Variant in me.get("conditions", []):
		var out: Variant = data["rules"]["condition_effects"].get(str(id), {}).get("out", {})
		if out is Dictionary and str((out as Dictionary).get("act", "")) == self.id:
			return out
	return {}


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	var out := _row(s, data, f)
	var me := Sheet.holder(s, f)
	var r := Roll.check(s, data, f, {"ability": str(out.get("ability", "dex")), "dc": int(out.get("dc", 10)), "what": title(), "quiet": true})
	var lines: Array[String] = []
	if bool(r["ok"]):
		for id: Variant in (me.get("conditions", []) as Array).duplicate():
			if str(data["rules"]["condition_effects"].get(str(id), {}).get("out", {}).get("act", "")) == self.id:
				ConditionRules.remove(me, str(id))
		if not LiquidRules.burning(s, data, me).is_empty():  # what still burns on it: a coat of a thing's kind
			LiquidRules.uncoat(me)
		if Sheet.is_hero(f):
			CharacterRules.refresh(me, data, s.items)
	lines.append("%s сбивает пламя: %s %d против Сл %d — %s" % [_name(s, f), CombatRules.ab_name(str(out.get("ability", "dex"))), int(r["total"]),
		int(out.get("dc", 10)), "огонь погас" if bool(r["ok"]) else "не выходит"])
	return lines


func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	return _weight(data) if not _row(s, data, f).is_empty() else 0.0


## By the moment, not the character's own: not in the book (v0.8.4.43.13).
func book() -> bool:
	return false
