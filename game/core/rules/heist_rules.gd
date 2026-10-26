class_name HeistRules
extends RefCounted
## Criminal jobs (roadmap v0.7.33, the author: burglary, robbery, smuggling). A job — world.json `heists` or the
## master's (`heist`, generated.heists): {kind, name, target (room of the act), victim (NPC) | victim_name, giver, org,
## dc_tier, loot_cp, items, reward_cp, cargo, law_location, text}. Its kind (rules.underworld.kinds) sets the act's hours,
## its check (the better of the skills and the tool), the preparations — each once a day, at the target or anywhere,
## a check against the job's DC or a thing carried; a success adds `prep_bonus` to the act. The act at the target in
## the hours, without the victim watching: a failure brings the kind's `fail` (caught — the crime known; fight — the
## victim's guards; seized — the cargo taken and the crime known); a success — the loot (a burglary's things are the
## victim's: OwnerRules), the cargo delivered for the reward, a trace by `trace_chance` on a plain success (a robbery
## without the mask step is always seen). An organization's job owes its cut and moves its rank (OrgRules).
## c.heists {id: {taken, steps {step: {day, ok}}, status: active | done | failed}}.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["underworld"]


static func kind(data: Dictionary, k: String) -> Dictionary:
	return cfg(data)["kinds"].get(k, {})


static func all(s: GameSession, data: Dictionary) -> Dictionary:
	var out: Dictionary = (data["world"].get("heists", {}) as Dictionary).duplicate()
	out.merge(WorldGen.generated(s).get("heists", {}))
	return out


