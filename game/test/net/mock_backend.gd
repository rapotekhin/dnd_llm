class_name MockBackend
extends RefCounted
## A tiny llm_server stand-in for gdUnit (ADR-0009 §8): a WebSocket server on 127.0.0.1 that answers
## session.hello itself and hands every other message to `on_message`. Call poll() every frame.

var port: int = 0
var received: Array[Dictionary] = []
## func(mock: MockBackend, msg: Dictionary) -> void — the test's script for turn.request, engine answers, …
var on_message: Callable
var connections: int = 0

var _server := TCPServer.new()
var _peer: WebSocketPeer
var _pending_tcp: StreamPeerTCP


func start() -> int:
	for p in range(18765, 18865):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			return p
	return 0


func url() -> String:
	return "ws://127.0.0.1:%d/ws" % port


func stop() -> void:
	drop()
	_server.stop()


func poll() -> void:
	if _server.is_connection_available():
		_pending_tcp = _server.take_connection()
		_peer = WebSocketPeer.new()
		_peer.inbound_buffer_size = 1024 * 1024
		_peer.accept_stream(_pending_tcp)
		connections += 1
	if _peer == null:
		return
	_peer.poll()
	while _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN and _peer.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(_peer.get_packet().get_string_from_utf8())
		if not (msg is Dictionary):
			continue
		received.append(msg)
		if msg.get("method") == "session.hello":
			reply(msg, {"protocol_version": BackendClient.PROTOCOL_VERSION, "server_version": "mock", "model": "mock/model",
				"models": [{"id": "mock/model", "name": "Mock", "input_usd_per_mtok": 0.0, "output_usd_per_mtok": 0.0}],
				"limits": {"max_message_bytes": 1048576, "turn_timeout_s": 90, "engine_timeout_s": 10, "hello_timeout_s": 10}})
		elif on_message.is_valid():
			on_message.call(self, msg)


func send(msg: Dictionary) -> void:
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.send_text(JSON.stringify(msg))


func reply(to: Dictionary, result: Dictionary) -> void:
	send({"jsonrpc": "2.0", "id": to["id"], "result": result})


func reply_error(to: Dictionary, code: int, reason: String) -> void:
	send({"jsonrpc": "2.0", "id": to["id"], "error": {"code": code, "message": reason, "data": {"reason": reason, "retryable": true}}})


func call_engine(id: String, method: String, params: Dictionary) -> void:
	send({"jsonrpc": "2.0", "id": id, "method": method, "params": params})


## Cuts the connection without a close handshake (a dropped network).
func drop() -> void:
	if _peer != null:
		_peer.close(-1)
		_peer = null
	if _pending_tcp != null:
		_pending_tcp.disconnect_from_host()
		_pending_tcp = null


func methods() -> Array:
	return received.map(func(m: Dictionary) -> String: return str(m.get("method", "<result>")))
