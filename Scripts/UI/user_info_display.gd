extends PanelContainer

## Emitted when a convoy is selected from the dropdown, requesting its menu to be opened.
@warning_ignore("unused_signal")
signal convoy_menu_requested(convoy_id: String)

@onready var username_label: Label = %UsernameLabel
@onready var user_money_label: Label = %UserMoneyLabel
@onready var settings_button: MenuButton = %SettingsButton
@onready var report_bug_button: Button = %ReportBugButton
var _settings_menu_instance: CanvasLayer
var _bug_report_window: BugReportWindow
var _discord_popup: PopupPanel
var _account_links_popup: CanvasLayer

const _OPTIONS_SETTINGS_ID := 1
const _OPTIONS_REPORT_BUG_ID := 2
const _OPTIONS_DISCORD_ID := 3
const _OPTIONS_CONNECT_ACCOUNTS_ID := 4
# Store original font sizes to scale them from a clean base
var _original_username_font_size: int
var _original_money_font_size: int

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _user_service: Node = get_node_or_null("/root/UserService")

@export var navbar_background_color: Color = Color(0.16, 0.16, 0.16, 0.92)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for child in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_PASS

	if is_instance_valid(_store) and _store.has_signal("user_changed"):
		if not _store.user_changed.is_connected(_on_user_data_updated):
			_store.user_changed.connect(_on_user_data_updated)
	
	if is_instance_valid(_hub) and _hub.has_signal("user_refresh_requested"):
		_hub.user_refresh_requested.connect(_on_user_refresh_requested)

	# Connect to the global UI scale manager (autoload under /root)
	var usm = get_node_or_null("/root/ui_scale_manager")
	if is_instance_valid(usm):
		# Store original sizes before applying any scaling
		_original_username_font_size = username_label.get_theme_font_size("font_size")
		_original_money_font_size = user_money_label.get_theme_font_size("font_size")
		usm.scale_changed.connect(_on_ui_scale_changed)
		# Apply initial scale
		_on_ui_scale_changed(usm.get_global_ui_scale())
	else:
		printerr("UserInfoDisplay: ui_scale_manager autoload not found at /root/ui_scale_manager. UI scaling will not be dynamic.")

	# Connect standalone report bug button
	if is_instance_valid(report_bug_button):
		report_bug_button.pressed.connect(call_deferred.bind("_on_bug_report_pressed"))

	# Options dropdown (replaces separate top-row buttons)
	_configure_options_dropdown()
	
	# Initial desktop sizing/styling if not mobile
	if not _is_mobile():
		_apply_desktop_styling()
	
	if _is_mobile():
		_apply_mobile_optimizations()
	
	queue_redraw()

func _is_mobile() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.get_name() in ["Android", "iOS"]:
		return true
	if is_inside_tree():
		var win_size = get_viewport().get_visible_rect().size
		if win_size.y > win_size.x:
			return true
	return false

