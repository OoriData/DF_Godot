extends Control

# Emitted when the user clicks the back button. MenuManager listens for this.
signal back_requested
signal open_mechanics_menu_requested(convoy_data)
signal open_warehouse_menu_requested(convoy_data)
signal tabs_ready

# Preload the new panel scene for instancing.
const VendorTradePanel = preload("res://Scenes/VendorTradePanel.tscn")

# Node references using @onready. Paths are relative to the node this script is attached to.
# %NodeName syntax is used for nodes with "unique_name_in_owner" enabled.
# $Path/To/Node is used for direct or indirect children without unique names.
@onready var title_label: Button = $MainVBox/TopBarHBox/TitleLabel
@onready var top_up_button: Button = $MainVBox/TopBarHBox/TopUpButton
@onready var top_bar_hbox: HBoxContainer = $MainVBox/TopBarHBox
@onready var vendor_tab_container = %VendorTabContainer
@onready var settlement_content_vbox = %SettlementContentVBox
@onready var back_button = $MainVBox/BackButton
var mechanics_tab_vbox: VBoxContainer = null

# This will be populated by MenuManager with the specific convoy's data.
var _convoy_data: Dictionary
# This will be populated once the settlement is found.
var _settlement_data: Dictionary
var _all_settlement_data: Array # New: To store all settlement data from GameDataManager

# Add a reference to GameDataManager
var gdm: Node = null
# Debounce flags to avoid rapid repeated refresh causing flicker
var _ui_refresh_pending: bool = false

# Cached computed top-up plan
var _top_up_plan: Dictionary = {
	"total_cost": 0.0,
	"allocations": [], # Array of {res, vendor_id, vendor_name, price, quantity, subtotal}
	"resources": {}, # resource_type -> {total_quantity, total_cost}
	"planned_list": [] # ordered list (unique) of resource types included
}

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

	# Connect to GameDataManager signals to refresh UI when data updates
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_gdm_convoy_data_updated")):
			gdm.convoy_data_updated.connect(_on_gdm_convoy_data_updated)
		if not gdm.is_connected("settlement_data_updated", Callable(self, "_on_gdm_settlement_data_updated")):
			gdm.settlement_data_updated.connect(_on_gdm_settlement_data_updated)

	# Also listen directly to APICalls resource transactions so we can trigger timely refreshes
	var api = get_node_or_null("/root/APICalls")
	if is_instance_valid(api):
		if api.has_signal("resource_bought") and not api.resource_bought.is_connected(_on_api_resource_txn):
			api.resource_bought.connect(_on_api_resource_txn)
		if api.has_signal("resource_sold") and not api.resource_sold.is_connected(_on_api_resource_txn):
			api.resource_sold.connect(_on_api_resource_txn)
		# Fallback: cargo/vehicle transactions also imply convoy changes
		for sig in ["cargo_bought", "cargo_sold", "vehicle_bought", "vehicle_sold"]:
			if api.has_signal(sig):
				var callable = Callable(self, "_on_api_other_txn")
				var already=false
				match sig:
					"cargo_bought": already = api.cargo_bought.is_connected(callable)
					"cargo_sold": already = api.cargo_sold.is_connected(callable)
					"vehicle_bought": already = api.vehicle_bought.is_connected(callable)
					"vehicle_sold": already = api.vehicle_sold.is_connected(callable)
				if not already:
					match sig:
						"cargo_bought": api.cargo_bought.connect(_on_api_other_txn)
						"cargo_sold": api.cargo_sold.connect(_on_api_other_txn)
						"vehicle_bought": api.vehicle_bought.connect(_on_api_other_txn)
						"vehicle_sold": api.vehicle_sold.connect(_on_api_other_txn)


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
	gdm = get_node_or_null("/root/GameDataManager")
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
			# Ensure vendor tabs are created in a deterministic order so tutorial steps remain consistent.
			var vendors_sorted: Array = _settlement_data.vendors.duplicate(true)
			vendors_sorted.sort_custom(func(a, b):
				var ka:Array = _vendor_order_key(a)
				var kb:Array = _vendor_order_key(b)
				# 1) Primary: category index (lower first)
				if int(ka[0]) != int(kb[0]):
					return int(ka[0]) < int(kb[0])
				# 2) Secondary (within-category): optional subpriority (lower first) if provided
				var a_has_sub := ka.size() > 1 and typeof(ka[1]) == TYPE_INT
				var b_has_sub := kb.size() > 1 and typeof(kb[1]) == TYPE_INT
				if a_has_sub or b_has_sub:
					if a_has_sub and not b_has_sub:
						return true
					if b_has_sub and not a_has_sub:
						return false
					if int(ka[1]) != int(kb[1]):
						return int(ka[1]) < int(kb[1])
				# 3) Tertiary: alphabetical by short display name
				var na := _vendor_short_display_name(a).to_lower()
				var nb := _vendor_short_display_name(b).to_lower()
				return na < nb
			)

			for vendor in vendors_sorted:
				_create_vendor_tab(vendor)
			# Removed the old Mechanics tab vendor. Mechanics is now accessed via Install on parts within each vendor.

			# After creating vendor tabs compute top up plan
			_update_top_up_button()
			# Notify listeners (e.g., tutorial) that tabs are built and ready
			tabs_ready.emit()

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
	# Log tab creation and category for debugging/tutorial targeting
	var created_index: int = int(vendor_tab_container.get_tab_count() - 1)
	var cat_idx: int = int(_vendor_category_index(vendor_data))
	print("[ConvoySettlementMenu] Added vendor tab index=", created_index, " title='", short_vendor_name, "' full_name='", vendor_name, "' category_idx=", cat_idx)
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
	mechanics_tab_vbox = null

