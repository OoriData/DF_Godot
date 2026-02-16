extends VBoxContainer


@onready var toggle_button: Button = $ToggleButton
@onready var convoy_popup: PopupPanel = %ConvoyPopup
@onready var list_item_container: VBoxContainer = %ConvoyItemsContainer

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

func _ready():
	# More robust node checks.
	if not is_instance_valid(toggle_button) or not is_instance_valid(convoy_popup) or not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: One or more required child nodes are missing. Check scene setup.")
		return

	# Set mouse filter to STOP so this panel receives mouse input (for dropdowns/buttons)
	mouse_filter = Control.MOUSE_FILTER_STOP

	toggle_button.pressed.connect(_on_toggle_button_pressed)
	# The popup hides itself when focus is lost. We connect to its signal to update our button.
	convoy_popup.popup_hide.connect(_on_popup_hide)

	# Attempt to connect to MenuManager's signal to auto-close this panel.
	# Since MenuManager is an Autoload, it's globally available.
	var menu_manager_node = get_node_or_null("/root/MenuManager")
	if is_instance_valid(menu_manager_node):
		if menu_manager_node.has_signal("menu_opened"):
			menu_manager_node.menu_opened.connect(_on_main_menu_opened)
		else:
			printerr("ConvoyListPanel: MenuManager found but does not have 'menu_opened' signal.")
	else:
		# The warning message is updated to reflect the new expected structure.
		printerr("ConvoyListPanel: MenuManager Autoload node not found. Cannot auto-close on menu open. Check Project Settings -> Autoload.")

	# Subscribe to canonical snapshots + selection bus
	if is_instance_valid(_store) and _store.has_signal("convoys_changed"):
		if not _store.convoys_changed.is_connected(_on_convoy_data_updated):
			_store.convoys_changed.connect(_on_convoy_data_updated)
		if _store.has_method("get_convoys"):
			var convoys_now: Array = _store.get_convoys()
			if not convoys_now.is_empty():
				populate_convoy_list(convoys_now)

	if is_instance_valid(_hub) and _hub.has_signal("convoy_selection_changed"):
		if not _hub.convoy_selection_changed.is_connected(_on_convoy_selection_changed):
			_hub.convoy_selection_changed.connect(_on_convoy_selection_changed)

	# Setup styling for toggle button if it exists
	if is_instance_valid(toggle_button):
		# Ensure button has a reasonable minimum size since we're clearing its text
		toggle_button.custom_minimum_size = Vector2(200, 36)
		toggle_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		# We'll use a RichTextLabel child for BBCode styling on the button
		var rtl = RichTextLabel.new()
		rtl.name = "StyleLabel"
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		# Using full rect so [center] has the button width to work with
		rtl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rtl.offset_top = 4 # Vertical offset for centering
		rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		toggle_button.add_child(rtl)
		toggle_button.text = "" # Use child for display
		
	# Initialize display
	_update_toggle_button_display(false)

func _on_toggle_button_pressed() -> void:
	if not is_instance_valid(convoy_popup) or not is_instance_valid(toggle_button):
		printerr("ConvoyListPanel: Critical nodes missing in _on_toggle_button_pressed.")
		return

	# If it was just hidden via focus loss (like clicking the button itself), 
	# we don't want to immediately redeploy.
	if Time.get_ticks_msec() - _last_hide_ms < 100:
		return

	if convoy_popup.is_visible():
		convoy_popup.hide()
	else:
		var item_count = max(1, list_item_container.get_child_count()) # Avoid 0
		var popup_height = clamp(item_count * 30 + 10, 50, 300) # e.g., 30px per item + padding
		convoy_popup.size = Vector2(toggle_button.size.x, popup_height)


		# Use popup(Rect2i) for robust positioning in Godot 4.
		# This positions the popup relative to the viewport, using global coordinates.
		var button_rect = toggle_button.get_global_rect()
		# Position the popup to start at the bottom-left of the button.
		var popup_position = Vector2(button_rect.position.x, button_rect.end.y)
		convoy_popup.popup(Rect2i(popup_position, convoy_popup.size))

		# Update button display to show it's open
		_update_toggle_button_display(true)

