extends Act
## A shove instead of one attack: the same contest as a grapple. It lays the foe down, or with `how.at` pushes it 5 ft to that
## square, a dangerous one too.


func title() -> String:
	return "Сбить с ног"


func tip() -> String:
	return "Вместо одной атаки: Атлетика против Атлетики или Акробатики врага рядом. Сбитый лежит: по нему вплотную — с преимуществом, издалека — с помехой; встаёт он в свой ход"


func order() -> int:
	return 26


func aim() -> String:
	return FOE


func second() -> bool:
	return true


func squares(s: GameSession, data: Dictionary, f: Dictionary, to: String) -> Dictionary:
	var t := CombatRules.fighter(s, to)
	var out := {}
	var g := FightGrid.grid(s, data)
	var taken := FightGrid.bodies(s, to)
	for d: Vector2i in FightGrid.CIRCLE:
		var at := FightGrid.cell(t) + d
		if FightGrid.dist_to(f, at) < FightGrid.dist(f, t):
			continue  # never towards the one who shoves
		var free := true
		for c: Vector2i in FightGrid.body_at(at, int(t.get("span", 1))):
			if FightGrid.flags_at(g, c) & FightGrid.SOLID != 0 and FightGrid.flags_at(g, c) & FightGrid.PIT == 0 or taken.has(c) or FightGrid.shut(s, g, c):
				free = false  # a pit or a fire counts as free: that is why one shoves
		if free:
			out[at] = true
	return out


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "attack"


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, _how: Dictionary) -> String:
	return CombatRules.why_tussle(s, data, f, to)


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> Array[String]:
	var t := CombatRules.fighter(s, to)
	var at := FightGrid.aim_of(str(how["at"])) if how.has("at") else FightGrid.NONE
	var lines: Array[String] = []
	if not CombatRules.tussle(s, data, f, t, "толкает, чтобы сбить с ног", "" if how.has("at") else "prone", lines):
		return lines
	if how.has("at"):
		FightField.thrust(s, data, t, at - FightGrid.cell(t), 1, lines)
		return lines
	CombatRules._hold(Sheet.holder(s, t), "prone")
	if Sheet.is_hero(t):
		CharacterRules.refresh(s.character, data, s.items)
	lines.append("%s падает" % Sheet.holder(s, t)["name"])
	return lines


func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	return CombatRules.tussle_offers(s, data, f, targets, id, _weight(data))
