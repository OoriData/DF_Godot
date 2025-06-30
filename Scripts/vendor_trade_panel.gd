extends Control

# Signals to notify the main menu of transactions
signal item_purchased(item, quantity, total_price)
signal item_sold(item, quantity, total_price)

# --- Node References ---
@onready var vendor_item_tree: Tree = %VendorItemTree
@onready var convoy_item_tree: Tree = %ConvoyItemTree
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_preview: TextureRect = %ItemPreview
@onready var item_info_rich_text: RichTextLabel = %ItemInfoRichText
@onready var comparison_panel: PanelContainer = %ComparisonPanel
@onready var description_toggle_button: Button = %DescriptionToggleButton
@onready var item_description_rich_text: RichTextLabel = %ItemDescriptionRichText
@onready var selected_item_stats: RichTextLabel = %SelectedItemStats
@onready var equipped_item_stats: RichTextLabel = %EquippedItemStats
@onready var quantity_spinbox: SpinBox = %QuantitySpinBox
@onready var price_label: RichTextLabel = %PriceLabel
@onready var max_button: Button = %MaxButton
@onready var action_button: Button = %ActionButton
@onready var convoy_money_label: Label = %ConvoyMoneyLabel
@onready var convoy_cargo_label: Label = %ConvoyCargoLabel
@onready var trade_mode_tab_container: TabContainer = %TradeModeTabContainer

# --- Data ---
var vendor_data # Should be set by the parent
var convoy_data # Should be set by the parent
var gdm: Node # GameDataManager instance
var current_settlement_data # Will hold the current settlement data for local vendor lookup
var all_settlement_data_global: Array # New: Will hold all settlement data for global vendor lookup
var selected_item = null
var current_mode = "buy" # or "sell"

func _ready() -> void:
	# Connect signals from UI elements
	vendor_item_tree.item_selected.connect(_on_vendor_item_selected)
	# Use item_selected for Tree to update the inspector on a single click.
	convoy_item_tree.item_selected.connect(_on_convoy_item_selected)
	trade_mode_tab_container.tab_changed.connect(_on_tab_changed)

	if is_instance_valid(max_button):
		max_button.pressed.connect(_on_max_button_pressed)
	else:
		printerr("VendorTradePanel: 'MaxButton' node not found. Please check the scene file.")

	if is_instance_valid(action_button):
		action_button.pressed.connect(_on_action_button_pressed)
	else:
		printerr("VendorTradePanel: 'ActionButton' node not found. Please check the scene file.")

	quantity_spinbox.value_changed.connect(_on_quantity_changed)
	if is_instance_valid(description_toggle_button):
		description_toggle_button.pressed.connect(_on_description_toggle_pressed)
	else:
		printerr("VendorTradePanel: 'DescriptionToggleButton' node not found. Please check the scene file.")

	# Get GameDataManager and connect to its signal to keep user money updated.
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("user_data_updated", _on_user_data_updated):
			gdm.user_data_updated.connect(_on_user_data_updated)
	else:
		printerr("VendorTradePanel: Could not find GameDataManager.")

	# Initially hide comparison panel until an item is selected
	comparison_panel.hide()
	if is_instance_valid(action_button):
		action_button.disabled = true
	if is_instance_valid(max_button):
		max_button.disabled = true

# Public method to initialize the panel with data
func initialize(p_vendor_data, p_convoy_data, p_current_settlement_data, p_all_settlement_data_global) -> void:
	self.vendor_data = p_vendor_data
	self.convoy_data = p_convoy_data
	self.current_settlement_data = p_current_settlement_data # Store the current settlement data
	self.all_settlement_data_global = p_all_settlement_data_global # Store the global settlement data
	
	_populate_vendor_list()
	_populate_convoy_list()
	_update_convoy_info_display()
	_on_tab_changed(trade_mode_tab_container.current_tab)