func _apply_mobile_optimizations() -> void:
	# 1. Scaling & Touch Targets
	_update_mobile_sizing()
	
	# 2. Aggressive Typography Boost for Portrait
	var win_size = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(0, 0)
	var is_portrait = win_size.y > win_size.x
	var boost = 3.2 if is_portrait else 2.2
	
	var labels = [username_label, user_money_label]
	for label in labels:
		if is_instance_valid(label):
			var fs = label.get_theme_font_size("font_size")
			label.add_theme_font_size_override("font_size", int(fs * boost))
	
	# Settings button scaling
	if is_instance_valid(settings_button):
		var btn_fs = settings_button.get_theme_font_size("font_size")
		settings_button.add_theme_font_size_override("font_size", int(btn_fs * boost))
		settings_button.custom_minimum_size.y = 100 if is_portrait else 60
		var sb_btn = StyleBoxFlat.new()
		sb_btn.bg_color = Color(0.12, 0.15, 0.2, 0.95)
		sb_btn.border_width_left = 1
		sb_btn.border_width_right = 1
		sb_btn.border_width_top = 1
		sb_btn.border_width_bottom = 1
		sb_btn.border_color = Color(0.4, 0.45, 0.5, 0.8)
		sb_btn.corner_radius_top_left = 8
		sb_btn.corner_radius_top_right = 8
		sb_btn.corner_radius_bottom_left = 8
		sb_btn.corner_radius_bottom_right = 8
		sb_btn.content_margin_left = 28
		sb_btn.content_margin_right = 28
		settings_button.add_theme_stylebox_override("normal", sb_btn)

	# Report Bug button scaling & red styling
	if is_instance_valid(report_bug_button):
		var bug_fs = report_bug_button.get_theme_font_size("font_size")
		report_bug_button.add_theme_font_size_override("font_size", int(bug_fs * boost))
		report_bug_button.custom_minimum_size.y = 100 if is_portrait else 60
		var bug_style = StyleBoxFlat.new()
		bug_style.bg_color = Color(0.7, 0.1, 0.15, 0.95) # Prominent Red
		bug_style.border_width_left = 2
		bug_style.border_width_right = 2
		bug_style.border_width_top = 2
		bug_style.border_width_bottom = 2
		bug_style.border_color = Color(1.0, 0.4, 0.4, 0.8)
		bug_style.corner_radius_top_left = 8
		bug_style.corner_radius_top_right = 8
		bug_style.corner_radius_bottom_left = 8
		bug_style.corner_radius_bottom_right = 8
		bug_style.content_margin_left = 28
		bug_style.content_margin_right = 28
		report_bug_button.add_theme_stylebox_override("normal", bug_style)
		# Hover/Pressed states
		var bug_style_hover = bug_style.duplicate()
		bug_style_hover.bg_color = Color(0.85, 0.15, 0.2, 1.0)
		report_bug_button.add_theme_stylebox_override("hover", bug_style_hover)
		report_bug_button.add_theme_stylebox_override("pressed", bug_style_hover)
	
	# 3. Layout & Density (16px margins)
	add_theme_constant_override("separation", 16)
	
	# 4. Safe Area Handling (Curved corners and notches)
	_update_safe_margins()
	if not get_viewport().size_changed.is_connected(_update_safe_margins):
		get_viewport().size_changed.connect(_update_safe_margins)
	
	# 5. Ledger Style for Username Chip
	var ledger_chip = StyleBoxFlat.new()
	ledger_chip.bg_color = Color(0.12, 0.15, 0.2, 0.95) # Deep slate
	ledger_chip.border_width_left = 1
	ledger_chip.border_width_right = 1
	ledger_chip.border_width_top = 1
	ledger_chip.border_width_bottom = 1
	ledger_chip.border_color = Color(0.4, 0.45, 0.5, 0.8) # Steel border
	ledger_chip.corner_radius_top_left = 6
	ledger_chip.corner_radius_top_right = 6
	ledger_chip.corner_radius_bottom_left = 6
	ledger_chip.corner_radius_bottom_right = 6
	ledger_chip.content_margin_left = 12
	ledger_chip.content_margin_right = 12
	if is_instance_valid(username_label):
		username_label.add_theme_stylebox_override("normal", ledger_chip)

func _update_mobile_sizing() -> void:
	if not _is_mobile():
		return
	var win_size = get_viewport_rect().size if is_inside_tree() else Vector2(0, 0)
	var is_portrait = win_size.y > win_size.x
	if is_portrait:
		custom_minimum_size.y = 170
		if is_instance_valid(settings_button): settings_button.custom_minimum_size.y = 120
		if is_instance_valid(report_bug_button): report_bug_button.custom_minimum_size.y = 120
	else:
		custom_minimum_size.y = 90
		if is_instance_valid(settings_button): settings_button.custom_minimum_size.y = 64
		if is_instance_valid(report_bug_button): report_bug_button.custom_minimum_size.y = 64

func _apply_desktop_styling() -> void:
	custom_minimum_size.y = 68 # Reverted from 56 (closer to original 48-60 range)
	
	var boost = 1.3 # Slightly reduced from 1.2
	var btn_fs = settings_button.get_theme_font_size("font_size")
	if btn_fs <= 0: btn_fs = 16
	
	settings_button.add_theme_font_size_override("font_size", int(btn_fs * boost))
	settings_button.custom_minimum_size.y = 52 # Reverted from 44
	
	if is_instance_valid(report_bug_button):
		report_bug_button.add_theme_font_size_override("font_size", int(btn_fs * boost))
		report_bug_button.custom_minimum_size.y = 52
		var bug_style = StyleBoxFlat.new()
		bug_style.bg_color = Color(0.6, 0.1, 0.1, 0.9)
		bug_style.corner_radius_top_left = 4
		bug_style.corner_radius_top_right = 4
		bug_style.corner_radius_bottom_left = 4
		bug_style.corner_radius_bottom_right = 4
		bug_style.content_margin_left = 16
		bug_style.content_margin_right = 16
		report_bug_button.add_theme_stylebox_override("normal", bug_style)
		
		var bug_style_hover = bug_style.duplicate()
		bug_style_hover.bg_color = Color(0.8, 0.15, 0.15, 1.0)
		report_bug_button.add_theme_stylebox_override("hover", bug_style_hover)

