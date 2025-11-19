extends Control

# Signals to notify the main menu of transactions
signal item_purchased(item, quantity, total_price)
signal item_sold(item, quantity, total_price)
signal install_requested(item, quantity, vendor_id)

# --- Node References ---
@onready var vendor_item_tree: Tree = %VendorItemTree
@onready var convoy_item_tree: Tree = %ConvoyItemTree
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_preview: TextureRect = %ItemPreview
@onready var item_info_rich_text: RichTextLabel = %ItemInfoRichText
@onready var fitment_panel: VBoxContainer = %FitmentPanel
@onready var fitment_rich_text: RichTextLabel = %FitmentRichText
@onready var comparison_panel: PanelContainer = %ComparisonPanel
@onready var description_toggle_button: Button = %DescriptionToggleButton
@onready var description_panel: VBoxContainer = %DescriptionPanel
@onready var item_description_rich_text: RichTextLabel = %ItemDescriptionRichText
@onready var selected_item_stats: RichTextLabel = %SelectedItemStats
@onready var equipped_item_stats: RichTextLabel = %EquippedItemStats
@onready var quantity_spinbox: SpinBox = %QuantitySpinBox
@onready var price_label: RichTextLabel = %PriceLabel
@onready var max_button: Button = %MaxButton
@onready var action_button: Button = %ActionButton
@onready var install_button: Button = %InstallButton
@onready var convoy_money_label: Label = %ConvoyMoneyLabel
@onready var convoy_cargo_label: Label = %ConvoyCargoLabel
@onready var trade_mode_tab_container: TabContainer = %TradeModeTabContainer
@onready var toast_notification: Control = %ToastNotification
@onready var loading_panel: Panel = %LoadingPanel # (Add a Panel node in your scene and name it LoadingPanel)

# --- Data ---
var vendor_data # Should be set by the parent
var convoy_data = {} # Add this line
var gdm: Node # GameDataManager instance
var vendor_items = {}
var convoy_items = {}
var current_settlement_data # Will hold the current settlement data for local vendor lookup
var all_settlement_data_global: Array # New: Will hold all settlement data for global vendor lookup
var selected_item = null
var current_mode = "buy" # or "sell"
var _last_selected_item_id = null # <-- Add this line
var _last_selected_ref = null # Track last selected aggregated data reference to avoid resetting quantity repeatedly
var _last_selection_unique_key: String = "" # Used to detect same logical selection even if reference changes
var _last_selected_tree: String = "" # "vendor" or "convoy"; used to restore selection after refreshes
var _last_selected_restore_id: String = "" # Raw cargo_id or vehicle_id string for restoring selection

var _transaction_in_progress: bool = false
# Backend compatibility cache (per vehicle + part uid), shared semantics with Mechanics menu
var _compat_cache: Dictionary = {} # key: vehicle_id||part_uid -> payload

# Optional: cache install prices per vehicle+part (for future UI use)
var _install_price_cache: Dictionary = {} # key: vehicle_id||part_uid -> float

# Cached convoy cargo stats for transaction projection
var _convoy_used_weight: float = 0.0
var _convoy_total_weight: float = 0.0
var _convoy_used_volume: float = 0.0
var _convoy_total_volume: float = 0.0

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

	if is_instance_valid(install_button):
		install_button.visible = false
		install_button.disabled = true
		install_button.pressed.connect(_on_install_button_pressed)
	else:
		printerr("VendorTradePanel: 'InstallButton' node not found. Please check the scene file.")

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
		# Hook backend part compatibility so vendor UI can display the same truth as mechanics
		if gdm.has_signal("part_compatibility_ready") and not gdm.part_compatibility_ready.is_connected(_on_part_compatibility_ready):
			gdm.part_compatibility_ready.connect(_on_part_compatibility_ready)
		# Connect to settlement updates to know when a vendor refresh is complete.
		if gdm.has_signal("settlement_data_updated") and not gdm.is_connected("settlement_data_updated", Callable(self, "_on_settlement_data_updated_for_refresh")):
			gdm.settlement_data_updated.connect(Callable(self, "_on_settlement_data_updated_for_refresh"))
		# After a transaction, GDM will update convoy data. We listen to this to trigger a full panel refresh,
		# which includes re-fetching vendor inventory. This creates a sequential, non-flickering update.
		if gdm.has_signal("convoy_data_updated") and not gdm.is_connected("convoy_data_updated", Callable(self, "_on_gdm_convoy_data_changed")):
			gdm.convoy_data_updated.connect(Callable(self, "_on_gdm_convoy_data_changed"))
	else:
		printerr("VendorTradePanel: Could not find GameDataManager.")

	# Enable wrapping for convoy cargo label so multi-line text keeps panel narrow
	if is_instance_valid(convoy_cargo_label):
		convoy_cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD

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

func _exit_tree() -> void:
	# Disconnect from GDM signals to avoid lingering <INVALID INSTANCE> connections
	if is_instance_valid(gdm):
		var c = Callable(self, "_on_vendor_panel_data_ready")
		if gdm.has_signal("vendor_panel_data_ready") and gdm.is_connected("vendor_panel_data_ready", c):
			gdm.disconnect("vendor_panel_data_ready", c)
		c = Callable(self, "_on_part_compatibility_ready")
		if gdm.has_signal("part_compatibility_ready") and gdm.is_connected("part_compatibility_ready", c):
			gdm.disconnect("part_compatibility_ready", c)
		c = Callable(self, "_on_settlement_data_updated_for_refresh")
		if gdm.has_signal("settlement_data_updated") and gdm.is_connected("settlement_data_updated", c):
			gdm.disconnect("settlement_data_updated", c)
		c = Callable(self, "_on_gdm_convoy_data_changed")
		if gdm.has_signal("convoy_data_updated") and gdm.is_connected("convoy_data_updated", c):
			gdm.disconnect("convoy_data_updated", c)

	# Disconnect from API signals
	var api = get_node_or_null("/root/APICalls")
	if is_instance_valid(api):
		var cb = Callable(self, "_on_api_transaction_result")
		if api.is_connected("vehicle_bought", cb): api.disconnect("vehicle_bought", cb)
		if api.is_connected("vehicle_sold", cb): api.disconnect("vehicle_sold", cb)
		if api.is_connected("cargo_bought", cb): api.disconnect("cargo_bought", cb)
		if api.is_connected("cargo_sold", cb): api.disconnect("cargo_sold", cb)
		if api.is_connected("resource_bought", cb): api.disconnect("resource_bought", cb)
		if api.is_connected("resource_sold", cb): api.disconnect("resource_sold", cb)
		var cbe = Callable(self, "_on_api_transaction_error")
		if api.is_connected("fetch_error", cbe): api.disconnect("fetch_error", cbe)

# Request data for the panel (call this when opening the panel)
func request_panel_data(convoy_id: String, vendor_id: String) -> void:
	if is_instance_valid(gdm):
		gdm.request_vendor_panel_data(convoy_id, vendor_id)

# Handler for when GDM emits vendor_panel_data_ready
func _on_vendor_panel_data_ready(vendor_panel_data: Dictionary) -> void:
	print("[VendorTradePanel][LOG] _on_vendor_panel_data_ready called. Hiding loading panel and updating UI.")
	_transaction_in_progress = false # Failsafe reset
	loading_panel.visible = false # Hide loading indicator on data arrival
	self.vendor_data = vendor_panel_data.get("vendor_data")
	self.convoy_data = vendor_panel_data.get("convoy_data")
	self.current_settlement_data = vendor_panel_data.get("settlement_data")
	self.all_settlement_data_global = vendor_panel_data.get("all_settlement_data")
	self.vendor_items = vendor_panel_data.get("vendor_items", {})
	self.convoy_items = vendor_panel_data.get("convoy_items", {})

	# --- START ATOMIC REFRESH to prevent flicker ---
	# Disconnect signals to prevent flicker from intermediate states during repopulation.
	vendor_item_tree.item_selected.disconnect(_on_vendor_item_selected)
	convoy_item_tree.item_selected.disconnect(_on_convoy_item_selected)

	var prev_selected_id := _last_selected_restore_id
	var prev_tree := _last_selected_tree
	
	selected_item = null # Clear selection variable before repopulating tree

	_update_vendor_ui()

	var selection_restored = false
	if typeof(prev_selected_id) == TYPE_STRING and not String(prev_selected_id).is_empty():
		if prev_tree == "vendor":
			selection_restored = _restore_selection(vendor_item_tree, prev_selected_id)
		elif prev_tree == "convoy":
			selection_restored = _restore_selection(convoy_item_tree, prev_selected_id)

	# If selection was not restored, manually clear the inspector panels.
	if not selection_restored:
		_clear_inspector()
		_update_transaction_panel() # This will correctly show $0 since selected_item is null
		action_button.disabled = true
		max_button.disabled = true

	# Reconnect signals
	vendor_item_tree.item_selected.connect(_on_vendor_item_selected)
	convoy_item_tree.item_selected.connect(_on_convoy_item_selected)
	# --- END ATOMIC REFRESH ---

