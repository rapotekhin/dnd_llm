class_name MonsterRules
extends RefCounted
## Monsters by 5e (roadmap v0.7.9 «Правила 5e: монстры»), the parts CombatRules calls:
## - effects of attacks on the hero (`action.effect`, parsed from the SRD by tools/srd_import.py, hand fixes in
##   tools/srd/riders.json): a save, a condition with its duration and repeat save, a grapple with its escape DC (and
##   restrained while it lasts), save damage, unconscious when the save fails by 5, paralysis when the poison drops the
##   hero to 0, life drain, petrification step by step; immune races and sizes;
## - recharge (d6 at the start of the monster's turn) and uses per day of actions;
## - traits: keen senses, charge and pounce, blood frenzy, reckless, sunlight sensitivity, relentless and undead
##   fortitude, death burst, nimble escape, surprise attack, ambusher, martial advantage, sneak attack, aggressive,
##   flyby, save advantages (magic resistance, dark devotion, fey ancestry, gnome cunning, brave, duergar resilience);
## - casters: spells the engine resolves for the hero (damage, conditions, healing) with slots, uses and concentration;
## - the Parry reaction; holds that end with the grappler.
## Pure: randomness from s.rng.

const KEEN := ["keen_smell", "keen_hearing", "keen_sight", "keen_hearing_and_smell", "keen_hearing_and_sight", "keen_sight_and_smell", "keen_senses"]
const CHARGES := ["charge", "pounce", "trampling_charge"]


static func trait_of(data: Dictionary, f: Dictionary, id: String) -> Dictionary:
	for t: Dictionary in Sheet.template(data, f).get("traits", []):
		if str(t["id"]) == id:
			return t
	return {}


## Its template's, its class's or its race's.
static func has_trait(data: Dictionary, f: Dictionary, id: String) -> bool:
	return not trait_of(data, f, id).is_empty() or CharacterRules.has_feature(f, id) or CharacterRules.has_trait(f, id)


# --- uses of actions ---------------------------------------------------------------------------------


static func available(f: Dictionary, a: Dictionary) -> bool:
	var key := str(a.get("name_en", ""))
	if a.has("recharge"):
		return not (f.get("spent", {}) as Dictionary).has(key)
	if a.has("per_day"):
		return int(f.get("used", {}).get(key, 0)) < int(a["per_day"])
	return true


static func spend(f: Dictionary, a: Dictionary) -> void:
	var key := str(a.get("name_en", ""))
	if a.has("recharge"):
		var spent: Dictionary = f.get("spent", {})
		spent[key] = int(a["recharge"])
		f["spent"] = spent
	if a.has("per_day"):
		var used: Dictionary = f.get("used", {})
		used[key] = int(used.get(key, 0)) + 1
		f["used"] = used


