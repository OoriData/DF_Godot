extends MenuBase
signal open_mechanics_menu_requested(convoy_data)
signal open_warehouse_menu_requested(convoy_data)

# Preload the new panel scene for instancing.
const VendorTradePanel = preload("res://Scenes/VendorTradePanel.tscn")

# Node references using @onready. Paths are relative to the node this script is attached to.
# %NodeName syntax is used for nodes with "unique_name_in_owner" enabled.
# $Path/To/Node is used for direct or indirect children without unique names.
@onready var title_label: Button = $MainVBox/TopBarHBox/TitleLabel
@onready var top_up_button: Button = $MainVBox/TopBarHBox/TopUpButton
@onready var top_bar_hbox: HBoxContainer = $MainVBox/TopBarHBox
@onready var vendor_tab_container = %VendorTabContainer
# The node 'SettlementInfoTab' is renamed to 'Settlement Info' by its 'name' property in the scene file.
# The SettlementInfoTab has been removed. All tabs are now dynamically generated.
@onready var back_button: Button = $MainVBox/BackButton
var mechanics_tab_vbox: VBoxContainer = null
var warehouse_button: Button = null

# This will be populated by MenuManager with the specific convoy's data.
var _convoy_data: Dictionary
# This will be populated once the settlement is found.
var _settlement_data: Dictionary
var _all_settlement_data: Array # Cached settlements snapshot

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _user_service: Node = get_node_or_null("/root/UserService")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")
@onready var _api: Node = get_node_or_null("/root/APICalls")

# Cached computed top-up plan
var _top_up_plan: Dictionary = {
	"total_cost": 0.0,
	"allocations": [], # Array of {res, vendor_id, vendor_name, price, quantity, subtotal}
	"resources": {}, # resource_type -> {total_quantity, total_cost}
	"planned_list": [] # ordered list (unique) of resource types included
}

# This function is called by MenuManager to pass the convoy data when the menu is opened.
func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
	print("ConvoySettlementMenu: initialize_with_data called.")
	if data_or_id is Dictionary:
		var d: Dictionary = data_or_id as Dictionary
		convoy_id = String(d.get("convoy_id", d.get("id", "")))
		_convoy_data = d
		# Set the main title to the convoy's name, fallback to 'name' if needed
		title_label.text = String(d.get("convoy_name", d.get("name", "Settlement Interactions")))
	else:
		convoy_id = String(data_or_id)
		_convoy_data = {}
	# Delegate initial UI to MenuBase; it will apply store snapshot when possible
	super.initialize_with_data(data_or_id, extra_arg)
	# Defer the display logic to ensure readiness
	print("ConvoySettlementMenu: initialize_with_data - Deferring _display_settlement_info.")
	call_deferred("_display_settlement_info")


func _ready():
	print("ConvoySettlementMenu: _ready() started processing.")
	# It's crucial to connect signals here for the UI to be interactive.
	if is_instance_valid(back_button):
		back_button.pressed.connect(_on_back_button_pressed)
	else:
		printerr("ConvoySettlementMenu: BackButton node not found.")
	
	# Connect the title label (now a Button) to go back to the convoy menu
	if is_instance_valid(title_label):
		if not title_label.is_connected("pressed", Callable(self, "_on_title_label_pressed")):
			title_label.pressed.connect(_on_title_label_pressed)

	# Connect top up button
	if is_instance_valid(top_up_button):
		if not top_up_button.is_connected("pressed", Callable(self, "_on_top_up_button_pressed")):
			top_up_button.pressed.connect(_on_top_up_button_pressed)
		_update_top_up_button()
		_style_top_up_button()

	# Add a Warehouse button to the top bar (only once)
	if is_instance_valid(top_bar_hbox):
		var existing_btn: Button = top_bar_hbox.get_node_or_null("WarehouseButton")
		if existing_btn == null:
			var warehouse_btn := Button.new()
			warehouse_btn.name = "WarehouseButton"
			warehouse_btn.text = "Warehouse"
			warehouse_btn.tooltip_text = "View or buy a Warehouse in this settlement"
			warehouse_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
			top_bar_hbox.add_child(warehouse_btn)

			warehouse_btn.pressed.connect(_on_warehouse_button_pressed)

		# Cache reference for later enable/disable
		warehouse_button = top_bar_hbox.get_node_or_null("WarehouseButton")
		if is_instance_valid(warehouse_button):
			warehouse_button.disabled = false

	# Subscribe to canonical snapshots (store 'convoys_changed' handled by MenuBase)
	if is_instance_valid(_store):
		if _store.has_signal("map_changed") and not _store.map_changed.is_connected(_on_store_map_changed):
			_store.map_changed.connect(_on_store_map_changed)
		if _store.has_signal("user_changed") and not _store.user_changed.is_connected(_on_store_user_changed):
			_store.user_changed.connect(_on_store_user_changed)

	# Also listen directly to APICalls transaction outcomes so we can trigger timely refreshes
	# Phase 4: UI no longer listens to APICalls transaction signals. Authoritative
	# refreshes are driven via services + GameStore/SignalHub events.


