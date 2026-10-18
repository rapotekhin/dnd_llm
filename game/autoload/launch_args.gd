class_name LaunchArgs
extends RefCounted
## User arguments after `--` on the command line, in `--name=value` form (docs/tech/dev-tools.md).


static func has(flag: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == flag or arg.begins_with(flag + "="):
			return true
	return false


## The value of `--flag=value`, `fallback` when the flag is missing.
static func value(flag: String, fallback: String = "") -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(flag + "="):
			return arg.trim_prefix(flag + "=")
	return fallback
