extends Control

signal login_successful(user_id: String)

@onready var center_container: CenterContainer = $CenterContainer
@onready var vbox_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var subtitle_label: Label = $CenterContainer/VBoxContainer/SubtitleLabel
@onready var background_overlay: ColorRect = $Background
@onready var title_logo: TextureRect = $CenterContainer/VBoxContainer/TitleLogo
@onready var loading_bar: ProgressBar = $CenterContainer/VBoxContainer/LoadingBar

# Brand colors
const DISCORD_BLURPLE := Color("5865F2")
const DISCORD_HOVER := Color("6D78F6")
const DISCORD_PRESSED := Color("4752C4")

const APPLE_BLACK := Color("111111")
const APPLE_HOVER := Color("1f1f1f")
const APPLE_PRESSED := Color("000000")

const GOOGLE_BLUE := Color("4285F4")
const GOOGLE_HOVER := Color("5b97f5")
const GOOGLE_PRESSED := Color("3367d6")

const STEAM_DARK := Color("171a21")
const STEAM_HOVER := Color("2a475e")
const STEAM_ACCENT := Color("66c0f4")

const DISABLED_BG := Color("2a2a2a")

const _TERRAIN_INT_TO_NAME := {
	0: "impassable",
	1: "highway",
	2: "road",
	3: "trail",
	4: "desert",
	5: "plains",
	6: "forest",
	7: "swamp",
	8: "mountains",
	9: "near_impassible",
}

const _SETTLEMENT_TYPE_TO_NAME := {
	"town": "town",
	"village": "village",
	"city": "city",
	"city-state": "city-state",
	"dome": "dome",
	"military_base": "military_base",
	"tutorial": "tutorial",
}

var _pkce_state: String = ""
var _pkce_code_verifier: String = ""
var _spinner_phase: int = 0
var _spinner_timer: Timer
var _oauth_in_progress: bool = false

var _bg_viewport: SubViewport
var _bg_texture_rect: TextureRect
var _bg_root: Node2D
var _bg_tilemap: TileMapLayer
var _bg_camera: Camera2D
var _bg_tile_name_to_entry: Dictionary = {}
var _bg_map_size: Vector2i = Vector2i(140, 90)
var _bg_drift_speed: Vector2 = Vector2(18.0, 10.0)
var _bg_time: float = 0.0
var _bg_has_real_map: bool = false

var _discord_button: Button = null
var _apple_button: Button = null
var _google_button: Button = null
var _steam_button: Button = null
var _active_oauth_provider_label: String = "Discord"

# ────────────────────────────────────────────────────────────────────
# Lifecycle
# ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	print("[LoginScreen] _ready() called.")
	_setup_map_background()

	if SteamManager.has_signal("steam_initialized"):
		if not SteamManager.steam_initialized.is_connected(_on_steam_initialized):
			SteamManager.steam_initialized.connect(_on_steam_initialized)

	if GoogleAuthService.has_signal("sign_in_success"):
		if not GoogleAuthService.sign_in_success.is_connected(_on_google_native_login_success):
			GoogleAuthService.sign_in_success.connect(_on_google_native_login_success)
		if not GoogleAuthService.sign_in_failed.is_connected(_on_google_native_login_error):
			GoogleAuthService.sign_in_failed.connect(_on_google_native_login_error)

	_connect_hub_store_signals()
	_connect_api_signals()
	_build_login_buttons()
	_try_use_real_map_background()

	# Ensure overlay sits above the generated map background.
	if is_instance_valid(background_overlay):
		background_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Apply portrait layout before first frame
	_apply_portrait_layout()

	# Focus the first button
	if is_instance_valid(_discord_button):
		_discord_button.grab_focus()

	# Attempt automatic session reuse if token already valid
	var api = _api()
	if api and api.is_auth_token_valid():
		set_loading_mode(true, "Resuming session...")
	else:
		set_loading_mode(false)

	_add_version_label()

