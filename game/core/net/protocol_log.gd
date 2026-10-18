class_name ProtocolLog
extends RefCounted
## Every JSON-RPC message to/from the backend as JSON lines (ADR-0009 §8: base for cassettes and replay).
## The token travels only in the upgrade header, so messages never contain it.

const KEPT_IN_MEMORY := 200

var path: String = ""
var recent: PackedStringArray = []
var _file: FileAccess


## Starts a new log at `file_path`; the previous run's log is kept as *.prev.jsonl.
func open(file_path: String) -> void:
	path = file_path
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	if FileAccess.file_exists(file_path):
		var prev := file_path.get_basename() + ".prev.jsonl"
		DirAccess.remove_absolute(prev)
		DirAccess.rename_absolute(file_path, prev)
	_file = FileAccess.open(file_path, FileAccess.WRITE)


func record(direction: String, text: String) -> void:
	var line := JSON.stringify({"t": Time.get_ticks_msec(), "dir": direction, "msg": text})
	recent.append(line)
	if recent.size() > KEPT_IN_MEMORY:
		recent = recent.slice(recent.size() - KEPT_IN_MEMORY)
	if _file != null:
		_file.store_line(line)
		_file.flush()
