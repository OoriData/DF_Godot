extends MenuBase # Standardized menu base for store-driven updates

# Optional: If your menu needs to display data passed from MenuManager
var convoy_data_received: Dictionary

# Classification helpers from centralized item data
const ItemsData = preload("res://Scripts/Data/Items.gd")

const SettlementModel = preload("res://Scripts/Data/Models/Settlement.gd")
const VendorModel = preload("res://Scripts/Data/Models/Vendor.gd")
const VendorPanelContextController = preload("res://Scripts/Menus/VendorPanel/vendor_panel_context_controller.gd")
const TopUpPlanner = preload("res://Scripts/Menus/VendorPanel/top_up_planner.gd")

# --- Font Scaling Parameters ---
const BASE_FONT_SIZE: float = 18.0  # Increased from 14.0
const BASE_TITLE_FONT_SIZE: float = 22.0 # Increased from 18.0
const REFERENCE_MENU_HEIGHT: float = 600.0 # The menu height at which BASE_FONT_SIZE looks best
const MIN_FONT_SIZE: float = 8.0
const MAX_FONT_SIZE: float = 24.0
const MAX_TITLE_FONT_SIZE: float = 30.0

# --- Color Constants for Styling ---
const COLOR_GREEN: Color = Color("66bb6a") # Material Green 400
const COLOR_YELLOW: Color = Color("ffee58") # Material Yellow 400
const COLOR_RED: Color = Color("ef5350")   # Material Red 400
const COLOR_BOX_FONT: Color = Color("000000") # Black font for boxes for contrast
const COLOR_PERFORMANCE_BOX_BG: Color = Color("404040cc") # Dark Gray, 80% opaque
const COLOR_PERFORMANCE_BOX_FONT: Color = Color.WHITE   # White

# --- Vendor Preview Tab Constants ---
enum VendorTab { CONVOY_MISSIONS, SETTLEMENT_MISSIONS, COMPATIBLE_PARTS, JOURNEY }
const COLOR_TAB_ACTIVE_BG: Color = Color("424242") # Grey 800
const COLOR_TAB_INACTIVE_BG: Color = Color("757575") # Grey 600
const COLOR_TAB_CONTENT_BG: Color = Color("303030") # Grey 850
const COLOR_MISSION_TEXT: Color = Color("ffd700") # Gold
const COLOR_PART_TEXT: Color = Color("4dd0e1") # Material Cyan 300
const COLOR_BULLET_POINT: Color = Color("9e9e9e") # Grey 500
const COLOR_TAB_DISABLED_FONT: Color = Color("a0a0a0") # Lighter gray for disabled text
const COLOR_ITEM_BUTTON_BG: Color = Color("5a5a5a") # Dark-medium gray for item buttons
# Journey progress fill: UITheme.ACCENT_VERDIGRIS (living/growth/resource signal).
# Token is an autoload const (not a compile-time constant expr), so used inline below, not here.

# --- Vendor Item Button Layout ---
var VENDOR_ITEM_BUTTON_MIN_WIDTH: float = 190.0
var VENDOR_ITEM_BUTTON_HEIGHT: float = 72.0
const VENDOR_ITEM_BUTTON_PADDING_X: float = 16.0
const VENDOR_ITEM_BUTTON_TOP_PADDING: float = 6.0
const VENDOR_ITEM_BUTTON_BOTTOM_CLEARANCE: float = 6.0

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
@onready var cargo_volume_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/CargoBarsHBox/CargoVolumeContainer/CargoVolumeTextLabel
@onready var cargo_volume_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/CargoBarsHBox/CargoVolumeContainer/CargoVolumeBar
@onready var cargo_weight_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/CargoBarsHBox/CargoWeightContainer/CargoWeightTextLabel
@onready var cargo_weight_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/CargoBarsHBox/CargoWeightContainer/CargoWeightBar

@onready var scroll_container: ScrollContainer = $MainVBox/ScrollContainer
@onready var content_vbox: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox

# Stat section containers — captured at _ready (original paths) so references
# survive the runtime reparent into the two-column split layout.
@onready var _res_stats_hbox: BoxContainer = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox
@onready var _perf_stats_hbox: BoxContainer = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox
@onready var _cargo_bars_hbox: BoxContainer = $MainVBox/ScrollContainer/ContentVBox/CargoBarsHBox
@onready var _vendor_preview_panel_node: PanelContainer = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel

# Two-column split (built at runtime in _setup_two_column_layout)
var _main_split: BoxContainer = null
var _stats_column: VBoxContainer = null
var _content_column: VBoxContainer = null

# Portrait summary strip (built at runtime) — compact stat chips that replace the full
# stats column on the cramped portrait bottom sheet.
var _portrait_summary_panel: PanelContainer = null
var _portrait_summary_flow: HFlowContainer = null

@onready var vehicles_label: Label = get_node_or_null("MainVBox/ScrollContainer/ContentVBox/VehiclesLabel")
# Optional: AllCargoLabel may not exist in the scene variant.
var all_cargo_label: Label = null
@onready var back_button: Button = $MainVBox/TopBarHBox/BackButton

# --- Vendor Preview Nodes ---
@onready var preview_title_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/PreviewTitleLabel
@onready var convoy_missions_tab_button: Button = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorTabsHBox/ConvoyMissionsTabButton
@onready var settlement_missions_tab_button: Button = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorTabsHBox/SettlementMissionsTabButton
@onready var compatible_parts_tab_button: Button = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorTabsHBox/CompatiblePartsTabButton
@onready var journey_tab_button: Button = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorTabsHBox/JourneyTabButton
@onready var vendor_item_grid: GridContainer = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/VendorItemContainer/VendorItemGrid
@onready var vendor_item_container: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/VendorItemContainer
@onready var vendor_no_items_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/VendorNoItemsLabel
@onready var journey_info_vbox: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox
@onready var journey_dest_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox/JourneyDestLabel
@onready var journey_progress_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox/JourneyProgressControl/JourneyProgressBar
@onready var journey_progress_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox/JourneyProgressControl/JourneyProgressLabel
@onready var journey_eta_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/VendorContentPanel/VendorContentScroll/ContentWrapper/JourneyInfoVBox/JourneyETALabel


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
@onready var _user_service: Node = get_node_or_null("/root/UserService")
var _debug_convoy_menu: bool = true # toggle verbose diagnostics for this menu

# Top Up (Sprint 5): relocated here from the settlement menu. Replenishes Fuel/Water/Food from the
# vendors of the settlement the convoy currently sits in (cheapest-first leveling via TopUpPlanner).
# The button is hidden unless the convoy is parked in a settlement that actually sells resources.
var _top_up_button: Button = null
var _top_up_plan: Dictionary = {"total_cost": 0.0, "allocations": [], "resources": {}, "planned_list": []}

# ConvoyMenu should always render from a *full* convoy snapshot. Some signal paths provide
# a shallow convoy dict (missing capacities/resources), which can temporarily render 0/0.
# We request full details once per open and ignore incomplete updates after we have complete.
var _requested_full_convoy_id: String = ""

# --- Vendor Preview State ---
var _current_vendor_tab: VendorTab = VendorTab.CONVOY_MISSIONS
var _convoy_mission_items: Array[String] = []
var _settlement_mission_items: Array[String] = []
var _compatible_part_items: Array[String] = []
var _convoy_mission_meta: Array[Dictionary] = []
var _settlement_mission_meta: Array[Dictionary] = []
var _compatible_part_meta: Array[Dictionary] = []
var _latest_all_settlements: Array = []
var _latest_all_settlement_models: Array = [] # Array[Settlement]
var _vendors_by_id: Dictionary = {} # vendor_id -> vendor Dictionary (from VendorService/Hub)
var _vendors_by_id_models: Dictionary = {} # vendor_id -> Vendor
var _vendors_from_settlements_by_id: Dictionary = {} # vendor_id -> vendor Dictionary (from map snapshot)
var _vendor_id_to_settlement: Dictionary = {} # vendor_id -> settlement Dictionary (from map snapshot)
var _vendor_id_to_name: Dictionary = {} # vendor_id -> vendor name String (from map snapshot + vendor previews)
var _vendor_preview_update_timer: Timer = null # For debouncing updates
var _vendor_preview_update_pending: bool = false
var _cargo_sort_metric: int = 0
var _mission_sort_container: HBoxContainer = null
var _mission_sort_option_button: OptionButton = null
var _destinations_cache: Dictionary = {} # item_name -> recipient_settlement_name (or destination string)

# Avoid spamming vendor detail requests when Available Missions refreshes.
var _requested_vendor_details: Dictionary = {} # vendor_id -> true

# For deep-linking Active Missions -> Cargo menu, preserve at least one representative cargo_id per mission item name.
var _active_mission_cargo_id_by_name: Dictionary = {} # item_name -> cargo_id
var _active_mission_cargo_id_by_display: Dictionary = {} # "name — to DEST" -> cargo_id

func _get_settings_manager() -> Node:
	return get_node_or_null("/root/SettingsManager")

func _is_portrait_view() -> bool:
	if not is_inside_tree(): return false
	var win_size = get_viewport_rect().size
	return win_size.y > win_size.x

func _is_mobile() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.get_name() in ["Android", "iOS"]:
		return true
	if is_inside_tree():
		var win_size = get_viewport_rect().size
		# Catch short landscape screens or portrait
		if win_size.y > win_size.x or win_size.y < 500:
			return true
	return false

func _load_cargo_sort_metric_from_settings() -> void:
	var sm := _get_settings_manager()
	if is_instance_valid(sm) and sm.has_method("get_value"):
		_cargo_sort_metric = int(sm.get_value("ui.cargo_sort_metric", 0))

