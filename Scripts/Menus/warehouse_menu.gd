extends MenuBase

const ItemsData = preload("res://Scripts/Data/Items.gd")

@onready var title_label: Label = $MainVBox/TopBarHBox/TitleLabel
@onready var buy_button: Button = $MainVBox/TopBarHBox/BuyButton
@onready var back_button: Button = $MainVBox/BackButton
@onready var info_label: Label = $MainVBox/Body/InfoLabel
@onready var owned_tabs: TabContainer = $MainVBox/Body/OwnedTabs
@onready var body_vbox: VBoxContainer = $MainVBox/Body
@onready var main_vbox: VBoxContainer = $MainVBox
@onready var top_bar_hbox: HBoxContainer = $MainVBox/TopBarHBox
@onready var summary_label: Label = $MainVBox/Body/OwnedTabs/Overview/SummaryLabel
@onready var expand_cargo_btn: Button = $MainVBox/Body/OwnedTabs/Overview/ExpandCargoHBox/ExpandCargoBtn
@onready var expand_vehicle_btn: Button = $MainVBox/Body/OwnedTabs/Overview/ExpandVehicleHBox/ExpandVehicleBtn
@onready var cargo_store_dd: OptionButton = $MainVBox/Body/OwnedTabs/Cargo/CargoStoreHBox/CargoStoreDropdown
@onready var cargo_qty_store: SpinBox = $MainVBox/Body/OwnedTabs/Cargo/CargoStoreHBox/CargoQtyStore
@onready var store_cargo_btn: Button = $MainVBox/Body/OwnedTabs/Cargo/CargoStoreHBox/StoreCargoBtn
@onready var cargo_retrieve_dd: OptionButton = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/CargoRetrieveDropdown
@onready var cargo_retrieve_vehicle_dd: OptionButton = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/CargoRetrieveVehicleDropdown
@onready var cargo_qty_retrieve: SpinBox = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/CargoQtyRetrieve
@onready var retrieve_cargo_btn: Button = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/RetrieveCargoBtn
@onready var cargo_usage_label: Label = $MainVBox/Body/OwnedTabs/Cargo/CargoUsageLabel
@onready var cargo_grid: GridContainer = $MainVBox/Body/OwnedTabs/Cargo/CargoInventoryPanel/CargoGridScroll/CargoGrid
@onready var cargo_inventory_panel: Control = $MainVBox/Body/OwnedTabs/Cargo/CargoInventoryPanel
@onready var cargo_grid_scroll: ScrollContainer = $MainVBox/Body/OwnedTabs/Cargo/CargoInventoryPanel/CargoGridScroll
@onready var vehicle_store_dd: OptionButton = $MainVBox/Body/OwnedTabs/Vehicles/VehicleStoreHBox/VehicleStoreDropdown
@onready var store_vehicle_btn: Button = $MainVBox/Body/OwnedTabs/Vehicles/VehicleStoreHBox/StoreVehicleBtn
@onready var vehicle_retrieve_dd: OptionButton = $MainVBox/Body/OwnedTabs/Vehicles/VehicleRetrieveHBox/VehicleRetrieveDropdown
@onready var retrieve_vehicle_btn: Button = $MainVBox/Body/OwnedTabs/Vehicles/VehicleRetrieveHBox/RetrieveVehicleBtn
@onready var spawn_vehicle_dd: OptionButton = $MainVBox/Body/OwnedTabs/Vehicles/SpawnHBox/SpawnVehicleDropdown
@onready var spawn_name_input: LineEdit = $MainVBox/Body/OwnedTabs/Vehicles/SpawnHBox/SpawnNameInput
@onready var spawn_convoy_btn: Button = $MainVBox/Body/OwnedTabs/Vehicles/SpawnHBox/SpawnConvoyBtn
@onready var vehicle_grid: GridContainer = $MainVBox/Body/OwnedTabs/Vehicles/VehicleInventoryPanel/VehicleGridScroll/VehicleGrid
@onready var vehicle_inventory_panel: Control = $MainVBox/Body/OwnedTabs/Vehicles/VehicleInventoryPanel
@onready var vehicle_grid_scroll: ScrollContainer = $MainVBox/Body/OwnedTabs/Vehicles/VehicleInventoryPanel/VehicleGridScroll
@onready var expand_cargo_label: Label = $MainVBox/Body/OwnedTabs/Overview/ExpandCargoHBox/ExpandCargoLabel
@onready var expand_vehicle_label: Label = $MainVBox/Body/OwnedTabs/Overview/ExpandVehicleHBox/ExpandVehicleLabel
@onready var overview_cargo_bar: ProgressBar = $MainVBox/Body/OwnedTabs/Overview/OverviewCargoHBox/OverviewCargoBar
@onready var overview_vehicle_bar: ProgressBar = $MainVBox/Body/OwnedTabs/Overview/OverviewVehicleHBox/OverviewVehicleBar
@onready var overview_cargo_label: Label = $MainVBox/Body/OwnedTabs/Overview/OverviewCargoHBox/OverviewCargoLabel
@onready var overview_vehicle_label: Label = $MainVBox/Body/OwnedTabs/Overview/OverviewVehicleHBox/OverviewVehicleLabel

var _convoy_data: Dictionary
var _settlement: Dictionary
var _warehouse: Dictionary
var _warehouse_service: Node
var _hub: Node
var _is_loading: bool = false
var _pending_action_refresh: bool = false
var _last_known_wid: String = "" # Remember last successfully loaded warehouse_id for unconditional refresh after actions
var _upgrade_in_progress: bool = false # When true, disable upgrade buttons until fresh warehouse data arrives
var _pre_expand_cargo_cap: int = -1
var _pre_expand_vehicle_cap: int = -1
var _last_expand_type: String = "" # "cargo" or "vehicle" when an expansion attempt is active
var _last_expand_used_json: bool = false # Tracks whether we've already retried with JSON body
var _optimistic_money_active: bool = false
var _optimistic_money_before: float = 0.0
var _optimistic_money_after: float = 0.0

var _info_card: PanelContainer = null
var _bg_rect: ColorRect = null
var _content_frame: PanelContainer = null

var _post_buy_refresh_attempts_left: int = 0
var _post_buy_refresh_in_flight: bool = false

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _user_service: Node = get_node_or_null("/root/UserService")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")


# Track last-seen dropdown contents to avoid reshuffling
var _last_cargo_store_ids: Array[String] = []
var _last_cargo_retrieve_ids: Array[String] = []
var _last_vehicle_store_ids: Array[String] = []
var _last_vehicle_retrieve_ids: Array[String] = []
var _last_spawn_vehicle_ids: Array[String] = []

const WAREHOUSE_PRICES := {
	"dome": 5000000,
	"city-state": 4000000,
	"city": 3000000,
	"town": 1000000,
	"village": 500000,
	"military_base": null,
}

const WAREHOUSE_UPGRADE_PRICES := {
	"dome": 250000,
	"city-state": 200000,
	"city": 150000,
	"town": 75000,
	"village": 50000,
	"military_base": null,
}

func _ready():
	print("[WarehouseMenu] _ready()")
	_warehouse_service = get_node_or_null("/root/WarehouseService")
	_hub = get_node_or_null("/root/SignalHub")
	_ensure_inventory_headers()
	# Subscribe to canonical snapshots so money/convoy cargo stay current.
	if is_instance_valid(_store):
		if _store.has_signal("user_changed") and not _store.user_changed.is_connected(_on_store_user_changed):
			_store.user_changed.connect(_on_store_user_changed)
		if _store.has_signal("convoys_changed") and not _store.convoys_changed.is_connected(_on_store_convoys_changed):
			_store.convoys_changed.connect(_on_store_convoys_changed)
		if _store.has_signal("map_changed") and not _store.map_changed.is_connected(_on_store_map_changed):
			_store.map_changed.connect(_on_store_map_changed)
	# Remove top title per request
	if is_instance_valid(title_label):
		title_label.visible = false
		title_label.text = ""
	# UI polish (buy state card + button styling)
	_style_buy_menu_ui()
	_tune_inventory_panels_layout()
	# Diagnostics: verify expand buttons and signal connections
	if is_instance_valid(expand_cargo_btn):
		print("[WarehouseMenu][Diag] Found expand_cargo_btn path=", expand_cargo_btn.get_path(), " disabled=", expand_cargo_btn.disabled)
	else:
		print("[WarehouseMenu][Diag][WARN] expand_cargo_btn NOT found at expected path.")
	if is_instance_valid(expand_vehicle_btn):
		print("[WarehouseMenu][Diag] Found expand_vehicle_btn path=", expand_vehicle_btn.get_path(), " disabled=", expand_vehicle_btn.disabled)
	else:
		print("[WarehouseMenu][Diag][WARN] expand_vehicle_btn NOT found at expected path.")
	# Attach raw press test callbacks (secondary) to confirm signal emission even if handler not firing
	if is_instance_valid(expand_cargo_btn) and not expand_cargo_btn.pressed.is_connected(_diag_expand_cargo_pressed):
		expand_cargo_btn.pressed.connect(_diag_expand_cargo_pressed)
	if is_instance_valid(expand_vehicle_btn) and not expand_vehicle_btn.pressed.is_connected(_diag_expand_vehicle_pressed):
		expand_vehicle_btn.pressed.connect(_diag_expand_vehicle_pressed)
	# Schedule a deferred re-check to ensure connections after scene tree stabilization
	call_deferred("_post_ready_expand_diag")
	if is_instance_valid(back_button):
		back_button.pressed.connect(func(): emit_signal("back_requested"))
	if is_instance_valid(buy_button):
		buy_button.pressed.connect(_on_buy_pressed)
	# Selection change hooks to enforce quantity limits
	if is_instance_valid(cargo_store_dd):
		cargo_store_dd.item_selected.connect(func(_idx): _update_store_qty_limit())
	if is_instance_valid(cargo_retrieve_dd):
		cargo_retrieve_dd.item_selected.connect(func(_idx): _update_retrieve_qty_limit())
	# Hook Hub signals (transport → services → hub)
	if is_instance_valid(_hub):
		if _hub.has_signal("warehouse_created") and not _hub.warehouse_created.is_connected(_on_hub_warehouse_created):
			_hub.warehouse_created.connect(_on_hub_warehouse_created)
		if _hub.has_signal("warehouse_updated") and not _hub.warehouse_updated.is_connected(_on_hub_warehouse_received):
			_hub.warehouse_updated.connect(_on_hub_warehouse_received)
		if _hub.has_signal("warehouse_expanded") and not _hub.warehouse_expanded.is_connected(_on_hub_warehouse_action):
			_hub.warehouse_expanded.connect(_on_hub_warehouse_action)
		if _hub.has_signal("warehouse_cargo_stored") and not _hub.warehouse_cargo_stored.is_connected(_on_hub_warehouse_action):
			_hub.warehouse_cargo_stored.connect(_on_hub_warehouse_action)
		if _hub.has_signal("warehouse_cargo_retrieved") and not _hub.warehouse_cargo_retrieved.is_connected(_on_hub_warehouse_action):
			_hub.warehouse_cargo_retrieved.connect(_on_hub_warehouse_action)
		if _hub.has_signal("warehouse_vehicle_stored") and not _hub.warehouse_vehicle_stored.is_connected(_on_hub_warehouse_action):
			_hub.warehouse_vehicle_stored.connect(_on_hub_warehouse_action)
		if _hub.has_signal("warehouse_vehicle_retrieved") and not _hub.warehouse_vehicle_retrieved.is_connected(_on_hub_warehouse_action):
			_hub.warehouse_vehicle_retrieved.connect(_on_hub_warehouse_action)
		if _hub.has_signal("warehouse_convoy_spawned") and not _hub.warehouse_convoy_spawned.is_connected(_on_hub_warehouse_action):
			_hub.warehouse_convoy_spawned.connect(_on_hub_warehouse_action)
		if _hub.has_signal("error_occurred") and not _hub.error_occurred.is_connected(_on_hub_error):
			_hub.error_occurred.connect(_on_hub_error)

	# Wire UI buttons
	if is_instance_valid(expand_cargo_btn):
		# Add gui_input logging even if disabled to see attempted clicks
		if not expand_cargo_btn.gui_input.is_connected(_on_expand_button_gui_input):
			expand_cargo_btn.gui_input.connect(_on_expand_button_gui_input.bind("cargo"))
		expand_cargo_btn.pressed.connect(_on_expand_cargo)
	if is_instance_valid(expand_vehicle_btn):
		if not expand_vehicle_btn.gui_input.is_connected(_on_expand_button_gui_input):
			expand_vehicle_btn.gui_input.connect(_on_expand_button_gui_input.bind("vehicle"))
		expand_vehicle_btn.pressed.connect(_on_expand_vehicle)
	if is_instance_valid(store_cargo_btn):
		store_cargo_btn.pressed.connect(_on_store_cargo)
	if is_instance_valid(retrieve_cargo_btn):
		retrieve_cargo_btn.pressed.connect(_on_retrieve_cargo)
	if is_instance_valid(store_vehicle_btn):
		store_vehicle_btn.pressed.connect(_on_store_vehicle)
	if is_instance_valid(retrieve_vehicle_btn):
		retrieve_vehicle_btn.pressed.connect(_on_retrieve_vehicle)
	if is_instance_valid(spawn_convoy_btn):
		spawn_convoy_btn.pressed.connect(_on_spawn_convoy)
		print("[WarehouseMenu][Debug] Connected spawn_convoy_btn pressed signal path=", spawn_convoy_btn.get_path())
	_update_ui()

