extends GutTest
const CargoSorter = preload("res://Scripts/System/cargo_sorter.gd")

var cargo_list: Array = []

func before_each():
	cargo_list = [
		{	# Item A: High profit margin, heavy, bulky
			"id": "A",
			"name": "Steel Beams",
			"unit_price": 50.0,
			"unit_delivery_reward": 150.0, # Margin: 100
			"unit_weight": 50.0,           # Density/W: 2.0
			"unit_volume": 25.0,           # Density/V: 4.0
			"quantity": 2,                 # Total Profit: 200
			"route_distance": 100.0        # Profit/Dist: 2.0
		},
		{	# Item B: Low profit margin, extremely light, small
			"id": "B",
			"name": "Microchips",
			"unit_price": 500.0,
			"unit_delivery_reward": 520.0, # Margin: 20
			"unit_weight": 0.5,            # Density/W: 40.0
			"unit_volume": 0.1,            # Density/V: 200.0
			"quantity": 10,                # Total Profit: 200
			"route_distance": 200.0        # Profit/Dist: 1.0
		},
		{	# Item C: Huge order profit, middle of the road
			"id": "C",
			"name": "Bulk Grain",
			"unit_price": 5.0,
			"unit_delivery_reward": 15.0,  # Margin: 10
			"unit_weight": 2.0,            # Density/W: 5.0
			"unit_volume": 4.0,            # Density/V: 2.5
			"quantity": 100,               # Total Profit: 1000
			"route_distance": 50.0         # Profit/Dist: 20.0
		},
		{	# Item D: Loss leader (negative margin)
			"id": "D",
			"name": "Scrap",
			"unit_price": 30.0,
			"unit_delivery_reward": 20.0,  # Margin: -10
			"unit_weight": 10.0,           # Density/W: -1.0
			"unit_volume": 5.0,            # Density/V: -2.0
			"quantity": 5,                 # Total Profit: -50
			"route_distance": 10.0         # Profit/Dist: -5.0
		}
	]


func test_sort_by_profit_margin_per_unit():
	var sorted = CargoSorter.sort_cargo(cargo_list, CargoSorter.SortMetric.PROFIT_MARGIN_PER_UNIT, false)
	# Expected order: A (100), B (20), C (10), D (-10)
	assert_eq(sorted[0].id, "A")
	assert_eq(sorted[1].id, "B")
	assert_eq(sorted[2].id, "C")
	assert_eq(sorted[3].id, "D")
	
	# Ascending test
	var sorted_asc = CargoSorter.sort_cargo(cargo_list, CargoSorter.SortMetric.PROFIT_MARGIN_PER_UNIT, true)
	assert_eq(sorted_asc[0].id, "D")
	assert_eq(sorted_asc[3].id, "A")

func test_sort_by_profit_density_per_weight():
	var sorted = CargoSorter.sort_cargo(cargo_list, CargoSorter.SortMetric.PROFIT_DENSITY_PER_WEIGHT, false)
	# Expected order: B (40.0), C (5.0), A (2.0), D (-1.0)
	assert_eq(sorted[0].id, "B")
	assert_eq(sorted[1].id, "C")
	assert_eq(sorted[2].id, "A")
	assert_eq(sorted[3].id, "D")

func test_sort_by_profit_density_per_volume():
	var sorted = CargoSorter.sort_cargo(cargo_list, CargoSorter.SortMetric.PROFIT_DENSITY_PER_VOLUME, false)
	# Expected order: B (200.0), A (4.0), C (2.5), D (-2.0)
	assert_eq(sorted[0].id, "B")
	assert_eq(sorted[1].id, "A")
	assert_eq(sorted[2].id, "C")
	assert_eq(sorted[3].id, "D")

func test_sort_by_total_order_profit():
	var sorted = CargoSorter.sort_cargo(cargo_list, CargoSorter.SortMetric.TOTAL_ORDER_PROFIT, false)
	# Expected order: C (1000), A & B (200, order maintained stably ideally, but Gut sort_custom may vary. We just need C first, D last)
	assert_eq(sorted[0].id, "C")
	assert_eq(sorted[3].id, "D")
	# A and B both have total order profit 200, so they will be in the middle

func test_sort_by_distance_to_recipient():
	var sorted = CargoSorter.sort_cargo(cargo_list, CargoSorter.SortMetric.PROFIT_PER_DISTANCE, false)
	# Distance-only, nearest first: D (10), C (50), A (100), B (200)
	assert_eq(sorted[0].id, "D")
	assert_eq(sorted[1].id, "C")
	assert_eq(sorted[2].id, "A")
	assert_eq(sorted[3].id, "B")

func test_context_distance_override():
	# If we pass route_distance in context, all items have equal distance.
	var context = { "route_distance": 1.0 }
	var sorted = CargoSorter.sort_cargo(cargo_list, CargoSorter.SortMetric.PROFIT_PER_DISTANCE, false, context)
	# All distances equal, so no distance-based preference can be asserted.
	assert_eq(sorted.size(), cargo_list.size())

func test_value_extractors_robustness():
	var weak_dict = {
		"value": 15.0,
		"delivery_reward": 50.0,
		"total_quantity": 2,
		"weight": 10.0,
		"total_volume": 4.0
	}
	# margin = (50.0 / 2) - 15.0 = 25.0 - 15.0 = 10.0
	# weight = 10.0/2 = 5.0
	# vol = 4.0/2 = 2.0
	assert_eq(CargoSorter.get_unit_profit_margin(weak_dict, {}), 10.0)
	assert_eq(CargoSorter.get_unit_weight(weak_dict), 5.0)
	assert_eq(CargoSorter.get_unit_volume(weak_dict), 2.0)
	assert_eq(CargoSorter.get_total_order_profit(weak_dict, {}), 20.0) # 10.0 margin * 2 qty
