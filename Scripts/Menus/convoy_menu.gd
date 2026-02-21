extends MenuBase # Standardized menu base for store-driven updates

# Optional: If your menu needs to display data passed from MenuManager
var convoy_data_received: Dictionary

# Classification helpers from centralized item data
const ItemsData = preload("res://Scripts/Data/Items.gd")

const SettlementModel = preload("res://Scripts/Data/Models/Settlement.gd")
const VendorModel = preload("res://Scripts/Data/Models/Vendor.gd")
const VendorPanelContextController = preload("res://Scripts/Menus/VendorPanel/vendor_panel_context_controller.gd")

# --- Font Scaling Parameters ---
const BASE_FONT_SIZE: float = 18.0 # Increased from 14.0
const BASE_TITLE_FONT_SIZE: float = 22.0 # Increased from 18.0
const REFERENCE_MENU_HEIGHT: float = 600.0 # The menu height at which BASE_FONT_SIZE looks best
const MIN_FONT_SIZE: float = 8.0
const MAX_FONT_SIZE: float = 24.0
const MAX_TITLE_FONT_SIZE: float = 30.0

# --- Color Constants for Styling ---
const COLOR_GREEN: Color = Color("66bb6a") # Material Green 400
const COLOR_YELLOW: Color = Color("ffee58") # Material Yellow 400
const COLOR_RED: Color = Color("ef5350") # Material Red 400
const COLOR_BOX_FONT: Color = Color("000000") # Black font for boxes for contrast
const COLOR_PERFORMANCE_BOX_BG: Color = Color("404040cc") # Dark Gray, 80% opaque
const COLOR_MENU_BUTTON_GREY_BG: Color = Color("b0b0b0") # Light-Medium Grey for menu buttons
const COLOR_PERFORMANCE_BOX_FONT: Color = Color.WHITE # White

# --- Vendor Preview Tab Constants ---
enum VendorTab {CONVOY_MISSIONS, SETTLEMENT_MISSIONS, COMPATIBLE_PARTS, JOURNEY}
const COLOR_TAB_ACTIVE_BG: Color = Color("424242") # Grey 800
const COLOR_TAB_INACTIVE_BG: Color = Color("757575") # Grey 600
const COLOR_TAB_CONTENT_BG: Color = Color("303030") # Grey 850
const COLOR_MISSION_TEXT: Color = Color("ffd700") # Gold
const COLOR_PART_TEXT: Color = Color("4dd0e1") # Material Cyan 300
const COLOR_BULLET_POINT: Color = Color("9e9e9e") # Grey 500
const COLOR_TAB_DISABLED_FONT: Color = Color("a0a0a0") # Lighter gray for disabled text
const COLOR_ITEM_BUTTON_BG: Color = Color("5a5a5a") # Dark-medium gray for item buttons
const COLOR_JOURNEY_PROGRESS_FILL: Color = Color("29b6f6") # Material Light Blue 400

# --- @onready vars for new labels ---
# Paths updated to reflect the new TopBarHBox container in the scene.
@onready var title_label: Label = $MainVBox/TopBarHBox/TitleLabel

# Resource/Stat Boxes (Panel and inner Label)
@onready var fuel_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/FuelBox/FuelBar
@onready var fuel_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/FuelBox/FuelTextLabel
@onready var water_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/WaterBox/WaterBar
@onready var water_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/WaterBox/WaterTextLabel
@onready var food_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/FoodBox/FoodBar
@onready var food_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/FoodBox/FoodTextLabel

@onready var speed_box: PanelContainer = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/SpeedBox
@onready var speed_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/SpeedBox/SpeedTextLabel
@onready var offroad_box: PanelContainer = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/OffroadBox
@onready var offroad_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/OffroadBox/OffroadTextLabel
@onready var efficiency_box: PanelContainer = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/EfficiencyBox
@onready var efficiency_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/EfficiencyBox/EfficiencyTextLabel

# Cargo Progress Bars and Labels
@onready var cargo_volume_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/CargoVolumeContainer/CargoVolumeTextLabel
@onready var cargo_volume_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/CargoVolumeContainer/CargoVolumeBar
@onready var cargo_weight_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/CargoWeightContainer/CargoWeightTextLabel
@onready var cargo_weight_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/CargoWeightContainer/CargoWeightBar

@onready var scroll_container: ScrollContainer = $MainVBox/ScrollContainer
@onready var content_vbox: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox

@onready var vehicles_label: Label = get_node_or_null("MainVBox/ScrollContainer/ContentVBox/VehiclesLabel")
# Optional: AllCargoLabel may not exist in the scene variant.
var all_cargo_label: Label = null
@onready var back_button: Button = $MainVBox/TopBarHBox/BackButton

# --- Vendor Panel Utilities ---
@onready var preview_title_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/PreviewTitleLabel
@onready var convoy_missions_tab_button: Button = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorTabsHBox/ConvoyMissionsTabButton
@onready var settlement_missions_tab_button: Button = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorTabsHBox/SettlementMissionsTabButton
@onready var compatible_parts_tab_button: Button = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorTabsHBox/CompatiblePartsTabButton
@onready var journey_tab_button: Button = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorTabsHBox/JourneyTabButton
@onready var vendor_item_grid: GridContainer = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/VendorItemContainer/VendorItemGrid
@onready var vendor_item_container: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/VendorItemContainer
@onready var vendor_no_items_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/VendorNoItemsLabel
@onready var overview_vbox: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox/OverviewVBox
@onready var journey_info_vbox: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox
@onready var journey_dest_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox/JourneyDestLabel
@onready var journey_progress_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox/JourneyProgressControl/JourneyProgressBar
@onready var journey_progress_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox/JourneyProgressControl/JourneyProgressLabel
@onready var journey_eta_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox/JourneyETALabel

# --- Placeholder Menu Buttons ---
@onready var vehicle_menu_button: Button = $MainVBox/BottomBarPanel/BottomMenuButtonsHBox/VehicleMenuButton
@onready var journey_menu_button: Button = $MainVBox/BottomBarPanel/BottomMenuButtonsHBox/JourneyMenuButton
@onready var settlement_menu_button: Button = $MainVBox/BottomBarPanel/BottomMenuButtonsHBox/SettlementMenuButton
@onready var cargo_menu_button: Button = $MainVBox/BottomBarPanel/BottomMenuButtonsHBox/CargoMenuButton

# --- Signals for Sub-Menu Navigation ---
signal open_vehicle_menu_requested(convoy_data)
signal open_journey_menu_requested(convoy_data)
signal open_settlement_menu_requested(convoy_data)
signal open_cargo_menu_requested(convoy_data)

# --- Deep-link navigation from Settlement Preview buttons ---
# Used by MenuManager to open destination menu with a focus intent via extra_arg.
signal open_settlement_menu_with_focus_requested(convoy_data: Dictionary, focus_intent: Dictionary)
# Used by MenuManager to open Cargo menu and auto-inspect a specific item via extra_arg (expects cargo_id).
signal open_cargo_menu_inspect_requested(convoy_data: Dictionary, item_data: Dictionary)

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _vendor_service: Node = get_node_or_null("/root/VendorService")
@onready var _mechanics_service: Node = get_node_or_null("/root/MechanicsService")
@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")
var _debug_convoy_menu: bool = true # toggle verbose diagnostics for this menu

# ConvoyMenu should always render from a *full* convoy snapshot. Some signal paths provide
# a shallow convoy dict (missing capacities/resources), which can temporarily render 0/0.
# We request full details once per open and ignore incomplete updates after we have complete.
var _requested_full_convoy_id: String = ""

# --- Vendor Preview State ---
var _current_vendor_tab: VendorTab = VendorTab.CONVOY_MISSIONS
var _convoy_mission_items: Array[String] = []
var _settlement_mission_items: Array[String] = []
var _compatible_part_items: Array[String] = []
var _latest_all_settlements: Array = []
var _latest_all_settlement_models: Array = [] # Array[Settlement]
var _vendors_by_id: Dictionary = {} # vendor_id -> vendor Dictionary (from VendorService/Hub)
var _vendors_by_id_models: Dictionary = {} # vendor_id -> Vendor
var _vendors_from_settlements_by_id: Dictionary = {} # vendor_id -> vendor Dictionary (from map snapshot)
var _vendor_id_to_settlement: Dictionary = {} # vendor_id -> settlement Dictionary (from map snapshot)
var _vendor_id_to_name: Dictionary = {} # vendor_id -> vendor name String (from map snapshot + vendor previews)
var _vendor_preview_update_timer: Timer = null # For debouncing updates
var _vendor_preview_update_pending: bool = false
var _destinations_cache: Dictionary = {} # item_name -> recipient_settlement_name (or destination string)

# Avoid spamming vendor detail requests when Available Missions refreshes.
var _requested_vendor_details: Dictionary = {} # vendor_id -> true

# For deep-linking Active Missions -> Cargo menu, preserve at least one representative cargo_id per mission item name.
var _active_mission_cargo_id_by_name: Dictionary = {} # item_name -> cargo_id
var _active_mission_cargo_id_by_display: Dictionary = {} # "name — to DEST" -> cargo_id


func _is_convoy_payload_complete(c: Dictionary) -> bool:
	# Heuristic: a "full" convoy snapshot includes capacity/resource maxima.
	# Shallow snapshots often omit these keys, causing UI to render 0/0.
	if c.is_empty():
		return false
	var has_capacity := c.has("total_cargo_capacity") or c.has("total_weight_capacity") or c.has("max_cargo_volume") or c.has("max_cargo_weight")
	var has_resource_max := c.has("max_fuel") or c.has("max_water") or c.has("max_food")
	return has_capacity and has_resource_max


func _ensure_full_convoy_loaded(target_id: String, snapshot: Dictionary) -> void:
	if target_id == "":
		return
	if _requested_full_convoy_id == target_id:
		return
	if _is_convoy_payload_complete(snapshot):
		_parse_convoy_payload(snapshot) # Call parse if already complete
		return
	if not is_instance_valid(_convoy_service) or not _convoy_service.has_method("refresh_single"):
		return
	_requested_full_convoy_id = target_id
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] Requesting full convoy snapshot for convoy_id=", target_id)
	_convoy_service.refresh_single(target_id)

func _parse_convoy_payload(payload: Dictionary) -> void:
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] Parsing full convoy payload. Convoy ID=", payload.get("id", "Unknown"), " Vehicles=", payload.get("vehicles", []).size())
	
	# Pass data to the Vendor Preview pane if active
	# (The rest of the original _ensure_full_convoy_loaded function was not part of the instruction,
	# so it's assumed to be handled elsewhere or not relevant to this specific change.)


func _set_latest_settlements_snapshot(settlements: Array) -> void:
	_latest_all_settlements = settlements if settlements != null else []
	_latest_all_settlement_models.clear()
	_vendors_from_settlements_by_id.clear()
	_vendor_id_to_settlement.clear()
	_vendor_id_to_name.clear()
	for s_any in _latest_all_settlements:
		if not (s_any is Dictionary):
			continue
		var s_dict := s_any as Dictionary
		_latest_all_settlement_models.append(SettlementModel.new(s_dict))
		var vendors_any: Variant = s_dict.get("vendors", [])
		var vendors: Array = vendors_any if vendors_any is Array else []
		for v_any in vendors:
			if not (v_any is Dictionary):
				continue
			var v_dict := v_any as Dictionary
			var vid := String(v_dict.get("vendor_id", v_dict.get("id", "")))
			if vid == "":
				continue
			# first-writer wins to keep stable results if duplicates exist
			if not _vendors_from_settlements_by_id.has(vid):
				_vendors_from_settlements_by_id[vid] = v_dict
			if not _vendor_id_to_settlement.has(vid):
				_vendor_id_to_settlement[vid] = s_dict
			var nm := String(v_dict.get("name", ""))
			if nm != "" and not _vendor_id_to_name.has(vid):
				_vendor_id_to_name[vid] = nm

