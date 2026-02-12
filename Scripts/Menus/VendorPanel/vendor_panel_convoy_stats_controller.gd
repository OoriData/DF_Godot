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
			weight_segment = " | Weight: %s / %s" % [NumberFormat.fmt_float(panel._convoy_used_weight, 2), NumberFormat.fmt_float(panel._convoy_total_weight, 2)]
		else:
			weight_segment = " | Weight: %s" % NumberFormat.fmt_float(panel._convoy_used_weight, 2)

	if is_instance_valid(panel.convoy_cargo_label):
		panel.convoy_cargo_label.text = "Volume: %s / %s%s" % [NumberFormat.fmt_float(panel._convoy_used_volume, 2), NumberFormat.fmt_float(panel._convoy_total_volume, 2), weight_segment]

	# Update capacity bars with current usage plus any projection.
	refresh_capacity_bars(panel, projected_volume_delta, projected_weight_delta)


static func refresh_capacity_bars(panel: Object, projected_volume_delta: float, projected_weight_delta: float) -> void:
	if is_instance_valid(panel.convoy_volume_bar):
		if float(panel._convoy_total_volume) > 0.0:
			panel.convoy_volume_bar.visible = true
			panel.convoy_volume_bar.max_value = float(panel._convoy_total_volume)
			var base_vol: float = clamp(float(panel._convoy_used_volume), 0.0, float(panel._convoy_total_volume))
			var projected_vol: float = clamp(base_vol + projected_volume_delta, 0.0, float(panel._convoy_total_volume))
			panel.convoy_volume_bar.value = projected_vol
			panel.convoy_volume_bar.tooltip_text = "Volume: %s / %s" % [NumberFormat.fmt_float(projected_vol, 2), NumberFormat.fmt_float(panel._convoy_total_volume, 2)]
			var vol_pct: float = projected_vol / max(0.00001, float(panel._convoy_total_volume))
			panel.convoy_volume_bar.self_modulate = _bar_color_for_pct(vol_pct)
			_update_projection_overlay(panel.convoy_volume_bar, base_vol, projected_vol, float(panel._convoy_total_volume), projected_volume_delta)
		else:
			panel.convoy_volume_bar.visible = false
			_update_projection_overlay(panel.convoy_volume_bar, 0.0, 0.0, 0.0, 0.0)

	if is_instance_valid(panel.convoy_weight_bar):
		if float(panel._convoy_total_weight) > 0.0:
			panel.convoy_weight_bar.visible = true
			panel.convoy_weight_bar.max_value = float(panel._convoy_total_weight)
			var base_wt: float = clamp(float(panel._convoy_used_weight), 0.0, float(panel._convoy_total_weight))
			var projected_wt: float = clamp(base_wt + projected_weight_delta, 0.0, float(panel._convoy_total_weight))
			panel.convoy_weight_bar.value = projected_wt
			panel.convoy_weight_bar.tooltip_text = "Weight: %s / %s" % [NumberFormat.fmt_float(projected_wt, 2), NumberFormat.fmt_float(panel._convoy_total_weight, 2)]
			var wt_pct: float = projected_wt / max(0.00001, float(panel._convoy_total_weight))
			panel.convoy_weight_bar.self_modulate = _bar_color_for_pct(wt_pct)
			_update_projection_overlay(panel.convoy_weight_bar, base_wt, projected_wt, float(panel._convoy_total_weight), projected_weight_delta)
		else:
			panel.convoy_weight_bar.visible = false
			_update_projection_overlay(panel.convoy_weight_bar, 0.0, 0.0, 0.0, 0.0)


