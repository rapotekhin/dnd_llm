class_name ArenaRules
extends RefCounted
## The arena and tournaments (roadmap v0.7.45). An arena is an object of the world (a site with `arena` {rule}) of the
## kind `arena`, its manager — the staff of the role `rules.arena.manager_role` (or its owner). Its rule is its data:
## «yield» — a bout ends when a side gives up or drops (the hero's blows only knock out, the hero at 0 HP loses, not
## dies), «death» — the blood pit (`rules.arena.rules`: the prize and the fame of a rule). The hero enlists for
## `fee_cp`, fights one bout a day against the opponent of its rank (`ranks`: SRD templates, a prize, the wins that
## lift the rank); a bout is a fight of CombatRules with `source.arena`, its end — after_bout: the prize, the bet on
## oneself, the rank, the fame of the settlement (ReputationRules). Bets on others: the day's card of two fighters, the
## engine plays the bout out itself (simulate — the same attacks, to-hit and dice as the combat AI). The odds come from
## the engine's estimate by HP and damage a round (what XP stands for), the house's shown one is off by up to
## `bet.noise_pct`; an Insight check against `insight.dc` shows the true estimate. A festival with `tournament`
## {site, bouts, prize_cp, prize_item} makes a ladder for one day: bouts of rising ranks, a loss — out.
## A duel by challenge (the contest kind with `bout`, v0.7.40) is a bout of the same kind with the NPC itself.
##
## c["arena"] = {site: {rank, wins, rank_wins, losses, day}}; c["arena_bets"] = {site: day};
## c["arena_insight"] = {site: {day, ok}}; c["tourney"] = {fest, day, site, round, out, done}.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["arena"]


static func on(data: Dictionary) -> bool:
	return data["rules"].has("arena")


## The arena's own data: {rule, name?}; {} — the site is no arena.
static func arena(data: Dictionary, sid: String) -> Dictionary:
	var a: Variant = WorldView.new(data["world"]).site(sid).get("arena", null)
	return a if a is Dictionary else {}


static func rule(data: Dictionary, sid: String) -> String:
	var r := str(arena(data, sid).get("rule", "yield"))
	return r if (cfg(data)["rules"] as Dictionary).has(r) else "yield"


static func rule_cfg(data: Dictionary, sid: String) -> Dictionary:
	return cfg(data)["rules"][rule(data, sid)]


## The arena an NPC runs: the site whose staff has it as the manager (or whose owner it is). "" — none.
static func of_manager(data: Dictionary, npc_id: String) -> String:
	if not on(data) or npc_id.is_empty():
		return ""
	var sites: Dictionary = data["world"].get("sites", {})
	for sid: String in sites:
		if arena(data, sid).is_empty():
			continue
		for h: Variant in sites[sid].get("staff", []):
			if str((h as Dictionary).get("npc", "")) == npc_id and str((h as Dictionary).get("role", "")) == str(cfg(data)["manager_role"]):
				return sid
		if str(sites[sid].get("owner", "")) == npc_id:
			return sid
	return ""


static func manager(s: GameSession, data: Dictionary, sid: String) -> String:
	for h: Dictionary in ObjectRules.staff(s, data, sid):
		if str(h["role"]) == str(cfg(data)["manager_role"]):
			return str(h["who"])
	return str(WorldView.new(data["world"]).site(sid).get("owner", ""))


static func site_name(data: Dictionary, sid: String) -> String:
	return str(WorldView.new(data["world"]).site(sid).get("name", sid))


static func rec(s: GameSession, sid: String) -> Dictionary:
	return s.character.get("arena", {}).get(sid, {})


static func enlisted(s: GameSession, sid: String) -> bool:
	return not rec(s, sid).is_empty()


static func _rec_new(s: GameSession, sid: String) -> Dictionary:
	var all: Dictionary = s.character.get("arena", {})
	if not all.has(sid):
		all[sid] = {"rank": 0, "wins": 0, "rank_wins": 0, "losses": 0, "day": 0}
	s.character["arena"] = all
	return all[sid]


static func ranks(data: Dictionary) -> Array:
	return cfg(data)["ranks"]


static func rank(s: GameSession, sid: String) -> int:
	return int(rec(s, sid).get("rank", 0))


