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

## If true, MenuManager will cache this menu node instead of destroying it on navigation.
## The node will be detached from the tree and re-attached on return, preserving all UI state.
var persistence_enabled: bool = false

# ── Shared loadout-card visual language ──────────────────────────────────────
# Self-contained helpers (no dependency on per-menu scaling hooks) so any menu can
# render parts as consistent "loadout cards". A single accent color per vehicle
# system keeps cards grouped by type across the Parts and Service tabs.
func _card_is_mobile() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.get_name() in ["Android", "iOS"]:
		return true
	if is_inside_tree():
		var s := get_viewport_rect().size
		if s.y > s.x:
			return true
	return false

func _slot_accent(slot_name: String) -> Color:
	match slot_name.to_lower():
		"engine", "ice", "motor":
			return Color(0.62, 0.77, 0.35) # green
		"battery", "cell":
			return Color(0.36, 0.79, 0.65) # teal
		"tune", "ecu", "chip":
			return Color(0.94, 0.78, 0.29) # amber
		"transmission", "trans", "gearbox", "drivetrain":
			return Color(0.49, 0.62, 0.85) # blue
		"tires", "tire", "wheels", "wheel":
			return Color(0.74, 0.55, 0.85) # purple
		"chassis", "frame", "suspension":
			return Color(0.83, 0.56, 0.42) # coral
		_:
			return Color(0.55, 0.60, 0.70) # neutral


# Rounded card surface used by every slot/cart/candidate card.
func _make_card_style(filled: bool, accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UITheme.METAL_BASE, 0.92) if filled else Color(UITheme.METAL_DARK, 0.85)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12 if _card_is_mobile() else 10)
	if filled:
		sb.border_width_left = 3
		sb.border_color = accent
	else:
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.10)
	return sb

# Small rounded badge carrying the slot's initial, tinted by its accent.
func _make_slot_badge(slot_name: String, accent: Color, is_empty: bool) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(accent.r, accent.g, accent.b, 0.16 if is_empty else 0.28)
	bsb.set_corner_radius_all(6)
	badge.add_theme_stylebox_override("panel", bsb)
	var sz := 28 if _card_is_mobile() else 24
	badge.custom_minimum_size = Vector2(sz, sz)
	var lbl := Label.new()
	lbl.text = (slot_name.substr(0, 1)).to_upper() if slot_name != "" else "?"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", accent if not is_empty else UITheme.TEXT_MUTED)
	badge.add_child(lbl)
	return badge

# Build the card container for the current orientation, attach it to parent,
# and return the Container that cards should be added to directly.
# Portrait  → 2-col GridContainer added straight to parent.
# Landscape → HBoxContainer inside a horizontal ScrollContainer.
func _make_slot_container(parent: Control) -> Container:
	var is_port := is_inside_tree() and get_viewport_rect().size.y > get_viewport_rect().size.x
	if is_port:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(grid)
		return grid
	else:
		var hscroll := ScrollContainer.new()
		hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		hscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hscroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		parent.add_child(hscroll)
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		hbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		hbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		hscroll.add_child(hbox)
		return hbox

# Min card width for a landscape horizontal-scroll strip.
func _landscape_card_width() -> int:
	return 190 if _card_is_mobile() else 220

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
	
	_apply_standard_margins()

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
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	UITheme.apply_oori_bg(bg)
	
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
		if is_visible_in_tree():
			_ensure_store_subscription()
			_apply_standard_margins()
		if is_visible_in_tree() and convoy_id != "":
			_refresh_from_store()
	elif what == NOTIFICATION_RESIZED:
		_apply_standard_margins()

func _on_user_changed(_user: Dictionary) -> void:
	# Virtual: override in subclasses to update UI on money/user changes
	pass

## Centralized logic to ensure consistent side buffers in portrait mode.
func _apply_standard_margins() -> void:
	var main_vbox = get_node_or_null("MainVBox")
	if not is_instance_valid(main_vbox):
		return
		
	var dsm = get_node_or_null("/root/DeviceStateManager")
	var is_portrait = dsm.get_is_portrait() if is_instance_valid(dsm) else false
	
	if is_portrait:
		# Standard 14px buffer for portrait elements from the screen edge.
		# This prevents UI elements from being flush against the glass.
		main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	else:
		# Landscape/Desktop: usually edge-to-edge content is preferred for horizontal density
		main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)

func _on_convoys_changed(_convoys: Array) -> void:
	# Only refresh if this menu is visible and has a convoy context.
	if not is_visible_in_tree() or convoy_id == "":
		return
	print("[MenuBase] _on_convoys_changed triggered for: ", name, " (convoy_id: ", convoy_id, ")")
	_refresh_from_store()

