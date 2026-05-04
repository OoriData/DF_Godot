extends Control
class_name MenuBase

@warning_ignore("unused_signal")
signal back_requested

signal open_vehicle_menu_requested(convoy_data)
signal open_journey_menu_requested(convoy_data)
signal open_settlement_menu_requested(convoy_data)
signal open_cargo_menu_requested(convoy_data)
signal return_to_convoy_overview_requested(convoy_data)

var convoy_id: String = ""
var extra: Variant = null
var _last_convoy_data: Dictionary = {}
var _top_banner_convoy_button: Button = null
var _top_banner_suffix_label: Label = null
var _top_banner_menu_name: String = ""

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
			_update_top_banner_text(convoy)
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
			if node.has_theme_stylebox(key):
				var current = node.get_theme_stylebox(key)
				if current:
					empty.content_margin_left = current.content_margin_left
					empty.content_margin_right = current.content_margin_right
					empty.content_margin_top = current.content_margin_top
					empty.content_margin_bottom = current.content_margin_bottom
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

func _update_navigation_bar_visibility(convoy: Dictionary) -> void:
	var journey_data = convoy.get("journey")
	var has_journey = journey_data != null and not journey_data.is_empty()
	
	# Look for the navigation bar in common paths
	var nav_bar = get_node_or_null("MainVBox/BottomBarPanel/BottomMenuButtonsHBox")
	if not is_instance_valid(nav_bar):
		nav_bar = find_child("BottomMenuButtonsHBox", true, false)
		
	if is_instance_valid(nav_bar):
		var settlement_btn = nav_bar.get_node_or_null("SettlementMenuButton")
		if is_instance_valid(settlement_btn):
			settlement_btn.visible = not has_journey

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
			
			_update_top_banner_text(convoy)
			
			if _has_relevant_changes(_last_convoy_data, convoy):

				_last_convoy_data = convoy.duplicate(true)
				print("[MenuBase] Found relevant changes, calling _update_ui for: ", name)
				_update_ui(convoy)
				_update_navigation_bar_visibility(convoy)
			else:
				print("[MenuBase] No relevant changes, skipping update for: ", name)
				# Still update nav bar visibility in case it was just created
				_update_navigation_bar_visibility(convoy)
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

## Style a button to match the convoy navigation bar buttons (light grey, black text).
## Use this for auxiliary buttons that sit alongside the nav bar (e.g. Manifest, Apply).
func style_convoy_nav_button(button_node: Button) -> void:
	if not is_instance_valid(button_node):
		return
	
	var dsm_node = get_node_or_null("/root/DeviceStateManager")
	var on_mobile := false
	if is_instance_valid(dsm_node) and dsm_node.get("is_mobile") != null:
		on_mobile = dsm_node.is_mobile
	elif OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		on_mobile = true
	
	var corner_r := 6 if on_mobile else 4
	var v_pad := 8.0 if on_mobile else 4.0
	var min_h := 70.0 if on_mobile else 34.0
	if button_node.custom_minimum_size.y < min_h:
		button_node.custom_minimum_size.y = min_h
	if on_mobile:
		button_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var COLOR_BG := Color("b0b0b0")
	var COLOR_FONT := Color("000000")
	
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = COLOR_BG
	sb_n.corner_radius_top_left = corner_r
	sb_n.corner_radius_top_right = corner_r
	sb_n.corner_radius_bottom_left = corner_r
	sb_n.corner_radius_bottom_right = corner_r
	sb_n.border_width_left = 1
	sb_n.border_width_right = 1
	sb_n.border_width_top = 1
	sb_n.border_width_bottom = 1
	sb_n.border_color = COLOR_FONT.darkened(0.2)
	sb_n.shadow_size = 4
	sb_n.shadow_color = Color(0, 0, 0, 0.4)
	sb_n.content_margin_top = v_pad
	sb_n.content_margin_bottom = v_pad
	
	var sb_h := sb_n.duplicate() as StyleBoxFlat
	sb_h.bg_color = COLOR_BG.lightened(0.1)
	
	var sb_p := sb_n.duplicate() as StyleBoxFlat
	sb_p.bg_color = COLOR_BG.darkened(0.15)
	sb_p.shadow_size = 2
	sb_p.shadow_color = Color(0, 0, 0, 0.25)
	
	button_node.add_theme_stylebox_override("normal", sb_n)
	button_node.add_theme_stylebox_override("hover", sb_h)
	button_node.add_theme_stylebox_override("pressed", sb_p)
	button_node.add_theme_color_override("font_color", COLOR_FONT)