func _tune_inventory_panels_layout() -> void:
	# The scene marks inventory panels as SIZE_EXPAND_FILL, which makes a huge empty
	# box when the grid has only a few entries. Prefer content-sized panels.
	for ctrl in [cargo_inventory_panel, cargo_grid_scroll, vehicle_inventory_panel, vehicle_grid_scroll]:
		if ctrl is Control and is_instance_valid(ctrl):
			# Expand horizontally but not vertically.
			(ctrl as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			(ctrl as Control).size_flags_vertical = Control.SIZE_FILL

func _style_buy_menu_ui() -> void:
	# Improve contrast between menu background and UI surfaces.
	_ensure_background_layers()
	_style_containers()
	_style_form_controls()
	# Make the "no warehouse yet" state feel like a real menu instead of raw text.
	_ensure_info_card_wrapper()
	_style_primary_button(buy_button, Color(0.35, 0.65, 1.0, 1.0))
	_style_secondary_button(back_button)
	_style_info_label(info_label)
	# Tabs are the "owned" state; keep label card hidden when tabs show.
	if is_instance_valid(owned_tabs) and is_instance_valid(info_label):
		# Ensure the info label expands nicely when visible
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Style owned-state panels too, so tabs and inventory panels read as distinct surfaces.
	_style_panel_surface(owned_tabs)
	_style_panel_surface(cargo_inventory_panel)
	_style_panel_surface(vehicle_inventory_panel)

func _ensure_background_layers() -> void:
	# Add a background and a framed content area behind the VBox.
	# This keeps UI readable even on dark global themes.
	if not is_inside_tree():
		return
	# Background
	if not (is_instance_valid(_bg_rect) and _bg_rect.is_inside_tree()):
		var bg := ColorRect.new()
		bg.name = "WarehouseBackground"
		bg.color = Color(0.02, 0.03, 0.04, 1.0)
		bg.anchor_left = 0
		bg.anchor_top = 0
		bg.anchor_right = 1
		bg.anchor_bottom = 1
		bg.offset_left = 0
		bg.offset_top = 0
		bg.offset_right = 0
		bg.offset_bottom = 0
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.z_index = -100
		add_child(bg)
		move_child(bg, 0)
		_bg_rect = bg
	# Content frame
	if not (is_instance_valid(_content_frame) and _content_frame.is_inside_tree()):
		var frame := PanelContainer.new()
		frame.name = "WarehouseContentFrame"
		frame.anchor_left = 0
		frame.anchor_top = 0
		frame.anchor_right = 1
		frame.anchor_bottom = 1
		frame.offset_left = 10
		frame.offset_top = 10
		frame.offset_right = -10
		frame.offset_bottom = -10
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.z_index = -50
		var sb := StyleBoxFlat.new()
		# Slightly lighter than background so the content area pops.
		sb.bg_color = Color(0.06, 0.07, 0.09, 0.95)
		sb.border_color = Color(0.35, 0.42, 0.55, 0.9)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 12
		sb.corner_radius_top_right = 12
		sb.corner_radius_bottom_left = 12
		sb.corner_radius_bottom_right = 12
		sb.shadow_color = Color(0, 0, 0, 0.6)
		sb.shadow_size = 10
		frame.add_theme_stylebox_override("panel", sb)
		add_child(frame)
		# Keep frame behind MainVBox (which is expected to be child index > 0).
		move_child(frame, 1)
		_content_frame = frame
	# Add some padding so content doesn't touch the frame border.
	if is_instance_valid(main_vbox):
		main_vbox.offset_left = 18
		main_vbox.offset_top = 18
		main_vbox.offset_right = -18
		main_vbox.offset_bottom = -18

func _style_containers() -> void:
	if is_instance_valid(main_vbox):
		main_vbox.add_theme_constant_override("separation", 12)
	if is_instance_valid(body_vbox):
		body_vbox.add_theme_constant_override("separation", 10)
		# Key fix: don't let Body expand to consume all remaining height.
		# Otherwise it creates a huge empty gap between the tabs/content and the Back button.
		body_vbox.size_flags_vertical = Control.SIZE_FILL
	if is_instance_valid(top_bar_hbox):
		top_bar_hbox.add_theme_constant_override("separation", 10)
		# Improve top bar readability
		top_bar_hbox.add_theme_constant_override("margin_left", 2)
	# Tabs/content should be content-sized by default; internal scroll areas handle overflow.
	if is_instance_valid(owned_tabs):
		owned_tabs.size_flags_vertical = Control.SIZE_FILL
	if is_instance_valid(info_label):
		info_label.size_flags_vertical = Control.SIZE_FILL
	# Back button sits at bottom; give it breathing room
	if is_instance_valid(back_button):
		back_button.add_theme_constant_override("hseparation", 8)

func _style_panel_surface(ctrl: Control) -> void:
	# Apply a consistent panel surface style to containers that draw a panel.
	if not is_instance_valid(ctrl):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	sb.border_color = Color(0.38, 0.46, 0.60, 0.9)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	ctrl.add_theme_stylebox_override("panel", sb)

func _style_form_controls() -> void:
	# Dropdowns/inputs need to pop against dark panels.
	_style_option_button(cargo_store_dd)
	_style_option_button(cargo_retrieve_dd)
	_style_option_button(cargo_retrieve_vehicle_dd)
	_style_option_button(vehicle_store_dd)
	_style_option_button(vehicle_retrieve_dd)
	_style_option_button(spawn_vehicle_dd)
	_style_spin_box(cargo_qty_store)
	_style_spin_box(cargo_qty_retrieve)
	_style_line_edit(spawn_name_input)

func _style_option_button(ob: OptionButton) -> void:
	if not is_instance_valid(ob):
		return
	ob.custom_minimum_size = Vector2(0, 40)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_theme_font_size_override("font_size", 16)
	ob.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	ob.add_theme_color_override("font_color_disabled", Color(0.60, 0.62, 0.68, 1.0))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.18, 1.0)
	normal.border_color = Color(0.55, 0.68, 0.88, 0.95)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.shadow_color = Color(0, 0, 0, 0.35)
	normal.shadow_size = 3
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		normal.set_content_margin(side, 10)

	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.18, 0.24, 1.0)
	hover.border_color = Color(0.70, 0.82, 1.0, 1.0)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.10, 0.11, 0.15, 1.0)
	pressed.border_color = Color(0.45, 0.58, 0.78, 1.0)

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.10, 0.10, 0.12, 1.0)
	disabled.border_color = Color(0.25, 0.28, 0.34, 1.0)
	disabled.shadow_size = 0

	ob.add_theme_stylebox_override("normal", normal)
	ob.add_theme_stylebox_override("hover", hover)
	ob.add_theme_stylebox_override("pressed", pressed)
	ob.add_theme_stylebox_override("disabled", disabled)
	ob.add_theme_stylebox_override("focus", hover)

	# Also style the dropdown list popup for readability.
	var popup := ob.get_popup()
	if popup is PopupMenu:
		_style_popup_menu(popup)

func _style_popup_menu(pm: PopupMenu) -> void:
	if not is_instance_valid(pm):
		return
	pm.add_theme_font_size_override("font_size", 16)
	pm.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	pm.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	pm.add_theme_color_override("font_disabled_color", Color(0.60, 0.62, 0.68, 1.0))

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	panel.border_color = Color(0.55, 0.68, 0.88, 0.9)
	panel.border_width_left = 1
	panel.border_width_right = 1
	panel.border_width_top = 1
	panel.border_width_bottom = 1
	panel.corner_radius_top_left = 10
	panel.corner_radius_top_right = 10
	panel.corner_radius_bottom_left = 10
	panel.corner_radius_bottom_right = 10
	panel.shadow_color = Color(0, 0, 0, 0.65)
	panel.shadow_size = 10
	pm.add_theme_stylebox_override("panel", panel)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.20, 0.28, 0.40, 1.0)
	hover.corner_radius_top_left = 6
	hover.corner_radius_top_right = 6
	hover.corner_radius_bottom_left = 6
	hover.corner_radius_bottom_right = 6
	pm.add_theme_stylebox_override("hover", hover)

func _style_line_edit(le: LineEdit) -> void:
	if not is_instance_valid(le):
		return
	le.custom_minimum_size = Vector2(le.custom_minimum_size.x, 40)
	le.add_theme_font_size_override("font_size", 16)
	le.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	le.add_theme_color_override("placeholder_color", Color(0.70, 0.74, 0.82, 0.85))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 1.0)
	sb.border_color = Color(0.55, 0.68, 0.88, 0.75)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_content_margin(side, 10)
	le.add_theme_stylebox_override("normal", sb)
	var focus := sb.duplicate()
	focus.border_color = Color(0.75, 0.88, 1.0, 1.0)
	le.add_theme_stylebox_override("focus", focus)

func _style_spin_box(sb: SpinBox) -> void:
	if not is_instance_valid(sb):
		return
	sb.custom_minimum_size = Vector2(0, 40)
	# SpinBox's internal LineEdit draws the background; style it for contrast.
	var le: LineEdit = sb.get_line_edit()
	if is_instance_valid(le):
		_style_line_edit(le)

func _ensure_info_card_wrapper() -> void:
	if not is_instance_valid(info_label) or not is_instance_valid(body_vbox):
		return
	# If we've already wrapped it, nothing to do.
	if is_instance_valid(_info_card) and _info_card.is_inside_tree():
		return
	# If the scene already contains an InfoCard (future-proof), reuse it.
	var existing := body_vbox.get_node_or_null("InfoCard")
	if existing is PanelContainer:
		_info_card = existing
		return
	# Wrap InfoLabel in a PanelContainer+MarginContainer to get padding + background.
	var original_parent: Node = info_label.get_parent()
	if original_parent != body_vbox:
		# Unexpected structure; bail rather than reparenting aggressively.
		return
	var insert_index := info_label.get_index()
	body_vbox.remove_child(info_label)

	var card := PanelContainer.new()
	card.name = "InfoCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 150)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	panel_sb.border_color = Color(0.35, 0.45, 0.60, 0.9)
	panel_sb.border_width_left = 1
	panel_sb.border_width_right = 1
	panel_sb.border_width_top = 1
	panel_sb.border_width_bottom = 1
	panel_sb.corner_radius_top_left = 10
	panel_sb.corner_radius_top_right = 10
	panel_sb.corner_radius_bottom_left = 10
	panel_sb.corner_radius_bottom_right = 10
	panel_sb.shadow_color = Color(0, 0, 0, 0.55)
	panel_sb.shadow_size = 6
	card.add_theme_stylebox_override("panel", panel_sb)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)

	card.add_child(margin)
	margin.add_child(info_label)

	body_vbox.add_child(card)
	body_vbox.move_child(card, insert_index)
	_info_card = card

func _style_info_label(lbl: Label) -> void:
	if not is_instance_valid(lbl):
		return
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	lbl.add_theme_constant_override("shadow_outline_size", 0)
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 1)

