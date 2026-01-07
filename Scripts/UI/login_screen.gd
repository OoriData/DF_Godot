extends Control

signal login_successful(user_id: String)

# Removed obsolete InstructionsLabel (not present in scene)
@onready var user_id_line_edit: LineEdit = $CenterContainer/VBoxContainer/UserIDLineEdit
@onready var center_container: CenterContainer = $CenterContainer
@onready var vbox_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var login_button: Button = $CenterContainer/VBoxContainer/LoginButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var google_button: Button = $CenterContainer/VBoxContainer/GoogleLoginButton  # Discord login button

var _pkce_state: String = ""
var _pkce_code_verifier: String = ""
var _spinner_phase: int = 0
var _spinner_timer: Timer
var _oauth_in_progress: bool = false

func _ready() -> void:
	# Manual user ID login disabled for production. Hide related controls.
	if is_instance_valid(user_id_line_edit):
		user_id_line_edit.visible = false
	if is_instance_valid(login_button):
		login_button.visible = false
	# (Disabled) login_button.pressed.connect(_on_login_button_pressed)
	if is_instance_valid(google_button):
		google_button.pressed.connect(_on_discord_login_pressed)
	_connect_hub_store_signals()
	_connect_api_signals()
	# Focus now goes to OAuth button if needed
	if is_instance_valid(google_button):
		google_button.grab_focus()
	# Attempt automatic session reuse if token already valid
	var api = _api()
	if api and api.is_auth_token_valid():
		status_label.text = "Resuming session..."
		api.resolve_current_user_id()

func _process(_delta: float) -> void:
	# Lightweight spinner animation when OAuth in progress
	if _oauth_in_progress:
		_spin_status()

func _connect_hub_store_signals() -> void:
	var hub := get_node_or_null("/root/SignalHub")
	if is_instance_valid(hub):
		if hub.has_signal("auth_state_changed") and not hub.auth_state_changed.is_connected(_on_auth_state_changed):
			hub.auth_state_changed.connect(_on_auth_state_changed)
		if hub.has_signal("error_occurred") and not hub.error_occurred.is_connected(_on_hub_error_occurred):
			hub.error_occurred.connect(_on_hub_error_occurred)
	var store := get_node_or_null("/root/GameStore")
	if is_instance_valid(store):
		if store.has_signal("user_changed") and not store.user_changed.is_connected(_on_store_user_changed):
			store.user_changed.connect(_on_store_user_changed)

func _connect_api_signals() -> void:
	var api = _api()
	if is_instance_valid(api):
		if api.has_signal("user_id_resolved") and not api.user_id_resolved.is_connected(_on_user_id_resolved):
			api.user_id_resolved.connect(_on_user_id_resolved)
		if api.has_signal("auth_url_received") and not api.auth_url_received.is_connected(_on_auth_url_received):
			api.auth_url_received.connect(_on_auth_url_received)
		if api.has_signal("fetch_error") and not api.fetch_error.is_connected(_on_api_error):
			api.fetch_error.connect(_on_api_error)
		if api.has_signal("auth_expired") and not api.auth_expired.is_connected(_on_auth_expired):
			api.auth_expired.connect(_on_auth_expired)

# Disabled manual user ID login handler (kept for potential future debugging)
# func _on_login_button_pressed() -> void:
# 	var user_id: String = user_id_line_edit.text.strip_edges()
# 	if user_id.is_empty():
# 		status_label.text = "User ID cannot be empty."
# 		return
# 	status_label.text = "Loading user..."
# 	emit_signal("login_successful", user_id)

func _on_discord_login_pressed() -> void:
	if _oauth_in_progress:
		return
	status_label.text = "Starting Discord auth..."
	var api = _api()
	if api == null:
		status_label.text = "Auth system not ready."
		return
	api.get_auth_url()

func _on_auth_url_received(data: Dictionary) -> void:
	var auth_url: String = str(data.get("url", ""))
	_pkce_state = str(data.get("state", ""))
	_pkce_code_verifier = str(data.get("code_verifier", ""))
	if auth_url == "":
		status_label.text = "Failed to get auth URL."
		return
	OS.shell_open(auth_url)
	status_label.text = "Browser opened. Complete Discord sign-in..."

func _on_api_error(message: String) -> void:
	if _oauth_in_progress:
		status_label.text = "Auth error: %s" % message
		_set_oauth_active(false)
	else:
		status_label.text = message

func _on_auth_state_changed(state: String) -> void:
	# Drive UI from canonical Hub auth state.
	match state:
		"pending":
			_set_oauth_active(true)
			if not status_label.text.begins_with("Authenticating"):
				status_label.text = "Authenticating"
		"authenticated":
			# User resolution will arrive via GameStore.user_changed
			status_label.text = "Session established. Resolving user..."
			_set_oauth_active(false)
		"expired":
			_set_oauth_active(false)
			status_label.text = "Session expired. Please login."
		"failed":
			_set_oauth_active(false)
			if status_label.text == "Authenticating" or status_label.text == "":
				status_label.text = "Authentication failed."
		_: # default
			pass

func _on_hub_error_occurred(domain: String, code: String, message: String, inline: bool) -> void:
	if domain == "auth" or not inline:
		show_error(message)

func _on_store_user_changed(user: Dictionary) -> void:
	var uid := String(user.get("user_id", user.get("id", "")))
	if uid == "":
		return
	status_label.text = "Welcome."
	_set_oauth_active(false)
	emit_signal("login_successful", uid)

func _on_user_id_resolved(user_id: String) -> void:
	# Deprecated: prefer GameStore.user_changed; kept for compatibility.
	if user_id == "":
		status_label.text = "Failed to resolve user."
		_set_oauth_active(false)
		return
	status_label.text = "Welcome."
	_set_oauth_active(false)
	emit_signal("login_successful", user_id)

func _on_auth_expired() -> void:
	_set_oauth_active(false)
	status_label.text = "Session expired. Please login."

func _spin_status() -> void:
	if not status_label.text.begins_with("Authenticating"):
		return
	var dots = (_spinner_phase % 4)
	var base = "Authenticating" + ".".repeat(dots)
	status_label.text = base
	_spinner_phase += 1

func _set_oauth_active(active: bool) -> void:
	_oauth_in_progress = active
	google_button.disabled = active
	login_button.disabled = active
	if active and _spinner_timer == null:
		_spinner_timer = Timer.new()
		_spinner_timer.wait_time = 0.5
		_spinner_timer.autostart = true
		_spinner_timer.one_shot = false
		add_child(_spinner_timer)
		_spinner_timer.timeout.connect(_spin_status)
	elif not active and _spinner_timer:
		_spinner_timer.queue_free()
		_spinner_timer = null

func _input(_event: InputEvent) -> void:
	# Manual user ID entry disabled; ignore enter key path.
	pass

func show_error(message: String) -> void:
	status_label.text = message

func _api():
	return get_node_or_null("/root/APICalls")
