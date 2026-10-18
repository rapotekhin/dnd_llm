class_name JsonRpcPeer
extends RefCounted
## JSON-RPC 2.0 in both directions over one WebSocketPeer (ADR-0009 §2). Call poll() every frame.
## Outgoing ids are "g-N"; incoming requests go only to registered handlers (the engine.* whitelist).

signal opened
## code -1 = the connection never opened (no server, TLS failure, HTTP 401).
signal closed(code: int, reason: String)

const MAX_MESSAGE_BYTES := 1024 * 1024
const ERR_METHOD_NOT_FOUND := -32601
const ERR_INVALID_PARAMS := -32602
const ERR_INTERNAL := -32603
# Client-side only, never sent on the wire.
const ERR_CONNECTION_LOST := -32090
const ERR_CLIENT_TIMEOUT := -32091
const ERR_MESSAGE_TOO_BIG := -32092
## A handler returns a Dictionary result, or fail() to answer with an error.
const FAILURE_KEY := "__rpc_failure__"

var _ws: WebSocketPeer = WebSocketPeer.new()
var _state: WebSocketPeer.State = WebSocketPeer.STATE_CLOSED
var _next_id: int = 1
var _pending: Dictionary[String, RpcCall] = {}
var _handlers: Dictionary[String, Callable] = {}


static func fail(code: int, message: String) -> Dictionary:
	return {FAILURE_KEY: {"code": code, "message": message}}


func register_handler(method: String, handler: Callable) -> void:
	_handlers[method] = handler


func open(url: String, token: String, tls: TLSOptions = null) -> Error:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = MAX_MESSAGE_BYTES
	_ws.outbound_buffer_size = MAX_MESSAGE_BYTES
	# The token goes in the upgrade header, never in the URL (ADR-0009 §1).
	_ws.handshake_headers = PackedStringArray(["Authorization: Bearer %s" % token])
	var err := _ws.connect_to_url(url, tls)
	_state = WebSocketPeer.STATE_CONNECTING if err == OK else WebSocketPeer.STATE_CLOSED
	return err


func close(code: int = 1000) -> void:
	if _state != WebSocketPeer.STATE_CLOSED:
		_ws.close(code)


## Drop the socket without the close handshake and without emitting `closed` (the caller already knows).
func abort() -> void:
	_ws = WebSocketPeer.new()
	_state = WebSocketPeer.STATE_CLOSED
	_fail_pending(ERR_CONNECTION_LOST, "connection_lost")


func is_open() -> bool:
	return _state == WebSocketPeer.STATE_OPEN


func poll() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	while state != WebSocketPeer.STATE_CLOSED and _ws.get_available_packet_count() > 0:
		_on_text(_ws.get_packet().get_string_from_utf8())
	if state != _state:
		var was := _state
		_state = state
		if state == WebSocketPeer.STATE_OPEN:
			opened.emit()
		elif state == WebSocketPeer.STATE_CLOSED:
			_fail_pending(ERR_CONNECTION_LOST, "connection_lost")
			var code := _ws.get_close_code() if was != WebSocketPeer.STATE_CONNECTING else -1
			closed.emit(code, _ws.get_close_reason())
	_expire_calls()


func request(method: String, params: Dictionary, timeout_s: float) -> RpcCall:
	var call := RpcCall.new("g-%d" % _next_id, method, timeout_s)
	_next_id += 1
	if not is_open():
		call.finish(null, _local_error(ERR_CONNECTION_LOST, "connection_lost"))
		return call
	var err := _send({"jsonrpc": "2.0", "id": call.id, "method": method, "params": params})
	if err != OK:
		call.finish(null, _local_error(ERR_MESSAGE_TOO_BIG if err == ERR_OUT_OF_MEMORY else ERR_CONNECTION_LOST, "send_failed"))
		return call
	_pending[call.id] = call
	return call


# --- incoming ---------------------------------------------------------------


func _on_text(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not (msg is Dictionary) or msg.get("jsonrpc") != "2.0":
		push_warning("JsonRpcPeer: dropped malformed message")
		return
	if msg.has("method"):
		_handle_request(msg)
	elif msg.has("id"):
		var call: RpcCall = _pending.get(str(msg["id"]))
		if call == null:
			return  # late answer to a call that already timed out
		_pending.erase(call.id)
		var err: Variant = msg.get("error")
		call.finish(msg.get("result"), err if err is Dictionary else {})


func _handle_request(msg: Dictionary) -> void:
	var req_id: Variant = msg.get("id")
	var method := str(msg.get("method", ""))
	var params: Variant = msg.get("params", {})
	if req_id == null:
		return  # notifications are not part of the protocol yet
	if not _handlers.has(method):
		_send_error(req_id, ERR_METHOD_NOT_FOUND, "method not found: %s" % method)
		return
	if not (params is Dictionary):
		_send_error(req_id, ERR_INVALID_PARAMS, "params must be an object")
		return
	var out: Variant = await _handlers[method].call(params)
	if not (out is Dictionary):
		_send_error(req_id, ERR_INTERNAL, "handler returned no result")
	elif out.has(FAILURE_KEY):
		_send_error(req_id, int(out[FAILURE_KEY]["code"]), str(out[FAILURE_KEY]["message"]))
	else:
		_send({"jsonrpc": "2.0", "id": req_id, "result": out})


# --- helpers ----------------------------------------------------------------


func _send(msg: Dictionary) -> Error:
	var text := JSON.stringify(msg)
	if text.to_utf8_buffer().size() > MAX_MESSAGE_BYTES:
		push_error("JsonRpcPeer: message over %d bytes not sent" % MAX_MESSAGE_BYTES)
		return ERR_OUT_OF_MEMORY
	if not is_open():
		return ERR_CONNECTION_ERROR
	return _ws.send_text(text)


func _send_error(req_id: Variant, code: int, message: String) -> void:
	_send({"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}})


func _expire_calls() -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id: String in _pending.keys():
		var call: RpcCall = _pending[id]
		if now >= call.deadline_ms:
			_pending.erase(id)
			call.finish(null, _local_error(ERR_CLIENT_TIMEOUT, "client_timeout"))


func _fail_pending(code: int, reason: String) -> void:
	var calls := _pending.values()
	_pending.clear()
	for call: RpcCall in calls:
		call.finish(null, _local_error(code, reason))


static func _local_error(code: int, reason: String) -> Dictionary:
	return {"code": code, "message": reason, "data": {"reason": reason, "retryable": true}}