func setup_convoy_navigation_bar(back_button_node: Node) -> void:
	if not is_instance_valid(back_button_node):
		return
	
	var parent = back_button_node.get_parent()
	var index = back_button_node.get_index()
	
	# --- Device/layout detection ---
	var dsm = get_node_or_null("/root/DeviceStateManager")
	var is_portrait := false
	var use_mobile := false
	var font_size := 16
	if is_instance_valid(dsm):
		if dsm.has_method("get_is_portrait"):
			is_portrait = dsm.get_is_portrait()
		if dsm.get("is_mobile") != null:
			use_mobile = dsm.is_mobile
		elif OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
			use_mobile = true
		if dsm.has_method("get_scaled_base_font_size"):
			font_size = dsm.get_scaled_base_font_size(16)
	else:
		if is_inside_tree():
			var win_size = get_viewport_rect().size
			is_portrait = win_size.y > win_size.x
			use_mobile = is_portrait or OS.has_feature("mobile")
	
	# --- Create PanelContainer (bar background) matching convoy_menu.gd ---
	var bottom_panel = PanelContainer.new()
	bottom_panel.name = "BottomBarPanel"
	
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.18, 0.18, 0.18, 0.85)
	bar_style.corner_radius_top_left = 6
	bar_style.corner_radius_top_right = 6
	bar_style.border_width_top = 1
	bar_style.border_color = Color(0.28, 0.28, 0.28)
	# Content margins match convoy_menu._update_mobile_dependent_layout
	var bar_margin := 10.0 if is_portrait else (6.0 if use_mobile else 0.0)
	bar_style.content_margin_top = bar_margin
	bar_style.content_margin_bottom = bar_margin
	bar_style.content_margin_left = bar_margin
	bar_style.content_margin_right = bar_margin
	bottom_panel.add_theme_stylebox_override("panel", bar_style)
	
	# NOTE: Don't add bottom_panel to tree yet — insertion point depends on
	# whether back_button has siblings (handled at the end of this method).
	
	# --- HFlowContainer for the buttons (matches scene: HFlowContainer, centered, 10px gaps) ---
	var hbox = HFlowContainer.new()
	hbox.name = "BottomMenuButtonsHBox"
	hbox.add_theme_constant_override("h_separation", 10)
	hbox.add_theme_constant_override("v_separation", 10)
	hbox.alignment = FlowContainer.ALIGNMENT_CENTER
	bottom_panel.add_child(hbox)
	
	# --- Button configs ---
	var btn_configs = [
		{"name": "VehicleMenuButton", "text": "Vehicles", "signal": "open_vehicle_menu_requested"},
		{"name": "JourneyMenuButton", "text": "Journey", "signal": "open_journey_menu_requested"},
		{"name": "SettlementMenuButton", "text": "Settlement", "signal": "open_settlement_menu_requested"},
		{"name": "CargoMenuButton", "text": "Cargo", "signal": "open_cargo_menu_requested"}
	]
	
	# Button height matching convoy_menu._update_mobile_dependent_layout
	var btn_min_h := 140.0 if is_portrait else (70.0 if use_mobile else 34.0)
	# Button corner radius and padding matching convoy_menu._style_menu_button
	var corner_r := 6 if use_mobile else 4
	var v_pad := 8.0 if use_mobile else 4.0
	
	# Color constants matching convoy_menu.gd
	var COLOR_MENU_BUTTON_GREY_BG := Color("b0b0b0")
	var COLOR_BOX_FONT := Color("000000")
	
	for config in btn_configs:
		var btn = Button.new()
		btn.name = config["name"]
		btn.text = config["text"]
		btn.custom_minimum_size = Vector2(110, btn_min_h)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", font_size)
		
		# --- Style matching convoy_menu._style_menu_button exactly ---
		var sb_normal := StyleBoxFlat.new()
		sb_normal.bg_color = COLOR_MENU_BUTTON_GREY_BG
		sb_normal.corner_radius_top_left = corner_r
		sb_normal.corner_radius_top_right = corner_r
		sb_normal.corner_radius_bottom_left = corner_r
		sb_normal.corner_radius_bottom_right = corner_r
		sb_normal.border_width_left = 1
		sb_normal.border_width_right = 1
		sb_normal.border_width_top = 1
		sb_normal.border_width_bottom = 1
		sb_normal.border_color = COLOR_BOX_FONT.darkened(0.2)
		sb_normal.shadow_size = 4
		sb_normal.shadow_color = Color(0, 0, 0, 0.4)
		sb_normal.content_margin_top = v_pad
		sb_normal.content_margin_bottom = v_pad
		
		var sb_hover := sb_normal.duplicate() as StyleBoxFlat
		sb_hover.bg_color = COLOR_MENU_BUTTON_GREY_BG.lightened(0.1)
		
		var sb_pressed := sb_normal.duplicate() as StyleBoxFlat
		sb_pressed.bg_color = COLOR_MENU_BUTTON_GREY_BG.darkened(0.15)
		sb_pressed.shadow_size = 2
		sb_pressed.shadow_color = Color(0, 0, 0, 0.25)
		
		btn.add_theme_stylebox_override("normal", sb_normal)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_stylebox_override("pressed", sb_pressed)
		btn.add_theme_color_override("font_color", COLOR_BOX_FONT)
		
		# Connect signal to emit the respective menu navigation signal with _last_convoy_data
		btn.pressed.connect(func():
			emit_signal(config["signal"], _last_convoy_data)
		)
		
		hbox.add_child(btn)
	
	# If the back button has siblings (e.g. vehicle menu's BottomRow with Manifest/Apply),
	# reparent those siblings into our flow container and replace the entire old container.
	var siblings_to_reparent: Array[Node] = []
	for child in parent.get_children():
		if child != back_button_node:
			siblings_to_reparent.append(child)
	
	if not siblings_to_reparent.is_empty() and parent != get_node_or_null("MainVBox"):
		# Parent is a wrapper container (e.g. BottomRow HBox) — replace it entirely
		var grandparent = parent.get_parent()
		var parent_index = parent.get_index()
		
		# Reparent siblings into the nav bar's flow container
		for sibling in siblings_to_reparent:
			parent.remove_child(sibling)
			hbox.add_child(sibling)
		
		# Insert the nav bar where the old container was
		grandparent.add_child(bottom_panel)
		grandparent.move_child(bottom_panel, parent_index)
		
		# Remove the old container (it still contains just the back button)
		grandparent.remove_child(parent)
		parent.remove_child(back_button_node)
		back_button_node.queue_free()
		parent.queue_free()
	else:
		# Simple case: back button is a direct child of MainVBox — insert nav bar at same position
		parent.add_child(bottom_panel)
		parent.move_child(bottom_panel, index)
		parent.remove_child(back_button_node)
		back_button_node.queue_free()

