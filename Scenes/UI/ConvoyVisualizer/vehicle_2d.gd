extends Node2D

@onready var chassis = $Chassis
@onready var sprite = %VehicleSprite
@onready var error_rect = %ErrorRect
@onready var wheels_container = $Wheels
@onready var joints_container = $Joints
@onready var cargo_container = $CargoBed

var _color: String = ""
var _shape: String = ""
var _weight_class: float = 0.0

const NORMALIZED_WIDTH: float = 200.0
const SPRITE_DIR = "res://Assets/vehicle_sprites/"

var _is_moving: bool = false
var _driven_wheels: Array = []
var _cargo_data: Array = []

var target_world_x: float = 0.0
var travel_direction: float = 1.0

var _wheel_rays: Array[RayCast2D] = []
var _wheel_visuals: Array[Node2D] = []
var _prev_spring_lengths: Array[float] = []
var _wheel_grounded: Array[bool] = []
var _wheel_suspension_forces: Array[float] = []

var _cargo_bodies: Array[RigidBody2D] = []
var _wheel_attach_xs: Array[float] = [] # X positions on chassis where each wheel connects
var _wheel_rest_y: float = 0.0 # Rest Y offset of wheel from chassis
var _wheel_max_travel: float = 0.0

var _body_layer_bit: int = 0

func setup(vehicle_color: String, vehicle_shape: String, vehicle_weight_class: float, driven: Array = [], cargo: Array = [], direction: float = 1.0, layer_idx: int = 0) -> void:
	_color = vehicle_color
	_shape = vehicle_shape # Keep case for mapping check
	_weight_class = vehicle_weight_class
	if _weight_class <= 0.0:
		_weight_class = 1.0
	_driven_wheels = driven.duplicate()
	_cargo_data = cargo.duplicate()

	travel_direction = sign(direction)
	if travel_direction == 0: travel_direction = 1.0

	# Unique layer for this vehicle's body+cargo starting at bit 3 (Layer 4)
	# Max 16 vehicles comfortably within 32-bit int limit for layers
	_body_layer_bit = 1 << (3 + (layer_idx % 16))

	_apply_visuals()
	_build_physics()

func _parse_color(color_str: String) -> Color:
	var s = color_str.strip_edges()
	if s.is_empty():
		return Color(0.7, 0.7, 0.7, 1.0)

	var normalized = s.to_lower().replace(" ", "").replace("_", "")
	var custom_map = {
		"olivedrab": Color(0.42, 0.56, 0.14),
		"drab": Color(0.59, 0.53, 0.44),
		"tan": Color(0.82, 0.71, 0.55),
		"navy": Color.NAVY_BLUE,
		"forest": Color.FOREST_GREEN,
		"maroon": Color.MAROON,
		"beige": Color(0.96, 0.90, 0.70),
		"gray": Color(0.75, 0.75, 0.75),
		"grey": Color(0.75, 0.75, 0.75),
		"black": Color(0.5, 0.5, 0.5),
		"silver": Color(0.9, 0.9, 0.9),
		"brown": Color(0.45, 0.28, 0.18),
		"pink": Color(1.0, 0.6, 0.8),
		"orange": Color(1.0, 0.4, 0.0),
		"yellow": Color(1.0, 0.9, 0.1)
	}

	if custom_map.has(normalized):
		return custom_map[normalized]

	var c = Color.from_string(s, Color.TRANSPARENT)
	if c != Color.TRANSPARENT:
		return c
	return Color.GRAY

