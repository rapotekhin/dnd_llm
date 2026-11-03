class_name Require
extends RefCounted
## What a job, a course or an office asks (v0.7.67): one reading of a `requires` record, rows [{text, ok}]. `ctx` says what
## the record leaves unsaid: `npc` and `npc_word` (a common tongue is asked with them), `tool`, `skill` (a job's `true`),
## `location`, `waive` {key: who} — a recommendation stands for that row; `who` — whose rows (v0.8.4.20, the hero by
## default). What people think (attitude, a settlement's fame, closeness, an organization's step) is kept of the hero
## only: a person passes those rows.


static func rows(s: GameSession, data: Dictionary, req: Dictionary, ctx: Dictionary = {}) -> Array[Dictionary]:
	var who := str(ctx.get("who", Being.HERO))
	var hero := who == Being.HERO
	var c := Life.of(s, who, data)
	var out: Array[Dictionary] = []
	var n := WorldView.new(data["world"]).npc(str(ctx.get("npc", "")))
	if not n.is_empty() and ctx.has("npc_word") and not LanguageRules.npc_understands(c, data, n):
		out.append({"text": "общий язык с %s" % str(ctx["npc_word"]), "ok": false})
	if req.has("level"):
		out.append({"text": "уровень %d" % int(req["level"]), "ok": int(c.get("level", 1)) >= int(req["level"])})
	if req.has("classes"):
		out.append({"text": "класс: " + ", ".join(req["classes"]), "ok": (req["classes"] as Array).has(str(c.get("class", "")))})
	if req.has("attitude"):
		var a := int(req["attitude"])
		var word := TranslationServer.translate("ATTITUDE_0" if a == 0 else ("ATTITUDE_P%d" % a if a > 0 else "ATTITUDE_M%d" % -a))
		out.append({"text": "отношение %s не хуже: %s" % [str(ctx.get("npc_of", "")), word], "ok": not hero or s.attitude(str(ctx.get("npc", ""))) >= a})
	if req.has("quest"):
		var qid := str(req["quest"])
		out.append({"text": "сделано задание «%s»" % data["world"].get("quests", {}).get(qid, {}).get("title", qid), "ok": Cond.met(s, {"quest_done": qid})})
	if req.has("when"):
		var wt := str(req.get("when_text", ""))
		out.append({"text": wt if not wt.is_empty() else "условие учителя", "ok": Cond.met(s, req["when"])})
	if bool(req.get("tool", false)):
		var tool := str(ctx.get("tool", ""))
		out.append({"text": "владение: " + BackgroundRules.tool_name(data, tool), "ok": CraftRules.proficient(c, tool)})
	if req.has("skill") and not (req["skill"] is bool and not bool(req["skill"])):
		var skill := str(ctx.get("skill", "")) if req["skill"] is bool else str(req["skill"])
		out.append({"text": "владение навыком: " + CraftRules.tr_skill(data, skill), "ok": JobRules._skilled(c, skill)})
	if req.has("language"):
		var lang := str(req["language"])
		out.append({"text": "язык: " + LanguageRules.name_of(data, lang), "ok": LanguageRules.hero(c, data).has(lang)})
	if req.has("diploma"):
		out.append({"text": "грамота выпускника: " + StudyRules.name_of(s, data, str(req["diploma"])), "ok": StudyRules.has_diploma(c, str(req["diploma"]))})
	if req.has("org"):
		var org := str(req["org"].get("id", ""))
		var need := int(req["org"].get("rank", 0))
		var rank_word := str(OrgRules.ranks(s, data, org)[clampi(need, 0, OrgRules.ranks(s, data, org).size() - 1)]["name"])
		out.append({"text": "член «%s»%s" % [OrgRules.org_name(s, data, org), (", ступень от «%s»" % rank_word) if need > 0 else ""],
			"ok": OrgRules.member(c, org) and (not hero or OrgRules.rank(s, data, org) >= need)})
	var waive: Dictionary = ctx.get("waive", {})
	if req.has("reputation"):
		var loc := str(ctx.get("location", ""))
		var ok := not hero or not ReputationRules.is_settlement(data, loc) or ReputationRules.step(s, data, loc) >= int(req["reputation"])
		out.append(_waived("слава в поселении не ниже «%s»" % ReputationRules.word(data, int(req["reputation"])), ok, str(waive.get("reputation", ""))))
	if req.has("served"):
		var loc := str(ctx.get("location", ""))
		out.append({"text": "заслуги на службе здесь: %d из %d" % [OfficeRules.served(c, data, loc), int(req["served"])],
			"ok": OfficeRules.served(c, data, loc) >= int(req["served"])})
	if req.has("bond"):
		var b: Dictionary = req["bond"]
		out.append(_waived("близость с %s от %d" % [WorldView.name_of(data, str(b["npc"])), int(b["at"])],
			not hero or BondRules.points(c, str(b["npc"])) >= int(b["at"]), str(waive.get("bond", ""))))
	return out


static func met(rows_of: Array[Dictionary]) -> bool:
	return rows_of.all(func(r: Dictionary) -> bool: return bool(r["ok"]))


static func _waived(text: String, ok: bool, by: String) -> Dictionary:
	var by_letter := not ok and not by.is_empty()
	return {"text": text + (" — рекомендация: " + by if by_letter else ""), "ok": ok or by_letter}