func _display_error(message: String):
	_clear_tabs()
	# Disable Top Up interactions when no settlement is present
	if is_instance_valid(top_up_button):
		top_up_button.disabled = true
		top_up_button.tooltip_text = "No settlement available at current location."

	# Hide tab headers for placeholder state
	if is_instance_valid(vendor_tab_container):
		if vendor_tab_container.has_method("set_tabs_visible"):
			vendor_tab_container.set_tabs_visible(false)
		else:
			var bar = get_vendor_tab_bar()
			if bar is Control:
				bar.visible = false

	# Leave the title as-is (convoy or settlement label) and add simple text directly
	if is_instance_valid(vendor_tab_container):
		var label := create_info_label(message)
		label.name = "InfoMessage"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vendor_tab_container.add_child(label)
		# Ensure any temporary info tab has a friendly title and won't look like a vendor
		if vendor_tab_container.get_tab_count() > 0:
			vendor_tab_container.set_tab_title(vendor_tab_container.get_tab_count() - 1, "Info")


func _display_settlement_info():
	if not is_instance_valid(_store) or not _store.has_method("get_tiles"):
		_display_error("GameStore not available. Cannot load settlement data.")
		return
	
	# Store the title of the currently selected tab before clearing everything.
	# This allows us to restore the selection if the menu is re-initialized.
	var previous_tab_title = ""
	if is_instance_valid(vendor_tab_container) and vendor_tab_container.get_tab_count() > 0 and vendor_tab_container.current_tab >= 0:
		previous_tab_title = vendor_tab_container.get_tab_title(vendor_tab_container.current_tab)

	_clear_tabs()

	# Get the convoy's current tile coordinates by rounding its float position.
	# The 'x' and 'y' in convoy_data are interpolated floats. We need integer tile coordinates.
	var current_convoy_x: int = roundi(float(_convoy_data.get("x", -1.0)))
	var current_convoy_y: int = roundi(float(_convoy_data.get("y", -1.0)))

	# Fetch settlements + tiles from GameStore snapshot
	_all_settlement_data = _store.get_settlements() if _store.has_method("get_settlements") else []
	if _all_settlement_data.is_empty():
		_display_error("Error: Settlement data not loaded.")

	var map_tiles: Array = _store.get_tiles()
	if map_tiles.is_empty():
		_display_error("Error: Map data not loaded.")
		return

	var target_tile = null

	# Direct lookup of the tile using coordinates, which is much more efficient than iterating.
	if current_convoy_y >= 0 and current_convoy_y < map_tiles.size():
		var row_array = map_tiles[current_convoy_y]
		if current_convoy_x >= 0 and current_convoy_x < row_array.size():
			target_tile = row_array[current_convoy_x]

	# Display information based on whether a settlement was found on the tile.
	if target_tile and target_tile.has("settlements") and target_tile.settlements is Array and not target_tile.settlements.is_empty():
		# Remove any placeholder info tab added earlier in error states
		for i in range(vendor_tab_container.get_tab_count() - 1, -1, -1):
			var tab_control: Node = vendor_tab_container.get_tab_control(i)
			if tab_control is Label and tab_control.name == "InfoMessage":
				vendor_tab_container.remove_child(tab_control)
				tab_control.queue_free()

		# When at a settlement, make sure tab headers are visible and warehouse enabled
		if is_instance_valid(vendor_tab_container):
			if vendor_tab_container.has_method("set_tabs_visible"):
				vendor_tab_container.set_tabs_visible(true)
			else:
				var bar = get_vendor_tab_bar()
				if bar is Control:
					bar.visible = true
		if is_instance_valid(warehouse_button):
			warehouse_button.disabled = false
		_settlement_data = target_tile.settlements[0] # Assuming we display info for the first settlement.

		if _settlement_data.has("vendors") and _settlement_data.vendors is Array and not _settlement_data.vendors.is_empty():
			# print("ConvoySettlementMenu: Found ", _settlement_data.vendors.size(), " vendors in settlement.") # Debug line

			for vendor in _settlement_data.vendors:
				_create_vendor_tab(vendor)

			# Tutorial Helper: If the tutorial is on Level 1, proactively select the Dealership tab
			# when this menu is first displayed. This avoids hardcoding tutorial logic that
			# can cause issues on other levels if the menu is re-initialized.
			var handled_by_tutorial = false
			var tutorial_manager = get_node_or_null("/root/GameRoot/TutorialManager")
			if is_instance_valid(tutorial_manager) and tutorial_manager.has_method("get_current_level"):
				if tutorial_manager.get_current_level() == 1:
					call_deferred("select_vendor_tab_by_title_contains", "Dealership")
					handled_by_tutorial = true

			# If the tutorial didn't force a tab, try to restore the previously selected one.
			if not handled_by_tutorial and not previous_tab_title.is_empty():
				for i in range(vendor_tab_container.get_tab_count()):
					if vendor_tab_container.get_tab_title(i) == previous_tab_title:
						vendor_tab_container.current_tab = i
						break
			
			# After creating vendor tabs compute top up plan
			_update_top_up_button()

	else:
		# No settlement on this tile (likely in transit). Show convoy name and disable settlement-only controls.
		if is_instance_valid(title_label):
			var convoy_name: String = String(_convoy_data.get("convoy_name", title_label.text))
			if not convoy_name.is_empty():
				title_label.text = convoy_name
		if is_instance_valid(warehouse_button):
			warehouse_button.disabled = true
			warehouse_button.tooltip_text = "Warehouse unavailable while in transit."
		_display_error("No settlement found at convoy coordinates: (%d, %d)" % [current_convoy_x, current_convoy_y])