func _update_navigation_bar_visibility(convoy: Dictionary) -> void:
	var journey_data = convoy.get("journey")
	var has_journey = journey_data != null and not journey_data.is_empty()
	
	# Check MenuManager first (new centralized location)
	var menu_mgr := get_tree().get_root().get_node_or_null("MenuManager")
	if is_instance_valid(menu_mgr) and menu_mgr.has_method("set_nav_button_visible"):
		menu_mgr.set_nav_button_visible("convoy_settlement_submenu", not has_journey)
	
	# Legacy BottomBarPanel/BottomMenuButtonsHBox fallback removed (Sprint 5) — that node no longer
	# exists in any scene; nav-button visibility is owned solely by MenuManager.set_nav_button_visible.

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

## Returns a unique key to identify the state of this menu instance.
## Defaults to combination of menu_type and convoy_id.
func get_menu_state_key() -> String:
	var menu_type = get_meta("menu_type", "default")
	var key = menu_type
	if convoy_id != "":
		key += "_" + convoy_id
	return key

## Virtual: override in subclasses to return a dictionary of UI state (e.g., scroll position).
func get_ui_state() -> Dictionary:
	return {}

## Virtual: override in subclasses to restore UI state from a dictionary.
func apply_ui_state(_state: Dictionary) -> void:
	pass

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
		font_size = 18
	else:
		var win_size = get_viewport_rect().size if is_inside_tree() else Vector2(0, 0)
		is_portrait = win_size.y > win_size.x
		is_mobile = is_portrait # fallback logic
		
	btn.custom_minimum_size.y = 100 if is_portrait else (72 if is_mobile else 50)
	btn.add_theme_font_size_override("font_size", font_size)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(UITheme.METAL_BASE, 0.95)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(UITheme.METAL_EDGE, 0.9)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", sb)
	
	var sb_hover = sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(UITheme.METAL_HOVER, 1.0)
	btn.add_theme_stylebox_override("hover", sb_hover)
	
	var sb_pressed = sb.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = Color(UITheme.METAL_DARK, 1.0)
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
	
	# Simply hide the back button. The static navigation bar is now managed by MenuManager.
	# We no longer reparent siblings (context buttons) as per user request to keep them in the menu view.
	if back_button_node is Control:
		back_button_node.visible = false
	else:
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
		banner_style.bg_color = UITheme.METAL_BASE
		banner_style.shadow_color = Color(0, 0, 0, 0.5)
		banner_style.shadow_size = 4
		banner_style.shadow_offset = Vector2(0, 2)
	else:
		banner_style.bg_color = Color(0, 0, 0, 0)
		banner_style.shadow_size = 0

	banner_style.border_width_bottom = 3
	banner_style.border_color = UITheme.ACCENT_VERDIGRIS

	
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
	btn_normal.bg_color = Color(UITheme.METAL_BASE, 0.9) 
	btn_normal.border_width_left = 2
	btn_normal.border_width_top = 2
	btn_normal.border_width_right = 2
	btn_normal.border_width_bottom = 2
	btn_normal.border_color = UITheme.ACCENT_BRASS
	
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
	btn_hover.bg_color = Color(UITheme.METAL_HOVER, 1.0)
	btn_hover.border_color = UITheme.ACCENT_BRASS
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.15, 0.16, 0.18, 1.0)
	btn_pressed.border_color = UITheme.ACCENT_BRASS
	btn_pressed.shadow_size = 1
	btn_pressed.shadow_offset = Vector2(0, 1)
	
	_top_banner_convoy_button.add_theme_stylebox_override("normal", btn_normal)
	_top_banner_convoy_button.add_theme_stylebox_override("hover", btn_hover)
	_top_banner_convoy_button.add_theme_stylebox_override("pressed", btn_pressed)
	_top_banner_convoy_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	_top_banner_convoy_button.add_theme_color_override("font_color", UITheme.ACCENT_BRASS)
	_top_banner_convoy_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	_top_banner_convoy_button.add_theme_color_override("font_pressed_color", Color(0.8, 0.8, 0.8))

	
	# Fixed logical font sizes; the canvas scale handles per-device sizing.
	var title_fs = 28
	var suffix_fs = 22
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
			_top_banner_convoy_button.text = "< " + str(cname)
		else:
			_top_banner_convoy_button.text = str(cname)


func set_menu_title_suffix(suffix: String) -> void:
	_top_banner_menu_name = suffix
	if is_instance_valid(_top_banner_suffix_label):
		_top_banner_suffix_label.text = " - " + suffix
