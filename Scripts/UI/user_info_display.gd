extends HBoxContainer

## Emitted when a convoy is selected from the dropdown, requesting its menu to be opened.
signal convoy_menu_requested(convoy_id: String)

@onready var username_label: Label = $UsernameLabel
@onready var user_money_label: Label = $UserMoneyLabel

# Store original font sizes to scale them from a clean base
var _original_username_font_size: int
var _original_money_font_size: int

var gdm: Node

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for child in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_PASS
			print("UserInfoDisplay: Set mouse_filter=PASS on child Control node:", child.name)
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		# Connect to signals from the GameDataManager
		if not gdm.is_connected("user_data_updated", _on_user_data_updated):
			gdm.user_data_updated.connect(_on_user_data_updated)

		# Connect to the global UI scale manager
		if Engine.has_singleton("ui_scale_manager"):
			# Store original sizes before applying any scaling
			_original_username_font_size = username_label.get_theme_font_size("font_size")
			_original_money_font_size = user_money_label.get_theme_font_size("font_size")
			ui_scale_manager.scale_changed.connect(_on_ui_scale_changed)
			# Apply initial scale
			_on_ui_scale_changed(ui_scale_manager.get_global_ui_scale())
		else:
			printerr("UserInfoDisplay: ui_scale_manager singleton not found. UI scaling will not be dynamic.")

	else:
		printerr("UserInfoDisplay: Could not find GameDataManager.")



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

func _on_user_data_updated(user_data: Dictionary):
	_update_display()


func _on_ui_scale_changed(new_scale: float) -> void:
	"""Applies the new global UI scale to the font sizes of the labels."""
	if _original_username_font_size > 0:
		username_label.add_theme_font_size_override("font_size", int(_original_username_font_size * new_scale))
	if _original_money_font_size > 0:
		user_money_label.add_theme_font_size_override("font_size", int(_original_money_font_size * new_scale))


func _update_display():
	if not is_node_ready() or not is_instance_valid(gdm):
		return

	var user_data = gdm.get_current_user_data()
	var username: String = user_data.get("username", "Player")
	var money_amount = user_data.get("money", 0)

	username_label.text = username
	user_money_label.text = _format_money(money_amount)

func _format_money(amount: Variant) -> String:
	"""Formats a number into a currency string, e.g., $1,234,567"""
	var num: int = 0
	if amount is int or amount is float:
		num = int(amount)
	
	if amount == null:
		return "$0"
	
	var s = str(num)
	var mod = s.length() % 3
	var res = ""
	if mod != 0:
		res = s.substr(0, mod)
	for i in range(mod, s.length(), 3):
		res += ("," if res.length() > 0 else "") + s.substr(i, 3)
	return "$%s" % res