## Sets up a standardized top banner with a clickable convoy name and menu title.
func setup_convoy_top_banner(title_node: Control, menu_name_suffix: String, break_out_siblings: bool = false, use_dark_bg: bool = true) -> void:


	if not is_instance_valid(title_node):
		return
	
	_top_banner_menu_name = menu_name_suffix
	
	var parent = title_node.get_parent()
	var index = title_node.get_index()
	
	# --- Create the Banner Panel ---
	var banner_panel = PanelContainer.new()
	banner_panel.name = "TopBannerPanel"
	
	var banner_style = StyleBoxFlat.new()
	if use_dark_bg:
		# Subtle vertical gradient: dark grey to slightly darker grey
		banner_style.bg_color = Color(0.15, 0.16, 0.18, 0.95)
		# Depth with shadow
		banner_style.shadow_color = Color(0, 0, 0, 0.5)
		banner_style.shadow_size = 4
		banner_style.shadow_offset = Vector2(0, 2)
	else:
		banner_style.bg_color = Color(0, 0, 0, 0) # Transparent
		banner_style.shadow_size = 0

	banner_style.border_width_bottom = 4
	# Oori Accent Blue - Solid
	banner_style.border_color = Color(0.25, 0.55, 0.85, 1.0) 

	
	banner_style.content_margin_top = 10
	banner_style.content_margin_bottom = 10
	banner_style.content_margin_left = 16
	banner_style.content_margin_right = 16
	banner_panel.add_theme_stylebox_override("panel", banner_style)


	
	# --- Create the HBox Container ---
	var hbox = HBoxContainer.new()
	hbox.name = "BannerHBox"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_panel.add_child(hbox)
	
	# --- Create the Convoy Name Button ---
	_top_banner_convoy_button = Button.new()
	_top_banner_convoy_button.name = "ConvoyNameButton"
	_top_banner_convoy_button.text = "Convoy" # Placeholder
	
	# Premium Button Styling (Tactile and clearly a button)
	var btn_normal = StyleBoxFlat.new()
	# Rich dark background with slight transparency
	btn_normal.bg_color = Color(0.22, 0.24, 0.28, 0.9) 
	btn_normal.border_width_left = 2
	btn_normal.border_width_top = 2
	btn_normal.border_width_right = 2
	btn_normal.border_width_bottom = 2
	# Oori Accent Blue / Gold-ish border
	btn_normal.border_color = Color(0.45, 0.55, 0.75, 0.7) 
	
	btn_normal.content_margin_left = 14
	btn_normal.content_margin_right = 14
	btn_normal.content_margin_top = 6
	btn_normal.content_margin_bottom = 6
	
	btn_normal.corner_radius_top_left = 8
	btn_normal.corner_radius_bottom_left = 8
	btn_normal.corner_radius_top_right = 8
	btn_normal.corner_radius_bottom_right = 8
	
	btn_normal.shadow_color = Color(0, 0, 0, 0.35)
	btn_normal.shadow_size = 3
	btn_normal.shadow_offset = Vector2(0, 2)

	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.28, 0.32, 0.38, 1.0)
	btn_hover.border_color = Color(0.6, 0.75, 1.0, 0.9) # Brighten border on hover
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.15, 0.16, 0.18, 1.0)
	btn_pressed.border_color = Color(0.3, 0.4, 0.6, 0.8)
	btn_pressed.shadow_size = 1
	btn_pressed.shadow_offset = Vector2(0, 1)
	
	_top_banner_convoy_button.add_theme_stylebox_override("normal", btn_normal)
	_top_banner_convoy_button.add_theme_stylebox_override("hover", btn_hover)
	_top_banner_convoy_button.add_theme_stylebox_override("pressed", btn_pressed)
	_top_banner_convoy_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	_top_banner_convoy_button.add_theme_color_override("font_color", Color(0.95, 0.95, 0.6)) # Warm gold
	_top_banner_convoy_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	_top_banner_convoy_button.add_theme_color_override("font_pressed_color", Color(0.8, 0.8, 0.8))

	
	# Scale font size based on device
	var dsm = get_node_or_null("/root/DeviceStateManager")
	var title_fs = 22
	var suffix_fs = 20
	if is_instance_valid(dsm) and dsm.has_method("get_scaled_base_font_size"):
		title_fs = dsm.get_scaled_base_font_size(22)
		suffix_fs = dsm.get_scaled_base_font_size(20)
		
	_top_banner_convoy_button.add_theme_font_size_override("font_size", title_fs)
	
	_top_banner_convoy_button.pressed.connect(func():
		emit_signal("return_to_convoy_overview_requested", _last_convoy_data)
	)
	
	_top_banner_convoy_button.tooltip_text = "Return to Convoy Overview"
	
	hbox.add_child(_top_banner_convoy_button)

	
	# --- Create the Suffix Label ---
	if menu_name_suffix != "":
		_top_banner_suffix_label = Label.new()
		_top_banner_suffix_label.name = "MenuSuffixLabel"
		_top_banner_suffix_label.text = " | " + menu_name_suffix.to_upper()
		_top_banner_suffix_label.add_theme_font_size_override("font_size", suffix_fs)
		_top_banner_suffix_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		# Monospaced or clean font feel
		_top_banner_suffix_label.add_theme_constant_override("outline_size", 1)
		_top_banner_suffix_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.2))
		hbox.add_child(_top_banner_suffix_label)

	
	# --- Handle Insertion ---
	var final_parent = parent
	var final_index = index
	
	# If parent is a wrapper (TopBarHBox or TopRow), replace it and swallow siblings
	if parent is HBoxContainer and (parent.name.contains("TopBar") or parent.name.contains("TopRow")):
		final_parent = parent.get_parent()
		final_index = parent.get_index()
		
		# Move siblings into banner or into a secondary row
		var siblings = parent.get_children()
		var secondary_row: Control = null
		var flow_container: HFlowContainer = null

		
		if break_out_siblings:
			var sub_panel = PanelContainer.new()
			sub_panel.name = "SecondaryBannerPanel"
			
			flow_container = HFlowContainer.new()
			flow_container.name = "SecondaryBannerRow"
			flow_container.alignment = FlowContainer.ALIGNMENT_CENTER
			flow_container.add_theme_constant_override("h_separation", 15)
			flow_container.add_theme_constant_override("v_separation", 10)
			
			# Subtle background for the breakout row to keep it grounded
			var sub_style = StyleBoxFlat.new()
			if use_dark_bg:
				sub_style.bg_color = Color(0.1, 0.1, 0.1, 0.4)
			else:
				sub_style.bg_color = Color(0, 0, 0, 0)
			
			sub_style.content_margin_top = 6
			sub_style.content_margin_bottom = 6
			sub_style.content_margin_left = 10
			sub_style.content_margin_right = 10
			sub_style.corner_radius_bottom_left = 8
			sub_style.corner_radius_bottom_right = 8
			sub_panel.add_theme_stylebox_override("panel", sub_style)
			
			sub_panel.add_child(flow_container)
			secondary_row = sub_panel
		
		for s in siblings:
			if s != title_node:
				parent.remove_child(s)
				if break_out_siblings:
					flow_container.add_child(s)
				else:
					hbox.add_child(s)

				
				# If it's the old back button, we might want to hide it as navigation is at bottom now
				if s.name == "BackButton":
					s.visible = false
		
		final_parent.add_child(banner_panel)
		final_parent.move_child(banner_panel, final_index)
		
		if break_out_siblings and secondary_row.get_child_count() > 0:
			final_parent.add_child(secondary_row)
			final_parent.move_child(secondary_row, final_index + 1)
		
		final_parent.remove_child(parent)
		parent.queue_free()

	else:
		# Direct child of MainVBox
		parent.add_child(banner_panel)
		parent.move_child(banner_panel, index)
		parent.remove_child(title_node)
		title_node.queue_free()

	# Update text immediately if we have data
	if not _last_convoy_data.is_empty():
		_update_top_banner_text(_last_convoy_data)

func _update_top_banner_text(convoy_data: Dictionary) -> void:
	if is_instance_valid(_top_banner_convoy_button):
		var cname = convoy_data.get("convoy_name", convoy_data.get("name", "Convoy"))
		# Add a back indicator if we have a suffix (meaning we are in a sub-menu)
		if _top_banner_menu_name != "":
			_top_banner_convoy_button.text = "« " + str(cname)
		else:
			_top_banner_convoy_button.text = str(cname)


func set_menu_title_suffix(suffix: String) -> void:
	_top_banner_menu_name = suffix
	if is_instance_valid(_top_banner_suffix_label):
		_top_banner_suffix_label.text = " - " + suffix
