class_name Attack
extends RefCounted
## One attack of anybody at anybody (v0.8.4.8, ADR-0016): the hero, a person, a foe, a summoned creature, on either side. A blow is
## a plain dictionary made by `of_weapon`, `of_action` or `of_spell`, so a sword in the hero's hands, a wolf's bite and a Fire Bolt
## go one road: why it has advantage, what stops it, the roll, what turns it, the damage, what it lays on the target. What a class
## adds to a weapon's blow is on this road too (v0.8.4.9): `opts` of a blow — stunning, open_hand, no_horde.


## A weapon of `CombatRules.weapon_profile`, or what a button asks about a weapon.
static func of_weapon(w: Dictionary) -> Dictionary:
	var b := w.duplicate()
	if w.has("dice"):
		b["pieces"] = [{"dice": str(w["dice"]), "type": str(w["type"])}]
	b["reach"] = 2 if bool(w.get("reach", false)) else 1
	b["weapon"] = true
	return b


## An action of an SRD template.
static func of_action(data: Dictionary, f: Dictionary, a: Dictionary) -> Dictionary:
	var plus := int(SpellEffects.boon(f, "weapon_plus", 0))
	var pieces: Array = []
	var hurt := a.has("bloodied") and int(f.get("hp", 1)) * 2 <= int(f.get("max_hp", 0))  # a swarm at half its HP bites less (v0.8.4.27.1)
	for d: Dictionary in a.get("bloodied" if hurt else "damage", []):
		pieces.append({"dice": str(d["dice"]), "type": str(d.get("type", ""))})
	return {"name": str(a.get("name", "")), "to_hit": int(a.get("to_hit", 0)) + plus, "pieces": pieces, "bonus": plus, "melee": str(a.get("kind")) == "melee",
		"reach": FightGrid.squares_of(data, int(a.get("reach", 5))), "range": a.get("range", []), "weapon": true, "act": a,  # 0 ft — in its own square
		"ammo": str(ItemRules.cfg(data)["ammo"].get(str(a.get("item", "")), "")), "magical": bool(a.get("magical", false)), "silvered": bool(a.get("silvered", false))}


## A spell's attack roll; `dtype` "" — a roll with no damage of its own.
static func of_spell(name: String, to_hit: int, dice: String, bonus: int, dtype: String, melee: bool, feet: int) -> Dictionary:
	return {"name": name, "to_hit": to_hit, "pieces": [{"dice": dice, "type": dtype}], "bonus": bonus, "melee": melee, "reach": 1, "range": [feet, feet],
		"magical": true, "str_based": false}


## What `how` strikes with: an action of its template by name, a hand of the hero, what it has at arm's length. {} with nothing.
## `how.throw` — a weapon that is both thrown and swung goes thrown, even at arm's length (v0.8.4.31: two buttons).
static func way(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary) -> Dictionary:
	var b := {}
	if how.has("action"):
		for a: Dictionary in Sheet.template(data, f).get("actions", []):
			if str(a.get("name_en")) == str(how["action"]):
				b = of_action(data, f, a)
	else:
		b = of_weapon(CombatRules.hand_profile(s, data, str(how.get("hand", "")))) if Sheet.is_hero(f) else blade(s, data, f)
	if bool(how.get("throw", false)) and not b.is_empty():
		b["thrown"] = true
	return b


## The weapon is both swung and thrown: a melee one with a range.
static func throwable(b: Dictionary) -> bool:
	return bool(b.get("melee", false)) and not (b.get("range", []) as Array).is_empty()


## The blow it strikes with at arm's length: {} with nothing for it.
static func blade(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	if Sheet.is_hero(f):
		var c := s.character
		return of_weapon(CombatRules.weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("main_hand", ""))))
	var a := CombatRules._best_action(data, f, "melee")
	return {} if a.is_empty() else of_action(data, f, a)


## The blow does not come from arm's length: a shot, a throw.
static func shot(f: Dictionary, t: Dictionary, b: Dictionary) -> bool:
	return bool(b.get("thrown", false)) or not bool(b.get("melee", false)) or FightGrid.dist(f, t) > maxi(1, int(b.get("reach", 1)))


static func up(s: GameSession, t: Dictionary) -> bool:
	return int(s.character.get("hp", 0)) > 0 if Sheet.is_hero(t) else str(t.get("status")) == "active"


