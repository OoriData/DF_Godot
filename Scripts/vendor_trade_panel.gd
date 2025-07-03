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
@onready var loading_panel: Panel = %LoadingPanel # (Add a Panel node in your scene and name it LoadingPanel)

# --- Data ---
var vendor_data # Should be set by the parent
var convoy_data = {} # Add this line
var gdm: Node # GameDataManager instance
var current_settlement_data # Will hold the current settlement data for local vendor lookup
var all_settlement_data_global: Array # New: Will hold all settlement data for global vendor lookup
var selected_item = null
var current_mode = "buy" # or "sell"
var _last_selected_item_id = null # <-- Add this line

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
		if not gdm.is_connected("vendor_panel_data_ready", _on_vendor_panel_data_ready):
			gdm.vendor_panel_data_ready.connect(_on_vendor_panel_data_ready)
	else:
		printerr("VendorTradePanel: Could not find GameDataManager.")

	# Initially hide comparison panel until an item is selected
	comparison_panel.hide()
	if is_instance_valid(action_button):
		action_button.disabled = true
	if is_instance_valid(max_button):
		max_button.disabled = true

	var api = get_node("/root/APICalls")
	api.vehicle_bought.connect(_on_api_transaction_result)
	api.vehicle_sold.connect(_on_api_transaction_result)
	api.cargo_bought.connect(_on_api_transaction_result)
	api.cargo_sold.connect(_on_api_transaction_result)
	api.resource_bought.connect(_on_api_transaction_result)
	api.resource_sold.connect(_on_api_transaction_result)
	api.fetch_error.connect(_on_api_transaction_error)

# Request data for the panel (call this when opening the panel)
func request_panel_data(convoy_id: String, vendor_id: String) -> void:
	if is_instance_valid(gdm):
		gdm.request_vendor_panel_data(convoy_id, vendor_id)

# Handler for when GDM emits vendor_panel_data_ready
func _on_vendor_panel_data_ready(vendor_panel_data: Dictionary) -> void:
	self.vendor_data = vendor_panel_data.get("vendor_data")
	self.convoy_data = vendor_panel_data.get("convoy_data")
	self.current_settlement_data = vendor_panel_data.get("settlement_data")
	self.all_settlement_data_global = vendor_panel_data.get("all_settlement_data")
	self.vendor_items = vendor_panel_data.get("vendor_items", {})
	self.convoy_items = vendor_panel_data.get("convoy_items", {})
	_update_vendor_ui()

func _update_vendor_ui() -> void:
	# Use self.vendor_items and self.convoy_items to populate the UI
	_populate_tree_from_agg(vendor_item_tree, self.vendor_items)
	_populate_tree_from_agg(convoy_item_tree, self.convoy_items)
	_update_convoy_info_display()

func _populate_tree_from_agg(tree: Tree, agg: Dictionary) -> void:
	tree.clear()
	var root = tree.create_item()
	for category in ["missions", "vehicles", "parts", "other", "resources"]:
		if agg.has(category) and not agg[category].is_empty():
			var category_item = tree.create_item(root)
			category_item.set_text(0, category.capitalize())
			category_item.set_selectable(0, false)
			category_item.set_custom_color(0, Color.GOLD)
			category_item.collapsed = category != "missions"
			for item_name in agg[category]:
				var agg_data = agg[category][item_name]
				var display_text = "%s (x%d)" % [item_name, agg_data.total_quantity]
				var tree_child_item = tree.create_item(category_item)
				tree_child_item.set_text(0, display_text)
				tree_child_item.set_metadata(0, agg_data)

# --- Data Initialization ---
func initialize(p_vendor_data, p_convoy_data, p_current_settlement_data, p_all_settlement_data_global) -> void:
	self.vendor_data = p_vendor_data
	self.convoy_data = p_convoy_data
	self.current_settlement_data = p_current_settlement_data
	self.all_settlement_data_global = p_all_settlement_data_global

	# Let GameDataManager handle the initial fetch
	if is_instance_valid(gdm) and self.vendor_data and self.vendor_data.has("vendor_id"):
		gdm.request_vendor_data_refresh(self.vendor_data.get("vendor_id"))

	_populate_vendor_list()
	_populate_convoy_list()
	_update_convoy_info_display()
	_on_tab_changed(trade_mode_tab_container.current_tab)