func _save_cargo_sort_metric_to_settings(metric: int) -> void:
	var sm := _get_settings_manager()
	if is_instance_valid(sm) and sm.has_method("set_and_save"):
		sm.set_and_save("ui.cargo_sort_metric", metric)



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
		return
	if not is_instance_valid(_convoy_service) or not _convoy_service.has_method("refresh_single"):
		return
	_requested_full_convoy_id = target_id
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] Requesting full convoy snapshot for convoy_id=", target_id)
	_convoy_service.refresh_single(target_id)


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
	super._ready()
	# Ensure we don't force a minimum width that breaks the parent container
	custom_minimum_size.x = 0
	if has_node("MainVBox"):
		$MainVBox.custom_minimum_size.x = 0
		$MainVBox.clip_contents = true
		if has_node("MainVBox/ScrollContainer"):
			$MainVBox/ScrollContainer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			$MainVBox/ScrollContainer.custom_minimum_size.x = 0
	
	_update_mobile_dependent_layout()
	call_deferred("_enforce_label_wrapping", self)

	# Resolve optional nodes that might be missing depending on scene variant
	all_cargo_label = get_node_or_null("MainVBox/ScrollContainer/ContentVBox/AllCargoLabel")
	if all_cargo_label == null:
		if _debug_convoy_menu:
			printerr("[ConvoyMenu] Optional AllCargoLabel not found at path MainVBox/ScrollContainer/ContentVBox/AllCargoLabel")
	# --- Banner Setup ---
	if is_instance_valid(title_label):
		setup_convoy_top_banner(title_label, "", false, true)
		_upgrade_stat_boxes()
		_setup_two_column_layout()
		_add_section_headers()
		_update_mobile_dependent_layout()
	else:
		printerr("ConvoyMenu: CRITICAL - TitleLabel node not found. Check the path in the script.")

	_setup_top_up_button()


	# --- Layout Tuning: GridContainer Separation ---
	if is_instance_valid(vendor_item_grid):
		var sep_h = 12 if _is_mobile() else 8
		var sep_v = 16 if _is_mobile() else 10
		vendor_item_grid.add_theme_constant_override("h_separation", sep_h)
		vendor_item_grid.add_theme_constant_override("v_separation", sep_v)


	var preview_vbox = _vendor_preview_panel_node.get_node_or_null("VendorPreviewVBox") if is_instance_valid(_vendor_preview_panel_node) else null
	if is_instance_valid(preview_vbox):
		var sort_dropdown_container := preview_vbox.get_node_or_null("SortDropdownContainer") as HBoxContainer
		if not is_instance_valid(sort_dropdown_container):
			sort_dropdown_container = HBoxContainer.new()
			sort_dropdown_container.name = "SortDropdownContainer"
			sort_dropdown_container.alignment = BoxContainer.ALIGNMENT_END
			sort_dropdown_container.visible = false

		var sort_option := sort_dropdown_container.get_node_or_null("MissionSortOptionButton") as OptionButton
		if not is_instance_valid(sort_option):
			sort_option = OptionButton.new()
			sort_option.name = "MissionSortOptionButton"
			sort_dropdown_container.add_child(sort_option)

		# Make sort control stand out against dark backgrounds.
		sort_dropdown_container.add_theme_constant_override("separation", 8)
		sort_option.custom_minimum_size = Vector2(300, 34)
		sort_option.add_theme_color_override("font_color", Color(0.93, 0.93, 0.93, 1.0))
		sort_option.add_theme_color_override("font_hover_color", Color(0.98, 0.98, 0.98, 1.0))
		var so_normal := StyleBoxFlat.new()
		so_normal.bg_color = Color(0.24, 0.24, 0.24, 0.96)
		so_normal.border_width_left = 1
		so_normal.border_width_right = 1
		so_normal.border_width_top = 1
		so_normal.border_width_bottom = 1
		so_normal.border_color = Color(0.56, 0.56, 0.56, 0.95)
		so_normal.corner_radius_top_left = 4
		so_normal.corner_radius_top_right = 4
		so_normal.corner_radius_bottom_left = 4
		so_normal.corner_radius_bottom_right = 4
		so_normal.content_margin_left = 10
		so_normal.content_margin_right = 10
		so_normal.content_margin_top = 4
		so_normal.content_margin_bottom = 4
		var so_hover := so_normal.duplicate()
		so_hover.bg_color = Color(0.31, 0.31, 0.31, 0.98)
		so_hover.border_color = Color(0.70, 0.70, 0.70, 1.0)
		var so_pressed := so_normal.duplicate()
		so_pressed.bg_color = Color(0.18, 0.18, 0.18, 1.0)
		sort_option.add_theme_stylebox_override("normal", so_normal)
		sort_option.add_theme_stylebox_override("hover", so_hover)
		sort_option.add_theme_stylebox_override("pressed", so_pressed)
		sort_option.add_theme_stylebox_override("focus", so_hover)

		_load_cargo_sort_metric_from_settings()

		sort_option.clear()
		sort_option.add_item("Sort: Profit Margin/Unit")
		sort_option.add_item("Sort: Profit Density/Weight")
		sort_option.add_item("Sort: Profit Density/Volume")
		sort_option.add_item("Sort: Total Order Profit")
		sort_option.add_item("Sort: Distance to Recipient")
		_cargo_sort_metric = clampi(_cargo_sort_metric, 0, max(0, sort_option.item_count - 1))
		sort_option.select(_cargo_sort_metric)
		if sort_option.item_selected.is_connected(_on_mission_sort_selected):
			sort_option.item_selected.disconnect(_on_mission_sort_selected)
		sort_option.item_selected.connect(_on_mission_sort_selected)
		_mission_sort_container = sort_dropdown_container
		_mission_sort_option_button = sort_option

		if sort_dropdown_container.get_parent() == null:
			# Insert below VendorTabsHBox
			var tabs_hbox = preview_vbox.get_node_or_null("VendorTabsHBox")
			if tabs_hbox:
				preview_vbox.add_child(sort_dropdown_container)
				preview_vbox.move_child(sort_dropdown_container, tabs_hbox.get_index() + 1)
	# Bottom bar styling is now handled by MenuManager

	# Style vendor preview panel if present
	var vendor_preview_panel := _vendor_preview_panel_node
	if is_instance_valid(vendor_preview_panel):
		var vp_style := StyleBoxFlat.new()
		vp_style.bg_color = UITheme.METAL_BASE
		vp_style.corner_radius_top_left = UITheme.RADIUS_MD
		vp_style.corner_radius_top_right = UITheme.RADIUS_MD
		vp_style.corner_radius_bottom_left = UITheme.RADIUS_MD
		vp_style.corner_radius_bottom_right = UITheme.RADIUS_MD
		vp_style.border_width_left = 1
		vp_style.border_width_right = 1
		vp_style.border_width_top = 1
		vp_style.border_width_bottom = 1
		vp_style.border_color = UITheme.METAL_EDGE
		vp_style.shadow_color = Color(0, 0, 0, 0.45)
		vp_style.shadow_size = 4
		vendor_preview_panel.add_theme_stylebox_override("panel", vp_style)
		# Style the content panel inside the vendor preview
		var content_panel = vendor_preview_panel.get_node_or_null("VendorPreviewVBox/VendorContentPanel")
		if is_instance_valid(content_panel):
			var content_style := StyleBoxFlat.new()
			content_style.bg_color = UITheme.METAL_DARK
			content_style.corner_radius_top_left = UITheme.RADIUS_SM
			content_style.corner_radius_bottom_right = UITheme.RADIUS_SM
			content_panel.add_theme_stylebox_override("panel", content_style)

	# Style the new journey progress bar
	if is_instance_valid(journey_progress_bar):
		_style_journey_progress_bar(journey_progress_bar)

	if is_instance_valid(back_button):
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT)
		if _is_mobile():
			back_button.custom_minimum_size = Vector2(back_button.custom_minimum_size.x, 60.0)
	else:
		printerr("ConvoyMenu: CRITICAL - BackButton node NOT found or is not a Button. Ensure it's named 'BackButton' in ConvoyMenu.tscn.")

	# Legacy BottomBarPanel removed (Sprint 5) — the StaticBottomNav in MenuManager is the only
	# navigation bar now. The node no longer exists in any scene; the lookup/setup call was dead.

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

	# Placeholder menu button connections are now handled by MenuManager

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

	# Reflow the two-column split, stat bars, and vendor button sizing when the device rotates
	# mid-session. Layout-only — no data reprocessing — with the vendor grid re-rendered through the
	# existing debounce so the new button dimensions apply. (Sprint 7)
	var dsm := get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(dsm) and dsm.has_signal("layout_mode_changed") and not dsm.layout_mode_changed.is_connected(_on_layout_mode_changed):
		dsm.layout_mode_changed.connect(_on_layout_mode_changed)

	# initialize_with_data can run before _ready; if so, we may have missed the initial preview refresh.
	if _vendor_preview_update_pending:
		_vendor_preview_update_pending = false
		_queue_vendor_preview_update()
	elif convoy_data_received != null and not convoy_data_received.is_empty():
		_queue_vendor_preview_update()

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
		call_deferred("_update_mobile_dependent_layout")
		call_deferred("_update_vendor_grid_columns")

func _on_layout_mode_changed(_mode: int = -1, _screen_size: Vector2 = Vector2.ZERO, _is_mobile_val: bool = false) -> void:
	if not is_inside_tree():
		return
	_update_mobile_dependent_layout()
	# Re-render the vendor preview grid so items pick up the new orientation button sizing.
	if convoy_data_received != null and not convoy_data_received.is_empty():
		_queue_vendor_preview_update()

func _update_mobile_dependent_layout() -> void:
	var is_portrait = _is_portrait_view()
	var use_mobile = _is_mobile()

	if is_portrait:
		VENDOR_ITEM_BUTTON_MIN_WIDTH = 200.0
		VENDOR_ITEM_BUTTON_HEIGHT = 100.0
	elif use_mobile:
		VENDOR_ITEM_BUTTON_MIN_WIDTH = 180.0
		VENDOR_ITEM_BUTTON_HEIGHT = 80.0
	else:
		VENDOR_ITEM_BUTTON_MIN_WIDTH = 160.0
		VENDOR_ITEM_BUTTON_HEIGHT = 70.0

	# Two-column split: side-by-side in landscape (desktop and mobile), stacked in portrait.
	if is_instance_valid(_main_split):
		var stack: bool = is_portrait
		_main_split.vertical = stack
		if is_instance_valid(_stats_column) and is_instance_valid(_content_column):
			if stack:
				_stats_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_content_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			else:
				# Stats take ~35%, content ~65% of the row in landscape.
				_stats_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_content_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_stats_column.size_flags_stretch_ratio = 1.35
				_content_column.size_flags_stretch_ratio = 2.65

	# In mobile landscape the full-width top banner clips off the top of the cramped menu,
	# so relocate the convoy name into the top of the stats column instead.
	_relocate_convoy_banner(use_mobile and not is_portrait)

	# Portrait: replace the tall stats column with a compact chip strip; the vendor preview
	# (with its tabs) then fills the rest of the bottom-sheet height.
	if is_portrait:
		_ensure_portrait_summary()
		_refresh_portrait_summary()
		if is_instance_valid(_portrait_summary_panel):
			_portrait_summary_panel.visible = true
		if is_instance_valid(_stats_column):
			_stats_column.visible = false
	else:
		if is_instance_valid(_portrait_summary_panel):
			_portrait_summary_panel.visible = false
		if is_instance_valid(_stats_column):
			_stats_column.visible = true

	# Super-scale stats in portrait by stacking them vertically
	var res_hbox := _res_stats_hbox
	var perf_hbox := _perf_stats_hbox

	var stat_height = 120.0 if is_portrait else 50.0

	var stat_fs = 28

	if is_instance_valid(res_hbox):
		# Resources stack vertically in portrait, but sit side-by-side in landscape
		# (like the performance stats row) to save vertical space.
		res_hbox.vertical = is_portrait
		res_hbox.add_theme_constant_override("separation", 8 if is_portrait else 4)
		# In landscape the three bars share the row width; in portrait they stack full-width.
		var res_box_h = stat_height if is_portrait else 44.0
		var supply_fs = stat_fs if is_portrait else 14
		for child in res_hbox.get_children():
			if child is Control:
				child.custom_minimum_size.y = res_box_h
				if is_portrait:
					child.custom_minimum_size.x = 0
					child.size_flags_horizontal = Control.SIZE_FILL
				else:
					# Equal-width columns in the landscape row.
					child.custom_minimum_size.x = 0
					child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				for grand_child in child.get_children():
					if grand_child is Label:
						grand_child.add_theme_font_size_override("font_size", supply_fs)
						if not is_portrait:
							# Keep long values from overflowing the narrow columns.
							grand_child.clip_text = true
							grand_child.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
							grand_child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_instance_valid(perf_hbox):
		perf_hbox.add_theme_constant_override("separation", 4)
		for child in perf_hbox.get_children():
			if child is Control:
				child.custom_minimum_size.y = 48  # compact, always horizontal row

	# Scale cargo bars taller in portrait so the built-in % text is readable
	var cargo_bars_hbox := _cargo_bars_hbox
	if is_instance_valid(cargo_bars_hbox):
		var cargo_bar_h = 80.0 if is_portrait else (48.0 if use_mobile else 28.0)
		for child in cargo_bars_hbox.get_children():
			if child is Control:
				child.custom_minimum_size.y = cargo_bar_h
				# Scale the label inside the cargo bar container
				for sub in child.get_children():
					if sub is Label:
						var dsm = get_node_or_null("/root/DeviceStateManager")
						var fs = 13
						sub.add_theme_font_size_override("font_size", fs)
					elif sub is ProgressBar:
						# Make in-bar % text bigger in portrait
						var dsm = get_node_or_null("/root/DeviceStateManager")
						var fs = 16
						sub.add_theme_font_size_override("font_size", fs)

	# Update vendor scroll handling
	var vendor_preview_panel := _vendor_preview_panel_node
	if is_instance_valid(vendor_preview_panel):
		var vendor_content_scroll = vendor_preview_panel.get_node_or_null("VendorPreviewVBox/VendorContentPanel/VendorContentScroll")
		if is_instance_valid(vendor_content_scroll) and vendor_content_scroll is ScrollContainer:
			vendor_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			vendor_content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			vendor_content_scroll.custom_minimum_size.y = 0
			vendor_content_scroll.scroll_deadzone = 8

	if is_instance_valid(_mission_sort_option_button):
		if is_portrait:
			_mission_sort_option_button.custom_minimum_size = Vector2(400, 80)
			var dsm = get_node_or_null("/root/DeviceStateManager")
			var fs = 18
			_mission_sort_option_button.add_theme_font_size_override("font_size", fs)
		else:
			_mission_sort_option_button.custom_minimum_size = Vector2(300, 34)
			_mission_sort_option_button.add_theme_font_size_override("font_size", 14)
			
		if use_mobile:
			var popup = _mission_sort_option_button.get_popup()
			var dsm = get_node_or_null("/root/DeviceStateManager")
			var fs = 16
			popup.add_theme_font_size_override("font_size", fs)
			popup.add_theme_constant_override("v_separation", 16 if is_portrait else 12)
			var popup_style = StyleBoxFlat.new()
			popup_style.bg_color = Color(0.15, 0.15, 0.15, 0.98)
			popup_style.content_margin_left = 24
			popup_style.content_margin_right = 24
			popup_style.content_margin_top = 16 if is_portrait else 12
			popup_style.content_margin_bottom = 16 if is_portrait else 12
			popup_style.border_width_left = 1
			popup_style.border_width_right = 1
			popup_style.border_width_top = 1
			popup_style.border_width_bottom = 1
			popup_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
			popup_style.corner_radius_top_left = 6
			popup_style.corner_radius_top_right = 6
			popup_style.corner_radius_bottom_left = 6
			popup_style.corner_radius_bottom_right = 6
			popup.add_theme_stylebox_override("panel", popup_style)

	if is_instance_valid(vendor_item_grid):
		for child in vendor_item_grid.get_children():
			if child is Control and child.has_meta("nav_intent"):
				_style_vendor_item_button(child, _current_vendor_tab)

func _get_convoy_display_name() -> String:
	if convoy_data_received is Dictionary:
		var n = convoy_data_received.get("convoy_name", convoy_data_received.get("name", ""))
		if n != null and str(n) != "":
			return str(n)
	return "Convoy"