# --- UI Population ---
func _populate_vendor_list() -> void:
	vendor_item_tree.clear()
	if not vendor_data:
		return

	var aggregated_missions: Dictionary = {}
	var aggregated_resources: Dictionary = {}
	var aggregated_vehicles: Dictionary = {}
	var aggregated_other: Dictionary = {}

	for item in vendor_data.get("cargo_inventory", []):
		if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
			continue

		var category_dict: Dictionary
		var mission_vendor_name: String = ""
		if item.get("recipient") != null:
			category_dict = aggregated_missions
			var recipient_id = item.get("recipient")
			if recipient_id:
				mission_vendor_name = _get_vendor_name_for_recipient(recipient_id)
		elif (item.has("food") and item.get("food") != null and item.get("food") > 0) or \
		   (item.has("water") and item.get("water") != null and item.get("water") > 0) or \
		   (item.has("fuel") and item.get("fuel") != null and item.get("fuel") > 0):
			category_dict = aggregated_resources
		else:
			category_dict = aggregated_other
		
		_aggregate_vendor_item(category_dict, item, mission_vendor_name)

	# --- Create virtual items for raw resources AFTER processing normal cargo ---
	if vendor_data.get("fuel", 0) > 0 and vendor_data.get("fuel_price", 0) > 0:
		var fuel_quantity = vendor_data.get("fuel")
		var fuel_item = {
			"name": "Fuel (Bulk)",
			"base_desc": "Bulk fuel to fill your containers.",
			"quantity": fuel_quantity,
			"fuel": fuel_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, fuel_item)

	if vendor_data.get("water", 0) > 0 and vendor_data.get("water_price", 0) > 0:
		var water_quantity = vendor_data.get("water")
		var water_item = {
			"name": "Water (Bulk)",
			"base_desc": "Bulk water to fill your containers.",
			"quantity": water_quantity,
			"water": water_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, water_item)

	if vendor_data.get("food", 0) > 0 and vendor_data.get("food_price", 0) > 0:
		var food_quantity = vendor_data.get("food")
		var food_item = {
			"name": "Food (Bulk)",
			"base_desc": "Bulk food supplies.",
			"quantity": food_quantity,
			"food": food_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, food_item)

	# Process vehicles into their own category
	for vehicle in vendor_data.get("vehicle_inventory", []):
		_aggregate_vendor_item(aggregated_vehicles, vehicle)

	var root = vendor_item_tree.create_item()
	_populate_category(vendor_item_tree, root, "Mission Cargo", aggregated_missions)
	_populate_category(vendor_item_tree, root, "Vehicles", aggregated_vehicles)
	_populate_category(vendor_item_tree, root, "Other", aggregated_other)
	_populate_category(vendor_item_tree, root, "Resources", aggregated_resources)

func _populate_convoy_list() -> void:
	convoy_item_tree.clear()
	if not convoy_data or not convoy_data.has("vehicle_details_list"):
		return

	var aggregated_missions: Dictionary = {}
	var aggregated_resources: Dictionary = {}
	var aggregated_parts: Dictionary = {}
	var aggregated_other: Dictionary = {}

	# Aggregate items from all vehicles to create a de-duplicated list.
	for vehicle in convoy_data.vehicle_details_list:
		var vehicle_name = vehicle.get("name", "Unknown Vehicle")
		
		# Process standard cargo
		for item in vehicle.get("cargo", []):
			# If an item has a non-null intrinsic_part_id, it's a core component
			# of the vehicle (like a battery) and should not be considered sellable cargo.
			if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
				continue # Skip this item and move to the next one.

			var category_dict: Dictionary
			var mission_vendor_name: String = "" # Initialize for mission cargo
			if item.get("recipient") != null or item.get("delivery_reward") != null:
				category_dict = aggregated_missions
			elif (item.has("food") and item.get("food") != null and item.get("food") > 0) or \
				 (item.has("water") and item.get("water") != null and item.get("water") > 0) or \
				 (item.has("fuel") and item.get("fuel") != null and item.get("fuel") > 0):
				category_dict = aggregated_resources
			else:
				category_dict = aggregated_other

			# If it's mission cargo, try to find the vendor name
			if category_dict == aggregated_missions:
				var recipient_id = item.get("recipient")
				if recipient_id:
					mission_vendor_name = _get_vendor_name_for_recipient(recipient_id)
			
			_aggregate_item(category_dict, item, vehicle_name, mission_vendor_name)

		# Process parts
		for item in vehicle.get("parts", []):
			if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
				continue
			_aggregate_item(aggregated_parts, item, vehicle_name) # Parts don't have mission vendors

	# --- Create virtual items for convoy's bulk resources AFTER processing normal cargo ---
	# Only show sell option if the convoy has the resource AND the vendor is buying it (price > 0)
	if convoy_data.get("fuel", 0) > 0 and vendor_data.get("fuel_price", 0) > 0:
		var fuel_quantity = convoy_data.get("fuel")
		var fuel_item = {
			"name": "Fuel (Bulk)",
			"base_desc": "Bulk fuel from your convoy's reserves.",
			"quantity": fuel_quantity,
			"fuel": fuel_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, fuel_item)

	if convoy_data.get("water", 0) > 0 and vendor_data.get("water_price", 0) > 0:
		var water_quantity = convoy_data.get("water")
		var water_item = {
			"name": "Water (Bulk)",
			"base_desc": "Bulk water from your convoy's reserves.",
			"quantity": water_quantity,
			"water": water_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, water_item)

	if convoy_data.get("food", 0) > 0 and vendor_data.get("food_price", 0) > 0:
		var food_quantity = convoy_data.get("food")
		var food_item = {
			"name": "Food (Bulk)",
			"base_desc": "Bulk food supplies from your convoy's reserves.",
			"quantity": food_quantity,
			"food": food_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, food_item)

	# --- POPULATION ---
	var root = convoy_item_tree.create_item()
	_populate_category(convoy_item_tree, root, "Mission Cargo", aggregated_missions)
	_populate_category(convoy_item_tree, root, "Parts", aggregated_parts)
	_populate_category(convoy_item_tree, root, "Other", aggregated_other)
	_populate_category(convoy_item_tree, root, "Resources", aggregated_resources)