# --- Tutorial helper: return the global rect of the Dealership tab header ---
func tutorial_get_dealership_tab_rect_global() -> Rect2:
	if not is_instance_valid(vendor_tab_container):
		return Rect2()
	var tc: TabContainer = vendor_tab_container
	var tab_bar: Control = null
	if tc.has_method("get_tab_bar"):
		tab_bar = tc.call("get_tab_bar")
	if tab_bar == null:
		# Try common child paths
		tab_bar = tc.find_child("TabBar", true, false)
	if tab_bar == null:
		for ch in tc.get_children():
			if ch is Control and String(ch.get_class()).to_lower().find("tabbar") != -1:
				tab_bar = ch
				break
	if tab_bar == null or not tab_bar.has_method("get_tab_rect"):
		print("[ConvoySettlementMenu][Tutor] TabBar not found or missing get_tab_rect; cannot compute dealership tab rect.")
		return Rect2()
	var count := tc.get_tab_count()
	print("[ConvoySettlementMenu][Tutor] Tab count=", count)
	# Always use the absolute TabContainer index (includes 'Settlement Info' at 0)
	var dealership_index := int(tutorial_get_dealership_tab_index())
	if dealership_index < 0 or dealership_index >= count:
		# Extra debug of titles to help diagnose
		var titles: Array = []
		for i in range(count):
			titles.append(String(tc.get_tab_title(i)))
		print("[ConvoySettlementMenu][Tutor] Invalid dealership index=", dealership_index, " Titles=", titles)
		return Rect2()
	var rect_local: Rect2 = tab_bar.call("get_tab_rect", dealership_index)
	if rect_local.size == Vector2.ZERO:
		await get_tree().process_frame
		rect_local = tab_bar.call("get_tab_rect", dealership_index)
		if rect_local.size == Vector2.ZERO:
			print("[ConvoySettlementMenu][Tutor] get_tab_rect still zero after wait; index=", dealership_index)
			return Rect2()
	var pos_global: Vector2 = tab_bar.get_global_transform() * rect_local.position
	var result := Rect2(pos_global, rect_local.size)
	print("[ConvoySettlementMenu][Tutor] Dealership tab index=", dealership_index, " rect_local=", rect_local, " rect_global=", result)
	return result