func _style_primary_button(btn: Button, accent: Color) -> void:
	if not is_instance_valid(btn):
		return
	btn.custom_minimum_size = Vector2(170, 44)
	btn.focus_mode = Control.FOCUS_ALL

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(accent.r * 0.70, accent.g * 0.70, accent.b * 0.70, 1.0)
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.95)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.shadow_color = Color(0, 0, 0, 0.55)
	normal.shadow_size = 5

	var hover := normal.duplicate()
	hover.bg_color = Color(accent.r * 0.78, accent.g * 0.78, accent.b * 0.78, 1.0)
	hover.border_color = Color(accent.r, accent.g, accent.b, 1.0)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(accent.r * 0.60, accent.g * 0.60, accent.b * 0.60, 1.0)
	pressed.shadow_size = 2

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.12, 0.12, 0.14, 1.0)
	disabled.border_color = Color(0.22, 0.22, 0.26, 1.0)
	disabled.shadow_size = 0

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	btn.add_theme_color_override("font_color_hover", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_color_pressed", Color(0.90, 0.94, 1.0, 1.0))
	btn.add_theme_color_override("font_color_disabled", Color(0.60, 0.62, 0.68, 1.0))
	btn.add_theme_font_size_override("font_size", 18)

func _style_secondary_button(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	btn.custom_minimum_size = Vector2(0, 42)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.13, 0.16, 1.0)
	normal.border_color = Color(0.32, 0.36, 0.44, 1.0)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8

	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.17, 0.21, 1.0)
	hover.border_color = Color(0.45, 0.50, 0.62, 1.0)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.10, 0.10, 0.12, 1.0)
	pressed.border_color = Color(0.28, 0.32, 0.40, 1.0)

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.10, 0.10, 0.11, 1.0)
	disabled.border_color = Color(0.20, 0.20, 0.22, 1.0)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	btn.add_theme_color_override("font_color_disabled", Color(0.60, 0.62, 0.68, 1.0))
	btn.add_theme_font_size_override("font_size", 16)

func _set_expand_buttons_enabled(enabled: bool) -> void:
	# Central helper so we can uniformly toggle & log state
	if is_instance_valid(expand_cargo_btn):
		expand_cargo_btn.disabled = not enabled
	if is_instance_valid(expand_vehicle_btn):
		expand_vehicle_btn.disabled = not enabled
	print("[WarehouseMenu][UpgradeState] set_expand_buttons_enabled enabled=", enabled, " in_progress=", _upgrade_in_progress)

func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
	if data_or_id is Dictionary:
		convoy_id = String((data_or_id as Dictionary).get("convoy_id", (data_or_id as Dictionary).get("id", "")))
	else:
		convoy_id = String(data_or_id)
	# Guard: avoid expensive re-initialization if convoy and settlement unchanged
	var incoming_cid := str((data_or_id as Dictionary).get("convoy_id", "")) if data_or_id is Dictionary else ""
	var existing_cid := str(_convoy_data.get("convoy_id", "")) if (_convoy_data is Dictionary) else ""
	var incoming_sett: Variant = (data_or_id as Dictionary).get("settlement", null) if data_or_id is Dictionary else null
	var incoming_sett_id: String = ""
	if typeof(incoming_sett) == TYPE_DICTIONARY:
		incoming_sett_id = str(incoming_sett.get("sett_id", ""))
	var existing_sett_id := str(_settlement.get("sett_id", "")) if (_settlement is Dictionary) else ""
	if incoming_cid != "" and existing_cid == incoming_cid and incoming_sett_id != "" and existing_sett_id == incoming_sett_id:
		# Still refresh dropdowns lightly (convoy cargo may have changed), but skip heavy logging spam
		_populate_dropdowns()
		return
	_convoy_data = (data_or_id as Dictionary).duplicate(true) if data_or_id is Dictionary else {}
	var incoming_settlement = (data_or_id as Dictionary).get("settlement", null) if data_or_id is Dictionary else null
	if typeof(incoming_settlement) == TYPE_DICTIONARY and not (incoming_settlement as Dictionary).is_empty():
		_settlement = (incoming_settlement as Dictionary).duplicate(true)
	else:
		# Try to resolve from settlement_name or coordinates; if unresolved, keep previous _settlement
		var resolved := _resolve_settlement_from_data(_convoy_data)
		if not resolved.is_empty():
			_settlement = resolved
	# Don't nuke existing settlement if nothing resolved
	print("[WarehouseMenu] initialize_with_data name=", String(_settlement.get("name", _convoy_data.get("settlement_name", ""))), " sett_type_resolved=", _get_settlement_type())
	_update_ui(_convoy_data)
	super.initialize_with_data(data_or_id, extra_arg)
	_try_load_warehouse_for_settlement()
	_populate_dropdowns() # initial (may be empty until data arrives)

func _update_ui(convoy: Dictionary = {}):
	# MenuBase passes an authoritative convoy snapshot when opened by convoy_id.
	# Consume it so we can resolve settlement/type/price reliably.
	if typeof(convoy) == TYPE_DICTIONARY and not (convoy as Dictionary).is_empty():
		_convoy_data = (convoy as Dictionary).duplicate(true)
		if (_settlement is Dictionary) and _settlement.is_empty():
			var resolved := _resolve_settlement_from_data(_convoy_data)
			if not resolved.is_empty():
				_settlement = resolved
	# Ensure we always have the best-effort settlement ID cached for buy actions.
	_get_settlement_id()
	var sett_name := String(_settlement.get("name", _convoy_data.get("settlement_name", "")))
	if is_instance_valid(title_label):
		if sett_name != "":
			title_label.text = "Warehouse — %s" % sett_name
		else:
			title_label.text = "Warehouse"
	# Basic state: if we have a warehouse object, show summary; else show buy CTA
	if _warehouse is Dictionary and not _warehouse.is_empty():
		if is_instance_valid(buy_button):
			buy_button.visible = false
		_set_info_area_visible(false)
		# Show the tabs and fill the summary label
		if is_instance_valid(owned_tabs):
			owned_tabs.visible = true
		if is_instance_valid(summary_label):
			summary_label.text = _format_warehouse_summary(_warehouse)
		# Now that we have warehouse details, repopulate dropdowns that depend on it
		_populate_dropdowns()
		_update_expand_buttons()
		_update_upgrade_labels()
		_update_cargo_usage_label()
		_update_overview_bars()
		_render_cargo_grid()
		_render_vehicle_grid()
		print("[WarehouseMenu] Owned state. sett_type=", _get_settlement_type())
		if is_instance_valid(info_label):
			info_label.text = ""
		_update_upgrade_labels()
	else:
		if is_instance_valid(buy_button):
			buy_button.visible = not _is_loading
		if is_instance_valid(owned_tabs):
			owned_tabs.visible = false
		_set_info_area_visible(true)
		if is_instance_valid(info_label):
			if _is_loading:
				info_label.text = "Loading warehouse..."
			else:
				var price := _get_warehouse_price()
				var funds := _get_user_money()
				var buy_available := _is_buy_available()
				var can_resolve_settlement := _get_settlement_id() != ""
				var price_text := ""
				if price > 0:
					price_text = NumberFormat.format_money(price)
				elif not buy_available:
					price_text = "N/A"
				else:
					# Previously showed "TBD" when settlement type wasn't resolved.
					# Prefer a clearer state and avoid enabling buy until settlement is known.
					price_text = "…" if not can_resolve_settlement else "Unknown"
				var funds_text := NumberFormat.format_money(funds)
				info_label.text = "No warehouse here yet.\nPrice: %s\nYour funds: %s" % [price_text, funds_text]
				print("[WarehouseMenu] No warehouse. sett_type=", _get_settlement_type(), " price=", price, " buy_available=", buy_available)
				# Update Buy button text and enabled state based on availability and affordability
				if is_instance_valid(buy_button):
					if not buy_available:
						buy_button.text = "Buy"
						buy_button.disabled = true
						buy_button.tooltip_text = "Warehouses are not available in this settlement."
					elif not can_resolve_settlement:
						buy_button.text = "Buy"
						buy_button.disabled = true
						buy_button.tooltip_text = "Loading settlement info…"
					elif price > 0:
						buy_button.text = "Buy (%s)" % price_text
						var can_afford := funds + 0.0001 >= float(price)
						buy_button.disabled = not can_afford
						var tip := "Price: %s\nYour funds: %s" % [price_text, funds_text]
						if not can_afford:
							tip += "\nInsufficient funds."
						buy_button.tooltip_text = tip
					else:
						buy_button.text = "Buy"
						buy_button.disabled = false
						buy_button.tooltip_text = ""


func _set_info_area_visible(should_show: bool) -> void:
	# The buy/no-warehouse state uses InfoLabel wrapped in an InfoCard panel.
	# When a warehouse exists we show OwnedTabs, and this InfoCard becomes an empty
	# middle panel between the tabs and the Back button unless we hide it.
	if is_instance_valid(_info_card):
		_info_card.visible = should_show
	if is_instance_valid(info_label):
		# Keep label visibility consistent even if wrapper is not present.
		info_label.visible = should_show

func _get_settlement_id() -> String:
	# Best-effort: ensure we have a settlement id for buy requests.
	if (_settlement is Dictionary) and String(_settlement.get("sett_id", "")) != "":
		return String(_settlement.get("sett_id", ""))
	if _convoy_data is Dictionary and not _convoy_data.is_empty():
		var resolved := _resolve_settlement_from_data(_convoy_data)
		if not resolved.is_empty() and String(resolved.get("sett_id", "")) != "":
			_settlement = resolved
			return String(resolved.get("sett_id", ""))
	return ""

func _format_warehouse_summary(_w: Dictionary) -> String:
	# Overview now minimal; details moved elsewhere
	var parts: Array[String] = []
	parts.append("Warehouse")
	return "\n".join(parts)

func _on_buy_pressed():
	if not is_instance_valid(_warehouse_service):
		push_warning("API node not available")
		return
	# Need settlement id from provided settlement snapshot
	var sett_id := _get_settlement_id()
	if sett_id == "":
		# Fallback: try to resolve by settlement name from canonical snapshot
		var name_guess := String(_settlement.get("name", _convoy_data.get("settlement_name", "")))
		if name_guess != "":
			for s in _get_all_settlements_snapshot():
				if typeof(s) == TYPE_DICTIONARY and String(s.get("name", "")) == name_guess:
					sett_id = String(s.get("sett_id", ""))
					break
	if sett_id == "":
		if is_instance_valid(info_label):
			info_label.text = "Settlement not resolved yet."
		return
	# Affordability check (client-side UX only; server remains authoritative)
	var price := _get_warehouse_price()
	var funds := _get_user_money()
	if price > 0 and funds + 0.0001 < float(price):
		if is_instance_valid(info_label):
			info_label.text = "Insufficient funds to buy warehouse. Price: %s, You have: %s" % [NumberFormat.format_money(price), NumberFormat.format_money(funds)]
		if is_instance_valid(buy_button):
			buy_button.disabled = true
		return
	if is_instance_valid(info_label):
		info_label.text = "Purchasing warehouse..."
	if is_instance_valid(buy_button):
		buy_button.disabled = true
	_is_loading = true
	_update_ui()
	_warehouse_service.request_new(sett_id)
	# APICalls no longer emits 'warehouse_created' (see logs), so we must refresh
	# authoritative snapshots and discover the new warehouse via user.warehouses.
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()
	_start_post_buy_refresh_poll()

func _start_post_buy_refresh_poll() -> void:
	# Try a handful of times: user refresh -> check user.warehouses -> request_get.
	_post_buy_refresh_attempts_left = 10
	_schedule_post_buy_refresh(0.5)

func _schedule_post_buy_refresh(delay_seconds: float) -> void:
	if _post_buy_refresh_attempts_left <= 0:
		# Give up gracefully; keep UI usable.
		_is_loading = false
		if is_instance_valid(info_label) and (_warehouse is Dictionary and _warehouse.is_empty()):
			info_label.text = "Purchase sent. Waiting for server sync…"
		_update_ui()
		return
	if _post_buy_refresh_in_flight:
		return
	if not is_inside_tree():
		return
	if _warehouse is Dictionary and not _warehouse.is_empty():
		return
	_post_buy_refresh_in_flight = true
	var t := get_tree().create_timer(delay_seconds)
	t.timeout.connect(func() -> void:
		_post_buy_refresh_in_flight = false
		if not is_inside_tree():
			return
		if _warehouse is Dictionary and not _warehouse.is_empty():
			return
		_post_buy_refresh_attempts_left -= 1
		if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
			_user_service.refresh_user()
		# Also try loading immediately from whatever snapshot we already have.
		if not _is_loading:
			_is_loading = true
		_try_load_warehouse_for_settlement()
		_schedule_post_buy_refresh(0.8)
	)