func _on_store_convoys_changed(all_convoys_data: Array) -> void:
	_apply_convoy_snapshot_update(all_convoys_data)


func _on_store_map_changed(_tiles: Array, all_settlements_data: Array) -> void:
	# Cache latest settlements and re-display based on current convoy coords.
	_all_settlement_data = all_settlements_data
	call_deferred("_display_settlement_info")

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
	# Forward install requests to open mechanics with a prefilled cart
	if vendor_panel_instance.has_signal("install_requested"):
		vendor_panel_instance.install_requested.connect(_on_install_requested)

func _update_ui(convoy: Dictionary) -> void:
	# Smart refresh: only rebuild tabs if we moved to a new tile.
	var old_data = _convoy_data
	_convoy_data = convoy.duplicate(true)
	
	if is_instance_valid(title_label):
		title_label.text = String(_convoy_data.get("convoy_name", title_label.text))

	var old_x = int(round(float(old_data.get("x", -9999))))
	var old_y = int(round(float(old_data.get("y", -9999))))
	var new_x = int(round(float(_convoy_data.get("x", -9999))))
	var new_y = int(round(float(_convoy_data.get("y", -9999))))

	if old_x != new_x or old_y != new_y or (is_instance_valid(vendor_tab_container) and vendor_tab_container.get_tab_count() == 0):
		call_deferred("_display_settlement_info")
	else:
		_update_top_up_button()