func set_loading_mode(active: bool, message: String = "") -> void:
	if active:
		if message != "":
			status_label.text = message
		_set_oauth_active(true)
		if is_instance_valid(subtitle_label):
			subtitle_label.visible = false
		if is_instance_valid(loading_bar):
			loading_bar.visible = true
			loading_bar.value = 0
		for btn in [_discord_button, _apple_button, _google_button, _steam_button]:
			if is_instance_valid(btn):
				btn.visible = false
	else:
		_set_oauth_active(false)
		if is_instance_valid(subtitle_label):
			subtitle_label.visible = true
		if is_instance_valid(loading_bar):
			loading_bar.visible = false
		for btn in [_discord_button, _apple_button, _google_button, _steam_button]:
			if is_instance_valid(btn):
				# Don't show steam button if disabled initially
				if btn == _steam_button and not SteamManager.is_steam_running():
					btn.visible = true
					_disable_steam_button()
				else:
					btn.visible = true

func _process(_delta: float) -> void:
	_update_map_background(_delta)
	
	if is_instance_valid(loading_bar) and loading_bar.visible:
		# Simple "indeterminate" pulse animation
		loading_bar.value = 50.0 + sin(_bg_time * 5.0) * 50.0

	if _oauth_in_progress:
		_spin_status()

# ────────────────────────────────────────────────────────────────────
# Portrait / Mobile helpers
# ────────────────────────────────────────────────────────────────────

func _is_portrait() -> bool:
	var sz := get_viewport_rect().size
	return sz.y > sz.x

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"]

## Re-sizes buttons and spacing to fill portrait screen width on mobile.
func _apply_portrait_layout() -> void:
	if not is_instance_valid(vbox_container):
		return

	var viewport_sz := get_viewport_rect().size
	var portrait := _is_portrait()
	var mobile := _is_mobile()

	if portrait and mobile:
		# Derive a uniform scale so all elements grow proportionally.
		# Reference width is 340 px (original button). Target 88 % of screen.
		var scale_f: float = (viewport_sz.x * 0.88) / 340.0

		var btn_w: float  = 340.0 * scale_f
		var btn_h: float  = 54.0  * scale_f
		var font_sz: int  = int(round(16.0 * scale_f))
		var vbox_sep: int = int(round(10.0 * scale_f))

		vbox_container.add_theme_constant_override("separation", vbox_sep)

		for btn in [_discord_button, _apple_button, _google_button, _steam_button]:
			if not is_instance_valid(btn):
				continue
			btn.custom_minimum_size = Vector2(btn_w, btn_h)
			btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			btn.add_theme_font_size_override("font_size", font_sz)

		# Scale the logo halfway between original and full scale (avoids clipping)
		if is_instance_valid(title_logo):
			var logo_f: float = (scale_f + 1.0) / 2.0
			title_logo.custom_minimum_size = Vector2(520.0 * logo_f, 160.0 * logo_f)

		if is_instance_valid(loading_bar):
			loading_bar.custom_minimum_size = Vector2(btn_w, 8 * scale_f)

		if is_instance_valid(status_label) and status_label.label_settings:
			status_label.label_settings.font_size = int(round(52.0 * scale_f))
			status_label.custom_minimum_size = Vector2(btn_w, 96 * scale_f)

		# Zoom the background camera so the map bleeds off all 4 edges
		if is_instance_valid(_bg_camera):
			_bg_camera.zoom = Vector2(4.5, 4.5)
	else:
		# Restore defaults
		vbox_container.add_theme_constant_override("separation", 8)
		for btn in [_discord_button, _apple_button, _google_button, _steam_button]:
			if not is_instance_valid(btn):
				continue
			btn.custom_minimum_size = Vector2(340, 54)
			btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			btn.remove_theme_font_size_override("font_size")
		if is_instance_valid(status_label) and status_label.label_settings:
			status_label.label_settings.font_size = 36
			status_label.custom_minimum_size = Vector2(300, 56)
		if is_instance_valid(loading_bar):
			loading_bar.custom_minimum_size = Vector2(340, 8)
		if is_instance_valid(_bg_camera):
			_bg_camera.zoom = Vector2(1.05, 1.05)

# ────────────────────────────────────────────────────────────────────
# Button creation
# ────────────────────────────────────────────────────────────────────