func _aggregate_vendor_item(agg_dict: Dictionary, item: Dictionary, p_mission_vendor_name: String = "") -> void:
	var item_name = item.get("name", "Unknown Item")
	if not agg_dict.has(item_name):
		agg_dict[item_name] = {"item_data": item, "total_quantity": 0, "total_weight": 0.0, "total_volume": 0.0, "total_food": 0.0, "total_water": 0.0, "total_fuel": 0.0, "mission_vendor_name": p_mission_vendor_name}
	
	var item_quantity = int(item.get("quantity", 1.0))
	agg_dict[item_name].total_quantity += item_quantity
	agg_dict[item_name].total_weight += item.get("weight", 0.0)
	agg_dict[item_name].total_volume += item.get("volume", 0.0)
	if item.get("food") is float or item.get("food") is int: agg_dict[item_name].total_food += item.get("food")
	if item.get("water") is float or item.get("water") is int: agg_dict[item_name].total_water += item.get("water")
	if item.get("fuel") is float or item.get("fuel") is int: agg_dict[item_name].total_fuel += item.get("fuel")
	
func _aggregate_item(agg_dict: Dictionary, item: Dictionary, vehicle_name: String, p_mission_vendor_name: String = "") -> void:
	var item_name = item.get("name", "Unknown Item")
	if not agg_dict.has(item_name):
		agg_dict[item_name] = {"item_data": item, "total_quantity": 0, "locations": {}, "mission_vendor_name": p_mission_vendor_name, "total_weight": 0.0, "total_volume": 0.0, "total_food": 0.0, "total_water": 0.0, "total_fuel": 0.0}
	
	var item_quantity = int(item.get("quantity", 1.0))
	agg_dict[item_name].total_quantity += item_quantity
	agg_dict[item_name].total_weight += item.get("weight", 0.0)
	agg_dict[item_name].total_volume += item.get("volume", 0.0)
	if item.get("food") is float or item.get("food") is int: agg_dict[item_name].total_food += item.get("food")
	if item.get("water") is float or item.get("water") is int: agg_dict[item_name].total_water += item.get("water")
	if item.get("fuel") is float or item.get("fuel") is int: agg_dict[item_name].total_fuel += item.get("fuel")

	if not agg_dict[item_name].locations.has(vehicle_name):
		agg_dict[item_name].locations[vehicle_name] = 0
	agg_dict[item_name].locations[vehicle_name] += item_quantity

func _update_convoy_info_display() -> void:
	# This function now updates both the user's money and the convoy's cargo stats.
	if not is_node_ready(): return

	# Update User Money from GameDataManager
	if is_instance_valid(gdm):
		var user_data = gdm.get_current_user_data()
		var money_amount = user_data.get("money", 0)
		convoy_money_label.text = "Money: %s" % _format_money(money_amount)
	else:
		convoy_money_label.text = "Money: N/A"

	# Update Convoy Cargo from local convoy_data
	if convoy_data:
		var used_volume = convoy_data.get("total_cargo_capacity", 0.0) - convoy_data.get("total_free_space", 0.0)
		var total_volume = convoy_data.get("total_cargo_capacity", 0.0)
		convoy_cargo_label.text = "Cargo: %.1f / %.1f" % [used_volume, total_volume]
	else:
		convoy_cargo_label.text = "Cargo: N/A"

