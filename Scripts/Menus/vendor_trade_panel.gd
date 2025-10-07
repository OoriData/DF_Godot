extends Control

# Signals to notify the main menu of transactions
signal item_purchased(item, quantity, total_price)
signal item_sold(item, quantity, total_price)
signal install_requested(item, quantity, vendor_id)
# Tutorial signal: emitted when a vehicle entry is selected in the vendor tree
signal tutorial_vehicle_selected
# Tutorial signal: emitted when the quantity SpinBox changes (for onboarding cues)
signal tutorial_quantity_changed(qty)

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
@onready var loading_panel: Panel = %LoadingPanel # (Add a Panel node in your scene and name it LoadingPanel)
@onready var quantity_row: HBoxContainer = get_node_or_null("HBoxContainer/RightPanel/HBoxContainer")
@onready var right_panel: VBoxContainer = get_node_or_null("HBoxContainer/RightPanel")

# --- Data ---
var vendor_data # Should be set by the parent
var convoy_data = {} # Add this line
var gdm: Node # GameDataManager instance
var current_settlement_data # Will hold the current settlement data for local vendor lookup
var all_settlement_data_global: Array # New: Will hold all settlement data for global vendor lookup
var selected_item = null
var current_mode = "buy" # or "sell"
var _last_selected_item_id = null # <-- Add this line
var _last_selected_ref = null # Track last selected aggregated data reference to avoid resetting quantity repeatedly
var _last_selection_unique_key: String = "" # Used to detect same logical selection even if reference changes
var _pending_select_prefix: String = "" # Tutorial: select this item by prefix when tree is ready
var _did_tutorial_auto_select_once: bool = false # Prevent repeated auto-select during tutorial
var _suspend_quantity_handler: bool = false # Prevent recursion when setting SpinBox programmatically

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
		print("VTP-DEBUG: ActionButton present; connecting signals…")
		action_button.pressed.connect(_on_action_button_pressed)
		# Also trace low-level input to detect if clicks are reaching the button even when disabled
		if not action_button.is_connected("gui_input", Callable(self, "_on_action_button_gui_input")):
			action_button.gui_input.connect(_on_action_button_gui_input)
		# button_down gives a pre-pressed hook
		if not action_button.is_connected("button_down", Callable(self, "_on_action_button_button_down")):
			action_button.button_down.connect(_on_action_button_button_down)
	else:
		printerr("VendorTradePanel: 'ActionButton' node not found. Please check the scene file.")

	# Trace input arriving at the vendor panel and right side panel (to detect if clicks are blocked before button)
	if not self.is_connected("gui_input", Callable(self, "_on_self_gui_input")):
		self.gui_input.connect(_on_self_gui_input)
	if is_instance_valid(right_panel) and not right_panel.is_connected("gui_input", Callable(self, "_on_right_panel_gui_input")):
		right_panel.gui_input.connect(_on_right_panel_gui_input)

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
		# Vendor panel aggregate payloads (initial fill and refreshes)
		if gdm.has_signal("vendor_panel_data_ready") and not gdm.vendor_panel_data_ready.is_connected(_on_vendor_panel_data_ready):
			gdm.vendor_panel_data_ready.connect(_on_vendor_panel_data_ready)
		# Hook backend part compatibility so vendor UI can display the same truth as mechanics
		if gdm.has_signal("part_compatibility_ready") and not gdm.part_compatibility_ready.is_connected(_on_part_compatibility_ready):
			gdm.part_compatibility_ready.connect(_on_part_compatibility_ready)
		# Keep the panel in sync with global data changes after transactions
		if gdm.has_signal("user_data_updated") and not gdm.user_data_updated.is_connected(_on_user_data_updated):
			gdm.user_data_updated.connect(_on_user_data_updated)
		if gdm.has_signal("convoy_data_updated") and not gdm.convoy_data_updated.is_connected(_on_gdm_convoy_data_updated):
			gdm.convoy_data_updated.connect(_on_gdm_convoy_data_updated)
		if gdm.has_signal("settlement_data_updated") and not gdm.settlement_data_updated.is_connected(_on_gdm_settlement_data_updated):
			gdm.settlement_data_updated.connect(_on_gdm_settlement_data_updated)
	else:
		printerr("VendorTradePanel: Could not find GameDataManager.")

	# Enable wrapping for convoy cargo label so multi-line text keeps panel narrow
	if is_instance_valid(convoy_cargo_label):
		convoy_cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	# Initially hide comparison panel until an item is selected
	comparison_panel.hide()
	if is_instance_valid(action_button):
		print("VTP-DEBUG: Initializing ActionButton state…")
		_update_action_button_enabled("_ready:init")
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

	# One-time sanity check of QuantitySpinBox configuration
	if is_instance_valid(quantity_spinbox):
		print("VTP-DEBUG: QuantitySpinBox init value=", int(quantity_spinbox.value), " min=", int(quantity_spinbox.min_value), " max=", int(quantity_spinbox.max_value))
		if quantity_spinbox.min_value < 1.0:
			print("VTP-DEBUG: WARNING: QuantitySpinBox.min_value < 1 (", quantity_spinbox.min_value, ") — zero quantity can disable Buy. This is allowed but tracked.")

	# Dump initial button state after wiring
	_debug_dump_button_state("_ready")

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
			# Keep 'resources' open by default to support tutorial and avoid flicker
			category_item.collapsed = not (category == "missions" or category == "resources")
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
				var display_text = "%s (x%d)" % [item_name, display_qty]
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
	# Capture current expand/collapse and selection state so we can restore after repopulating
	var _prev_tree_state := _capture_vendor_tree_state()
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

	# Restore previous expand/collapse and selection state (prevents immediate re-collapse while interacting)
	_restore_vendor_tree_state(_prev_tree_state)

	# Tutorial: if a deferred selection by prefix was requested before data was ready, try it now
	if not _pending_select_prefix.is_empty():
		print("VTP-DEBUG: tutorial deferred select prefix=", _pending_select_prefix)
		_tutorial_try_select_prefix(_pending_select_prefix)
		_pending_select_prefix = ""

