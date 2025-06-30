extends PanelContainer

@onready var username_label: Label = $UserInfoHBox/UsernameLabel
@onready var user_money_label: Label = $UserInfoHBox/UserMoneyLabel

var gdm: Node

func _ready() -> void:
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		# Use modern Godot 4 signal connection syntax for better clarity and practice.
		if not gdm.is_connected("user_data_updated", _on_user_data_updated):
			gdm.user_data_updated.connect(_on_user_data_updated)
	else:
		printerr("UserInfoDisplay: Could not find GameDataManager.")

	_style_panel()
	_update_display() # Initial update

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_update_display()

func _on_user_data_updated(user_data: Dictionary):
	_update_display()

func _update_display():
	if not is_node_ready() or not is_instance_valid(gdm):
		return

	var user_data = gdm.get_current_user_data()
	var username: String = user_data.get("username", "Player")
	var money_amount = user_data.get("money", 0)

	username_label.text = username
	user_money_label.text = _format_money(money_amount)

func _style_panel():
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.2, 0.2, 0.2, 0.8) # A dark, semi-transparent grey
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color.LIGHT_GRAY
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", panel_style)

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