static func rank_name(data: Dictionary, i: int) -> String:
	return str(ranks(data)[clampi(i, 0, ranks(data).size() - 1)]["name"])


## The day's seeded numbers of an arena: the same opponent and card all day long.
static func _rng(s: GameSession, sid: String, salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%d|%s|%d" % [sid, s.day, salt, int(s.rng.seed)])
	return r


static func _nick(data: Dictionary, r: RandomNumberGenerator) -> String:
	var names: Array = cfg(data)["nicknames"]
	return str(names[r.randi_range(0, names.size() - 1)])


static func fighter_name(data: Dictionary, monster: String, nick: String) -> String:
	return "%s «%s»" % [str(data["monsters"][monster]["name"]), nick]


## The hero's opponent of the day at its rank: {monster, name, rank}.
static func opponent(s: GameSession, data: Dictionary, sid: String, at_rank: int = -1) -> Dictionary:
	var i := rank(s, sid) if at_rank < 0 else at_rank
	i = clampi(i, 0, ranks(data).size() - 1)
	var foes: Array = ranks(data)[i]["foes"]
	var r := _rng(s, sid, "foe%d" % i)
	var m := str(foes[r.randi_range(0, foes.size() - 1)])
	return {"monster": m, "name": fighter_name(data, m, _nick(data, r)), "rank": i}


# --- the engine's estimate ----------------------------------------------------------------------------------------


static func _avg(expr: String) -> float:
	var d := CombatRules.dice_range(expr)
	return (d[0] + d[1]) / 2.0


static func _hit_p(to_hit: int, ac: int) -> float:
	return clampf((21.0 - (ac - to_hit)) / 20.0, 0.05, 0.95)


## The melee attacks of a template's full turn, as the combat AI makes them (Multiattack of melee actions).
static func attacks(data: Dictionary, monster: String) -> Array[Dictionary]:
	var m: Dictionary = data["monsters"][monster]
	var by_en := {}
	var best := {}
	for a: Dictionary in m["actions"]:
		by_en[str(a.get("name_en", ""))] = a
		if str(a.get("kind")) == "melee" and not (a.get("damage", []) as Array).is_empty() \
				and (best.is_empty() or int(a.get("to_hit", 0)) > int(best.get("to_hit", 0))):
			best = a
	var plan: Array[Dictionary] = []
	for x: Dictionary in m.get("multiattack", []):
		var a: Dictionary = by_en.get(str(x["action"]), {})
		if str(a.get("kind")) == "melee" and not (a.get("damage", []) as Array).is_empty():
			for i in int(x["count"]):
				plan.append(a)
	if plan.is_empty() and not best.is_empty():
		plan.append(best)
	return plan


static func monster_dpr(data: Dictionary, monster: String, ac: int) -> float:
	var out := 0.0
	for a: Dictionary in attacks(data, monster):
		var dmg := 0.0
		for d: Dictionary in a["damage"]:
			dmg += _avg(str(d["dice"]))
		out += _hit_p(int(a.get("to_hit", 0)), ac) * dmg
	return out


static func hero_dpr(s: GameSession, data: Dictionary, ac: int) -> float:
	var c := s.character
	var w := CombatRules.weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("main_hand", "")))
	var n := 1 + CharacterRules.extra_attacks(c, data)
	var best := n * _hit_p(int(w["to_hit"]), ac) * maxf(1.0, _avg(str(w["dice"])) + int(w["bonus"]))
	for sp: String in SpellRules.ready(c):  # an attack cantrip, when it does more than the weapon
		var d: Dictionary = data["spells"].get(sp, {})
		if int(d.get("level", 1)) == 0 and str(d.get("attack", "")) != "" and CombatRules.is_engine_spell(data, sp):
			best = maxf(best, _hit_p(int(c.get("spell_attack", 0)), ac) * _avg(CombatRules._spell_dice(d, 0, int(c.get("level", 1)))))
	return best


## The chance of a side of hp × damage-a-round `ra` against `rb` (Lanchester: who outlasts whom), 0..1.
static func chance(ra: float, rb: float) -> float:
	if ra <= 0.0 and rb <= 0.0:
		return 0.5
	return clampf(ra * ra / (ra * ra + rb * rb), 0.03, 0.97)