## Why the blow has advantage or disadvantage now: {"adv": [reasons], "dis": [reasons], "crit": a hit is critical}.
static func mods(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary) -> Dictionary:
	var me := Sheet.holder(s, f)
	var it := Sheet.holder(s, t)
	var d := FightGrid.dist(f, t)
	var far := shot(f, t, b)
	var by_status := ConditionRules.attack(data, me, it, d <= 1)
	var adv: Array[String] = []
	var dis: Array[String] = []
	adv.assign(by_status["adv"])
	dis.assign(by_status["dis"])
	var traits := MonsterRules.attack_mods(s, data, f, t, not far)
	adv.append_array(traits["adv"])
	dis.append_array(traits["dis"])
	if bool(f.get("hidden", false)):
		adv.append("вы спрятаны")
	if ConditionRules.invisible(me, data) and not SpellEffects.has(it, "see_invisible"):
		adv.append("вы невидимы")
	if ConditionRules.invisible(it, data) and not SpellEffects.has(me, "see_invisible") and not ConditionRules.has(it, "outlined"):
		dis.append("цель невидима")
	if SpellEffects.has_next_attack_adv(me):
		adv.append("Верный удар")
	if t.has("x") and not str(CombatRules.sight_mods(s, data, f, t)["adv"]).is_empty():
		adv.append("вас не видно")
	if t.has("x") and not ConditionRules.has(me, "blinded"):  # a Fog Cloud or Darkness: the target is not seen (v0.8.4.1)
		var blind := str(CombatRules.sight_mods(s, data, f, t)["dis"])
		if not blind.is_empty():
			dis.append(blind)
	if bool(t.get("dodging", false)) and up(s, t) and not ConditionRules.incapacitated(it):
		dis.append("цель уклоняется")
	if bool(t.get("hidden", false)):
		dis.append("цель спряталась")
	if bool(t.get("reckless", false)):
		adv.append("цель безрассудна")
	if bool(f.get("reckless", false)) and not far and bool(b.get("str_based", true)):
		adv.append("безрассудная атака")
	if Sheet.has_trait(s, data, f, "pack_tactics") and CombatRules.friend_beside(s, f, t):
		adv.append("стайная тактика")
	var dark_me := CombatRules.dark_for(s, data, f)
	var dark_it := CombatRules.dark_for(s, data, t)
	if dark_me and not dark_it:
		dis.append("темнота")
	elif dark_it and not dark_me:
		adv.append("цель не видит в темноте")
	elif far and CombatRules.shot_in_dark(s, data, f, t):
		dis.append("темнота")
	var at: Array = b.get("range", [])
	if far and not at.is_empty() and d * int(FightGrid.cfg(data)["ft"]) > int(at[0]):
		dis.append("дальше обычной дальности")
	if far and CombatRules._foe_beside(s, data, f):
		dis.append("враг вплотную")
	if bool(b.get("heavy", false)) and (ItemRules.cfg(data)["small_races"] as Array).has(Sheet.size(s, data, f)):
		dis.append("тяжёлое оружие не по росту")  # v0.7.12, PHB
	var wx := WeatherRules.obscure_why(s, data)
	if not wx.is_empty() and t.has("x") and far and d > 1:  # a ranged attack in fog or a downpour (v0.7.46)
		dis.append(wx)
	dis.append_array(SpellEffects.attack_dis(s, data, f, t))
	return {"adv": adv, "dis": dis, "crit": bool(by_status["crit"])}


## The AC the blow of `f` meets: the target's own with the cover between them (v0.8.4.29.3: the roll and the window alike).
static func ac_against(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary) -> int:
	t["cover"] = CombatRules.cover_of(s, data, f, t)
	var ac := Sheet.ac(s, t)
	t.erase("cover")
	return ac


## What the window says of the blow before the click (v0.8.4.29.3): the same reasons, cover and least critical die as the roll.
## {chance (%), adv: [reasons], dis: [reasons]}.
static func odds(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary) -> Dictionary:
	var m := mods(s, data, f, t, b)
	(m["adv"] as Array).append_array(b.get("adv", []))
	(m["dis"] as Array).append_array(b.get("dis", []))
	var chance := Roll.chance(int(b.get("to_hit", 0)), ac_against(s, data, f, t), not (m["adv"] as Array).is_empty(), not (m["dis"] as Array).is_empty(),
		int(b.get("crit_min", 20)))
	return {"chance": chance, "adv": m["adv"], "dis": m["dis"]}


## The whole of its action at `t`: Multiattack when it has one for this kind of action. A window of the hero's reaction leaves the
## rest of the blows in `resume_plan`.
static func full(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, act: Dictionary, lines: Array[String]) -> void:
	var plan := _plan(s, data, f, t, act)
	for i in plan.size():
		if not up(s, t) or str(s.combat.get("outcome", "")) == "dead":
			return  # nobody finishes the downed hero (v0.7.9)
		one(s, data, f, t, plan[i], lines)
		if bool(s.combat.get("halt", false)):
			var rest: Array = []
			for a: Dictionary in plan.slice(i + 1):
				rest.append(str(a["name_en"]))
			s.combat["resume_plan"] = rest
			return