func _update_safe_margins() -> void:
	if not _is_mobile():
		return
	
	var safe_area = DisplayServer.get_display_safe_area()
	var screen_size = DisplayServer.window_get_size() # Use window size for logical coordinates
	var screen_full = DisplayServer.screen_get_size()
	
	# Godot 4.3+ safe_area is in screen pixels. We need logical pixels if content_scale_factor is used.
	# However, since we're setting theme constants, we use the raw pixel offsets relative to the screen.
	# Actually, the best way is to let MarginContainer handle it or calculate relative to window.
	
	var left_pad = max(32.0, safe_area.position.x)
	var right_pad = max(32.0, screen_full.x - safe_area.end.x)
	var top_pad = safe_area.position.y
	
	if screen_size.y > screen_size.x:
		top_pad += 24.0 # Add extra clearance for dynamic islands in portrait
	
	# Update stylebox content margins instead of outer margins
	# This ensures the background remains full-width while content clears corners
	var style = get_theme_stylebox("panel").duplicate()
	if style is StyleBoxFlat:
		style.bg_color = Color(0.08, 0.1, 0.12, 0.96) # Deep Slate
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.35, 0.4, 0.8) # Steel border
		
		style.content_margin_left = int(left_pad)
		style.content_margin_right = int(right_pad)
		style.content_margin_top = int(top_pad)
		add_theme_stylebox_override("panel", style)
	
	# Remove any outer margins set previously to ensure the bar stays full-width
	remove_theme_constant_override("margin_left")
	remove_theme_constant_override("margin_right")
	remove_theme_constant_override("margin_top")



func _print_canvas_layers(node: Node):
	if node is CanvasLayer:
		print("  CanvasLayer:", node.name, "layer=", node.layer)
	for child in node.get_children():
		_print_canvas_layers(child)

func _print_ui_tree(node: Node, indent: int):
	var prefix = "  ".repeat(indent)
	var mf = ""
	if node is Control:
		mf = " mouse_filter=" + str(node.mouse_filter)
	print("%s- %s (%s)%s" % [prefix, node.name, node.get_class(), mf])
	for child in node.get_children():
		_print_ui_tree(child, indent + 1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_update_display()
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		_update_mobile_sizing()
		queue_redraw()


func _draw() -> void:
	# Explicit background so the navbar stays grey even if the project clear color is black.
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), navbar_background_color, true)

func _on_user_data_updated(user_data: Dictionary):
	_update_display(user_data)

func _on_user_refresh_requested() -> void:
	var refreshed = false
	
	# Try UserService first
	if is_instance_valid(_user_service) and _user_service.has_method("request_user"):
		_user_service.request_user()
		refreshed = true
	# Try APICalls with common method names
	elif is_instance_valid(_api):
		if _api.has_method("request_user"):
			_api.request_user()
			refreshed = true
		elif _api.has_method("refresh_user_data"):
			var uid = ""
			if is_instance_valid(_store) and _store.has_method("get_user"):
				var u = _store.get_user()
				uid = str(u.get("user_id", u.get("id", "")))
			_api.refresh_user_data(uid)
			refreshed = true
	# Try Store last
	elif is_instance_valid(_store) and _store.has_method("request_user_refresh"):
		_store.request_user_refresh()
		refreshed = true

	if not refreshed:
		print("[UserInfoDisplay] ERROR: No way to request user refresh found!")

	_update_display()

func _on_ui_scale_changed(_new_scale: float) -> void:
	# Font scaling is now handled globally by content_scale_factor.
	# We no longer need to manually override font sizes here.
	pass


func _configure_options_dropdown() -> void:
	if not is_instance_valid(settings_button):
		return
	# Ensure this button behaves like a dropdown.
	var popup := settings_button.get_popup()
	if not is_instance_valid(popup):
		push_error("UserInfoDisplay: SettingsButton is a MenuButton but has no popup")
		return

	popup.clear()
	popup.add_item("Settings", _OPTIONS_SETTINGS_ID)
	popup.add_item("Join Discord", _OPTIONS_DISCORD_ID)
	popup.add_item("Connect Accounts", _OPTIONS_CONNECT_ACCOUNTS_ID)
	popup.add_separator()
	popup.add_item("Highlights & Tips", 100) # Using 100 as a unique ID for Tips

	if not popup.id_pressed.is_connected(_on_options_menu_id_pressed):
		popup.id_pressed.connect(_on_options_menu_id_pressed)
		
	if _is_mobile():
		popup.add_theme_font_size_override("font_size", int(16 * 2.2))
		popup.add_theme_constant_override("v_separation", 48)
		popup.add_theme_constant_override("item_start_padding", 48)
		popup.add_theme_constant_override("item_end_padding", 48)
		var popup_style = StyleBoxFlat.new()
		popup_style.bg_color = Color(0.12, 0.15, 0.2, 0.98)
		popup_style.content_margin_left = 32
		popup_style.content_margin_right = 32
		popup_style.content_margin_top = 24
		popup_style.content_margin_bottom = 24
		popup_style.border_width_left = 1
		popup_style.border_width_right = 1
		popup_style.border_width_top = 1
		popup_style.border_width_bottom = 1
		popup_style.border_color = Color(0.4, 0.45, 0.5, 0.8)
		popup_style.corner_radius_top_left = 6
		popup_style.corner_radius_top_right = 6
		popup_style.corner_radius_bottom_left = 6
		popup_style.corner_radius_bottom_right = 6
		popup.add_theme_stylebox_override("panel", popup_style)


