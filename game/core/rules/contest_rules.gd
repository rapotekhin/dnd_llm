class_name ContestRules
extends RefCounted
## Contests (roadmap v0.7.40 «Состязание: досуг в таверне»): a game of the hero with an NPC of the scene for a stake —
## dice, cards, arm wrestling, drinking, a song, riddles. A kind is data (rules.contests.kinds, the master's own in
## world.contest_kinds): the check of each side ({skill} | {ability} | {save}), a gaming set that adds its
## proficiency, rounds to win, what the loser gets, the skill of cheating. Both sides roll a round, the higher total
## takes it, a tie — nobody; the NPC rolls by its SRD template. Cheating: the hero's cheat skill against the NPC's
## roll of `cheat_against` — higher wins the round, otherwise caught: the stake is lost and the NPC reacts as to a
## caught theft (TheftRules.react). The stake is coins (no more than the NPC's purse) or a thing of the NPC — an item of
## its pockets, its leave to walk in (SiteRules permits), a secret (SocialRules) — against the hero's coins of its
## worth; both stakes are on the table from the start. The game lives in `c.contest`; the games of the day with each
## NPC in `c.contests_day` {npc: {day, n, won, caught}}. The master offers a game by the effect `contest`.
## A kind with `bout` (v0.7.45) is a duel: no rounds of dice — a fight to surrender with the NPC's template by the
## arena's way (ArenaRules), its end settles the stake (settle).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["contests"]


## The engine's kinds and the master's made ones.
static func kinds(data: Dictionary) -> Dictionary:
	var out: Dictionary = (cfg(data)["kinds"] as Dictionary).duplicate()
	out.merge(data["world"].get("contest_kinds", {}), true)
	return out


static func kind(data: Dictionary, id: String) -> Dictionary:
	return kinds(data).get(id, {})


static func _mod(score: int) -> int:
	return floori((score - 10) / 2.0)


## The check of a kind as the hero's roll params: {skill | ability | save, dc_tier, tool}.
static func hero_params(data: Dictionary, k: Dictionary, cheat: bool = false) -> Dictionary:
	var p := {"dc_tier": "medium"}
	if cheat:
		p["skill"] = str(k.get("cheat", ""))
		return p
	p.merge(k.get("check", {}), true)
	if not str(k.get("tool", "")).is_empty():
		p["tool"] = str(k["tool"])
	return p


## The NPC's bonus for a check {skill | ability | save} by its SRD template, with its gaming set when the pack gives it
## one (`tools`): {bonus, why}.
static func npc_bonus(data: Dictionary, npc_id: String, check: Dictionary, tool: String = "") -> Dictionary:
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	var m: Dictionary = data["monsters"].get(str(npc.get("monster", CombatRules.cfg(data)["default_npc_monster"])), {})
	var ab: Dictionary = m.get("abilities", {})
	var bonus := 0
	var why := ""
	if check.has("skill"):
		var skill := str(check["skill"])
		bonus = int(m.get("skills", {}).get(skill, _mod(int(ab.get(str(data["rules"]["skills"].get(skill, "wis")), 10)))))
		why = skill
	elif check.has("save"):
		bonus = int(m.get("saves", {}).get(str(check["save"]), _mod(int(ab.get(str(check["save"]), 10)))))
		why = str(check["save"])
	else:
		bonus = _mod(int(ab.get(str(check.get("ability", "wis")), 10)))
		why = str(check.get("ability", "wis"))
	if not tool.is_empty() and (npc.get("tools", []) as Array).has(tool):
		bonus += 2 + int(maxf(float(m.get("cr", 0)), 1.0) - 1.0) / 4
	return {"bonus": bonus, "why": why}


## The hero's chance to take a round, percent: d20 + `hero` above d20 + `npc` (a tie takes nobody).
static func chance(hero: int, npc: int) -> int:
	var won := 0
	for a in range(1, 21):
		for b in range(1, 21):
			if a == 20 or (a != 1 and a + hero > b + npc):
				won += 1
	return roundi(won / 4.0)