func _on_hub_warehouse_created(result: Variant) -> void:
	# Backend returns the new UUID; refresh user data and show confirmation
	if is_instance_valid(buy_button):
		buy_button.disabled = false
	var wid := ""
	if typeof(result) == TYPE_DICTIONARY:
		wid = String((result as Dictionary).get("warehouse_id", ""))
	else:
		wid = String(result)
		wid = wid.strip_edges()
		# If backend returned a JSON string like "uuid", strip quotes
		if wid.length() >= 2 and wid[0] == '"' and wid[wid.length() - 1] == '"':
			wid = wid.substr(1, wid.length() - 2)
	if wid == "":
		if is_instance_valid(info_label):
			info_label.text = "Warehouse created."
	else:
		if is_instance_valid(info_label):
			info_label.text = "Warehouse created: %s" % wid
		# Immediately fetch details
		if is_instance_valid(_warehouse_service):
			_is_loading = true
			_update_ui()
			_warehouse_service.request_get(wid)
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()

func _on_hub_warehouse_received(warehouse_data: Dictionary) -> void:
	_warehouse = warehouse_data.duplicate(true)
	_is_loading = false
	_pending_action_refresh = false
	_upgrade_in_progress = false
	if _warehouse.has("warehouse_id"):
		_last_known_wid = str(_warehouse.get("warehouse_id", ""))
	# Re-enable upgrade buttons if pricing allows
	_update_expand_buttons()
	_set_expand_buttons_enabled(true)
	# Re-enable spawn button after any warehouse update (covers convoy spawn completion)
	if is_instance_valid(spawn_convoy_btn):
		spawn_convoy_btn.disabled = false
	# Debug: print warehouse keys and common inventory fields
	var keys: Array = []
	for k in _warehouse.keys():
		keys.append(str(k))
	print("[WarehouseMenu][Debug] Warehouse keys=", ", ".join(PackedStringArray(keys)))
	var cargo_inv: Variant = _warehouse.get("cargo_inventory", null)
	var all_cargo: Variant = _warehouse.get("all_cargo", null)
	var veh_inv: Variant = _warehouse.get("vehicle_inventory", null)
	var cargo_inv_size: int = (cargo_inv.size() if typeof(cargo_inv) == TYPE_ARRAY else -1)
	var all_cargo_size: int = (all_cargo.size() if typeof(all_cargo) == TYPE_ARRAY else -1)
	var veh_inv_size: int = (veh_inv.size() if typeof(veh_inv) == TYPE_ARRAY else -1)
	print("[WarehouseMenu][Debug] cargo_inventory type=", typeof(cargo_inv), " size=", cargo_inv_size)
	print("[WarehouseMenu][Debug] all_cargo type=", typeof(all_cargo), " size=", all_cargo_size)
	print("[WarehouseMenu][Debug] vehicle_inventory type=", typeof(veh_inv), " size=", veh_inv_size)
	# Capacity diagnostics after refresh
	var cargo_cap := int(_warehouse.get("cargo_storage_capacity", 0))
	var veh_cap := int(_warehouse.get("vehicle_storage_capacity", 0))
	print("[WarehouseMenu][AfterRefresh] cargo_cap=", cargo_cap, " vehicle_cap=", veh_cap)
	# If this refresh followed an expansion attempt, compute delta
	if _last_expand_type != "":
		var cargo_delta := -99999
		var veh_delta := -99999
		if _pre_expand_cargo_cap >= 0:
			cargo_delta = cargo_cap - _pre_expand_cargo_cap
		if _pre_expand_vehicle_cap >= 0:
			veh_delta = veh_cap - _pre_expand_vehicle_cap
		print("[WarehouseMenu][UpgradeDelta] attempt_type=", _last_expand_type, " cargo_delta=", cargo_delta, " vehicle_delta=", veh_delta, " used_json=", _last_expand_used_json)
		var no_change := false
		if _last_expand_type == "cargo" and cargo_delta <= 0:
			no_change = true
		elif _last_expand_type == "vehicle" and veh_delta <= 0:
			no_change = true
		if no_change:
			# Decide on retry with JSON body if we have not yet tried it
			if not _last_expand_used_json and is_instance_valid(_warehouse_service):
				print("[WarehouseMenu][UpgradeDelta][NoChange] Retrying expansion using JSON body fallback.")
				if is_instance_valid(info_label):
					info_label.text = "Expansion had no visible effect. Retrying (JSON)..."
				_upgrade_in_progress = true
				_set_expand_buttons_enabled(false)
				_pending_action_refresh = true
				_last_expand_used_json = true
				# Re-dispatch expansion using JSON body
				var wid_retry := ""
				if _warehouse is Dictionary and _warehouse.has("warehouse_id"):
					wid_retry = str(_warehouse.get("warehouse_id", ""))
				elif _last_known_wid != "":
					wid_retry = _last_known_wid
				if wid_retry != "":
					_warehouse_service.request_expand({"warehouse_id": wid_retry, "expand_type": _last_expand_type, "amount": 1})
					_schedule_refresh_fallback()
			else:
				# Second failure (JSON already used) – give up and notify
				print("[WarehouseMenu][UpgradeDelta][NoChangeAfterJSON] Expansion still shows no delta.")
				# Clear optimistic markers (authoritative user refresh will correct funds)
				if _optimistic_money_active:
					_optimistic_money_active = false
					_optimistic_money_before = 0.0
					_optimistic_money_after = 0.0
				if is_instance_valid(info_label):
					info_label.text = "Expansion request completed but capacity unchanged." 
				_last_expand_type = "" # reset so we don't loop
		else:
			# Success path – clear tracking
			_last_expand_type = ""
			_last_expand_used_json = false
			_pre_expand_cargo_cap = -1
			_pre_expand_vehicle_cap = -1
	# Clear optimistic deduction when warehouse refresh arrives (user refresh should follow separately)
	if _optimistic_money_active:
		print("[WarehouseMenu][Optimistic] Clearing optimistic deduction on warehouse refresh")
		_optimistic_money_active = false
		_optimistic_money_before = 0.0
		_optimistic_money_after = 0.0
	_update_ui()
	# Refresh canonical snapshots (authoritative)
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()
	if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_all"):
		_convoy_service.refresh_all()
	# Update dropdowns since we have fresh warehouse data
	_populate_dropdowns()

func _on_hub_error(_domain: String, _code: String, message: String, _inline: bool) -> void:
	# Only handle if this menu is visible; otherwise ignore
	if not is_inside_tree():
		return
	if is_instance_valid(buy_button):
		buy_button.disabled = false
	# Route error to modal using ErrorTranslator; avoid printing raw into menu
	# Optionally filter by domain; for now surface all.
	_show_error_modal(message)

func _show_error_modal(raw_msg: String) -> void:
	# Translate via ErrorTranslator and display with ErrorDialog.
	var translated := raw_msg
	var et_script := preload("res://Scripts/System/error_translator.gd")
	if et_script:
		var et := et_script.new()
		if et and et.has_method("translate"):
			translated = et.translate(raw_msg)
	# If translator returns empty (ignored), do nothing.
	if translated == "":
		return
	# Show modal dialog.
	var dlg_scene := load("res://Scenes/ErrorDialog.tscn")
	if dlg_scene:
		var dlg: AcceptDialog = dlg_scene.instantiate()
		add_child(dlg)
		if dlg and dlg.has_method("show_message"):
			dlg.show_message(translated)

func _on_hub_warehouse_action(_result: Variant) -> void:
	# After any action, reload warehouse even if we currently have no local _warehouse data.
	var wid := ""
	if _warehouse is Dictionary and _warehouse.has("warehouse_id"):
		wid = str(_warehouse.get("warehouse_id", ""))
	if wid == "" and _last_known_wid != "":
		wid = _last_known_wid
	print("[WarehouseMenu][ActionComplete] result_type=", typeof(_result), " chosen_wid=", wid, " had_local=", (_warehouse is Dictionary and not _warehouse.is_empty()), " last_known=", _last_known_wid)
	if wid == "" or not is_instance_valid(_warehouse_service):
		print("[WarehouseMenu][ActionComplete] Abort refresh: missing wid or api invalid")
		return
	# Skip early user data refresh for expansion actions to avoid flicker overriding optimistic deduction
	var skip_early_user_refresh := _last_expand_type != "" # still tracking an expansion attempt
	if not skip_early_user_refresh:
		if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
			print("[WarehouseMenu][ActionComplete] Triggering early user data refresh for non-expansion action")
			_user_service.refresh_user()
	_is_loading = true
	_update_ui()
	_warehouse_service.request_get(wid)

# Schedule a one-shot fallback refresh in case signals are delayed or missed
func _schedule_refresh_fallback() -> void:
	var timer := get_tree().create_timer(2.0)
	if timer and timer.timeout and not timer.timeout.is_connected(_on_refresh_fallback_timeout):
		timer.timeout.connect(_on_refresh_fallback_timeout)

func _on_refresh_fallback_timeout() -> void:
	if not _pending_action_refresh:
		return
	_refresh_warehouse()

func _refresh_warehouse() -> void:
	if not is_instance_valid(_warehouse_service):
		return
	var wid := ""
	if _warehouse is Dictionary and _warehouse.has("warehouse_id"):
		wid = str(_warehouse.get("warehouse_id", ""))
	if wid != "":
		_is_loading = true
		_update_ui()
		_warehouse_service.request_get(wid)
	else:
		_try_load_warehouse_for_settlement()

# --- UI action handlers ---
func _on_expand_cargo():
	print("[WarehouseMenu][ExpandCargo] Handler ENTER")
	var wid := ""
	if _warehouse is Dictionary and _warehouse.has("warehouse_id"):
		wid = str(_warehouse.get("warehouse_id", ""))
	elif _last_known_wid != "":
		wid = _last_known_wid
	if wid == "":
		print("[WarehouseMenu][ExpandCargo] Blocked: no warehouse id (local + last_known empty)")
		if is_instance_valid(info_label):
			info_label.text = "Cannot upgrade: warehouse not loaded yet."
		return
	print("[WarehouseMenu][ExpandCargo] Click received wid=", wid, " has_local=", (_warehouse is Dictionary and not _warehouse.is_empty()), " last_known=", _last_known_wid)
	var _amt := 1
	var per_unit := _get_upgrade_price_per_unit()
	if per_unit <= 0:
		var stype := _get_settlement_type()
		print("[WarehouseMenu][ExpandCargo] Blocked: upgrades not available at settlement_type=", stype)
		if is_instance_valid(info_label):
			info_label.text = "Upgrades not available at this settlement."
		return
	if wid != "" and is_instance_valid(_warehouse_service):
		info_label.text = "Expanding cargo..."
		print("[WarehouseMenu][ExpandCargo] Dispatch service.request_expand params=", {"warehouse_id": wid, "cargo_units": 1, "vehicle_units": 0, "unit_price": per_unit})
		# Record baseline before dispatch
		_pre_expand_cargo_cap = int(_warehouse.get("cargo_storage_capacity", -1)) if (_warehouse is Dictionary) else -1
		_pre_expand_vehicle_cap = int(_warehouse.get("vehicle_storage_capacity", -1)) if (_warehouse is Dictionary) else -1
		_last_expand_type = "cargo"
		_last_expand_used_json = false
		# Optimistic funds deduction (only once until next authoritative user refresh)
		if not _optimistic_money_active:
			_optimistic_money_before = _get_user_money() # already respects any active optimistic state (should be inactive here)
			_optimistic_money_after = max(0.0, _optimistic_money_before - float(per_unit))
			_optimistic_money_active = true
			print("[WarehouseMenu][Optimistic] Cargo upgrade: deduct", per_unit, "from", _optimistic_money_before, "=>", _optimistic_money_after)
			_update_expand_buttons()
			_update_upgrade_labels()
		_upgrade_in_progress = true
		_set_expand_buttons_enabled(false)
		_pending_action_refresh = true
		_schedule_refresh_fallback()
		_warehouse_service.request_expand({"warehouse_id": wid, "cargo_units": 1, "vehicle_units": 0})
	else:
		print("[WarehouseMenu][ExpandCargo] Blocked: invalid state wid=", wid, " svc_valid=", is_instance_valid(_warehouse_service))

