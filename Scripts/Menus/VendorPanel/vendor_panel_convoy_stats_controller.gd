extends RefCounted
class_name VendorPanelConvoyStatsController

# Convoy stats + capacity bar updates extracted from vendor_trade_panel.gd.
# Operates on the panel instance to preserve behavior while isolating buggy math/UI.

static func update_convoy_info_display(panel: Object, projected_volume_delta: float = 0.0, projected_weight_delta: float = 0.0) -> void:
	if not panel.is_node_ready():
		return

	# Money display is removed per requirements.
	if is_instance_valid(panel.convoy_money_label):
		panel.convoy_money_label.visible = false

	if panel.convoy_data == null:
		if is_instance_valid(panel.convoy_cargo_label):
			panel.convoy_cargo_label.text = "Cargo: N/A"
		return
	if not (panel.convoy_data is Dictionary):
		if is_instance_valid(panel.convoy_cargo_label):
			panel.convoy_cargo_label.text = "Cargo: N/A"
		return

	var convoy_data: Dictionary = panel.convoy_data

	# --- Volume ---
	var total_volume: float = float(convoy_data.get("total_cargo_capacity", 0.0))
	var free_volume: float = float(convoy_data.get("total_free_space", 0.0))
	var used_volume: float = total_volume - free_volume

	# --- Weight ---
	var weight_capacity: float = float(convoy_data.get("total_weight_capacity", 0.0))
	var weight_used: float = weight_capacity - float(convoy_data.get("total_remaining_capacity", 0.0))
	if weight_used < 0.0:
		weight_used = 0.0

	# Needed for fallback logic below
	var vlist_any: Variant = convoy_data.get("vehicle_details_list", [])

	# Cache stats (guard negatives).
	panel._convoy_used_volume = max(0.0, used_volume)
	panel._convoy_total_volume = max(0.0, total_volume)

	# Fallback: if volume capacity is missing, estimate from vehicles and cargo.
	if panel._convoy_total_volume <= 0.0 and vlist_any is Array:
		var sum_volume: float = 0.0
		var total_capacity: float = 0.0
		for vehicle_any2 in (vlist_any as Array):
			if not (vehicle_any2 is Dictionary):
				continue
			var vehicle2: Dictionary = vehicle_any2
			total_capacity += float(vehicle2.get("cargo_capacity", 0.0))
			var cargo_any2: Variant = vehicle2.get("cargo", [])
			if cargo_any2 is Array:
				for c_any2 in (cargo_any2 as Array):
					if c_any2 is Dictionary:
						sum_volume += float((c_any2 as Dictionary).get("volume", 0.0))
		panel._convoy_total_volume = max(panel._convoy_total_volume, total_capacity)
		panel._convoy_used_volume = max(panel._convoy_used_volume, sum_volume)

	panel._convoy_used_weight = max(0.0, weight_used if weight_used >= 0.0 else 0.0)
	panel._convoy_total_weight = max(0.0, weight_capacity if weight_capacity >= 0.0 else 0.0)

	# Fallback: if weight capacity is missing, estimate from vehicles.
	if panel._convoy_total_weight <= 0.0 and vlist_any is Array:
		var total_weight_capacity: float = 0.0
		for vehicle_any3 in (vlist_any as Array):
			if not (vehicle_any3 is Dictionary):
				continue
			var vdict: Dictionary = vehicle_any3
			total_weight_capacity += float(vdict.get("weight_capacity", vdict.get("max_weight", 0.0)))
		panel._convoy_total_weight = max(panel._convoy_total_weight, total_weight_capacity)

	# Compose label text.
	var weight_segment: String = ""
	if weight_used >= 0.0:
		if weight_capacity >= 0.0:
			weight_segment = " | Weight: %.1f / %.1f" % [float(panel._convoy_used_weight), float(panel._convoy_total_weight)]
		else:
			weight_segment = " | Weight: %.1f" % float(panel._convoy_used_weight)

	if is_instance_valid(panel.convoy_cargo_label):
		panel.convoy_cargo_label.text = "Volume: %.1f / %.1f%s" % [float(panel._convoy_used_volume), float(panel._convoy_total_volume), weight_segment]

	# Update capacity bars with current usage plus any projection.
	refresh_capacity_bars(panel, projected_volume_delta, projected_weight_delta)


static func refresh_capacity_bars(panel: Object, projected_volume_delta: float, projected_weight_delta: float) -> void:
	if is_instance_valid(panel.convoy_volume_bar):
		if float(panel._convoy_total_volume) > 0.0:
			panel.convoy_volume_bar.visible = true
			panel.convoy_volume_bar.max_value = float(panel._convoy_total_volume)
			var projected_vol: float = clamp(float(panel._convoy_used_volume) + projected_volume_delta, 0.0, float(panel._convoy_total_volume))
			panel.convoy_volume_bar.value = projected_vol
			panel.convoy_volume_bar.tooltip_text = "Volume: %.2f / %.2f" % [projected_vol, float(panel._convoy_total_volume)]
			var vol_pct: float = projected_vol / max(0.00001, float(panel._convoy_total_volume))
			panel.convoy_volume_bar.self_modulate = _bar_color_for_pct(vol_pct)
		else:
			panel.convoy_volume_bar.visible = false

	if is_instance_valid(panel.convoy_weight_bar):
		if float(panel._convoy_total_weight) > 0.0:
			panel.convoy_weight_bar.visible = true
			panel.convoy_weight_bar.max_value = float(panel._convoy_total_weight)
			var projected_wt: float = clamp(float(panel._convoy_used_weight) + projected_weight_delta, 0.0, float(panel._convoy_total_weight))
			panel.convoy_weight_bar.value = projected_wt
			panel.convoy_weight_bar.tooltip_text = "Weight: %.2f / %.2f" % [projected_wt, float(panel._convoy_total_weight)]
			var wt_pct: float = projected_wt / max(0.00001, float(panel._convoy_total_weight))
			panel.convoy_weight_bar.self_modulate = _bar_color_for_pct(wt_pct)
		else:
			panel.convoy_weight_bar.visible = false


static func _bar_color_for_pct(pct: float) -> Color:
	# Green <= 70%, Yellow <= 90%, Red > 90%
	if pct <= 0.7:
		return Color(0.2, 0.8, 0.2)
	elif pct <= 0.9:
		return Color(1.0, 0.8, 0.2)
	else:
		return Color(1.0, 0.3, 0.3)
