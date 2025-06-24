extends Control

# Emitted when the user clicks the back button. MenuManager listens for this.
signal back_requested

# Node references using @onready. Paths are relative to the node this script is attached to.
# %NodeName syntax is used for nodes with "unique_name_in_owner" enabled.
# $Path/To/Node is used for direct or indirect children without unique names.
@onready var title_label = $MainVBox/TitleLabel
@onready var vendor_tab_container = %VendorTabContainer
@onready var settlement_content_vbox = %SettlementContentVBox
@onready var back_button = $MainVBox/BackButton

# This will be populated by MenuManager with the specific convoy's data.
var _convoy_data: Dictionary
# This will be populated once the settlement is found.
var _settlement_data: Dictionary

# This function is called by MenuManager to pass the convoy data when the menu is opened.
func initialize_with_data(data: Dictionary):
	# This function is now connected to the 'ready' signal by MenuManager,
	# so we can be sure that all @onready variables are initialized.
	print("ConvoySettlementMenu: initialize_with_data called.")
	if not data or not data.has("convoy_id"):
		printerr("ConvoySettlementMenu: Received invalid or empty convoy data.")
		_display_error("No convoy data provided.")
		return
	
	_convoy_data = data
	_display_settlement_info()


func _ready():
	# Connect the back button's "pressed" signal to a handler function
	back_button.pressed.connect(_on_back_button_pressed)
	# Connect to the tab changed signal for lazy loading of vendor info
	vendor_tab_container.tab_changed.connect(_on_vendor_tab_changed)


func _display_error(message: String):
	_clear_tabs()
	
	# Clear the content of the main settlement info tab
	for child in settlement_content_vbox.get_children():
		child.queue_free()
	
	title_label.text = "Error"
	settlement_content_vbox.add_child(create_info_label(message))
	vendor_tab_container.set_tab_title(0, "Error") # Set title for the first tab (error tab)

func _populate_settlement_info_tab(settlement_data: Dictionary):
	for child in settlement_content_vbox.get_children():
		child.queue_free()
	
	_add_detail_row(settlement_content_vbox, "Type:", settlement_data.get("sett_type", "Unknown Type").capitalize())
	_add_detail_row(settlement_content_vbox, "ID:", settlement_data.get("sett_id", "N/A"))
	# Add more general settlement info here if needed in the future.
	settlement_content_vbox.add_child(create_info_label("\nSelect a vendor tab to see more details."))

func _populate_settlement_info_tab_with_error(message: String):
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
	var map_tiles = GameDataManager.map_tiles
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

		# Update title with settlement name
		title_label.text = _settlement_data.get("name", "Unnamed Settlement")

		_populate_settlement_info_tab(_settlement_data)

		if _settlement_data.has("vendors") and _settlement_data.vendors is Array and not _settlement_data.vendors.is_empty():
			print("ConvoySettlementMenu: Found ", _settlement_data.vendors.size(), " vendors in settlement.")

			for vendor in _settlement_data.vendors:
				_create_vendor_tab(vendor)
				print("ConvoySettlementMenu: Successfully created and added tab for vendor: ", vendor.get("name", "Unnamed Vendor"))
		
		# Manually trigger the changed signal for the initially selected tab to populate it.
		if vendor_tab_container.get_tab_count() > 0:
			_on_vendor_tab_changed(vendor_tab_container.current_tab)
			print("ConvoySettlementMenu: Triggered initial tab population for tab index ", vendor_tab_container.current_tab)


	else:
		title_label.text = "Location: (%d, %d)" % [current_convoy_x, current_convoy_y]
		_populate_settlement_info_tab_with_error("No settlement found at your current coordinates: (%d, %d)" % [current_convoy_x, current_convoy_y])

