extends Control

# Emitted when the user clicks the back button. MenuManager listens for this.
signal back_requested

# Preload the new panel scene for instancing.
const VendorTradePanel = preload("res://Scenes/VendorTradePanel.tscn")

# Node references using @onready. Paths are relative to the node this script is attached to.
# %NodeName syntax is used for nodes with "unique_name_in_owner" enabled.
# $Path/To/Node is used for direct or indirect children without unique names.
@onready var title_label: Button = $MainVBox/TitleLabel
@onready var vendor_tab_container = %VendorTabContainer
@onready var settlement_content_vbox = %SettlementContentVBox
@onready var back_button = $MainVBox/BackButton

# This will be populated by MenuManager with the specific convoy's data.
var _convoy_data: Dictionary
# This will be populated once the settlement is found.
var _settlement_data: Dictionary
var _all_settlement_data: Array # New: To store all settlement data from GameDataManager

# Add a reference to GameDataManager
var gdm: Node = null

# This function is called by MenuManager to pass the convoy data when the menu is opened.
func initialize_with_data(data: Dictionary):
	print("ConvoySettlementMenu: initialize_with_data called.")
	if not data or not data.has("convoy_id"):
		printerr("ConvoySettlementMenu: Received invalid or empty convoy data.")
		_display_error("No convoy data provided.")
		return

	# Set the main title to the convoy's name
	title_label.text = data.get("convoy_name", "Settlement Interactions")
	_convoy_data = data

	
	# Always defer the display logic to ensure the node is fully ready and in the scene tree,
	# and all @onready variables and their connections are established.
	print("ConvoySettlementMenu: initialize_with_data - Deferring _display_settlement_info.")
	call_deferred("_display_settlement_info")


func _ready():
	print("ConvoySettlementMenu: _ready() started processing.")
	# Fallback assignment if @onready somehow failed (shouldn't happen with proper setup)
	if not is_instance_valid(settlement_content_vbox):
		settlement_content_vbox = get_node_or_null("%SettlementContentVBox")
		if not is_instance_valid(settlement_content_vbox):
			printerr("ConvoySettlementMenu: Failed to re-assign settlement_content_vbox in _ready().")
		else:
			print("ConvoySettlementMenu: _ready() - settlement_content_vbox re-assigned and is valid.")

	# Explicitly check and potentially re-assign vendor_tab_container
	if not is_instance_valid(vendor_tab_container):
		vendor_tab_container = get_node_or_null("%VendorTabContainer")
		if not is_instance_valid(vendor_tab_container):
			printerr("ConvoySettlementMenu: Failed to re-assign vendor_tab_container in _ready().")
		else:
			print("ConvoySettlementMenu: _ready() - vendor_tab_container re-assigned and is valid.")
	
	# Explicitly check if the unique name node is found at _ready()
	if not get_node_or_null("%SettlementContentVBox"):
		printerr("ConvoySettlementMenu: CRITICAL - %SettlementContentVBox not found at _ready(). Check scene setup.")
	# It's crucial to connect signals here for the UI to be interactive.
	if is_instance_valid(back_button):
		back_button.pressed.connect(_on_back_button_pressed)
	else:
		printerr("ConvoySettlementMenu: BackButton node not found.")
	
	# Connect the title label (now a Button) to go back to the convoy menu
	if is_instance_valid(title_label):
		if not title_label.is_connected("pressed", Callable(self, "_on_title_label_pressed")):
			title_label.pressed.connect(_on_title_label_pressed)

	# Connect to GameDataManager signals to refresh UI when data updates
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_gdm_convoy_data_updated")):
			gdm.convoy_data_updated.connect(_on_gdm_convoy_data_updated)
		if not gdm.is_connected("settlement_data_updated", Callable(self, "_on_gdm_settlement_data_updated")):
			gdm.settlement_data_updated.connect(_on_gdm_settlement_data_updated)


func _display_error(message: String):
	_clear_tabs()
	
	if is_instance_valid(settlement_content_vbox):
		# Clear the content of the main settlement info tab
		for child in settlement_content_vbox.get_children():
			child.queue_free()
	else:
		printerr("ConvoySettlementMenu: settlement_content_vbox is invalid when trying to clear children in _display_error().")
		# If settlement_content_vbox is null, we can't add children to it directly.
		# The error message will be displayed in the console.
		return

	

	title_label.text = "Error"
	settlement_content_vbox.add_child(create_info_label(message))
	vendor_tab_container.set_tab_title(0, "Error") # Set title for the first tab (error tab)

