extends Control

# Signals to notify the main menu of transactions
signal item_purchased(item, quantity)
signal item_sold(item, quantity)

# --- Node References ---
@onready var vendor_item_list: ItemList = %VendorItemList
@onready var convoy_item_tree: Tree = %ConvoyItemTree
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_preview: TextureRect = %ItemPreview
@onready var item_info_rich_text: RichTextLabel = %ItemInfoRichText
@onready var comparison_panel: PanelContainer = %ComparisonPanel
@onready var selected_item_stats: RichTextLabel = %SelectedItemStats
@onready var equipped_item_stats: RichTextLabel = %EquippedItemStats
@onready var quantity_spinbox: SpinBox = %QuantitySpinBox
@onready var price_label: Label = %PriceLabel
@onready var max_button: Button = %MaxButton
@onready var action_button: Button = %ActionButton
@onready var convoy_money_label: Label = %ConvoyMoneyLabel
@onready var convoy_cargo_label: Label = %ConvoyCargoLabel
@onready var trade_mode_tab_container: TabContainer = %TradeModeTabContainer

# --- Data ---
var vendor_data # Should be set by the parent
var convoy_data # Should be set by the parent
var current_settlement_data # Will hold the current settlement data for local vendor lookup
var all_settlement_data_global: Array # New: Will hold all settlement data for global vendor lookup
var selected_item = null
var current_mode = "buy" # or "sell"

func _ready() -> void:
	# Connect signals from UI elements
	vendor_item_list.item_selected.connect(_on_vendor_item_selected)
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
	_update_convoy_info()
	_on_tab_changed(trade_mode_tab_container.current_tab)

# --- UI Population ---
func _populate_vendor_list() -> void:
	vendor_item_list.clear()
	if not vendor_data or not "cargo_inventory" in vendor_data:
		return

	var aggregated_vendor_cargo: Dictionary = {}

	for item in vendor_data.get("cargo_inventory", []):
		if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
			continue

		var item_name = item.get("name", "Unknown Item")
		if not aggregated_vendor_cargo.has(item_name):
			aggregated_vendor_cargo[item_name] = {"item_data": item, "total_quantity": 0}
		
		var item_quantity = int(item.get("quantity", 1.0))
		aggregated_vendor_cargo[item_name].total_quantity += item_quantity

	for item_name in aggregated_vendor_cargo:
		var agg_data = aggregated_vendor_cargo[item_name]
		var display_text = "%s (x%d)" % [item_name, agg_data.total_quantity]
		var item_icon = agg_data.item_data.get("icon") if agg_data.item_data.has("icon") else null
		vendor_item_list.add_item(display_text, item_icon)
		var index = vendor_item_list.get_item_count() - 1
		vendor_item_list.set_item_metadata(index, agg_data)

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

	# --- POPULATION ---
	var root = convoy_item_tree.create_item()
	_populate_category(root, "Mission Cargo", aggregated_missions)
	_populate_category(root, "Resources", aggregated_resources)
	_populate_category(root, "Parts", aggregated_parts)
	_populate_category(root, "Other", aggregated_other)

func _aggregate_item(agg_dict: Dictionary, item: Dictionary, vehicle_name: String, p_mission_vendor_name: String = "") -> void:
	var item_name = item.get("name", "Unknown Item")
	if not agg_dict.has(item_name):
		agg_dict[item_name] = {"item_data": item, "total_quantity": 0, "locations": {}, "mission_vendor_name": p_mission_vendor_name}
	
	var item_quantity = int(item.get("quantity", 1.0))
	agg_dict[item_name].total_quantity += item_quantity
	if not agg_dict[item_name].locations.has(vehicle_name):
		agg_dict[item_name].locations[vehicle_name] = 0
	agg_dict[item_name].locations[vehicle_name] += item_quantity

func _update_convoy_info() -> void:
	if not convoy_data:
		return
	# Use .get() for safety
	convoy_money_label.text = "Money: %d" % convoy_data.get("money", 0)
	var cargo_used = convoy_data.get("cargo_used", 0) # Replace with actual key if different
	var cargo_max = convoy_data.get("cargo_max", 0)   # Replace with actual key if different
	convoy_cargo_label.text = "Cargo: %d/%d" % [cargo_used, cargo_max]

# --- Signal Handlers ---
func _on_tab_changed(tab_index: int) -> void:
	current_mode = "buy" if tab_index == 0 else "sell"
	action_button.text = "Buy" if current_mode == "buy" else "Sell"
	
	# Clear selection and inspector when switching tabs
	selected_item = null
	vendor_item_list.deselect_all()
	if convoy_item_tree.get_selected():
		convoy_item_tree.get_selected().deselect(0)
	_clear_inspector()
	if is_instance_valid(action_button):
		action_button.disabled = true
	if is_instance_valid(max_button):
		max_button.disabled = true

func _on_vendor_item_selected(index: int) -> void:
	var item = vendor_item_list.get_item_metadata(index)
	_handle_new_item_selection(item)

func _on_convoy_item_selected() -> void:
	var tree_item = convoy_item_tree.get_selected()
	if tree_item and tree_item.get_metadata(0) != null:
		var item = tree_item.get_metadata(0)
		_handle_new_item_selection(item)
	else:
		# This happens if a category header is clicked, or selection is cleared
		_handle_new_item_selection(null)

func _populate_category(root_item: TreeItem, category_name: String, agg_dict: Dictionary) -> void:
	if agg_dict.is_empty():
		return

	var category_item = convoy_item_tree.create_item(root_item)
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
		var tree_child_item = convoy_item_tree.create_item(category_item)
		tree_child_item.set_text(0, display_text)
		if item_icon:
			tree_child_item.set_icon(0, item_icon)
		tree_child_item.set_metadata(0, agg_data)

