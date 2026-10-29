extends SceneTree
## Balance of pack encounters on the engine alone: every ready-made hero at a level fights an encounter many times
## with a simple policy (heal at half HP with a potion or Second Wind, step to the nearest foe, attack, end the turn).
##   godot --headless --path game -s res://tools/balance_sim.gd -- <encounter_id> <level> <fights> [preset_id]
## <encounter_id> may be «foes:wolf*2+bandit» — a quest's fight by its foes (v0.7.39.6: the tiers of quest_gen).
## «arena» (v0.7.45) — the ladder of rules.arena.ranks: every hero against every opponent of every rank in a bout
## to surrender, the win rate by rank beside the engine's own estimate.
## Prints the win rate and the average HP left per hero; with a preset id also the log of its first fight.
## Not a test: numbers for the game author.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var enc_id := args[0] if args.size() > 0 else "burrow_priest"
	var level := int(args[1]) if args.size() > 1 else 3
	var fights := int(args[2]) if args.size() > 2 else 100
	var only := args[3] if args.size() > 3 else ""
	var data := TestUtils.data()
	if enc_id == "arena":
		_arena(data, level, fights, only)
		quit()
		return
	var enc := {}
	if enc_id.begins_with("foes:"):
		var foes: Array = []
		for part: String in enc_id.trim_prefix("foes:").split("+"):
			foes.append({"monster": part.get_slice("*", 0), "count": int(part.get_slice("*", 1)) if part.contains("*") else 1})
		enc = {"id": "sim", "enemies": foes}
	for rid: String in data["world"]["rooms"]:
		var e: Dictionary = data["world"]["rooms"][rid].get("encounter", {})
		if str(e.get("id", "")) == enc_id:
			enc = e
	if enc.is_empty():
		print("no encounter ", enc_id)
		quit(1)
		return
	var total_wins := 0
	var total := 0
	for p: Dictionary in data["presets"]:
		if not only.is_empty() and p["id"] != only:
			continue
		var wins := 0
		var hp_left := 0
		for i in fights:
			var s := TestUtils.new_session(1000 + i)
			_hero(s, data, p, level)
			CombatRules.start(s, data, enc["enemies"], {"waves": enc.get("waves", []), "help": enc.get("help", {}), "ambush": enc.get("ambush", false),
				"allies": [] if OS.get_environment("BALANCE_NO_ALLIES") == "1" else enc.get("allies", [])})
			var log := _play(s, data)
			if not only.is_empty() and i == 0:
				print("
".join(log))
			if str(s.combat["outcome"]) == "victory":
				wins += 1
				hp_left += int(s.character["hp"])
		total_wins += wins
		total += fights
		print("%-16s L%d  wins %3d%%  HP left after a win %4.1f" % [p["id"], level, wins * 100 / fights, float(hp_left) / maxi(1, wins)])
	print("all: %d%% of %d fights won — %s at level %d" % [total_wins * 100 / total, total, enc_id, level])
	quit()


func _hero(s: GameSession, data: Dictionary, p: Dictionary, level: int) -> void:
	s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	while int(s.character["level"]) < level:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
		CharacterRules.refresh(s.character, data)
	s.character["hp"] = int(s.character["max_hp"])


func _play(s: GameSession, data: Dictionary) -> Array[String]:
	var guard := 0
	var log: Array[String] = []
	while str(s.combat["outcome"]).is_empty() and guard < 400:
		guard += 1
		if CombatRules.player_can_act(s):
			log.append_array(_turn(s, data))
			log.append_array(CombatRules.after_player_action(s, data))
			if str(s.combat["outcome"]).is_empty():
				log.append_array(CombatRules.end_player_turn(s, data))
		else:
			log.append_array(CombatRules.next_actor(s, data))
	return log


## The arena's ladder: per rank, every hero's win rate in bouts to surrender and the engine's estimate (v0.7.45).
func _arena(data: Dictionary, level: int, fights: int, only: String) -> void:
	var ranks: Array = ArenaRules.ranks(data)
	for ri in ranks.size():
		var all_w := 0
		var all_n := 0
		for p: Dictionary in data["presets"]:
			if not only.is_empty() and p["id"] != only:
				continue
			var wins := 0
			var n := 0
			var est := 0.0
			for m: Variant in ranks[ri]["foes"]:
				for i in fights:
					var s := TestUtils.new_session(2000 + i)
					_hero(s, data, p, level)
					est += float(ArenaRules.hero_odds(s, data, "", str(m))["p"])
					CombatRules.start(s, data, [{"monster": str(m), "name": str(m)}], {"arena": {"kind": "rank", "rule": "yield", "site": "sim"}})
					_play(s, data)
					n += 1
					if str(s.combat["outcome"]) == "victory":
						wins += 1
			all_w += wins
			all_n += n
			print("%-12s %-16s L%d  wins %3d%%  estimate %3d%%" % [ranks[ri]["name"], p["id"], level, wins * 100 / n, roundi(est * 100 / n)])
		print("%s: %d%% of %d bouts won at level %d" % [ranks[ri]["name"], all_w * 100 / maxi(1, all_n), all_n, level])


func _turn(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var c := s.character
	if int(c["hp"]) * 2 < int(c["max_hp"]):
		if FeatureUses.can_use(c, data, "second_wind", 1).is_empty() and int(CombatRules.economy(s).get("bonus", 0)) > 0:
			CombatRules.economy(s)["bonus"] = 0
			lines.append_array(FeatureUses.use(c, data, "second_wind", 1, s.rng))
		elif int(c["inventory"].get("healing_potion", 0)) > 0 and int(CombatRules.economy(s).get("action", 0)) > 0:
			CombatRules.economy(s)["action"] = 0
			lines.append_array(ItemRules.use(c, data, s.items, "healing_potion", s.rng))
			return lines
	if CombatRules.can_stand(s).is_empty():  # v0.7.9: get up, break out of a web or a coil
		lines.append_array(CombatRules.stand(s))
	if ConditionRules.has(c, "restrained") and CombatRules.can_escape(s).is_empty():
		lines.append_array(CombatRules.escape(s, data))
		return lines
	for guard in 3:
		var near := ""
		var best := 99
		for id: String in CombatRules.enemies(s):
			var d := CombatRules.cols_between(CombatRules.player(s), CombatRules.fighter(s, id))
			if d < best:
				best = d
				near = id
		if near.is_empty():
			return lines
		var cast := ""
		for sp: String in SpellRules.ready(c):
			if CombatRules.is_engine_spell(data, sp) and CombatRules.can_cast(s, data, sp, 0, near).is_empty() and not data["spells"][sp].has("heal_at_slot"):
				cast = sp
		var caster := str(c.get("class", "")) in ["wizard", "sorcerer", "warlock", "bard"]
		if caster and not cast.is_empty():
			lines.append_array(CombatRules.player_cast(s, data, cast, 0, near))
			continue
		if CombatRules.can_attack(s, data, near).is_empty():
			lines.append_array(CombatRules.player_attack(s, data, near))
			continue
		if not cast.is_empty():
			lines.append_array(CombatRules.player_cast(s, data, cast, 0, near))
			continue
		var dir := 1 if int(CombatRules.fighter(s, near)["col"]) > int(CombatRules.player(s)["col"]) else -1
		if caster and not SpellRules.ready(c).is_empty():
			return lines  # a caster waits for the foe to come, it does not walk into its teeth
		if CombatRules.can_move(s, data, dir).is_empty() and best > 0:
			lines.append_array(CombatRules.player_move(s, data, dir))
			continue
		return lines
	return lines