func _populate_settlement_info_tab(settlement_data: Dictionary):
	if is_instance_valid(settlement_content_vbox):
		for child in settlement_content_vbox.get_children():
			child.queue_free()
	else:
		printerr("ConvoySettlementMenu: settlement_content_vbox is invalid when trying to populate info tab.")
		return
	
	_add_detail_row(settlement_content_vbox, "Name:", settlement_data.get("name", "Unnamed Settlement"))
	_add_detail_row(settlement_content_vbox, "Type:", settlement_data.get("sett_type", "Unknown Type").capitalize())
	_add_detail_row(settlement_content_vbox, "ID:", settlement_data.get("sett_id", "N/A"))
	# Add more general settlement info here if needed in the future.
	settlement_content_vbox.add_child(create_info_label("\nSelect a vendor tab to see more details."))

func _populate_settlement_info_tab_with_error(message: String):
	if not is_instance_valid(settlement_content_vbox):
		printerr("ConvoySettlementMenu: settlement_content_vbox is invalid when trying to populate error tab.")
		return
	for child in settlement_content_vbox.get_children():
		child.queue_free()
	settlement_content_vbox.add_child(create_info_label(message))


func _display_settlement_info():
	# Ensure GameDataManager is available (it must be an Autoload singleton).
	if not ProjectSettings.has_setting("autoload/GameDataManager"):
		_display_error("GameDataManager singleton not found. Please configure it in Project > Project Settings > Autoload.")
		return
	
	_clear_tabs()

	# Get the convoy's current tile coordinates by rounding its float position.
	# The 'x' and 'y' in convoy_data are interpolated floats. We need integer tile coordinates.
	var current_convoy_x = roundi(_convoy_data.get("x", -1.0))
	var current_convoy_y = roundi(_convoy_data.get("y", -1.0))

	# Get map data directly from the GameDataManager singleton instead of loading it here.
	var gdm = get_node_or_null("/root/GameDataManager")
	if not is_instance_valid(gdm):
		_display_error("GameDataManager node is not valid or not found in the scene tree.")
		return
		
			
	# Fetch all settlement data from GameDataManager
	_all_settlement_data = gdm.get_all_settlements_data()
	if _all_settlement_data.is_empty():
		_populate_settlement_info_tab_with_error("Error: All settlement data not loaded in GameDataManager.")

	var map_tiles = gdm.map_tiles
	if map_tiles.is_empty():
		_populate_settlement_info_tab_with_error("Error: Map data not loaded in GameDataManager.")
		return

	var target_tile = null

	# Direct lookup of the tile using coordinates, which is much more efficient than iterating.
	if current_convoy_y >= 0 and current_convoy_y < map_tiles.size():
		var row_array = map_tiles[current_convoy_y]
		if current_convoy_x >= 0 and current_convoy_x < row_array.size():
			target_tile = row_array[current_convoy_x]

	# Display information based on whether a settlement was found on the tile.
	if target_tile and target_tile.has("settlements") and target_tile.settlements is Array and not target_tile.settlements.is_empty():
		_settlement_data = target_tile.settlements[0] # Assuming we display info for the first settlement.

		_populate_settlement_info_tab(_settlement_data)

		if _settlement_data.has("vendors") and _settlement_data.vendors is Array and not _settlement_data.vendors.is_empty():
			# print("ConvoySettlementMenu: Found ", _settlement_data.vendors.size(), " vendors in settlement.") # Debug line

			for vendor in _settlement_data.vendors:
				_create_vendor_tab(vendor)

	else:
		title_label.text = "Location: (%d, %d)" % [current_convoy_x, current_convoy_y]
		_populate_settlement_info_tab_with_error("No settlement found at convoy coordinates: (%d, %d)" % [current_convoy_x, current_convoy_y])

func _create_vendor_tab(vendor_data: Dictionary):
	var vendor_name = vendor_data.get("name", "Unnamed Vendor")
	var settlement_name = _settlement_data.get("name", "")
	var short_vendor_name = vendor_name
	if not settlement_name.is_empty():
		short_vendor_name = vendor_name.replace(settlement_name + " ", "").strip_edges()

	var vendor_panel_instance = VendorTradePanel.instantiate()

	if not is_instance_valid(vendor_tab_container):
		printerr("ConvoySettlementMenu: vendor_tab_container is NULL in _create_vendor_tab. Check scene and @onready initialization.")
		vendor_panel_instance.queue_free() # Clean up to prevent memory leaks
		return

	# 1. Add the panel to the scene tree. This is crucial because it triggers the panel's
	#    _ready() function, which populates all its @onready variables (like vendor_item_list).
	vendor_tab_container.add_child(vendor_panel_instance)
	vendor_panel_instance.name = vendor_name
	vendor_tab_container.set_tab_title(vendor_tab_container.get_tab_count() - 1, short_vendor_name)
	# Pass deep copies to avoid reference bugs!
	vendor_panel_instance.initialize(
		vendor_data.duplicate(true),
		_convoy_data.duplicate(true),
		_settlement_data.duplicate(true),
		_all_settlement_data.duplicate(true)
	)
	vendor_panel_instance.item_purchased.connect(_on_item_purchased)
	vendor_panel_instance.item_sold.connect(_on_item_sold)