func _apply_visuals() -> void:
	var path = SPRITE_DIR + _shape + ".png"
	var has_sprite = FileAccess.file_exists(path)

	sprite.visible = has_sprite
	error_rect.visible = not has_sprite
	sprite.flip_h = (travel_direction < 0)

	if has_sprite:
		var texture = load(path)
		if texture:
			sprite.texture = texture

		var color_low = _color.to_lower().strip_edges()
		var is_rainbow = color_low == "striped rainbow livery"
		var is_camo = color_low == "jungle camoflauge"
		var is_police = color_low == "police livery"

		var target_color = _parse_color(_color)

		if sprite.material is ShaderMaterial:
			var final_target = target_color
			if is_rainbow or is_camo or is_police:
				final_target = Color.WHITE

			sprite.material.set_shader_parameter("target_color", final_target)
			sprite.material.set_shader_parameter("rainbow_mode", is_rainbow)
			sprite.material.set_shader_parameter("camo_mode", is_camo)
			sprite.material.set_shader_parameter("police_mode", is_police)

		sprite.modulate = Color.WHITE

		var tex_w = sprite.texture.get_width()
		var base_scale = NORMALIZED_WIDTH / tex_w
		var weight_scale: float = 1.0 + (_weight_class * 0.2)
		sprite.scale = Vector2(base_scale, base_scale) * weight_scale

		var tex_h = sprite.texture.get_height()
		var scaled_h = tex_h * sprite.scale.y
		sprite.position = Vector2(0, -scaled_h / 2.0)
	else:
		var weight_scale: float = 1.0 + (_weight_class * 0.2)
		var target_size = NORMALIZED_WIDTH * weight_scale
		error_rect.size = Vector2(target_size, target_size)
		error_rect.position = Vector2(-target_size / 2.0, -target_size)
		error_rect.color = Color(1, 0, 1, 1)

func _build_physics() -> void:
	var tex_w = sprite.texture.get_width() if sprite.texture else NORMALIZED_WIDTH
	var tex_h = sprite.texture.get_height() if sprite.texture else NORMALIZED_WIDTH * 0.5
	var s_scale = sprite.scale.x

	var w = tex_w * s_scale
	var h = tex_h * sprite.scale.y

	var chassis_col = CollisionPolygon2D.new()
	var bed_depth = h * 0.3

	var points = PackedVector2Array([
		Vector2(-w / 2, -h), Vector2(-w / 2 + 20, -h),
		Vector2(-w / 2 + 20, -bed_depth), Vector2(w / 2 - 20, -bed_depth),
		Vector2(w / 2 - 20, -h), Vector2(w / 2, -h),
		Vector2(w / 2, 0), Vector2(-w / 2, 0)
	])

	if travel_direction < 0:
		var flipped_pts = PackedVector2Array()
		for i in range(points.size() - 1, -1, -1):
			flipped_pts.append(Vector2(-points[i].x, points[i].y))
		points = flipped_pts

	chassis_col.polygon = points
	chassis.add_child(chassis_col)

	# COLLISION LAYERS:
	# Layer 1: Ground/Static
	# Layer 2: All Wheels (Isolated globally)
	# Layer 4+: Unique per-vehicle Body Layer (Chassis + Cargo)

	chassis.collision_layer = _body_layer_bit
	chassis.collision_mask = 1 | _body_layer_bit # Ground + OWN Cargo only
	chassis.mass = _weight_class * 100.0

	var wheel_xs = [-w * 0.35, w * 0.35]
	var shape_low = _shape.to_lower()
	if shape_low == "semi_truck" or shape_low == "tanker" or shape_low == "container_truck":
		wheel_xs = [-w * 0.4, -w * 0.1, w * 0.4]

	if travel_direction < 0:
		var flipped_xs = []
		for wx in wheel_xs:
			flipped_xs.append(-wx)
		wheel_xs = flipped_xs

	var radius = h * 0.22

	for i in range(wheel_xs.size()):
		var wx = wheel_xs[i]

		var ray = RayCast2D.new()
		ray.position = Vector2(wx, 0)
		ray.target_position = Vector2(0, radius * 2.5) # Max travel distance + radius
		ray.collision_mask = 1 # ONLY collide with ground (Layer 1)
		# Force raycast to update before we rely on it
		ray.enabled = true
		chassis.add_child(ray)
		_wheel_rays.append(ray)

		var wheel_vis = Node2D.new()
		var w_vis_top = Polygon2D.new()
		w_vis_top.color = Color.DARK_GRAY
		w_vis_top.polygon = _create_semicircle_poly(radius, 0.0)
		wheel_vis.add_child(w_vis_top)

		var w_vis_bot = Polygon2D.new()
		w_vis_bot.color = Color(0.55, 0.55, 0.55)
		w_vis_bot.polygon = _create_semicircle_poly(radius, PI)
		wheel_vis.add_child(w_vis_bot)

		wheels_container.add_child(wheel_vis)
		_wheel_visuals.append(wheel_vis)
		_wheel_attach_xs.append(wx)
		_prev_spring_lengths.append(radius)
		_wheel_grounded.append(false)
		_wheel_suspension_forces.append(0.0)

	_wheel_rest_y = radius
	_wheel_max_travel = radius * 2.5

	_spawn_cargo()
	_setup_debug_overlay()

