class_name Roll
extends RefCounted
## One roll (v0.7.60, ADR-0012): every d20 of the game comes from here, so the rules cannot part ways between systems.
## Roll.hero is a check of the hero with everything a d20 of the hero has: conditions, Lucky, advantage and
## disadvantage, the natural 20 / 1, Bardic Inspiration on a failure, the labelled breakdown, the vows' deed.
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


## House rule (ADR-0008 §2): natural 20 / 1 always succeed / fail, skill checks included.
static func succeeds(nat: int, total: int, dc: int) -> bool:
	return nat == 20 or (nat != 1 and total >= dc)


## By how much a roll passed: the step of an outcome ladder.
static func margin(nat: int, total: int, dc: int, crit: int = CRIT_MARGIN) -> int:
	return crit if nat == 20 else -crit if nat == 1 else total - dc


## The chance in percent of passing `dc` with `bonus`.
static func chance(bonus: int, dc: int, adv: bool = false, dis: bool = false) -> int:
	var wins := 0
	for nat in range(1, 21):
		if succeeds(nat, nat + bonus, dc):
			wins += 1
	var p := wins / 20.0
	if adv and not dis:
		p = 1.0 - (1.0 - p) * (1.0 - p)
	elif dis and not adv:
		p = p * p
	return roundi(p * 100.0)


## Bardic Inspiration on a failed roll (it is spent): {value, label}; value 0 — there is none.
static func inspire(s: GameSession) -> Dictionary:
	var die := FeatureRules.inspiration_die(s.character)
	var n := FeatureRules.use_inspiration(s)
	return {"value": n, "label": "Вдохновение барда (к%d)" % die}


## A check of the hero. `spec`: what (the breakdown's title), dc, one of skill / ability / save (the conditions and the
## vows look at it), parts (the labelled bonus; a skill's own by default), bonus (the sheet's number, when it is kept
## apart from the parts), adv, dis, crit (the margin of a natural 20 / 1).
## {rolls, nat, bonus, total, dc, ok, margin, parts}.
static func hero(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var skill := str(spec.get("skill", ""))
	var mods := ConditionRules.check_mods(s.character, data, _keys(spec))
	var adv := bool(spec.get("adv", false))
	var dis := bool(spec.get("dis", false)) or not (mods["disadvantage"] as Array).is_empty()
	var failed := not (mods["auto_fail"] as Array).is_empty()
	var rolls := hero_dice(s, adv, dis)
	var nat := kept(rolls, adv, dis)
	var parts: Array[Dictionary] = []
	if spec.has("parts"):
		parts.assign(spec["parts"])
	else:
		parts = RollParts.skill(s, data, skill)
	var bonus := int(spec["bonus"]) if spec.has("bonus") else RollParts.sum(parts)
	var dc := int(spec.get("dc", 0))
	var ok := succeeds(nat, nat + bonus, dc) and not failed
	if not ok and nat != 1 and not failed:
		var insp := inspire(s)
		if int(insp["value"]) > 0:
			parts.append(RollParts.part(str(insp["label"]), int(insp["value"])))
			bonus += int(insp["value"])
			ok = nat + bonus >= dc
	var total := nat + bonus
	RollParts.note(s, str(spec.get("what", "")), rolls, nat, parts, bonus, dc)
	if not skill.is_empty():
		s.faith_lines.append_array(FaithRules.deed(s, data, "check:" + skill))  # a lie breaks a vow (v0.7.49)
	var crit := int(spec.get("crit", CRIT_MARGIN))
	return {"rolls": rolls, "nat": nat, "bonus": bonus, "total": total, "dc": dc, "ok": ok, "parts": parts,
		"margin": -crit if failed else margin(nat, total, dc, crit)}


static func _keys(spec: Dictionary) -> Dictionary:
	var out := {}
	for k: String in ["skill", "ability", "save"]:
		if not str(spec.get(k, "")).is_empty():
			out[k] = str(spec[k])
	return out