func _ready():
	# Resolve optional nodes that might be missing depending on scene variant
	all_cargo_label = get_node_or_null("MainVBox/ScrollContainer/ContentVBox/AllCargoLabel")
	if all_cargo_label == null:
		if _debug_convoy_menu:
			printerr("[ConvoyMenu] Optional AllCargoLabel not found at path MainVBox/ScrollContainer/ContentVBox/AllCargoLabel")
	# --- DIAGNOSTIC: Check if UI nodes are valid ---
	if not is_instance_valid(title_label):
		printerr("ConvoyMenu: CRITICAL - TitleLabel node not found. Check the path in the script.")

	# Style bottom bar panel if present
	var bottom_panel := $MainVBox/BottomBarPanel if has_node("MainVBox/BottomBarPanel") else null
	if is_instance_valid(bottom_panel):
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color = Color(0.18, 0.18, 0.18, 0.85)
		bar_style.corner_radius_top_left = 6
		bar_style.corner_radius_top_right = 6
		bar_style.border_width_top = 1
		bar_style.border_color = Color(0.28, 0.28, 0.28)
		bottom_panel.add_theme_stylebox_override("panel", bar_style)

	# Style vendor preview panel if present
	var vendor_preview_panel := $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel if has_node("MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel") else null
	if is_instance_valid(vendor_preview_panel):
		var vp_style := StyleBoxFlat.new()
		vp_style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
		vp_style.corner_radius_top_left = 6
		vp_style.corner_radius_top_right = 6
		vp_style.corner_radius_bottom_left = 6
		vp_style.corner_radius_bottom_right = 6
		vp_style.border_width_left = 1
		vp_style.border_width_right = 1
		vp_style.border_width_top = 1
		vp_style.border_width_bottom = 1
		vp_style.border_color = Color(0.25, 0.35, 0.55, 0.9)
		vp_style.shadow_color = Color(0, 0, 0, 0.45)
		vp_style.shadow_size = 4
		vendor_preview_panel.add_theme_stylebox_override("panel", vp_style)
		# Style the content panel inside the vendor preview
		var content_panel = vendor_preview_panel.get_node_or_null("VendorPreviewVBox/VendorContentPanel")
		if is_instance_valid(content_panel):
			var content_style := StyleBoxFlat.new()
			content_style.bg_color = COLOR_TAB_CONTENT_BG
			content_style.corner_radius_top_left = 4
			content_style.corner_radius_bottom_right = 4
			content_panel.add_theme_stylebox_override("panel", content_style)
	
	# Style the new journey progress bar
	if is_instance_valid(journey_progress_bar):
		_style_journey_progress_bar(journey_progress_bar)
	# IMPORTANT: Ensure you have a Button node in your ConvoyMenu.tscn scene
	# and that its name is "BackButton".
	# The third argument 'false' for find_child means 'owned by this node' is not checked,
	# which is usually fine for finding children within a scene instance.
	# var back_button = find_child("BackButton", true, false) # Now using @onready var

	if back_button and back_button is Button:
		# print("ConvoyMenu: BackButton found. Connecting its 'pressed' signal.") # DEBUG
		# Check if already connected to prevent duplicate connections if _ready is called multiple times (unlikely for menus but good practice)
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT) # Use ONE_SHOT as menu is freed
	else:
		printerr("ConvoyMenu: CRITICAL - BackButton node NOT found or is not a Button. Ensure it's named 'BackButton' in ConvoyMenu.tscn.")

	# Cache GameDataManager and connect relevant signals for live updates
	# Phase C: subscribe to canonical sources (Hub/Store/APICalls) instead of GameDataManager.
	if is_instance_valid(_api) and _api.has_signal("part_compatibility_checked") and not _api.part_compatibility_checked.is_connected(_on_part_compat_ready):
		_api.part_compatibility_checked.connect(_on_part_compat_ready)
	if is_instance_valid(_api) and _api.has_signal("cargo_data_received") and not _api.cargo_data_received.is_connected(_on_cargo_data_received):
		_api.cargo_data_received.connect(_on_cargo_data_received)
	if is_instance_valid(_hub) and _hub.has_signal("vendor_preview_ready") and not _hub.vendor_preview_ready.is_connected(_on_vendor_preview_ready):
		_hub.vendor_preview_ready.connect(_on_vendor_preview_ready)
	# Some flows emit vendor_updated instead of vendor_preview_ready.
	if is_instance_valid(_hub) and _hub.has_signal("vendor_updated") and not _hub.vendor_updated.is_connected(_on_vendor_preview_ready):
		_hub.vendor_updated.connect(_on_vendor_preview_ready)
	if is_instance_valid(_store) and _store.has_signal("map_changed") and not _store.map_changed.is_connected(_on_store_map_changed):
		_store.map_changed.connect(_on_store_map_changed)
	if is_instance_valid(_hub) and _hub.has_signal("initial_data_ready") and not _hub.initial_data_ready.is_connected(_on_initial_data_ready):
		_hub.initial_data_ready.connect(_on_initial_data_ready)
	# Prime cached settlements immediately if GameStore already has them.
	if is_instance_valid(_store) and _store.has_method("get_settlements"):
		var pre_cached = _store.get_settlements()
		if pre_cached is Array and not (pre_cached as Array).is_empty():
			_set_latest_settlements_snapshot(pre_cached)
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] pre-cached settlements count=", _latest_all_settlements.size())

	# Connect placeholder menu buttons
	if is_instance_valid(vehicle_menu_button):
		if not vehicle_menu_button.is_connected("pressed", Callable(self, "_on_vehicle_menu_button_pressed")):
			_style_menu_button(vehicle_menu_button)
			vehicle_menu_button.pressed.connect(_on_vehicle_menu_button_pressed)
	if is_instance_valid(journey_menu_button):
		if not journey_menu_button.is_connected("pressed", Callable(self, "_on_journey_menu_button_pressed")):
			_style_menu_button(journey_menu_button)
			journey_menu_button.pressed.connect(_on_journey_menu_button_pressed)
	if is_instance_valid(settlement_menu_button):
		if not settlement_menu_button.is_connected("pressed", Callable(self, "_on_settlement_menu_button_pressed")):
			_style_menu_button(settlement_menu_button)
			settlement_menu_button.pressed.connect(_on_settlement_menu_button_pressed)
	if is_instance_valid(cargo_menu_button):
		if not cargo_menu_button.is_connected("pressed", Callable(self, "_on_cargo_menu_button_pressed")):
			_style_menu_button(cargo_menu_button)
			cargo_menu_button.pressed.connect(_on_cargo_menu_button_pressed)

	# Connect vendor preview tab buttons
	if is_instance_valid(convoy_missions_tab_button):
		_initialize_tab_button_styles(convoy_missions_tab_button)
		convoy_missions_tab_button.pressed.connect(_on_vendor_tab_pressed.bind(VendorTab.CONVOY_MISSIONS))
	if is_instance_valid(settlement_missions_tab_button):
		_initialize_tab_button_styles(settlement_missions_tab_button)
		settlement_missions_tab_button.pressed.connect(_on_vendor_tab_pressed.bind(VendorTab.SETTLEMENT_MISSIONS))
	if is_instance_valid(compatible_parts_tab_button):
		_initialize_tab_button_styles(compatible_parts_tab_button)
		compatible_parts_tab_button.pressed.connect(_on_vendor_tab_pressed.bind(VendorTab.COMPATIBLE_PARTS))
	if is_instance_valid(journey_tab_button):
		_initialize_tab_button_styles(journey_tab_button)
		journey_tab_button.pressed.connect(_on_vendor_tab_pressed.bind(VendorTab.JOURNEY))

	# Set the initial active tab
	convoy_missions_tab_button.button_pressed = true

	# Set up debounce timer for vendor preview updates
	_vendor_preview_update_timer = Timer.new()
	_vendor_preview_update_timer.name = "VendorPreviewUpdateTimer"
	_vendor_preview_update_timer.wait_time = 0.1 # 100ms debounce window
	_vendor_preview_update_timer.one_shot = true
	_vendor_preview_update_timer.timeout.connect(_update_vendor_preview)
	add_child(_vendor_preview_update_timer)

	# initialize_with_data can run before _ready; if so, we may have missed the initial preview refresh.
	if _vendor_preview_update_pending:
		_vendor_preview_update_pending = false
		_queue_vendor_preview_update()
	elif convoy_data_received != null and not convoy_data_received.is_empty():
		_queue_vendor_preview_update()

	# Initial font size update
	call_deferred("_update_font_sizes")
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] services api=", is_instance_valid(_api), " vendor_service=", is_instance_valid(_vendor_service))


func _looks_like_full_vendor_payload(v: Dictionary) -> bool:
	# Settlement map snapshot vendor entries can be partial (mission items missing recipient/mission_vendor_id).
	# A "full" payload from VendorService typically includes mission routing fields in cargo_inventory.
	if v.is_empty():
		return false
	var inv_any: Variant = v.get("cargo_inventory", null)
	if not (inv_any is Array):
		return false
	for it_any in (inv_any as Array):
		if not (it_any is Dictionary):
			continue
		var it: Dictionary = it_any
		if it.get("recipient") != null:
			return true
		var mvid := str(it.get("mission_vendor_id", "")).strip_edges()
		if mvid != "":
			return true
	# Heuristic: full vendor payload often includes price fields.
	if v.has("fuel_price") or v.has("water_price") or v.has("food_price"):
		return true
	return false


func _request_vendor_details(vendor_id: String) -> void:
	if vendor_id == "":
		return
	if bool(_requested_vendor_details.get(vendor_id, false)):
		return
	_requested_vendor_details[vendor_id] = true
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] requesting vendor details vendor_id=", vendor_id)
	if is_instance_valid(_vendor_service) and _vendor_service.has_method("request_vendor"):
		_vendor_service.request_vendor(vendor_id)
		return
	# Fallback: call APICalls directly if VendorService isn't available.
	if is_instance_valid(_api) and _api.has_method("request_vendor_data"):
		_api.request_vendor_data(vendor_id)
		return
	if _debug_convoy_menu:
		printerr("[ConvoyMenu][Debug] cannot request vendor details; missing VendorService/APICalls.request_vendor_data")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# Call deferred to ensure the new size is fully applied before calculating font sizes
		call_deferred("_update_font_sizes")
		call_deferred("_update_vendor_grid_columns")

func _update_vendor_grid_columns() -> void:
	# Make the vendor item grid responsive: choose columns based on available width.
	if not is_instance_valid(vendor_item_grid):
		return
	var grid_width := vendor_item_grid.size.x
	if grid_width <= 0:
		# Fall back to parent/container width if grid has not sized yet
		var parent := vendor_item_grid.get_parent()
		if is_instance_valid(parent):
			grid_width = parent.size.x
	# Target a comfortable card width ~220px with some gap
	var target_card_px := 220.0
	var min_cols := 2
	var max_cols := 6
	var cols := int(max(min_cols, min(max_cols, floor(grid_width / target_card_px))))
	if cols <= 0:
		cols = min_cols
	vendor_item_grid.columns = cols

func _on_back_button_pressed():
	print("ConvoyMenu: Back button pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")