static func _plan(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, act: Dictionary) -> Array[Dictionary]:
	var m := Sheet.template(data, f)
	var by_en := {}
	for a: Dictionary in m.get("actions", []):
		by_en[str(a["name_en"])] = a
	var plan: Array[Dictionary] = []
	if not shot(f, t, of_action(data, f, act)) or str(act.get("kind")) != "melee":  # a throw of a melee weapon is one attack (v0.7.22.19, #13)
		for x: Dictionary in m.get("multiattack", []):
			var a: Dictionary = by_en.get(str(x["action"]), {})
			if not a.is_empty() and (str(a.get("kind")) == str(act.get("kind")) or (str(act.get("kind")) == "ranged" and a.has("range"))):
				for i in int(x["count"]):
					plan.append(a)
	if plan.is_empty():
		for i in 1 + CharacterRules.extra_attacks(Sheet.holder(s, f), data):  # a class on a template with no Multiattack
			plan.append(act)
	if ConditionRules.has(Sheet.holder(s, f), "slowed_spell"):  # Slow: one attack (v0.7.13.6)
		plan = [plan[0]]
	return plan


## One action of a template: a blow or a save.
static func one(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, a: Dictionary, lines: Array[String]) -> void:
	if str(a.get("kind")) == "save":
		breath(s, data, f, t, a, lines)
	else:
		swing(s, data, f, t, of_action(data, f, a), lines)


## A save action: a breath, a gaze, a song, at `t` and at every foe of it in its area.
static func breath(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, a: Dictionary, lines: Array[String]) -> void:
	MonsterRules.spend(f, a)
	AnimRules.breath(s, data, f, t, a)
	var caught: Array[Dictionary] = [t]
	if not a.get("effect", {}).get("area", {}).is_empty() and not (a["damage"] as Array).is_empty() and bool(CombatRules.cfg(data)["friendly_fire"]["on"]):
		var cells := CombatRules.monster_area(s, data, f, a, FightGrid.cell(t))
		for id: String in CombatRules.foes_of(s, f):
			var o := CombatRules.fighter(s, id)
			if id != str(t.get("id")) and FightGrid.in_cells(o, cells):
				caught.append(o)
	for x: Dictionary in caught:
		_saves(s, data, f, x, a, lines)


static func _saves(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, a: Dictionary, lines: Array[String]) -> void:
	var sv: Dictionary = a["save"]
	var tag := MonsterRules.tag_of(data, a.get("effect", {}), a)
	if tag.is_empty() and (a["damage"] as Array).any(func(d: Dictionary) -> bool: return str(d.get("type", "")) == "poison"):
		tag = "poison"
	var pieces: Array = []
	for d: Dictionary in a["damage"]:
		pieces.append({"n": CombatRules.roll_dice(s.rng, str(d["dice"])), "type": str(d.get("type", ""))})
	var sh := Harm.save_half(s, data, t, str(sv["ability"]), int(sv["dc"]), pieces, {"tag": tag, "half": str(sv["success"]) == "half", "from": FightGrid.cell(f)})
	var r: Dictionary = sh["save"]
	var ok := bool(sh["ok"])
	AnimRules.outcome(s, t, "resist" if ok else "debuff" if (a["damage"] as Array).is_empty() else "impact",
		str(a["damage"][0].get("type", "")) if not (a["damage"] as Array).is_empty() else "debuff")
	var dmg := int(sh["damage"])
	var notes: Array[String] = []
	notes.assign(sh["notes"])
	var name := str(Sheet.holder(s, t).get("name", ""))
	if (a["damage"] as Array).is_empty():
		lines.append("%s — %s по %s: спасбросок %s" % [f["name"], a["name"], name, r["text"]])
	else:
		lines.append("%s — %s по %s: спасбросок %s, %d урона%s" % [f["name"], a["name"], name, r["text"], dmg, (" (%s)" % ", ".join(notes)) if not notes.is_empty() else ""])
		Harm.take(s, data, t, dmg, lines, "", false, Sheet.is_hero(f))
	if not ok and a.has("effect"):
		MonsterRules.apply_effect(s, data, f, t, a, dmg, lines, {"ok": false, "dc": int(sv["dc"]), "total": int(r["total"])})


