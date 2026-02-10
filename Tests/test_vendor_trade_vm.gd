extends GutTest

func test_build_price_presenter_buy_mode_resource():
	# Setup a mock item with base value and physical properties
	var item = {
		"name": "Fuel",
		"base_value": 10.0,
		"unit_weight": 1.0,
		"unit_volume": 1.0
	}
	
	# Act: Buy 10 units
	var res = VendorTradeVM.build_price_presenter(item, "buy", 10, null)
	
	# Assert: Standard pricing and positive mass/volume projection
	# Note: Relies on PriceUtil returning base_value for simple items
	assert_eq(res.unit_price, 10.0, "Unit price should match base value in buy mode")
	assert_eq(res.total_price, 100.0, "Total price should be unit * qty")
	assert_eq(res.added_weight, 10.0, "Added weight should be positive for buy")
	assert_eq(res.added_volume, 10.0, "Added volume should be positive for buy")

func test_build_price_presenter_sell_mode_resource():
	var item = {
		"name": "Fuel",
		"base_value": 10.0,
		"unit_weight": 1.0,
		"unit_volume": 1.0
	}
	
	# Act: Sell 5 units
	var res = VendorTradeVM.build_price_presenter(item, "sell", 5, null)
	
	# Assert: Price halving and negative mass/volume projection
	assert_eq(res.unit_price, 5.0, "Sell price should be halved for non-vehicle resources")
	assert_eq(res.total_price, 25.0, "Total price should be halved unit * qty")
	assert_eq(res.added_weight, -5.0, "Added weight should be negative for sell (removing from convoy)")
	assert_eq(res.added_volume, -5.0, "Added volume should be negative for sell")


func test_build_price_presenter_buy_mode_bulk_raw_resource_simplified_text():
	var item = {
		"name": "Fuel (Bulk)",
		"is_raw_resource": true,
		"fuel": 100,
		"fuel_price": 20.0,
		"unit_weight": 1.0,
		"unit_volume": 0.0
	}
	var res = VendorTradeVM.build_price_presenter(item, "buy", 10, null)
	assert_eq(res.unit_price, 20.0)
	assert_eq(res.total_price, 200.0)
	assert_eq(res.added_weight, 10.0)
	assert_eq(res.added_volume, 0.0, "Bulk resources should not project volume")
	assert_ne(res.bbcode_text.find("Unit Price"), -1)
	assert_ne(res.bbcode_text.find("Total Price"), -1)
	assert_ne(res.bbcode_text.find("Weight Change"), -1)
	assert_eq(res.bbcode_text.find("Quantity"), -1, "Bulk resources should not show quantity line")
	assert_eq(res.bbcode_text.find("Order Volume"), -1, "Bulk resources should not show volume line")
	assert_eq(res.bbcode_text.find("Order Weight"), -1, "Bulk resources should use Weight Change label")


func test_build_price_presenter_sell_mode_bulk_raw_resource_full_price_and_negates_weight():
	var item = {
		"name": "Water (Bulk)",
		"is_raw_resource": true,
		"water": 50,
		"water_price": 10.0,
		"unit_weight": 1.0,
		"unit_volume": 0.0
	}
	var res = VendorTradeVM.build_price_presenter(item, "sell", 5, null)
	assert_eq(res.unit_price, 10.0, "Sell price should use vendor water_price for bulk resources")
	assert_eq(res.total_price, 50.0)
	assert_eq(res.added_weight, -5.0)
	assert_eq(res.bbcode_text.find("Quantity"), -1)

func test_build_price_presenter_vehicle_pricing():
	# Vehicles should NOT be halved in sell mode
	var item = {
		"name": "Truck",
		"vehicle_id": "v1",
		"base_value": 1000.0,
		"value": 1000.0, # Explicit value often used by PriceUtil for vehicles
		"base_top_speed": 100
	}
	
	# Buy
	var res_buy = VendorTradeVM.build_price_presenter(item, "buy", 1, null)
	assert_eq(res_buy.unit_price, 1000.0, "Vehicle buy price should match value")
	
	# Sell
	var res_sell = VendorTradeVM.build_price_presenter(item, "sell", 1, null)
	assert_eq(res_sell.unit_price, 1000.0, "Vehicle sell price should NOT be halved")
	assert_eq(res_sell.total_price, 1000.0)

func test_mass_volume_projection_zero_guards():
	# Item with no physical stats
	var item = {
		"name": "Ghost Item",
		"base_value": 10.0
	}
	
	var res = VendorTradeVM.build_price_presenter(item, "buy", 1, null)
	
	# Assert: Projections are strictly zero
	assert_eq(res.added_weight, 0.0)
	assert_eq(res.added_volume, 0.0)
	
	# Assert: Text summary doesn't mention weight/volume
	assert_eq(res.bbcode_text.find("Order Weight"), -1, "Should not show weight line if 0")
	assert_eq(res.bbcode_text.find("Order Volume"), -1, "Should not show volume line if 0")

func test_is_vehicle_item_detection():
	# 1. Deep vehicle object (full stats)
	var deep_veh = { "vehicle_id": "v1", "base_top_speed": 100, "name": "Truck" }
	assert_true(VendorTradeVM.is_vehicle_item(deep_veh), "Should detect deep vehicle object")

	# 2. Shallow vehicle object (inventory list) - Critical for Phase 2 fetch trigger
	var shallow_veh = { "vehicle_id": "v2", "name": "Truck" }
	assert_true(VendorTradeVM.is_vehicle_item(shallow_veh), "Should detect shallow vehicle object to trigger fetch")

	# 3. Cargo item referencing a vehicle (e.g. part or installed item)
	var cargo_ref = { "vehicle_id": "v1", "cargo_id": "c1", "name": "Box" }
	assert_false(VendorTradeVM.is_vehicle_item(cargo_ref), "Should NOT detect cargo with vehicle_id as a vehicle item")

	# 4. Raw resource
	var resource = { "vehicle_id": "v1", "is_raw_resource": true, "fuel": 10 }
	assert_false(VendorTradeVM.is_vehicle_item(resource), "Should NOT detect resource with vehicle_id as a vehicle item")

func test_build_price_presenter_mission_rewards():
	var item = {
		"name": "Mission Item",
		"base_value": 0.0,
		"unit_delivery_reward": 50.0
	}
	var res = VendorTradeVM.build_price_presenter(item, "buy", 3, null)
	assert_eq(res.total_delivery_reward, 150.0, "Should calculate total delivery reward")