func _build_login_buttons() -> void:
	if not is_instance_valid(vbox_container):
		return

	# Determine the insert index — right before StatusLabel
	var insert_idx := 0
	for i in range(vbox_container.get_child_count()):
		if vbox_container.get_child(i) == status_label:
			insert_idx = i
			break

	# --- Discord (always shown) ---
	_discord_button = _create_login_button(
		"DiscordLoginButton", "Continue with Discord",
		DISCORD_BLURPLE, DISCORD_HOVER, DISCORD_PRESSED,
		_on_discord_login_pressed
	)
	vbox_container.add_child(_discord_button)
	vbox_container.move_child(_discord_button, insert_idx)
	insert_idx += 1

	# --- Apple (always shown — native plugin on macOS/iOS, web OAuth elsewhere) ---
	_apple_button = _create_login_button(
		"AppleLoginButton", "Continue with Apple",
		APPLE_BLACK, APPLE_HOVER, APPLE_PRESSED,
		_on_apple_login_pressed
	)
	vbox_container.add_child(_apple_button)
	vbox_container.move_child(_apple_button, insert_idx)
	insert_idx += 1

	# --- Google (only when the native service is available) ---
	if GoogleAuthService.is_available():
		_google_button = _create_login_button(
			"GoogleLoginButton", "Continue with Google",
			GOOGLE_BLUE, GOOGLE_HOVER, GOOGLE_PRESSED,
			_on_google_login_pressed
		)
		vbox_container.add_child(_google_button)
		vbox_container.move_child(_google_button, insert_idx)
		insert_idx += 1

	# --- Steam (only shown on desktop; disabled if Steam client isn't running) ---
	if not _is_mobile():
		_steam_button = _create_login_button(
			"SteamLoginButton", "Continue with Steam",
			STEAM_DARK, STEAM_HOVER, STEAM_DARK,
			_on_steam_login_pressed
		)
		# Add Steam accent border
		var steam_normal: StyleBoxFlat = _steam_button.get_theme_stylebox("normal")
		if steam_normal:
			steam_normal.border_width_bottom = 2
			steam_normal.border_color = STEAM_ACCENT
		var steam_hover: StyleBoxFlat = _steam_button.get_theme_stylebox("hover")
		if steam_hover:
			steam_hover.border_width_bottom = 2
			steam_hover.border_color = STEAM_ACCENT

		vbox_container.add_child(_steam_button)
		vbox_container.move_child(_steam_button, insert_idx)

		# Enable/disable Steam based on current state
		if SteamManager.is_steam_running():
			_enable_steam_button()
		else:
			_disable_steam_button()

	# --- Debug Bypass (only in debug builds) ---
	if OS.is_debug_build():
		var debug_btn = _create_login_button(
			"DebugSkipButton", "DEBUG: Skip Login",
			Color("444444"), Color("555555"), Color("333333"),
			_on_debug_skip_pressed
		)
		vbox_container.add_child(debug_btn)
		# Place at the bottom
		vbox_container.move_child(debug_btn, vbox_container.get_child_count() - 1)

func _create_login_button(
	btn_name: String, label: String,
	color_normal: Color, color_hover: Color, color_pressed: Color,
	callback: Callable
) -> Button:
	var b := Button.new()
	b.name = btn_name
	b.text = label
	b.custom_minimum_size = Vector2(340, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Font colors
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))

	# Normal
	var normal := StyleBoxFlat.new()
	normal.bg_color = color_normal
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10

	# Hover
	var hover := normal.duplicate()
	hover.bg_color = color_hover

	# Pressed
	var pressed := normal.duplicate()
	pressed.bg_color = color_pressed

	# Disabled
	var disabled := normal.duplicate()
	disabled.bg_color = DISABLED_BG

	# Focus
	var focus := normal.duplicate()
	focus.border_width_left = 2
	focus.border_width_right = 2
	focus.border_width_top = 2
	focus.border_width_bottom = 2
	focus.border_color = Color(1, 1, 1, 0.35)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus)

	b.pressed.connect(callback)
	return b

# ────────────────────────────────────────────────────────────────────
# Steam button helpers
# ────────────────────────────────────────────────────────────────────

func _enable_steam_button() -> void:
	if not is_instance_valid(_steam_button):
		return
	print("[LoginScreen] Enabling Steam login button.")
	_steam_button.disabled = false
	_steam_button.tooltip_text = ""

func _disable_steam_button() -> void:
	if not is_instance_valid(_steam_button):
		return
	_steam_button.disabled = true
	_steam_button.tooltip_text = "Steam client is not running"
	_steam_button.focus_mode = Control.FOCUS_NONE

func _on_steam_initialized() -> void:
	print("[LoginScreen] Steam initialized signal received.")
	_enable_steam_button()

# ────────────────────────────────────────────────────────────────────
# Auth handlers
# ────────────────────────────────────────────────────────────────────

