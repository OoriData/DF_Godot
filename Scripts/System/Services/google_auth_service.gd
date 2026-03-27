extends Node

signal sign_in_success(id_token: String, email: String, display_name: String)
signal sign_in_failed(error_msg: String)
signal sign_out_complete()

var _plugin: Object = null
var _client_id: String = ""
var _is_linking: bool = false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://app_config.cfg") == OK:
		_client_id = cfg.get_value("google", "web_client_id", "")
	
	if OS.get_name() == "Android" and Engine.has_singleton("GodotGoogleSignIn"):
		_plugin = Engine.get_singleton("GodotGoogleSignIn")
		
		# Workaround: Connect signals if the plugin hasn't already done so.
		if not _plugin.is_connected("sign_in_success", Callable(self, "_on_sign_in_success")):
			_plugin.connect("sign_in_success", Callable(self, "_on_sign_in_success"))
		if not _plugin.is_connected("sign_in_failed", Callable(self, "_on_sign_in_failed")):
			_plugin.connect("sign_in_failed", Callable(self, "_on_sign_in_failed"))
		if not _plugin.is_connected("sign_out_complete", Callable(self, "_on_sign_out_complete")):
			_plugin.connect("sign_out_complete", Callable(self, "_on_sign_out_complete"))
		
		if _client_id != "":
			_plugin.initialize(_client_id)
			print("[GoogleAuthService] Initialized with client ID.")
		else:
			printerr("[GoogleAuthService] Missing web_client_id in app_config.cfg under [google]")
	else:
		print("[GoogleAuthService] Plugin GodotGoogleSignIn not found or not on Android. Using browser-based flow for PC.")
	

func is_available() -> bool:
	if OS.get_name() == "Android":
		return _plugin != null
	return true # Browser-based flow is always available on PC

func sign_in() -> void:
	_is_linking = false
	if OS.get_name() == "Android":
		if _plugin:
			_plugin.signIn()
		else:
			emit_signal("sign_in_failed", "Google Sign-In plugin not found on Android.")
	else:
		# PC / Browser flow
		print("[GoogleAuthService] Initiating PC browser login flow.")
		APICalls.get_auth_url("google")

func connect_account() -> void:
	_is_linking = true
	if OS.get_name() == "Android":
		if _plugin:
			_plugin.signIn()
		else:
			emit_signal("sign_in_failed", "Google Sign-In plugin not found on Android.")
	else:
		# PC / Browser link flow
		print("[GoogleAuthService] Initiating PC browser connect flow.")
		APICalls.get_google_link_url()

func sign_out() -> void:
	if is_available():
		_plugin.signOut()

func _on_sign_in_success(id_token: String, email: String, display_name: String) -> void:
	print("[GoogleAuthService] Sign in success. Email: ", email, " Linking: ", _is_linking)
	if _is_linking:
		APICalls.link_google_account(id_token)
	else:
		emit_signal("sign_in_success", id_token, email, display_name)


func _on_sign_in_failed(error_msg: String) -> void:
	printerr("[GoogleAuthService] Sign in failed: ", error_msg)
	emit_signal("sign_in_failed", error_msg)

func _on_sign_out_complete() -> void:
	print("[GoogleAuthService] Signed out.")
	emit_signal("sign_out_complete")