func _clear_tabs():
	# Remove all dynamically added vendor tabs, starting from the end.
	if not is_instance_valid(vendor_tab_container):
		printerr("ConvoySettlementMenu: vendor_tab_container is invalid in _clear_tabs().")
		return
	# Remove all dynamically added tabs using TabContainer API to avoid removing non-tab children.
	for i in range(vendor_tab_container.get_tab_count() - 1, -1, -1):
		var tab_control = vendor_tab_container.get_tab_control(i)
		if is_instance_valid(tab_control):
			vendor_tab_container.remove_child(tab_control)
			tab_control.queue_free()
	mechanics_tab_vbox = null

## Mechanics tab removed: Mechanics is now opened contextually via Install from vendor part purchase.

func _on_install_requested(item: Dictionary, quantity: int, vendor_id_from_panel: String = "") -> void:
	# Build a prefill payload for Mechanics and navigate there
	if not _convoy_data or not _convoy_data.has("convoy_id"):
		return
	# Prefer vendor_id provided by the panel; fallback to what's embedded in item or lookup by mission vendor name
	var effective_vendor_id := vendor_id_from_panel
	if effective_vendor_id == "":
		effective_vendor_id = String(item.get("vendor_id", ""))
	if effective_vendor_id == "" and item.has("mission_vendor_name"):
		var found := _find_vendor_by_name(String(item.get("mission_vendor_name", "")))
		if found is Dictionary and found.has("vendor_id"):
			effective_vendor_id = String(found.get("vendor_id", ""))

	var payload := {
		"_mechanic_prefill": {
			"part": item.duplicate(true),
			"quantity": int(quantity),
			"vendor_id": effective_vendor_id
		}
	}
	var next_data := _convoy_data.duplicate(true)
	# Attach the payload fields to convoy data; mechanics will consume _mechanic_prefill
	for k in payload.keys():
		next_data[k] = payload[k]
	emit_signal("open_mechanics_menu_requested", next_data)

func _on_warehouse_button_pressed() -> void:
	# Open the Warehouse menu for this convoy/settlement context
	if not (_convoy_data is Dictionary) or not _convoy_data.has("convoy_id"):
		push_warning("Convoy data unavailable; cannot open Warehouse menu.")
		return
	var payload := _convoy_data.duplicate(true)
	# Attach settlement snapshot if available so WarehouseMenu knows where we are
	if _settlement_data is Dictionary and not _settlement_data.is_empty():
		payload["settlement"] = _settlement_data.duplicate(true)
	else:
		# Fallback: resolve settlement name from GameStore snapshot
		var sett_name := _get_settlement_name_from_convoy_coords()
		if sett_name != "":
			payload["settlement_name"] = sett_name
	emit_signal("open_warehouse_menu_requested", payload)

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

func _on_item_purchased(_item: Dictionary, _quantity: int, _total_cost: float):
	# Money/convoy updates are authoritative; request fresh snapshots.
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()
	if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(str(_convoy_data.get("convoy_id", "")))

func _on_item_sold(_item: Dictionary, _quantity: int, _total_value: float):
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()
	if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(str(_convoy_data.get("convoy_id", "")))

func _apply_convoy_snapshot_update(all_convoys_data: Array) -> void:
	# Find the current convoy and update _convoy_data, then refresh UI
	if not _convoy_data or not _convoy_data.has("convoy_id"):
		return
	var current_id = str(_convoy_data.get("convoy_id"))
	for convoy in all_convoys_data:
		if convoy.has("convoy_id") and str(convoy.get("convoy_id")) == current_id:
			_convoy_data = convoy.duplicate(true)
			_refresh_all_vendor_panels()
			_update_top_up_button()
			break

func _apply_settlement_snapshot_update(all_settlements_data: Array) -> void:
	# Find the current settlement and update _settlement_data, then refresh UI
	if not _settlement_data or not _settlement_data.has("sett_id"):
		return
	var current_id = str(_settlement_data.get("sett_id"))
	for settlement in all_settlements_data:
		if settlement.has("sett_id") and str(settlement.get("sett_id")) == current_id:
			_settlement_data = settlement.duplicate(true)
			_refresh_all_vendor_panels()
			_update_top_up_button()
			break