# Add this method to support UI refreshes without re-initializing signals or state
func refresh_data(p_vendor_data, p_convoy_data, p_current_settlement_data, p_all_settlement_data_global) -> void:
	self.vendor_data = p_vendor_data
	self.convoy_data = p_convoy_data
	self.current_settlement_data = p_current_settlement_data
	self.all_settlement_data_global = p_all_settlement_data_global

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

	var fuel_quantity = int(vendor_data.get("fuel", 0) or 0)
	var fuel_price = float(vendor_data.get("fuel_price", 0) or 0)
	if fuel_quantity > 0 and fuel_price > 0:
		var fuel_item = {
			"name": "Fuel (Bulk)",
			"base_desc": "Bulk fuel to fill your containers.",
			"quantity": fuel_quantity,
			"fuel": fuel_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, fuel_item)

	var water_quantity = int(vendor_data.get("water", 0) or 0)
	var water_price = float(vendor_data.get("water_price", 0) or 0)
	if water_quantity > 0 and water_price > 0:
		var water_item = {
			"name": "Water (Bulk)",
			"base_desc": "Bulk water to fill your containers.",
			"quantity": water_quantity,
			"water": water_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, water_item)

	var food_quantity = int(vendor_data.get("food", 0) or 0)
	var food_price = float(vendor_data.get("food_price", 0) or 0)
	if food_quantity > 0 and food_price > 0:
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
	if not convoy_data:
		return

	var aggregated_missions: Dictionary = {}
	var aggregated_resources: Dictionary = {}
	var aggregated_parts: Dictionary = {}
	var aggregated_other: Dictionary = {}

	# Aggregate items from all vehicles to create a de-duplicated list.
	var found_any_cargo = false
	if convoy_data.has("vehicle_details_list"):
		for vehicle in convoy_data.vehicle_details_list:
			var vehicle_name = vehicle.get("name", "Unknown Vehicle")
			for item in vehicle.get("cargo", []):
				found_any_cargo = true
				if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
					continue
				var category_dict: Dictionary
				var mission_vendor_name: String = ""
				if item.get("recipient") != null or item.get("delivery_reward") != null:
					category_dict = aggregated_missions
				elif (item.has("food") and item.get("food") != null and item.get("food") > 0) or \
					 (item.has("water") and item.get("water") != null and item.get("water") > 0) or \
					 (item.has("fuel") and item.get("fuel") != null and item.get("fuel") > 0):
					category_dict = aggregated_resources
				else:
					category_dict = aggregated_other
				if category_dict == aggregated_missions:
					var recipient_id = item.get("recipient")
					if recipient_id:
						mission_vendor_name = _get_vendor_name_for_recipient(recipient_id)
				_aggregate_item(category_dict, item, vehicle_name, mission_vendor_name)
			for item in vehicle.get("parts", []):
				if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
					continue
				_aggregate_item(aggregated_parts, item, vehicle_name)

	# --- Fallback: If no cargo found in vehicles, use cargo_inventory (all_cargo) ---
	if not found_any_cargo and convoy_data.has("cargo_inventory"):
		for item in convoy_data.cargo_inventory:
			var category_dict: Dictionary
			var mission_vendor_name: String = ""
			if item.get("recipient") != null or item.get("delivery_reward") != null:
				category_dict = aggregated_missions
			elif (item.has("food") and item.get("food") != null and item.get("food") > 0) or \
				 (item.has("water") and item.get("water") != null and item.get("water") > 0) or \
				 (item.has("fuel") and item.get("fuel") != null and item.get("fuel") > 0):
				category_dict = aggregated_resources
			else:
				category_dict = aggregated_other
			if category_dict == aggregated_missions:
				var recipient_id = item.get("recipient")
				if recipient_id:
					mission_vendor_name = _get_vendor_name_for_recipient(recipient_id)
			_aggregate_item(category_dict, item, "Convoy", mission_vendor_name)

	# --- Create virtual items for convoy's bulk resources AFTER processing normal cargo ---
	var convoy_fuel_quantity = int(convoy_data.get("fuel", 0) or 0)
	var vendor_fuel_price = float(vendor_data.get("fuel_price", 0) or 0)
	if convoy_fuel_quantity > 0 and vendor_fuel_price > 0:
		var fuel_item = {
			"name": "Fuel (Bulk)",
			"base_desc": "Bulk fuel from your convoy's reserves.",
			"quantity": convoy_fuel_quantity,
			"fuel": convoy_fuel_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, fuel_item)

	var convoy_water_quantity = int(convoy_data.get("water", 0) or 0)
	var vendor_water_price = float(vendor_data.get("water_price", 0) or 0)
	if convoy_water_quantity > 0 and vendor_water_price > 0:
		var water_item = {
			"name": "Water (Bulk)",
			"base_desc": "Bulk water from your convoy's reserves.",
			"quantity": convoy_water_quantity,
			"water": convoy_water_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, water_item)

	var convoy_food_quantity = int(convoy_data.get("food", 0) or 0)
	var vendor_food_price = float(vendor_data.get("food_price", 0) or 0)
	if convoy_food_quantity > 0 and vendor_food_price > 0:
		var food_item = {
			"name": "Food (Bulk)",
			"base_desc": "Bulk food supplies from your convoy's reserves.",
			"quantity": convoy_food_quantity,
			"food": convoy_food_quantity,
			"is_raw_resource": true
		}
		_aggregate_vendor_item(aggregated_resources, food_item)

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