# --- Tutorial helper: return the index of the Dealership tab ---
func tutorial_get_dealership_tab_index() -> int:
	if not is_instance_valid(vendor_tab_container):
		return -1
	var tc: TabContainer = vendor_tab_container
	var count := tc.get_tab_count()
	var dealer_abs := -1
	var path_used := "title-exact"
	# 1) Primary: exact tab title match (case-insensitive) to 'Dealership'
	for t in range(count):
		var title_ci := String(tc.get_tab_title(t)).strip_edges().to_lower()
		if title_ci == "dealership":
			dealer_abs = t
			break
	# 2) Fallback by vendor full name containing 'dealership'
	if dealer_abs == -1:
		path_used = "name-fallback"
		for j in range(count):
			var tab_ctrl2: Node = tc.get_tab_control(j)
			if tab_ctrl2 == null:
				continue
			var full_name2 := String(tab_ctrl2.name).to_lower()
			if full_name2.find("dealership") != -1:
				dealer_abs = j
				break
	# 3) Final fallback: vendor classification (inventory-based)
	if dealer_abs == -1:
		path_used = "classification"
		for i in range(count):
			var tab_ctrl: Node = tc.get_tab_control(i)
			if tab_ctrl == null:
				continue
			var full_vendor_name := String(tab_ctrl.name)
			var vendor_dict := _find_vendor_by_name(full_vendor_name)
			if vendor_dict is Dictionary and not vendor_dict.is_empty():
				var v_idx := _vendor_category_index(vendor_dict)
				if v_idx == 2:
					dealer_abs = i
					break
	# One-time debug print of titles to verify absolute mapping
	var titles_dbg: Array = []
	for k in range(count):
		titles_dbg.append(String(tc.get_tab_title(k)))
	print("[ConvoySettlementMenu][Tutor] tutorial_get_dealership_tab_index -> ", dealer_abs, " via=", path_used, " titles=", titles_dbg)
	return dealer_abs

# --- Tutorial helper: create a proxy Control over the dealership tab header for reliable highlighting ---
var _tutor_tab_proxy: Control = null
var _tutor_tab_proxy_updater: Callable = Callable() # to disconnect on clear
var _tutor_tab_proxy_tabbar: Control = null

func tutorial_build_dealership_tab_highlight_proxy() -> Control:
	if not is_instance_valid(vendor_tab_container):
		return null
	var tc2: TabContainer = vendor_tab_container
	var tab_bar2: Control = null
	if tc2.has_method("get_tab_bar"):
		tab_bar2 = tc2.call("get_tab_bar")
	if tab_bar2 == null:
		tab_bar2 = tc2.find_child("TabBar", true, false)
	if tab_bar2 == null or not tab_bar2.has_method("get_tab_rect"):
		return null
	var idx2 := int(tutorial_get_dealership_tab_index())
	if idx2 < 0:
		return null
	var rl2: Rect2 = tab_bar2.call("get_tab_rect", idx2)
	if rl2.size == Vector2.ZERO:
		await get_tree().process_frame
		rl2 = tab_bar2.call("get_tab_rect", idx2)
		if rl2.size == Vector2.ZERO:
			return null
	tutorial_clear_tab_highlight_proxy()
	var proxy := Control.new()
	proxy.name = "TutorTabProxy"
	# Ignore mouse so it never blocks clicks; keep as child of TabBar so it tracks layout
	proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	proxy.anchor_left = 0
	proxy.anchor_right = 0
	proxy.anchor_top = 0
	proxy.anchor_bottom = 0
	proxy.position = rl2.position
	proxy.size = rl2.size
	tab_bar2.add_child(proxy)
	proxy.z_index = 1000
	# Keep proxy sticky to the tab header by updating on TabBar size/visibility changes
	var updater := func():
		if is_instance_valid(tab_bar2):
			var rnow: Rect2 = tab_bar2.call("get_tab_rect", idx2)
			proxy.position = rnow.position
			proxy.size = rnow.size
	# Store references so we can disconnect later
	_tutor_tab_proxy_updater = updater
	_tutor_tab_proxy_tabbar = tab_bar2
	# Connect supported signals; avoid duplicate connects
	if is_instance_valid(tab_bar2):
		if not tab_bar2.resized.is_connected(updater):
			tab_bar2.resized.connect(updater)
		if not tab_bar2.visibility_changed.is_connected(updater):
			tab_bar2.visibility_changed.connect(updater)
	# One immediate update in case the rect changed after creation
	updater.call()
	_tutor_tab_proxy = proxy
	return proxy

func tutorial_clear_tab_highlight_proxy() -> void:
	if is_instance_valid(_tutor_tab_proxy):
		var parent := _tutor_tab_proxy.get_parent()
		if parent:
			parent.remove_child(_tutor_tab_proxy)
		_tutor_tab_proxy.queue_free()
	# Disconnect updater signals to avoid leaks
	if is_instance_valid(_tutor_tab_proxy_tabbar) and _tutor_tab_proxy_updater.is_valid():
		if _tutor_tab_proxy_tabbar.resized.is_connected(_tutor_tab_proxy_updater):
			_tutor_tab_proxy_tabbar.resized.disconnect(_tutor_tab_proxy_updater)
		if _tutor_tab_proxy_tabbar.visibility_changed.is_connected(_tutor_tab_proxy_updater):
			_tutor_tab_proxy_tabbar.visibility_changed.disconnect(_tutor_tab_proxy_updater)
	_tutor_tab_proxy = null
	_tutor_tab_proxy_updater = Callable()
	_tutor_tab_proxy_tabbar = null