static func def(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return all(s, data).get(id, {})


static func view(c: Dictionary) -> Dictionary:
	return c.get("heists", {})


static func _rw(c: Dictionary) -> Dictionary:
	if not (c.get("heists") is Dictionary):
		c["heists"] = {}
	return c["heists"]


static func status(c: Dictionary, id: String) -> String:
	return str(view(c).get(id, {}).get("status", ""))


static func active(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in view(c):
		if status(c, id) == "active":
			out.append(id)
	return out


static func dc(s: GameSession, data: Dictionary, id: String) -> int:
	return int(data["rules"]["dc_tiers"].get(str(def(s, data, id).get("dc_tier", "medium")), 15))


static func target_name(s: GameSession, data: Dictionary, id: String) -> String:
	return WorldView.new(data["world"]).place_path(str(def(s, data, id).get("target", "")))


static func victim_name(s: GameSession, data: Dictionary, id: String) -> String:
	var d := def(s, data, id)
	return BondRules.npc_name(s, data, str(d["victim"])) if not str(d.get("victim", "")).is_empty() else str(d.get("victim_name", ""))


# --- taking -------------------------------------------------------------------------------------------------------


static func take_why(s: GameSession, data: Dictionary, id: String) -> String:
	if def(s, data, id).is_empty():
		return "HEIST_NONE"
	if not status(s.character, id).is_empty():
		return "HEIST_TAKEN"
	return ""


## The job is the hero's; a smuggler gets the cargo. Lines.
static func take(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var d := def(s, data, id)
	_rw(s.character)[id] = {"taken": s.day, "steps": {}, "status": "active"}
	var lines: Array[String] = ["Дело: «%s» — %s, %s" % [d["name"], kind(data, str(d["kind"]))["name"], target_name(s, data, id)]]
	var cargo: Dictionary = d.get("cargo", {})
	for item: String in cargo:
		ItemRules.found(s.character, data, s.items, item, int(cargo[item]))
		lines.append("Груз: %s ×%d" % [ItemRules.display_name(data["items"], s.items, item), int(cargo[item])])
	return lines


static func give_up(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	_rw(s.character)[id]["status"] = "failed"
	var lines: Array[String] = ["Дело брошено: «%s»" % def(s, data, id)["name"]]
	lines.append_array(OrgRules.on_heist(s, data, id, "fail", 0))
	return lines


# --- preparations -------------------------------------------------------------------------------------------------


static func steps(s: GameSession, data: Dictionary, id: String) -> Array:
	return kind(data, str(def(s, data, id).get("kind", ""))).get("steps", [])


static func step_def(s: GameSession, data: Dictionary, id: String, step_id: String) -> Dictionary:
	for st: Dictionary in steps(s, data, id):
		if str(st["id"]) == step_id:
			return st
	return {}


static func step_ok(c: Dictionary, id: String, step_id: String) -> bool:
	return bool(view(c).get(id, {}).get("steps", {}).get(step_id, {}).get("ok", false))


static func step_why(s: GameSession, data: Dictionary, id: String, step_id: String) -> String:
	var st := step_def(s, data, id, step_id)
	if status(s.character, id) != "active" or st.is_empty():
		return "HEIST_NOT_ACTIVE"
	if step_ok(s.character, id, step_id):
		return "HEIST_STEP_DONE"
	if st.has("item"):
		return "" if int(s.character.get("inventory", {}).get(str(st["item"]), 0)) > 0 else "HEIST_NO_ITEM"
	if str(st.get("at", "")) == "target" and s.room_id != str(def(s, data, id)["target"]):
		return "HEIST_NOT_THERE"
	if int(view(s.character)[id]["steps"].get(step_id, {}).get("day", -1)) == s.day:
		return "HEIST_STEP_TODAY"
	return ""


static func _bonus(s: GameSession, data: Dictionary, skill: String) -> int:
	return CheckEngine.bonus_for(s.character, {"skill": skill}) + DifficultyRules.bonus(s, data)


static func step_chance(s: GameSession, data: Dictionary, id: String, step_id: String) -> int:
	var st := step_def(s, data, id, step_id)
	if st.has("item"):
		return 100
	return JobRules._chance(_bonus(s, data, str(st["skill"])), dc(s, data, id), false)


static func step_minutes(s: GameSession, data: Dictionary, id: String, step_id: String) -> int:
	return int(step_def(s, data, id, step_id).get("minutes", 0))


## One preparation (step_why first; its time already passed). Lines.
static func step(s: GameSession, data: Dictionary, id: String, step_id: String) -> Array[String]:
	var st := step_def(s, data, id, step_id)
	var rec: Dictionary = view(s.character)[id]["steps"]
	if st.has("item"):
		rec[step_id] = {"day": s.day, "ok": true}
		return ["«%s»: %s — готово" % [def(s, data, id)["name"], st["name"]]]
	var skill := str(st["skill"])
	var nat := s.rng.randi_range(1, 20)
	var total := nat + _bonus(s, data, skill)
	var ok := nat == 20 or (nat != 1 and total >= dc(s, data, id))
	rec[step_id] = {"day": s.day, "ok": ok}
	return ["«%s»: %s — %s %d против Сл %d — %s" % [def(s, data, id)["name"], st["name"], CraftRules.tr_skill(data, skill), total, dc(s, data, id),
		"удалось: +%d к делу" % int(cfg(data)["prep_bonus"]) if ok else "не вышло, завтра снова"]]


static func prep(s: GameSession, data: Dictionary, id: String) -> int:
	var n := 0
	for st: Dictionary in steps(s, data, id):
		if step_ok(s.character, id, str(st["id"])):
			n += int(cfg(data)["prep_bonus"])
	return n


# --- the act ------------------------------------------------------------------------------------------------------


static func in_hours(s: GameSession, data: Dictionary, id: String) -> bool:
	var h: Array = def(s, data, id).get("hours", kind(data, str(def(s, data, id)["kind"]))["hours"])
	var hour := s.minute / 60
	var a := int(h[0])
	var b := int(h[1])
	return (a <= b and hour >= a and hour < b) or (a > b and (hour >= a or hour < b))


static func act_why(s: GameSession, data: Dictionary, id: String) -> String:
	var d := def(s, data, id)
	if status(s.character, id) != "active":
		return "HEIST_NOT_ACTIVE"
	if s.room_id != str(d["target"]):
		return "HEIST_NOT_THERE"
	if not in_hours(s, data, id):
		return "HEIST_NOT_NOW"
	if not str(d.get("victim", "")).is_empty() and str(d["kind"]) == "burglary" and BondRules.here(s, data, str(d["victim"])):
		return "HEIST_WATCHED"
	var cargo: Dictionary = d.get("cargo", {})
	for item: String in cargo:
		if int(s.character.get("inventory", {}).get(item, 0)) < int(cargo[item]):
			return "HEIST_NO_CARGO"
	return ""


## The act's check: the better of the kind's skills and its tool. {bonus, label}
static func act_check(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var a: Dictionary = kind(data, str(def(s, data, id)["kind"]))["act"]
	var best := {"bonus": -99, "label": ""}
	for skill: Variant in a.get("skills", []):
		var b := _bonus(s, data, str(skill))
		if b > int(best["bonus"]):
			best = {"bonus": b, "label": CraftRules.tr_skill(data, str(skill))}
	var tool := str(a.get("tool", ""))
	if not tool.is_empty() and int(s.character.get("inventory", {}).get(tool, 0)) > 0 and CraftRules.bonus(s, data, tool) > int(best["bonus"]):
		best = {"bonus": CraftRules.bonus(s, data, tool), "label": BackgroundRules.tool_name(data, tool)}
	best["bonus"] = int(best["bonus"]) + prep(s, data, id)
	return best


static func act_chance(s: GameSession, data: Dictionary, id: String) -> int:
	return JobRules._chance(int(act_check(s, data, id)["bonus"]), dc(s, data, id), false)


static func act_minutes(s: GameSession, data: Dictionary, id: String) -> int:
	return int(kind(data, str(def(s, data, id)["kind"])).get("act_minutes", 30))


static func outcome_for(data: Dictionary, margin: int) -> Dictionary:
	var out: Dictionary = cfg(data)["outcomes"][0]
	for o: Dictionary in cfg(data)["outcomes"]:
		if margin >= int(o["from"]):
			out = o
	return out


## The act (act_why first; its time already passed): {lines, fight: [foes]}.
static func act(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var d := def(s, data, id)
	var k := kind(data, str(d["kind"]))
	var c := s.character
	var ch := act_check(s, data, id)
	var nat := s.rng.randi_range(1, 20)
	var total := nat + int(ch["bonus"])
	var margin := 5 if nat == 20 else -5 if nat == 1 else total - dc(s, data, id)
	var o := outcome_for(data, margin)
	var lines: Array[String] = ["«%s»: %s %d против Сл %d — %s" % [d["name"], ch["label"], total, dc(s, data, id), o["name"]]]
	var fight: Array = []
	if str(o["id"]) == "fail":
		_rw(c)[id]["status"] = "failed"
		match str(k.get("fail", "caught")):
			"fight":
				lines.append("%s поднимает крик — охрана хватается за оружие" % victim_name(s, data, id).capitalize())
				fight.append({"monster": str(cfg(data)["fight_monster"]), "name": "Охранник", "col": 0})
				lines.append_array(_crime(s, data, id))
			"seized":
				var cargo: Dictionary = d.get("cargo", {})
				for item: String in cargo:
					_lose(c, item, int(cargo[item]))
				lines.append("Груз нашли и забрали")
				lines.append_array(_crime(s, data, id))
			_:
				lines.append("Вас заметили")
				lines.append_array(_crime(s, data, id))
		lines.append_array(OrgRules.on_heist(s, data, id, "fail", 0))
		return {"lines": lines, "fight": fight}
	_rw(c)[id]["status"] = "done"
	var got := int(d.get("loot_cp", 0)) + int(d.get("reward_cp", 0))
	c["gold_cp"] = int(c.get("gold_cp", 0)) + got
	if got > 0:
		lines.append("Добыча: %s" % Money.format(got))
	var cargo: Dictionary = d.get("cargo", {})
	for item: String in cargo:
		_lose(c, item, int(cargo[item]))
	var items: Dictionary = d.get("items", {})
	var owner := str(d.get("victim", "")) if bool(k.get("mark_owner", false)) else ""
	for item: String in items:
		OwnerRules.mark(s, ItemRules.found(c, data, s.items, item, int(items[item])), int(items[item]), owner)
		lines.append("Взято: %s%s" % [ItemRules.display_name(data["items"], s.items, item), " ×%d" % int(items[item]) if int(items[item]) > 1 else ""])
	var seen := str(o["id"]) == "done" and s.rng.randf() < float(cfg(data)["trace_chance"])
	var mask := str(k.get("mask_step", ""))
	if not mask.is_empty() and not step_ok(c, id, mask):
		seen = true
	if seen:
		lines.append("Остался след — вас узнают")
		lines.append_array(_crime(s, data, id))
	lines.append_array(OrgRules.on_heist(s, data, id, str(o["id"]), got))
	return {"lines": lines, "fight": fight}


## The job's crime is known where the law looks for it. Lines.
static func _crime(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var d := def(s, data, id)
	var world := WorldView.new(data["world"])
	var loc := str(d.get("law_location", world.location_id(str(d["target"]))))
	return CrimeRules.on_job(s, data, str(kind(data, str(d["kind"]))["crime"]), str(d.get("victim", "")), str(d["target"]), loc)


static func _lose(c: Dictionary, item: String, qty: int) -> void:
	var inv: Dictionary = c["inventory"]
	var left := int(inv.get(item, 0)) - qty
	if left > 0:
		inv[item] = left
	else:
		inv.erase(item)


# --- the master's `heist` -----------------------------------------------------------------------------------------


static func _level_cap(data: Dictionary, key: String, level: int) -> int:
	var caps: Array = cfg(data)["make_heist"][key]
	return int(caps[clampi(level, 0, caps.size() - 1)])


## A criminal job from the player's plan: {kind, name, target_room, victim_npc?, victim_name?, giver_npc?, org_id?,
## loot_cp, items?, reward_cp?, cargo?, dc_tier, text}. {plan, summary} or {reason}.
static func make(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make_heist"]
	var k := str(e.get("heist_kind", ""))
	if kind(data, k).is_empty():
		return {"reason": "heist_kind — из %s" % ", ".join(cfg(data)["kinds"].keys())}
	var world := WorldView.new(data["world"])
	var target := str(e.get("target_room", ""))
	if world.room(target).is_empty():
		return {"reason": "target_room %s — комната мира, где совершается дело" % target}
	var name := str(e.get("name", "")).strip_edges().left(60)
	if name.is_empty():
		return {"reason": "нужно name — как зовётся дело"}
	var tier := str(e.get("dc_tier", "medium"))
	if not (m["dc_tiers"] as Array).has(tier):
		return {"reason": "dc_tier — из %s" % ", ".join(m["dc_tiers"])}
	var lvl := int(s.character.get("level", 1))
	var loot := int(e.get("loot_cp", 0)) if e.get("loot_cp") != null else 0
	if loot < 0 or loot > _level_cap(data, "loot_cp_by_level", lvl):
		return {"reason": "loot_cp — не больше %s на %d уровне" % [Money.format(_level_cap(data, "loot_cp_by_level", lvl)), lvl]}
	var reward := int(e.get("reward_cp", 0)) if e.get("reward_cp") != null else 0
	if reward < 0 or reward > _level_cap(data, "reward_cp_by_level", lvl):
		return {"reason": "reward_cp — не больше %s на %d уровне" % [Money.format(_level_cap(data, "reward_cp_by_level", lvl)), lvl]}
	var items := {}
	var raw: Variant = e.get("items")
	for item: Variant in (raw if raw is Array else []):
		var iid := str(item)
		var idef := ItemRules.def_of(data["items"], s.items, iid)
		if idef.is_empty() or int(idef.get("value_cp", 0)) > int(m["max_item_cp"]):
			return {"reason": "items — вещи каталога не дороже %s; %s не подходит" % [Money.format(int(m["max_item_cp"])), iid]}
		items[iid] = int(items.get(iid, 0)) + 1
	if items.size() > int(m["max_items"]):
		return {"reason": "items — не больше %d вещей" % int(m["max_items"])}
	var cargo := {}
	var rc: Variant = e.get("cargo")
	for item: Variant in (rc if rc is Array else []):
		if ItemRules.def_of(data["items"], s.items, str(item)).is_empty():
			return {"reason": "cargo — вещи каталога; %s нет" % item}
		cargo[str(item)] = int(cargo.get(str(item), 0)) + 1
	if k == "smuggling" and cargo.is_empty():
		return {"reason": "контрабанде нужен cargo — что провозят"}
	var victim := str(e.get("victim_npc", "")) if e.get("victim_npc") != null else ""
	if not victim.is_empty() and BondRules.npc_def(s, data, victim).is_empty():
		return {"reason": "victim_npc %s — NPC мира" % victim}
	var giver := str(e.get("giver_npc", "")) if e.get("giver_npc") != null else ""
	if not giver.is_empty() and not BondRules.here(s, data, giver):
		return {"reason": "giver_npc %s — NPC сцены, что даёт дело" % giver}
	var org := str(e.get("org_id", "")) if e.get("org_id") != null else ""
	if not org.is_empty() and OrgRules.def(s, data, org).is_empty():
		return {"reason": "org_id %s — организация мира" % org}
	var id := "gen_h_" + ("%s|%s|%s" % [k, target, name]).md5_text().left(8)
	if not def(s, data, id).is_empty():
		return {"reason": "такое дело уже есть — окно «Дела»"}
	var d := {"kind": k, "name": name, "target": target, "dc_tier": tier, "loot_cp": loot, "items": items, "reward_cp": reward,
		"cargo": cargo, "text": str(e.get("text", "")).left(300), "generated": true}
	if not victim.is_empty():
		d["victim"] = victim
	else:
		d["victim_name"] = str(e.get("victim_name", "")).left(60)
	if not giver.is_empty():
		d["giver"] = giver
	if not org.is_empty():
		d["org"] = org
	return {"plan": {"id": id, "def": d}, "summary": "Дело: «%s» — %s, %s" % [name, kind(data, k)["name"], world.place_path(target)]}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	var made: Dictionary = gen.get("heists", {})
	made[str(plan["id"])] = (plan["def"] as Dictionary).duplicate(true)
	gen["heists"] = made
	var lines := take(s, data, str(plan["id"]))
	lines.append("Подготовка и само дело — окно «Дела»")
	return lines


# --- for the master -----------------------------------------------------------------------------------------------


static func text(s: GameSession, data: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in active(s.character):
		var d := def(s, data, id)
		var ready: Array[String] = []
		for st: Dictionary in steps(s, data, id):
			if step_ok(s.character, id, str(st["id"])):
				ready.append(str(st["name"]).to_lower())
		parts.append("«%s» — %s, %s%s%s" % [d["name"], kind(data, str(d["kind"]))["name"], target_name(s, data, id),
			", цель: " + victim_name(s, data, id) if not victim_name(s, data, id).is_empty() else "",
			", готово: " + ", ".join(ready) if not ready.is_empty() else ""])
	return ("Дела (окно «Дела»: подготовка и само дело — кнопки): " + "; ".join(parts)) if not parts.is_empty() else ""
