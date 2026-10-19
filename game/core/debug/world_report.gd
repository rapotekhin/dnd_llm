class_name WorldReport
extends RefCounted
## Plain-text reports of the world and the session for the dev console (docs/tech/godot-client.md «Отладка»):
## what the pack defines and what the session already knows — revealed, sprung, taken, done. Pure: no nodes.

const MAX_FOUND := 40


## The room in full: exits (closed ones and why), NPCs, hooks, secrets / traps / caches with their state, the
## encounter, the things the master furnished, locks.
static func room(s: GameSession, data: Dictionary, room_id: String) -> String:
	var world: Dictionary = data["world"]
	var view := WorldView.new(world)
	var r := view.room(room_id)
	if r.is_empty():
		return "нет комнаты %s (rooms — список)" % room_id
	var out: PackedStringArray = []
	out.append("[%s] %s — %s%s" % [room_id, r.get("name", ""), view.location(view.location_id(room_id)).get("name", ""),
		" · ночлег %s" % Money.format(int(r["safe"].get("rest_cost_cp", 0))) if r.get("safe") is Dictionary else ""])
	out.append("  %s" % r.get("description", ""))
	out.append("  посещена: %s · время: день %d, %s" % ["да" if s.visited.has(room_id) else "нет", s.day, TimeRules.clock(s)])
	var open := ExplorationRules.open_exits(s, world, room_id)
	out.append("Выходы:")
	for to: String in view.exits(room_id):
		out.append("  → %s [%s]%s" % [view.room(to).get("name", to), to, "" if open.has(to) else " — ЗАКРЫТ"])
	for to: String in r.get("closed_exits", {}):
		if not view.exits(room_id).has(to):
			out.append("  → %s [%s] — %s: %s" % [view.room(to).get("name", to), to, "открыт" if open.has(to) else "ЗАКРЫТ",
				r["closed_exits"][to].get("text", "")])
	out.append("NPC:")
	for id: String in view.npcs_in(room_id):
		var n := view.npc(id)
		out.append("  %s [%s] — %s%s, отношение %+d%s" % [n.get("name", id), id, n.get("role", ""), " · МЁРТВ" if s.dead_npcs.has(id) else "",
			s.attitude(id), " · торговец" if bool(n.get("trader", false)) else ""])
	for h: Variant in r.get("hooks", []):
		out.append("Зацепка: %s" % (h.get("text", "") if h is Dictionary else str(h)))
	var found: Array = s.revealed.get(room_id, [])
	for sec: Dictionary in r.get("secrets", []):
		var key := ExplorationRules.secret_key(room_id, sec)
		var tags: PackedStringArray = ["найден" if found.has(str(sec["id"])) else "скрыт", "%s Сл %d" % [sec.get("skill", "perception"), int(sec.get("dc", 0))]]
		if sec.has("trap"):
			tags.append("ловушка: %s (обезвредить Сл %d, охраняет %s)" % [s.traps.get(key, "взведена"), int(sec["trap"].get("disarm_dc", 0)), sec["trap"].get("guards", "")])
		if sec.has("loot"):
			tags.append("тайник: %s — %s" % [JSON.stringify(sec["loot"]), "забран" if s.caches_taken.has(key) else "на месте"])
		out.append("Секрет %s [%s]: %s" % [sec["id"], ", ".join(tags), sec.get("text", "")])
	var enc: Dictionary = r.get("encounter", {})
	if not enc.is_empty():
		var foes: PackedStringArray = []
		for e: Dictionary in enc.get("enemies", []):
			foes.append("%s ×%d (%s)" % [e.get("name", e["monster"]), int(e.get("count", 1)), e["monster"]])
		out.append("Встреча %s — %s: %s" % [enc["id"], "пройдена" if s.encounters_done.has(str(enc["id"])) else "впереди", ", ".join(foes)])
	var props := PropRules.room_props(s, room_id)
	out.append("Вещи (%s):" % ("не обставлена" if PropRules.needs_furnish(s, room_id) else "%d" % props.size()))
	for p: Dictionary in props:
		out.append("  %s [%s] — %s%s%s%s" % [p.get("name", ""), p.get("prop_id", ""), p.get("state", ""),
			" · хозяин " + str(p["owner"]) if not str(p.get("owner", "")).is_empty() else "", " · можно взять" if bool(p.get("portable", false)) else "",
			" · предмет " + str(p["item_id"]) if not str(p.get("item_id", "")).is_empty() else ""])
	var locks: Dictionary = s.locks.get(room_id, {}) if s.locks.get(room_id) is Dictionary else {}
	if not locks.is_empty():
		out.append("Блоки проверок: %s" % JSON.stringify(locks))
	return "\n".join(out)


