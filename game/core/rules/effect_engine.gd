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
## turn_id -> true once the master searched the world's people this turn (v0.7.20: before create_npc).
var searched_npcs: Dictionary = {}
## turn_id -> true once the master searched the world's quests this turn (v0.7.21: before create_quest).
var searched_quests: Dictionary = {}
## turn_id -> true once the master searched the world's places this turn (v0.7.20.1: before create_place).
var searched_places: Dictionary = {}
## Catalog.data of the last validate: apply() needs the rules of casts, feature uses and items.
var _data: Dictionary = {}


## Lines an applied effect adds after its summary (the owner of a taken thing reacts, v0.7.0).
var _extra_lines: Array[String] = []
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
	reserves[id] = {"turn_id": turn_id, "kind": str(effect.get("kind", "")), "plan": res["plan"], "summary": res["summary"]}
	var out := {"accepted": true, "effect_id": id, "summary": res["summary"]}
	if res["plan"].has("new_item_id"):
		out["item_id"] = res["plan"]["new_item_id"]
	return out


## Applies the listed reserves of `turn_id` in order, burns the rest. Returns the summaries shown to the player.
func apply(s: GameSession, turn_id: String, ids: Array) -> Array[String]:
	var lines: Array[String] = []
	for id: Variant in ids:
		var r: Dictionary = reserves.get(str(id), {})
		if r.is_empty() or r["turn_id"] != turn_id:
			continue
		_extra_lines.clear()
		s.reward_spent += int(r["plan"].get("reward", 0))  # the master's gift counts against the budget (v0.7.14.3)
		if bool(r["plan"].get("magic", false)):
			s.magic_given += 1
		_apply_one(s, r["kind"], r["plan"])
		lines.append(str(r["summary"]))
		lines.append_array(_extra_lines)  # an owner's reaction to a taken thing (v0.7.0)
	discard(turn_id)
	return lines


func _reject(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}