func _refresh_convoy_name_header() -> void:
	if not is_instance_valid(_stats_column):
		return
	var lbl := _stats_column.get_node_or_null("ConvoyNameHeader") as Label
	if is_instance_valid(lbl):
		lbl.text = _get_convoy_display_name()

func _relocate_convoy_banner(into_stats_column: bool) -> void:
	# In mobile landscape the heavy full-width top banner clips off the top of the cramped
	# menu, so hide it and show the convoy name as a compact flowing Label header at the
	# top of the stats column (a Label flows in the VBox like the section headers, so it
	# never overflows the top edge).
	var banner := find_child("TopBannerPanel", true, false)

	if into_stats_column and is_instance_valid(_stats_column):
		if is_instance_valid(banner):
			banner.visible = false
		var lbl := _stats_column.get_node_or_null("ConvoyNameHeader") as Label
		if lbl == null:
			lbl = Label.new()
			lbl.name = "ConvoyNameHeader"
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.clip_text = true
			lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			lbl.add_theme_color_override("font_color", UITheme.ACCENT_BRASS)
			lbl.add_theme_constant_override("outline_size", 1)
			lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			lbl.add_theme_font_size_override("font_size", 20)
			lbl.add_theme_font_override("font", _make_bold_font())
			_stats_column.add_child(lbl)
		_stats_column.move_child(lbl, 0)
		lbl.visible = true
		lbl.text = _get_convoy_display_name()
	else:
		if is_instance_valid(banner):
			banner.visible = true
		if is_instance_valid(_stats_column):
			var lbl := _stats_column.get_node_or_null("ConvoyNameHeader")
			if is_instance_valid(lbl):
				lbl.visible = false

# --- Portrait summary strip -------------------------------------------------

func _pct(current_value, max_value) -> float:
	var c := NumberFormat.to_f(current_value, 0.0)
	var m := NumberFormat.to_f(max_value, 0.0)
	if m <= 0.0:
		return 0.0
	return clampf((c / m) * 100.0, 0.0, 100.0)

func _resource_pct_color(pct: float) -> Color:
	if pct >= 50.0:
		return COLOR_GREEN
	if pct >= 25.0:
		return COLOR_YELLOW
	return COLOR_RED

# Fill color for a capacity bar by fullness (verdigris → brass → danger as it fills up).
func _capacity_fill_color(ratio: float) -> Color:
	if ratio >= 0.97:
		return UITheme.DANGER
	if ratio >= 0.85:
		return UITheme.ACCENT_BRASS
	return UITheme.ACCENT_VERDIGRIS

# Stable, distinct palette for distribution bars (cycles for long lists).
func _cargo_type_color(index: int) -> Color:
	const PALETTE := [
		UITheme.ACCENT_VERDIGRIS,
		UITheme.ACCENT_BRASS,
		Color("#6a8caf"), # steel blue
		Color("#c08552"), # copper
		Color("#8e9a7c"), # olive
		Color("#a3729b"), # mauve
		Color("#6fae9c"), # teal
		Color("#c2a35a"), # ochre
	]
	return PALETTE[index % PALETTE.size()]

func _ensure_portrait_summary() -> void:
	if is_instance_valid(_portrait_summary_panel):
		return
	if not is_instance_valid(content_vbox):
		return
	_portrait_summary_panel = PanelContainer.new()
	_portrait_summary_panel.name = "PortraitSummary"
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.METAL_DARK
	sb.corner_radius_top_left = UITheme.RADIUS_SM
	sb.corner_radius_top_right = UITheme.RADIUS_SM
	sb.corner_radius_bottom_left = UITheme.RADIUS_SM
	sb.corner_radius_bottom_right = UITheme.RADIUS_SM
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_portrait_summary_panel.add_theme_stylebox_override("panel", sb)

	_portrait_summary_flow = HFlowContainer.new()
	_portrait_summary_flow.name = "SummaryFlow"
	_portrait_summary_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_portrait_summary_flow.add_theme_constant_override("h_separation", 8)
	_portrait_summary_flow.add_theme_constant_override("v_separation", 6)
	_portrait_summary_panel.add_child(_portrait_summary_flow)

	content_vbox.add_child(_portrait_summary_panel)
	content_vbox.move_child(_portrait_summary_panel, 0)

func _add_summary_chip(label: String, value: String, color: Color, stat_type: String = "") -> void:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.18, 0.22, 0.92)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	# Tappable performance chips get a brass border to advertise the breakdown modal.
	if stat_type != "":
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = UITheme.ACCENT_BRASS
	chip.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(vbox)

	var label_lbl := Label.new()
	label_lbl.text = label.to_upper()
	label_lbl.add_theme_font_size_override("font_size", 11)
	label_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1.0))
	label_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(label_lbl)

	var value_lbl := Label.new()
	value_lbl.text = value
	value_lbl.add_theme_font_size_override("font_size", 18)
	value_lbl.add_theme_color_override("font_color", color)
	value_lbl.add_theme_font_override("font", _make_bold_font())
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(value_lbl)

	if stat_type != "":
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.tooltip_text = "Tap for breakdown"
		chip.gui_input.connect(_on_stat_box_gui_input.bind(stat_type))

	_portrait_summary_flow.add_child(chip)

func _refresh_portrait_summary() -> void:
	if not is_instance_valid(_portrait_summary_flow):
		return
	if not (convoy_data_received is Dictionary) or convoy_data_received.is_empty():
		return
	for c in _portrait_summary_flow.get_children():
		c.queue_free()

	# Resources (colour-coded by remaining %)
	var fuel_pct := _pct(convoy_data_received.get("fuel", 0.0), convoy_data_received.get("max_fuel", 0.0))
	var water_pct := _pct(convoy_data_received.get("water", 0.0), convoy_data_received.get("max_water", 0.0))
	var food_pct := _pct(convoy_data_received.get("food", 0.0), convoy_data_received.get("max_food", 0.0))
	_add_summary_chip("Fuel", "%d%%" % roundi(fuel_pct), _resource_pct_color(fuel_pct), "fuel")
	_add_summary_chip("Water", "%d%%" % roundi(water_pct), _resource_pct_color(water_pct), "water")
	_add_summary_chip("Food", "%d%%" % roundi(food_pct), _resource_pct_color(food_pct), "food")

	# Cargo capacity (neutral colour — higher just means fuller)
	var total_vol := NumberFormat.to_f(convoy_data_received.get("total_cargo_capacity", 0.0), 0.0)
	var used_vol := total_vol - NumberFormat.to_f(convoy_data_received.get("total_free_space", 0.0), 0.0)
	var total_wt := NumberFormat.to_f(convoy_data_received.get("total_weight_capacity", 0.0), 0.0)
	var used_wt := total_wt - NumberFormat.to_f(convoy_data_received.get("total_remaining_capacity", 0.0), 0.0)
	_add_summary_chip("Volume", "%d%%" % roundi(_pct(used_vol, total_vol)), UITheme.TEXT_PRIMARY, "cargo_volume")
	_add_summary_chip("Weight", "%d%%" % roundi(_pct(used_wt, total_wt)), UITheme.TEXT_PRIMARY, "cargo_weight")

	# Performance (raw ratings, brass)
	var spd := NumberFormat.to_f(convoy_data_received.get("top_speed", 0.0), 0.0)
	var off := NumberFormat.to_f(convoy_data_received.get("offroad_capability", 0.0), 0.0)
	var eff := NumberFormat.to_f(convoy_data_received.get("efficiency", 0.0), 0.0)
	_add_summary_chip("Speed", NumberFormat.fmt_float(spd, 0), UITheme.ACCENT_BRASS, "top_speed")
	_add_summary_chip("Offroad", NumberFormat.fmt_float(off, 0), UITheme.ACCENT_BRASS, "offroad_capability")
	_add_summary_chip("Efficiency", NumberFormat.fmt_float(eff, 0), UITheme.ACCENT_BRASS, "efficiency")