func _on_user_data_updated(user_data: Dictionary):
	# When user data changes (e.g., after a transaction), refresh the display.
	_update_convoy_info_display()

# --- Signal Handlers ---
func _on_tab_changed(tab_index: int) -> void:
	current_mode = "buy" if tab_index == 0 else "sell"
	action_button.text = "Buy" if current_mode == "buy" else "Sell"
	
	# Clear selection and inspector when switching tabs
	selected_item = null
	if vendor_item_tree.get_selected():
		vendor_item_tree.get_selected().deselect(0)
	if convoy_item_tree.get_selected():
		convoy_item_tree.get_selected().deselect(0)
	_clear_inspector()
	if is_instance_valid(action_button):
		action_button.disabled = true
	if is_instance_valid(max_button):
		max_button.disabled = true

func _on_vendor_item_selected() -> void:
	var tree_item = vendor_item_tree.get_selected()
	if tree_item and tree_item.get_metadata(0) != null:
		var item = tree_item.get_metadata(0)
		_handle_new_item_selection(item)
	else:
		_handle_new_item_selection(null)

func _on_convoy_item_selected() -> void:
	var tree_item = convoy_item_tree.get_selected()
	if tree_item and tree_item.get_metadata(0) != null:
		var item = tree_item.get_metadata(0)
		_handle_new_item_selection(item)
	else:
		# This happens if a category header is clicked, or selection is cleared
		_handle_new_item_selection(null)

func _populate_category(target_tree: Tree, root_item: TreeItem, category_name: String, agg_dict: Dictionary) -> void:
	if agg_dict.is_empty():
		return

	var category_item = target_tree.create_item(root_item)
	category_item.set_text(0, category_name)
	category_item.set_selectable(0, false)
	category_item.set_custom_color(0, Color.GOLD)

	# By default, collapse all categories except for "Mission Cargo".
	if category_name != "Mission Cargo":
		category_item.collapsed = true

	for item_name in agg_dict:
		var agg_data = agg_dict[item_name]
		var display_text = "%s (x%d)" % [item_name, agg_data.total_quantity]
		# Append vendor name for Mission Cargo items
		if category_name == "Mission Cargo" and agg_data.has("mission_vendor_name") and not agg_data.mission_vendor_name.is_empty() and agg_data.mission_vendor_name != "Unknown Vendor":
			display_text += " (To: %s)" % agg_data.mission_vendor_name
		
		var item_icon = agg_data.item_data.get("icon") if agg_data.item_data.has("icon") else null
		var tree_child_item = target_tree.create_item(category_item)
		tree_child_item.set_text(0, display_text)

		# For raw resource items, remove the color and use a bold font instead.
		if agg_data.item_data.get("is_raw_resource", false):
			var default_font = target_tree.get_theme_font("font")
			if default_font:
				var bold_font = FontVariation.new()
				bold_font.set_base_font(default_font)
				bold_font.set_variation_embolden(1.0)
				tree_child_item.set_custom_font(0, bold_font)

		if item_icon:
			tree_child_item.set_icon(0, item_icon)
		tree_child_item.set_metadata(0, agg_data)

func _handle_new_item_selection(p_selected_item) -> void:
	selected_item = p_selected_item
	
	# DEBUG: Print the raw selected item data
	print("DEBUG: _handle_new_item_selection - selected_item (aggregated): ", selected_item)

	
	if selected_item:
		# When selling or buying, cap the quantity to what is available.
		if current_mode == "sell" or current_mode == "buy":
			quantity_spinbox.max_value = selected_item.get("total_quantity", 99)
		else:
			quantity_spinbox.max_value = 99 # Fallback
		quantity_spinbox.value = 1 # Reset to 1 on new selection

		_update_inspector()
		_update_comparison()
		
		# DEBUG: Print item_data_source after it's determined in _update_inspector
		var item_data_source_debug = selected_item.get("item_data", {})
		print("DEBUG: _handle_new_item_selection - item_data_source (original): ", item_data_source_debug)

		_update_transaction_panel()
		if is_instance_valid(action_button): action_button.disabled = false
		if is_instance_valid(max_button): max_button.disabled = false
	else:
		_clear_inspector()
		if is_instance_valid(action_button): action_button.disabled = true
		if is_instance_valid(max_button): max_button.disabled = true

