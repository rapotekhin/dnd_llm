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


static func monster(data: Dictionary, f: Dictionary) -> Dictionary:
	if f.has("actions"):  # a fighter that lost its weapon (v0.7.22.8)
		var m: Dictionary = (data["monsters"].get(str(f.get("monster", "")), {}) as Dictionary).duplicate()
		m["actions"] = f["actions"]
		return m
	return data["monsters"].get(str(f.get("monster", "")), {})


static func trait_of(data: Dictionary, f: Dictionary, id: String) -> Dictionary:
	for t: Dictionary in monster(data, f).get("traits", []):
		if str(t["id"]) == id:
			return t
	return {}


static func has_trait(data: Dictionary, f: Dictionary, id: String) -> bool:
	return not trait_of(data, f, id).is_empty()


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
			for a: Dictionary in monster(data, f).get("actions", []):
				if str(a["name_en"]) == key:
					lines.append("%s: «%s» снова готово" % [f["name"], a["name"]])
	f["moved"] = 0
	f["once"] = []  # once-per-turn extras used (martial advantage, sneak attack)
	f["reckless"] = has_trait(data, f, "reckless")


## The best action of this kind (melee / ranged) the monster can use now: one that would lay a condition the hero does
## not have yet comes first (decision of the author: control before damage), then the surest hit.
static func pick(s: GameSession, data: Dictionary, f: Dictionary, kind: String) -> Dictionary:
	var best := {}
	var control := {}
	for a: Dictionary in monster(data, f).get("actions", []):
		var ok := str(a.get("kind")) == kind or (kind == "ranged" and a.has("range"))
		if not ok or not available(f, a):
			continue
		if kind == "ranged" and str(a.get("kind")) == "melee" and (f.get("thrown", []) as Array).has(str(a.get("name_en", ""))):
			continue  # v0.7.22.19 (#13): a thrown dagger is gone — no second throw
		if bool(a.get("effect", {}).get("target_prone", false)) and not ConditionRules.has(s.character, "prone"):
			continue  # hooves only for one who lies down
		var cond := str(a.get("effect", {}).get("condition", ""))
		if not cond.is_empty() and not ConditionRules.has(s.character, cond) and _works_on_hero(s, data, a.get("effect", {})):
			if control.is_empty() or int(a.get("to_hit", 0)) > int(control.get("to_hit", 0)):
				control = a
		if (a.get("damage", []) as Array).is_empty():
			continue  # a web: only as control
		if best.is_empty() or int(a.get("to_hit", 0)) > int(best.get("to_hit", 0)):
			best = a
	return control if not control.is_empty() else best


## A save action worth using now (a breath, a gaze, a song): ready, the hero within its area, and — for a pure
## condition — not under it already. {} when none.
static func save_action(s: GameSession, data: Dictionary, f: Dictionary, dist_cols: int) -> Dictionary:
	for a: Dictionary in monster(data, f).get("actions", []):
		if str(a.get("kind")) != "save" or not available(f, a):
			continue
		var fx: Dictionary = a.get("effect", {})
		var reach := CombatRules.range_cols(data, int(fx.get("area", {}).get("ft", 5)))
		if dist_cols > reach:
			continue
		var cond := str(fx.get("condition", ""))
		if (a.get("damage", []) as Array).is_empty() and (cond.is_empty() or ConditionRules.has(s.character, cond)):
			continue
		if not _works_on_hero(s, data, fx):
			continue
		return a
	return {}


# --- effects on the hero ----------------------------------------------------------------------------------


static func _works_on_hero(s: GameSession, data: Dictionary, fx: Dictionary) -> bool:
	var c := s.character
	if (fx.get("immune_races", []) as Array).has(str(c.get("race", ""))):
		return false
	if fx.has("size_max") and CombatRules.SIZES.find(CombatRules.hero_size(s, data)) > CombatRules.SIZES.find(str(fx["size_max"])):
		return false
	return true


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