func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
	# Manually resolve nodes as @onready vars aren't ready if called before add_child
	if _store == null: _store = get_node_or_null("/root/GameStore")
	if _hub == null: _hub = get_node_or_null("/root/SignalHub")
	if _vendor_service == null: _vendor_service = get_node_or_null("/root/VendorService")
	if _mechanics_service == null: _mechanics_service = get_node_or_null("/root/MechanicsService")
	if _api == null: _api = get_node_or_null("/root/APICalls")
	if _convoy_service == null: _convoy_service = get_node_or_null("/root/ConvoyService")

	# Prime settlements immediately if empty
	if _latest_all_settlements.is_empty() and is_instance_valid(_store) and _store.has_method("get_settlements"):
		_set_latest_settlements_snapshot(_store.get_settlements())

	if data_or_id is Dictionary:
		convoy_id = String((data_or_id as Dictionary).get("convoy_id", (data_or_id as Dictionary).get("id", "")))
	else:
		convoy_id = String(data_or_id)
	# Always resolve the latest snapshot from GameStore by id
	var resolved_convoy: Dictionary = {}
	if is_instance_valid(_store) and _store.has_method("get_convoys"):
		var convoys: Array = _store.get_convoys()
		for c in convoys:
			if c is Dictionary and String(c.get("convoy_id", c.get("id", ""))) == convoy_id:
				resolved_convoy = c
				break
	if resolved_convoy.is_empty() and data_or_id is Dictionary:
		resolved_convoy = (data_or_id as Dictionary).duplicate()
	convoy_data_received = resolved_convoy.duplicate()
	# Kick off a one-time full snapshot request if we only have a shallow convoy payload.
	_requested_full_convoy_id = "" if _requested_full_convoy_id != convoy_id else _requested_full_convoy_id
	_ensure_full_convoy_loaded(convoy_id, convoy_data_received)
	# Delegate initial draw to MenuBase-driven update
	super.initialize_with_data(convoy_data_received, extra_arg)
	# Mechanics warm-up and vendor refresh can still be triggered once at open
	if convoy_data_received is Dictionary and not convoy_data_received.is_empty():
		if is_instance_valid(_mechanics_service):
			if _mechanics_service.has_method("warm_mechanics_data_for_convoy"):
				_mechanics_service.warm_mechanics_data_for_convoy(convoy_data_received)
			elif _mechanics_service.has_method("start_mechanics_probe_session"):
				var cid := String(convoy_data_received.get("convoy_id", ""))
				if cid != "":
					_mechanics_service.start_mechanics_probe_session(cid)
		if convoy_data_received.has("x") and convoy_data_received.has("y"):
			var cv_x = convoy_data_received.get("x", 0)
			var cv_y = convoy_data_received.get("y", 0)
			var current_convoy_x := roundi(float(cv_x) if cv_x != null else 0.0)
			var current_convoy_y := roundi(float(cv_y) if cv_y != null else 0.0)
			var current_settlement: Dictionary = {}
			for s in _latest_all_settlements:
				if s is Dictionary:
					var sx_val = s.get("x", -999999)
					var sy_val = s.get("y", -999999)
					var sx := roundi(float(sx_val) if sx_val != null else 0.0)
					var sy := roundi(float(sy_val) if sy_val != null else 0.0)
					if sx == current_convoy_x and sy == current_convoy_y:
						current_settlement = s
						break
			if not current_settlement.is_empty():
				var vendors_in_settlement: Array = current_settlement.get("vendors", [])
				for vendor_entry in vendors_in_settlement:
					if vendor_entry is Dictionary:
						var vendor_id = String(vendor_entry.get("vendor_id", ""))
						if not vendor_id.is_empty():
							var inv: Array = []
							if vendor_entry.has("cargo_inventory"):
								var tmp = vendor_entry.get("cargo_inventory")
								if tmp is Array:
									inv = tmp
							var needs_refresh: bool = inv.is_empty()
							if needs_refresh:
								if is_instance_valid(_vendor_service) and _vendor_service.has_method("request_vendor"):
									_vendor_service.request_vendor(vendor_id)
								if _debug_convoy_menu:
									print("[ConvoyMenu][Debug] Requested vendor refresh for vendor_id:", vendor_id, " (inventory empty/missing)")
					elif vendor_entry is String:
						if is_instance_valid(_vendor_service) and _vendor_service.has_method("request_vendor"):
							_vendor_service.request_vendor(String(vendor_entry))
						if _debug_convoy_menu:
							print("[ConvoyMenu][Debug] Requested vendor refresh for vendor_id (string):", vendor_entry)
		for cargo_item in convoy_data_received.get("all_cargo", []):
			if cargo_item is Dictionary:
				var nm := String((cargo_item as Dictionary).get("name", (cargo_item as Dictionary).get("base_name", "Item")))
				var dest := _extract_destination_from_item(cargo_item)
				if dest != "":
					_destinations_cache[nm] = dest
		# Also scan per-vehicle typed/raw cargo to catch stamped destinations
		var vehicle_list2: Array = convoy_data_received.get("vehicle_details_list", [])
		for vehicle in vehicle_list2:
			if not (vehicle is Dictionary):
				continue
			var typed_arr: Array = (vehicle as Dictionary).get("cargo_items_typed", [])
			for typed in typed_arr:
				var raw: Dictionary = {}
				if typed is Dictionary:
					raw = (typed as Dictionary).get("raw", {})
				else:
					var raw_any = typed.get("raw") if typed is Object else null
					if raw_any is Dictionary:
						raw = raw_any
				if raw.is_empty():
					continue
				var nm2 := String(raw.get("name", raw.get("base_name", "Item")))
				var dest2 := _extract_destination_from_item(raw)
				if dest2 != "":
					_destinations_cache[nm2] = dest2
			var cargo_arr2: Array = (vehicle as Dictionary).get("cargo", [])
			for ci in cargo_arr2:
				if not (ci is Dictionary):
					continue
				var nm3 := String((ci as Dictionary).get("name", (ci as Dictionary).get("base_name", "Item")))
				var dest3 := _extract_destination_from_item(ci)
				if dest3 != "":
					_destinations_cache[nm3] = dest3

		# --- Convoy Name as Title ---
		if is_instance_valid(title_label):
			title_label.text = convoy_data_received.get("convoy_name", "N/A")

		# --- Resources (Fuel, Water, Food) ---
		var current_fuel = convoy_data_received.get("fuel", 0.0)
		var max_fuel = convoy_data_received.get("max_fuel", 0.0)
		if is_instance_valid(fuel_text_label): fuel_text_label.text = "Fuel: %s / %s" % [NumberFormat.fmt_float(current_fuel, 2), NumberFormat.fmt_float(max_fuel, 2)]
		if is_instance_valid(fuel_bar): _set_resource_bar_style(fuel_bar, fuel_text_label, current_fuel, max_fuel)

		var current_water = convoy_data_received.get("water", 0.0)
		var max_water = convoy_data_received.get("max_water", 0.0)
		if is_instance_valid(water_text_label): water_text_label.text = "Water: %s / %s" % [NumberFormat.fmt_float(current_water, 2), NumberFormat.fmt_float(max_water, 2)]
		if is_instance_valid(water_bar): _set_resource_bar_style(water_bar, water_text_label, current_water, max_water)

		var current_food = convoy_data_received.get("food", 0.0)
		var max_food = convoy_data_received.get("max_food", 0.0)
		if is_instance_valid(food_text_label): food_text_label.text = "Food: %s / %s" % [NumberFormat.fmt_float(current_food, 2), NumberFormat.fmt_float(max_food, 2)]
		if is_instance_valid(food_bar): _set_resource_bar_style(food_bar, food_text_label, current_food, max_food)

		# --- Performance Stats (Speed, Offroad, Efficiency) ---
		# Assuming these are rated 0-100 for coloring, adjust max_value if different
		var top_speed = convoy_data_received.get("top_speed", 0.0)
		if is_instance_valid(speed_text_label): speed_text_label.text = "Top Speed: %s" % NumberFormat.fmt_float(top_speed, 2)
		if is_instance_valid(speed_box): _set_fixed_color_box_style(speed_box, speed_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

		var offroad = convoy_data_received.get("offroad_capability", 0.0)
		if is_instance_valid(offroad_text_label): offroad_text_label.text = "Offroad: %s" % NumberFormat.fmt_float(offroad, 2)
		if is_instance_valid(offroad_box): _set_fixed_color_box_style(offroad_box, offroad_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

		var efficiency = convoy_data_received.get("efficiency", 0.0)
		if is_instance_valid(efficiency_text_label): efficiency_text_label.text = "Efficiency: %s" % NumberFormat.fmt_float(efficiency, 2)
		if is_instance_valid(efficiency_box): _set_fixed_color_box_style(efficiency_box, efficiency_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

		# --- Cargo Volume and Weight Bars ---
		if is_instance_valid(cargo_volume_text_label) and is_instance_valid(cargo_volume_bar):
			var used_volume = convoy_data_received.get("total_cargo_capacity", 0.0) - convoy_data_received.get("total_free_space", 0.0)
			var total_volume = convoy_data_received.get("total_cargo_capacity", 0.0)
			cargo_volume_text_label.text = "Cargo Volume: %s / %s" % [NumberFormat.fmt_float(used_volume, 2), NumberFormat.fmt_float(total_volume, 2)]
			_set_progressbar_style(cargo_volume_bar, used_volume, total_volume)
		if is_instance_valid(cargo_weight_text_label) and is_instance_valid(cargo_weight_bar):
			var used_weight = convoy_data_received.get("total_weight_capacity", 0.0) - convoy_data_received.get("total_remaining_capacity", 0.0)
			var total_weight = convoy_data_received.get("total_weight_capacity", 0.0)
			cargo_weight_text_label.text = "Cargo Weight: %s / %s" % [NumberFormat.fmt_float(used_weight, 2), NumberFormat.fmt_float(total_weight, 2)]
			_set_progressbar_style(cargo_weight_bar, used_weight, total_weight)

		# --- Populate Journey Details (or hide them if no journey) ---
		var journey_data = convoy_data_received.get("journey")
		var has_journey = journey_data != null and not journey_data.is_empty()

		if is_instance_valid(preview_title_label):
			if has_journey:
				preview_title_label.text = "Journey Preview"
			else:
				var s_dict := _get_current_settlement_dict()
				var s_name := str(s_dict.get("name", "Settlement"))
				if s_name == "" or s_name == "null":
					s_name = "Settlement"
				preview_title_label.text = "%s Preview" % s_name

		# Conditionally show/hide vendor tabs based on journey status
		if is_instance_valid(journey_tab_button):
			journey_tab_button.visible = has_journey
		if is_instance_valid(settlement_missions_tab_button):
			settlement_missions_tab_button.visible = not has_journey
		if is_instance_valid(compatible_parts_tab_button):
			compatible_parts_tab_button.visible = not has_journey

		# If we are on a journey and a settlement tab is active, switch to the journey tab.
		if has_journey and (_current_vendor_tab == VendorTab.SETTLEMENT_MISSIONS or _current_vendor_tab == VendorTab.COMPATIBLE_PARTS):
			_current_vendor_tab = VendorTab.JOURNEY
			if is_instance_valid(journey_tab_button):
				journey_tab_button.button_pressed = true
		# If we are NOT on a journey and the journey tab is active, switch to the convoy tab.
		elif not has_journey and _current_vendor_tab == VendorTab.JOURNEY:
			_current_vendor_tab = VendorTab.CONVOY_MISSIONS
			if is_instance_valid(convoy_missions_tab_button):
				convoy_missions_tab_button.button_pressed = true

		# Only populate the labels if there is a journey
		if has_journey:
			if is_instance_valid(journey_dest_label):
				var dest_text: String = "Destination: N/A"
				# Assuming journey_data contains destination coordinates, e.g., 'dest_coord_x', 'dest_coord_y'
				var dest_coord_x_val # Can be float or int
				var dest_coord_y_val # Can be float or int

				var direct_x = journey_data.get("dest_coord_x")
				var direct_y = journey_data.get("dest_coord_y")

				if direct_x != null and direct_y != null:
					dest_coord_x_val = direct_x
					dest_coord_y_val = direct_y
				else:
					# Fallback: Try to get destination from the end of route_x and route_y arrays
					var route_x_arr: Array = journey_data.get("route_x", [])
					var route_y_arr: Array = journey_data.get("route_y", [])
					if not route_x_arr.is_empty() and not route_y_arr.is_empty():
						if route_x_arr.size() == route_y_arr.size(): # Ensure arrays are consistent
							dest_coord_x_val = route_x_arr[-1] # Get last element
							dest_coord_y_val = route_y_arr[-1] # Get last element
						else:
							printerr("ConvoyMenu: route_x and route_y arrays have different sizes.")

				if dest_coord_x_val != null and dest_coord_y_val != null:
					var dest_x_int: int = roundi(float(dest_coord_x_val))
					var dest_y_int: int = roundi(float(dest_coord_y_val))
					var settlement_name: String = _get_settlement_name_from_coords(dest_x_int, dest_y_int)
					if settlement_name.begins_with("N/A"):
						dest_text = "Destination: %s (at %s, %s)" % [settlement_name, NumberFormat.fmt_float(dest_coord_x_val, 2), NumberFormat.fmt_float(dest_coord_y_val, 2)]
					else:
						dest_text = "Destination: %s" % settlement_name
				else:
					dest_text = "Destination: No coordinates"
				journey_dest_label.text = dest_text

			if is_instance_valid(journey_progress_bar) and is_instance_valid(journey_progress_label):
				var progress = journey_data.get("progress", 0.0)
				var length = journey_data.get("length", 0.0)
				var progress_percentage = 0.0
				if length > 0:
					progress_percentage = (progress / length) * 100.0
				
				journey_progress_bar.value = progress_percentage
				journey_progress_label.text = NumberFormat.fmt_float(progress_percentage, 2) + "%"

			if is_instance_valid(journey_eta_label):
				var eta_value = journey_data.get("eta")
				var formatted_eta: String = preload("res://Scripts/System/date_time_util.gd").format_timestamp_display(eta_value, true)
				journey_eta_label.text = "ETA: " + formatted_eta

		# --- Populate Vehicle Manifest (Simplified) ---
		if is_instance_valid(vehicles_label):
			var vehicle_list: Array = convoy_data_received.get("vehicle_details_list", [])
			var vehicle_display_strings: Array = []
			for vehicle_detail in vehicle_list:
				if vehicle_detail is Dictionary:
					var v_name = vehicle_detail.get("name", "Unknown Vehicle")
					var v_make_model = vehicle_detail.get("make_model", "")
					if not v_make_model.is_empty():
						vehicle_display_strings.append("- %s (%s)" % [v_name, v_make_model])
					else:
						vehicle_display_strings.append("- %s" % v_name)
			vehicles_label.text = "Vehicles:\n" + "\n".join(vehicle_display_strings)

		# --- Populate Cargo Details (Simplified) ---
		if is_instance_valid(all_cargo_label):
			var all_cargo_list: Array = convoy_data_received.get("all_cargo", [])
			var cargo_summary: Array = []
			var cargo_counts: Dictionary = {}
			for cargo_item in all_cargo_list:
				if cargo_item is Dictionary:
					var item_name = cargo_item.get("name", "Unknown Item")
					cargo_counts[item_name] = cargo_counts.get(item_name, 0) + cargo_item.get("quantity", 0)
			for item_name in cargo_counts:
				cargo_summary.append("%s x%s" % [item_name, cargo_counts[item_name]])
			all_cargo_label.text = "Cargo: " + ", ".join(cargo_summary)

		# Update the vendor preview. This will be called again by signals when async data arrives.
		# Queue an update. This will be debounced with other signals that fire on open.
		_queue_vendor_preview_update()
		# Initial font size update after data is populated
		call_deferred("_update_font_sizes")

func _queue_vendor_preview_update() -> void:
	# Debounce updates to prevent UI thrashing from rapid signals.
	if is_instance_valid(_vendor_preview_update_timer):
		_vendor_preview_update_timer.start()
	else:
		_vendor_preview_update_pending = true

func _update_vendor_preview() -> void:
	if not is_instance_valid(self) or convoy_data_received == null:
		return
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] _update_vendor_preview convoy_id=", String(convoy_data_received.get("convoy_id", convoy_data_received.get("id", ""))),
			" coords=", Vector2i(roundi(float(convoy_data_received.get("x", 0))), roundi(float(convoy_data_received.get("y", 0)))),
			" current_tab=", int(_current_vendor_tab))
	# Mission cargo preview: show items marked mission-critical if present
	_convoy_mission_items = _collect_mission_cargo_items(convoy_data_received)
	_settlement_mission_items = _collect_settlement_mission_items()
	
	# Compatible parts preview: use GDM mechanic vendor availability snapshot if available
	var compat_summary: Array[String] = []
	if is_instance_valid(_mechanics_service) and _mechanics_service.has_method("get_mechanic_probe_snapshot"):
		var snap: Dictionary = _mechanics_service.get_mechanic_probe_snapshot()
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] mech_probe_snapshot keys=", snap.keys())
		# Prefer showing actual part names using cargo_id enrichment
		var part_names: Array[String] = []
		var c2s: Dictionary = snap.get("cargo_id_to_slot", {}) if snap.has("cargo_id_to_slot") else {}
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] mech_probe_snapshot cargo_id_to_slot size=", (c2s.size() if c2s is Dictionary else -1))
			if c2s is Dictionary and not c2s.is_empty():
				var sample: Array = []
				var b := 5
				for cid in c2s.keys():
					sample.append({"cid": String(cid), "slot": String(c2s.get(cid, ""))})
					b -= 1
					if b <= 0:
						break
				print("[ConvoyMenu][Debug] mech_probe_snapshot sample=", sample)
		if c2s is Dictionary and not c2s.is_empty():
			# Attempt to fetch enriched cargo names for each cargo_id
			if _mechanics_service.has_method("get_enriched_cargo"):
				for cid in c2s.keys():
					var cargo: Dictionary = _mechanics_service.get_enriched_cargo(String(cid))
					var nm := String(cargo.get("name", cargo.get("base_name", "")))
					if nm == "" and _mechanics_service.has_method("ensure_cargo_details"):
						# Trigger enrichment for future updates
						_mechanics_service.ensure_cargo_details(String(cid))
					if nm != "":
						part_names.append(nm)
		# If names are still empty, fall back to slot summary counts
		if part_names.is_empty():
			if c2s is Dictionary and not c2s.is_empty():
				var slot_counts: Dictionary = {}
				for cid in c2s.keys():
					var slot_name: String = String(c2s.get(cid, ""))
					# If slot is unknown, use "General Part" as a label
					var display_slot = slot_name if slot_name != "" else "General"
					slot_counts[display_slot] = int(slot_counts.get(display_slot, 0)) + 1
				for sname in slot_counts.keys():
					compat_summary.append("%s (%d)" % [String(sname), int(slot_counts.get(sname, 0))])
		# If we found names, use them directly
		if not part_names.is_empty():
			compat_summary = part_names
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] compat_summary=", compat_summary)
	_compatible_part_items = compat_summary
	if _debug_convoy_menu and _compatible_part_items.is_empty():
		var settlement := _get_current_settlement_dict()
		if settlement.is_empty():
			print("[ConvoyMenu][Debug] Compatible Parts empty: no current settlement match; cached_settlements_count=", _latest_all_settlements.size())
		else:
			var vendors_any: Variant = settlement.get("vendors", [])
			var vendors: Array = vendors_any if vendors_any is Array else []
			print("[ConvoyMenu][Debug] Compatible Parts empty: settlement=", String(settlement.get("name", "")), " vendors_count=", vendors.size())
			var budget := 3
			for v_any in vendors:
				if budget <= 0:
					break
				budget -= 1
				if v_any is Dictionary:
					var v: Dictionary = v_any
					var vid := String(v.get("vendor_id", v.get("id", "")))
					var inv_any: Variant = v.get("cargo_inventory", null)
					var inv_len := (inv_any as Array).size() if inv_any is Array else -1
					print("[ConvoyMenu][Debug] settlement vendor vid=", vid, " cargo_inventory_len=", inv_len, " keys=", v.keys())
				else:
					print("[ConvoyMenu][Debug] settlement vendor entry type=", typeof(v_any), " val=", str(v_any))

	# If cache is available, merge cached destinations into display strings
	if _destinations_cache is Dictionary and not _destinations_cache.is_empty():
		for i in range(_convoy_mission_items.size()):
			var s := _convoy_mission_items[i]
			var name_only := s
			var sep_idx := name_only.find(" — to ")
			var _sep_len := 6
			if sep_idx == -1:
				sep_idx = name_only.find(" -> ")
				_sep_len = 4
			if sep_idx != -1:
				name_only = name_only.substr(0, sep_idx)
			var cached_dest := String(_destinations_cache.get(name_only, ""))
			if cached_dest != "":
				_convoy_mission_items[i] = "%s — to %s" % [name_only, cached_dest]

	# Render the new tabbed display
	_render_vendor_preview_display()
	# Ensure grid is responsive after content updates
	_update_vendor_grid_columns()

