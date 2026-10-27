class_name ImageFrame
extends RefCounted
## The frame of the last event (v0.7.35): the brush draws what the master told last. One image per event — the path
## to its file stays on the event's chat entry (`image`), saved with the chat; the brush on it opens that one again.

const GENDER := {"female": "женщина", "male": "мужчина"}


## The index of the last event's entry in the chat: the master's or an NPC's line; -1 — nothing to draw yet.
static func event_index(s: GameSession) -> int:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) in [GameSession.KIND_DM, GameSession.KIND_NPC]:
			return i
	return -1


## The image already drawn for the entry, or "".
static func image_of(entry: Dictionary) -> String:
	return str(entry.get("image", ""))


## The event's text: the player's words and every line of the master's turn that ends at `index`.
static func event_text(s: GameSession, index: int) -> String:
	var last: Dictionary = s.chat[index]
	var turn := str(last.get("turn_id", ""))
	var lines: Array[String] = []
	for i in range(index, -1, -1):
		var e: Dictionary = s.chat[i]
		var kind := str(e.get("kind", ""))
		if kind == GameSession.KIND_PLAYER:
			lines.push_front("Герой: " + str(e.get("text", "")))
			break
		if kind in [GameSession.KIND_DM, GameSession.KIND_NPC]:
			if i != index and (turn.is_empty() or str(e.get("turn_id", "")) != turn):
				break
			lines.push_front(("%s: %s" % [e.get("name", ""), e.get("text", "")]) if kind == GameSession.KIND_NPC else str(e.get("text", "")))
	return "\n".join(lines).left(3900)


## The image.request params of the event at `index`: the place, the hour, the hero's looks, the people it names.
static func params(s: GameSession, data: Dictionary, index: int) -> Dictionary:
	var world := WorldView.new(data["world"])
	var room := SceneRules.room(s, data["world"], s.room_id)
	var loc := world.location(world.location_id(s.room_id))
	var event := event_text(s, index)
	var people: Array[String] = []
	for id: String in s.npcs_here(world.world, s.room_id):
		var n := world.npc(id)
		var name := str(n.get("name", id))
		if people.size() < 8 and event.contains(name.get_slice(" ", 0)):
			var sex := str(GENDER.get(str(n.get("gender", "")), ""))
			var looks := ", ".join([str(n.get("race", "")), sex, BodyRules.npc_text(data, id, n)].filter(func(x: String) -> bool: return not x.is_empty()))
			people.append("%s — %s; %s" % [name, looks, str(n.get("description", "")).left(300)])
	return {
		"event": event,
		"place": "%s, %s: %s" % [loc.get("name", ""), room.get("name", s.room_id), str(room.get("description", "")).left(600)],
		"time": "%s, %s%s" % [TimeRules.part_name(s, data), TimeRules.clock(s), ", темно" if TimeRules.dark(s, data) else ""],
		"hero": hero(s, data),
		"people": people,
		"style": str(data.get("pack", {}).get("image_style", "")),
		"adult": bool(s.settings.get("adult", false)),  # v0.7.38.7: 18+ only with no child or teen in the frame
	}


## «Айра, человек, женщина, молодая, крепкая, высокая; воин; Кольчуга, Щит, Длинный меч».
static func hero(s: GameSession, data: Dictionary) -> String:
	var c := s.character
	var gender := str(c.get("gender", "other"))
	var looks: Array[String] = [str(c.get("name", "")), str(c.get("race_name", ""))]
	if GENDER.has(gender):
		looks.append(GENDER[gender])
	var body := BodyRules.text(data, c.get("body", {}), gender)
	if not body.is_empty():
		looks.append(body)
	var gear: Array[String] = []
	for slot: String in CharacterRules.SLOTS:
		var id := str(c.get("equipped", {}).get(slot, ""))
		if not id.is_empty():
			gear.append(ItemRules.display_name(data["items"], s.items, id))
	return "%s; %s%s" % [", ".join(looks.filter(func(x: String) -> bool: return not x.is_empty())), str(c.get("class_name", "")).to_lower(),
		("; " + ", ".join(gear)) if not gear.is_empty() else ""]


## Where the event's image lives: one folder per playthrough, one file per event.
static func file_path(dir: String, s: GameSession, index: int) -> String:
	var game := ("%s_%d" % [s.created_at, s.game_seed]).validate_filename().replace(" ", "_")
	var turn := str(s.chat[index].get("turn_id", ""))
	return "%s/images/%s/%s.webp" % [dir, game, (turn if not turn.is_empty() else "e%d" % index).validate_filename()]


## The answer's bytes as an image no wider than `max_width`; null — not an image.
static func decode(mime: String, data_b64: String, max_width: int) -> Image:
	var bytes := Marshalls.base64_to_raw(data_b64)
	var img := Image.new()
	var err: Error
	match mime:
		"image/jpeg", "image/jpg":
			err = img.load_jpg_from_buffer(bytes)
		"image/webp":
			err = img.load_webp_from_buffer(bytes)
		_:
			err = img.load_png_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	if img.get_width() > max_width:
		img.resize(max_width, roundi(float(img.get_height()) * max_width / img.get_width()), Image.INTERPOLATE_LANCZOS)
	return img
