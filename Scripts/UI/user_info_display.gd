extends HBoxContainer

## Emitted when a convoy is selected from the dropdown, requesting its menu to be opened.
@warning_ignore("unused_signal")
signal convoy_menu_requested(convoy_id: String)

@onready var username_label: Label = $UsernameLabel
@onready var user_money_label: Label = $UserMoneyLabel
@onready var settings_button: Button = $SettingsButton
var _settings_menu_instance: Window

# Store original font sizes to scale them from a clean base
var _original_username_font_size: int
var _original_money_font_size: int

@onready var _store: Node = get_node_or_null("/root/GameStore")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for child in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_PASS
			print("UserInfoDisplay: Set mouse_filter=PASS on child Control node:", child.name)
	if is_instance_valid(_store) and _store.has_signal("user_changed"):
		if not _store.user_changed.is_connected(_on_user_data_updated):
			_store.user_changed.connect(_on_user_data_updated)

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

	# Settings button hookup
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)



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

func _on_user_data_updated(_user_data: Dictionary):
	_update_display()


func _on_ui_scale_changed(new_scale: float) -> void:
	"""Applies the new global UI scale to the font sizes of the labels."""
	if _original_username_font_size > 0:
		username_label.add_theme_font_size_override("font_size", int(_original_username_font_size * new_scale))
	if _original_money_font_size > 0:
		user_money_label.add_theme_font_size_override("font_size", int(_original_money_font_size * new_scale))


func _update_display():
	if not is_node_ready() or not is_instance_valid(_store):
		return
	var user_data: Dictionary = {}
	if _store.has_method("get_user"):
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
