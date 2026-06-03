# map_overlay_settings_panel.gd
extends Control

var _is_expanded: bool = false
var _anim_tween: Tween = null

var _main_hbox: HBoxContainer
var _tab_button: Button
var _content_panel: PanelContainer
var _vbox: VBoxContainer

var active_dest_toggle: CheckButton
var curr_sett_dest_toggle: CheckButton
var all_convoy_dest_toggle: CheckButton
var settlement_labels_toggle: CheckButton
var warehouse_labels_toggle: CheckButton

@onready var _settings_service: Node = get_node_or_null("/root/MapSettingsService")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

# Dynamic Layout Helpers
func _is_mobile() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.get_name() in ["Android", "iOS"]:
		return true
	if is_inside_tree():
		var win_size = get_viewport_rect().size
		if win_size.y > win_size.x:
			return true
	return false

func _is_portrait() -> bool:
	var win_size = get_viewport_rect().size if is_inside_tree() else Vector2(0, 0)
	return win_size.y > win_size.x

func _is_landscape_mobile() -> bool:
	return _is_mobile() and not _is_portrait()

func _get_font_size(base: int) -> int:
	# Landscape mobile is vertically cramped, so use a much smaller boost there.
	var boost = 2.6 if _is_portrait() else (1.35 if _is_landscape_mobile() else 1.6)
	return int(base * boost)

func _get_panel_width() -> float:
	var win_size = get_viewport_rect().size if is_inside_tree() else Vector2(0, 0)
	if _is_portrait():
		return win_size.x * 0.75 # Use 75% of width on portrait mobile
	elif _is_mobile():
		return 520.0
	else:
		return 440.0

func _get_tab_width() -> float:
	return 80.0 if _is_portrait() else 55.0

var _was_portrait: bool = false

func _ready() -> void:
	_was_portrait = _is_portrait()
	_build_ui()

	# Menu visibility no longer hides this panel, it remains accessible at all times!
			
	# Connect to Settings Service updates via SignalHub to maintain 100% synchronization
	if is_instance_valid(_hub) and _hub.has_signal("map_overlay_settings_changed"):
		if not _hub.map_overlay_settings_changed.is_connected(_on_map_overlay_settings_changed):
			_hub.map_overlay_settings_changed.connect(_on_map_overlay_settings_changed)

	# Re-collapse/re-expand correctly whenever the window or orientation changes.
	# The panel itself is offset-anchored to zero width, so its own NOTIFICATION_RESIZED
	# may not fire — listen on the viewport instead.
	if is_inside_tree():
		var vp = get_viewport()
		if is_instance_valid(vp) and not vp.size_changed.is_connected(_on_viewport_resized):
			vp.size_changed.connect(_on_viewport_resized)

	# Start fully constructed — defer one frame so the parent's global rect is settled
	call_deferred("_update_layout", false)
	_sync_toggles_with_service()

func _on_viewport_resized() -> void:
	# Orientation flip changes compact-ness (fonts/spacing/descriptions), so rebuild the
	# rows from scratch when portrait <-> landscape changes.
	var now_portrait = _is_portrait()
	if now_portrait != _was_portrait:
		_was_portrait = now_portrait
		_rebuild_ui()
		return
	# Recompute panel width (portrait vs landscape) and re-apply collapsed/expanded offset.
	if is_instance_valid(_content_panel):
		_content_panel.custom_minimum_size.x = _get_panel_width()
	if is_instance_valid(_tab_button):
		_tab_button.custom_minimum_size.x = _get_tab_width()
	call_deferred("_update_layout", false)

func _rebuild_ui() -> void:
	if is_instance_valid(_main_hbox):
		_main_hbox.queue_free()
		_main_hbox = null
	_build_ui()
	call_deferred("_update_layout", false)
	_sync_toggles_with_service()

func _on_map_overlay_settings_changed(_settings: Dictionary) -> void:
	_sync_toggles_with_service()


