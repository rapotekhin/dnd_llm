class_name Harm
extends RefCounted
## One road of damage for anybody (v0.8.4.13, ADR-0016): the hero, a foe, an ally, a person hurt out of a fight. What its
## defenses left (`Sheet.damage`) comes here: oil on it catches, temporary hit points and a beast form take it first, a trait
## keeps it on its feet, a blow wakes it and shakes its concentration. At 0 HP in a fight the hero falls and rolls death
## saves, a fighter falls dead, knocked out, or gone when it was called; out of a fight the hero is knocked out after the turn.
## Damage of a type with no attack roll comes through `typed`: its defenses, its line, then `take`.


## Damage of a type with no attack roll — a trap, a poison, a fall, a monster's rider, the master's word, the console: `dmg`
## through `who`'s defenses (Sheet.damage), a line of `said` ({hp} — what is left, {words} — `words` of it), then `take`.
## What was left. `stable` — as `take`'s.
static func typed(s: GameSession, data: Dictionary, who: Dictionary, dmg: int, dtype: String, lines: Array[String], said := "−{hp} HP ({words})",
		crit := false, by_hero := true, magical := true, silvered := false, stable := false) -> int:
	var adj := Sheet.damage(s, data, who, dtype, dmg, magical, silvered)
	var left := int(adj["damage"])
	lines.append(said.format({"hp": left, "words": words(data, dtype, str(adj["note"]))}))
	take(s, data, who, left, lines, dtype, crit, by_hero, stable)
	return left


## The damage its statuses deal at the `when` of its turn (start | end, v0.8.4.43.54, as in BG3): each status of anybody with a
## harm — the source's numbers or its row's (ConditionRules.harm_of) — through the defenses and `take`; one with `ticks` goes
## after its last. One of a kind: a second source is weighed by the row's `same` (ConditionRules.impose).
static func each_turn(s: GameSession, data: Dictionary, who: Dictionary, when: String, lines: Array[String]) -> void:
	var h := Sheet.holder(s, who)
	for e: Dictionary in ConditionRules.effects(h).duplicate():
		var hm := ConditionRules.harm_of(data, e)
		if hm.is_empty() or str(hm.get("when", "start")) != when or not Attack.up(s, who):
			continue
		var by := str(e.get("by", ""))
		typed(s, data, who, CombatRules.roll_dice(s.rng, str(hm["dice"])), str(hm["type"]), lines,
			"%s — %s: −{hp} HP ({words})" % [h.get("name", ""), ConditionRules.name_of(data, str(e.get("condition", "")))], false,
			by.is_empty() or by == CombatRules.PLAYER)
		if e.has("ticks"):
			e["ticks"] = int(e["ticks"]) - 1
			if int(e["ticks"]) <= 0:
				ConditionRules.remove_effect(h, int(e["uid"]))
				if Sheet.is_hero(who):
					CharacterRules.refresh(h, data, s.items)


## A damage type's name with what a defense did to it: «огонь, сопротивление: …».
static func words(data: Dictionary, dtype: String, note: String) -> String:
	return ", ".join([str(data["misc"]["damage_types"].get(dtype, dtype)), note].filter(func(w: String) -> bool: return not w.is_empty()))