## What a hit (or a failed save of a save action) brings besides the damage. `dealt` — the damage of the hit (life
## drain), `save_result` — the hero's save already rolled by a save action ({} — roll here). Lines.
static func apply_effect(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, dealt: int, lines: Array[String],
		save_result: Dictionary = {}) -> void:
	var fx: Dictionary = a.get("effect", {})
	var c := s.character
	if fx.is_empty() or str(s.combat.get("outcome", "")) == "dead" or int(c.get("hp", 0)) <= 0:
		return  # a downed hero makes no saves: the bite already did its worst
	if not _works_on_hero(s, data, fx):
		if fx.has("condition"):
			lines.append("%s: на %s это не действует" % [a["name"], c.get("name", "")])
		return
	var tag := tag_of(fx, a)
	var failed := true
	var margin := 0
	var save_at := -1
	if not save_result.is_empty():
		failed = not bool(save_result["ok"])
		margin = int(save_result["dc"]) - int(save_result["total"])
	elif fx.has("save"):
		var r := HeroDefense.save(s, data, str(fx["save"]["ability"]), int(fx["save"]["dc"]), tag)
		failed = not bool(r["ok"])
		margin = int(fx["save"]["dc"]) - int(r["total"])
		lines.append("%s: спасбросок %s" % [c.get("name", ""), r["text"]])
		save_at = lines.size() - 1
	if fx.has("damage") and int(c.get("hp", 0)) > 0:
		var dmg := CombatRules.roll_dice(s.rng, str(fx["damage"]["dice"]))
		if not failed:
			dmg = dmg / 2 if bool(fx["damage"].get("half", false)) else 0
		var adj := HeroDefense.adjust(s, data, str(fx["damage"]["type"]), dmg)
		dmg = int(adj["damage"])
		if dmg > 0:
			lines.append("%s: ещё %d (%s)%s" % [a["name"], dmg, data["misc"]["damage_types"].get(str(fx["damage"]["type"]), fx["damage"]["type"]),
				(", " + str(adj["note"])) if not str(adj["note"]).is_empty() else ""])
			if bool(fx.get("zero_hp_paralyzed", false)) and int(c["hp"]) - dmg <= 0 and -(int(c["hp"]) - dmg) < int(c["max_hp"]):
				_poisoned_stable(s, data, f, a, lines)
				return
			CombatRules._hurt_player(s, data, dmg, false, lines)
	if not failed and fx.has("save"):
		return
	if not failed and not save_result.is_empty():
		return
	if bool(fx.get("drain", false)) and dealt > 0 and int(c.get("hp", 0)) > 0:
		ConditionRules.add_effect(c, {"condition": "", "max_hp": -dealt, "ends": {"rest": "long"}, "source": _source(f, a)})
		CharacterRules.refresh(c, data, s.items)
		lines.append("%s: максимум хитов −%d до долгого отдыха" % [c.get("name", ""), dealt])
	if fx.has("disease"):  # it shows after its incubation, out of the fight (v0.7.23.1)
		lines.append_array(DiseaseRules.contract(s, data, str(fx["disease"])))
	var cond := str(fx.get("condition", ""))
	if cond.is_empty() or int(c.get("hp", 0)) <= 0 and cond != "poisoned":
		return
	_lay(s, data, f, a, fx, cond, lines)
	if save_at >= 0 and save_at == lines.size() - 2:  # the save and what it brought — one line of the log (v0.7.9)
		lines[save_at] = lines[save_at] + " → " + lines[lines.size() - 1].trim_prefix("%s: " % c.get("name", ""))
		lines.remove_at(lines.size() - 1)
	if fx.has("fail_by_5") and margin >= 5:
		var fx5 := fx.duplicate()
		fx5["wake"] = true
		_lay(s, data, f, a, fx5, str(fx["fail_by_5"]), lines)


static func _source(f: Dictionary, a: Dictionary) -> Dictionary:
	return {"kind": "monster", "id": str(f.get("id", "")), "name": "%s — %s" % [f.get("name", ""), a.get("name", "")]}


