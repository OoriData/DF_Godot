extends GutTest

var Aggregator = preload("res://Scripts/Menus/VendorPanel/cargo_aggregator.gd")
var VehicleSellController = preload("res://Scripts/Menus/VendorPanel/vendor_panel_vehicle_sell_controller.gd")
var ItemsData = preload("res://Scripts/Data/Items.gd")


class DummyPanel:
	extends RefCounted
	var current_mode: String = ""
	var vendor_data: Dictionary = {}
	var vendor_items: Dictionary = {}


func test_sell_mode_includes_bulk_fuel_when_vendor_has_positive_fuel_price():
	var vendor := {"fuel_price": 20, "cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "fuel": 10}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_true((buckets.get("resources", {}) as Dictionary).has("Fuel (Bulk)"), "Should show bulk fuel in sell when fuel_price > 0")


func test_sell_mode_excludes_bulk_fuel_when_vendor_has_zero_price():
	var vendor := {"fuel_price": 0, "cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "fuel": 10}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_false((buckets.get("resources", {}) as Dictionary).has("Fuel (Bulk)"), "Should not show bulk fuel when fuel_price == 0")


func test_sell_mode_excludes_food_resource_cargo_when_vendor_food_price_zero_even_if_item_is_other():
	# Simulate a resource-bearing item that does not use the canonical lowercase key.
	# This historically could be mis-bucketed as Other and slip past resource gating.
	var vendor := {"food_price": 0, "cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "all_cargo": [{"cargo_id": "x", "name": "Rations", "quantity": 1, "Food": 10.0}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_eq((buckets.get("resources", {}) as Dictionary).size(), 0, "Food cargo should not appear in Resources when food_price == 0")
	assert_eq((buckets.get("other", {}) as Dictionary).size(), 0, "Food cargo should not appear in Other when food_price == 0")


func test_sell_mode_includes_cargo_even_when_vendor_has_no_cargo_inventory_key():
	var vendor := {"fuel_price": 20} # no cargo_inventory key
	var convoy := {"convoy_id": "c1", "cargo_inventory": [{"cargo_id": "x", "name": "Box", "quantity": 1}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_true((buckets.get("other", {}) as Dictionary).size() > 0, "Cargo should be sellable to all vendors")


func test_sell_mode_includes_cargo_when_vendor_has_cargo_inventory_capability():
	var vendor := {"cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "cargo_inventory": [{"cargo_id": "x", "name": "Box", "quantity": 1}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_true((buckets.get("other", {}) as Dictionary).size() > 0, "Should show cargo when vendor has cargo_inventory")


func test_sell_mode_includes_all_cargo_when_convoy_uses_all_cargo_key():
	var vendor := {"cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "all_cargo": [{"cargo_id": "x", "name": "Box", "quantity": 1}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_true((buckets.get("other", {}) as Dictionary).size() > 0, "Should show all_cargo items when cargo_inventory is absent")


func test_sell_mode_includes_all_cargo_when_all_cargo_contains_cargoitem_objects():
	var vendor := {"cargo_inventory": [], "vehicle_inventory": []}
	var typed: CargoItem = CargoItem.from_dict({"cargo_id": "x", "name": "Box", "quantity": 1, "weight": 1.0, "volume": 1.0})
	var convoy := {"convoy_id": "c1", "all_cargo": [typed]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_true((buckets.get("other", {}) as Dictionary).size() > 0, "Should show CargoItem entries from all_cargo")


func test_sell_mode_vehicle_category_hidden_when_vendor_vehicle_inventory_empty():
	var panel := DummyPanel.new()
	panel.current_mode = "sell"
	panel.vendor_data = {"vehicle_inventory": []}
	assert_false(VehicleSellController.should_show_vehicle_sell_category(panel), "Vehicle sell category should be hidden when vehicle_inventory is empty")


func test_sell_mode_excludes_convoy_vehicles_when_vendor_vehicle_inventory_empty():
	var vendor := {"cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "vehicle_details_list": [{"vehicle_id": "v1", "name": "Truck"}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_false((buckets.get("vehicles", {}) as Dictionary).has("v1"), "Vehicles should not appear in Sell when vendor has no vehicles")


func test_sell_mode_includes_convoy_vehicles_when_vendor_vehicle_inventory_nonempty():
	var vendor := {"cargo_inventory": [], "vehicle_inventory": [{"vehicle_id": "vv", "name": "DealerStock"}]}
	var convoy := {"convoy_id": "c1", "vehicle_details_list": [{"vehicle_id": "v1", "name": "Truck"}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_true((buckets.get("vehicles", {}) as Dictionary).has("v1"), "Vehicles should appear in Sell only when vendor vehicle_inventory is non-empty")