func _on_expand_vehicle():
	print("[WarehouseMenu][ExpandVehicle] Handler ENTER")
	var wid := ""
	if _warehouse is Dictionary and _warehouse.has("warehouse_id"):
		wid = str(_warehouse.get("warehouse_id", ""))
	elif _last_known_wid != "":
		wid = _last_known_wid
	if wid == "":
		print("[WarehouseMenu][ExpandVehicle] Blocked: no warehouse id (local + last_known empty)")
		if is_instance_valid(info_label):
			info_label.text = "Cannot upgrade: warehouse not loaded yet."
		return
	print("[WarehouseMenu][ExpandVehicle] Click received wid=", wid, " has_local=", (_warehouse is Dictionary and not _warehouse.is_empty()), " last_known=", _last_known_wid)
	var _amt := 1
	var per_unit := _get_upgrade_price_per_unit()
	if per_unit <= 0:
		var stype := _get_settlement_type()
		print("[WarehouseMenu][ExpandVehicle] Blocked: upgrades not available at settlement_type=", stype)
		if is_instance_valid(info_label):
			info_label.text = "Upgrades not available at this settlement."
		return
	if wid != "" and is_instance_valid(_warehouse_service):
		info_label.text = "Expanding vehicle slots..."
		print("[WarehouseMenu][ExpandVehicle] Dispatch service.request_expand params=", {"warehouse_id": wid, "cargo_units": 0, "vehicle_units": 1, "unit_price": per_unit})
		# Record baseline before dispatch
		_pre_expand_cargo_cap = int(_warehouse.get("cargo_storage_capacity", -1)) if (_warehouse is Dictionary) else -1
		_pre_expand_vehicle_cap = int(_warehouse.get("vehicle_storage_capacity", -1)) if (_warehouse is Dictionary) else -1
		_last_expand_type = "vehicle"
		_last_expand_used_json = false
		# Optimistic funds deduction
		if not _optimistic_money_active:
			_optimistic_money_before = _get_user_money()
			_optimistic_money_after = max(0.0, _optimistic_money_before - float(per_unit))
			_optimistic_money_active = true
			print("[WarehouseMenu][Optimistic] Vehicle upgrade: deduct", per_unit, "from", _optimistic_money_before, "=>", _optimistic_money_after)
			# Do not mutate global snapshots optimistically; rely on refresh.
			_update_expand_buttons()
			_update_upgrade_labels()
		_upgrade_in_progress = true
		_set_expand_buttons_enabled(false)
		_pending_action_refresh = true
		_schedule_refresh_fallback()
		_warehouse_service.request_expand({"warehouse_id": wid, "cargo_units": 0, "vehicle_units": 1})
	else:
		print("[WarehouseMenu][ExpandVehicle] Blocked: invalid state wid=", wid, " svc_valid=", is_instance_valid(_warehouse_service))

func _diag_expand_cargo_pressed():
	var state := "n/a"
	if is_instance_valid(expand_cargo_btn):
		state = str(expand_cargo_btn.disabled)
	print("[WarehouseMenu][Diag] expand_cargo_btn raw pressed. disabled=", state)

func _diag_expand_vehicle_pressed():
	var state := "n/a"
	if is_instance_valid(expand_vehicle_btn):
		state = str(expand_vehicle_btn.disabled)
	print("[WarehouseMenu][Diag] expand_vehicle_btn raw pressed. disabled=", state)

func _on_expand_button_gui_input(ev: InputEvent, kind: String):
	# Capture mouse button presses even when button is disabled (pressed signal won't emit)
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var disabled_state := "?"
		if kind == "cargo" and is_instance_valid(expand_cargo_btn):
			disabled_state = str(expand_cargo_btn.disabled)
		elif kind == "vehicle" and is_instance_valid(expand_vehicle_btn):
			disabled_state = str(expand_vehicle_btn.disabled)
		print("[WarehouseMenu][Diag][gui_input] kind=", kind, " left_click. disabled=", disabled_state)

func _post_ready_expand_diag():
	# Reconnect primary handlers if somehow disconnected; then dump state again
	if is_instance_valid(expand_cargo_btn):
		if not expand_cargo_btn.pressed.is_connected(_on_expand_cargo):
			print("[WarehouseMenu][Diag] Reconnecting _on_expand_cargo (deferred)")
			expand_cargo_btn.pressed.connect(_on_expand_cargo)
		print("[WarehouseMenu][Diag] Post-ready cargo disabled=", expand_cargo_btn.disabled)
	else:
		print("[WarehouseMenu][Diag][PostReady] Missing expand_cargo_btn")
	if is_instance_valid(expand_vehicle_btn):
		if not expand_vehicle_btn.pressed.is_connected(_on_expand_vehicle):
			print("[WarehouseMenu][Diag] Reconnecting _on_expand_vehicle (deferred)")
			expand_vehicle_btn.pressed.connect(_on_expand_vehicle)
		print("[WarehouseMenu][Diag] Post-ready vehicle disabled=", expand_vehicle_btn.disabled)
	else:
		print("[WarehouseMenu][Diag][PostReady] Missing expand_vehicle_btn")
	# Self-test: do NOT actually trigger expansion, just log readiness
	var per_unit := _get_upgrade_price_per_unit()
	print("[WarehouseMenu][Diag] Self-test per_unit=", per_unit, " warehouse_loaded=", (_warehouse is Dictionary and not _warehouse.is_empty()))

func _on_store_cargo():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var cargo_meta := _get_selected_meta(cargo_store_dd)
	var qty := int(cargo_qty_store.value) if is_instance_valid(cargo_qty_store) else 0
	if wid != "" and cid != "" and cargo_meta != "" and qty > 0 and is_instance_valid(_warehouse_service):
		info_label.text = "Storing cargo..."
		_pending_action_refresh = true
		_schedule_refresh_fallback()
		_store_cargo_by_meta(wid, cid, cargo_meta, qty)

func _on_retrieve_cargo():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var cargo_meta := _get_selected_meta(cargo_retrieve_dd)
	# pick vehicle to receive
	var recv_vid := _get_selected_meta(cargo_retrieve_vehicle_dd)
	var qty := int(cargo_qty_retrieve.value) if is_instance_valid(cargo_qty_retrieve) else 0
	if wid != "" and cid != "" and cargo_meta != "" and qty > 0 and is_instance_valid(_warehouse_service):
		info_label.text = "Retrieving cargo..."
		_pending_action_refresh = true
		_schedule_refresh_fallback()
		_retrieve_cargo_by_meta(wid, cid, cargo_meta, qty, recv_vid)

func _on_store_vehicle():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var vid := _get_selected_meta(vehicle_store_dd)
	if wid != "" and cid != "" and vid != "" and is_instance_valid(_warehouse_service):
		info_label.text = "Storing vehicle..."
		_warehouse_service.store_vehicle({"warehouse_id": wid, "convoy_id": cid, "vehicle_id": vid})

func _on_retrieve_vehicle():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var vid := _get_selected_meta(vehicle_retrieve_dd)
	if wid != "" and cid != "" and vid != "" and is_instance_valid(_warehouse_service):
		info_label.text = "Retrieving vehicle..."
		_warehouse_service.retrieve_vehicle({"warehouse_id": wid, "convoy_id": cid, "vehicle_id": vid})

func _on_spawn_convoy():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cname := spawn_name_input.text if is_instance_valid(spawn_name_input) else ""
	if cname == "":
		cname = "New Convoy"
	var spawn_vid := _get_selected_meta(spawn_vehicle_dd)
	# Detailed diagnostics
	print("[WarehouseMenu][SpawnConvoy] Attempt wid=", wid, " spawn_vid=", spawn_vid, " name=", cname, " svc_valid=", is_instance_valid(_warehouse_service))
	if wid != "" and spawn_vid != "" and is_instance_valid(_warehouse_service):
		if is_instance_valid(info_label):
			info_label.text = "Spawning convoy..."
		# Temporarily disable button to prevent double clicks
		if is_instance_valid(spawn_convoy_btn):
			spawn_convoy_btn.disabled = true
		_pending_action_refresh = true
		_schedule_refresh_fallback()
		# API spec requires 'new_convoy_name'; send both for backward compatibility
		_warehouse_service.spawn_convoy({
			"warehouse_id": wid,
			"vehicle_id": spawn_vid,
			"new_convoy_name": cname,
			"name": cname # legacy / fallback if server still expects 'name'
		})
	else:
		var abort_reason := ""
		if wid == "":
			abort_reason = "missing_warehouse_id"
		elif spawn_vid == "":
			abort_reason = "missing_vehicle_id"
		elif not is_instance_valid(_warehouse_service):
			abort_reason = "api_unavailable"
		else:
			abort_reason = "unknown"
		if is_instance_valid(info_label):
			match abort_reason:
				"missing_warehouse_id": info_label.text = "No warehouse ID available (reload)."
				"missing_vehicle_id": info_label.text = "Select a stored vehicle first."
				"api_unavailable": info_label.text = "Cannot spawn convoy (API unavailable)."
				_: info_label.text = "Cannot spawn convoy (unknown issue)."
		print("[WarehouseMenu][SpawnConvoy][Abort] reason=", abort_reason, " wid=", wid, " spawn_vid=", spawn_vid, " name=", cname)

func _try_load_warehouse_for_settlement() -> void:
	var sett_id := String(_settlement.get("sett_id", ""))
	if sett_id == "":
		return
	var user: Dictionary = {}
	if is_instance_valid(_user_service) and _user_service.has_method("get_user"):
		user = _user_service.get_user()
	var warehouses: Array = []
	if typeof(user) == TYPE_DICTIONARY:
		warehouses = user.get("warehouses", [])
	var local_warehouse: Dictionary = {}
	for w in warehouses:
		if typeof(w) == TYPE_DICTIONARY and String(w.get("sett_id", "")) == sett_id:
			local_warehouse = w
			break
	if not local_warehouse.is_empty():
		var wid := String(local_warehouse.get("warehouse_id", ""))
		if wid != "" and is_instance_valid(_warehouse_service):
			_is_loading = true
			_update_ui()
			_warehouse_service.request_get(wid)

func _get_warehouse_price() -> int:
	var stype := _get_settlement_type()
	if WAREHOUSE_PRICES.has(stype):
		var v = WAREHOUSE_PRICES[stype]
		if v == null:
			return 0
		return int(v)
	# Unknown types: return 0 to indicate no client-side price (server may decide)
	return 0

func _is_buy_available() -> bool:
	var stype := _get_settlement_type()
	if WAREHOUSE_PRICES.has(stype):
		return WAREHOUSE_PRICES[stype] != null
	return true

func _get_upgrade_price_per_unit() -> int:
	# Prefer server-provided price when available
	if _warehouse is Dictionary and _warehouse.has("expansion_price") and _warehouse.get("expansion_price") != null:
		return int(_warehouse.get("expansion_price"))
	var stype := _get_settlement_type()
	if WAREHOUSE_UPGRADE_PRICES.has(stype):
		var v = WAREHOUSE_UPGRADE_PRICES[stype]
		if v == null:
			return 0
		return int(v)
	return 0

func _get_settlement_type() -> String:
	# Try direct type first
	var stype := ""
	if _settlement and _settlement.has("sett_type"):
		stype = String(_settlement.get("sett_type", "")).to_lower()
	if stype != "":
		return _normalize_settlement_type(stype)
	# Try resolve by sett_id
	if _settlement and _settlement.has("sett_id"):
		var sid := String(_settlement.get("sett_id", ""))
		if sid != "":
			for s in _get_all_settlements_snapshot():
				if typeof(s) == TYPE_DICTIONARY and String(s.get("sett_id", "")) == sid:
					return _normalize_settlement_type(String(s.get("sett_type", "")).to_lower())
	# Try resolve by name
	if _settlement and _settlement.has("name"):
		var sname := String(_settlement.get("name", ""))
		if sname != "":
			for s2 in _get_all_settlements_snapshot():
				if typeof(s2) == TYPE_DICTIONARY and String(s2.get("name", "")) == sname:
					return _normalize_settlement_type(String(s2.get("sett_type", "")).to_lower())
	# Fallback: try convoy_data settlement_name or coords
	if _convoy_data:
		var from_convoy := _resolve_settlement_from_data(_convoy_data)
		if not from_convoy.is_empty():
			_settlement = from_convoy # cache it for later
			if from_convoy.has("sett_type"):
				return _normalize_settlement_type(String(from_convoy.get("sett_type", "")).to_lower())
			# else if only name/id, try again via lookups
			if from_convoy.has("sett_id"):
				var sid2 := String(from_convoy.get("sett_id", ""))
				for s3 in _get_all_settlements_snapshot():
					if typeof(s3) == TYPE_DICTIONARY and String(s3.get("sett_id", "")) == sid2:
						return _normalize_settlement_type(String(s3.get("sett_type", "")).to_lower())
			if from_convoy.has("name"):
				var sname2 := String(from_convoy.get("name", ""))
				for s4 in _get_all_settlements_snapshot():
					if typeof(s4) == TYPE_DICTIONARY and String(s4.get("name", "")) == sname2:
						return _normalize_settlement_type(String(s4.get("sett_type", "")).to_lower())
	print("[WarehouseMenu][SettlType] Unable to resolve settlement type. settlement=", _settlement)
	return ""

