class_name Roll
extends RefCounted
## One roll (v0.7.60, ADR-0012): every d20 of the game comes from here, so the rules cannot part ways between systems.
## Roll.check is a check of anybody with everything its d20 has (v0.8.4.14): statuses, Lucky, what the moment gives
## (CheckEngine.situation), the natural 20 / 1, Bardic Inspiration on a failure; the hero's also the labelled breakdown
## and the vows' deed. Roll.odds is its chance by the same spec, nothing rolled.
## What a check is for (a shift, a theft, an exam) stays with its rule, which reads the result.

## How far a natural 20 / 1 counts in a margin (an outcome ladder); a recipe's quality passes its own.
const CRIT_MARGIN := 5


## A plain die of a creature or a table.
static func d20(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, 20)


## The dice of a roll: a second die with advantage or disadvantage, both cancel out (5e). `lucky` rerolls a 1.
static func dice(rng: RandomNumberGenerator, adv: bool, dis: bool, lucky: bool = false) -> Array[int]:
	var rolls: Array[int] = [_die(rng, lucky)]
	if adv != dis:
		rolls.append(_die(rng, lucky))
	return rolls


static func _die(rng: RandomNumberGenerator, lucky: bool) -> int:
	var r := d20(rng)
	return d20(rng) if r == 1 and lucky else r


## The die that counts.
static func kept(rolls: Array[int], adv: bool, dis: bool) -> int:
	return rolls.max() if adv and not dis else rolls.min() if dis and not adv else rolls[0]


## The hero's dice (a halfling's Lucky).
static func hero_dice(s: GameSession, adv: bool, dis: bool) -> Array[int]:
	return dice(s.rng, adv, dis, CharacterRules.has_trait(s.character, "lucky"))


## The dice of anybody's roll.
static func of(s: GameSession, who: Dictionary, adv: bool, dis: bool) -> Array[int]:
	return dice(s.rng, adv, dis, CharacterRules.has_trait(Sheet.holder(s, who), "lucky"))


## House rule (ADR-0008 §2): natural 20 / 1 always succeed / fail, skill checks included.
static func succeeds(nat: int, total: int, dc: int) -> bool:
	return nat == 20 or (nat != 1 and total >= dc)


## By how much a roll passed: the step of an outcome ladder.
static func margin(nat: int, total: int, dc: int, crit: int = CRIT_MARGIN) -> int:
	return crit if nat == 20 else -crit if nat == 1 else total - dc


## The chance in percent of passing `dc` with `bonus`; `crit_min` — the least die that hits whatever the AC (a Champion's 19).
static func chance(bonus: int, dc: int, adv: bool = false, dis: bool = false, crit_min: int = 20) -> int:
	var wins := 0
	for nat in range(1, 21):
		if nat >= crit_min or succeeds(nat, nat + bonus, dc):
			wins += 1
	var p := wins / 20.0
	if adv and not dis:
		p = 1.0 - (1.0 - p) * (1.0 - p)
	elif dis and not adv:
		p = p * p
	return roundi(p * 100.0)


## Bardic Inspiration on a failed roll (it is spent): {value, label}; value 0 — there is none.
static func inspire(s: GameSession, who: Dictionary = Sheet.HERO) -> Dictionary:
	var die := FeatureRules.inspiration_die(Sheet.holder(s, who))
	var n := FeatureRules.use_inspiration(s, who)
	return {"value": n, "label": "Вдохновение барда (к%d)" % die}


