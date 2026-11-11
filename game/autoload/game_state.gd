extends Node
## The current session and the turn loop (ADR-0009): player input → turn.request with a snapshot →
## engine.* callbacks (checks, effect reserves, lookup, item search) → turn.result → apply listed reserves.
## Modes: exploration, social and trade with an NPC of the room. One turn at a time.
## Deterministic moves (exits, talking to an NPC, leaving a conversation) do not ask the model to decide.

var session: GameSession
## turn_id of the turn in flight, "" when idle.
var busy_turn: String = ""
var drawing := false  ## the brush waits for a frame (v0.7.35)
var effects := EffectEngine.new()

## Enemy turns of a fight are being played out (with a pause per line).
var combat_playing: bool = false
## Seconds between enemy lines; 0 in tests (LaunchArgs --combat-delay).
var combat_delay: float = 0.6
var instant_walk := false  # a walk on the map ends at once: the playtests
const COMBAT_SAVE := "autosave_combat"

var _last_kind: String = ""
var _last_input: String = ""
var _letter_tried: String = ""  # the letter whose reply turn ran last (v0.7.48)
## The spell, feature or consumable pinned to the next message at the input field (roadmap v0.7.7, the author's
## request): {kind, id, slot, target} or {}. The engine spends it when the message goes, and the master gets the
## cast and the player's intent in one turn. Not saved.
var attached: Dictionary = {}
## The check the player picked for the next message (v0.7.36): {skill} or {ability}; the engine rolls every check of
## that turn by it, whatever skill the master asks for. `_forced` — the one of the turn sent ({…, input, turn}).
var pinned_check: Dictionary = {}
var _forced: Dictionary = {}
## The character before an attached spend: back if that turn fails to reach the master (the slot is returned).
var _refund: Dictionary = {}
var _refund_what: Dictionary = {}  # the attachment spent then
var _retry_spend: Dictionary = {}  # an attachment given back by a failed turn: «Повторить» spends it again
## A combat spell pinned to words aimed at an NPC (v0.7.7, as in BG3): if that turn starts the fight, the hero
## strikes first with it, the NPC caught off guard. {spell, slot, npc_id} or {}.
var _opening: Dictionary = {}
## The second line (v0.8.4.25): turn_id → the job the master readies ahead beside the player's turns; the day the
## server kept the rest of the daily limit for the player's turns — nothing more is readied that day.
var _ahead: Dictionary = {}
var _ahead_stop := -1
var _ahead_n := 0  # its own ids, b-N: the session's turn counter counts the player's turns only
var _act_told: Dictionary = {}  # «the master builds the next act» said once per act (v0.8.4.30)
var _build_tally: Dictionary = {}  # parts built or taken while the build screen is open: one line when it closes (v0.8.4.42.7)


func has_session() -> bool:
	return session != null


## No turn is going: the game can take a new deed.
func _idle() -> bool:
	return session != null and not is_busy()


func _out_of_fight() -> bool:
	return _idle() and session.mode != GameSession.MODE_COMBAT


## Out of a fight and of a conversation.
func _at_leisure() -> bool:
	return _out_of_fight() and not session.in_conversation()


## A deed the master tells of needs the server.
func _master_ready() -> bool:
	return _idle() and Backend.is_ready()


func is_busy() -> bool:
	return not busy_turn.is_empty() or combat_playing


func world() -> WorldView:
	return WorldView.new(Catalog.data["world"])


## A new game: `settings` from the new game screen (world pack and master settings; {} = the active world's
## defaults) and a built character ({} = the world's first ready-made character).
func new_game(character: Dictionary = {}, settings: Dictionary = {}, game_seed: int = -1) -> void:
	if game_seed < 0:
		game_seed = GameSession.seed_of(settings.get("seed", LaunchArgs.value("--seed", str(randi()))))
	if settings.has("world"):
		Catalog.activate(str(settings["world"]))
	if settings.is_empty():
		settings = WorldPack.default_settings(Catalog.data["pack"])
	if character.is_empty():
		character = CharacterBuilder.build_preset(Catalog.data["presets"][0], Catalog.data)
	var s := GameSession.create(game_seed, Time.get_datetime_string_from_system(), world().start_room(), character)
	s.world_id = Catalog.active_world
	s.world_version = str(Catalog.data["pack"].get("version", ""))
	s.settings = settings.duplicate(true)
	s.settings["world"] = Catalog.active_world
	s.settings.erase("seed")  # the game's own, not a setting for the master
	BackgroundRules.apply_ties(s, Catalog.data)  # the people of the hero's past (v0.7.11)
	PetRules.seed(s, Catalog.data, s.room_id)  # the start room's wild beasts (v0.7.43)
	start(s)
	TimeRules.settle(s, Catalog.data)  # a festival and the weather of the first day (v0.7.44, v0.7.46)
	RumorRules.seed(s, Catalog.data)  # the pack's talk (v0.7.47)
	_request("enter", "")


## Long rest (ADR-0010 §6): in a safe room outside a conversation with the price paid, or — v0.7.8, the author: «as in
## Baldur's Gate» — a camp anywhere safe for `supplies` {item_id: qty} of food from the pack. The engine restores the
## character, clears the check locks and all exhaustion, then the master describes the morning (kind=rest).
## `prepared` — the spells of tomorrow picked in the same window (v0.8.4.4).
func long_rest(supplies: Dictionary = {}, prepared: Array = []) -> String:
	if not _master_ready():
		return "REST_BUSY"
	var why := ExplorationRules.can_rest(session, Catalog.data["world"], Catalog.data) if supplies.is_empty() \
		else ExplorationRules.camp_error(session, Catalog.data, supplies)
	if not why.is_empty():
		return why
	var lines := ExplorationRules.long_rest(session, Catalog.data, supplies)  # the night, the morning and the world's hooks in it
	lines.append_array(SpellRules.rested(session.character, Catalog.data, prepared))  # the rest gave the right to prepare
	_refresh()
	_effect_lines(lines)
	_request("rest", "")
	return ""