func _normalize_settlement_type(t: String) -> String:
	var s := t.strip_edges(true, true).to_lower()
	# Normalize separators
	s = s.replace("_", "-")
	s = s.replace(" ", "-")
	# Collapse common variants
	if s == "citystate" or s == "city-state" or s == "city-state-":
		s = "city-state"
	elif s == "city_state":
		s = "city-state"
	elif s == "military-base" or s == "military base" or s == "militarybase":
		s = "military_base" # our pricing map uses underscore here
	return s

func _resolve_settlement_from_data(d: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	# Prefer explicit settlement_name on convoy payload
	if d.has("settlement_name") and String(d.get("settlement_name", "")) != "":
		var sname := String(d.get("settlement_name"))
		for s in _get_all_settlements_snapshot():
			if typeof(s) == TYPE_DICTIONARY and String(s.get("name", "")) == sname:
				result = s.duplicate(true)
				break
		# If we found by name, return immediately
		if not result.is_empty():
			return result
	# Fallback by coordinates if available
	var sx := int(roundf(float(d.get("x", -999999.0))))
	var sy := int(roundf(float(d.get("y", -999999.0))))
	if sx > -999999 and sy > -999999:
		for s2 in _get_all_settlements_snapshot():
			if typeof(s2) != TYPE_DICTIONARY:
				continue
			var sx2 := int(roundf(float(s2.get("x", -999999.0))))
			var sy2 := int(roundf(float(s2.get("y", -999999.0))))
			if sx2 == sx and sy2 == sy:
				result = (s2 as Dictionary).duplicate(true)
				break
	return result

func _get_user_money() -> float:
	# If we applied an optimistic deduction, surface that immediately so tooltips & labels reflect it.
	if _optimistic_money_active:
		return _optimistic_money_after
	if is_instance_valid(_user_service) and _user_service.has_method("get_user"):
		var user: Dictionary = _user_service.get_user()
		if typeof(user) == TYPE_DICTIONARY:
			return float(user.get("money", 0.0))
	return 0.0


func _get_all_settlements_snapshot() -> Array:
	if is_instance_valid(_store) and _store.has_method("get_settlements"):
		return _store.get_settlements()
	return []


func _on_store_user_changed(_user: Dictionary) -> void:
	# Money / warehouses may change; refresh text + buttons.
	_update_ui()
	_update_expand_buttons()
	_update_upgrade_labels()
	# If we don't have a warehouse yet, try to discover it from user.warehouses.
	if (_warehouse is Dictionary and _warehouse.is_empty()) and not _is_loading:
		_try_load_warehouse_for_settlement()


func _on_store_convoys_changed(convoys: Array) -> void:
	# Keep convoy cargo/vehicles dropdowns current.
	var cid := str(_convoy_data.get("convoy_id", "")) if (_convoy_data is Dictionary) else ""
	if cid == "":
		return
	for c in convoys:
		if c is Dictionary and str(c.get("convoy_id", "")) == cid:
			_convoy_data = (c as Dictionary).duplicate(true)
			break
	_populate_dropdowns()


func _on_store_map_changed(_tiles: Array, _settlements: Array) -> void:
	# Settlement resolution/type may become available after map arrives.
	if (_settlement is Dictionary) and not _settlement.is_empty() and String(_settlement.get("sett_type", "")) != "":
		return
	var resolved := _resolve_settlement_from_data(_convoy_data)
	if not resolved.is_empty():
		_settlement = resolved
		_update_ui()

 

func _update_expand_buttons() -> void:
	# With fixed +1 upgrades, enable when upgrades are available for this settlement.
	var per_unit := _get_upgrade_price_per_unit()
	var funds := _get_user_money()
	var total := int(per_unit) * 1
	var available := per_unit > 0
	print("[WarehouseMenu][UpgradeState] update_buttons sett_type=", _get_settlement_type(), " per_unit=", per_unit, " funds=", funds, " available=", available)
	var base_disabled := not available
	var disabled_reason := ""
	if _upgrade_in_progress:
		base_disabled = true
		disabled_reason = " (upgrade in progress)"
	if is_instance_valid(expand_cargo_btn):
		expand_cargo_btn.disabled = base_disabled
		expand_cargo_btn.tooltip_text = ("Upgrades not available" if not available else "Cost: %s (per unit %s)\nYour funds: %s%s" % [NumberFormat.format_money(total), NumberFormat.format_money(per_unit), NumberFormat.format_money(funds), disabled_reason])
	if is_instance_valid(expand_vehicle_btn):
		expand_vehicle_btn.disabled = base_disabled
		expand_vehicle_btn.tooltip_text = ("Upgrades not available" if not available else "Cost: %s (per unit %s)\nYour funds: %s%s" % [NumberFormat.format_money(total), NumberFormat.format_money(per_unit), NumberFormat.format_money(funds), disabled_reason])

func _update_upgrade_labels() -> void:
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var cargo_cap := int(_warehouse.get("cargo_storage_capacity", 0))
	var veh_cap := int(_warehouse.get("vehicle_storage_capacity", 0))
	if is_instance_valid(expand_cargo_label):
		expand_cargo_label.text = "Upgrade Cargo Capacity (Cap: %s)" % cargo_cap
	if is_instance_valid(expand_vehicle_label):
		expand_vehicle_label.text = "Upgrade Vehicle Slots (Cap: %s)" % veh_cap

# --- Helpers for dropdowns ---
func _populate_dropdowns() -> void:
	# Convoy cargo (Store): aggregate across vehicles, exclude parts, list destination cargo first, then other cargo
	if is_instance_valid(cargo_store_dd):
		var agg := _aggregate_convoy_cargo(_convoy_data)
		var normals_dest: Array = agg["normal_dest"] if agg.has("normal_dest") else []
		var normals_other: Array = agg["normal_other"] if agg.has("normal_other") else []
		# Build id/label list in stable order
		var items: Array = []
		for it in normals_dest:
			items.append({"id": String(it.get("meta", "")), "label": "%s x%d" % [it.get("name", "Unknown"), int(it.get("quantity", 0))]})
		for itn in normals_other:
			items.append({"id": String(itn.get("meta", "")), "label": "%s x%d" % [itn.get("name", "Unknown"), int(itn.get("quantity", 0))]})
		_set_option_button_items(cargo_store_dd, items, _last_cargo_store_ids)
		# Sync store qty limit to selected item after (re)population
		_update_store_qty_limit()

	# Warehouse cargo (Retrieve): classify normal vs part cargo; prefer cargo_storage
	if is_instance_valid(cargo_retrieve_dd):
		var wh_items: Array = []
		if _warehouse and _warehouse.has("cargo_storage"):
			wh_items = _warehouse.get("cargo_storage", [])
		elif _warehouse and _warehouse.has("cargo_inventory"):
			wh_items = _warehouse.get("cargo_inventory", [])
		elif _warehouse and _warehouse.has("all_cargo"):
			wh_items = _warehouse.get("all_cargo", [])
		# Debug: show how many warehouse cargo items were found before classification
		print("[WarehouseMenu][Debug] Dropdown populate: wh cargo count=", wh_items.size())
		var wh_agg := _aggregate_warehouse_cargo(wh_items)
		var wh_items_final: Array = []
		for a in (wh_agg.get("normal_dest", []) as Array):
			wh_items_final.append({"id": String(a.get("meta","")), "label": "%s x%d" % [String(a.get("name","Unknown")), int(a.get("quantity",0))]})
		for a2 in (wh_agg.get("normal_other", []) as Array):
			wh_items_final.append({"id": String(a2.get("meta","")), "label": "%s x%d" % [String(a2.get("name","Unknown")), int(a2.get("quantity",0))]})
		_set_option_button_items(cargo_retrieve_dd, wh_items_final, _last_cargo_retrieve_ids)
		# Sync retrieve qty limit to selected item after (re)population
		_update_retrieve_qty_limit()
		# Also re-render cargo grid in case of updates
		_render_cargo_grid()

	# Vehicles from convoy for store and target vehicle dropdowns (stable sort by name then id)
	var convoy_vehicles: Array = _get_convoy_vehicle_details_list(_convoy_data)
	var convoy_vehicle_items: Array = []
	for v in convoy_vehicles:
		if v is Dictionary:
			convoy_vehicle_items.append({"name": String(v.get("name","Vehicle")), "id": String(v.get("vehicle_id",""))})
	convoy_vehicle_items.sort_custom(func(a, b): return a["name"] < b["name"] or (a["name"] == b["name"] and a["id"] < b["id"]))
	if is_instance_valid(vehicle_store_dd):
		var items_vs: Array = []
		for cv in convoy_vehicle_items: items_vs.append({"id": cv["id"], "label": cv["name"]})
		_set_option_button_items(vehicle_store_dd, items_vs, _last_vehicle_store_ids)
	if is_instance_valid(cargo_retrieve_vehicle_dd):
		var items_recv: Array = []
		for cv2 in convoy_vehicle_items: items_recv.append({"id": cv2["id"], "label": cv2["name"]})
		_set_option_button_items(cargo_retrieve_vehicle_dd, items_recv, []) # no last tracking needed

	# Warehouse vehicles (retrieve/spawn) stable sort; prefer vehicle_storage
	var wh_vehicle_items: Array = []
	if _warehouse and _warehouse.has("vehicle_storage"):
		for v2 in _warehouse.get("vehicle_storage", []):
			if v2 is Dictionary:
				wh_vehicle_items.append({"name": String(v2.get("name","Vehicle")), "id": String(v2.get("vehicle_id",""))})
	elif _warehouse and _warehouse.has("vehicle_inventory"):
		for v3 in _warehouse.get("vehicle_inventory", []):
			if v3 is Dictionary:
				wh_vehicle_items.append({"name": String(v3.get("name","Vehicle")), "id": String(v3.get("vehicle_id",""))})
	wh_vehicle_items.sort_custom(func(a, b): return a["name"] < b["name"] or (a["name"] == b["name"] and a["id"] < b["id"]))
	if is_instance_valid(vehicle_retrieve_dd):
		var items_vr: Array = []
		for wv in wh_vehicle_items: items_vr.append({"id": wv["id"], "label": wv["name"]})
		_set_option_button_items(vehicle_retrieve_dd, items_vr, _last_vehicle_retrieve_ids)
	if is_instance_valid(spawn_vehicle_dd):
		var items_sv: Array = []
		for wv2 in wh_vehicle_items: items_sv.append({"id": wv2["id"], "label": wv2["name"]})
		_set_option_button_items(spawn_vehicle_dd, items_sv, _last_spawn_vehicle_ids)
		# UX: manage spawn button enable state based on availability
		if is_instance_valid(spawn_convoy_btn):
			if spawn_vehicle_dd.item_count == 0:
				spawn_convoy_btn.disabled = true
				spawn_convoy_btn.tooltip_text = "Store a vehicle first to spawn a new convoy."
			else:
				spawn_convoy_btn.disabled = false
				spawn_convoy_btn.tooltip_text = "Spawn a new convoy using the selected stored vehicle."
	# Update vehicle grid visuals as well
	_render_vehicle_grid()

func _get_selected_meta(dd: OptionButton) -> String:
	if not is_instance_valid(dd) or dd.item_count == 0:
		return ""
	var idx := dd.get_selected_id()
	if idx < 0:
		idx = dd.get_selected()
	if idx < 0:
		return ""
	var meta = dd.get_item_metadata(idx)
	return String(meta) if meta != null else ""

func _update_cargo_usage_label() -> void:
	if not is_instance_valid(cargo_usage_label):
		return
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		cargo_usage_label.text = "Cargo: 0 / 0 L"
		return
	var cap := int(_warehouse.get("cargo_storage_capacity", 0))
	var used := int(_warehouse.get("stored_volume", 0))
	cargo_usage_label.text = "Cargo: %s / %s L" % [str(used), str(cap)]
	_update_overview_bars()

func _update_overview_bars() -> void:
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		if is_instance_valid(overview_cargo_bar):
			overview_cargo_bar.value = 0
		if is_instance_valid(overview_vehicle_bar):
			overview_vehicle_bar.value = 0
		if is_instance_valid(overview_cargo_label):
			overview_cargo_label.text = "Cargo Usage: 0 / 0 L"
		if is_instance_valid(overview_vehicle_label):
			overview_vehicle_label.text = "Vehicles: 0 / 0"
		return
	# Cargo bar
	var cap_cargo := float(_warehouse.get("cargo_storage_capacity", 0))
	var used_cargo := float(_warehouse.get("stored_volume", 0))
	if cap_cargo <= 0:
		cap_cargo = 1.0
	var display_used_cargo := used_cargo
	# Guarantee at least a visible 1% if there is any cargo (>0 but below 1%)
	var one_percent_cargo := cap_cargo * 0.01
	if display_used_cargo > 0.0 and display_used_cargo < one_percent_cargo:
		display_used_cargo = one_percent_cargo
	if is_instance_valid(overview_cargo_bar):
		overview_cargo_bar.max_value = cap_cargo
		overview_cargo_bar.value = clamp(display_used_cargo, 0.0, cap_cargo)
	if is_instance_valid(overview_cargo_label):
		overview_cargo_label.text = "Cargo Usage: %s / %s L" % [str(int(used_cargo)), str(int(cap_cargo))]
	# Vehicle bar (derive from counts if capacity key exists, else hide)
	var veh_list: Array = []
	if _warehouse.has("vehicle_storage"):
		veh_list = _warehouse.get("vehicle_storage", [])
	elif _warehouse.has("vehicle_inventory"):
		veh_list = _warehouse.get("vehicle_inventory", [])
	var veh_used := float(veh_list.size())
	var veh_cap := float(_warehouse.get("vehicle_storage_capacity", max(veh_used, 1)))
	if veh_cap <= 0:
		veh_cap = max(veh_used, 1.0)
	var display_veh_used := veh_used
	var one_percent_veh := veh_cap * 0.01
	if display_veh_used > 0.0 and display_veh_used < one_percent_veh:
		display_veh_used = one_percent_veh
	if is_instance_valid(overview_vehicle_bar):
		overview_vehicle_bar.max_value = veh_cap
		overview_vehicle_bar.value = clamp(display_veh_used, 0.0, veh_cap)
	if is_instance_valid(overview_vehicle_label):
		overview_vehicle_label.text = "Vehicles: %s / %s" % [str(int(veh_used)), str(int(veh_cap))]

func _render_cargo_grid() -> void:
	if not is_instance_valid(cargo_grid):
		return
	# Clear existing
	for c in cargo_grid.get_children():
		c.queue_free()
	if not (_warehouse is Dictionary):
		return
	# (Banner handled outside grid via _ensure_inventory_headers)
	var wh_items: Array = []
	if _warehouse.has("cargo_storage"):
		wh_items = _warehouse.get("cargo_storage", [])
	elif _warehouse.has("cargo_inventory"):
		wh_items = _warehouse.get("cargo_inventory", [])
	elif _warehouse.has("all_cargo"):
		wh_items = _warehouse.get("all_cargo", [])
	# Render simple boxes (no icons) with name + qty (aggregated; parts excluded)
	var wh_agg := _aggregate_warehouse_cargo(wh_items)
	var wh_items_display: Array = []
	for a in (wh_agg.get("normal_dest", []) as Array):
		wh_items_display.append(a)
	for a2 in (wh_agg.get("normal_other", []) as Array):
		wh_items_display.append(a2)
	if wh_items_display.is_empty():
		_set_inventory_panel_empty_state(cargo_inventory_panel, "CargoInventoryEmptyPanel", "No cargo stored yet.")
		return
	_set_inventory_panel_empty_state(cargo_inventory_panel, "CargoInventoryEmptyPanel", "", true)
	_adjust_inventory_panel_height(cargo_inventory_panel, cargo_grid_scroll, wh_items_display.size(), 4)
	for wi in wh_items_display:
		if wi is Dictionary:
			var item_name := String(wi.get("name", "Item"))
			var qty := int(wi.get("quantity", 0))
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(120, 32)
			var vb := VBoxContainer.new()
			var label := Label.new()
			label.text = "%s x%d" % [item_name, qty]
			vb.add_child(label)
			panel.add_child(vb)
			cargo_grid.add_child(panel)

func _render_vehicle_grid() -> void:
	if not is_instance_valid(vehicle_grid):
		return
	for c in vehicle_grid.get_children():
		c.queue_free()
	if not (_warehouse is Dictionary):
		return
	# (Banner handled outside grid via _ensure_inventory_headers)
	var wh_vehicles: Array = []
	if _warehouse.has("vehicle_storage"):
		wh_vehicles = _warehouse.get("vehicle_storage", [])
	elif _warehouse.has("vehicle_inventory"):
		wh_vehicles = _warehouse.get("vehicle_inventory", [])
	if wh_vehicles.is_empty():
		_set_inventory_panel_empty_state(vehicle_inventory_panel, "VehicleInventoryEmptyPanel", "No vehicles stored yet.")
		return
	_set_inventory_panel_empty_state(vehicle_inventory_panel, "VehicleInventoryEmptyPanel", "", true)
	_adjust_inventory_panel_height(vehicle_inventory_panel, vehicle_grid_scroll, wh_vehicles.size(), 4)
	for v in wh_vehicles:
		if v is Dictionary:
			var vehicle_name := String(v.get("name", "Vehicle"))
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(120, 32)
			var vb := VBoxContainer.new()
			var label := Label.new()
			label.text = vehicle_name
			vb.add_child(label)
			panel.add_child(vb)
			vehicle_grid.add_child(panel)

func _set_inventory_panel_empty_state(panel_ctrl: Control, empty_panel_name: String, empty_message: String, show_inventory_panel: bool = false) -> void:
	# When inventories are empty, the ScrollContainer panels in the scene expand
	# and look like a big blank box. Collapse them and show a compact empty-state.
	if not is_instance_valid(panel_ctrl):
		return
	var parent := panel_ctrl.get_parent()
	if parent == null:
		return
	var existing: Node = parent.get_node_or_null(empty_panel_name)
	if show_inventory_panel:
		panel_ctrl.visible = true
		# Restore content-sized behavior (no vertical expand)
		if panel_ctrl is Control:
			(panel_ctrl as Control).size_flags_vertical = Control.SIZE_FILL
		# Also ensure the internal scroll doesn't expand to fill the tab.
		if panel_ctrl.has_node("CargoGridScroll"):
			var sc := panel_ctrl.get_node_or_null("CargoGridScroll")
			if sc is Control:
				(sc as Control).size_flags_vertical = Control.SIZE_FILL
		elif panel_ctrl.has_node("VehicleGridScroll"):
			var sc2 := panel_ctrl.get_node_or_null("VehicleGridScroll")
			if sc2 is Control:
				(sc2 as Control).size_flags_vertical = Control.SIZE_FILL
		if existing:
			existing.queue_free()
		return

	panel_ctrl.visible = false
	if existing == null:
		var p := PanelContainer.new()
		p.name = empty_panel_name
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(0, 48)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.09, 0.12, 0.96)
		sb.border_color = Color(0.38, 0.46, 0.60, 0.6)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_left = 10
		sb.corner_radius_bottom_right = 10
		p.add_theme_stylebox_override("panel", sb)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 12)
		m.add_theme_constant_override("margin_right", 12)
		m.add_theme_constant_override("margin_top", 8)
		m.add_theme_constant_override("margin_bottom", 8)
		var l := Label.new()
		l.text = empty_message
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 1.0))
		l.add_theme_font_size_override("font_size", 16)
		m.add_child(l)
		p.add_child(m)
		parent.add_child(p)
		parent.move_child(p, panel_ctrl.get_index())
	else:
		# Update message if needed
		var pc := existing as PanelContainer
		if pc and pc.get_child_count() > 0:
			var margin := pc.get_child(0)
			if margin and margin.get_child_count() > 0 and margin.get_child(0) is Label:
				(margin.get_child(0) as Label).text = empty_message