func _on_settlement_data_updated_for_refresh(_all_settlements: Array) -> void:
	# This signal is broad, so we only act if we are specifically waiting for a refresh.
	# The loading_panel's visibility is our state indicator.
	if not is_instance_valid(loading_panel) or not loading_panel.visible:
		# This is now expected for general settlement updates not related to a transaction.
		return

	# The vendor data in GDM has been updated. Now, we need to re-request the fully
	# aggregated panel data (which includes convoy items, etc.). This will trigger
	# the `_on_vendor_panel_data_ready` handler, which will hide the loading panel
	# and update the entire UI with the fresh data.
	print("[VendorTradePanel][LOG] Settlement data updated while loading. Re-requesting full panel data.")
	if is_instance_valid(gdm) and self.convoy_data and self.vendor_data:
		var convoy_id = self.convoy_data.get("convoy_id", "")
		var vendor_id = self.vendor_data.get("vendor_id", "")
		if not convoy_id.is_empty() and not vendor_id.is_empty():
			gdm.request_vendor_panel_data(convoy_id, vendor_id)
		else:
			# Failsafe: if we can't re-request, at least hide the loading panel.
			loading_panel.visible = false
	else:
		# Failsafe
		loading_panel.visible = false

func _on_gdm_convoy_data_changed(_all_convoys: Array) -> void:
	# This is our primary trigger to refresh the panel after a transaction (buy/sell).
	# We only act if the panel is visible and we've flagged that a transaction was initiated (`_transaction_in_progress`).
	if not is_visible_in_tree() or not _transaction_in_progress or not is_instance_valid(gdm):
		return

	# Consume the flag so this refresh cycle only runs once per transaction.
	_transaction_in_progress = false

	# To get the latest vendor stock, we must re-request it. This will, in turn,
	# trigger a full panel data aggregation and UI refresh via the `settlement_data_updated` signal chain.
	if vendor_data and vendor_data.has("vendor_id"):
		print("[VendorTradePanel][LOG] Post-transaction convoy update detected. Refreshing vendor data.")
		loading_panel.visible = true
		gdm.request_vendor_data_refresh(vendor_data.get("vendor_id"))

func _update_vendor_ui() -> void:
	# Use self.vendor_items and self.convoy_items to populate the UI
	_populate_tree_from_agg(vendor_item_tree, self.vendor_items)
	_populate_tree_from_agg(convoy_item_tree, self.convoy_items)
	_update_convoy_info_display()

func _populate_tree_from_agg(tree: Tree, agg: Dictionary) -> void:
	tree.clear()
	var root = tree.create_item()

	# Build a display copy to re-bucket parts that might have been placed under 'other'
	var display_agg: Dictionary = {}
	for cat in agg.keys():
		if agg[cat] is Dictionary:
			display_agg[cat] = {}.duplicate() # create empty dict for category
	# Ensure all expected categories exist
	for cat in ["missions", "vehicles", "parts", "other", "resources"]:
		if not display_agg.has(cat):
			display_agg[cat] = {}
	# Shallow-copy entries
	for cat in agg.keys():
		if agg[cat] is Dictionary:
			for k in agg[cat].keys():
				display_agg[cat][k] = agg[cat][k]

	# Move any 'other' entries that look like parts to 'parts' (slot on item or nested parts[] slot)
	if display_agg.has("other") and display_agg["other"] is Dictionary:
		var move_keys: Array = []
		for k in display_agg["other"].keys():
			var entry = display_agg["other"][k]
			if entry is Dictionary and entry.has("item_data") and entry.item_data is Dictionary:
				var slot_text := ""
				if entry.item_data.has("slot") and entry.item_data.get("slot") != null:
					slot_text = String(entry.item_data.get("slot"))
				elif entry.item_data.has("parts") and entry.item_data.get("parts") is Array and not (entry.item_data.get("parts") as Array).is_empty():
					var nested_first: Dictionary = (entry.item_data.get("parts") as Array)[0]
					if nested_first.has("slot") and nested_first.get("slot") != null:
						slot_text = String(nested_first.get("slot"))
				if not slot_text.is_empty():
					# Inject inferred slot back to item_data so inspector/fitment panel can use it
					display_agg["other"][k].item_data["slot"] = slot_text
					move_keys.append(k)
		if not move_keys.is_empty():
			if not display_agg.has("parts") or not (display_agg["parts"] is Dictionary):
				display_agg["parts"] = {}
			for mk in move_keys:
				display_agg["parts"][mk] = display_agg["other"][mk]
				display_agg["other"].erase(mk)

	for category in ["missions", "vehicles", "parts", "other", "resources"]:
		if display_agg.has(category) and not display_agg[category].is_empty():
			var category_item = tree.create_item(root)
			category_item.set_text(0, category.capitalize())
			category_item.set_selectable(0, false)
			category_item.set_custom_color(0, Color.GOLD)
			# Let the Tree control manage the collapsed state.
			# category_item.collapsed = category != "missions"
			for item_name in display_agg[category]:
				var agg_data = display_agg[category][item_name]
				var display_qty = agg_data.total_quantity
				if category == "parts" and agg_data.has("item_data"):
					var part_slot = String(agg_data.item_data.get("slot", ""))
					if not part_slot.is_empty():
						print("DEBUG: Vendor parts category item:", agg_data.item_data.get("name","?"), "slot=", part_slot)
				if category == "resources" and agg_data.has("item_data") and agg_data.item_data.get("is_raw_resource", false):
					# For raw resources prefer the resource amount (fuel/water/food) if larger than total_quantity
					var res_qty = 0
					if agg_data.total_fuel > res_qty: res_qty = int(agg_data.total_fuel)
					if agg_data.total_water > res_qty: res_qty = int(agg_data.total_water)
					if agg_data.total_food > res_qty: res_qty = int(agg_data.total_food)
					if res_qty > display_qty: display_qty = res_qty
				# Prefer the human-friendly name from item_data for display; fallback to key
				var display_name: String = item_name
				if agg_data is Dictionary and agg_data.has("item_data") and agg_data.item_data is Dictionary:
					var n = agg_data.item_data.get("name")
					if n is String and not n.is_empty():
						display_name = n
				var display_text = "%s (x%d)" % [display_name, display_qty]
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

	# Preserve current selection context for restore after repopulation
	var prev_selected_id := _last_selected_restore_id
	var prev_tree := _last_selected_tree

	_populate_vendor_list()
	_populate_convoy_list()
	_update_convoy_info_display()
	# Do not forcibly clear selection; instead, restore it if we know what was selected
	if typeof(prev_selected_id) == TYPE_STRING and not String(prev_selected_id).is_empty():
		if prev_tree == "vendor":
			_restore_selection(vendor_item_tree, prev_selected_id)
		elif prev_tree == "convoy":
			_restore_selection(convoy_item_tree, prev_selected_id)
	# Keep buttons and panels in sync
	_update_transaction_panel()
	_update_install_button_state()
  