func _on_options_menu_id_pressed(id: int) -> void:
	match id:
		_OPTIONS_SETTINGS_ID:
			_on_settings_button_pressed()
		_OPTIONS_REPORT_BUG_ID:
			call_deferred("_on_bug_report_pressed")
		_OPTIONS_DISCORD_ID:
			call_deferred("_on_discord_pressed")
		_OPTIONS_CONNECT_ACCOUNTS_ID:
			call_deferred("_on_connect_accounts_pressed")
		100:
			_on_highlights_tips_pressed()
		_:
			pass

func _on_highlights_tips_pressed() -> void:
	var main_screen := get_tree().root.find_child("MainScreen", true, false)
	if is_instance_valid(main_screen) and main_screen.has_method("show_returning_player_tips"):
		main_screen.show_returning_player_tips()


func _on_discord_pressed() -> void:
	print("[UserInfoDisplay] _on_discord_pressed called | LOUD LOG")
	# Lazy-create discord popup
	if not is_instance_valid(_discord_popup):
		var script := load("res://Scripts/UI/discord_popup.gd")
		if script == null:
			push_error("Failed to load discord_popup.gd")
			return
		_discord_popup = script.new()
		get_tree().root.add_child(_discord_popup)

	if _discord_popup.has_method("open_centered"):
		_discord_popup.open_centered()
	else:
		_discord_popup.show()


func _on_connect_accounts_pressed() -> void:
	# Lazy-create Account links popup
	if not is_instance_valid(_account_links_popup):
		var script := load("res://Scripts/UI/account_links_popup.gd")
		if script == null:
			push_error("Failed to load account_links_popup.gd")
			return
		_account_links_popup = script.new()
		get_tree().root.add_child(_account_links_popup)

	if _account_links_popup.has_method("open_centered"):
		_account_links_popup.open_centered()
	else:
		_account_links_popup.show()


func _on_bug_report_pressed() -> void:
	# Capture screenshot BEFORE any window/popup appears.
	var png_bytes := PackedByteArray()
	# Wait until the frame is rendered so the viewport image is valid.
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if is_instance_valid(vp) and is_instance_valid(vp.get_texture()):
		var img := vp.get_texture().get_image()
		if img:
			png_bytes = img.save_png_to_buffer()

	# Lazy-create bug report window
	if not is_instance_valid(_bug_report_window):
		var script := load("res://Scripts/UI/bug_report_window.gd")
		if script == null:
			push_error("Failed to load bug_report_window.gd")
			return
		_bug_report_window = script.new()
		get_tree().root.add_child(_bug_report_window)

	if _bug_report_window.has_method("set_screenshot_png_bytes"):
		_bug_report_window.set_screenshot_png_bytes(png_bytes)
	if _bug_report_window.has_method("open_centered"):
		_bug_report_window.open_centered()
	else:
		_bug_report_window.show()


func _update_display(data: Dictionary = {}):
	if not is_node_ready() or not is_instance_valid(_store):
		return
	var user_data: Dictionary = data
	if user_data.is_empty() and _store.has_method("get_user"):
		user_data = _store.get_user()
		
	var username: String = user_data.get("username", "Player")
	var money_amount = user_data.get("money", 0)

	username_label.text = username
	user_money_label.text = NumberFormat.format_money(money_amount)

func _format_money(amount: Variant) -> String:
	return NumberFormat.format_money(amount)

func _on_settings_button_pressed():
	# Lazy-load the settings menu
	if not is_instance_valid(_settings_menu_instance):
		var scene: PackedScene = load("res://Scenes/SettingsMenu.tscn")
		if scene:
			_settings_menu_instance = scene.instantiate()
			# Add to the root so it behaves like a full-screen overlay
			get_tree().root.add_child(_settings_menu_instance)
		else:
			push_error("Failed to load SettingsMenu.tscn")
			return
	
	if _settings_menu_instance:
		_settings_menu_instance.show()
		# Refresh layout/sizing for the current screen orientation
		if _settings_menu_instance.has_method("_apply_mobile_optimizations"):
			_settings_menu_instance.call("_apply_mobile_optimizations")
