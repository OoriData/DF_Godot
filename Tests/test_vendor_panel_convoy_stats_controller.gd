extends GutTest

const ConvoyStats = preload("res://Scripts/Menus/VendorPanel/vendor_panel_convoy_stats_controller.gd")

class FakePanel:
	extends Control

	var convoy_data: Variant = {}
	var all_settlement_data_global: Array = []

	var convoy_money_label: Label = Label.new()
	var convoy_cargo_label: Label = Label.new()
	var convoy_volume_bar: ProgressBar = ProgressBar.new()
	var convoy_weight_bar: ProgressBar = ProgressBar.new()

	var _convoy_used_weight: float = 0.0
	var _convoy_total_weight: float = 0.0
	var _convoy_used_volume: float = 0.0
	var _convoy_total_volume: float = 0.0

func test_missing_keys_hides_bars_and_does_not_crash() -> void:
	var p := FakePanel.new()
	add_child_autofree(p)
	await get_tree().process_frame
	p.convoy_data = {}

	ConvoyStats.update_convoy_info_display(p)

	assert_true(p.convoy_cargo_label.text.begins_with("Volume:"), "Should still render a Volume label")
	assert_false(p.convoy_volume_bar.visible, "Volume bar hidden when capacity is 0")
	assert_false(p.convoy_weight_bar.visible, "Weight bar hidden when capacity is 0")


func test_negative_free_space_clamps_bar_value_to_capacity() -> void:
	var p := FakePanel.new()
	add_child_autofree(p)
	await get_tree().process_frame
	p.convoy_data = {
		"total_cargo_capacity": 10.0,
		"total_free_space": -5.0, # used becomes 15.0
		"total_weight_capacity": 100.0,
		"total_free_weight": -50.0, # used becomes 150.0
	}

	ConvoyStats.update_convoy_info_display(p)

	assert_true(p.convoy_volume_bar.visible)
	assert_eq(p.convoy_volume_bar.max_value, 10.0)
	assert_eq(p.convoy_volume_bar.value, 10.0, "Projected volume should clamp to capacity")

	assert_true(p.convoy_weight_bar.visible)
	assert_eq(p.convoy_weight_bar.max_value, 100.0)
	assert_eq(p.convoy_weight_bar.value, 100.0, "Projected weight should clamp to capacity")


func test_weight_falls_back_to_sum_of_vehicle_cargo_and_parts() -> void:
	var p := FakePanel.new()
	add_child_autofree(p)
	await get_tree().process_frame
	p.convoy_data = {
		"total_cargo_capacity": 20.0,
		"total_free_space": 10.0,
		"vehicle_details_list": [
			{
				"weight_capacity": 200.0,
				"cargo": [
					{"weight": 5.0, "volume": 1.0},
					{"weight": 7.0, "volume": 2.0},
				],
				"parts": [
					{"weight": 3.0},
				]
			}
		]
	}

	ConvoyStats.update_convoy_info_display(p)

	assert_eq(p._convoy_used_weight, 15.0, "Should sum cargo+parts weights")
	assert_eq(p._convoy_total_weight, 200.0, "Should estimate weight capacity from vehicles")
	assert_true(p.convoy_weight_bar.visible)
	assert_eq(p.convoy_weight_bar.value, 15.0)


func test_refresh_capacity_bars_applies_projection_and_color() -> void:
	var p := FakePanel.new()
	add_child_autofree(p)
	await get_tree().process_frame
	p._convoy_total_volume = 100.0
	p._convoy_used_volume = 50.0
	p._convoy_total_weight = 100.0
	p._convoy_used_weight = 50.0

	ConvoyStats.refresh_capacity_bars(p, 10.0, 10.0) # -> 60%

	assert_true(p.convoy_volume_bar.visible)
	assert_eq(p.convoy_volume_bar.value, 60.0)
	assert_eq(p.convoy_volume_bar.self_modulate, Color(0.2, 0.8, 0.2), "<=70% should be green")

	assert_true(p.convoy_weight_bar.visible)
	assert_eq(p.convoy_weight_bar.value, 60.0)
	assert_eq(p.convoy_weight_bar.self_modulate, Color(0.2, 0.8, 0.2), "<=70% should be green")
