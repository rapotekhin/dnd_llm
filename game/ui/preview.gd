class_name Preview
extends RefCounted
## Straight into a screen with a ready state, to look at the interface without playing up to it (the author, after
## v0.7.9): `godot --path game -- --preview=<name>` (list: `--preview=list`). The game runs as usual — scripts
## reload from the editor, the master answers if llm_server is up — but the saves go to the «preview» profile.
## Options: `--preset=<ready-made hero id>`, `--room=<room id>`.

const SCREENS := {
	"menu": "главное меню",
	"new_game": "экран новой игры",
	"creation": "создание персонажа",
	"game": "игра: таверна, чат, варианты, состояния над вводом",
	"sheet": "лист персонажа",
	"map": "карта",
	"journal": "журнал",
	"trade": "торговля с трактирщиком",
	"pockets": "окно карманов",
	"short_rest": "короткий отдых",
	"long_rest": "долгий отдых: комната и лагерь",
	"prepare": "подготовка заклинаний (жрец)",
	"level_up": "повышение уровня",
	"combat": "бой: волк, гоблин, паук; герой лежит и отравлен",
	"combat_results": "итоги победы",
	"death": "экран смерти",
	"settings": "настройки",
	"slots": "загрузка",
}


static func requested() -> bool:
	return LaunchArgs.has("--preview")


## Opens the screen of `--preview`. Called by main after the menu is up.
static func open(main: Node, which: String = "") -> void:
	var name := which if not which.is_empty() else LaunchArgs.value("--preview", "list")
	if not SCREENS.has(name):
		print("--preview=<name>, one of:")
		for k: String in SCREENS:
			print("  %-15s %s" % [k, SCREENS[k]])
		return
	match name:
		"menu":
			return
		"new_game":
			EventBus.navigate.emit("new_game", {})
		"creation":
			EventBus.navigate.emit("creation", {"settings": WorldPack.default_settings(Catalog.data["pack"])})
		"death":
			EventBus.navigate.emit("death", {"epitaph": "Айра пала на тропе лесорубов, прикрывая отход последнего ополченца. Её меч нашли в папоротнике, а Пуща ещё долго помнила её шаги."})
		"settings":
			EventBus.navigate.emit("settings", {"back": "menu"})
		"slots":
			EventBus.navigate.emit("slots", {"mode": SlotsScreen.MODE_LOAD, "back": "menu"})
		"combat", "combat_results":
			_start(_combat(name == "combat_results"))
		_:
			var s := _session("cleric_branko" if name == "prepare" else "fighter_aira")
			if name == "trade":
				s.mode = GameSession.MODE_TRADE
				s.npc_id = "npc_innkeeper"
			if name == "level_up":
				s.character["xp"] = LevelUp.xp_for(Catalog.data, 2)
			if name == "prepare":
				s.day = 2
			_start(s)
			await main.get_tree().process_frame
			await main.get_tree().process_frame
			_overlay(main, name)


static func _start(s: GameSession) -> void:
	GameState.start(s)


## A game in the tavern with a short chat, options and a few effects on the hero.
static func _session(fallback_preset: String) -> GameSession:
	var data := Catalog.data
	var preset_id := LaunchArgs.value("--preset", fallback_preset)
	var preset: Dictionary = data["presets"][0]
	for p: Dictionary in data["presets"]:
		if str(p["id"]) == preset_id:
			preset = p
	var c := CharacterBuilder.build_preset(preset, data)
	var room := LaunchArgs.value("--room", WorldView.new(data["world"]).start_room())
	var s := GameSession.create(42, Time.get_datetime_string_from_system(), room, c)
	s.world_id = Catalog.active_world
	s.settings = WorldPack.default_settings(data["pack"])
	CharacterRules.refresh(s.character, data, s.items)
	s.visited.append(room)
	s.append(GameSession.player_entry("Осматриваюсь в зале и подхожу к стойке."))
	s.append(GameSession.dm_entry("Низкий зал пахнет дымом и вчерашним элем. За стойкой **Бруно** протирает кружки и поглядывает на твой меч, у окна однорукий старик смотрит на восток.", "t-1"))
	s.append(GameSession.effect_entry(["Отравлен (1 ч 0 мин, кислое вино) — спасбросок Тел 9 против Сл 15 — провал"]))
	s.append(GameSession.npc_entry("npc_innkeeper", "Бруно", "Вино у нас, бывает, киснет. Не держи зла — следующая кружка за мой счёт.", "t-2"))
	s.options = ["Спросить Бруно о слухах", "Подойти к старику у окна", "Выйти на площадь"]
	ConditionRules.add_effect(s.character, {"condition": "poisoned", "ends": ConditionRules.ends_for(s, data, "hour"), "source": {"kind": "master", "name": "кислое вино"}})
	ConditionRules.add_effect(s.character, {"condition": "", "adv_tag": "poison", "ends": ConditionRules.ends_for(s, data, "hour"), "source": {"kind": "item", "name": "Противоядие"}})
	s.character["exhaustion"] = 1
	s.character["inventory"]["rations"] = 2
	s.character["inventory"]["bread"] = 1
	CharacterRules.refresh(s.character, data, s.items)
	return s


## A fight on the trail: a wolf next to the hero, a goblin and a giant spider further off; the hero is prone and
## poisoned, the spider is known. With `won` — the fight is over and its results wait.
static func _combat(won: bool) -> GameSession:
	var data := Catalog.data
	var s := _session("fighter_aira")
	s.room_id = "pushcha-trail"
	s.chat.clear()
	s.options.clear()
	s.append(GameSession.dm_entry("Из папоротника выходит серый волк, за ним на пне мелькает гоблин, а с ели на паутине спускается паук размером с собаку.", "t-3"))
	s.known_monsters.append("giant_spider")
	CombatRules.start(s, data, [{"monster": "wolf", "col": 0, "name": "Серый волк"}, {"monster": "goblin", "col": 2},
		{"monster": "giant_spider", "col": -2}], {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	ConditionRules.add_effect(s.character, {"condition": "prone", "ends": {}, "source": {"kind": "monster", "name": "Серый волк — Укус"}})
	CharacterRules.refresh(s.character, data, s.items)
	s.combat["log"] = ["Серый волк — Укус: 15 + 4 = 19 против КД 18 — попадание, 6 (колющий)",
		"Айра: спасбросок Сил 7 против Сл 11 — провал → лежит ничком", "Гоблин прячется (Проворное бегство)"]
	if won:
		for id: String in CombatRules.enemies(s):
			CombatRules.fighter(s, id)["status"] = "dead"
		s.combat["outcome"] = "victory"
		s.combat["narrated"] = true
		CombatRules.results(s, data, {"coins_cp": 1200, "items": {"healing_potion": 1}})
	return s


static func _overlay(main: Node, name: String) -> void:
	var node_name: String = {"sheet": "CharacterSheet", "map": "MapView", "journal": "JournalView", "short_rest": "ShortRestView",
		"long_rest": "LongRestView", "prepare": "PrepareView", "level_up": "LevelUpView", "pockets": "TheftView"}.get(name, "")
	if node_name.is_empty():
		return
	var view := main.find_child(node_name, true, false)
	if view == null:
		push_error("preview: no %s" % node_name)
		return
	if name == "pockets":
		view.call("open", "npc_innkeeper")
	else:
		view.call("open")
