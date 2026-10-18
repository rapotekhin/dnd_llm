class_name BackendConfig
extends RefCounted
## Where the LLM backend lives and how to authenticate (ADR-0007 §4, ADR-0009 §1).
## Sources, later wins: user://backend.cfg → env BTR_BACKEND_TOKEN → command line after `--`.
## The token never goes to logs: use describe() for output.

const DEFAULT_PATH := "user://backend.cfg"
const TOKEN_ENV := "BTR_BACKEND_TOKEN"
const LOCAL_HOSTS: Array[String] = ["localhost", "127.0.0.1", "::1"]

var url: String = "ws://127.0.0.1:8765/ws"
var token: String = ""
## Root certificate to trust for wss:// (Caddy `tls internal` in dev). Empty = system CAs.
var ca_cert_path: String = ""
var hello_timeout_s: float = 10.0


static func load_from(path: String = DEFAULT_PATH, args: PackedStringArray = OS.get_cmdline_user_args()) -> BackendConfig:
	var cfg := BackendConfig.new()
	var file := ConfigFile.new()
	if file.load(path) == OK:
		cfg.url = str(file.get_value("backend", "url", cfg.url))
		cfg.token = str(file.get_value("backend", "token", cfg.token))
		cfg.ca_cert_path = str(file.get_value("backend", "ca_cert", cfg.ca_cert_path))
	var env_token := OS.get_environment(TOKEN_ENV)
	if not env_token.is_empty():
		cfg.token = env_token
	for arg in args:
		if arg.begins_with("--backend-url="):
			cfg.url = arg.trim_prefix("--backend-url=")
		elif arg.begins_with("--backend-ca="):
			cfg.ca_cert_path = arg.trim_prefix("--backend-ca=")
	return cfg


## Empty string when the config is usable, otherwise why not.
func validate() -> String:
	if token.is_empty():
		return "no backend token (user://backend.cfg or %s)" % TOKEN_ENV
	if url.begins_with("wss://"):
		return ""
	if url.begins_with("ws://"):
		# Plain ws:// only to this machine: the token must not cross a network in the clear.
		return "" if host() in LOCAL_HOSTS else "ws:// is allowed only for localhost, use wss://"
	return "backend url must start with ws:// or wss://"


func host() -> String:
	var rest := url.get_slice("://", 1).get_slice("/", 0)
	if rest.begins_with("["):
		return rest.get_slice("]", 0).trim_prefix("[")
	return rest.get_slice(":", 0)


func tls_options() -> TLSOptions:
	if not url.begins_with("wss://"):
		return null
	if ca_cert_path.is_empty():
		return TLSOptions.client()
	var cert := X509Certificate.new()
	if cert.load(ca_cert_path) != OK:
		push_error("BackendConfig: cannot load CA certificate %s" % ca_cert_path)
		return TLSOptions.client()
	return TLSOptions.client(cert)


func describe() -> String:
	return "%s (token %s, ca %s)" % [url, "set" if not token.is_empty() else "missing", ca_cert_path if not ca_cert_path.is_empty() else "system"]