func _create_semicircle_poly(radius: float, start_angle: float) -> PackedVector2Array:
	var pts = PackedVector2Array()
	var segs = 12
	for i in range(segs + 1):
		var a = start_angle + (PI * i / segs)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

var _debug_overlay: Node2D = null

func _setup_debug_overlay() -> void:
	_debug_overlay = Node2D.new()
	_debug_overlay.z_index = 100
	_debug_overlay.z_as_relative = false # Absolute z so it's truly on top
	add_child(_debug_overlay)
	_debug_overlay.set_script(preload("res://Scenes/UI/ConvoyVisualizer/suspension_debug.gd"))
	_debug_overlay.vehicle = self

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return

	# Update wheel visuals based on raycasts
	for i in range(_wheel_visuals.size()):
		var vis = _wheel_visuals[i]
		var ray = _wheel_rays[i]
		if ray.is_colliding():
			var hit_point = ray.get_collision_point()
			var hit_normal = ray.get_collision_normal()
			# Place the wheel slightly above the ground contact point based on radius
			vis.global_position = hit_point + (hit_normal * _wheel_rest_y)
			# Rotate wheel visual over time to simulate rolling if moving
			if is_instance_valid(chassis):
				vis.rotation += (chassis.linear_velocity.dot(chassis.global_transform.basis_xform(Vector2.RIGHT)) * _delta) / _wheel_rest_y
		else:
			# Droop wheel to max travel
			vis.global_position = ray.global_position + (chassis.global_transform.basis_xform(Vector2.DOWN).normalized() * _wheel_max_travel)

	if _debug_overlay:
		_debug_overlay.queue_redraw()

func _spawn_cargo() -> void:
	var max_cargo = 5
	var count = min(_cargo_data.size(), max_cargo)
	if count == 0: return

	var w = NORMALIZED_WIDTH * sprite.scale.x
	var step = (w * 0.6) / float(max(1, count))
	var start_x = - (w * 0.3)


	for i in range(count):
		var cb = RigidBody2D.new()
		cb.position = Vector2(start_x + (i * step), -100)
		cb.mass = 5.0

		var col = CollisionShape2D.new()
		var r = RectangleShape2D.new()
		r.size = Vector2(25, 25)
		col.shape = r
		cb.add_child(col)

		var vis = ColorRect.new()
		vis.size = Vector2(25, 25)
		vis.position = Vector2(-12.5, -12.5)
		vis.color = Color(randf(), randf(), randf(), 1.0)
		cb.add_child(vis)

		cb.collision_layer = _body_layer_bit
		cb.collision_mask = 1 | _body_layer_bit # Ground + OWN Chassis/Cargo only

		cargo_container.add_child(cb)
		_cargo_bodies.append(cb)

		# Explicitly exempt cargo from hitting wheels (Fail-safe for layer isolation)
		# No longer necessary as wheels are purely visual under the RayCast model

func set_moving(state: bool) -> void:
	_is_moving = state

# --- Tuning Parameters ---
var stiffness: float = 250.0
var damping: float = 10.0
var propulsion_torque: float = 800000.0
var brake_torque: float = 2000000.0
var cruise_speed: float = 100.0 # Feed-forward speed from convoy

# --- Diagnostics ---
var telemetry: Dictionary = {
	"mode": "IDLE",
	"throttle": 0.0,
	"distance_error": 0.0,
	"speed": 0.0,
	"torque": 0.0,
	"valid_wheels": 0
}

func _physics_process(delta: float) -> void:
	if not is_instance_valid(chassis): return

	_update_telemetry()
	_apply_suspension(delta)

	var torque = 0.0
	if _is_moving:
		torque = _calculate_propulsion_torque(delta)
	else:
		torque = _calculate_idle_braking(delta)

	_apply_drive_torque(torque)

func _update_telemetry() -> void:
	telemetry.speed = chassis.linear_velocity.x * travel_direction
	telemetry.distance_error = (target_world_x - chassis.global_position.x) * travel_direction

	var valid_wheels = 0
	for g in _wheel_grounded:
		if g: valid_wheels += 1
	telemetry.valid_wheels = valid_wheels