func _on_discord_login_pressed() -> void:
	if _oauth_in_progress:
		return
	_active_oauth_provider_label = "Discord"
	status_label.text = "Starting Discord auth..."
	var api = _api()
	if api == null:
		status_label.text = "Auth system not ready."
		return
	api.get_auth_url("discord")

func _on_apple_login_pressed() -> void:
	if _oauth_in_progress:
		return
	_active_oauth_provider_label = "Apple"
	status_label.text = "Starting Apple auth..."
	_set_oauth_active(true)
	var api = _api()
	if api == null:
		status_label.text = "Auth system not ready."
		_set_oauth_active(false)
		return

	# Attempt to use native Plugin on macOS/iOS
	if OS.get_name() in ["macOS", "iOS"]:
		if Engine.has_singleton("SignInWithApple"):
			var apple = Engine.get_singleton("SignInWithApple")
			if not apple.is_connected("on_login_success", Callable(self, "_on_apple_native_login_success")):
				apple.connect("on_login_success", Callable(self, "_on_apple_native_login_success"))
				apple.connect("on_login_error", Callable(self, "_on_apple_native_login_error"))
			apple.login()
			return
		elif Engine.has_singleton("AppleAuth"):
			var apple = Engine.get_singleton("AppleAuth")
			apple.login()
			return

	# Fallback to Web OAuth flow
	api.get_auth_url("apple")

func _on_apple_native_login_success(identity_token: String, _auth_code: String = "") -> void:
	var api = _api()
	if api:
		status_label.text = "Verifying Apple session..."
		api.login_with_apple(identity_token)

func _on_apple_native_login_error(error_msg: String) -> void:
	status_label.text = "Apple sign-in failed: " + error_msg
	_set_oauth_active(false)

func _on_google_login_pressed() -> void:
	if _oauth_in_progress:
		return
	_active_oauth_provider_label = "Google"
	status_label.text = "Starting Google auth..."
	_set_oauth_active(true)
	var api = _api()
	if api == null:
		status_label.text = "Auth system not ready."
		_set_oauth_active(false)
		return

	GoogleAuthService.sign_in()

func _on_google_native_login_success(id_token: String, email: String, display_name: String, nonce: String) -> void:
	var api = _api()
	if api:
		status_label.text = "Verifying Google session..."
		api.login_with_google(id_token, nonce)

func _on_google_native_login_error(error_msg: String) -> void:
	status_label.text = "Google sign-in failed: " + error_msg
	_set_oauth_active(false)

func _on_steam_login_pressed() -> void:
	if _oauth_in_progress:
		return
	status_label.text = "Checking Steam ID..."
	var steam_id = SteamManager.get_steam_id()
	if steam_id == "":
		status_label.text = "Error: Could not get Steam ID."
		return

	status_label.text = "Logging in with Steam..."
	_set_oauth_active(true)
	var api = _api()
	if api:
		var persona := ""
		if SteamManager.has_method("get_steam_username"):
			persona = SteamManager.get_steam_username()
		api.login_with_steam(steam_id, persona)
	else:
		status_label.text = "API System offline."
		_set_oauth_active(false)

func _on_debug_skip_pressed() -> void:
	if _oauth_in_progress:
		return
	_active_oauth_provider_label = "Debug Bypass"
	status_label.text = "Starting Debug Bypass..."
	_set_oauth_active(true)
	var api = _api()
	if api == null:
		status_label.text = "Auth system not ready."
		_set_oauth_active(false)
		return
	
	print("[LoginScreen] Debug bypass triggered. Setting dummy token.")
	var store := get_node_or_null("/root/GameStore")
	if is_instance_valid(store) and store.has_method("set_session_token"):
		store.set_session_token("DEBUG_BYPASS_TOKEN")
	else:
		api.set_auth_session_token("DEBUG_BYPASS_TOKEN")
		
	status_label.text = "Bypassing authentication..."
	api.resolve_current_user_id(true)

# ────────────────────────────────────────────────────────────────────
# OAuth / auth-state plumbing
# ────────────────────────────────────────────────────────────────────

func _on_auth_url_received(data: Dictionary) -> void:
	var auth_url: String = str(data.get("url", ""))
	_pkce_state = str(data.get("state", ""))
	_pkce_code_verifier = str(data.get("code_verifier", ""))
	if auth_url == "":
		status_label.text = "Failed to get auth URL."
		return
	OS.shell_open(auth_url)
	status_label.text = "Browser opened. Complete %s sign-in..." % _active_oauth_provider_label