func _create_vendor_tab(vendor_data: Dictionary):
	var vendor_name = vendor_data.get("name", "Unnamed Vendor")
	
	var scroll_container = ScrollContainer.new()
	scroll_container.name = vendor_name
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.set_meta("vendor_data", vendor_data)
	scroll_container.set_meta("is_populated", false) # For lazy loading

	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 8)
	scroll_container.add_child(content_vbox)
	
	vendor_tab_container.add_child(scroll_container) # Add the new ScrollContainer as a child
	vendor_tab_container.set_tab_title(vendor_tab_container.get_tab_count() - 1, vendor_name) # Explicitly set the tab title
	
func _on_vendor_tab_changed(tab_idx: int):
	var tab_control = vendor_tab_container.get_tab_control(tab_idx)
	if not is_instance_valid(tab_control):
		return
	
	# Check if it's a vendor tab (has metadata) and if it's not already populated
	if tab_control.has_meta("vendor_data") and not tab_control.get_meta("is_populated", false):
		var vendor_data = tab_control.get_meta("vendor_data")
		# The tab_control is the ScrollContainer. Its first child is the VBoxContainer for content.
		if tab_control.get_child_count() > 0:
			var content_vbox = tab_control.get_child(0)
			if content_vbox is VBoxContainer:
				_populate_vendor_tab(content_vbox, vendor_data)
				tab_control.set_meta("is_populated", true)

func _populate_vendor_tab(parent_vbox: VBoxContainer, vendor_data: Dictionary):
	# Clear any placeholder content
	for child in parent_vbox.get_children():
		child.queue_free()

	# Vendor Description
	var desc = vendor_data.get("base_desc", "No description available.")
	if desc.is_empty():
		desc = "No description available."
	_add_detail_row(parent_vbox, "Description:", desc, true)
	
	# Money
	_add_detail_row(parent_vbox, "Money:", "$%s" % vendor_data.get("money", 0))

	# Separator
	var separator1 = HSeparator.new()
	separator1.custom_minimum_size.y = 10
	parent_vbox.add_child(separator1)

	# Resources Section
	var resources_title = Label.new()
	resources_title.text = "Resources & Services"
	resources_title.add_theme_font_size_override("font_size", 18)
	parent_vbox.add_child(resources_title)

	var has_resources = false
	if vendor_data.get("fuel", 0) > 0:
		_add_detail_row(parent_vbox, "  Fuel Stock:", "%d L @ $%d/L" % [vendor_data.fuel, vendor_data.get("fuel_price", 0)])
		has_resources = true
	if vendor_data.get("water", 0) > 0:
		_add_detail_row(parent_vbox, "  Water Stock:", "%d L @ $%d/L" % [vendor_data.water, vendor_data.get("water_price", 0)])
		has_resources = true
	if vendor_data.get("food", 0) > 0:
		_add_detail_row(parent_vbox, "  Food Stock:", "%d units @ $%d/unit" % [vendor_data.food, vendor_data.get("food_price", 0)])
		has_resources = true
	if vendor_data.get("repair_price", 0) > 0:
		_add_detail_row(parent_vbox, "  Repair Service:", "$%d per point" % vendor_data.get("repair_price"))
		has_resources = true
	
	if not has_resources:
		parent_vbox.add_child(create_info_label("  No resources or services available."))

	# Separator
	var separator2 = HSeparator.new()
	separator2.custom_minimum_size.y = 10
	parent_vbox.add_child(separator2)

	# Inventories Section
	var inventory_title = Label.new()
	inventory_title.text = "Inventories"
	inventory_title.add_theme_font_size_override("font_size", 18)
	parent_vbox.add_child(inventory_title)

	var cargo_inventory = vendor_data.get("cargo_inventory", [])
	var vehicle_inventory = vendor_data.get("vehicle_inventory", [])

	_add_detail_row(parent_vbox, "  Cargo Items:", "%d items" % cargo_inventory.size())
	_add_detail_row(parent_vbox, "  Vehicles for Sale:", "%d vehicles" % vehicle_inventory.size())

func _clear_tabs():
	# Remove all dynamically added vendor tabs, starting from the end.
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