func _apply_suspension(delta: float) -> void:
	# Convert parameters to "per-wheel" force multipliers based on weight class
	var p_stiffness = stiffness * _weight_class * 100.0 # Force N/m
	var p_damping = damping * _weight_class * 10.0

	for i in range(_wheel_rays.size()):
		var ray = _wheel_rays[i]

		# Reset state for telemetry/traction
		_wheel_grounded[i] = false
		_wheel_suspension_forces[i] = 0.0

		if ray.is_colliding():
			var hit_point = ray.get_collision_point()
			var hit_normal = ray.get_collision_normal()
			var dist = ray.global_position.distance_to(hit_point)

			var current_spring_len = dist - _wheel_rest_y

			# Displacement: Positive means compressed (wheel pushed up relative to rest), Negative means extended
			var displacement = _wheel_rest_y - current_spring_len

			var spring_velocity = (current_spring_len - _prev_spring_lengths[i]) / delta
			_prev_spring_lengths[i] = current_spring_len

			var force_mag = (displacement * p_stiffness) - (spring_velocity * p_damping)
			force_mag = max(0.0, force_mag) # Springs only push UP, they don't pull the chassis down

			if force_mag > 0:
				_wheel_grounded[i] = true
				_wheel_suspension_forces[i] = force_mag

				# Apply force to chassis AT the contact point
				var force_offset = hit_point - chassis.global_position
				chassis.apply_force(hit_normal * force_mag, force_offset)
		else:
			_prev_spring_lengths[i] = _wheel_max_travel

func _calculate_propulsion_torque(delta: float) -> float:
	var dist = telemetry.distance_error
	var speed = telemetry.speed
	var is_ahead = dist < 0.0
	var is_moving_forward = speed > 5.0

	# 1. Calculate Target Throttling
	var base_throttle = clamp(cruise_speed / 400.0, 0.0, 1.0)
	var throttle = 0.0

	if dist > 0:
		# P-gain on distance error + base feed-forward
		var p_throttle = dist / 150.0
		throttle = clamp(base_throttle + p_throttle, 0.0, 4.0)
		telemetry.mode = "DRIVE"
	else:
		# Ahead: reduce/reverse base throttle to settle back
		var settling = dist / 100.0 # dist is negative
		throttle = clamp(base_throttle + settling, -1.2, base_throttle)
		if throttle < 0:
			telemetry.mode = "REVERSE"
		else:
			telemetry.mode = "COAST"

	if is_ahead:
		if is_moving_forward:
			telemetry.mode = "BRAKE"
			var brake_mag = clamp(speed / 100.0, 0.5, 3.0)
			throttle = - brake_mag
		else:
			telemetry.mode = "REVERSE"
			throttle = clamp(dist / 100.0, -1.2, 0.0)

	# Soft Speed Cap (700-800 unit range)
	if speed > 700.0:
		throttle *= (1.0 - clamp((speed - 700.0) / 100.0, 0.0, 1.0))

	telemetry.throttle = throttle
	var torque = propulsion_torque * throttle * chassis.mass * delta
	telemetry.torque = torque

	return torque * travel_direction

func _calculate_idle_braking(delta: float) -> float:
	telemetry.mode = "IDLE"
	telemetry.throttle = 0.0
	telemetry.torque = 0.0

	var vel = chassis.linear_velocity.x
	var torque = 0.0
	if abs(vel) > 5.0:
		torque = - sign(vel) * brake_torque * chassis.mass * delta

	return torque

func _apply_drive_torque(torque: float) -> void:
	if abs(torque) < 1.0: return

	telemetry.torque = torque

	var driven_count = _driven_wheels.size()
	if driven_count == 0:
		driven_count = _wheel_rays.size()

	var force_per_wheel = torque / driven_count
	var local_forward = chassis.global_transform.basis_xform(Vector2.RIGHT).normalized()

	for idx in range(_wheel_rays.size()):
		var is_driven = _driven_wheels.is_empty() or (idx < _driven_wheels.size() and _driven_wheels[idx])

		if is_driven and _wheel_grounded[idx]:
			# The traction force is limited by how much normal force (suspension load) is on the wheel
			var max_traction = _wheel_suspension_forces[idx] * 1.5 # Friction coefficient
			var applied_force = clamp(force_per_wheel, -max_traction, max_traction)

			var ray = _wheel_rays[idx]
			var hit_point = ray.get_collision_point()
			var force_offset = hit_point - chassis.global_position

			# Apply forward drive force directly to chassis through the contact patch
			chassis.apply_force(local_forward * applied_force, force_offset)