func _on_gdm_settlement_data_updated(all_settlements_data: Array) -> void:
	if vendor_data.is_empty() or not vendor_data.has("vendor_id"):
		return
	self.all_settlement_data_global = all_settlements_data
	var current_vendor_id = str(vendor_data.get("vendor_id"))
	for settlement in all_settlements_data:
		if settlement.has("vendors") and settlement.vendors is Array:
			for vendor in settlement.vendors:
				if vendor.has("vendor_id") and str(vendor.get("vendor_id")) == current_vendor_id:
					self.vendor_data = vendor # <-- Only update here!
					_populate_vendor_list()
					_handle_new_item_selection(null)
					return
	if is_instance_valid(loading_panel):
		loading_panel.visible = false

func _on_gdm_convoy_data_updated(all_convoys_data: Array) -> void:
	if convoy_data.is_empty() or not convoy_data.has("convoy_id"):
		return
	var current_convoy_id = str(convoy_data.get("convoy_id"))
	for updated_convoy_data in all_convoys_data:
		if updated_convoy_data.has("convoy_id") and str(updated_convoy_data.get("convoy_id")) == current_convoy_id:
			self.convoy_data = updated_convoy_data # <-- Only update here!
			_populate_convoy_list()
			_update_convoy_info_display()
			# Try to restore selection
			if _last_selected_item_id:
				_restore_selection(convoy_item_tree, _last_selected_item_id)
			else:
				_handle_new_item_selection(null)
			return
	if is_instance_valid(loading_panel):
		loading_panel.visible = false



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

	# Save the unique ID for later restoration
	if selected_item and selected_item.has("item_data"):
		if selected_item.item_data.has("cargo_id"):
			_last_selected_item_id = selected_item.item_data.cargo_id
		elif selected_item.item_data.has("vehicle_id"):
			_last_selected_item_id = selected_item.item_data.vehicle_id
		else:
			_last_selected_item_id = null
	else:
		_last_selected_item_id = null
	
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
		return
	var item_data_source = selected_item.get("item_data")
	if not item_data_source:
		return
	var vendor_id = vendor_data.get("vendor_id", "")
	var convoy_id = convoy_data.get("convoy_id", "")
	if current_mode == "buy":
		gdm.buy_item(convoy_id, vendor_id, item_data_source, quantity)
	else:
		gdm.sell_item(convoy_id, vendor_id, item_data_source, quantity)

func _on_quantity_changed(_value: float) -> void:
	_update_transaction_panel()