func _on_max_button_pressed() -> void:
	if not selected_item:
		return

	if current_mode == "sell":
		# For selling, the max is the total quantity the player has.
		quantity_spinbox.value = selected_item.get("total_quantity", 1)
	elif current_mode == "buy":
		# For buying, the max is how many the player can afford, limited by vendor stock.
		var item_data_source = selected_item.get("item_data", {})
		var vendor_stock = selected_item.get("total_quantity", 0)
		
		var max_can_afford = 9999 # A large number
		var price: float = 0.0
		var buy_price_val = item_data_source.get("price")
		if buy_price_val is float or buy_price_val is int:
			price = float(buy_price_val)
		
		if price > 0:
			var convoy_money = 0
			if is_instance_valid(gdm):
				var user_data = gdm.get_current_user_data()
				convoy_money = user_data.get("money", 0)
			max_can_afford = floori(convoy_money / price)
		else:
			max_can_afford = vendor_stock # Can afford all if free

		var max_quantity = min(max_can_afford, vendor_stock)

		quantity_spinbox.value = max_quantity

func _on_action_button_pressed() -> void:
	if not selected_item:
		return
		
	var quantity = int(quantity_spinbox.value)
	if quantity <= 0:
		return # Do not process transactions for zero or negative quantity

	var item_data_source = selected_item.get("item_data")
	if not item_data_source: return

	var final_unit_price = _get_contextual_unit_price(item_data_source)
	var total_price = final_unit_price * quantity

	if current_mode == "buy":
		var current_money = 0
		if is_instance_valid(gdm):
			var user_data = gdm.get_current_user_data()
			current_money = user_data.get("money", 0)
		if current_money >= total_price:
			emit_signal("item_purchased", item_data_source, quantity, total_price)
		else:
			# Replace with proper user feedback
			print("Not enough money!")
	else: # "sell"
		# For selling, we don't need a money check here, just emit the signal with the calculated total value.
		emit_signal("item_sold", item_data_source, quantity, total_price)

func _on_quantity_changed(_value: float) -> void:
	_update_transaction_panel()

