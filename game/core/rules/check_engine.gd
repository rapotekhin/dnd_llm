class_name CheckEngine
extends RefCounted
## Ability checks and saves for engine.check (ADR-0008 §2): the engine owns the DC number, the roll and
## the result; the LLM only names the skill and a DC tier. Locks of failed checks — ExplorationRules.


## `params` = engine.check params; `bonus` = the character's total bonus. An engine-set `dc` (haggling: DC by the
## merchant's attitude, TradeRules) replaces the tier number; the master never sends one.
## Returns the engine.check result, or {"error": text} for bad params.
static func roll(rules: Dictionary, rng: RandomNumberGenerator, params: Dictionary, bonus: int, check_id: String) -> Dictionary:
	var tiers: Dictionary = rules["dc_tiers"]
	var tier := str(params.get("dc_tier", ""))
	if not tiers.has(tier):
		return {"error": "unknown dc_tier: %s" % tier}
	var skill := str(params.get("skill", "")) if params.get("skill") != null else ""
	var save := str(params.get("save", "")) if params.get("save") != null else ""
	var ability := str(params.get("ability", ""))  # a bare ability check, the player's pick (v0.7.36)
	if [skill, save, ability].filter(func(x: String) -> bool: return not x.is_empty()).size() != 1:
		return {"error": "exactly one of skill or save is required"}
	if not ability.is_empty() and not (rules["saves"] as Array).has(ability):
		return {"error": "unknown ability: %s" % ability}
	if not skill.is_empty() and not (rules["skills"] as Dictionary).has(skill):
		return {"error": "unknown skill: %s" % skill}
	if not save.is_empty() and not (rules["saves"] as Array).has(save):
		return {"error": "unknown save: %s" % save}

	var lucky := bool(params.get("reroll_ones", false))  # a halfling's Lucky (v0.7.10)
	var d20 := func() -> int:
		var r := rng.randi_range(1, 20)
		return rng.randi_range(1, 20) if r == 1 and lucky else r
	var rolls: Array[int] = [d20.call()]
	# The LLM may suggest a situational advantage, but only with a reason that the card shows. Disadvantage comes
	# from the engine (conditions, ConditionRules); both cancel out (5e).
	var adv := params.get("advantage_reason") != null and not str(params.get("advantage_reason", "")).is_empty()
	var dis := not str(params.get("disadvantage_reason", "")).is_empty()
	if adv != dis:
		rolls.append(d20.call())
	var nat: int = rolls.max() if adv or not dis else rolls.min()
	var dc := int(params["dc"]) if params.has("dc") else int(tiers[tier])
	var total := nat + bonus
	# House rule (ADR-0008 §2): natural 20 / 1 always succeed / fail, skill checks included.
	var success := nat == 20 or (nat != 1 and total >= dc)
	var auto_fail := str(params.get("auto_fail_reason", ""))
	if not auto_fail.is_empty():
		success = false
	var out := {
		"check_id": check_id,
		"rolls": rolls,
		"bonus": bonus,
		"total": total,
		"dc": dc,
		"success": success,
		"nat": nat,
		"blocked": false,
	}
	if dis:
		out["disadvantage_reason"] = str(params["disadvantage_reason"])
	if not str(params.get("dc_reason", "")).is_empty():  # the NPC's SRD template set the DC (v0.7.15.1)
		out["dc_reason"] = str(params["dc_reason"])
	if not auto_fail.is_empty():
		out["auto_fail_reason"] = auto_fail
	return out


## The character's total bonus for engine.check params: skill bonus or save bonus from the sheet.
static func bonus_for(character: Dictionary, params: Dictionary, data: Dictionary = {}) -> int:
	var skill := str(params.get("skill", "")) if params.get("skill") != null else ""
	if not skill.is_empty():
		return int(character.get("skills", {}).get(skill, 0))
	if not str(params.get("ability", "")).is_empty():
		return CharacterRules.ability_check_bonus(character, data, str(params["ability"]))
	var save := str(params.get("save", "")) if params.get("save") != null else ""
	return int(character.get("saves", {}).get(save, 0))
