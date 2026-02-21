extends HBoxContainer

## Emitted when a convoy is selected from the dropdown, requesting its menu to be opened.
@warning_ignore("unused_signal")
signal convoy_menu_requested(convoy_id: String)

@onready var username_label: Label = $UsernameLabel
@onready var user_money_label: Label = $UserMoneyLabel
@onready var settings_button: MenuButton = $SettingsButton
var _settings_menu_instance: Window
var _bug_report_window: BugReportWindow
var _discord_popup: PopupPanel
var _steam_link_popup: PopupPanel

const _OPTIONS_SETTINGS_ID := 1
const _OPTIONS_REPORT_BUG_ID := 2
const _OPTIONS_DISCORD_ID := 3
const _OPTIONS_LINK_STEAM_ID := 4
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

	# Options dropdown (replaces separate top-row buttons)
	_configure_options_dropdown()
	queue_redraw()



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
	popup.add_item("Report Bug", _OPTIONS_REPORT_BUG_ID)
	popup.add_item("Join Discord", _OPTIONS_DISCORD_ID)
	popup.add_item("Link Steam", _OPTIONS_LINK_STEAM_ID)

	if not popup.id_pressed.is_connected(_on_options_menu_id_pressed):
		popup.id_pressed.connect(_on_options_menu_id_pressed)


func _on_options_menu_id_pressed(id: int) -> void:
	match id:
		_OPTIONS_SETTINGS_ID:
			_on_settings_button_pressed()
		_OPTIONS_REPORT_BUG_ID:
			call_deferred("_on_bug_report_pressed")
		_OPTIONS_DISCORD_ID:
			call_deferred("_on_discord_pressed")
		_OPTIONS_LINK_STEAM_ID:
			call_deferred("_on_link_steam_pressed")
		_:
			pass


func _on_discord_pressed() -> void:
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


func _on_link_steam_pressed() -> void:
	# Lazy-create Steam link popup
	if not is_instance_valid(_steam_link_popup):
		var script := load("res://Scripts/UI/steam_link_popup.gd")
		if script == null:
			push_error("Failed to load steam_link_popup.gd")
			return
		_steam_link_popup = script.new()
		get_tree().root.add_child(_steam_link_popup)

	if _steam_link_popup.has_method("open_centered"):
		_steam_link_popup.open_centered()
	else:
		_steam_link_popup.show()


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
			# Add to the root so it behaves like a popup window
			get_tree().root.add_child(_settings_menu_instance)
			_settings_menu_instance.title = "Options"
			_settings_menu_instance.min_size = Vector2(600, 480)
		else:
			push_error("Failed to load SettingsMenu.tscn")
			return
	# Popup centered each time
	if _settings_menu_instance:
		if _settings_menu_instance.has_method("popup_centered"):
			_settings_menu_instance.popup_centered(Vector2i(720, 560))
		else:
			_settings_menu_instance.show()