## `dmg` to `who`; `by_hero` — the hero's blow (a nonlethal one only knocks out). `stable` — what drops it to 0 HP leaves it
## stable (a giant spider's poison, 5e): the hero and one of its side roll no death saves, a foe is knocked out, not killed.
## Lines into `lines`.
static func take(s: GameSession, data: Dictionary, who: Dictionary, dmg: int, lines: Array[String], dtype: String = "", crit: bool = false, by_hero: bool = true,
		stable: bool = false) -> void:
	var hero := Sheet.is_hero(who)
	var fight := CombatRules.active(s) and (hero or who.has("status"))
	var f: Dictionary = CombatRules.player(s) if hero and fight else who
	var me := Sheet.holder(s, who)
	if fight:
		FightField.din(s, data, dtype)  # a thunderous blow carries farther
	if dmg <= 0:
		return
	if dtype == "fire" and LiquidRules.fire_plus(s, me) > 0:  # oil on it catches (v0.7.12; a coat since v0.8.4.28.2)
		var more := Sheet.taken(s, data, who, "fire", LiquidRules.fire_plus(s, me))
		LiquidRules.uncoat(me)
		dmg += more
		lines.append("%s: масло вспыхивает, ещё %d" % [me.get("name", ""), more])
	if fight:
		f["rage_kept"] = true
	dmg = absorb(me, dmg, lines)
	if fight:
		dmg = _transfer(s, data, f, dmg, dtype, lines)
	dmg = FeatureRules.hurt_shape(s, data, dmg, lines, who)  # a beast form takes it first
	if dmg <= 0:
		return
	var hp := Sheet.hp(s, data, who)
	if hero and Cheats.on(me, "god"):  # the dev console's immortality: the blow lands, the hero stays up
		me["hp"] = maxi(1, hp - dmg)
		_after(s, data, who, dmg, lines)
		return
	if hero and fight:
		if ArenaRules.yield_bout(s) and hp - dmg <= 0:  # v0.7.45: the manager stops the bout
			me["hp"] = 0
			s.combat["outcome"] = "arena_lost"
			lines.append("%s падает — распорядитель останавливает бой" % me["name"])
			return
		if hp <= 0:  # a blow at 0 HP is a failed death save, a critical one two
			CombatRules.blow_at_fallen(s, f, crit, lines)
			return
		if dmg - hp >= int(me["max_hp"]):  # massive damage
			me["hp"] = 0
			s.combat["outcome"] = "dead"
			lines.append("%s погибает на месте" % me["name"])
			return
	if fight and not hero and str(who.get("status")) == "down":  # one of the hero's side who fell (v0.8.4.26.3)
		CombatRules.blow_at_fallen(s, who, crit, lines)
		return
	if dmg >= hp and hp > 0 and survives(s, data, who, dmg, dtype, crit, lines):
		me["hp"] = 1
	else:
		me["hp"] = maxi(0, hp - dmg)
	_after(s, data, who, dmg, lines)
	_share(s, data, who, dmg, dtype, lines)
	if int(me["hp"]) > 0 or not fight:
		return
	if not hero and Guise.has_body(me) and not Guise.body(me).has("hp"):  # a shapechanger falls in its true form (5e)
		lines.append_array(FeatureRules.end_shape(s, data, 0, who))
	if hero:
		lines.append_array(ConditionRules.impose(s, data, {"condition": "unconscious", "ends": {"rest": "long"}, "source": {"kind": "engine", "name": "0 HP"}}))
		s.combat["death_saves"] = {"ok": 0, "fail": 0, "stable": true} if stable else {"ok": 0, "fail": 0}
		FeatureRules.rage_ends(s, data, f, lines)
		lines.append("%s падает без сознания" % me["name"])
		return
	if who.has("called_by") and str(who.get("side")) == "enemy":
		who["status"] = "gone"
		lines.append("%s развеивается" % who["name"])
		MonsterRules.release(s, data, who, lines)
		return
	if str(who.get("side")) == "ally":
		var summoned := str(who.get("ally", "")) == "summon"
		who["status"] = "gone" if summoned else "down"
		if stable and not summoned:
			who["death_saves"] = {"ok": 0, "fail": 0, "stable": true}
		lines.append(("%s развеивается" if summoned else "%s падает без сознания") % who["name"])
		MonsterRules.release(s, data, who, lines)
		return
	if stable or (by_hero and ArenaRules.yield_bout(s)) or (bool(s.combat.get("spare_blow", false)) and bool(s.combat.get("melee_strike", false))):
		who["status"] = "unconscious"  # v0.7.45: in a bout to surrender any blow only knocks out; 5e: a melee blow at 0 HP may knock out (v0.7.22.11)
		lines.append(("%s падает без сознания" if stable else "%s оглушён и падает без сознания") % who["name"])
		return
	who["status"] = "dead"
	lines.append("%s повержен" % who["name"])
	FeatureRules.on_kill(s, data, lines)
	MonsterRules.release(s, data, who, lines)
	MonsterRules.death_burst(s, data, who, lines)


## Damage Transfer (a cloaker, v0.8.4.27.5): while it holds one grappled, it takes half of the damage (rounded down) and the
## other half goes to that one. What it keeps.
static func _transfer(s: GameSession, data: Dictionary, f: Dictionary, dmg: int, dtype: String, lines: Array[String]) -> int:
	var name := ItemRules.born_name(data, Sheet.holder(s, f), "transfer_held")
	if name.is_empty():
		return dmg
	var held := CombatRules.held_of(s, f)
	if held.is_empty():
		return dmg
	var kept := dmg / 2
	lines.append("%s: %s — %d на %s" % [f.get("name", ""), name, dmg - kept, Sheet.holder(s, held[0]).get("name", "")])
	take(s, data, held[0], dmg - kept, lines, dtype, false, false)
	return kept