func _on_api_error(message: String) -> void:
	var friendly := ErrorTranslator.translate(message)
	
	# Always reset oauth state on API error to prevent UI hang, 
	# even if the error message itself is silenced.
	if _oauth_in_progress:
		_set_oauth_active(false)
	
	if friendly.is_empty():
		# If it's a silenced auth error (like 401 during background poll), 
		# we don't want to overwrite the status label if we're not currently in an OAuth flow.
		if _oauth_in_progress:
			status_label.text = "Authentication failed."
		return
		
	status_label.text = friendly

func _on_auth_state_changed(state: String) -> void:
	match state:
		"pending":
			set_loading_mode(true, "Authenticating")
		"authenticated":
			set_loading_mode(true, "Session established. Resolving user...")
		"expired":
			set_loading_mode(false)
			status_label.text = "Session expired. Please login."
		"failed":
			set_loading_mode(false)
			if status_label.text == "Authenticating" or status_label.text == "" or status_label.text.begins_with("Authenticating"):
				status_label.text = "Authentication failed."
		_:
			pass

func _on_hub_error_occurred(domain: String, _code: String, message: String, inline: bool) -> void:
	if domain == "auth" or not inline:
		set_loading_mode(false)
		show_error(message)

func _on_store_user_changed(user: Dictionary) -> void:
	var uid := String(user.get("user_id", user.get("id", "")))
	if uid == "":
		return
	status_label.text = "Loading game data..."
	emit_signal("login_successful", uid)

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
	if is_instance_valid(_discord_button):
		_discord_button.disabled = active
	if is_instance_valid(_apple_button):
		_apple_button.disabled = active
	if is_instance_valid(_google_button):
		_google_button.disabled = active
	if is_instance_valid(_steam_button) and not _steam_button.disabled:
		# Only toggle if steam was enabled in the first place
		_steam_button.disabled = active
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
	
	# OAuth Failsafe: if we're stuck in 'Loading' for more than 20s, reset.
	if active:
		var failsafe := get_tree().create_timer(20.0)
		failsafe.timeout.connect(func():
			if _oauth_in_progress and status_label.text.begins_with("Authenticating"):
				print("[LoginScreen] OAuth failsafe triggered after 20s stall.")
				_set_oauth_active(false)
				status_label.text = "Authentication timed out. Please try again."
		)

# ────────────────────────────────────────────────────────────────────
# Signal wiring
# ────────────────────────────────────────────────────────────────────

func _connect_hub_store_signals() -> void:
	var hub := get_node_or_null("/root/SignalHub")
	if is_instance_valid(hub):
		if hub.has_signal("auth_state_changed") and not hub.auth_state_changed.is_connected(_on_auth_state_changed):
			hub.auth_state_changed.connect(_on_auth_state_changed)
		if hub.has_signal("map_changed") and not hub.map_changed.is_connected(_on_map_changed):
			hub.map_changed.connect(_on_map_changed)
		if hub.has_signal("error_occurred") and not hub.error_occurred.is_connected(_on_hub_error_occurred):
			hub.error_occurred.connect(_on_hub_error_occurred)
	var store := get_node_or_null("/root/GameStore")
	if is_instance_valid(store):
		if store.has_signal("map_changed") and not store.map_changed.is_connected(_on_map_changed):
			store.map_changed.connect(_on_map_changed)
		if store.has_signal("user_changed") and not store.user_changed.is_connected(_on_store_user_changed):
			store.user_changed.connect(_on_store_user_changed)

func _connect_api_signals() -> void:
	var api = _api()
	if is_instance_valid(api):
		if api.has_signal("auth_url_received") and not api.auth_url_received.is_connected(_on_auth_url_received):
			api.auth_url_received.connect(_on_auth_url_received)
		if api.has_signal("fetch_error") and not api.fetch_error.is_connected(_on_api_error):
			api.fetch_error.connect(_on_api_error)
		if api.has_signal("auth_expired") and not api.auth_expired.is_connected(_on_auth_expired):
			api.auth_expired.connect(_on_auth_expired)

# ────────────────────────────────────────────────────────────────────
# Version label
# ────────────────────────────────────────────────────────────────────