# --- UI Population ---
func _populate_vendor_list() -> void:
	vendor_item_tree.clear()
	if not vendor_data:
		return

	var aggregated_missions: Dictionary = {}
	var aggregated_resources: Dictionary = {}
	var aggregated_vehicles: Dictionary = {}
	var aggregated_parts: Dictionary = {}
	var aggregated_other: Dictionary = {}

	print("DEBUG: vendor_data at start of _populate_vendor_list:", vendor_data)
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
			# Robust part detection: top-level slot OR nested parts[] with slot OR part-like hints
			var part_slot: String = ""
			if item.has("slot") and item.get("slot") != null and String(item.get("slot")).length() > 0:
				part_slot = String(item.get("slot"))
			elif item.has("parts") and item.get("parts") is Array and not (item.get("parts") as Array).is_empty():
				var nested_parts: Array = item.get("parts")
				var first_part: Dictionary = nested_parts[0]
				var slot_val = first_part.get("slot", "")
				if typeof(slot_val) == TYPE_STRING and String(slot_val).length() > 0:
					part_slot = String(slot_val)
			# Heuristic fallback if still no slot: check flags/types/stats that imply a part
			var likely_part := false
			if part_slot != "":
				likely_part = true
			elif item.has("is_part") and item.get("is_part"):
				likely_part = true
			else:
				var type_s := String(item.get("type", "")).to_lower()
				var itype_s := String(item.get("item_type", "")).to_lower()
				if type_s == "part" or itype_s == "part":
					likely_part = true
				else:
					var stat_keys := ["top_speed_add", "efficiency_add", "offroad_capability_add", "cargo_capacity_add", "weight_capacity_add", "fuel_capacity", "kwh_capacity"]
					for sk in stat_keys:
						if item.has(sk) and item[sk] != null:
							likely_part = true
							break

			if likely_part:
				category_dict = aggregated_parts
				# Use a display copy and inject inferred slot so UI shows fitment
				var item_disp: Dictionary = item
				if part_slot != "":
					item_disp = item.duplicate(true)
					item_disp["slot"] = part_slot
				print("DEBUG: Vendor part detected name=", item.get("name","?"), " inferred_slot=", part_slot)
			else:
				category_dict = aggregated_other
		print("DEBUG: Aggregating vendor cargo item:", item)
		# Aggregate the display copy when we inferred a slot
		if category_dict == aggregated_parts and (item.has("slot") or (item.has("parts") and item.get("parts") is Array)):
			var use_item: Dictionary = item
			if item.has("slot"):
				use_item = item
			elif item.has("parts") and item.get("parts") is Array and not (item.get("parts") as Array).is_empty():
				var nested_first: Dictionary = (item.get("parts") as Array)[0]
				if nested_first.has("slot") and String(nested_first.get("slot", "")).length() > 0:
					use_item = item.duplicate(true)
					use_item["slot"] = String(nested_first.get("slot"))
			_aggregate_vendor_item(category_dict, use_item, mission_vendor_name)
		else:
			_aggregate_vendor_item(category_dict, item, mission_vendor_name)

	# --- Create virtual items for raw resources AFTER processing normal cargo ---

	print("DEBUG: vendor_data raw resources: fuel=", vendor_data.get("fuel", 0), "water=", vendor_data.get("water", 0), "food=", vendor_data.get("food", 0))
	# Explicitly coerce numeric values without using 'or' (which can mask None vs 0) and log types
	var raw_fuel_val = vendor_data.get("fuel", 0)
	var raw_fuel_price_val = vendor_data.get("fuel_price", 0)
	print("DEBUG: RAW_FUEL before cast value=", raw_fuel_val, " type=", typeof(raw_fuel_val), " price=", raw_fuel_price_val)
	var fuel_quantity = int(raw_fuel_val) if (raw_fuel_val is float or raw_fuel_val is int) else 0
	var fuel_price_is_numeric = raw_fuel_price_val is float or raw_fuel_price_val is int
	var fuel_price = float(raw_fuel_price_val) if fuel_price_is_numeric else 0.0
	if fuel_quantity > 0 and fuel_price_is_numeric:
		var fuel_item = {
			"name": "Fuel (Bulk)",
			"base_desc": "Bulk fuel to fill your containers.",
			"quantity": fuel_quantity, # force exact resource amount
			"fuel": fuel_quantity,
			"fuel_price": fuel_price,
			"is_raw_resource": true
		}
		print("DEBUG: Creating vendor bulk fuel item:", fuel_item)
		_aggregate_vendor_item(aggregated_resources, fuel_item)
	elif fuel_quantity > 0:
		print("DEBUG: Skipping vendor bulk fuel (no numeric fuel_price)")

	var raw_water_val = vendor_data.get("water", 0)
	var raw_water_price_val = vendor_data.get("water_price", 0)
	print("DEBUG: RAW_WATER before cast value=", raw_water_val, " type=", typeof(raw_water_val), " price=", raw_water_price_val)
	var water_quantity = int(raw_water_val) if (raw_water_val is float or raw_water_val is int) else 0
	var water_price_is_numeric = raw_water_price_val is float or raw_water_price_val is int
	var water_price = float(raw_water_price_val) if water_price_is_numeric else 0.0
	if water_quantity > 0 and water_price_is_numeric:
		var water_item = {
			"name": "Water (Bulk)",
			"base_desc": "Bulk water to fill your containers.",
			"quantity": water_quantity, # force exact resource amount
			"water": water_quantity,
			"water_price": water_price,
			"is_raw_resource": true
		}
		print("DEBUG: Creating vendor bulk water item:", water_item)
		_aggregate_vendor_item(aggregated_resources, water_item)
	elif water_quantity > 0:
		print("DEBUG: Skipping vendor bulk water (no numeric water_price)")

	var raw_food_val = vendor_data.get("food", 0)
	var raw_food_price_val = vendor_data.get("food_price", 0)
	print("DEBUG: RAW_FOOD before cast value=", raw_food_val, " type=", typeof(raw_food_val), " price=", raw_food_price_val)
	var food_quantity = int(raw_food_val) if (raw_food_val is float or raw_food_val is int) else 0
	var food_price_is_numeric = raw_food_price_val is float or raw_food_price_val is int
	var food_price = float(raw_food_price_val) if food_price_is_numeric else 0.0
	if food_quantity > 0 and food_price_is_numeric:
		var food_item = {
			"name": "Food (Bulk)",
			"base_desc": "Bulk food supplies.",
			"quantity": food_quantity,
			"food": food_quantity,
			"food_price": food_price,
			"is_raw_resource": true
		}
		print("DEBUG: Creating vendor bulk food item:", food_item)
		_aggregate_vendor_item(aggregated_resources, food_item)
	elif food_quantity > 0:
		print("DEBUG: Skipping vendor bulk food (no numeric food_price)")

	# Process vehicles into their own category
	for vehicle in vendor_data.get("vehicle_inventory", []):
		_aggregate_vendor_item(aggregated_vehicles, vehicle)

	var root = vendor_item_tree.create_item()
	_populate_category(vendor_item_tree, root, "Mission Cargo", aggregated_missions)
	_populate_category(vendor_item_tree, root, "Vehicles", aggregated_vehicles)
	_populate_category(vendor_item_tree, root, "Parts", aggregated_parts)
	_populate_category(vendor_item_tree, root, "Other", aggregated_other)
	_populate_category(vendor_item_tree, root, "Resources", aggregated_resources)

func _populate_convoy_list() -> void:
	convoy_item_tree.clear()
	print("DEBUG: convoy_data at start of _populate_convoy_list:", convoy_data)
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
	# Defensive: avoid 'or 0' which can coerce bools, and log types
	var raw_convoy_fuel = convoy_data.get("fuel", 0)
	var raw_convoy_water = convoy_data.get("water", 0)
	var raw_convoy_food = convoy_data.get("food", 0)
	var vendor_fuel_price = float(vendor_data.get("fuel_price", 0)) if (vendor_data.get("fuel_price", 0) is float or vendor_data.get("fuel_price", 0) is int) else 0.0
	var vendor_water_price = float(vendor_data.get("water_price", 0)) if (vendor_data.get("water_price", 0) is float or vendor_data.get("water_price", 0) is int) else 0.0
	var vendor_food_price = float(vendor_data.get("food_price", 0)) if (vendor_data.get("food_price", 0) is float or vendor_data.get("food_price", 0) is int) else 0.0
	print("DEBUG: convoy_data raw resources: fuel=", raw_convoy_fuel, " type=", typeof(raw_convoy_fuel), "water=", raw_convoy_water, " type=", typeof(raw_convoy_water), "food=", raw_convoy_food, " type=", typeof(raw_convoy_food))
	var convoy_fuel_quantity = int(raw_convoy_fuel) if (raw_convoy_fuel is float or raw_convoy_fuel is int) else 0
	var vendor_fuel_price_numeric = vendor_data.has("fuel_price") and (vendor_data.get("fuel_price") is float or vendor_data.get("fuel_price") is int)
	if convoy_fuel_quantity > 0 and vendor_fuel_price_numeric:
		var fuel_item = {
			"name": "Fuel (Bulk)",
			"base_desc": "Bulk fuel from your convoy's reserves.",
			"quantity": convoy_fuel_quantity,
			"fuel": convoy_fuel_quantity,
			"fuel_price": vendor_fuel_price,
			"is_raw_resource": true
		}
		print("DEBUG: Creating convoy bulk fuel item:", fuel_item)
		_aggregate_vendor_item(aggregated_resources, fuel_item)
	elif convoy_fuel_quantity > 0:
		print("DEBUG: Skipping convoy bulk fuel (vendor has no numeric fuel_price)")

	var convoy_water_quantity = int(raw_convoy_water) if (raw_convoy_water is float or raw_convoy_water is int) else 0
	var vendor_water_price_numeric = vendor_data.has("water_price") and (vendor_data.get("water_price") is float or vendor_data.get("water_price") is int)
	if convoy_water_quantity > 0 and vendor_water_price_numeric:
		var water_item = {
			"name": "Water (Bulk)",
			"base_desc": "Bulk water from your convoy's reserves.",
			"quantity": convoy_water_quantity,
			"water": convoy_water_quantity,
			"water_price": vendor_water_price,
			"is_raw_resource": true
		}
		print("DEBUG: Creating convoy bulk water item:", water_item)
		_aggregate_vendor_item(aggregated_resources, water_item)
	elif convoy_water_quantity > 0:
		print("DEBUG: Skipping convoy bulk water (vendor has no numeric water_price)")

	var convoy_food_quantity = int(raw_convoy_food) if (raw_convoy_food is float or raw_convoy_food is int) else 0
	var vendor_food_price_numeric = vendor_data.has("food_price") and (vendor_data.get("food_price") is float or vendor_data.get("food_price") is int)
	if convoy_food_quantity > 0 and vendor_food_price_numeric:
		var food_item = {
			"name": "Food (Bulk)",
			"base_desc": "Bulk food supplies from your convoy's reserves.",
			"quantity": convoy_food_quantity,
			"food": convoy_food_quantity,
			"food_price": vendor_food_price,
			"is_raw_resource": true
		}
		print("DEBUG: Creating convoy bulk food item:", food_item)
		_aggregate_vendor_item(aggregated_resources, food_item)
	elif convoy_food_quantity > 0:
		print("DEBUG: Skipping convoy bulk food (vendor has no numeric food_price)")

	var root = convoy_item_tree.create_item()
	_populate_category(convoy_item_tree, root, "Mission Cargo", aggregated_missions)
	# Only show loose/aggregated parts when BUYING. In SELL mode installed vehicle parts are not sellable
	# and were causing crashes when selected. Suppressing the entire Parts category avoids invalid selections.
	if current_mode == "buy":
		_populate_category(convoy_item_tree, root, "Parts", aggregated_parts)
	_populate_category(convoy_item_tree, root, "Other", aggregated_other)
	_populate_category(convoy_item_tree, root, "Resources", aggregated_resources)