static func rating_monster(data: Dictionary, monster: String, foe_ac: int) -> float:
	return float(data["monsters"][monster]["hp"]) * monster_dpr(data, monster, foe_ac)


## The engine's estimate of the hero against a template: {p, house, mult} — the true chance, the house's shown one
## (off by the day's noise) and the payout of a bet on the hero.
static func hero_odds(s: GameSession, data: Dictionary, sid: String, monster: String) -> Dictionary:
	var m: Dictionary = data["monsters"][monster]
	var ra := float(s.character["hp"]) * hero_dpr(s, data, int(m["ac"]))
	var rb := rating_monster(data, monster, int(s.character.get("ac", 10)))
	return _odds(s, data, sid, "hero" + monster, chance(ra, rb))


static func _odds(s: GameSession, data: Dictionary, sid: String, salt: String, p: float) -> Dictionary:
	var b: Dictionary = cfg(data)["bet"]
	var noise := _rng(s, sid, "noise" + salt).randf_range(-1.0, 1.0) * float(b["noise_pct"]) / 100.0
	var house := clampf(p + noise, 0.05, 0.95)
	return {"p": p, "house": house, "mult": mult(data, house)}


## The payout of a won bet a coin, by the house's chance: (1 − the house's cut) / chance.
static func mult(data: Dictionary, house: float) -> float:
	var b: Dictionary = cfg(data)["bet"]
	return clampf((1.0 - float(b["house_pct"]) / 100.0) / house, 1.05, float(b["max_mult"]))


# --- enlisting and the hero's bout ------------------------------------------------------------------------------


static func here_why(s: GameSession, data: Dictionary, sid: String) -> String:
	var mgr := manager(s, data, sid)
	if mgr.is_empty() or not s.npcs_here(data["world"], s.room_id).has(mgr):
		return "распорядителя здесь нет"
	if CombatRules.active(s):
		return "идёт бой"
	return ""


static func enlist_why(s: GameSession, data: Dictionary, sid: String) -> String:
	var why := here_why(s, data, sid)
	if not why.is_empty():
		return why
	if enlisted(s, sid):
		return "вы уже в списке бойцов"
	if int(s.character["gold_cp"]) < int(cfg(data)["fee_cp"]):
		return "запись стоит %s" % Money.format(int(cfg(data)["fee_cp"]))
	return ""


static func enlist(s: GameSession, data: Dictionary, sid: String) -> Array[String]:
	var fee := int(cfg(data)["fee_cp"])
	s.character["gold_cp"] = int(s.character["gold_cp"]) - fee
	_rec_new(s, sid)
	ObjectRules.note(s, sid, "%s записался в бойцы" % s.character.get("name", ""))
	return ["%s: вы в списке бойцов (−%s), ранг — %s; правило — %s" % [site_name(data, sid), Money.format(fee), rank_name(data, 0),
		str(rule_cfg(data, sid)["name"])]]


static func bout_why(s: GameSession, data: Dictionary, sid: String) -> String:
	var why := here_why(s, data, sid)
	if not why.is_empty():
		return why
	if not enlisted(s, sid):
		return "сначала запишитесь в бойцы"
	if int(rec(s, sid).get("day", 0)) == s.day:
		return "на сегодня ваш бой уже был — завтра"
	if int(s.character["hp"]) * 2 < int(s.character["max_hp"]):
		return "распорядитель не выпустит раненого: отдохните"
	return ""


## The bout of the day: {foes, source, lines} for GameState.start_combat or {reason}. `bet_cp` — a bet on oneself.
static func bout(s: GameSession, data: Dictionary, sid: String, bet_cp: int = 0) -> Dictionary:
	var why := bout_why(s, data, sid)
	if not why.is_empty():
		return {"reason": why}
	var bw := bet_why(s, data, bet_cp)
	if bet_cp > 0 and not bw.is_empty():
		return {"reason": bw}
	var opp := opponent(s, data, sid)
	var o := hero_odds(s, data, sid, str(opp["monster"]))
	s.character["gold_cp"] = int(s.character["gold_cp"]) - bet_cp
	_rec_new(s, sid)["day"] = s.day
	var src := {"site": sid, "kind": "rank", "rule": rule(data, sid), "rank": int(opp["rank"]), "bet": bet_cp, "mult": float(o["mult"]),
		"foe": str(opp["name"])}
	return {"foes": [{"monster": str(opp["monster"]), "name": str(opp["name"])}], "source": {"arena": src, "room_from": s.room_id},
		"lines": [_opening(data, sid, str(opp["name"]), bet_cp, float(o["mult"]))]}


