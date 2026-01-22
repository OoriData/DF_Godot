# SignalHub.gd
extends Node

# Canonical domain events for the app. UI and services communicate via Hub.

# Map and Settlements
signal map_changed(tiles: Array, settlements: Array)

# Convoys
signal convoys_changed(convoys: Array)
signal convoy_updated(convoy: Dictionary)

# UI selection (source of truth for convoy selection events)
# - convoy_selection_requested is an intent (dropdown/map click/etc.)
# - convoy_selection_changed is the resolved selection payload (Dictionary or null)
# - selected_convoy_ids_changed is the resolved id list used by map/UI highlight
signal convoy_selection_requested(convoy_id: String, allow_toggle: bool)
signal convoy_selection_changed(selected_convoy_data: Variant)
signal selected_convoy_ids_changed(selected_ids: Array)

# User
signal user_changed(user: Dictionary)
signal auth_state_changed(state: String)
signal user_refresh_requested

# Vendors
signal vendor_updated(vendor: Dictionary)
signal vendor_panel_ready(data: Dictionary)
signal vendor_preview_ready(data: Dictionary)

# Routing
signal route_choices_request_started
signal route_choices_ready(routes: Array)
signal route_choices_error(message: String)

# Lifecycle and errors
signal error_occurred(domain: String, code: String, message: String, inline: bool)

# Warehouses
signal warehouse_created(result: Variant)
signal warehouse_updated(warehouse: Dictionary)
signal warehouse_expanded(result: Variant)
signal warehouse_cargo_stored(result: Variant)
signal warehouse_cargo_retrieved(result: Variant)
signal warehouse_vehicle_stored(result: Variant)
signal warehouse_vehicle_retrieved(result: Variant)
signal warehouse_convoy_spawned(result: Variant)
signal initial_data_ready

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
