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


func test_sell_mode_excludes_bulk_water_when_vendor_has_zero_price():
	var vendor := {"water_price": 0, "cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "water": 10}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_false((buckets.get("resources", {}) as Dictionary).has("Water (Bulk)"), "Should not show bulk water when water_price == 0")


func test_sell_mode_excludes_bulk_food_when_vendor_has_zero_price():
	var vendor := {"food_price": 0, "cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "food": 10}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_false((buckets.get("resources", {}) as Dictionary).has("Food (Bulk)"), "Should not show bulk food when food_price == 0")


func test_sell_mode_excludes_bulk_water_when_vendor_price_missing():
	var vendor := {"cargo_inventory": [], "vehicle_inventory": []} # no water_price key
	var convoy := {"convoy_id": "c1", "water": 10}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_false((buckets.get("resources", {}) as Dictionary).has("Water (Bulk)"), "Should not show bulk water when water_price is missing")


func test_vendor_buckets_exclude_bulk_water_when_water_price_missing_or_zero():
	var vendor_data_missing = {
		"vendor_id": "v1",
		"water": 100,
		# water_price intentionally missing
		"cargo_inventory": [],
		"vehicle_inventory": []
	}
	var buckets_missing := VendorCargoAggregator.build_vendor_buckets(vendor_data_missing, false, Callable())
	assert_eq(int((buckets_missing.get("resources", {}) as Dictionary).size()), 0, "Vendor bulk water should be omitted when water_price is missing")

	var vendor_data_zero = {
		"vendor_id": "v1",
		"water": 100,
		"water_price": 0,
		"cargo_inventory": [],
		"vehicle_inventory": []
	}
	var buckets_zero := VendorCargoAggregator.build_vendor_buckets(vendor_data_zero, false, Callable())
	assert_eq(int((buckets_zero.get("resources", {}) as Dictionary).size()), 0, "Vendor bulk water should be omitted when water_price is 0")


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


func test_sell_mode_excludes_fuel_bearing_cargo_when_vendor_has_no_fuel_price():
	var vendor := {"fuel_price": 0, "cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "cargo_inventory": [{"cargo_id": "x", "name": "Jerry Cans", "quantity": 1, "fuel": 20.0}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_eq((buckets.get("resources", {}) as Dictionary).size(), 0)
	assert_eq((buckets.get("other", {}) as Dictionary).size(), 0, "Fuel-bearing cargo should be excluded when vendor fuel_price == 0")


func test_sell_mode_includes_fuel_bearing_cargo_when_vendor_has_positive_fuel_price():
	var vendor := {"fuel_price": 20, "cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "cargo_inventory": [{"cargo_id": "x", "name": "Jerry Cans", "quantity": 1, "fuel": 20.0}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_true((buckets.get("resources", {}) as Dictionary).size() > 0 or (buckets.get("other", {}) as Dictionary).size() > 0, "Fuel-bearing cargo should be sellable when vendor fuel_price > 0")


func test_sell_mode_excludes_capitalized_fuel_key_when_vendor_has_no_fuel_price():
	var vendor := {"fuel_price": 0, "cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "all_cargo": [{"cargo_id": "x", "name": "Jerry Cans", "quantity": 1, "Fuel": 20.0}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_eq((buckets.get("resources", {}) as Dictionary).size(), 0)
	assert_eq((buckets.get("other", {}) as Dictionary).size(), 0, "Fuel-bearing cargo with 'Fuel' key should be excluded when vendor fuel_price == 0")


func test_sell_mode_requires_all_contained_resources_to_be_buyable():
	# This case shouldn't exist in real data, but ensures strictness if it does.
	var vendor := {"fuel_price": 20, "water_price": 0, "cargo_inventory": [], "vehicle_inventory": []}
	var convoy := {"convoy_id": "c1", "cargo_inventory": [{"cargo_id": "x", "name": "Mixed Tank", "quantity": 1, "fuel": 1.0, "water": 1.0}]}
	var buckets := Aggregator.build_convoy_buckets(convoy, vendor, "sell", false, Callable(), false)
	assert_eq((buckets.get("resources", {}) as Dictionary).size(), 0)
	assert_eq((buckets.get("other", {}) as Dictionary).size(), 0, "Multi-resource cargo should be excluded unless vendor buys all contained resources")


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