func _aggregate_vendor_item(agg_dict: Dictionary, item: Dictionary, p_mission_vendor_name: String = "") -> void:
	var item_name = item.get("name", "Unknown Item")
	if not agg_dict.has(item_name):
		agg_dict[item_name] = {"item_data": item, "total_quantity": 0, "total_weight": 0.0, "total_volume": 0.0, "total_food": 0.0, "total_water": 0.0, "total_fuel": 0.0, "mission_vendor_name": p_mission_vendor_name}
	
	var item_quantity = int(item.get("quantity", 1.0))
	# For raw bulk resources, prefer the explicit resource amount if larger than the generic quantity field.
	if item.get("is_raw_resource", false):
		if item.get("fuel", 0) is int or item.get("fuel", 0) is float:
			item_quantity = max(item_quantity, int(item.get("fuel", 0) or 0))
		if item.get("water", 0) is int or item.get("water", 0) is float:
			item_quantity = max(item_quantity, int(item.get("water", 0) or 0))
		if item.get("food", 0) is int or item.get("food", 0) is float:
			item_quantity = max(item_quantity, int(item.get("food", 0) or 0))
		# Mirror back onto the stored item_data so later selection logic sees the larger quantity.
		agg_dict[item_name].item_data["quantity"] = item_quantity
	print("DEBUG: _aggregate_vendor_item before add name=", item_name, "incoming quantity=", item.get("quantity"), "parsed=", item_quantity)
	agg_dict[item_name].total_quantity += item_quantity
	agg_dict[item_name].total_weight += item.get("weight", 0.0)
	agg_dict[item_name].total_volume += item.get("volume", 0.0)
	if item.get("food") is float or item.get("food") is int: agg_dict[item_name].total_food += item.get("food")
	if item.get("water") is float or item.get("water") is int: agg_dict[item_name].total_water += item.get("water")
	if item.get("fuel") is float or item.get("fuel") is int: agg_dict[item_name].total_fuel += item.get("fuel")
	print("DEBUG: _aggregate_vendor_item after add name=", item_name, "total_quantity=", agg_dict[item_name].total_quantity, "total_fuel=", agg_dict[item_name].total_fuel)
	
func _aggregate_item(agg_dict: Dictionary, item: Dictionary, vehicle_name: String, p_mission_vendor_name: String = "") -> void:
	# Use cargo_id as aggregation key if present, but store/display by name
	var agg_key = str(item.get("cargo_id")) if item.has("cargo_id") else item.get("name", "Unknown Item")
	var display_name = item.get("name", "Unknown Item")
	if not agg_dict.has(agg_key):
		agg_dict[agg_key] = {
			"item_data": item,
			"display_name": display_name, # <-- Store the name for display
			"total_quantity": 0,
			"locations": {},
			"mission_vendor_name": p_mission_vendor_name,
			"total_weight": 0.0,
			"total_volume": 0.0,
			"total_food": 0.0,
			"total_water": 0.0,
			"total_fuel": 0.0,
			# Keep a list of the underlying cargo items so we can sell more than a single instance.
			"items": []
		}
	var item_quantity = int(item.get("quantity", 1.0))
	if item.get("is_raw_resource", false):
		if item.get("fuel", 0) is int or item.get("fuel", 0) is float:
			item_quantity = max(item_quantity, int(item.get("fuel", 0) or 0))
		if item.get("water", 0) is int or item.get("water", 0) is float:
			item_quantity = max(item_quantity, int(item.get("water", 0) or 0))
		if item.get("food", 0) is int or item.get("food", 0) is float:
			item_quantity = max(item_quantity, int(item.get("food", 0) or 0))
		agg_dict[agg_key].item_data["quantity"] = item_quantity
	agg_dict[agg_key].total_quantity += item_quantity
	agg_dict[agg_key].total_weight += item.get("weight", 0.0)
	agg_dict[agg_key].total_volume += item.get("volume", 0.0)
	if item.get("food") is float or item.get("food") is int: agg_dict[agg_key].total_food += item.get("food")
	if item.get("water") is float or item.get("water") is int: agg_dict[agg_key].total_water += item.get("water")
	if item.get("fuel") is float or item.get("fuel") is int: agg_dict[agg_key].total_fuel += item.get("fuel")
	if not agg_dict[agg_key].locations.has(vehicle_name):
		agg_dict[agg_key].locations[vehicle_name] = 0
	agg_dict[agg_key].locations[vehicle_name] += item_quantity
	# Track each raw cargo item for selling across multiple underlying stacks
	agg_dict[agg_key].items.append(item)

func _update_convoy_info_display() -> void:
	# This function now updates both the user's money and the convoy's cargo stats.
	if not is_node_ready(): return

	# We are removing the money display per new requirements. Hide or clear the label.
	if is_instance_valid(convoy_money_label):
		convoy_money_label.visible = false

	# Update Convoy Cargo from local convoy_data and cache stats for projections
	if convoy_data:
		var used_volume = convoy_data.get("total_cargo_capacity", 0.0) - convoy_data.get("total_free_space", 0.0)
		var total_volume = convoy_data.get("total_cargo_capacity", 0.0)
		# Attempt to find weight stats; fall back to calculating if absent.
		var weight_capacity: float = -1.0
		var weight_used: float = -1.0
		var possible_capacity_keys = ["total_cargo_weight_capacity", "total_weight_capacity", "weight_capacity"]
		for k in possible_capacity_keys:
			if convoy_data.has(k):
				weight_capacity = float(convoy_data.get(k))
				break
		# Derive used weight from free weight if available
		if weight_capacity >= 0.0:
			var possible_free_keys = ["total_free_weight", "free_weight"]
			for fk in possible_free_keys:
				if convoy_data.has(fk):
					weight_used = weight_capacity - float(convoy_data.get(fk))
					break
		# If still unknown, sum cargo + parts weights
		if weight_used < 0.0 and convoy_data.has("vehicle_details_list"):
			var sum_weight := 0.0
			for vehicle in convoy_data.vehicle_details_list:
				for c in vehicle.get("cargo", []):
					sum_weight += c.get("weight", 0.0)
				for p in vehicle.get("parts", []):
					sum_weight += p.get("weight", 0.0)
			weight_used = sum_weight
		# Cache stats (guard negatives)
		_convoy_used_volume = max(0.0, used_volume)
		_convoy_total_volume = max(0.0, total_volume)
		_convoy_used_weight = max(0.0, weight_used if weight_used >= 0.0 else 0.0)
		_convoy_total_weight = max(0.0, weight_capacity if weight_capacity >= 0.0 else 0.0)
		# If capacity unknown, attempt an estimate (leave -1 to hide)
		var weight_segment = ""
		if weight_used >= 0.0:
			if weight_capacity >= 0.0:
				weight_segment = " | Weight: %.1f / %.1f" % [_convoy_used_weight, _convoy_total_weight]
			else:
				weight_segment = " | Weight: %.1f" % _convoy_used_weight
		convoy_cargo_label.text = "Volume: %.1f / %.1f%s" % [_convoy_used_volume, _convoy_total_volume, weight_segment]
	else:
		convoy_cargo_label.text = "Cargo: N/A"

func _on_user_data_updated(_user_data: Dictionary):
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

	_update_install_button_state()

	# Repopulate convoy list to apply mode-specific filtering (e.g., hide Parts when selling).
	if is_node_ready():
		_populate_convoy_list()