func _update_vendor_grid_columns(override_count: int = -1) -> void:
	if not is_instance_valid(vendor_item_grid):
		return

	# To prioritize 2 rows while maintaining horizontal scrolling, 
	# we set columns to half the item count (rounded up).
	# Use override_count if provided, otherwise use current child count.
	var item_count = override_count if override_count >= 0 else vendor_item_grid.get_child_count()
	
	# If we are using the live child count, we must subtract any that are queue_freed
	# but not yet removed from the tree.
	if override_count < 0:
		var active_count = 0
		for child in vendor_item_grid.get_children():
			if not child.is_queued_for_deletion():
				active_count += 1
		item_count = active_count

	vendor_item_grid.columns = 1

	if _debug_convoy_menu:
		print("[ConvoyMenu] vertical scroll: items=", item_count, " cols=1")

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
		# Keep the landscape stats-column name header in sync with the latest convoy data.
		_refresh_convoy_name_header()
		# Keep the portrait summary chips in sync too.
		_refresh_portrait_summary()

		# --- Resources (Fuel, Water, Food) ---
		# On mobile the boxes are narrow, so show a compact percentage; desktop shows full values.
		var current_fuel = convoy_data_received.get("fuel", 0.0)
		var max_fuel = convoy_data_received.get("max_fuel", 0.0)
		if is_instance_valid(fuel_text_label): fuel_text_label.text = _format_resource_label("⛽", "Fuel", current_fuel, max_fuel)
		if is_instance_valid(fuel_bar): _set_resource_bar_style(fuel_bar, fuel_text_label, current_fuel, max_fuel)

		var current_water = convoy_data_received.get("water", 0.0)
		var max_water = convoy_data_received.get("max_water", 0.0)
		if is_instance_valid(water_text_label): water_text_label.text = _format_resource_label("💧", "Water", current_water, max_water)
		if is_instance_valid(water_bar): _set_resource_bar_style(water_bar, water_text_label, current_water, max_water)

		var current_food = convoy_data_received.get("food", 0.0)
		var max_food = convoy_data_received.get("max_food", 0.0)
		if is_instance_valid(food_text_label): food_text_label.text = _format_resource_label("🍖", "Food", current_food, max_food)
		if is_instance_valid(food_bar): _set_resource_bar_style(food_bar, food_text_label, current_food, max_food)

		# --- Performance Stats (Speed, Offroad, Efficiency) ---
		# Assuming these are rated 0-100 for coloring, adjust max_value if different
		var top_speed = convoy_data_received.get("top_speed", 0.0)
		if is_instance_valid(speed_text_label): speed_text_label.text = NumberFormat.fmt_float(top_speed, 2)
		if is_instance_valid(speed_box): _set_fixed_color_box_style(speed_box, speed_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

		var offroad = convoy_data_received.get("offroad_capability", 0.0)
		if is_instance_valid(offroad_text_label): offroad_text_label.text = NumberFormat.fmt_float(offroad, 2)
		if is_instance_valid(offroad_box): _set_fixed_color_box_style(offroad_box, offroad_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

		var efficiency = convoy_data_received.get("efficiency", 0.0)
		if is_instance_valid(efficiency_text_label): efficiency_text_label.text = NumberFormat.fmt_float(efficiency, 2)
		if is_instance_valid(efficiency_box): _set_fixed_color_box_style(efficiency_box, efficiency_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

		# --- Cargo Volume and Weight Bars ---
		if is_instance_valid(cargo_volume_text_label) and is_instance_valid(cargo_volume_bar):
			var used_volume = convoy_data_received.get("total_cargo_capacity", 0.0) - convoy_data_received.get("total_free_space", 0.0)
			var total_volume = convoy_data_received.get("total_cargo_capacity", 0.0)
			cargo_volume_text_label.text = "📐 Volume: %s / %s" % [NumberFormat.fmt_float(used_volume, 2), NumberFormat.fmt_float(total_volume, 2)]
			_set_progressbar_style(cargo_volume_bar, used_volume, total_volume)
		if is_instance_valid(cargo_weight_text_label) and is_instance_valid(cargo_weight_bar):
			var used_weight = convoy_data_received.get("total_weight_capacity", 0.0) - convoy_data_received.get("total_remaining_capacity", 0.0)
			var total_weight = convoy_data_received.get("total_weight_capacity", 0.0)
			cargo_weight_text_label.text = "⚖️ Weight: %s / %s" % [NumberFormat.fmt_float(used_weight, 2), NumberFormat.fmt_float(total_weight, 2)]
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
		var part_metas: Array[Dictionary] = []
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
			# Precompute each convoy vehicle's available slots so we can annotate every part
			# with which vehicles can actually use it (matched by slot).
			var veh_slot_map: Array = _convoy_vehicle_slot_map()
			# Attempt to fetch enriched cargo names for each cargo_id
			if _mechanics_service.has_method("get_enriched_cargo"):
				for cid in c2s.keys():
					var cargo: Dictionary = _mechanics_service.get_enriched_cargo(String(cid))
					var nm := String(cargo.get("name", cargo.get("base_name", "")))
					if nm == "" and _mechanics_service.has_method("ensure_cargo_details"):
						# Trigger enrichment for future updates
						_mechanics_service.ensure_cargo_details(String(cid))
					if nm != "":
						var pslot := String(c2s.get(cid, ""))
						part_names.append(nm)
						part_metas.append({
							"slot": pslot,
							"weight": cargo.get("weight", 0.0),
							"volume": cargo.get("volume", 0.0),
							"fits": _vehicle_names_for_slot(pslot, veh_slot_map),
						})
		# Sort parts so the most broadly compatible (fits the most convoy vehicles) come first;
		# keep names and metas aligned by sorting a combined view, then rebuilding both.
		if not part_names.is_empty():
			var combined: Array = []
			for idx in range(part_names.size()):
				combined.append({"name": part_names[idx], "meta": part_metas[idx]})
			combined.sort_custom(func(a, b):
				var fa: int = (a.get("meta", {}).get("fits", []) as Array).size()
				var fb: int = (b.get("meta", {}).get("fits", []) as Array).size()
				if fa != fb:
					return fa > fb
				return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0
			)
			part_names.clear()
			part_metas.clear()
			for entry in combined:
				part_names.append(String(entry.get("name", "")))
				part_metas.append(entry.get("meta", {}))
		# If names are still empty, fall back to slot summary counts
		if part_names.is_empty():
			part_metas.clear()
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
		_compatible_part_meta = part_metas
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


func _build_vendor_preview_button(item_string: String, item_meta: Dictionary = {}) -> Control:
	var button := PanelContainer.new()
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
	var item_name := name_qty

	# Card layout: left accent strip + padded text content
	var inner_hbox := HBoxContainer.new()
	inner_hbox.name = "InnerHBox"
	inner_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_hbox.add_theme_constant_override("separation", 0)
	button.add_child(inner_hbox)

	var accent_strip := ColorRect.new()
	accent_strip.name = "AccentStrip"
	accent_strip.custom_minimum_size = Vector2(3, 0)
	accent_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	accent_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_hbox.add_child(accent_strip)

	var text_bounds := MarginContainer.new()
	text_bounds.name = "TextBounds"
	text_bounds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_bounds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_bounds.add_theme_constant_override("margin_left", int(VENDOR_ITEM_BUTTON_PADDING_X))
	text_bounds.add_theme_constant_override("margin_right", int(VENDOR_ITEM_BUTTON_PADDING_X))
	text_bounds.add_theme_constant_override("margin_top", int(VENDOR_ITEM_BUTTON_TOP_PADDING))
	text_bounds.add_theme_constant_override("margin_bottom", int(VENDOR_ITEM_BUTTON_BOTTOM_CLEARANCE))
	inner_hbox.add_child(text_bounds)

	var vbox := VBoxContainer.new()
	vbox.name = "ButtonVBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	text_bounds.add_child(vbox)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = item_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var cargo_fs = 20 if not _is_mobile() else (22 if _is_portrait_view() else 20)
	name_label.add_theme_font_size_override("font_size", cargo_fs)

	vbox.add_child(name_label)

	if dest_text != "":
		var dest_label := Label.new()
		dest_label.name = "DestLabel"
		dest_label.text = "→ " + dest_text
		dest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		dest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dest_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		dest_label.clip_text = true
		dest_label.add_theme_constant_override("outline_size", 2)
		dest_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		dest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dest_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dest_label.add_theme_color_override("font_color", UITheme.ACCENT_VERDIGRIS)
		dest_label.add_theme_font_size_override("font_size", cargo_fs)
		vbox.add_child(dest_label)

	var meta_text := _format_item_meta(item_meta, _current_vendor_tab)
	if meta_text != "":
		var meta_label := Label.new()
		meta_label.name = "MetaLabel"
		meta_label.text = meta_text
		meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		meta_label.add_theme_font_size_override("font_size", max(11, int(cargo_fs * 0.72)))
		# Highlight parts that actually fit a convoy vehicle so they read as actionable.
		var fits_here: Variant = item_meta.get("fits", [])
		var fits_ok := _current_vendor_tab == VendorTab.COMPATIBLE_PARTS and (fits_here is Array) and not (fits_here as Array).is_empty()
		meta_label.add_theme_color_override("font_color", UITheme.STATUS_GOOD if fits_ok else UITheme.TEXT_MUTED)
		meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		meta_label.clip_text = true
		meta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(meta_label)

	button.set_meta("name_label", name_label)
	button.set_meta("accent_strip", accent_strip)
	var fits_meta: Variant = item_meta.get("fits", [])
	button.set_meta("fits_count", (fits_meta as Array).size() if fits_meta is Array else 0)
	if dest_text != "":
		button.set_meta("dest_label", vbox.get_child(1) if vbox.get_child_count() > 1 else null)

	# Set flexible default width. The labels will adapt based on Control.SIZE_EXPAND_FILL behavior
	# but text_overrun_behavior stops them from pushing button minimum bounds outward.
	var default_text_width := 10.0
	name_label.custom_minimum_size.x = default_text_width
	if vbox.get_child_count() > 1 and vbox.get_child(1) is Label:
		(vbox.get_child(1) as Label).custom_minimum_size.x = default_text_width

	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.x = VENDOR_ITEM_BUTTON_MIN_WIDTH
	button.custom_minimum_size.y = VENDOR_ITEM_BUTTON_HEIGHT
	button.clip_contents = true

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

	# Mobile tap detection logic to replace Button press
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				button.set_meta("tap_start_pos", event.global_position)
				# Update background to pressed style
				var custom_style = StyleBoxFlat.new()
				custom_style.bg_color = UITheme.METAL_ACTIVE
				custom_style.border_color = UITheme.METAL_EDGE
				custom_style.border_width_top = 1
				custom_style.border_width_bottom = 2
				custom_style.border_width_right = 1
				custom_style.corner_radius_top_left = UITheme.RADIUS_SM
				custom_style.corner_radius_top_right = UITheme.RADIUS_SM
				custom_style.corner_radius_bottom_left = UITheme.RADIUS_SM
				custom_style.corner_radius_bottom_right = UITheme.RADIUS_SM
				custom_style.content_margin_top = 1
				button.add_theme_stylebox_override("panel", custom_style)
			else:
				# Reset style
				_style_vendor_item_button(button, _current_vendor_tab)
				var start_pos = button.get_meta("tap_start_pos", event.global_position)
				var move_dist = (event.global_position - start_pos).length()
				if move_dist < 10:
					_on_vendor_preview_item_button_pressed(button)
					get_viewport().set_input_as_handled()
	)

	_style_vendor_item_button(button, _current_vendor_tab)
	return button

func _render_vendor_preview_display() -> void:
	# Tab labels (counts intentionally omitted — noise at this point in the flow)
	if is_instance_valid(convoy_missions_tab_button):
		convoy_missions_tab_button.text = "Active Deliveries"
	if is_instance_valid(settlement_missions_tab_button):
		settlement_missions_tab_button.text = "Available Deliveries"
	if is_instance_valid(compatible_parts_tab_button):
		compatible_parts_tab_button.text = "Available Parts"
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

	var sort_container: HBoxContainer = _mission_sort_container
	if not is_instance_valid(sort_container):
		var preview_vbox = _vendor_preview_panel_node.get_node_or_null("VendorPreviewVBox") if is_instance_valid(_vendor_preview_panel_node) else null
		sort_container = preview_vbox.get_node_or_null("SortDropdownContainer") if preview_vbox else null
		_mission_sort_container = sort_container
	if sort_container:
		if content_list.is_empty() or _current_vendor_tab == VendorTab.COMPATIBLE_PARTS:
			sort_container.visible = false
		else:
			sort_container.visible = true

	if content_list.is_empty():
		vendor_item_container.visible = false
		vendor_no_items_label.visible = true
	else:
		vendor_item_container.visible = true
		vendor_no_items_label.visible = false
		var item_count = content_list.size()
		var meta_list := _get_current_meta_list()
		for i in range(content_list.size()):
			var item_meta: Dictionary = meta_list[i] if i < meta_list.size() else {}
			var button := _build_vendor_preview_button(content_list[i], item_meta)
			vendor_item_grid.add_child(button)

	# Ensure font sizes and grid columns are updated

	_update_vendor_grid_columns(content_list.size())


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
				if ItemsData != null and ItemsData.DeliveryCargoItem:
					mission_ok = ItemsData.DeliveryCargoItem._looks_like_delivery_dict(it)
				if not mission_ok:
					mission_ok = NumberFormat.to_f(it.get("delivery_reward"), 0.0) > 0.0 or NumberFormat.to_f(it.get("unit_delivery_reward"), 0.0) > 0.0
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


func _on_vendor_preview_item_button_pressed(button: Control) -> void:
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
	var agg_data: Dictionary = {} # display_key -> raw item
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
						if not agg_data.has(display_key):
							agg_data[display_key] = raw_item.duplicate()
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
						if _looks_like_delivery_item(item):
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
							if not agg_data.has(display_key2):
								agg_data[display_key2] = item.duplicate()
							diag_raw_mission += 1

	# Fallback to convoy-level inventory if nothing was found in vehicles
	if not found_any_cargo and convoy.has("cargo_inventory") and convoy.cargo_inventory is Array:
		for item in convoy.cargo_inventory:
			if not (item is Dictionary):
				continue
			if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
				continue
			if _looks_like_delivery_item(item):
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
				if not agg_data.has(display_key3):
					agg_data[display_key3] = item.duplicate()
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
			if _looks_like_delivery_item(ac):
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
				if not agg_data.has(display_key4):
					agg_data[display_key4] = ac.duplicate()
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] all_cargo mission item=", aname, " q=", aq)
				diag_allcargo_mission += 1


	var CargoSorter = null
	if _cargo_sort_metric >= 0:
		CargoSorter = preload("res://Scripts/System/cargo_sorter.gd")
	var items_to_sort = []
	for k in agg.keys():
		var data = agg_data.get(k, {}).duplicate()
		data["display_name"] = String(k)
		data["total_quantity"] = agg[k]
		items_to_sort.append(data)

	if CargoSorter and _cargo_sort_metric >= 0:
		items_to_sort = CargoSorter.sort_cargo(items_to_sort, _cargo_sort_metric, false)

	_convoy_mission_meta.clear()
	for sorted_item in items_to_sort:
		out.append(sorted_item["display_name"])
		_convoy_mission_meta.append(sorted_item)
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] mission agg result=", out)
		print("[ConvoyMenu][Debug] diag typed=", diag_typed_mission, " raw=", diag_raw_mission, " all=", diag_allcargo_mission)
	return out

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

func _looks_like_delivery_item(item: Dictionary) -> bool:
	# Prefer centralized classification when available
	if ItemsData != null and ItemsData.DeliveryCargoItem:
		var looks_delivery := ItemsData.DeliveryCargoItem._looks_like_delivery_dict(item)
		if looks_delivery:
			return true
		return false
	# Local rule: mission cargo must have positive delivery_reward and not be an intrinsic part
	if not item:
		return false
	if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
		return false
	if _is_part_item(item):
		return false
	return NumberFormat.to_f(item.get("delivery_reward"), 0.0) > 0.0 or NumberFormat.to_f(item.get("unit_delivery_reward"), 0.0) > 0.0

# Helper: scan an array of settlement records and aggregate mission items into agg
func _scan_settlement_array(arr: Array, agg: Dictionary) -> void:
	for it in arr:
		if not (it is Dictionary):
			continue
		if it.has("intrinsic_part_id") and it.get("intrinsic_part_id") != null:
			continue
		var mission_ok := false
		if ItemsData != null and ItemsData.DeliveryCargoItem:
			mission_ok = ItemsData.DeliveryCargoItem._looks_like_delivery_dict(it)
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
	var raw_items = []
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
			var is_delivery := false
			if ItemsData and ItemsData.DeliveryCargoItem:
				is_delivery = ItemsData.DeliveryCargoItem._looks_like_delivery_dict(ci)
			else:
				is_delivery = NumberFormat.to_f(ci.get("delivery_reward"), 0.0) > 0.0 or NumberFormat.to_f(ci.get("unit_delivery_reward"), 0.0) > 0.0
			if not is_delivery:
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

			var sort_data = ci.duplicate()
			sort_data["display_name"] = entry2
			raw_items.append(sort_data)


	var CargoSorter = null
	if _cargo_sort_metric >= 0:
		CargoSorter = preload("res://Scripts/System/cargo_sorter.gd")
	if CargoSorter and _cargo_sort_metric >= 0:
		raw_items = CargoSorter.sort_cargo(raw_items, _cargo_sort_metric, false)

	_settlement_mission_meta.clear()
	for ri in raw_items:
		out.append(ri["display_name"])
		_settlement_mission_meta.append(ri)

	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] Settlement missions via vendor fallback: ", out)
	return out