func _render_vendor_preview_display() -> void:
	# Update button text with counts
	if is_instance_valid(convoy_missions_tab_button):
		convoy_missions_tab_button.text = "Active Deliveries (%d)" % _convoy_mission_items.size()
	if is_instance_valid(settlement_missions_tab_button):
		settlement_missions_tab_button.text = "Available Deliveries (%d)" % _settlement_mission_items.size()
	if is_instance_valid(compatible_parts_tab_button):
		compatible_parts_tab_button.text = "Available Parts (%d)" % _compatible_part_items.size()
	# Journey tab does not need a count

	# Show/hide content containers based on the active tab
	var is_journey_tab = (_current_vendor_tab == VendorTab.JOURNEY)

	journey_info_vbox.visible = is_journey_tab

	# Logic to hide "Active Missions" if empty
	if _convoy_mission_items.is_empty():
		if is_instance_valid(convoy_missions_tab_button):
			convoy_missions_tab_button.visible = false
		# If we were on the hidden tab, switch to Settlement/Available Missions
		if _current_vendor_tab == VendorTab.CONVOY_MISSIONS:
			_current_vendor_tab = VendorTab.SETTLEMENT_MISSIONS
			if is_instance_valid(settlement_missions_tab_button):
				settlement_missions_tab_button.button_pressed = true
	else:
		if is_instance_valid(convoy_missions_tab_button):
			convoy_missions_tab_button.visible = true

	if is_journey_tab:
		vendor_item_container.visible = false
		vendor_no_items_label.visible = false
		return # Nothing more to render for the journey tab

	# --- Handle non-journey tabs ---
	# Clear previous items from the grid
	for child in vendor_item_grid.get_children():
		child.queue_free()

	# Get the correct list of items for the current tab
	var content_list: Array[String] = []
	match _current_vendor_tab:
		VendorTab.CONVOY_MISSIONS:
			content_list = _convoy_mission_items
		VendorTab.SETTLEMENT_MISSIONS:
			content_list = _settlement_mission_items
		VendorTab.COMPATIBLE_PARTS:
			content_list = _compatible_part_items

	if content_list.is_empty():
		vendor_item_container.visible = false
		vendor_no_items_label.visible = true
	else:
		vendor_item_container.visible = true
		vendor_no_items_label.visible = false
		for item_string in content_list:
			var button := Button.new()
			# Support destination annotations in two formats:
			# "name — to DEST" (em dash syntax) or "name -> DEST" (arrow syntax)
			var name_qty := item_string
			var lookup_key := item_string
			var dest_text := ""
			var sep_idx := name_qty.find(" — to ")
			var sep_len := 6 # length of " — to "
			if sep_idx == -1:
				sep_idx = name_qty.find(" -> ")
				sep_len = 4
			if sep_idx != -1:
				dest_text = name_qty.substr(sep_idx + sep_len)
				name_qty = name_qty.substr(0, sep_idx)
			# No quantity display: use item name only
			var item_name = name_qty
			# GDScript does not have C-style ternary; use if/else
			var dest_line := ""
			if dest_text != "":
				dest_line = "\n→ " + dest_text
			button.text = "%s%s" % [item_name, dest_line]
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# NOTE: Button text is clipped by default; allow enough height for the optional 2nd line.
			button.custom_minimum_size.y = 54 if dest_text != "" else 36
			button.clip_text = false if dest_text != "" else true
			# Attach a deep-link intent so clicks can navigate to the right destination.
			var nav_intent: Dictionary = {}
			match _current_vendor_tab:
				VendorTab.CONVOY_MISSIONS:
					var cid := String(_active_mission_cargo_id_by_display.get(lookup_key, ""))
					if cid == "":
						cid = String(_active_mission_cargo_id_by_name.get(item_name, ""))
					nav_intent = {"target": "cargo_inspect", "cargo_id": cid, "item_name": item_name}
					if cid == "":
						button.tooltip_text = "Open Cargo (no cargo_id available for deep-link)"
				VendorTab.SETTLEMENT_MISSIONS:
					nav_intent = _build_settlement_focus_intent(item_name, "missions")
				VendorTab.COMPATIBLE_PARTS:
					nav_intent = _build_settlement_focus_intent(item_name, "parts")
					# If this looks like a slot summary (e.g., "Engine (2)") rather than a real item,
					# keep navigation but expect focus to be best-effort.
			button.set_meta("nav_intent", nav_intent)
			button.pressed.connect(_on_vendor_preview_item_button_pressed.bind(button))
			_style_vendor_item_button(button, _current_vendor_tab)
			vendor_item_grid.add_child(button)
	
	# Ensure font sizes are applied to newly created buttons
	_update_font_sizes()


func _get_current_settlement_dict() -> Dictionary:
	if not (convoy_data_received is Dictionary) or convoy_data_received.is_empty():
		return {}
	var sx := roundi(float(convoy_data_received.get("x", 0)))
	var sy := roundi(float(convoy_data_received.get("y", 0)))
	for s in _latest_all_settlements:
		if s is Dictionary and roundi(float(s.get("x", -999999))) == sx and roundi(float(s.get("y", -999999))) == sy:
			return s
	return {}


func _resolve_vendor_focus_for_item(item_name: String, category_hint: String) -> Dictionary:
	# Best-effort: find a vendor at the current settlement whose inventory contains this item.
	# Returns a partial dict like {vendor_id, vendor_name_hint}.
	if item_name == "":
		return {}
	var settlement := _get_current_settlement_dict()
	if settlement.is_empty():
		return {}
	var vendors: Array = settlement.get("vendors", [])
	for v_any in vendors:
		var v: Dictionary = {}
		if v_any is Dictionary:
			v = v_any
		elif v_any is String:
			var looked: Dictionary = _get_vendor_by_id(String(v_any))
			if not looked.is_empty():
				v = looked
			else:
				v = {"vendor_id": String(v_any)}
		else:
			continue

		var vid := String(v.get("vendor_id", ""))
		var vname := String(v.get("name", v.get("vendor_name", "")))
		var inv: Array = []
		if v.get("cargo_inventory") is Array:
			inv = v.get("cargo_inventory")
		elif v.get("inventory") is Array:
			inv = v.get("inventory")

		for it_any in inv:
			if not (it_any is Dictionary):
				continue
			var it: Dictionary = it_any
			var nm := String(it.get("name", it.get("base_name", "")))
			if nm != item_name:
				continue
			# Optional category filtering to avoid accidental matches.
			if category_hint == "parts" and not _is_part_item(it):
				continue
			if category_hint == "missions":
				# Accept either central classification or presence of delivery_reward.
				var mission_ok := false
				if ItemsData != null and ItemsData.MissionItem:
					mission_ok = ItemsData.MissionItem._looks_like_mission_dict(it)
				if not mission_ok:
					var dr = it.get("delivery_reward")
					mission_ok = (dr is float or dr is int) and float(dr) > 0.0
				if not mission_ok:
					continue

			var out: Dictionary = {}
			if vid != "":
				out["vendor_id"] = vid
			if vname != "":
				out["vendor_name_hint"] = vname
			return out

	return {}


func _build_settlement_focus_intent(item_name: String, category_hint: String) -> Dictionary:
	var intent: Dictionary = {
		"target": "settlement_vendor",
		"mode": "buy",
		"tree": "vendor",
		"category_hint": category_hint,
	}
	if item_name != "":
		intent["item_restore_key"] = "name:%s" % item_name
	var vendor_bits := _resolve_vendor_focus_for_item(item_name, category_hint)
	for k in vendor_bits.keys():
		intent[k] = vendor_bits[k]
	return intent


func _on_vendor_preview_item_button_pressed(button: Button) -> void:
	if not is_instance_valid(button):
		return
	if not (convoy_data_received is Dictionary) or convoy_data_received.is_empty():
		return

	var intent_any: Variant = button.get_meta("nav_intent", null)
	if typeof(intent_any) != TYPE_DICTIONARY:
		# Fallback: open settlement menu (best default for preview buttons)
		emit_signal("open_settlement_menu_requested", convoy_data_received)
		return
	var intent: Dictionary = intent_any as Dictionary
	var target := String(intent.get("target", ""))

	if target == "cargo_inspect":
		var cargo_id := String(intent.get("cargo_id", ""))
		if cargo_id != "":
			emit_signal("open_cargo_menu_inspect_requested", convoy_data_received, {"cargo_id": cargo_id})
		else:
			# No cargo_id means we can't deep-link; still open Cargo menu.
			push_warning("ConvoyMenu: Active Mission deep-link missing cargo_id; opening Cargo menu without focus. item_name=%s" % String(intent.get("item_name", "")))
			emit_signal("open_cargo_menu_requested", convoy_data_received)
		return

	if target == "settlement_vendor":
		var has_focus_bits := String(intent.get("item_restore_key", "")) != "" or String(intent.get("vendor_id", "")) != "" or String(intent.get("vendor_name_hint", "")) != ""
		if has_focus_bits:
			emit_signal("open_settlement_menu_with_focus_requested", convoy_data_received, intent)
		else:
			emit_signal("open_settlement_menu_requested", convoy_data_received)
		return

	# Default fallback
	emit_signal("open_settlement_menu_requested", convoy_data_received)