## The hero's bonus to a kind's round (or its cheating) and the NPC's against it: {hero, npc, chance}.
static func odds(s: GameSession, data: Dictionary, npc_id: String, kind_id: String, cheat: bool = false) -> Dictionary:
	var k := kind(data, kind_id)
	var p := hero_params(data, k, cheat)
	var t := BackgroundRules.tool_check(s.character, data, str(p.get("tool", "")), str(p.get("skill", "")))
	var hero := CheckEngine.bonus_for(s.character, p, data) + int(t["bonus"]) + DifficultyRules.bonus(s, data)
	var check: Dictionary = {"skill": str(k.get("cheat_against", "insight"))} if cheat else k.get("npc_check", k.get("check", {}))
	var npc := int(npc_bonus(data, npc_id, check, "" if cheat else str(k.get("tool", "")))["bonus"])
	return {"hero": hero, "npc": npc, "chance": chance(hero, npc)}


static func state(s: GameSession) -> Dictionary:
	return s.character.get("contest", {})


static func _day(s: GameSession, npc_id: String) -> Dictionary:
	var all: Dictionary = s.character.get("contests_day", {})
	var rec: Dictionary = all.get(npc_id, {})
	if int(rec.get("day", 0)) != s.day:
		rec = {"day": s.day, "n": 0}
		all[npc_id] = rec
		s.character["contests_day"] = all
	return rec


## The coins in the NPC's pockets, cp.
static func purse(s: GameSession, data: Dictionary, npc_id: String) -> int:
	var cp := 0
	for e: Dictionary in TheftRules.pockets(s, data, npc_id):
		cp += int(e.get("cp", 0))
	return cp


static func _purse_add(s: GameSession, data: Dictionary, npc_id: String, delta: int) -> void:
	var list: Array = TheftRules.pockets(s, data, npc_id)
	for e: Dictionary in list.duplicate():
		if int(e.get("cp", 0)) <= 0:
			continue
		var left := int(e["cp"]) + delta
		if left > 0 or delta > 0:
			e["cp"] = maxi(0, left)
			return
		delta = left
		list.erase(e)
	if delta > 0:
		list.append({"id": "k%d" % (list.size() + 100), "name": "Кошель", "item_id": "", "cp": delta, "qty": 1, "worn": false,
			"dc": TheftRules.dc(s, data, npc_id, {"item_id": ""})})