static func _opening(data: Dictionary, sid: String, foe: String, bet_cp: int, m: float) -> String:
	var t := "%s — бой %s: %s" % [site_name(data, sid), str(rule_cfg(data, sid)["name"]), foe]
	if bet_cp > 0:
		t += "; ставка на себя %s ×%.2f" % [Money.format(bet_cp), m]
	return t


static func bet_why(s: GameSession, data: Dictionary, cp: int) -> String:
	var b: Dictionary = cfg(data)["bet"]
	if cp < int(b["min_cp"]):
		return "ставка — от %s" % Money.format(int(b["min_cp"]))
	if cp > max_bet(s, data):
		return "ставка — не больше %s" % Money.format(max_bet(s, data))
	if cp > int(s.character["gold_cp"]):
		return "у героя нет %s" % Money.format(cp)
	return ""


static func max_bet(s: GameSession, data: Dictionary) -> int:
	return int(cfg(data)["bet"]["max_cp_level"]) * int(s.character.get("level", 1))


## Whether a fight is a bout where nobody dies: the arena's «yield» rule or a duel.
static func yield_bout(s: GameSession) -> bool:
	var a: Dictionary = s.combat.get("arena", {})
	return not a.is_empty() and str(a.get("rule", "yield")) == "yield"


## The end of a bout (GameState.finish_combat): the prize, the bet, the rank and the fame, or the tournament's step,
## or the duel's stake. Lines.
static func after_bout(s: GameSession, data: Dictionary, a: Dictionary, won: bool) -> Array[String]:
	match str(a.get("kind", "rank")):
		"duel":
			return ContestRules.settle(s, data, won)
		"tourney":
			return _tourney_after(s, data, a, won)
	var sid := str(a["site"])
	var r := _rec_new(s, sid)
	var rc := rule_cfg(data, sid)
	var lines: Array[String] = []
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	var fame: Dictionary = cfg(data)["fame"]
	if not won:
		r["losses"] = int(r.get("losses", 0)) + 1
		lines.append("Поражение на арене: %s" % a.get("foe", ""))
		if int(a.get("bet", 0)) > 0:
			lines.append("Ставка на себя проиграна: −%s" % Money.format(int(a["bet"])))
		ObjectRules.note(s, sid, "%s проиграл бой: %s" % [s.character.get("name", ""), a.get("foe", "")])
		return lines
	var i := int(a.get("rank", 0))
	var prize := int(int(ranks(data)[i]["prize_cp"]) * int(rc.get("prize_pct", 100)) / 100)
	s.character["gold_cp"] = int(s.character["gold_cp"]) + prize
	lines.append("Победа на арене: приз %s" % Money.format(prize))
	if int(a.get("bet", 0)) > 0:
		var pay := roundi(int(a["bet"]) * float(a.get("mult", 1.0)))
		s.character["gold_cp"] = int(s.character["gold_cp"]) + pay
		lines.append("Ставка на себя: +%s" % Money.format(pay))
	r["wins"] = int(r.get("wins", 0)) + 1
	r["rank_wins"] = int(r.get("rank_wins", 0)) + 1
	var pts := int(int(fame["win"]) * int(rc.get("fame_pct", 100)) / 100)
	var need := int(ranks(data)[i].get("wins", 0))
	if need > 0 and int(r["rank_wins"]) >= need and int(r["rank"]) < ranks(data).size() - 1:
		r["rank"] = int(r["rank"]) + 1
		r["rank_wins"] = 0
		pts += int(fame["rank_up"])
		lines.append("Новый ранг на арене: %s" % rank_name(data, int(r["rank"])))
	lines.append_array(ReputationRules.add(s, data, loc, pts, "победы на арене"))
	ObjectRules.note(s, sid, "%s победил: %s" % [s.character.get("name", ""), a.get("foe", "")])
	return lines


# --- bets on the bouts of others ----------------------------------------------------------------------------------