# --- Direct API transaction handlers ---
func _on_api_resource_txn(_result: Dictionary) -> void:
	# Deprecated: previously handled APICalls transaction signals. Kept for compatibility.
	# Now refreshes are triggered directly after initiating transactions.
	var convoy_uuid := str(_convoy_data.get("convoy_id", ""))
	if convoy_uuid != "" and is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(convoy_uuid)
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()
	call_deferred("_post_txn_update_ui")

func _on_api_other_txn(_result: Dictionary) -> void:
	# Cargo / vehicle transactions also alter convoy state.
	_on_api_resource_txn(_result)

func _post_txn_update_ui():
	_refresh_all_vendor_panels()
	_update_top_up_button()
	if is_instance_valid(top_up_button) and top_up_button.disabled:
		top_up_button.disabled = false
		_update_top_up_button()

func _refresh_all_vendor_panels():
	# Only call refresh_data, never initialize, and always pass deep copies.
	# IMPORTANT: Skip refreshing the currently active vendor tab; the active
	# panel already performs its own authoritative refresh
	# vendor_panel_data_ready. Double-refreshing it causes selection flicker
	# during transactions.
	var active_idx: int = vendor_tab_container.current_tab
	for i in range(vendor_tab_container.get_tab_count()):
		if i == active_idx:
			continue
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
	# Also refresh top up button when vendor data may have changed
	_update_top_up_button()

func _find_vendor_by_name(vendor_name: String) -> Dictionary:
	if _settlement_data and _settlement_data.has("vendors"):
		for vendor in _settlement_data.vendors:
			if vendor.get("name", "") == vendor_name:
				return vendor
	return {}


# --- Top Up Feature ---

const TOP_UP_RESOURCES := ["fuel", "water", "food"]

func _update_top_up_button():
	if not is_instance_valid(top_up_button):
		return
	if _settlement_data.is_empty() or not _settlement_data.has("vendors"):
		top_up_button.text = "Top Up (No Vendors)"
		top_up_button.disabled = true
		top_up_button.tooltip_text = "No vendors present in this settlement."
		return
	if _convoy_data.is_empty():
		top_up_button.text = "Top Up (No Convoy)"
		top_up_button.disabled = true
		top_up_button.tooltip_text = "Convoy data unavailable."
		return

	_top_up_plan = _calculate_top_up_plan()
	var planned_list: Array = _top_up_plan.get("planned_list", [])
	var total_cost: float = _top_up_plan.get("total_cost", 0.0)
	if planned_list.is_empty():
		top_up_button.text = "Top Up (Full)"
		top_up_button.disabled = true
		top_up_button.tooltip_text = "Fuel, Water and Food are already at maximum levels."
		return

	var user_money: float = 0.0
	if is_instance_valid(_user_service) and _user_service.has_method("get_user"):
		var user_data: Dictionary = _user_service.get_user()
		user_money = float(user_data.get("money", 0.0))
	var can_afford = total_cost <= user_money + 0.0001
	var _label_resources = ", ".join(planned_list)
	top_up_button.text = "Top Up"
	top_up_button.disabled = not can_afford
	if not can_afford:
		top_up_button.text += " !"

	# Build tooltip breakdown (group by resource, showing each vendor line)
	var breakdown_lines: Array = []
	var allocations_by_res: Dictionary = {}
	for alloc in _top_up_plan.allocations:
		var r = String(alloc.get("res",""))
		if r == "":
			continue
		if not allocations_by_res.has(r):
			allocations_by_res[r] = []
		allocations_by_res[r].append(alloc)
	for r in allocations_by_res.keys():
		var group:Array = allocations_by_res[r]
		group.sort_custom(func(a,b): return float(a.price) < float(b.price))
		var res_total_qty:int = 0
		var res_total_cost:float = 0.0
		breakdown_lines.append(r.capitalize() + ":")
		for g in group:
			var qty_i = int(g.get("quantity",0))
			var price_i = float(g.get("price",0.0))
			var vendor_name = String(g.get("vendor_name","?"))
			var sub_i = float(qty_i) * price_i
			res_total_qty += qty_i
			res_total_cost += sub_i
			breakdown_lines.append("  %s: %d @ $%.2f = $%.0f" % [vendor_name, qty_i, price_i, sub_i])
		breakdown_lines.append("  Subtotal %s: %d = $%.0f" % [r, res_total_qty, res_total_cost])
	breakdown_lines.append("Total: $%.0f" % total_cost)
	if not can_afford:
		var deficit = max(0.0, total_cost - user_money)
		breakdown_lines.append("Insufficient funds (need $%.0f more)." % deficit)
	top_up_button.tooltip_text = "Top Up Plan:\n" + "\n".join(breakdown_lines)