## The start of a monster's turn: recharge rolls, a reckless one goes all in, the turn's flags reset. Lines.
static func start_turn(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var spent: Dictionary = f.get("spent", {})
	for key: String in spent.keys():
		if s.rng.randi_range(1, 6) >= int(spent[key]):
			spent.erase(key)
			for a: Dictionary in Sheet.template(data, f).get("actions", []):
				if str(a["name_en"]) == key:
					lines.append("%s: «%s» снова готово" % [f["name"], a["name"]])
	f["once"] = []  # once-per-turn extras used (martial advantage, sneak attack)
	f["reckless"] = has_trait(data, f, "reckless")


## The best action of this kind (melee / ranged) it can use now at `t`: one that would lay a condition `t` does
## not have yet comes first (decision of the author: control before damage), then the surest hit.
static func pick(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, kind: String) -> Dictionary:
	var best := {}
	var control := {}
	var it := Sheet.holder(s, t)
	for a: Dictionary in Sheet.template(data, f).get("actions", []):
		var ok := str(a.get("kind")) == kind or (kind == "ranged" and a.has("range"))
		if not ok or not available(f, a):
			continue
		if kind == "ranged" and str(a.get("kind")) == "melee" and (f.get("thrown", []) as Array).has(str(a.get("name_en", ""))):
			continue  # v0.7.22.19 (#13): a thrown dagger is gone — no second throw
		if bool(a.get("effect", {}).get("target_prone", false)) and not ConditionRules.has(it, "prone"):
			continue  # hooves only for one who lies down
		var cond := str(a.get("effect", {}).get("condition", ""))
		if not cond.is_empty() and not ConditionRules.has(it, cond) and works_on(s, data, t, a.get("effect", {})):
			if control.is_empty() or int(a.get("to_hit", 0)) > int(control.get("to_hit", 0)):
				control = a
		if (a.get("damage", []) as Array).is_empty():
			continue  # a web: only as control
		if best.is_empty() or int(a.get("to_hit", 0)) > int(best.get("to_hit", 0)):
			best = a
	return control if not control.is_empty() else best


## A save action worth using now at `t` (a breath, a gaze, a song): ready, `t` within its area, and — for a pure
## condition — not under it already. {} when none.
static func save_action(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, squares: int) -> Dictionary:
	for a: Dictionary in Sheet.template(data, f).get("actions", []):
		if str(a.get("kind")) != "save" or not available(f, a):
			continue
		var fx: Dictionary = a.get("effect", {})
		if squares > FightGrid.squares_of(data, int(fx.get("area", {}).get("ft", 5))):
			continue
		var cond := str(fx.get("condition", ""))
		if (a.get("damage", []) as Array).is_empty() and (cond.is_empty() or ConditionRules.has(Sheet.holder(s, t), cond)):
			continue
		if not works_on(s, data, t, fx):
			continue
		return a
	return {}


# --- effects on anybody ---------------------------------------------------------------------------------


## The effect takes on `t`: its race, its size, what its template cannot be.
static func works_on(s: GameSession, data: Dictionary, t: Dictionary, fx: Dictionary) -> bool:
	if (fx.get("immune_races", []) as Array).has(str(Sheet.holder(s, t).get("race", ""))):
		return false
	if fx.has("size_max") and CombatRules.SIZES.find(Sheet.size(s, data, t)) > CombatRules.SIZES.find(str(fx["size_max"])):
		return false
	return not CombatRules.immune_to(data, t, str(fx.get("condition", "")))


static func tag_of(fx: Dictionary, a: Dictionary) -> String:
	if fx.has("tag"):
		return str(fx["tag"])
	var cond := str(fx.get("condition", ""))
	var tags: Array[String] = []
	if cond == "poisoned" or str(fx.get("damage", {}).get("type", "")) == "poison" \
			or (a.get("damage", []) as Array).any(func(d: Dictionary) -> bool: return str(d.get("type", "")) == "poison") and fx.has("save"):
		tags.append("poison")
	if cond == "charmed":
		tags.append("charm")
	if cond == "frightened":
		tags.append("fear")
	if cond == "unconscious":
		tags.append("sleep")
	if bool(fx.get("magic", false)):
		tags.append("magic")
	return ",".join(tags)


## What a hit (or a failed save of a save action) brings to `t` besides the damage. `dealt` — the damage of the hit (life
## drain), `save_result` — the save already rolled by a save action ({} — roll here). Lines.
static func apply_effect(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, a: Dictionary, dealt: int, lines: Array[String],
		save_result: Dictionary = {}) -> void:
	var fx: Dictionary = a.get("effect", {})
	var me := Sheet.holder(s, t)
	var hero := Sheet.is_hero(t)
	if fx.is_empty() or str(s.combat.get("outcome", "")) == "dead" or not Attack.up(s, t):
		return  # a downed hero makes no saves: the bite already did its worst
	if not works_on(s, data, t, fx):
		if fx.has("condition"):
			lines.append("%s: на %s это не действует" % [a["name"], me.get("name", "")])
		return
	var tag := tag_of(fx, a)
	var failed := true
	var margin := 0
	var save_at := -1
	if not save_result.is_empty():
		failed = not bool(save_result["ok"])
		margin = int(save_result["dc"]) - int(save_result["total"])
	elif fx.has("save"):
		var r := Sheet.save(s, data, t, str(fx["save"]["ability"]), int(fx["save"]["dc"]), tag)
		failed = not bool(r["ok"])
		margin = int(fx["save"]["dc"]) - int(r["total"])
		lines.append("%s: спасбросок %s" % [me.get("name", ""), r["text"]])
		save_at = lines.size() - 1
	if fx.has("damage"):
		var dmg := CombatRules.roll_dice(s.rng, str(fx["damage"]["dice"]))
		if not failed:
			dmg = dmg / 2 if bool(fx["damage"].get("half", false)) else 0
		var adj := Sheet.damage(s, data, t, str(fx["damage"]["type"]), dmg)
		dmg = int(adj["damage"])
		if dmg > 0:
			lines.append("%s: ещё %d (%s)%s" % [a["name"], dmg, data["misc"]["damage_types"].get(str(fx["damage"]["type"]), fx["damage"]["type"]),
				(", " + str(adj["note"])) if not str(adj["note"]).is_empty() else ""])
			if hero and bool(fx.get("zero_hp_paralyzed", false)) and int(me["hp"]) - dmg <= 0 and -(int(me["hp"]) - dmg) < int(me["max_hp"]):
				_poisoned_stable(s, data, f, a, lines)
				return
			CombatRules.hurt(s, data, t, dmg, lines, str(fx["damage"]["type"]), false, Sheet.is_hero(f))
	if not failed and fx.has("save"):
		return
	if not failed and not save_result.is_empty():
		return
	if bool(fx.get("drain", false)) and dealt > 0 and Attack.up(s, t):
		_drain(s, data, f, t, a, dealt)
		lines.append("%s: максимум хитов −%d до долгого отдыха" % [me.get("name", ""), dealt])
	if hero and fx.has("disease"):  # it shows after its incubation, out of the fight (v0.7.23.1)
		lines.append_array(DiseaseRules.contract(s, data, str(fx["disease"])))
	var cond := str(fx.get("condition", ""))
	if cond.is_empty() or not Attack.up(s, t) and cond != "poisoned":
		return
	_lay(s, data, f, t, a, fx, cond, lines)
	if save_at >= 0 and save_at == lines.size() - 2:  # the save and what it brought — one line of the log (v0.7.9)
		lines[save_at] = lines[save_at] + " → " + lines[lines.size() - 1].trim_prefix("%s: " % me.get("name", ""))
		lines.remove_at(lines.size() - 1)
	if fx.has("fail_by_5") and margin >= 5:
		var fx5 := fx.duplicate()
		fx5["wake"] = true
		_lay(s, data, f, t, a, fx5, str(fx["fail_by_5"]), lines)


## Life drain: the maximum of hit points goes down until the long rest.
static func _drain(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, a: Dictionary, dealt: int) -> void:
	if Sheet.is_hero(t):
		ConditionRules.add_effect(s.character, {"condition": "", "max_hp": -dealt, "ends": {"rest": "long"}, "source": _source(f, a)})
		CharacterRules.refresh(s.character, data, s.items)
	else:
		t["max_hp"] = maxi(1, int(t["max_hp"]) - dealt)
		t["hp"] = mini(int(t["hp"]), int(t["max_hp"]))


static func _source(f: Dictionary, a: Dictionary) -> Dictionary:
	return {"kind": "monster", "id": str(f.get("id", "")), "name": "%s — %s" % [f.get("name", ""), a.get("name", "")]}


## Lays one condition on `t` (and the one that comes with it — restrained while grappled).
static func _lay(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, a: Dictionary, fx: Dictionary, cond: String, lines: Array[String]) -> void:
	var me := Sheet.holder(s, t)
	var duration := str(fx.get("duration", ""))
	var e := {"condition": cond, "source": _source(f, a), "by": str(f["id"]),
		"ends": ConditionRules.ends_for(s, data, duration) if not duration.is_empty() else {}}
	if bool(fx.get("repeat", false)) and fx.has("save"):
		e["save"] = {"ability": str(fx["save"]["ability"]), "dc": int(fx["save"]["dc"]), "tag": tag_of(fx, a), "repeat": true,
			"once": bool(fx.get("repeat_once", false))}
		if fx.has("escalate"):
			e["escalate"] = fx["escalate"]
	elif bool(fx.get("repeat", false)) and str(a.get("kind")) == "save":
		e["save"] = {"ability": str(a["save"]["ability"]), "dc": int(a["save"]["dc"]), "tag": tag_of(fx, a), "repeat": true}
	if fx.has("escape_dc"):
		e["escape_dc"] = int(fx["escape_dc"])
	if bool(fx.get("wake", false)):
		e["wake"] = true
	if cond == "grappled":
		e["hold"] = true  # ends with the grappler
	lines.append_array(ConditionRules.impose(s, data, e, t))
	var what := ConditionRules.name_of(data, cond).to_lower()
	if fx.has("also") and cond == str(fx.get("condition", "")):
		var also := {"condition": str(fx["also"]), "source": _source(f, a), "by": str(f["id"]), "ends": e["ends"], "with": cond}
		lines.append_array(ConditionRules.impose(s, data, also, t))
		what += " и " + ConditionRules.name_of(data, str(fx["also"])).to_lower()
	if Sheet.is_hero(t):
		CharacterRules.refresh(me, data, s.items)
	var left := ConditionRules.left_text(s, e)
	lines.append("%s: %s%s%s" % [me.get("name", ""), what, (" (%s)" % left) if e["ends"].has("at") else "",
		(", вырваться — Сл %d" % int(e["escape_dc"])) if e.has("escape_dc") else ""])


## A spider's poison dropped the hero to 0: stable, poisoned for an hour and paralysed while so (5e).
static func _poisoned_stable(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	c["hp"] = 0
	s.combat["death_saves"] = {"ok": 0, "fail": 0, "stable": true}
	ConditionRules.impose(s, data, {"condition": "unconscious", "ends": {"rest": "long"}, "source": {"kind": "engine", "name": "0 HP"}})
	var ends := ConditionRules.ends_for(s, data, "hour")
	ConditionRules.add_effect(c, {"condition": "poisoned", "ends": ends, "source": _source(f, a), "by": str(f["id"])})
	ConditionRules.add_effect(c, {"condition": "paralyzed", "ends": ends, "source": _source(f, a), "by": str(f["id"]), "with": "poisoned"})
	lines.append("%s падает: яд сковал тело — без сознания, но жив (отравлен и парализован на час)" % c.get("name", ""))


## The holds of a grappler end when it dies, is incapacitated or moves off (5e), and with `conc` what it keeps by concentration. Lines.
static func release(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String], conc: bool = true) -> void:
	var all: Array[Dictionary] = [s.character]
	for id: String in s.combat.get("fighters", []):
		all.append(CombatRules.fighter(s, id))
	for me: Dictionary in all:
		for e: Dictionary in ConditionRules.effects(me).duplicate():
			if str(e.get("by", "")) == str(f["id"]) and (bool(e.get("hold", false)) or conc and bool(e.get("conc", false))):
				ConditionRules.remove_effect(me, int(e["uid"]))
				lines.append("%s больше не %s" % [me.get("name", ""), ConditionRules.name_of(data, str(e.get("condition", ""))).to_lower()])
	if conc and f.has("concentration"):
		lines.append_array(CombatRules.end_spell(s, data, str(f["concentration"]), str(f["id"])))
		f.erase("concentration")
	CharacterRules.refresh(s.character, data, s.items)


# --- traits in the attack -------------------------------------------------------------------------------


static func passive_bonus(data: Dictionary, f: Dictionary) -> int:
	return 5 if KEEN.any(func(t: String) -> bool: return has_trait(data, f, t)) else 0


## The game's sun: morning or day, and the room or its location is not indoors (`indoor` in the pack).
static func sunlit(s: GameSession, data: Dictionary) -> bool:
	if not TimeRules.part(s, data) in ["morning", "day"]:
		return false
	var w := WorldView.new(data["world"])
	return not w.flag(s.room_id, "indoor")


## `t` was caught by surprise in this first round.
static func caught(s: GameSession, t: Dictionary) -> bool:
	return int(s.combat.get("round", 1)) == 1 and (bool(t.get("surprised", false)) or (Sheet.is_hero(t) and bool(s.combat.get("hero_surprised", false))))


## Why its attack has advantage / disadvantage from its traits: {"adv": [], "dis": []}.
static func attack_mods(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, near: bool) -> Dictionary:
	var it := Sheet.holder(s, t)
	var adv: Array[String] = []
	var dis: Array[String] = []
	if Sheet.has_trait(s, data, f, "blood_frenzy") and int(it.get("hp", 0)) < int(it.get("max_hp", 0)) and near:
		adv.append("неистовство крови")
	if Sheet.has_trait(s, data, f, "ambusher") and caught(s, t):
		adv.append("засадник")
	if (has_trait(data, f, "sunlight_sensitivity") or has_trait(data, f, "sunlight_weakness")) and sunlit(s, data):
		dis.append("солнце")
	return {"adv": adv, "dis": dis}


## Extra damage of a hit from traits (charge after a run, martial advantage, sneak attack, surprise attack):
## {"damage", "notes", "prone": save fx of a charge or {}}.
static func extra_on_hit(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, a: Dictionary, adv: bool, dis: bool, crit: bool) -> Dictionary:
	var out := {"damage": 0, "notes": [], "prone": {}}
	var once: Array = f.get("once", [])
	for id: String in CHARGES:
		var tr := trait_of(data, f, id)
		if tr.is_empty() or str(a.get("kind")) != "melee" or int(f.get("points", {}).get("walked", 0)) < int(FightGrid.cfg(data)["charge"]) or once.has("charge"):
			continue
		var fx: Dictionary = tr.get("effect", {})
		once.append("charge")
		if fx.has("extra"):
			out["damage"] = int(out["damage"]) + CombatRules.roll_dice(s.rng, str(fx["extra"]["dice"]), crit)
			(out["notes"] as Array).append(str(tr["name"]))
		if fx.has("save") and str(fx.get("condition", "")) == "prone":
			out["prone"] = {"save": fx["save"], "condition": "prone", "pounce": id != "charge", "name": str(tr["name"])}
	var ally := CombatRules.friend_beside(s, f, t)
	var ma := trait_of(data, f, "martial_advantage")
	if not ma.is_empty() and ally and not once.has("martial"):
		once.append("martial")
		out["damage"] = int(out["damage"]) + CombatRules.roll_dice(s.rng, str(ma.get("effect", {}).get("extra", {}).get("dice", "2d6")), crit)
		(out["notes"] as Array).append(str(ma["name"]))
	var sa := trait_of(data, f, "sneak_attack_1/turn")
	if not sa.is_empty() and not once.has("sneak") and not dis and (adv or ally):
		once.append("sneak")
		out["damage"] = int(out["damage"]) + CombatRules.roll_dice(s.rng, str(sa.get("effect", {}).get("extra", {}).get("dice", "2d6")), crit)
		(out["notes"] as Array).append(str(sa["name"]))
	var su := trait_of(data, f, "surprise_attack")
	if not su.is_empty() and caught(s, t) and not once.has("surprise"):
		once.append("surprise")
		out["damage"] = int(out["damage"]) + CombatRules.roll_dice(s.rng, str(su.get("effect", {}).get("extra", {}).get("dice", "2d6")), crit)
		(out["notes"] as Array).append(str(su["name"]))
	f["once"] = once
	return out


## A charge or pounce knocks `t` down (a Strength save); a pounce then bites it as a bonus action. True when the bite follows.
static func charge_prone(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, spec: Dictionary, lines: Array[String]) -> bool:
	var me := Sheet.holder(s, t)
	if spec.is_empty() or not Attack.up(s, t) or ConditionRules.has(me, "prone"):
		return false
	var r := Sheet.save(s, data, t, str(spec["save"]["ability"]), int(spec["save"]["dc"]))
	lines.append("%s (%s): спасбросок %s" % [f["name"], spec["name"], r["text"]])
	if bool(r["ok"]):
		return false
	ConditionRules.impose(s, data, {"condition": "prone", "ends": {}, "source": {"kind": "monster", "id": str(f["id"]), "name": "%s — %s" % [f["name"], spec["name"]]}}, t)
	lines.append("%s сбит с ног" % me.get("name", ""))
	return bool(spec.get("pounce", false))


# --- traits of the monster's own body --------------------------------------------------------------------


## Relentless (boar) and Undead Fortitude (zombie): a blow that would drop it leaves it at 1 HP. True when so.
static func survives(s: GameSession, data: Dictionary, t: Dictionary, dmg: int, dtype: String, crit: bool, lines: Array[String]) -> bool:
	if CharacterRules.has_trait(t, "relentless_endurance") and not bool(t.get("relentless_used", false)):
		t["relentless_used"] = true
		lines.append("%s остаётся на ногах с 1 HP" % t["name"])
		return true
	var r := trait_of(data, t, "relentless")
	if not r.is_empty() and not bool(t.get("relentless_used", false)) and dmg <= int(r.get("effect", {}).get("relentless", 0)):
		t["relentless_used"] = true
		lines.append("%s: %s — остаётся на ногах с 1 HP" % [t["name"], r["name"]])
		return true
	var uf := trait_of(data, t, "undead_fortitude")
	if not uf.is_empty() and dtype != "radiant" and not crit:
		var dc := 5 + dmg
		if Sheet.saved(s, data, t, "con", dc):
			lines.append("%s: %s (Тел против Сл %d) — встаёт с 1 HP" % [t["name"], uf["name"], dc])
			return true
	return false


## Death Burst (mephits, magmin): everyone next to it saves or takes it. Lines.
static func death_burst(s: GameSession, data: Dictionary, t: Dictionary, lines: Array[String]) -> void:
	var db := trait_of(data, t, "death_burst")
	if db.is_empty():
		return
	var said := false
	for id: String in CombatRules.foes_of(s, t) + CombatRules.friends_of(s, t):
		var o := CombatRules.fighter(s, id)
		if id == str(t["id"]) or not FightGrid.touching(t, o) or not Attack.up(s, o):
			continue
		if not said:
			lines.append("%s: %s" % [t["name"], db["name"]])
			said = true
		apply_effect(s, data, t, o, {"name": str(db["name"]), "effect": db.get("effect", {}), "damage": []}, 0, lines)


## Saving throw advantages of a monster's traits: magic resistance (spells), dark devotion and fey ancestry (charm,
## fear), gnome cunning (INT / WIS / CHA against magic), brave (fear), duergar resilience. `tags` — what the save is
## against (magic, charm, fear, sleep, paralysis, poison).
static func save_advantage(data: Dictionary, f: Dictionary, ability: String, tags: Array) -> bool:
	if tags.has("fighting"):  # Charm Person on a foe in a fight (v0.7.13)
		return true
	if tags.has("magic") and (has_trait(data, f, "magic_resistance") or has_trait(data, f, "duergar_resilience")):
		return true
	if (tags.has("charm") or tags.has("fear")) and has_trait(data, f, "dark_devotion"):
		return true
	if tags.has("charm") and has_trait(data, f, "fey_ancestry"):
		return true
	if tags.has("magic") and ability in ["int", "wis", "cha"] and has_trait(data, f, "gnome_cunning"):
		return true
	if tags.has("fear") and has_trait(data, f, "brave"):
		return true
	return (tags.has("charm") or tags.has("paralysis") or tags.has("poison")) and has_trait(data, f, "duergar_resilience")


## Immune to a magical sleep (fey ancestry).
static func sleep_immune(data: Dictionary, f: Dictionary) -> bool:
	return has_trait(data, f, "fey_ancestry")


# --- casters -------------------------------------------------------------------------------------------


## The spells the monster can cast now with what it would spend: [{id, slot (0 — cantrip or innate)}].
static func castable(data: Dictionary, f: Dictionary) -> Array[Dictionary]:
	var sc: Dictionary = Sheet.template(data, f).get("spellcasting", {})
	var out: Array[Dictionary] = []
	if sc.is_empty():
		return out
	if not f.has("slots"):
		f["slots"] = (sc.get("slots", {}) as Dictionary).duplicate()
	for x: Dictionary in sc["spells"]:
		var id := str(x["id"])
		if not data["spells"].has(id):
			continue
		var lv := int(x.get("level", 0))
		if x.has("per_day"):
			if int(f.get("used", {}).get("spell:" + id, 0)) < int(x["per_day"]):
				out.append({"id": id, "slot": 0, "per_day": true})
			continue
		if lv == 0:
			out.append({"id": id, "slot": 0})
			continue
		for k in range(lv, 6):
			if int(f["slots"].get(str(k), 0)) > 0:
				out.append({"id": id, "slot": k})
				break
	return out


## It pays for a spell by what `castable` said.
static func pay_spell(f: Dictionary, spell: String, how: Dictionary) -> void:
	var slot := int(how.get("slot", 0))
	if slot > 0:
		f["slots"][str(slot)] = int(f["slots"][str(slot)]) - 1
	if bool(how.get("per_day", false)):
		var used: Dictionary = f.get("used", {})
		used["spell:" + spell] = int(used.get("spell:" + spell, 0)) + 1
		f["used"] = used


static func _spell_reach(data: Dictionary, id: String) -> int:
	return maxi(1, FightGrid.squares_of(data, int(data["spells"][id].get("range_ft", 0))))


static func _caster_level(data: Dictionary, f: Dictionary) -> int:
	return maxi(1, int(Sheet.template(data, f).get("spellcasting", {}).get("level", 1)))


## Command's word for `t`: one that does something now (Grovel — not when prone, Drop — only with a weapon in hand);
## {} for a spell without words.
static func _command_word(s: GameSession, spec: Dictionary, t: Dictionary = Sheet.HERO) -> Dictionary:
	var c := Sheet.holder(s, t)
	var fits: Array = (spec.get("words", []) as Array).filter(func(w: Dictionary) -> bool:
		if not str(w.get("not_if", "")).is_empty() and ConditionRules.has(c, str(w["not_if"])):
			return false
		return not bool(w.get("drop", false)) or not str(c.get("equipped", {}).get("main_hand", "")).is_empty())
	return fits[s.rng.randi_range(0, fits.size() - 1)] if not fits.is_empty() else {}


## Damage breaks a monster's concentration on a failed CON save (DC 10 or half the damage). Lines.
static func concentration_check(s: GameSession, data: Dictionary, f: Dictionary, dmg: int, lines: Array[String]) -> void:
	var spell := str(f.get("concentration", ""))
	if spell.is_empty() or dmg <= 0:
		return
	if int(f["hp"]) > 0 and Sheet.saved(s, data, f, "con", maxi(10, dmg / 2)):
		return
	lines.append("%s теряет концентрацию на «%s»" % [f["name"], data["spells"].get(spell, {}).get("name", spell)])
	release(s, data, f, lines)


## A short line of what an action does besides its damage, for the card of an inspected foe: «сбивает с ног (Сил Сл 11)»,
## «хватает (вырваться — Сл 14) и опутывает», «яд 2к8 (Тел Сл 11, половина)», «перезарядка 5–6».
static func effect_text(data: Dictionary, a: Dictionary) -> String:
	var fx: Dictionary = a.get("effect", {})
	var parts: Array[String] = []
	var sv := ""
	if fx.has("save"):
		sv = "%s Сл %d" % [CombatRules.ab_name(str(fx["save"]["ability"])), int(fx["save"]["dc"])]
	if fx.has("damage"):
		parts.append("%s %s (%s%s)" % [str(data["misc"]["damage_types"].get(str(fx["damage"]["type"]), fx["damage"]["type"])),
			str(fx["damage"]["dice"]).replace("d", "к"), sv, ", половина" if bool(fx["damage"].get("half", false)) else ""])
	var cond := str(fx.get("condition", ""))
	if not cond.is_empty():
		var t := ConditionRules.name_of(data, cond).to_lower()
		if fx.has("escape_dc"):
			t += " (вырваться — Сл %d)" % int(fx["escape_dc"])
		if fx.has("also"):
			t += " и " + ConditionRules.name_of(data, str(fx["also"])).to_lower()
		if not sv.is_empty() and not fx.has("damage"):
			t += " (%s)" % sv
		if bool(fx.get("repeat", false)):
			t += ", повтор спасброска"
		parts.append(t)
	if bool(fx.get("drain", false)):
		parts.append("высасывает максимум хитов (%s)" % sv)
	if fx.has("disease"):
		parts.append("заражает: %s (%s)" % [DiseaseRules.def_of(null, data, str(fx["disease"])).get("name", fx["disease"]), sv])
	if a.has("master_effect"):
		parts.append(str(a["master_effect"]).get_slice(" — ", 0))
	if a.has("recharge"):
		parts.append("перезарядка %d–6" % int(a["recharge"]) if int(a["recharge"]) < 6 else "перезарядка 6")
	if a.has("per_day"):
		parts.append("%d раз за бой" % int(a["per_day"]))
	return ", ".join(parts)


## Darkvision of a monster (v0.7.10): it fights in the dark of a dungeon without trouble.
static func sees_in_dark(data: Dictionary, f: Dictionary) -> bool:
	return int(Sheet.template(data, f).get("darkvision", 0)) > 0