func _collect_mission_cargo_items(convoy: Dictionary) -> Array[String]:
	# Mirror vendor_trade_panel.gd logic to avoid mismatches.
	# Rules:
	# 1) Prefer vehicle.cargo_items_typed entries where typed.category == "mission".
	# 2) Else, treat raw cargo entries as mission if they have non-null `recipient` or `delivery_reward`.
	# 3) Skip items that represent intrinsic parts (have `intrinsic_part_id`).
	# 4) If no per-vehicle cargo found, fall back to `convoy.cargo_inventory` with the same rules.
	var out: Array[String] = []
	var found_any_cargo := false
	var agg: Dictionary = {} # display_key -> total quantity
	_active_mission_cargo_id_by_name.clear()
	_active_mission_cargo_id_by_display.clear()
	var diag_typed_mission := 0
	var diag_raw_mission := 0
	var diag_allcargo_mission := 0
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] start mission aggregation. convoy keys=", convoy.keys())

	if convoy.has("vehicle_details_list") and convoy.vehicle_details_list is Array:
		for vehicle in convoy.vehicle_details_list:
			var vname := String((vehicle as Dictionary).get("name", "Vehicle")) if vehicle is Dictionary else "Vehicle"
			if _debug_convoy_menu:
				var typed_sz := 0
				if vehicle is Dictionary and vehicle.has("cargo_items_typed") and vehicle["cargo_items_typed"] is Array:
					typed_sz = (vehicle["cargo_items_typed"] as Array).size()
				var raw_sz := 0
				if vehicle is Dictionary and vehicle.has("cargo") and vehicle["cargo"] is Array:
					raw_sz = (vehicle["cargo"] as Array).size()
				print("[ConvoyMenu][Debug] vehicle=", vname, " typed_sz=", typed_sz, " raw_sz=", raw_sz)
			# Typed cargo path
			if vehicle.has("cargo_items_typed") and vehicle["cargo_items_typed"] is Array and not (vehicle["cargo_items_typed"] as Array).is_empty():
				for typed in vehicle["cargo_items_typed"]:
					# Accept both typed objects (Resource) and plain dictionaries
					var typed_cat := ""
					if typed is Dictionary:
						typed_cat = String((typed as Dictionary).get("category", ""))
					else:
						# GDScript Resources don't have has(), use get()
						var cat_any = typed.get("category") if typed is Object else null
						if cat_any != null:
							typed_cat = String(cat_any)
					if _debug_convoy_menu:
						print("[ConvoyMenu][Debug] typed item cat=", typed_cat, " q=", (typed.get("quantity") if typed is Object else ((typed as Dictionary).get("quantity", null) if typed is Dictionary else null)))
					found_any_cargo = true
					if typed_cat == "mission":
						var raw_item: Dictionary = {}
						if typed is Dictionary:
							raw_item = (typed as Dictionary).get("raw", {})
						else:
							# Try property access via get() on Resource
							var raw_any = typed.get("raw") if typed is Object else null
							if raw_any is Dictionary:
								raw_item = raw_any
						if raw_item.is_empty():
							continue
						# Exclude parts to avoid double-counting parts as mission cargo
						if _is_part_item(raw_item):
							if _debug_convoy_menu:
								print("[ConvoyMenu][Debug] skip typed mission (part) name=", String(raw_item.get("name", "Item")))
							continue
						if raw_item.has("intrinsic_part_id") and raw_item.get("intrinsic_part_id") != null:
							continue
						var item_name := String(raw_item.get("name", "Item"))
						var dest_key := _extract_destination_from_item(raw_item)
						var display_key := item_name
						if dest_key != "":
							display_key = "%s — to %s" % [item_name, dest_key]
						var cid := String(raw_item.get("cargo_id", raw_item.get("id", "")))
						if cid != "" and not _active_mission_cargo_id_by_name.has(item_name):
							_active_mission_cargo_id_by_name[item_name] = cid
						if cid != "" and not _active_mission_cargo_id_by_display.has(display_key):
							_active_mission_cargo_id_by_display[display_key] = cid
						var qty := 1
						if typed is Dictionary:
							qty = int((typed as Dictionary).get("quantity", 1))
						else:
							var q_any = typed.get("quantity") if typed is Object else null
							if q_any != null:
								qty = int(q_any)
						agg[display_key] = int(agg.get(display_key, 0)) + qty
						diag_typed_mission += 1
				# Also scan raw cargo for mission items regardless of typed presence
				var cargo_arr: Array = vehicle.get("cargo", [])
				if cargo_arr is Array and not cargo_arr.is_empty():
					for item in cargo_arr:
						found_any_cargo = true
						if not (item is Dictionary):
							continue
						if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
							continue
						if _looks_like_mission_item(item):
							var item_name2 := String(item.get("name", "Item"))
							var dest_key2 := _extract_destination_from_item(item)
							var display_key2 := item_name2
							if dest_key2 != "":
								display_key2 = "%s — to %s" % [item_name2, dest_key2]
							var cid2 := String(item.get("cargo_id", item.get("id", "")))
							if cid2 != "" and not _active_mission_cargo_id_by_name.has(item_name2):
								_active_mission_cargo_id_by_name[item_name2] = cid2
							if cid2 != "" and not _active_mission_cargo_id_by_display.has(display_key2):
								_active_mission_cargo_id_by_display[display_key2] = cid2
							var qty2 := int(item.get("quantity", 1))
							if _debug_convoy_menu:
								print("[ConvoyMenu][Debug] raw mission item=", item_name2, " q=", qty2)
							agg[display_key2] = int(agg.get(display_key2, 0)) + qty2
							diag_raw_mission += 1

	# Fallback to convoy-level inventory if nothing was found in vehicles
	if not found_any_cargo and convoy.has("cargo_inventory") and convoy.cargo_inventory is Array:
		for item in convoy.cargo_inventory:
			if not (item is Dictionary):
				continue
			if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
				continue
			if _looks_like_mission_item(item):
				var item_name3 := String(item.get("name", "Item"))
				var dest_key3 := _extract_destination_from_item(item)
				var display_key3 := item_name3
				if dest_key3 != "":
					display_key3 = "%s — to %s" % [item_name3, dest_key3]
				var cid3 := String(item.get("cargo_id", item.get("id", "")))
				if cid3 != "" and not _active_mission_cargo_id_by_name.has(item_name3):
					_active_mission_cargo_id_by_name[item_name3] = cid3
				if cid3 != "" and not _active_mission_cargo_id_by_display.has(display_key3):
					_active_mission_cargo_id_by_display[display_key3] = cid3
				var qty3 := int(item.get("quantity", 1))
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] inventory mission item=", item_name3, " q=", qty3)
				agg[display_key3] = int(agg.get(display_key3, 0)) + qty3
				diag_raw_mission += 1

	# Also scan convoy-level all_cargo for mission stacks
	var all_cargo: Array = convoy.get("all_cargo", [])
	if all_cargo is Array and not all_cargo.is_empty():
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] scanning all_cargo sz=", all_cargo.size())
		for ac in all_cargo:
			if not (ac is Dictionary):
				continue
			if ac.has("intrinsic_part_id") and ac.get("intrinsic_part_id") != null:
				continue
			if _looks_like_mission_item(ac):
				var aname := String(ac.get("name", "Item"))
				var dest_key4 := _extract_destination_from_item(ac)
				var display_key4 := aname
				if dest_key4 != "":
					display_key4 = "%s — to %s" % [aname, dest_key4]
				var cid4 := String(ac.get("cargo_id", ac.get("id", "")))
				if cid4 != "" and not _active_mission_cargo_id_by_name.has(aname):
					_active_mission_cargo_id_by_name[aname] = cid4
				if cid4 != "" and not _active_mission_cargo_id_by_display.has(display_key4):
					_active_mission_cargo_id_by_display[display_key4] = cid4
				var aq := int(ac.get("quantity", 1))
				agg[display_key4] = int(agg.get(display_key4, 0)) + (aq if aq > 0 else 1)
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] all_cargo mission item=", aname, " q=", aq)
				diag_allcargo_mission += 1

	# Build display strings from aggregated totals.
	# Keys are already in "name" or "name — to DEST" form.
	for k in agg.keys():
		out.append(String(k))
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] mission agg result=", out)
		print("[ConvoyMenu][Debug] diag typed=", diag_typed_mission, " raw=", diag_raw_mission, " all=", diag_allcargo_mission)
	return out

func _is_resource_item(d: Dictionary) -> bool:
	if not d:
		return false
	# Prefer centralized classification
	if ItemsData != null and ItemsData.ResourceItem:
		return ItemsData.ResourceItem._looks_like_resource_dict(d)
	# Fallback heuristics
	if d.get("is_raw_resource", false):
		return true
	if String(d.get("category", "")).to_lower() == "resource":
		return true
	for k in ["fuel", "water", "food"]:
		var v = d.get(k)
		if (v is float or v is int) and float(v) > 0.0:
			return true
	return false

func _is_part_item(d: Dictionary) -> bool:
	if not d:
		return false
	if ItemsData != null and ItemsData.PartItem:
		return ItemsData.PartItem._looks_like_part_dict(d)
	# Fallback: crude hint keys often present on parts
	var hint_keys = ["slot", "slot_name", "quality", "condition", "part_type", "part_modifiers"]
	for hk in hint_keys:
		if d.has(hk):
			return true
	return false

func _looks_like_mission_item(item: Dictionary) -> bool:
	# Prefer centralized classification when available
	if ItemsData != null and ItemsData.MissionItem:
		# Keep central classification but ensure reward-positive
		if not item:
			return false
		var dr_any = item.get("delivery_reward")
		if dr_any != null and (dr_any is float or dr_any is int) and float(dr_any) > 0.0:
			return true
		return false
	# Local rule: mission cargo must have positive delivery_reward and not be an intrinsic part
	if not item:
		return false
	if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
		return false
	if _is_part_item(item):
		return false
	var dr = item.get("delivery_reward")
	return (dr is float or dr is int) and float(dr) > 0.0

# Helper: scan an array of settlement records and aggregate mission items into agg
func _scan_settlement_array(arr: Array, agg: Dictionary) -> void:
	for it in arr:
		if not (it is Dictionary):
			continue
		if it.has("intrinsic_part_id") and it.get("intrinsic_part_id") != null:
			continue
		var mission_ok := false
		if ItemsData != null and ItemsData.MissionItem:
			mission_ok = ItemsData.MissionItem._looks_like_mission_dict(it)
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] _scan_settlement_array item=", String(it.get("name", it.get("base_name", "?"))), " mission=", mission_ok)
		if mission_ok:
			var nm := String(it.get("name", "Item"))
			var q := int(it.get("quantity", 1))
			agg[nm] = int(agg.get(nm, 0)) + (q if q > 0 else 1)

# Helper: extract integer-ish coords from a dictionary with flexible shapes
func _extract_coords_from_dict(d: Dictionary) -> Vector2i:
	var x_val: Variant = null
	var y_val: Variant = null
	if d.has("x") and d.has("y"):
		x_val = d.get("x")
		y_val = d.get("y")
	elif d.has("coord_x") and d.has("coord_y"):
		x_val = d.get("coord_x")
		y_val = d.get("coord_y")
	elif d.has("coords") and d.get("coords") is Array and (d.get("coords") as Array).size() >= 2:
		var ar: Array = d.get("coords")
		x_val = ar[0]
		y_val = ar[1]
	elif d.has("coord") and d.get("coord") is Array and (d.get("coord") as Array).size() >= 2:
		var ar2: Array = d.get("coord")
		x_val = ar2[0]
		y_val = ar2[1]

	var xi: int = roundi(float(x_val)) if x_val != null else 0
	var yi: int = roundi(float(y_val)) if y_val != null else 0
	return Vector2i(xi, yi)

# Collect available mission cargo at the current settlement (not in convoy)
func _collect_settlement_mission_items() -> Array[String]:
	var out: Array[String] = []
	if convoy_data_received == null:
		return out
	var diag_budget: int = 6
	var diag_vendor_budget: int = 6

	# Determine current convoy coordinates (round to match settlement keys)
	var sx: int = 0
	var sy: int = 0
	if convoy_data_received.has("x") and convoy_data_received.has("y"):
		sx = roundi(float(convoy_data_received.get("x", 0)))
		sy = roundi(float(convoy_data_received.get("y", 0)))
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] Collecting settlement missions at coords (", sx, ",", sy, ")")

	# Fallback: scan vendors at current settlement for mission cargo dictionaries (has recipient)
	# Use cached settlements snapshot
	var settlement_dict: Dictionary = {}
	for s in _latest_all_settlements:
		if s is Dictionary and int(roundf(float(s.get("x", -999999)))) == sx and int(roundf(float(s.get("y", -999999)))) == sy:
			settlement_dict = s
			break
	if settlement_dict.is_empty():
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] No settlement dict found at coords; vendor fallback unavailable.")
		return out

	var vendors: Array = settlement_dict.get("vendors", []) if settlement_dict.has("vendors") else []
	for v_any in vendors:
		# Vendors in map snapshot are often partial; prefer full vendor payloads from VendorService/Hub.
		var vendor_dict: Dictionary = {}
		var vid: String = ""
		if v_any is Dictionary:
			vendor_dict = v_any
			vid = String((v_any as Dictionary).get("vendor_id", (v_any as Dictionary).get("id", "")))
		elif v_any is String:
			vid = String(v_any)
		else:
			continue

		# Some settlement snapshots don't include vendor_id on the vendor object.
		# Try to infer from the first cargo item.
		if vid == "" and not vendor_dict.is_empty():
			var inv_probe: Variant = vendor_dict.get("cargo_inventory", null)
			if inv_probe is Array and not (inv_probe as Array).is_empty():
				var first_any: Variant = (inv_probe as Array)[0]
				if first_any is Dictionary:
					vid = String((first_any as Dictionary).get("vendor_id", ""))
					if _debug_convoy_menu and diag_vendor_budget > 0:
						diag_vendor_budget -= 1
						print("[ConvoyMenu][Debug] inferred vendor_id from cargo item vendor_id=", vid,
							" vendor_keys=", vendor_dict.keys(),
							" cargo_keys=", (first_any as Dictionary).keys())
			elif _debug_convoy_menu and diag_vendor_budget > 0:
				diag_vendor_budget -= 1
				print("[ConvoyMenu][Debug] settlement vendor missing vendor_id; keys=", vendor_dict.keys())

		# If we have a cached payload for this vendor, prefer it.
		# IMPORTANT: _get_vendor_by_id can return the map snapshot vendor entry; only trust it if it looks full.
		if vid != "":
			var cached := _get_vendor_by_id(vid)
			if not cached.is_empty() and _looks_like_full_vendor_payload(cached):
				vendor_dict = cached
			else:
				_request_vendor_details(vid)
		elif _debug_convoy_menu and diag_vendor_budget > 0:
			diag_vendor_budget -= 1
			print("[ConvoyMenu][Debug] cannot request vendor details (no vendor_id)")

		var cargo_inv: Array = vendor_dict.get("cargo_inventory", [])
		for ci_any in cargo_inv:
			if not (ci_any is Dictionary):
				continue
			var ci: Dictionary = ci_any
			# Use centralized mission detection when available
			var is_mission := false
			if ItemsData != null and ItemsData.MissionItem:
				is_mission = ItemsData.MissionItem._looks_like_mission_dict(ci)
			else:
				var dr = ci.get("delivery_reward")
				is_mission = (dr is float or dr is int) and float(dr) > 0.0
			if not is_mission:
				continue
			var nm2 := String(ci.get("name", ci.get("base_name", "Item")))
			# Force-request full vendor payload based on the mission item's origin vendor_id.
			# Settlement snapshot vendor entries sometimes omit vendor_id, but cargo items often include it.
			var origin_vid := String(ci.get("vendor_id", "")).strip_edges()
			if origin_vid != "":
				_request_vendor_details(origin_vid)
			var dest2 := _extract_destination_from_item(ci)
			# Fallback: mission cargo from snapshots may omit routing fields; try to enrich by cargo_id.
			if dest2 == "":
				var cid2 := String(ci.get("cargo_id", ""))
				if cid2 != "" and is_instance_valid(_mechanics_service):
					if _mechanics_service.has_method("get_enriched_cargo"):
						var enriched_any: Variant = _mechanics_service.get_enriched_cargo(cid2)
						if enriched_any is Dictionary and not (enriched_any as Dictionary).is_empty():
							dest2 = _extract_destination_from_item(enriched_any as Dictionary)
					if dest2 == "" and _mechanics_service.has_method("ensure_cargo_details"):
						if _debug_convoy_menu and diag_budget > 0:
							print("[ConvoyMenu][Debug][AvailMission] requesting cargo enrichment cargo_id=", cid2)
						_mechanics_service.ensure_cargo_details(cid2)
			if _debug_convoy_menu and diag_budget > 0:
				diag_budget -= 1
				var rec_any: Variant = ci.get("recipient", null)
				var mvid_any: Variant = ci.get("mission_vendor_id", null)
				print("[ConvoyMenu][Debug][AvailMission] name=", nm2,
					" dest=", dest2,
					" recipient=", rec_any,
					" mission_vendor_id=", mvid_any,
					" recipient_vendor_id=", ci.get("recipient_vendor_id", null),
					" destination_vendor_id=", ci.get("destination_vendor_id", null),
					" recipient_settlement_name=", ci.get("recipient_settlement_name", null),
					" keys=", (ci.keys() if ci is Dictionary else [])
				)
			var entry2 := "%s" % [nm2]
			if dest2 != "":
				entry2 += " — to %s" % dest2
			out.append(entry2)

	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] Settlement missions via vendor fallback: ", out)
	return out