## Capture expand/collapse and selection state of the vendor tree
func _capture_vendor_tree_state() -> Dictionary:
	var state := {"categories": {}, "selected": {}}
	if not is_instance_valid(vendor_item_tree):
		return state
	var root := vendor_item_tree.get_root()
	if root == null:
		return state
	for cat in root.get_children():
		if cat == null:
			continue
		var cat_name := str(cat.get_text(0))
		state.categories[cat_name] = {"collapsed": cat.collapsed}
	# Selected item path (category + text)
	var sel := vendor_item_tree.get_selected()
	if sel:
		var stext := str(sel.get_text(0))
		var parent := sel.get_parent()
		var cat_name := ""
		if parent != null and parent != root:
			cat_name = str(parent.get_text(0))
		state.selected = {"cat": cat_name, "text": stext}
	return state

## Restore expand/collapse and selection state captured earlier
func _restore_vendor_tree_state(state: Dictionary) -> void:
	if not is_instance_valid(vendor_item_tree):
		return
	var root := vendor_item_tree.get_root()
	if root == null:
		return
	if state.has("categories"):
		for cat in root.get_children():
			if cat == null:
				continue
			var cat_name := str(cat.get_text(0))
			if state.categories.has(cat_name):
				var collapsed := bool(state.categories[cat_name].get("collapsed", cat.collapsed))
				# Keep Resources expanded to avoid flicker/retraction during tutorial and user interaction
				if cat_name.to_lower() == "resources":
					collapsed = false
				cat.collapsed = collapsed
	# Restore selection if possible
	if state.has("selected"):
		var want_cat := str(state.selected.get("cat", ""))
		var want_text := str(state.selected.get("text", ""))
		for cat in root.get_children():
			if cat == null:
				continue
			if want_cat == "" or str(cat.get_text(0)) == want_cat:
				for it in cat.get_children():
					if it != null and str(it.get_text(0)) == want_text:
						# Ensure the category is expanded when reselecting
						cat.collapsed = false
						it.select(0)
						vendor_item_tree.scroll_to_item(it)
						return

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
					# Do NOT clear selection here; preserving it prevents immediate collapse after user click
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
			# Always clear selection after a transaction to avoid stale state
			_handle_new_item_selection(null)
			return
	if is_instance_valid(loading_panel):
		loading_panel.visible = false



# --- Signal Handlers ---
func _on_tab_changed(tab_index: int) -> void:
	var new_mode := "buy" if tab_index == 0 else "sell"
	var prev_mode: String = String(current_mode)
	current_mode = new_mode
	action_button.text = "Buy" if current_mode == "buy" else "Sell"
	print("VTP-DEBUG: _on_tab_changed -> index=", tab_index, " current_mode=", current_mode, " action_button.text=", action_button.text)
	if prev_mode == current_mode:
		# Redundant tab change signal; avoid clearing selection
		if is_instance_valid(action_button):
			_update_action_button_enabled("_on_tab_changed(redundant)")
		_update_quantity_controls_visibility()
		return
	
	# Clear selection and inspector when switching tabs
	selected_item = null
	if vendor_item_tree.get_selected():
		vendor_item_tree.get_selected().deselect(0)
	if convoy_item_tree.get_selected():
		convoy_item_tree.get_selected().deselect(0)
	_clear_inspector()
	if is_instance_valid(action_button):
		_update_action_button_enabled("_on_tab_changed")
	if is_instance_valid(max_button):
		max_button.disabled = true

	_update_install_button_state()
	_update_quantity_controls_visibility()

func _on_vendor_item_selected() -> void:
	var tree_item = vendor_item_tree.get_selected()
	if tree_item and tree_item.get_metadata(0) != null:
		var item = tree_item.get_metadata(0)
		_handle_new_item_selection(item)
	else:
		_handle_new_item_selection(null)
	_debug_dump_button_state("_on_vendor_item_selected")
	_update_install_button_state()
	_update_quantity_controls_visibility()

func _on_convoy_item_selected() -> void:
	var tree_item = convoy_item_tree.get_selected()
	if tree_item and tree_item.get_metadata(0) != null:
		var item = tree_item.get_metadata(0)
		_handle_new_item_selection(item)
	else:
		# This happens if a category header is clicked, or selection is cleared
		_handle_new_item_selection(null)
	_debug_dump_button_state("_on_convoy_item_selected")
	_update_install_button_state()
	_update_quantity_controls_visibility()