# --- Inspector and Transaction UI Updates ---
func _update_inspector() -> void:
	if not selected_item:
		return

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item

	if is_instance_valid(item_name_label):
		item_name_label.text = item_data_source.get("name", "No Name")

	var item_icon = item_data_source.get("icon") if item_data_source.has("icon") else null
	if is_instance_valid(item_preview):
		item_preview.texture = item_icon
		item_preview.visible = item_icon != null

	# --- Description Handling ---
	var description_text: String
	var base_desc_val = item_data_source.get("base_desc")
	if is_instance_valid(description_toggle_button):
		description_toggle_button.visible = true
		description_toggle_button.text = "Description (Click to Expand)"
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.visible = false

	if base_desc_val is String and not base_desc_val.is_empty():
		description_text = base_desc_val
	else:
		var desc_val = item_data_source.get("description")
		if desc_val is String and not desc_val.is_empty():
			description_text = desc_val
		elif desc_val is bool:
			description_text = str(desc_val)
		else:
			description_text = "No description available."
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.text = description_text

	var bbcode = ""
	if current_mode == "sell" and selected_item.has("mission_vendor_name") and not str(selected_item.mission_vendor_name).is_empty() and selected_item.mission_vendor_name != "Unknown Vendor":
		bbcode += "[b]Destination:[/b] %s\n\n" % selected_item.mission_vendor_name

	bbcode += "[b]Stats:[/b]\n"
	bbcode += "  [u]Per Unit:[/u]\n"
	var contextual_unit_price = _get_contextual_unit_price(item_data_source)
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

	bbcode += "\n  [u]Total Order:[/u]\n"
	var total_quantity = selected_item.get("total_quantity", 0)
	if total_quantity > 0: bbcode += "    - Quantity: %d\n" % total_quantity
	var total_weight = selected_item.get("total_weight", 0.0)
	if total_weight > 0: bbcode += "    - Total Weight: %s\n" % str(total_weight)
	var total_volume = selected_item.get("total_volume", 0.0)
	if total_volume > 0: bbcode += "    - Total Volume: %s\n" % str(total_volume)
	var total_food = selected_item.get("total_food", 0.0)
	if total_food > 0: bbcode += "    - Food: %s\n" % str(total_food)
	var total_water = selected_item.get("total_water", 0.0)
	if total_water > 0: bbcode += "    - Water: %s\n" % str(total_water)
	var total_fuel = selected_item.get("total_fuel", 0.0)
	if total_fuel > 0: bbcode += "    - Fuel: %s\n" % str(total_fuel)

	var delivery_reward_val = item_data_source.get("delivery_reward")
	if (delivery_reward_val is float or delivery_reward_val is int) and delivery_reward_val > 0:
		bbcode += "    - Delivery Reward: $%s\n" % str(delivery_reward_val)

	if item_data_source.has("stats") and item_data_source.stats is Dictionary and not item_data_source.stats.is_empty():
		bbcode += "\n"
		for stat_name in item_data_source.stats:
			bbcode += "- %s: %s\n" % [stat_name.capitalize(), str(item_data_source.stats[stat_name])]

	if current_mode == "sell":
		bbcode += "\n[b]Locations:[/b]\n"
		var locations = selected_item.get("locations", {})
		for vehicle_name in locations:
			bbcode += "- %s: %d\n" % [vehicle_name, locations[vehicle_name]]

	print("DEBUG: _update_inspector - Final bbcode for ItemInfoRichText:\n", bbcode)

	if is_instance_valid(item_info_rich_text):
		item_info_rich_text.text = bbcode

func _update_transaction_panel() -> void:
	if not selected_item:
		price_label.text = "Total Price: $0"
		return

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item

	print("DEBUG: item_data_source for price calculation: ", item_data_source)

	var quantity = int(quantity_spinbox.value)
	var final_unit_price = _get_contextual_unit_price(item_data_source)
	var total_price = final_unit_price * quantity

	if typeof(final_unit_price) != TYPE_FLOAT and typeof(final_unit_price) != TYPE_INT:
		final_unit_price = 0.0
	if typeof(total_price) != TYPE_FLOAT and typeof(total_price) != TYPE_INT:
		total_price = 0.0

	var price_components = _get_item_price_components(item_data_source)
	var container_unit_price = price_components.container_unit_price
	var resource_unit_value = price_components.resource_unit_value

	var total_container_value_display: float = 0.0
	var total_resource_value_display: float = 0.0

	if current_mode == "buy":
		total_container_value_display = container_unit_price * quantity
		total_resource_value_display = resource_unit_value * quantity
	else: # "sell"
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

# --- Price Calculation Helpers ---

