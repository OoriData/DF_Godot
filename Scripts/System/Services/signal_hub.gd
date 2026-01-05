# SignalHub.gd
extends Node

# Canonical domain events for the app. UI and services communicate via Hub.

# Map and Settlements
signal map_changed(tiles: Array, settlements: Array)

# Convoys
signal convoys_changed(convoys: Array)
signal convoy_updated(convoy: Dictionary)

# User
signal user_changed(user: Dictionary)
signal auth_state_changed(state: String)

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