# --- Tutorial helper: global rect covering all vendor tab headers (union) ---
func tutorial_get_tab_bar_rect_global() -> Rect2:
	if not is_instance_valid(vendor_tab_container):
		return Rect2()
	var tc: TabContainer = vendor_tab_container
	var tab_bar: Control = null
	if tc.has_method("get_tab_bar"):
		tab_bar = tc.call("get_tab_bar")
	if tab_bar == null:
		tab_bar = tc.find_child("TabBar", true, false)
	if tab_bar == null:
		for ch in tc.get_children():
			if ch is Control and String(ch.get_class()).to_lower().find("tabbar") != -1:
				tab_bar = ch
				break
	if tab_bar == null or not tab_bar.has_method("get_tab_rect"):
		return Rect2()
	var count := tc.get_tab_count()
	if count <= 0:
		return Rect2()
	var has_any := false
	var ul := Vector2(1.0/0.0, 1.0/0.0) # +INF
	var br := Vector2(-1.0/0.0, -1.0/0.0) # -INF
	for i in range(count):
		var rl: Rect2 = tab_bar.call("get_tab_rect", i)
		if rl.size == Vector2.ZERO:
			continue
		var pg: Vector2 = tab_bar.get_global_transform() * rl.position
		ul.x = min(ul.x, pg.x)
		ul.y = min(ul.y, pg.y)
		br.x = max(br.x, pg.x + rl.size.x)
		br.y = max(br.y, pg.y + rl.size.y)
		has_any = true
	return Rect2(ul, br - ul) if has_any else Rect2()

# --- Tutorial helper: info for each vendor tab header ---
# Returns Array of { index:int, title:String, rect:Rect2, category_idx:int }
func tutorial_get_vendor_tab_headers_info() -> Array:
	var result: Array = []
	if not is_instance_valid(vendor_tab_container):
		return result
	var tc: TabContainer = vendor_tab_container
	var tab_bar: Control = null
	if tc.has_method("get_tab_bar"):
		tab_bar = tc.call("get_tab_bar")
	if tab_bar == null:
		tab_bar = tc.find_child("TabBar", true, false)
	if tab_bar == null:
		for ch in tc.get_children():
			if ch is Control and String(ch.get_class()).to_lower().find("tabbar") != -1:
				tab_bar = ch
				break
	if tab_bar == null or not tab_bar.has_method("get_tab_rect"):
		return result
	var count := tc.get_tab_count()
	for i in range(count):
		var tab_ctrl: Node = tc.get_tab_control(i)
		var full_vendor_name := String(tab_ctrl.name) if tab_ctrl != null else ""
		var vendor_dict := _find_vendor_by_name(full_vendor_name)
		var cat_idx := -1
		var has_fuel := false
		var has_water := false
		var has_food := false
		var short_name_ci := ""
		if vendor_dict is Dictionary and not vendor_dict.is_empty():
			cat_idx = _vendor_category_index(vendor_dict)
			# Compute simple resource capability flags (price presence OR inventory quantities)
			short_name_ci = _vendor_short_display_name(vendor_dict).to_lower()
			if vendor_dict.has("fuel_price") or (vendor_dict.has("fuel") and (vendor_dict.get("fuel") is int or vendor_dict.get("fuel") is float) and float(vendor_dict.get("fuel")) > 0.0):
				has_fuel = true
			if vendor_dict.has("water_price") or (vendor_dict.has("water") and (vendor_dict.get("water") is int or vendor_dict.get("water") is float) and float(vendor_dict.get("water")) > 0.0):
				has_water = true
			if vendor_dict.has("food_price") or (vendor_dict.has("food") and (vendor_dict.get("food") is int or vendor_dict.get("food") is float) and float(vendor_dict.get("food")) > 0.0):
				has_food = true
			if vendor_dict.has("cargo_inventory") and (vendor_dict.get("cargo_inventory") is Array):
				for it in (vendor_dict.get("cargo_inventory") as Array):
					if it is Dictionary:
						var fv = it.get("fuel") if it.has("fuel") else null
						var wv = it.get("water") if it.has("water") else null
						var fd = it.get("food") if it.has("food") else null
						if (fv is int or fv is float) and float(fv) > 0.0: has_fuel = true
						if (wv is int or wv is float) and float(wv) > 0.0: has_water = true
						if (fd is int or fd is float) and float(fd) > 0.0: has_food = true
		var rect_local: Rect2 = tab_bar.call("get_tab_rect", i)
		var pos_global: Vector2 = tab_bar.get_global_transform() * rect_local.position
		var rect_global := Rect2(pos_global, rect_local.size)
		result.append({
			"index": i,
			"title": String(tc.get_tab_title(i)),
			"rect": rect_global,
			"category_idx": cat_idx,
			"has_fuel": has_fuel,
			"has_water": has_water,
			"has_food": has_food,
			"short_name": short_name_ci
		})
	return result

