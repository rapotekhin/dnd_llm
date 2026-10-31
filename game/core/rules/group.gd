class_name Group
extends RefCounted
## A group of people (v0.7.67, the audit's «Группа»): a faction, an organization, a settlement, the hero's family or
## party are one reading — {id, name, kind, head, members, ranks, rank, treasury_cp}. Each keeps its own state: an
## organization's ranks in OrgRules, a town's treasury in OfficeRules, the standing in FactionRules.

const FAMILY := "family"
const PARTY := "party"


## The group by id: a faction or organization of the world, or the hero's `family` / `party`. {} — no such group.
static func view(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	if id == FAMILY:
		var kin: Array[String] = []
		if not FamilyRules.spouse(s).is_empty():
			kin.append(FamilyRules.spouse(s))
		kin.append_array(FamilyRules.children(s))
		return _record(id, "семья", "family", OwnerRules.HERO, kin)
	if id == PARTY:
		var near: Array[String] = []
		near.assign(Being.followers(s))
		return _record(id, "спутники", "party", OwnerRules.HERO, near)
	var d := FactionRules.def(s, data, id)
	if d.is_empty():
		return {}
	var out := _record(id, str(d.get("name", id)), str(d.get("kind", "")), str(d.get("head", "")), _people(s, data, id))
	if OrgRules.all(s, data).has(id):
		out["members"] = _merged(out["members"], OrgRules.members(s, data, id))
		out["ranks"] = OrgRules.ranks(s, data, id)
		out["rank"] = OrgRules.rank(s, data, id) if OrgRules.member(s.character, id) else -1
	var scope: Variant = d.get("scope", "")
	if str(d.get("kind", "")) == "settlement" and scope is Array and not (scope as Array).is_empty():
		out["treasury_cp"] = int(s.character.get("towns", {}).get(str(scope[0]), {}).get("treasury", 0))
	return out


## The groups a person leads.
static func headed_by(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in FactionRules.all(s, data):
		if str(FactionRules.def(s, data, id).get("head", "")) == npc_id:
			out.append(id)
	return out


## The living people of the pack and the master who belong to a faction.
static func _people(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var out: Array[String] = []
	for n: String in data["world"]["npcs"]:
		if FactionRules.of_npc(s, data, n) == id and not Being.dead(s, n):
			out.append(n)
	return out


static func _merged(a: Array, b: Array) -> Array[String]:
	var out: Array[String] = []
	for x: Variant in a + b:
		if not out.has(str(x)):
			out.append(str(x))
	return out


static func _record(id: String, name: String, kind: String, head: String, members: Array[String]) -> Dictionary:
	return {"id": id, "name": name, "kind": kind, "head": head, "members": members, "ranks": [], "rank": -1, "treasury_cp": 0}
