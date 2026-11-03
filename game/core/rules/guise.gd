class_name Guise
extends RefCounted
## A look that is not one's own (v0.7.63): a status with the part `guise`, on anyone who holds statuses. Its end, its
## source and its place on the sheet are the status's.
## - A body: {monster, hp, max_hp} — the character is that template for now (Wild Shape).
## - A face: {name, faction, dc, seen {viewer: taken in}} — others see it, and each viewer is tested once against `dc` by
##   Investigation (a spell's DC, a kit's Deception). What a viewer found stays with it. With a faction the look is
##   one of its people: FactionRules reads who takes the hero for a friend and who for a foe.


static func _effect(h: Dictionary) -> Dictionary:
	for e: Dictionary in h.get("effects", []):
		if e.has("guise"):
			return e
	return {}


static func of(h: Dictionary) -> Dictionary:
	return _effect(h).get("guise", {})


## The template's body the character is in, {} when none.
static func body(h: Dictionary) -> Dictionary:
	var g := of(h)
	return g if g.has("monster") else {}


static func has_body(h: Dictionary) -> bool:
	return not body(h).is_empty()


## The name others see, "" when the character looks like itself.
static func face(h: Dictionary) -> String:
	return str(of(h).get("name", ""))


## A look laid but not named yet: the master names it by the effect `guise`; `dc` — what a viewer's Investigation must
## beat (a spell's DC, a disguise kit's Deception, v0.8.4.26.4).
static func blank(dc: int) -> Dictionary:
	return {"name": "", "faction": "", "dc": dc, "seen": {}}


## Puts a look on: the old one goes. `more` — what the status also gives while it is worn (a mimic's object form: `still`).
static func wear(h: Dictionary, guise: Dictionary, source: Dictionary, ends: Dictionary = {}, more: Dictionary = {}) -> void:
	take_off(h)
	ConditionRules.add_effect(h, more.merged({"guise": guise.duplicate(true), "source": source, "ends": ends}, true))


static func take_off(h: Dictionary) -> void:
	var e := _effect(h)
	if not e.is_empty():
		ConditionRules.remove_effect(h, int(e["uid"]))


## What the `viewer` has already made of the face (no new roll): it was taken in.
static func kept(h: Dictionary, viewer: String) -> bool:
	return bool((of(h).get("seen", {}) as Dictionary).get(viewer, false))


## The `viewer` (an NPC id, or a group by `mon` — its monster) takes the character for its face: tested once by
## Investigation, the answer is kept.
static func fools(s: GameSession, data: Dictionary, h: Dictionary, viewer: String, mon: String = "") -> bool:
	var g := of(h)
	if str(g.get("name", "")).is_empty():
		return false
	var seen: Dictionary = g.get("seen", {})
	g["seen"] = seen
	return taken_in(s, data, seen, viewer, int(g.get("dc", 10)), mon)


## Whether the `viewer` is taken in by a false thing of `dc` — a look, a forged letter (v0.8.4.26.4): its Investigation
## once, the answer kept in `seen`.
static func taken_in(s: GameSession, data: Dictionary, seen: Dictionary, viewer: String, dc: int, mon: String = "") -> bool:
	if not seen.has(viewer):
		var who := Sheet.who(s, data, viewer) if mon.is_empty() else {"monster": mon}
		seen[viewer] = not Roll.check(s, data, who, {"skill": "investigation", "dc": dc})["ok"]  # Investigation against the false thing
	return bool(seen[viewer])


## The effect `guise`: the master names the look a spell or a kit has laid. {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var look := str(e.get("look", "")).strip_edges().left(60)
	if look.is_empty():
		return {"reason": "нужен look: как выглядит герой"}
	var casting := pending.any(func(p: Dictionary) -> bool: return p["kind"] == "cast" and SpellEffects.spec(data, str(p["plan"]["spell_id"])).has("guise"))
	if (_effect(s.character).is_empty() or has_body(s.character)) and not casting:
		return {"reason": "чужого облика нет: сначала заклинание (cast «Маскировка»), набор для грима с пояса или части `guise` в make"}
	var faction := str(e.get("faction", "")) if e.get("faction") != null else ""
	if not faction.is_empty():
		if not FactionRules.has(s, data, faction):
			return {"reason": "фракции %s нет; есть: %s" % [faction, ", ".join(FactionRules.all(s, data).keys())]}
		if (data["rules"]["guise"]["no_kinds"] as Array).has(str(FactionRules.def(s, data, faction).get("kind", ""))):
			return {"reason": "за %s себя не выдать: облик не меняет телосложения и разума" % FactionRules.def(s, data, faction)["name"]}
	return {"plan": {"look": look, "faction": faction}, "summary": "Облик: %s" % look}


static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var g := of(s.character)
	if g.is_empty():
		return []
	g["name"] = str(p["look"])
	g["faction"] = str(p["faction"])
	g["seen"] = {}
	FactionRules.look_around(s, data, s.room_id)
	ReputationRules.refresh(s, data)
	return []


## For the master: the look and what it does, "" when the hero looks like itself.
static func text(s: GameSession, data: Dictionary) -> String:
	var g := of(s.character)
	if g.is_empty() or g.has("monster"):
		return ""
	var title := str(_effect(s.character).get("source", {}).get("name", ""))
	if str(g.get("name", "")).is_empty():
		return "%s лежит на герое, облик не назван: узнай у игрока, кем он выглядит, и дай эффект guise" % title
	var out := "Чужой облик (%s): %s, Сл разоблачения %d" % [title, g["name"], int(g.get("dc", 10))]
	var f := str(g.get("faction", ""))
	if f.is_empty():
		return out
	out += "; выдаёт себя за своего у «%s» (%s)" % [FactionRules.def(s, data, f).get("name", f), f]
	var foes := FactionRules.foes_of(s, data, f).map(func(id: String) -> String: return str(FactionRules.def(s, data, id).get("name", id)))
	return out + ("; для них враг: %s" % ", ".join(foes) if not foes.is_empty() else "")


## What the NPC makes of the hero's look, for the master. "" without a look.
static func seen_by(s: GameSession, id: String) -> String:
	var g := of(s.character)
	if str(g.get("name", "")).is_empty():
		return ""
	if not (g.get("seen", {}) as Dictionary).has(id):
		return " Ещё не присматривался к герою."
	return " Принимает героя за: %s." % g["name"] if kept(s.character, id) else " Разглядел: облик героя не настоящий."