## One attack roll of `f` at `t`, and all that comes of it. Its price is paid before. {"hit", "crit", "damage"}.
static func swing(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary, lines: Array[String]) -> Dictionary:
	var me := Sheet.holder(s, f)
	var m := mods(s, data, f, t, b)
	(m["adv"] as Array).append_array(b.get("adv", []))
	(m["dis"] as Array).append_array(b.get("dis", []))
	var blow :=FeatureRules.armed(s, data, f, t, b, m) if bool(b.get("weapon", false)) else b
	lines.append_array(SpellEffects.end_on_attack(me))
	Gear.spend_ammo(s, data, f, str(b.get("ammo", "")))  # arrows and bolts are spent, whoever shoots (v0.8.4.10)
	var a: Dictionary = b.get("act", {})
	if not a.is_empty():
		MonsterRules.spend(f, a)
	if shot(f, t, b) and throwable(b):  # thrown: out of the hand onto the target's square, anybody's (v0.8.4.31)
		Gear.throw_out(s, data, f, b, FightGrid.cell(t))
	if not Sheet.is_hero(f) and ConditionRules.has(me, "invisible"):
		FightGrid.keep_seen(f)  # a strike gives an invisible foe away
	var out := {"hit": false, "crit": false, "damage": 0}
	var anim := AnimRules.blow(s, data, f, t, b)  # v0.8.4.23: the strike is seen before what comes of it
	var stop := _stopped(s, data, f, t, blow)
	if stop.is_empty():
		out = _roll(s, data, f, t, blow, m, lines)
	else:
		lines.append(stop)
	AnimRules.result(s, data, anim, t, "crit" if bool(out["crit"]) else "hit" if bool(out["hit"]) else "miss")
	lines.append_array(ConditionRules.end_invisibility_on_attack(me, data))  # the attack is made unseen, then it ends
	ConditionRules.remove(Sheet.holder(s, t), "helped")
	ConditionRules.remove(me, "mocked")  # Vicious Mockery: only the next attack roll (v0.7.13)
	f["hidden"] = false
	if bool(b.get("weapon", false)) and not bool(s.combat.get("halt", false)):
		_horde(s, data, f, t, b, lines)
	return out


## Horde Breaker: once a turn one more blow at another foe beside the target.
static func _horde(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary, lines: Array[String]) -> void:
	var e := CombatRules.points(s, data, f)
	if bool(b.get("opts", {}).get("no_horde", false)) or bool(e.get("horde", false)) or not FeatureRules.has(Sheet.holder(s, f), "hunters_prey_horde_breaker"):
		return
	for id: String in CombatRules.foes_of(s, f):
		var o := CombatRules.fighter(s, id)
		if id != str(t["id"]) and FightGrid.touching(o, t) and (not bool(b["melee"]) or CombatRules.blade_reaches(s, data, f, o, int(b["reach"]))):
			e["horde"] = true
			lines.append("Разрушитель орд: удар по %s" % Sheet.holder(s, o).get("name", ""))
			swing(s, data, f, o, b.merged({"opts": {"no_horde": true}}, true), lines)
			return


## What keeps the blow from being rolled at all: a line, or "".
static func _stopped(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary) -> String:
	var who := str(Sheet.holder(s, f).get("name", ""))
	var it := str(Sheet.holder(s, t).get("name", ""))
	if CombatRules._missed_unseen(s, t):
		return "%s — %s: удар в пустоту, %s уже не там" % [who, b["name"], it]
	if bool(t.get("blinked", false)):  # Blink (v0.7.13.3)
		return "%s бьёт в пустоту — %s нет на этом плане" % [who, it]
	if bool(b.get("weapon", false)) and shot(f, t, b) and not (b.get("range", []) as Array).is_empty() and not SpellEffects.wall_between(s, data, f, t).is_empty():
		return "%s — %s: снаряд сносит Стена ветра" % [who, b["name"]]  # v0.7.13.6
	return SpellEffects.sanctuary(s, data, f, t)  # v0.7.13.2