func _on_vendor_item_selected() -> void:
	var tree_item = vendor_item_tree.get_selected()
	# --- START TUTORIAL DEBUG LOG ---
	var item_text = tree_item.get_text(0) if is_instance_valid(tree_item) else "<none>"
	print("[VendorPanel][LOG] _on_vendor_item_selected. Item: '%s'" % item_text)
	# --- END TUTORIAL DEBUG LOG ---
	_last_selected_tree = "vendor"
	var item = tree_item.get_metadata(0) if tree_item and tree_item.get_metadata(0) != null else null
	# Defer handling to the next idle frame. This is critical to prevent a race condition
	# where the panel resizes in the same frame as the input, causing the Tree to lose focus and deselect the item.
	call_deferred("_handle_new_item_selection", item)

func _on_convoy_item_selected() -> void:
	var tree_item = convoy_item_tree.get_selected()
	_last_selected_tree = "convoy"
	var item = tree_item.get_metadata(0) if tree_item and tree_item.get_metadata(0) != null else null
	# Defer handling to prevent UI race conditions, same as for the vendor tree.
	call_deferred("_handle_new_item_selection", item)

func _populate_category(target_tree: Tree, root_item: TreeItem, category_name: String, agg_dict: Dictionary) -> void:
	if agg_dict.is_empty():
		return

	var category_item = target_tree.create_item(root_item)
	category_item.set_text(0, category_name)
	category_item.set_selectable(0, false)
	category_item.set_custom_color(0, Color.GOLD)

	# Let the Tree control manage the collapsed state by not setting the
	# `collapsed` property here.

	for agg_key in agg_dict:
		var agg_data = agg_dict[agg_key]
		var display_name = agg_data.display_name if agg_data.has("display_name") else agg_key
		var display_text = "%s (x%d)" % [display_name, agg_data.total_quantity]
		if category_name == "Resources" and ("Fuel" in display_name or "fuel" in display_name):
			print("DEBUG: _populate_category resource node fuel display_name=", display_name, "total_quantity=", agg_data.total_quantity, "total_fuel=", agg_data.get("total_fuel"))
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
	var previous_key = _last_selection_unique_key
	selected_item = p_selected_item
	var new_key: String = ""
	var restore_id: String = ""
	if selected_item and selected_item.has("item_data"):
		var item_data_local = selected_item.item_data
		if item_data_local.has("cargo_id") and item_data_local.cargo_id != null:
			new_key = "cargo:" + str(item_data_local.cargo_id)
			restore_id = str(item_data_local.cargo_id)
		elif item_data_local.has("vehicle_id") and item_data_local.vehicle_id != null:
			new_key = "veh:" + str(item_data_local.vehicle_id)
			restore_id = str(item_data_local.vehicle_id)
		else:
			if item_data_local.get("fuel",0) > 0 and item_data_local.get("is_raw_resource", false):
				new_key = "fuel_bulk"
			elif item_data_local.get("water",0) > 0 and item_data_local.get("is_raw_resource", false):
				new_key = "water_bulk"
			elif item_data_local.get("food",0) > 0 and item_data_local.get("is_raw_resource", false):
				new_key = "food_bulk"
			else:
				new_key = "name:" + str(item_data_local.get("name", ""))
	_last_selected_item_id = new_key
	_last_selection_unique_key = new_key
	var is_same_selection = previous_key == new_key
	_last_selected_ref = selected_item
	_last_selected_restore_id = restore_id

	# --- START: Reduced logging to prevent output overflow ---
	var item_summary_for_log = "null"
	if selected_item and selected_item.has("item_data"):
		var item_name_for_log = selected_item.item_data.get("name", "<no_name>")
		item_summary_for_log = "Item(name='%s', key='%s')" % [item_name_for_log, new_key]
	print("DEBUG: _handle_new_item_selection - selected_item: ", item_summary_for_log, " is_same_selection: ", is_same_selection)
	# --- END: Reduced logging ---

	if selected_item:
		var stock_qty = selected_item.get("total_quantity", -1)
		if stock_qty < 0 and selected_item.has("item_data") and selected_item.item_data.has("quantity"):
			stock_qty = int(selected_item.item_data.get("quantity", 1))
		if selected_item.has("item_data") and selected_item.item_data.get("is_raw_resource", false):
			var idata = selected_item.item_data
			print("DEBUG: selected_item is raw resource, idata:", idata)
			if idata.get("fuel",0) > 0: stock_qty = int(idata.get("fuel"))
			elif idata.get("water",0) > 0: stock_qty = int(idata.get("water"))
			elif idata.get("food",0) > 0: stock_qty = int(idata.get("food"))
			print("DEBUG: raw resource stock_qty chosen=", stock_qty)
		print("DEBUG: stock_qty for selected_item:", stock_qty)
		if stock_qty <= 0:
			stock_qty = 1
		quantity_spinbox.max_value = max(1, stock_qty)
		print("DEBUG: quantity_spinbox.max_value set to:", quantity_spinbox.max_value)
		if not is_same_selection:
			quantity_spinbox.value = 1
		else:
			quantity_spinbox.value = clampi(int(quantity_spinbox.value), 1, int(quantity_spinbox.max_value))
		print("DEBUG: quantity_spinbox.value set to:", quantity_spinbox.value)

		_update_inspector()
		_update_comparison()

		var item_data_source_debug = selected_item.get("item_data", {})

		# --- START: Reduced logging to prevent output overflow ---
		var item_name_for_log_debug = item_data_source_debug.get("name", "<no_name>")
		var item_id_for_log_debug = item_data_source_debug.get("cargo_id", item_data_source_debug.get("vehicle_id", "<no_id>"))
		print("DEBUG: _handle_new_item_selection - item_data_source (original): name='%s', id='%s'" % [item_name_for_log_debug, item_id_for_log_debug])
		# --- END: Reduced logging ---
		
		_update_transaction_panel()
		_update_install_button_state()
		# Fire backend compatibility checks for this item against all convoy vehicles (to align with Mechanics)
		if selected_item and selected_item.has("item_data") and convoy_data and convoy_data.has("vehicle_details_list"):
			var idata = selected_item.item_data
			var uid := String(idata.get("cargo_id", idata.get("part_id", "")))
			# Only request compatibility for items that look like vehicle parts.
			if uid != "" and _looks_like_part(idata):
				for v in convoy_data.vehicle_details_list:
					var vid := String(v.get("vehicle_id", ""))
					if vid != "" and is_instance_valid(gdm) and gdm.has_method("request_part_compatibility"):
						var key := _compat_key(vid, uid)
						if not _compat_cache.has(key):
							gdm.request_part_compatibility(vid, uid)
		if is_instance_valid(action_button): action_button.disabled = false
		if is_instance_valid(max_button): max_button.disabled = false
	else:
		_clear_inspector()
		if is_instance_valid(action_button): action_button.disabled = true
		if is_instance_valid(max_button): max_button.disabled = true
		_update_install_button_state()

func _on_max_button_pressed() -> void:
	if not selected_item:
		return

	if current_mode == "sell":
		var sel_qty = selected_item.get("total_quantity", 1)
		if selected_item.has("item_data") and selected_item.item_data.get("is_raw_resource", false):
			var idata = selected_item.item_data
			if idata.get("fuel",0) > 0: sel_qty = int(idata.get("fuel"))
			elif idata.get("water",0) > 0: sel_qty = int(idata.get("water"))
			elif idata.get("food",0) > 0: sel_qty = int(idata.get("food"))
		quantity_spinbox.value = sel_qty
	elif current_mode == "buy":
		# For buying, the max is limited by: vendor stock, money, remaining weight, remaining volume.
		var item_data_source: Dictionary = selected_item.get("item_data", {})
		var vendor_stock: int = int(selected_item.get("total_quantity", 0))
		if item_data_source.get("is_raw_resource", false):
			if item_data_source.get("fuel",0) > 0:
				vendor_stock = int(item_data_source.get("fuel"))
			elif item_data_source.get("water",0) > 0:
				vendor_stock = int(item_data_source.get("water"))
			elif item_data_source.get("food",0) > 0:
				vendor_stock = int(item_data_source.get("food"))

		# Money constraint
		var is_vehicle: bool = _is_vehicle_item(item_data_source)
		var unit_price: float = _get_vehicle_price(item_data_source) if is_vehicle else _get_contextual_unit_price(item_data_source)
		var afford_limit: int = 99999999
		if unit_price > 0.0:
			var money: int = 0
			var have_money := false
			# Prefer authoritative user money, fallback to convoy money if present.
			if is_instance_valid(gdm):
				var ud: Dictionary = gdm.get_current_user_data()
				if ud.has("money") and (ud.get("money") is int or ud.get("money") is float):
					money = int(ud.get("money"))
					have_money = true
			# If user money wasn't available (or GDM missing), try convoy money
			if not have_money and convoy_data and convoy_data.has("money") and (convoy_data.get("money") is int or convoy_data.get("money") is float):
				money = int(convoy_data.get("money"))
				have_money = true
			afford_limit = floori(money / unit_price) if unit_price > 0.0 and have_money else 99999999

		# Capacity constraints (skip for vehicles)
		var weight_limit: int = 99999999
		var volume_limit: int = 99999999
		if not is_vehicle:
			# Compute per-unit weight/volume from explicit unit_* or derived from totals.
			var unit_weight := 0.0
			if item_data_source.has("unit_weight"):
				unit_weight = float(item_data_source.get("unit_weight", 0.0))
			elif item_data_source.has("weight") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
				unit_weight = float(item_data_source.get("weight", 0.0)) / float(item_data_source.get("quantity", 1.0))
			var unit_volume := 0.0
			if item_data_source.has("unit_volume"):
				unit_volume = float(item_data_source.get("unit_volume", 0.0))
			elif item_data_source.has("volume") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
				unit_volume = float(item_data_source.get("volume", 0.0)) / float(item_data_source.get("quantity", 1.0))
			# Remaining capacities
			var remaining_weight: float = max(0.0, _convoy_total_weight - _convoy_used_weight)
			var remaining_volume: float = max(0.0, _convoy_total_volume - _convoy_used_volume)
			if unit_weight > 0.0 and _convoy_total_weight > 0.0:
				weight_limit = int(floor(remaining_weight / unit_weight))
			if unit_volume > 0.0 and _convoy_total_volume > 0.0:
				volume_limit = int(floor(remaining_volume / unit_volume))

		var max_quantity = vendor_stock
		max_quantity = min(max_quantity, afford_limit)
		max_quantity = min(max_quantity, weight_limit)
		max_quantity = min(max_quantity, volume_limit)
		max_quantity = max(1, max_quantity)
		quantity_spinbox.value = max_quantity