func _on_popup_hide() -> void:
	"""Called when the PopupPanel is hidden for any reason (selection, clicked away)."""
	_last_hide_ms = Time.get_ticks_msec()
	# Update button display to show it's closed
	_update_toggle_button_display(false)

var _last_hide_ms: int = 0

func close_list():
	"""Closes the convoy list if it's open."""
	if convoy_popup.is_visible():
		convoy_popup.hide()

func _on_main_menu_opened(_menu_node, _menu_type: String):
	# If a menu from MenuManager opens, and our panel is currently expanded, close it.
	if convoy_popup.is_visible():
		close_list()

## Populates the list with convoy data.
func populate_convoy_list(convoys_data: Array) -> void:
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger) and logger.has_method("info"):
		logger.info("ConvoyListPanel.populate count=%s visible=%s", convoys_data.size(), visible)
	else:
		print("ConvoyListPanel: populate_convoy_list() called. Visible:", visible, "Parent:", get_parent())

	# Diagnostic: Print node tree under ConvoyItemsContainer to help debug UI population issues
	if is_instance_valid(list_item_container):
		print("ConvoyListPanel: ConvoyItemsContainer children:")
		for child in list_item_container.get_children():
			print("  -", child.name, "type:", child.get_class())
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: populate_convoy_list - list_item_container node not found or invalid. Check unique name in scene.")
		return

	# Clear existing items
	for child in list_item_container.get_children():
		child.queue_free()

	if convoys_data.is_empty():
		var no_convoys_label = Label.new()
		no_convoys_label.text = "No convoys available."
		no_convoys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_item_container.add_child(no_convoys_label)
		return

	for convoy_item_data in convoys_data:
		if not convoy_item_data is Dictionary:
			printerr("ConvoyListPanel: Invalid convoy data item: ", convoy_item_data)
			continue

		var convoy_id = convoy_item_data.get("convoy_id", convoy_item_data.get("id", "N/A"))
		var convoy_name = convoy_item_data.get("convoy_name", convoy_item_data.get("name", "Unknown Convoy"))

		var item_button = Button.new()
		item_button.name = "ConvoyButton_%s" % str(convoy_id)
		item_button.custom_minimum_size = Vector2(0, 32)
		item_button.clip_contents = true
		item_button.text = "" # Clear default text
		
		var hbox = HBoxContainer.new()
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		hbox.add_theme_constant_override("separation", 8)
		# Add margins so text isn't flush with button edge
		var margin = 8
		hbox.offset_left = margin
		hbox.offset_right = -margin
		item_button.add_child(hbox)

		var name_label = Label.new()
		name_label.text = convoy_name
		name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0)) # Bright White
		hbox.add_child(name_label)
		
		var journey: Variant = convoy_item_data.get("journey")
		if journey is Dictionary and not (journey as Dictionary).is_empty():
			var j_dict := journey as Dictionary
			var dest_x = j_dict.get("dest_x")
			var dest_y = j_dict.get("dest_y")
			var dest_name = _get_settlement_name(dest_x, dest_y)
			
			var progress: float = j_dict.get("progress", 0.0)
			var length: float = j_dict.get("length", 0.0)
			var progress_percentage := 0.0
			if length > 0.001:
				progress_percentage = (progress / length) * 100.0
			
			var dest_label = Label.new()
			dest_label.text = "to %s" % dest_name
			dest_label.add_theme_color_override("font_color", Color(0.16, 0.71, 0.96)) # Cyan
			dest_label.add_theme_font_size_override("font_size", 15)
			hbox.add_child(dest_label)
			
			var prog_label = Label.new()
			prog_label.text = "(%.0f%%)" % progress_percentage
			prog_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4)) # Light Yellow
			prog_label.add_theme_font_size_override("font_size", 14)
			hbox.add_child(prog_label)

		# Connect the button's pressed signal to a local handler, binding the full convoy_item_data
		item_button.pressed.connect(_on_convoy_item_pressed.bind(convoy_item_data))
		list_item_container.add_child(item_button)