## Damage back at one who hits it with a melee attack from beside it (v0.8.4.27.6): a status's `retort` {dice, type} — Heated
## Body of an azer, Armor of Agathys while its temporary hit points last (`while_temp`), a Fire Shield after; `touch` — a
## grapple or a shove counts too. Lines.
static func retort(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, touch: bool, lines: Array[String]) -> void:
	if FightGrid.dist(f, t) > 1:
		return
	var me := Sheet.holder(s, t)
	for e: Dictionary in ItemRules.born_effects(data, me):
		var r: Variant = e.get("retort")
		if not r is Dictionary or touch and not bool(r.get("touch", false)) or bool(r.get("while_temp", false)) and int(me.get("temp_hp", 0)) <= 0:
			continue
		if not Attack.up(s, f):
			return
		typed(s, data, f, CombatRules.roll_dice(s.rng, str(r["dice"])), str(r["type"]), lines,
			"%s: %s — −{hp} HP ({words})" % [e.get("source", {}).get("name", ""), Sheet.holder(s, f).get("name", "")], false, Sheet.is_hero(t))



## Warding Bond (v0.8.4.26.3): the one who laid the bond takes the same damage; the bond is gone once it lies at 0 HP.
static func _share(s: GameSession, data: Dictionary, who: Dictionary, dmg: int, dtype: String, lines: Array[String]) -> void:
	var me := Sheet.holder(s, who)
	for e: Dictionary in ConditionRules.effects(me).duplicate():
		if not bool(e.get("ward", false)):
			continue
		var by := str(e.get("by", ""))
		var warder: Dictionary = Sheet.HERO if by == Being.HERO else CombatRules.fighter(s, by) if CombatRules.active(s) else {}
		if warder.is_empty() or by == str(who.get("id")) or Sheet.hp(s, data, warder) <= 0:
			ConditionRules.remove_effect(me, int(e["uid"]))
			continue
		lines.append("%s: %s — урон делит %s" % [me.get("name", ""), e["source"]["name"], Sheet.holder(s, warder).get("name", "")])
		take(s, data, warder, dmg, lines, dtype)


## A save against damage of anybody (v0.8.4.29.3: one road for a spell's area, a zone, a monster's breath or gaze and a
## dragonborn's breath): the cover between `from` (a cell, opts) and it on a DEX save, the save, half on success (`half`, true by
## default) or nothing, each piece of `pieces` ([{n, type}]) through its defenses. No save when `ab` is "" (a zone with none).
## opts: tag, half, from, dis. {ok, damage, notes: [..], save: Sheet.save's result or {}}.
static func save_half(s: GameSession, data: Dictionary, who: Dictionary, ab: String, dc: int, pieces: Array, opts: Dictionary = {}) -> Dictionary:
	var r := {}
	var ok := false
	if not ab.is_empty():
		if ab == "dex" and opts.has("from") and who.has("x"):
			who["cover"] = mini(int(FightGrid.cfg(data)["cover"]["three_quarters"]), FightGrid.cover_at(s, data, opts["from"], FightGrid.cell(who)))
		r = Sheet.save(s, data, who, ab, dc, str(opts.get("tag", "")), bool(opts.get("dis", false)))
		who.erase("cover")
		ok = bool(r["ok"])
	var dmg := 0
	var notes: Array[String] = []
	for p: Dictionary in pieces:
		var part := int(p["n"])
		part = part / 2 if ok and bool(opts.get("half", true)) else (0 if ok else part)
		var adj := Sheet.damage(s, data, who, str(p.get("type", "")), part)
		dmg += int(adj["damage"])
		if not str(adj["note"]).is_empty() and not notes.has(str(adj["note"])):
			notes.append(str(adj["note"]))
	return {"ok": ok, "damage": dmg, "notes": notes, "save": r}


## Hit points back to anybody with what comes of them (v0.8.4.29.3, one road for a spell, a potion, Lay on Hands): `heal`, and
## one who lay at 0 HP gets up — the hero wakes with its death saves gone, a fighter who fell or was knocked out stands again.
## What it got.
static func mend(s: GameSession, data: Dictionary, who: Dictionary, n: int) -> int:
	var me := Sheet.holder(s, who)
	var before := int(me.get("hp", 0))
	var got := heal(data, me, n)
	if got <= 0:
		return got
	if Sheet.is_hero(who) or is_same(me, s.character):
		if before <= 0:
			ConditionRules.remove(me, "unconscious")
			if CombatRules.active(s):
				s.combat["death_saves"] = {"ok": 0, "fail": 0}
	elif str(who.get("status", "")) in ["down", "unconscious"]:
		who["status"] = "active"
		who.erase("death_saves")
	return got