func _on_cargo_data_received(cargo: Dictionary) -> void:
	# Cargo enrichment responses can include recipient/destination fields.
	# When one arrives, refresh preview so Available Missions can show destinations.
	if not (cargo is Dictionary) or cargo.is_empty():
		return
	# Keep this cheap: only queue a refresh if this looks like mission cargo or has useful destination fields.
	var looks_mission := false
	if ItemsData != null and ItemsData.MissionItem:
		looks_mission = ItemsData.MissionItem._looks_like_mission_dict(cargo)
	else:
		var dr = cargo.get("delivery_reward")
		looks_mission = (dr is float or dr is int) and float(dr) > 0.0

	var looks_part := false
	if ItemsData != null and ItemsData.PartItem:
		looks_part = ItemsData.PartItem._looks_like_part_dict(cargo)

	if not looks_mission and not looks_part and cargo.get("recipient_settlement_name") == null and cargo.get("recipient") == null and cargo.get("mission_vendor_id") == null:
		return
	_queue_vendor_preview_update()

func _infer_destination_for_item(convoy: Dictionary, item_name: String) -> String:
	# Attempt to find destination for a given mission item within convoy cargo structures.
	# Look into vehicle cargo typed/raw and convoy-level cargo inventory for fields like
	# 'recipient_settlement_name', 'destination', 'dest_settlement', or coordinates.
	var candidates: Array[String] = []
	# Scan vehicles
	var vehicles: Array = convoy.get("vehicle_details_list", [])
	for vehicle in vehicles:
		if not (vehicle is Dictionary):
			continue
		var typed_arr: Array = vehicle.get("cargo_items_typed", [])
		for typed in typed_arr:
			var raw: Dictionary = {}
			if typed is Dictionary:
				raw = (typed as Dictionary).get("raw", {})
			else:
				var raw_any = typed.get("raw") if typed is Object else null
				if raw_any is Dictionary:
					raw = raw_any
			if raw.is_empty():
				continue
			if String(raw.get("name", "")) != item_name:
				continue
			var dest := _extract_destination_from_item(raw)
			if dest != "":
				candidates.append(dest)
		var cargo_arr: Array = vehicle.get("cargo", [])
		for ci in cargo_arr:
			if not (ci is Dictionary):
				continue
			if String(ci.get("name", "")) != item_name:
				continue
			var dest2 := _extract_destination_from_item(ci)
			if dest2 != "":
				candidates.append(dest2)
	# Scan convoy-level inventory
	var inv: Array = convoy.get("cargo_inventory", [])
	for ci2 in inv:
		if not (ci2 is Dictionary):
			continue
		if String(ci2.get("name", "")) != item_name:
			continue
		var dest3 := _extract_destination_from_item(ci2)
		if dest3 != "":
			candidates.append(dest3)
	# Return the first distinct destination if any
	if candidates.size() > 0:
		return candidates[0]
	return ""

func _extract_destination_from_item(item: Dictionary) -> String:
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] _extract_destination_from_item keys=", (item.keys() if item is Dictionary else []))
	# Fast path: trust GameDataManager-provided destination name first to avoid race conditions
	if item.has("recipient_settlement_name"):
		var rsn_val = item.get("recipient_settlement_name")
		if rsn_val != null:
			var rsn := str(rsn_val)
			if rsn != "" and rsn != "null":
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] dest via recipient_settlement_name=", rsn)
				return rsn

	# 1) Other direct settlement name fields
	var name_fields := ["destination_settlement_name", "dest_settlement", "destination_name"]
	for k in name_fields:
		if item.has(k):
			var v_val = item.get(k)
			if v_val != null:
				var v := str(v_val)
				if v != "" and v != "null":
					if _debug_convoy_menu:
						print("[ConvoyMenu][Debug] dest via direct name field ", k, "=", v)
					return v

	# 1b) Recipient settlement object with name
	if item.has("recipient_settlement") and (item.get("recipient_settlement") is Dictionary):
		var rs_dict: Dictionary = item.get("recipient_settlement")
		var rs_name_val = rs_dict.get("name")
		if rs_name_val != null:
			var rs_name := str(rs_name_val)
			if rs_name != "" and rs_name != "null":
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] dest via recipient_settlement.name=", rs_name)
				return rs_name
		# Try coords if name missing
		var rs_coords := _extract_coords_from_dict(rs_dict)
		if rs_coords != Vector2i.ZERO:
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] dest via recipient_settlement coords=", rs_coords)
			return "(%d, %d)" % [rs_coords.x, rs_coords.y]

	# 2) Resolve via vendor_id -> settlement name using cached settlement/vendor data
	# IMPORTANT: Do NOT use plain `vendor_id` here; that is often the origin vendor
	# for available missions and will incorrectly map to the current settlement.
	var vendor_id_fields := ["recipient_vendor_id", "destination_vendor_id", "dest_vendor_id"]
	for vk in vendor_id_fields:
		if item.has(vk):
			var vid_val = item.get(vk)
			if vid_val != null:
				var vid := str(vid_val)
				if vid != "" and vid != "null":
					# Prefer settlement lookup via vendor
					var s = _get_settlement_for_vendor_id(vid)
					if s is Dictionary:
						var sn_val = (s as Dictionary).get("name")
						if sn_val != null:
							var sn := str(sn_val)
							if sn != "" and sn != "null":
								return sn
					# Fallback: vendor name via shared resolver (VendorTradePanel semantics)
					var vn := ""
					if VendorPanelContextController != null:
						vn = str(VendorPanelContextController.get_vendor_name_for_recipient(self, vid))
					if vn != "" and vn != "null" and vn != "Unknown Vendor":
						return vn

	# 2b) Some mission payloads use `mission_vendor_id` as the destination vendor when `recipient` is missing.
	# Mirror VendorCargoAggregator behavior: only use it when we don't have `recipient`.
	if item.get("recipient") == null and item.has("mission_vendor_id") and item.get("mission_vendor_id") != null:
		var mvid := str(item.get("mission_vendor_id"))
		if mvid != "" and mvid != "null":
			var sm: Dictionary = _get_settlement_for_vendor_id(mvid)
			if not sm.is_empty():
				var smn_val2: Variant = sm.get("name")
				if smn_val2 != null:
					var smn2 := str(smn_val2)
					if smn2 != "" and smn2 != "null":
						return smn2
			var vvn2 := ""
			if VendorPanelContextController != null:
				vvn2 = str(VendorPanelContextController.get_vendor_name_for_recipient(self, mvid))
			if vvn2 != "" and vvn2 != "null" and vvn2 != "Unknown Vendor":
				return vvn2

	# 0) Fallback to resolving recipient field (destination vendor/settlement)
	var recipient_any: Variant = item.get("recipient", null)
	if recipient_any != null:
		if recipient_any is Dictionary:
			var rdict: Dictionary = recipient_any
			var rname_val = rdict.get("name")
			if rname_val != null:
				var rname := str(rname_val)
				if rname != "" and rname != "null":
					if _debug_convoy_menu:
						print("[ConvoyMenu][Debug] dest via recipient.name=", rname)
					return rname
			# recipient_settlement_id direct mapping
			var rsid_val = rdict.get("recipient_settlement_id", rdict.get("settlement_id"))
			if rsid_val != null:
				var rsid := str(rsid_val)
				for s2 in _latest_all_settlements:
					if s2 is Dictionary and str((s2 as Dictionary).get("sett_id", (s2 as Dictionary).get("id", ""))) == rsid:
						var sn2_val = (s2 as Dictionary).get("name")
						if sn2_val != null:
							var sn2 := str(sn2_val)
							if sn2 != "" and sn2 != "null":
								if _debug_convoy_menu:
									print("[ConvoyMenu][Debug] dest via recipient_settlement_id=", sn2)
								return sn2
			# recipient may carry sett_id
			var sett_id_val = rdict.get("sett_id")
			if sett_id_val != null:
				var sett_id := str(sett_id_val)
				for s in _latest_all_settlements:
					if s is Dictionary and str((s as Dictionary).get("sett_id", "")) == sett_id:
						var sn_val = (s as Dictionary).get("name")
						if sn_val != null:
							var sn := str(sn_val)
							if sn != "" and sn != "null":
								if _debug_convoy_menu:
									print("[ConvoyMenu][Debug] dest via recipient.sett_id=", sn)
								return sn
			# recipient may have coordinates
			var r_coords := _extract_coords_from_dict(rdict)
			if r_coords != Vector2i.ZERO:
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] dest via recipient coords=", r_coords)
				return "(%d, %d)" % [r_coords.x, r_coords.y]
			# recipient may carry vendor_id
			var rvid_val = rdict.get("vendor_id", rdict.get("recipient_vendor_id"))
			if rvid_val != null:
				var rvid := str(rvid_val)
				if rvid != "" and rvid != "null":
					var s = _get_settlement_for_vendor_id(rvid)
					if s is Dictionary:
						var sn2_val = (s as Dictionary).get("name")
						if sn2_val != null:
							var sn2 := str(sn2_val)
							if sn2 != "" and sn2 != "null":
								return sn2
					var vn2 := ""
					if VendorPanelContextController != null:
						vn2 = str(VendorPanelContextController.get_vendor_name_for_recipient(self, rvid))
					if vn2 != "" and vn2 != "null" and vn2 != "Unknown Vendor":
						return vn2
		elif recipient_any is String or recipient_any is int or recipient_any is float:
			# Some payloads use numeric recipient ids.
			var rvid_str := str(recipient_any)
			if rvid_str != "" and rvid_str != "null":
				var s3: Dictionary = _get_settlement_for_vendor_id(rvid_str)
				if not s3.is_empty():
					var sn3_val: Variant = s3.get("name")
					if sn3_val != null:
						var sn3 := str(sn3_val)
						if sn3 != "" and sn3 != "null":
							return sn3
				# If recipient is actually a settlement id, resolve directly.
				var sn_sett := _get_settlement_name_by_any_id(rvid_str)
				if sn_sett != "":
					if _debug_convoy_menu:
						print("[ConvoyMenu][Debug] dest via recipient settlement id=", sn_sett)
					return sn_sett
				# Shared resolver used by VendorTradePanel/VendorCargoAggregator.
				var vn3 := ""
				if VendorPanelContextController != null:
					vn3 = str(VendorPanelContextController.get_vendor_name_for_recipient(self, rvid_str))
				if vn3 != "" and vn3 != "null" and vn3 != "Unknown Vendor":
					if _debug_convoy_menu:
						print("[ConvoyMenu][Debug] dest via recipient vendor name (shared)=", vn3)
					return vn3

	# 3) Destination dictionary object
	var dest_any: Variant = item.get("destination", null)
	if dest_any is Dictionary:
		var dd: Dictionary = dest_any
		# Try name first
		var n_val = dd.get("name")
		if n_val != null:
			var n := str(n_val)
			if n != "" and n != "null":
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] dest via destination.name=", n)
				return n
		# Try nested vendor -> settlement mapping
		var nested_vid_val = dd.get("vendor_id", dd.get("recipient_vendor_id"))
		if nested_vid_val != null:
			var nested_vid := str(nested_vid_val)
			if nested_vid != "" and nested_vid != "null":
				var s2 = _get_settlement_for_vendor_id(nested_vid)
				if s2 is Dictionary:
					var sn2_val = (s2 as Dictionary).get("name")
					if sn2_val != null:
						var sn2 := str(sn2_val)
						if sn2 != "" and sn2 != "null":
							if _debug_convoy_menu:
								print("[ConvoyMenu][Debug] dest via destination.vendor->settlement=", sn2)
							return sn2
		var coords := _extract_coords_from_dict(dd)
		if coords != Vector2i.ZERO:
			var name_from_coords: String = _get_settlement_name_from_coords(coords.x, coords.y)
			if String(name_from_coords) != "" and not String(name_from_coords).begins_with("N/A"):
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] dest via destination coords -> name=", name_from_coords)
				return String(name_from_coords)
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] dest via destination coords=", coords)
			return "(%d, %d)" % [coords.x, coords.y]

	# 4) Raw coordinate fields on item
	var dx_val = item.get("dest_coord_x", null)
	var dy_val = item.get("dest_coord_y", null)
	if dx_val != null and dy_val != null:
		var dx := roundi(float(dx_val))
		var dy := roundi(float(dy_val))
		var name_from_coords2: String = _get_settlement_name_from_coords(dx, dy)
		if String(name_from_coords2) != "" and not String(name_from_coords2).begins_with("N/A"):
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] dest via raw coord fields -> name=", name_from_coords2)
			return String(name_from_coords2)
		var coord_str := "(%d, %d)" % [dx, dy]
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] dest via raw coord fields=", coord_str)
		return coord_str

	# LAST RESORT: mission_vendor_id may refer to origin vendor; use only if absolutely nothing else available
	if item.has("mission_vendor_id"):
		var mvid_val2 = item.get("mission_vendor_id")
		if mvid_val2 != null:
			var mvid2 := str(mvid_val2)
			if mvid2 != "" and mvid2 != "null":
				var sm2 = _get_settlement_for_vendor_id(mvid2)
				if sm2 is Dictionary:
						var smn2_val = (sm2 as Dictionary).get("name")
						if smn2_val != null:
							var smn2 := str(smn2_val)
							if smn2 != "" and smn2 != "null":
								if _debug_convoy_menu:
									print("[ConvoyMenu][Debug] dest via mission_vendor_id (fallback)=", smn2)
								return smn2
				var vv2_name := ""
				if VendorPanelContextController != null:
					vv2_name = str(VendorPanelContextController.get_vendor_name_for_recipient(self, mvid2))
				if vv2_name != "" and vv2_name != "null" and vv2_name != "Unknown Vendor":
					if _debug_convoy_menu:
						print("[ConvoyMenu][Debug] dest via mission_vendor_id vendor (shared fallback)=", vv2_name)
					return vv2_name

	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] destination unresolved for item=", String(item.get("name", item.get("base_name", "?"))))
	return ""
	
