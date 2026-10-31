class_name Progress
extends RefCounted
## Progress to a term (v0.7.67, the audit's «Прогресс к сроку»): work counted up, a course or a craft, is {done, need}; a
## thing that is ready on its day, an upgrade or a building, is {ready}. One record and one reading for both.


static func of_work(need: int) -> Dictionary:
	return {"done": 0, "need": need}


static func by_day(day: int) -> Dictionary:
	return {"ready": day}


## Adds `n`; true when the work is done. `need` — a term that moved since the start (a course shortened by development).
static func add(rec: Dictionary, n: int, need: int = -1) -> bool:
	if need >= 0:
		rec["need"] = need
	rec["done"] = int(rec.get("done", 0)) + n
	return finished(rec)


static func finished(rec: Dictionary) -> bool:
	return int(rec.get("done", 0)) >= int(rec.get("need", 0))


static func left(rec: Dictionary) -> int:
	return maxi(0, int(rec.get("need", 0)) - int(rec.get("done", 0)))


static func percent(rec: Dictionary) -> int:
	return 0 if rec.is_empty() else int(100.0 * int(rec.get("done", 0)) / maxf(1.0, float(rec.get("need", 0))))


static func due(rec: Dictionary, day: int) -> bool:
	return rec.has("ready") and int(rec["ready"]) <= day


## Takes what is due on `day` out of `list` and gives it back.
static func take_due(list: Array, day: int) -> Array:
	var out: Array = list.filter(func(r: Dictionary) -> bool: return due(r, day))
	for r: Dictionary in out:
		list.erase(r)
	return out
