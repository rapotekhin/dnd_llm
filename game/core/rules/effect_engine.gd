class_name EffectEngine
extends RefCounted
## engine.validate and the turn transaction (ADR-0008 §3–4, ADR-0009 §5): a proposed effect is checked
## against the state and the budgets, then *reserved* under the turn; the world changes only when
## turn.result lists its id. Unlisted reserves, errors, cancels and drops burn every reserve of the turn.
##
## `data` = {"rules": rules.json, "items": items.json, "world": world.json}.

## effect_id -> {"turn_id", "kind", "plan": what apply() does, "summary"}
var reserves: Dictionary = {}
## turn_id -> true once the master searched items this turn (required before creating one).
var searched: Dictionary = {}
## turn_id -> true once the master searched the world's people this turn (v0.7.20: before create:npc).
var searched_npcs: Dictionary = {}
## turn_id -> true once the master searched the world's quests this turn (v0.7.21: before create:quest).
var searched_quests: Dictionary = {}
## turn_id -> true once the master searched the world's places this turn (v0.7.20.1: before create:place).
var searched_places: Dictionary = {}
## Catalog.data of the last validate: apply() needs the rules of casts, feature uses and items.
var _data: Dictionary = {}
## The table of effects, built once (_build_table).
var _rows: Dictionary = {}


## Lines an applied effect adds after its summary (the owner of a taken thing reacts, v0.7.0).
var _extra_lines: Array[String] = []
## What this apply made: {"rooms": {key: id}, "site": id, "npc": id} — for the refs «new:<key>» (v0.7.22.25.1).
var _made: Dictionary = {}
## The tiers of successful checks of each turn (v0.7.14.3): a nearly_impossible one caps the turn's rewards.
var _won: Dictionary = {}
## NPCs won over this turn by a successful Persuasion, Deception or Intimidation (v0.7.15.2): turn_id → [npc_id].
var _won_over: Dictionary = {}
## The checks of each turn (v0.7.18.1): turn_id → [{skill, total, success}] — a lock opened by words needs one.
var _rolls: Dictionary = {}
## Turns started by the player's own words or ability (v0.7.8): only there a condition may come without a save
## (`cause: player` — the hero drank it, lay down to sleep). turn_id → true; GameState marks them.
var player_turns: Dictionary = {}

func mark_searched(turn_id: String) -> void:
	searched[turn_id] = true


## Drops every reserve (and the search mark) of `turn_id`.
func discard(turn_id: String) -> void:
	_won.erase(turn_id)
	searched_npcs.erase(turn_id)
	searched_quests.erase(turn_id)
	searched_places.erase(turn_id)
	_rolls.erase(turn_id)
	_won_over.erase(turn_id)
	for id: String in reserves.keys():
		if reserves[id]["turn_id"] == turn_id:
			reserves.erase(id)
	searched.erase(turn_id)
	player_turns.erase(turn_id)


