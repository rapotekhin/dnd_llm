class_name Look
extends RefCounted
## How a thing looks (v0.7.60.1, ADR-0012): the optional part `look` {token, sprite, icon, portrait} of a record in the
## pack, with res:// paths for the pictures. The token is what stands for it with no picture: a letter by default.


static func of(record: Dictionary) -> Dictionary:
	return record.get("look", {})


## The letter or mark of a record called `name`.
static func token(record: Dictionary, name: String) -> String:
	var t := str(of(record).get("token", ""))
	return t if not t.is_empty() else name.left(1).to_upper()
