extends Node

signal sign_in_success(id_token: String, email: String, display_name: String, nonce: String)
signal sign_in_failed(error_msg: String)
signal sign_out_complete()
signal silent_sign_in_failed(error_msg: String)

var _plugin: Object = null
var _client_id: String = ""
var _is_linking: bool = false
var _pending_nonce: String = ""


func _ready() -> void:
	print("[GoogleAuthService] _ready() starting...")
	var cfg := ConfigFile.new()
	if cfg.load("res://app_config.cfg") == OK:
		_client_id = cfg.get_value("google", "web_client_id", "")
		print("[GoogleAuthService] App config loaded. Client ID present: ", _client_id != "")
	
	print("[GoogleAuthService] OS: ", OS.get_name(), " Has GodotGoogleSignIn: ", Engine.has_singleton("GodotGoogleSignIn"))
	if OS.get_name() == "Android" and Engine.has_singleton("GodotGoogleSignIn"):
		print("[GoogleAuthService] Getting plugin singleton...")
		_plugin = Engine.get_singleton("GodotGoogleSignIn")
		print("[GoogleAuthService] Plugin singleton found: ", _plugin != null)
		
		# Workaround: Connect signals if the plugin hasn't already done so.
		print("[GoogleAuthService] Connecting signals...")
		if not _plugin.is_connected("sign_in_success", Callable(self, "_on_sign_in_success")):
			_plugin.connect("sign_in_success", Callable(self, "_on_sign_in_success"))
		if not _plugin.is_connected("sign_in_failed", Callable(self, "_on_sign_in_failed")):
			_plugin.connect("sign_in_failed", Callable(self, "_on_sign_in_failed"))
		if not _plugin.is_connected("silent_sign_in_failed", Callable(self, "_on_silent_sign_in_failed")):
			_plugin.connect("silent_sign_in_failed", Callable(self, "_on_silent_sign_in_failed"))
		if not _plugin.is_connected("sign_out_complete", Callable(self, "_on_sign_out_complete")):
			_plugin.connect("sign_out_complete", Callable(self, "_on_sign_out_complete"))
		print("[GoogleAuthService] Signals connected.")
		
		if _client_id != "":
			print("[GoogleAuthService] Calling _plugin.initialize()...")
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
	print("[GoogleAuthService] sign_in() called. OS: ", OS.get_name())
	_is_linking = false
	if OS.get_name() == "Android":
		if _plugin:
			_pending_nonce = _generate_random_nonce()
			print("[GoogleAuthService] Calling _plugin.signInWithNonce()... Nonce: ", _pending_nonce)
			_plugin.signInWithNonce(_pending_nonce)
		else:
			print("[GoogleAuthService] ERROR: _plugin is null in sign_in()")
			emit_signal("sign_in_failed", "Google Sign-In plugin not found on Android.")
	else:
		# PC / Browser flow
		print("[GoogleAuthService] Initiating PC browser login flow.")
		_pending_nonce = ""
		APICalls.get_auth_url("google")

func silent_sign_in() -> void:
	print("[GoogleAuthService] silent_sign_in() called.")
	if OS.get_name() == "Android" and _plugin:
		_pending_nonce = _generate_random_nonce()
		_plugin.silentSignInWithNonce(_pending_nonce)
	else:
		emit_signal("silent_sign_in_failed", "Silent sign-in not supported on this platform.")

func connect_account() -> void:
	_is_linking = true
	if OS.get_name() == "Android":
		if _plugin:
			_pending_nonce = _generate_random_nonce()
			print("[GoogleAuthService] Calling _plugin.signInWithNonce() for linking... Nonce: ", _pending_nonce)
			_plugin.signInWithNonce(_pending_nonce)
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
	var nonce = _pending_nonce
	_pending_nonce = ""
	if _is_linking:
		APICalls.link_google_account(id_token, nonce)
	else:
		emit_signal("sign_in_success", id_token, email, display_name, nonce)


func _on_sign_in_failed(error_msg: String) -> void:
	print("[GoogleAuthService] Sign in failed: ", error_msg)
	emit_signal("sign_in_failed", error_msg)

func _on_silent_sign_in_failed(error_msg: String) -> void:
	print("[GoogleAuthService] Silent sign in failed: ", error_msg)
	emit_signal("silent_sign_in_failed", error_msg)

func _on_sign_out_complete() -> void:
	print("[GoogleAuthService] Signed out.")
	emit_signal("sign_out_complete")

func _generate_random_nonce() -> String:
	# Generate 32 bytes of random data for the nonce
	var crypto = Crypto.new()
	var bytes = crypto.generate_random_bytes(32)
	return bytes.hex_encode()