## Why `npc_id` will not play now ("" — it will).
static func why_not(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var who := BondRules.npc_name(s, data, npc_id)
	if not s.npcs_here(data["world"], s.room_id).has(npc_id):
		return "%s здесь нет" % who
	if CombatRules.active(s):
		return "в бою не до игр"
	if not state(s).is_empty():
		return "игра уже идёт"
	var rec := _day(s, npc_id)
	if bool(rec.get("caught", false)):
		return "%s не сядет играть с шулером до завтра" % who
	if s.attitude(npc_id) < int(cfg(data)["min_attitude"]):
		return "%s не станет играть с героем" % who
	if int(rec.get("n", 0)) >= int(cfg(data)["per_npc_day"]):
		return "%s на сегодня наигрался — завтра" % who
	if stakes(s, data, npc_id).is_empty():
		return "%s нечего поставить" % who
	return ""


## What the NPC may put on the table: [{kind: coins | item | permit | secret, name, cp | max, …}].
static func stakes(s: GameSession, data: Dictionary, npc_id: String) -> Array[Dictionary]:
	var c := cfg(data)
	var out: Array[Dictionary] = []
	var cap := mini(purse(s, data, npc_id), int(c["stake"]["max_cp_level"]) * int(s.character.get("level", 1)))
	if cap >= int(c["stake"]["min_cp"]):
		out.append({"kind": "coins", "name": "Монеты", "max": cap})
	for e: Dictionary in TheftRules.pockets(s, data, npc_id):
		var id := str(e.get("item_id", ""))
		if id.is_empty() or bool(e.get("worn", false)):
			continue
		var cp := int(ItemRules.def_of(data["items"], s.items, id).get("value_cp", 0))
		if cp > 0 and cp <= int(c["things"]["item_cap_cp"]):
			out.append({"kind": "item", "entry": str(e["id"]), "name": str(e["name"]), "cp": maxi(cp, int(c["stake"]["min_cp"]))})
	var world := WorldView.new(data["world"])
	for sid: String in SiteRules.closed_to_hero(s, data, npc_id):
		out.append({"kind": "permit", "site": sid, "name": "Пропуск: %s" % world.site(sid).get("name", sid), "cp": int(c["things"]["permit_cp"])})
	for sec: Dictionary in SocialRules.secrets(data, npc_id):
		if not SocialRules.told(s, npc_id, str(sec["id"])):
			out.append({"kind": "secret", "id": str(sec["id"]), "name": "Тайна: %s" % sec.get("hint", "что-то, о чём молчит"), "cp": int(c["things"]["secret_cp"])})
	return out


## Sits down to play: both stakes go on the table. {lines} or {reason}. `cp` — the coins of a coins stake.
static func start(s: GameSession, data: Dictionary, npc_id: String, kind_id: String, stake_i: int, cp: int = 0) -> Dictionary:
	var why := why_not(s, data, npc_id)
	if not why.is_empty():
		return {"reason": why}
	var k := kind(data, kind_id)
	if k.is_empty():
		return {"reason": "нет такой игры: %s" % kind_id}
	var list := stakes(s, data, npc_id)
	if stake_i < 0 or stake_i >= list.size():
		return {"reason": "нет такой ставки"}
	var stake: Dictionary = list[stake_i]
	if str(stake["kind"]) == "coins":
		cp = clampi(cp, int(cfg(data)["stake"]["min_cp"]), int(stake["max"]))
	else:
		cp = int(stake["cp"])
	if int(s.character["gold_cp"]) < cp:
		return {"reason": "у героя нет %s на ставку" % Money.format(cp)}
	s.character["gold_cp"] = int(s.character["gold_cp"]) - cp
	if str(stake["kind"]) == "coins":
		_purse_add(s, data, npc_id, -cp)
	var rec := _day(s, npc_id)
	rec["n"] = int(rec.get("n", 0)) + 1
	s.character["contest"] = {"npc": npc_id, "kind": kind_id, "stake": stake, "cp": cp, "hero": 0, "npc_wins": 0, "round": 0}
	var on := Money.format(cp) if str(stake["kind"]) == "coins" else "%s против %s" % [stake["name"], Money.format(cp)]
	return {"lines": ["%s с %s, до %d побед — на кону %s" % [k["name"], BondRules.npc_name(s, data, npc_id), int(k.get("wins", 1)), on]]}


## The NPC's roll of the round: {total, nat, bonus} — its check of the kind or, against cheating, `cheat_against`.
static func npc_roll(s: GameSession, data: Dictionary, cheat: bool = false) -> Dictionary:
	var st := state(s)
	var k := kind(data, str(st["kind"]))
	var check: Dictionary = {"skill": str(k.get("cheat_against", "insight"))} if cheat else k.get("npc_check", k.get("check", {}))
	var b := npc_bonus(data, str(st["npc"]), check, "" if cheat else str(k.get("tool", "")))
	var nat := s.rng.randi_range(1, 20)
	return {"total": nat + int(b["bonus"]), "nat": nat, "bonus": int(b["bonus"])}


## One round by the hero's total against the NPC's: lines; the game ends when a side reaches the kind's wins.
static func round(s: GameSession, data: Dictionary, hero_total: int, npc_total: int, cheat: bool = false) -> Array[String]:
	var st := state(s)
	if st.is_empty():
		return []
	var k := kind(data, str(st["kind"]))
	var who := BondRules.npc_name(s, data, str(st["npc"]))
	st["round"] = int(st["round"]) + 1
	var lines: Array[String] = []
	if cheat and hero_total <= npc_total:
		return _caught(s, data)
	if hero_total > npc_total:
		st["hero"] = int(st["hero"]) + 1
		lines.append("Раунд %d: %d против %d — ваш%s" % [st["round"], hero_total, npc_total, " (рука ловчее глаза)" if cheat else ""])
	elif hero_total < npc_total:
		st["npc_wins"] = int(st["npc_wins"]) + 1
		lines.append("Раунд %d: %d против %d — за %s" % [st["round"], hero_total, npc_total, who])
	else:
		lines.append("Раунд %d: %d против %d — ничья" % [st["round"], hero_total, npc_total])
	lines.append("Счёт %d : %d" % [st["hero"], st["npc_wins"]])
	var wins := int(k.get("wins", 1))
	if int(st["hero"]) >= wins:
		lines.append_array(_finish(s, data, true))
	elif int(st["npc_wins"]) >= wins:
		lines.append_array(_finish(s, data, false))
	return lines


## The hero gives up: the NPC takes the stake. Lines.
static func forfeit(s: GameSession, data: Dictionary) -> Array[String]:
	if state(s).is_empty():
		return []
	return ["Герой сдаётся"] + _finish(s, data, false)


## Whether a kind is a duel by the arena's way (v0.7.45).
static func is_bout(data: Dictionary, kind_id: String) -> bool:
	return bool(kind(data, kind_id).get("bout", false))


## The duel's fight for GameState.start_combat (the game going is a `bout`): {foes, source, lines}.
static func duel(s: GameSession, data: Dictionary) -> Dictionary:
	var st := state(s)
	var npc := str(st["npc"])
	var n: Dictionary = data["world"]["npcs"].get(npc, {})
	var who := BondRules.npc_name(s, data, npc)
	var mon := str(n.get("monster", CombatRules.cfg(data)["default_npc_monster"]))
	return {"foes": [{"monster": mon, "name": who}], "source": {"arena": {"kind": "duel", "rule": "yield", "npc": npc, "foe": who}, "room_from": s.room_id},
		"lines": ["Поединок до сдачи с %s" % who]}


## The end of a duel: the stake goes to the winner. Lines.
static func settle(s: GameSession, data: Dictionary, won: bool) -> Array[String]:
	if state(s).is_empty():
		return []
	return _finish(s, data, won)


static func _finish(s: GameSession, data: Dictionary, won: bool) -> Array[String]:
	var st := state(s)
	var npc := str(st["npc"])
	var k := kind(data, str(st["kind"]))
	var who := BondRules.npc_name(s, data, npc)
	var stake: Dictionary = st["stake"]
	var cp := int(st["cp"])
	var game := str(k.get("name", "игра")).to_lower()
	var lines: Array[String] = []
	s.character.erase("contest")
	var rec := _day(s, npc)
	if won:
		s.character["gold_cp"] = int(s.character["gold_cp"]) + cp
		match str(stake["kind"]):
			"coins":
				s.character["gold_cp"] = int(s.character["gold_cp"]) + cp
				lines.append("Победа: +%s" % Money.format(cp))
			"item":
				for e: Dictionary in TheftRules.pockets(s, data, npc).duplicate():
					if str(e["id"]) == str(stake["entry"]):
						(s.pockets[npc] as Array).erase(e)
						ItemRules.found(s.character, data, s.items, str(e["item_id"]), int(e.get("qty", 1)))
						lines.append("Победа: %s отдаёт %s" % [who, e["name"]])
			"permit":
				lines.append("Победа")
				lines.append_array(SiteRules.grant(s, data, npc, str(stake["site"])))
			"secret":
				for sec: Dictionary in SocialRules.secrets(data, npc):
					if str(sec["id"]) == str(stake["id"]):
						lines.append("Победа: %s выкладывает тайну — %s" % [who, SocialRules.tell(s, data, npc, sec)])
		s.remember(npc, "проиграл%s герою: %s" % [CrimeRules._ending(data, npc), game])
		if not bool(rec.get("won", false)):
			rec["won"] = true
			lines.append_array(ReputationRules.add(s, data, WorldView.new(data["world"]).location_id(s.room_id),
				int(ReputationRules.cfg(data)["points"].get("contest_won", 0)), "победа: " + game))
	else:
		if str(stake["kind"]) == "coins":
			_purse_add(s, data, npc, cp * 2)
		else:
			_purse_add(s, data, npc, cp)
		lines.append("Поражение: −%s" % Money.format(cp))
		s.remember(npc, "обыграл%s героя: %s" % [CrimeRules._ending(data, npc), game])
		var lose: Dictionary = k.get("lose", {})
		if not str(lose.get("condition", "")).is_empty():
			ConditionRules.add_effect(s.character, {"condition": str(lose["condition"]), "ends": ConditionRules.ends_for(s, data, str(lose.get("ends", "long_rest"))),
				"source": {"kind": "contest", "name": str(k["name"])}})
			lines.append("%s: %s до отдыха" % [k["name"], ConditionRules.name_of(data, str(lose["condition"]))])
	lines.append_array(BondRules.on_deed(s, data, npc, "contest_played", game))
	return lines


## Caught cheating: the stake goes to the NPC, which reacts as to a caught theft. Lines.
static func _caught(s: GameSession, data: Dictionary) -> Array[String]:
	var st := state(s)
	var npc := str(st["npc"])
	var who := BondRules.npc_name(s, data, npc)
	var cp := int(st["cp"])
	_purse_add(s, data, npc, cp * 2 if str(st["stake"]["kind"]) == "coins" else cp)
	s.character.erase("contest")
	_day(s, npc)["caught"] = true
	var lines: Array[String] = ["%s ловит героя на жульничестве — ставка %s пропала" % [who, Money.format(cp)]]
	lines.append_array(TheftRules.react(s, data, npc, "поймал%s героя на жульничестве в игре", "contest_cheat", "contest_cheat", "жульничество"))
	return lines


# --- the master's offer (effect `contest`) ------------------------------------------------------------------------


## The plan of `contest` {npc_id, game | new_kind {name, check, npc_check?, wins, lose_condition?, cheat?}}:
## {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var npc := str(e.get("npc_id", "")) if e.get("npc_id") != null else ""
	var why := why_not(s, data, npc)
	if not why.is_empty():
		return {"reason": why}
	var made := {}
	var kid := str(e.get("game", "")) if e.get("game") != null else ""
	if e.get("new_kind") is Dictionary:
		var r := _plan_kind(data, e["new_kind"])
		if r.has("reason"):
			return r
		made = r
		kid = str(r["id"])
	elif kind(data, kid).is_empty():
		return {"reason": "нет такой игры: %s — game одна из %s или new_kind" % [kid, ", ".join(kinds(data).keys())]}
	var name := str((made.get("def", {}) as Dictionary).get("name", kind(data, kid).get("name", kid)))
	return {"plan": {"npc_id": npc, "kind": kid, "made": made}, "summary": "%s зовёт сыграть: %s (окно «Состязание»)" % [BondRules.npc_name(s, data, npc), name]}


static func _plan_kind(data: Dictionary, spec: Dictionary) -> Dictionary:
	var mk: Dictionary = cfg(data)["make"]
	var name := str(spec.get("name", "")).strip_edges()
	if name.is_empty():
		return {"reason": "new_kind без name"}
	var check := _check_of(data, spec.get("check", {}))
	if check.is_empty():
		return {"reason": "new_kind.check — ровно одно: skill (навык 5e), ability или save (str, dex, con, int, wis, cha)"}
	var def := {"name": name, "check": check, "wins": clampi(int(spec.get("wins", 2)), int(mk["wins"][0]), int(mk["wins"][1]))}
	if spec.get("npc_check") is Dictionary:
		var nc := _check_of(data, spec["npc_check"])
		if not nc.is_empty():
			def["npc_check"] = nc
	var cond := str(spec.get("lose_condition", "")) if spec.get("lose_condition") != null else ""
	if not cond.is_empty():
		if not (mk["conditions"] as Array).has(cond):
			return {"reason": "lose_condition — одно из %s" % ", ".join(mk["conditions"])}
		def["lose"] = {"condition": cond, "ends": "long_rest"}
	var cheat := str(spec.get("cheat", "")) if spec.get("cheat") != null else ""
	if (data["rules"]["skills"] as Dictionary).has(cheat):
		def["cheat"] = cheat
		def["cheat_against"] = "perception" if cheat == "sleight_of_hand" else "insight"
	return {"id": "gen_c_" + name.md5_text().substr(0, 8), "def": def}


static func _check_of(data: Dictionary, spec: Variant) -> Dictionary:
	if not (spec is Dictionary):
		return {}
	var d: Dictionary = spec
	var out := {}
	if (data["rules"]["skills"] as Dictionary).has(str(d.get("skill", ""))):
		out["skill"] = str(d["skill"])
	if (data["rules"]["saves"] as Array).has(str(d.get("ability", ""))):
		out["ability"] = str(d["ability"])
	if (data["rules"]["saves"] as Array).has(str(d.get("save", ""))):
		out["save"] = str(d["save"])
	return out if out.size() == 1 else {}


## Applies the offer: the made kind is kept with the world, the window opens on the master's turn's end. Lines.
static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var made: Dictionary = p.get("made", {})
	if not made.is_empty():
		var gen := WorldGen.generated(s)
		if not gen.has("contest_kinds"):
			gen["contest_kinds"] = {}
		gen["contest_kinds"][str(made["id"])] = (made["def"] as Dictionary).duplicate(true)
		if not data["world"].has("contest_kinds"):
			data["world"]["contest_kinds"] = {}
		data["world"]["contest_kinds"][str(made["id"])] = (made["def"] as Dictionary).duplicate(true)
	s.character["contest_offer"] = {"npc": str(p["npc_id"]), "kind": str(p["kind"])}
	return ["%s зовёт сыграть: %s" % [BondRules.npc_name(s, data, str(p["npc_id"])), kind(data, str(p["kind"])).get("name", p["kind"])]]
