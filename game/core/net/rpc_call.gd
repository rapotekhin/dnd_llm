class_name RpcCall
extends RefCounted
## One outgoing JSON-RPC request. Await `wait()`: it returns at once if the call already finished.

signal completed(call: RpcCall)

var id: String
var method: String
var result: Variant = null
var error: Dictionary = {}
var done: bool = false
var deadline_ms: int = 0


func _init(call_id: String, call_method: String, timeout_s: float) -> void:
	id = call_id
	method = call_method
	deadline_ms = Time.get_ticks_msec() + int(timeout_s * 1000.0)


func wait() -> RpcCall:
	if not done:
		await completed
	return self


func is_error() -> bool:
	return not error.is_empty()


## Machine-readable reason from error.data.reason (ADR-0009 §7), "" on success.
func reason() -> String:
	var data: Variant = error.get("data", {})
	return str(data.get("reason", "")) if data is Dictionary else ""


func finish(res: Variant, err: Dictionary) -> void:
	if done:
		return
	done = true
	result = res
	error = err
	completed.emit(self)