# Tutorial helper: choose the best index for Market (bulk food/water)
func tutorial_get_best_market_tab_index() -> int:
	if not is_instance_valid(vendor_tab_container):
		return -1
	var info: Array = tutorial_get_vendor_tab_headers_info()
	# 1) Strongest: exact tab title 'Market' (case-insensitive), regardless of category
	for e in info:
		if not (e is Dictionary):
			continue
		var title_ci := String(e.get("title", "")).strip_edges().to_lower()
		if title_ci == "market":
			return int(e.get("index", -1))
	# 2) Category-based resources tabs with additional preferences
	var best_any := -1
	var prefer_name := -1
	var prefer_both := -1
	var prefer_some := -1
	for e in info:
		if not (e is Dictionary):
			continue
		if int(e.get("category_idx", -1)) != 4:
			continue
		var idx := int(e.get("index", -1))
		if idx == -1:
			continue
		if best_any == -1:
			best_any = idx
		var title_ci2 := String(e.get("title", "")).to_lower()
		var short_ci := String(e.get("short_name", "")).to_lower()
		if prefer_name == -1 and (title_ci2.find("market") != -1 or short_ci.find("market") != -1):
			prefer_name = idx
		var has_w := bool(e.get("has_water", false))
		var has_f := bool(e.get("has_food", false))
		if prefer_both == -1 and has_w and has_f:
			prefer_both = idx
		if prefer_some == -1 and (has_w or has_f):
			prefer_some = idx
	# Priority: named Market > has both water+food > has water/food > any resources
	if prefer_name != -1:
		return prefer_name
	if prefer_both != -1:
		return prefer_both
	if prefer_some != -1:
		return prefer_some
	return best_any

# --- Tutorial helper: return the index of the Market/Resources tab ---
func tutorial_get_market_tab_index() -> int:
	# Wrapper for clarity; uses best-guess selection for Market/Resources tab
	return tutorial_get_best_market_tab_index()

# --- Tutorial helper: return the global rect of the Market tab header ---
func tutorial_get_market_tab_rect_global() -> Rect2:
	if not is_instance_valid(vendor_tab_container):
		return Rect2()
	var tc: TabContainer = vendor_tab_container
	var tab_bar: Control = null
	if tc.has_method("get_tab_bar"):
		tab_bar = tc.call("get_tab_bar")
	if tab_bar == null:
		tab_bar = tc.find_child("TabBar", true, false)
	if tab_bar == null or not tab_bar.has_method("get_tab_rect"):
		return Rect2()
	var market_index := int(tutorial_get_market_tab_index())
	if market_index < 0 or market_index >= tc.get_tab_count():
		return Rect2()
	var rect_local: Rect2 = tab_bar.call("get_tab_rect", market_index)
	if rect_local.size == Vector2.ZERO:
		await get_tree().process_frame
		rect_local = tab_bar.call("get_tab_rect", market_index)
		if rect_local.size == Vector2.ZERO:
			return Rect2()
	var pos_global: Vector2 = tab_bar.get_global_transform() * rect_local.position
	return Rect2(pos_global, rect_local.size)

# --- Tutorial helper: create a proxy Control over the Market tab header for reliable highlighting ---
var _tutor_market_tab_proxy: Control = null
var _tutor_market_tab_proxy_updater: Callable = Callable()
var _tutor_market_tab_proxy_tabbar: Control = null