func _adjust_inventory_panel_height(panel_ctrl: Control, scroll_ctrl: ScrollContainer, item_count: int, columns: int) -> void:
	# Clamp the inventory panel height to its content so we don't get a giant blank area.
	if not (is_instance_valid(panel_ctrl) and is_instance_valid(scroll_ctrl)):
		return
	columns = max(1, columns)
	var rows := int(ceil(float(max(item_count, 1)) / float(columns)))
	# Rough row height: our panels are 32px min + margins.
	var row_h := 40
	var desired := 20 + rows * row_h
	# Clamp so it never takes half the menu.
	var clamped := clampi(desired, 70, 220)
	scroll_ctrl.custom_minimum_size = Vector2(scroll_ctrl.custom_minimum_size.x, float(clamped))
	# Ensure the container doesn't expand beyond its minimum.
	scroll_ctrl.size_flags_vertical = Control.SIZE_FILL
	panel_ctrl.size_flags_vertical = Control.SIZE_FILL

# Enforce SpinBox max based on selected cargo quantities
func _update_store_qty_limit() -> void:
	if not is_instance_valid(cargo_qty_store):
		return
	var cargo_meta := _get_selected_meta(cargo_store_dd)
	var max_qty := 1
	if cargo_meta != "":
		max_qty = max(1, _get_convoy_cargo_quantity_for_meta(cargo_meta))
	cargo_qty_store.min_value = 1
	cargo_qty_store.step = 1
	cargo_qty_store.allow_greater = false
	cargo_qty_store.max_value = float(max_qty)
	if cargo_qty_store.value > cargo_qty_store.max_value:
		cargo_qty_store.value = cargo_qty_store.max_value
	# Optionally disable button if none available
	if is_instance_valid(store_cargo_btn):
		store_cargo_btn.disabled = (cargo_meta == "" or max_qty <= 0)

func _update_retrieve_qty_limit() -> void:
	if not is_instance_valid(cargo_qty_retrieve):
		return
	var cargo_meta := _get_selected_meta(cargo_retrieve_dd)
	var max_qty := 1
	if cargo_meta != "":
		max_qty = max(1, _get_warehouse_cargo_quantity_for_meta(cargo_meta))
	cargo_qty_retrieve.min_value = 1
	cargo_qty_retrieve.step = 1
	cargo_qty_retrieve.allow_greater = false
	cargo_qty_retrieve.max_value = float(max_qty)
	if cargo_qty_retrieve.value > cargo_qty_retrieve.max_value:
		cargo_qty_retrieve.value = cargo_qty_retrieve.max_value
	if is_instance_valid(retrieve_cargo_btn):
		retrieve_cargo_btn.disabled = (cargo_meta == "" or max_qty <= 0)

func _get_convoy_cargo_quantity_by_id(cargo_id: String) -> int:
	if cargo_id == "":
		return 0
	var total := 0
	var vehicles: Array = _get_convoy_vehicle_details_list(_convoy_data)
	for veh in vehicles:
		if not (veh is Dictionary):
			continue
		var cargo_arr: Array = veh.get("cargo", [])
		for item in cargo_arr:
			if not (item is Dictionary):
				continue
			if String(item.get("cargo_id", "")) != cargo_id:
				continue
			if _looks_like_part_cargo(item as Dictionary):
				continue
			total += int(item.get("quantity", 0))
	return total

func _get_warehouse_cargo_quantity_by_id(cargo_id: String) -> int:
	if cargo_id == "" or not (_warehouse is Dictionary) or _warehouse.is_empty():
		return 0
	var total := 0
	var wh_items: Array = []
	if _warehouse.has("cargo_storage"):
		wh_items = _warehouse.get("cargo_storage", [])
	elif _warehouse.has("cargo_inventory"):
		wh_items = _warehouse.get("cargo_inventory", [])
	elif _warehouse.has("all_cargo"):
		wh_items = _warehouse.get("all_cargo", [])
	for wi in wh_items:
		if wi is Dictionary and String(wi.get("cargo_id", "")) == cargo_id:
			total += int(wi.get("quantity", 0))
	return total

