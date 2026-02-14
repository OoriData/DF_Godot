extends Control

signal login_successful(user_id: String)

# Removed obsolete InstructionsLabel (not present in scene)
@onready var center_container: CenterContainer = $CenterContainer
@onready var vbox_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var discord_button: Button = $CenterContainer/VBoxContainer/GoogleLoginButton
@onready var background_overlay: ColorRect = $Background

const DISCORD_BLURPLE := Color("5865F2")

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

func _ready() -> void:
	_setup_map_background()
	if is_instance_valid(discord_button):
		discord_button.pressed.connect(_on_discord_login_pressed)
	_connect_hub_store_signals()
	_connect_api_signals()
	_style_discord_button()
	_ensure_coming_soon_section()
	_try_use_real_map_background()
	# Ensure overlay sits above the generated map background.
	if is_instance_valid(background_overlay):
		background_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Focus now goes to OAuth button if needed
	if is_instance_valid(discord_button):
		discord_button.grab_focus()
	# Attempt automatic session reuse if token already valid
	var api = _api()
	if api and api.is_auth_token_valid():
		status_label.text = "Resuming session..."
		# APICalls autoload will resolve the session/user automatically.

func _process(_delta: float) -> void:
	_update_map_background(_delta)
	# Lightweight spinner animation when OAuth in progress
	if _oauth_in_progress:
		_spin_status()

func _setup_map_background() -> void:
	# Creates a lightweight "map-like" background from the game's TileSet.
	# This avoids depending on live API/GameStore map data during login.
	if _bg_viewport != null:
		return

	_bg_texture_rect = TextureRect.new()
	_bg_texture_rect.name = "MapBackground"
	_bg_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
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

	# TileSet shared with the actual map.
	var tile_set: TileSet = load("res://Assets/tiles/tile_set.tres")
	if tile_set == null:
		return
	_bg_tilemap.tile_set = tile_set

	_build_tile_lookup(tile_set)
	_populate_placeholder_tiles(tile_set)

	# Insert behind everything else.
	add_child(_bg_texture_rect)
	move_child(_bg_texture_rect, 0)
	_bg_texture_rect.add_child(_bg_viewport)
	# Only make current after the camera is inside the scene tree.
	call_deferred("_make_bg_camera_current")

	# Render viewport into the TextureRect.
	_bg_texture_rect.texture = _bg_viewport.get_texture()

	# Keep viewport sized to the screen.
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
		# Pick the first tile in that atlas source.
		if source.has_method("get_tiles_count") and source.get_tiles_count() > 0:
			var coords := source.get_tile_id(0)
			_bg_tile_name_to_entry[texture_name] = {"source_id": source_id, "coords": coords}

func _pick_tile_name(v: float) -> String:
	# Rough terrain mix that looks like the game map.
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

	# Center camera roughly.
	var map_px := Vector2(_bg_map_size.x * tile_size.x, _bg_map_size.y * tile_size.y)
	_bg_camera.position = map_px * 0.5

func _try_use_real_map_background() -> void:
	# Prefer rendering the actual game map if it is already present in GameStore.
	# If we have a valid session token, request the map as well.
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

	# Subtle drifting with a little sinusoidal wobble.
	var wobble := Vector2(sin(_bg_time * 0.35) * 6.0, cos(_bg_time * 0.28) * 5.0)
	_bg_camera.position += (_bg_drift_speed * delta) + (wobble * delta)

	# Wrap within the safe bounds so we never reveal empty space.
	var span := max_pos - min_pos
	_bg_camera.position.x = min_pos.x + fposmod(_bg_camera.position.x - min_pos.x, span.x)
	_bg_camera.position.y = min_pos.y + fposmod(_bg_camera.position.y - min_pos.y, span.y)

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

func _on_hub_error_occurred(domain: String, _code: String, message: String, inline: bool) -> void:
	if domain == "auth" or not inline:
		show_error(message)

func _on_store_user_changed(user: Dictionary) -> void:
	var uid := String(user.get("user_id", user.get("id", "")))
	if uid == "":
		return
	status_label.text = "Welcome."
	_set_oauth_active(false)
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
	if is_instance_valid(discord_button):
		discord_button.disabled = active
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

func _style_discord_button() -> void:
	if not is_instance_valid(discord_button):
		return
	if discord_button.text.strip_edges() == "":
		discord_button.text = "Continue with Discord"
	discord_button.add_theme_color_override("font_color", Color.WHITE)
	discord_button.add_theme_color_override("font_hover_color", Color.WHITE)
	discord_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	discord_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))

	var normal := StyleBoxFlat.new()
	normal.bg_color = DISCORD_BLURPLE
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10

	var hover := normal.duplicate()
	hover.bg_color = Color("6D78F6")

	var pressed := normal.duplicate()
	pressed.bg_color = Color("4752C4")

	var disabled := normal.duplicate()
	disabled.bg_color = Color("3A3D47")

	var focus := normal.duplicate()
	focus.bg_color = normal.bg_color
	focus.border_width_left = 2
	focus.border_width_right = 2
	focus.border_width_top = 2
	focus.border_width_bottom = 2
	focus.border_color = Color(1, 1, 1, 0.35)

	discord_button.add_theme_stylebox_override("normal", normal)
	discord_button.add_theme_stylebox_override("hover", hover)
	discord_button.add_theme_stylebox_override("pressed", pressed)
	discord_button.add_theme_stylebox_override("disabled", disabled)
	discord_button.add_theme_stylebox_override("focus", focus)
	discord_button.custom_minimum_size = Vector2(340, 54)
	discord_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func _ensure_coming_soon_section() -> void:
	if not is_instance_valid(vbox_container):
		return
	if vbox_container.has_node("ComingSoonSection"):
		return

	var section := VBoxContainer.new()
	section.name = "ComingSoonSection"
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "More login options (coming soon)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(1, 1, 1, 0.75)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)

	row.add_child(_make_coming_soon_button("Steam"))
	row.add_child(_make_coming_soon_button("iOS"))
	row.add_child(_make_coming_soon_button("Android"))

	section.add_child(title)
	section.add_child(row)
	vbox_container.add_child(section)

	# Place the section just below the Discord button when possible.
	if is_instance_valid(discord_button) and discord_button.get_parent() == vbox_container:
		var idx := vbox_container.get_children().find(discord_button)
		if idx != -1:
			vbox_container.move_child(section, min(idx + 1, vbox_container.get_child_count() - 1))

func _make_coming_soon_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 44)

	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.21, 0.23, 0.75)
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("disabled", normal)
	return b

func show_error(message: String) -> void:
	status_label.text = message

func _api():
	return get_node_or_null("/root/APICalls")