func _calculate_top_up_plan() -> Dictionary:
	var plan: Dictionary = {"total_cost": 0.0, "allocations": [], "resources": {}, "planned_list": []}
	if _settlement_data.is_empty() or not _settlement_data.has("vendors"):
		return plan
	var convoy = _convoy_data
	if convoy.is_empty():
		return plan

	# Determine fill percentage order (lowest first)
	var res_fill_pairs: Array = []
	for res in TOP_UP_RESOURCES:
		var current = float(convoy.get(res, 0.0))
		var maximum = float(convoy.get("max_" + res, 0.0))
		var fill = 1.0
		if maximum > 0.001:
			fill = current / maximum
		res_fill_pairs.append({"res": res, "fill": fill})
	res_fill_pairs.sort_custom(func(a, b): return a.fill < b.fill)

	# Basic weight limiting (optional) using total_remaining_capacity if present
	var remaining_weight = float(convoy.get("total_remaining_capacity", 999999.0))
	var weight_limited = remaining_weight <= 0.001
	# Optional resource weights (if present inside convoy misc or weights dict)
	var resource_weights: Dictionary = convoy.get("resource_weights", {})

	for pair in res_fill_pairs:
		var res = pair.res
		var current_amount = float(convoy.get(res, 0.0))
		var max_amount = float(convoy.get("max_" + res, 0.0))
		var needed_exact = max(max_amount - current_amount, 0.0)
		var needed_remaining = int(floor(needed_exact + 0.0001))
		if needed_remaining <= 0:
			continue
		var price_key = res + "_price"
		# Gather vendors with price & stock
		var vendor_candidates: Array = []
		for v in _settlement_data.get("vendors", []):
			if v.has(price_key) and v[price_key] != null and v.has(res):
				var stock_available = int(v.get(res, 0))
				var price = float(v.get(price_key, 0.0))
				if stock_available > 0 and price > 0:
					vendor_candidates.append({"vendor": v, "price": price, "stock": stock_available})
		if vendor_candidates.is_empty():
			continue
		# Sort by ascending price
		vendor_candidates.sort_custom(func(a,b): return a.price < b.price)
		var weight_per_unit = float(resource_weights.get(res, 1.0))
		if weight_per_unit <= 0: weight_per_unit = 1.0
		var any_allocated = false
		for cand in vendor_candidates:
			if needed_remaining <= 0:
				break
			if not weight_limited and remaining_weight <= 0.0:
				break
			var take_qty = min(needed_remaining, int(cand.stock))
			if not weight_limited and remaining_weight < 999998:
				var max_by_weight = int(floor(remaining_weight / weight_per_unit))
				take_qty = min(take_qty, max_by_weight)
			if take_qty <= 0:
				continue
			var vdict: Dictionary = cand.vendor
			var vendor_id = str(vdict.get("vendor_id", ""))
			var vendor_name = str(vdict.get("name", "Vendor"))
			var price = float(cand.price)
			var subtotal = float(take_qty) * price
			plan.allocations.append({
				"res": res,
				"vendor_id": vendor_id,
				"vendor_name": vendor_name,
				"price": price,
				"quantity": take_qty,
				"subtotal": subtotal
			})
			plan.total_cost += subtotal
			needed_remaining -= take_qty
			any_allocated = true
			if not weight_limited:
				remaining_weight -= float(take_qty) * weight_per_unit
				if remaining_weight <= 0:
					remaining_weight = 0
					break
		if any_allocated:
			if not plan.resources.has(res):
				plan.resources[res] = {"total_quantity": 0, "total_cost": 0.0}
			# Aggregate totals for resource
			for alloc in plan.allocations:
				if alloc.res == res:
					plan.resources[res].total_quantity += int(alloc.quantity)
					plan.resources[res].total_cost += float(alloc.subtotal)
			plan.planned_list.append(res)
	return plan