## The day's card of an arena: two fighters of one rank {a, b: {monster, name}, rank, p (a wins), house, mult_a, mult_b}.
static func card(s: GameSession, data: Dictionary, sid: String) -> Dictionary:
	var r := _rng(s, sid, "card")
	var list: Array = cfg(data)["card_ranks"]
	var i := clampi(int(list[r.randi_range(0, list.size() - 1)]), 0, ranks(data).size() - 1)
	var foes: Array = ranks(data)[i]["foes"]
	var ma := str(foes[r.randi_range(0, foes.size() - 1)])
	var mb := str(foes[r.randi_range(0, foes.size() - 1)])
	var na := _nick(data, r)
	var nb := _nick(data, r)
	while nb == na:
		nb = _nick(data, r)
	var ra := rating_monster(data, ma, int(data["monsters"][mb]["ac"]))
	var rb := rating_monster(data, mb, int(data["monsters"][ma]["ac"]))
	var o := _odds(s, data, sid, "card", chance(ra, rb))
	return {"a": {"monster": ma, "name": fighter_name(data, ma, na)}, "b": {"monster": mb, "name": fighter_name(data, mb, nb)}, "rank": i,
		"p": float(o["p"]), "house": float(o["house"]), "mult_a": mult(data, float(o["house"])), "mult_b": mult(data, 1.0 - float(o["house"]))}


static func card_why(s: GameSession, data: Dictionary, sid: String) -> String:
	var why := here_why(s, data, sid)
	if not why.is_empty():
		return why
	if int(s.character.get("arena_bets", {}).get(sid, 0)) == s.day:
		return "на сегодняшний бой вы уже ставили"
	return ""


## The hero knows the fighters today (Insight): the true estimate is shown beside the house's.
static func knows(s: GameSession, sid: String) -> bool:
	var k: Dictionary = s.character.get("arena_insight", {}).get(sid, {})
	return int(k.get("day", 0)) == s.day and bool(k.get("ok", false))


static func insight_why(s: GameSession, data: Dictionary, sid: String) -> String:
	var why := here_why(s, data, sid)
	if not why.is_empty():
		return why
	if int(s.character.get("arena_insight", {}).get(sid, {}).get("day", 0)) == s.day:
		return "сегодня вы уже присматривались"
	return ""


static func insight_params(data: Dictionary) -> Dictionary:
	var c: Dictionary = cfg(data)["insight"]
	return {"skill": str(c["skill"]), "dc": int(c["dc"]), "dc_tier": "medium"}


static func set_insight(s: GameSession, data: Dictionary, sid: String, ok: bool) -> Array[String]:
	var all: Dictionary = s.character.get("arena_insight", {})
	all[sid] = {"day": s.day, "ok": ok}
	s.character["arena_insight"] = all
	if not ok:
		return ["Вы присматриваетесь к бойцам, но ничего нового не видите"]
	var c := card(s, data, sid)
	return ["Вы видите бойцов насквозь: %s победит с шансом около %d%% (у распорядителя — %d%%)" % [c["a"]["name"], roundi(float(c["p"]) * 100),
		roundi(float(c["house"]) * 100)]]


## A bet on a side ("a" / "b") of the day's card: the engine plays the bout out at once. {lines} or {reason}.
static func bet(s: GameSession, data: Dictionary, sid: String, side: String, cp: int) -> Dictionary:
	var why := card_why(s, data, sid)
	if why.is_empty():
		why = bet_why(s, data, cp)
	if not why.is_empty():
		return {"reason": why}
	var c := card(s, data, sid)
	s.character["gold_cp"] = int(s.character["gold_cp"]) - cp
	var bets: Dictionary = s.character.get("arena_bets", {})
	bets[sid] = s.day
	s.character["arena_bets"] = bets
	var sim := simulate(data, s.rng, str(c["a"]["monster"]), str(c["b"]["monster"]), rule(data, sid))
	var lines: Array[String] = ["Ставка %s на %s" % [Money.format(cp), c[side]["name"]]]
	var names := {"a": str(c["a"]["name"]), "b": str(c["b"]["name"])}
	for l: String in sim["lines"]:
		lines.append(l.replace("{a}", names["a"]).replace("{b}", names["b"]))
	if str(sim["winner"]) == side:
		var pay := roundi(cp * float(c["mult_" + side]))
		s.character["gold_cp"] = int(s.character["gold_cp"]) + pay
		lines.append("Ставка сыграла: +%s" % Money.format(pay))
	else:
		lines.append("Ставка проиграна: −%s" % Money.format(cp))
	ObjectRules.note(s, sid, "бой %s против %s — победил %s" % [names["a"], names["b"], names[str(sim["winner"])]])
	return {"lines": lines, "winner": str(sim["winner"])}


