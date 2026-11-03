class_name Harm
extends RefCounted
## One road of damage for anybody (v0.8.4.13, ADR-0016): the hero, a foe, an ally, a person hurt out of a fight. What its
## defenses left (`Sheet.damage`) comes here: oil on it catches, temporary hit points and a beast form take it first, a trait
## keeps it on its feet, a blow wakes it and shakes its concentration. At 0 HP in a fight the hero falls and rolls death
## saves, a fighter falls dead, knocked out, or gone when it was called; out of a fight the hero is knocked out after the turn.


## `dmg` to `who`; `by_hero` — the hero's blow (a nonlethal one only knocks out). Lines into `lines`.
static func take(s: GameSession, data: Dictionary, who: Dictionary, dmg: int, lines: Array[String], dtype: String = "", crit: bool = false, by_hero: bool = true) -> void:
	var hero := Sheet.is_hero(who)
	var fight := CombatRules.active(s) and (hero or who.has("status"))
	var f: Dictionary = CombatRules.player(s) if hero and fight else who
	var me := Sheet.holder(s, who)
	if fight:
		FightField.din(s, data, dtype)  # a thunderous blow carries farther
	if dmg <= 0:
		return
	if dtype == "fire" and f.has("oiled"):  # oil on it catches (v0.7.12)
		var more := Sheet.taken(s, data, who, "fire", int(f["oiled"]))
		f.erase("oiled")
		dmg += more
		lines.append("%s: масло вспыхивает, ещё %d" % [me.get("name", ""), more])
	if fight:
		f["rage_kept"] = true
	dmg = absorb(me, dmg, lines)
	dmg = FeatureRules.hurt_shape(s, data, dmg, lines, who)  # a beast form takes it first
	if dmg <= 0:
		return
	var hp := int(me.get("hp", Sheet.max_hp(s, data, who)))  # a record whole has no count of its own: its template's
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
		var ds: Dictionary = s.combat["death_saves"]
		if hp <= 0:  # a blow at 0 HP is a failed death save, a critical one two
			ds["fail"] = int(ds["fail"]) + (2 if crit else 1)
			ds["stable"] = false
			lines.append("%s: провал спасброска от смерти (%d из 3)" % [me["name"], mini(3, int(ds["fail"]))])
			if int(ds["fail"]) >= 3:
				s.combat["outcome"] = "dead"
			return
		if dmg - hp >= int(me["max_hp"]):  # massive damage
			me["hp"] = 0
			s.combat["outcome"] = "dead"
			lines.append("%s погибает на месте" % me["name"])
			return
	if dmg >= hp and hp > 0 and survives(s, data, who, dmg, dtype, crit, lines):
		me["hp"] = 1
	else:
		me["hp"] = maxi(0, hp - dmg)
	_after(s, data, who, dmg, lines)
	if int(me["hp"]) > 0 or not fight:
		return
	if hero:
		lines.append_array(ConditionRules.impose(s, data, {"condition": "unconscious", "ends": {"rest": "long"}, "source": {"kind": "engine", "name": "0 HP"}}))
		s.combat["death_saves"] = {"ok": 0, "fail": 0}
		f.erase("raging")
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
		lines.append(("%s развеивается" if summoned else "%s падает без сознания") % who["name"])
		MonsterRules.release(s, data, who, lines)
		return
	if by_hero and (ArenaRules.yield_bout(s) or bool(s.combat.get("nonlethal", false)) and bool(s.combat.get("melee_strike", false))):
		who["status"] = "unconscious"  # v0.7.45: in a bout to surrender any blow only knocks out; 5e: a melee blow at 0 HP may knock out (v0.7.22.11)
		lines.append("%s оглушён и падает без сознания" % who["name"])
		return
	who["status"] = "dead"
	lines.append("%s повержен" % who["name"])
	FeatureRules.on_kill(s, data, lines)
	MonsterRules.release(s, data, who, lines)
	MonsterRules.death_burst(s, data, who, lines)


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
		if Sheet.saved(s, data, who, "con", dc):
			lines.append("%s: %s (Тел против Сл %d) — встаёт с 1 HP" % [name, uf["name"], dc])
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
	if bool(r["ok"]):
		lines.append("%s: концентрация удержана (%s)" % [name, r["text"]])
	else:
		lines.append_array(ConditionRules.lose_concentration(s, data, who, r["text"]))