# Returns a Dictionary with container_unit_price and resource_unit_value for the item.
func _get_item_price_components(item_data_source: Dictionary) -> Dictionary:
	var container_unit_price: float = 0.0
	var resource_unit_value: float = 0.0

	# Container price (for most items, this is just "price" or "container_price")
	if item_data_source.has("container_price"):
		container_unit_price = float(item_data_source.get("container_price", 0.0))
	elif item_data_source.has("price"):
		container_unit_price = float(item_data_source.get("price", 0.0))

	# Resource value (for bulk resources, e.g. food, water, fuel)
	if item_data_source.has("resource_unit_value"):
		resource_unit_value = float(item_data_source.get("resource_unit_value", 0.0))
	elif item_data_source.has("fuel_price") and item_data_source.has("fuel"):
		resource_unit_value = float(item_data_source.get("fuel_price", 0.0))
	elif item_data_source.has("water_price") and item_data_source.has("water"):
		resource_unit_value = float(item_data_source.get("water_price", 0.0))
	elif item_data_source.has("food_price") and item_data_source.has("food"):
		resource_unit_value = float(item_data_source.get("food_price", 0.0))

	return {
		"container_unit_price": container_unit_price,
		"resource_unit_value": resource_unit_value
	}

# Returns the price per unit for the given item, depending on buy/sell mode.
func _get_contextual_unit_price(item_data_source: Dictionary) -> float:
	var price: float = 0.0
	if current_mode == "buy":
		# Prefer explicit unit price, fallback to base_unit_price, then price/quantity, then components
		if item_data_source.has("unit_price"):
			price = float(item_data_source.get("unit_price", 0.0))
		elif item_data_source.has("base_unit_price"):
			price = float(item_data_source.get("base_unit_price", 0.0))
		elif item_data_source.has("price") and item_data_source.has("quantity") and item_data_source.get("quantity", 0) > 0:
			price = float(item_data_source.get("price", 0.0)) / float(item_data_source.get("quantity", 1.0))
		else:
			var comps = _get_item_price_components(item_data_source)
			price = comps.container_unit_price + comps.resource_unit_value
	else: # sell
		if item_data_source.has("sell_unit_price"):
			price = float(item_data_source.get("sell_unit_price", 0.0))
		else:
			var comps = _get_item_price_components(item_data_source)
			price = (comps.container_unit_price / 2.0) + (comps.resource_unit_value / 2.0)
	return price

func _on_api_transaction_result(result: Dictionary) -> void:
	if not is_instance_valid(gdm):
		printerr("VendorTradePanel: Cannot refresh data after transaction, GameDataManager is invalid.")
		return
	gdm.request_user_data_refresh()
	if convoy_data and convoy_data.has("convoy_id"):
		gdm.request_convoy_data_refresh()
	if vendor_data and vendor_data.has("vendor_id"):
		gdm.request_vendor_data_refresh(vendor_data.get("vendor_id"))

func _on_api_transaction_error(error_message: String) -> void:
	# Called when a transaction fails.
	printerr("API Transaction Error: ", error_message)

# Updates the comparison panel (stub, fill in as needed)
func _update_comparison() -> void:
	# Implement your comparison logic here if needed
	pass

# Clears the inspector panel (stub, fill in as needed)
func _clear_inspector() -> void:
	if is_instance_valid(item_info_rich_text):
		item_info_rich_text.text = ""
	if is_instance_valid(item_name_label):
		item_name_label.text = ""
	if is_instance_valid(item_preview):
		item_preview.texture = null
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.text = ""
	# Add more UI clearing as needed

# Formats money as a string with commas (e.g., 1,234,567)
func _format_money(amount) -> String:
	return "%s" % String("{:,}".format(amount))

# Looks up the vendor name for a recipient ID (stub, fill in as needed)
func _get_vendor_name_for_recipient(recipient_id) -> String:
	for settlement in all_settlement_data_global:
		if settlement.has("vendors"):
			for vendor in settlement.vendors:
				if vendor.get("vendor_id", "") == recipient_id:
					return vendor.get("name", "Unknown Vendor")
	return "Unknown Vendor"

# Handler for description toggle button (stub, fill in as needed)
func _on_description_toggle_pressed() -> void:
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.visible = not item_description_rich_text.visible
# Helper to restore selection in a tree after data refresh
func _restore_selection(tree: Tree, item_id):
	if not tree or not tree.get_root():
		_handle_new_item_selection(null)
		return
	for category in tree.get_root().get_children():
		for item in category.get_children():
			var agg_data = item.get_metadata(0)
			if agg_data and agg_data.has("item_data"):
				var id = agg_data.item_data.get("cargo_id", agg_data.item_data.get("vehicle_id", null))
				if id == item_id:
					item.select(0)
					_handle_new_item_selection(agg_data)
					return
	_handle_new_item_selection(null)	# Helper to restore selection in a tree after data refresh
