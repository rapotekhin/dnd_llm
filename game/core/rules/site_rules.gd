class_name SiteRules
extends RefCounted
## Sites (roadmap v0.7.22.24, the author's request): a location holds sites — a building, a yard, a cave — and a site
## holds rooms. A site gives its rooms an owner (an NPC), hours, tags of its kind and whether anyone may walk in
## (`public`, a room may say otherwise: a tavern's hall and rented rooms are public, its kitchen is not). Walking into a
## private room of someone else's site unasked, before eyes — the owner thinks worse of the hero and, where there is
## law, it is a light crime (`trespass`). Unseen (sneaking unnoticed, invisible), asked (the owner goes with the hero)
## or welcome (the owner's friend) — nothing. The author: the first time is a warning only (s.trespass_warned), the
## trespass is the next one; the exit button says a room is private.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["sites"]


## "" — the hero may be here; otherwise why not: the owner of this private room is alive and did not ask the hero in.
static func unwelcome(s: GameSession, data: Dictionary, room_id: String) -> String:
	var world := WorldView.new(data["world"])
	if world.is_public(room_id):
		return ""
	var owner := str(world.site_of(room_id).get("owner", ""))
	if owner.is_empty() or s.dead_npcs.has(owner) or s.followers.has(owner):
		return ""
	if s.attitude(owner) >= int(cfg(data)["welcome_attitude"]):
		return ""
	return owner


## On entering `room_id` (GameState._step, after sneaking): who sees a trespass and what follows. Lines.
static func on_enter(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var owner := unwelcome(s, data, room_id)
	if owner.is_empty() or s.sneaking or ConditionRules.invisible(s.character, data):
		return []  # welcome, or nobody saw the hero come in
	var world := WorldView.new(data["world"])
	var site_id := world.site_id(room_id)
	var seen := s.npcs_here(world.world, room_id)
	for r: String in world.site_rooms(site_id):  # the owner anywhere in the site hears the door
		if r != room_id and s.npcs_here(world.world, r).has(owner):
			seen.append(owner)
	if seen.is_empty():
		return []
	var who := ", ".join(seen.map(func(id: String) -> String: return str(world.npc(id).get("name", id))))
	if not s.trespass_warned.has(site_id):  # the first time — a warning
		s.trespass_warned[site_id] = TimeRules.abs_minute(s)
		return ["%s: «Сюда посторонним нельзя — выйдите!» Предупреждение: войдёте сюда снова без спроса — это вторжение" % who]
	var today := TimeRules.abs_minute(s) / 1440
	if s.crimes.any(func(c: Dictionary) -> bool: return str(c.get("kind")) == "trespass" and str(c.get("site", "")) == site_id and int(c["at"]) / 1440 == today):
		return []  # once a day a site
	var lines: Array[String] = ["%s: «Сюда посторонним нельзя!» — вы вошли без спроса (%s)" % [who, world.room_short(room_id).to_lower()]]
	if seen.has(owner):
		s.shift_attitude(owner, int(cfg(data)["trespass_attitude"]), data)
		s.remember(owner, "герой без спроса вошёл ко мне: %s" % world.room_short(room_id))
	lines.append_array(CrimeRules.on_trespass(s, data, owner, room_id, seen))
	return lines