## A bout of two templates played out by the engine: initiative by DEX, each turn the full melee attack of the
## combat AI against the other's AC, crits double the dice; «yield» — a side at `yield_hp_pct` gives up.
## {winner: "a" | "b", rounds, lines} with {a} / {b} for the names.
static func simulate(data: Dictionary, rng: RandomNumberGenerator, ma: String, mb: String, rule_id: String) -> Dictionary:
	var ms := {"a": data["monsters"][ma], "b": data["monsters"][mb]}
	var hp := {"a": int(ms["a"]["hp"]), "b": int(ms["b"]["hp"])}
	var max_rounds := int(cfg(data)["sim_rounds"])
	var yield_pct := int(cfg(data)["yield_hp_pct"])
	var ia := rng.randi_range(1, 20) + CharacterRules.mod(int(ms["a"]["abilities"].get("dex", 10)))
	var ib := rng.randi_range(1, 20) + CharacterRules.mod(int(ms["b"]["abilities"].get("dex", 10)))
	var order := ["a", "b"] if ia >= ib else ["b", "a"]
	var dealt := {"a": 0, "b": 0}
	for rnd in range(1, max_rounds + 1):
		for who: String in order:
			var foe := "b" if who == "a" else "a"
			for a: Dictionary in attacks(data, ma if who == "a" else mb):
				var nat := rng.randi_range(1, 20)
				if nat == 1 or (nat != 20 and nat + int(a.get("to_hit", 0)) < int(ms[foe]["ac"])):
					continue
				var dmg := 0
				for d: Dictionary in a["damage"]:
					dmg += CombatRules.roll_dice(rng, str(d["dice"]), nat == 20)
				hp[foe] = maxi(0, int(hp[foe]) - dmg)
				dealt[who] = int(dealt[who]) + dmg
				if int(hp[foe]) == 0:
					var end := "{%s} падает" % foe + (" замертво" if rule_id == "death" else " без чувств")
					return {"winner": who, "rounds": rnd, "lines": ["Бой {a} против {b}: %d раунд(ов) — %s" % [rnd, end]]}
			if rule_id == "yield" and int(hp[foe]) * 100 <= int(ms[foe]["hp"]) * yield_pct:
				return {"winner": who, "rounds": rnd, "lines": ["Бой {a} против {b}: %d раунд(ов) — {%s} сдаётся" % [rnd, foe]]}
	var w := "a" if float(hp["a"]) / int(ms["a"]["hp"]) >= float(hp["b"]) / int(ms["b"]["hp"]) else "b"
	return {"winner": w, "rounds": max_rounds, "lines": ["Бой {a} против {b}: время вышло — по очкам за {%s}" % w]}


# --- the festival's tournament ------------------------------------------------------------------------------------


## The tournament of a festival going today at `sid`: {fest, name, bouts, prize_cp, prize_item} or {}.
static func tournament(s: GameSession, data: Dictionary, sid: String) -> Dictionary:
	for fid: String in CalendarRules.active(s, data["world"]):
		var f: Dictionary = CalendarRules.cal(data["world"]).get("festivals", {}).get(fid, {})
		var t: Variant = f.get("tournament", null)
		if t is Dictionary and str((t as Dictionary).get("site", "")) == sid:
			var out: Dictionary = (t as Dictionary).duplicate()
			out["fest"] = fid
			out["name"] = str(f.get("name", fid))
			return out
	return {}


static func tourney_state(s: GameSession, sid: String) -> Dictionary:
	var t: Dictionary = s.character.get("tourney", {})
	return t if int(t.get("day", 0)) == s.day and str(t.get("site", "")) == sid else {}