func _populate_category(target_tree: Tree, root_item: TreeItem, category_name: String, agg_dict: Dictionary) -> void:
	if agg_dict.is_empty():
		return

	var category_item = target_tree.create_item(root_item)
	category_item.set_text(0, category_name)
	category_item.set_selectable(0, false)
	category_item.set_custom_color(0, Color.GOLD)

	# By default, collapse all categories except for "Mission Cargo".
	if category_name != "Mission Cargo" and category_name != "Resources":
		category_item.collapsed = true

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
	if selected_item and selected_item.has("item_data"):
		var item_data_local = selected_item.item_data
		if item_data_local.has("cargo_id") and item_data_local.cargo_id != null:
			new_key = "cargo:" + str(item_data_local.cargo_id)
		elif item_data_local.has("vehicle_id") and item_data_local.vehicle_id != null:
			new_key = "veh:" + str(item_data_local.vehicle_id)
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

	print("DEBUG: _handle_new_item_selection - selected_item (aggregated):", selected_item)
	print("DEBUG: _handle_new_item_selection - new_key:", new_key, "is_same_selection:", is_same_selection)

	if selected_item:
		# If the selected aggregated item corresponds to a vehicle, emit tutorial hook
		if selected_item.has("item_data") and selected_item.item_data.has("vehicle_id") and selected_item.item_data.get("vehicle_id") != null:
			emit_signal("tutorial_vehicle_selected")
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
			# If this selection was triggered by the tutorial auto-select after a quantity change,
			# preserve the current quantity instead of resetting to 1 to avoid tutorial flicker.
			if _did_tutorial_auto_select_once:
				quantity_spinbox.value = clampi(int(quantity_spinbox.value), 1, int(quantity_spinbox.max_value))
			else:
				quantity_spinbox.value = 1
		else:
			quantity_spinbox.value = clampi(int(quantity_spinbox.value), 1, int(quantity_spinbox.max_value))
		print("DEBUG: quantity_spinbox.value set to:", quantity_spinbox.value)

		_update_inspector()
		_update_comparison()

		var item_data_source_debug = selected_item.get("item_data", {})
		print("DEBUG: _handle_new_item_selection - item_data_source (original):", item_data_source_debug)

		_update_transaction_panel()
		_update_install_button_state()
		# Fire backend compatibility checks for this item against all convoy vehicles (to align with Mechanics)
		if selected_item and selected_item.has("item_data") and convoy_data and convoy_data.has("vehicle_details_list"):
			var idata = selected_item.item_data
			var uid := String(idata.get("cargo_id", idata.get("part_id", "")))
			if uid != "":
				for v in convoy_data.vehicle_details_list:
					var vid := String(v.get("vehicle_id", ""))
					if vid != "" and is_instance_valid(gdm) and gdm.has_method("request_part_compatibility"):
						var key := _compat_key(vid, uid)
						if not _compat_cache.has(key):
							gdm.request_part_compatibility(vid, uid)
		if is_instance_valid(action_button):
			print("VTP-DEBUG: _handle_new_item_selection -> item selected, updating ActionButton state")
		if is_instance_valid(max_button): max_button.disabled = false
	else:
		_clear_inspector()
		if is_instance_valid(action_button):
			print("VTP-DEBUG: _handle_new_item_selection -> no selection, updating ActionButton state")
		if is_instance_valid(max_button): max_button.disabled = true
		_update_install_button_state()

	_update_action_button_enabled("_handle_new_item_selection")

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
		# For buying, the max is how many the player can afford, limited by vendor stock.
		var item_data_source = selected_item.get("item_data", {})
		var vendor_stock = selected_item.get("total_quantity", 0)
		if item_data_source.get("is_raw_resource", false):
			if item_data_source.get("fuel",0) > 0: vendor_stock = int(item_data_source.get("fuel"))
			elif item_data_source.get("water",0) > 0: vendor_stock = int(item_data_source.get("water"))
			elif item_data_source.get("food",0) > 0: vendor_stock = int(item_data_source.get("food"))
		
		var max_can_afford = 9999 # A large number
		var price: float = 0.0
		var buy_price_val = item_data_source.get("price")
		if (buy_price_val == null or (not (buy_price_val is float or buy_price_val is int) or float(buy_price_val) == 0.0)) and item_data_source.get("is_raw_resource", false):
			if item_data_source.get("fuel",0) > 0:
				buy_price_val = item_data_source.get("fuel_price", vendor_data.get("fuel_price", 0.0))
			elif item_data_source.get("water",0) > 0:
				buy_price_val = item_data_source.get("water_price", vendor_data.get("water_price", 0.0))
			elif item_data_source.get("food",0) > 0:
				buy_price_val = item_data_source.get("food_price", vendor_data.get("food_price", 0.0))
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
		print("VTP-DEBUG: _on_action_button_pressed but no selected_item — ignoring")
		return
	var quantity = int(quantity_spinbox.value)
	if quantity <= 0:
		print("VTP-DEBUG: _on_action_button_pressed quantity<=0 (", quantity, ") — ignoring")
		return
	var item_data_source = selected_item.get("item_data")
	if not item_data_source:
		print("VTP-DEBUG: _on_action_button_pressed missing item_data_source — ignoring")
		return
	var vendor_id = vendor_data.get("vendor_id", "")
	var convoy_id = convoy_data.get("convoy_id", "")
	print("VTP-DEBUG: _on_action_button_pressed mode=", current_mode, " qty=", quantity, " item=", String(item_data_source.get("name","?")), " vendor=", vendor_id, " convoy=", convoy_id)
	if current_mode == "buy":
		gdm.buy_item(convoy_id, vendor_id, item_data_source, quantity)
		# Emit local signal for UI listeners
		var unit_price = _get_contextual_unit_price(item_data_source)
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
	# Avoid re-entrancy when we set SpinBox programmatically
	if _suspend_quantity_handler:
		return
	# Defensive: if selection was lost due to any async refresh, restore the last known selection
	if selected_item == null and _last_selected_ref != null:
		selected_item = _last_selected_ref
	# Tutorial assist: if user interacts with quantity but nothing is selected, try auto-select once
	if selected_item == null and not _did_tutorial_auto_select_once:
		_did_tutorial_auto_select_once = true
		var desired_q := int(_value)
		if is_instance_valid(quantity_spinbox):
			desired_q = int(quantity_spinbox.value)
		print("VTP-DEBUG: No selection on quantity change; attempting tutorial auto-select 'Water (Bulk)' and preserving qty=", desired_q)
		tutorial_select_item_by_prefix("Water (Bulk)")
		# Restore user-desired quantity without triggering recursive handling
		if is_instance_valid(quantity_spinbox):
			_suspend_quantity_handler = true
			quantity_spinbox.value = clampi(desired_q, 1, int(quantity_spinbox.max_value))
			_suspend_quantity_handler = false
	_update_transaction_panel()
	_update_install_button_state()
	# Also ensure the action button reflects current quantity/selection
	if is_instance_valid(action_button):
		print("VTP-DEBUG: _on_quantity_changed value=", int(_value), " spin=", (int(quantity_spinbox.value) if is_instance_valid(quantity_spinbox) else -1), " selected_item?=", (selected_item != null))
		_update_action_button_enabled("_on_quantity_changed")
	# Emit tutorial signal so onboarding can react to quantity milestones (e.g., qty == 2)
	if is_instance_valid(quantity_spinbox):
		emit_signal("tutorial_quantity_changed", int(quantity_spinbox.value))
	else:
		emit_signal("tutorial_quantity_changed", int(_value))
	_debug_dump_button_state("_on_quantity_changed")

