extends GutTest

const PriceUtil = preload("res://Scripts/Menus/VendorPanel/price_util.gd")

func test_price_components_basic():
	var item := {"unit_price": 12.5, "unit_value": 3}
	var c := PriceUtil.get_item_price_components(item)
	assert_eq(c.container_unit_price, 12.5, "unit price")
	assert_eq(c.resource_unit_value, 3.0, "unit value")

func test_vehicle_price_fallbacks():
	var v1 := {"vehicle_price": 25000}
	assert_eq(PriceUtil.get_vehicle_price(v1), 25000.0)
	var v2 := {"price": {"vehicle": 12345}}
	assert_eq(PriceUtil.get_vehicle_price(v2), 12345.0)

func test_contextual_unit_price_buy_sell():
	var item := {"buy_price": 10, "sell_price": 6}
	assert_eq(PriceUtil.get_contextual_unit_price(item, "buy"), 10.0)
	assert_eq(PriceUtil.get_contextual_unit_price(item, "sell"), 6.0)