func _on_cargo_data_received(cargo: Dictionary) -> void:
	# Cargo enrichment responses can include recipient/destination fields.
	# When one arrives, refresh preview so Available Missions can show destinations.
	if not (cargo is Dictionary) or cargo.is_empty():
		return
	# Keep this cheap: only queue a refresh if this looks like mission cargo or has useful destination fields.
	var looks_delivery := false
	if ItemsData != null and ItemsData.DeliveryCargoItem:
		looks_delivery = ItemsData.DeliveryCargoItem._looks_like_delivery_dict(cargo)
	else:
		looks_delivery = NumberFormat.to_f(cargo.get("delivery_reward"), 0.0) > 0.0 or NumberFormat.to_f(cargo.get("unit_delivery_reward"), 0.0) > 0.0

	var looks_part := false
	if ItemsData != null and ItemsData.PartItem:
		looks_part = ItemsData.PartItem._looks_like_part_dict(cargo)

	if not looks_delivery and not looks_part and cargo.get("recipient_settlement_name") == null and cargo.get("recipient") == null and cargo.get("mission_vendor_id") == null:
		return
	_queue_vendor_preview_update()

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
	# Settlement vendor prices/stock just changed → re-evaluate the Top Up plan/affordability.
	_update_top_up_button()
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
			var is_delivery := false
			if ItemsData and ItemsData.DeliveryCargoItem:
				is_delivery = ItemsData.DeliveryCargoItem._looks_like_delivery_dict(it)
			if not is_delivery:
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

func _on_mission_sort_selected(idx: int) -> void:
	_cargo_sort_metric = idx
	_save_cargo_sort_metric_to_settings(idx)
	_update_vendor_preview()

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

func _format_resource_label(icon: String, name: String, current_value: float, max_value: float) -> String:
	# Mobile: compact percentage (e.g. "⛽ 83%"). Desktop: full "⛽ Fuel: 56.27 / 68".
	if _is_mobile():
		var pct: float = 0.0
		if max_value > 0:
			pct = (current_value / max_value) * 100.0
		return "%s %d%%" % [icon, roundi(pct)]
	return "%s %s: %s / %s" % [icon, name, NumberFormat.fmt_float(current_value, 2), NumberFormat.fmt_float(max_value, 2)]

func _set_resource_bar_style(bar_node: ProgressBar, label_node: Label, current_value: float, max_value: float, custom_color: Color = Color.TRANSPARENT):
	if not is_instance_valid(bar_node) or not is_instance_valid(label_node):
		return

	var percentage: float = 0.0
	if max_value > 0:
		percentage = clamp(current_value / max_value, 0.0, 1.0)
		bar_node.value = percentage * 100.0
	else:
		bar_node.value = 0.0

	var fill_color := _get_color_for_percentage(percentage)
	if custom_color != Color.TRANSPARENT:
		fill_color = custom_color
		
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.border_width_left = 1
	fill_style.border_width_right = 1
	fill_style.border_width_top = 1
	fill_style.border_width_bottom = 1
	fill_style.border_color = fill_color.darkened(0.2)
	fill_style.corner_radius_top_left = UITheme.RADIUS_MD
	fill_style.corner_radius_top_right = UITheme.RADIUS_MD
	fill_style.corner_radius_bottom_right = UITheme.RADIUS_MD
	fill_style.corner_radius_bottom_left = UITheme.RADIUS_MD
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
	bg_style.corner_radius_top_left = UITheme.RADIUS_MD
	bg_style.corner_radius_top_right = UITheme.RADIUS_MD
	bg_style.corner_radius_bottom_right = UITheme.RADIUS_MD
	bg_style.corner_radius_bottom_left = UITheme.RADIUS_MD
	bar_node.add_theme_stylebox_override("background", bg_style)

	# Use a contrasting font color for the label on top of the bar and add a shadow for readability
	label_node.add_theme_color_override("font_color", Color.WHITE)
	label_node.add_theme_constant_override("shadow_outline_size", 1)
	label_node.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))

func _upgrade_stat_boxes() -> void:
	_upgrade_single_stat_box(speed_box, speed_text_label, "🏎️ SPEED", true)
	_upgrade_single_stat_box(offroad_box, offroad_text_label, "🏔️ OFFROAD", true)
	_upgrade_single_stat_box(efficiency_box, efficiency_text_label, "⚡ EFFICIENCY", true)
	# Each performance stat is an aggregate of the convoy's vehicles — make the box tappable
	# to open a per-vehicle breakdown (mirrors convoy_vehicle_menu's inspect pattern).
	_make_stat_box_inspectable(speed_box, "top_speed")
	_make_stat_box_inspectable(offroad_box, "offroad_capability")
	_make_stat_box_inspectable(efficiency_box, "efficiency")
	# Resources (fuel/water/food) and cargo bars are also per-vehicle aggregates — tap to
	# see where they're stored / how they're distributed. The boxes are the labels' parents.
	if is_instance_valid(fuel_text_label): _make_stat_box_inspectable(fuel_text_label.get_parent(), "fuel")
	if is_instance_valid(water_text_label): _make_stat_box_inspectable(water_text_label.get_parent(), "water")
	if is_instance_valid(food_text_label): _make_stat_box_inspectable(food_text_label.get_parent(), "food")
	if is_instance_valid(cargo_volume_bar): _make_stat_box_inspectable(cargo_volume_bar.get_parent(), "cargo_volume")
	if is_instance_valid(cargo_weight_bar): _make_stat_box_inspectable(cargo_weight_bar.get_parent(), "cargo_weight")
	_style_supply_labels()
	_style_cargo_bar_labels()

func _make_stat_box_inspectable(box: Control, stat_type: String) -> void:
	if not is_instance_valid(box):
		return
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.tooltip_text = "Tap for breakdown"
	# Children must not eat the tap so it reaches the box's gui_input.
	for child in box.get_children():
		_set_mouse_ignore_recursive(child)
	var cb := _on_stat_box_gui_input.bind(stat_type)
	if not box.gui_input.is_connected(cb):
		box.gui_input.connect(cb)

func _set_mouse_ignore_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_set_mouse_ignore_recursive(c)

func _on_stat_box_gui_input(event: InputEvent, stat_type: String) -> void:
	var tapped := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true
	if tapped:
		_on_inspect_convoy_stat_pressed(stat_type)

# ────────────────────────────────────────────────────────────────────
# Convoy stat breakdown modal (per-vehicle). Ported from convoy_vehicle_menu's
# inspect pattern (_make_inspect_overlay / _make_inspect_panel / _add_kv_row).
# ────────────────────────────────────────────────────────────────────

func _on_inspect_convoy_stat_pressed(stat_type: String) -> void:
	var portrait := _is_portrait_view()
	var pretty := stat_type.capitalize().replace("_", " ")
	var ctx := _make_inspect_overlay("Inspect: " + pretty)
	var overlay: Control = ctx["overlay"]
	var content_vb: VBoxContainer = ctx["content_vb"]

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.add_child(scroll)

	var inner_vb := VBoxContainer.new()
	inner_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_vb.add_theme_constant_override("separation", UITheme.SPACE_SM)
	scroll.add_child(inner_vb)

	# The convoy snapshot carries the vehicle list under either key depending on source
	# (full snapshot vs lighter payload), so fall back like the rest of the codebase
	# (mechanics_menu, convoy_cargo_menu, UI_manager all do this).
	var vehicles: Array = convoy_data_received.get("vehicle_details_list", convoy_data_received.get("vehicles", []))

	match stat_type:
		"top_speed", "offroad_capability", "efficiency":
			_build_performance_breakdown(inner_vb, vehicles, stat_type, portrait)
		"fuel", "water", "food":
			_build_resource_breakdown(inner_vb, vehicles, stat_type, portrait)
		"cargo_volume", "cargo_weight":
			_build_cargo_breakdown(inner_vb, vehicles, stat_type, portrait)

	add_child(overlay)

func _inspect_empty_label(inner_vb: VBoxContainer, portrait: bool) -> void:
	var none_lbl := Label.new()
	none_lbl.text = "No vehicles in this convoy."
	none_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	none_lbl.add_theme_font_size_override("font_size", 20 if portrait else 14)
	inner_vb.add_child(none_lbl)

func _inspect_rule_label(inner_vb: VBoxContainer, text: String, portrait: bool) -> void:
	if text.is_empty():
		return
	var rule_lbl := Label.new()
	rule_lbl.text = text
	rule_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	rule_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	rule_lbl.add_theme_font_size_override("font_size", 18 if portrait else 13)
	inner_vb.add_child(rule_lbl)

# Performance stats (speed/offroad = minimum across vehicles, efficiency = average).
func _build_performance_breakdown(inner_vb: VBoxContainer, vehicles: Array, stat_type: String, portrait: bool) -> void:
	var entries: Array = [] # [{name, value}]
	for v in vehicles:
		if not (v is Dictionary):
			continue
		entries.append({
			"name": str((v as Dictionary).get("name", "Vehicle")),
			"value": float((v as Dictionary).get(stat_type, 0.0)),
		})

	var convoy_value: float = float(convoy_data_received.get(stat_type, 0.0))
	var is_min_stat := stat_type in ["top_speed", "offroad_capability"]
	var limiting_idx := -1
	if is_min_stat and not entries.is_empty():
		limiting_idx = 0
		for i in range(1, entries.size()):
			if entries[i].value < entries[limiting_idx].value:
				limiting_idx = i

	var stat_label := ""
	match stat_type:
		"top_speed": stat_label = "Top Speed"
		"offroad_capability": stat_label = "Offroad"
		"efficiency": stat_label = "Efficiency"
	inner_vb.add_child(_make_inspect_panel("Convoy", [{"k": stat_label, "v": NumberFormat.fmt_float(convoy_value, 2)}]))

	# Per-vehicle breakdown (highlight the limiting vehicle for min stats).
	if not entries.is_empty():
		var per_vehicle_rows: Array = []
		for i in range(entries.size()):
			var row := {"k": entries[i].name, "v": NumberFormat.fmt_float(entries[i].value, 2)}
			if is_min_stat and i == limiting_idx:
				row["highlight"] = true
			per_vehicle_rows.append(row)
		inner_vb.add_child(_make_inspect_panel("Per vehicle", per_vehicle_rows))
	else:
		_inspect_empty_label(inner_vb, portrait)

	var rule_text := ""
	match stat_type:
		"top_speed": rule_text = "Convoy speed = the slowest vehicle's speed (minimum)."
		"offroad_capability": rule_text = "Convoy offroad = the least-capable vehicle (minimum)."
		"efficiency": rule_text = "Convoy efficiency = the average across all vehicles."
	_inspect_rule_label(inner_vb, rule_text, portrait)

# Resources (fuel/water/food) live inside each vehicle's cargo items — show where they're stored.
func _build_resource_breakdown(inner_vb: VBoxContainer, vehicles: Array, res_key: String, portrait: bool) -> void:
	var pretty := res_key.capitalize()
	var fill_col := _resource_pct_color(_pct(convoy_data_received.get(res_key, 0.0), convoy_data_received.get("max_" + res_key, 0.0)))
	var current: float = float(convoy_data_received.get(res_key, 0.0))
	var maximum: float = float(convoy_data_received.get("max_" + res_key, 0.0))

	# Convoy total as a capacity bar (current / max).
	inner_vb.add_child(_make_bar_panel("Convoy", [{
		"label": "%s stored" % pretty,
		"value": "%s / %s" % [NumberFormat.fmt_float(current, 2), NumberFormat.fmt_float(maximum, 2)],
		"ratio": (current / maximum) if maximum > 0.0 else 0.0,
		"color": fill_col,
	}]))

	# Containers: which cargo stacks hold the resource, grouped by vehicle. The cargo
	# field on each stack is its total amount (stacks sum to the convoy total).
	var any_carrier := false
	for v in vehicles:
		if not (v is Dictionary):
			continue
		var vd := v as Dictionary
		var container_amounts: Dictionary = {} # container name -> amount (merge dupes)
		var container_order: Array = []
		for c in vd.get("cargo", []):
			if not (c is Dictionary):
				continue
			var raw = (c as Dictionary).get(res_key)
			var amt := float(raw) if raw != null else 0.0
			if amt <= 0.0:
				continue
			var cname := str((c as Dictionary).get("name", "Container"))
			if not container_amounts.has(cname):
				container_amounts[cname] = 0.0
				container_order.append(cname)
			container_amounts[cname] += amt
		if container_order.is_empty():
			continue
		any_carrier = true
		var rows: Array = []
		for cname in container_order:
			rows.append({"k": cname, "v": NumberFormat.fmt_float(container_amounts[cname], 2)})
		inner_vb.add_child(_make_inspect_panel("📦 %s" % str(vd.get("name", "Vehicle")), rows))

	if vehicles.is_empty():
		_inspect_empty_label(inner_vb, portrait)
	elif not any_carrier:
		_inspect_rule_label(inner_vb, "No vehicle is carrying %s." % pretty.to_lower(), portrait)
	else:
		_inspect_rule_label(inner_vb, "%s is held in these cargo containers aboard your vehicles." % pretty, portrait)