# --- Inspector and Transaction UI Updates ---
func _update_inspector() -> void:
	if not selected_item: return
	
	var item_data_source = selected_item
	# If selling or buying, the actual item data is nested inside the aggregated structure.
	if current_mode == "sell" or current_mode == "buy":
		item_data_source = selected_item.get("item_data", {})
		
	if is_instance_valid(item_name_label):
		item_name_label.text = item_data_source.get("name", "No Name")
	
	var item_icon = item_data_source.get("icon") if item_data_source.has("icon") else null
	if is_instance_valid(item_preview):
		item_preview.texture = item_icon
		item_preview.visible = item_icon != null
	
	# --- Description Handling ---
	# The checks for description_toggle_button and item_description_rich_text are already here.
	var description_text: String
	var base_desc_val = item_data_source.get("base_desc")
	
	# Ensure description_toggle_button is visible if there's any description
	if is_instance_valid(description_toggle_button):
		description_toggle_button.visible = true
		description_toggle_button.text = "Description (Click to Expand)"
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.visible = false # Always start collapsed

	if base_desc_val is String and not base_desc_val.is_empty():
		description_text = base_desc_val
	else:
		var desc_val = item_data_source.get("description")
		# Check if desc_val is a string and not empty, or if it's a boolean 'true' (which can happen from API)
		# If it's boolean 'true', convert it to a string "true" for display, otherwise use default.
		if desc_val is String and not desc_val.is_empty(): # Standard string description
			description_text = desc_val
		elif desc_val is bool: # Handle any boolean from API by converting it to a string
			description_text = str(desc_val)
		else:
			description_text = "No description available."
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.text = description_text # Assign description here

	var bbcode = "" # Start building the main info text (stats, etc.)
	# Add mission destination right after the description, if applicable.
	if current_mode == "sell" and selected_item.has("mission_vendor_name") and not str(selected_item.mission_vendor_name).is_empty() and selected_item.mission_vendor_name != "Unknown Vendor":
		bbcode += "[b]Destination:[/b] %s\n\n" % selected_item.mission_vendor_name

	bbcode += "[b]Stats:[/b]\n"

	# --- Per Unit Stats ---
	bbcode += "  [u]Per Unit:[/u]\n"
	# Ensure item_data_source is valid before accessing its properties
	if not item_data_source:
		item_data_source = {} # Default to empty dictionary to prevent further errors
	var contextual_unit_price = _get_contextual_unit_price(item_data_source)
	if contextual_unit_price > 0:
		var price_label_text = "Unit Price"
		if current_mode == "buy":
			price_label_text = "Buy Price"
		elif current_mode == "sell":
			price_label_text = "Sell Price"
		bbcode += "    - %s: $%s\n" % [price_label_text, "%.2f" % contextual_unit_price]
		
		var price_components = _get_item_price_components(item_data_source)
		if price_components.resource_unit_value > 0.01:
			bbcode += "      [color=gray](Item: %.2f + Resources: %.2f)[/color]\n" % [price_components.container_unit_price, price_components.resource_unit_value]
	
	var unit_weight = item_data_source.get("unit_weight", 0.0)
	if unit_weight == 0.0 and item_data_source.has("weight") and item_data_source.has("quantity"):
		var total_weight = item_data_source.get("weight", 0.0)
		var total_quantity_float = float(item_data_source.get("quantity", 1.0))
		if total_quantity_float > 0:
			unit_weight = total_weight / total_quantity_float
	if unit_weight > 0: bbcode += "    - Weight: %s\n" % str(unit_weight)

	var unit_volume = item_data_source.get("unit_volume", 0.0)
	if unit_volume == 0.0 and item_data_source.has("volume") and item_data_source.has("quantity"):
		var total_volume = item_data_source.get("volume", 0.0)
		var total_quantity_float = float(item_data_source.get("quantity", 1.0))
		if total_quantity_float > 0:
			unit_volume = total_volume / total_quantity_float
	if unit_volume > 0: bbcode += "    - Volume: %s\n" % str(unit_volume)

	# --- Total Order Stats ---
	bbcode += "\n  [u]Total Order:[/u]\n" # Ensure selected_item is valid before accessing its properties
	if not selected_item:
		selected_item = {} # Default to empty dictionary to prevent further errors
	var total_quantity = selected_item.get("total_quantity", 0)
	if total_quantity > 0: bbcode += "    - Quantity: %d\n" % total_quantity
	var total_weight = selected_item.get("total_weight", 0.0)
	if total_weight > 0: bbcode += "    - Total Weight: %s\n" % str(total_weight)
	var total_volume = selected_item.get("total_volume", 0.0)
	if total_volume > 0: bbcode += "    - Total Volume: %s\n" % str(total_volume)
	# Display total resources for the order
	var total_food = selected_item.get("total_food", 0.0)
	if total_food > 0: bbcode += "    - Food: %s\n" % str(total_food)
	var total_water = selected_item.get("total_water", 0.0)
	if total_water > 0: bbcode += "    - Water: %s\n" % str(total_water)
	var total_fuel = selected_item.get("total_fuel", 0.0)
	if total_fuel > 0: bbcode += "    - Fuel: %s\n" % str(total_fuel)

	var delivery_reward_val = item_data_source.get("delivery_reward")
	if (delivery_reward_val is float or delivery_reward_val is int) and delivery_reward_val > 0:
		bbcode += "    - Delivery Reward: $%s\n" % str(delivery_reward_val)

	# Add a newline separator if there are also generic stats to display
	if item_data_source.has("stats") and item_data_source.stats is Dictionary and not item_data_source.stats.is_empty():
		bbcode += "\n" # Add a separator for readability

	if item_data_source.has("stats") and item_data_source.stats is Dictionary:
		for stat_name in item_data_source.stats:
			bbcode += "- %s: %s\n" % [stat_name.capitalize(), str(item_data_source.stats[stat_name])]
	
	# Add location info to the inspector if in sell mode.
	if current_mode == "sell":
		bbcode += "\n[b]Locations:[/b]\n"
		var locations = selected_item.get("locations", {})
		for vehicle_name in locations:
			bbcode += "- %s: %d\n" % [vehicle_name, locations[vehicle_name]]

	# DEBUG: Print the final bbcode before assignment
	print("DEBUG: _update_inspector - Final bbcode for ItemInfoRichText:\n", bbcode)

	if is_instance_valid(item_info_rich_text):
		item_info_rich_text.text = bbcode # This now only contains stats and location info