func _build_ui() -> void:
	# Anchor to the absolute left edge of the screen and span full height
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Explicitly anchor HBox to span full screen height to guarantee centering
	_main_hbox = HBoxContainer.new()
	_main_hbox.anchor_left = 0.0
	_main_hbox.anchor_right = 0.0
	_main_hbox.anchor_top = 0.0
	_main_hbox.anchor_bottom = 1.0
	_main_hbox.offset_top = 0
	_main_hbox.offset_bottom = 0
	_main_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	_main_hbox.add_theme_constant_override("separation", 0)
	_main_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main_hbox)
	
	# Tab button container
	var tab_container = CenterContainer.new()
	tab_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	_tab_button = Button.new()
	_tab_button.text = "⚙"
	_tab_button.custom_minimum_size = Vector2(_get_tab_width(), 100 if _is_portrait() else 80)
	_tab_button.add_theme_font_size_override("font_size", _get_font_size(24))
	
	var tab_sb = StyleBoxFlat.new()
	tab_sb.bg_color = Color(0.15, 0.16, 0.18, 0.95)
	tab_sb.border_width_top = 3
	tab_sb.border_width_right = 3
	tab_sb.border_width_bottom = 3
	tab_sb.border_color = Color(0.35, 0.45, 0.65, 0.7)
	tab_sb.corner_radius_top_right = 16
	tab_sb.corner_radius_bottom_right = 16
	_tab_button.add_theme_stylebox_override("normal", tab_sb)
	_tab_button.add_theme_stylebox_override("hover", tab_sb)
	_tab_button.add_theme_stylebox_override("pressed", tab_sb)
	_tab_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	_tab_button.pressed.connect(_on_tab_button_pressed)
	tab_container.add_child(_tab_button)
	
	# Content Panel
	_content_panel = PanelContainer.new()
	_content_panel.custom_minimum_size.x = _get_panel_width()
	_content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var content_sb = StyleBoxFlat.new()
	content_sb.bg_color = Color(0.11, 0.12, 0.14, 0.96)
	content_sb.border_width_right = 3
	content_sb.border_color = Color(0.25, 0.35, 0.55, 0.6)
	
	var compact = _is_landscape_mobile()
	var pad_lr = 28 if _is_portrait() else (14 if compact else 20)
	var pad_tb = 36 if _is_portrait() else (12 if compact else 28)
	content_sb.content_margin_left = pad_lr
	content_sb.content_margin_right = pad_lr
	content_sb.content_margin_top = pad_tb
	content_sb.content_margin_bottom = pad_tb
	_content_panel.add_theme_stylebox_override("panel", content_sb)

	# Scroll fallback: if the rows ever exceed the available height (short landscape
	# screens, notches), they scroll instead of dropping below the screen edge.
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_content_panel.add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 24 if _is_portrait() else (7 if compact else 18))
	scroll.add_child(_vbox)

	var title = Label.new()
	title.text = "Map Overlays"
	title.add_theme_font_size_override("font_size", _get_font_size(18 if compact else 22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(title)

	if not compact:
		var sep = HSeparator.new()
		_vbox.add_child(sep)
	
	# Toggles with descriptive rows
	active_dest_toggle = _add_toggle_row(
		"Active Convoy Targets", 
		"🎯", 
		"Highlight destinations matching cargo in the selected convoy."
	)
	curr_sett_dest_toggle = _add_toggle_row(
		"Local Settlement Targets", 
		"📦", 
		"Show delivery routes departing from the convoy's current city."
	)
	all_convoy_dest_toggle = _add_toggle_row(
		"All Convoy Targets", 
		"🚚", 
		"Map every active convoy destination globally."
	)
	settlement_labels_toggle = _add_toggle_row(
		"Settlement Labels", 
		"🏘️", 
		"Draw overhead names for all discovered cities."
	)
	warehouse_labels_toggle = _add_toggle_row(
		"Warehouse Indicators", 
		"🏭", 
		"Display markers over settlements where you own warehouses."
	)
	
	active_dest_toggle.toggled.connect(func(v): _update_setting("active_delivery_destinations", v))
	curr_sett_dest_toggle.toggled.connect(func(v): _update_setting("settlement_delivery_destinations", v))
	all_convoy_dest_toggle.toggled.connect(func(v): _update_setting("all_convoy_destinations", v))
	settlement_labels_toggle.toggled.connect(func(v): _update_setting("settlement_labels", v))
	warehouse_labels_toggle.toggled.connect(func(v): _update_setting("warehouse_labels", v))
	
	_main_hbox.add_child(_content_panel)
	_main_hbox.add_child(tab_container)

func _add_toggle_row(text: String, icon: String, description: String) -> CheckButton:
	var row_panel = PanelContainer.new()
	var row_sb = StyleBoxFlat.new()
	row_sb.bg_color = Color(0.16, 0.18, 0.22, 0.5)
	row_sb.border_width_right = 4
	row_sb.border_color = Color(0.35, 0.45, 0.65, 0.6)
	
	var compact = _is_landscape_mobile()
	var r_pad = 16 if _is_portrait() else (6 if compact else 10)
	row_sb.content_margin_left = r_pad
	row_sb.content_margin_right = r_pad
	row_sb.content_margin_top = r_pad
	row_sb.content_margin_bottom = r_pad
	row_sb.corner_radius_top_right = 8
	row_sb.corner_radius_bottom_right = 8
	row_panel.add_theme_stylebox_override("panel", row_sb)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 2 if compact else 6)
	row_panel.add_child(main_vbox)
	
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	main_vbox.add_child(row)
	
	var icon_label = Label.new()
	icon_label.text = icon
	icon_label.custom_minimum_size.x = _get_font_size(20)
	icon_label.add_theme_font_size_override("font_size", _get_font_size(18))
	
	var label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", _get_font_size(15))
	
	var toggle = CheckButton.new()
	toggle.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	row.add_child(icon_label)
	row.add_child(label)
	row.add_child(toggle)
	
	# Descriptions are hidden in landscape mobile to keep all rows on-screen.
	if not description.is_empty() and not compact:
		var desc_label = Label.new()
		desc_label.text = description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.add_theme_font_size_override("font_size", _get_font_size(11))
		desc_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 0.85))
		main_vbox.add_child(desc_label)
		
	_vbox.add_child(row_panel)
	return toggle