# --- Inspector and Transaction UI Updates ---
func _update_inspector() -> void:
	if not selected_item:
		return

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item
	var is_vehicle := _is_vehicle(item_data_source)
	var is_part := _looks_like_part(item_data_source) and not is_vehicle

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

	# --- Fitment (slot + compatible vehicles via backend) ---
	if is_instance_valid(fitment_panel) and is_instance_valid(fitment_rich_text):
		if is_part:
			var slot_name: String = ""
			if item_data_source.has("slot") and item_data_source.get("slot") != null:
				slot_name = String(item_data_source.get("slot"))
			# Resolve a part UID to query (prefer cargo_id; fallback part_id)
			var part_uid: String = ""
			if item_data_source.has("cargo_id") and item_data_source.get("cargo_id") != null:
				part_uid = String(item_data_source.get("cargo_id"))
			elif item_data_source.has("part_id") and item_data_source.get("part_id") != null:
				part_uid = String(item_data_source.get("part_id"))

			var lines: Array[String] = []
			if not slot_name.is_empty():
				lines.append("[b]Slot:[/b] %s" % slot_name)
			else:
				lines.append("[b]Slot:[/b] (unknown)")

			var compat_lines: Array[String] = []
			if convoy_data and convoy_data.has("vehicle_details_list") and convoy_data.vehicle_details_list is Array:
				for v in convoy_data.vehicle_details_list:
					var vid: String = String(v.get("vehicle_id", ""))
					if vid == "" or part_uid == "":
						continue
					# Build cache key and request on-demand if missing
					var key := _compat_key(vid, part_uid)
					if not _compat_cache.has(key) and is_instance_valid(gdm) and gdm.has_method("request_part_compatibility"):
						gdm.request_part_compatibility(vid, part_uid)
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
		else:
			fitment_rich_text.text = ""
			fitment_rich_text.visible = false
			fitment_panel.visible = false

	var bbcode = ""
	if current_mode == "sell" and selected_item.has("mission_vendor_name") and not str(selected_item.mission_vendor_name).is_empty() and selected_item.mission_vendor_name != "Unknown Vendor":
		bbcode += "[b]Destination:[/b] %s\n\n" % selected_item.mission_vendor_name

	if is_vehicle:
		bbcode += "[b]Vehicle Stats:[/b]\n"
		var veh_label_map := {
			"top_speed": "Top Speed",
			"max_speed": "Top Speed",
			"speed": "Top Speed",
			"efficiency": "Efficiency",
			"offroad_capability": "Off-road",
			"cargo_capacity": "Cargo Volume",
			"weight_capacity": "Weight Capacity",
			"fuel_capacity": "Fuel Capacity",
			"kwh_capacity": "Battery Capacity",
			"range": "Range",
			"armor": "Armor",
			"armor_class": "Armor Class",
			"hp": "Horsepower",
			"passenger_capacity": "Passengers",
			"weight": "Weight"
		}
		var veh_lines: Array[String] = []
		for k in veh_label_map.keys():
			if item_data_source.has(k) and item_data_source.get(k) != null:
				veh_lines.append("- %s: %s" % [veh_label_map[k], str(item_data_source.get(k))])
		if item_data_source.has("stats") and item_data_source.stats is Dictionary:
			var s: Dictionary = item_data_source.stats
			for k in veh_label_map.keys():
				if s.has(k) and s.get(k) != null:
					veh_lines.append("- %s: %s" % [veh_label_map[k], str(s.get(k))])
		if veh_lines.is_empty():
			bbcode += "(No detailed stats available)\n"
		else:
			for ln in veh_lines:
				bbcode += ln + "\n"
	else:
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