## Hit points back to anybody (v0.8.4.27.1): up to `top` (its maximum by default) on `body` (its own record by default; a
## beast's form keeps its own). One that may not regain them (a swarm's `no_heal`) gets none. What it got.
static func heal(data: Dictionary, me: Dictionary, n: int, top := -1, body: Dictionary = {}) -> int:
	var on := me if body.is_empty() else body
	if n <= 0 or ConditionRules.does(me, data, "no_heal"):
		return 0
	var before := int(on.get("hp", 0))
	on["hp"] = mini(int(on.get("max_hp", before)) if top < 0 else top, before + n)
	return maxi(0, int(on["hp"]) - before)


## Temporary hit points of anybody: `n` when more than it has (they do not add up), none for one with `no_heal`. True when
## they were laid.
static func shield(data: Dictionary, me: Dictionary, n: int) -> bool:
	if n <= int(me.get("temp_hp", 0)) or ConditionRules.does(me, data, "no_heal"):
		return false
	me["temp_hp"] = n
	return true


## Temporary hit points take damage first (Dark One's Blessing, Heroism). What is left.
static func absorb(me: Dictionary, dmg: int, lines: Array[String]) -> int:
	var thp := int(me.get("temp_hp", 0))
	if thp <= 0 or dmg <= 0:
		return dmg
	var taken := mini(thp, dmg)
	me["temp_hp"] = thp - taken
	lines.append("%s: временные хиты −%d" % [me.get("name", ""), taken])
	return dmg - taken


## A blow that would drop it leaves it at 1 HP: Relentless Endurance of a half-orc (once a long rest), Relentless of a
## boar, Undead Fortitude of a zombie. True when so; the line goes to `lines`.
static func survives(s: GameSession, data: Dictionary, who: Dictionary, dmg: int, dtype: String, crit: bool, lines: Array[String]) -> bool:
	var me := Sheet.holder(s, who)
	var name := str(me.get("name", ""))
	if CharacterRules.has_trait(me, "relentless_endurance") and not bool(me.get("relentless_used", false)):
		me["relentless_used"] = true
		lines.append("%s: %s — остаётся на ногах с 1 HP" % [name, data["races"]["traits"].get("relentless_endurance", {}).get("name", "")])
		return true
	var r := MonsterRules.trait_of(data, who, "relentless")
	if not r.is_empty() and not bool(me.get("relentless_used", false)) and dmg <= int(r.get("effect", {}).get("relentless", 0)):
		me["relentless_used"] = true
		lines.append("%s: %s — остаётся на ногах с 1 HP" % [name, r["name"]])
		return true
	var uf := MonsterRules.trait_of(data, who, "undead_fortitude")
	if not uf.is_empty() and dtype != "radiant" and not crit:
		var dc := 5 + dmg
		if Sheet.saved(s, data, who, "con", dc, "", false, lines):
			lines.append("%s: %s — встаёт с 1 HP" % [name, uf["name"]])
			return true
	return false


## What a blow does past the hit points: an effect that ends on damage (sleep) goes, the concentration holds by a CON save
## (DC 10 or half the damage) or breaks — at 0 HP always.
static func _after(s: GameSession, data: Dictionary, who: Dictionary, dmg: int, lines: Array[String]) -> void:
	var me := Sheet.holder(s, who)
	var name := str(me.get("name", ""))
	var up := int(me.get("hp", 0)) > 0
	for e: Dictionary in ConditionRules.effects(me).duplicate():
		if bool(e.get("wake", false)) and up:
			ConditionRules.remove_effect(me, int(e["uid"]))
			var cond := str(e.get("condition", ""))
			lines.append("%s приходит в себя от удара" % name if cond == "unconscious" else "%s: %s проходит от удара" % [name, ConditionRules.name_of(data, cond).to_lower()])
	if str(me.get("concentration", "")).is_empty():
		return
	if not up:
		lines.append_array(ConditionRules.lose_concentration(s, data, who, "0 HP"))
		return
	var r := Sheet.save(s, data, who, "con", maxi(10, dmg / 2), "")
	lines.append(str(r["line"]))
	if bool(r["ok"]):
		lines.append("%s: концентрация удержана" % name)
	else:
		lines.append_array(ConditionRules.lose_concentration(s, data, who, "провален спасбросок"))