func _add_version_label() -> void:
	var version = ProjectSettings.get_setting("application/config/version", "0.0.0")
	var label = Label.new()
	label.text = "v" + str(version)
	label.name = "VersionLabel"

	label.modulate = Color(1, 1, 1, 0.4)
	var settings = LabelSettings.new()
	settings.font_size = 14
	label.label_settings = settings
	TextScale.register(label)

	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.offset_left -= 12
	label.offset_top += 12
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_END

	add_child(label)

# ────────────────────────────────────────────────────────────────────
# Map background
# ────────────────────────────────────────────────────────────────────

func _setup_map_background() -> void:
	if _bg_viewport != null:
		return

	_bg_texture_rect = TextureRect.new()
	_bg_texture_rect.name = "MapBackground"
	_bg_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bg_texture_rect.modulate = Color(1, 1, 1, 0.26)
	_bg_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_bg_viewport = SubViewport.new()
	_bg_viewport.name = "MapBackgroundViewport"
	_bg_viewport.transparent_bg = true
	_bg_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bg_viewport.gui_disable_input = true
	_bg_viewport.msaa_2d = Viewport.MSAA_2X
	_bg_viewport.size = get_viewport_rect().size

	_bg_root = Node2D.new()
	_bg_root.name = "Root"
	_bg_viewport.add_child(_bg_root)

	_bg_tilemap = TileMapLayer.new()
	_bg_tilemap.name = "BackgroundTileMap"
	_bg_root.add_child(_bg_tilemap)

	_bg_camera = Camera2D.new()
	_bg_camera.name = "Camera"
	_bg_camera.enabled = false
	_bg_camera.zoom = Vector2(1.05, 1.05)
	_bg_root.add_child(_bg_camera)

	var tile_set: TileSet = load("res://Assets/tiles/tile_set.tres")
	if tile_set == null:
		return
	_bg_tilemap.tile_set = tile_set

	_build_tile_lookup(tile_set)
	_populate_placeholder_tiles(tile_set)

	add_child(_bg_texture_rect)
	move_child(_bg_texture_rect, 0)
	_bg_texture_rect.add_child(_bg_viewport)
	call_deferred("_make_bg_camera_current")

	_bg_texture_rect.texture = _bg_viewport.get_texture()

	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)

func _make_bg_camera_current() -> void:
	if _bg_camera == null:
		return
	if not _bg_camera.is_inside_tree():
		call_deferred("_make_bg_camera_current")
		return
	_bg_camera.enabled = true
	_bg_camera.make_current()

func _on_viewport_size_changed() -> void:
	if _bg_viewport == null:
		return
	_bg_viewport.size = get_viewport_rect().size
	_apply_portrait_layout()

func _build_tile_lookup(tile_set: TileSet) -> void:
	_bg_tile_name_to_entry.clear()
	for i in range(tile_set.get_source_count()):
		var source_id := tile_set.get_source_id(i)
		var source := tile_set.get_source(source_id)
		if source == null:
			continue
		if not source.has_method("get_texture"):
			continue
		var tex: Texture2D = source.get_texture()
		if tex == null or tex.resource_path == "":
			continue
		var texture_name := tex.resource_path.get_file().get_basename()
		if source.has_method("get_tiles_count") and source.get_tiles_count() > 0:
			var coords := source.get_tile_id(0)
			_bg_tile_name_to_entry[texture_name] = {"source_id": source_id, "coords": coords}

func _pick_tile_name(v: float) -> String:
	if v < -0.55:
		return "mountains"
	if v < -0.25:
		return "forest"
	if v < 0.05:
		return "plains"
	if v < 0.35:
		return "desert"
	if v < 0.60:
		return "road"
	return "highway"

func _populate_placeholder_tiles(tile_set: TileSet) -> void:
	if _bg_tilemap == null:
		return
	_bg_has_real_map = false
	_bg_tilemap.clear()
	var tile_size: Vector2i = tile_set.tile_size
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.frequency = 0.025
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	for y in range(_bg_map_size.y):
		for x in range(_bg_map_size.x):
			var n := noise.get_noise_2d(float(x), float(y))
			var tile_name := _pick_tile_name(n)
			var entry: Dictionary = _bg_tile_name_to_entry.get(tile_name, {})
			if entry.is_empty():
				continue
			_bg_tilemap.set_cell(Vector2i(x, y), int(entry["source_id"]), entry["coords"])

	var map_px := Vector2(_bg_map_size.x * tile_size.x, _bg_map_size.y * tile_size.y)
	_bg_camera.position = map_px * 0.5

