# MapSettingsService.gd
extends Node

# Single source of truth for map visual overlays and settings.
# Adheres to the Law of Unidirectional Data Flow by storing raw setting state
# and notifying subscribers when a change occurs.

# Diagnostic Flag as per the Law of Diagnostic Flags
const _debug_map_menu: bool = true

# --- Global Map Visual Overlay Toggles (Defaults) ---
var active_delivery_destinations: bool = false
var settlement_delivery_destinations: bool = false
var settlement_labels: bool = false
var warehouse_labels: bool = false
var all_convoy_destinations: bool = false
var grid_lines: bool = false

@onready var _hub: Node = get_node_or_null("/root/SignalHub")

# When true (journey planning), all MARKER overlays are reported OFF by get_settings_dict() so the map
# is clean — without persisting or mutating the user's real toggle state. Grid lines (a background
# layer, not a marker) are left as-is. Cleared on planning exit to restore the user's settings.
var _planning_override_active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Load persisted settings on boot
	var sm = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		active_delivery_destinations = sm.get_value("map.active_delivery_destinations", false)
		settlement_delivery_destinations = sm.get_value("map.settlement_delivery_destinations", false)
		settlement_labels = sm.get_value("map.settlement_labels", false)
		warehouse_labels = sm.get_value("map.warehouse_labels", false)
		all_convoy_destinations = sm.get_value("map.all_convoy_destinations", false)
		grid_lines = sm.get_value("map.grid_lines", false)
	
	if _debug_map_menu:
		print("[MapSettingsService] Initialized with persisted overlay settings.")

## Mutates a specific setting and broadcasts the updated dictionary to SignalHub.
func update_setting(setting_name: String, value: bool) -> void:
	if _debug_map_menu:
		print("[MapSettingsService] Updating setting '%s' to: %s" % [setting_name, value])
		
	match setting_name:
		"active_delivery_destinations":
			active_delivery_destinations = value
		"settlement_delivery_destinations":
			settlement_delivery_destinations = value
		"settlement_labels":
			settlement_labels = value
		"warehouse_labels":
			warehouse_labels = value
		"all_convoy_destinations":
			all_convoy_destinations = value
		"grid_lines":
			grid_lines = value
		_:
			printerr("[MapSettingsService] Error: Unknown setting '%s'" % setting_name)
			return
			
	var sm = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		sm.set_and_save("map." + setting_name, value)
		
	_broadcast_settings_changed()

## Helper to emit full settings state
func _broadcast_settings_changed() -> void:
	var settings_dict = get_settings_dict()
	if is_instance_valid(_hub) and _hub.has_signal("map_overlay_settings_changed"):
		_hub.map_overlay_settings_changed.emit(settings_dict)
		if _debug_map_menu:
			print("[MapSettingsService] Broadcasted updated settings to SignalHub.")

## Temporarily suppress all marker overlays (journey planning) WITHOUT persisting or changing the
## user's real toggle values. Broadcasts the effective (suppressed) settings; clearing restores them.
func set_planning_override(active: bool) -> void:
	if _planning_override_active == active:
		return
	_planning_override_active = active
	if _debug_map_menu:
		print("[MapSettingsService] Planning marker override: %s" % active)
	_broadcast_settings_changed()

## Returns the EFFECTIVE state dictionary (marker overlays forced off while the planning override is
## active; the user's persisted values otherwise). Grid lines are never a marker, so pass through.
func get_settings_dict() -> Dictionary:
	if _planning_override_active:
		return {
			"active_delivery_destinations": false,
			"settlement_delivery_destinations": false,
			"settlement_labels": false,
			"warehouse_labels": false,
			"all_convoy_destinations": false,
			"grid_lines": grid_lines
		}
	return {
		"active_delivery_destinations": active_delivery_destinations,
		"settlement_delivery_destinations": settlement_delivery_destinations,
		"settlement_labels": settlement_labels,
		"warehouse_labels": warehouse_labels,
		"all_convoy_destinations": all_convoy_destinations,
		"grid_lines": grid_lines
	}