# Cargo volume/weight distribution across vehicles (used vs capacity).
func _build_cargo_breakdown(inner_vb: VBoxContainer, vehicles: Array, kind: String, portrait: bool) -> void:
	var is_volume := kind == "cargo_volume"
	var pretty := "Volume" if is_volume else "Weight"

	var convoy_cap: float
	var convoy_used: float
	if is_volume:
		convoy_cap = float(convoy_data_received.get("total_cargo_capacity", 0.0))
		convoy_used = convoy_cap - float(convoy_data_received.get("total_free_space", 0.0))
	else:
		convoy_cap = float(convoy_data_received.get("total_weight_capacity", 0.0))
		convoy_used = convoy_cap - float(convoy_data_received.get("total_remaining_capacity", 0.0))
	var fill_ratio := (convoy_used / convoy_cap) if convoy_cap > 0.0 else 0.0
	inner_vb.add_child(_make_bar_panel("Convoy capacity", [{
		"label": "Used (%d%% full)" % roundi(fill_ratio * 100.0),
		"value": "%s / %s" % [NumberFormat.fmt_float(convoy_used, 2), NumberFormat.fmt_float(convoy_cap, 2)],
		"ratio": fill_ratio,
		"color": _capacity_fill_color(fill_ratio),
	}]))

	if vehicles.is_empty():
		_inspect_empty_label(inner_vb, portrait)
		return

	# Distribution by cargo type — sum this cargo field across every stack, grouped by name.
	var type_totals: Dictionary = {} # name -> amount
	var type_order: Array = []
	var grand_total := 0.0
	var field := "volume" if is_volume else "weight"
	for v in vehicles:
		if not (v is Dictionary):
			continue
		for c in (v as Dictionary).get("cargo", []):
			if not (c is Dictionary):
				continue
			var raw = (c as Dictionary).get(field)
			var amt := float(raw) if raw != null else 0.0
			if amt <= 0.0:
				continue
			var cname := str((c as Dictionary).get("name", "Cargo"))
			if not type_totals.has(cname):
				type_totals[cname] = 0.0
				type_order.append(cname)
			type_totals[cname] += amt
			grand_total += amt

	if grand_total > 0.0:
		type_order.sort_custom(func(a, b): return type_totals[a] > type_totals[b])
		# Cap the list so the panel stays readable; lump the tail into "Other".
		const MAX_TYPES := 8
		var dist_bars: Array = []
		var shown := 0
		var other := 0.0
		for cname in type_order:
			if shown < MAX_TYPES:
				var amt: float = type_totals[cname]
				dist_bars.append({
					"label": cname,
					"value": "%s (%d%%)" % [NumberFormat.fmt_float(amt, 0), roundi(amt / grand_total * 100.0)],
					"ratio": amt / grand_total,
					"color": _cargo_type_color(shown),
				})
				shown += 1
			else:
				other += type_totals[cname]
		if other > 0.0:
			dist_bars.append({
				"label": "Other",
				"value": "%s (%d%%)" % [NumberFormat.fmt_float(other, 0), roundi(other / grand_total * 100.0)],
				"ratio": other / grand_total,
				"color": UITheme.TEXT_MUTED,
			})
		inner_vb.add_child(_make_pie_panel("%s by cargo type" % pretty, dist_bars, portrait))

	# Per-vehicle capacity bars (used / capacity).
	var per_vehicle_bars: Array = []
	for v in vehicles:
		if not (v is Dictionary):
			continue
		var vd := v as Dictionary
		var used: float
		var cap: float
		if is_volume:
			cap = float(vd.get("cargo_capacity", 0.0))
			used = float(vd.get("total_cargo_volume", cap - float(vd.get("free_space", 0.0))))
		else:
			cap = float(vd.get("weight_capacity", 0.0))
			used = float(vd.get("total_cargo_weight", cap - float(vd.get("remaining_capacity", 0.0))))
		var r := (used / cap) if cap > 0.0 else 0.0
		per_vehicle_bars.append({
			"label": str(vd.get("name", "Vehicle")),
			"value": "%s / %s" % [NumberFormat.fmt_float(used, 0), NumberFormat.fmt_float(cap, 0)],
			"ratio": r,
			"color": _capacity_fill_color(r),
		})
	inner_vb.add_child(_make_bar_panel("Per vehicle (used / capacity)", per_vehicle_bars))

func _make_inspect_overlay(title: String) -> Dictionary:
	var portrait := _is_portrait_view()
	var panel_margin := 16 if portrait else 24

	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(backdrop)

	var dialog_panel := PanelContainer.new()
	dialog_panel.set_anchor(SIDE_LEFT,   0.0)
	dialog_panel.set_anchor(SIDE_RIGHT,  1.0)
	dialog_panel.set_anchor(SIDE_TOP,    0.0)
	dialog_panel.set_anchor(SIDE_BOTTOM, 1.0)
	dialog_panel.set_offset(SIDE_LEFT,   panel_margin)
	dialog_panel.set_offset(SIDE_RIGHT,  -panel_margin)
	dialog_panel.set_offset(SIDE_TOP,    panel_margin)
	dialog_panel.set_offset(SIDE_BOTTOM, -panel_margin)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = UITheme.METAL_BASE
	panel_sb.border_color = UITheme.METAL_EDGE
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(UITheme.RADIUS_LG)
	panel_sb.set_content_margin_all(0)
	dialog_panel.add_theme_stylebox_override("panel", panel_sb)
	overlay.add_child(dialog_panel)

	var im_val := UITheme.SPACE_LG if portrait else UITheme.SPACE_MD
	var inner_margin := MarginContainer.new()
	inner_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner_margin.add_theme_constant_override("margin_left",   im_val)
	inner_margin.add_theme_constant_override("margin_right",  im_val)
	inner_margin.add_theme_constant_override("margin_top",    im_val)
	inner_margin.add_theme_constant_override("margin_bottom", im_val)
	dialog_panel.add_child(inner_margin)

	var shell_vb := VBoxContainer.new()
	shell_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell_vb.add_theme_constant_override("separation", UITheme.SPACE_MD)
	inner_margin.add_child(shell_vb)

	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 28 if portrait else 20)
	title_lbl.add_theme_color_override("font_color", UITheme.ACCENT_BRASS)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(56 if portrait else 40, 56 if portrait else 40)
	close_btn.add_theme_font_size_override("font_size", 22 if portrait else 16)
	close_btn.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	title_row.add_child(close_btn)
	shell_vb.add_child(title_row)
	shell_vb.add_child(HSeparator.new())

	var close_fn := func():
		if is_instance_valid(overlay):
			overlay.queue_free()

	close_btn.pressed.connect(close_fn)
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close_fn.call()
	)

	var content_vb := VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vb.add_theme_constant_override("separation", UITheme.SPACE_MD)
	shell_vb.add_child(content_vb)

	return {"overlay": overlay, "content_vb": content_vb, "close_fn": close_fn}

# Titled, bordered panel shell. Returns {panel, vbox} so callers can add k/v rows or bars.
func _make_inspect_shell(title: String) -> Dictionary:
	var portrait := _is_portrait_view()
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.METAL_DARK
	sb.border_color = UITheme.METAL_EDGE
	sb.set_border_width_all(UITheme.BORDER_THIN)
	sb.set_corner_radius_all(UITheme.RADIUS_MD)
	sb.content_margin_left = UITheme.SPACE_MD
	sb.content_margin_right = UITheme.SPACE_MD
	sb.content_margin_top = UITheme.SPACE_SM
	sb.content_margin_bottom = UITheme.SPACE_SM
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", UITheme.SPACE_XS)
	panel.add_child(vb)

	if not title.is_empty():
		var hdr := Label.new()
		hdr.text = title
		hdr.add_theme_font_size_override("font_size", 22 if portrait else 15)
		hdr.add_theme_color_override("font_color", UITheme.ACCENT_BRASS)
		vb.add_child(hdr)

	return {"panel": panel, "vbox": vb}

func _make_inspect_panel(title: String, rows: Array) -> PanelContainer:
	var shell := _make_inspect_shell(title)
	var panel: PanelContainer = shell["panel"]
	var vb: VBoxContainer = shell["vbox"]

	var row_index := 0
	for r in rows:
		if not (r is Dictionary):
			continue
		var k := str(r.get("k", "")).strip_edges()
		var v := str(r.get("v", "")).strip_edges()
		if k.is_empty() or v.is_empty():
			continue
		_add_kv_row(vb, k, v, row_index, r.get("highlight", false))
		row_index += 1

	return panel

# Panel of labeled horizontal bars. `bars` = [{label, value, ratio, color}].
func _make_bar_panel(title: String, bars: Array) -> PanelContainer:
	var portrait := _is_portrait_view()
	var shell := _make_inspect_shell(title)
	var panel: PanelContainer = shell["panel"]
	var vb: VBoxContainer = shell["vbox"]
	vb.add_theme_constant_override("separation", UITheme.SPACE_SM)
	for b in bars:
		if not (b is Dictionary):
			continue
		vb.add_child(_make_inspect_bar(
			str(b.get("label", "")),
			str(b.get("value", "")),
			float(b.get("ratio", 0.0)),
			b.get("color", UITheme.ACCENT_VERDIGRIS),
			portrait))
	return panel

# A single labeled bar: header row (label left / value right) above a filled track.
func _make_inspect_bar(label_text: String, value_text: String, ratio: float, fill_color: Color, portrait: bool) -> Control:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", UITheme.SPACE_SM)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.clip_text = true
	lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	lbl.add_theme_font_size_override("font_size", 18 if portrait else 13)
	header.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	val.add_theme_font_size_override("font_size", 18 if portrait else 13)
	header.add_child(val)
	vb.add_child(header)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clamp(ratio, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 14 if portrait else 10
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := StyleBoxFlat.new()
	bg.bg_color = UITheme.METAL_BASE
	bg.set_corner_radius_all(UITheme.RADIUS_SM)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(UITheme.RADIUS_SM)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	vb.add_child(bar)
	return vb

# Pie (donut) chart with a swatch legend. `segments` = [{label, value, ratio, color}].
func _make_pie_panel(title: String, segments: Array, portrait: bool) -> PanelContainer:
	var shell := _make_inspect_shell(title)
	var panel: PanelContainer = shell["panel"]
	var vb: VBoxContainer = shell["vbox"]

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UITheme.SPACE_MD)
	vb.add_child(row)

	var pie_sz := 150.0 if portrait else 120.0
	var pie := Control.new()
	pie.custom_minimum_size = Vector2(pie_sz, pie_sz)
	pie.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Draw from the `draw` signal so we don't need a separate script on the node.
	pie.draw.connect(_draw_pie.bind(pie, segments))
	row.add_child(pie)

	var legend := VBoxContainer.new()
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	legend.add_theme_constant_override("separation", UITheme.SPACE_XS)
	for seg in segments:
		if seg is Dictionary:
			legend.add_child(_make_legend_row(
				str(seg.get("label", "")),
				str(seg.get("value", "")),
				seg.get("color", UITheme.TEXT_MUTED),
				portrait))
	row.add_child(legend)
	return panel

func _make_legend_row(label_text: String, value_text: String, swatch_color: Color, portrait: bool) -> Control:
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", UITheme.SPACE_SM)

	var swatch := ColorRect.new()
	var s := 16.0 if portrait else 12.0
	swatch.custom_minimum_size = Vector2(s, s)
	swatch.color = swatch_color
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(swatch)

	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	name_lbl.add_theme_font_size_override("font_size", 18 if portrait else 13)
	hb.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = value_text
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	val_lbl.add_theme_font_size_override("font_size", 18 if portrait else 13)
	hb.add_child(val_lbl)
	return hb

func _draw_pie(pie: Control, segments: Array) -> void:
	var sz := pie.size
	var radius: float = min(sz.x, sz.y) * 0.5 - 2.0
	if radius <= 0.0:
		return
	var center := sz * 0.5
	var start := -PI * 0.5  # begin at 12 o'clock
	for seg in segments:
		if not (seg is Dictionary):
			continue
		var ratio: float = clamp(float(seg.get("ratio", 0.0)), 0.0, 1.0)
		if ratio <= 0.0:
			continue
		var sweep := ratio * TAU
		var col: Color = seg.get("color", UITheme.TEXT_MUTED)
		var steps: int = max(2, int(ceil(sweep / 0.12)))
		var pts := PackedVector2Array()
		pts.append(center)
		for i in range(steps + 1):
			var a := start + sweep * (float(i) / float(steps))
			pts.append(center + Vector2(cos(a), sin(a)) * radius)
		pie.draw_colored_polygon(pts, col)
		start += sweep
	# Donut hole matching the panel background for a cleaner look.
	pie.draw_circle(center, radius * 0.42, UITheme.METAL_DARK)

func _add_kv_row(parent: Container, key_text: String, value_text: String, row_index: int, highlight: bool = false) -> void:
	var bg_panel := PanelContainer.new()
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var portrait := _is_portrait_view()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UITheme.ACCENT_BRASS, 0.18) if highlight else (UITheme.METAL_BASE if row_index % 2 == 0 else UITheme.METAL_DARK)
	sb.set_corner_radius_all(UITheme.RADIUS_SM)
	sb.set_content_margin_all(UITheme.SPACE_SM)
	bg_panel.add_theme_stylebox_override("panel", sb)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", UITheme.SPACE_MD)
	bg_panel.add_child(content_row)

	var key_label := Label.new()
	key_label.text = key_text + ":"
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	key_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY if highlight else UITheme.TEXT_MUTED)
	key_label.add_theme_font_size_override("font_size", 20 if portrait else 14)
	content_row.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	value_label.add_theme_font_size_override("font_size", 20 if portrait else 14)
	content_row.add_child(value_label)

	parent.add_child(bg_panel)