func _on_description_toggle_pressed() -> void:
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.visible = not item_description_rich_text.visible
		if is_instance_valid(description_toggle_button):
			if item_description_rich_text.visible:
				description_toggle_button.text = "Description (Click to Collapse)"
			else:
				description_toggle_button.text = "Description (Click to Expand)"
	else:
		if is_instance_valid(description_toggle_button):
			description_toggle_button.text = "Description (Error: Text field missing)"
		printerr("VendorTradePanel: 'ItemDescriptionRichText' is invalid in _on_description_toggle_pressed.")

	# Ensure the parent container updates its size if needed
	get_parent().queue_sort()

func _update_comparison() -> void:
	# Placeholder for your comparison logic.
	# You need to find a comparable equipped item from the convoy's data.
	var equipped_item = null # find_equipped_item_for_comparison(selected_item)
	
	if equipped_item:
		comparison_panel.show()
		selected_item_stats.text = _get_stats_bbcode(selected_item)
		equipped_item_stats.text = _get_stats_bbcode(equipped_item)
	else:
		comparison_panel.hide()

func _get_stats_bbcode(item) -> String:
	if not item or not item.has("stats") or not item.stats is Dictionary: return ""
	var bbcode = ""
	for stat_name in item.stats:
		bbcode += "%s: %s\n" % [stat_name.capitalize(), str(item.stats[stat_name])]
	return bbcode

func _update_transaction_panel() -> void:
	if not selected_item:
		price_label.text = "Total Price: 0"
		return
	
	var item_data_source = selected_item
	# If selling or buying, the actual item data is nested inside the aggregated structure.
	if current_mode == "sell" or current_mode == "buy":
		item_data_source = selected_item.get("item_data", {})
	
	var quantity = int(quantity_spinbox.value) # Ensure integer for display
	var final_unit_price = _get_contextual_unit_price(item_data_source)
	var total_price = final_unit_price * quantity

	var price_components = _get_item_price_components(item_data_source)
	var container_unit_price = price_components.container_unit_price
	var resource_unit_value = price_components.resource_unit_value

	var total_container_value_display: float = 0.0
	var total_resource_value_display: float = 0.0

	if current_mode == "buy":
		total_container_value_display = container_unit_price * quantity
		total_resource_value_display = resource_unit_value * quantity
	else: # "sell"
		# Apply sell price logic to components for display
		var final_container_sell_price_unit = container_unit_price / 2.0
		var sell_price_val = item_data_source.get("sell_unit_price")
		if sell_price_val is float or sell_price_val is int:
			final_container_sell_price_unit = float(sell_price_val)
		
		total_container_value_display = final_container_sell_price_unit * quantity
		total_resource_value_display = (resource_unit_value / 2.0) * quantity

	var bbcode_text = ""
	bbcode_text += "[b]Unit Price:[/b] $%s\n" % ("%.2f" % final_unit_price)

	var is_mission_cargo = current_mode == "sell" and selected_item.has("mission_vendor_name") and not selected_item.mission_vendor_name.is_empty() and selected_item.mission_vendor_name != "Unknown Vendor"

	# Show the breakdown ONLY for mission cargo that also has resources of value.
	if total_resource_value_display > 0.01 and is_mission_cargo:
		bbcode_text += "  [color=gray](Item: %.2f + Resources: %.2f)[/color]\n" % [total_container_value_display, total_resource_value_display]

	bbcode_text += "[b]Quantity:[/b] %d\n" % quantity
	bbcode_text += "[b]Total Price:[/b] $%s" % ("%.2f" % total_price)
	price_label.text = bbcode_text

func _clear_inspector() -> void:
	if is_instance_valid(item_name_label):
		item_name_label.text = "Select an Item"
	if is_instance_valid(item_preview):
		item_preview.texture = null
		item_preview.visible = false
	if is_instance_valid(item_info_rich_text):
		item_info_rich_text.text = ""
	
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.text = ""
		item_description_rich_text.visible = false
	if is_instance_valid(description_toggle_button):
		description_toggle_button.visible = false # Hide button if no item selected

	if is_instance_valid(comparison_panel):
		comparison_panel.hide()
	if is_instance_valid(price_label):
		price_label.text = "Total Price: $0.00" # Update default text for RichTextLabel

