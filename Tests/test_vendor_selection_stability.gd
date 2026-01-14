extends GutTest

var VendorTradePanel = load("res://Scripts/Menus/vendor_trade_panel.gd")
var panel

func before_each():
	panel = VendorTradePanel.new()

func after_each():
	panel.free()

func test_matches_restore_key_cargo_id():
	# Arrange
	var item_agg = { 
		"item_data": { 
			"cargo_id": "uuid-1234", 
			"name": "Box" 
		} 
	}
	var key = "uuid-1234"
	
	# Act
	var result = panel._matches_restore_key(item_agg, key)
	
	# Assert
	assert_true(result, "Should match cargo by UUID")

func test_matches_restore_key_vehicle_id():
	# Arrange
	var item_agg = { 
		"item_data": { 
			"vehicle_id": "v-999", 
			"name": "Truck" 
		} 
	}
	var key = "v-999"
	
	# Act
	var result = panel._matches_restore_key(item_agg, key)
	
	# Assert
	assert_true(result, "Should match vehicle by UUID")

func test_matches_restore_key_name_fallback():
	# Arrange
	var item_agg = { 
		"item_data": { 
			"name": "Generic Item" 
		} 
	}
	var key = "name:Generic Item"
	
	# Act
	var result = panel._matches_restore_key(item_agg, key)
	
	# Assert
	assert_true(result, "Should match by name prefix")

func test_matches_restore_key_resource():
	# Arrange
	var item_agg = { 
		"item_data": { 
			"is_raw_resource": true,
			"fuel": 100
		} 
	}
	var key = "res:fuel"
	
	# Act
	var result = panel._matches_restore_key(item_agg, key)
	
	# Assert
	assert_true(result, "Should match fuel resource key")

func test_matches_restore_key_mismatch():
	# Arrange
	var item_agg = { "item_data": { "cargo_id": "uuid-1234" } }
	var key = "uuid-5678"
	
	# Act
	var result = panel._matches_restore_key(item_agg, key)
	
	# Assert
	assert_false(result, "Should not match different IDs")