func _on_top_up_button_pressed():
	if _top_up_plan.is_empty() or _top_up_plan.get("resources", {}).is_empty():
		return
	var convoy_uuid = str(_convoy_data.get("convoy_id", ""))
	if convoy_uuid.is_empty():
		return
	if not is_instance_valid(_api):
		return
	# Execute purchases individually (one PATCH per resource) based on current plan snapshot.
	for alloc in _top_up_plan.allocations:
		var res = alloc.get("res", "")
		var vendor_id = str(alloc.get("vendor_id", ""))
		var send_qty:int = int(alloc.get("quantity", 0))
		if res == "" or vendor_id.is_empty() or send_qty <= 0:
			continue
		print("[TopUp] Purchasing %d %s from vendor %s (price=%.2f) convoy=%s" % [send_qty, res, vendor_id, float(alloc.get("price",0.0)), convoy_uuid])
		# Raw resources use dedicated API call
		_api.buy_resource(vendor_id, convoy_uuid, String(res), float(send_qty))
	# Immediately trigger authoritative refreshes via services; UI updates via Store/Hub
	if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(convoy_uuid)
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()
	# Disable button until data refresh comes back
	if is_instance_valid(top_up_button):
		top_up_button.disabled = true
		top_up_button.text = "Top Up (Processing...)"


func _on_store_user_changed(_user: Dictionary) -> void:
	# Money changes affect top-up affordability/tooltips.
	_update_top_up_button()


func _get_settlement_name_from_convoy_coords() -> String:
	if not (_convoy_data is Dictionary):
		return ""
	if not is_instance_valid(_store) or not _store.has_method("get_tiles"):
		return ""
	var sx := int(roundf(float(_convoy_data.get("x", -9999.0))))
	var sy := int(roundf(float(_convoy_data.get("y", -9999.0))))
	if sx < 0 or sy < 0:
		return ""
	var tiles: Array = _store.get_tiles()
	if sy >= 0 and sy < tiles.size():
		var row: Variant = tiles[sy]
		if row is Array and sx >= 0 and sx < (row as Array).size():
			var tile: Variant = (row as Array)[sx]
			if tile is Dictionary and tile.has("settlements") and tile.settlements is Array and not tile.settlements.is_empty():
				var s0: Variant = tile.settlements[0]
				if s0 is Dictionary and (s0 as Dictionary).has("name"):
					return String((s0 as Dictionary).get("name", ""))
				elif s0 is String:
					return String(s0)
	# Fallback: scan settlements snapshot by coords
	if _store.has_method("get_settlements"):
		for s in _store.get_settlements():
			if s is Dictionary:
				var sx2 := int(roundf(float(s.get("x", -9999.0))))
				var sy2 := int(roundf(float(s.get("y", -9999.0))))
				if sx2 == sx and sy2 == sy:
					return String(s.get("name", ""))
	return ""

