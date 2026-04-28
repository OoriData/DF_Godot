extends Control
class_name MenuBase

@warning_ignore("unused_signal")
signal back_requested

var convoy_id: String = ""
var extra: Variant = null
var _last_convoy_data: Dictionary = {}
## If true, automatically add a subtle Oori background texture on ready.
var auto_apply_oori_background: bool = true

func _ensure_store_subscription() -> void:
	var store = get_node_or_null("/root/GameStore")
	if store and store.has_signal("convoys_changed"):
		var cb := Callable(self, "_on_convoys_changed")
		if not store.convoys_changed.is_connected(cb):
			store.convoys_changed.connect(cb)

func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
	"""
	Standardized initializer:
	- If provided a Dictionary (convoy snapshot), sets context and calls _update_ui(convoy) directly.
	- If provided a String (convoy_id), sets context and refreshes from store.
	"""
	_ensure_store_subscription()
	extra = extra_arg
	if data_or_id is Dictionary:
		var convoy: Dictionary = data_or_id
		convoy_id = str(convoy.get("convoy_id", convoy.get("id", "")))
		if not convoy.is_empty():
			_last_convoy_data = convoy.duplicate(true)
			_update_ui(convoy)
		else:
			_last_convoy_data = {}
			reset_view()
	else:
		convoy_id = str(data_or_id)
		_last_convoy_data = {}
		_refresh_from_store()

func set_convoy_context(id: String, extra_arg: Variant = null) -> void:
	_ensure_store_subscription()
	convoy_id = id
	extra = extra_arg
	_last_convoy_data = {}
	_refresh_from_store()

func set_extra(extra_arg: Variant) -> void:
	extra = extra_arg

func refresh_now() -> void:
	_ensure_store_subscription()
	_last_convoy_data = {}
	_refresh_from_store()

func _ready() -> void:
	_ensure_store_subscription()
	if auto_apply_oori_background:
		_apply_oori_background()

func _apply_oori_background() -> void:
	# Subtle tileable background
	if get_node_or_null("OoriBackground"): return
	
	print("[MenuBase] Applying Oori Background to ", name)
	
	# Detect and hide existing scene-level background rects that would block the texture
	var legacy_bg = get_node_or_null("ColorRect")
	if is_instance_valid(legacy_bg):
		legacy_bg.visible = false
		
	var bg = TextureRect.new()
	bg.name = "OoriBackground"
	bg.texture = load("res://Assets/Themes/Oori Backround.png")
	if bg.texture == null:
		printerr("[MenuBase] ERROR: Failed to load background texture at res://Assets/Themes/Oori Backround.png")
		return
		
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	add_child(bg)
	
	# Ensure the texture is behind the main VBox but on top of legacy layers
	var ContentNode = get_node_or_null("MainVBox")
	if is_instance_valid(ContentNode):
		move_child(bg, ContentNode.get_index())
	else:
		move_child(bg, 0)
		
	# NEW: Maximize transparency across the whole hierarchy to let the texture shine through
	_maximize_transparency_recursive(self)

func _maximize_transparency_recursive(node: Node) -> void:
	if not is_instance_valid(node): return
	
	# Panel nodes: Enforce an Empty StyleBox so that no grey backgrounds are ever drawn
	if node is PanelContainer or node is Panel or node is TabContainer or node is ScrollContainer:
		var style_keys := ["panel"]
		if node is TabContainer:
			style_keys.append("tabbar_panel")
			
		for key in style_keys:
			var empty = StyleBoxEmpty.new()
			node.add_theme_stylebox_override(key, empty)
				
	# If it's a ProgressBar, make its background transparent too
	if node is ProgressBar:
		var empty = StyleBoxEmpty.new()
		node.add_theme_stylebox_override("background", empty)

	# Recursively check children
	for child in node.get_children():
		_maximize_transparency_recursive(child)

func _notification(what: int) -> void:
	# Important for embedded menus inside hidden tabs:
	# they may miss refreshes while hidden, so refresh when shown.
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree() and convoy_id != "":
			_refresh_from_store()

func _on_convoys_changed(_convoys: Array) -> void:
	# Only refresh if this menu is visible and has a convoy context.
	if not is_visible_in_tree() or convoy_id == "":
		return
	print("[MenuBase] _on_convoys_changed triggered for: ", name, " (convoy_id: ", convoy_id, ")")
	_refresh_from_store()

func _refresh_from_store() -> void:
	print("[MenuBase] _refresh_from_store executing for: ", name)
	var store = get_node_or_null("/root/GameStore")
	if store and convoy_id != "":
		var convoy: Dictionary = {}
		if store.has_method("get_convoy_by_id"):
			convoy = store.get_convoy_by_id(convoy_id)
		elif store.has_method("get_convoys"):
			var all = store.get_convoys()
			if all is Array:
				for c in all:
					if c is Dictionary and String(c.get("convoy_id", c.get("id", ""))) == convoy_id:
						convoy = c
						break
		if convoy and not convoy.is_empty():
			var vdl = convoy.get("vehicle_details_list", [])
			print("[MenuBase] _refresh_from_store: convoy found. ID=", convoy_id, " Keys=", convoy.keys().size(), " VDL size=", vdl.size() if vdl else "null")
			
			if _has_relevant_changes(_last_convoy_data, convoy):
				_last_convoy_data = convoy.duplicate(true)
				print("[MenuBase] Found relevant changes, calling _update_ui for: ", name)
				_update_ui(convoy)
			else:
				print("[MenuBase] No relevant changes, skipping update for: ", name)
		else:
			_last_convoy_data = {}
			print("[MenuBase] Convoy data empty/missing, calling reset_view for: ", name)
			reset_view()

func _exit_tree() -> void:
	# Disconnect to avoid duplicate connections on reopen
	var store = get_node_or_null("/root/GameStore")
	if store and store.has_signal("convoys_changed"):
		var cb := Callable(self, "_on_convoys_changed")
		if store.convoys_changed.is_connected(cb):
			store.convoys_changed.disconnect(cb)

func _update_ui(_convoy: Dictionary) -> void:
	pass

func reset_view() -> void:
	pass

func _has_relevant_changes(old_data: Dictionary, new_data: Dictionary) -> bool:
	return old_data.hash() != new_data.hash()

func style_back_button(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var dsm = get_node_or_null("/root/DeviceStateManager")
	var is_portrait = false
	var is_mobile = false
	var font_size = 18
	if dsm and dsm.has_method("get_is_portrait"):
		is_portrait = dsm.get_is_portrait()
		is_mobile = dsm.is_mobile
		font_size = dsm.get_scaled_base_font_size(18)
	else:
		var win_size = get_viewport_rect().size if is_inside_tree() else Vector2(0, 0)
		is_portrait = win_size.y > win_size.x
		is_mobile = is_portrait # fallback logic
		
	btn.custom_minimum_size.y = 100 if is_portrait else (72 if is_mobile else 50)
	btn.add_theme_font_size_override("font_size", font_size)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.22, 0.32, 0.95)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.40, 0.50, 0.70, 0.9)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", sb)
	
	var sb_hover = sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.25, 0.30, 0.45, 1.0)
	btn.add_theme_stylebox_override("hover", sb_hover)
	
	var sb_pressed = sb.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = Color(0.12, 0.15, 0.22, 1.0)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
