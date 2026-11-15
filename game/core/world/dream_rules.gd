class_name DreamRules
extends RefCounted
## The prologue as a dream (v0.8.4.44.2, the tutorial — docs/design/systems/tutorial/description.md): a world pack with
## `dream` {wake: {when, text}} is played before the world that names it its `prologue`. It is not in the list of worlds;
## the master makes nothing of the pack's `closed` kinds there (EffectEngine, the prompt); the hero comes into it with
## no things — its spells stay; when `wake.when` holds, the player wakes: a new game of the real world begins from the
## same creation choices and settings, at level 1 with its starting kit, and nothing of the dream remains (the session
## is a new one): the last screen of teaching says so (wake_row). The profile remembers the tutorial was played (SaveManager.tutorial_done).


## The dream part of a pack: {wake?}; {} — a world of its own.
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


## The settings the real game begins with: the new game screen's, without the dream's tick.
static func waking_settings(s: GameSession) -> Dictionary:
	var st: Dictionary = (s.dream.get("settings", {}) as Dictionary).duplicate(true)
	st.erase("tutorial")
	st["world"] = str(s.dream.get("world", ""))
	return st