func _update_transaction_panel() -> void:
	# Defensive: if selection was lost due to async UI updates, restore it
	if not selected_item and _last_selected_ref != null:
		selected_item = _last_selected_ref
	if not selected_item:
		price_label.text = "Total Price: $0"
		print("VTP-DEBUG: _update_transaction_panel no selection — setting price to $0")
		return

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item

	var is_vehicle_buy := (current_mode == "buy" and _is_vehicle(item_data_source))
	if is_vehicle_buy:
		# Vehicles are purchased as a single unit; hide quantity controls and show only a single price
		if is_instance_valid(quantity_spinbox):
			quantity_spinbox.value = 1
		var vehicle_price := _get_contextual_unit_price(item_data_source)
		# Show this as Current Value for clarity
		var base_val_hint := ""
		var bv = item_data_source.get("base_value")
		if (bv is float or bv is int) and float(bv) > 0.0 and float(bv) != float(vehicle_price):
			base_val_hint = "\n[color=gray](Base Value: $%s)[/color]" % ("%.2f" % float(bv))
		price_label.text = "[b]Current Value:[/b] $%s%s" % ["%.2f" % vehicle_price, base_val_hint]
		return

	print("VTP-DEBUG: item_data_source for price calculation:", item_data_source)

	var quantity = int(quantity_spinbox.value)
	var final_unit_price = _get_contextual_unit_price(item_data_source)
	# In sell mode, display prices at 50% for transparency
	var display_unit_price: float = float(final_unit_price)
	if current_mode == "sell":
		display_unit_price = final_unit_price / 2.0
	var total_price = display_unit_price * quantity
	print("VTP-DEBUG: pricing mode=", current_mode, " unit=", display_unit_price, " qty=", quantity, " total=", total_price)

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
	var unit_label := "Unit Price:"
	if current_mode == "buy":
		unit_label = "Buy Price:"
	elif current_mode == "sell":
		unit_label = "Sell Price:"
	bbcode_text += "[b]%s[/b] $%s\n" % [unit_label, "%.2f" % display_unit_price]

	var is_mission_cargo = current_mode == "sell" and selected_item.has("mission_vendor_name") and not selected_item.mission_vendor_name.is_empty() and selected_item.mission_vendor_name != "Unknown Vendor"

	# Show the breakdown ONLY for mission cargo that also has resources of value.
	if total_resource_value_display > 0.01 and is_mission_cargo:
		bbcode_text += "  [color=gray](Item: %.2f + Resources: %.2f)[/color]\n" % [total_container_value_display, total_resource_value_display]

	bbcode_text += "[b]Quantity:[/b] %d\n" % quantity
	bbcode_text += "[b]Total Price:[/b] $%s\n" % ("%.2f" % total_price)

	# --- Added detailed weight/volume and projected convoy stats ---
	var unit_weight := 0.0
	if item_data_source.has("unit_weight"):
		unit_weight = float(item_data_source.get("unit_weight", 0.0))
	elif item_data_source.has("weight") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
		var qw = float(item_data_source.get("quantity", 1.0))
		if qw > 0.0:
			unit_weight = float(item_data_source.get("weight", 0.0)) / qw
	var added_weight = unit_weight * quantity

	var unit_volume := 0.0
	if item_data_source.has("unit_volume"):
		unit_volume = float(item_data_source.get("unit_volume", 0.0))
	elif item_data_source.has("volume") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
		var qv = float(item_data_source.get("quantity", 1.0))
		if qv > 0.0:
			unit_volume = float(item_data_source.get("volume", 0.0)) / qv
	var added_volume = unit_volume * quantity

	# Adjust direction for sell mode (capacity freed instead of consumed)
	if current_mode == "sell":
		added_weight = -added_weight
		added_volume = -added_volume

	if unit_weight > 0.0: bbcode_text += "[b]Unit Weight:[/b] %.2f\n" % unit_weight
	if unit_volume > 0.0: bbcode_text += "[b]Unit Volume:[/b] %.2f\n" % unit_volume
	if abs(added_weight) > 0.0001: bbcode_text += "[b]Total Weight:[/b] %.2f\n" % added_weight
	if abs(added_volume) > 0.0001: bbcode_text += "[b]Total Volume:[/b] %.2f\n" % added_volume

	# Projected post-transaction stats (only if we have convoy totals)
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
	_update_quantity_controls_visibility()
	# Keep the Buy/Sell button enabled when a valid item is selected and quantity >= 1
	if is_instance_valid(action_button):
		_update_action_button_enabled("_update_transaction_panel")