func _style_supply_labels() -> void:
	for lbl in [water_text_label, food_text_label, fuel_text_label]:
		if is_instance_valid(lbl):
			lbl.add_theme_font_size_override("font_size", 17)
			lbl.add_theme_font_override("font", _make_bold_font())

var _bold_font: FontVariation = null
func _make_bold_font() -> FontVariation:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = load("res://Assets/Lexend Light.ttf")
		_bold_font.variation_embolden = 0.8
	return _bold_font

func _style_cargo_bar_labels() -> void:
	for lbl in [cargo_volume_text_label, cargo_weight_text_label]:
		if is_instance_valid(lbl):
			lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
			lbl.add_theme_font_size_override("font_size", 15)
			lbl.add_theme_font_override("font", _make_bold_font())

func _add_section_headers() -> void:
	# Headers live in the stats column once the split layout exists, else the scroll vbox.
	var host: Node = _stats_column if is_instance_valid(_stats_column) else content_vbox
	if not is_instance_valid(host): return
	if host.get_node_or_null("SectionHeader_SUPPLIES") != null:
		return
	var sections := [
		[_res_stats_hbox, "📋 SUPPLIES"],
		[_perf_stats_hbox, "⚙️ PERFORMANCE"],
		[_cargo_bars_hbox, "📦 CARGO CAPACITY"],
	]
	for i in range(sections.size() - 1, -1, -1):
		var target_node = sections[i][0]
		var header_text: String = sections[i][1]
		if not is_instance_valid(target_node): continue
		if (target_node as Node).get_parent() != host: continue
		var idx: int = (target_node as Node).get_index()
		var lbl := Label.new()
		lbl.name = "SectionHeader_" + header_text.replace(" ", "_")
		lbl.text = header_text
		lbl.add_theme_color_override("font_color", UITheme.ACCENT_BRASS)
		lbl.add_theme_constant_override("outline_size", 1)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_font_override("font", _make_bold_font())
		host.add_child(lbl)
		host.move_child(lbl, idx)

func _setup_two_column_layout() -> void:
	if not is_instance_valid(content_vbox): return
	if is_instance_valid(_main_split): return  # already built

	_main_split = BoxContainer.new()
	_main_split.name = "MainSplit"
	_main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_split.add_theme_constant_override("separation", UITheme.SPACE_LG)

	_stats_column = VBoxContainer.new()
	_stats_column.name = "StatsColumn"
	_stats_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_column.size_flags_vertical = Control.SIZE_FILL
	_stats_column.add_theme_constant_override("separation", UITheme.SPACE_XS)

	_content_column = VBoxContainer.new()
	_content_column.name = "ContentColumn"
	_content_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	content_vbox.add_child(_main_split)
	_main_split.add_child(_stats_column)
	_main_split.add_child(_content_column)

	# Section headers replace the old inter-section separators.
	for sep_name in ["HSeparator2", "HSeparator3", "HSeparator4"]:
		var sep = content_vbox.get_node_or_null(sep_name)
		if is_instance_valid(sep):
			sep.queue_free()

	# Stats go left, vendor/content panel goes right.
	for n in [_res_stats_hbox, _perf_stats_hbox, _cargo_bars_hbox]:
		if is_instance_valid(n):
			n.reparent(_stats_column, false)

	# Add Convoy Visualizer placeholder to the bottom of the Stats column
	var hero_panel = PanelContainer.new()
	hero_panel.name = "ConvoyVisualizer"
	hero_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_panel.custom_minimum_size = Vector2(0, 200)
	var hero_style = StyleBoxFlat.new()
	hero_style.bg_color = Color(0.1, 0.1, 0.12, 0.8)
	hero_style.border_width_left = 1
	hero_style.border_width_right = 1
	hero_style.border_width_top = 1
	hero_style.border_width_bottom = 1
	hero_style.border_color = UITheme.METAL_EDGE
	hero_style.corner_radius_top_left = UITheme.RADIUS_MD
	hero_style.corner_radius_top_right = UITheme.RADIUS_MD
	hero_style.corner_radius_bottom_left = UITheme.RADIUS_MD
	hero_style.corner_radius_bottom_right = UITheme.RADIUS_MD
	hero_style.content_margin_left = 8.0
	hero_style.content_margin_right = 8.0
	hero_style.content_margin_top = 8.0
	hero_style.content_margin_bottom = 8.0
	hero_panel.add_theme_stylebox_override("panel", hero_style)

	# PanelContainer sizes all direct children to fill its content rect.
	# Using alignment on each label positions them visually without needing nested containers.
	var hero_label = Label.new()
	hero_label.text = "[ Convoy Visualizer ]"
	hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hero_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	hero_label.add_theme_font_size_override("font_size", 14)
	hero_panel.add_child(hero_label)

	# Expand hint in top-right — signals this will one day open a dedicated menu
	var expand_icon = Label.new()
	expand_icon.text = "⛶"
	expand_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	expand_icon.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	expand_icon.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	expand_icon.add_theme_font_size_override("font_size", 15)
	hero_panel.add_child(expand_icon)

	_stats_column.add_child(hero_panel)

	if is_instance_valid(_vendor_preview_panel_node):
		_vendor_preview_panel_node.reparent(_content_column, false)

func _upgrade_single_stat_box(box: PanelContainer, value_label: Label, key: String, compact: bool = false) -> void:
	if not is_instance_valid(box) or not is_instance_valid(value_label): return
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1 if compact else 2)
	# Let taps fall through to the box (which is wired for the breakdown modal).
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_lbl := Label.new()
	key_lbl.text = key
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	box.remove_child(value_label)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(key_lbl)
	vbox.add_child(value_label)
	box.add_child(vbox)
	key_lbl.add_theme_font_size_override("font_size", 10 if compact else 13)
	key_lbl.add_theme_font_override("font", _make_bold_font())
	value_label.add_theme_font_size_override("font_size", 17 if compact else 24)
	value_label.add_theme_font_override("font", _make_bold_font())

func _set_fixed_color_box_style(panel_node: PanelContainer, label_node: Label, _p_bg_color: Color, _p_font_color: Color):
	if not is_instance_valid(panel_node) or not is_instance_valid(label_node): return
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = UITheme.METAL_HOVER
	style_box.content_margin_left = UITheme.SPACE_SM
	style_box.content_margin_right = UITheme.SPACE_SM
	style_box.content_margin_top = UITheme.SPACE_SM
	style_box.content_margin_bottom = UITheme.SPACE_SM
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	# Brass border signals the box is tappable (opens the per-vehicle breakdown modal),
	# consistent with convoy_vehicle_menu's inspectable stat affordance.
	style_box.border_color = UITheme.ACCENT_BRASS
	style_box.corner_radius_top_left = UITheme.RADIUS_SM
	style_box.corner_radius_top_right = UITheme.RADIUS_SM
	style_box.corner_radius_bottom_right = UITheme.RADIUS_SM
	style_box.corner_radius_bottom_left = UITheme.RADIUS_SM
	style_box.shadow_color = Color(0, 0, 0, 0.35)
	style_box.shadow_size = 2
	style_box.shadow_offset = Vector2(0, 2)
	panel_node.add_theme_stylebox_override("panel", style_box)
	label_node.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)


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
	if percentage > 0.75 and percentage <= 0.95:
		progressbar_node.add_theme_color_override("font_color", COLOR_BOX_FONT)
		progressbar_node.add_theme_constant_override("outline_size", 0)
	else:
		progressbar_node.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		progressbar_node.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		progressbar_node.add_theme_constant_override("outline_size", 2)

	pass

	if is_instance_valid(back_button):
		var dsm = get_node_or_null("/root/DeviceStateManager")
		var fs = 18
		back_button.add_theme_font_size_override("font_size", fs)

	# Scale vendor tab buttons
	var dsm = get_node_or_null("/root/DeviceStateManager")
	var tab_fs = 22
	if is_instance_valid(convoy_missions_tab_button):
		convoy_missions_tab_button.add_theme_font_size_override("font_size", tab_fs)
	if is_instance_valid(settlement_missions_tab_button):
		settlement_missions_tab_button.add_theme_font_size_override("font_size", tab_fs)
	if is_instance_valid(compatible_parts_tab_button):
		compatible_parts_tab_button.add_theme_font_size_override("font_size", tab_fs)
	if is_instance_valid(journey_tab_button):
		journey_tab_button.add_theme_font_size_override("font_size", tab_fs)

	# print("ConvoyMenu: Updated font sizes. Scale: %.2f, Base: %d, Title: %d" % [scale_factor, new_font_size, new_title_font_size]) # DEBUG


func _initialize_tab_button_styles(button: Button) -> void:
	if not is_instance_valid(button): return
	button.theme_type_variation = &"TabButton"
	
	var active_style = StyleBoxFlat.new()
	active_style.bg_color = UITheme.METAL_HOVER
	active_style.border_width_bottom = 3
	active_style.border_color = COLOR_MISSION_TEXT # Use local gold constant
	active_style.content_margin_top = 8
	active_style.content_margin_bottom = 8
	
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = UITheme.METAL_BASE
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8
	
	button.add_theme_stylebox_override("pressed", active_style)
	button.add_theme_stylebox_override("focus", active_style)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", normal_style)

	# Clip the (long) tab labels so they never force a minimum width larger than the menu.
	# Without this, the tab text inflates VendorTabsHBox, which inflates the whole menu's
	# minimum width — and because MenuContainer grows in both directions, the entire menu
	# (and the nav bar) overflow off both screen edges.
	button.clip_text = true
	button.autowrap_mode = TextServer.AUTOWRAP_OFF

	var on_mobile := _is_mobile()
	if on_mobile:
		var is_portrait = get_viewport_rect().size.y > get_viewport_rect().size.x
		button.custom_minimum_size = Vector2(0.0, 80.0 if is_portrait else 52.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _get_current_meta_list() -> Array:
	match _current_vendor_tab:
		VendorTab.CONVOY_MISSIONS: return _convoy_mission_meta
		VendorTab.SETTLEMENT_MISSIONS: return _settlement_mission_meta
		VendorTab.COMPATIBLE_PARTS: return _compatible_part_meta
		_: return []

## Build a per-vehicle slot map for the current convoy: [{name, slots}] where `slots` is a
## Dictionary(slot_name -> true) derived from each vehicle's installed parts. Used to work out
## which vehicles a settlement part can be fitted to (slot match) in the Available Parts preview.
func _convoy_vehicle_slot_map() -> Array:
	var out: Array = []
	if not (convoy_data_received is Dictionary):
		return out
	var vehicles: Array = convoy_data_received.get("vehicle_details_list", convoy_data_received.get("vehicles", []))
	for veh in vehicles:
		if not (veh is Dictionary):
			continue
		var slots: Dictionary = {}
		for p in veh.get("parts", []):
			if p is Dictionary and p.get("slot") != null:
				var s := String(p.get("slot"))
				if s != "":
					slots[s] = true
		var nm := String(veh.get("name", veh.get("make_model", "Vehicle")))
		out.append({"name": nm, "slots": slots})
	return out

## Names of the convoy vehicles that expose `slot` (and can therefore accept a part in that slot).
func _vehicle_names_for_slot(slot: String, veh_slot_map: Array) -> Array:
	var names: Array = []
	if slot == "":
		return names
	for entry in veh_slot_map:
		if entry is Dictionary and (entry.get("slots", {}) as Dictionary).has(slot):
			names.append(String(entry.get("name", "")))
	return names

func _format_slot_name(raw: String) -> String:
	if raw.is_empty(): return ""
	var words := raw.replace("_", " ").split(" ")
	var out: PackedStringArray = []
	for w in words:
		if not w.is_empty():
			out.append(w.substr(0, 1).to_upper() + w.substr(1).to_lower())
	return " ".join(out)

func _format_item_meta(meta: Dictionary, tab: VendorTab) -> String:
	if meta.is_empty(): return ""
	match tab:
		VendorTab.CONVOY_MISSIONS:
			var parts: Array[String] = []
			var w: float = NumberFormat.to_f(meta.get("weight", 0), 0.0)
			var v: float = NumberFormat.to_f(meta.get("volume", 0), 0.0)
			if w > 0.0: parts.append("%.0f kg" % w)
			if v > 0.0: parts.append("%.0f L" % v)
			return "  •  ".join(PackedStringArray(parts))
		VendorTab.SETTLEMENT_MISSIONS:
			var parts: Array[String] = []
			var reward: float = NumberFormat.to_f(meta.get("unit_delivery_reward", 0), 0.0)
			if reward <= 0.0: reward = NumberFormat.to_f(meta.get("delivery_reward", 0), 0.0)
			var w: float = NumberFormat.to_f(meta.get("weight", 0), 0.0)
			if reward > 0.0: parts.append("$%.0f" % reward)
			if w > 0.0: parts.append("%.0f kg" % w)
			return "  •  ".join(PackedStringArray(parts))
		VendorTab.COMPATIBLE_PARTS:
			var pieces: Array[String] = []
			var slot_str := _format_slot_name(String(meta.get("slot", "")))
			if slot_str != "":
				pieces.append(slot_str)
			var fits_any: Variant = meta.get("fits", [])
			var fits: Array = fits_any if fits_any is Array else []
			if not fits.is_empty():
				pieces.append("Fits: " + ", ".join(PackedStringArray(fits)))
			return "  •  ".join(PackedStringArray(pieces))
		_:
			return ""

func _style_vendor_item_button(button: Control, tab_type: VendorTab) -> void:
	var accent_color: Color
	match tab_type:
		VendorTab.COMPATIBLE_PARTS:
			# Green accent for parts that fit a convoy vehicle; brass otherwise.
			var fits_count := int(button.get_meta("fits_count", 0))
			accent_color = UITheme.STATUS_GOOD if fits_count > 0 else UITheme.ACCENT_BRASS
		_:
			accent_color = UITheme.ACCENT_VERDIGRIS

	if button.has_meta("accent_strip"):
		var strip = button.get_meta("accent_strip")
		if is_instance_valid(strip):
			strip.color = accent_color

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.15, 0.15, 0.17, 1.0)
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 2
	style_normal.border_width_left = 0
	style_normal.border_width_right = 1
	style_normal.content_margin_left = 0
	style_normal.content_margin_right = 0
	style_normal.content_margin_top = 0
	style_normal.content_margin_bottom = 0
	style_normal.border_color = UITheme.METAL_EDGE
	style_normal.corner_radius_top_left = UITheme.RADIUS_SM
	style_normal.corner_radius_top_right = UITheme.RADIUS_SM
	style_normal.corner_radius_bottom_left = UITheme.RADIUS_SM
	style_normal.corner_radius_bottom_right = UITheme.RADIUS_SM
	style_normal.shadow_color = Color(0, 0, 0, 0.3)
	style_normal.shadow_size = 3
	style_normal.shadow_offset = Vector2(0, 2)

	if button is PanelContainer:
		button.add_theme_stylebox_override("panel", style_normal)
		if button.has_meta("name_label"):
			var lbl = button.get_meta("name_label")
			if is_instance_valid(lbl):
				lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	elif button is Button:
		var style_hover := style_normal.duplicate() as StyleBoxFlat
		style_hover.bg_color = UITheme.METAL_ACTIVE

		var style_pressed := style_normal.duplicate() as StyleBoxFlat
		style_pressed.bg_color = UITheme.METAL_ACTIVE
		style_pressed.content_margin_top = 1

		button.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", UITheme.ACCENT_BRASS)
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
	fill_style.bg_color = UITheme.ACCENT_VERDIGRIS
	fill_style.border_width_left = 1
	fill_style.border_width_right = 1
	fill_style.border_width_top = 1
	fill_style.border_width_bottom = 1
	fill_style.border_color = UITheme.ACCENT_VERDIGRIS.darkened(0.2)

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
		if is_instance_valid(cargo_volume_text_label):
			cargo_volume_text_label.text = "Cargo Volume: loading…"
		if is_instance_valid(cargo_weight_text_label):
			cargo_weight_text_label.text = "Cargo Weight: loading…"
		return

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
	if is_instance_valid(speed_text_label): speed_text_label.text = NumberFormat.fmt_float(top_speed, 2)
	if is_instance_valid(speed_box): _set_fixed_color_box_style(speed_box, speed_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)
	var offroad: float = float(convoy_data_received.get("offroad_capability", 0.0))
	if is_instance_valid(offroad_text_label): offroad_text_label.text = NumberFormat.fmt_float(offroad, 2)
	if is_instance_valid(offroad_box): _set_fixed_color_box_style(offroad_box, offroad_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)
	var efficiency: float = float(convoy_data_received.get("efficiency", 0.0))
	if is_instance_valid(efficiency_text_label): efficiency_text_label.text = NumberFormat.fmt_float(efficiency, 2)
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
	
	# Update navigation bar visibility (Settlement button should be hidden during journey)
	_update_navigation_bar_visibility(convoy_data_received)

	# Top Up reflects the convoy's current resources + the settlement it sits in.
	_update_top_up_button()