func _clear_tabs():
	# Remove all dynamically added vendor tabs, starting from the end.
	if not is_instance_valid(vendor_tab_container):
		printerr("ConvoySettlementMenu: vendor_tab_container is invalid in _clear_tabs().")
		return
	# We only remove tabs from index 1 onwards, to keep the "Settlement Info" tab.
	for i in range(vendor_tab_container.get_tab_count() - 1, 0, -1):
		var tab = vendor_tab_container.get_child(i)
		vendor_tab_container.remove_child(tab)
		tab.queue_free()

func create_info_label(text: String) -> Label:
	# Helper function to create a new Label node with common properties
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _add_detail_row(parent: Container, label_text: String, value_text: String, value_autowrap: bool = false):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label_node = Label.new()
	label_node.text = label_text
	label_node.custom_minimum_size.x = 150

	var value_node = Label.new()
	value_node.text = value_text
	value_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_node.clip_text = true
	if value_autowrap:
		value_node.autowrap_mode = TextServer.AUTOWRAP_WORD
	
	hbox.add_child(label_node)
	hbox.add_child(value_node)
	parent.add_child(hbox)

func _on_back_button_pressed():
	# MenuManager is connected to this signal and will handle closing the menu.
	emit_signal("back_requested")

func _on_title_label_pressed():
	# When the title (which is now a button) is pressed, go back to the convoy menu.
	print("ConvoySettlementMenu: Title label pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")


# --- Transaction Logic ---

func _on_item_purchased(item: Dictionary, quantity: int, total_cost: float):
	# Only update user money via GameDataManager. Do NOT mutate local convoy/vendor data.
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm) and gdm.has_method("update_user_money"):
		gdm.update_user_money(-total_cost)
	else:
		printerr("ConvoySettlementMenu: Could not update user money. GameDataManager not found or is missing 'update_user_money' method.")
	# Do NOT mutate _convoy_data or vendor data here.
	# Wait for GameDataManager to emit updated data signals, then refresh UI.

func _on_item_sold(item: Dictionary, quantity: int, total_value: float):
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm) and gdm.has_method("update_user_money"):
		gdm.update_user_money(total_value)
	else:
		printerr("ConvoySettlementMenu: Could not update user money. GameDataManager not found or is missing 'update_user_money' method.")
	# Do NOT mutate _convoy_data or vendor data here.
	# Wait for GameDataManager to emit updated data signals, then refresh UI.

func _on_gdm_convoy_data_updated(all_convoys_data: Array) -> void:
	# Find the current convoy and update _convoy_data, then refresh UI
	if not _convoy_data or not _convoy_data.has("convoy_id"):
		return
	var current_id = str(_convoy_data.get("convoy_id"))
	for convoy in all_convoys_data:
		if convoy.has("convoy_id") and str(convoy.get("convoy_id")) == current_id:
			_convoy_data = convoy.duplicate(true)
			_refresh_all_vendor_panels()
			break

func _on_gdm_settlement_data_updated(all_settlements_data: Array) -> void:
	# Find the current settlement and update _settlement_data, then refresh UI
	if not _settlement_data or not _settlement_data.has("sett_id"):
		return
	var current_id = str(_settlement_data.get("sett_id"))
	for settlement in all_settlements_data:
		if settlement.has("sett_id") and str(settlement.get("sett_id")) == current_id:
			_settlement_data = settlement.duplicate(true)
			_refresh_all_vendor_panels()
			break

func _refresh_all_vendor_panels():
	# Only call refresh_data, never initialize, and always pass deep copies
	for i in range(vendor_tab_container.get_tab_count()):
		var tab_content = vendor_tab_container.get_tab_control(i)
		if tab_content is Control and tab_content.has_method("refresh_data"):
			var full_vendor_name = tab_content.name
			var vendor_data = _find_vendor_by_name(full_vendor_name)
			if vendor_data:
				tab_content.refresh_data(
					vendor_data.duplicate(true),
					_convoy_data.duplicate(true),
					_settlement_data.duplicate(true),
					_all_settlement_data.duplicate(true)
				)

func _find_vendor_by_name(vendor_name: String) -> Dictionary:
	if _settlement_data and _settlement_data.has("vendors"):
		for vendor in _settlement_data.vendors:
			if vendor.get("name", "") == vendor_name:
				return vendor
	return {}