## Trade panel (roadmap v0.5.3): the engine checks both purses and stocks and makes the deal at once, then the
## master narrates it (kind=deal, the deal lines as input). Returns the quote; its `error` is "" on success.
func deal(cart: Dictionary) -> Dictionary:
	if session == null or is_busy() or not Backend.is_ready() or session.mode != GameSession.MODE_TRADE:
		return {"error": "TRADE_ERR_BUSY", "args": {}}
	var q := TradeRules.quote(session, Catalog.data, session.npc_id, cart)
	if not str(q["error"]).is_empty():
		return q
	var lines := TradeRules.execute(session, Catalog.data, session.npc_id, cart)
	_refresh()
	_add(GameSession.effect_entry(lines))
	_log("Сделка: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("deal", TradeRules.deal_note(lines, int(q["net_cp"])))
	return q


## Haggle button: a Persuasion or Deception check (the better one) against the DC of the merchant's attitude;
## the master plays the merchant's reaction (kind=haggle). "" on success or a localization key.
func haggle() -> String:
	if session == null or is_busy() or not Backend.is_ready() or session.mode != GameSession.MODE_TRADE:
		return "TRADE_ERR_BUSY"
	var why := TradeRules.can_haggle(session, Catalog.data, session.npc_id)
	if not why.is_empty():
		return why
	var params := {"skill": TradeRules.best_skill(session, Catalog.data), "dc_tier": "medium", "target_id": session.npc_id}
	var result := _haggle_check(params)
	EventBus.state_changed.emit()
	_request("haggle", str(result["note"]))
	return ""


## Switches a conversation with a trader between talk and the deal panel without a turn: the master's options
## stay as they are (B33), the next turn's snapshot carries the new mode.
## Follow a quest: its step goes over the chat (v0.7.22.32, П11).
func track_quest(quest_id: String) -> void:
	if session == null:
		return
	session.tracked_quest = quest_id
	EventBus.state_changed.emit()


func set_trade(on: bool) -> bool:
	if session == null or is_busy() or not session.in_conversation():
		return false
	if on and (not world().is_trader(session.npc_id) or TimeRules.shops_closed(session, Catalog.data) or TheftRules.shop_closed_for(session, session.npc_id, Catalog.data)):
		return false
	var mode := GameSession.MODE_TRADE if on else GameSession.MODE_SOCIAL
	if session.mode == mode:
		return false
	session.mode = mode
	EventBus.state_changed.emit()
	return true


## Quest button (XpRules): the engine completes a pack quest in its room — reward and experience — then the
## master narrates it (kind=quest, the quest's done_text and the reward as input). "" or a localization key.
func complete_quest(quest_id: String) -> String:
	if not _master_ready():
		return "QUEST_BUSY"
	var why := XpRules.can_complete(session, Catalog.data["world"], quest_id)
	if not why.is_empty():
		return why
	var lines := XpRules.complete(session, Catalog.data, quest_id)
	_effect_lines(lines)
	var q: Dictionary = XpRules.quests(Catalog.data["world"])[quest_id]
	var reward := lines.slice(1).filter(func(l: String) -> bool: return not l.begins_with("можно"))
	_request("quest", "%s Награда: %s." % [q["done_text"], ", ".join(reward)])
	return ""


## Level-up screen (LevelUp): applies the next level with the player's picks. Not while the master thinks:
## the snapshot of the turn in flight would no longer match. "" or a localization key.
func level_up(picks: Dictionary) -> String:
	if not _idle():
		return "LVL_ERR_BUSY"
	var errs := LevelUp.errors(session.character, Catalog.data, picks)
	if not errs.is_empty():
		return errs[0]
	var lines := LevelUp.apply(session.character, Catalog.data, picks, session.items)
	_effect_lines(lines, true)
	return ""


## «Колдовать» on the sheet (SpellRules): the engine checks and spends the slot, the master narrates the cast
## (kind=ability). `slot` 0 = the lowest fitting one. "" or a reason for the toast.
func cast(spell_id: String, slot: int = 0) -> String:
	return _use_alone({"kind": "spell", "id": spell_id, "slot": slot})


## «Использовать» a feature with limited uses on the sheet (Stock). "" or a reason.
func use_feature(resource_id: String) -> String:
	return _use_alone({"kind": "feature", "id": resource_id})


## «Использовать» an item on the sheet (ItemRules consumables). "" or a reason.
func use_item(item_id: String) -> String:
	return _use_alone({"kind": "item", "id": item_id})


func _use_alone(what: Dictionary) -> String:
	if not _master_ready():
		return tr("ABILITY_BUSY")
	var spent := _spend(what)
	if spent.has("reason"):
		return str(spent["reason"])
	_ability(spent["lines"], str(spent["facts"]))
	return ""


const SELF_TARGET := "self"


## Who a spell of the hero's side lands on: the ids picked ({SELF_TARGET} — the hero), at most its number of targets.
func _friend_targets(what: Dictionary, spell_id: String) -> Array[String]:
	var out: Array[String] = []
	if str(what.get("kind", "")) != "spell" or not SpellEffects.picks_side(Catalog.data, spell_id) in ["friend", "any"]:
		return out
	var picked: Array = what.get("targets", [])
	if picked.is_empty() and not str(what.get("target", "")).is_empty():
		picked = [what["target"]]
	var n := SpellEffects.picks_count(Catalog.data, spell_id, int(what.get("slot", 0)))
	for id: Variant in picked.slice(0, n):
		out.append(str(id))
	return out


## A spell, a feature use or a consumable checked and spent by the engine (v0.7.7: shared by the sheet buttons and
## the attachment at the input field): {"lines", "facts"} or {"reason"}. `what`: {kind spell|feature|item, id,
## slot (spells, 0 = the lowest fitting), target (an NPC id of the scene, optional)}.
func _spend(what: Dictionary) -> Dictionary:
	var c := session.character
	var id := str(what.get("id", ""))
	var lines: Array[String] = []
	var facts := ""
	match str(what.get("kind", "")):
		"spell":
			var chk := SpellRules.check(c, Catalog.data, id, int(what.get("slot", 0)))
			if chk.has("reason"):
				return {"reason": str(chk["reason"])}
			var friends := _friend_targets(what, str(chk["spell_id"]))  # v0.7.50.1: the NPCs and the hero picked for it
			lines = SpellRules.cast(c, Catalog.data, chk["spell_id"], int(chk["slot"]), session,
				str(what.get("target", "")).is_empty() and friends.is_empty() or friends.has(SELF_TARGET))
			for npc: String in friends:
				if npc != SELF_TARGET:
					lines.append_array(AllyRules.cast_on_npc(session, Catalog.data, str(chk["spell_id"]), int(chk["slot"]), npc))
			if not friends.is_empty() and not friends.has(SELF_TARGET) and (Catalog.data["rules"]["invisibility"]["spells"] as Dictionary).has(str(chk["spell_id"])):
				c["invisible_others"] = true
			lines.append_array(AllyRules.expire(session))  # a new concentration lets the old summons go (v0.7.22.22)
			lines.append_array(AllyRules.summon(session, Catalog.data, str(chk["spell_id"])))
			what["spent_slot"] = int(chk["slot"])
			facts = "Игрок колдует " + SpellRules.describe(Catalog.data, chk["spell_id"], int(chk["slot"])) + \
				". Движок уже потратил ячейку — не вызывай cast сам; опиши, как это выглядит и что происходит."
			if lines.size() > 1:  # what the engine did with the spell (v0.7.13.8: found traps, light, the hero's numbers)
				facts += " Движок: %s — опиши это, ничего не добавляя." % ", ".join(lines.slice(1))
			var target := str(what.get("target", ""))
			var cure: Dictionary = Catalog.data["rules"]["hero_effects"]["spell_cures"].get(str(chk["spell_id"]), {})
			if not target.is_empty() and (cure.get("cure", []) as Array).has("disease"):  # a sick NPC healed (v0.7.39)
				var healed := DiseaseRules.cure_npc(session, Catalog.data, target, "magic")
				lines.append_array(healed)
				if not healed.is_empty():
					facts += " Движок: %s — опиши это." % ", ".join(healed)
			var npc_try := SpellEffects.npc_save(session, Catalog.data, str(chk["spell_id"]), target)
			if not npc_try.is_empty():  # Suggestion, Charm Person… (v0.7.13.7): the engine rolls the NPC's save
				lines.append(str(npc_try["line"]))
				if bool(npc_try["ok"]):
					SpellEffects.charm_npc(session, Catalog.data, str(chk["spell_id"]), str(what.get("target", "")))  # v0.7.22.3: it lasts, then ends
				facts += " Движок бросил спасбросок цели: %s. %s" % [npc_try["line"], "Заклинание действует — отыграй это по его описанию." if bool(npc_try["ok"]) \
					else "Заклинание не подействовало — цель может заметить попытку."]
		"feature":
			var why := Stock.can_use(c, Catalog.data, id, 1)
			if not why.is_empty():
				return {"reason": why}
			lines = Stock.use(c, Catalog.data, id, 1, session.rng, session)
			facts = "Игрок использует умение «%s». Движок уже учёл использование: %s. Опиши, как это выглядит." % \
				[Stock.display_name(c, Catalog.data, id), ", ".join(lines)]
		"item":
			var why := ItemRules.can_use(c, Catalog.data, session.items, id)
			if not why.is_empty():
				return {"reason": why}
			lines = ItemRules.use(c, Catalog.data, session.items, id, session.rng, session)
			facts = "Игрок использует предмет. Движок уже применил: %s. Опиши коротко." % ", ".join(lines)
		"feature_note":
			var f: Dictionary = Catalog.data["classes"]["features"].get(id, Catalog.data["races"]["traits"].get(id, {}))
			lines = ["Умение: %s" % f.get("name", id)]
			facts = "Игрок пускает в ход умение «%s» (%s). Движок его не считает: реши исход по правилам — проверкой engine.check, если нужна." % \
				[f.get("name", id), str(f.get("desc", "")).left(240)]
		"item_note":
			if int(c.get("inventory", {}).get(id, 0)) <= 0:
				return {"reason": "EQUIP_NOT_OWNED"}
			var nm := ItemRules.display_name(Catalog.data["items"], session.items, id)
			lines = ["Предмет: %s" % nm]
			facts = "Игрок пускает в ход предмет «%s» [%s] из своего снаряжения. Опиши по правилам; трата или потеря — эффектом." % [nm, id]
		_:
			return {"reason": "ABILITY_BUSY"}
	var target := str(what.get("target", ""))
	if not target.is_empty():
		facts += " Цель — %s [%s]." % [world().npc(target).get("name", target), target]
	CharacterRules.refresh(c, Catalog.data, session.items)
	return {"lines": lines, "facts": facts}


func _ability(lines: Array[String], facts: String) -> void:
	_effect_lines(lines)
	_request("ability", facts)


func attach(kind: String, id: String, slot: int = 0, target: String = "") -> void:
	attached = {"kind": kind, "id": id, "slot": slot, "target": target}
	EventBus.state_changed.emit()


func detach() -> void:
	attached = {}
	EventBus.state_changed.emit()


func pin_check(kind: String, id: String) -> void:
	pinned_check = {kind: id}
	EventBus.state_changed.emit()


func unpin_check() -> void:
	pinned_check = {}
	EventBus.state_changed.emit()


## The checks the player may pin: skills by name, then bare abilities — [{kind skill|ability, id, name, bonus, prof}].
func check_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if session == null:
		return out
	var c := session.character
	for id: String in Catalog.rules()["skills"]:
		out.append({"kind": "skill", "id": id, "name": tr("SKILL_" + id.to_upper()), "bonus": int(c.get("skills", {}).get(id, 0)),
			"prof": (c.get("skill_profs", []) as Array).has(id) or (c.get("expertise", []) as Array).has(id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	for ab: Variant in Catalog.rules()["saves"]:
		out.append({"kind": "ability", "id": str(ab), "name": tr("ABILITY_" + str(ab).to_upper()),
			"bonus": CharacterRules.ability_check_bonus(c, Catalog.data, str(ab)), "prof": false})
	return out


## «Атлетика +5» for the menu and the chip.
static func check_label(ch: Dictionary) -> String:
	return "%s %+d" % [ch["name"], int(ch["bonus"])]


## The master's note for a pinned check, after the player's words.
func _pinned_note(pin: Dictionary) -> String:
	return " [Игрок сам выбрал проверку: %s. Проверка обязательна — вызови request_check; движок бросит её этим, какой бы навык ты ни указал. Ты выбираешь только сложность: чем невозможнее действие или твёрже отказ NPC, тем выше, вплоть до nearly_impossible. Согласие NPC на близость кубиком не решается: успех смягчает отказ, но согласием не становится.]" % _pin_name(pin)


static func _pin_name(pin: Dictionary) -> String:
	return TranslationServer.translate("SKILL_" + str(pin["skill"]).to_upper()) if pin.has("skill") \
		else TranslationServer.translate("ABILITY_" + str(pin["ability"]).to_upper())


## What can be pinned now (v0.7.7 fixes: everything, not only spells): [{kind, id, name, slots [circles], off}].
## spell — ready spells (`off` when no slot is left); feature — uses that the engine spends; feature_note — any other
## feature or trait of the hero; item — consumables the engine uses; item_note — any other thing in the pack.
func attach_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if session == null:
		return out
	var c := session.character
	var data: Dictionary = Catalog.data
	for sid: Variant in SpellRules.ready(c):
		var lv := SpellRules.level_of(data, str(sid))
		var slots: Array[int] = []
		for circle in range(maxi(1, lv), 6):
			if lv > 0 and SpellRules.slots_left(c, circle) > 0:
				slots.append(circle)
		out.append({"kind": "spell", "id": str(sid), "name": str(data["spells"][str(sid)]["name"]), "slots": slots, "off": lv > 0 and slots.is_empty()})
	var with_uses: Array[String] = []
	for r: Dictionary in Stock.lines(c, data):
		out.append({"kind": "feature", "id": str(r["id"]), "name": "%s (%d/%d)" % [r["name"], int(r["left"]), int(r["max"])], "slots": [], "off": int(r["left"]) <= 0})
		for f: Variant in data["rules"]["resources"].get(str(r["id"]), {}).get("features", []):
			with_uses.append(str(f))
	for pool: Array in [[c.get("features", []), data["classes"]["features"]], [c.get("traits", []), data["races"]["traits"]]]:
		for fid: Variant in pool[0]:
			var f: Dictionary = (pool[1] as Dictionary).get(str(fid), {})
			if f.is_empty() or with_uses.has(str(fid)) or f.has("options") or _quiet_feature(str(fid)):
				continue
			out.append({"kind": "feature_note", "id": str(fid), "name": str(f["name"]), "slots": [], "off": false})
	for iid: String in c.get("inventory", {}):
		var usable := not ItemRules.consumable(data, iid, session.items).is_empty()
		out.append({"kind": "item" if usable else "item_note", "id": iid,
			"name": "%s ×%d" % [ItemRules.display_name(data["items"], session.items, iid), int(c["inventory"][iid])], "slots": [],
			"off": usable and not ItemRules.can_use(c, data, session.items, iid).is_empty()})  # off the belt (v0.8.4.24)
	return out


## Features that are bookkeeping, not something to use: spellcasting, ability increases, the choice of a subclass.
static func _quiet_feature(id: String) -> bool:
	return id.begins_with("spellcasting") or id.contains("ability_score_improvement") or id.ends_with("_expertise_1") or id in [
		"bonus_cantrip", "bonus_proficiency", "bonus_proficiencies", "arcane_tradition", "bard_college", "divine_domain", "druid_circle",
		"martial_archetype", "monastic_tradition", "otherworldly_patron", "primal_path", "ranger_archetype", "roguish_archetype",
		"sacred_oath", "sorcerous_origin", "fighter_fighting_style", "ranger_fighting_style", "paladin_fighting_style", "pact_magic"]


## Attunement (v0.7.12): an hour with the thing out of a fight, no master turn; the line goes to the history. "" or a key.
func attune(item_id: String) -> String:
	if not _idle():
		return "EQUIP_BUSY"
	if CombatRules.active(session) or session.in_conversation():
		return "ATTUNE_NOT_NOW"
	var c := session.character
	var why := ItemRules.can_attune(c, Catalog.data, session.items, item_id)
	if not why.is_empty():
		return why
	var lines := ItemRules.attune(c, Catalog.data, session.items, item_id)
	lines.append("Настройка: %d мин" % int(ItemRules.cfg(Catalog.data)["attune_minutes"]))
	lines.append_array(TimeRules.advance(session, Catalog.data, int(ItemRules.cfg(Catalog.data)["attune_minutes"])))
	CharacterRules.refresh(c, Catalog.data, session.items)
	_effect_lines(lines, true)
	return ""


func unattune(item_id: String) -> String:
	if not _idle():
		return "EQUIP_BUSY"
	var why := ItemRules.can_unattune(session.character, Catalog.data, session.items, item_id)
	if not why.is_empty():
		return why
	ItemRules.unattune(session.character, item_id)
	_refresh()
	_effect_lines(["Настройка снята: " + ItemRules.display_name(Catalog.data["items"], session.items, item_id)], true)
	return ""


## «Собрать стрелы» after a fight (v0.7.12): each spent shot found by its chance (v0.8.4.30), a minute, here only. "" or a key.
func collect_ammo() -> String:
	if not _idle():
		return "EQUIP_BUSY"
	var left: Dictionary = session.character.get("ammo_left", {})
	if left.is_empty() or str(left.get("room", "")) != session.room_id or CombatRules.active(session):
		return "AMMO_NOTHING"
	_effect_lines(_gather_ammo(session), true)
	return ""


func _gather_ammo(s: GameSession) -> Array[String]:
	var left: Dictionary = s.character.get("ammo_left", {})
	var lines: Array[String] = []
	for id: String in left.get("items", {}):
		Gear.stow_ammo(s, Catalog.data, s.character, id, int(left["items"][id]))
		lines.append("Собрано: %s ×%d" % [ItemRules.display_name(Catalog.data["items"], s.items, id), int(left["items"][id])])
	s.character.erase("ammo_left")
	lines.append_array(TimeRules.advance(s, Catalog.data, int(ItemRules.cfg(Catalog.data)["collect_minutes"])))
	return lines


## A service of a person (v0.7.12; any person since v0.8.4.35): at the counter or under its row, out of a fight; `item` —
## what it acts on, the thing in the hand first by default. "" or a localization key.
func service(npc_id: String, id: String, item: String = "") -> String:
	if not _out_of_fight():
		return "EQUIP_BUSY"
	return _act("service", {"service": _row(ServiceRules.why, ServiceRules.buy, [session, Catalog.data, npc_id, id, item])})


## A spell cast into a thing that keeps spells (v0.8.4.36, a Ring of Spell Storing): its slot spent, out of a fight. "" or a key.
func store_spell(item: String, spell: String, circle: int) -> String:
	if not _out_of_fight():
		return "EQUIP_BUSY"
	return _act("store", {"store": _row(ItemRules.store_why, ItemRules.store_spell, [session, Catalog.data, item, spell, circle])})


## «Слухи» at an NPC (v0.7.47): what it knows and the hero has not heard, without the master. "" or a localization key.
func rumor_ask(npc_id: String) -> String:
	if not _idle():
		return "EQUIP_BUSY"
	var why := RumorRules.ask_why(session, Catalog.data, npc_id)
	if not why.is_empty():
		return why
	_effect_lines(RumorRules.ask(session, Catalog.data, npc_id), true)
	return ""


## «Письмо» at a person with a post (v0.7.48): the letter goes, the master answers on its reply day. "" or why not.
func send_letter(poster: String, to: String, purpose: String, text: String, way: String, extra: Dictionary = {}) -> String:
	if not _idle():
		return "EQUIP_BUSY"
	var why := LetterRules.send_why(session, Catalog.data, poster, to, purpose, text, way, extra)
	if not why.is_empty():
		return why
	_effect_lines(LetterRules.send(session, Catalog.data, poster, to, purpose, text, way, extra), true)
	_after_turn(session, "")
	return ""


## The shrine's acts (v0.7.49): service, donate, bless, vow (`arg` — its id), atone, convert. The engine's own, no
## master's turn; the time passes by rules.faith. "" or a localization key.
func faith_act(what: String, arg: String = "") -> String:
	if not _out_of_fight():
		return "EQUIP_BUSY"
	var data := Catalog.data
	var cfg := FaithRules.cfg(data)
	var a := [session, data]
	var timed := func(do: Callable, key: String) -> Array:
		var lines: Array = do.call()
		lines.append_array(TimeRules.advance(session, data, int(cfg[key]["minutes"])))
		return lines
	return _act(what, {
		"service": [FaithRules.service_why.bindv(a), timed.bind(FaithRules.service.bindv(a), "service")],
		"donate": _row(FaithRules.donate_why, FaithRules.donate, a),
		"bless": _row(FaithRules.bless_why, FaithRules.bless, a),
		"vow": _row(FaithRules.vow_why, FaithRules.take_vow, a + [arg]),
		"atone": [FaithRules.atone_why.bindv(a), timed.bind(FaithRules.atone.bindv(a), "atone")],
		"convert": [FaithRules.convert_why.bindv(a), timed.bind(FaithRules.convert.bindv(a), "convert")],
	}, "FAITH_NO_SHRINE")


## The board read (v0.7.47): its notices go to the journal, a notice with a place onto the map.
func read_notices() -> void:
	if session == null:
		return
	var ids := RumorRules.notices(session, Catalog.data).filter(func(r: Dictionary) -> bool:
		return not RumorRules.heard(session, str(r["id"]))).map(func(r: Dictionary) -> String: return str(r["id"]))
	if not ids.is_empty():
		_effect_lines(RumorRules.hear(session, Catalog.data, ids, "доска"), true)


## The name of the spell the hero concentrates on that this one would break (v0.7.13.1), or "".
func concentration_conflict(spell_id: String) -> String:
	if session == null or not bool(Catalog.data["spells"].get(spell_id, {}).get("concentration", false)):
		return ""
	var held := str(session.character.get("concentration", ""))
	return "" if held.is_empty() or held == spell_id else str(Catalog.data["spells"].get(held, {}).get("name", held))


## «Короткий отдых» (ExplorationRules): an hour, `dice` hit dice; no master turn — the line goes to the history.
func short_rest(dice: int) -> String:
	if not _idle():
		return "REST_BUSY"
	var why := ExplorationRules.can_short_rest(session, Catalog.data)
	if not why.is_empty():
		return why
	var lines := ExplorationRules.short_rest(session, Catalog.data, dice, session.rng)
	_refresh()
	lines.append_array(TimeRules.advance(session, Catalog.data, int(TimeRules.cfg(Catalog.data)["short_rest_minutes"])))
	_effect_lines(lines)
	if _exhaustion_death():
		return ""
	SaveManager.save_slot(SaveManager.AUTOSAVE, session)
	return ""


## Exhaustion 6 outside a fight (v0.7.8, 5e): the hero dies — the master's epitaph, then the death screen. True
## when it happened.
func _exhaustion_death() -> bool:
	if session == null or not ConditionRules.dead(session.character) or CombatRules.active(session):
		return false
	_request("death", "Герой умирает от истощения (шестая степень).\n" + _hero_path())
	return true


## The hero cannot act outside a fight (asleep, paralysed for a while — v0.7.8): the engine lets the time pass until
## the longest such effect ends. Lines.
func _sleep_through() -> Array[String]:
	var c := session.character
	var longest := 0
	for cond: String in ConditionRules.INCAPACITATING:
		for e: Dictionary in ConditionRules.effects_of(c, cond):
			longest = maxi(longest, ConditionRules.rounds_left(session, e))
	if longest <= 0:
		return []
	var minutes := ceili(longest / float(ConditionRules.ROUNDS_PER_MINUTE))
	var lines: Array[String] = ["Без чувств: " + TimeRules.span(minutes)]
	lines.append_array(TimeRules.advance(session, Catalog.data, minutes))
	return lines


## The prepared spells (SpellRules): once after each long rest. "" or a localization key.
func prepare_spells(ids: Array) -> String:
	if not _idle():
		return "PREP_BUSY"
	var why := SpellRules.prepare_error(session.character, Catalog.data, ids)
	if not why.is_empty():
		return why
	SpellRules.prepare(session.character, ids)
	_add(GameSession.effect_entry(["Подготовлены заклинания: %d" % ids.size()]))
	EventBus.state_changed.emit()
	return ""


# --- combat (v0.6.1, CombatRules) ---------------------------------------------------------------


## Starts a fight: an autosave to come back to, the combat screen, the master describes the start.
func start_combat(foes: Array, source: Dictionary = {}) -> void:
	if session == null:
		return
	_end_conversation()
	combat_delay = float(LaunchArgs.value("--combat-delay", str(SaveManager.combat_delay())))
	session.fight_on_load = {"foes": foes.duplicate(true), "source": source.duplicate(true)}
	SaveManager.save_slot(COMBAT_SAVE, session)  # loading it starts this fight again (a lost fight is not skipped)
	session.fight_on_load = {}
	var lines := CombatRules.start(session, Catalog.data, foes, source)
	lines.append_array(_opening_strike(source.get("opening", {})))
	session.mode = GameSession.MODE_COMBAT
	session.npc_id = ""
	session.combat["start_lines"] = lines  # shown after the master's description (playtest-1: the order)
	EventBus.state_changed.emit()
	_request("combat_start", "\n".join(lines))


## The pinned spell that started the fight lands first (v0.7.7): its slot was spent with the words, so it is given
## back and spent again by the combat cast — on that NPC, now caught off guard. Lines.
func _opening_strike(opening: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if opening.is_empty() or not opening.has("spell"):  # the button or a weapon: the hero strikes by the combat buttons
		return lines
	var data: Dictionary = Catalog.data
	var target := CombatRules.fighter_of_npc(session, str(opening["npc_id"]))
	var spell := str(opening["spell"])
	var slot := int(opening.get("slot", 0))
	if target.is_empty():
		return lines
	if slot > 0:
		Stock.give(session.character, "slot_%d" % slot)
	var how := {"spell": spell, "slot": slot}
	var why := Acts.one("cast").can(session, data, CombatRules.player(session), target, how)
	if not why.is_empty():
		lines.append("%s не удаётся: %s — ячейка не потрачена" % [data["spells"][spell]["name"], tr(why)])
		return lines
	lines.append_array(Acts.one("cast").go(session, data, CombatRules.player(session), target, how))
	return lines


## The engine lines of the fight's start go to the combat log once the master has described the scene.
func _show_start_lines() -> void:
	if session == null or not CombatRules.active(session) or not session.combat.has("start_lines"):
		return
	var lines: Array[String] = []
	for l: Variant in session.combat["start_lines"]:
		lines.append(str(l))
	session.combat.erase("start_lines")
	EventBus.combat_lines.emit(lines)


func _start_pending_fight() -> void:
	var foes := session.pending_fight.duplicate(true)
	session.pending_fight = []
	var help := CrimeRules.defenders(session, Catalog.data, foes)  # v0.7.22.18: the room stands up for the NPC
	if not help.is_empty():
		foes.append_array(help)
		var lines: Array[String] = ["На помощь бросается: " + ", ".join(help.map(func(f: Dictionary) -> String: return str(f["name"])))]
		_add(GameSession.effect_entry(lines))
		_log("События: " + lines[0])
	var source := {"room_from": session.room_id}
	if not _opening.is_empty() and foes.any(func(f: Dictionary) -> bool: return str(f.get("npc_id", "")) == str(_opening["npc_id"])):
		source["opening"] = _opening
	_opening = {}
	start_combat(foes, source)


## A deed of the engine in a fight made beside the buttons (the dev console's `hit`): played on as the hero's act.
func fight_lines(lines: Array[String]) -> void:
	if session != null and CombatRules.active(session):
		_after_deed(lines)


## A deed of the hero's turn done: its lines into the fight's log, the end checked, an outcome played on. True when it was.
func _after_deed(lines: Array[String]) -> bool:
	_refresh()
	_combat_log(lines)
	_combat_log(CombatRules.after_player_action(session, Catalog.data))
	EventBus.state_changed.emit()
	if str(session.combat.get("outcome", "")).is_empty():
		return false
	_combat_continue()
	return true


## Damage of the engine out of a fight made beside the buttons (the dev console's `dmg`): its lines into the chat; the hero
## at 0 HP is knocked out as by a trap, and the master is told.
func harm_lines(lines: Array[String]) -> void:
	if session == null or _trap_downed(lines):
		return
	_effect_lines(lines)


func _combat_log(lines: Array[String]) -> void:
	if lines.is_empty() or not CombatRules.active(session):
		return
	var log: Array = session.combat.get("log", [])
	log.append_array(lines)
	session.combat["log"] = log
	EventBus.combat_lines.emit(lines)


func _combat_ready() -> bool:
	return session != null and CombatRules.player_can_act(session) and not is_busy() and Backend.is_ready()


## One player command in a fight: `why` "" means do it; the lines go to the log; an outcome ends the fight.
func _combat_do(why: String, act: Callable) -> String:
	if not _combat_ready():
		return "COMBAT_NOT_YOUR_TURN" if session != null and CombatRules.active(session) else "COMBAT_NONE"
	if session.combat.has("prompt"):
		return "COMBAT_ANSWER_FIRST"
	if not why.is_empty():
		return why
	var lines: Array[String] = act.call()
	if not _after_deed(lines) and int(session.character["hp"]) <= 0:  # dropped on its own turn (an attack of opportunity): the turn is over
		_combat_log(CombatRules.end_player_turn(session, Catalog.data))
		_combat_continue()
	return ""


## «Оглушать, а не убивать» (v0.7.22.11, big test #44): a melee blow that brings a foe to 0 HP knocks it out.
func combat_nonlethal(on: bool) -> void:
	if session != null and CombatRules.active(session):
		session.combat["nonlethal"] = on
		EventBus.state_changed.emit()


## A spell in a fight: engine spells resolve at once; others spend the slot and go to the master (it costs the action).
func combat_cast(spell_id: String, slot: int, target_id: String) -> String:
	if session == null or not CombatRules.active(session):
		return "COMBAT_NONE"
	var act := Acts.one("cast")
	var hero := CombatRules.player(session)
	var how := {"spell": spell_id, "slot": slot}
	var why := act.can(session, Catalog.data, hero, target_id, how)
	var sp: Dictionary = Catalog.data["spells"].get(spell_id, {})
	if why.is_empty() and not CombatRules.is_engine_spell(Catalog.data, spell_id) and not sp.has("heal_at_slot"):
		if not _combat_ready():
			return "COMBAT_NOT_YOUR_TURN"
		var lines := act.go(session, Catalog.data, hero, "", how)
		_combat_log(lines)
		var target := str(CombatRules.fighter(session, target_id).get("name", "")) if not target_id.is_empty() else ""
		_request("action", "Игрок колдует %s%s. Ячейка уже потрачена движком — `cast` не нужен; реши исход проверками и эффектами с target_id врага." %
			[SpellRules.describe(Catalog.data, spell_id, slot if slot > 0 else SpellRules.lowest_slot(session.character, Catalog.data, spell_id)),
			(" на " + target) if not target.is_empty() else ""])
		return ""
	return _combat_do(why, func() -> Array[String]: return act.go(session, Catalog.data, hero, target_id, how))


## An act of `Acts` by the hero: the same the AI picks from. A check it asks for is the game's, with its card.
func combat_act(id: String, to: String = "", how: Dictionary = {}) -> String:
	if session == null or not CombatRules.active(session):
		return "COMBAT_NONE"
	var hero := CombatRules.player(session)
	var act := Acts.one(id)
	return _combat_do(act.can(session, Catalog.data, hero, to, how), func() -> Array[String]:
		var lines := act.go(session, Catalog.data, hero, to, how)
		var chk := act.check(how)
		if not chk.is_empty():
			lines.append_array(_parley_check(chk)["lines"])
		return lines)


## A feature in a fight costs what rules.resources say (combat_cost): Rage and Second Wind — a bonus action,
## Action Surge — free and gives one more action.
func combat_use_feature(resource_id: String) -> String:
	return combat_act("feature", "", {"stock": resource_id})


func combat_end_turn() -> String:
	if not _combat_ready():
		return "COMBAT_NOT_YOUR_TURN"
	_combat_log(CombatRules.end_player_turn(session, Catalog.data))
	EventBus.state_changed.emit()
	_combat_continue()
	return ""


## A feature action of the fight (v0.7.10, FeatureRules): Reckless Attack, the ki techniques, Channel Divinity, Wild
## Shape, Font of Magic, Breath Weapon. "" or a localization key.
func combat_feature(id: String, target_id: String = "") -> String:
	return combat_act("feature", target_id, {"id": id})


## The answer to a prompt of the hero's turn (Divine Smite, the beast of Wild Shape, Font of Magic).
func combat_answer(choice: String) -> String:
	if session == null or not CombatRules.active(session) or not session.combat.has("prompt"):
		return "COMBAT_NONE"
	_after_deed(FeatureRules.answer_prompt(session, Catalog.data, choice))
	return ""


## The answer to a reaction prompt in a foe's turn (Uncanny Dodge, Deflect Missiles, Cutting Words, Giant Killer).
func combat_react(choice: String) -> String:
	if session == null or not CombatRules.active(session) or not session.combat.has("pending"):
		return "COMBAT_NONE"
	var lines := CombatRules.answer_reaction(session, Catalog.data, choice)
	_refresh()
	_combat_log(lines)
	EventBus.state_changed.emit()
	_combat_continue()
	return ""


## Font of Magic outside a fight (the sheet): a slot for points or points for a slot. Stays out of the master's turns.
func font_convert(id: String) -> String:
	if not _idle():
		return "ABILITY_BUSY"
	var lines := FeatureRules.font_convert(session, Catalog.data, id)
	_add(GameSession.effect_entry(lines))
	EventBus.state_changed.emit()
	return ""


## Pact of the Blade out of a fight (v0.8.4.33): call a form, bind a weapon carried or let it go; in a fight it is the
## features' act with its prompt.
func pact_weapon(choice: String) -> String:
	if not _idle():
		return "ABILITY_BUSY"
	if CombatRules.active(session):
		return "PACT_IN_FIGHT"
	_add(GameSession.effect_entry(FeatureRules.pact_weapon(session, Catalog.data, Sheet.HERO, choice)))
	EventBus.state_changed.emit()
	return ""


## The form of the next familiar (v0.8.4.33): any of Find Familiar's, the special ones with Pact of the Chain.
func choose_familiar(form: String) -> String:
	if not _idle():
		return "ABILITY_BUSY"
	_add(GameSession.effect_entry(AllyRules.choose_familiar(session, Catalog.data, Sheet.HERO, form)))
	EventBus.state_changed.emit()
	return ""


## The metamagic of the next spell (a toggle; "" — none).
func combat_metamagic(id: String) -> void:
	if session == null or not CombatRules.active(session):
		return
	var hero := CombatRules.player(session)
	if str(hero.get("metamagic", "")) == id or id.is_empty():
		hero.erase("metamagic")
	else:
		hero["metamagic"] = id
	EventBus.state_changed.emit()


## A parley check (the button or the master's request_check of Intimidation / Persuasion in a fight): the DC is the
## engine's, the outcome is applied at once and goes to the master in `note`. Adds the check card.
func _parley_check(params: Dictionary) -> Dictionary:
	var skill := str(params["skill"])
	var p := params.duplicate()
	p["dc"] = CombatRules.parley_dc(session, Catalog.data)
	p["dc_tier"] = "medium"
	if skill == "intimidation" and not CombatRules.parley_understood(session, Catalog.data):
		p["disadvantage_reason"] = "без общего языка — жесты и оружие"  # v0.7.11
	var result := CheckEngine.card(session, Catalog.data, p)
	var lines: Array[String] = ["%s — %s: %d против Сл %d — %s" % [session.character["name"], tr("SKILL_" + skill.to_upper()),
		int(result["total"]), int(result["dc"]), "успех" if bool(result["success"]) else "провал"]]
	var outcome := CombatRules.parley_apply(session, Catalog.data, skill, bool(result["success"]))
	lines.append_array(outcome)
	result["note"] = "Переговоры (исход решил движок): " + "; ".join(outcome)
	_add(GameSession.check_entry(p, result))
	return {"result": result, "lines": lines}


## «Осмотреться» (Perception) and «Обыскать» (Investigation, 10 minutes) buttons (v0.6.6, playtest-1): the engine
## rolls for the room (with the lock of a repeat), the master narrates the result and asks for no new check.
## "" or a localization key.
func search_room(skill: String) -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session) or not ExplorationRules.SEARCH_SKILLS.has(skill):
		return "WAIT_NOT_NOW"
	var params := {"skill": skill, "dc_tier": "medium"}
	var result := _engine_check(params)
	if result.has("error"):
		return "MSG_MASTER_FAILED"
	if skill == "investigation":
		var passed := TimeRules.advance(session, Catalog.data, int(TimeRules.cfg(Catalog.data)["search_minutes"]))
		if not passed.is_empty():
			_add(GameSession.effect_entry(passed))
	var found: Array = result.get("revealed", [])
	var what := tr("SKILL_" + skill.to_upper())
	var note := "[движок уже бросил: %s %d%s — %s]" % [what, int(result["total"]), " (повтор без изменений)" if bool(result.get("blocked", false)) else "",
		("найдено: " + "; ".join(found)) if not found.is_empty() else "ничего нового"]
	var text := tr("SEARCH_SAY_" + skill.to_upper())
	_add(GameSession.player_entry(text))
	_log("Игрок: " + text)
	EventBus.state_changed.emit()
	_request("action", text + " " + note)
	return ""


## «Забрать всё» (the author, v0.7.8): the engine takes every portable thing of the room nobody owns, as long as the
## hero can carry it (PropRules.take_all); since v0.7.22.20 (#6) without a master's turn. "" or a localization key.
func take_all() -> String:
	if not _idle():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var plan := PropRules.take_all_plan(session, Catalog.data)
	if (plan["take"] as Array).is_empty():
		return "TAKE_ALL_TOO_HEAVY" if not (plan["left"] as Array).is_empty() else "TAKE_ALL_NOTHING"
	var names := PropRules.take_all(session, Catalog.data)
	var left: Array = (plan["left"] as Array).map(func(p: Dictionary) -> String: return str(p["name"]))
	var lines: Array[String] = ["Взято: " + ", ".join(names)]
	if not left.is_empty():
		lines.append("не унести: " + ", ".join(left))
	_refresh()
	_effect_lines(lines, true)  # nobody's things: the engine's move, no master (v0.7.22.20, #6)
	return ""


## «Осмотреть» a thing of the room (the place window, the map's menu): the master looks closer. "" or a key.
func look_at(prop_id: String) -> String:
	var p := PropRules.find(session, session.room_id, prop_id)
	return "" if submit(tr("PLACE_LOOK_SAY").format({"name": p.get("name", prop_id)})) else "WAIT_BUSY"


## «Взять» in the place window (v0.7.22.7): one thing of the room by the engine; the master narrates only an owner who
## saw it (v0.7.22.20, #6). "" or a localization key.
func take_prop(prop_id: String) -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var r := PropRules.plan_take(session, Catalog.data, {"prop_id": prop_id})
	if r.has("reason"):
		EventBus.message.emit(str(r["reason"]))
		return ""
	var lines: Array[String] = [str(r["summary"])]
	lines.append_array(PropRules.apply_take(session, Catalog.data, r["plan"]))
	_refresh()
	if str(r["plan"].get("owner", "")).is_empty():  # nobody saw a theft: the engine's move, no master (v0.7.22.20, #6)
		_effect_lines(lines, true)
		return ""
	var p := PropRules.find(session, session.room_id, prop_id)
	var text := tr("PLACE_TAKE_SAY").format({"name": p.get("name", prop_id)})
	_add(GameSession.player_entry(text))
	_add(GameSession.effect_entry(lines))
	_log("Игрок: " + text)
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("action", text + " [движок уже применил: %s — эффект move_item:room>hero не нужен; опиши коротко]" % ", ".join(lines))
	return ""


## The container window (v0.7.18.1): take or put without a master's turn — like the gear in the sheet; taking from
## someone else's container before them is a theft, the master narrates the owner's reaction. "" or a localization key.
func container_move(prop_id: String, item_id: String, qty: int, take: bool) -> String:
	if session == null or is_busy() or session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var r := ContainerRules.plan_take(session, Catalog.data, prop_id, item_id, qty) if take else ContainerRules.plan_put(session, Catalog.data, prop_id, item_id, qty)
	if r.has("reason"):
		EventBus.message.emit(str(r["reason"]))
		return ""
	var lines: Array[String] = [str(r["summary"])]
	if take:
		lines.append_array(ContainerRules.apply_take(session, Catalog.data, r["plan"]))
	else:
		ContainerRules.apply_put(session, Catalog.data, r["plan"])
	if take and not str(r["plan"].get("owner", "")).is_empty():  # caught: the master narrates the owner
		_effect_lines(lines)
		_request("action", "Беру из чужого %s [движок: %s]" % [PropRules.find(session, session.room_id, prop_id).get("name", ""), " · ".join(lines)])
		return ""
	_effect_lines(lines, true)
	return ""


## «Взять всё» in a container's window (v0.7.49.4, the author's finding): every thing of it whole, one after another,
## until the hero can carry no more; one engine line, and one master turn when the container is someone else's.
func container_take_all(prop_id: String) -> String:
	if session == null or is_busy() or session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var p := ContainerRules.target(session, Catalog.data, prop_id)
	var lines: Array[String] = []
	var owner := ""
	for id: String in (p.get("contents", {}) as Dictionary).keys():
		var r := ContainerRules.plan_take(session, Catalog.data, prop_id, id, int(p["contents"][id]))
		if r.has("reason"):
			EventBus.message.emit(str(r["reason"]))
			break
		lines.append(str(r["summary"]))
		lines.append_array(ContainerRules.apply_take(session, Catalog.data, r["plan"]))
		owner = str(r["plan"].get("owner", ""))
	if lines.is_empty():
		return ""
	if not owner.is_empty():  # caught: the master narrates the owner
		_effect_lines(lines)
		_request("action", "Беру всё из чужого %s [движок: %s]" % [PropRules.find(session, session.room_id, prop_id).get("name", ""), " · ".join(lines)])
		return ""
	_effect_lines(lines, true)
	return ""


## Picks a skill of a peaceful direction for a level reached (v0.7.19.1), no master turn. "" or a localization key.
func pick_development(dir: String, skill: String) -> String:
	if not _idle():
		return "WAIT_BUSY"
	var why := DevelopmentRules.pick(session.character, Catalog.data, dir, skill)
	if why.is_empty():
		var sk: Dictionary = DevelopmentRules.direction(Catalog.data, dir)["skills"][skill]
		_effect_lines(["%s: навык «%s»" % [DevelopmentRules.direction(Catalog.data, dir)["name"], sk["name"]]] as Array[String], true)
	return why


## Writes the hero's life goal (v0.7.22; "" clears it); a new goal goes to the master for its assessment. "" or a key.
func set_goal(text: String) -> String:
	if not _idle():
		return "WAIT_BUSY"
	var before := str(GoalRules.goal(session.character).get("text", ""))
	GoalRules.write(session.character, text)
	var now := str(GoalRules.goal(session.character).get("text", ""))
	_log("Жизненная цель: %s" % (now if not now.is_empty() else "стёрта"))
	EventBus.state_changed.emit()
	if not now.is_empty() and now != before and Backend.is_ready():
		_request("goal", now)
	return ""


## Leaves a thing of the pack — a bag with what is in it — in the room (v0.7.18.2), no master turn; from the sheet
## too, in a talk or a fight (big test #10, v0.7.22.2: an overloaded hero could not leave). "" or a key.
func drop_item(what: String, qty: int = 1) -> String:
	if not _idle():
		return "WAIT_NOT_NOW"
	var r := ContainerRules.plan_drop(session, Catalog.data, what, qty)
	if r.has("reason"):
		EventBus.message.emit(str(r["reason"]))
		return ""
	ContainerRules.apply_drop(session, Catalog.data, r["plan"])
	_effect_lines([str(r["summary"])] as Array[String], true)
	return ""


## A locked container (v0.7.18.1): the key, thieves' tools (Sleight of Hand) or force (Athletics) against its lock;
## the master narrates the attempt. "" or a localization key.
func container_unlock(prop_id: String, how: String) -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var p := PropRules.find(session, session.room_id, prop_id)
	if p.is_empty() or not ContainerRules.ways(session, Catalog.data, p).has(how):
		return "WAIT_NOT_NOW"
	var lines: Array[String] = []
	if how != "key":
		var need := ContainerRules.lock_check(Catalog.data, p, how)
		var result := _lock_roll(how, int(need["dc"]), prop_id)
		TimeRules.advance(session, Catalog.data, int(ContainerRules.cfg(Catalog.data).get("minutes", 1)))
		if not bool(result["success"]):
			lines.append("%s не поддался" % p["name"])
	if lines.is_empty():
		lines = ContainerRules.unlock(p, how)
	_effect_lines(lines)
	_request("action", "%s %s [движок: %s]" % [{"key": "Открываю ключом", "pick": "Вскрываю отмычками", "force": "Выбиваю"}[how], p["name"], " · ".join(lines)])
	return ""


## The hero's own lock on a container of the room (v0.8.4.27): "hang" — the lock hung, its key made; "relock" — shut by
## the key. No master's turn. "" or a localization key.
func container_lock(prop_id: String, how: String) -> String:
	if not _idle():
		return "EQUIP_BUSY"
	var p := PropRules.find(session, session.room_id, prop_id)
	if p.is_empty() or not ContainerRules.lock_ways(session, Catalog.data, p).has(how):
		return "WAIT_NOT_NOW"
	var lines := ContainerRules.lock_up(session, Catalog.data, p, how)
	lines.append_array(TimeRules.advance(session, Catalog.data, int(ContainerRules.cfg(Catalog.data).get("minutes", 1))))
	_effect_lines(lines, true)
	return ""


## A door on the way to `to` (v0.7.22.25, WayRules): a key, thieves' tools (Sleight of Hand), force (Athletics),
## blows of the weapon, a door spell, a torch, waiting for the site's hours. Breaking into someone's closed or
## private site before eyes is a trespass at once. The master narrates it. "" or a localization key.
func door_act(to: String, how: String, spell_id: String = "") -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var data := Catalog.data
	var from := session.room_id
	var way := {"how": how, "spell": spell_id} if how == "spell" else {"how": how}
	if not WayRules.ways(session, data, from, to).has(way):
		return "WAIT_NOT_NOW"
	if how == "ask":  # a knock: the owner answers as to «Попросить впустить»
		_effect_lines(SiteRules.ask(session, data, SiteRules.unwelcome(session, data, to)), true)
		return ""
	if how == "lock":  # the hero's own lock, or its key (v0.8.4.27): no master's turn
		_effect_lines(WayRules.lock_with(session, data, from, to), true)
		return ""
	var lines: Array[String] = []
	var minutes := int(WayRules.cfg(data)["try_minutes"])
	match how:
		"key":
			WayRules.unlock(session, data, from, to)
			lines.append("Дверь отперта ключом")
		"latch":
			WayRules.unlock(session, data, from, to)
			lines.append("Засов отодвинут")
		"pick", "force":
			var result := _lock_roll(how, int(WayRules.dcs(session, data, from, to)[how]), to)
			if not bool(result["success"]):
				lines.append("Замок не поддался" if how == "pick" else "Дверь выдержала")
			elif how == "pick":
				WayRules.unlock(session, data, from, to)
				lines.append("Замок вскрыт")
			else:
				WayRules.break_down(session, from, to)
				lines.append(WayRules.break_line(data, from, to))
		"hit":
			lines = WayRules.hit(session, data, from, to)
		"spell":
			var r := _spend({"kind": "spell", "id": spell_id})
			if r.has("reason"):
				return str(r["reason"])
			lines.assign(r["lines"])
			lines.append_array(WayRules.spell(session, data, from, to, spell_id))
		"torch":
			lines = WayRules.ignite(session, data, from, to, "факел")
		"wait":
			var h := WayRules.hours(session, data, str(WayRules.def(data, from, to)["site"]))
			minutes = 0
			lines.append("Ожидание до %02d:00" % int(h["from"]))
			lines.append_array(CrimeRules.wait(session, data, int(h["opens"]) - TimeRules.abs_minute(session))["lines"])
	if minutes > 0:
		lines.append_array(TimeRules.advance(session, data, minutes))
	if how in ["pick", "force", "hit", "torch"] or (how == "spell" and str(data["rules"]["spell_effects"].get(spell_id, {}).get("door", "")) != "lock"):
		lines.append_array(WayRules.forced(session, data, from, to))
	_effect_lines(lines)
	var verb: String = {"key": "Отпираю ключом", "latch": "Отодвигаю засов", "pick": "Вскрываю отмычками", "force": "Выбиваю", "hit": "Рублю",
		"spell": "Колдую на", "torch": "Поджигаю", "wait": "Жду, пока откроют"}[how]
	_request("wait" if how == "wait" else "action", "%s дверь в «%s» [движок: %s]" % [verb, world().room(to).get("name", to), " · ".join(lines)])
	return ""


## The theft window (v0.7.0): a Sleight of Hand against the entry's DC; success — it is taken; failure — the NPC
## reacts by its kind. The master narrates it (kind=theft); a fight it causes starts after. "" or a localization key.
func steal(npc_id: String, entry_id: String) -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	var why := TheftRules.can_steal(session, Catalog.data, npc_id)
	if not why.is_empty():
		return why
	var entry := {}
	for e: Dictionary in TheftRules.pockets(session, Catalog.data, npc_id):
		if str(e["id"]) == entry_id:
			entry = e
	if entry.is_empty():
		return "THEFT_NOBODY"
	var params := TheftRules.check_params(session, Catalog.data, npc_id, entry)
	var result := CheckEngine.card(session, Catalog.data, params)
	_add(GameSession.check_entry(params, result))
	var lines := TheftRules.steal(session, Catalog.data, npc_id, entry_id, bool(result["success"]))
	_effect_lines(lines)
	_request("theft", "карманы %s — %s (%s): %s" % [world().npc(npc_id).get("name", npc_id), entry["name"],
		"успех" if bool(result["success"]) else "провал", "; ".join(lines)])
	return ""


## A contest (v0.7.40): sits down to play `kind` with `npc_id` for the stake `stake_i` (`cp` — the coins of a coins
## stake). "" or the reason.
func contest_start(npc_id: String, kind: String, stake_i: int, cp: int) -> String:
	if not _master_ready():
		return tr("WAIT_BUSY")
	var r := ContestRules.start(session, Catalog.data, npc_id, kind, stake_i, cp)
	if r.has("reason"):
		return str(r["reason"])
	var lines: Array[String] = []
	lines.assign(r["lines"])
	_told(lines)
	if ContestRules.is_bout(Catalog.data, kind):  # v0.7.45: a duel is a fight to surrender, not rounds of dice
		var d := ContestRules.duel(session, Catalog.data)
		var dl: Array[String] = []
		dl.assign(d["lines"])
		_add(GameSession.effect_entry(dl))
		start_combat(d["foes"], d["source"])
		return ""
	EventBus.state_changed.emit()
	return ""


# --- the arena (v0.7.45, ArenaRules) ----------------------------------------------------------------------------


## Enlists the hero as a fighter of the arena `sid`. "" or the reason.
func arena_enlist(sid: String) -> String:
	if not _idle():
		return tr("WAIT_BUSY")
	var why := ArenaRules.enlist_why(session, Catalog.data, sid)
	if not why.is_empty():
		return why
	_effect_lines(ArenaRules.enlist(session, Catalog.data, sid))
	return ""


## The bout of the day (`bet_cp` on oneself) or the tournament's next one: the fight starts. "" or the reason.
func arena_bout(sid: String, bet_cp: int, tourney: bool = false) -> String:
	if not _master_ready():
		return tr("WAIT_BUSY")
	var r := ArenaRules.tourney_bout(session, Catalog.data, sid) if tourney else ArenaRules.bout(session, Catalog.data, sid, bet_cp)
	if r.has("reason"):
		return str(r["reason"])
	var lines: Array[String] = []
	lines.assign(r["lines"])
	_add(GameSession.effect_entry(lines))
	start_combat(r["foes"], r["source"])
	return ""


## Insight on the fighters of the day: the check card, the true estimate on success. "" or the reason.
func arena_insight(sid: String) -> String:
	if not _idle():
		return tr("WAIT_BUSY")
	var why := ArenaRules.insight_why(session, Catalog.data, sid)
	if not why.is_empty():
		return why
	var params := ArenaRules.insight_params(Catalog.data)
	var result := CheckEngine.card(session, Catalog.data, params)
	if result.has("error"):
		return str(result["error"])
	_add(GameSession.check_entry(params, result))
	_effect_lines(ArenaRules.set_insight(session, Catalog.data, sid, bool(result["success"])))
	return ""


## A bet on a fighter of the day's card: the bout starts, the hero watches it. "" or the reason.
func arena_bet(sid: String, side: String, cp: int) -> String:
	if not _master_ready():
		return tr("WAIT_BUSY")
	var r := ArenaRules.bet(session, Catalog.data, sid, side, cp)
	if r.has("reason"):
		return str(r["reason"])
	var lines: Array[String] = []
	lines.assign(r["lines"])
	_add(GameSession.effect_entry(lines))
	start_combat(r["foes"], r["source"])
	return ""


## What the engine did, told (v0.8.4.29.6, the one helper of a deed's lines): to the chat and the log, a creature gone from the
## talk forgotten, the screens refreshed; `save` — the autosave too.
func _effect_lines(lines: Array[String], save := false) -> void:
	_told(lines)
	_forget_gone_creature()
	EventBus.state_changed.emit()
	if save:
		SaveManager.save_slot(SaveManager.AUTOSAVE, session)


## What the engine did goes to the chat and the log.
func _told(lines: Array[String]) -> void:
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))


## An act of a window's button (v0.7.70): `rows` {what: [why, do]}, `why` gives "" or a key, `do` the lines of the deed.
## "" or the key of the refusal.
func _act(what: String, rows: Dictionary, no: String = "PROPERTY_NOT_NOW") -> String:
	if not rows.has(what):
		return no
	var why: String = (rows[what][0] as Callable).call()
	if not why.is_empty():
		return why
	var lines: Array[String] = []
	lines.assign((rows[what][1] as Callable).call())
	_refresh()
	if lines.is_empty():
		EventBus.state_changed.emit()
		return ""
	_effect_lines(lines, true)
	return ""


## A row of _act whose two rules take the same arguments.
func _row(why: Callable, do: Callable, args: Array) -> Array:
	return [why.bindv(args), do.bindv(args)]


## Work that takes `minutes`: the patrol may break it (CrimeRules.wait). `work` gets the minutes that passed and gives
## lines; with `whole` it runs only when they all passed.
func _waited(minutes: int, work: Callable, whole := false) -> Array:
	var w := CrimeRules.wait(session, Catalog.data, minutes)
	var lines: Array = w["lines"]
	if not whole or int(w["minutes"]) >= minutes:
		lines.append_array(work.call(int(w["minutes"])))
	return lines


func _refresh() -> void:
	CharacterRules.refresh(session.character, Catalog.data, session.items)


## One round of the contest going: the NPC rolls by its template, the hero by the kind's check (or its cheat skill
## against the NPC's watch); the card shows the hero's roll against the NPC's total. The end asks the master to tell
## it. "" or the reason.
func contest_round(cheat: bool) -> String:
	if not _master_ready():
		return tr("WAIT_BUSY")
	var st := ContestRules.state(session)
	if st.is_empty():
		return "игры нет"
	var npc := str(st["npc"])
	if not session.npcs_here(world().world, session.room_id).has(npc):
		return "%s ушёл из-за стола" % world().npc(npc).get("name", npc)
	var k := ContestRules.kind(Catalog.data, str(st["kind"]))
	if cheat and str(k.get("cheat", "")).is_empty():
		return "в этой игре не сжульничать"
	var foe := ContestRules.npc_roll(session, Catalog.data, cheat)
	var params := ContestRules.hero_params(Catalog.data, k, cheat)
	params["dc"] = int(foe["total"])
	params["target_id"] = npc
	var result := CheckEngine.card(session, Catalog.data, params)
	if result.has("error"):
		return str(result["error"])
	var total := ContestRules.settled(int(result["nat"]), int(result["total"]), int(foe["total"]), result.has("auto_fail_reason"))
	result["success"] = total > int(foe["total"])
	_add(GameSession.check_entry(params, result))
	var lines := ContestRules.round(session, Catalog.data, total, int(foe["total"]), cheat)
	_effect_lines(lines)
	if ContestRules.state(session).is_empty():
		_request("contest", "%s с %s: %s" % [k.get("name", ""), world().npc(npc).get("name", npc), "; ".join(lines)])
	return ""


## Gives the contest going up: the NPC takes the stake. "" or the reason.
func contest_forfeit() -> String:
	if not _idle():
		return tr("WAIT_BUSY")
	var lines := ContestRules.forfeit(session, Catalog.data)
	if lines.is_empty():
		return "игры нет"
	_effect_lines(lines)
	return ""


## The «Красться» toggle of exploration (v0.6.2): foes notice the hero only in their cones and by a Stealth roll (v0.8.3);
## passive Perception for hidden things is 5 lower while sneaking (PHB).
## Among people (v0.6.5, playtest-1) it is a Stealth roll against the best passive Perception of the NPCs here: a
## failure — they noticed, no sneaking in this room until the player leaves it. "" or a localization key.
func set_sneaking(on: bool) -> String:
	if session == null:
		return "SNEAK_BUSY"
	if not on:
		session.sneaking = false
		walked(WalkRules.view(session, Catalog.data))  # out of hiding: they may see the hero now
		EventBus.state_changed.emit()
		return ""
	if session.sneak_noticed == session.room_id:
		EventBus.state_changed.emit()
		return "SNEAK_NOTICED"
	var line := _sneak_past_people(session.room_id)
	if not line.is_empty():
		_add(GameSession.effect_entry([line]))
		_log("События: " + line)
	session.sneaking = session.sneak_noticed != session.room_id
	EventBus.state_changed.emit()
	return "" if session.sneaking else "SNEAK_NOTICED"


## A Stealth roll against the NPCs of `room_id` (none — no roll, ""). A failure marks the room noticed. The line.
func _sneak_past_people(room_id: String) -> String:
	var npcs := session.npcs_here(world().world, room_id)
	if room_id == session.room_id:  # hidden from those who see the hero; the next room is met from its door
		var was := session.sneaking
		session.sneaking = false
		npcs.assign(WatchRules.eyes(session, Catalog.data, npcs))
		session.sneaking = was
	if npcs.is_empty():
		return ""
	var roll := CombatRules.stealth_roll(session, Catalog.data)
	var vs := WatchRules.against(session, Catalog.data, npcs.map(func(id: String) -> Dictionary: return Sheet.who(session, Catalog.data, id)), Sheet.HERO, int(roll["total"]))
	var best := int(vs["best"])
	var who := WorldView.name_of(Catalog.data, str(vs["by"].get("id", "")))
	if bool(vs["ok"]):
		return "Крадётесь: Скрытность %d%s против Внимательности %d — никто не обращает внимания" % [int(roll["total"]), roll["note"], best]
	session.sneak_noticed = room_id
	session.sneaking = false
	return "Крадётесь: Скрытность %d%s против Внимательности %d — %s замечает вас" % [int(roll["total"]), roll["note"], best, who]


## Plays the turns of the others with a pause per actor until it is the player's turn (alive), the round ends
## (the master narrates it) or the fight ends (the final narration, then the results).
func _combat_continue() -> void:
	if combat_playing or session == null or not CombatRules.active(session) or not busy_turn.is_empty():
		return
	var s := session
	combat_playing = true
	while CombatRules.active(s) and session == s:
		if s.combat.has("pending"):  # the hero is asked about a reaction (v0.7.10): combat_react goes on
			break
		if bool(s.combat.get("round_ended", false)):
			s.combat.erase("round_ended")
			if bool(CombatRules.cfg(Catalog.data)["told"]["rounds"]) and not ArenaRules.watching(s):
				combat_playing = false
				_narrate_round()
				return
			_story_round()  # v0.8.4.31: the round's rolls in the chat, the master tells the fight once, at its end
		if not str(s.combat.get("outcome", "")).is_empty():
			combat_playing = false
			_combat_outcome()
			return
		if CombatRules.player_can_act(s):
			break
		var lines := CombatRules.next_actor(s, Catalog.data)
		CharacterRules.refresh(s.character, Catalog.data, s.items)
		_combat_log(lines)
		EventBus.state_changed.emit()
		if combat_delay > 0.0 and not lines.is_empty():
			await get_tree().create_timer(combat_delay).timeout
	combat_playing = false
	EventBus.state_changed.emit()


func _narrate_round() -> void:
	var log: Array = session.combat.get("log", [])
	session.combat["log"] = []
	_keep_rolls(log)
	_request("combat_round", "\n".join(log))


## A round not told by the master: its rolls go to the chat now, its lines wait for the telling of the whole fight.
func _story_round() -> void:
	var log: Array = session.combat.get("log", [])
	if log.is_empty():
		return
	session.combat["log"] = []
	var story: Array = session.combat.get("story", [])
	story.append("Раунд %d:" % int(session.combat.get("round", 1)))
	story.append_array(log)
	session.combat["story"] = story
	_keep_rolls(log)


## The round's rolls stay in the chat after the fight, before the master's words of it, with their breakdowns (v0.8.4.21.1).
func _keep_rolls(log: Array) -> void:
	if log.is_empty():
		return
	var tips := {}
	for l: Variant in log:
		var tip := CombatRules.tip_for(session, str(l))
		if not tip.is_empty():
			tips[str(l)] = tip
	_add(GameSession.rolls_entry(int(session.combat.get("round", 1)), log, tips))


## The fight is over: the final narration (death — the epitaph), then the results wait for finish_combat().
func _combat_outcome() -> void:
	var s := session
	if bool(s.combat.get("narrated", false)):
		return
	s.combat["narrated"] = true
	var outcome := str(s.combat["outcome"])
	if outcome in ["victory", "truce"]:
		CombatRules.results(s, Catalog.data)
		var xp_lines := XpRules.share(s, Catalog.data, int(s.combat["xp"]), "бой", GrowthRules.fought(s))  # split with the followers who fought (v0.8.4.42.2)
		_combat_log(xp_lines)
	var log: Array = s.combat.get("log", [])
	s.combat["log"] = []
	_keep_rolls(log)
	var story: Array = s.combat.get("story", [])  # the rounds the master did not tell (v0.8.4.31): the whole fight at once
	s.combat.erase("story")
	if not story.is_empty() and not log.is_empty():
		story.append("Раунд %d:" % int(s.combat.get("round", 1)))
	story.append_array(log)
	story = story.slice(maxi(0, story.size() - int(CombatRules.cfg(Catalog.data)["told"]["lines"])))
	if outcome == "dead":
		_request("death", "\n".join(story) + "\n" + _hero_path())
	else:
		_request("combat_round", "\n".join(story) + "\nИтог боя: " + tr("COMBAT_OUTCOME_" + outcome.to_upper()))


func _hero_path() -> String:
	var c := session.character
	return "Путь героя: %s, %s %s %d уровня; дней в пути %d; выполнено заданий %d." % [c["name"], c.get("race_name", ""),
		c.get("class_name", ""), int(c.get("level", 1)), session.day, session.quests_done.size()]


## The treasure of the encounter just won: it lies on the foes (CreatureRules.after_fight).
func _treasure() -> Dictionary:
	var id := str(session.combat.get("encounter", ""))
	if id.is_empty() or str(session.combat.get("outcome", "")) != "victory":
		return {}
	for rid: String in Catalog.data["world"]["rooms"]:
		var enc: Dictionary = SceneRules.room(session, Catalog.data["world"], rid).get("encounter", {})
		if str(enc.get("id", "")) == id:
			return enc.get("loot", {})
	return {}


## The player leaves the results: the world remembers the fight, back to the game. `gather` — «Собрать стрелы» ticked in
## the results (v0.8.4.30): what was found of the spent shots goes back at once.
func finish_combat(gather := false) -> void:
	if session == null or not CombatRules.active(session) or is_busy():
		return
	var s := session
	var outcome := str(s.combat.get("outcome", ""))
	if outcome == "dead":
		return
	var lines: Array[String] = [tr("COMBAT_OUTCOME_" + outcome.to_upper())]
	if outcome in ["victory", "truce"]:
		var back := {}  # v0.7.12: half the spent arrows can be picked up here
		back = Gear.shot_back(Catalog.data, CombatRules.player(s), s.rng)
		var lying := Gear.left_on_field(s)  # thrown weapons, the hero's and the foes' (v0.8.4.31): picked up with the arrows
		for item: String in lying:
			back[item] = int(back.get(item, 0)) + int(lying[item])
		if not back.is_empty():
			s.character["ammo_left"] = {"room": s.room_id, "items": back}
		if int(s.combat.get("xp", 0)) > 0:
			lines.append("+%d опыта" % int(s.combat["xp"]))
		lines.append_array(FactionRules.after_fight(s, Catalog.data))  # v0.7.50
		if not str(s.combat.get("encounter", "")).is_empty():
			s.encounters_done.append(str(s.combat["encounter"]))
		for id: Variant in s.combat.get("joined", []):  # those who came on the noise (v0.8.4)
			s.encounters_done.append(str(id))
	var arena: Dictionary = s.combat.get("arena", {})
	if not arena.is_empty():  # v0.7.45: a bout — the prize, the bet, the rank; nobody stays beaten in the room, no crime
		lines.append_array(ArenaRules.after_bout(s, Catalog.data, arena, outcome == "victory" or bool(arena.get("won", false))))
	elif outcome in ["victory", "truce"]:
		lines.append_array(CreatureRules.after_fight(s, Catalog.data, s.room_id, _treasure()))  # the beaten stay in the room (v0.7.22.11)
	if not ArenaRules.watching(s):
		lines.append_array(AllyRules.after_fight(s, Catalog.data))  # v0.7.22.22: the fallen followers come to, the summoned keep their wounds
	var by_law := outcome == "captured" and CombatRules.law_captors(s)
	if not arena.is_empty():
		pass
	elif by_law:  # v0.7.22.17: the guard holds the hero, as at an arrest
		lines.append_array(CrimeRules.held_after_fight(s, Catalog.data))
	elif outcome == "captured":  # v0.7.22.12: bound in their place, not a won fight
		var foes: Array = CombatRules.enemies(s).filter(func(fid: String) -> bool: return str(CombatRules.fighter(s, fid).get("npc_id", "")).is_empty())
		lines.append_array(EncounterRules.capture(s, Catalog.data, foes, str(s.combat.get("encounter", "")), str(s.combat.get("room_from", ""))))
		lines.append_array(EncounterRules.seize(s, Catalog.data))  # v0.7.22.17, #15
	if outcome == "captured" and arena.is_empty():  # a quest's fight lost: its act goes on from the captivity (v0.8.4.31)
		lines.append_array(QuestRules.lost(s, Catalog.data, str(s.combat.get("encounter", ""))))
	for id: String in CombatRules.enemies(s, false) if arena.is_empty() else []:
		var f := CombatRules.fighter(s, id)
		if str(f.get("status")) == "dead" and not str(f.get("npc_id", "")).is_empty():  # the body, quests, a murder (v0.7.14)
			lines.append_array(CrimeRules.on_death(s, Catalog.data, str(f["npc_id"]), bool(f.get("by_hero", false)), s.room_id))
		elif not str(f.get("npc_id", "")).is_empty() and bool(f.get("by_hero", false)) and (outcome != "captured" or by_law):  # v0.7.22.16: an assault
			lines.append_array(CrimeRules.on_assault(s, Catalog.data, str(f["npc_id"]), str(f.get("status")) != "unconscious", s.room_id))
	if outcome == "player_fled":
		CreatureRules.after_flight(s)
	if outcome in ["player_fled", "captured"] and arena.is_empty():  # v0.8.4.4: the dead stay dead, with their things
		CreatureRules.after_fight(s, Catalog.data, str(s.combat.get("room_start", s.room_id)), {}, true)
	var flee_to := str(s.combat.get("flee_to", ""))
	var walked_in := "" if str(s.combat.get("room_start", s.room_id)) == s.room_id else s.room_id  # v0.8.4: a fight crosses doors
	if outcome == "player_fled" and flee_to.is_empty() and walked_in.is_empty() and not str(s.combat.get("room_from", "")).is_empty():
		s.room_id = str(s.combat["room_from"])
	if not walked_in.is_empty():
		s.room_id = str(s.combat["room_start"])
		_step(walked_in, lines)
	if int(s.character["hp"]) <= 0:
		s.character["hp"] = 1
	for cond: String in ["unconscious", "prone", "grappled"]:  # the fight is over: up, and nobody holds the hero
		ConditionRules.remove(s.character, cond)
	lines.append_array(FeatureRules.end_shape(s, Catalog.data, 0))  # the beast form ends with the fight (v0.7.10)
	for id: String in s.combat.get("order", []):  # a rage ends with the fight: a frenzy's exhaustion, anybody's (v0.8.4.33)
		var rager := CombatRules.fighter(s, id)
		if bool(rager.get("raging", false)) and Attack.up(s, rager):
			FeatureRules.rage_ends(s, Catalog.data, rager, lines)
	var minutes := ceili(int(s.combat.get("round", 1)) / float(ConditionRules.ROUNDS_PER_MINUTE))
	CombatRules.close(s)
	lines.append_array(TimeRules.advance(s, Catalog.data, minutes))  # the rounds of the fight on the clock (v0.7.8)
	if gather and str(s.character.get("ammo_left", {}).get("room", "")) == s.room_id:
		lines.append_array(_gather_ammo(s))
	s.mode = GameSession.MODE_EXPLORATION
	lines.append_array(CrimeRules.check_arrest(s, Catalog.data))  # a murder before the guard's eyes (v0.7.14)
	CharacterRules.refresh(s.character, Catalog.data, s.items)
	_told(lines)
	_set_options([])
	_quest_progress()
	SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	EventBus.state_changed.emit()
	EventBus.navigate.emit("game", {})
	if not flee_to.is_empty():  # through the way out: a room like any other
		_move_to(flee_to, [])


## A lock, a door or a trap by the hero's hands (one road for the three): `how` "pick" — thieves' tools (Sleight of
## Hand), "force" — Athletics, "dodge" — Acrobatics past a trap; against `dc`. Adds the check card; the result.
func _lock_roll(how: String, dc: int, target: String) -> Dictionary:
	var params := {"skill": {"pick": "sleight_of_hand", "force": "athletics", "dodge": "acrobatics"}[how], "dc_tier": "medium", "dc": dc, "target_id": target}
	if how == "force":
		params["about"] = "force"  # a crowbar, a portable ram (rules.check_about, v0.8.4.27)
	if how == "pick":
		params["tool"] = "thieves_tools"  # v0.8.4.29.1: the tools by the check's own road (rules.tools: required, proficiency)
	var result := CheckEngine.card(session, Catalog.data, params)
	_add(GameSession.check_entry(params, result))
	return result


## Eat, drink, fill the waterskins (v0.7.23): the engine's own acts, no master's turn; they take a few minutes.
## "" or a localization key.
func need_act(act: String, only := "") -> String:
	if not _out_of_fight():
		return "NEED_BUSY"
	var data := Catalog.data
	var cfg := NeedRules.cfg(data)
	var timed := func(lines: Array[String], minutes: int) -> Array[String]:  # the deed and the minutes it takes
		lines.append_array(TimeRules.advance(session, data, minutes))
		return lines
	return _act(act, {  # one road of a window's button (v0.8.4.29.6)
		"eat": [NeedRules.can_eat.bind(session, data), func() -> Array[String]: return timed.call(NeedRules.eat(session, data), int(cfg["food"]["eat_minutes"]))],
		"drink": [NeedRules.can_drink.bind(session, data), func() -> Array[String]: return timed.call(NeedRules.drink(session, data), int(cfg["water"]["drink_minutes"]))],
		"fill": [NeedRules.can_fill.bind(session, data, only), func() -> Array[String]: return timed.call(NeedRules.fill(session, data, only), int(cfg["water"]["fill_minutes"]))],
	}, "NEED_BUSY")


## A liquid in a vessel or a ready thing (v0.8.4.28): drink a portion, pour it out, pour it into another vessel. `key` and
## `to` — copies as LiquidRules.key_of names them. "" or a localization key.
func liquid_act(what: String, key: String, to: String = "") -> String:
	if not _out_of_fight():
		return "NEED_BUSY"
	var data := Catalog.data
	var s := session
	var c := s.character
	var a := LiquidRules.by_key(c, data, key)
	return _act(what, {
		"drink": [LiquidRules.drink_why.bind(data, a), func() -> Array:
			var lines: Array = LiquidRules.drink(s, data, Sheet.HERO, a)
			lines.append_array(TimeRules.advance(s, data, int(NeedRules.cfg(data)["water"]["drink_minutes"])))
			return lines],
		"pour_out": [func() -> String: return "LIQUID_GONE" if a.is_empty() else "LIQUID_EMPTY" if float(a["pints"]) <= 0.0 else "",
			LiquidRules.pour_out.bind(c, data, a, s.items)],
		"pour": [func() -> String: return LiquidRules.pour_why(c, data, a, LiquidRules.by_key(c, data, to)),
			func() -> Array: return LiquidRules.pour(c, data, a, LiquidRules.by_key(c, data, to), s.items)],
	})


## Crafting (v0.7.24): the acts go without the master, the time passes by the engine. "" or a localization key.
func craft_act(what: String, arg: String = "", hours: int = 1) -> String:
	if not _at_leisure():
		return "CRAFT_NOT_NOW"
	var data := Catalog.data
	var s := session
	return _act(what, {
		"start": _row(CraftRules.why_not, CraftRules.start, [s, data, arg]),
		"work": [CraftRules.can_work.bind(s, data), func() -> Array:  # the patrol may break the work (v0.7.22.18)
			return _waited(CraftRules.shift_minutes(s, data, hours), func(m: int) -> Array: return CraftRules.worked(s, data, m))],
		"abandon": [func() -> String: return "", CraftRules.abandon.bind(s, data)],
		"salvage": [func() -> String: return "" if CraftRules.salvageable(s, data).has(arg) else "CRAFT_NO_SALVAGE", func() -> Array:
			var lines: Array = CraftRules.salvage(s, data, arg)
			lines.append_array(TimeRules.advance(s, data, int(CraftRules.cfg(data)["salvage"]["minutes"])))
			return lines],
		"gather": [CraftRules.gather_why.bind(s, data, arg), func() -> Array:  # a patrol breaks it off: nothing gathered
			return _waited(int(CraftRules.cfg(data)["gather"][arg]["minutes"]), func(_m: int) -> Array: return CraftRules.gather(s, data, arg), true)],
	}, "CRAFT_NOT_NOW")


## Hunting or fishing (v0.7.41): `hours` at the room's ground of `kind` (WildsRules) — the time passes first (the
## patrol may cut it), then the check and the catch; a big beast or a predator starts a fight.
func wilds_act(kind: String, hours: int) -> String:
	if not _at_leisure():
		return "CRAFT_NOT_NOW"
	var data := Catalog.data
	var why := WildsRules.why_not(session, data, kind)
	if not why.is_empty():
		return why
	var span: Array = WildsRules.kind(data, kind)["hours"]
	var w := CrimeRules.wait(session, data, clampi(hours, int(span[0]), int(span[1])) * 60)
	var lines: Array[String] = w["lines"]
	var spent := int(w["minutes"]) / 60
	var fight: Array = []
	if spent > 0:
		var r := WildsRules.go(session, data, kind, spent)
		lines.append_array(r["lines"])
		fight = r["fight"]
	_refresh()
	_effect_lines(lines, fight.is_empty())  # the one helper (v0.8.4.29.6)
	if not fight.is_empty():
		session.pending_fight = fight
		_start_pending_fight()
	return ""


## Pets (v0.7.43): tame (id — a creature of the room, arg — a thing of its taste or ""), feed (arg — the thing),
## scout (arg — a room behind an exit), rename (arg — the name). The engine decides; "" or a localization key.
func pet_act(what: String, id: String, arg: String = "") -> String:
	if not _at_leisure():
		return "PET_NOT_NOW"
	var data := Catalog.data
	var s := session
	var a := [s, data, id, arg]
	return _act(what, {
		"tame": [PetRules.tame_why.bind(s, data, id), func() -> Array:
			return _waited(int(PetRules.cfg(data)["tame_minutes"]), func(_m: int) -> Array:
				if not PetRules.tame_why(s, data, id).is_empty() and PetRules.tame_why(s, data, id) != "PET_TRIED_TODAY":
					return ["Пока вы подбирались, зверь ушёл"]
				return PetRules.tame(s, data, id, arg)["lines"])],
		"feed": _row(PetRules.feed_why, PetRules.feed, a),
		"scout": [PetRules.scout_why.bindv(a), func() -> Array:
			var lines: Array = TimeRules.advance(s, data, int(PetRules.cfg(data)["scout"]["minutes"]))
			lines.append_array(PetRules.scout(s, data, id, arg))
			return lines],
		"rename": [func() -> String: return PetRules.pet_why(s, id) if not arg.strip_edges().is_empty() else "PET_BAD_NAME", PetRules.rename.bind(s, id, arg)],
	}, "PET_NOT_NOW")


## Work (v0.7.26): hire, a shift, quit — the engine decides; a shift's event goes to the master as a short turn.
func job_act(what: String, id: String) -> String:
	if not _at_leisure():
		return "JOB_NOT_NOW"
	var data := Catalog.data
	var s := session
	var out := {"lines": [], "event": "", "fight": []}  # what a shift brings beside its lines
	var why := _act(what, {
		"hire": _row(JobRules.hire_why, JobRules.hire, [s, data, id]),
		"shift": [JobRules.shift_why.bind(s, data, id), func() -> Array:  # the patrol may break the shift
			out["lines"] = _waited(JobRules.hours(s, data, id) * 60, func(m: int) -> Array:
				var r := JobRules.shift(s, data, id, m)
				out["event"] = str(r["event"])
				out["fight"] = r["fight"]
				return r["lines"])
			return out["lines"]],
		"quit": [func() -> String: return "" if JobRules.hired(s.character, id) else "JOB_NOT_HIRED", JobRules.quit.bind(s, data, id)],
	}, "JOB_NOT_NOW")
	if not why.is_empty():
		return why
	if not (out["fight"] as Array).is_empty():  # bandits at the convoy (v0.7.39.1)
		session.pending_fight = out["fight"]
		_start_pending_fight()
	elif not str(out["event"]).is_empty() and Backend.is_ready():
		_request("shift", "%s. Событие смены: %s" % ["; ".join(PackedStringArray(out["lines"])), out["event"]])
	return ""


## Property (v0.7.27): buy, deed, collect, shift, worker, serf, repair, animal, release — the
## engine's acts by the buttons of the property window. "" or a localization key.
func property_act(what: String, id: String, arg: String = "") -> String:
	if not _at_leisure():
		return "PROPERTY_NOT_NOW"
	var data := Catalog.data
	var s := session
	var a := [s, data, id]
	var b := a + [arg]  # arg — the role of a worker (v0.7.39.5), the person fired, the serf, the upgrade, the thing built
	var rent := a + [arg.get_slice(":", 0), int(arg.get_slice(":", 1))]  # v0.7.42: arg «monster:days»
	return _act(what, {
		"buy": _row(PropertyRules.buy_why, PropertyRules.buy, a),
		"deed": _row(PropertyRules.deed_why, PropertyRules.deed, a),
		"collect": _row(PropertyRules.collect_why, PropertyRules.collect, a),
		"tax": _row(PropertyRules.pay_tax_why, PropertyRules.pay_tax, a),
		"shift": [PropertyRules.shift_why.bindv(a), func() -> Array:
			return _waited(PropertyRules.shift_hours(s, data, id) * 60, func(m: int) -> Array:  # the patrol may break the work
				return PropertyRules.shift(s, data, id, m) if PropertyRules.owned(s.character, id) else [])],
		"repair": [PropertyRules.repair_why.bindv(a), func() -> Array:
			return _waited(PropertyRules.repair_hours(s, data, id) * 60, func(m: int) -> Array:
				return PropertyRules.repair(s, data, id, m) if PropertyRules.owned(s.character, id) else [])],
		"hire": _row(PropertyRules.worker_why, PropertyRules.hire_worker, b),
		"fire": _row(PropertyRules.fire_why, PropertyRules.fire, b),
		"serf": _row(PropertyRules.serf_why, PropertyRules.set_serf, b),
		"animal": _row(PropertyRules.animal_why, PropertyRules.buy_animal, b),
		"rent": _row(MountRules.rent_why, MountRules.rent, rent),
		"sell_animal": _row(MountRules.sell_why, MountRules.sell, b),
		"vehicle": _row(MountRules.vehicle_why, MountRules.buy_vehicle, b),
		"release": [func() -> String: return "" if not CreatureRules.find(s, s.room_id, id).is_empty() else "CREATURE_NONE", func() -> Array:
			var cr := CreatureRules.find(s, s.room_id, id)
			MountRules.unload(s, data, cr)  # v0.7.42: the pack comes off first
			PropertyRules.remove_creature(s, id)
			return ["%s отпущен на волю" % cr.get("name", id)]],
	})


## The build screen (v0.8.4.42): «build» a row of the catalog `id` on `cell` (a passage's room named `name`), «remove»
## what the hands built there. "" or a localization key.
func build_act(what: String, id: String, cell: Vector2i, name: String = "") -> String:
	if not _at_leisure():
		return "BUILD_NOT_NOW"
	var data := Catalog.data
	return _act(what, {
		"build": [BuildRules.build_why.bindv([session, data, id, cell, name]), BuildRules.build.bindv([session, data, id, cell, name, Being.HERO, _build_tally])],
		"remove": [BuildRules.remove_why.bindv([session, data, cell]), BuildRules.remove.bindv([session, data, cell, Being.HERO, _build_tally])],
	}, "BUILD_NOT_NOW")


## The build screen closed: one line of what the hands built and took away while it was open.
func build_done() -> void:
	var lines := BuildRules.summary(_build_tally)
	_build_tally.clear()
	if not lines.is_empty() and has_session():
		_effect_lines(lines, true)


## Own trade (v0.7.29): put / take (vid, arg — the item, amount — qty), price (arg — the item, amount ±1), collect,
## shift, hire (arg — the role), fire (arg — the person) (vid); charter, rent (npc, arg — the kind, amount — days);
## wholesale (npc, arg — the item). "" or a localization key.
func shop_act(what: String, id: String, arg: String = "", amount: int = 0) -> String:
	if not _at_leisure():
		return "PROPERTY_NOT_NOW"
	var data := Catalog.data
	var s := session
	var a := [s, data, id]
	var b := a + [arg]
	var rent := a + [arg if not arg.is_empty() else "stall", amount]
	return _act(what, {
		"put": [ShopRules.put_why.bindv(b), ShopRules.put.bindv(b + [maxi(1, amount)])],
		"take": _row(ShopRules.take_why, ShopRules.take, b),
		"price": [ShopRules.price_step_why.bindv(b + [amount]), func() -> Array:
			ShopRules.price_step(s, data, id, arg, amount)
			return []],
		"collect": _row(ShopRules.collect_why, ShopRules.collect, a),
		"shift": [ShopRules.shift_why.bindv(a), func() -> Array:
			return _waited(ShopRules.shift_hours(data) * 60, func(m: int) -> Array: return ShopRules.shift(s, data, id, m))],  # the patrol may break the trade
		"charter": _row(ShopRules.charter_why, ShopRules.charter, a),
		"rent": _row(PropertyRules.rent_why, PropertyRules.rent, rent),
		"wholesale": _row(ShopRules.wholesale_why, ShopRules.wholesale, b),
		"hire": _row(PropertyRules.worker_why, PropertyRules.hire_worker, b),
		"fire": _row(PropertyRules.fire_why, PropertyRules.fire, b),
	})


## Study (v0.7.30): exam (id — a school), enroll, lesson, drop (id — a course). "" or a localization key.
## Family (v0.7.32): propose (id — the partner), wedding (id — the officiant), child, rename (id — the child, arg — the
## name). "" or a localization key.
func family_act(what: String, id: String = "", arg: String = "") -> String:
	if not _out_of_fight():
		return "PROPERTY_NOT_NOW"
	var s := session
	var a := [s, Catalog.data, id]
	return _act(what, {
		"propose": _row(FamilyRules.propose_why, FamilyRules.propose, a),
		"wedding": _row(FamilyRules.wedding_why, FamilyRules.wedding, a),
		"child": _row(FamilyRules.child_why, FamilyRules.try_child, [s, Catalog.data]),
		"rename": [func() -> String: return "" if FamilyRules.children(s).has(id) and not arg.strip_edges().is_empty() else "FAMILY_BAD_NAME", FamilyRules.rename.bindv(a + [arg])],
	})


## Criminal jobs (v0.7.33): take (a job of the world), step (arg — the preparation), act, give_up. "" or a key.
func heist_act(what: String, id: String, arg: String = "") -> String:
	if not _at_leisure():
		return "PROPERTY_NOT_NOW"
	var data := Catalog.data
	var s := session
	var a := [s, data, id]
	var err := _act(what, {
		"step": [HeistRules.step_why.bindv(a + [arg]), func() -> Array:
			return _waited(HeistRules.step_minutes(s, data, id, arg), func(_m: int) -> Array: return HeistRules.step(s, data, id, arg), true)],  # the patrol may break it off
		"act": [HeistRules.act_why.bindv(a), func() -> Array:
			return _waited(HeistRules.act_minutes(s, data, id), func(_m: int) -> Array:
				var r := HeistRules.act(s, data, id)
				s.pending_fight = r["fight"]
				return r["lines"], true)],
		"give_up": [func() -> String: return "" if HeistRules.status(s.character, id) == "active" else "HEIST_NOT_ACTIVE", HeistRules.give_up.bindv(a)],
	})
	if err.is_empty() and what == "act" and not s.pending_fight.is_empty():
		_start_pending_fight()
	return err


## Organizations (v0.7.33): join, leave, pay, take (arg — a job), found (arg — the name, id — the place), recruit
## (id — the NPC). "" or a localization key.
func org_act(what: String, id: String, arg: String = "") -> String:
	if not _out_of_fight():
		return "PROPERTY_NOT_NOW"
	var data := Catalog.data
	var s := session
	var a := [s, data, id]
	return _act(what, {
		"join": _row(OrgRules.join_why, OrgRules.join, a),
		"leave": [func() -> String: return "" if OrgRules.member(s.character, id) or OrgRules.candidate(s.character, id) else "ORG_NONE", OrgRules.leave.bindv(a)],
		"pay": _row(OrgRules.pay_why, OrgRules.pay, a),
		"take": [OrgRules.take_why.bindv(a + [arg]), HeistRules.take.bind(s, data, arg)],
		"found": _row(OrgRules.found_why, OrgRules.found, [s, data, arg, id]),
		"recruit": _row(OrgRules.recruit_why, OrgRules.recruit, a),
		"entry": _row(OrgRules.entry_why, OrgRules.pay_entry, a),
	})


## The hero's offices (v0.7.34): appoint / elect / buy / leave (id — the office), decide (arg — "<case>:<option>"), tax
## (arg — the level), build (arg — the project). A decision takes the case's time (the patrol may break it off).
func office_act(what: String, id: String, arg: String = "") -> String:
	if not _at_leisure():
		return "PROPERTY_NOT_NOW"
	var data := Catalog.data
	var s := session
	var idx := int(arg.get_slice(":", 0)) if what == "decide" else -1
	var opt := arg.get_slice(":", 1) if what == "decide" else ""
	var a := [s, data, id]
	return _act(what, {
		"appoint": _row(OfficeRules.appoint_why, OfficeRules.appoint, a),
		"elect": _row(OfficeRules.elect_why, OfficeRules.elect, a),
		"buy": _row(OfficeRules.buy_why, OfficeRules.buy, a),
		"leave": [func() -> String: return "" if OfficeRules.holds(s.character, id) else "OFFICE_NOT_HELD", OfficeRules.leave.bindv(a)],
		"decide": [OfficeRules.decide_why.bindv(a + [idx, opt]), func() -> Array:
			return _waited(int(OfficeRules.cfg(data)["case_minutes"]), func(_m: int) -> Array: return OfficeRules.decide(s, data, id, idx, opt), true)],
		"tax": _row(OfficeRules.tax_why, OfficeRules.set_tax, a + [arg]),
		"build": _row(OfficeRules.build_why, OfficeRules.build, a + [arg]),
	})


## The hero died and an adult child goes on (v0.7.32): the heir's character takes the dead hero's place in the same
## game — its coins, things, places and family; the world and what it knows stay.
func continue_as_heir(character: Dictionary) -> void:
	var s := session
	if s == null or character.is_empty() or FamilyRules.heir(s, Catalog.data).is_empty():
		EventBus.navigate.emit("menu", {})
		return
	var old := str(s.character.get("name", ""))
	var lines := FamilyRules.inherit(s, Catalog.data, character)
	s.character = character
	CombatRules.close(s)
	s.mode = GameSession.MODE_EXPLORATION
	s.npc_id = ""
	s.pending_fight = []
	Being.clear(s, "follows")
	s.wanted = {}
	s.arrest = ""
	s.let_go = {}
	s.sneaking = false
	var home := str(FamilyRules.view(character).get("home_room", ""))
	if not home.is_empty():
		s.room_id = home
	start(s)
	_add(GameSession.effect_entry(lines))
	SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	_request("enter", "%s погиб(ла). Дальше играет наследник — %s: просыпается дома, род продолжается." % [old, character.get("name", "")])


## «Попросить впустить» (v0.7.39.2): Persuasion against the owner of a private site. Allowed in a talk too. "" or a key.
func permit_ask(npc_id: String) -> String:
	if not _out_of_fight():
		return "PROPERTY_NOT_NOW"
	if not session.npcs_here(world().world, session.room_id).has(npc_id):
		return "PROPERTY_NOT_NOW"
	var why := SiteRules.ask_why(session, Catalog.data, npc_id)
	if not why.is_empty():
		return why
	var lines := SiteRules.ask(session, Catalog.data, npc_id)
	_effect_lines(lines, true)
	return ""


## Bonds (v0.7.31): gift (item — the thing), confess, break, hide. Allowed in a talk too. "" or a localization key.
func bond_act(what: String, npc_id: String, item: String = "") -> String:
	if not _out_of_fight():
		return "PROPERTY_NOT_NOW"
	var a := [session, Catalog.data, npc_id]
	return _act(what, {
		"gift": _row(BondRules.gift_why, BondRules.gift, a + [item]),
		"confess": _row(BondRules.confess_why, BondRules.confess, a),
		"break": _row(BondRules.break_why, BondRules.break_off, a),
		"hide": _row(BondRules.hide_why, BondRules.hide, a),
	})


func study_act(what: String, id: String) -> String:
	if not _at_leisure():
		return "PROPERTY_NOT_NOW"
	var data := Catalog.data
	var s := session
	var a := [s, data, id]
	return _act(what, {
		"exam": _row(StudyRules.exam_why, StudyRules.exam, a),
		"enroll": _row(StudyRules.enroll_why, StudyRules.enroll, a),
		"lesson": [StudyRules.lesson_why.bindv(a), func() -> Array:
			return _waited(StudyRules.lesson_hours(data) * 60, func(m: int) -> Array: return StudyRules.lesson(s, data, id, m))],  # the patrol may break the lesson
		"drop": [func() -> String: return "" if StudyRules.enrolled(s.character, id) else "STUDY_NOT_ENROLLED", StudyRules.drop.bindv(a)],
	})


## The bank (v0.7.28): deposit (arg — the term, amount), withdraw (arg — the contract), loan (arg — «kind:id» of the
## collateral, days), repay, put / take (arg — an item; none — coins by amount). "" or a localization key.
func bank_act(what: String, npc_id: String, arg: String = "", amount: int = 0, days: int = 0) -> String:
	if not _at_leisure():
		return "PROPERTY_NOT_NOW"
	var data := Catalog.data
	var s := session
	var col := arg.split(":", true, 1)
	var a := [s, data, npc_id]
	var loan := a + [col[0], col[1] if col.size() > 1 else "", days]
	return _act(what, {
		"deposit": _row(BankRules.deposit_why, BankRules.deposit, a + [arg, amount]),
		"withdraw": _row(BankRules.withdraw_why, BankRules.withdraw, [s, data, arg]),
		"loan": _row(BankRules.loan_why, BankRules.loan, loan),
		"repay": _row(BankRules.repay_why, BankRules.repay, [s, data, arg]),
		"put": _row(BankRules.vault_why, BankRules.vault_move, a + ["in", arg, amount]),
		"take": _row(BankRules.vault_why, BankRules.vault_move, a + ["out", arg, amount]),
	})


## 18+ of this game (v0.7.38.7): the master's intimate scenes and the images; never with a child or a teen.
func set_adult(on: bool) -> void:
	if session != null:
		session.settings["adult"] = on
		EventBus.state_changed.emit()


func set_needs(on: bool) -> void:
	if session != null:
		session.settings["needs"] = on
		if on:  # the needs start full again: no hunger for the days they were off
			session.character.erase("needs")
		NeedRules.tick(session, Catalog.data)
		EventBus.state_changed.emit()


func set_difficulty(id: String) -> void:
	if session != null and DifficultyRules.levels(Catalog.data).has(id):
		session.settings["difficulty"] = id


## v0.8.4.37: how many heroes the master's fights are made for.
func set_party(n: int) -> void:
	if session != null and DifficultyRules.party_sizes(Catalog.data).has(n):
		session.settings["party"] = n


func set_dm_style(style: String) -> void:
	if session != null and WorldPack.DM_STYLES.has(style):
		session.settings["dm_style"] = style


func start(s: GameSession) -> void:
	s.settings["reactions"] = SaveManager.reactions  # the player's choice of the settings (v0.7.10)
	# v0.7.20: this game's world — the pack's with what the master made in it (a copy; the pack is never touched)
	var pack: Dictionary = Catalog.bundle(Catalog.active_world).get("world", Catalog.data["world"])
	Catalog.data["world"] = WorldGen.merged(pack, s.generated)
	MakeRules.install(Catalog.data, s.generated)  # v0.7.63: and the rules with its own statuses and skills
	CharacterRules.refresh(s.character, Catalog.data, s.items)
	ExplorationRules.enter_room(s, Catalog.data["world"], s.room_id)
	TimeRules.settle(s, Catalog.data)  # the festivals' flags and the weather by the date of a save (v0.7.44, v0.7.46)
	session = s
	busy_turn = ""
	_last_kind = ""
	effects = EffectEngine.new()
	_ahead = {}
	_ahead_stop = -1
	_act_told = {}
	EventBus.session_started.emit()
	_prepare.call_deferred()


func close_session() -> void:
	cancel_turn()
	session = null
	busy_turn = ""
	EventBus.session_closed.emit()


## An option button of the master: a paid one (option_costs, v0.6.5) takes the coins first — the engine, not the
## master's words; the turn input tells the master it is paid. "" or a localization key.
func choose_option(index: int) -> String:
	if session == null or index < 0 or index >= session.options.size():
		return "MSG_NO_MASTER"
	var text := session.options[index]
	var cost := session.option_costs[index] if index < session.option_costs.size() else 0
	var check: Dictionary = option_check(index)
	if cost <= 0:
		return "" if submit(text, "", check) else "MSG_NO_MASTER"
	if Ledger.balance(session) < cost:
		return "MSG_NO_MONEY"
	if is_busy() or not Backend.is_ready():
		return "MSG_NO_MASTER"
	Ledger.add(session, -cost, "game_state:choose_option")
	var paid := "−" + Money.format(cost)
	_add(GameSession.effect_entry([paid]))
	_log("События: " + paid)
	EventBus.state_changed.emit()
	return "" if submit(text, "[движок уже списал %s]" % Money.format(cost), check) else "MSG_NO_MASTER"


## The check of a master's option (v0.7.22.28, П5): {skill, dc_tier} or {}.
func option_check(index: int) -> Dictionary:
	if session == null or index < 0 or index >= session.option_checks.size() or not session.option_checks[index] is Dictionary:
		return {}
	return session.option_checks[index]


## What the engine would roll for an option: {skill, dc, bonus, chance (%), dc_reason}; {} — no check. The same spec as the
## roll (CheckEngine.preview): the DC by the tier or the listener's template, every advantage and disadvantage of the moment.
func option_preview(index: int) -> Dictionary:
	var check := option_check(index)
	if check.is_empty():
		return {}
	var r := CheckEngine.preview(session, Catalog.data, check)
	if r.has("error"):
		return {}
	r["skill"] = str(check["skill"])
	return r


## «Ждать» (v0.6.5): an hour or until a part of the day; not in a conversation or a fight. The master tells how the
## time passed (kind=wait). "" or a localization key.
func wait(target: String) -> String:
	return wait_for(TimeRules.minutes_until(session, Catalog.data, target)) if session != null else "WAIT_BUSY"


## «Ждать» a number of minutes the player wrote (v0.8.4.2), up to `time.wait_max_minutes`.
func wait_for(minutes: int) -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var mins := mini(minutes, int(TimeRules.cfg(Catalog.data)["wait_max_minutes"]))
	if mins <= 0:
		return "WAIT_NOT_NOW"
	var lines: Array[String] = ["Ожидание до %s" % TimeRules.clock_after(session, mins)]
	lines.append_array(CrimeRules.wait(session, Catalog.data, mins)["lines"])  # the patrol looks in on the way (v0.7.22.18)
	_effect_lines(lines)
	_request("wait", "; ".join(lines))
	return ""


## Returns false when the input cannot be sent now (empty, a turn in flight, no master). `engine_note` goes to the
## master after the text (a paid option), never into the chat.
func submit(text: String, engine_note: String = "", check: Dictionary = {}) -> bool:
	text = text.strip_edges()
	var pinned := not attached.is_empty() and session != null and session.mode != GameSession.MODE_COMBAT
	if session == null or (text.is_empty() and not pinned) or is_busy() or not Backend.is_ready():
		if session != null and text.is_empty() and not pinned_check.is_empty() and not is_busy():
			EventBus.message.emit(tr("CHECK_PIN_NEEDS_WORDS"))
		return false
	var pin := pinned_check if session.mode != GameSession.MODE_COMBAT and not text.is_empty() else {}
	var hostile := pinned and _hostile_attach(attached)  # v0.7.22.16: a blow or a hostile spell at an NPC — the fight
	if pinned and text.is_empty() and not hostile:  # the attachment alone: a cast as from the sheet
		var why := _use_alone(attached)
		if not why.is_empty():
			EventBus.message.emit(tr(why))
			return false
		attached = {}
		return true
	if session.mode == GameSession.MODE_COMBAT:
		if not CombatRules.player_can_act(session) or int(CombatRules.economy(session).get("action", 0)) <= 0:
			EventBus.message.emit(tr("COMBAT_NO_ACTION"))
			return false
		CombatRules.economy(session)["action"] = int(CombatRules.economy(session)["action"]) - 1
	var facts := ""
	if pinned:
		var backup := session.character.duplicate(true)
		var spent := _spend(attached)
		if spent.has("reason"):
			EventBus.message.emit(tr(str(spent["reason"])))
			return false
		_refund = backup
		_refund_what = attached
		_retry_spend = {}
		_opening = {}
		var data: Dictionary = Catalog.data
		if str(attached.get("kind", "")) == "spell" and not str(attached.get("target", "")).is_empty() and CombatRules.is_engine_spell(data, str(attached["id"])):
			_opening = {"spell": str(attached["id"]), "slot": int(attached.get("spent_slot", 0)), "npc_id": str(attached["target"])}
			spent["facts"] = str(spent["facts"]) + " Если этим игрок нападает на NPC — начни бой с ним (next_mode combat): исход заклинания движок разрешит первым ходом боя, урон и последствия не описывай."
		var target := str(attached.get("target", ""))
		attached = {}
		_add(GameSession.effect_entry(spent["lines"]))
		_log("События: " + ", ".join(spent["lines"]))
		facts = " [Вместе с этим, до слов игрока: %s]" % spent["facts"]
		if hostile:  # v0.7.22.16 (#26): a blow or a hostile spell at an NPC is an attack — the engine starts the fight
			var op := _opening.duplicate()
			_refund = {}
			_refund_what = {}
			if not text.is_empty():
				_add(GameSession.player_entry(text))
				_log("Игрок: " + text)
			if session.npcs_here(world().world, session.room_id).has(target):
				return attack_npc(target, op).is_empty()
			return encounter_attack(true, op).is_empty()  # v0.8.4.30: at a foe seen before the fight
	_add(GameSession.player_entry(text))
	_log("Игрок: " + text)
	_forced = {}
	if not pin.is_empty():  # v0.7.36: the player's own check — the engine holds the master to it
		pinned_check = {}
		facts += _pinned_note(pin)
		_forced = pin.duplicate()
		_forced["fresh"] = true
	if not check.is_empty() and session.mode != GameSession.MODE_COMBAT:  # a tagged option: the engine rolls first (v0.7.22.28)
		var r := _engine_check(check.duplicate())
		if not r.has("error"):
			engine_note = ("%s [движок уже бросил для варианта: %s %d против Сл %d — %s%s]" % [engine_note, tr("SKILL_" + str(check["skill"]).to_upper()),
				int(r["total"]), int(r["dc"]), "успех" if bool(r["success"]) else "провал", ", повтор без изменений" if bool(r.get("blocked", false)) else ""]).strip_edges()
	_request("action", text + facts + ((" " + engine_note) if not engine_note.is_empty() else ""))
	return true


## Exit button: the engine moves the player (no model decision), then the master describes the new room.
func go(room_id: String) -> bool:
	if session == null or is_busy() or not Backend.is_ready() or not WayRules.open_exits(session, Catalog.data["world"], session.room_id).has(room_id):
		return false
	var why := WayRules.leave_why(session, Catalog.data, session.room_id, room_id)
	if not why.is_empty():
		EventBus.message.emit(tr(why))
		return false
	_end_conversation()
	var from := session.room_id
	var lines: Array[String] = []
	var trap := ExplorationRules.trap_on_exit(session, Catalog.data["world"], from, room_id)
	if not trap.is_empty():
		var seen := ExplorationRules.approach(session, Catalog.data, from, trap)
		if not seen.is_empty():
			_effect_lines(["Замечено: " + seen] as Array[String])
		if ExplorationRules.is_found(session, from, trap):
			EventBus.message.emit(tr("TRAP_ON_WAY"))
			return false  # a found trap: disarm it or go around it (trap_action)
		lines = ExplorationRules.spring_trap(session, Catalog.data, from, trap)
		if _trap_downed(lines):
			return true
	_move_to(room_id, lines)
	return true


## Steps into `room_id`: time passes, passive Perception (sneaking, darkness), caches, quest steps; an encounter
## starts the fight, otherwise the master describes the room. `lines` — what happened on the way (a trap).
func _move_to(room_id: String, lines: Array[String], announce: bool = true) -> void:
	var from := session.room_id
	_set_options([])  # what was offered here stays here
	_step(room_id, lines)
	if announce:  # the master's move already showed «Переход» among its effects (v0.7.22.16)
		lines.push_front("Переход: %s" % world().room(room_id).get("name", room_id))
	if not lines.is_empty():
		_add(GameSession.effect_entry(lines))
	EventBus.state_changed.emit()
	if not session.pending_fight.is_empty():  # v0.7.39.2: an organization's guards on a stranger in its hideout
		_start_pending_fight()
		return
	var enc := EncounterRules.live(session, Catalog.data, room_id)  # by the flags (v0.7.14.1)
	if not enc.is_empty():
		var meet := EncounterRules.meet(session, Catalog.data, room_id, from, enc)  # who sees whom (v0.7.22.12, v0.8.3)
		if meet.has("line"):
			_add(GameSession.effect_entry([str(meet["line"])]))
			EventBus.state_changed.emit()
			_request("enter", "\n".join(lines.slice(1) + [str(meet["line"])]))
			return
		if not (meet["lines"] as Array).is_empty():
			_add(GameSession.effect_entry(meet["lines"]))
			lines.append_array(meet["lines"])
		if bool(meet["fight"]):
			session.lurking.erase(room_id)
			start_combat(EncounterRules.heads(session, Catalog.data, room_id, enc), EncounterRules.source(enc, from, meet["source"]))
			return
	var again := ExplorationRules.again_line(session, Catalog.data, room_id) if lines.size() <= 1 else ""
	if not again.is_empty():  # described today and nothing on the way: the engine's line, no master (v0.7.22.20, #8)
		_effect_lines([again] as Array[String], true)
		return
	session.described[room_id] = session.day
	if not _enter_ready(lines):
		_request("enter", "\n".join(lines.slice(1)))


## The room's description readied with its furnishing (v0.8.4.25.3): told at once, without the master, when nothing
## happened on the way and the hour, the weather and the people are as they were; a furnishing the world refuses now
## leaves the entry to the master.
func _enter_ready(lines: Array[String]) -> bool:
	var s := session
	var text := PrepareRules.told(s, Catalog.data, s.room_id) if lines.size() <= 1 else ""
	if text.is_empty() or not PropRules.needs_furnish(s, s.room_id):  # told of the things it lays, not of others
		return false
	_lay_furnishing(s)
	if PropRules.needs_furnish(s, s.room_id):
		return false
	_add(GameSession.dm_entry(text, s.next_turn_id()))
	EventBus.state_changed.emit()
	SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	_maybe_summarize_location()
	_maybe_tell_quests()
	_prepare()
	_after_turn(s, "enter")
	return true


## The engine side of a step into `room_id` (no master, no fight): sneaking past people, time, passive Perception,
## caches, quest steps. Appends the lines; returns what passive Perception found on entering.
func _step(room_id: String, lines: Array[String]) -> Array[String]:
	var from := session.room_id
	if session.sneak_noticed != room_id:
		session.sneak_noticed = ""  # a new room: people there have not seen the player sneak yet
	var past := EncounterRules.slip_past(session, from, room_id)  # a quest's «пройти стражу» (v0.7.49.3)
	if not past.is_empty():
		lines.append(past)
	EncounterRules.unlurk(session, from)  # the unaware foes are left behind (v0.7.22.12)
	if session.sneaking:
		var seen := _sneak_past_people(room_id)
		if not seen.is_empty():
			lines.append(seen)
	lines.append_array(MountRules.on_move(session, Catalog.data, from, room_id))  # a beast waits where it cannot go (v0.7.42)
	lines.append_array(ConditionRules.left_room(session.character, room_id))  # Magic Circle stays behind (v0.8.4.26.3)
	lines.append_array(WayRules.on_pass(session, Catalog.data, from, room_id))  # a way down is a fall (v0.7.66)
	lines.append_array(TimeRules.on_move(session, Catalog.data, from, room_id))
	CreatureRules.follow(session, from, room_id)  # a bound captive on the rope (v0.7.22.11)
	PetRules.seed(session, Catalog.data, room_id)  # the pack's wild beasts to tame (v0.7.43)
	var gone := PropRules.abandon(session, Catalog.data, room_id)  # big test #28 (v0.7.22.8)
	if not gone.is_empty():
		lines.append("Того, что вы здесь оставили, уже нет: " + ", ".join(gone))
	var found := ExplorationRules.enter_room(session, Catalog.data["world"], room_id, TimeRules.passive_penalty(session, Catalog.data))
	lines.append_array(SiteRules.on_enter(session, Catalog.data, room_id))  # a private room unasked (v0.7.22.24)
	lines.append_array(RumorRules.on_enter(session, Catalog.data, room_id))  # a heard tip checked (v0.7.47)
	lines.append_array(LetterRules.on_enter(session, Catalog.data, room_id))  # a helper called by letter waits here (v0.7.48)
	lines.append_array(DiseaseRules.contagion(session, Catalog.data))  # a sick NPC here (v0.7.23.1)
	lines.append_array(ExplorationRules.take_caches(session, Catalog.data, room_id))
	lines.append_array(QuestRules.advance(session, Catalog.data))
	lines.append_array(CrimeRules.check_arrest(session, Catalog.data))  # the wanted hero meets the guard (v0.7.14)
	return found


## The hero stands on a new square of `map` (a click's walk, a round of sneaking): what passive Perception finds, a trap
## underfoot, who sees whom. While the master's turn runs a danger waits for its end. True — the walk stops here.
func walked(map: Dictionary) -> bool:
	if session == null or session.mode == GameSession.MODE_COMBAT or session.in_conversation():
		return true
	var s := session
	var data: Dictionary = Catalog.data
	var cell := WalkRules.settle(s, data, map)
	var said := ExplorationRules.notice(s, data, map, cell)
	var trap := ExplorationRules.trap_at(s, data, map, cell)
	var eyes := EncounterRules.watch(s, data, map)
	said.append_array(eyes["lines"])
	if not said.is_empty():
		_effect_lines(said)
	var fight := bool(eyes["fight"])
	if trap.is_empty() and not fight:
		return eyes.has("new_sight")
	if is_busy() or not Backend.is_ready():
		return true
	if not trap.is_empty():
		var lines := ExplorationRules.spring_trap(s, data, s.room_id, trap)
		if not _trap_downed(lines):
			_effect_lines(lines)
			_request("trap", "\n".join(lines))
		return true
	var lk := EncounterRules.lurking(s, s.room_id)
	var enc := EncounterRules.lurking_encounter(s, data, s.room_id)
	s.lurking.erase(s.room_id)
	start_combat(enc["enemies"], EncounterRules.source(enc, str(lk.get("from", "")), eyes["source"]))
	return true


## A round of a sneaking walk is over: those who watch turn.
func sneak_round() -> void:
	if session == null or session.mode == GameSession.MODE_COMBAT:
		return
	WatchRules.next_round(session)
	walked(WalkRules.view(session, Catalog.data))
	EventBus.state_changed.emit()


## «Идти сюда» on the map (roadmap v0.7.6, decisions of the author): a fast travel to a visited room along known
## paths. The engine walks the route step by step without the master: time, sneaking, passive Perception, caches,
## quest steps; the line «Путь: … · N мин» goes to the chat and the history. It stops on a live encounter (that
## step is an ordinary move — the fight starts), on a trap that springs (an ordinary move — the master tells it)
## and before an exit whose trap the hero has just noticed. "" or a localization key.
func travel(to: String) -> String:
	if session == null or is_busy() or not Backend.is_ready() or session.mode == GameSession.MODE_COMBAT:
		return "TRAVEL_BUSY"
	var path := WorldMap.route(session, Catalog.data["world"], session.room_id, to, Catalog.data)  # a locked door stops the way (v0.7.22.25)
	if path.is_empty():
		return "TRAVEL_NO_ROUTE"
	var why := WayRules.leave_why(session, Catalog.data, session.room_id, path[0])
	if not why.is_empty():
		return why
	_walk(path)
	return ""


## The dev console's `goto` (Dev): straight into any room of the world, walked as one step of fast travel — no master
## turn; the room's encounter starts its fight as walking in would. "" or the reason.
func teleport(to: String) -> String:
	if session == null or is_busy() or session.mode == GameSession.MODE_COMBAT:
		return "TRAVEL_BUSY"
	if world().room(to).is_empty():
		return "нет комнаты %s" % to
	_walk([to])
	return ""


## The rooms of `path` walked one by one by the engine, no master turn: it stops on a live encounter or a trap (an ordinary
## move), before a found trap, at death, a hold or a fight that waits (`travel`).
func _walk(path: Array) -> void:
	_end_conversation()
	var names: Array[String] = [str(world().room(session.room_id).get("name", session.room_id))]
	var lines: Array[String] = []
	var minute0 := session.day * 1440 + session.minute
	for to_room: String in path:
		var from := session.room_id
		var trap := ExplorationRules.trap_on_exit(session, Catalog.data["world"], from, to_room)
		if not trap.is_empty():
			ExplorationRules.approach(session, Catalog.data, from, trap)
		if not trap.is_empty() and ExplorationRules.is_found(session, from, trap):
			lines.append("Дальше путь стережёт найденная ловушка — переход остановлен")
			break
		if not trap.is_empty() or not EncounterRules.live(session, Catalog.data, to_room).is_empty():
			_travel_line(names, minute0, lines)
			var step_lines: Array[String] = []
			if not trap.is_empty():
				step_lines = ExplorationRules.spring_trap(session, Catalog.data, from, trap)
				if _trap_downed(step_lines):
					return
			_move_to(to_room, step_lines)
			return
		for f: String in _step(to_room, lines):
			lines.append("Замечено: " + f)
		names.append(str(world().room(to_room).get("name", to_room)))
		if ConditionRules.dead(session.character) or CrimeRules.held(session) or not session.pending_fight.is_empty():
			break
	_travel_line(names, minute0, lines)
	_set_options([])  # the old room's replies do not follow the hero (big test #34, v0.7.22.5)
	EventBus.state_changed.emit()
	if not session.pending_fight.is_empty():  # v0.7.39.2: a hideout's guards on the way
		_start_pending_fight()
		return
	if _exhaustion_death():
		return
	SaveManager.save_slot(SaveManager.AUTOSAVE, session)


## «Путь: A → B → C · N мин» and what happened on the way, into the chat and the history (no master turn).
func _travel_line(names: Array[String], minute0: int, lines: Array[String]) -> void:
	if names.size() < 2 and lines.is_empty():
		return
	var all: Array[String] = ["Путь: %s · %s" % [" → ".join(names), TimeRules.span(session.day * 1440 + session.minute - minute0)]]
	all.append_array(lines)
	_told(all)


## A trap brought the character to 0 HP outside combat: they come to on the spot (no death), the master tells the
## cost. True when that happened (the move does not go on).
func _trap_downed(lines: Array[String]) -> bool:
	if int(session.character["hp"]) > 0:
		return false
	lines.append_array(ExplorationRules.knock_out(session))
	_effect_lines(lines)
	_request("downed", "")
	return true


## A found trap on the exit to `to`: «Обезвредить» (Sleight of Hand with thieves' tools) — success spends it,
## the player stays; «Обойти» (Acrobatics) — success passes on. Both against disarm_dc; a failure springs the trap.
## "" or a localization key.
func trap_action(to: String, disarm: bool, trap_id: String = "") -> String:
	if session == null or is_busy() or not Backend.is_ready() or session.in_conversation():
		return "TRAP_BUSY"
	var from := session.room_id
	var trap := ExplorationRules.trap_on_exit(session, Catalog.data["world"], from, to) if trap_id.is_empty() \
		else ExplorationRules.found_trap(session, Catalog.data["world"], from, trap_id)
	if trap.is_empty() or not ExplorationRules.is_found(session, from, trap):
		return "TRAP_NONE"
	if disarm and not BackgroundRules.has_tool(session.character, "thieves_tools"):
		return "PICK_NO_TOOLS"
	var t: Dictionary = trap["trap"]
	var result := _lock_roll("pick" if disarm else "dodge", int(t["disarm_dc"]), str(trap["id"]))
	var lines: Array[String] = []
	if bool(result["success"]):
		if disarm:
			ExplorationRules.disarm_trap(session, from, trap)
			lines.append("Ловушка обезврежена: %s" % trap["text"])
			_effect_lines(lines)
			_request("trap", "\n".join(lines))
			return ""
		lines.append("Ловушка обойдена — она по-прежнему на месте")
		_move_to(to, lines)
		return ""
	lines = ExplorationRules.spring_trap(session, Catalog.data, from, trap)
	if _trap_downed(lines):
		return ""
	if disarm:
		_effect_lines(lines)
		_request("trap", "\n".join(lines))
		return ""
	_move_to(to, lines)
	return ""


## The giver's button: take a quest with steps (QuestRules); the master plays the giver (kind=quest). "" or a key.
func accept_quest(quest_id: String) -> String:
	if not _master_ready():
		return "QUEST_BUSY"
	var why := QuestRules.can_accept(session, Catalog.data["world"], quest_id)
	if why.is_empty():
		why = QuestGen.can_take(session, Catalog.data, quest_id)  # v0.7.21.2: the limit of taken made quests
	if not why.is_empty():
		return why
	var q := QuestRules.quest(Catalog.data["world"], quest_id)
	var lines := QuestRules.accept(session, Catalog.data, quest_id)
	lines.append_array(_lay_acts(session))  # v0.8.4.30: its first act readied while it hung on offer
	_refresh()
	_effect_lines(lines)
	_request("quest", "%s даёт игроку задание «%s». %s %s" % [world().npc(str(q["giver"])).get("name", ""), q["title"],
		str(q.get("offer_text", q.get("description", ""))), " ".join(lines.slice(1))])
	return ""


## «Прочитать объявления» (v0.7.22.13): an empty board — the master puts its orders up as real quests. "" or a key.
func read_board(prop_id: String) -> String:
	if not _master_ready():
		return "QUEST_BUSY"
	var why := QuestGen.board_why_not(session, Catalog.data, prop_id)
	if not why.is_empty():
		return why
	var p := PropRules.find(session, session.room_id, prop_id)
	var room_left := int(QuestGen.cfg(Catalog.data)["max_offered"]) - QuestGen.offered_by(session, "board:%s:%s" % [session.room_id, prop_id]).size()
	if room_left <= 0:  # still full of old orders: nothing new fits, no master's turn
		QuestGen.mark_board_read(session, prop_id)  # a new order marks it read when it is put up (QuestGen.apply_quest)
		EventBus.state_changed.emit()
		return ""
	var text := tr("BOARD_READ_SAY").format({"name": p.get("name", prop_id)})
	_add(GameSession.player_entry(text))
	_log("Игрок: " + text)
	var lines := _lay_prepared(session, PrepareRules.orders(session, session.room_id, prop_id))
	if not lines.is_empty():  # v0.8.4.25: the orders readied ahead are on it — no master's turn
		_effect_lines(lines)
		SaveManager.save_slot(SaveManager.AUTOSAVE, session)
		return ""
	_request("action", text + (" [движок: на «%s» [%s] есть место для новых заказов — повесь 1–%d настоящих заказа: сначала find_quests, потом create:quest с board_prop_id %s " +
		"и заказчиком из этой округи — живым человеком из find_npcs или новым в new_npcs самого create:quest (giver new:<key>), без отдельного create:npc; " +
		"каждый заказ — каркас: сложность (лучше разная: простое, среднее, сложное) и акты с целями, без шагов; " +
		"что написано в листках — это и есть эти задания, игрок возьмёт их кнопкой]") % [p.get("name", prop_id), prop_id, room_left, prop_id])
	return ""


## «Взять все» on a board (v0.7.22.13): every order that fits under the limit of taken quests, one master's turn. "" or a key.
func take_board_all(orders: Array) -> String:
	if not _master_ready():
		return "QUEST_BUSY"
	var lines: Array[String] = []
	var titles: Array[String] = []
	for qid: Variant in orders:
		if not QuestRules.can_accept(session, Catalog.data["world"], str(qid)).is_empty() or not QuestGen.can_take(session, Catalog.data, str(qid)).is_empty():
			continue
		lines.append_array(QuestRules.accept(session, Catalog.data, str(qid)))
		titles.append(str(QuestRules.quest(Catalog.data["world"], str(qid))["title"]))
	if titles.is_empty():
		return "QUEST_TOO_MANY"
	lines.append_array(_lay_acts(session))
	_refresh()
	_effect_lines(lines)
	_request("quest", "Игрок срывает с доски листки заказов: %s. %s" % [", ".join(titles), " ".join(lines)])
	return ""


## A talk step of a quest: the button at the NPC closes it (the item is handed over); the master narrates. "" or a key.
func quest_talk(quest_id: String) -> String:
	if not _master_ready():
		return "QUEST_BUSY"
	var why := QuestRules.can_talk(session, Catalog.data["world"], quest_id)
	if not why.is_empty():
		return why
	var step := QuestRules.current(session, Catalog.data["world"], quest_id)
	var lines := QuestRules.talk(session, Catalog.data, quest_id)
	_refresh()
	_effect_lines(lines)
	_request("quest", "%s Итог: %s." % [str(step.get("done_text", step["text"])), ", ".join(lines)])
	return ""


## A choice step of a quest (v0.6.4): the button in its room makes the choice — its rewards and world flag — and the
## master narrates it with the choice's done_text. "" or a localization key.
func quest_choose(quest_id: String, choice_id: String) -> String:
	if not _master_ready():
		return "QUEST_BUSY"
	var why := QuestRules.can_choose(session, Catalog.data["world"], quest_id, choice_id)
	if not why.is_empty():
		return why
	var c := QuestRules.choice(session, Catalog.data["world"], quest_id, choice_id)
	var lines := QuestRules.choose(session, Catalog.data, quest_id, choice_id)
	_refresh()
	_effect_lines(lines)
	_request("quest", "%s Итог: %s." % [str(c.get("done_text", c["action"])), ", ".join(lines)])
	return ""


## The arrest buttons (v0.7.14, CrimeRules): pay the wergild, sit in the stocks, or resist — then a fight. "" or a key.
func crime_answer(how: String) -> String:
	if not _master_ready():
		return "QUEST_BUSY"
	var why := CrimeRules.can_answer(session, Catalog.data, how)
	if not why.is_empty():
		return why
	var lines: Array[String] = []
	if CrimeRules.TALK.has(how):  # v0.7.22.2: talk the guard out of it — the engine rolls
		var loc := world().location_id(session.room_id)
		var result := _engine_check({"skill": CrimeRules.TALK[how], "dc_tier": CrimeRules.talk_tier(session, Catalog.data, loc)})
		if result.has("error"):
			return "MSG_MASTER_FAILED"
		lines = CrimeRules.talked(session, Catalog.data, how, bool(result["success"]))
	else:
		lines = CrimeRules.answer(session, Catalog.data, how)
	_effect_lines(lines)
	if not session.pending_fight.is_empty():  # resisted, or a threat that failed
		_start_pending_fight()
		return ""
	SaveManager.save_slot(SaveManager.AUTOSAVE, session)
	_request("law", "%s. Исход: %s" % [", ".join(lines), CrimeRules.outcome(session, Catalog.data)])
	return ""


## The foes lurking unaware (v0.7.22.12): attack them by surprise (or, `surprise` false, they saw the hero). "" or a key.
## `opening` — a spell already spent at one of them (v0.8.4.30): the engine resolves it as the first blow.
func encounter_attack(surprise: bool = true, opening: Dictionary = {}) -> String:
	if not _idle():
		return "WAIT_BUSY"
	var lk := EncounterRules.lurking(session, session.room_id)
	if lk.is_empty():
		return "ENCOUNTER_NONE"
	var enc := EncounterRules.lurking_encounter(session, Catalog.data, session.room_id)
	session.lurking.erase(session.room_id)
	var hid := WatchRules.sneaky(session, Catalog.data) or bool(lk.get("word", false)) or lk.has("foes")  # a charge across the field warns them
	var src := {"sneak": surprise and hid}
	if surprise and hid:
		src["stealth_total"] = 99  # nobody saw the hero: all caught off guard
		src["from_hiding"] = true
	if not opening.is_empty():
		src["opening"] = opening.merged({"unaware": surprise and hid}, true)
	start_combat(enc["enemies"], EncounterRules.source(enc, str(lk.get("from", "")), src))
	return ""


## The foes of the room the hero sees, before a fight (v0.8.4.30): [{id, name, monster…}] — their records.
func foes_here() -> Array:
	if session == null or CombatRules.active(session) or not EncounterRules.sighted(session, session.room_id):
		return []
	return (EncounterRules.lurking_encounter(session, Catalog.data, session.room_id).get("enemies", []) as Array) 		.filter(func(e: Dictionary) -> bool: return not Being.dead(session, EncounterRules.foe_id(e)))


## Who a pinned thing may aim at out of a fight (v0.8.4.30): the people here, then the foes seen. [{id, name, foe}]
func attach_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if session == null:
		return out
	for id: String in session.npcs_here(world().world, session.room_id):
		out.append({"id": id, "name": world().npc_name(id), "foe": false})
	for e: Dictionary in foes_here():
		out.append({"id": EncounterRules.foe_id(e), "name": str(e.get("name", e.get("monster", ""))), "foe": true})
	return out


## Who `id` is for a look (v0.8.4.41, the card of any creature): a fighter of the fight, a foe seen before it with its
## wounds, the hero, else its record — a person, a creature of the room, a follower. {} — nobody here.
func creature_who(id: String) -> Dictionary:
	if session == null or id.is_empty():
		return {}
	if id == Being.HERO:
		return Sheet.HERO
	if CombatRules.active(session):
		return CombatRules.fighter(session, id)
	for e: Dictionary in foes_here():
		if EncounterRules.foe_id(e) == id:
			var mx := int(e.get("max_hp", Sheet.template(Catalog.data, e).get("hp", 0)))
			return e.merged({"hp": int(e.get("hp", mx)), "max_hp": mx})
	if session.npcs_here(Catalog.data["world"], session.room_id).has(id) or not CreatureRules.find(session, session.room_id, id).is_empty() \
			or Being.follows(session, id):
		return Sheet.who(session, Catalog.data, id)
	return {}


## Why the hero may not look `id` over now: "" or a key. In a fight — the act's own («Присмотреться», a bonus action).
func inspect_why(id: String) -> String:
	if session == null:
		return "WAIT_BUSY"
	if CombatRules.active(session):
		return Acts.one("inspect").can(session, Catalog.data, CombatRules.player(session), id)
	var who := creature_who(id)
	if who.is_empty():
		return "CREATURE_NONE"
	if CombatRules.known(session, who):
		return "COMBAT_ALREADY_KNOWN"
	if bool(Being.view(session, id).get("looked", false)):
		return "FOE_LOOKED"
	return "" if _out_of_fight() else "WAIT_BUSY"


## «Присмотреться» to anybody (v0.8.4.30 a foe before the fight, v0.8.4.41 a person or a creature of the room): the knowledge
## check of a fight (CombatRules.look_over), once a creature out of it; in a fight the act itself. "" or a key.
func inspect(id: String) -> String:
	if session != null and CombatRules.active(session):
		return combat_act("inspect", id)
	var why := inspect_why(id)
	if not why.is_empty():
		return why
	Being.of(session, id)["looked"] = true
	_effect_lines(CombatRules.look_over(session, Catalog.data, creature_who(id)), true)
	return ""


## A thing pinned with a target, from a person's or a foe's menu (v0.8.4.30): the spell aimed at it, sent at once — a
## hostile one starts the fight with it as the first blow, another is cast as from the sheet. "" or a key.
func cast_at(spell_id: String, target: String) -> String:
	if not _master_ready() or session.mode == GameSession.MODE_COMBAT:
		return "WAIT_BUSY"
	for ch: Dictionary in attach_choices():
		if str(ch["kind"]) == "spell" and str(ch["id"]) == spell_id and not bool(ch["off"]):
			attached = {"kind": "spell", "id": spell_id, "slot": int(ch["slots"][0]) if not (ch["slots"] as Array).is_empty() else 0, "target": target}
			return "" if submit("") else "WAIT_BUSY"
	return "SPELL_NOT_READY"


## The spells the hero may aim at `target` out of a fight now: a hostile one at anybody, a charm at a person.
func spells_at(target: String) -> Array[Dictionary]:
	var foe := not session.npcs_here(world().world, session.room_id).has(target)
	return attach_choices().filter(func(ch: Dictionary) -> bool: return str(ch["kind"]) == "spell" and not bool(ch["off"]) 		and (CombatRules.hostile_spell(Catalog.data, str(ch["id"])) or not foe and bool(SpellEffects.spec(Catalog.data, str(ch["id"])).get("npc_save", false))))


## Talking to the lurking foes before a fight (v0.7.22.12): one roll; a truce, they go, or the fight. "" or a key.
func encounter_parley(skill: String) -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	var lk := EncounterRules.lurking(session, session.room_id)
	if lk.is_empty():
		return "ENCOUNTER_NONE"
	var enc := EncounterRules.lurking_encounter(session, Catalog.data, session.room_id)
	var why := EncounterRules.talkable(session, Catalog.data, enc["enemies"], skill)
	if not why.is_empty():
		return why
	var text := tr("ENCOUNTER_PARLEY_SAY_" + skill.to_upper())
	_add(GameSession.player_entry(text))
	var from := str(lk.get("from", ""))
	var r := EncounterRules.parley(session, Catalog.data, session.room_id, enc, skill)
	_add(GameSession.effect_entry(r["lines"]))
	_log("События: " + ", ".join(r["lines"]))
	if bool(r["fight"]):
		start_combat(enc["enemies"], EncounterRules.source(enc, from))
		return ""
	EventBus.state_changed.emit()
	_request("action", text + " [движок уже решил: %s — опиши это, эффекты не нужны]" % ", ".join(r["lines"]))
	return ""


## A way out of captivity (v0.7.22.12): break free, slip the ropes, or talk the captors round. "" or a key.
func escape_captivity(how: String) -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	var why := EncounterRules.can_escape(session, Catalog.data, how)
	if not why.is_empty():
		return why
	var text := tr("CAPTIVE_SAY_" + how.to_upper())
	_add(GameSession.player_entry(text))
	var lines := EncounterRules.escape(session, Catalog.data, how)
	_effect_lines(lines, true)
	_request("action", text + " [движок уже решил: %s — опиши это, эффекты не нужны]" % ", ".join(lines))
	return ""


## A follower by the buttons, without the master (v0.7.22.22, #25): `what` stay (waits here), lead (one left here
## goes again), let_go (goes home). "" or a key.
## The follower's next level by the player's button (v0.8.4.42.2).
func follower_grow(npc_id: String) -> String:
	if not _idle():
		return "WAIT_BUSY"
	return _act("grow", {"grow": [GrowthRules.grow_why.bind(session, Catalog.data, npc_id), GrowthRules.grow.bind(session, Catalog.data, npc_id)]})


func follower_act(npc_id: String, what: String) -> String:
	if not _idle():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var here := Being.follows(session, npc_id) or str(Being.view(session, npc_id).get("at", "")) == session.room_id
	if not here:
		return "ALLY_NOT_HERE"
	var name := str(world().npc(npc_id).get("name", npc_id))
	var plan := {"follow_npc": npc_id, "on": what == "lead", "room": session.room_id if what == "stay" else ""}
	if what == "lead" and not FollowRules.room_why(session, Catalog.data).is_empty():
		return FollowRules.room_why(session, Catalog.data)
	FollowRules.apply(session, plan)
	var line: String = {"stay": "%s остаётся здесь и ждёт", "lead": "%s снова идёт с героем", "let_go": "%s уходит к себе"}[what] % name
	_effect_lines([line], true)
	return ""


## «Отпустить» a summoned creature (v0.7.22.22). "" or a key.
func dismiss_summon(summon_id: String) -> String:
	if session == null or is_busy() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var name := ""
	for m: Dictionary in AllyRules.called(session):
		if str(m["id"]) == summon_id:
			name = str(m["name"])
	var why := AllyRules.dismiss(session, summon_id)
	if not why.is_empty():
		return why
	_effect_lines(["%s отпущен(а) и исчезает" % name], true)
	return ""


## The creatures a fight left (v0.7.22.11): bind, free, lead, talk (a master's turn), attack (a fight). "" or a key.
func creature_act(id: String, what: String) -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var c := CreatureRules.find(session, session.room_id, id)
	var why := CreatureRules.can(session, id, what, Catalog.data)  # talking too (v0.8.4.29.6)
	if not why.is_empty():
		return why
	if what == "talk":  # a truce is talked to as an equal, a prisoner as a prisoner (v0.7.22.17, #10)
		var say := tr("CREATURE_TALK_SAY_CAPTIVE" if CreatureRules.captive(c) else "CREATURE_TALK_SAY").format({"name": c.get("name", id)})
		if not submit(say):
			return "WAIT_BUSY"
		session.talk_creature = id
		return ""
	_effect_lines(CreatureRules.act(session, Catalog.data, id, what), what != "attack")
	if what == "attack":
		_start_pending_fight()
	return ""


## The master's replies of a talk with a creature go when it is gone — let go, sold, finished off (v0.7.22.17, #11).
func _forget_gone_creature() -> void:
	if session.talk_creature.is_empty() or not CreatureRules.find(session, session.room_id, session.talk_creature).is_empty():
		return
	session.talk_creature = ""
	_set_options([])


## «Спрятать тело» (v0.7.22.10, big test #9): the engine rolls (rules.crime.hide) — its total is how hard the body is
## to find; the master narrates. "" or a key.
func hide_body(npc_id: String) -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var why := CrimeRules.can_hide(session, Catalog.data, npc_id)
	if not why.is_empty():
		return why
	var h: Dictionary = CrimeRules.cfg(Catalog.data)["hide"]
	var who := str(world().npc(npc_id).get("name", npc_id))
	var text := tr("HIDE_BODY_SAY").format({"name": who})
	_add(GameSession.player_entry(text))
	var result := _engine_check({"skill": str(h["skill"]), "dc_tier": str(h["dc_tier"])})
	if result.has("error"):
		return "MSG_MASTER_FAILED"
	var lines := CrimeRules.hide(session, Catalog.data, npc_id, int(result["total"]), bool(result["success"]))
	lines.append_array(TimeRules.advance(session, Catalog.data, int(TimeRules.cfg(Catalog.data).get("search_minutes", 10))))
	_add(GameSession.effect_entry(lines))
	_log("Игрок: " + text)
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("action", text + " [движок уже бросил Скрытность %d — %s; %s — эффекты не нужны, опиши, куда и как герой прячет тело]" %
		[int(result["total"]), "успех" if bool(result["success"]) else "провал", ", ".join(lines)])
	return ""


## «Обыскать тело» (v0.7.14): its pockets and some wares come to the hero; living people here see it. "" or a key.
func search_body(npc_id: String) -> String:
	if session == null or is_busy() or not Backend.is_ready() or session.in_conversation():
		return "QUEST_BUSY"
	if str(Being.view(session, npc_id).get("body", "")) != session.room_id or Being.searched(session, npc_id):
		return "CRIME_NO_BODY"
	var lines := CrimeRules.search_body(session, Catalog.data, npc_id)
	_refresh()
	_effect_lines(lines, true)
	return ""


## Quest steps closed by new facts (a fight finished, a secret found, a flag set) go to the chat.
func _quest_progress() -> void:
	var lines := QuestRules.advance(session, Catalog.data)
	if not lines.is_empty():
		_told(lines)


## A hostile thing pinned to the words with an NPC of the scene as its target (v0.7.22.16): a weapon, or a spell that
## hurts or holds (CombatRules.hostile_spell). Charms, heals and words stay a master's turn.
func _hostile_attach(what: Dictionary) -> bool:
	var target := str(what.get("target", ""))
	if target.is_empty() or not attach_targets().any(func(t: Dictionary) -> bool: return str(t["id"]) == target):
		return false
	match str(what.get("kind", "")):
		"spell":
			return CombatRules.hostile_spell(Catalog.data, str(what.get("id", "")))
		"item_note":
			return ItemRules.def_of(Catalog.data["items"], session.items, str(what.get("id", ""))).has("weapon")
	return false


## «Напасть» on an NPC of the scene (v0.7.22.16, the author's fixes check #32): the fight at once, without the master.
## The hero acts first; one who does not expect it is caught off guard (CombatRules.npc_unaware). `opening` — a
## spell already spent at it ({spell, slot}): the engine resolves it as the first blow. "" or a localization key.
func attack_npc(npc_id: String, opening: Dictionary = {}) -> String:
	if session == null or is_busy() or not Backend.is_ready() or CombatRules.active(session):
		return "WAIT_BUSY"
	if not session.npcs_here(world().world, session.room_id).has(npc_id):
		return "CREATURE_NONE"
	_end_conversation()
	var npc := world().npc(npc_id)
	session.pending_fight = [{"monster": str(npc.get("monster", CombatRules.cfg(Catalog.data)["default_npc_monster"])),
		"name": str(npc.get("name", npc_id)), "desc": str(npc.get("description", "")), "npc_id": npc_id, "by_hero": true}]
	_opening = opening.duplicate()
	_opening["npc_id"] = npc_id
	_opening["unaware"] = CombatRules.npc_unaware(session, Catalog.data, npc_id)
	_start_pending_fight()
	return ""


## NPC button: start a conversation (or trade with a trader); the NPC greets the player.
func talk_to(npc_id: String, trade: bool = false) -> bool:
	if session == null or is_busy() or not Backend.is_ready() or not session.npcs_here(world().world, session.room_id).has(npc_id):
		return false
	if trade and (not world().is_trader(npc_id) or TimeRules.shops_closed(session, Catalog.data) or TheftRules.shop_closed_for(session, npc_id, Catalog.data)):
		return false
	if SocialRules.refuses(session, Catalog.data, npc_id):  # v0.7.15.3: a hostile NPC turns away
		return false
	session.talk_creature = ""
	_begin_conversation(npc_id, GameSession.MODE_TRADE if trade else GameSession.MODE_SOCIAL)
	_request("enter", "")
	return true


func leave_conversation() -> bool:
	if session == null or is_busy() or not session.in_conversation() or not Backend.is_ready():
		return false
	_end_conversation()
	_request("resume", "")
	return true


## Repeats the last failed request as a new turn (ADR-0009 §5: no idempotency, a retry is a new turn_id).
## An attached spend given back by the failed turn is spent again first (its facts are in the input).
func retry() -> void:
	if not can_retry():
		return
	if not _retry_spend.is_empty():
		var backup := session.character.duplicate(true)
		var spent := _spend(_retry_spend)
		if spent.has("reason"):
			EventBus.message.emit(tr(str(spent["reason"])))
			return
		_refund = backup
		_refund_what = _retry_spend
		_retry_spend = {}
		_add(GameSession.effect_entry(spent["lines"]))
	_request(_last_kind, _last_input)


## The last turn failed and can be repeated.
func can_retry() -> bool:
	return session != null and not is_busy() and not _last_kind.is_empty()


func cancel_turn() -> void:
	if is_busy() and Backend.is_ready():
		Backend.request("turn.cancel", {"turn_id": busy_turn}, 5.0)


## Puts an owned item into an equipment slot (CharacterRules.SLOTS). "" on success, else a localization key.
## Not while the master thinks: the snapshot of the turn in flight would no longer match. `spare` — into the set put away.
## `who` — whose: the hero, or a follower by its «Снаряжение» window (v0.8.4.40, Equip — one set of rules for anybody).
func equip(item_id: String, slot: String, both: bool = false, spare: bool = false, who: String = Being.HERO) -> String:
	if not _idle():
		return "EQUIP_BUSY"
	var why := Equip.why(session, Catalog.data, who, item_id, slot, spare, both)
	if not why.is_empty():
		return why
	var c := Gear.of(session, Catalog.data, who)
	var before: Dictionary = (c.get("equipped", {}) as Dictionary).duplicate()
	Equip.put(session, Catalog.data, who, item_id, slot, spare, both)
	if spare:  # a thing of the row put away goes there without touching the hands (as in BG3)
		_refresh()
		EventBus.state_changed.emit()
		return ""
	_gear_changed(before, who)
	return ""


## The other weapon set into the hands: nothing to pay, in a fight and out of it (v0.8.4.1, as in BG3).
func swap_weapons() -> String:
	if session == null:
		return "EQUIP_BUSY"
	if not _idle() and not CombatRules.active(session):
		return "EQUIP_BUSY"
	return _act("swap", {"swap": [func() -> String: return Acts.one("swap").can(session, Catalog.data, Sheet.HERO),
		func() -> Array[String]: return Acts.one("swap").go(session, Catalog.data, Sheet.HERO)]})


## The «Снаряжение» window of a follower (v0.8.4.40): a thing handed over either way, the sets swapped. Equip's rules.
func gear_act(what: String, who: String, item: String = "") -> String:
	if not _idle():
		return "EQUIP_BUSY"
	var data := Catalog.data
	var s := session
	return _act(what, {
		"give": _row(Equip.hand_why, Equip.hand, [s, data, Being.HERO, who, item]),
		"take": _row(Equip.hand_why, Equip.hand, [s, data, who, Being.HERO, item]),
		"swap": [Equip.swap_why.bind(s, data, who), func() -> Array:
			Equip.swap(s, data, who)
			return []],
	})


func unequip_stowed(slot: String, who: String = Being.HERO) -> void:
	unequip(slot, who, true)


## An act of a thing in the character window (v0.8.4.43.6, as in BG3): a row of ItemActs.of — the right button's menu, a
## double click, a drag — done by the road its `act` names, for `who`'s things. "" or the key of the refusal.
func item_act(row: Dictionary, who: String = Being.HERO) -> String:
	var item := str(row.get("item", ""))
	var roads := {
		"equip": func() -> String: return equip(item, str(row["slot"]), bool(row.get("both", false)), bool(row.get("spare", false)), who),
		"unequip": func() -> String:
			unequip(str(row["slot"]), who, bool(row.get("spare", false)))
			return "",
		"use": use_item.bind(item),
		"belt": belt_put.bind(item, int(row.get("at", -1))),
		"belt_take": belt_take.bind(int(row.get("at", -1))),
		"drink": liquid_act.bind("drink", str(row.get("key", ""))),
		"pour": liquid_act.bind("pour", str(row.get("key", "")), str(row.get("to", ""))),
		"pour_out": liquid_act.bind("pour_out", str(row.get("key", ""))),
		"to_bag": container_move.bind(str(row.get("bag", "")), item, int(row.get("n", 1)), false),
		"attune": attune.bind(item),
		"unattune": unattune.bind(item),
		"store": store_spell.bind(item, str(row.get("spell", "")), int(row.get("circle", 0))),
		"drop": drop_item.bind(item, int(row.get("qty", 1))),
		"drop_bag": drop_item.bind(str(row.get("bag", ""))),
		"give": func() -> String: return _handed("give", str(row.get("to", "")), item, int(row.get("qty", 1))),
		"take": func() -> String: return _handed("take", who, item, int(row.get("qty", 1))),
	}
	if not roads.has(str(row.get("act", ""))):
		return "PROPERTY_NOT_NOW"
	return (roads[str(row["act"])] as Callable).call()


## `qty` copies handed over one by one (Equip.hand passes one): stops at the first refusal, "" when at least one went.
func _handed(what: String, who: String, item: String, qty: int) -> String:
	var err := ""
	for i in maxi(1, qty):
		err = gear_act(what, who, item)
		if not err.is_empty():
			return err if i == 0 else ""
	return ""


## A thing onto the belt under the doll (v0.8.4.24): "" or the reason. Not in a fight, as in Pathfinder.
func belt_put(item_id: String, at: int = -1) -> String:
	if not _idle():
		return "EQUIP_BUSY"
	if CombatRules.active(session):
		return "BELT_IN_COMBAT"
	var why := ItemRules.belt_why(session.character, Catalog.data, session.items, item_id, at)
	if not why.is_empty():
		return why
	ItemRules.belt_put(session.character, Catalog.data, session.items, item_id, at)
	EventBus.state_changed.emit()
	return ""


func belt_take(at: int) -> String:
	if not _idle():
		return "EQUIP_BUSY"
	if CombatRules.active(session):
		return "BELT_IN_COMBAT"
	ItemRules.belt_take(session.character, Catalog.data, session.items, at)
	EventBus.state_changed.emit()
	return ""


func unequip(slot: String, who: String = Being.HERO, spare: bool = false) -> void:
	if not _idle():
		return
	var why := Equip.off_why(session, Catalog.data, who, slot, spare)
	if not why.is_empty():
		if why != "EQUIP_EMPTY":
			EventBus.message.emit(tr(why))
		return
	var before: Dictionary = (Gear.of(session, Catalog.data, who).get("equipped", {}) as Dictionary).duplicate()
	Equip.off(session, Catalog.data, who, slot, spare)
	if spare:
		_refresh()
		EventBus.state_changed.emit()
		return
	_gear_changed(before, who)


## After the sheet changed the gear: the minutes of armour (v0.7.7, rules.equip_minutes) pass and show in the chat
## and the history, so the master knows the hero is now in other clothes.
func _gear_changed(before: Dictionary, who: String = Being.HERO) -> void:
	var c := Gear.of(session, Catalog.data, who)
	Equip.settle(session, Catalog.data, who)
	var minutes := CharacterRules.gear_minutes(Catalog.data, session.items, before, c["equipped"])
	if minutes > 0 and session.mode != GameSession.MODE_COMBAT:
		var lines: Array[String] = []
		for slot: String in ["armor", "shield"]:
			var was := str(before.get(slot, ""))
			var now := str(c["equipped"].get(slot, ""))
			if was != now:
				if not was.is_empty():
					lines.append(("Снято: " if who == Being.HERO else "%s снимает: " % WorldView.new(Catalog.data["world"]).npc_name(who)) + ItemRules.display_name(Catalog.data["items"], session.items, was))
				if not now.is_empty():
					lines.append(("Надето: " if who == Being.HERO else "%s надевает: " % WorldView.new(Catalog.data["world"]).npc_name(who)) + ItemRules.display_name(Catalog.data["items"], session.items, now))
		lines.append("Переодевание: %d мин" % minutes)
		lines.append_array(TimeRules.advance(session, Catalog.data, minutes))
		_told(lines)
	EventBus.state_changed.emit()


func save_to(slot: String) -> bool:
	return SaveManager.save_slot(slot, session)


## F5 (v0.7.22.27): the quick slot, not while the master thinks or in a fight. "" or a localization key.
func quick_save() -> String:
	if session == null:
		return "MSG_SAVE_FAILED"
	if is_busy():
		return "REST_BUSY"
	if CombatRules.active(session):
		return "MSG_NO_SAVE_IN_FIGHT"
	return "" if save_to(SaveManager.QUICKSAVE) else "MSG_SAVE_FAILED"


## "" on success or a localization key.
func load_from(slot: String) -> String:
	var res: Variant = SaveManager.read_slot(slot)
	if res is String:
		return res
	start(res)
	if not session.fight_on_load.is_empty() and not CombatRules.active(session):
		var fight := session.fight_on_load
		session.fight_on_load = {}
		_restart_fight.call_deferred(fight)  # after the game screen opens
	return ""


## The pre-fight save was loaded: the same fight starts again (v0.7.2).
func _restart_fight(fight: Dictionary) -> void:
	if session != null and not CombatRules.active(session):
		start_combat(fight.get("foes", []), fight.get("source", {}))


# --- turn --------------------------------------------------------------------------


func _add(entry: Dictionary) -> void:
	if not session.roll_notes.is_empty() and str(entry.get("kind", "")) == GameSession.KIND_EFFECT:  # v0.7.39.5
		entry["rolls"] = session.roll_notes.duplicate()
		session.roll_notes.clear()
	if not session.faith_lines.is_empty() and str(entry.get("kind", "")) == GameSession.KIND_EFFECT:  # v0.7.49: a vow broken by a roll
		(entry["lines"] as Array).append_array(session.faith_lines)
		session.faith_lines.clear()
	if str(entry.get("kind", "")) == GameSession.KIND_EFFECT:  # every deed told closes the quest steps it made true: a quest's
		(entry["lines"] as Array).append_array(QuestRules.advance(session, Catalog.data))  # thing taken any way (v0.8.4.42.10)
	EventBus.chat_appended.emit(session.append(entry))  # a repeat of the engine's line comes back as the line it folded into
	if not session.faith_lines.is_empty():
		var faith := session.faith_lines.duplicate()
		session.faith_lines.clear()
		_add(GameSession.effect_entry(faith))


func _set_options(options: Array[String], costs: Array[int] = [], checks: Array = []) -> void:
	session.options = options
	session.option_costs = costs
	session.option_checks = checks
	EventBus.options_changed.emit(options)


func _log(line: String) -> void:
	var cap := int(Catalog.game()["summaries"]["events_max"])
	session.location_log.append(line)
	if session.location_log.size() > cap:
		session.location_log = session.location_log.slice(session.location_log.size() - cap)
	if session.in_conversation():
		session.dialogue_log.append(line)


func _request(kind: String, input: String) -> void:
	var s := session
	var turn_id := s.next_turn_id()
	_retry_spend = {}  # a new turn: an older given-back spend is not repeated
	_last_kind = kind
	if kind in ["action", "ability"]:
		effects.player_turns[turn_id] = true
	_last_input = input
	busy_turn = turn_id
	if bool(_forced.get("fresh", false)):
		_forced.merge({"fresh": false, "input": input, "turn": turn_id}, true)
	elif not _forced.is_empty():
		_forced["turn"] = turn_id if kind == "action" and str(_forced.get("input", "")) == input else ""  # a retry keeps it
	_set_options([])
	EventBus.turn_started.emit(turn_id)
	if kind == "enter":
		_lay_furnishing(s)
	var params := {
		"turn_id": turn_id,
		"mode": GameSession.MODE_EXPLORATION if kind in ["quest_act", "letter"] else s.mode,  # the designer builds, nobody speaks
		"kind": kind,
		"input": input,
		"snapshot": TurnSnapshot.build(s, Catalog.data, int(Catalog.game()["chat"]["history_chars"])),
	}
	if s.in_conversation() and not kind in ["quest_act", "letter"]:
		params["npc_id"] = s.npc_id
	if not _forced.is_empty() and str(_forced.get("turn", "")) == turn_id:
		params["pinned_check"] = _pin_name(_forced)  # v0.7.38: the server holds the master to a roll
	SaveManager.master_params(params)
	var call := await Backend.request("turn.request", params, float(Catalog.game()["turn"]["client_timeout_s"]))
	if session != s or busy_turn != turn_id:
		return  # the session was closed or replaced while the master was thinking
	busy_turn = ""
	if call.is_error():
		effects.discard(turn_id)
		if not _refund.is_empty():  # the attached spend did not reach the master: give the slot back
			session.character.clear()
			session.character.merge(_refund)
			_refund = {}
			_retry_spend = _refund_what
			_refund_what = {}
			_opening = {}
			_add(GameSession.system_entry("ATTACH_REFUNDED"))
		_show_start_lines()
		_add(GameSession.system_entry(_error_key(call.reason())))
		EventBus.turn_finished.emit(turn_id, false)
		return
	_refund = {}
	_refund_what = {}
	_retry_spend = {}
	var turn_kind := _last_kind
	_last_kind = ""
	var follow_up := _apply_result(s, turn_id, call.result, turn_kind)
	EventBus.turn_finished.emit(turn_id, true)
	EventBus.state_changed.emit()
	SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	_maybe_summarize_location()
	_maybe_tell_quests()
	_prepare()
	if follow_up != "combat":
		_opening = {}
	if kind == "death" and s.mode != GameSession.MODE_COMBAT:
		EventBus.navigate.emit("death", {"epitaph": str(call.result.get("narration", ""))})
		return
	if follow_up == "combat":
		_start_pending_fight()
	elif not follow_up.is_empty():
		_request(follow_up, "")
	elif s.mode == GameSession.MODE_COMBAT:
		_show_start_lines()
		if str(s.combat.get("outcome", "")) == "dead" and kind == "death":
			EventBus.navigate.emit("death", {"epitaph": str(call.result.get("narration", ""))})
		else:
			_combat_continue()
	else:
		_after_turn(s, kind)


## After a turn: a quest's act to build, else a letter's reply that is due (v0.7.48) — one master turn each.
func _after_turn(s: GameSession, kind: String) -> void:
	if kind != "quest_act" and _build_next_act(s):
		return
	_answer_letter(s, kind)


## A taken quest waits for its next act (v0.7.39.6). One readied ahead is laid at once; one not ready yet is built on the
## second line while the game goes on (v0.8.4.30) and laid when it comes. Only when the second line is shut for the day
## the designer's turn builds it here, after the turn that opened it; a failed build is tried again after the next turn.
func _build_next_act(s: GameSession) -> bool:
	var lines := _lay_acts(s)
	if not lines.is_empty():
		_effect_lines(lines, true)
	var waiting := QuestRules.awaiting(s, Catalog.data["world"])
	if waiting.is_empty() or is_busy() or not Backend.is_ready():
		return false
	if _ahead_stop != s.day and PrepareRules.on(Catalog.data):
		for qid: String in waiting:
			var key := "%s:%d" % [qid, int(QuestRules.quest(Catalog.data["world"], qid).get("built", 0)) + 1]
			if not _act_told.has(key):
				_act_told[key] = true
				_add(GameSession.system_entry("QUEST_ACT_AHEAD"))
		_prepare()
		return false
	_add(GameSession.system_entry("QUEST_ACT_BUILDING"))
	_request("quest_act", QuestGen.act_frame(s, Catalog.data, waiting[0]))
	return true


## The acts readied ahead for the taken quests that wait for them, checked again and laid: their lines.
func _lay_acts(s: GameSession) -> Array[String]:
	var out: Array[String] = []
	for qid: String in QuestRules.awaiting(s, Catalog.data["world"]):
		var built := int(QuestRules.quest(Catalog.data["world"], qid).get("built", 0))
		out.append_array(_lay_prepared(s, [PrepareRules.act_of(s, qid, built + 1)]))
	return out


## «Есть дело?» at a person (v0.8.4.25): the quest it readied ahead, checked again, offered in its own words without a
## master's turn. "" or a key.
func ask_work(npc_id: String) -> String:
	if not _idle() or not session.npcs_here(Catalog.data["world"], session.room_id).has(npc_id):
		return "QUEST_BUSY"
	var e := PrepareRules.quest_of(session, npc_id)
	PrepareRules.part(session, PrepareRules.QUESTS).erase(npc_id)
	var lines := _lay_prepared(session, [e])
	if lines.is_empty():
		EventBus.state_changed.emit()
		return "WORK_NONE"
	_add(GameSession.player_entry(tr("ASK_WORK_SAY")))
	var say := str(e.get("offer_text", "")).strip_edges()
	if not say.is_empty():
		_add(GameSession.npc_entry(npc_id, world().npc_name(npc_id), say, ""))
	_effect_lines(lines)
	SaveManager.save_slot(SaveManager.AUTOSAVE, session)
	return ""


## The readied furnishing of the room the hero enters is laid before the entry turn, which then only tells of it.
func _lay_furnishing(s: GameSession) -> void:
	if PropRules.needs_furnish(s, s.room_id):
		var lines := _lay_prepared(s, [PrepareRules.furnishing(s, Catalog.data, s.room_id)])
		if not lines.is_empty():
			_log("События: " + ", ".join(lines))


## Effects readied ahead, checked by the engine again as if the master proposed them now and applied: the lines of
## those the world still takes.
func _lay_prepared(s: GameSession, raw: Array) -> Array[String]:
	_ahead_n += 1
	var turn_id := "lay-%d" % _ahead_n  # never sent: checked and applied here
	effects.searched_quests[turn_id] = true  # the master searched when it readied them
	var ids: Array = []
	for e: Variant in raw:
		if e is Dictionary and not (e as Dictionary).is_empty():
			var r := effects.validate(s, Catalog.data, turn_id, e)
			if bool(r.get("accepted", false)):
				ids.append(r["effect_id"])
	if ids.is_empty():
		effects.discard(turn_id)
		return []
	return effects.apply(s, turn_id, ids)


## The second line (v0.8.4.25, master-prefetch.md): beside the player's turns the master readies what the hero meets
## soon — up to `parallel` turns at once, out of a fight; the server refuses them near the end of the daily limit.
func _prepare() -> void:
	var s := session
	if s == null or not Backend.is_ready() or _ahead_stop == s.day or s.mode == GameSession.MODE_COMBAT:
		return
	var busy: Array = _ahead.values().map(func(j: Dictionary) -> String: return "%s:%s" % [j["kind"], j["key"]])
	for job: Dictionary in PrepareRules.jobs(s, Catalog.data, busy):
		if _ahead.size() >= int(PrepareRules.cfg(Catalog.data).get("parallel", 1)):
			return
		_prepare_one(s, job)


func _prepare_one(s: GameSession, job: Dictionary) -> void:
	_ahead_n += 1
	var turn_id := "b-%d" % _ahead_n
	_ahead[turn_id] = job
	if job["kind"] == "goal":
		TimeRules.count(s, s.prepared, "goal_tries")  # a refused or failed one is not asked again and again
	effects.ahead[turn_id] = PrepareRules.ahead_of(job)
	var params := {
		"turn_id": turn_id,
		"mode": GameSession.MODE_EXPLORATION,
		"kind": "quest_act" if job["kind"] == "act" else "prepare",
		"input": PrepareRules.frame(s, Catalog.data, job),
		"snapshot": TurnSnapshot.build(s, Catalog.data, int(Catalog.game()["chat"]["history_chars"])),
		"background": true,
	}
	SaveManager.master_params(params)
	var call := await Backend.request("turn.request", params, float(Catalog.game()["turn"]["client_timeout_s"]))
	_ahead.erase(turn_id)
	if session != s:
		return
	if call.is_error():
		effects.discard(turn_id)
		if call.reason() == "budget_exceeded":
			_ahead_stop = s.day
		_log("Заготовка %s %s: %s" % [job["kind"], job["key"], call.reason()])
		return
	PrepareRules.keep(s, Catalog.data, job, effects.kept(turn_id, call.result.get("effect_ids", [])), str(call.result.get("narration", "")))
	_log("Заготовка %s %s: %s" % [job["kind"], job["key"], str(call.result.get("narration", ""))])
	if not is_busy() and s.mode != GameSession.MODE_COMBAT and job["kind"] == "act":
		_build_next_act(s)  # v0.8.4.30: a quest waiting for this act goes on now; else the next turn lays it
	if job["kind"] == "goal":  # v0.8.4.36: the goal's quest is offered by its giver at once, checked again
		var got := _lay_prepared(s, PrepareRules.goal_quests(s, Catalog.data))
		_log("Задание цели: %s" % (", ".join(got) if not got.is_empty() else "движок не принял"))
		if not got.is_empty():
			EventBus.state_changed.emit()
			SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	if not is_busy():
		_prepare()


## A letter's reply day came (v0.7.48): the master writes the person's answer in a turn of its own.
func _answer_letter(s: GameSession, after: String) -> void:
	var id := LetterRules.due(s, Catalog.data)
	if id.is_empty() or not Backend.is_ready() or is_busy() or s.mode == GameSession.MODE_COMBAT or (after == "letter" and id == _letter_tried):
		return  # an answer the engine could not take is not asked again in a loop
	_letter_tried = id
	_request("letter", LetterRules.frame(s, Catalog.data, id))


## Shows the narration, applies listed reserves, handles next_mode. Returns the follow-up turn kind or "".
func _apply_result(s: GameSession, turn_id: String, result: Dictionary, turn_kind: String = "") -> String:
	var text := str(result.get("narration", ""))
	if turn_kind == "letter":  # v0.7.48: the narration is the person's letter
		return _letter_answered(s, turn_id, result, text)
	if s.in_conversation() and turn_kind != "quest_act":
		_add(GameSession.npc_entry(s.npc_id, str(world().npc(s.npc_id).get("name", s.npc_id)), text, turn_id))
	else:
		_add(GameSession.dm_entry(text, turn_id))
	_log(("%s: " % world().npc(s.npc_id).get("name", "")) + text if s.in_conversation() else "Мастер: " + text)
	var room_before := s.room_id
	var lines := effects.apply(s, turn_id, result.get("effect_ids", []))
	CharacterRules.refresh(s.character, Catalog.data, s.items)  # an item given away is unequipped
	if not lines.is_empty():
		_told(lines)
	var options: Array[String] = []
	for o: Variant in result.get("options", []):
		options.append(str(o))
	var costs: Array[int] = []
	for c: Variant in result.get("option_costs", []):
		costs.append(maxi(0, int(c)))
	var checks: Array = []
	var raw: Array = result.get("option_checks", []) if result.get("option_checks") is Array else []
	for i in options.size():
		var ch: Variant = raw[i] if i < raw.size() else null
		var ok: bool = ch is Dictionary and Catalog.rules()["skills"].has(str(ch.get("skill", ""))) and Catalog.rules()["dc_tiers"].has(str(ch.get("dc_tier", "")))
		checks.append({"skill": str(ch["skill"]), "dc_tier": str(ch["dc_tier"])} if ok else {})
	_set_options(options, costs, checks)
	_forget_gone_creature()

	if s.mode == GameSession.MODE_COMBAT:
		var after := CombatRules.after_player_action(s, Catalog.data)
		if not after.is_empty():
			_combat_log(after)
		return ""
	if not s.pending_fight.is_empty():
		return "combat"
	if ConditionRules.incapacitated(s.character) and int(s.character["hp"]) > 0:
		var slept := _sleep_through()
		if not slept.is_empty():
			_told(slept)
	if ConditionRules.dead(s.character) and turn_kind != "death":
		_request.call_deferred("death", "Герой умирает от истощения (шестая степень).\n" + _hero_path())
		return ""
	if int(s.character["hp"]) <= 0:
		var out := ExplorationRules.knock_out(s)
		_told(out)
		_end_conversation()
		return "downed"

	_quest_progress()
	if s.room_id != room_before and s.arrest != s.room_id:
		# v0.7.22.16: the master's move goes the way of the exit button — a trap on the exit, a meeting, the fight; first, so a
		# captive on the rope and the followers come along out of a conversation too (v0.8.4.36, the author's feedback)
		var to := s.room_id
		s.room_id = room_before
		_end_conversation()
		if not WayRules.open_exits(s, Catalog.data["world"], room_before).has(to):  # a far place by the known paths, as «Идти сюда»
			_walk.call_deferred(WorldMap.route(s, Catalog.data["world"], room_before, to, Catalog.data))
			return ""
		var steps: Array[String] = []
		var trap := ExplorationRules.trap_on_exit(s, Catalog.data["world"], room_before, to)
		if not trap.is_empty():
			steps = ExplorationRules.spring_trap(s, Catalog.data, room_before, trap)
			if int(s.character["hp"]) <= 0:
				_trap_downed.call_deferred(steps)
				return ""
		_move_to.call_deferred(to, steps, false)
		return ""
	if s.room_id != room_before:  # the guard leads the held hero: the one road of a step (v0.8.4.29.6) — Magic Circle, a fall, the place's hooks
		var to := s.room_id
		s.room_id = room_before
		var moved: Array[String] = []
		_step(to, moved)
		if not moved.is_empty():
			_add(GameSession.effect_entry(moved))
		_end_conversation()
		return "enter"
	if s.in_conversation() and not s.npcs_here(Catalog.data["world"], s.room_id).has(s.npc_id):  # its hour came (v0.7.14.2)
		_add(GameSession.effect_entry(["%s уходит" % world().npc(s.npc_id).get("name", s.npc_id)]))
		_end_conversation()
		return "resume"
	var next: Variant = result.get("next_mode")
	if not (next is Dictionary):
		return ""
	var mode := str(next.get("mode", ""))
	var npc_id := str(next.get("npc_id", "")) if next.get("npc_id") != null else ""
	if mode == GameSession.MODE_EXPLORATION and s.in_conversation():
		_end_conversation()
		return "resume"
	if mode == GameSession.MODE_COMBAT and s.npcs_here(world().world, s.room_id).has(npc_id):
		var npc := world().npc(npc_id)
		s.pending_fight = [{"monster": str(npc.get("monster", CombatRules.cfg(Catalog.data)["default_npc_monster"])),
			"name": str(npc.get("name", npc_id)), "desc": str(npc.get("description", "")), "npc_id": npc_id, "by_hero": true}]
		return "combat"
	if mode in [GameSession.MODE_SOCIAL, GameSession.MODE_TRADE] and not s.in_conversation() and turn_kind != "action":
		return ""  # a conversation starts only from the player's own words (v0.7.2: the master opened one on «resume»)
	if mode in [GameSession.MODE_SOCIAL, GameSession.MODE_TRADE] and not s.in_conversation() and SocialRules.refuses(s, Catalog.data, npc_id):
		return ""  # v0.7.15.3: a hostile NPC will not talk; the master narrated the refusal
	if mode in [GameSession.MODE_SOCIAL, GameSession.MODE_TRADE] and s.npcs_here(world().world, s.room_id).has(npc_id):
		if mode == GameSession.MODE_TRADE and (not world().is_trader(npc_id) or TimeRules.shops_closed(s, Catalog.data) or TheftRules.shop_closed_for(s, npc_id, Catalog.data)):
			mode = GameSession.MODE_SOCIAL
		if s.in_conversation() and s.npc_id == npc_id:
			# The same partner: the master already answered, no new greeting (B33). Leaving the deal panel is the
			# player's button: talk goes on in trade mode too, so the master never closes the panel.
			if mode == GameSession.MODE_TRADE:
				s.mode = mode
			return ""
		_begin_conversation(npc_id, mode)
		return ""  # v0.8.4.36, the author's feedback: the master's turn already answered as the NPC; a greeting after it was off the point
	return ""


func _letter_answered(s: GameSession, turn_id: String, result: Dictionary, text: String) -> String:
	var id := _last_input.get_slice("]", 0).get_slice(":", 1)
	var to := str(LetterRules.get_letter(s, id).get("to", ""))
	var lines := effects.apply(s, turn_id, result.get("effect_ids", []))
	lines.append_array(LetterRules.answered(s, Catalog.data, id, text))
	_add(GameSession.npc_entry(to, tr("LETTER_FROM").format({"name": world().npc(to).get("name", to)}), text, turn_id))
	_log("Письмо от %s: %s" % [world().npc(to).get("name", to), text])
	if not lines.is_empty():
		_told(lines)
	return ""


func _begin_conversation(npc_id: String, mode: String) -> void:
	if session.in_conversation() and session.npc_id != npc_id:
		_end_conversation()
	session.mode = mode
	session.npc_id = npc_id
	EventBus.state_changed.emit()


## Back to exploration; the conversation log goes to summary.request (kept in the save, ADR-0009 §3).
func _end_conversation() -> void:
	if not session.in_conversation():
		return
	var npc_id := session.npc_id
	var events := session.dialogue_log.duplicate()
	TradeRules.end_visit(session, npc_id)
	session.mode = GameSession.MODE_EXPLORATION
	session.npc_id = ""
	session.dialogue_log.clear()
	EventBus.state_changed.emit()
	if not events.is_empty():
		_summarize("dialogue", npc_id, "dialogue:" + npc_id, events)


func _maybe_summarize_location() -> void:
	var every := int(Catalog.game()["summaries"]["location_every_turns"])
	if session.location_log.size() < every:
		return
	var loc := world().location_id(session.room_id)
	var events := session.location_log.duplicate()
	session.location_log.clear()
	_summarize("location", str(world().location(loc).get("name", loc)), "location:" + loc, events)


## The hero's diary of a quest (v0.8.4.30, the author's feedback): steps done since its last entry — the master rewrites
## the account in the hero's words with them and the chronicle since, beside the turn like a summary.
func _maybe_tell_quests() -> void:
	var s := session
	if s == null or not Backend.is_ready():
		return
	var w: Dictionary = Catalog.data["world"]
	var ids: Array = s.quests_active.keys() + s.quests_done + s.quests_failed
	for qid: String in ids:
		var q := QuestRules.quest(w, qid)
		var done := QuestRules.history(s, w, qid)
		var n := done.size() + (1 if s.quests_done.has(qid) or s.quests_failed.has(qid) else 0)
		var mark := QuestRules.STORY + qid + "#"
		var was := str(s.summaries.get(mark, "0|0")).split("|")
		if q.is_empty() or done.is_empty() or n <= int(was[0]):
			continue
		var events: Array[String] = []
		if int(was[0]) == 0 and not str(q.get("giver", "")).is_empty():
			events.append("Задание дал %s: %s" % [world().npc_name(str(q["giver"])), q.get("description", "")])
		events.append_array(done.slice(int(was[0])))
		var since := int(was[1])
		if since == 0:  # the first entry: the chronicle from the quest's first line in it
			var first := s.chronicle.filter(func(f: Dictionary) -> bool: return str(f["text"]).contains("«%s»" % q.get("title", "")))
			since = int(first[0]["at"]) - 1 if not first.is_empty() else TimeRules.abs_minute(s)
		for f: Dictionary in s.chronicle:
			if int(f["at"]) > since:
				events.append(str(f["text"]))
		if s.quests_done.has(qid) or s.quests_failed.has(qid):
			events.append("Задание %s." % ("выполнено" if s.quests_done.has(qid) else "провалено"))
		s.summaries[mark] = "%d|%d" % [n, TimeRules.abs_minute(s)]
		_summarize("quest", str(q.get("title", qid)), QuestRules.STORY + qid, events.slice(maxi(0, events.size() - 24)))


## The brush (v0.7.35): the last event's image — drawn once, opened again afterwards. Beside a turn, like a summary.
func draw_image() -> void:
	if session == null or drawing:
		return
	var i := ImageFrame.event_index(session)
	if i < 0:
		return
	var entry: Dictionary = session.chat[i]
	if FileAccess.file_exists(ImageFrame.image_of(entry)):
		EventBus.image_drawn.emit(entry)
		return
	var s := session
	var params := SaveManager.image_params(ImageFrame.params(s, Catalog.data, i))
	drawing = true
	EventBus.image_busy.emit(true)
	var cfg: Dictionary = Catalog.game()["images"]
	var call := await Backend.request("image.request", params, float(cfg["timeout_s"]))
	drawing = false
	EventBus.image_busy.emit(false)
	if session != s:
		return
	if call.is_error():
		EventBus.message.emit(tr(_error_key(call.reason())))
		return
	var img := ImageFrame.decode(str(call.result.get("mime", "")), str(call.result.get("data_b64", "")), int(cfg["max_width"]))
	var path := ImageFrame.file_path(SaveManager.profile_dir, s, i)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if img == null or img.save_webp(path, true, 0.85) != OK:
		EventBus.message.emit(tr("MSG_IMAGE_FAILED"))
		return
	entry["image"] = path
	EventBus.image_drawn.emit(entry)


func _summarize(kind: String, subject: String, key: String, events: Array) -> void:
	var s := session
	var params := {"kind": kind, "subject_id": subject, "previous": str(s.summaries.get(key, "")), "events": events}
	SaveManager.master_params(params)
	var call := await Backend.request("summary.request", params, float(Catalog.game()["turn"]["summary_timeout_s"]))
	if session == s and not call.is_error():
		s.summaries[key] = str(call.result.get("summary", ""))


static func _error_key(reason: String) -> String:
	match reason:
		"turn_cancelled":
			return "MSG_TURN_CANCELLED"
		"turn_timeout", "client_timeout", "engine_timeout":
			return "MSG_TURN_TIMEOUT"
		"server_busy", "turn_in_progress":
			return "MSG_SERVER_BUSY"
		"budget_exceeded":
			return "MSG_BUDGET_EXCEEDED"
		"llm_unavailable", "llm_invalid_output":
			return "MSG_MASTER_FAILED"
		_:
			return "MSG_NO_MASTER"


# --- engine.* handlers (only for the turn in flight, ADR-0009 §3) ---------------------


func _active(params: Dictionary) -> bool:
	var turn_id := str(params.get("turn_id", ""))
	return session != null and (turn_id == busy_turn or _ahead.has(turn_id))  # a turn of the second line too (v0.8.4.25)


func handle_engine_check(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	if TradeRules.is_haggle(session, Catalog.data, params):
		return _haggle_check(params)
	if session.mode == GameSession.MODE_COMBAT and CombatRules.active(session) and params.get("skill") != null \
			and CombatRules.can_parley(session, Catalog.data, str(params["skill"])).is_empty():
		var parley := _parley_check(params)
		_combat_log(parley["lines"])
		return parley["result"]
	var forced := _forced_skill(params)
	var result := _engine_check(params)
	if not forced.is_empty() and not result.has("error"):
		result["rolled_as"] = forced
	var won_over := CheckEngine.listener(session, Catalog.data, params) if ["persuasion", "deception", "intimidation"].has(str(params.get("skill", ""))) and not bool(result.get("blocked", false)) else ""
	effects.note_check(str(params.get("turn_id", "")), str(params.get("dc_tier", "")), bool(result.get("success", false)), won_over)
	effects.note_roll(str(params.get("turn_id", "")), str(params.get("skill", "")), int(result.get("total", 0)), bool(result.get("success", false)))
	return result


## v0.7.36: a check (not a save) of the turn with the player's pinned skill or ability is rolled by it; its name, or "".
func _forced_skill(params: Dictionary) -> String:
	if _forced.is_empty() or str(_forced.get("turn", "")) != str(params.get("turn_id", "")) or params.get("save") != null and not str(params["save"]).is_empty():
		return ""
	if _forced.has("skill"):
		params["skill"] = _forced["skill"]
		return tr("SKILL_" + str(_forced["skill"]).to_upper())
	params.erase("skill")
	params["ability"] = _forced["ability"]
	return tr("ABILITY_" + str(_forced["ability"]).to_upper())


## An engine check (the master's request_check or a button of the client): the card of CheckEngine (the DC by the tier or
## the listener, every advantage and disadvantage of the moment), the lock of a repeat, theft, hidden things and caches
## found. Adds the check card.
func _engine_check(params: Dictionary) -> Dictionary:
	for k: String in ["dc", "dc_reason", "disadvantage_reason", "auto_fail_reason"]:
		params.erase(k)  # the DC number and the reasons are the engine's
	var sp := CheckEngine.spec(session, Catalog.data, params)
	if sp.has("error"):
		return JsonRpcPeer.fail(JsonRpcPeer.ERR_INVALID_PARAMS, str(sp["error"]))
	var adv: Array = CheckEngine.situation(session, Catalog.data, Sheet.HERO, sp["spec"], true)["adv"]
	if not adv.is_empty():
		params["advantage_reason"] = ", ".join(adv)  # a new source of advantage unlocks a repeat
	var skill_id := str(params.get("skill", "")) if params.get("skill") != null else ""
	var room := session.room_id
	var result: Dictionary
	var listener_id := CheckEngine.listener(session, Catalog.data, params)
	if not listener_id.is_empty() and ExplorationRules.SOCIAL_SKILLS.has(skill_id) and (params.get("target_id") == null or str(params["target_id"]).is_empty()):
		params["target_id"] = listener_id  # a talk's check is locked on its NPC, not on the room (v0.7.22.3)
	var state := ExplorationRules.state_key(session, Catalog.data, params, listener_id)
	var lock := ExplorationRules.locked(session, params, room, state)
	if not lock.is_empty():
		# A repeat without a change: the old result, no roll (ADR-0008 §2).
		result = (lock["result"] as Dictionary).duplicate()
		result["check_id"] = session.next_check_id()
		result["blocked"] = true
	else:
		result = CheckEngine.card(session, Catalog.data, params)
		ExplorationRules.lock(session, params, room, result, state)
		var mark := _theft_target(params)
		if not mark.is_empty():
			result["note"] = _theft(mark, bool(result["success"]))
		if bool(result["success"]) and not skill_id.is_empty():
			result["revealed"] = ExplorationRules.active_reveal(session, Catalog.data["world"], skill_id, int(result["total"]))
			if not listener_id.is_empty():  # v0.7.15.3: a won social check makes the NPC tell what it paid for
				(result["revealed"] as Array).append_array(SocialRules.reveal_by_check(session, Catalog.data, listener_id, skill_id, int(result["total"])))
	_add(GameSession.check_entry(params, result))
	if not bool(result.get("blocked", false)) and not skill_id.is_empty():  # a quest's secret missed: its act goes on from the failure (v0.8.4.31)
		var missed := QuestRules.missed(session, Catalog.data, skill_id)
		if not missed.is_empty():
			_told(missed)
	if not (result.get("revealed", []) as Array).is_empty():
		var found := ExplorationRules.take_caches(session, Catalog.data, room)
		found.append_array(QuestRules.advance(session, Catalog.data))
		if not found.is_empty():
			_told(found)
	return result


## «Выступить» (v0.7.11): a Performance check on a stage of the pack, once a day; coins and, for an entertainer, a free
## room tonight; the master narrates the show. The instrument the hero carries goes into the check (v0.8.4.26.4). "" or a
## localization key.
func perform() -> String:
	if not _master_ready():
		return "WAIT_BUSY"
	var why := BackgroundRules.can_perform(session, Catalog.data)
	if not why.is_empty():
		return why
	var text := tr("PERFORM_SAY")
	_add(GameSession.player_entry(text))
	var result := _engine_check(BackgroundRules.perform_check(session, Catalog.data))
	if result.has("error"):
		return "MSG_MASTER_FAILED"
	var lines := BackgroundRules.performed(session, Catalog.data, int(result["total"]), bool(result["success"]))
	_add(GameSession.effect_entry(lines))
	EventBus.state_changed.emit()
	_request("action", text + " [движок уже бросил Выступление %d — %s; %s — эффекты coins не нужны, опиши выступление и публику]" %
		[int(result["total"]), "успех" if bool(result["success"]) else "провал", ", ".join(lines)])
	return ""


## The NPC of the scene a Sleight of Hand check aims at (theft by words, v0.6.5), or "".
func _theft_target(params: Dictionary) -> String:
	if str(params.get("skill", "")) != "sleight_of_hand" or CombatRules.active(session):
		return ""
	var tid := str(params.get("target_id", "")) if params.get("target_id") != null else ""
	return tid if session.npcs_here(world().world, session.room_id).has(tid) else ""


## Theft by words: the engine gives the loot (rules.theft) or the NPC notices; the master narrates the note.
func _theft(npc_id: String, ok: bool) -> String:
	var who := WorldView.name_of(Catalog.data, npc_id)
	var before := Ledger.balance(session)
	var lines := TheftRules.steal(session, Catalog.data, npc_id, TheftRules.PURSE, ok)  # v0.8.4.29.1: the pockets' own road
	var cp := Ledger.balance(session) - before
	var note := ""
	if ok and cp <= 0:
		note = "Кража: у %s в кошеле больше ничего нет" % who
	elif ok:
		note = "Кража удалась, %s ничего не заметил(а): движок уже выдал %s (зм — золотые, см — серебряные, мм — медные) — опиши добычу ровно так" % [who, Money.format(cp)]
	else:
		note = "Кража провалилась: " + "; ".join(lines) + " — движок уже всё применил"
	if not lines.is_empty():
		_told(lines)
	return note


## A haggling check (the button or the master's request_check in trade mode): DC by attitude, the haggle percent or
## the day lock (TradeRules). A repeat returns the old result without a roll. Adds the check card.
func _haggle_check(params: Dictionary) -> Dictionary:
	var npc_id := session.npc_id
	var m := TradeRules.merchant(session, Catalog.data, npc_id)
	var skill := str(params["skill"])
	var result: Dictionary
	var pct := 0
	if not TradeRules.can_haggle(session, Catalog.data, npc_id).is_empty() and not (m["haggle_result"] as Dictionary).is_empty():
		result = (m["haggle_result"] as Dictionary).duplicate()
		result["check_id"] = session.next_check_id()
		result["blocked"] = true
	else:
		var p := params.duplicate()
		p["dc"] = TradeRules.haggle_dc(session, Catalog.data, npc_id)
		p["dc_tier"] = "medium"
		if bool(DevelopmentRules.effect(session.character, Catalog.data, "trade", "haggle_adv", false)):  # v0.7.19.1
			p["advantage_reason"] = str(DevelopmentRules.direction(Catalog.data, "trade")["skills"]["silver_tongue"]["name"])
		result = CheckEngine.card(session, Catalog.data, p)
		pct = TradeRules.apply_haggle(session, Catalog.data, npc_id, result)
		result["haggle_pct"] = pct
	result["note"] = TradeRules.haggle_note(tr("SKILL_" + skill.to_upper()), result, pct)
	_add(GameSession.check_entry(params, result))
	return result


func handle_engine_validate(params: Dictionary) -> Dictionary:
	if not _active(params) or not (params.get("effect") is Dictionary):
		return JsonRpcPeer.fail(-32041, "no such active turn or no effect")
	return effects.validate(session, Catalog.data, str(params["turn_id"]), params["effect"])


func handle_engine_lookup(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	return Lookup.find(session, Catalog.data, str(params.get("kind", "")), str(params.get("id", "")))


## The master looks for a place in the world before making one (v0.7.20.1).
func handle_engine_find_places(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	effects.searched_places[str(params["turn_id"])] = true
	return {"places": WorldGen.find_places(session, Catalog.data, str(params.get("query", ""))).slice(0, 10),
		"edges": WorldGen.reach_edges(session, Catalog.data).slice(0, 12)}  # where a new place may grow (the author, 2026-10-24)


## The master looks for a person in the world before making one (v0.7.20).
func handle_engine_find_npcs(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	effects.searched_npcs[str(params["turn_id"])] = true
	return {"npcs": WorldGen.find_npcs(session, Catalog.data, str(params.get("query", ""))).slice(0, 10)}


## Who of the world teaches a thing (v0.7.39.7): a teacher to point to, or none — a quest to find one.
func handle_engine_find_teachers(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	var kind := str(params.get("kind", ""))
	var what := TeachRules.resolve(session, Catalog.data, kind, str(params.get("what", "")))
	if what.is_empty():
		return {"what": "", "teachers": [], "reason": "Движок не знает «%s» (%s): назови id или точное русское название" % [params.get("what", ""), kind]}
	var out: Array = []
	for x: Dictionary in TeachRules.find(session, Catalog.data, kind, what):
		out.append({"npc_id": x["id"], "name": x["name"], "role": x["role"], "teaches": x["teaches"], "place": x["place"], "here": x["here"], "course": x["course"]})
	return {"what": what, "teachers": out}


func handle_engine_find_quests(params: Dictionary) -> Dictionary:  # v0.7.21
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	effects.searched_quests[str(params["turn_id"])] = true
	return {"quests": QuestGen.find_quests(session, Catalog.data, str(params.get("query", ""))).slice(0, 10),
		"open_made": QuestGen.open_made(session).size(), "max_open": int(QuestGen.cfg(Catalog.data)["max_open"])}


func handle_engine_find_items(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	effects.mark_searched(str(params["turn_id"]))
	var base := str(params.get("base", "")) if params.get("base") != null else ""
	return {"items": ItemRules.find(Catalog.data["items"], session.items, str(params.get("query", "")), base,
		params.get("properties", []))}