func _update_action_button_enabled(origin: String = "") -> void:
	if not is_instance_valid(action_button):
		return
	var q := int(quantity_spinbox.value) if is_instance_valid(quantity_spinbox) else 0
	var reason := ""
	if selected_item == null:
		reason = "Select an item from the list."
	elif q < 1:
		reason = "Increase quantity (must be at least 1)."
	action_button.disabled = reason != ""
	if reason == "":
		action_button.tooltip_text = "Click to %s" % ("Buy" if current_mode == "buy" else "Sell")
	else:
		action_button.tooltip_text = "Disabled: %s" % reason
	print("VTP-DEBUG: ", origin, " -> set ActionButton.disabled=", action_button.disabled, " reason=", (reason if reason != "" else "<none>"))
	_debug_dump_button_state(origin)

# --- Debug helpers ---
func _on_action_button_gui_input(event: InputEvent) -> void:
	# Log raw input arriving at the ActionButton to detect overlay interception or disabled state behavior
	var _ev_str := str(event)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var btn := event as InputEventMouseButton
		var disabled_str := "<na>"
		if is_instance_valid(action_button):
			disabled_str = str(action_button.disabled)
		print("VTP-DEBUG: ActionButton.gui_input left ", ("pressed" if btn.pressed else "released"), " at ", btn.position, " disabled=", disabled_str)
		_debug_dump_button_state("gui_input")
	elif event is InputEventMouseMotion:
		# Keep motion logs sparse; uncomment if needed
		pass

func _on_action_button_button_down() -> void:
	var disabled_str := "<na>"
	if is_instance_valid(action_button):
		disabled_str = str(action_button.disabled)
	print("VTP-DEBUG: ActionButton.button_down fired (disabled=", disabled_str, ")")

func _on_self_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var btn := event as InputEventMouseButton
		print("VTP-DEBUG: VendorTradePanel.gui_input left ", ("pressed" if btn.pressed else "released"), " at ", btn.position)

func _on_right_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var btn := event as InputEventMouseButton
		print("VTP-DEBUG: RightPanel.gui_input left ", ("pressed" if btn.pressed else "released"), " at ", btn.position)

func _debug_dump_button_state(origin: String = "") -> void:
	if not is_instance_valid(action_button):
		print("VTP-DEBUG: ", origin, " -> ActionButton invalid")
		return
	var btn_rect := action_button.get_global_rect()
	var spin_v := int(quantity_spinbox.value) if is_instance_valid(quantity_spinbox) else -1
	var spin_min := int(quantity_spinbox.min_value) if is_instance_valid(quantity_spinbox) else -1
	var spin_max := int(quantity_spinbox.max_value) if is_instance_valid(quantity_spinbox) else -1
	var sel_name := "<none>"
	if selected_item and selected_item.has("item_data"):
		sel_name = String(selected_item.item_data.get("name", "?"))
	print("VTP-DEBUG: ", origin, " -> mode=", current_mode, " btn(disabled=", action_button.disabled, ", visible=", action_button.visible, ", z=", action_button.z_index, ") rect=", btn_rect,
		" spin(value=", spin_v, ", min=", spin_min, ", max=", spin_max, ") selection=", sel_name)

func _update_quantity_controls_visibility() -> void:
	# Hide quantity controls when buying a vehicle, otherwise show them
	if not is_instance_valid(quantity_row):
		return
	var is_vehicle_buy := false
	if selected_item and selected_item.has("item_data") and current_mode == "buy":
		var idata: Dictionary = selected_item.item_data
		is_vehicle_buy = _is_vehicle(idata)
	quantity_row.visible = not is_vehicle_buy
	if is_instance_valid(max_button):
		max_button.visible = not is_vehicle_buy
		max_button.disabled = is_vehicle_buy
	if is_instance_valid(quantity_spinbox):
		quantity_spinbox.editable = not is_vehicle_buy
		if is_vehicle_buy:
			quantity_spinbox.value = 1

func _looks_like_part(item_data_source: Dictionary) -> bool:
	# Avoid misclassifying vehicles (which often have parts[]) as parts
	# Never treat raw resources (Fuel/Water/Food bulk) as parts
	if item_data_source.has("is_raw_resource") and bool(item_data_source.get("is_raw_resource")):
		return false
	if _is_vehicle(item_data_source):
		return false
	if item_data_source.has("slot") and item_data_source.get("slot") != null:
		return true
	if item_data_source.has("intrinsic_part_id"):
		return true
	if item_data_source.has("parts") and item_data_source.get("parts") is Array and not (item_data_source.get("parts") as Array).is_empty():
		var first_p: Dictionary = (item_data_source.get("parts") as Array)[0]
		if first_p.has("slot") and first_p.get("slot") != null:
			return true
	if item_data_source.has("is_part") and bool(item_data_source.get("is_part")):
		return true
	return false

func _is_vehicle(item_data_source: Dictionary) -> bool:
	if item_data_source.has("vehicle_id") and item_data_source.get("vehicle_id") != null:
		return true
	var t := String(item_data_source.get("type", "")).to_lower()
	if t == "vehicle":
		return true
	# Heuristics: if it lacks cargo_id and has vehicle-like stats
	if not item_data_source.has("cargo_id"):
		var vehish := ["top_speed", "max_speed", "speed", "efficiency", "offroad_capability", "cargo_capacity", "weight_capacity", "fuel_capacity", "kwh_capacity", "passenger_capacity"]
		for k in vehish:
			if item_data_source.has(k):
				return true
		if item_data_source.has("stats") and item_data_source.stats is Dictionary:
			var s: Dictionary = item_data_source.stats
			for k in vehish:
				if s.has(k):
					return true
	return false