func _on_action_button_pressed() -> void:
	if not selected_item:
		return
	var quantity = int(quantity_spinbox.value)
	if quantity <= 0:
		return

	_transaction_in_progress = true
	action_button.disabled = true # Prevent double-clicks
	var item_data_source = selected_item.get("item_data")
	if not item_data_source:
		return
	var vendor_id = vendor_data.get("vendor_id", "")
	var convoy_id = convoy_data.get("convoy_id", "")

	if current_mode == "buy":
		gdm.buy_item(convoy_id, vendor_id, item_data_source, quantity)
		# Emit local signal for UI listeners
		var unit_price: float = _get_vehicle_price(item_data_source) if item_data_source.has("vehicle_id") else _get_contextual_unit_price(item_data_source)
		emit_signal("item_purchased", item_data_source, quantity, unit_price * quantity)
	else:
		# SELL: Support selling across multiple underlying cargo stacks in the aggregated selection.
		var remaining = quantity
		if selected_item.has("items") and selected_item.items is Array and not selected_item.items.is_empty():
			for cargo_item in selected_item.items:
				if remaining <= 0:
					break
				var available = int(cargo_item.get("quantity", 0))
				if available <= 0:
					continue
				var to_sell = min(available, remaining)
				gdm.sell_item(convoy_id, vendor_id, cargo_item, to_sell)
				remaining -= to_sell
		else:
			# Fallback: original single-item sale
			gdm.sell_item(convoy_id, vendor_id, item_data_source, quantity)
		# Emit local signal for UI listeners
		var sell_unit_price = _get_contextual_unit_price(item_data_source) / 2.0
		emit_signal("item_sold", item_data_source, quantity, sell_unit_price * quantity)

func _on_quantity_changed(_value: float) -> void:
	_update_transaction_panel()
	_update_install_button_state()

# --- Inspector and Transaction UI Updates ---
func _update_inspector() -> void:
	# --- START TUTORIAL DEBUG LOG ---
	var old_size = size
	print("[VendorPanel][LOG] _update_inspector called. Current panel size: %s" % str(old_size))
	# --- END TUTORIAL DEBUG LOG ---
	if not selected_item:
		return

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item

	# If the selected item is a vehicle, use a dedicated inspector update function and skip the generic one.
	if _is_vehicle_item(item_data_source):
		_update_inspector_for_vehicle(item_data_source)
		# Fitment panel should be updated for all items, including vehicles (to hide it).
		_update_fitment_panel()
		return

	if is_instance_valid(item_name_label):
		item_name_label.text = item_data_source.get("name", "No Name")

	var item_icon = item_data_source.get("icon") if item_data_source.has("icon") else null
	if is_instance_valid(item_preview):
		item_preview.texture = item_icon
		item_preview.visible = item_icon != null

	if is_instance_valid(description_panel):
		description_panel.visible = true

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

	# --- Fitment (slot + compatible vehicles via backend) ---
	# This is now handled by its own function to allow for targeted updates.
	_update_fitment_panel()

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
		var _total_weight_calc = item_data_source.get("weight", 0.0)
		var _total_quantity_float_w = float(item_data_source.get("quantity", 1.0))
		if _total_quantity_float_w > 0:
			unit_weight = _total_weight_calc / _total_quantity_float_w
	if unit_weight > 0: bbcode += "    - Weight: %s\n" % str(unit_weight)

	var unit_volume = item_data_source.get("unit_volume", 0.0)
	if unit_volume == 0.0 and item_data_source.has("volume") and item_data_source.has("quantity"):
		var _total_volume_calc = item_data_source.get("volume", 0.0)
		var _total_quantity_float_v = float(item_data_source.get("quantity", 1.0))
		if _total_quantity_float_v > 0:
			unit_volume = _total_volume_calc / _total_quantity_float_v
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
	call_deferred("_log_size_after_update")

func _update_inspector_for_vehicle(vehicle_data: Dictionary) -> void:
	if is_instance_valid(item_name_label):
		item_name_label.text = vehicle_data.get("name", "No Name")

	# Vehicles don't have a preview icon, so ensure the preview control is hidden
	# to prevent it from taking up space.
	if is_instance_valid(item_preview):
		item_preview.visible = false

	# --- Description Handling for Vehicles ---
	if is_instance_valid(description_panel):
		description_panel.visible = true

	var description_text: String
	var base_desc_val = vehicle_data.get("base_desc")
	if is_instance_valid(description_toggle_button):
		description_toggle_button.visible = true
		description_toggle_button.text = "Description (Click to Expand)"
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.visible = false # Always start collapsed

	if base_desc_val is String and not base_desc_val.is_empty():
		description_text = base_desc_val
	else:
		var desc_val = vehicle_data.get("description")
		if desc_val is String and not desc_val.is_empty():
			description_text = desc_val
		else:
			description_text = "No description available."
	
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.text = description_text
	var bbcode = ""

	# --- Vehicle Stats ---
	bbcode += "[b]Vehicle Stats:[/b]\n"
	var stats_found = false
	
	var stat_map = {
		"top_speed": "Top Speed", "efficiency": "Efficiency", "offroad_capability": "Off-road",
		"cargo_capacity": "Cargo Capacity", "weight_capacity": "Weight Capacity",
		"fuel_capacity": "Fuel Capacity", "kwh_capacity": "Battery", "base_weight": "Base Weight"
	}
	var unit_map = {
		"top_speed": "kph", "efficiency": "km/L", "cargo_capacity": "m³",
		"weight_capacity": "kg", "fuel_capacity": "L", "kwh_capacity": "kWh", "base_weight": "kg"
	}

	for key in stat_map:
		if vehicle_data.has(key) and vehicle_data[key] != null:
			stats_found = true
			var unit = unit_map.get(key, "")
			bbcode += "  - %s: %s%s\n" % [stat_map[key], str(vehicle_data[key]), (" " + unit if not unit.is_empty() else "")]

	if not stats_found:
		bbcode += "  No detailed stats available.\n"

	# --- Installed Parts ---
	if vehicle_data.has("parts") and vehicle_data.get("parts") is Array:
		var parts_list: Array = vehicle_data.get("parts")
		if not parts_list.is_empty():
			bbcode += "\n[b]Installed Parts:[/b]\n"
			for part in parts_list:
				if part is Dictionary:
					var part_name = part.get("name", "Unknown Part")
					var part_slot = part.get("slot", "no slot")
					bbcode += "  - %s (%s)\n" % [part_name, part_slot]

	if is_instance_valid(item_info_rich_text):
		item_info_rich_text.text = bbcode

