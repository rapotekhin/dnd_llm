class_name ObjectRules
extends RefCounted
## Objects (v0.7.39.5, the author: «лавка — это объект, всё унифицировано»): a site (location → site → room) is an
## object of the world, one template for the pack's, the master's and the hero's. An object has its kind
## (rules.property.kinds — staff places by roles, income, trade, rent), its owner, its staff — any number of people
## with roles: the pack's or the master's `staff` [{npc, role}], the hero's hired hands (PropertyRules.staff) and the
## hero at a job there (JobRules — a job is a place in the staff of its employer's object), its upgrades (the site's
## `upgrades` and the hero's bought ones), hours, access (SiteRules) and a chronicle of its facts. The state of the
## hero's objects stays in c["property"] (PropertyRules), their shelves in c["shop"] (ShopRules).
##
## s.generated["site_facts"] = {site_id: ["день N: …"]}.

const FACTS_KEEP := 10


## The kind of the object: the hero's (built or bought), else the site's own `kind`, else the first kind among its tags.
static func kind_id(s: GameSession, data: Dictionary, sid: String) -> String:
	if not data["rules"].has("property"):
		return ""
	var pid := PropertyRules.at(s, data, WorldView.new(data["world"]).site_entry(sid))
	if not pid.is_empty() and PropertyRules.owned(s.character, pid):
		return PropertyRules.kind_id(s, data, pid)
	var site := WorldView.new(data["world"]).site(sid)
	if PropertyRules.kinds(data).has(str(site.get("kind", ""))):
		return str(site["kind"])
	for t: Variant in site.get("tags", []):
		if PropertyRules.kinds(data).has(str(t)):
			return str(t)
	return ""


static func kind_name(s: GameSession, data: Dictionary, sid: String) -> String:
	var k := kind_id(s, data, sid)
	return str(PropertyRules.kind_cfg(data, k).get("name", "")) if not k.is_empty() else ""


## The hero's property of the object, "" — not the hero's.
static func property_of(s: GameSession, data: Dictionary, sid: String) -> String:
	if not data["rules"].has("property"):
		return ""
	var pid := PropertyRules.at(s, data, WorldView.new(data["world"]).site_entry(sid))
	return pid if PropertyRules.owned(s.character, pid) else ""


## The staff of the object: [{who, name, role, source}] — `source`: "owner", "staff" (the pack's or the master's),
## "hired" (the hero's hand), "serf", "hero" (the hero's job here).
static func staff(s: GameSession, data: Dictionary, sid: String) -> Array[Dictionary]:
	var w := WorldView.new(data["world"])
	var site := w.site(sid)
	var out: Array[Dictionary] = []
	var owner := str(site.get("owner", ""))
	if not owner.is_empty() and owner != OwnerRules.HERO and not s.dead_npcs.has(owner):
		out.append({"who": owner, "name": str(w.npc(owner).get("name", owner)), "role": str(site.get("owner_role", "хозяин")), "source": "owner"})
	for h: Variant in site.get("staff", []):
		var npc := str((h as Dictionary).get("npc", ""))
		if not npc.is_empty() and not s.dead_npcs.has(npc) and npc != owner:
			out.append({"who": npc, "name": str(w.npc(npc).get("name", npc)), "role": str((h as Dictionary).get("role", "")), "source": "staff"})
	var pid := property_of(s, data, sid)
	if not pid.is_empty():
		for h: Dictionary in PropertyRules.staff(s, pid):
			out.append({"who": str(h.get("npc", h.get("cid", ""))), "name": PropertyRules.hand_name(s, data, h), "role": str(h.get("role", "")),
				"source": "serf" if bool(h.get("serf", false)) else "hired"})
	if data["rules"].has("jobs"):
		for jid: String in JobRules.state(s.character):
			if JobRules.site_of(s, data, jid) == sid:
				out.append({"who": OwnerRules.HERO, "name": str(s.character.get("name", "")),
					"role": JobRules.rank_name(s, data, jid, JobRules.rank(s.character, jid)), "source": "hero"})
	return out


## The upgrades the object has: the site's own and the hero's ready ones (names).
static func upgrades(s: GameSession, data: Dictionary, sid: String) -> Array[String]:
	var out: Array[String] = []
	if not data["rules"].has("property"):
		return out
	var ups: Dictionary = PropertyRules.ups(data)
	var ids: Array = (WorldView.new(data["world"]).site(sid).get("upgrades", []) as Array).duplicate()
	var pid := property_of(s, data, sid)
	if not pid.is_empty():
		ids.append_array(PropertyRules.state(s.character)[pid].get("upgrades", []))
	for u: Variant in ids:
		var n := str(ups.get(str(u), {}).get("name", u))
		if not out.has(n):
			out.append(n)
	return out


## A fact of the object for its chronicle (the master and the place window see it).
static func note(s: GameSession, sid: String, fact: String) -> void:
	if sid.is_empty():
		return
	var gen := WorldGen.generated(s)
	if not gen.has("site_facts"):
		gen["site_facts"] = {}
	var list: Array = gen["site_facts"].get(sid, [])
	list.append("день %d: %s" % [s.day, fact])
	while list.size() > FACTS_KEEP:
		list.pop_front()
	gen["site_facts"][sid] = list


static func facts(s: GameSession, sid: String) -> Array:
	return WorldGen.generated(s).get("site_facts", {}).get(sid, [])


## What the place window shows: {name, kind, owner, staff, upgrades, hours, public, facts, mine}.
static func info(s: GameSession, data: Dictionary, sid: String) -> Dictionary:
	var w := WorldView.new(data["world"])
	var site := w.site(sid)
	var owner := str(site.get("owner", ""))
	var h: Dictionary = site.get("hours", {})
	return {"name": str(site.get("name", sid)), "kind": kind_name(s, data, sid),
		"owner": "вы" if owner == OwnerRules.HERO else str(w.npc(owner).get("name", "")) if not owner.is_empty() else "",
		"staff": staff(s, data, sid), "upgrades": upgrades(s, data, sid),
		"hours": "%02d:00–%02d:00" % [int(h["from"]), int(h["to"])] if h.has("from") else "",
		"public": bool(site.get("public", true)), "facts": facts(s, sid), "mine": not property_of(s, data, sid).is_empty()}


## For the master — the object the hero stands in: «Объект «Кузница» (мастерская): хозяин …; штат: …; есть: …; было: …».
static func text(s: GameSession, data: Dictionary, room_id: String) -> String:
	var sid := WorldView.new(data["world"]).site_id(room_id)
	if sid.is_empty():
		return ""
	var i := info(s, data, sid)
	var bits: Array[String] = []
	if not str(i["owner"]).is_empty():
		bits.append("хозяин " + str(i["owner"]))
	var people: Array = (i["staff"] as Array).filter(func(x: Dictionary) -> bool: return str(x["source"]) != "owner")
	if not people.is_empty():
		bits.append("штат: " + ", ".join(people.map(func(x: Dictionary) -> String: return "%s (%s)" % [x["name"], x["role"]])))
	if not (i["upgrades"] as Array).is_empty():
		bits.append("есть: " + ", ".join(i["upgrades"]))
	if not str(i["hours"]).is_empty():
		bits.append("часы " + str(i["hours"]))
	var f: Array = i["facts"]
	if not f.is_empty():
		bits.append("было: " + "; ".join(f.slice(maxi(0, f.size() - 3))))
	if bits.is_empty():
		return ""
	return "Объект «%s»%s: %s" % [i["name"], (" (%s)" % i["kind"]) if not str(i["kind"]).is_empty() else "", "; ".join(bits)]