func _on_part_compat_ready(_payload: Dictionary) -> void:
	_queue_vendor_preview_update()

func _on_store_map_changed(_tiles: Array, settlements: Array) -> void:
	# Cache the latest settlements payload for local lookups
	if settlements is Array:
		_set_latest_settlements_snapshot(settlements)
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] cached settlements count=", _latest_all_settlements.size())
	_queue_vendor_preview_update()
	# Ensure mechanics preview is warmed up with the new settlement data
	if is_instance_valid(_mechanics_service) and _mechanics_service.has_method("warm_mechanics_data_for_convoy"):
		_mechanics_service.warm_mechanics_data_for_convoy(convoy_data_received)

func _on_initial_data_ready() -> void:
	# When initial data comes online (map + convoys), try to sync settlements
	if is_instance_valid(_store) and _store.has_method("get_settlements"):
		var arr = _store.get_settlements()
		if arr is Array:
			_set_latest_settlements_snapshot(arr)
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] initial_data_ready -> synced settlements count=", _latest_all_settlements.size())
	_queue_vendor_preview_update()
	# Ensure mechanics preview is warmed up with the initial settlement data
	if is_instance_valid(_mechanics_service) and _mechanics_service.has_method("warm_mechanics_data_for_convoy"):
		_mechanics_service.warm_mechanics_data_for_convoy(convoy_data_received)

func _on_vendor_preview_ready(vendor_any: Variant) -> void:
	# This signal is used as a general "vendor preview changed" notifier across the app.
	# Most emitters send a vendor Dictionary, but some older code paths may emit non-dicts.
	# Always refresh the preview (debounced) so Compatible Parts can populate early.
	if not (vendor_any is Dictionary):
		_queue_vendor_preview_update()
		return
	var vendor: Dictionary = vendor_any
	if vendor.is_empty():
		_queue_vendor_preview_update()
		return

	# Vendor updated via VendorService; cache it and refresh destinations if needed.
	var vendor_id := String(vendor.get("vendor_id", vendor.get("id", "")))
	if vendor_id != "":
		_vendors_by_id[vendor_id] = vendor
		_vendors_by_id_models[vendor_id] = VendorModel.new(vendor)
		var vendor_name := String(vendor.get("name", ""))
		if vendor_name != "":
			_vendor_id_to_name[vendor_id] = vendor_name

	var destinations_changed := false
	var cargo_inv: Array = vendor.get("cargo_inventory", [])
	if cargo_inv is Array and not cargo_inv.is_empty():
		for it in cargo_inv:
			if not (it is Dictionary):
				continue
			# Mission items in vendor inventory help us map destinations.
			var is_mission := false
			if ItemsData != null and ItemsData.MissionItem:
				is_mission = ItemsData.MissionItem._looks_like_mission_dict(it)
			if not is_mission:
				continue
			var nm := String((it as Dictionary).get("name", (it as Dictionary).get("base_name", "Item")))
			var dest := _extract_destination_from_item(it)
			var prev := String(_destinations_cache.get(nm, ""))
			if dest != "" and dest != prev:
				_destinations_cache[nm] = dest
				destinations_changed = true
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] vendor_preview_ready destinations_changed=", destinations_changed, " cache_size=", (_destinations_cache.size() if _destinations_cache is Dictionary else -1))

	# Always refresh on vendor updates so Available Parts/Missions can appear without visiting SettlementMenu.
	_queue_vendor_preview_update()


func _get_vendor_by_id(vendor_id: String) -> Dictionary:
	if vendor_id == "":
		return {}
	if _vendors_by_id.has(vendor_id) and (_vendors_by_id[vendor_id] is Dictionary):
		return _vendors_by_id[vendor_id]
	if _vendors_from_settlements_by_id.has(vendor_id) and (_vendors_from_settlements_by_id[vendor_id] is Dictionary):
		return _vendors_from_settlements_by_id[vendor_id]
	return {}


func _get_settlement_for_vendor_id(vendor_id: String) -> Dictionary:
	if vendor_id == "":
		return {}
	if _vendor_id_to_settlement.has(vendor_id) and (_vendor_id_to_settlement[vendor_id] is Dictionary):
		return _vendor_id_to_settlement[vendor_id]
	return {}


func _get_settlement_name_from_coords(x: int, y: int) -> String:
	# Prefer the tile snapshot for 1:1 lookup if available; otherwise fall back to settlement list.
	var tiles: Array = []
	if is_instance_valid(_store) and _store.has_method("get_tiles"):
		tiles = _store.get_tiles()
	if not tiles.is_empty() and y >= 0 and y < tiles.size():
		var row_array: Array = tiles[y]
		if x >= 0 and x < row_array.size():
			var tile_data: Dictionary = row_array[x]
			var settlements_array: Array = tile_data.get("settlements", [])
			if not settlements_array.is_empty():
				var first_settlement: Dictionary = settlements_array[0]
				if first_settlement.has("name"):
					return String(first_settlement.get("name"))
				return "N/A (Settlement Name Missing)"
			return "N/A (No Settlements at Coords)"
		return "N/A (X Out of Bounds)"
	return "N/A (Y Out of Bounds)"


func _get_settlement_name_by_any_id(id_any: Variant) -> String:
	var id_str := str(id_any)
	if id_str == "" or id_str == "null":
		return ""
	for s_any in _latest_all_settlements:
		if not (s_any is Dictionary):
			continue
		var s: Dictionary = s_any
		var sid := str(s.get("sett_id", s.get("settlement_id", s.get("id", ""))))
		if sid != "" and sid == id_str:
			var nm := str(s.get("name", ""))
			if nm != "" and nm != "null":
				return nm
	return ""

func _on_vendor_tab_pressed(tab_index: VendorTab) -> void:
	_current_vendor_tab = tab_index
	_render_vendor_preview_display()

# --- Placeholder Button Handlers ---
func _on_vehicle_menu_button_pressed():
	print("ConvoyMenu: Vehicle Menu button pressed. Emitting 'open_vehicle_menu_requested'.")
	emit_signal("open_vehicle_menu_requested", convoy_data_received)

func _on_journey_menu_button_pressed():
	print("ConvoyMenu: Journey Menu button pressed. Emitting 'open_journey_menu_requested'.")
	emit_signal("open_journey_menu_requested", convoy_data_received)

func _on_settlement_menu_button_pressed():
	print("ConvoyMenu: Settlement Menu button pressed. Emitting 'open_settlement_menu_requested'.")
	emit_signal("open_settlement_menu_requested", convoy_data_received)

func _on_cargo_menu_button_pressed():
	print("ConvoyMenu: Cargo Menu button pressed. Emitting 'open_cargo_menu_requested'.")
	emit_signal("open_cargo_menu_requested", convoy_data_received)


func _get_color_for_percentage(percentage: float) -> Color:
	if percentage > 0.7:
		return COLOR_GREEN
	elif percentage > 0.3:
		return COLOR_YELLOW
	else:
		return COLOR_RED

func _get_color_for_capacity(percentage: float) -> Color:
	if percentage > 0.95:
		return COLOR_RED
	elif percentage > 0.75:
		return COLOR_YELLOW
	else:
		return COLOR_GREEN

func _set_resource_bar_style(bar_node: ProgressBar, label_node: Label, current_value: float, max_value: float):
	if not is_instance_valid(bar_node) or not is_instance_valid(label_node):
		return

	var percentage: float = 0.0
	if max_value > 0:
		percentage = clamp(current_value / max_value, 0.0, 1.0)
		bar_node.value = percentage * 100.0
	else:
		bar_node.value = 0.0

	var fill_color := _get_color_for_percentage(percentage)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.border_width_left = 1
	fill_style.border_width_right = 1
	fill_style.border_width_top = 1
	fill_style.border_width_bottom = 1
	fill_style.border_color = fill_color.darkened(0.2)
	bar_node.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("2a2a2a") # Opaque dark grey
	# Add a border to help it stand out from the menu background
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = bg_style.bg_color.lightened(0.4) # Match performance box border
	bg_style.shadow_color = Color(0, 0, 0, 0.4)
	bg_style.shadow_size = 2
	bg_style.shadow_offset = Vector2(0, 2)
	bar_node.add_theme_stylebox_override("background", bg_style)

	# Use a contrasting font color for the label on top of the bar and add a shadow for readability
	label_node.add_theme_color_override("font_color", Color.WHITE)
	label_node.add_theme_constant_override("shadow_outline_size", 1)
	label_node.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))

func _set_fixed_color_box_style(panel_node: PanelContainer, label_node: Label, p_bg_color: Color, p_font_color: Color):
	if not is_instance_valid(panel_node) or not is_instance_valid(label_node):
		return

	var style_box = StyleBoxFlat.new()
	style_box.bg_color = p_bg_color
	style_box.content_margin_left = 8
	style_box.content_margin_right = 8
	# Add a border and shadow to make the panel pop
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.border_color = p_bg_color.lightened(0.4)
	style_box.shadow_color = Color(0, 0, 0, 0.4)
	style_box.shadow_size = 2
	style_box.shadow_offset = Vector2(0, 2)
	panel_node.add_theme_stylebox_override("panel", style_box)
	label_node.add_theme_color_override("font_color", p_font_color)
	
	# Center text
	label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _set_progressbar_style(progressbar_node: ProgressBar, current_value: float, max_value: float):
	if not is_instance_valid(progressbar_node):
		return
	
	var percentage: float = 0.0
	if max_value > 0:
		percentage = clamp(current_value / max_value, 0.0, 1.0)
		progressbar_node.value = percentage * 100.0
	else:
		progressbar_node.value = 0.0

	var fill_color := _get_color_for_capacity(percentage)
	var fill_style_box = StyleBoxFlat.new()
	fill_style_box.bg_color = fill_color
	fill_style_box.border_width_left = 1
	fill_style_box.border_width_right = 1
	fill_style_box.border_width_top = 1
	fill_style_box.border_width_bottom = 1
	fill_style_box.border_color = fill_color.darkened(0.2)
	progressbar_node.add_theme_stylebox_override("fill", fill_style_box)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("2a2a2a") # Opaque dark grey
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = bg_style.bg_color.lightened(0.4) # Match performance box border
	bg_style.shadow_color = Color(0, 0, 0, 0.4)
	bg_style.shadow_size = 2
	bg_style.shadow_offset = Vector2(0, 2)
	progressbar_node.add_theme_stylebox_override("background", bg_style)

	# Ensure in-bar percentage text is visible and readable
	progressbar_node.show_percentage = true
	progressbar_node.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	progressbar_node.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	progressbar_node.add_theme_constant_override("outline_size", 2)

