class_name DreamRules
extends RefCounted
## The prologue as a dream (v0.8.4.44.2, the tutorial — docs/design/systems/tutorial/description.md): a world pack with
## `dream` {wake: {when, text}} is played before the world that names it its `prologue`. It is not in the list of worlds;
## the master makes nothing of the pack's `closed` kinds there (EffectEngine, the prompt); the hero comes into it with
## no things — its spells stay; when `wake.when` holds, the player wakes: a new game of the real world begins from the
## same creation choices and settings, at level 1 with its starting kit, and nothing of the dream remains (the session
## is a new one): the last screen of teaching says so (wake_row). The profile remembers the tutorial was played (SaveManager.tutorial_done).


const BACK := "back"  ## a death in the dream: the hall again from its entry
const END := "end"  ## a death in the dream's last hall: the dream is over


## The dream part of a pack: {wake?, fall?}; {} — a world of its own.
static func of(pack: Dictionary) -> Dictionary:
	return pack["dream"] if pack.get("dream") is Dictionary else {}


static func is_dream(pack: Dictionary) -> bool:
	return pack.get("dream") is Dictionary


## The master may not make an effect of `kind` in this world (the pack's `closed`, a dream's world-building).
static func closes(data: Dictionary, kind: String) -> bool:
	return (data.get("pack", {}).get("closed", []) as Array).has(kind)


## The game `s` begins as a dream of the world `world_id`: the real game is kept to begin on waking.
static func begin(s: GameSession, data: Dictionary, world_id: String, choices: Dictionary, settings: Dictionary) -> void:
	s.dream = {"world": world_id, "choices": choices.duplicate(true), "settings": settings.duplicate(true)}
	Gear.strip(s, data, Being.HERO, false)
	s.character["bags"] = {}
	CharacterRules.refresh(s.character, data, s.items)


## The dream's end as a screen of teaching (HintRules, v0.8.4.44.5): `wake.when` and its words, «Проснуться» instead of
## «Продолжить» — the last row of the queue, shown in every dream whatever the hints' setting; {} — not a dream.
static func wake_row(pack: Dictionary) -> Dictionary:
	var wake: Dictionary = of(pack).get("wake", {})
	if not wake.get("when") is Dictionary:
		return {}
	return {"id": HintRules.WAKE, "when": wake["when"], "title": TranslationServer.translate("WAKE_TITLE"), "text": str(wake.get("text", "")),
		"once": HintRules.GAME, "button": HintRules.WAKE}


## What a death does in the dream `s` (the pack's `dream.fall`, v0.8.4.44.7, the author's decision 12): "" — not a dream, a
## death; END — in a hall of its `end`: the dream is over, its `flag` set (a wake's `when`), nothing reset; BACK — the hero
## comes back to the entry of the hall where it fell (the checkpoint GameState made when it walked in).
static func fall(s: GameSession, data: Dictionary) -> String:
	var f: Dictionary = of(data.get("pack", {})).get("fall", {})
	if s.dream.is_empty() or f.is_empty():
		return ""
	return END if (f.get("end", []) as Array).has(s.room_id) else BACK


## The hall again after a death (v0.8.4.44.7, found by the tutorial playtest of v0.8.4.44.8): the party whole — the hero
## and whoever walks with it at their hit points' maximum — and other dice than last time (the save keeps the generator's
## state: without it the same blows fell the hero the same way at every try, from the same wounded entry). `tries` — how
## many times the hall came back in this game.
static func again(s: GameSession, data: Dictionary, tries: int) -> void:
	for p: Dictionary in AllyRules.party(s, data):
		var who: Dictionary = p["who"]
		Harm.mend(s, data, who, Sheet.max_hp(s, data, who))
	s.rng.seed = Roll.seeded([s.game_seed, s.room_id, "dream_again", tries]).seed


## The dream is over by a death in its last hall: its flag. Lines — none.
static func end(s: GameSession, data: Dictionary) -> void:
	var flag := str(of(data.get("pack", {})).get("fall", {}).get("flag", ""))
	if not flag.is_empty() and not s.flags.has(flag):
		s.flags.append(flag)


## The settings the real game begins with: the new game screen's, without the dream's tick.
static func waking_settings(s: GameSession) -> Dictionary:
	var st: Dictionary = (s.dream.get("settings", {}) as Dictionary).duplicate(true)
	st.erase("tutorial")
	st["world"] = str(s.dream.get("world", ""))
	return st
