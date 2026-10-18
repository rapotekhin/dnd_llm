class_name CheckEngine
extends RefCounted
## Ability checks and saves for engine.check (ADR-0008 §2): the engine owns the DC number, the roll and
## the result; the LLM only names the skill and a DC tier. Failed-check locks come with v0.6.0.


## `params` = engine.check params; `bonus` = the character's total bonus (0 until characters, v0.5.0).
## Returns the engine.check result, or {"error": text} for bad params.
static func roll(rules: Dictionary, rng: RandomNumberGenerator, params: Dictionary, bonus: int, check_id: String) -> Dictionary:
	var tiers: Dictionary = rules["dc_tiers"]
	var tier := str(params.get("dc_tier", ""))
	if not tiers.has(tier):
		return {"error": "unknown dc_tier: %s" % tier}
	var skill := str(params.get("skill", ""))
	var save := str(params.get("save", ""))
	if skill.is_empty() == save.is_empty():
		return {"error": "exactly one of skill or save is required"}
	if not skill.is_empty() and not (rules["skills"] as Dictionary).has(skill):
		return {"error": "unknown skill: %s" % skill}
	if not save.is_empty() and not (rules["saves"] as Array).has(save):
		return {"error": "unknown save: %s" % save}

	var rolls: Array[int] = [rng.randi_range(1, 20)]
	# The LLM may suggest a situational advantage, but only with a reason that the card shows.
	if not str(params.get("advantage_reason", "")).is_empty():
		rolls.append(rng.randi_range(1, 20))
	var nat: int = rolls.max()
	var dc := int(tiers[tier])
	var total := nat + bonus
	# House rule (ADR-0008 §2): natural 20 / 1 always succeed / fail, skill checks included.
	var success := nat == 20 or (nat != 1 and total >= dc)
	return {
		"check_id": check_id,
		"rolls": rolls,
		"bonus": bonus,
		"total": total,
		"dc": dc,
		"success": success,
		"nat": nat,
		"blocked": false,
	}
