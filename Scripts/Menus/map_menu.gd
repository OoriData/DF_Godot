# map_menu.gd
extends MenuBase

# Controller for the Map Overlay Settings & Layers Menu.
# Adheres to the Law of Thin Panels by delegating all state modification
# to MapSettingsService, acting purely as a coordinator between widgets and the service.

const _debug_map_menu: bool = true

# Node references (using editor unique names % or direct children)
@onready var title_label: Button = $MainVBox/TopBarHBox/TitleLabel
@onready var back_button: Button = $MainVBox/BackButton
@onready var active_dest_toggle: CheckButton = %ActiveDestinationsToggle
@onready var curr_sett_dest_toggle: CheckButton = %CurrentSettlementDestToggle
@onready var all_convoy_dest_toggle: CheckButton = %AllConvoyDestToggle
@onready var settlement_labels_toggle: CheckButton = %SettlementLabelsToggle
@onready var warehouse_labels_toggle: CheckButton = %WarehouseLabelsToggle

@onready var _settings_service: Node = get_node_or_null("/root/MapSettingsService")
@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")


var _convoy_data: Dictionary = {}

func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
	if _debug_map_menu:
		print("[MapMenu] initialize_with_data called.")
		
	if data_or_id is Dictionary:
		_convoy_data = data_or_id as Dictionary
		convoy_id = String(_convoy_data.get("convoy_id", _convoy_data.get("id", "")))
	else:
		convoy_id = String(data_or_id)
		_convoy_data = {}
		
	super.initialize_with_data(data_or_id, extra_arg)
	
	if is_node_ready():
		_sync_toggles_with_service()
		_update_current_settlement_dest_toggle_availability()

func _ready() -> void:
	persistence_enabled = true
	super._ready()
	
	if _debug_map_menu:
		print("[MapMenu] _ready() entered processing.")
		
	# Setup bottom navigation bar
	if is_instance_valid(back_button):
		setup_convoy_navigation_bar(back_button)
	else:
		printerr("[MapMenu] BackButton node not found.")
		
	# Setup standardized top banner
	if is_instance_valid(title_label):
		setup_convoy_top_banner(title_label, "Map Overlay Settings", true, false)
		_style_top_bar_button(title_label)
		
	# Connect toggle change signals
	_connect_toggles()
	
	# Initial settings sync
	_sync_toggles_with_service()
	_update_current_settlement_dest_toggle_availability()
	
	# Connect to Settings Service updates via SignalHub to maintain 100% synchronization
	if is_instance_valid(_hub) and _hub.has_signal("map_overlay_settings_changed"):
		if not _hub.map_overlay_settings_changed.is_connected(_on_map_overlay_settings_changed):
			_hub.map_overlay_settings_changed.connect(_on_map_overlay_settings_changed)

	# Listen for scale/layout changes to keep UI responsive
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(dsm):
		if not dsm.is_connected("layout_mode_changed", _on_layout_mode_changed):
			dsm.layout_mode_changed.connect(_on_layout_mode_changed)

func _on_map_overlay_settings_changed(_settings: Dictionary) -> void:
	_sync_toggles_with_service()


func _connect_toggles() -> void:
	if is_instance_valid(active_dest_toggle) and not active_dest_toggle.is_connected("toggled", Callable(self, "_on_active_dest_toggled")):
		active_dest_toggle.toggled.connect(_on_active_dest_toggled)
		
	if is_instance_valid(curr_sett_dest_toggle) and not curr_sett_dest_toggle.is_connected("toggled", Callable(self, "_on_curr_sett_dest_toggled")):
		curr_sett_dest_toggle.toggled.connect(_on_curr_sett_dest_toggled)
		
	if is_instance_valid(all_convoy_dest_toggle) and not all_convoy_dest_toggle.is_connected("toggled", Callable(self, "_on_all_convoy_dest_toggled")):
		all_convoy_dest_toggle.toggled.connect(_on_all_convoy_dest_toggled)
		
	if is_instance_valid(settlement_labels_toggle) and not settlement_labels_toggle.is_connected("toggled", Callable(self, "_on_settlement_labels_toggled")):
		settlement_labels_toggle.toggled.connect(_on_settlement_labels_toggled)
		
	if is_instance_valid(warehouse_labels_toggle) and not warehouse_labels_toggle.is_connected("toggled", Callable(self, "_on_warehouse_labels_toggled")):
		warehouse_labels_toggle.toggled.connect(_on_warehouse_labels_toggled)