func _sync_toggles_with_service() -> void:
	if not is_instance_valid(_settings_service): return
	_set_toggle_value_quietly(active_dest_toggle, _settings_service.active_delivery_destinations)
	_set_toggle_value_quietly(curr_sett_dest_toggle, _settings_service.settlement_delivery_destinations)
	_set_toggle_value_quietly(all_convoy_dest_toggle, _settings_service.all_convoy_destinations)
	_set_toggle_value_quietly(settlement_labels_toggle, _settings_service.settlement_labels)
	_set_toggle_value_quietly(warehouse_labels_toggle, _settings_service.warehouse_labels)

func _set_toggle_value_quietly(toggle: CheckButton, value: bool) -> void:
	if is_instance_valid(toggle):
		toggle.set_block_signals(true)
		toggle.button_pressed = value
		toggle.set_block_signals(false)

func _update_setting(setting_name: String, value: bool) -> void:
	if is_instance_valid(_settings_service) and _settings_service.has_method("update_setting"):
		_settings_service.update_setting(setting_name, value)

func _on_tab_button_pressed() -> void:
	_is_expanded = !_is_expanded
	_update_layout(true)

func _update_layout(animate: bool = false) -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	# When collapsed, slide the panel far enough left that its content is fully off-screen.
	# The parent container may start at a non-zero screen X (e.g. safe area margin), so we
	# must add that parent offset to ensure the content panel clears the screen left edge.
	var panel_width = _get_panel_width()
	var parent_screen_x = 0.0
	if not _is_expanded and is_inside_tree():
		var parent = get_parent()
		if is_instance_valid(parent) and parent is Control:
			parent_screen_x = (parent as Control).get_global_rect().position.x

	var target_left = 0.0 if _is_expanded else -(panel_width + parent_screen_x)

	if animate:
		_anim_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_anim_tween.tween_property(self, "offset_left", target_left, 0.3)
	else:
		offset_left = target_left



