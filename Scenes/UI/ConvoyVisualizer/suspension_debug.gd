extends Node2D

var vehicle: Node2D = null

func _draw() -> void:
	if not vehicle or not is_instance_valid(vehicle.chassis): return
	
	var tel = vehicle.telemetry
	var chassis_xform = vehicle.chassis.global_transform
	
	# 1. DRAW TARGET LINE
	var target_rel_x = (vehicle.target_world_x - vehicle.global_position.x)
	draw_line(Vector2(target_rel_x, -150), Vector2(target_rel_x, 50), Color(0, 1, 1, 0.4), 1.0)
	
	for i in range(vehicle._wheel_rays.size()):
		var ray = vehicle._wheel_rays[i]
		if not is_instance_valid(ray): continue
		
		var ray_origin_world = ray.global_position
		var ray_origin_local = ray_origin_world - vehicle.global_position
		var ray_end_world = ray_origin_world + (chassis_xform.basis_xform(Vector2.DOWN).normalized() * vehicle._wheel_max_travel)
		var ray_end_local = ray_end_world - vehicle.global_position
		
		# Draw the maximum travel line (Grey)
		draw_line(ray_origin_local, ray_end_local, Color(0.5, 0.5, 0.5, 0.5), 2.0)
		
		if vehicle._wheel_grounded[i]:
			# Draw the actual compressed spring (Blue)
			var current_end_world = vehicle._wheel_visuals[i].global_position
			var current_end_local = current_end_world - vehicle.global_position
			draw_line(ray_origin_local, current_end_local, Color.CYAN, 3.0)
			
			# Draw an upward arrow representing the suspension force
			var force = vehicle._wheel_suspension_forces[i]
			var force_len = clamp(force / 500.0, 5.0, 100.0)
			var force_end_local = current_end_local + (chassis_xform.basis_xform(Vector2.UP).normalized() * force_len)
			draw_line(current_end_local, force_end_local, Color.YELLOW, 4.0)
		
		# 2. DRAW TORQUE ARROWS (Propulsion/Braking)
		var torque = tel.torque
		if tel.mode == "BRAKE": torque = -1000.0 # Force visual for brake
		
		if abs(torque) > 1.0:
			var arrow_dir = Vector2(sign(torque) * vehicle.travel_direction, 0)
			var wheel_local = vehicle._wheel_visuals[i].global_position - vehicle.global_position
			var arrow_start = wheel_local + Vector2(0, 30)
			# Square root scaling makes low torque values much more visible
			var arrow_len = 5.0 + sqrt(abs(torque) / 200.0)
			var arrow_end = arrow_start + arrow_dir * clamp(arrow_len, 5, 80)
			draw_line(arrow_start, arrow_end, Color.ORANGE, 3.0)
			draw_circle(arrow_end, 3.0, Color.ORANGE)

	# 3. DRAW TELEMETRY OVERLAY
	var label_pos = Vector2(-100, -180)
	var mode_color = Color.WHITE
	match tel.mode:
		"DRIVE": mode_color = Color.GREEN
		"BRAKE": mode_color = Color.RED
		"REVERSE": mode_color = Color.ORANGE
		"IDLE": mode_color = Color.GRAY
	
	var summary = "MODE: %s\nSPD: %d\nERR: %d\nTHR: %.2f" % [
		tel.mode, tel.speed, tel.distance_error, tel.throttle
	]
	# Note: draw_string requires a font, so we use a simpler approach or just color a rect
	draw_rect(Rect2(label_pos, Vector2(100, 20)), mode_color)