static func _roll(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary, m: Dictionary, lines: Array[String]) -> Dictionary:
	var me := Sheet.holder(s, f)
	var it := Sheet.holder(s, t)
	var adv := not (m["adv"] as Array).is_empty()
	var dis := not (m["dis"] as Array).is_empty()
	if SpellEffects.take_next_attack_adv(me):  # True Strike (v0.7.13.1)
		adv = true
	for o: String in CombatRules.friends_of(s, t):  # Protection: a shield raised for the target (v0.8.4.26.1)
		if not dis and o != str(t["id"]) and Acts.react(s, data, CombatRules.fighter(s, o), "attacked", {"foe": str(f["id"]), "target": str(t["id"])}, lines):
			dis = true
	var rolls := Roll.of(s, f, adv, dis)
	var nat := Roll.kept(rolls, adv, dis)
	ConditionRules.remove(it, "guided")  # Guiding Bolt's light goes with the first attack roll (v0.7.13)
	var die := SpellEffects.die(s, me, "attack")  # Bless, Bane (v0.7.13.1)
	var to_hit := int(b.get("to_hit", 0)) + int(die["bonus"])
	var ac := ac_against(s, data, f, t)
	var total := nat + to_hit
	var crit_min := int(b.get("crit_min", 20))
	var hit := nat >= crit_min or (nat != 1 and total >= ac)
	var mark := " (с преимуществом)" if adv and not dis else " (с помехой)" if dis and not adv else ""
	var thrown := " (бросок)" if throwable(b) and shot(f, t, b) else ""  # a spear thrown, not thrust (v0.8.4.30)
	var both := "%s → " % " и ".join(rolls.map(func(r: int) -> String: return str(r))) if rolls.size() > 1 else ""  # both dice of an advantage (v0.8.4.31)
	var line := "%s — %s%s по %s: %s%d%s%d = %d против КД %d%s%s" % [me.get("name", ""), b["name"], thrown, it.get("name", ""), both, nat, " + " if to_hit >= 0 else " − ", absi(to_hit), total, ac, mark,
		(" [%s]" % die["note"]) if not str(die["note"]).is_empty() else ""]
	var parts: Array[Dictionary] = []  # the hover of the line (v0.7.49.4, the author's finding)
	parts.assign(b.get("hit_parts", []))
	parts.append_array(die.get("parts", []))
	if RollParts.sum(parts) != to_hit:
		parts.append(RollParts.part("прочие бонусы атаки", to_hit - RollParts.sum(parts)))
	if not hit and nat != 1:
		var insp := Roll.inspire(s, f)
		if int(insp["value"]) > 0:
			total += int(insp["value"])
			hit = total >= ac
			line += " + вдохновение %d = %d" % [int(insp["value"]), total]
			parts.append(RollParts.part(str(insp["label"]), int(insp["value"])))
	var tip := RollParts.text({"what": b["name"], "rolls": rolls, "nat": nat, "parts": parts, "total": total}) + " против КД %d" % ac
	CombatRules.line_tip(s, line, tip)
	var none := {"hit": false, "crit": false, "damage": 0}
	if not hit:
		lines.append(line + " — промах")
		CombatRules.fx(s, str(t["id"]), "dodge")
		if FeatureRules.giant_killer(s, data, t, f) and (not Sheet.is_hero(t) or FeatureRules.policy(s) != "never"):  # on a miss too (v0.8.4.33)
			t["reacted"] = true
			lines.append("%s: Убийца великанов — удар в ответ" % Sheet.holder(s, t).get("name", ""))
			swing(s, data, t, f, blade(s, data, t).merged({"opts": {"no_horde": true}}, true), lines)
		return none
	var guard := SpellEffects.against_attack(s, data, f, t, total)  # Mirror Image (v0.7.13.2)
	if not guard.is_empty():
		lines.append(line + " — " + guard)
		return none
	var crit := nat >= crit_min or bool(m["crit"])
	if crit and Sheet.prop(s, data, t, "no_crit"):
		crit = false  # adamantine armor: a critical hit is a normal one (v0.7.12)
		line += " (адамантин: не крит)"
	if not crit and Acts.react(s, data, t, "hit", {"foe": str(f["id"]), "total": total, "melee": bool(b.get("melee", false)) and not shot(f, t, b)}, lines):  # Parry, Shield
		lines.append(line + " — отбито")
		CombatRules.fx(s, str(t["id"]), "dodge")
		return none
	if not crit and _words_for(s, data, f, t, total, ac, lines):
		lines.append(line + " — мимо")
		CombatRules.fx(s, str(t["id"]), "dodge")
		return none
	var hurt := _damage(s, data, f, t, b, adv and not dis, dis and not adv, crit)
	CombatRules.line_tip(s, line, tip + "\n\nУрон: %s" % hurt["tip"])
	var ctx := {"foe": str(f["id"]), "blow": b, "line": line, "crit": crit, "dmg": int(hurt["dmg"]), "types": hurt["types"], "notes": hurt["notes"], "prone": hurt["prone"],
		"hit": true, "total": total, "ac": ac, "nat20": nat == 20}
	if Sheet.is_hero(t):
		f["last_total"] = total  # for the labels of the reaction spells (v0.7.13.7)
		var rx := FeatureRules.reactions(s, data, t, f, b.get("act", {}), shot(f, t, b), int(hurt["dmg"]), ctx)  # v0.7.10
		if not rx.is_empty():
			var pol := FeatureRules.policy(s)
			if pol == "ask" and CombatRules.current(s) == str(f["id"]):
				ctx["options"] = rx
				s.combat["pending"] = ctx
				s.combat["halt"] = true
				return {"hit": true, "crit": crit, "damage": int(hurt["dmg"])}
			if pol != "never":
				FeatureRules.apply_reaction(s, data, t, f, str(rx[0]["id"]), ctx, lines)
	else:
		Acts.react(s, data, t, "hurt", ctx, lines)
	land(s, data, f, t, b, ctx, lines)
	return {"hit": bool(ctx["hit"]), "crit": crit, "damage": int(ctx["dmg"])}


