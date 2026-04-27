extends SceneTree

func _init():
	print("Starting CargoSorter Test...")
	
	var cargo_array = [
		{"id": "c1", "unit_delivery_reward": 100.0, "unit_price": 50.0},
		{"id": "c2", "unit_delivery_reward": {"amount": 200, "currency": "credits"}, "unit_price": 50.0}, # Malformed
		{"id": "c3", "unit_delivery_reward": 150.0, "unit_price": 50.0}
	]
	
	print("Sorting with malformed data...")
	# Should not crash, should log a warning (if Logger is ready, or print fallback)
	var sorted = CargoSorter.sort_cargo(cargo_array, CargoSorter.SortMetric.PROFIT_MARGIN_PER_UNIT)
	
	print("Sort complete. Results:")
	for item in sorted:
		var price = CargoSorter.get_unit_purchase_price(item)
		var reward = CargoSorter.get_unit_delivery_reward(item, {})
		print("  ID: %s, Reward: %s, Price: %s, Margin: %s" % [item.id, reward, price, reward - price])
	
	quit()