# Creates a small styled banner panel for inventory headers
func _make_inventory_label(text: String, node_name: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l

# Ensure inventory labels exist above grids (only created once)
func _ensure_inventory_headers() -> void:
	# Place labels as siblings BEFORE the inventory panels so they read like true titles.
	if is_instance_valid(cargo_inventory_panel) and cargo_inventory_panel.get_parent():
		var parent = cargo_inventory_panel.get_parent()
		# Remove any internal label previously added inside the panel
		var internal = cargo_inventory_panel.get_node_or_null("CargoInventoryLabel")
		if internal: internal.queue_free()
		if parent.get_node_or_null("CargoInventoryLabel") == null:
			var lbl = _make_inventory_label("Current Cargo Inventory", "CargoInventoryLabel")
			parent.add_child(lbl)
			parent.move_child(lbl, parent.get_children().find(cargo_inventory_panel))
	if is_instance_valid(vehicle_inventory_panel) and vehicle_inventory_panel.get_parent():
		var parent_v = vehicle_inventory_panel.get_parent()
		var internal_v = vehicle_inventory_panel.get_node_or_null("VehicleInventoryLabel")
		if internal_v: internal_v.queue_free()
		if parent_v.get_node_or_null("VehicleInventoryLabel") == null:
			var lbl2 = _make_inventory_label("Current Vehicle Inventory", "VehicleInventoryLabel")
			parent_v.add_child(lbl2)
			parent_v.move_child(lbl2, parent_v.get_children().find(vehicle_inventory_panel))

# Helpers for stable dropdown population and cargo aggregation
func _set_option_button_items(dd: OptionButton, items: Array, last_ids_ref: Array) -> void:
	if not is_instance_valid(dd):
		return
	# Build current ids from control
	var current_ids: Array[String] = []
	for i in range(dd.item_count):
		var m = dd.get_item_metadata(i)
		current_ids.append(String(m) if m != null else "")
	# Build new ids
	var new_ids: Array[String] = []
	for it in items:
		new_ids.append(String(it.get("id","")))
	# If unchanged, just return to avoid reshuffle
	if current_ids == new_ids:
		return
	# Preserve selection by id
	var prev_selected_id := _get_selected_meta(dd)
	dd.clear()
	for it2 in items:
		dd.add_item(String(it2.get("label","")))
		dd.set_item_metadata(dd.item_count - 1, String(it2.get("id","")))
	# Empty placeholder
	if dd.item_count == 0:
		dd.add_item("-- None --")
		dd.set_item_metadata(0, "")
		dd.disabled = true
	else:
		dd.disabled = false
	# Restore selection if possible
	if prev_selected_id != "":
		for j in range(dd.item_count):
			if String(dd.get_item_metadata(j)) == prev_selected_id:
				dd.select(j)
				break
	# Update last ids tracking if provided
	if typeof(last_ids_ref) == TYPE_ARRAY:
		last_ids_ref.clear()
		for nid in new_ids: last_ids_ref.append(nid)

func _looks_like_part_cargo(d: Dictionary) -> bool:
	return (ItemsData != null and ItemsData.PartItem and ItemsData.PartItem._looks_like_part_dict(d))

func _get_cargo_display_name(d: Dictionary) -> String:
	# Prefer base_name so variants (e.g. different cereals) collapse nicely.
	var base := String(d.get("base_name", ""))
	if base.strip_edges() != "":
		return base
	return String(d.get("name", "Unknown"))

func _get_cargo_group_key(d: Dictionary, has_dest: bool) -> String:
	var name_key := _get_cargo_display_name(d).to_lower().strip_edges()
	if has_dest:
		# Do not merge destination/mission cargo across different recipients.
		var recipient_key := str(d.get("recipient", d.get("mission_id", d.get("mission_vendor_id", ""))))
		return "dest|%s|%s" % [name_key, recipient_key]
	return "norm|%s" % name_key

func _encode_cargo_meta(items: Array) -> String:
	# items is an array of {cargo_id, quantity}. If a single cargo_id, return it directly.
	var clean: Array = []
	for e in items:
		if e is Dictionary:
			var cid := String((e as Dictionary).get("cargo_id", ""))
			var q := int((e as Dictionary).get("quantity", 0))
			if cid != "" and q > 0:
				clean.append({"cargo_id": cid, "quantity": q})
	if clean.size() == 0:
		return ""
	if clean.size() == 1:
		return String((clean[0] as Dictionary).get("cargo_id", ""))
	# Keep deterministic order
	clean.sort_custom(func(a, b): return String(a.get("cargo_id", "")) < String(b.get("cargo_id", "")))
	return JSON.stringify(clean)

func _decode_cargo_meta(meta: String) -> Array:
	var s := meta.strip_edges()
	if s.begins_with("["):
		var parsed: Variant = JSON.parse_string(s)
		if parsed is Array:
			return parsed as Array
	return []

func _get_convoy_cargo_quantity_for_meta(cargo_meta: String) -> int:
	if cargo_meta == "":
		return 0
	var decoded := _decode_cargo_meta(cargo_meta)
	if not decoded.is_empty():
		var total := 0
		for e in decoded:
			if e is Dictionary:
				total += int((e as Dictionary).get("quantity", 0))
		return total
	# Single-id meta; quantity should be present in aggregation.
	var agg := _aggregate_convoy_cargo(_convoy_data)
	for arr_name in ["normal_dest", "normal_other"]:
		if agg.has(arr_name):
			for it in (agg[arr_name] as Array):
				if String(it.get("meta", "")) == cargo_meta:
					return int(it.get("quantity", 0))
	return 0

func _get_warehouse_cargo_quantity_for_meta(cargo_meta: String) -> int:
	if cargo_meta == "" or not (_warehouse is Dictionary) or _warehouse.is_empty():
		return 0
	var decoded := _decode_cargo_meta(cargo_meta)
	if not decoded.is_empty():
		var total := 0
		for e in decoded:
			if e is Dictionary:
				total += int((e as Dictionary).get("quantity", 0))
		return total
	return _get_warehouse_cargo_quantity_by_id(cargo_meta)

func _store_cargo_by_meta(wid: String, cid: String, cargo_meta: String, qty: int) -> void:
	var decoded := _decode_cargo_meta(cargo_meta)
	if decoded.is_empty():
		_warehouse_service.store_cargo({"warehouse_id": wid, "convoy_id": cid, "cargo_id": cargo_meta, "quantity": qty})
		return
	var remaining: int = qty
	for e in decoded:
		if remaining <= 0:
			break
		if e is Dictionary:
			var eid := String((e as Dictionary).get("cargo_id", ""))
			var avail := int((e as Dictionary).get("quantity", 0))
			var take: int = min(remaining, avail)
			if eid != "" and take > 0:
				_warehouse_service.store_cargo({"warehouse_id": wid, "convoy_id": cid, "cargo_id": eid, "quantity": take})
				remaining -= take

func _retrieve_cargo_by_meta(wid: String, cid: String, cargo_meta: String, qty: int, recv_vid: String) -> void:
	var decoded := _decode_cargo_meta(cargo_meta)
	if decoded.is_empty():
		var payload := {"warehouse_id": wid, "convoy_id": cid, "cargo_id": cargo_meta, "quantity": qty}
		if recv_vid != "":
			payload["vehicle_id"] = recv_vid
		_warehouse_service.retrieve_cargo(payload)
		return
	var remaining: int = qty
	for e in decoded:
		if remaining <= 0:
			break
		if e is Dictionary:
			var eid := String((e as Dictionary).get("cargo_id", ""))
			var avail := int((e as Dictionary).get("quantity", 0))
			var take: int = min(remaining, avail)
			if eid != "" and take > 0:
				var payload2 := {"warehouse_id": wid, "convoy_id": cid, "cargo_id": eid, "quantity": take}
				if recv_vid != "":
					payload2["vehicle_id"] = recv_vid
				_warehouse_service.retrieve_cargo(payload2)
				remaining -= take

func _aggregate_warehouse_cargo(items: Array) -> Dictionary:
	# Aggregate cargo by base name and exclude parts.
	var result := {"normal_dest": [], "normal_other": []}
	if items.is_empty():
		return result
	var by_key: Dictionary = {}
	for wi in items:
		if wi is Dictionary:
			var d := wi as Dictionary
			var cid := String(d.get("cargo_id", ""))
			var qty := int(d.get("quantity", 0))
			if cid == "" or qty <= 0:
				continue
			if _looks_like_part_cargo(d):
				continue
			var has_dest: bool = (d.get("recipient") != null) or (d.get("delivery_reward") != null)
			var key := _get_cargo_group_key(d, has_dest)
			if not by_key.has(key):
				by_key[key] = {"name": _get_cargo_display_name(d), "quantity": 0, "has_dest": has_dest, "items": []}
			(by_key[key] as Dictionary)["quantity"] = int((by_key[key] as Dictionary).get("quantity", 0)) + qty
			var arr: Array = (by_key[key] as Dictionary).get("items", [])
			arr.append({"cargo_id": cid, "quantity": qty})
			(by_key[key] as Dictionary)["items"] = arr
	for k in by_key.keys():
		var g: Dictionary = by_key[k]
		var entry := {"meta": _encode_cargo_meta(g.get("items", [])), "name": String(g.get("name", "Unknown")), "quantity": int(g.get("quantity", 0))}
		if bool(g.get("has_dest", false)):
			(result["normal_dest"] as Array).append(entry)
		else:
			(result["normal_other"] as Array).append(entry)
	(result["normal_dest"] as Array).sort_custom(func(a, b): return String(a.get("name", "")) < String(b.get("name", "")) or (String(a.get("name", "")) == String(b.get("name", "")) and String(a.get("meta", "")) < String(b.get("meta", ""))))
	(result["normal_other"] as Array).sort_custom(func(a, b): return String(a.get("name", "")) < String(b.get("name", "")) or (String(a.get("name", "")) == String(b.get("name", "")) and String(a.get("meta", "")) < String(b.get("meta", ""))))
	return result

func _aggregate_convoy_cargo(convoy: Dictionary) -> Dictionary:
	var result := {"normal_dest": [], "normal_other": []}
	if not (convoy is Dictionary):
		return result
	var vehicles: Array = _get_convoy_vehicle_details_list(convoy)
	if vehicles.is_empty():
		return result
	var by_key: Dictionary = {}

	# Aggregate by base name where possible (e.g., cereal variants), and exclude parts (e.g., fuel tanks).
	for veh in vehicles:
		if not (veh is Dictionary):
			continue
		var cargo_arr: Array = veh.get("cargo", [])
		for item in cargo_arr:
			if not (item is Dictionary):
				continue
			var cid := String(item.get("cargo_id", ""))
			if cid == "":
				continue
			var qty := int(item.get("quantity", 0))
			if qty <= 0:
				continue
			if _looks_like_part_cargo(item):
				continue
			var has_dest: bool = (item.get("recipient") != null) or (item.get("delivery_reward") != null)
			var key := _get_cargo_group_key(item, has_dest)
			if not by_key.has(key):
				by_key[key] = {"name": _get_cargo_display_name(item), "quantity": 0, "has_dest": has_dest, "items": []}
			(by_key[key] as Dictionary)["quantity"] = int((by_key[key] as Dictionary).get("quantity", 0)) + qty
			var arr: Array = (by_key[key] as Dictionary).get("items", [])
			arr.append({"cargo_id": cid, "quantity": qty})
			(by_key[key] as Dictionary)["items"] = arr
	for k in by_key.keys():
		var g: Dictionary = by_key[k]
		var entry := {"meta": _encode_cargo_meta(g.get("items", [])), "name": String(g.get("name", "Unknown")), "quantity": int(g.get("quantity", 0))}
		if bool(g.get("has_dest", false)):
			(result["normal_dest"] as Array).append(entry)
		else:
			(result["normal_other"] as Array).append(entry)
	(result["normal_dest"] as Array).sort_custom(func(a, b): return String(a.get("name", "")) < String(b.get("name", "")) or (String(a.get("name", "")) == String(b.get("name", "")) and String(a.get("meta", "")) < String(b.get("meta", ""))))
	(result["normal_other"] as Array).sort_custom(func(a, b): return String(a.get("name", "")) < String(b.get("name", "")) or (String(a.get("name", "")) == String(b.get("name", "")) and String(a.get("meta", "")) < String(b.get("meta", ""))))
	return result

func _get_convoy_vehicle_details_list(convoy: Dictionary) -> Array:
	# Convoy payload shape has varied across API versions.
	# Prefer vehicle_details_list, fallback to vehicles/vehicle_list.
	if not (convoy is Dictionary) or convoy.is_empty():
		return []
	var vlist: Variant = convoy.get("vehicle_details_list", null)
	if typeof(vlist) == TYPE_ARRAY and (vlist as Array).size() > 0:
		return vlist as Array
	vlist = convoy.get("vehicles", null)
	if typeof(vlist) == TYPE_ARRAY and (vlist as Array).size() > 0:
		return vlist as Array
	vlist = convoy.get("vehicle_list", null)
	if typeof(vlist) == TYPE_ARRAY and (vlist as Array).size() > 0:
		return vlist as Array
	# If key exists but empty, return empty.
	if convoy.has("vehicle_details_list") and typeof(convoy.get("vehicle_details_list")) == TYPE_ARRAY:
		return convoy.get("vehicle_details_list")
	if convoy.has("vehicles") and typeof(convoy.get("vehicles")) == TYPE_ARRAY:
		return convoy.get("vehicles")
	if convoy.has("vehicle_list") and typeof(convoy.get("vehicle_list")) == TYPE_ARRAY:
		return convoy.get("vehicle_list")
	return []