static func _update_projection_overlay(bar: ProgressBar, base_value: float, projected_value: float, total_value: float, delta: float) -> void:
	if not is_instance_valid(bar):
		return

	# Hide overlay when no projection is active.
	var projection_active: bool = abs(delta) > 0.00001 and total_value > 0.0 and bar.visible and abs(projected_value - base_value) > 0.00001
	var segment: Panel = _ensure_projection_segment(bar)
	segment.visible = projection_active

	# Keep old marker nodes hidden (in case a previous session created them).
	var base_marker: Node = bar.get_node_or_null("ProjectionBaseMarker")
	if base_marker != null and base_marker is CanvasItem:
		(base_marker as CanvasItem).visible = false
	var proj_marker: Node = bar.get_node_or_null("ProjectionProjectedMarker")
	if proj_marker != null and proj_marker is CanvasItem:
		(proj_marker as CanvasItem).visible = false

	if not projection_active:
		return

	# 1) Ensure overlay is clipped to the bar rect.
	# (This is rectangular clipping; the segment itself will be rounded to match.)
	bar.clip_contents = true

	# Place the overlay segment between base and projected positions.
	# We align to the bar's content margins but allow the height to fill more
	# to avoid looking disconnected.
	var inner_pos := Vector2.ZERO
	var w: float = bar.size.x
	var h: float = bar.size.y
	
	var bg_sb: StyleBox = bar.get_theme_stylebox("background")
	if bg_sb != null:
		var l := float(bg_sb.get_content_margin(SIDE_LEFT))
		var r := float(bg_sb.get_content_margin(SIDE_RIGHT))
		var t := float(bg_sb.get_content_margin(SIDE_TOP))
		var b := float(bg_sb.get_content_margin(SIDE_BOTTOM))
		inner_pos = Vector2(l, t)
		w = max(1.0, bar.size.x - l - r)
		# Force full height to perfectly cover the bar.
		inner_pos.y = 0.0
		h = bar.size.y

	var base_x: float = inner_pos.x + (clamp(base_value, 0.0, total_value) / max(0.00001, total_value)) * w
	var proj_x: float = inner_pos.x + (clamp(projected_value, 0.0, total_value) / max(0.00001, total_value)) * w
	var left_x: float = min(base_x, proj_x)
	var right_x: float = max(base_x, proj_x)
	segment.position = Vector2(left_x, inner_pos.y)
	segment.size = Vector2(max(1.0, right_x - left_x), h)
	segment.z_index = 100

	# Styling: translucent fill + white border.
	var sb := StyleBoxFlat.new()
	var is_adding: bool = delta > 0.0
	sb.bg_color = (Color(0.25, 0.95, 0.85, 0.30) if is_adding else Color(1.0, 0.45, 0.45, 0.25))
	sb.border_color = Color(1.0, 1.0, 1.0, 0.80) # Brighter, clearer border
	
	# Fetch rounding from the bar's theme.
	var fill_sb: StyleBox = bar.get_theme_stylebox("fill")
	var bg_sb_actual: StyleBox = bar.get_theme_stylebox("background")
	var radius: int = int(round(h * 0.5)) # Default to pill shape
	
	if fill_sb != null and fill_sb is StyleBoxFlat:
		var f := fill_sb as StyleBoxFlat
		radius = maxi(int(f.corner_radius_top_left), int(f.corner_radius_top_right))
		radius = maxi(radius, maxi(int(f.corner_radius_bottom_left), int(f.corner_radius_bottom_right)))
	elif bg_sb_actual != null and bg_sb_actual is StyleBoxFlat:
		var b_sb := bg_sb_actual as StyleBoxFlat
		radius = maxi(int(b_sb.corner_radius_top_left), int(b_sb.corner_radius_top_right))
	
	var touches_left: bool = left_x <= (bar.get_theme_stylebox("background").get_content_margin(SIDE_LEFT) + 1.0) if bar.get_theme_stylebox("background") else left_x <= 1.0
	var touches_right: bool = right_x >= (bar.size.x - (bar.get_theme_stylebox("background").get_content_margin(SIDE_RIGHT) if bar.get_theme_stylebox("background") else 0.0) - 1.0)
	
	# Border and corner logic for "flush" appearance:
	# - Both ends now have a border for clarity (1px for inner, 2px for front).
	sb.set_border_width_all(1)
	
	if is_adding:
		# The left side (left_x) is the "inner" start.
		# The right side (right_x) is the "front" (leading edge).
		sb.corner_radius_top_left = 0
		sb.corner_radius_bottom_left = 0
		sb.border_width_left = 1 # Inner start
		sb.border_width_right = 2 # Front
		
		# The right side is the "tip" of the bar.
		sb.corner_radius_top_right = radius
		sb.corner_radius_bottom_right = radius
	else:
		# The left side (left_x) is the "front" (new tip of green).
		# The right side (right_x) is the "inner" start (where cargo used to end).
		sb.corner_radius_top_left = radius
		sb.corner_radius_bottom_left = radius
		sb.border_width_left = 2 # Front
		sb.border_width_right = 1 # Inner start
		
		# The right side is where the bar used to end.
		sb.corner_radius_top_right = radius if touches_right else 0
		sb.corner_radius_bottom_right = radius if touches_right else 0
	
	# Override: if we touch the absolute left, always round.
	if touches_left:
		sb.corner_radius_top_left = radius
		sb.corner_radius_bottom_left = radius
		# If it's touching the left at 0, both edges are visible/important.

	segment.add_theme_stylebox_override("panel", sb)


static func _ensure_marker(bar: ProgressBar, name: String) -> ColorRect:
	# Backward compatibility for previously-created marker nodes.
	var existing: Node = bar.get_node_or_null(name)
	if existing != null and existing is ColorRect:
		return existing as ColorRect
	var cr := ColorRect.new()
	cr.name = name
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(cr)
	return cr


static func _ensure_projection_segment(bar: ProgressBar) -> Panel:
	var existing: Node = bar.get_node_or_null("ProjectionSegment")
	if existing != null and existing is Panel:
		return existing as Panel
	# If a previous version created ProjectionSegment as a ColorRect, remove it.
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	var p := Panel.new()
	p.name = "ProjectionSegment"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(p)
	return p


static func _bar_color_for_pct(pct: float) -> Color:
	# Green <= 70%, Yellow <= 90%, Red > 90%
	if pct <= 0.7:
		return Color(0.2, 0.8, 0.2)
	elif pct <= 0.9:
		return Color(1.0, 0.8, 0.2)
	else:
		return Color(1.0, 0.3, 0.3)
