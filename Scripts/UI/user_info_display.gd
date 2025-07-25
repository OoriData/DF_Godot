extends HBoxContainer

## Emitted when a convoy is selected from the dropdown, requesting its menu to be opened.
signal convoy_menu_requested(convoy_id: String)

@onready var username_label: Label = $UsernameLabel
@onready var user_money_label: Label = $UserMoneyLabel
@onready var convoy_menu_button: MenuButton = $ConvoyMenuButton

# Store original font sizes to scale them from a clean base
var _original_username_font_size: int
var _original_money_font_size: int

var gdm: Node

func _ready() -> void:
	# Ensure UserInfoDisplay and all child Control nodes do not block input to ConvoyMenuButton
	mouse_filter = Control.MOUSE_FILTER_PASS
	for child in get_children():
		if child is Control and child != convoy_menu_button:
			child.mouse_filter = Control.MOUSE_FILTER_PASS
			print("UserInfoDisplay: Set mouse_filter=PASS on child Control node:", child.name)
	# Diagnostics for convoy_menu_button
	print("[DIAG] UserInfoDisplay: convoy_menu_button mouse_filter:", convoy_menu_button.mouse_filter)
	print("[DIAG] UserInfoDisplay: convoy_menu_button global_position:", convoy_menu_button.global_position, " size:", convoy_menu_button.size)
	print("[DIAG] UserInfoDisplay: self (UserInfoDisplay) global_position:", global_position, " size:", size)
	var diag_popup = convoy_menu_button.get_popup()
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		# Connect to signals from the GameDataManager
		if not gdm.is_connected("user_data_updated", _on_user_data_updated):
			gdm.user_data_updated.connect(_on_user_data_updated)
		if not gdm.is_connected("convoy_data_updated", _on_convoy_data_updated):
			gdm.convoy_data_updated.connect(_on_convoy_data_updated)
		if not gdm.is_connected("convoy_selection_changed", _on_convoy_selection_changed):
			gdm.convoy_selection_changed.connect(_on_convoy_selection_changed)

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

	# Connect to the menu button's popup signal
	var popup = convoy_menu_button.get_popup()
	if not popup.is_connected("id_pressed", _on_convoy_menu_item_pressed):
		popup.id_pressed.connect(_on_convoy_menu_item_pressed)

	# Debug: print when the button itself is pressed
	if not convoy_menu_button.is_connected("pressed", _on_convoy_menu_button_pressed_debug):
		convoy_menu_button.pressed.connect(_on_convoy_menu_button_pressed_debug)

func _on_convoy_menu_button_pressed_debug():
	print("[DEBUG] ConvoyMenuButton was pressed!")

	_update_display() # Initial update

	# Print the full UI tree and mouse_filter values after a short delay to ensure all UI is loaded
	await get_tree().process_frame
	await get_tree().process_frame
	print("[DIAG] FULL UI TREE (after login):")
	_print_ui_tree(get_tree().root, 0)

	# Print all CanvasLayer nodes and their layer property
	print("[DIAG] CanvasLayer order:")
	_print_canvas_layers(get_tree().root)

	# Print layer property for known CanvasLayer nodes by name
	var root = get_tree().root
	var screen_space_ui = root.find_child("ScreenSpaceUI", true, false)
	var ui_manager_node = root.find_child("UIManagerNode", true, false)
	var menu_ui_layer = root.find_child("MenuUILayer", true, false)
	if screen_space_ui and screen_space_ui is CanvasLayer:
		print("[DIAG] ScreenSpaceUI.layer:", screen_space_ui.layer)
	if ui_manager_node and ui_manager_node is CanvasLayer:
		print("[DIAG] UIManagerNode.layer:", ui_manager_node.layer)
	if menu_ui_layer and menu_ui_layer is CanvasLayer:
		print("[DIAG] MenuUILayer.layer:", menu_ui_layer.layer)

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

func _on_convoy_data_updated(all_convoy_data: Array) -> void:
	var popup = convoy_menu_button.get_popup()
	popup.clear()

	if all_convoy_data.is_empty():
		popup.add_item("No Convoys Available")
		popup.set_item_disabled(0, true)
	else:
		for i in range(all_convoy_data.size()):
			var convoy_data: Dictionary = all_convoy_data[i]
			var convoy_name = convoy_data.get("convoy_name", "Unnamed Convoy")
			var convoy_id = convoy_data.get("convoy_id", "")
			
			popup.add_item(convoy_name, i)
			# Store the actual convoy_id in the item's metadata for later retrieval
			popup.set_item_metadata(i, convoy_id)

	# After updating the list, update the button text based on current selection
	_on_convoy_selection_changed(gdm.get_selected_convoy())

func _on_convoy_selection_changed(selected_convoy_data: Variant) -> void:
	if selected_convoy_data is Dictionary:
		var convoy_name = selected_convoy_data.get("convoy_name", "Unnamed Convoy")
		convoy_menu_button.text = "Convoy: %s" % convoy_name
	else:
		convoy_menu_button.text = "Select Convoy"

func _on_convoy_menu_item_pressed(index: int) -> void:
	var popup = convoy_menu_button.get_popup()
	var convoy_id_variant = popup.get_item_metadata(index)
	if convoy_id_variant:
		var convoy_id_str = str(convoy_id_variant)
		# Tell the GameDataManager to select this convoy.
		# Set allow_toggle to false to ensure selecting from the list always sets the convoy, never deselects.
		gdm.select_convoy_by_id(convoy_id_str, false)
		# Emit a signal to tell the main view to open the corresponding menu.
		emit_signal("convoy_menu_requested", convoy_id_str)

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