func _update_install_button_state() -> void:
	if not is_instance_valid(install_button):
		return
	var is_buy_mode := trade_mode_tab_container.current_tab == 0
	var can_install := false
	if is_buy_mode and selected_item and selected_item.has("item_data"):
		var idata: Dictionary = selected_item.item_data
		can_install = _looks_like_part(idata)
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
			_update_inspector()

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

# Returns the price per unit for the given item, depending on buy/sell mode.
func _get_contextual_unit_price(item_data_source: Dictionary) -> float:
	var price: float = 0.0
	# Vehicles: prefer current value ("value"), fallback to market_value, then base_value
	if _is_vehicle(item_data_source):
		var cv = item_data_source.get("value")
		if (cv is float or cv is int) and float(cv) > 0.0:
			return float(cv)
		var mv = item_data_source.get("market_value")
		if (mv is float or mv is int) and float(mv) > 0.0:
			return float(mv)
		var bv = item_data_source.get("base_value")
		if bv is float or bv is int:
			return float(bv)
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
	if not is_instance_valid(gdm):
		printerr("VendorTradePanel: Cannot refresh data after transaction, GameDataManager is invalid.")
		return
	gdm.request_user_data_refresh()
	if convoy_data and convoy_data.has("convoy_id"):
		print("DEBUG: Requesting convoy data refresh after transaction.")
		gdm.request_convoy_data_refresh()
	if vendor_data and vendor_data.has("vendor_id"):
		print("DEBUG: Requesting vendor data refresh after transaction.")
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
	if is_instance_valid(fitment_rich_text):
		fitment_rich_text.text = ""
		fitment_rich_text.visible = false
	if is_instance_valid(fitment_panel):
		fitment_panel.visible = false
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

# --- Tutorial helpers ---
## Highlights a top-level category in the vendor tree (e.g., "Vehicles") if present and scrolls to it.
func tutorial_highlight_category(category_name: String) -> void:
	if not is_instance_valid(vendor_item_tree):
		return
	var root := vendor_item_tree.get_root()
	if root == null:
		return
	for it in root.get_children():
		if it == null:
			continue
		var label := str(it.get_text(0))
		if label.to_lower() == category_name.to_lower():
			# Ensure category is expanded for visibility
			it.collapsed = false
			it.select(0)
			vendor_item_tree.scroll_to_item(it)
			return

## Expands a top-level category in the vendor tree without changing selection
func tutorial_expand_category(category_name: String) -> void:
	if not is_instance_valid(vendor_item_tree):
		return
	var root := vendor_item_tree.get_root()
	if root == null:
		return
	for it in root.get_children():
		if it == null:
			continue
		var label := str(it.get_text(0))
		if label.to_lower() == category_name.to_lower():
			it.collapsed = false
			vendor_item_tree.scroll_to_item(it)
			return

## Convenience for stage 2: expand Resources and keep it open
func tutorial_open_resources() -> void:
	if not is_instance_valid(vendor_item_tree):
		return
	var root := vendor_item_tree.get_root()
	if root == null:
		return
	for cat in root.get_children():
		if cat == null:
			continue
		if str(cat.get_text(0)).to_lower() == "resources":
			cat.collapsed = false
			vendor_item_tree.scroll_to_item(cat)
			return

# --- Tutorial rectangle helpers ---
## Returns the global rect of a top-level category header in the vendor tree (e.g., "Vehicles").
func tutorial_get_category_header_rect_global(category_name: String) -> Rect2:
	if not is_instance_valid(vendor_item_tree):
		return Rect2()
	var root := vendor_item_tree.get_root()
	if root == null:
		return Rect2()
	for it in root.get_children():
		if it == null:
			continue
		var label := str(it.get_text(0))
		if label.to_lower() == category_name.to_lower():
			# Ensure it's expanded so the row has measurable size and doesn't immediately collapse
			it.collapsed = false
			var row_rect: Rect2 = vendor_item_tree.get_item_area_rect(it, 0)
			# Convert from tree local to global
			var top_left := vendor_item_tree.get_global_transform() * row_rect.position
			return Rect2(top_left, row_rect.size)
	return Rect2()

## Returns the global rect of the right-side Buy button
func tutorial_get_buy_button_global_rect() -> Rect2:
	if not is_instance_valid(action_button):
		return Rect2()
	var grect := action_button.get_global_rect()
	return grect

# Preferred: return the Control for the Buy button so callers can track it live
func tutorial_get_buy_button_control() -> Control:
	return action_button if is_instance_valid(action_button) else null

# --- Stage 2 helpers: selection and rects for item rows and quantity control ---
## Sets the quantity SpinBox value safely for tutorial use
func tutorial_set_quantity(qty: int) -> void:
	if not is_instance_valid(quantity_spinbox):
		return
	var q := int(qty)
	if q < int(quantity_spinbox.min_value):
		q = int(quantity_spinbox.min_value)
	if q > int(quantity_spinbox.max_value):
		q = int(quantity_spinbox.max_value)
	quantity_spinbox.value = q

## Selects an item whose display text starts with the given prefix in the vendor tree (buy tab)
func tutorial_select_item_by_prefix(prefix: String) -> void:
	# If tree isn't ready, defer selection until after population
	if not is_instance_valid(vendor_item_tree) or vendor_item_tree.get_root() == null:
		_pending_select_prefix = prefix
		print("VTP-DEBUG: tutorial_select_item_by_prefix deferred; tree not ready. prefix=", prefix)
		return
	_tutorial_try_select_prefix(prefix)