func _plan(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var items: Dictionary = data["items"]
	var world := WorldView.new(data["world"])
	var c := s.character
	var level := int(c.get("level", 1))
	if s.mode == GameSession.MODE_COMBAT:
		if str(e.get("kind", "")) in ["move", "coins", "give_item", "take_item", "npc_attitude", "advance_time", "furnish", "take_prop"]:
			return {"reason": "в бою это нельзя: исход боя, переходы и добычу ведёт движок; здесь — проверки, урон и состояния врагам (target_id), подкрепление (start_combat)"}
		var tid := str(e.get("target_id", "")) if e.get("target_id") != null else ""
		if not tid.is_empty():
			return _plan_on_foe(s, data, e, tid)
	elif str(e.get("kind", "")) in ["damage", "condition"] and e.get("target_id") != null and not str(e.get("target_id", "")).is_empty():
		# v0.7.22.16 (the author's trace): out of a fight a blow at an NPC is a fight, not an effect — the damage went to the hero
		return {"reason": "вне боя урон и состояния NPC эффектом не проводятся: нападение на NPC сцены — next_mode combat с его npc_id, исход решит бой"}
	if str(e.get("kind", "")) == "start_combat":
		if not CombatRules.active(s):  # v0.7.4: a fight starts only with the scene's people or an encounter of the world
			return {"reason": "вне боя мастер не зовёт врагов: драка начинается, когда игрок нападает на NPC сцены (next_mode combat), или встречей мира"}
		return _plan_fight(s, data, e)
	if s.mode == GameSession.MODE_TRADE and str(e.get("kind", "")) in ["coins", "give_item", "take_item"]:
		return {"reason": "в торговле сделки проводит панель сделки: назови цену и предложи игроку положить товар в сделку"}
	if s.mode == GameSession.MODE_SOCIAL and str(e.get("kind", "")) == "give_item" and world.is_trader(s.npc_id) 			and TradeRules.pack_stock(world.npc(s.npc_id), rules).has(str(e.get("item_id", ""))):
		return {"reason": "это товар торговца — покупка идёт через торговлю: назови цену и открой её (next_mode trade); монеты не списывай"}
	match str(e.get("kind", "")):
		"move":
			var to := str(e.get("room_id", ""))
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "move"):
				return {"reason": "переход уже предложен в этом ходе"}
			if EncounterRules.captive(s):  # v0.7.22.12: bound by the captors
				return {"reason": "герой связан и в плену — уйти нельзя, пока не освободится (кнопки игрока)"}
			if CrimeRules.held(s):  # big test #5 (v0.7.22.2): the guard leads the hero — anywhere in the location
				if world.location_id(to) != world.location_id(s.room_id) or world.room(to).is_empty():
					return {"reason": "стража держит героя: увести его можно только в комнату этой же округи (%s) — к капитану, в караулку; сам он не уйдёт" % world.location_id(s.room_id)}
				return {"plan": {"room_id": to, "with": [], "escort": true}, "summary": "Под стражей: %s" % world.room(to).get("name", to)}
			if not ExplorationRules.open_exits(s, data["world"], s.room_id).has(to):
				return {"reason": "из этой комнаты нет выхода в %s" % to}
			# v0.7.22.16: the master's move is checked as the exit button — the overload, a trap the hero found
			if CharacterRules.overloaded(c, data, s.items):
				return {"reason": "герой перегружен и не может идти — сначала оставить лишнее (drop_item)"}
			var trap := ExplorationRules.trap_on_exit(s, data["world"], s.room_id, to)
			if not trap.is_empty() and ExplorationRules.is_found(s, s.room_id, trap):
				return {"reason": "путь стережёт найденная ловушка — её обезвреживают или обходят (кнопки игрока), просто пройти нельзя"}
			var with: Array = []  # NPCs who go along (v0.7.20.4): the same engine rule as npc_follow
			for n: Variant in e.get("npcs", []) if e.get("npcs") is Array else []:
				var nid := str(n)
				if s.followers.has(nid) or with.has(nid) or pending.any(func(p: Dictionary) -> bool: return str(p["plan"].get("follow_npc", "")) == nid):
					continue
				var f := FollowRules.plan(s, data, nid, true, false, (_won_over.get(turn_id, []) as Array).has(nid))
				if f.has("reason"):
					return {"reason": "%s; без него — move без npcs" % f["reason"]}
				with.append(nid)
			var names := ", ".join(with.map(func(n: String) -> String: return str(world.npc(n).get("name", n))))
			return {"plan": {"room_id": to, "with": with},
				"summary": "Переход: %s%s" % [world.room(to).get("name", to), (" (с героем: %s)" % names) if not with.is_empty() else ""]}
		"damage":
			var dice := _damage_dice(rules, level, str(e.get("severity", "")))
			if dice.is_empty():
				return {"reason": "неизвестная тяжесть урона"}
			var amount := _roll(s.rng, int(dice[0]), int(dice[1]), 0)
			var dtype := HeroDefense.damage_type(data, str(e.get("damage_type", "")))
			var adj := HeroDefense.adjust(s, data, dtype, amount)  # v0.7.8: the hero's resistances
			var note := str(adj["note"])
			return {"plan": {"amount": int(adj["damage"])}, "summary": "−%d HP (%s%s)" % [int(adj["damage"]),
				data["misc"]["damage_types"].get(dtype, e.get("damage_type", "урон")), (", " + note) if not note.is_empty() else ""]}
		"heal":
			var h: Array = rules["heal_dice"].get(str(e.get("tier", "")), [])
			if h.is_empty():
				return {"reason": "неизвестная сила лечения"}
			if int(c["hp"]) >= int(c["max_hp"]):
				return {"reason": "персонаж и так здоров"}
			var amount := _roll(s.rng, int(h[0]), int(h[1]), int(h[2]))
			return {"plan": {"amount": amount}, "summary": "+%d HP" % amount}
		"coins":
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
			return {"plan": {"delta": delta, "reward": maxi(0, delta)}, "summary": ("+" if delta > 0 else "") + Money.format(delta)}
		"give_item":
			var given := _plan_quest_give(s, data, str(e.get("item_id", "")) if e.get("item_id") != null else "")
			if not given.is_empty():
				return given
			var give := _plan_give(s, items, rules, turn_id, e, level)
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
		"take_item":
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
		"npc_attitude":
			var npc_id := str(e.get("npc_id", ""))
			if not s.npcs_here(world.world, s.room_id).has(npc_id):
				return {"reason": "NPC %s нет в этой комнате" % npc_id}
			var delta := clampi(int(e.get("delta", 0)), -2, 2)
			if delta == 0:
				return {"reason": "пустое изменение отношения"}
			return {"plan": {"npc_id": npc_id, "delta": delta},
				"summary": "%s: отношение %+d" % [world.npc(npc_id).get("name", npc_id), delta]}
		"cast":
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
		"condition":
			return _plan_condition(s, data, turn_id, e, pending)
		"use_feature":
			var rid := FeatureUses.resolve(c, data, str(e.get("feature", "")))
			var amount := int(e.get("amount", 1))
			var spent := 0
			for p: Dictionary in pending:
				if p["kind"] == "use_feature" and p["plan"]["id"] == rid:
					spent += int(p["plan"]["amount"])
			var why := FeatureUses.can_use(c, data, rid, amount, spent)
			if not why.is_empty():
				return {"reason": why}
			var heals: bool = not (FeatureUses.table(data)[rid].get("on_use", {}) as Dictionary).is_empty()
			return {"plan": {"id": rid, "amount": amount}, "summary": "Умение: %s%s" % [FeatureUses.display_name(c, data, rid),
				" (лечение движок посчитает сам, heal не нужен)" if heals else ""]}
		"use_item":
			var iid := str(e.get("item_id", ""))
			var in_use := pending.filter(func(p: Dictionary) -> bool: return p["kind"] == "use_item" and p["plan"]["item_id"] == iid).size()
			var why := ItemRules.can_use(c, data, s.items, iid, _pending_taken(pending, iid) + in_use)
			if not why.is_empty():
				return {"reason": why}
			return {"plan": {"item_id": iid}, "summary": "Использовано: %s" % ItemRules.display_name(items, s.items, iid)}
		"furnish":
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "furnish"):
				return {"reason": "комната уже обставляется в этом ходе"}
			return PropRules.plan_furnish(s, data, e)
		"take_prop":
			return PropRules.plan_take(s, data, e)
		"take_from":  # out of a container of the room (v0.7.18.1)
			return ContainerRules.plan_take(s, data, str(e.get("prop_id", "")), str(e.get("item_id", "")), int(e.get("qty", 1)))
		"put_in":
			return ContainerRules.plan_put(s, data, str(e.get("prop_id", "")), str(e.get("item_id", "")), int(e.get("qty", 1)))
		"unlock":
			return _plan_unlock(s, data, turn_id, e)
		"create_place":  # a room or a small place on an open edge of the pack (v0.7.20.1)
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "create_place"):
				return {"reason": "одно новое место за ход"}
			return WorldGen.plan_place(s, data, e, searched_places.has(turn_id))
		"goal_assess":  # the master assesses the hero's life goal (v0.7.22)
			return GoalRules.plan_assess(s.character, data, e)
		"goal_hint":  # past the threshold, on the player's asking (v0.7.22.1)
			if pending.any(func(p: Dictionary) -> bool: return p["plan"].has("goal_hint")):
				return {"reason": "один намёк за ход"}
			return GoalRules.plan_hint(s.character, data)
		"create_quest":  # a quest of the pack's schema from a giver of the scene (v0.7.21)
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "create_quest"):
				return {"reason": "одно новое задание за ход"}
			return QuestGen.plan_quest(s, data, e, searched_quests.has(turn_id))
		"create_npc":  # a person the world lacks, by the pack's schema (v0.7.20)
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "create_npc"):
				return {"reason": "один новый человек за ход"}
			return WorldGen.plan_npc(s, data, e.get("npc", {}) if e.get("npc") is Dictionary else {}, searched_npcs.has(turn_id))
		"drop_item":  # the hero leaves a thing (a bag with what is in it) in the room (v0.7.18.2)
			return ContainerRules.plan_drop(s, data, str(e.get("item_id", "")), int(e.get("qty", 1)))
		"prop_state":
			return PropRules.plan_state(s, e)
		"advance_time":
			var mins := int(e.get("minutes", 0))
			var cap := int(TimeRules.cfg(data)["max_master_minutes"])
			if mins <= 0 or mins > cap:
				return {"reason": "время — от 1 до %d минут за ход" % cap}
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "advance_time"):
				return {"reason": "время уже сдвинуто в этом ходе"}
			return {"plan": {"minutes": mins}, "summary": "Прошло: %s" % _duration(mins)}
		"flag":
			var flag := str(e.get("flag", ""))
			if flag.is_empty():
				return {"reason": "пустой флаг"}
			if not QuestRules.known_flags(data["world"]).has(flag):
				return {"reason": "флаг %s миру не знаком; память о событии — эффект note с короткой фразой по-русски" % flag}
			return {"plan": {"flag": flag, "value": bool(e.get("value", true))}, "summary": "Отмечено: %s" % flag}
		"npc_discount", "npc_favor":  # what an NPC grants by words (v0.7.15.2)
			var npc_id := str(e.get("npc_id", ""))
			if not s.npcs_here(world.world, s.room_id).has(npc_id):
				return {"reason": "NPC %s нет в этой комнате" % npc_id}
			var won := (_won_over.get(turn_id, []) as Array).has(npc_id)
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == e["kind"] and str(p["plan"].get("discount", p["plan"].get("favor", ""))) == npc_id):
				return {"reason": "это уже есть в этом ходе"}
			if str(e["kind"]) == "npc_discount":
				return SocialRules.plan_discount(s, data, npc_id, int(e.get("percent", 0)), won)
			return SocialRules.plan_favor(s, data, npc_id, str(e.get("service", "")), str(e.get("item_id", "")) if e.get("item_id") != null else "", won)
		"npc_follow":  # an NPC goes with the hero, or stays (v0.7.20.3)
			var fid := str(e.get("npc_id", ""))
			if pending.any(func(p: Dictionary) -> bool: return str(p["plan"].get("follow_npc", "")) == fid):
				return {"reason": "это уже есть в этом ходе"}
			return FollowRules.plan(s, data, fid, bool(e.get("follow", true)), bool(e.get("home", false)),
				(_won_over.get(turn_id, []) as Array).has(fid))
		"reputation":  # the place learned of a deed of the hero (v0.7.17)
			return ReputationRules.plan(s, data, int(e.get("delta", 0)), str(e.get("reason", "")), pending)
		"reveal_secret":  # the NPC tells a secret of its own by goodwill (v0.7.15.3)
			var who := str(e.get("npc_id", ""))
			if not s.npcs_here(world.world, s.room_id).has(who):
				return {"reason": "NPC %s нет в этой комнате" % who}
			return SocialRules.plan_secret(s, data, who, str(e.get("secret_id", "")))
		"accept_quest":  # the hero takes a quest the NPC offers by words, like the button (v0.7.15.2)
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
		"crime_known":  # the hero confessed or was exposed (v0.7.14)
			return CrimeRules.plan_reveal(s, data, str(e.get("victim_id", "")))
		"crime_release":  # the guard lets the hero go by words after a passed check (v0.7.22.2)
			return CrimeRules.plan_release(s, data, _won.get(turn_id, []))
		"owner":  # a prisoner sold or let go, a thing given up by its owner (v0.7.22.17)
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "owner"):
				return {"reason": "одна смена хозяина за ход"}
			return OwnerRules.plan(s, data, e)
		"note":
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
		"equip":
			return _plan_equip(s, data, e)
	return {"reason": "движок не знает эффект %s" % e.get("kind", "?")}