func _sync_toggles_with_service() -> void:
	if not is_instance_valid(_settings_service):
		printerr("[MapMenu] MapSettingsService not found. Cannot sync settings.")
		return
		
	if _debug_map_menu:
		print("[MapMenu] Syncing toggle states with MapSettingsService...")
		
	_set_toggle_value_quietly(active_dest_toggle, _settings_service.active_delivery_destinations)
	_set_toggle_value_quietly(curr_sett_dest_toggle, _settings_service.settlement_delivery_destinations)
	_set_toggle_value_quietly(all_convoy_dest_toggle, _settings_service.all_convoy_destinations)
	_set_toggle_value_quietly(settlement_labels_toggle, _settings_service.settlement_labels)
	_set_toggle_value_quietly(warehouse_labels_toggle, _settings_service.warehouse_labels)

func _set_toggle_value_quietly(toggle: CheckButton, value: bool) -> void:
	if is_instance_valid(toggle):
		toggle.set_block_signals(true)
		toggle.button_pressed = value
		toggle.set_block_signals(false)

func _update_current_settlement_dest_toggle_availability() -> void:
	if not is_instance_valid(curr_sett_dest_toggle):
		return
		
	# Determine if the convoy is currently inside a settlement tile.
	# If in transit, disable the current settlement deliveries toggle.
	var is_in_settlement: bool = false
	if not _convoy_data.is_empty() and is_instance_valid(_store):
		var current_convoy_x: int = roundi(float(_convoy_data.get("x", -1.0)))
		var current_convoy_y: int = roundi(float(_convoy_data.get("y", -1.0)))
		
		var map_tiles: Array = _store.get_tiles() if _store.has_method("get_tiles") else []
		if current_convoy_y >= 0 and current_convoy_y < map_tiles.size():
			var row_array = map_tiles[current_convoy_y]
			if current_convoy_x >= 0 and current_convoy_x < row_array.size():
				var target_tile = row_array[current_convoy_x]
				if target_tile and target_tile.has("settlements") and not target_tile.settlements.is_empty():
					is_in_settlement = true
					
	if is_in_settlement:
		curr_sett_dest_toggle.disabled = false
		curr_sett_dest_toggle.tooltip_text = "Toggle visibility of cargo routes originating from this settlement."
	else:
		curr_sett_dest_toggle.disabled = true
		curr_sett_dest_toggle.button_pressed = false
		curr_sett_dest_toggle.tooltip_text = "Only available when the selected convoy is stationed inside a settlement."
		if is_instance_valid(_settings_service) and _settings_service.settlement_delivery_destinations:
			_settings_service.update_setting("settlement_delivery_destinations", false)

func _update_ui(convoy: Dictionary) -> void:
	if _debug_map_menu:
		print("[MapMenu] _update_ui triggered.")
	_convoy_data = convoy.duplicate(true)
	_update_current_settlement_dest_toggle_availability()

func _on_active_dest_toggled(button_pressed: bool) -> void:
	_update_setting("active_delivery_destinations", button_pressed)

func _on_curr_sett_dest_toggled(button_pressed: bool) -> void:
	_update_setting("settlement_delivery_destinations", button_pressed)

func _on_all_convoy_dest_toggled(button_pressed: bool) -> void:
	_update_setting("all_convoy_destinations", button_pressed)

func _on_settlement_labels_toggled(button_pressed: bool) -> void:
	_update_setting("settlement_labels", button_pressed)

func _on_warehouse_labels_toggled(button_pressed: bool) -> void:
	_update_setting("warehouse_labels", button_pressed)

func _update_setting(setting_name: String, value: bool) -> void:
	if is_instance_valid(_settings_service) and _settings_service.has_method("update_setting"):
		_settings_service.update_setting(setting_name, value)
		
	# Fire local sound cues or tactile feedback if desired in future premium iterations

func _on_layout_mode_changed(_mode: int, _size: Vector2, _is_mobile_val: bool) -> void:
	if is_instance_valid(title_label):
		_style_top_bar_button(title_label)

func _style_top_bar_button(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	# Matches premium style guidelines established in MenuBase
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.24, 0.28, 0.9)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.45, 0.55, 0.75, 0.7)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", sb)