# --- Top Up (relocated from the settlement menu, Sprint 5) ---

func _setup_top_up_button() -> void:
	if is_instance_valid(_top_up_button):
		return
	var top_bar := get_node_or_null("MainVBox/TopBarHBox")
	if not is_instance_valid(top_bar):
		return
	# The RightSpacer only balanced the (now hidden) back button to keep the title centred; with a
	# right-side action present, drop it so Top Up can pin to the edge.
	var spacer := top_bar.get_node_or_null("RightSpacer")
	if is_instance_valid(spacer) and spacer is Control:
		(spacer as Control).visible = false
	_top_up_button = Button.new()
	_top_up_button.name = "TopUpButton"
	_top_up_button.text = "Top Up"
	_top_up_button.focus_mode = Control.FOCUS_NONE
	_top_up_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	if _is_mobile():
		_top_up_button.custom_minimum_size.y = 60.0
	_style_top_up_button()
	_top_up_button.pressed.connect(_on_top_up_button_pressed)
	top_bar.add_child(_top_up_button)
	_top_up_button.visible = false # shown only once we resolve a settlement with resource vendors

	# Money changes affect affordability / the partial-plan split.
	if is_instance_valid(_store) and _store.has_signal("user_changed") and not _store.user_changed.is_connected(_on_top_up_user_changed):
		_store.user_changed.connect(_on_top_up_user_changed)

func _style_top_up_button() -> void:
	if not is_instance_valid(_top_up_button):
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.METAL_BASE
	normal.set_border_width_all(UITheme.BORDER_THIN)
	normal.border_color = UITheme.ACCENT_BRASS # action edge
	normal.set_corner_radius_all(UITheme.RADIUS_MD)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := normal.duplicate()
	hover.bg_color = UITheme.METAL_HOVER
	var pressed := normal.duplicate()
	pressed.bg_color = UITheme.METAL_ACTIVE
	var disabled := normal.duplicate()
	disabled.bg_color = UITheme.METAL_DARK
	disabled.border_color = UITheme.METAL_EDGE.lerp(Color.BLACK, 0.3)
	for state in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed], ["focus", hover], ["disabled", disabled]]:
		_top_up_button.add_theme_stylebox_override(state[0], state[1])
	_top_up_button.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	_top_up_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_top_up_button.add_theme_color_override("font_pressed_color", UITheme.TEXT_PRIMARY)
	_top_up_button.add_theme_color_override("font_disabled_color", UITheme.TEXT_MUTED)

func _on_top_up_user_changed(_user: Dictionary) -> void:
	_update_top_up_button()

func _resolve_current_settlement() -> Dictionary:
	# The settlement the convoy is currently parked on (coord match against the cached snapshot).
	if not (convoy_data_received is Dictionary) or convoy_data_received.is_empty():
		return {}
	if not convoy_data_received.has("x") or not convoy_data_received.has("y"):
		return {}
	var cx := roundi(float(convoy_data_received.get("x", -999999.0)))
	var cy := roundi(float(convoy_data_received.get("y", -999999.0)))
	for s in _latest_all_settlements:
		if s is Dictionary:
			var sx := roundi(float((s as Dictionary).get("x", -999999.0)))
			var sy := roundi(float((s as Dictionary).get("y", -999999.0)))
			if sx == cx and sy == cy:
				return s as Dictionary
	return {}

func _get_user_money() -> float:
	if is_instance_valid(_store) and _store.has_method("get_user"):
		var u: Dictionary = _store.get_user()
		if u is Dictionary:
			return float(u.get("money", 0.0))
	if is_instance_valid(_user_service) and _user_service.has_method("get_user"):
		var u2: Dictionary = _user_service.get_user()
		if u2 is Dictionary:
			return float(u2.get("money", 0.0))
	return 0.0

func _set_top_up_state(text: String, disabled: bool, tooltip: String) -> void:
	if not is_instance_valid(_top_up_button):
		return
	_top_up_button.visible = true
	_top_up_button.text = text
	_top_up_button.disabled = disabled
	_top_up_button.tooltip_text = tooltip

func _update_top_up_button() -> void:
	if not is_instance_valid(_top_up_button):
		return
	var convoy := convoy_data_received
	if not (convoy is Dictionary) or convoy.is_empty():
		_top_up_button.visible = false
		return
	var settlement := _resolve_current_settlement()
	if settlement.is_empty() or not settlement.has("vendors"):
		# Not parked at a settlement that sells resources — hide rather than show a dead button.
		_top_up_button.visible = false
		return

	var full_plan: Dictionary = TopUpPlanner.calculate_plan(convoy, settlement)
	if (full_plan.get("planned_list", []) as Array).is_empty():
		_top_up_plan = full_plan
		_set_top_up_state("Top Up (Full)", true, "Fuel, Water and Food are already at maximum levels.")
		return

	var needed_cost: float = float(full_plan.get("total_cost", 0.0))
	var user_money: float = _get_user_money()
	var is_partial := false
	if user_money < needed_cost:
		_top_up_plan = TopUpPlanner.calculate_plan(convoy, settlement, user_money)
		is_partial = true
	else:
		_top_up_plan = full_plan

	var planned_list: Array = _top_up_plan.get("planned_list", [])
	var total_cost: float = float(_top_up_plan.get("total_cost", 0.0))
	if planned_list.is_empty() or total_cost <= 0.0001:
		_set_top_up_state("Top Up", true, "Insufficient funds to purchase any resources.")
		return

	_top_up_button.visible = true
	_top_up_button.disabled = false
	_top_up_button.text = "Top Up (Partial)" if is_partial else "Top Up"
	_top_up_button.tooltip_text = _build_top_up_tooltip(is_partial, needed_cost, user_money)

func _build_top_up_tooltip(is_partial: bool, needed_cost: float, user_money: float) -> String:
	var breakdown_lines: Array = []
	var allocations_by_res: Dictionary = {}
	for alloc in _top_up_plan.get("allocations", []):
		var r := String(alloc.get("res", ""))
		if r == "":
			continue
		if not allocations_by_res.has(r):
			allocations_by_res[r] = []
		allocations_by_res[r].append(alloc)
	for r in allocations_by_res.keys():
		var group: Array = allocations_by_res[r]
		group.sort_custom(func(a, b): return float(a.price) < float(b.price))
		var res_total_qty := 0
		var res_total_cost := 0.0
		breakdown_lines.append(String(r).capitalize() + ":")
		for g in group:
			var qty_i := int(g.get("quantity", 0))
			var price_i := float(g.get("price", 0.0))
			var vendor_name := String(g.get("vendor_name", "?"))
			var sub_i := float(qty_i) * price_i
			res_total_qty += qty_i
			res_total_cost += sub_i
			breakdown_lines.append("  %s: %d @ $%.2f = $%.0f" % [vendor_name, qty_i, price_i, sub_i])
		breakdown_lines.append("  Subtotal %s: %d = $%.0f" % [r, res_total_qty, res_total_cost])
	breakdown_lines.append("Total: $%.0f" % float(_top_up_plan.get("total_cost", 0.0)))
	if is_partial:
		var missing: float = max(0.0, needed_cost - user_money)
		breakdown_lines.append("Partial Top Up (Need $%.0f more for full)." % missing)
	return "Top Up Plan:\n" + "\n".join(breakdown_lines)

func _on_top_up_button_pressed() -> void:
	if _top_up_plan.is_empty() or (_top_up_plan.get("resources", {}) as Dictionary).is_empty():
		return
	var convoy_uuid := String(convoy_data_received.get("convoy_id", convoy_data_received.get("id", "")))
	if convoy_uuid.is_empty() or not is_instance_valid(_api):
		return
	# Execute purchases individually (one PATCH per allocation) from the current plan snapshot.
	for alloc in _top_up_plan.get("allocations", []):
		var res := String(alloc.get("res", ""))
		var vendor_id := String(alloc.get("vendor_id", ""))
		var send_qty := int(alloc.get("quantity", 0))
		if res == "" or vendor_id.is_empty() or send_qty <= 0:
			continue
		if _debug_convoy_menu:
			print("[ConvoyMenu][TopUp] Buying %d %s from vendor %s (price=%.2f) convoy=%s" % [send_qty, res, vendor_id, float(alloc.get("price", 0.0)), convoy_uuid])
		_api.buy_resource(vendor_id, convoy_uuid, res, float(send_qty))
	# Authoritative refreshes via services; UI updates flow back through Store/Hub → _update_ui.
	if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(convoy_uuid)
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()
	if is_instance_valid(_top_up_button):
		_top_up_button.disabled = true
		_top_up_button.text = "Topping Up…"

func _enforce_label_wrapping(node: Node):
	if node is Label:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.custom_minimum_size.x = 10 # Allow it to shrink very small if needed
		# Ensure it doesn't force its parent to expand to unwrapped text size
		if "size_flags_horizontal" in node:
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in node.get_children():
		_enforce_label_wrapping(child)