func _get_settlement_name(coord_x, coord_y) -> String:
	if not is_instance_valid(_store) or not _store.has_method("get_settlements"):
		return "Unknown"
	if coord_x == null or coord_y == null:
		return "Unknown"
		
	var x_int := roundi(float(coord_x))
	var y_int := roundi(float(coord_y))
	for s in _store.get_settlements():
		if s is Dictionary:
			var sx := int((s as Dictionary).get("x", -9999))
			var sy := int((s as Dictionary).get("y", -9999))
			if sx == x_int and sy == y_int:
				var settlement_name := str((s as Dictionary).get("name", "Unknown"))
				return settlement_name if settlement_name != "" else "Unknown"
	return "Uncharted Location"

func _on_convoy_item_pressed(convoy_item_data: Dictionary) -> void:
	if not is_instance_valid(convoy_popup) or not is_instance_valid(toggle_button):
		printerr("ConvoyListPanel: Critical nodes missing in _on_convoy_item_pressed.")
		return

	# Tell the canonical selection bus about the intent.
	if is_instance_valid(_hub) and _hub.has_signal("convoy_selection_requested"):
		_hub.convoy_selection_requested.emit(str(convoy_item_data.get("convoy_id", "")), false)

	# Close the list after an item is selected
	close_list()

# Add this handler to update the list when convoy data changes
func _on_convoy_data_updated(all_convoy_data: Array) -> void:
	populate_convoy_list(all_convoy_data)
	# Selection highlight updates on convoy_selection_changed.


# NEW: Handles updates when the globally selected convoy changes.
func _on_convoy_selection_changed(selected_convoy_data: Variant) -> void:
	# NEW: Store current data for re-renders with chevron changes
	_last_selected_convoy_data = selected_convoy_data
	_update_toggle_button_display(convoy_popup.is_visible() if is_instance_valid(convoy_popup) else false)

	var convoy_id_str: String = ""
	if selected_convoy_data and selected_convoy_data.has("convoy_id"):
		convoy_id_str = str(selected_convoy_data.get("convoy_id"))
	
	# Highlight the corresponding item in the list
	highlight_convoy_in_list(convoy_id_str)

var _last_selected_convoy_data: Variant = null

func _update_toggle_button_display(is_open: bool) -> void:
	if not is_instance_valid(toggle_button):
		return
		
	var arrow = "[color=gray]%s[/color]" % ("▲" if is_open else "▼")
	var display_text = "Select Convoy %s" % arrow
	
	if _last_selected_convoy_data and _last_selected_convoy_data is Dictionary and _last_selected_convoy_data.has("convoy_id"):
		var convoy_name = _last_selected_convoy_data.get("convoy_name", _last_selected_convoy_data.get("name", "Unnamed Convoy"))
		var status_text = ""
		var journey: Variant = _last_selected_convoy_data.get("journey")
		if journey is Dictionary and not (journey as Dictionary).is_empty():
			var j_dict := journey as Dictionary
			var dest_x = j_dict.get("dest_x")
			var dest_y = j_dict.get("dest_y")
			var dest_name = _get_settlement_name(dest_x, dest_y)
			status_text = " [font_size=15][color=#29b6f6]to %s[/color][/font_size]" % dest_name
		
		display_text = "%s%s %s" % [convoy_name, status_text, arrow]
	
	# Center the text using BBCode [center]
	var styled_text = "[center]%s[/center]" % display_text
	
	var rtl = toggle_button.get_node_or_null("StyleLabel")
	if is_instance_valid(rtl) and rtl is RichTextLabel:
		rtl.text = styled_text
	else:
		toggle_button.text = display_text.replace("[color=gray]", "").replace("[/color]", "").replace("[color=#29b6f6]", "")

## Highlights a specific convoy in the list.
## Call this from main.gd when a convoy is selected on the map.
func highlight_convoy_in_list(selected_convoy_id_str: String) -> void:
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: highlight_convoy_in_list - list_item_container node not found or invalid. Check unique name in scene.")
		return

	for child in list_item_container.get_children():
		if child is Button: # Or your custom item type
			# A more robust way is to check the name or metadata set during creation
			if child.name == "ConvoyButton_%s" % selected_convoy_id_str:
				child.modulate = Color.LIGHT_SKY_BLUE # Highlight color
			else:
				child.modulate = Color.WHITE # Reset others