static func tourney_why(s: GameSession, data: Dictionary, sid: String) -> String:
	var why := here_why(s, data, sid)
	if not why.is_empty():
		return why
	var t := tournament(s, data, sid)
	if t.is_empty():
		return "турнира сегодня нет"
	var st := tourney_state(s, sid)
	if bool(st.get("out", false)):
		return "вы выбыли из турнира"
	if bool(st.get("done", false)):
		return "турнир вы уже выиграли"
	if int(s.character["hp"]) * 4 < int(s.character["max_hp"]):
		return "распорядитель не выпустит раненого"
	return ""


## The tournament's next bout: rising ranks bout by bout. {foes, source, lines} or {reason}.
static func tourney_bout(s: GameSession, data: Dictionary, sid: String) -> Dictionary:
	var why := tourney_why(s, data, sid)
	if not why.is_empty():
		return {"reason": why}
	var t := tournament(s, data, sid)
	var st := tourney_state(s, sid)
	if st.is_empty():
		st = {"fest": str(t["fest"]), "day": s.day, "site": sid, "round": 0}
		s.character["tourney"] = st
	var n := int(st["round"])
	var opp := opponent(s, data, sid, mini(n + int(t.get("from_rank", 0)), ranks(data).size() - 1))
	var src := {"site": sid, "kind": "tourney", "rule": rule(data, sid), "rank": int(opp["rank"]), "foe": str(opp["name"]), "round": n + 1,
		"bouts": int(t.get("bouts", 3))}
	return {"foes": [{"monster": str(opp["monster"]), "name": str(opp["name"])}], "source": {"arena": src, "room_from": s.room_id},
		"lines": ["%s — бой %d из %d: %s" % [t["name"], n + 1, int(t.get("bouts", 3)), opp["name"]]]}


static func _tourney_after(s: GameSession, data: Dictionary, a: Dictionary, won: bool) -> Array[String]:
	var sid := str(a["site"])
	var st: Dictionary = s.character.get("tourney", {})
	var t := tournament(s, data, sid)
	var lines: Array[String] = []
	if not won:
		st["out"] = true
		lines.append("Вы выбыли из турнира в %d-м бою" % int(a.get("round", 1)))
		return lines
	st["round"] = int(st.get("round", 0)) + 1
	if int(st["round"]) < int(a.get("bouts", 3)):
		lines.append("Турнир: победа в %d-м бою из %d" % [int(st["round"]), int(a.get("bouts", 3))])
		return lines
	st["done"] = true
	var cp := int(t.get("prize_cp", 0))
	s.character["gold_cp"] = int(s.character["gold_cp"]) + cp
	lines.append("Победитель турнира «%s»! Приз %s" % [t.get("name", ""), Money.format(cp)])
	var item := str(t.get("prize_item", ""))
	if not item.is_empty() and data["items"]["catalog"].has(item):
		var inv: Dictionary = s.character["inventory"]  # the prize is named: no identifying
		inv[item] = int(inv.get(item, 0)) + 1
		lines.append("Награда чемпиона: %s" % ItemRules.display_name(data["items"], s.items, item))
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	lines.append_array(ReputationRules.add(s, data, loc, int(cfg(data)["fame"]["champion"]), "чемпион турнира"))
	ObjectRules.note(s, sid, "%s — чемпион турнира «%s»" % [s.character.get("name", ""), t.get("name", "")])
	return lines


# --- for the master -----------------------------------------------------------------------------------------------


## The arena of the object the hero stands in, for the master: «арена: до сдачи; герой — Боец, побед 3».
static func text(s: GameSession, data: Dictionary, sid: String) -> String:
	if not on(data) or arena(data, sid).is_empty():
		return ""
	var t := "арена — бой %s" % str(rule_cfg(data, sid)["name"])
	if enlisted(s, sid):
		var r := rec(s, sid)
		t += "; герой в бойцах: %s, побед %d, поражений %d" % [rank_name(data, int(r["rank"])), int(r.get("wins", 0)), int(r.get("losses", 0))]
		if bout_why(s, data, sid).is_empty() or int(rec(s, sid).get("day", 0)) != s.day:
			t += "; соперник героя сегодня — %s" % opponent(s, data, sid)["name"]
	var c := card(s, data, sid)
	t += "; бой дня для ставок — %s против %s (ставки — в книге распорядителя, окно «Арена»)" % [c["a"]["name"], c["b"]["name"]]
	var tour := tournament(s, data, sid)
	if not tour.is_empty():
		t += "; сегодня турнир «%s»" % tour["name"]
	return t