## Cutting Words (5e) for one of the target's side: a bard within 60 ft who sees the striker spends its reaction and a die of
## Bardic Inspiration on the roll at `t` (the hero's own is in its hit's reactions). Whether the blow misses now.
static func _words_for(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, total: int, ac: int, lines: Array[String]) -> bool:
	for id: String in CombatRules.friends_of(s, t):
		var o := CombatRules.fighter(s, id)
		var c := Sheet.holder(s, o)
		if id == str(t["id"]) or not FeatureRules.has(c, "cutting_words") or bool(o.get("reacted", false)) or not up(s, o) 				or ConditionRules.incapacitated(c) or Stock.left(c, data, "bardic_inspiration") < 1 or ConditionRules.has(c, "blinded") 				or ConditionRules.invisible(Sheet.holder(s, f), data) or FightGrid.dist(o, f) > FightGrid.squares_of(data, 60) 				or (Sheet.is_hero(o) and FeatureRules.policy(s) == "never"):
			continue
		var ctx := {"total": total, "ac": ac, "nat20": false, "hit": true}
		FeatureRules.apply_reaction(s, data, o, f, "cutting_words", ctx, lines)
		return not bool(ctx["hit"])
	return false


## The damage of a hit by its pieces, each through what the target resists: {dmg, types, notes, prone, tip}.
static func _damage(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary, adv: bool, dis: bool, crit: bool) -> Dictionary:
	var me := Sheet.holder(s, f)
	var a: Dictionary = b.get("act", {})
	var magical := bool(b.get("magical", false))
	var silvered := bool(b.get("silvered", false))
	var dtypes: Dictionary = data["misc"]["damage_types"]
	var pieces: Array = b.get("pieces", [])
	var extra := MonsterRules.extra_on_hit(s, data, f, t, a, adv, dis, crit)
	var dmg := 0
	var rolled := 0
	var said: Array[String] = []
	var types: Array[String] = []
	var notes: Array[String] = []
	if int(extra["damage"]) > 0:
		dmg += int(Sheet.damage(s, data, t, str(pieces[0]["type"]) if not pieces.is_empty() else "", int(extra["damage"]), magical, silvered)["damage"])
		notes.append_array(extra["notes"])
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		var part := CombatRules.roll_dice(s.rng, str(p["dice"]), crit, 0, 2 if bool(b.get("gwf", false)) else 0)
		var text := str(p["dice"]).replace("d", "к")
		if i == 0:
			part = maxi(1, part + int(b.get("bonus", 0)))
			text += ("%+d" % int(b["bonus"])) if int(b.get("bonus", 0)) != 0 else ""
			if not str(b.get("extra", "")).is_empty():
				part += CombatRules.roll_dice(s.rng, str(b["extra"]), crit)
				text += " + %s %s" % [str(b["extra"]).replace("d", "к"), b.get("extra_name", "")]
				notes.append(str(b.get("extra_name", "")))
		rolled += part
		said.append(text)
		var adj := Sheet.damage(s, data, t, str(p["type"]), part, magical, silvered)
		dmg += int(adj["damage"])
		var word := str(dtypes.get(str(p["type"]), p["type"]))
		if not types.has(word):
			types.append(word)
		if not str(adj["note"]).is_empty() and not notes.has(str(adj["note"])):
			notes.append(str(adj["note"]))
	if ConditionRules.has(me, "enfeebled") and bool(b.get("weapon", false)):  # Ray of Enfeeblement (v0.7.13.6)
		dmg /= 2
		notes.append("ослаблен")
	if SpellEffects.boon(me, "reduced") != null:  # Reduce (v0.7.50.1)
		dmg = maxi(1, dmg - CombatRules.roll_dice(s.rng, "1d4"))
	return {"dmg": dmg, "types": types, "notes": notes, "prone": extra["prone"],
		"tip": "%s = %d%s%s" % [" + ".join(said), rolled, " (крит: кости дважды)" if crit else "", (" → %d у цели (сопротивление или уязвимость)" % dmg) if dmg != rolled else ""]}