## A check of the hero (Roll.check of Sheet.HERO).
static func hero(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	return check(s, data, Sheet.HERO, spec)


## A check or a save of anybody, one road (v0.8.4.14, ADR-0016): the statuses, Lucky, advantage and disadvantage with what
## this moment gives (CheckEngine.situation), the natural 20 / 1, Bardic Inspiration on a failure, the breakdown and the
## vows' deed of the hero. `spec`: what (the breakdown's title), dc, one of skill / ability / save (a save goes by
## Sheet.save with `tag`), parts (the labelled bonus; the sheet's own by default, the hero's with the game's difficulty),
## bonus (the sheet's number, when it is kept apart from the parts), adv, dis, the reasons adv_why / dis_why / fail_why,
## tool, target_id, sense, crit (the margin of a natural 20 / 1), quiet (no line of the breakdown: a card is its own).
## {rolls, nat, bonus, total, dc, ok, margin, parts, adv, dis, fail: [why]}.
static func check(s: GameSession, data: Dictionary, who: Dictionary, spec: Dictionary) -> Dictionary:
	if not str(spec.get("save", "")).is_empty():
		return _save(s, data, who, spec)
	var hero := Sheet.is_hero(who)
	var at := CheckEngine.situation(s, data, who, spec)
	var adv := bool(spec.get("adv", false)) or not (at["adv"] as Array).is_empty()
	var dis := bool(spec.get("dis", false)) or not (at["dis"] as Array).is_empty()
	var failed := not (at["fail"] as Array).is_empty()
	var rolls := of(s, who, adv, dis)
	var nat := kept(rolls, adv, dis)
	var parts := _parts(s, data, who, spec)
	var bonus := (int(spec["bonus"]) if spec.has("bonus") else RollParts.sum(parts)) + RollParts.sum(at["parts"])
	parts.append_array(at["parts"])
	var dc := int(spec.get("dc", 0))
	var ok := succeeds(nat, nat + bonus, dc) and not failed
	if not ok and nat != 1 and not failed:
		var insp := inspire(s, who)
		if int(insp["value"]) > 0:
			parts.append(RollParts.part(str(insp["label"]), int(insp["value"])))
			bonus += int(insp["value"])
			ok = nat + bonus >= dc
	var total := nat + bonus
	var skill := str(spec.get("skill", ""))
	if hero and not bool(spec.get("quiet", false)):
		RollParts.note(s, str(spec.get("what", "")), rolls, nat, parts, bonus, dc)
	if hero and not skill.is_empty():
		s.faith_lines.append_array(WorldEvent.deed(s, data, "check:" + skill))  # a lie breaks a vow (v0.7.49)
	var crit := int(spec.get("crit", CRIT_MARGIN))
	return {"rolls": rolls, "nat": nat, "bonus": bonus, "total": total, "dc": dc, "ok": ok, "parts": parts,
		"margin": -crit if failed else margin(nat, total, dc, crit), "adv": at["adv"], "dis": at["dis"], "fail": at["fail"]}


## The chance in percent and the bonus of a check by the same `spec`, nothing rolled or spent: {chance, bonus, adv, dis,
## failed}. A save counts its statuses and advantages as Sheet.save does.
static func odds(s: GameSession, data: Dictionary, who: Dictionary, spec: Dictionary) -> Dictionary:
	var dc := int(spec.get("dc", 0))
	if not str(spec.get("save", "")).is_empty():
		var sv := Sheet.save_odds(s, data, who, str(spec["save"]), str(spec.get("tag", "")), spec)
		var p := 0 if bool(sv["failed"]) else chance(int(sv["bonus"]), dc, bool(sv["adv"]), bool(sv["dis"]))
		return {"chance": p, "bonus": sv["bonus"], "adv": sv["adv"], "dis": sv["dis"], "failed": sv["failed"]}
	var at := CheckEngine.situation(s, data, who, spec, true)
	var adv := bool(spec.get("adv", false)) or not (at["adv"] as Array).is_empty()
	var dis := bool(spec.get("dis", false)) or not (at["dis"] as Array).is_empty()
	var failed := not (at["fail"] as Array).is_empty()
	var bonus := (int(spec["bonus"]) if spec.has("bonus") else RollParts.sum(_parts(s, data, who, spec))) + RollParts.sum(at["parts"])
	return {"chance": 0 if failed else chance(bonus, dc, adv, dis), "bonus": bonus, "adv": adv, "dis": dis, "failed": failed}


## The chance in percent of a check of `who` by `spec` (Roll.check's own): what a window shows.
static func chance_of(s: GameSession, data: Dictionary, who: Dictionary, spec: Dictionary) -> int:
	return int(odds(s, data, who, spec)["chance"])


## The labelled bonus of a check: the caller's parts, or the sheet's (the hero's with the game's difficulty).
static func _parts(s: GameSession, data: Dictionary, who: Dictionary, spec: Dictionary) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if spec.has("parts"):
		parts.assign(spec["parts"])
		return parts
	var skill := str(spec.get("skill", ""))
	var ab := str(spec.get("ability", ""))
	if Sheet.is_hero(who):
		if not skill.is_empty():
			return RollParts.skill(s, data, skill)
		parts = RollParts.of_params(s.character, data, {"ability": ab}, s.items) if not ab.is_empty() else parts
		RollParts.difficulty(s, data, parts)
		return parts
	if not skill.is_empty():
		parts.append(RollParts.part(TranslationServer.translate("SKILL_" + skill.to_upper()), Sheet.skill(s, data, who, skill)))
	elif not ab.is_empty():
		parts.append(RollParts.part(RollParts.ability_name(ab), Sheet.ability_mod(s, data, who, ab)))
	return parts


## A save on the road of Roll.check: Sheet.save with the caller's reasons, in the shape of a check.
static func _save(s: GameSession, data: Dictionary, who: Dictionary, spec: Dictionary) -> Dictionary:
	var dc := int(spec.get("dc", 0))
	var r := Sheet.save(s, data, who, str(spec["save"]), dc, str(spec.get("tag", "")), bool(spec.get("dis", false)), spec)
	var crit := int(spec.get("crit", CRIT_MARGIN))
	var failed := not (r["fail"] as Array).is_empty()
	return {"rolls": r["rolls"], "nat": r["nat"], "bonus": r["bonus"], "total": r["total"], "dc": dc, "ok": r["ok"], "parts": r["parts"],
		"margin": -crit if failed else margin(int(r["nat"]), int(r["total"]), dc, crit), "adv": r["adv"], "dis": r["dis"], "fail": r["fail"],
		"text": r["text"]}