## Lays one condition of a monster on the hero (and the one that comes with it — restrained while grappled).
static func _lay(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, fx: Dictionary, cond: String, lines: Array[String]) -> void:
	var c := s.character
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
	lines.append_array(ConditionRules.impose(s, data, e))
	var what := ConditionRules.name_of(data, cond).to_lower()
	if fx.has("also") and cond == str(fx.get("condition", "")):
		var also := {"condition": str(fx["also"]), "source": _source(f, a), "by": str(f["id"]), "ends": e["ends"], "with": cond}
		lines.append_array(ConditionRules.impose(s, data, also))
		what += " и " + ConditionRules.name_of(data, str(fx["also"])).to_lower()
	CharacterRules.refresh(c, data, s.items)
	var left := ConditionRules.left_text(s, e)
	lines.append("%s: %s%s%s" % [c.get("name", ""), what, (" (%s)" % left) if e["ends"].has("at") else "",
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


## The holds of a grappler end when it dies, is incapacitated or moves off (5e). Lines.
static func release(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	for e: Dictionary in ConditionRules.effects(c).duplicate():
		if str(e.get("by", "")) == str(f["id"]) and (bool(e.get("hold", false)) or bool(e.get("conc", false))):
			ConditionRules.remove_effect(c, int(e["uid"]))
			lines.append("%s больше не %s" % [c.get("name", ""), ConditionRules.name_of(data, str(e.get("condition", ""))).to_lower()])
	f.erase("concentration")
	CharacterRules.refresh(c, data, s.items)


# --- traits in the attack -------------------------------------------------------------------------------


static func passive_bonus(data: Dictionary, f: Dictionary) -> int:
	return 5 if KEEN.any(func(t: String) -> bool: return has_trait(data, f, t)) else 0


## The game's sun: morning or day, and the room or its location is not indoors (`indoor` in the pack).
static func sunlit(s: GameSession, data: Dictionary) -> bool:
	if not TimeRules.part(s, data) in ["morning", "day"]:
		return false
	var w := WorldView.new(data["world"])
	return not bool(w.room(s.room_id).get("indoor", false)) and not bool(w.location(w.location_id(s.room_id)).get("indoor", false))


## Why a monster's attack on the hero has advantage / disadvantage from its traits: {"adv": [], "dis": []}.
static func attack_mods(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary) -> Dictionary:
	var c := s.character
	var adv: Array[String] = []
	var dis: Array[String] = []
	if has_trait(data, f, "blood_frenzy") and int(c.get("hp", 0)) < int(c.get("max_hp", 0)) and str(a.get("kind")) == "melee":
		adv.append("неистовство крови")
	if bool(f.get("reckless", false)) and str(a.get("kind")) == "melee":
		adv.append("безрассудство")
	if has_trait(data, f, "ambusher") and int(s.combat.get("round", 1)) == 1 and bool(s.combat.get("hero_surprised", false)):
		adv.append("засадник")
	if bool(f.get("hidden", false)):
		adv.append("спрятан")
	if (has_trait(data, f, "sunlight_sensitivity") or has_trait(data, f, "sunlight_weakness")) and sunlit(s, data):
		dis.append("солнце")
	return {"adv": adv, "dis": dis}


## Extra damage of a hit from traits (charge after a run, martial advantage, sneak attack, surprise attack):
## {"damage", "notes", "prone": save fx of a charge or {}}.
static func extra_on_hit(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, adv: bool, dis: bool, crit: bool) -> Dictionary:
	var out := {"damage": 0, "notes": [], "prone": {}}
	var once: Array = f.get("once", [])
	for id: String in CHARGES:
		var t := trait_of(data, f, id)
		if t.is_empty() or str(a.get("kind")) != "melee" or int(f.get("moved", 0)) <= 0 or once.has("charge"):
			continue
		var fx: Dictionary = t.get("effect", {})
		once.append("charge")
		if fx.has("extra"):
			out["damage"] = int(out["damage"]) + CombatRules.roll_dice(s.rng, str(fx["extra"]["dice"]), crit)
			(out["notes"] as Array).append(str(t["name"]))
		if fx.has("save") and str(fx.get("condition", "")) == "prone":
			out["prone"] = {"save": fx["save"], "condition": "prone", "pounce": id != "charge", "name": str(t["name"])}
	var ally := _ally_by_hero(s, f)
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
	if not su.is_empty() and int(s.combat.get("round", 1)) == 1 and bool(s.combat.get("hero_surprised", false)) and not once.has("surprise"):
		once.append("surprise")
		out["damage"] = int(out["damage"]) + CombatRules.roll_dice(s.rng, str(su.get("effect", {}).get("extra", {}).get("dice", "2d6")), crit)
		(out["notes"] as Array).append(str(su["name"]))
	f["once"] = once
	return out


static func _ally_by_hero(s: GameSession, f: Dictionary) -> bool:
	var p := CombatRules.player(s)
	for id: String in CombatRules.enemies(s):
		var o := CombatRules.fighter(s, id)
		if id != str(f["id"]) and int(o["col"]) == int(p["col"]) and not CombatRules.incapacitated(o):
			return true
	return false


## A charge or pounce knocks the hero down (a Strength save); a pounce then bites the prone hero as a bonus action.
## True when the pounce bite follows.
static func charge_prone(s: GameSession, data: Dictionary, f: Dictionary, spec: Dictionary, lines: Array[String]) -> bool:
	if spec.is_empty() or int(s.character.get("hp", 0)) <= 0 or ConditionRules.has(s.character, "prone"):
		return false
	var r := HeroDefense.save(s, data, str(spec["save"]["ability"]), int(spec["save"]["dc"]))
	lines.append("%s (%s): спасбросок %s" % [f["name"], spec["name"], r["text"]])
	if bool(r["ok"]):
		return false
	ConditionRules.impose(s, data, {"condition": "prone", "ends": {}, "source": {"kind": "monster", "id": str(f["id"]), "name": "%s — %s" % [f["name"], spec["name"]]}})
	lines.append("%s сбит с ног" % s.character.get("name", ""))
	return bool(spec.get("pounce", false))


# --- traits of the monster's own body --------------------------------------------------------------------


## Relentless (boar) and Undead Fortitude (zombie): a blow that would drop it leaves it at 1 HP. True when so.
static func survives(s: GameSession, data: Dictionary, t: Dictionary, dmg: int, dtype: String, crit: bool, lines: Array[String]) -> bool:
	var r := trait_of(data, t, "relentless")
	if not r.is_empty() and not bool(t.get("relentless_used", false)) and dmg <= int(r.get("effect", {}).get("relentless", 0)):
		t["relentless_used"] = true
		lines.append("%s: %s — остаётся на ногах с 1 HP" % [t["name"], r["name"]])
		return true
	var uf := trait_of(data, t, "undead_fortitude")
	if not uf.is_empty() and dtype != "radiant" and not crit:
		var dc := 5 + dmg
		if CombatRules._monster_save(s, data, t, "con", dc):
			lines.append("%s: %s (Тел против Сл %d) — встаёт с 1 HP" % [t["name"], uf["name"], dc])
			return true
	return false


## Death Burst (mephits, magmin): the hero next to it saves or takes it. Lines.
static func death_burst(s: GameSession, data: Dictionary, t: Dictionary, lines: Array[String]) -> void:
	var db := trait_of(data, t, "death_burst")
	if db.is_empty() or CombatRules.cols_between(t, CombatRules.player(s)) > 0 or int(s.character.get("hp", 0)) <= 0:
		return
	lines.append("%s: %s" % [t["name"], db["name"]])
	var fx: Dictionary = db.get("effect", {})
	apply_effect(s, data, t, {"name": str(db["name"]), "effect": fx, "damage": []}, 0, lines)


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


## Nimble Escape (goblin): out of the hero's reach, it hides as a bonus action — Stealth against the hero's passive
## Perception. Lines.
static func end_turn(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	if not has_trait(data, f, "nimble_escape") or bool(f.get("hidden", false)) or str(f.get("status")) != "active":
		return
	if CombatRules.cols_between(f, CombatRules.player(s)) == 0:
		return
	var m := monster(data, f)
	var stealth := Roll.d20(s.rng) + int(m.get("skills", {}).get("stealth", CharacterRules.mod(int(m["abilities"].get("dex", 10)))))
	if stealth >= int(s.character.get("passive_perception", 10)):
		f["hidden"] = true
		lines.append("%s прячется (%s)" % [f["name"], trait_of(data, f, "nimble_escape")["name"]])


# --- Parry ---------------------------------------------------------------------------------------------


## Parry (a reaction): +AC against one melee hit it sees, wielding a melee weapon. True when the hit is turned.
static func parry(s: GameSession, data: Dictionary, t: Dictionary, total: int, lines: Array[String]) -> bool:
	for r: Dictionary in monster(data, t).get("reactions", []):
		if not r.has("ac") or bool(t.get("reacted", false)) or CombatRules.incapacitated(t) or ConditionRules.invisible(s.character, data):
			continue
		if not (monster(data, t).get("actions", []) as Array).any(func(a: Dictionary) -> bool: return str(a.get("kind")) == "melee"):
			continue
		if total < int(t["ac"]) + int(r["ac"]):
			t["reacted"] = true
			lines.append("%s парирует (+%d КД)" % [t["name"], int(r["ac"])])
			return true
	return false


# --- casters -------------------------------------------------------------------------------------------


## The spells the monster can cast now with what it would spend: [{id, slot (0 — cantrip or innate)}].
static func castable(data: Dictionary, f: Dictionary) -> Array[Dictionary]:
	var sc: Dictionary = monster(data, f).get("spellcasting", {})
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


## A caster's turn (decision of v0.7.9: the spells the engine resolves for the hero, with slots): heal itself when hurt,
## lay a condition the hero has not got, the strongest damage spell in range, or a damaging cantrip when it is better
## than the weapon. True when it cast (the turn's action is spent).
static func cast_turn(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> bool:
	var options := castable(data, f)
	if options.is_empty() or int(s.character.get("hp", 0)) <= 0 or SpellEffects.silenced(s, int(f["col"])):
		return false  # Silence (v0.7.13.6): no spell from inside
	var d := CombatRules.cols_between(f, CombatRules.player(s))
	var in_range := func(id: String) -> bool:
		return d <= CombatRules.range_cols(data, int(data["spells"][id].get("range_ft", 0))) or int(data["spells"][id].get("range_ft", 0)) == 0 and d == 0
	var cfg: Dictionary = CombatRules.cfg(data)
	for o: Dictionary in options:  # v0.7.22.19 (#14): the most wounded of its side within the spell's reach, not only itself
		if data["spells"][o["id"]].has("heal_at_slot"):
			var who := _wounded_ally(s, data, f, str(o["id"]))
			if not who.is_empty():
				var oh := o.duplicate()
				oh["target"] = who
				_cast(s, data, f, oh, lines)
				return true
	if str(f.get("concentration", "")).is_empty():
		for o: Dictionary in options:
			var spec: Dictionary = cfg["condition_spells"].get(str(o["id"]), {})
			if spec.is_empty() or not in_range.call(str(o["id"])):
				continue
			if str(f.get("last_spell", "")) == str(o["id"]) and not bool(data["spells"][o["id"]].get("concentration", false)):
				continue  # not the same Command every turn (#14): a spell that holds by itself waits a turn
			if (spec["conditions"] as Array).all(func(x: String) -> bool: return ConditionRules.has(s.character, x)):
				continue
			if spec.has("min_int") and int(s.character["abilities"].get("int", 10)) < int(spec["min_int"]):
				continue
			_cast(s, data, f, o, lines)
			return true
	var best := {}
	var best_avg := 0.0
	for o: Dictionary in options:
		var sp: Dictionary = data["spells"][o["id"]]
		if not (cfg["engine_spells"] as Array).has(str(o["id"])) or sp.has("heal_at_slot") or not in_range.call(str(o["id"])):
			continue
		var avg := _avg(CombatRules._spell_dice(sp, int(o["slot"]), _caster_level(data, f)))
		if avg > best_avg:
			best = o
			best_avg = avg
	if best.is_empty():
		return false
	var weapon := CombatRules._best_action(data, f, "melee" if d == 0 else "ranged")
	var weapon_avg := 0.0
	for dd: Dictionary in weapon.get("damage", []):
		weapon_avg += _avg(str(dd["dice"]))
	if int(best["slot"]) == 0 and not bool(best.get("per_day", false)) and not weapon.is_empty() and weapon_avg > best_avg:
		return false
	_cast(s, data, f, best, lines)
	return true


## Who of the caster's side needs healing most: at half HP or less, the lowest share, within the spell's reach. "" — none.
static func _wounded_ally(s: GameSession, data: Dictionary, f: Dictionary, spell_id: String) -> String:
	var reach := CombatRules.range_cols(data, int(data["spells"][spell_id].get("range_ft", 0)))
	var best := ""
	var share := 0.5
	for id: String in CombatRules.enemies(s):
		var a := CombatRules.fighter(s, id)
		var part := float(a["hp"]) / maxf(1.0, float(a["max_hp"]))
		if CombatRules.cols_between(a, f) <= reach and (part < share or (part == share and best.is_empty())):
			best = id
			share = part
	return best


static func _caster_level(data: Dictionary, f: Dictionary) -> int:
	return maxi(1, int(monster(data, f).get("spellcasting", {}).get("level", 1)))


static func _avg(expr: String) -> float:
	var r := CombatRules.dice_range(expr)
	return (r[0] + r[1]) / 2.0


## Resolves one spell of a monster at the hero (or itself for healing). Lines.
static func _cast(s: GameSession, data: Dictionary, f: Dictionary, o: Dictionary, lines: Array[String], asked: bool = false) -> void:
	var id := str(o["id"])
	var sp: Dictionary = data["spells"][id]
	var sc: Dictionary = monster(data, f)["spellcasting"]
	var slot := int(o["slot"])
	if not asked:  # Counterspell (v0.7.13.7): the window, or the policy decides
		var label := SpellEffects.counter_option(s, data, f, id)
		if not label.is_empty():
			var pol := FeatureRules.policy(s)
			if pol == "ask":
				lines.append("%s начинает колдовать «%s»…" % [f["name"], sp["name"]])
				s.combat["pending"] = {"kind": "counter", "foe": str(f["id"]), "option": o, "circle": maxi(int(sp["level"]), slot),
					"options": [{"id": "counterspell", "label": label}], "line": "%s колдует «%s»" % [f["name"], sp["name"]], "dmg": 0}
				s.combat["halt"] = true
				return
			if pol == "always" and SpellEffects.counter(s, data, f, id, maxi(int(sp["level"]), slot), lines):
				return
	if not f.has("slots"):
		f["slots"] = (sc.get("slots", {}) as Dictionary).duplicate()
	if slot > 0:
		f["slots"][str(slot)] = int(f["slots"][str(slot)]) - 1
	if bool(o.get("per_day", false)):
		var used: Dictionary = f.get("used", {})
		used["spell:" + id] = int(used.get("spell:" + id, 0)) + 1
		f["used"] = used
	var c := s.character
	var name := str(sp["name"])
	CombatRules.fx(s, str(f["id"]) if sp.has("heal_at_slot") else CombatRules.PLAYER, "spell")  # v0.7.22.14
	var dc := int(sc.get("dc", 10))
	var ab_mod := CharacterRules.mod(int(monster(data, f)["abilities"].get(str(sc.get("ability", "wis")), 10)))
	f["hidden"] = false
	f["last_spell"] = id
	if sp.has("heal_at_slot"):
		var heal := CombatRules.roll_dice(s.rng, str(sp["heal_at_slot"].get(str(maxi(1, slot)), "1d8+MOD")), false, ab_mod)
		var who := CombatRules.fighter(s, str(o.get("target", f["id"])))
		if who.is_empty():
			who = f
		var before := int(who["hp"])
		who["hp"] = mini(int(who["max_hp"]), before + heal)
		lines.append("%s колдует «%s» на %s: +%d HP" % [f["name"], name, "себя" if who == f else who["name"], int(who["hp"]) - before])
		return
	var spec: Dictionary = CombatRules.cfg(data)["condition_spells"].get(id, {})
	if not spec.is_empty():
		_cast_condition_on_hero(s, data, f, id, slot, spec, dc, lines)
		return
	var dice := CombatRules._spell_dice(sp, slot, _caster_level(data, f))
	var dtype := str(sp.get("damage_type", ""))
	var dtext := str(data["misc"]["damage_types"].get(dtype, dtype))
	var multi: Dictionary = CombatRules.cfg(data)["multi"].get(id, {})
	if bool(multi.get("auto_hit", false)):
		var n := int(multi.get("base", 1)) + int(multi.get("per_slot", 0)) * maxi(0, slot - maxi(1, int(sp["level"])))
		var total := 0
		for i in n:
			total += CombatRules.roll_dice(s.rng, dice)
		var adj := HeroDefense.adjust(s, data, dtype, total)
		lines.append("%s колдует «%s»: %d (%s)" % [f["name"], name, int(adj["damage"]), dtext])
		CombatRules._hurt_player(s, data, int(adj["damage"]), false, lines)
		return
	if sp.has("attack"):
		var p := CombatRules.player(s)
		var dis := (bool(p.get("dodging", false)) and not ConditionRules.incapacitated(c)) or ConditionRules.invisible(c, data) \
			or (str(sp["attack"]) == "ranged" and CombatRules.cols_between(f, p) == 0)
		var adv := ["paralyzed", "stunned", "unconscious", "restrained", "petrified", "blinded"].any(func(x: String) -> bool: return ConditionRules.has(c, x))
		var rolls := Roll.dice(s.rng, adv, dis)
		var nat := Roll.kept(rolls, adv, dis)
		var to_hit := int(sc.get("attack", 0))
		var hit := nat == 20 or (nat != 1 and nat + to_hit >= int(c.get("ac", 10)))
		var line := "%s колдует «%s»: %d + %d = %d против КД %d" % [f["name"], name, nat, to_hit, nat + to_hit, int(c.get("ac", 10))]
		if not hit:
			lines.append(line + " — промах")
			return
		var dmg := CombatRules.roll_dice(s.rng, dice, nat == 20)
		var adj := HeroDefense.adjust(s, data, dtype, dmg)
		lines.append(line + " — попадание, %d (%s)%s" % [int(adj["damage"]), dtext, (", " + str(adj["note"])) if not str(adj["note"]).is_empty() else ""])
		CombatRules._hurt_player(s, data, int(adj["damage"]), nat == 20, lines)
		return
	if sp.has("save"):
		var r := HeroDefense.save(s, data, str(sp["save"]["ability"]), dc, "magic")
		var dmg := CombatRules.roll_dice(s.rng, dice)
		if bool(r["ok"]):
			dmg = dmg / 2 if str(sp["save"].get("success", "none")) == "half" else 0
		var adj := HeroDefense.adjust(s, data, dtype, dmg)
		lines.append("%s колдует «%s»: спасбросок %s, %d (%s)" % [f["name"], name, r["text"], int(adj["damage"]), dtext])
		CombatRules._hurt_player(s, data, int(adj["damage"]), false, lines)


static func _cast_condition_on_hero(s: GameSession, data: Dictionary, f: Dictionary, id: String, slot: int, spec: Dictionary, dc: int,
		lines: Array[String]) -> void:
	var c := s.character
	var sp: Dictionary = data["spells"][id]
	var name := str(sp["name"])
	var conds: Array = spec["conditions"]
	var word := _command_word(s, spec)  # Command's word (v0.7.22.4)
	var said := ""
	if not word.is_empty():
		conds = word["conditions"]
		said = " — «%s»" % word["word"]
	var tags: Array[String] = ["magic"]
	if conds.has("charmed"):
		tags.push_front("charm")
	if conds.has("frightened"):
		tags.push_front("fear")
	if conds.has("unconscious"):
		tags.push_front("sleep")
	var tag := ",".join(tags)
	for cond: String in conds:
		var immune := HeroDefense.immune(c, data, cond, tag)
		if not immune.is_empty():
			lines.append("%s колдует «%s»%s — не действует: %s" % [f["name"], name, said, immune])
			return
	if spec.has("pool"):
		var pool := CombatRules.roll_dice(s.rng, str(spec["pool"]))
		for i in maxi(0, slot - maxi(1, int(sp["level"]))):
			pool += CombatRules.roll_dice(s.rng, str(spec["pool_per_slot"]))
		if int(c["hp"]) > pool:
			lines.append("%s колдует «%s»%s: пул %d хитов — %s устоял" % [f["name"], name, said, pool, c.get("name", "")])
			return
		lines.append("%s колдует «%s»%s: пул %d хитов" % [f["name"], name, said, pool])
	elif sp.has("save"):
		var r := HeroDefense.save(s, data, str(sp["save"]["ability"]), dc, tag)
		lines.append("%s колдует «%s»%s: спасбросок %s" % [f["name"], name, said, r["text"]])
		if bool(r["ok"]):
			return
	var ends := {"at": ConditionRules.now(s) + int(spec.get("rounds", 10))}
	var conc := bool(sp.get("concentration", false))
	for cond: String in conds:
		var e := {"condition": cond, "ends": {} if cond == "prone" else ends, "by": str(f["id"]), "source": {"kind": "monster_spell", "id": id, "name": "%s — %s" % [f["name"], name]}}
		if bool(spec.get("repeat_save", false)) and sp.has("save"):
			e["save"] = {"ability": str(sp["save"]["ability"]), "dc": dc, "tag": tag, "repeat": true}
		if bool(spec.get("ends_on_damage", false)):
			e["wake"] = true
		if conc:
			e["conc"] = true
		lines.append_array(ConditionRules.impose(s, data, e))
	if conc:
		f["concentration"] = id
	if bool(word.get("drop", false)):
		var held := str(c.get("equipped", {}).get("main_hand", ""))
		c["equipped"]["main_hand"] = ""
		c["dropped"] = held  # picked up at the start of the hero's next turn it can act (a free interaction, 5e)
		lines.append("%s роняет %s" % [c.get("name", ""), ItemRules.display_name(data["items"], s.items, held)])
	if int(word.get("flee", 0)) > 0:
		var p := CombatRules.player(s)
		var away := signi(int(p["col"]) - int(f["col"]))
		var edge := int(CombatRules.cfg(data)["edge"])
		p["col"] = clampi(int(p["col"]) + (away if away != 0 else 1) * int(word["flee"]), -edge, edge)
		lines.append("%s бежит прочь" % c.get("name", ""))
	CharacterRules.refresh(c, data, s.items)
	lines.append("%s: %s" % [c.get("name", ""), ", ".join(conds.map(func(x: String) -> String: return ConditionRules.name_of(data, x).to_lower()))])


## Command's word: the first that does something now (Grovel — not when prone, Drop — only with a weapon in hand);
## {} for a spell without words.
static func _command_word(s: GameSession, spec: Dictionary) -> Dictionary:
	var c := s.character
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
	if int(f["hp"]) > 0 and CombatRules._monster_save(s, data, f, "con", maxi(10, dmg / 2)):
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
	return int(monster(data, f).get("darkvision", 0)) > 0


## The monster flies (a fly speed in the SRD): it reaches a flying hero (v0.7.13.3).
static func flies(data: Dictionary, f: Dictionary) -> bool:
	return int(monster(data, f).get("fly", 0)) > 0


## The way a monster covers in a turn on the field: the walk or, if faster, the fly (a Flying Sword: 0 ft, fly 50 ft).
static func move_speed(m: Dictionary) -> int:
	return maxi(int(m.get("speed", 30)), int(m.get("fly", 0)))


## «0 фт, полёт 50 фт» for a card.
static func speed_text(m: Dictionary) -> String:
	var fly := int(m.get("fly", 0))
	return "%d фт" % int(m.get("speed", 30)) + (", полёт %d фт" % fly if fly > 0 else "")