func _of_turn(turn_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in reserves:
		if reserves[id]["turn_id"] == turn_id:
			out.append(reserves[id])
	return out


## Returns the engine.validate result: {accepted, effect_id, summary, item_id} or {accepted: false, reason}.
## A check of the turn resolved (GameState): a success on nearly_impossible caps what the master may give this turn.
## A check of the turn and its total (v0.7.18.1): the effect `unlock` by words needs a passed one.
func note_roll(turn_id: String, skill: String, total: int, success: bool) -> void:
	var list: Array = _rolls.get(turn_id, [])
	list.append({"skill": skill, "total": total, "success": success})
	_rolls[turn_id] = list


## `npc_id` — the NPC of a social check (v0.7.15.2): a success wins it over for this turn's discount or favor.
func note_check(turn_id: String, dc_tier: String, success: bool, npc_id: String = "") -> void:
	if success:
		var tiers: Array = _won.get(turn_id, [])
		tiers.append(dc_tier)
		_won[turn_id] = tiers
		if not npc_id.is_empty():
			var who: Array = _won_over.get(turn_id, [])
			who.append(npc_id)
			_won_over[turn_id] = who


## What the master may still give (cp) this turn: the budget of the level until the long rest, minus what it gave
## and what this turn already holds; a quarter of it after a nearly impossible success.
func reward_left(s: GameSession, data: Dictionary, turn_id: String, pending: Array[Dictionary]) -> int:
	var left := budget_left(s, data)
	for p: Dictionary in pending:
		left -= int(p["plan"].get("reward", 0))
	if (_won.get(turn_id, []) as Array).has("nearly_impossible"):
		left = int(left * float(data["rules"]["reward_budget"]["impossible_share"]))
	return maxi(0, left)


static func budget_left(s: GameSession, data: Dictionary) -> int:
	var per: Dictionary = data["rules"]["reward_budget"]["per_rest_cp"]
	var level := clampi(int(s.character.get("level", 1)), 1, per.size())
	return maxi(0, int(per[str(level)]) - s.reward_spent)


func validate(s: GameSession, data: Dictionary, turn_id: String, effect: Dictionary) -> Dictionary:
	_data = data
	var rules: Dictionary = data["rules"]
	var pending := _of_turn(turn_id)
	if pending.size() >= int(rules["turn_limits"]["max_effects"]):
		return _reject("лимит эффектов на ход исчерпан")
	var res := _plan(s, data, turn_id, effect, pending)
	if res.has("reason"):
		return _reject(str(res["reason"]))
	var id := s.next_effect_id()
	reserves[id] = {"turn_id": turn_id, "kind": key(effect), "plan": res["plan"], "summary": res["summary"],
		"line": str(res.get("line", res["summary"]))}  # the player's line may say less than the master's summary (v0.7.49.4)
	var out := {"accepted": true, "effect_id": id, "summary": res["summary"]}
	if res["plan"].has("new_item_id"):
		out["item_id"] = res["plan"]["new_item_id"]
	return out


## Applies the listed reserves of `turn_id` in order, burns the rest. Returns the summaries shown to the player.
func apply(s: GameSession, turn_id: String, ids: Array) -> Array[String]:
	var lines: Array[String] = []
	_made = {}
	for id: Variant in _ordered(ids):
		var r: Dictionary = reserves.get(str(id), {})
		if r.is_empty() or r["turn_id"] != turn_id:
			continue
		_extra_lines.clear()
		s.reward_spent += int(r["plan"].get("reward", 0))  # the master's gift counts against the budget (v0.7.14.3)
		if bool(r["plan"].get("magic", false)):
			s.magic_given += 1
		_apply_one(s, r["kind"], r["plan"])
		lines.append(str(r.get("line", r["summary"])))
		lines.append_array(_extra_lines)  # an owner's reaction to a taken thing (v0.7.0)
	discard(turn_id)
	_link_new_owner(s)
	return lines


func _reject(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}


## `new:<key>` of this turn's `make` stands for its id wherever a thing is named (v0.7.63).
func _made_ids(e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var out := e.duplicate()
	for k: String in ["condition", "teach_id", "item_id", "reward_item_id"]:
		if out.get(k) is String:
			out[k] = MakeRules.resolve(pending, out[k])
	return out


## The effects, one row each (v0.7.69): the key is `key()`; `rule` checks it in its system (s, data, e), `plan` here
## (s, data, turn_id, e, pending), both give {plan, summary} or {reason}; `apply` applies it there (s, data, plan) and may give
## lines, `do` here (s, plan). `one`: the refusal when the turn already has one. `no_fight`, `no_trade`: the engine runs
## those by its buttons.
func _table() -> Dictionary:
	if not _rows.is_empty():
		return _rows
	_rows = {
		"move": {"plan": _plan_move, "do": _do_move, "no_fight": true},
		"damage": {"plan": _plan_damage, "do": _do_damage},
		"heal": {"plan": _plan_heal, "do": _do_heal},
		"coins": {"plan": _plan_coins, "do": _do_coins, "no_fight": true, "no_trade": true},
		"move_item:world>hero": {"plan": _plan_give_item, "do": _do_give_item, "no_fight": true, "no_trade": true},
		"move_item:hero>world": {"plan": _plan_take_item, "do": _do_take_item, "no_fight": true, "no_trade": true},
		"move_item:room>hero": {"rule": PropRules.plan_take, "apply": PropRules.apply_take, "no_fight": true},
		"move_item:container>hero": {"plan": _plan_take_from, "apply": ContainerRules.apply_take},
		"move_item:hero>container": {"plan": _plan_put_in, "apply": ContainerRules.apply_put},
		"move_item:hero>room": {"plan": _plan_drop_item, "apply": ContainerRules.apply_drop},
		"cast": {"plan": _plan_cast, "do": _do_cast},
		"use:feature": {"plan": _plan_use_feature, "do": _do_use_feature},
		"use:item": {"plan": _plan_use_item, "do": _do_use_item},
		"condition": {"plan": _plan_condition, "do": _do_condition},
		"disease": {"plan": _plan_disease, "do": _do_disease},
		"guise": {"plan": _plan_guise, "apply": Guise.apply},
		"make": {"plan": _plan_make, "apply": MakeRules.apply},
		"furnish": {"plan": _plan_furnish, "do": _do_furnish, "one": "комната уже обставляется в этом ходе", "no_fight": true},
		"prop_state": {"rule": PropRules.plan_state, "apply": PropRules.apply_state},
		"note": {"plan": _plan_note, "do": _do_note},
		"flag": {"plan": _plan_flag, "do": _do_flag},
		"equip": {"rule": _plan_equip, "do": _do_equip},
		"fill": {"plan": _plan_fill, "do": _do_fill},
		"start_combat": {"plan": _plan_start_combat, "do": _do_start_combat},
		"advance_time": {"plan": _plan_advance_time, "do": _do_advance_time, "no_fight": true},
		"rumor": {"plan": _plan_rumor, "apply": RumorRules.apply},
		"weather": {"rule": WeatherRules.plan, "apply": WeatherRules.apply},
		"letter_reply": {"plan": _plan_letter_reply, "apply": LetterRules.apply},
		"vow": {"rule": FaithRules.plan_vow, "apply": FaithRules.apply_vow},
		"owner": {"plan": _plan_owner, "apply": OwnerRules.apply, "one": "одна смена хозяина за ход"},
		"quest_act": {"plan": _plan_quest_act, "apply": QuestGen.apply_act, "one": "один акт за ход"},
		"shift:attitude": {"plan": _plan_npc_attitude, "do": _do_npc_attitude, "no_fight": true},
		"shift:reputation": {"plan": _plan_reputation, "do": _do_reputation},
		"shift:bond": {"plan": _plan_bond, "do": _do_bond},
		"grant:discount": {"plan": _plan_grant, "apply": SocialRules.grant_discount},
		"grant:favor": {"plan": _plan_grant, "apply": SocialRules.grant_favor},
		"grant:permit": {"rule": SiteRules.make, "do": _do_permit},
		"grant:secret": {"plan": _plan_reveal_secret, "do": _do_secret},
		"grant:follow": {"plan": _plan_npc_follow, "do": _do_follow},
		"grant:quest": {"plan": _plan_accept_quest, "do": _do_quest},
		"crime:known": {"plan": _plan_crime_known, "do": _do_crime_known},
		"crime:release": {"plan": _plan_crime_release, "do": _do_crime_release},
		"goal:assess": {"plan": _plan_goal_assess, "do": _do_goal_assess},
		"goal:hint": {"plan": _plan_goal_hint, "do": _do_goal_hint, "one": "один намёк за ход"},
		"open:container": {"plan": _plan_unlock, "do": _do_unlock},
		"open:door": {"plan": _plan_door, "do": _do_door},
		"create:npc": {"plan": _plan_create_npc, "do": _do_create_npc, "one": "один новый человек за ход"},
		"create:place": {"plan": _plan_create_place, "do": _do_create_place, "one": "одно новое место за ход"},
		"create:quest": {"plan": _plan_create_quest, "do": _do_create_quest, "one": "одно новое задание за ход"},
		"create:recipe": {"plan": _plan_recipe, "apply": CraftRules.apply_make},
		"create:job": {"plan": _plan_job, "apply": JobRules.apply_make},
		"create:course": {"plan": _plan_course, "apply": StudyRules.apply_make},
		"create:way": {"rule": WayRules.plan_make, "apply": WayRules.apply_make},
		"create:supplier": {"rule": ShopRules.make, "apply": ShopRules.apply_make},
		"create:bank": {"rule": BankRules.make, "do": _do_bank},
		"create:fence": {"rule": FenceRules.make, "apply": FenceRules.apply_make},
		"create:heist": {"rule": HeistRules.make, "apply": HeistRules.apply_make},
		"create:org": {"rule": OrgRules.make, "apply": OrgRules.apply_make},
		"create:god": {"rule": FaithRules.plan_god, "apply": FaithRules.apply_god},
		"create:festival": {"rule": CalendarRules.plan_festival, "apply": CalendarRules.apply_festival},
		"create:beast": {"plan": _plan_beast, "apply": PetRules.apply_beast},
		"create:property": {"plan": _plan_property, "do": _do_property},
		"create:upgrade": {"plan": _plan_upgrade, "apply": PropertyRules.apply_asked, "one": "одно новое улучшение за ход"},
		"create:stock": {"plan": _plan_stock, "do": _do_stock},
		"create:wilds": {"plan": _plan_wilds, "apply": WildsRules.apply},
		"create:contest": {"plan": _plan_contest, "apply": ContestRules.apply},
		"create:faction": {"rule": FactionRules.make, "apply": FactionRules.apply_make},
		"shift:standing": {"rule": FactionRules.make, "apply": FactionRules.apply_make},
		"move_item:world>npc": {"rule": WorldItemRules.plan, "apply": WorldItemRules.apply},
		"move_item:npc>world": {"rule": WorldItemRules.plan, "apply": WorldItemRules.apply},
		"move_item:world>container": {"rule": WorldItemRules.plan, "apply": WorldItemRules.apply},
		"move_item:container>world": {"rule": WorldItemRules.plan, "apply": WorldItemRules.apply},
	}
	return _rows


## The one name of an effect: `create:npc`, `move_item:world>hero`, `coins`.
static func key(e: Dictionary) -> String:
	var kind := str(e.get("kind", ""))
	if kind == "move_item":
		return "move_item:%s>%s" % [e.get("source", ""), e.get("target", "")]
	var what: Variant = e.get("what")
	return "%s:%s" % [kind, what] if what != null and not str(what).is_empty() and kind != "make" else kind


func _plan(s: GameSession, data: Dictionary, turn_id: String, raw: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var e := _made_ids(raw, pending)
	for k: String in ["condition", "teach_id", "item_id", "reward_item_id"]:
		if str(e.get(k, "")).begins_with("new:") and (k in ["condition", "teach_id"] or str(e[k]).begins_with("new:book:") or str(e[k]).begins_with("new:scroll:")):
			return {"reason": "%s: этого ещё не собрали — сначала эффект make с таким key в этом же ходе" % e[k]}
	var world := WorldView.new(data["world"])
	var id := key(e)
	var row: Dictionary = _table().get(id, {})
	if row.is_empty():
		return {"reason": "движок не знает эффект %s" % id}
	if s.mode == GameSession.MODE_COMBAT:
		if bool(row.get("no_fight", false)):
			return {"reason": "в бою это нельзя: исход боя, переходы и добычу ведёт движок; здесь — проверки, урон и состояния врагам (target_id), подкрепление (start_combat)"}
		var tid := str(e.get("target_id", "")) if e.get("target_id") != null else ""
		if not tid.is_empty():
			return _plan_on_foe(s, data, e, tid)
	elif id in ["damage", "condition"] and e.get("target_id") != null and not str(e.get("target_id", "")).is_empty():
		# v0.7.22.16 (the author's trace): out of a fight a blow at an NPC is a fight, not an effect — the damage went to the hero
		return {"reason": "вне боя урон и состояния NPC эффектом не проводятся: нападение на NPC сцены — next_mode combat с его npc_id, исход решит бой"}
	if s.mode == GameSession.MODE_TRADE and bool(row.get("no_trade", false)):
		return {"reason": "в торговле сделки проводит панель сделки: назови цену и предложи игроку положить товар в сделку"}
	if s.mode == GameSession.MODE_SOCIAL and id == "move_item:world>hero" and world.is_trader(s.npc_id) and TradeRules.pack_stock(world.npc(s.npc_id), data["rules"]).has(str(e.get("item_id", ""))):
		return {"reason": "это товар торговца — покупка идёт через торговлю: назови цену и открой её (next_mode trade); монеты не списывай"}
	if row.has("one") and pending.any(func(p: Dictionary) -> bool: return p["kind"] == id):
		return {"reason": str(row["one"])}
	if row.has("rule"):
		return (row["rule"] as Callable).call(s, data, e)
	return (row["plan"] as Callable).call(s, data, turn_id, e, pending)


func _plan_move(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var world := WorldView.new(data["world"])
	var c := s.character
	var to := str(e.get("room_id", ""))
	if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "move"):
		return {"reason": "переход уже предложен в этом ходе"}
	if EncounterRules.captive(s):  # v0.7.22.12: bound by the captors
		return {"reason": "герой связан и в плену — уйти нельзя, пока не освободится (кнопки игрока)"}
	if CrimeRules.held(s):  # big test #5 (v0.7.22.2): the guard leads the hero — anywhere in the location
		if world.location_id(to) != world.location_id(s.room_id) or world.room(to).is_empty():
			return {"reason": "стража держит героя: увести его можно только в комнату этой же округи (%s) — к капитану, в караулку; сам он не уйдёт" % world.location_id(s.room_id)}
		return {"plan": {"room_id": to, "with": [], "escort": true}, "summary": "Под стражей: %s" % world.room(to).get("name", to)}
	if not to.begins_with("new:") and world.room(to).is_empty() and _new_rooms(s, data, pending).has(to):
		to = "new:" + to
	if to.begins_with("new:"):  # into the place made in this turn at this room: only its first room
		var place := _new_place(pending)
		if place.is_empty() or str(place["from"]) != s.room_id or str(place["rooms"][0]["key"]) != to.trim_prefix("new:"):
			return {"reason": "войти можно только в первую комнату места, созданного в этом ходе у этой комнаты (new:<её key>)"}
		return {"plan": {"room_id": to, "with": []}, "summary": "Переход: %s" % place["rooms"][0]["name"]}
	if not WayRules.open_exits(s, data["world"], s.room_id).has(to):
		return {"reason": "из этой комнаты нет выхода в %s" % to}
	# v0.7.22.16: the master's move is checked as the exit button — the overload, a trap the hero found
	if CharacterRules.overloaded(c, data, s.items):
		return {"reason": "герой перегружен и не может идти — сначала оставить лишнее (move_item:hero>room)"}
	var trap := ExplorationRules.trap_on_exit(s, data["world"], s.room_id, to)
	if not trap.is_empty() and ExplorationRules.is_found(s, s.room_id, trap):
		return {"reason": "путь стережёт найденная ловушка — её обезвреживают или обходят (кнопки игрока), просто пройти нельзя"}
	if not WayRules.blocked(s, data, s.room_id, to).is_empty():  # v0.7.22.25
		return {"reason": "%s — пройти нельзя: открыть её — кнопки игрока (ключ, отмычки, сила, заклинание) или эффект door, если её отпирает хозяин" % WayRules.describe(s, data, s.room_id, to)}
	var with: Array = []  # NPCs who go along (v0.7.20.4): the same engine rule as grant:follow
	for n: Variant in e.get("npcs", []) if e.get("npcs") is Array else []:
		var nid := str(n)
		if Being.follows(s, nid) or with.has(nid) or pending.any(func(p: Dictionary) -> bool: return str(p["plan"].get("follow_npc", "")) == nid):
			continue
		var f := FollowRules.plan(s, data, nid, true, false, (_won_over.get(turn_id, []) as Array).has(nid))
		if f.has("reason"):
			return {"reason": "%s; без него — move без npcs" % f["reason"]}
		with.append(nid)
	var names := ", ".join(with.map(func(n: String) -> String: return str(world.npc(n).get("name", n))))
	return {"plan": {"room_id": to, "with": with},
		"summary": "Переход: %s%s" % [world.room(to).get("name", to), (" (с героем: %s)" % names) if not with.is_empty() else ""]}


func _plan_damage(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var c := s.character
	var level := int(c.get("level", 1))
	var dice := _damage_dice(rules, level, str(e.get("severity", "")))
	if dice.is_empty():
		return {"reason": "неизвестная тяжесть урона"}
	var amount := _roll(s.rng, int(dice[0]), int(dice[1]), 0)
	var dtype := HeroDefense.damage_type(data, str(e.get("damage_type", "")))
	var adj := HeroDefense.adjust(s, data, dtype, amount)  # v0.7.8: the hero's resistances
	var note := str(adj["note"])
	return {"plan": {"amount": int(adj["damage"])}, "summary": "−%d HP (%s%s)" % [int(adj["damage"]),
		data["misc"]["damage_types"].get(dtype, e.get("damage_type", "урон")), (", " + note) if not note.is_empty() else ""]}


func _plan_heal(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var c := s.character
	var h: Array = rules["heal_dice"].get(str(e.get("tier", "")), [])
	if h.is_empty():
		return {"reason": "неизвестная сила лечения"}
	if int(c["hp"]) >= int(c["max_hp"]):
		return {"reason": "персонаж и так здоров"}
	var amount := _roll(s.rng, int(h[0]), int(h[1]), int(h[2]))
	return {"plan": {"amount": amount}, "summary": "+%d HP" % amount}


func _plan_coins(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var c := s.character
	var level := int(c.get("level", 1))
	var delta := int(e.get("delta_cp", 0))
	if delta == 0:
		return {"reason": "пустое изменение монет"}
	var gold := int(c["gold_cp"]) + _pending_coins(pending)
	if delta < 0 and gold + delta < 0:
		return {"reason": "у персонажа нет %s (есть %s)" % [Money.format(-delta), Money.format(gold)]}
	if delta > _reward_cap(rules, level):
		return {"reason": "награда больше бюджета для %d уровня (до %s)" % [level, Money.format(_reward_cap(rules, level))]}
	if delta > 0 and delta > reward_left(s, data, turn_id, pending):
		return {"reason": _over_budget(s, data, turn_id, pending)}
	if str(e.get("settles", "")) == "tax":  # the tax debt paid by words (v0.7.39)
		var debt := PropertyRules.tax_debt(s)
		if delta > 0 or debt <= 0:
			return {"reason": "у героя нет долга по налогу" if debt <= 0 else "уплата налога — монеты с минусом"}
		if -delta > debt:
			return {"reason": "долг по налогу всего %s" % Money.format(debt)}
		if PropertyRules.registry_here(s, data).is_empty() and PropertyRules.here(s, data).is_empty():
			return {"reason": "налог принимает писарь ратуши или его платят на месте"}
		return {"plan": {"delta": delta, "reward": 0, "settles": "tax"}, "summary": "налог −" + Money.format(-delta)}
	return {"plan": {"delta": delta, "reward": maxi(0, delta)}, "summary": ("+" if delta > 0 else "") + Money.format(delta)}


func _plan_give_item(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var items: Dictionary = data["items"]
	var c := s.character
	var level := int(c.get("level", 1))
	var given := _plan_quest_give(s, data, str(e.get("item_id", "")) if e.get("item_id") != null else "")
	if not given.is_empty():
		return given
	var give := _plan_give(s, items, rules, turn_id, e, level, pending)
	if give.has("plan"):  # the master's own gift: within the budget until the long rest (v0.7.14.3)
		var def := ItemRules.def_of(items, s.items, str(give["plan"]["item_id"])) if not give["plan"].has("def") else (give["plan"]["def"] as Dictionary)
		var value := int(def.get("value_cp", 0)) * int(give["plan"]["qty"])
		if not str(def.get("rarity", "common")) in ["common", ""]:  # big test #16 (v0.7.22.2): magic is a find, not coins
			var why := _magic_why_not(s, data, turn_id, pending)
			if not why.is_empty():
				return {"reason": why}
			give["plan"]["magic"] = true
			return give
		if value > reward_left(s, data, turn_id, pending):
			return {"reason": _over_budget(s, data, turn_id, pending)}
		give["plan"]["reward"] = value
	return give


func _plan_take_item(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var items: Dictionary = data["items"]
	var c := s.character
	var taken := _plan_quest_take(s, data, str(e.get("item_id", "")))
	if not taken.is_empty():
		return taken
	var id := str(e.get("item_id", ""))
	var qty := int(e.get("qty", 1))
	var have := int(c["inventory"].get(id, 0)) - _pending_taken(pending, id)
	if ItemRules.held_by_curse(c, data, s.items, id):
		return {"reason": "%s проклят: герой не может с ним расстаться" % ItemRules.display_name(items, s.items, id)}
	if have < qty:
		return {"reason": "у персонажа нет %s ×%d" % [id, qty]}
	return {"plan": {"item_id": id, "qty": qty},
		"summary": "Отдано: %s%s" % [ItemRules.display_name(items, s.items, id), " ×%d" % qty if qty > 1 else ""]}


func _plan_npc_attitude(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var world := WorldView.new(data["world"])
	var npc_id := str(e.get("npc_id", ""))
	if not s.npcs_here(world.world, s.room_id).has(npc_id):
		return {"reason": "NPC %s нет в этой комнате" % npc_id}
	var delta := clampi(int(e.get("delta", 0)), -2, 2)
	if delta == 0:
		return {"reason": "пустое изменение отношения"}
	return {"plan": {"npc_id": npc_id, "delta": delta},
		"summary": "%s: отношение %+d" % [world.npc(npc_id).get("name", npc_id), delta]}


func _plan_cast(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var c := s.character
	var slots := {}
	for p: Dictionary in pending:
		if p["kind"] == "cast" and int(p["plan"]["slot"]) > 0:
			slots[int(p["plan"]["slot"])] = int(slots.get(int(p["plan"]["slot"]), 0)) + 1
	var chk := SpellRules.check(c, data, str(e.get("spell", "")), int(e.get("slot_level", 0)) if e.get("slot_level") != null else 0, slots)
	if chk.has("reason"):
		return {"reason": chk["reason"]}
	var on_self := bool(e.get("on_self", false))
	return {"plan": {"spell_id": chk["spell_id"], "slot": chk["slot"], "on_self": on_self},
		"summary": "Заклинание: " + SpellRules.describe(data, chk["spell_id"], chk["slot"]) + (" — на себя" if on_self else "")}


func _plan_make(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return MakeRules.plan(s, data, e, pending)


func _plan_guise(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return Guise.plan(s, data, e, pending)


func _plan_recipe(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var made := CraftRules.make(s, data, CraftRules.spec_of(e))
	if made.has("reason"):
		return {"reason": made["reason"]}
	var title := str(e.get("book", "")).strip_edges().left(60) if e.get("book") != null else ""
	if not title.is_empty():  # v0.7.64: a book of it, for a reward or a find; known while it is carried
		CraftRules.bound(s, made, title, str(e.get("key", "")))
	return {"plan": made, "summary": "Рецепт: %s — %s, %d ч, Сл %d" % [CraftRules.recipe_name_of(s, data, made["def"], made.get("item", {})),
		BackgroundRules.tool_name(data, str(made["def"]["tool"])), int(made["def"]["hours"]), int(made["def"]["dc"])]}


func _plan_job(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var made := JobRules.make(s, data, e)
	if made.has("reason"):
		return {"reason": made["reason"]}
	return {"plan": made, "summary": "Работа: %s у %s — %d ч, Сл %d, %s за смену" % [made["def"]["name"],
		JobRules.npc_name(s, data, str(made["def"]["employer"])),
		int(made["def"]["hours"]), int(made["def"]["dc"]), Money.format(int(made["def"]["pay_cp"]))]}


func _plan_property(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var made := PropertyRules.make(s, data, e)
	if made.has("reason"):
		return {"reason": made["reason"]}
	return {"plan": made, "summary": "Продаётся: %s (%s) за %s%s" % [made["def"]["name"], (made["made"]["def"] if made.has("made") else PropertyRules.kinds(data)[made["def"]["kind"]])["name"],
		Money.format(int(made["def"]["price_cp"])), ", доход %s в день" % Money.format(int(made["def"]["income_cp_day"])) if made["def"].has("income_cp_day") else ""]}


func _plan_upgrade(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var up := PropertyRules.plan_asked(s, data, e)
	if up.has("reason"):
		return {"reason": up["reason"]}
	return {"plan": up, "summary": "Улучшение для «%s»: %s — %s, %s работы" % [PropertyRules.name_of(s, data, str(up["place"])), up["def"]["name"],
		Money.format(int(up["def"]["price_cp"])), PropertyRules._days(int(up["def"]["days"]))]}


func _plan_course(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var ce := e.duplicate()
	if ce.get("recipe") is Dictionary:
		ce["recipe"] = CraftRules.spec_of(ce["recipe"])
	var co := StudyRules.make(s, data, ce)
	if co.has("reason"):
		return {"reason": co["reason"]}
	return co


func _plan_contest(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	if not data["rules"].has("contests"):
		return {"reason": "состязаний в этих правилах нет"}
	return ContestRules.plan(s, data, e)


func _plan_wilds(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	if not data["rules"].has("wilds"):
		return {"reason": "угодий в этих правилах нет"}
	return WildsRules.plan(s, data, e)


func _plan_stock(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	if e.get("animal") != null and not str(e.get("animal", "")).is_empty():  # v0.7.42: a beast at a dealer
		if not MountRules.on(data):
			return {"reason": "ездовых животных в этих правилах нет"}
		return MountRules.plan_stock(s, data, e)
	return TradeRules.make_stock(s, data, e)


func _plan_rumor(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return RumorRules.plan(s, data, e, pending)


func _plan_letter_reply(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return LetterRules.plan(s, data, e, pending)


func _plan_beast(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	if not PetRules.on(data):
		return {"reason": "питомцев в этих правилах нет"}
	return PetRules.plan_beast(s, data, e)


func _plan_bond(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	if e.get("creature_id") != null and not str(e.get("creature_id", "")).is_empty():  # v0.7.43: a scene with a pet
		return PetRules.plan_bond(s, data, e)
	var bo := BondRules.make(s, data, e)
	if bo.has("reason"):
		return {"reason": bo["reason"]}
	return bo


func _plan_use_feature(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var c := s.character
	var rid := Stock.resolve(c, data, str(e.get("feature", "")))
	var amount := int(e.get("amount", 1))
	var spent := 0
	for p: Dictionary in pending:
		if p["kind"] == "use:feature" and p["plan"]["id"] == rid:
			spent += int(p["plan"]["amount"])
	var why := Stock.can_use(c, data, rid, amount, spent)
	if not why.is_empty():
		return {"reason": why}
	var heals: bool = not (Stock.table(data)[rid].get("on_use", {}) as Dictionary).is_empty()
	return {"plan": {"id": rid, "amount": amount}, "summary": "Умение: %s%s" % [Stock.display_name(c, data, rid),
		" (лечение движок посчитает сам, heal не нужен)" if heals else ""]}


func _plan_use_item(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var items: Dictionary = data["items"]
	var c := s.character
	var iid := str(e.get("item_id", ""))
	var in_use := pending.filter(func(p: Dictionary) -> bool: return p["kind"] == "use:item" and p["plan"]["item_id"] == iid).size()
	var why := ItemRules.can_use(c, data, s.items, iid, _pending_taken(pending, iid) + in_use)
	if not why.is_empty():
		return {"reason": why}
	return {"plan": {"item_id": iid}, "summary": "Использовано: %s" % ItemRules.display_name(items, s.items, iid)}


func _plan_furnish(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return PropRules.plan_furnish(s, data, e)


func _plan_take_from(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return ContainerRules.plan_take(s, data, str(e.get("prop_id", "")), str(e.get("item_id", "")), int(e.get("qty", 1)))


func _plan_put_in(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return ContainerRules.plan_put(s, data, str(e.get("prop_id", "")), str(e.get("item_id", "")), int(e.get("qty", 1)))


func _plan_create_place(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return WorldGen.plan_place(s, data, e, searched_places.has(turn_id))


func _plan_goal_assess(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return GoalRules.plan_assess(s.character, data, e)


func _plan_goal_hint(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return GoalRules.plan_hint(s.character, data)


func _plan_create_quest(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return QuestGen.plan_quest(s, data, e, searched_quests.has(turn_id))


func _plan_quest_act(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return QuestGen.plan_act(s, data, e)


func _plan_create_npc(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return WorldGen.plan_npc(s, data, e.get("npc", {}) if e.get("npc") is Dictionary else {}, searched_npcs.has(turn_id), _new_rooms(s, data, pending))


func _plan_drop_item(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return ContainerRules.plan_drop(s, data, str(e.get("item_id", "")), int(e.get("qty", 1)))


func _plan_fill(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var only := str(e.get("item_id", "")) if e.get("item_id") != null else ""
	var why := NeedRules.can_fill(s, data, only)
	if not why.is_empty():
		return {"reason": {"NEED_NO_SKIN": "у героя нет такой ёмкости (бурдюк, фляга, кувшин, ведро)", "NEED_NO_SOURCE":
			"здесь нет воды: ни тега комнаты, ни вещи-источника (колодец, ручей, река — вещь обстановки с source)",
			"NEED_SKIN_FULL": "ёмкости уже полны"}.get(why, why)}
	return {"plan": {"only": only}, "summary": "Набрать воды: %s" % ", ".join(VesselRules.to_fill(s.character, data, NeedRules.foul_here(s, data), only)
		.map(func(v: Dictionary) -> String: return ItemRules.display_name(data["items"], s.items, v["id"])))}


func _plan_advance_time(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var mins := int(e.get("minutes", 0))
	var cap := int(TimeRules.cfg(data)["max_master_minutes"])
	if mins <= 0 or mins > cap:
		return {"reason": "время — от 1 до %d минут за ход" % cap}
	if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "advance_time"):
		return {"reason": "время уже сдвинуто в этом ходе"}
	return {"plan": {"minutes": mins}, "summary": "Прошло: %s" % _duration(mins)}


func _plan_flag(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var flag := str(e.get("flag", ""))
	if flag.is_empty():
		return {"reason": "пустой флаг"}
	if not QuestRules.known_flags(data["world"]).has(flag):
		return {"reason": "флаг %s миру не знаком; память о событии — эффект note с короткой фразой по-русски" % flag}
	return {"plan": {"flag": flag, "value": bool(e.get("value", true))}, "summary": "Отмечено: %s" % flag}


func _plan_npc_follow(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var fid := str(e.get("npc_id", ""))
	if pending.any(func(p: Dictionary) -> bool: return str(p["plan"].get("follow_npc", "")) == fid):
		return {"reason": "это уже есть в этом ходе"}
	return FollowRules.plan(s, data, fid, bool(e.get("follow", true)), bool(e.get("home", false)),
		(_won_over.get(turn_id, []) as Array).has(fid))


func _plan_reputation(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return ReputationRules.plan(s, data, int(e.get("delta", 0)), str(e.get("reason", "")), pending)


func _plan_reveal_secret(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var world := WorldView.new(data["world"])
	var who := str(e.get("npc_id", ""))
	if not s.npcs_here(world.world, s.room_id).has(who):
		return {"reason": "NPC %s нет в этой комнате" % who}
	return SocialRules.plan_secret(s, data, who, str(e.get("secret_id", "")))


func _plan_accept_quest(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var world := WorldView.new(data["world"])
	var qid := str(e.get("quest_id", ""))
	var why := QuestRules.can_accept(s, world.world, qid)
	if not why.is_empty():
		return {"reason": {"QUEST_UNKNOWN": "нет задания %s в пакете" % qid, "QUEST_DONE": "задание %s уже взято или сделано" % qid,
			"QUEST_WRONG_PLACE": "задание %s здесь не предлагают — только его задатель (список в quests)" % qid}.get(why, why)}
	if not QuestGen.can_take(s, data, qid).is_empty():
		return {"reason": "у героя уже %d созданных заданий в работе — больше не взять" % QuestGen.open_made(s).size()}
	var giver := QuestRules.stand_in(s, world.world, str(QuestRules.quest(world.world, qid).get("giver", "")))
	if s.in_conversation() and s.npc_id != giver:
		return {"reason": "задание %s даёт не собеседник, а %s" % [qid, world.npc(giver).get("name", giver)]}
	return {"plan": {"quest_accept": qid}, "summary": "Новое задание: %s" % QuestRules.quest(world.world, qid)["title"]}


func _plan_crime_known(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return CrimeRules.plan_reveal(s, data, str(e.get("victim_id", "")))


func _plan_crime_release(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return CrimeRules.plan_release(s, data, _won.get(turn_id, []))


func _plan_owner(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return OwnerRules.plan(s, data, e)


func _plan_note(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var world := WorldView.new(data["world"])
	var text := str(e.get("text", "")).strip_edges()
	if text.length() < 5:
		return {"reason": "пустая заметка"}
	var about := str(e.get("npc_id", "")) if e.get("npc_id") != null else ""
	if not about.is_empty():  # v0.7.15: the NPC of the scene remembers it
		if not s.npcs_here(world.world, s.room_id).has(about):
			return {"reason": "NPC %s нет в этой комнате: память — о тех, кто здесь" % about}
		return {"plan": {"text": text.left(200), "npc_id": about},
			"summary": "%s запомнит: %s" % [world.npc(about).get("name", about), text.left(200)]}
	return {"plan": {"text": text.left(200)}, "summary": "Запомнено: %s" % text.left(200)}


func _plan_grant(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var world := WorldView.new(data["world"])
	var npc_id := str(e.get("npc_id", ""))
	if not s.npcs_here(world.world, s.room_id).has(npc_id):
		return {"reason": "NPC %s нет в этой комнате" % npc_id}
	var won := (_won_over.get(turn_id, []) as Array).has(npc_id)
	if pending.any(func(p: Dictionary) -> bool: return p["kind"] == key(e) and str(p["plan"].get("discount", p["plan"].get("favor", ""))) == npc_id):
		return {"reason": "это уже есть в этом ходе"}
	if str(e["what"]) == "discount":
		return SocialRules.plan_discount(s, data, npc_id, int(e.get("percent", 0)), won)
	return SocialRules.plan_favor(s, data, npc_id, str(e.get("service", "")), str(e.get("item_id", "")) if e.get("item_id") != null else "", won)


func _plan_start_combat(s: GameSession, data: Dictionary, _turn_id: String, e: Dictionary, _pending: Array[Dictionary]) -> Dictionary:
	if not CombatRules.active(s):  # v0.7.4: a fight starts only with the scene's people or an encounter of the world
		return {"reason": "вне боя мастер не зовёт врагов: драка начинается, когда игрок нападает на NPC сцены (next_mode combat), или встречей мира"}
	return _plan_fight(s, data, e)



## A condition on the hero by the master (v0.7.8, «Правила 5e: состояния»): with a reason, a save the engine rolls
## (an ability and a DC tier; the tag gives race traits their advantage or immunity) and a duration from the list.
## Without a save — only when the hero brought it on themselves this turn (`cause: player`: drank, lay down). An
## incapacitating condition out of a fight needs an end in time (the engine lets the time pass). `on: false` lifts
## it (exhaustion — one level).
func _plan_condition(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var c := s.character
	var cond := str(e.get("condition", ""))
	var made := MakeRules.def_of(data, cond)
	if e.get("target_id") != null and not str(e.get("target_id", "")).is_empty():
		return {"reason": "вне боя target_id не нужен: состояние ложится на героя; что случилось с NPC — опиши словами"}
	if not ConditionRules.known(data, cond):
		return {"reason": "неизвестное состояние %s; есть: %s" % [cond, ", ".join((rules["conditions"] as Dictionary).keys())]}
	var title := ConditionRules.name_of(data, cond)
	if not bool(e.get("on", true)):
		if MakeRules.is_trait(data, cond):
			return {"reason": "черта остаётся с героем: её не снять словами"}
		if cond == "exhaustion" and ConditionRules.exhaustion(c) <= 0 or cond != "exhaustion" and not ConditionRules.has(c, cond):
			return {"reason": "у персонажа нет состояния %s" % cond}
		return {"plan": {"condition": cond, "on": false}, "summary": "Снято: %s" % title}
	if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "condition" and str(p["plan"].get("condition", "")) == cond):
		return {"reason": "это состояние уже предложено в этом ходе"}
	var duration := str(e.get("duration", "")) if e.get("duration") != null else ""
	if duration.is_empty():
		duration = "long_rest"
	if not ConditionRules.durations(data).has(duration):
		return {"reason": "неизвестная длительность %s; есть: %s" % [duration, ", ".join(ConditionRules.durations(data))]}
	if ThingRules.lies_on_things(data, cond):
		return {"reason": "это состояние вещи, не героя"}
	if cond == "invisible":
		return {"reason": "невидимость героя — только заклинанием (cast) или вещью"}
	if ConditionRules.INCAPACITATING.has(cond) and not CombatRules.active(s) and not (rules["hero_effects"]["durations"] as Dictionary).has(duration):
		return {"reason": "«%s» вне боя — только на время из списка (round … eight_hours): движок проматывает его, пока герой не очнётся" % title}
	var reason := str(e.get("reason", "")).strip_edges()
	if reason.is_empty():
		return {"reason": "у состояния нужна причина (reason): что его вызвало"}
	var sv: Variant = e.get("save")
	var tag := str(e.get("tag", "")) if e.get("tag") != null else ""
	if not tag.is_empty() and not (rules["hero_effects"]["save_tags"] as Array).has(tag):
		return {"reason": "неизвестный тег %s; есть: %s" % [tag, ", ".join(rules["hero_effects"]["save_tags"])]}
	var by_player := str(e.get("cause", "")) == "player"
	if sv == null or not (sv is Dictionary):
		if not by_player and (made.is_empty() or bool(made.get("harm", false))):
			return {"reason": "состояние на героя — со спасброском (save {ability, dc_tier} и tag); без него — только если герой сам навлёк его своими словами в этом ходе (cause: player)"}
		if by_player and not player_turns.has(turn_id):
			return {"reason": "cause: player — только в ход, где игрок сам что-то сделал; здесь нужен спасбросок"}
	var source := {"kind": "master", "name": reason}
	var plan := {"condition": cond, "on": true, "ends": ConditionRules.ends_for(s, data, duration), "duration": duration, "source": source}
	var by := str(e.get("by", "")) if e.get("by") != null else ""
	if not by.is_empty():
		plan["by"] = by
	if bool(e.get("ends_on_damage", false)):
		plan["wake"] = true
	var dur_text := ConditionRules.left_text(s, {"ends": plan["ends"]})
	var immune := HeroDefense.immune(c, data, cond, tag)
	if not immune.is_empty():
		return {"plan": {"condition": cond, "on": true, "resisted": true}, "summary": "%s: не действует — %s" % [title, immune]}
	if sv is Dictionary:
		var ab := str((sv as Dictionary).get("ability", ""))
		var tier := str((sv as Dictionary).get("dc_tier", ""))
		if not (rules["saves"] as Array).has(ab) or not (rules["dc_tiers"] as Dictionary).has(tier):
			return {"reason": "спасбросок: ability одна из %s, dc_tier один из %s" % [", ".join(rules["saves"]), ", ".join((rules["dc_tiers"] as Dictionary).keys())]}
		var dc := maxi(int(rules["dc_tiers"][tier]), int(made.get("dc", 0)))  # the parts' price: no easier than it does
		var r := HeroDefense.save(s, data, ab, dc, tag)
		if bool(r["ok"]):
			return {"plan": {"condition": cond, "on": true, "resisted": true}, "summary": "%s: устоял — спасбросок %s" % [title, r["text"]]}
		if bool(e.get("repeat_save", false)):
			plan["save"] = {"ability": ab, "dc": dc, "tag": tag, "repeat": true}
		return {"plan": plan, "summary": "%s (%s, %s) — спасбросок %s" % [title, dur_text, reason, r["text"]]}
	return {"plan": plan, "summary": "%s (%s, %s)" % [title, dur_text, reason]}


## A disease caught by the hero (v0.7.23.1): a known one by id or name, or a new one made within rules.diseases.make;
## always with the engine's save (CON by default, tag disease). The summary does not name it: it shows later.
func _plan_disease(s: GameSession, data: Dictionary, _turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var c := s.character
	var reason := str(e.get("reason", "")).strip_edges()
	if reason.is_empty():
		return {"reason": "у заражения нужна причина (reason): укус, гнилая вода, больной рядом"}
	var sv: Variant = e.get("save")
	if not (sv is Dictionary) or not (rules["saves"] as Array).has(str(sv.get("ability", ""))) or not (rules["dc_tiers"] as Dictionary).has(str(sv.get("dc_tier", ""))):
		return {"reason": "заражение — всегда со спасброском движка: save {ability (обычно con), dc_tier из %s}" % ", ".join((rules["dc_tiers"] as Dictionary).keys())}
	if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "disease"):
		return {"reason": "одно заражение за ход"}
	var key := str(e.get("disease", ""))
	var id := DiseaseRules.find(s, data, key)
	var made := {}
	if id.is_empty():
		if e.get("days") == null:
			var names: Array[String] = []
			for k: String in DiseaseRules.all(s, data):
				names.append("%s (%s)" % [k, DiseaseRules.all(s, data)[k].get("name", k)])
			return {"reason": "неизвестная болезнь «%s»; есть: %s. Новую — с days, incubation_hours и symptoms" % [key, ", ".join(names)]}
		var m := DiseaseRules.make(data, key, e)
		if m.has("reason"):
			return {"reason": m["reason"]}
		made = m["def"]
		id = "gen_disease_%d" % (DiseaseRules.all(s, data).size() + 1)
	if DiseaseRules.sick(c, id):
		return {"reason": "герой уже болен этим — опиши без нового заражения"}
	var immune := HeroDefense.immune(c, data, "", "disease")
	if not immune.is_empty():
		return {"plan": {"resisted": true}, "summary": "Зараза не берёт — %s" % immune}
	var dc := int(rules["dc_tiers"][str(sv["dc_tier"])])
	var r := HeroDefense.save(s, data, str(sv["ability"]), dc, "disease")
	if bool(r["ok"]):
		return {"plan": {"resisted": true}, "summary": "Зараза (%s): устоял — спасбросок %s" % [reason, r["text"]]}
	return {"plan": {"disease": id, "made": made}, "summary": "Зараза (%s): провал — спасбросок %s" % [reason, r["text"]]}


## Effects on an enemy in a fight (the master's improvisation): damage by severity, a condition.
func _plan_on_foe(s: GameSession, data: Dictionary, e: Dictionary, tid: String) -> Dictionary:
	var f := CombatRules.fighter(s, tid)
	if f.is_empty() or str(f.get("side")) != "enemy" or str(f.get("status")) != "active":
		return {"reason": "в бою нет такого врага: %s (есть: %s)" % [tid, ", ".join(CombatRules.enemies(s))]}
	match str(e.get("kind", "")):
		"damage":
			var dice := _damage_dice(data["rules"], int(s.character.get("level", 1)), str(e.get("severity", "")))
			if dice.is_empty():
				return {"reason": "неизвестная тяжесть урона"}
			var amount := _roll(s.rng, int(dice[0]), int(dice[1]), 0)
			return {"plan": {"foe": tid, "amount": amount}, "summary": "%s: −%d HP" % [f["name"], amount]}
		"condition":
			var cond := str(e.get("condition", ""))
			if not ConditionRules.known(data, cond):
				return {"reason": "неизвестное состояние %s" % cond}
			if bool(e.get("on", true)) and CombatRules.immune_to(data, f, cond):
				return {"reason": "%s невосприимчив к этому состоянию (иммунитет монстра) — опиши, что не вышло" % f["name"]}
			return {"plan": {"foe": tid, "condition": cond, "on": bool(e.get("on", true))},
				"summary": "%s: %s" % [f["name"], str(data["rules"]["conditions"][cond]).get_slice(":", 0)]}
	return {"reason": "на врага в бою — только damage и condition"}


## The master starts a fight: SRD monsters within the hard XP budget of the character's level (DMG). In a fight it is
## a reinforcement (v0.6.2): the foes still fighting and on the way plus the new ones stay within the same budget;
## they come at the edge column after rules.combat.reinforce_delay rounds.
func _plan_fight(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var foes: Array = []
	var xp := 0
	for spec: Variant in e.get("enemies", []):
		if not (spec is Dictionary):
			continue
		var mid := str(spec.get("monster", ""))
		var m: Dictionary = data["monsters"].get(mid, {})
		if m.is_empty():
			return {"reason": "нет такого монстра SRD: %s" % mid}
		var n := clampi(int(spec.get("count", 1)), 1, 6)
		xp += int(m["xp"]) * n
		foes.append({"monster": mid, "count": n, "name": str(spec.get("name", m["name"]))})
	if foes.is_empty():
		return {"reason": "кого звать в бой? enemies: [{monster, count}]"}
	var cap := int(CombatRules.cfg(data)["xp_budget_hard"].get(str(int(s.character.get("level", 1))), 750))
	if CombatRules.active(s):
		var in_play := CombatRules.xp_in_play(s, data)
		if in_play + xp > cap:
			return {"reason": "подкрепление не по силам %d уровню: в бою и на подходе %d опыта врагов, с новыми %d при пределе %d" % [int(s.character.get("level", 1)), in_play, in_play + xp, cap]}
		var side := str(e.get("side", "")) if e.get("side") != null else ""
		if not side in ["left", "right"]:
			side = "left" if s.rng.randi_range(0, 1) == 0 else "right"
		return {"plan": {"foes": foes, "reinforce": true, "side": side}, "summary": "Подкрепление: " + ", ".join(foes.map(func(f: Dictionary) -> String: return "%s ×%d" % [f["name"], f["count"]]))}
	if xp > cap:
		return {"reason": "бой слишком тяжёл для %d уровня: %d опыта врагов при пределе %d — меньше врагов или слабее" % [int(s.character.get("level", 1)), xp, cap]}
	return {"plan": {"foes": foes}, "summary": "Бой: " + ", ".join(foes.map(func(f: Dictionary) -> String: return "%s ×%d" % [f["name"], f["count"]]))}


## Gear by words (v0.7.4): like the character sheet; `all` strips every slot; in a fight armour cannot change.
func _plan_equip(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var c := s.character
	var slot := str(e.get("slot", ""))
	var id := str(e.get("item_id", "")) if e.get("item_id") != null else ""
	var eq: Dictionary = c.get("equipped", {})
	if slot == "all":
		if CombatRules.active(s) and not str(eq.get("armor", "")).is_empty():
			return {"reason": "в бою доспех не снять — на это уходят минуты"}
		var worn: Array[String] = []
		for sl: String in CharacterRules.SLOTS:
			if ItemRules.held_by_curse(c, data, s.items, str(eq.get(sl, ""))):
				return {"reason": "%s проклят и не снимается — только «Снятие проклятия»" % ItemRules.display_name(data["items"], s.items, str(eq[sl]))}
			if not str(eq.get(sl, "")).is_empty():
				worn.append(ItemRules.display_name(data["items"], s.items, str(eq[sl])))
		if worn.is_empty():
			return {"reason": "на персонаже и так ничего не надето"}
		return {"plan": {"slots": CharacterRules.SLOTS.duplicate(), "item_id": ""}, "summary": "Снято: %s" % ", ".join(worn)}
	if not CharacterRules.SLOTS.has(slot):
		return {"reason": "нет такого слота: %s (%s, all)" % [slot, ", ".join(CharacterRules.SLOTS)]}
	if CharacterRules.WEAR_SLOTS.has(slot) and CombatRules.active(s):
		return {"reason": "в бою кольца, плащи и сапоги не меняют — на это уходит время"}
	if (slot == "armor" or slot == "shield") and CombatRules.active(s):
		return {"reason": "в бою %s не сменить — на это уходят минуты или целое действие" % ("доспех" if slot == "armor" else "щит")}
	if CombatRules.active(s) and not id.is_empty():  # drawing a weapon: free once a turn, then the action (5e)
		var econ := CombatRules.economy(s)
		if bool(econ.get("object", false)) and int(econ.get("action", 0)) <= 0:
			return {"reason": "в этот ход оружие уже доставали, а действие потрачено — сменить можно в следующий ход"}
	if ItemRules.held_by_curse(c, data, s.items, str(eq.get(slot, ""))):
		return {"reason": "%s проклят и не снимается — только «Снятие проклятия»" % ItemRules.display_name(data["items"], s.items, str(eq[slot]))}
	if id.is_empty():
		if str(eq.get(slot, "")).is_empty():
			return {"reason": "в слоте %s и так пусто" % slot}
		return {"plan": {"slots": [slot], "item_id": ""}, "summary": "Снято: %s" % ItemRules.display_name(data["items"], s.items, str(eq[slot]))}
	var why := CharacterRules.can_equip(c, data, s.items, id, slot)
	if not why.is_empty():
		return {"reason": "нельзя надеть %s в %s: %s" % [id, slot, tr(why)]}
	var freed := CharacterRules.hands_freed(c, data, s.items, id, slot)
	if freed.has("shield") and CombatRules.active(s):
		return {"reason": "двуручное в бою не взять со щитом — щит снимают целым действием"}
	return {"plan": {"slots": [slot], "item_id": id, "freed": freed}, "summary": "Надето: %s" % ItemRules.display_name(data["items"], s.items, id)}


## Opening a locked container by words (v0.7.18.1): a key the hero carries, or a check of this turn that beat the lock
## (Sleight of Hand with thieves' tools — `pick`, Athletics — `force`, it breaks).
func _plan_unlock(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, _pending: Array[Dictionary]) -> Dictionary:
	var p := PropRules.find(s, s.room_id, str(e.get("prop_id", "")))
	if p.is_empty() or not bool(p.get("locked", false)):
		return {"reason": "в комнате нет запертого %s" % e.get("prop_id", "")}
	var how := str(e.get("how", "key"))
	if not ContainerRules.ways(s, data, p).has(how):
		return {"reason": "так не открыть: можно %s" % ", ".join(ContainerRules.ways(s, data, p))}
	if how != "key":
		var need := ContainerRules.lock_check(data, p, how)
		var ok := (_rolls.get(turn_id, []) as Array).any(func(r: Dictionary) -> bool:
			return str(r["skill"]) == str(need["skill"]) and bool(r["success"]) and int(r["total"]) >= int(need["dc"]))
		if not ok:
			return {"reason": "сначала проверка %s (DC движок знает) — `request_check`; при успехе — `unlock`" % need["skill"]}
	return {"plan": {"room": s.room_id, "prop": p["id"], "how": how}, "summary": "%s: %s" % [p["name"], "открыт ключом" if how == "key" else "вскрыт" if how == "pick" else "взломан"]}


## The master's door (v0.7.22.25): its owner unlocks or locks it; a passed Sleight of Hand this turn picks it, a passed
## Athletics breaks it — against WayRules.dcs.
func _plan_door(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, _pending: Array[Dictionary]) -> Dictionary:
	var to := str(e.get("to_room", ""))
	if not WayRules.open_exits(s, data["world"], s.room_id).has(to) or WayRules.def(data, s.room_id, to).is_empty():
		return {"reason": "между %s и %s нет двери" % [s.room_id, to]}
	var action := str(e.get("action", "unlock"))
	var w := WorldView.new(data["world"])
	var owner := str(w.site_of(to).get("owner", w.site_of(s.room_id).get("owner", "")))
	var by_owner := not owner.is_empty() and (s.npcs_here(w.world, s.room_id).has(owner) or s.npcs_here(w.world, to).has(owner)) 		and not Being.dead(s, owner)
	var dcs := WayRules.dcs(s, data, s.room_id, to)
	var passed := func(skill: String, dc: int) -> bool:
		return (_rolls.get(turn_id, []) as Array).any(func(r: Dictionary) -> bool:
			return str(r["skill"]) == skill and bool(r["success"]) and int(r["total"]) >= dc)
	var how := ""
	match action:
		"lock":
			if not by_owner:
				return {"reason": "запереть дверь может её хозяин, когда он рядом; игрок запирает ключом сам"}
			how = "owner"
		"unlock":
			if WayRules.blocked(s, data, s.room_id, to).is_empty():
				return {"reason": "дверь и так открыта"}
			how = "owner" if by_owner else "pick" if passed.call("sleight_of_hand", int(dcs["pick"])) else ""
			if how.is_empty():
				return {"reason": "отпереть может хозяин (его здесь нет) или проверка sleight_of_hand с отмычками (`request_check`) — либо кнопки игрока у выхода"}
		"break":
			if not passed.call("athletics", int(dcs["force"])):
				return {"reason": "сначала проверка athletics (DC движок знает) — `request_check`; при успехе — `door` break"}
			how = "force"
	var words := {"lock": "заперта", "unlock": "отперта", "break": "выбита"}
	return {"plan": {"from": s.room_id, "to": to, "action": action, "how": how},
		"summary": "Дверь в «%s» %s" % [w.room(to).get("name", to), words[action]]}


## A thing of a quest (its giver hands it over, or a step wants it) never changes hands by a plain effect (v0.7.2):
## the master giving it where its giver offers the quest takes the quest — the thing comes with it; anywhere else it
## is refused. {} when the thing belongs to no quest.
func _plan_quest_give(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var world: Dictionary = data["world"]
	var quests := QuestRules.stepped(world)
	for qid: String in quests:
		if not (quests[qid].get("offer_items", {}) as Dictionary).has(id):
			continue
		var q: Dictionary = quests[qid]
		if QuestRules.can_accept(s, world, qid).is_empty() and (not s.in_conversation() or s.npc_id == str(q.get("giver", ""))):
			return {"plan": {"quest_accept": qid}, "summary": "Новое задание: %s" % q["title"]}
		if s.quests_active.has(qid) or s.quests_done.has(qid):
			return {"reason": "это вещь задания «%s», она уже выдана по заданию — второй раз её не дают" % q["title"]}
		return {"reason": "это вещь задания «%s»: её даёт %s вместе с заданием — игрок берёт его кнопкой «Взять задание» у него" % [q["title"],
			WorldView.new(world).npc(str(q.get("giver", ""))).get("name", q.get("giver", ""))]}
	return _plan_hidden_give(s, world, id)


## A thing lying in a hiding place not yet found (a quest's thing, a cache) comes only from finding it: given by
## words it skipped the quest's «find» step (v0.7.38.5, the author's white root).
func _plan_hidden_give(s: GameSession, world: Dictionary, id: String) -> Dictionary:
	for rid: String in world["rooms"]:
		for sec: Dictionary in ExplorationRules.secrets(world, rid):
			if not (sec.get("loot", {}).get("items", {}) as Dictionary).has(id) or Knows.has(s, Knows.SECRET, rid, str(sec["id"])):
				continue
			var skill := str(sec.get("skill", "perception"))
			var how := "request_check %s или investigation" % skill if skill != "investigation" else "request_check investigation"
			var where := str(world["rooms"][rid].get("name", rid))
			if rid != s.room_id:
				return {"reason": "эта вещь спрятана в «%s» — её находят там проверкой (%s), а не move_item:world>hero" % [where, how]}
			return {"reason": "эта вещь спрятана здесь, в тайнике — её даёт успешная проверка поиска (%s) против его сложности, а не move_item:world>hero; проверка уже провалена или не та — расскажи, что не нашёл" % how}
	return {}


## The thing a talk step of an active quest wants: handing it over by words to that NPC closes the step, as its
## button does; to anyone else it is refused. {} when no active step wants it.
func _plan_quest_take(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var world: Dictionary = data["world"]
	for qid: String in s.quests_active:
		var when: Dictionary = QuestRules.current(s, world, qid).get("when", {})
		if str(when.get("item", "")) != id:
			continue
		var q := QuestRules.quest(world, qid)
		var npc := str(when.get("talk", ""))
		if not npc.is_empty() and QuestRules.can_talk(s, world, qid).is_empty():
			return {"plan": {"quest_talk": qid}, "summary": "Отдано: %s" % ItemRules.display_name(data["items"], s.items, id)}
		return {"reason": "это вещь задания «%s»: её отдают только %s — не забирай её эффектом" % [q["title"],
			WorldView.new(world).npc(npc).get("name", npc) if not npc.is_empty() else "по заданию"]}
	return {}


func _plan_give(s: GameSession, items: Dictionary, rules: Dictionary, turn_id: String, e: Dictionary, level: int, pending: Array[Dictionary] = []) -> Dictionary:
	var qty := int(e.get("qty", 1))
	var id := str(e.get("item_id", "")) if e.get("item_id") != null else ""
	var new_def := {}
	if e.get("item") is Dictionary:
		if not searched.has(turn_id):
			return {"reason": "сначала найди похожие предметы через find_items"}
		var chk := ItemRules.check_generated(items, MakeRules.resolved_item(e["item"], pending), level, _data.get("spells", {}))
		if not bool(chk["ok"]):
			return {"reason": chk["reason"]}
		new_def = chk["def"]
		id = ItemRules.generated_id(new_def)
		if items["catalog"].has(id):
			return {"reason": "такой предмет уже есть в каталоге: %s" % id}
	var def := new_def if not new_def.is_empty() else ItemRules.def_of(items, s.items, id)
	if def.is_empty():
		return {"reason": "предмета %s нет ни в каталоге, ни в игре; найди его через find_items" % id}
	if qty > 1 and not bool(def.get("stack", false)):
		return {"reason": "%s не складывается в стопку, дай по одному" % def.get("name", id)}
	var rare := ItemRules.rarity_ok({"rules": rules}, def, level)  # v0.7.12: nothing rarer than uncommon at levels 1-5
	if not rare.is_empty():
		return {"reason": rare}
	if int(def.get("value_cp", 0)) * qty > _reward_cap(rules, level):
		return {"reason": "предмет дороже бюджета награды для %d уровня" % level}
	var plan := {"item_id": id, "qty": qty}
	if not new_def.is_empty():
		plan["new_item_id"] = id
		plan["def"] = new_def
	return {"plan": plan, "summary": "Получено: %s%s" % [def.get("name", id), " ×%d" % qty if qty > 1 else ""]}


func _apply_one(s: GameSession, kind: String, plan: Dictionary) -> void:
	if plan.has("foe"):
		var f := CombatRules.fighter(s, str(plan["foe"]))
		if kind == "damage":
			var tmp: Array[String] = []
			CombatRules._hurt_enemy(s, _data, f, int(plan["amount"]), tmp)
		elif bool(plan.get("on", true)):
			CombatRules._hold(f, str(plan["condition"]))
		else:
			ConditionRules.remove(f, str(plan["condition"]))
		return
	var row: Dictionary = _table()[kind]
	if row.has("do"):
		(row["do"] as Callable).call(s, plan)
	else:
		var said: Variant = (row["apply"] as Callable).call(s, _data, plan)
		if said is Array:
			_extra_lines.append_array(said)


func _do_move(s: GameSession, plan: Dictionary) -> void:
	s.room_id = str(_made.get("rooms", {}).get(str(plan["room_id"]).trim_prefix("new:"), plan["room_id"])) if str(plan["room_id"]).begins_with("new:") else str(plan["room_id"])
	if bool(plan.get("escort", false)):
		s.arrest = s.room_id  # the hold goes along with the guard
	for n: Variant in plan.get("with", []):
		FollowRules.apply(s, {"follow_npc": str(n), "on": true, "room": ""})


func _do_damage(s: GameSession, plan: Dictionary) -> void:
	var c := s.character
	c["hp"] = maxi(0, int(c["hp"]) - int(plan["amount"]))
	_extra_lines.append_array(HeroDefense.after_damage(s, _data, int(plan["amount"])))
	HeroDefense.relentless(s, _data, _extra_lines)


func _do_heal(s: GameSession, plan: Dictionary) -> void:
	var c := s.character
	c["hp"] = mini(int(c["max_hp"]), int(c["hp"]) + int(plan["amount"]))


func _do_coins(s: GameSession, plan: Dictionary) -> void:
	Ledger.add(s, int(plan["delta"]), "effect_engine:apply_one")
	if str(plan.get("settles", "")) == "tax":
		_extra_lines.append_array(PropertyRules.settle_tax(s, _data, -int(plan["delta"])))


func _do_give_item(s: GameSession, plan: Dictionary) -> void:
	if _quest_thing(s, plan):
		return
	var c := s.character
	if plan.has("def"):
		s.items[plan["item_id"]] = plan["def"]
	ItemRules.found(c, _data, s.items, str(plan["item_id"]), int(plan["qty"]))


func _do_take_item(s: GameSession, plan: Dictionary) -> void:
	if _quest_thing(s, plan):
		return
	var c := s.character
	var left := int(c["inventory"].get(plan["item_id"], 0)) - int(plan["qty"])
	if left > 0:
		c["inventory"][plan["item_id"]] = left
	else:
		c["inventory"].erase(plan["item_id"])


func _do_npc_attitude(s: GameSession, plan: Dictionary) -> void:
	s.shift_attitude(str(plan["npc_id"]), int(plan["delta"]), _data)


func _do_start_combat(s: GameSession, plan: Dictionary) -> void:
	if bool(plan.get("reinforce", false)) and CombatRules.active(s):
		CombatRules.add_incoming(s, _data, plan["foes"], int(s.combat["round"]) + int(CombatRules.cfg(_data)["reinforce_delay"]), str(plan["side"]))
	else:
		s.pending_fight = plan["foes"]


func _do_cast(s: GameSession, plan: Dictionary) -> void:
	var c := s.character
	var cast := SpellRules.cast(c, _data, plan["spell_id"], int(plan["slot"]), s, bool(plan.get("on_self", false)))
	if bool(plan.get("on_self", false)):
		_extra_lines.append_array(cast.slice(1))  # what landed on the hero; the master tells the cast itself


func _do_condition(s: GameSession, plan: Dictionary) -> void:
	var c := s.character
	if bool(plan.get("resisted", false)):
		return
	var cond := str(plan["condition"])
	if not bool(plan["on"]):
		if cond == "exhaustion":
			_extra_lines.append_array(ConditionRules.add_exhaustion(s, _data, -1, ""))
		else:
			ConditionRules.remove(c, cond)
		CharacterRules.refresh(c, _data, s.items)
		return
	var fx := {"condition": cond, "ends": plan["ends"], "source": plan["source"]}
	for k: String in ["by", "wake", "save"]:
		if plan.has(k):
			fx[k] = plan[k]
	_extra_lines.append_array(ConditionRules.impose(s, _data, fx))
	CharacterRules.refresh(c, _data, s.items)


func _do_disease(s: GameSession, plan: Dictionary) -> void:
	var c := s.character
	if bool(plan.get("resisted", false)):
		return
	if not (plan["made"] as Dictionary).is_empty():
		var gen := WorldGen.generated(s)
		var made: Dictionary = gen.get("diseases", {})
		made[str(plan["disease"])] = plan["made"]
		gen["diseases"] = made
	_extra_lines.append_array(DiseaseRules.contract(s, _data, str(plan["disease"])))
	CharacterRules.refresh(c, _data, s.items)


func _do_recipe(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(CraftRules.apply_make(s, _data, plan))


func _do_job(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(JobRules.apply_make(s, _data, plan))


func _do_property(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(PropertyRules.apply_make(s, _data, plan, str(_made.get("site", "")), str(_made.get("npc", ""))))


func _do_upgrade(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(PropertyRules.apply_asked(s, _data, plan))


func _do_world_item(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(WorldItemRules.apply(s, _data, plan))


func _do_course(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(StudyRules.apply_make(s, _data, plan))


func _do_make(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(MakeRules.apply(s, _data, plan))


func _do_guise(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(Guise.apply(s, _data, plan))


func _do_supplier(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(ShopRules.apply_make(s, _data, plan))


func _do_fence(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(FenceRules.apply_make(s, _data, plan))


func _do_heist(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(HeistRules.apply_make(s, _data, plan))


func _do_org(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(OrgRules.apply_make(s, _data, plan))


func _do_faction(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(FactionRules.apply_make(s, _data, plan))


func _do_bond(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(PetRules.apply_bond(s, _data, plan) if plan.has("creature_id") else BondRules.apply_make(s, _data, plan))


func _do_beast(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(PetRules.apply_beast(s, _data, plan))


func _do_festival(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(CalendarRules.apply_festival(s, _data, plan))


func _do_weather(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(WeatherRules.apply(s, _data, plan))


func _do_rumor(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(RumorRules.apply(s, _data, plan))


func _do_letter_reply(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(LetterRules.apply(s, _data, plan))


func _do_vow(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(FaithRules.apply_vow(s, _data, plan))


func _do_god(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(FaithRules.apply_god(s, _data, plan))


func _do_stock(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(MountRules.apply_stock(s, _data, plan) if plan.has("animal") else TradeRules.apply_stock(s, _data, plan))


func _do_permit(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(SiteRules.grant(s, _data, str(plan["npc_id"]), str(plan["site_id"])))


func _do_contest(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(ContestRules.apply(s, _data, plan))


func _do_wilds(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(WildsRules.apply(s, _data, plan))


func _do_bank(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(BankRules.apply_make(s, _data, plan, str(_made.get("npc", ""))))


func _do_use_feature(s: GameSession, plan: Dictionary) -> void:
	var c := s.character
	Stock.use(c, _data, plan["id"], int(plan["amount"]), s.rng)


func _do_use_item(s: GameSession, plan: Dictionary) -> void:
	var c := s.character
	ItemRules.use(c, _data, s.items, plan["item_id"], s.rng, s)


func _do_advance_time(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(CrimeRules.wait(s, _data, int(plan["minutes"]))["lines"])


func _do_furnish(s: GameSession, plan: Dictionary) -> void:
	PropRules.apply_furnish(s, plan)


func _do_take_prop(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(PropRules.apply_take(s, _data, plan))


func _do_take_from(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(ContainerRules.apply_take(s, _data, plan))


func _do_put_in(s: GameSession, plan: Dictionary) -> void:
	ContainerRules.apply_put(s, _data, plan)


func _do_drop_item(s: GameSession, plan: Dictionary) -> void:
	ContainerRules.apply_drop(s, _data, plan)


func _do_fill(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(NeedRules.fill(s, _data, str(plan["only"])))
	_extra_lines.append_array(TimeRules.advance(s, _data, int(NeedRules.cfg(_data)["water"]["fill_minutes"])))


func _do_create_npc(s: GameSession, plan: Dictionary) -> void:
	var room := str(plan["room"])
	if room.begins_with("new:"):
		room = str(_made.get("rooms", {}).get(room.trim_prefix("new:"), s.room_id))
	_made["npc"] = WorldGen.apply_npc(s, _data, plan.merged({"room": room}, true))
	_extra_lines.append("[%s]" % _made["npc"])


func _do_create_quest(s: GameSession, plan: Dictionary) -> void:
	var qid := QuestGen.apply_quest(s, _data, plan)
	_extra_lines.append("[%s]" % qid)
	if bool(plan["quest"].get("own", false)):  # one's own deed is taken at once (v0.7.21.2); its first act comes next
		s.quests_active[qid] = 0
		_extra_lines.append("Своё дело: %s · Цель: %s" % [plan["quest"]["title"], plan["quest"]["acts"][0]["goal"]])


func _do_quest_act(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(QuestGen.apply_act(s, _data, plan))


func _do_create_place(s: GameSession, plan: Dictionary) -> void:
	var entry := WorldGen.apply_place(s, _data, plan)
	_extra_lines.append("выход: [%s]" % entry)
	WorldEvent.emit(s, _data, "place_made", {"room": entry})
	_made["rooms"] = plan["ids"]
	_made["site"] = plan["site_id"]


func _do_way(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(WayRules.apply_make(s, _data, plan))


func _do_door(s: GameSession, plan: Dictionary) -> void:
	var a := str(plan["from"])
	var b := str(plan["to"])
	match str(plan["action"]):
		"lock":
			WayRules.lock(s, a, b)
		"unlock":
			WayRules.unlock(s, _data, a, b)
		"break":
			WayRules.break_down(s, a, b)
	if str(plan["how"]) != "owner":
		var seen := WayRules.witnesses(s, _data, a, b)
		if not seen.is_empty():
			_extra_lines.append_array(CrimeRules.on_trespass(s, _data, SiteRules.unwelcome(s, _data, b), b, seen))


func _do_unlock(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(ContainerRules.unlock(PropRules.find(s, str(plan["room"]), str(plan["prop"])), str(plan["how"])))


func _do_prop_state(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(PropRules.apply_state(s, _data, plan))


func _do_flag(s: GameSession, plan: Dictionary) -> void:
	if bool(plan["value"]) and not s.flags.has(plan["flag"]):
		s.flags.append(plan["flag"])
	elif not bool(plan["value"]):
		s.flags.erase(plan["flag"])


func _do_equip(s: GameSession, plan: Dictionary) -> void:
	var before: Dictionary = (s.character["equipped"] as Dictionary).duplicate()
	for sl: Variant in plan["slots"]:
		s.character["equipped"][str(sl)] = str(plan["item_id"])
	for sl: Variant in plan.get("freed", []):  # a two-handed weapon empties the other hand
		s.character["equipped"][str(sl)] = ""
	if CombatRules.active(s):
		if not str(plan["item_id"]).is_empty():
			var econ := CombatRules.economy(s)
			if bool(econ.get("object", false)):
				econ["action"] = int(econ.get("action", 0)) - 1
			econ["object"] = true
	else:
		var minutes := CharacterRules.gear_minutes(_data, s.items, before, s.character["equipped"])
		if minutes > 0:
			_extra_lines.append("Переодевание: %d мин" % minutes)
			_extra_lines.append_array(TimeRules.advance(s, _data, minutes))
	var main := str(s.character["equipped"].get("main_hand", ""))
	if not main.is_empty() and str(s.character["equipped"].get("off_hand", "")) == main and int(s.character["inventory"].get(main, 0)) < 2:
		s.character["equipped"]["off_hand"] = ""
	CharacterRules.refresh(s.character, _data, s.items)


func _do_follow(s: GameSession, plan: Dictionary) -> void:
	FollowRules.apply(s, plan)


func _do_crime_known(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(CrimeRules.reveal(s, _data, str(plan["victim"])))


func _do_crime_release(s: GameSession, _plan_of: Dictionary) -> void:
	_extra_lines.append_array(CrimeRules.let_go(s, _data, "Стража отпускает героя — но розыск не снят"))


func _do_note(s: GameSession, plan: Dictionary) -> void:
	if plan.has("npc_id"):  # v0.7.15: an NPC remembers it
		s.remember(str(plan["npc_id"]), str(plan["text"]))
	else:
		s.notes.append(Fact.of(s, str(plan["text"]), s.room_id))


func _do_reputation(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(ReputationRules.add(s, _data, str(plan["reputation"]), int(plan["delta"]), str(plan["why"])))


func _do_secret(s: GameSession, plan: Dictionary) -> void:
	for sec: Dictionary in SocialRules.secrets(_data, str(plan["secret_npc"])):
		if str(sec["id"]) == str(plan["secret"]):
			SocialRules.tell(s, _data, str(plan["secret_npc"]), sec)
	_extra_lines.append_array(QuestRules.advance(s, _data))


func _do_goal_assess(s: GameSession, plan: Dictionary) -> void:
	GoalRules.apply_assess(s.character, plan)


func _do_goal_hint(s: GameSession, _plan_of: Dictionary) -> void:
	GoalRules.apply_hint(s.character)


func _do_quest(s: GameSession, plan: Dictionary) -> void:
	_extra_lines.append_array(QuestRules.accept(s, _data, str(plan["quest_accept"])).slice(1))


## A quest thing given or handed over by words takes the quest (v0.7.2) or closes its talk step.
func _quest_thing(s: GameSession, plan: Dictionary) -> bool:
	if plan.has("quest_accept"):
		_do_quest(s, plan)
	elif plan.has("quest_talk"):
		_extra_lines.append_array(QuestRules.talk(s, _data, str(plan["quest_talk"])).slice(1))
	return plan.has("quest_accept") or plan.has("quest_talk")



static func _damage_dice(rules: Dictionary, level: int, severity: String) -> Array:
	for row: Dictionary in rules["damage_dice_by_level"]:
		if level <= int(row["max_level"]):
			return row.get(severity, [])
	return []


## A magic thing the master gives (v0.7.22.2): not by its price in the coin budget (an uncommon thing costs more
## than the whole budget of levels 1-5), but rules.reward_budget.magic_per_rest of them until the long rest, each
## in a turn with a check that passed (a search, Arcana, Perception). "" or the reason.
func _magic_why_not(s: GameSession, data: Dictionary, turn_id: String, pending: Array[Dictionary]) -> String:
	if (_won.get(turn_id, []) as Array).is_empty():
		return "магическая вещь — находка: только в ходе с пройденной проверкой (обыск, Анализ, Внимательность — engine.check); иначе награди словами или обычной вещью"
	var given := s.magic_given + pending.filter(func(p: Dictionary) -> bool: return bool(p["plan"].get("magic", false))).size()
	if given >= int(data["rules"]["reward_budget"]["magic_per_rest"]):
		return "магическая вещь до долгого отдыха уже дана — дай обычную вещь, монеты или наводку"
	return ""


func _over_budget(s: GameSession, data: Dictionary, turn_id: String, pending: Array[Dictionary]) -> String:
	var left := reward_left(s, data, turn_id, pending)
	if (_won.get(turn_id, []) as Array).has("nearly_impossible"):
		return "после «почти невозможного» успеха награда не больше %s — дай лучший исход словами: услугу, наводку, расположение" % Money.format(left)
	return "бюджет наград до долгого отдыха исчерпан (осталось %s) — награди словами: услугой, наводкой, расположением" % Money.format(left)


static func _reward_cap(rules: Dictionary, level: int) -> int:
	for row: Array in rules["reward_max_cp_by_level"]:
		if level <= int(row[0]):
			return int(row[1])
	return 0


static func _roll(rng: RandomNumberGenerator, count: int, sides: int, bonus: int) -> int:
	var total := bonus
	for i in count:
		total += rng.randi_range(1, sides)
	return total


static func _pending_coins(pending: Array[Dictionary]) -> int:
	var sum := 0
	for p: Dictionary in pending:
		if p["kind"] == "coins":
			sum += int(p["plan"]["delta"])
	return sum


static func _pending_taken(pending: Array[Dictionary], id: String) -> int:
	var sum := 0
	for p: Dictionary in pending:
		if p["kind"] == "move_item:hero>world" and p["plan"]["item_id"] == id:
			sum += int(p["plan"]["qty"])
	return sum


static func _duration(mins: int) -> String:
	return TimeRules.span(mins)



## The place `create:place` made in this turn (pending), or {}.
static func _new_place(pending: Array[Dictionary]) -> Dictionary:
	for p: Dictionary in pending:
		if p["kind"] == "create:place":
			return p["plan"]["place"]
	return {}


## {key: location id} of the rooms of this turn's new place ("" — a new location).
static func _new_rooms(s: GameSession, data: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var place := _new_place(pending)
	var out := {}
	if place.is_empty():
		return out
	var loc := "" if bool(place["new_location"]) else WorldView.new(data["world"]).location_id(str(place["from"]))
	for r: Dictionary in place["rooms"]:
		out[str(r["key"])] = loc
	return out


## The made place goes first, then its person, then the rest: «new:<key>» refs need their ids.
func _ordered(ids: Array) -> Array:
	var rank := func(id: Variant) -> int:
		return {"create:place": 0, "create:npc": 1}.get(str(reserves.get(str(id), {}).get("kind", "")), 2)
	var out: Array = []
	for r: int in 3:
		out.append_array(ids.filter(func(id: Variant) -> bool: return rank.call(id) == r))
	return out


## A site whose owner is «new» gets the person made in this turn, or no owner.
func _link_new_owner(s: GameSession) -> void:
	if not _made.has("site"):
		return
	var sid := str(_made["site"])
	for site: Dictionary in [WorldGen.generated(s)["sites"].get(sid, {}), _data["world"].get("sites", {}).get(sid, {})]:
		if str(site.get("owner", "")) != "new":
			continue
		if _made.has("npc"):
			site["owner"] = str(_made["npc"])
		else:
			site.erase("owner")