func _handle_new_item_selection(p_selected_item) -> void:
	selected_item = p_selected_item
	
	if selected_item:
		# When selling or buying, cap the quantity to what is available.
		if current_mode == "sell" or current_mode == "buy":
			quantity_spinbox.max_value = selected_item.get("total_quantity", 99)
		else:
			quantity_spinbox.max_value = 99 # Fallback
		quantity_spinbox.value = 1 # Reset to 1 on new selection

		_update_inspector()
		_update_comparison()
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
			var convoy_money = convoy_data.get("money", 0)
			max_can_afford = floori(convoy_money / price)
		else:
			max_can_afford = vendor_stock # Can afford all if free

		var max_quantity = min(max_can_afford, vendor_stock)

		quantity_spinbox.value = max_quantity

func _on_action_button_pressed() -> void:
	if not selected_item:
		return
		
	var quantity = int(quantity_spinbox.value)
	if current_mode == "buy":
		var item_to_buy = selected_item.get("item_data")
		if not item_to_buy: return
		
		var total_cost = item_to_buy.get("price", 0) * quantity
		if convoy_data.get("money", 0) >= total_cost:
			emit_signal("item_purchased", item_to_buy, quantity)
		else:
			# Replace with proper user feedback
			print("Not enough money!")
	else: # "sell"
		# Pass the base item data, not the aggregated structure, so the parent logic doesn't need to change.
		var item_to_sell = selected_item.get("item_data")
		if item_to_sell:
			emit_signal("item_sold", item_to_sell, quantity)

func _on_quantity_changed(_value: float) -> void:
	_update_transaction_panel()

# --- Inspector and Transaction UI Updates ---
func _update_inspector() -> void:
	if not selected_item: return
	
	var item_data_source = selected_item
	# If selling or buying, the actual item data is nested inside the aggregated structure.
	if current_mode == "sell" or current_mode == "buy":
		item_data_source = selected_item.get("item_data", {})
		
	item_name_label.text = item_data_source.get("name", "No Name")
	item_preview.texture = item_data_source.get("icon") if item_data_source.has("icon") else null
	
	# Safely get the description, prioritizing 'base_desc'.
	# This handles cases where the value might be null, a boolean, or an empty string from the API.
	var description_text: String
	var base_desc_val = item_data_source.get("base_desc")
	if base_desc_val is String and not base_desc_val.is_empty():
		description_text = base_desc_val
	else:
		var desc_val = item_data_source.get("description")
		if desc_val is String and not desc_val.is_empty():
			description_text = desc_val
		else:
			description_text = "No description available."
	
	var bbcode = "[b]Description:[/b]\n%s\n\n" % description_text

	# Add mission destination right after the description, if applicable.
	if current_mode == "sell" and selected_item.has("mission_vendor_name") and not selected_item.mission_vendor_name.is_empty() and selected_item.mission_vendor_name != "Unknown Vendor":
		bbcode += "[b]Destination:[/b] %s\n\n" % selected_item.mission_vendor_name

	bbcode += "[b]Stats:[/b]\n"

	# Add resource specific stats if available and greater than zero
	var has_resource_stats = false
	var food_val = item_data_source.get("food")
	if (food_val is float or food_val is int) and food_val > 0:
		bbcode += "- Food: %s\n" % str(food_val)
		has_resource_stats = true
	
	var water_val = item_data_source.get("water")
	if (water_val is float or water_val is int) and water_val > 0:
		bbcode += "- Water: %s\n" % str(water_val)
		has_resource_stats = true

	var fuel_val = item_data_source.get("fuel")
	if (fuel_val is float or fuel_val is int) and fuel_val > 0:
		bbcode += "- Fuel: %s\n" % str(fuel_val)
		has_resource_stats = true

	# Add a newline after resource stats if any were added and generic stats follow
	if has_resource_stats and item_data_source.has("stats") and item_data_source.stats is Dictionary and not item_data_source.stats.is_empty():
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

	item_info_rich_text.text = bbcode

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
	
	var quantity = int(quantity_spinbox.value)
	var price: float = 0.0
	
	if current_mode == "buy":
		# Explicitly check if the price is a number to avoid errors with non-numeric data (like null or booleans).
		var buy_price_val = item_data_source.get("price")
		if buy_price_val is float or buy_price_val is int:
			price = float(buy_price_val)
	else: # "sell"
		# Prioritize "sell_price" if it's a valid number.
		var sell_price_val = item_data_source.get("sell_price")
		if sell_price_val is float or sell_price_val is int:
			price = float(sell_price_val)
		else:
			# Fallback to calculating from "price" if it's a valid number.
			var base_price_val = item_data_source.get("price")
			if base_price_val is float or base_price_val is int:
				price = float(base_price_val) / 2.0
	
	var total_price = price * quantity
	price_label.text = "Total Price: %d" % total_price

func _clear_inspector() -> void:
	item_name_label.text = "Select an Item"
	item_preview.texture = null
	item_info_rich_text.text = ""
	comparison_panel.hide()
	price_label.text = "Total Price: 0"

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
						var vendor_name = vendor.get("name", "Unknown Vendor")
						print("  > Found match! Vendor: '%s' in Settlement: '%s'" % [vendor_name, settlement.get("name", "N/A")])
						return vendor_name
	
	# --- DEBUGGING: Print when no match is found after searching everything ---
	print("  > ID not found in any settlement after checking all vendors.")
	return "Unknown Vendor (ID Not Found)"