func tutorial_build_market_tab_highlight_proxy() -> Control:
	if not is_instance_valid(vendor_tab_container):
		return null
	var tc2: TabContainer = vendor_tab_container
	var tab_bar2: Control = null
	if tc2.has_method("get_tab_bar"):
		tab_bar2 = tc2.call("get_tab_bar")
	if tab_bar2 == null:
		tab_bar2 = tc2.find_child("TabBar", true, false)
	if tab_bar2 == null or not tab_bar2.has_method("get_tab_rect"):
		return null
	var idx2 := int(tutorial_get_market_tab_index())
	if idx2 < 0:
		return null
	var rl2: Rect2 = tab_bar2.call("get_tab_rect", idx2)
	if rl2.size == Vector2.ZERO:
		await get_tree().process_frame
		rl2 = tab_bar2.call("get_tab_rect", idx2)
		if rl2.size == Vector2.ZERO:
			return null
	tutorial_clear_market_tab_highlight_proxy()
	var proxy := Control.new()
	proxy.name = "TutorMarketTabProxy"
	# Ignore mouse so it never blocks clicks; keep as child of TabBar so it tracks layout
	proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	proxy.anchor_left = 0
	proxy.anchor_right = 0
	proxy.anchor_top = 0
	proxy.anchor_bottom = 0
	proxy.position = rl2.position
	proxy.size = rl2.size
	tab_bar2.add_child(proxy)
	proxy.z_index = 1000
	# Keep proxy sticky to the tab header by updating on TabBar size/visibility changes
	var updater := func():
		if is_instance_valid(tab_bar2):
			var rnow: Rect2 = tab_bar2.call("get_tab_rect", idx2)
			proxy.position = rnow.position
			proxy.size = rnow.size
	# Store references so we can disconnect later
	_tutor_market_tab_proxy_updater = updater
	_tutor_market_tab_proxy_tabbar = tab_bar2
	# Connect supported signals; avoid duplicate connects
	if is_instance_valid(tab_bar2):
		if not tab_bar2.resized.is_connected(updater):
			tab_bar2.resized.connect(updater)
		if not tab_bar2.visibility_changed.is_connected(updater):
			tab_bar2.visibility_changed.connect(updater)
	# One immediate update in case the rect changed after creation
	updater.call()
	_tutor_market_tab_proxy = proxy
	return proxy

func tutorial_clear_market_tab_highlight_proxy() -> void:
	if is_instance_valid(_tutor_market_tab_proxy):
		var parent := _tutor_market_tab_proxy.get_parent()
		if parent:
			parent.remove_child(_tutor_market_tab_proxy)
		_tutor_market_tab_proxy.queue_free()
	# Disconnect updater signals to avoid leaks
	if is_instance_valid(_tutor_market_tab_proxy_tabbar) and _tutor_market_tab_proxy_updater.is_valid():
		if _tutor_market_tab_proxy_tabbar.resized.is_connected(_tutor_market_tab_proxy_updater):
			_tutor_market_tab_proxy_tabbar.resized.disconnect(_tutor_market_tab_proxy_updater)
		if _tutor_market_tab_proxy_tabbar.visibility_changed.is_connected(_tutor_market_tab_proxy_updater):
			_tutor_market_tab_proxy_tabbar.visibility_changed.disconnect(_tutor_market_tab_proxy_updater)
	_tutor_market_tab_proxy = null
	_tutor_market_tab_proxy_updater = Callable()
	_tutor_market_tab_proxy_tabbar = null

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
		# Try to resolve from GameDataManager for current coordinates
		var sx = int(roundf(float(_convoy_data.get("x", -9999.0))))
		var sy = int(roundf(float(_convoy_data.get("y", -9999.0))))
		if is_instance_valid(gdm) and gdm.has_method("get_settlement_name_from_coords"):
			var sett_name := String(gdm.get_settlement_name_from_coords(sx, sy))
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

func _on_item_purchased(_item: Dictionary, _quantity: int, total_cost: float):
	# Only update user money via GameDataManager. Do NOT mutate local convoy/vendor data.
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm) and gdm.has_method("update_user_money"):
		gdm.update_user_money(-total_cost)
	else:
		printerr("ConvoySettlementMenu: Could not update user money. GameDataManager not found or is missing 'update_user_money' method.")
	# Do NOT mutate _convoy_data or vendor data here.
	# Wait for GameDataManager to emit updated data signals, then refresh UI.

func _on_item_sold(_item: Dictionary, _quantity: int, total_value: float):
	gdm = get_node_or_null("/root/GameDataManager")
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
			_debounced_ui_refresh()
			break