func _try_use_real_map_background() -> void:
	var store := get_node_or_null("/root/GameStore")
	if is_instance_valid(store) and store.has_method("get_tiles"):
		var tiles: Array = store.get_tiles()
		if not tiles.is_empty():
			_apply_real_map_tiles(tiles)

	var api = _api()
	var map_service := get_node_or_null("/root/MapService")
	if is_instance_valid(api) and api.has_method("is_auth_token_valid") and api.is_auth_token_valid():
		if is_instance_valid(map_service) and map_service.has_method("request_map"):
			map_service.request_map()

func _on_map_changed(tiles: Array, _settlements: Array) -> void:
	if tiles == null or tiles.is_empty():
		return
	_apply_real_map_tiles(tiles)

func _apply_real_map_tiles(tiles: Array) -> void:
	if _bg_tilemap == null or _bg_camera == null:
		return
	if _bg_tilemap.tile_set == null:
		return

	_build_tile_lookup(_bg_tilemap.tile_set)
	_bg_tilemap.clear()
	_bg_has_real_map = true

	var rows := tiles.size()
	var cols := 0
	if rows > 0 and tiles[0] is Array:
		cols = (tiles[0] as Array).size()
	_bg_map_size = Vector2i(max(cols, 1), max(rows, 1))

	for y in range(rows):
		var row_any: Variant = tiles[y]
		if not (row_any is Array):
			continue
		var row := row_any as Array
		for x in range(row.size()):
			var tile_any: Variant = row[x]
			var tile_name := "impassable"
			if tile_any is Dictionary:
				var d := tile_any as Dictionary
				var settlements_any: Variant = d.get("settlements", [])
				if settlements_any is Array and (settlements_any as Array).size() > 0:
					var s0_any: Variant = (settlements_any as Array)[0]
					if s0_any is Dictionary:
						var stype := str((s0_any as Dictionary).get("sett_type", "town"))
						tile_name = _SETTLEMENT_TYPE_TO_NAME.get(stype, "town")
					else:
						tile_name = "town"
				else:
					var terrain_int := int(d.get("terrain_difficulty", 0))
					tile_name = _TERRAIN_INT_TO_NAME.get(terrain_int, "impassable")
			else:
				tile_name = _TERRAIN_INT_TO_NAME.get(int(tile_any), "impassable")

			var entry: Dictionary = _bg_tile_name_to_entry.get(tile_name, {})
			if entry.is_empty():
				continue
			_bg_tilemap.set_cell(Vector2i(x, y), int(entry["source_id"]), entry["coords"])

	var tile_size: Vector2i = _bg_tilemap.tile_set.tile_size
	var map_px := Vector2(_bg_map_size.x * tile_size.x, _bg_map_size.y * tile_size.y)
	_bg_camera.position = map_px * 0.5

func _update_map_background(delta: float) -> void:
	if _bg_camera == null or _bg_tilemap == null or _bg_tilemap.tile_set == null:
		return
	_bg_time += delta
	var tile_size: Vector2i = _bg_tilemap.tile_set.tile_size
	if tile_size.x <= 0 or tile_size.y <= 0:
		return
	var map_px := Vector2(_bg_map_size.x * tile_size.x, _bg_map_size.y * tile_size.y)
	var view_px := Vector2(_bg_viewport.size) if _bg_viewport != null else Vector2(get_viewport_rect().size)
	var half_view_world := (view_px * 0.5) / _bg_camera.zoom
	var min_pos := half_view_world
	var max_pos := map_px - half_view_world
	if max_pos.x <= min_pos.x or max_pos.y <= min_pos.y:
		_bg_camera.position = map_px * 0.5
		return

	var wobble := Vector2(sin(_bg_time * 0.35) * 6.0, cos(_bg_time * 0.28) * 5.0)
	_bg_camera.position += (_bg_drift_speed * delta) + (wobble * delta)

	var span := max_pos - min_pos
	_bg_camera.position.x = min_pos.x + fposmod(_bg_camera.position.x - min_pos.x, span.x)
	_bg_camera.position.y = min_pos.y + fposmod(_bg_camera.position.y - min_pos.y, span.y)

# ────────────────────────────────────────────────────────────────────
# Utilities
# ────────────────────────────────────────────────────────────────────

func show_error(message: String) -> void:
	status_label.text = message

func _api():
	return get_node_or_null("/root/APICalls")