## The hit lands (after the hero's reaction, if any): the damage, what a weapon adds, a charge's fall, the effect of the action, a
## pounce, the hero's answer. Lines.
static func land(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary, ctx: Dictionary, lines: Array[String]) -> void:
	var dmg := int(ctx["dmg"])
	var crit := bool(ctx["crit"])
	var line := str(ctx["line"])
	var pieces: Array = b.get("pieces", [])
	var it := Sheet.holder(s, t)
	b["wounded"] = int(it.get("hp", 0)) < int(it.get("max_hp", 0))  # as it was before this blow: Colossus Slayer (v0.8.4.33)
	if not bool(ctx["hit"]):
		lines.append(line + " — промах")
		CombatRules.fx(s, str(t["id"]), "dodge")
	else:
		var notes: Array = ctx["notes"]
		lines.append(line + (" — попадание" if pieces.is_empty() else (" — КРИТ! " if crit else " — попадание, ") + "%d (%s)%s" % [dmg,
			", ".join(ctx["types"]), (", " + ", ".join(notes)) if not notes.is_empty() else ""]))
		if not shot(f, t, b):  # before the damage lands: Armor of Agathys counts the hit points it had (v0.8.4.27.6)
			Harm.retort(s, data, f, t, false, lines)
		if crit and not pieces.is_empty():
			CombatRules.fx(s, str(t["id"]), "crit")
		if not pieces.is_empty():
			Harm.take(s, data, t, dmg, lines, str(pieces[0]["type"]), crit, Sheet.is_hero(f))
			if bool(b.get("weapon", false)) and (weapon_def(s, data, f, b).get("properties", []) as Array).has("life_drain"):
				var back := Harm.mend(s, data, f, dmg / 2)  # the blow drinks: half its damage back (v0.8.4.36)
				if back > 0:
					lines.append("%s: удар возвращает %d хитов" % [Sheet.holder(s, f).get("name", ""), back])
	if str(s.combat.get("outcome", "")) == "dead":
		return
	if bool(ctx["hit"]):
		if bool(b.get("weapon", false)):
			_extras(s, data, f, t, b, crit, lines)
			_by_class(s, data, f, t, b, crit, lines)
		b.erase("wounded")
		var a: Dictionary = b.get("act", {})
		if not a.is_empty():
			var pounce := MonsterRules.charge_prone(s, data, f, t, ctx["prone"], lines)
			MonsterRules.apply_effect(s, data, f, t, a, dmg, lines)
			if pounce:  # a pounce: one bite at the prone one as a bonus action
				follow_up(s, data, f, t, "%s кусает упавшего", lines)
		_rampage(s, data, f, t, b, lines)
	if int(ctx.get("rebuke", 0)) > 0 and str(f.get("status")) == "active":  # Hellish Rebuke (v0.7.13.7)
		SpellEffects.rebuke(s, data, f, str(ctx.get("rebuke_spell", "hellish_rebuke")), int(ctx["rebuke"]), lines)
	if dmg > 0 and str(f.get("status")) == "active":
		Acts.react(s, data, t, "damage", {"foe": str(f["id"]), "dmg": dmg}, lines)
	if bool(ctx.get("counter", false)) and str(f.get("status")) == "active" and up(s, t):
		lines.append("%s: Убийца великанов — удар в ответ" % Sheet.holder(s, t).get("name", ""))
		swing(s, data, t, f, blade(s, data, t).merged({"opts": {"no_horde": true}}, true), lines)


## One bite at `t` for its bonus action (a pounce at the one it threw down, Rampage after a kill; v0.8.4.27.5): the melee Bite
## of its template, the bonus point paid. Whether it bit.
static func follow_up(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, line: String, lines: Array[String]) -> bool:
	var bite := bite_of(data, f)
	if bite.is_empty() or int(CombatRules.points(s, data, f).get("bonus", 0)) < 1 or not up(s, f) or not up(s, t) or not FightGrid.touching(f, t):
		return false
	CombatRules.pay(f, "bonus")
	lines.append(line % f["name"])
	swing(s, data, f, t, of_action(data, f, bite), lines)
	return true


## The thing a blow is struck with, the copy in that hand with its marks (v0.8.4.36); {} — no thing.
static func weapon_def(s: GameSession, data: Dictionary, f: Dictionary, b: Dictionary) -> Dictionary:
	var id := str(b.get("id", ""))
	if id.is_empty():
		return {}
	var h := Sheet.things(s, data, f)
	return ItemRules.copy_def(data["items"], s.items, h, id, CharacterRules.hold_index(h, id, "off_hand" if bool(b.get("offhand", false)) else "main_hand"))


## The melee Bite of its template, {} when it has none.
static func bite_of(data: Dictionary, f: Dictionary) -> Dictionary:
	for x: Dictionary in Sheet.template(data, f).get("actions", []):
		if str(x.get("name_en", "")) == "Bite" and str(x.get("kind")) == "melee":
			return x
	return {}


## Rampage (v0.8.4.27.5): a melee blow on its own turn brought `t` down — for its bonus action it walks half its speed to the
## nearest foe still up and bites it.
static func _rampage(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary, lines: Array[String]) -> void:
	if up(s, t) or shot(f, t, b) or CombatRules.current(s) != str(f.get("id")) or bite_of(data, f).is_empty() \
			or int(CombatRules.points(s, data, f).get("bonus", 0)) < 1:
		return
	var name := ItemRules.born_name(data, Sheet.holder(s, f), "rampage")
	var next := {}
	for id: String in CombatRules.foes_of(s, f):
		var o := CombatRules.fighter(s, id)
		if up(s, o) and (next.is_empty() or FightGrid.dist(f, o) < FightGrid.dist(f, next)):
			next = o
	if name.is_empty() or next.is_empty():
		return
	lines.append("%s: %s" % [f["name"], name])
	var e := CombatRules.points(s, data, f)
	var walk := int(e["move"])
	e["move"] = Move.steps(s, data, f) / 2
	FightAI.step_to(s, data, f, next, lines)
	e["move"] = walk
	if not follow_up(s, data, f, next, "%s кусает", lines):
		CombatRules.pay(f, "bonus")