func _on_gdm_settlement_data_updated(all_settlements_data: Array) -> void:
	# Find the current settlement and update _settlement_data, then refresh UI
	if not _settlement_data or not _settlement_data.has("sett_id"):
		return
	var current_id = str(_settlement_data.get("sett_id"))
	for settlement in all_settlements_data:
		if settlement.has("sett_id") and str(settlement.get("sett_id")) == current_id:
			_settlement_data = settlement.duplicate(true)
			_debounced_ui_refresh()
			break

# --- Direct API transaction handlers ---
func _on_api_resource_txn(_result: Dictionary) -> void:
	# Called when resource bought/sold; trigger convoy refresh for authoritative state.
	if is_instance_valid(gdm):
		gdm.request_convoy_data_refresh()
		# Also refresh user data (money changes)
		gdm.request_user_data_refresh()
	# Re-enable top-up button after a short delay so updated values incorporated.
	_schedule_post_txn_update_ui()

func _on_api_other_txn(_result: Dictionary) -> void:
	# Cargo / vehicle transactions also alter convoy state.
	_on_api_resource_txn(_result)

func _post_txn_update_ui():
	_update_top_up_button()
	if is_instance_valid(top_up_button) and top_up_button.disabled:
		top_up_button.disabled = false
		_update_top_up_button()

# Debounced refresh to coalesce multiple data change signals
func _debounced_ui_refresh() -> void:
	if _ui_refresh_pending:
		return
	_ui_refresh_pending = true
	call_deferred("_perform_ui_refresh")

func _perform_ui_refresh() -> void:
	_ui_refresh_pending = false
	_update_top_up_button()

func _schedule_post_txn_update_ui() -> void:
	# Small delay to allow GDM to propagate new data; avoids thrash
	call_deferred("_post_txn_update_ui")

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
	# Also refresh top up button when vendor data may have changed
	_update_top_up_button()

func _find_vendor_by_name(vendor_name: String) -> Dictionary:
	if _settlement_data and _settlement_data.has("vendors"):
		for vendor in _settlement_data.vendors:
			if vendor.get("name", "") == vendor_name:
				return vendor
	return {}


# --- Vendor ordering helpers ---
# Classify a vendor into a category index for deterministic tab ordering.
# Lower index sorts first. Chosen order:
#   0: Settlement Info (implicit, not part of vendors array)
#   1: Missions (delivery/quest-like)
#   2: Dealership / Vehicles (vendors offering vehicles)
#   3: Parts (sells parts/accessories)
#   4: Resources (fuel/water/food bulk)
#   9: Other/Unknown
func _vendor_category_index(vendor: Dictionary) -> int:
	if vendor.is_empty():
		return 9
	# Heuristics based on inventory and known fields
	var inv: Array = []
	if vendor.has("cargo_inventory") and (vendor.get("cargo_inventory") is Array):
		inv = vendor.get("cargo_inventory")
	# If the backend/model provides a dedicated vehicle inventory, prefer that as an authoritative signal
	var veh_inv: Array = vendor.get("vehicle_inventory", []) if vendor.has("vehicle_inventory") else []
	if veh_inv is Array and not veh_inv.is_empty():
		return 2
	var has_mission := false
	var has_vehicle := false
	var has_part := false
	var has_resource := false
	# Strong name-based override for dealership
	var vname := String(vendor.get("name", "")).to_lower()
	if vname.find("dealership") != -1 or vname.find("dealer") != -1:
		has_vehicle = true
	for item in inv:
		if not (item is Dictionary):
			continue
		if item.get("recipient") != null:
			has_mission = true
		# Vehicle: explicit type or vehicle-like stats
		var t := String(item.get("type", "")).to_lower()
		# Treat as vehicle only on clear indicators; avoid mission cargo or resource entries
		var looks_vehicle := false
		if t == "vehicle":
			looks_vehicle = true
		elif item.has("stats") and (item.get("stats") is Dictionary):
			var stats: Dictionary = item.get("stats")
			var vehish := ["top_speed","max_speed","speed","efficiency","offroad_capability","cargo_capacity","weight_capacity","fuel_capacity","kwh_capacity","passenger_capacity"]
			for k in vehish:
				if stats.has(k):
					looks_vehicle = true
					break
		if looks_vehicle:
			has_vehicle = true
		# Part indicators
		if item.has("slot") and item.get("slot") != null:
			has_part = true
		# Resource indicators
		var food_v = item.get("food") if item.has("food") else null
		var water_v = item.get("water") if item.has("water") else null
		var fuel_v = item.get("fuel") if item.has("fuel") else null
		if (food_v is int or food_v is float) and float(food_v) > 0:
			has_resource = true
		elif (water_v is int or water_v is float) and float(water_v) > 0:
			has_resource = true
		elif (fuel_v is int or fuel_v is float) and float(fuel_v) > 0:
			has_resource = true

	# Quick check for explicit resource price fields on vendor
	var has_resource_prices := vendor.has("fuel_price") or vendor.has("water_price") or vendor.has("food_price")

	if has_mission:
		return 1
	if has_vehicle:
		return 2
	if has_part:
		return 3
	if has_resource or has_resource_prices:
		return 4
	return 9