func _style_top_up_button():
	if not is_instance_valid(top_up_button):
		return
	# --- Button StyleBoxes ---
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.15, 0.18, 1.0)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.40, 0.60, 0.90)
	normal.shadow_color = Color(0,0,0,0.6)
	normal.shadow_size = 3

	var hover = normal.duplicate()
	hover.bg_color = Color(0.22, 0.22, 0.28, 1.0)
	hover.border_color = Color(0.55, 0.75, 1.0)

	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.10, 0.10, 0.14, 1.0)
	pressed.border_color = Color(0.30, 0.50, 0.80)

	var disabled = normal.duplicate()
	disabled.bg_color = Color(0.08, 0.08, 0.09, 1.0)
	disabled.border_color = Color(0.20, 0.20, 0.20)
	disabled.shadow_size = 0

	top_up_button.add_theme_stylebox_override("normal", normal)
	top_up_button.add_theme_stylebox_override("hover", hover)
	top_up_button.add_theme_stylebox_override("pressed", pressed)
	top_up_button.add_theme_stylebox_override("disabled", disabled)

	# --- Tooltip Style ---
	var tooltip_panel = StyleBoxFlat.new()
	# Make fully opaque for readability (user requested less transparency)
	tooltip_panel.bg_color = Color(0.05, 0.05, 0.06, 1.0)
	tooltip_panel.corner_radius_top_left = 4
	tooltip_panel.corner_radius_top_right = 4
	tooltip_panel.corner_radius_bottom_left = 4
	tooltip_panel.corner_radius_bottom_right = 4
	tooltip_panel.border_color = Color(0.60, 0.60, 0.70)
	tooltip_panel.border_width_left = 1
	tooltip_panel.border_width_right = 1
	tooltip_panel.border_width_top = 1
	tooltip_panel.border_width_bottom = 1
	tooltip_panel.shadow_color = Color(0,0,0,0.7)
	tooltip_panel.shadow_size = 4
	# Extra padding inside tooltip for clarity
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		tooltip_panel.set_content_margin(side, 6)
	top_up_button.add_theme_stylebox_override("tooltip_panel", tooltip_panel)

	# --- Font & Colors ---
	top_up_button.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	top_up_button.add_theme_color_override("font_color_hover", Color(1.0, 1.0, 1.0))
	top_up_button.add_theme_color_override("font_color_pressed", Color(0.85, 0.90, 1.0))
	top_up_button.add_theme_color_override("font_color_disabled", Color(0.55, 0.55, 0.60))
	# Slightly larger font to pop
	top_up_button.add_theme_font_size_override("font_size", 18)

	# Optional: Increase content margin for a beefier look
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		normal.set_content_margin(side, normal.get_content_margin(side) + 2)
		hover.set_content_margin(side, hover.get_content_margin(side) + 2)
		pressed.set_content_margin(side, pressed.get_content_margin(side) + 2)
		disabled.set_content_margin(side, disabled.get_content_margin(side) + 2)


# --- Custom Tooltip Override ---
# Godot will call _make_custom_tooltip on the Control that has the tooltip_text set (this script's node),
# allowing us to supply a high-contrast, fully opaque tooltip. This improves readability beyond simple
# theme overrides, which may not always apply depending on global theme inheritance.
## Custom tooltip now handled directly by TopUpButton script (top_up_button_tooltip.gd)

# --- Tutorial helper methods: stable target resolution for tabs/panels ---

# Return the TabBar used by the VendorTabContainer (if available)
func get_vendor_tab_bar() -> Node:
	if is_instance_valid(vendor_tab_container) and vendor_tab_container.has_method("get_tab_bar"):
		return vendor_tab_container.get_tab_bar()
	return null

# Find the rect of a vendor tab whose title contains the given substring (case-insensitive)
func get_vendor_tab_rect_by_title_contains(substr: String) -> Rect2:
	if not is_instance_valid(vendor_tab_container):
		return Rect2()
	var bar = get_vendor_tab_bar()
	if bar == null:
		return Rect2()
	var needle := substr.to_lower()
	for i in range(vendor_tab_container.get_tab_count()):
		var title := String(vendor_tab_container.get_tab_title(i))
		if title.to_lower().find(needle) != -1:
			if bar.has_method("get_tab_rect"):
				var local_r: Rect2 = bar.get_tab_rect(i)
				var bar_global := (bar as Control).get_global_rect()
				return Rect2(bar_global.position + local_r.position, local_r.size)
			# Fallback to whole bar rect if API not present
			return (bar as Control).get_global_rect()
	return Rect2()

# Select a vendor tab by title contains; returns true if selection changed
func select_vendor_tab_by_title_contains(substr: String) -> bool:
	if not is_instance_valid(vendor_tab_container):
		return false
	var needle := substr.to_lower()
	for i in range(vendor_tab_container.get_tab_count()):
		var title := String(vendor_tab_container.get_tab_title(i))
		if title.to_lower().find(needle) != -1:
			if vendor_tab_container.current_tab != i:
				vendor_tab_container.current_tab = i
			return true
	return false

# Return the active vendor panel node (content of the current tab)
func get_active_vendor_panel_node() -> Node:
	if not is_instance_valid(vendor_tab_container):
		return null
	return vendor_tab_container.get_tab_control(vendor_tab_container.current_tab)