func _update_font_sizes() -> void:
	if REFERENCE_MENU_HEIGHT <= 0:
		printerr("ConvoyMenu: REFERENCE_MENU_HEIGHT is not positive. Cannot scale fonts.")
		return

	var current_menu_height: float = self.size.y
	if current_menu_height <= 0: # Menu might not have a size yet if called too early
		return

	var scale_factor: float = current_menu_height / REFERENCE_MENU_HEIGHT

	var new_font_size: int = clamp(int(BASE_FONT_SIZE * scale_factor), MIN_FONT_SIZE, MAX_FONT_SIZE)
	var new_title_font_size: int = clamp(int(BASE_TITLE_FONT_SIZE * scale_factor), MIN_FONT_SIZE, MAX_TITLE_FONT_SIZE)

	var labels_to_scale: Array[Label] = [
		fuel_text_label, water_text_label, food_text_label,
		speed_text_label, offroad_text_label, efficiency_text_label,
		cargo_volume_text_label, cargo_weight_text_label,
		journey_dest_label, journey_progress_label, journey_eta_label,
		vehicles_label, all_cargo_label, vendor_no_items_label,
		# Add text of placeholder buttons if they need scaling
		# vehicle_menu_button, journey_menu_button, 
		# settlement_menu_button, cargo_menu_button 
	]
	# title_label is handled separately as it's the main convoy name title

	if is_instance_valid(title_label):
		title_label.add_theme_font_size_override("font_size", new_title_font_size)

	if is_instance_valid(preview_title_label):
		preview_title_label.add_theme_font_size_override("font_size", new_font_size + 2)

	# Scale fonts for dynamically created vendor item buttons
	if is_instance_valid(vendor_item_grid):
		for child in vendor_item_grid.get_children():
			if child is Button:
				# Increase font for mission/parts item buttons to improve readability
				child.add_theme_font_size_override("font_size", new_font_size + 2)
				
	for label_node in labels_to_scale:
		if is_instance_valid(label_node):
			label_node.add_theme_font_size_override("font_size", new_font_size)

	if is_instance_valid(back_button):
		back_button.add_theme_font_size_override("font_size", new_font_size)
	
	# Scale placeholder button fonts if they are valid
	if is_instance_valid(vehicle_menu_button):
		vehicle_menu_button.add_theme_font_size_override("font_size", new_font_size)
	if is_instance_valid(journey_menu_button):
		journey_menu_button.add_theme_font_size_override("font_size", new_font_size)
	if is_instance_valid(settlement_menu_button):
		settlement_menu_button.add_theme_font_size_override("font_size", new_font_size)
	if is_instance_valid(cargo_menu_button):
		cargo_menu_button.add_theme_font_size_override("font_size", new_font_size)
	
	# Scale vendor tab buttons
	if is_instance_valid(convoy_missions_tab_button):
		convoy_missions_tab_button.add_theme_font_size_override("font_size", new_font_size - 2)
	if is_instance_valid(settlement_missions_tab_button):
		settlement_missions_tab_button.add_theme_font_size_override("font_size", new_font_size - 2)
	if is_instance_valid(compatible_parts_tab_button):
		compatible_parts_tab_button.add_theme_font_size_override("font_size", new_font_size - 2)
	if is_instance_valid(journey_tab_button):
		journey_tab_button.add_theme_font_size_override("font_size", new_font_size - 2)

	# print("ConvoyMenu: Updated font sizes. Scale: %.2f, Base: %d, Title: %d" % [scale_factor, new_font_size, new_title_font_size]) # DEBUG


func _style_menu_button(button_node: Button) -> void:
	if not is_instance_valid(button_node):
		return

	# Consistent min height already set in scene; enforce if loaded dynamically
	if button_node.custom_minimum_size.y < 30.0:
		button_node.custom_minimum_size = Vector2(button_node.custom_minimum_size.x, 34.0)

	var style_box_normal := StyleBoxFlat.new()
	style_box_normal.bg_color = COLOR_MENU_BUTTON_GREY_BG
	style_box_normal.corner_radius_top_left = 4
	style_box_normal.corner_radius_top_right = 4
	style_box_normal.corner_radius_bottom_left = 4
	style_box_normal.corner_radius_bottom_right = 4
	style_box_normal.border_width_left = 1
	style_box_normal.border_width_right = 1
	style_box_normal.border_width_top = 1
	style_box_normal.border_width_bottom = 1
	style_box_normal.border_color = COLOR_BOX_FONT.darkened(0.2)
	style_box_normal.shadow_size = 4
	style_box_normal.shadow_color = Color(0, 0, 0, 0.4)

	var style_box_hover := style_box_normal.duplicate()
	style_box_hover.bg_color = COLOR_MENU_BUTTON_GREY_BG.lightened(0.1)

	var style_box_pressed := style_box_normal.duplicate()
	style_box_pressed.bg_color = COLOR_MENU_BUTTON_GREY_BG.darkened(0.15)
	style_box_pressed.shadow_size = 2
	style_box_pressed.shadow_color = Color(0, 0, 0, 0.25)

	button_node.add_theme_stylebox_override("normal", style_box_normal)
	button_node.add_theme_stylebox_override("hover", style_box_hover)
	button_node.add_theme_stylebox_override("pressed", style_box_pressed)
	button_node.add_theme_color_override("font_color", COLOR_BOX_FONT)

func _initialize_tab_button_styles(button: Button) -> void:
	if not is_instance_valid(button):
		return

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = COLOR_TAB_INACTIVE_BG
	style_normal.corner_radius_top_left = 3
	style_normal.corner_radius_top_right = 3

	var style_hover := style_normal.duplicate() as StyleBoxFlat
	style_hover.bg_color = COLOR_TAB_INACTIVE_BG.lightened(0.15)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = COLOR_TAB_ACTIVE_BG # This is the "active" color
	style_pressed.corner_radius_top_left = 3
	style_pressed.corner_radius_top_right = 3

	var style_disabled := style_normal.duplicate() as StyleBoxFlat
	style_disabled.bg_color = COLOR_TAB_INACTIVE_BG.darkened(0.3)

	button.add_theme_color_override("font_disabled_color", COLOR_TAB_DISABLED_FONT)
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("disabled", style_disabled)

func _style_vendor_item_button(button: Button, tab_type: VendorTab) -> void:
	var font_color: Color
	match tab_type:
		VendorTab.CONVOY_MISSIONS, VendorTab.SETTLEMENT_MISSIONS:
			font_color = COLOR_MISSION_TEXT
		VendorTab.COMPATIBLE_PARTS:
			font_color = COLOR_PART_TEXT
		_:
			font_color = Color.WHITE

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = COLOR_ITEM_BUTTON_BG
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_color = COLOR_ITEM_BUTTON_BG.darkened(0.4)
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4

	var style_hover := style_normal.duplicate() as StyleBoxFlat
	style_hover.bg_color = COLOR_ITEM_BUTTON_BG.lightened(0.2)
	style_hover.border_color = style_hover.bg_color.darkened(0.4)

	var style_pressed := style_normal.duplicate() as StyleBoxFlat
	style_pressed.bg_color = COLOR_ITEM_BUTTON_BG.darkened(0.2)
	style_pressed.content_margin_top = 2 # Add a little press-down effect

	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color.lightened(0.1))
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)

func _style_journey_progress_bar(bar: ProgressBar) -> void:
	if not is_instance_valid(bar):
		return

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("2a2a2a") # Opaque dark grey
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = bg_style.bg_color.lightened(0.4) # Match performance box border
	bg_style.shadow_color = Color(0, 0, 0, 0.4)
	bg_style.shadow_size = 2
	bg_style.shadow_offset = Vector2(0, 2)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COLOR_JOURNEY_PROGRESS_FILL
	fill_style.border_width_left = 1
	fill_style.border_width_right = 1
	fill_style.border_width_top = 1
	fill_style.border_width_bottom = 1
	fill_style.border_color = COLOR_JOURNEY_PROGRESS_FILL.darkened(0.2)

	bar.add_theme_stylebox_override("background", bg_style)
	bar.add_theme_stylebox_override("fill", fill_style)

# The _update_label function is no longer needed with this simplified structure.
# You can remove it or comment it out.
# func _update_label(node_path: String, text_content: Variant):
# 	...

func _update_ui(convoy: Dictionary) -> void:
	var incoming: Dictionary = convoy.duplicate(true)
	var incoming_id := String(incoming.get("convoy_id", incoming.get("id", "")))
	if incoming_id == "":
		incoming_id = convoy_id
	var same_id := (incoming_id != "" and convoy_id != "" and incoming_id == convoy_id)
	var incoming_complete := _is_convoy_payload_complete(incoming)
	var current_complete := _is_convoy_payload_complete(convoy_data_received)

	# If we already have a complete snapshot, ignore later incomplete snapshots for the same convoy.
	if same_id and current_complete and not incoming_complete:
		_ensure_full_convoy_loaded(convoy_id, incoming)
		return

	# Accept update and track id.
	convoy_data_received = incoming
	if incoming_id != "":
		convoy_id = incoming_id

	# If we received a shallow snapshot, request full details once and avoid rendering misleading 0/0.
	if not incoming_complete:
		_ensure_full_convoy_loaded(convoy_id, convoy_data_received)
		if is_instance_valid(title_label):
			title_label.text = String(convoy_data_received.get("convoy_name", convoy_data_received.get("name", title_label.text)))
		if is_instance_valid(cargo_volume_text_label):
			cargo_volume_text_label.text = "Cargo Volume: loading…"
		if is_instance_valid(cargo_weight_text_label):
			cargo_weight_text_label.text = "Cargo Weight: loading…"
		return

	# Title
	if is_instance_valid(title_label):
		title_label.text = String(convoy_data_received.get("convoy_name", convoy_data_received.get("name", title_label.text)))

	# Resources (prefer max_*; fall back to capacity keys if present)
	var current_fuel: float = float(convoy_data_received.get("fuel", 0.0))
	var max_fuel: float = float(convoy_data_received.get("max_fuel", convoy_data_received.get("fuel_capacity", 0.0)))
	if is_instance_valid(fuel_text_label): fuel_text_label.text = "Fuel: %s / %s" % [NumberFormat.fmt_float(current_fuel, 2), NumberFormat.fmt_float(max_fuel, 2)]
	if is_instance_valid(fuel_bar): _set_resource_bar_style(fuel_bar, fuel_text_label, current_fuel, max_fuel)

	var current_water: float = float(convoy_data_received.get("water", 0.0))
	var max_water: float = float(convoy_data_received.get("max_water", convoy_data_received.get("water_capacity", 0.0)))
	if is_instance_valid(water_text_label): water_text_label.text = "Water: %s / %s" % [NumberFormat.fmt_float(current_water, 2), NumberFormat.fmt_float(max_water, 2)]
	if is_instance_valid(water_bar): _set_resource_bar_style(water_bar, water_text_label, current_water, max_water)

	var current_food: float = float(convoy_data_received.get("food", 0.0))
	var max_food: float = float(convoy_data_received.get("max_food", convoy_data_received.get("food_capacity", 0.0)))
	if is_instance_valid(food_text_label): food_text_label.text = "Food: %s / %s" % [NumberFormat.fmt_float(current_food, 2), NumberFormat.fmt_float(max_food, 2)]
	if is_instance_valid(food_bar): _set_resource_bar_style(food_bar, food_text_label, current_food, max_food)

	# Performance
	var top_speed: float = float(convoy_data_received.get("top_speed", 0.0))
	if is_instance_valid(speed_text_label): speed_text_label.text = "Top Speed: %s" % NumberFormat.fmt_float(top_speed, 2)
	if is_instance_valid(speed_box): _set_fixed_color_box_style(speed_box, speed_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)
	var offroad: float = float(convoy_data_received.get("offroad_capability", 0.0))
	if is_instance_valid(offroad_text_label): offroad_text_label.text = "Offroad: %s" % NumberFormat.fmt_float(offroad, 2)
	if is_instance_valid(offroad_box): _set_fixed_color_box_style(offroad_box, offroad_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)
	var efficiency: float = float(convoy_data_received.get("efficiency", 0.0))
	if is_instance_valid(efficiency_text_label): efficiency_text_label.text = "Efficiency: %s" % NumberFormat.fmt_float(efficiency, 2)
	if is_instance_valid(efficiency_box): _set_fixed_color_box_style(efficiency_box, efficiency_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

	# Cargo (support both schema shapes)
	var used_volume: float = 0.0
	var total_volume: float = 0.0
	if convoy_data_received.has("total_cargo_capacity"):
		total_volume = float(convoy_data_received.get("total_cargo_capacity", 0.0))
		used_volume = total_volume - float(convoy_data_received.get("total_free_space", 0.0))
	else:
		used_volume = float(convoy_data_received.get("cargo_volume", 0.0))
		total_volume = float(convoy_data_received.get("max_cargo_volume", 0.0))
	if is_instance_valid(cargo_volume_text_label):
		cargo_volume_text_label.text = "Cargo Volume: %s / %s" % [NumberFormat.fmt_float(used_volume, 2), NumberFormat.fmt_float(total_volume, 2)]
	if is_instance_valid(cargo_volume_bar):
		_set_progressbar_style(cargo_volume_bar, used_volume, total_volume)

	var used_weight: float = 0.0
	var total_weight: float = 0.0
	if convoy_data_received.has("total_weight_capacity"):
		total_weight = float(convoy_data_received.get("total_weight_capacity", 0.0))
		used_weight = total_weight - float(convoy_data_received.get("total_remaining_capacity", 0.0))
	else:
		used_weight = float(convoy_data_received.get("cargo_weight", 0.0))
		total_weight = float(convoy_data_received.get("max_cargo_weight", 0.0))
	if is_instance_valid(cargo_weight_text_label):
		cargo_weight_text_label.text = "Cargo Weight: %s / %s" % [NumberFormat.fmt_float(used_weight, 2), NumberFormat.fmt_float(total_weight, 2)]
	if is_instance_valid(cargo_weight_bar):
		_set_progressbar_style(cargo_weight_bar, used_weight, total_weight)