## What the class of `f` adds to a weapon's hit: Sneak Attack spent, its extra dice, what comes after the hit.
static func _by_class(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary, crit: bool, lines: Array[String]) -> void:
	if not str(b.get("extra", "")).is_empty():
		CombatRules.points(s, data, f)["sneak"] = true
	if not up(s, t):
		return
	var x := FeatureRules.hit_extras(s, data, f, b, t, crit)
	var pieces: Array = b.get("pieces", [])
	if not str(x["dice"]).is_empty():
		var type := str(pieces[0]["type"])
		var more := Sheet.taken(s, data, t, type, CombatRules.roll_dice(s.rng, str(x["dice"])), bool(b.get("magical", false)), bool(b.get("silvered", false)))
		lines.append("%s: ещё %d" % [", ".join(x["notes"]), more])
		Harm.take(s, data, t, more, lines, type, false, Sheet.is_hero(f))
	FeatureRules.after_hit(s, data, f, b, t, crit, b.get("opts", {}), lines)


## What comes with a weapon's hit: the spells on the striker (Divine Favor, Hunter's Mark, Branding Smite), the weapon's own
## properties (fire_damage — +1d6 fire, v0.7.12), a Potion of Growth.
static func _extras(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary, crit: bool, lines: Array[String]) -> void:
	var me := Sheet.holder(s, f)
	var pieces: Array = b.get("pieces", [])
	var type := str(pieces[0]["type"]) if not pieces.is_empty() else ""
	var by_hero := Sheet.is_hero(f)
	var it := Sheet.holder(s, t)
	var more := func(add: int, dtype: String) -> void:
		Harm.take(s, data, t, add, lines, dtype, false, by_hero)
	for x: Dictionary in SpellEffects.hit_extras(me, t, type):
		if not up(s, t):
			break
		if not str(x.get("save", "")).is_empty():  # a poison on the blade: the struck one's save, nothing on a success
			var r := Sheet.save(s, data, t, str(x["save"]), int(x["dc"]), str(x["type"]))
			if bool(r["ok"]):
				lines.append("%s: спасбросок %s — яд не подействовал" % [x["name"], r["text"]])
				continue
		if not (x.get("effect", {}) as Dictionary).is_empty():  # a made liquid on the blade (v0.8.4.28.5): a monster's attack's effect
			MonsterRules.apply_effect(s, data, f, t, {"name": x["name"], "effect": x["effect"]}, 0, lines)
		if str(x["dice"]).is_empty():
			continue
		var add := Sheet.taken(s, data, t, str(x["type"]), CombatRules.roll_dice(s.rng, str(x["dice"]), crit), true, false)
		lines.append("%s: ещё %d (%s)" % [x["name"], add, data["misc"]["damage_types"].get(str(x["type"]), x["type"])])
		more.call(add, str(x["type"]))
		if bool(x.get("reveal", false)) and ConditionRules.has(it, "invisible"):
			ConditionRules.remove(it, "invisible")
			lines.append("%s светится — невидимость спадает" % it.get("name", ""))
	var def := ItemRules.def_of(data["items"], s.items, str(b.get("id", "")))
	for el: Dictionary in ItemRules.elements(data, def):
		if up(s, t):
			var dtype := str(el["type"])
			var add := Sheet.taken(s, data, t, dtype, CombatRules.roll_dice(s.rng, str(el["dice"]), crit))
			lines.append("%s: ещё %d (%s)" % [def.get("name", ""), add, data["misc"]["damage_types"][dtype]])
			more.call(add, dtype)
	var hit := ItemRules.hit_effect(weapon_def(s, data, f, b))  # a weapon that lays a status on a hit (v0.8.4.36)
	if not hit.is_empty() and up(s, t):
		MonsterRules.apply_effect(s, data, f, t, {"name": str(def.get("name", "")), "effect": hit}, 0, lines)
	if ConditionRules.effects(me).any(func(e: Dictionary) -> bool: return bool(e.get("enlarged", false))) and up(s, t):
		var big := Sheet.taken(s, data, t, type, CombatRules.roll_dice(s.rng, "1d4", crit), bool(b.get("magical", false)), bool(b.get("silvered", false)))
		lines.append("увеличение: ещё %d" % big)
		more.call(big, type)