## A condition on the hero by the master (v0.7.8, «Правила 5e: состояния»): with a reason, a save the engine rolls
## (an ability and a DC tier; the tag gives race traits their advantage or immunity) and a duration from the list.
## Without a save — only when the hero brought it on themselves this turn (`cause: player`: drank, lay down). An
## incapacitating condition out of a fight needs an end in time (the engine lets the time pass). `on: false` lifts
## it (exhaustion — one level).
func _plan_condition(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var c := s.character
	var cond := str(e.get("condition", ""))
	if e.get("target_id") != null and not str(e.get("target_id", "")).is_empty():
		return {"reason": "вне боя target_id не нужен: состояние ложится на героя; что случилось с NPC — опиши словами"}
	if not ConditionRules.known(data, cond):
		return {"reason": "неизвестное состояние %s; есть: %s" % [cond, ", ".join((rules["conditions"] as Dictionary).keys())]}
	var title := ConditionRules.name_of(data, cond)
	if not bool(e.get("on", true)):
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
		if not by_player:
			return {"reason": "состояние на героя — со спасброском (save {ability, dc_tier} и tag); без него — только если герой сам навлёк его своими словами в этом ходе (cause: player)"}
		if not player_turns.has(turn_id):
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
		var dc := int(rules["dc_tiers"][tier])
		var r := HeroDefense.save(s, data, ab, dc, tag)
		if bool(r["ok"]):
			return {"plan": {"condition": cond, "on": true, "resisted": true}, "summary": "%s: устоял — спасбросок %s" % [title, r["text"]]}
		if bool(e.get("repeat_save", false)):
			plan["save"] = {"ability": ab, "dc": dc, "tag": tag, "repeat": true}
		return {"plan": plan, "summary": "%s (%s, %s) — спасбросок %s" % [title, dur_text, reason, r["text"]]}
	return {"plan": plan, "summary": "%s (%s, %s)" % [title, dur_text, reason]}


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
	return {"plan": {"slots": [slot], "item_id": id}, "summary": "Надето: %s" % ItemRules.display_name(data["items"], s.items, id)}


## Opening a locked container by words (v0.7.18.1): a key the hero carries, or a check of this turn that beat the lock
## (Sleight of Hand with thieves' tools — `pick`, Athletics — `force`, it breaks).
func _plan_unlock(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary) -> Dictionary:
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


func _plan_give(s: GameSession, items: Dictionary, rules: Dictionary, turn_id: String, e: Dictionary, level: int) -> Dictionary:
	var qty := int(e.get("qty", 1))
	var id := str(e.get("item_id", "")) if e.get("item_id") != null else ""
	var new_def := {}
	if e.get("item") is Dictionary:
		if not searched.has(turn_id):
			return {"reason": "сначала найди похожие предметы через find_items"}
		var chk := ItemRules.check_generated(items, e["item"], level, _data.get("spells", {}))
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
	var c := s.character
	if plan.has("foe"):
		var f := CombatRules.fighter(s, str(plan["foe"]))
		if kind == "damage":
			var tmp: Array[String] = []
			CombatRules._hurt_enemy(s, _data, f, int(plan["amount"]), tmp)
		elif bool(plan.get("on", true)):
			CombatRules._hold(f, str(plan["condition"]))
		else:
			(f["conditions"] as Array).erase(str(plan["condition"]))
		return
	if plan.has("victim"):  # crime_known (v0.7.14)
		_extra_lines.append_array(CrimeRules.reveal(s, _data, str(plan["victim"])))
		return
	if kind == "owner":  # owner (v0.7.22.17)
		_extra_lines.append_array(OwnerRules.apply(s, _data, plan))
		return
	if plan.has("crime_release"):  # crime_release (v0.7.22.2)
		_extra_lines.append_array(CrimeRules.let_go(s, _data, "Стража отпускает героя — но розыск не снят"))
		return
	if plan.has("text") and plan.has("npc_id"):  # note about an NPC (v0.7.15)
		s.remember(str(plan["npc_id"]), str(plan["text"]))
		return
	if plan.has("text"):  # note (v0.7.4)
		s.notes.append({"day": s.day, "clock": TimeRules.clock(s), "room": s.room_id, "text": str(plan["text"])})
		return
	if plan.has("slots"):  # equip (v0.7.4); time and the turn's economy (v0.7.7)
		var before: Dictionary = (s.character["equipped"] as Dictionary).duplicate()
		for sl: Variant in plan["slots"]:
			s.character["equipped"][str(sl)] = str(plan["item_id"])
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
		return
	if plan.has("reputation"):  # reputation (v0.7.17)
		_extra_lines.append_array(ReputationRules.add(s, _data, str(plan["reputation"]), int(plan["delta"]), str(plan["why"])))
		return
	if plan.has("secret"):  # reveal_secret (v0.7.15.3)
		for sec: Dictionary in SocialRules.secrets(_data, str(plan["secret_npc"])):
			if str(sec["id"]) == str(plan["secret"]):
				SocialRules.tell(s, _data, str(plan["secret_npc"]), sec)
		_extra_lines.append_array(QuestRules.advance(s, _data))
		return
	if plan.has("goal_scale"):  # goal_assess (v0.7.22)
		GoalRules.apply_assess(c, plan)
		return
	if plan.has("goal_hint"):  # goal_hint (v0.7.22.1)
		GoalRules.apply_hint(c)
		return
	if plan.has("follow_npc"):  # npc_follow (v0.7.20.3)
		FollowRules.apply(s, plan)
		return
	if plan.has("discount"):  # npc_discount (v0.7.15.2)
		SocialRules.grant_discount(s, _data, plan)
		return
	if plan.has("favor"):  # npc_favor (v0.7.15.2)
		_extra_lines.append_array(SocialRules.grant_favor(s, _data, plan))
		return
	if plan.has("quest_accept"):  # a quest thing given by words takes the quest (v0.7.2)
		_extra_lines.append_array(QuestRules.accept(s, _data, str(plan["quest_accept"])).slice(1))
		return
	if plan.has("quest_talk"):  # a quest thing handed over by words closes the talk step
		_extra_lines.append_array(QuestRules.talk(s, _data, str(plan["quest_talk"])).slice(1))
		return
	match kind:
		"move":
			s.room_id = plan["room_id"]
			if bool(plan.get("escort", false)):
				s.arrest = s.room_id  # the hold goes along with the guard
			for n: Variant in plan.get("with", []):
				FollowRules.apply(s, {"follow_npc": str(n), "on": true, "room": ""})
		"damage":
			c["hp"] = maxi(0, int(c["hp"]) - int(plan["amount"]))
			_extra_lines.append_array(HeroDefense.after_damage(s, _data, int(plan["amount"])))
			HeroDefense.relentless(s, _data, _extra_lines)
		"heal":
			c["hp"] = mini(int(c["max_hp"]), int(c["hp"]) + int(plan["amount"]))
		"coins":
			c["gold_cp"] = int(c["gold_cp"]) + int(plan["delta"])
		"give_item":
			if plan.has("def"):
				s.items[plan["item_id"]] = plan["def"]
			ItemRules.found(c, _data, s.items, str(plan["item_id"]), int(plan["qty"]))
		"take_item":
			var left := int(c["inventory"].get(plan["item_id"], 0)) - int(plan["qty"])
			if left > 0:
				c["inventory"][plan["item_id"]] = left
			else:
				c["inventory"].erase(plan["item_id"])
		"npc_attitude":
			s.shift_attitude(str(plan["npc_id"]), int(plan["delta"]), _data)
		"start_combat":
			if bool(plan.get("reinforce", false)) and CombatRules.active(s):
				CombatRules.add_incoming(s, _data, plan["foes"], int(s.combat["round"]) + int(CombatRules.cfg(_data)["reinforce_delay"]), str(plan["side"]))
			else:
				s.pending_fight = plan["foes"]
		"cast":
			SpellRules.cast(c, _data, plan["spell_id"], int(plan["slot"]), s)
			var cure: Dictionary = _data["rules"]["hero_effects"]["spell_cures"].get(str(plan["spell_id"]), {})
			if bool(plan.get("on_self", false)) and not cure.is_empty():
				_extra_lines.append_array(ConditionRules.cure(s, _data, cure, {"kind": "spell", "id": str(plan["spell_id"]),
					"name": SpellRules.s_name(_data, str(plan["spell_id"]))}))
		"condition":
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
		"use_feature":
			FeatureUses.use(c, _data, plan["id"], int(plan["amount"]), s.rng)
		"use_item":
			ItemRules.use(c, _data, s.items, plan["item_id"], s.rng, s)
		"advance_time":
			_extra_lines.append_array(TimeRules.advance(s, _data, int(plan["minutes"])))
		"furnish":
			PropRules.apply_furnish(s, plan)
		"take_prop":
			_extra_lines.append_array(PropRules.apply_take(s, _data, plan))
		"take_from":
			_extra_lines.append_array(ContainerRules.apply_take(s, _data, plan))
		"put_in":
			ContainerRules.apply_put(s, _data, plan)
		"drop_item":
			ContainerRules.apply_drop(s, _data, plan)
		"create_npc":
			_extra_lines.append("[%s]" % WorldGen.apply_npc(s, _data, plan))
		"create_quest":
			var qid := QuestGen.apply_quest(s, _data, plan)
			_extra_lines.append("[%s]" % qid)
			if bool(plan["quest"].get("own", false)):  # one's own deed is taken at once (v0.7.21.2)
				s.quests_active[qid] = 0
				_extra_lines.append("Своё дело: %s · Цель: %s" % [plan["quest"]["title"], plan["quest"]["steps"][0]["text"]])
				_extra_lines.append_array(QuestRules.advance(s, _data))
		"create_place":
			_extra_lines.append("выход: [%s]" % WorldGen.apply_place(s, _data, plan))
		"unlock":
			_extra_lines.append_array(ContainerRules.unlock(PropRules.find(s, str(plan["room"]), str(plan["prop"])), str(plan["how"])))
		"prop_state":
			PropRules.apply_state(s, plan)
		"flag":
			if bool(plan["value"]) and not s.flags.has(plan["flag"]):
				s.flags.append(plan["flag"])
			elif not bool(plan["value"]):
				s.flags.erase(plan["flag"])


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
		if p["kind"] == "take_item" and p["plan"]["item_id"] == id:
			sum += int(p["plan"]["qty"])
	return sum


static func _duration(mins: int) -> String:
	if mins < 60:
		return "%d мин" % mins
	return "%d ч%s" % [mins / 60, (" %d мин" % (mins % 60)) if mins % 60 > 0 else ""]