# New helper function to get the final unit price based on buy/sell context.
func _get_contextual_unit_price(item_data_source: Dictionary) -> float:
	var final_unit_price: float = 0.0
	
	var price_components = _get_item_price_components(item_data_source)
	var container_unit_price = price_components.container_unit_price
	var resource_unit_value = price_components.resource_unit_value

	if current_mode == "buy":
		final_unit_price = container_unit_price + resource_unit_value
	else: # "sell"
		# When selling, the player gets a lower price. Assume 50% unless a specific sell price is defined.
		var final_container_sell_price = container_unit_price / 2.0
		var sell_price_val = item_data_source.get("sell_unit_price")
		if sell_price_val is float or sell_price_val is int:
			final_container_sell_price = float(sell_price_val)
		
		final_unit_price = final_container_sell_price + (resource_unit_value / 2.0)
	
	return final_unit_price

# New helper function to calculate the price components of a single unit of an item.
func _get_item_price_components(item_data: Dictionary) -> Dictionary:
	var components = {
		"container_unit_price": 0.0,
		"resource_unit_value": 0.0
	}

	# 1. Get base unit price of the container. If it's a raw resource, the container price is 0.
	if item_data.get("is_raw_resource", false):
		components.container_unit_price = 0.0
	else:
		var unit_price_val = item_data.get("unit_price")
		if not (unit_price_val is float or unit_price_val is int):
			unit_price_val = item_data.get("base_unit_price")
		# Add fallbacks for vehicle value fields
		if not (unit_price_val is float or unit_price_val is int):
			unit_price_val = item_data.get("value")
		if not (unit_price_val is float or unit_price_val is int):
			unit_price_val = item_data.get("base_value")

		if unit_price_val is float or unit_price_val is int:
			components.container_unit_price = float(unit_price_val)

	# 2. Calculate value of resources per unit of item
	var item_quantity_in_stack = item_data.get("quantity", 1.0)
	if item_quantity_in_stack <= 0: item_quantity_in_stack = 1.0

	# Resource prices are from the vendor's perspective
	var food_price = vendor_data.get("food_price", 0.0)
	var water_price = vendor_data.get("water_price", 0.0)
	var fuel_price = vendor_data.get("fuel_price", 0.0)
	
	var food_in_stack = item_data.get("food")
	var water_in_stack = item_data.get("water")
	var fuel_in_stack = item_data.get("fuel")

	var resource_value = 0.0
	# Use explicit type checks and ensure the vendor actually trades the resource (price > 0)
	if (food_in_stack is float or food_in_stack is int) and food_price > 0:
		resource_value += (float(food_in_stack) / item_quantity_in_stack) * food_price
	if (water_in_stack is float or water_in_stack is int) and water_price > 0:
		resource_value += (float(water_in_stack) / item_quantity_in_stack) * water_price
	if (fuel_in_stack is float or fuel_in_stack is int) and fuel_price > 0:
		resource_value += (float(fuel_in_stack) / item_quantity_in_stack) * fuel_price
	
	components.resource_unit_value = resource_value
	return components

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

# New helper function to find vendor name by recipient ID
func _get_vendor_name_for_recipient(recipient_id: String) -> String:
	if not all_settlement_data_global:
		return "Unknown Vendor (No Global Data)"
	
	var search_id_str = str(recipient_id)
	# --- DEBUGGING: Print the ID we are searching for and its type ---
	print("VendorTradePanel: Searching for recipient_id: '%s' (Type: %s)" % [search_id_str, typeof(recipient_id)])

	for settlement in all_settlement_data_global:
		if settlement.has("vendors") and settlement.vendors is Array:
			for vendor in settlement.vendors:
				var vendor_id = vendor.get("vendor_id")
				if vendor_id != null:
					var vendor_id_str = str(vendor_id)
					if vendor_id_str == search_id_str:
						# --- DEBUGGING: Print when a match is found ---
						var full_vendor_name = vendor.get("name", "Unknown Vendor")
						var settlement_name = settlement.get("name", "")
						var short_vendor_name = full_vendor_name
						if not settlement_name.is_empty():
							short_vendor_name = full_vendor_name.replace(settlement_name + " ", "").strip_edges()

						print("  > Found match! Vendor: '%s' in Settlement: '%s'" % [full_vendor_name, settlement.get("name", "N/A")])
						return short_vendor_name
	
	# --- DEBUGGING: Print when no match is found after searching everything ---
	print("  > ID not found in any settlement after checking all vendors.")
	return "Unknown Vendor (ID Not Found)"