## Every quest of the pack: taken (the step), done, offered where, not met yet.
static func quests(s: GameSession, data: Dictionary) -> String:
	var world: Dictionary = data["world"]
	var view := WorldView.new(world)
	var here := QuestRules.offers_here(s, world)
	var out: PackedStringArray = []
	var stepped := QuestRules.stepped(world)
	for id: String in stepped:
		var q: Dictionary = stepped[id]
		var status := "не взято"
		if s.quests_done.has(id):
			status = "ВЫПОЛНЕНО"
		elif s.quests_active.has(id):
			status = "в работе, шаг %d: %s" % [int(s.quests_active[id]) + 1, QuestRules.step_text(s, world, id)]
		elif here.has(id):
			status = "даёт здесь (кнопка «Взять задание»)"
		out.append("«%s» [%s] — %s; даёт %s" % [q["title"], id, status, view.npc(str(q.get("giver", ""))).get("name", q.get("giver", "—"))])
		var i := 0
		for st: Dictionary in q.get("steps", []):
			var mark := "✓" if s.quests_done.has(id) or (s.quests_active.has(id) and i < int(s.quests_active[id])) else ("→" if s.quests_active.has(id) and i == int(s.quests_active[id]) else " ")
			out.append("   %s %d. %s  %s" % [mark, i + 1, st.get("text", ""), JSON.stringify(st.get("when", st.get("choices", {})))])
			i += 1
	var simple := XpRules.quests(world)
	for id: String in simple:
		if stepped.has(id):
			continue
		var q: Dictionary = simple[id]
		out.append("«%s» [%s] — %s; где: %s" % [q.get("title", id), id, "ВЫПОЛНЕНО" if s.quests_done.has(id) else "доступно", q.get("room", "")])
	return "\n".join(out) if not out.is_empty() else "в пакете нет заданий"


## The inventory; with `query` — the catalog, pack and game items whose id or name contains it.
static func items(s: GameSession, data: Dictionary, query: String = "") -> String:
	var out: PackedStringArray = []
	if query.is_empty():
		var c := s.character
		out.append("Монеты: %s" % Money.format(int(c.get("gold_cp", 0))))
		var inv: Dictionary = c.get("inventory", {})
		for id: String in inv:
			out.append("  %s [%s] ×%d" % [ItemRules.display_name(data["items"], s.items, id), id, int(inv[id])])
		out.append("Надето: %s" % JSON.stringify(c.get("equipped", {})))
		return "\n".join(out)
	var q := query.to_lower()
	var pools := {"каталог": data["items"].get("catalog", {}), "пакет": data["world"].get("items", {}), "игра": s.items}
	var n := 0
	for pool: String in pools:
		var defs: Dictionary = pools[pool]
		for id: String in defs:
			var d: Dictionary = defs[id]
			if not (id.to_lower().contains(q) or str(d.get("name", "")).to_lower().contains(q)):
				continue
			n += 1
			if n <= MAX_FOUND:
				out.append("%s [%s] (%s) — %s, %s, %s мм" % [d.get("name", id), id, pool, d.get("item_type", d.get("type", "")), d.get("rarity", "common"), int(d.get("value_cp", 0))])
	if n > MAX_FOUND:
		out.append("…и ещё %d" % (n - MAX_FOUND))
	return "\n".join(out) if n > 0 else "ничего не найдено по «%s»" % query


## One NPC by id or a part of the name: the pack entry and what the session knows about them.
static func npc(s: GameSession, data: Dictionary, query: String) -> String:
	var npcs: Dictionary = data["world"].get("npcs", {})
	var q := query.to_lower()
	for id: String in npcs:
		var n: Dictionary = npcs[id]
		if id != query and not str(n.get("name", "")).to_lower().contains(q):
			continue
		var where: PackedStringArray = []
		var rooms: Dictionary = data["world"]["rooms"]
		for rid: String in rooms:
			if (rooms[rid].get("npcs", []) as Array).has(id):
				where.append(rid)
		return "%s [%s] — %s\n  где: %s · отношение %+d%s\n  %s\n  пакет: %s\n  кошель/запас в игре: %s · карманы: %s\n  память: %s" % [
			n.get("name", id), id, n.get("role", ""), ", ".join(where), s.attitude(id), " · МЁРТВ" if s.dead_npcs.has(id) else "",
			n.get("description", ""), JSON.stringify(n), JSON.stringify(s.merchants.get(id, {})), JSON.stringify(s.pockets.get(id, {})),
			s.summaries.get("dialogue:" + id, "—")]
	return "нет NPC «%s»" % query


## Every room of the world by location, with what is done there.
static func rooms(s: GameSession, data: Dictionary) -> String:
	var view := WorldView.new(data["world"])
	var by_loc := {}
	var rs: Dictionary = data["world"]["rooms"]
	for rid: String in rs:
		var loc := view.location_id(rid)
		if not by_loc.has(loc):
			by_loc[loc] = PackedStringArray()
		var enc: Dictionary = rs[rid].get("encounter", {})
		by_loc[loc].append("  %s%s [%s]%s%s" % ["● " if rid == s.room_id else ("· " if s.visited.has(rid) else "  "), rs[rid].get("name", rid), rid,
			" · встреча " + ("пройдена" if s.encounters_done.has(str(enc["id"])) else "впереди") if not enc.is_empty() else "",
			" · секретов %d" % (rs[rid].get("secrets", []) as Array).size() if not (rs[rid].get("secrets", []) as Array).is_empty() else ""])
	var out: PackedStringArray = ["● здесь · · посещена"]
	for loc: String in by_loc:
		out.append(str(view.location(loc).get("name", loc)))
		out.append_array(by_loc[loc])
	return "\n".join(out)


## The world's memory: flags, visited, encounters, the dead, attitudes, known foes, time.
static func state(s: GameSession) -> String:
	return "день %d, %s · режим %s%s\nфлаги: %s\nпосещено: %s\nвстречи пройдены: %s\nпогибшие NPC: %s\nотношения: %s\nизвестные враги: %s\nобворованы: %s" % [
		s.day, TimeRules.clock(s), s.mode, " с " + s.npc_id if not s.npc_id.is_empty() else "", ", ".join(s.flags), ", ".join(s.visited),
		", ".join(s.encounters_done), ", ".join(s.dead_npcs), JSON.stringify(s.attitudes), ", ".join(s.known_monsters), JSON.stringify(s.pickpocketed)]