func _update_fitment_panel() -> void:
	# --- Fitment (slot + compatible vehicles via backend) ---
	if is_instance_valid(fitment_panel) and is_instance_valid(fitment_rich_text):
		if not selected_item:
			fitment_panel.visible = false
			return

		var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item

		var slot_name: String = ""
		if item_data_source.has("slot") and item_data_source.get("slot") != null:
			slot_name = String(item_data_source.get("slot"))
		# Resolve a part UID to query (prefer cargo_id; fallback part_id)
		var part_uid: String = ""
		if item_data_source.has("cargo_id") and item_data_source.get("cargo_id") != null:
			part_uid = String(item_data_source.get("cargo_id"))
		elif item_data_source.has("part_id") and item_data_source.get("part_id") != null:
			part_uid = String(item_data_source.get("part_id"))

		# Per user request: Only show the fitment panel if the item has a "slot" property.
		# This is the primary indicator of it being a vehicle part for UI purposes.
		if slot_name.is_empty():
			fitment_panel.visible = false
			return

		var lines: Array[String] = []
		lines.append("[b]Slot:[/b] %s" % slot_name)
		var compat_lines: Array[String] = []
		if convoy_data and convoy_data.has("vehicle_details_list") and convoy_data.vehicle_details_list is Array:
			for v in convoy_data.vehicle_details_list:
				var vid: String = String(v.get("vehicle_id", ""))
				if vid == "" or part_uid == "":
					continue
				# Build cache key and request on-demand if missing
				# NOTE: Request is sent from _handle_new_item_selection. This function only displays results.
				var key := _compat_key(vid, part_uid)
				var compat_ok: bool = _compat_payload_is_compatible(_compat_cache.get(key, {}))
				var vname: String = v.get("name", "Vehicle")
				if compat_ok:
					compat_lines.append("  • %s" % vname)

		if compat_lines.is_empty():
			lines.append("[color=grey]No compatible convoy vehicles detected by server.[/color]")
		else:
			lines.append("[b]Compatible Vehicles:[/b]")
			for ln in compat_lines:
				lines.append(ln)

		fitment_rich_text.text = "\n".join(lines)
		fitment_rich_text.visible = true
		fitment_panel.visible = true

func _update_transaction_panel() -> void:
	var item_name_for_log = selected_item.item_data.get("name", "<no_name>") if selected_item and selected_item.has("item_data") else "null"
	print("[VendorTradePanel][LOG] _update_transaction_panel called for item: '%s'" % item_name_for_log)

	if not selected_item:
		print("[VendorTradePanel][LOG]   -> No item selected, setting price to $0.")
		price_label.text = "Total Price: $0" # FIX: Ensure dollar sign is present
		return

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item

	# --- START: UNIFIED PRICE & DISPLAY LOGIC ---
	var is_vehicle = _is_vehicle_item(item_data_source)
	var quantity = int(quantity_spinbox.value)
	var unit_price: float = 0.0

	if is_vehicle:
		# For vehicles, compute price from vehicle fields (includes base_value fallback).
		unit_price = _get_vehicle_price(item_data_source)
	else:
		# For cargo, use the existing complex calculation.
		unit_price = _get_contextual_unit_price(item_data_source)

	# Apply sell price reduction for display purposes. The backend handles the actual value.
	if current_mode == "sell":
		unit_price /= 2.0

	var total_price = unit_price * quantity

	var bbcode_text = ""
	if is_vehicle:
		bbcode_text += "[b]Price:[/b] $%s\n" % ("%.2f" % unit_price)
		bbcode_text += "[b]Quantity:[/b] %d\n" % quantity
		bbcode_text += "[b]Total Price:[/b] $%s" % ("%.2f" % total_price)
	else:
		# Use the original detailed display logic for cargo items
		bbcode_text += "[b]Unit Price:[/b] $%s\n" % ("%.2f" % unit_price)

		var price_components = _get_item_price_components(item_data_source)
		var resource_unit_value = price_components.resource_unit_value
		var total_container_value_display: float = (price_components.container_unit_price / (2.0 if current_mode == "sell" else 1.0)) * quantity
		var total_resource_value_display: float = (resource_unit_value / (2.0 if current_mode == "sell" else 1.0)) * quantity
		var is_mission_cargo = current_mode == "sell" and selected_item.has("mission_vendor_name") and not selected_item.mission_vendor_name.is_empty() and selected_item.mission_vendor_name != "Unknown Vendor"
		if total_resource_value_display > 0.01 and is_mission_cargo:
			bbcode_text += "  [color=gray](Item: %.2f + Resources: %.2f)[/color]\n" % [total_container_value_display, total_resource_value_display]

		bbcode_text += "[b]Quantity:[/b] %d\n" % quantity
		bbcode_text += "[b]Total Price:[/b] $%s\n" % ("%.2f" % total_price)

		# --- Added detailed weight/volume and projected convoy stats ---
		var unit_weight := 0.0
		if item_data_source.has("unit_weight"): unit_weight = float(item_data_source.get("unit_weight", 0.0))
		elif item_data_source.has("weight") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
			unit_weight = float(item_data_source.get("weight", 0.0)) / float(item_data_source.get("quantity", 1.0))
		var added_weight = unit_weight * quantity

		var unit_volume := 0.0
		if item_data_source.has("unit_volume"): unit_volume = float(item_data_source.get("unit_volume", 0.0))
		elif item_data_source.has("volume") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
			unit_volume = float(item_data_source.get("volume", 0.0)) / float(item_data_source.get("quantity", 1.0))
		var added_volume = unit_volume * quantity

		if current_mode == "sell":
			added_weight = -added_weight
			added_volume = -added_volume

		if unit_weight > 0.0: bbcode_text += "[b]Unit Weight:[/b] %.2f\n" % unit_weight
		if unit_volume > 0.0: bbcode_text += "[b]Unit Volume:[/b] %.2f\n" % unit_volume
		if abs(added_weight) > 0.0001: bbcode_text += "[b]Total Weight:[/b] %.2f\n" % added_weight
		if abs(added_volume) > 0.0001: bbcode_text += "[b]Total Volume:[/b] %.2f\n" % added_volume

		if (_convoy_total_volume > 0.0 or _convoy_total_weight > 0.0):
			bbcode_text += "[b]After %s:[/b]\n" % ("Purchase" if current_mode == "buy" else "Sale")
			if _convoy_total_volume > 0.0:
				var projected_used_volume = clamp(_convoy_used_volume + added_volume, 0.0, 9999999.0)
				var vol_pct = clamp((projected_used_volume / _convoy_total_volume) * 100.0, 0.0, 999.9)
				bbcode_text += "  Volume: %.2f / %.2f (%.1f%%)\n" % [projected_used_volume, _convoy_total_volume, vol_pct]
			if _convoy_total_weight > 0.0:
				var projected_used_weight = clamp(_convoy_used_weight + added_weight, 0.0, 9999999.0)
				var wt_pct = clamp((projected_used_weight / _convoy_total_weight) * 100.0, 0.0, 999.9)
				bbcode_text += "  Weight: %.2f / %.2f (%.1f%%)\n" % [projected_used_weight, _convoy_total_weight, wt_pct]

	# Trim trailing newline
	if bbcode_text.ends_with("\n"):
		bbcode_text = bbcode_text.substr(0, bbcode_text.length() - 1)
	# --- End added detail block ---
	price_label.text = bbcode_text
	_update_install_button_state()

func _is_positive_number(v: Variant) -> bool:
	return (v is float or v is int) and float(v) > 0.0

func _looks_like_part(item_data_source: Dictionary) -> bool:
	# First, rule out items that are explicitly resources.
	if item_data_source.get("is_raw_resource", false):
		return false
	
	# Also rule out items that provide resources, like MREs or Jerry Cans.
	# These are not vehicle parts for compatibility checking purposes.
	if _is_positive_number(item_data_source.get("food")) or \
	   _is_positive_number(item_data_source.get("water")) or \
	   _is_positive_number(item_data_source.get("fuel")):
		return false

	if item_data_source.has("slot") and item_data_source.get("slot") != null and String(item_data_source.get("slot")).length() > 0:
		return true
	if item_data_source.has("intrinsic_part_id"):
		return true
	if item_data_source.has("parts") and item_data_source.get("parts") is Array and not (item_data_source.get("parts") as Array).is_empty():
		var first_p: Dictionary = (item_data_source.get("parts") as Array)[0]
		if first_p.has("slot") and first_p.get("slot") != null and String(first_p.get("slot")).length() > 0:
			return true
	if item_data_source.has("is_part") and bool(item_data_source.get("is_part")):
		return true
	return false

func _update_install_button_state() -> void:
	if not is_instance_valid(install_button):
		return
	var is_buy_mode := trade_mode_tab_container.current_tab == 0
	var can_install := false
	if is_buy_mode and selected_item and selected_item.has("item_data"):
		var idata: Dictionary = selected_item.item_data
		# Per user request, the install button is only available for items with a "slot".
		can_install = idata.has("slot") and idata.get("slot") != null and not String(idata.get("slot")).is_empty()
	install_button.visible = can_install
	install_button.disabled = not can_install

func _on_install_button_pressed() -> void:
	if not selected_item or not selected_item.has("item_data"):
		return
	var idata: Dictionary = selected_item.item_data
	var qty := int(quantity_spinbox.value)
	if qty <= 0:
		qty = 1
	var vend_id := String(vendor_data.get("vendor_id", "")) if vendor_data else ""
	emit_signal("install_requested", idata, qty, vend_id)