func _vendor_short_display_name(vendor: Dictionary) -> String:
	var vendor_name = String(vendor.get("name", ""))
	var settlement_name = String(_settlement_data.get("name", ""))
	if settlement_name != "":
		return vendor_name.replace(settlement_name + " ", "").strip_edges()
	return vendor_name

func _vendor_order_key(vendor: Dictionary) -> Array:
	# Return a sortable key. Base: [category_index, (optional) subpriority, short_name_lower]
	var idx := _vendor_category_index(vendor)
	var short_name := _vendor_short_display_name(vendor).to_lower()
	# Within Resources category (4), prefer Market-like vendors over fuel-only (e.g., Gas Station)
	if idx == 4:
		var title_ci := short_name
		var caps := _vendor_resource_capabilities(vendor)
		var has_w := bool(caps.get("has_water", false))
		var has_f := bool(caps.get("has_food", false))
		var subprio := 3 # default: fuel-only or unknown
		if title_ci.find("market") != -1:
			subprio = 0
		elif has_w and has_f:
			subprio = 1
		elif has_w or has_f:
			subprio = 2
		return [idx, subprio, short_name]
	return [idx, short_name]

# Compute simple resource capability flags for a vendor
func _vendor_resource_capabilities(vendor: Dictionary) -> Dictionary:
	var has_fuel := false
	var has_water := false
	var has_food := false
	if vendor is Dictionary and not vendor.is_empty():
		# Price fields imply the vendor sells the resource
		if vendor.has("fuel_price"): has_fuel = true
		if vendor.has("water_price"): has_water = true
		if vendor.has("food_price"): has_food = true
		# Direct stock fields
		if vendor.has("fuel") and (vendor.fuel is int or vendor.fuel is float) and float(vendor.fuel) > 0.0:
			has_fuel = true
		if vendor.has("water") and (vendor.water is int or vendor.water is float) and float(vendor.water) > 0.0:
			has_water = true
		if vendor.has("food") and (vendor.food is int or vendor.food is float) and float(vendor.food) > 0.0:
			has_food = true
		# Cargo inventory scan
		if vendor.has("cargo_inventory") and (vendor.get("cargo_inventory") is Array):
			for it in (vendor.get("cargo_inventory") as Array):
				if it is Dictionary:
					var fv = it.get("fuel") if it.has("fuel") else null
					var wv = it.get("water") if it.has("water") else null
					var fd = it.get("food") if it.has("food") else null
					if (fv is int or fv is float) and float(fv) > 0.0: has_fuel = true
					if (wv is int or wv is float) and float(wv) > 0.0: has_water = true
					if (fd is int or fd is float) and float(fd) > 0.0: has_food = true
	return {"has_fuel": has_fuel, "has_water": has_water, "has_food": has_food}



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
	if is_instance_valid(gdm):
		var user_data = gdm.get_current_user_data()
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
	if not is_instance_valid(gdm):
		return
	var convoy_id = str(_convoy_data.get("convoy_id", ""))
	if convoy_id.is_empty():
		return
	# Execute purchases individually (one PATCH per resource) based on current plan snapshot.
	for alloc in _top_up_plan.allocations:
		var res = alloc.get("res", "")
		var vendor_id = str(alloc.get("vendor_id", ""))
		var send_qty:int = int(alloc.get("quantity", 0))
		if res == "" or vendor_id.is_empty() or send_qty <= 0:
			continue
		print("[TopUp] Purchasing %d %s from vendor %s (price=%.2f) convoy=%s" % [send_qty, res, vendor_id, float(alloc.get("price",0.0)), convoy_id])
		var item_dict = {"is_raw_resource": true}
		item_dict[res] = send_qty
		gdm.buy_item(convoy_id, vendor_id, item_dict, send_qty)
	# Disable button until data refresh comes back
	if is_instance_valid(top_up_button):
		top_up_button.disabled = true
		top_up_button.text = "Top Up (Processing...)"

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