func tutorial_defer_select_item_by_prefix(prefix: String) -> void:
	_pending_select_prefix = prefix
	print("VTP-DEBUG: tutorial_defer_select_item_by_prefix set prefix=", prefix)

func _tutorial_try_select_prefix(prefix: String) -> void:
	if not is_instance_valid(vendor_item_tree):
		return
	var root := vendor_item_tree.get_root()
	if root == null:
		return
	for cat in root.get_children():
		for it in cat.get_children():
			var label := str(it.get_text(0))
			if label.begins_with(prefix):
				it.select(0)
				vendor_item_tree.scroll_to_item(it)
				# Trigger selection handler
				_on_vendor_item_selected()
				print("VTP-DEBUG: tutorial selected by prefix '", prefix, "' -> ", label)
				return

## Returns the global rect of an item row matching an exact display text (or startswith if exact not found)
func tutorial_get_item_row_rect_global(display_text: String) -> Rect2:
	if not is_instance_valid(vendor_item_tree):
		return Rect2()
	var root := vendor_item_tree.get_root()
	if root == null:
		return Rect2()
	var fallback: Rect2 = Rect2()
	for cat in root.get_children():
		for it in cat.get_children():
			var label := str(it.get_text(0))
			if label == display_text or label.begins_with(display_text):
				var rlocal: Rect2 = vendor_item_tree.get_item_area_rect(it, 0)
				var gpos := vendor_item_tree.get_global_transform() * rlocal.position
				return Rect2(gpos, rlocal.size)
			elif fallback == Rect2() and label.to_lower().find(display_text.to_lower()) != -1:
				var rlocal2: Rect2 = vendor_item_tree.get_item_area_rect(it, 0)
				var gpos2 := vendor_item_tree.get_global_transform() * rlocal2.position
				fallback = Rect2(gpos2, rlocal2.size)
	return fallback

## Returns the global rect of the quantity spinbox (right panel)
func tutorial_get_quantity_spinbox_rect_global() -> Rect2:
	if not is_instance_valid(quantity_spinbox):
		return Rect2()
	return quantity_spinbox.get_global_rect()

## Returns the global rect approximating the SpinBox's increment (up) button area
## Useful for tutorials to direct users to increase the quantity themselves.
func tutorial_get_quantity_increment_rect_global() -> Rect2:
	if not is_instance_valid(quantity_spinbox):
		return Rect2()
	var r: Rect2 = quantity_spinbox.get_global_rect()
	if r.size == Vector2.ZERO:
		return Rect2()
	# Try to use a theme metric; otherwise fall back to a heuristic width for the up/down control cluster
	var updown_w: float = 0.0
	if quantity_spinbox.has_theme_constant("updown"):
		updown_w = float(quantity_spinbox.get_theme_constant("updown"))
	if updown_w <= 0.0:
		updown_w = clamp(r.size.x * 0.3, 16.0, 28.0)
	var up_h: float = r.size.y * 0.5
	var pos := Vector2(r.position.x + r.size.x - updown_w, r.position.y)
	return Rect2(pos, Vector2(updown_w, up_h))

## Convenience for stage 1: expand Vehicles and keep it open
func tutorial_open_vehicles() -> void:
	if not is_instance_valid(vendor_item_tree):
		return
	var root := vendor_item_tree.get_root()
	if root == null:
		return
	for cat in root.get_children():
		if str(cat.get_text(0)).strip_edges().to_lower() == "vehicles":
			cat.collapsed = false
			vendor_item_tree.scroll_to_item(cat)
			return

## Returns the global rect of the first vehicle row under the Vehicles category, if available
func tutorial_get_first_vehicle_row_rect_global() -> Rect2:
	if not is_instance_valid(vendor_item_tree):
		return Rect2()
	var root := vendor_item_tree.get_root()
	if root == null:
		return Rect2()
	for cat in root.get_children():
		if str(cat.get_text(0)).strip_edges().to_lower() == "vehicles":
			var child := cat.get_first_child()
			while child != null and child.is_selectable(0) == false:
				child = child.get_next()
			if child != null:
				var rlocal: Rect2 = vendor_item_tree.get_item_area_rect(child, 0)
				var gpos := vendor_item_tree.get_global_transform() * rlocal.position
				return Rect2(gpos, rlocal.size)
			break
	return Rect2()

## Returns an Array of up to the first N vehicle row global rects
func tutorial_get_vehicle_row_rects_global(max_count: int = 3) -> Array:
	var rects: Array = []
	if not is_instance_valid(vendor_item_tree):
		return rects
	var root := vendor_item_tree.get_root()
	if root == null:
		return rects
	for cat in root.get_children():
		if str(cat.get_text(0)).strip_edges().to_lower() == "vehicles":
			var child := cat.get_first_child()
			while child != null and rects.size() < max_count:
				if child.is_selectable(0):
					var rlocal: Rect2 = vendor_item_tree.get_item_area_rect(child, 0)
					var gpos := vendor_item_tree.get_global_transform() * rlocal.position
					rects.append(Rect2(gpos, rlocal.size))
				child = child.get_next()
			break
	return rects
