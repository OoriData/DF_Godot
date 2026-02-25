extends Node2D

var vehicle: Node2D = null

func _draw() -> void:
	if not vehicle or not is_instance_valid(vehicle.chassis): return
	
	var tel = vehicle.telemetry
	var chassis_xform = vehicle.chassis.global_transform
	
	# 1. DRAW TARGET LINE
	var target_rel_x = (vehicle.target_world_x - vehicle.global_position.x)
	draw_line(Vector2(target_rel_x, -150), Vector2(target_rel_x, 50), Color(0, 1, 1, 0.4), 1.0)
	
	for i in range(vehicle._wheel_bodies.size()):
		var w = vehicle._wheel_bodies[i]
		if not is_instance_valid(w): continue
		
		var attach_world = chassis_xform * Vector2(vehicle._wheel_attach_xs[i], 0)
		var wheel_local = w.global_position - vehicle.global_position
		draw_circle(wheel_local, 4.0, Color.GREEN)
		
		# 2. DRAW TORQUE ARROWS (Propulsion/Braking)
		var torque = tel.torque
		if tel.mode == "BRAKE": torque = - sign(w.angular_velocity) * 1000.0 # Force visual for brake
		
		if abs(torque) > 1.0:
			var arrow_dir = Vector2(sign(torque) * vehicle.travel_direction, 0)
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
