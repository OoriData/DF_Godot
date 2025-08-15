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
	login_button.pressed.connect(_on_login_button_pressed)
	if is_instance_valid(google_button):
		google_button.pressed.connect(_on_discord_login_pressed)
	_connect_api_signals()
	user_id_line_edit.grab_focus()
	# Attempt automatic session reuse if token already valid
	var api = _api()
	if api and api.is_auth_token_valid():
		status_label.text = "Resuming session..."
		api.resolve_current_user_id()

func _process(_delta: float) -> void:
	# Lightweight spinner animation when OAuth in progress
	if _oauth_in_progress:
		_spin_status()

func _connect_api_signals() -> void:
	var api = _api()
	if not api:
		return
	if not api.auth_url_received.is_connected(_on_auth_url_received):
		api.auth_url_received.connect(_on_auth_url_received)
	if not api.fetch_error.is_connected(_on_api_error):
		api.fetch_error.connect(_on_api_error)
	if api.has_signal("auth_status_update") and not api.auth_status_update.is_connected(_on_auth_status_update):
		api.auth_status_update.connect(_on_auth_status_update)
	if api.has_signal("auth_session_received") and not api.auth_session_received.is_connected(_on_auth_session_received):
		api.auth_session_received.connect(_on_auth_session_received)
	if api.has_signal("user_id_resolved") and not api.user_id_resolved.is_connected(_on_user_id_resolved):
		api.user_id_resolved.connect(_on_user_id_resolved)
	if api.has_signal("auth_poll_started") and not api.auth_poll_started.is_connected(_on_auth_poll_started):
		api.auth_poll_started.connect(_on_auth_poll_started)
	if api.has_signal("auth_poll_finished") and not api.auth_poll_finished.is_connected(_on_auth_poll_finished):
		api.auth_poll_finished.connect(_on_auth_poll_finished)
	if api.has_signal("auth_expired") and not api.auth_expired.is_connected(_on_auth_expired):
		api.auth_expired.connect(_on_auth_expired)

func _on_login_button_pressed() -> void:
	var user_id: String = user_id_line_edit.text.strip_edges()
	if user_id.is_empty():
		status_label.text = "User ID cannot be empty."
		return
	status_label.text = "Loading user..."
	emit_signal("login_successful", user_id)

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

func _on_auth_status_update(status: String) -> void:
	if status != "pending":
		return
	# Spinner handled in _process; keep lightweight text
	if not status_label.text.begins_with("Authenticating"):
		status_label.text = "Authenticating"

func _on_auth_poll_started() -> void:
	_set_oauth_active(true)
	status_label.text = "Authenticating"

func _on_auth_poll_finished(success: bool) -> void:
	if not success:
		_set_oauth_active(false)
		# Preserve error message if already set
		if status_label.text == "Authenticating" or status_label.text == "":
			status_label.text = "Authentication failed."

func _on_auth_session_received(_token: String) -> void:
	status_label.text = "Session established. Resolving user..."

func _on_user_id_resolved(user_id: String) -> void:
	if user_id == "":
		status_label.text = "No linked user."
		_set_oauth_active(false)
		return
	status_label.text = "Welcome."  # Brief indicator
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

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and user_id_line_edit.has_focus():
		_on_login_button_pressed()
		get_viewport().set_input_as_handled()

func show_error(message: String) -> void:
	status_label.text = message

func _api():
	return get_node_or_null("/root/APICalls")