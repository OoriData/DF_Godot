extends HBoxContainer

@export var hide_on_convoy_select: bool = false

@onready var username_label: Label = $UsernameLabel
@onready var user_money_label: Label = $UserMoneyLabel

var gdm: Node

func _ready() -> void:
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		# Use modern Godot 4 signal connection syntax for better clarity and practice.
		if not gdm.is_connected("user_data_updated", _on_user_data_updated):
			gdm.user_data_updated.connect(_on_user_data_updated)
		
		if hide_on_convoy_select:
			if gdm.has_signal("convoy_selection_changed"):
				if not gdm.is_connected("convoy_selection_changed", _on_convoy_selection_changed):
					gdm.convoy_selection_changed.connect(_on_convoy_selection_changed)
				# Set initial visibility based on whether a convoy is already selected.
				# This assumes gdm.get_selected_convoy() exists and returns null if none is selected.
				if gdm.has_method("get_selected_convoy"):
					_on_convoy_selection_changed(gdm.get_selected_convoy())
			else:
				printerr("UserInfoDisplay: GameDataManager is missing the 'convoy_selection_changed' signal. The top bar display will not hide on convoy selection.")
	else:
		printerr("UserInfoDisplay: Could not find GameDataManager.")

	_update_display() # Initial update

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_update_display()

func _on_convoy_selection_changed(selected_convoy: Variant) -> void:
	# This logic is only connected if hide_on_convoy_select is true.
	# If a convoy is selected (not null), hide this UI element.
	# If no convoy is selected (null), show it.
	visible = (selected_convoy == null)

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