# --- Compatibility plumbing (align with Mechanics) ---
func _compat_key(vehicle_id: String, part_uid: String) -> String:
	return "%s||%s" % [vehicle_id, part_uid]

func _on_part_compatibility_ready(payload: Dictionary) -> void:
	# Cache payload
	var part_cargo_id := String(payload.get("part_cargo_id", ""))
	var vehicle_id := String(payload.get("vehicle_id", ""))
	if part_cargo_id != "" and vehicle_id != "":
		var key := _compat_key(vehicle_id, part_cargo_id)
		_compat_cache[key] = payload
		# Extract and remember install price for potential future display
		var price := _extract_install_price(payload)
		if price >= 0.0:
			_install_price_cache[key] = price
	# If current selection references this part, refresh inspector for updated fitment
	if selected_item and selected_item.has("item_data"):
		var idata: Dictionary = selected_item.item_data
		var uid := String(idata.get("cargo_id", idata.get("part_id", "")))
		if uid != "" and uid == part_cargo_id:
			# This was causing a recursive loop.
			# Only update the part of the UI that depends on this data.
			_update_fitment_panel()

func _compat_payload_is_compatible(payload: Variant) -> bool:
	if not (payload is Dictionary):
		return false
	var pd: Dictionary = payload
	var status := int(pd.get("status", 0))
	var data_any = pd.get("data")
	if data_any is Dictionary:
		var dd: Dictionary = data_any
		if dd.has("compatible"):
			return bool(dd.get("compatible"))
		if dd.has("fitment") and dd.get("fitment") is Dictionary:
			var fit: Dictionary = dd.get("fitment")
			return bool(fit.get("compatible", false))
	elif data_any is Array and status >= 200 and status < 300:
		return (data_any as Array).size() > 0
	return false

func _extract_install_price(payload: Dictionary) -> float:
	var d = payload.get("data")
	if d is Dictionary and (d as Dictionary).has("installation_price"):
		return float((d as Dictionary).get("installation_price", 0.0))
	if d is Array and (d as Array).size() > 0 and (d[0] is Dictionary) and (d[0] as Dictionary).has("installation_price"):
		return float((d[0] as Dictionary).get("installation_price", 0.0))
	return -1.0

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

# True if this dictionary represents a vehicle record (not cargo that happens to reference a vehicle_id)
func _is_vehicle_item(d: Dictionary) -> bool:
	if not (d.has("vehicle_id") and d.get("vehicle_id") != null):
		return false
	# Cargo often contains vehicle_id reference; exclude if it has a cargo_id or is a raw resource
	if (d.has("cargo_id") and d.get("cargo_id") != null) or d.get("is_raw_resource", false):
		return false
	# Positive signals it is a vehicle record
	var vehicle_keys = [
		"base_top_speed", "base_value", "base_cargo_capacity", "base_weight_capacity",
		"base_offroad_capability", "parts"
	]
	for k in vehicle_keys:
		if d.has(k):
			return true
	return false

# Returns the unit price for a vehicle, checking several common fields.
func _get_vehicle_price(vehicle_data: Dictionary) -> float:
	var keys = ["price", "unit_price", "base_unit_price", "base_value", "base_price", "value"]
	for k in keys:
		if vehicle_data.has(k) and vehicle_data[k] != null:
			var v = vehicle_data[k]
			if v is float or v is int:
				var f = float(v)
				if f > 0.0:
					return f
	return 0.0

# Returns the price per unit for the given item, depending on buy/sell mode.
func _get_contextual_unit_price(item_data_source: Dictionary) -> float:
	var price: float = 0.0
	if item_data_source.has("unit_price") and item_data_source.unit_price != null:
		price = float(item_data_source.unit_price)
	elif item_data_source.has("base_unit_price") and item_data_source.base_unit_price != null:
		price = float(item_data_source.base_unit_price)
	elif item_data_source.has("price") and item_data_source.has("quantity") and item_data_source.price != null and item_data_source.quantity > 0:
		price = float(item_data_source.price) / float(item_data_source.quantity)
	else:
		var comps = _get_item_price_components(item_data_source)
		price = comps.container_unit_price + comps.resource_unit_value
	return price

func _on_api_transaction_result(result: Dictionary) -> void:
	print("DEBUG: _on_api_transaction_result called with result: ", result)
	# This handler is now mostly deprecated. The panel's refresh logic is now driven by
	# signals from the GameDataManager (`convoy_data_updated`) to ensure a more
	# orderly update flow and prevent UI flicker from multiple concurrent refresh requests.
	# The GDM's own handlers for transaction signals (e.g., `_on_convoy_transaction`)
	# are responsible for updating the core data models.
	pass

func _on_api_transaction_error(error_message: String) -> void:
	# This panel is only interested in errors that happen while it's visible.
	if not is_visible_in_tree():
		return

	# Check if this is a special "stale inventory" error that we should handle locally.
	if ErrorTranslator.is_inline_error(error_message):
		printerr("VendorTradePanel: Handling inline API error: ", error_message)
		
		# Show a toast notification instead of a jarring popup.
		var toast_msg = ErrorTranslator.translate(error_message)
		toast_notification.show_message(toast_msg)
		
		_transaction_in_progress = false # The transaction failed, so reset the flag.
		# Show loading indicator and refresh the vendor data to get the latest inventory.
		loading_panel.visible = true
		gdm.request_vendor_data_refresh(self.vendor_data.get("vendor_id"))

# Updates the comparison panel (stub, fill in as needed)
func _update_comparison() -> void:
	# Hide comparison for vehicles, as there's nothing to compare against.
	if selected_item and selected_item.has("item_data") and selected_item.item_data.has("vehicle_id"):
		if is_instance_valid(comparison_panel):
			comparison_panel.hide()
		return
	
	# Future: Implement comparison logic for parts, etc.

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
	if is_instance_valid(fitment_rich_text):
		fitment_rich_text.text = ""
		fitment_rich_text.visible = false
	if is_instance_valid(fitment_panel):
		fitment_panel.visible = false
	if is_instance_valid(description_panel):
		description_panel.visible = false
	# Add more UI clearing as needed

# Helper: recompute aggregate convoy cargo stats (not currently used directly; kept for future refactors)
func _recalculate_convoy_cargo_stats() -> Dictionary:
	return {
		"used_weight": _convoy_used_weight,
		"total_weight": _convoy_total_weight,
		"used_volume": _convoy_used_volume,
		"total_volume": _convoy_total_volume
	}

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

func _log_size_after_update():
	print("[VendorPanel][LOG] _update_inspector finished. New panel size: %s" % str(size))

func _restore_selection(tree: Tree, item_id) -> bool:
	if not tree or not tree.get_root():
		_handle_new_item_selection(null)
		return false
	for category in tree.get_root().get_children():
		for item in category.get_children():
			var agg_data = item.get_metadata(0)
			if agg_data and agg_data.has("item_data"):
				var id = agg_data.item_data.get("cargo_id", agg_data.item_data.get("vehicle_id", null))
				if id != null and str(id) == str(item_id):
					item.select(0)
					# Manually call the handler since the selection signal is disconnected during the refresh.
					# This ensures the inspector panel updates correctly.
					call_deferred("_handle_new_item_selection", agg_data)
					return true
	
	# If we get here, the previously selected item was not found (e.g., it was sold or is out of stock).
	# Explicitly clear the selection.
	_handle_new_item_selection(null)
	return false

# --- Tutorial helpers: target resolution for highlight/gating ---

# Expose the primary action button (Buy/Sell) for highlighting
func get_action_button_node() -> Button:
	return action_button

# Ensure the Buy tab is selected
func focus_buy_tab() -> void:
	if is_instance_valid(trade_mode_tab_container):
		trade_mode_tab_container.current_tab = 0

# Find the rect of a vendor item in the tree by display text contains (case-insensitive)
func get_vendor_item_rect_by_text_contains(substr: String) -> Rect2:
	if not is_instance_valid(vendor_item_tree):
		return Rect2()
	var root := vendor_item_tree.get_root()
	if root == null:
		return Rect2()
	var needle := substr.to_lower()
	var found: TreeItem = null
	var q := [root]
	while not q.is_empty():
		var it: TreeItem = q.pop_back()
		if it != null:
			var txt := String(it.get_text(0))
			if txt.to_lower().find(needle) != -1:
				found = it
				break
			# enqueue children
			var child := it.get_first_child()
			while child != null:
				q.push_back(child)
				child = child.get_next()
	if found == null:
		return Rect2()
	# Ensure the item is visible (expand parents) so rect is meaningful
	var parent := found.get_parent()
	while parent != null:
		parent.collapsed = false
		parent = parent.get_parent()
	var local_r: Rect2 = vendor_item_tree.get_item_rect(found, 0, false)
	var tree_global := vendor_item_tree.get_global_rect()
	return Rect2(tree_global.position + local_r.position, local_r.size)
