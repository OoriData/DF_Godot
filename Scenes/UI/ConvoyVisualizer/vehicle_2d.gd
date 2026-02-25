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

var _wheel_bodies: Array[RigidBody2D] = []
var _cargo_bodies: Array[RigidBody2D] = []
var _wheel_attach_xs: Array[float] = [] # X positions on chassis where each wheel connects
var _wheel_rest_y: float = 0.0 # Rest Y offset of wheel from chassis

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

		var wheel = RigidBody2D.new()
		wheel.position = Vector2(wx, radius * 0.5)
		wheel.mass = chassis.mass * 0.15

		var phys_mat = PhysicsMaterial.new()
		phys_mat.friction = 1.0
		phys_mat.rough = true
		wheel.physics_material_override = phys_mat

		var w_col = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = radius
		w_col.shape = circle
		wheel.add_child(w_col)

		var w_vis_top = Polygon2D.new()
		w_vis_top.color = Color.DARK_GRAY
		w_vis_top.polygon = _create_semicircle_poly(radius, 0.0)
		wheel.add_child(w_vis_top)

		var w_vis_bot = Polygon2D.new()
		w_vis_bot.color = Color(0.55, 0.55, 0.55)
		w_vis_bot.polygon = _create_semicircle_poly(radius, PI)
		wheel.add_child(w_vis_bot)
		wheel.collision_layer = 2 # bit 2 (Layer 2)
		wheel.collision_mask = 1 # ONLY collide with ground

		# Isolated layers mean no exceptions are strictly necessary,
		# but we keep them as a cheap fail-safe.
		wheel.add_collision_exception_with(chassis)
		chassis.add_collision_exception_with(wheel)

		wheels_container.add_child(wheel)
		_wheel_bodies.append(wheel)
		_wheel_attach_xs.append(wx)
		# No joints! Constraints are applied manually in _physics_process

	_wheel_rest_y = radius

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
		for wheel in _wheel_bodies:
			cb.add_collision_exception_with(wheel)
			wheel.add_collision_exception_with(cb)

func set_moving(state: bool) -> void:
	_is_moving = state

# --- Tuning Parameters ---
var stiffness: float = 250.0
var damping: float = 10.0
var lateral_stiffness: float = 1000.0
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
	_apply_constraints(delta)

	var torque = 0.0
	if _is_moving:
		torque = _calculate_propulsion_torque(delta)
	else:
		torque = _calculate_idle_braking(delta)

	_apply_drive_torque(torque)

func _update_telemetry() -> void:
	telemetry.speed = chassis.linear_velocity.x * travel_direction
	telemetry.distance_error = (target_world_x - chassis.global_position.x) * travel_direction
	telemetry.valid_wheels = _wheel_bodies.size()

func _apply_constraints(delta: float) -> void:
	for i in range(_wheel_bodies.size()):
		var w = _wheel_bodies[i]
		if not is_instance_valid(w): continue

		# Ensure bodies don't sleep so constraints always run
		w.sleeping = false
		chassis.sleeping = false

		var attach_local_offset = Vector2(_wheel_attach_xs[i], 0)
		var chassis_xform = chassis.global_transform
		var attach_world = chassis_xform * attach_local_offset

		var local_down = chassis_xform.basis_xform(Vector2(0, 1)).normalized()
		var local_right = chassis_xform.basis_xform(Vector2(1, 0)).normalized()

		# 1. LATERAL CONSTRAINT (Soft Force-based pull)
		var wheel_to_attach = w.global_position - attach_world
		var lateral_dist = wheel_to_attach.dot(local_right)
		var vel_diff = w.linear_velocity - chassis.linear_velocity
		var lateral_vel_diff = vel_diff.dot(local_right)

		# Restoring stiffness and high damping to keep wheels vertically aligned
		var lateral_force_mag = - (lateral_stiffness * w.mass) * lateral_dist - (80.0 * w.mass) * lateral_vel_diff
		w.apply_central_force(local_right * lateral_force_mag)
		chassis.apply_central_force(-local_right * lateral_force_mag)

		# Extra wheel damping to kill jitter from high stiffness
		w.linear_velocity *= 0.99

		# 2. SUSPENSION SPRING
		var axial_dist = wheel_to_attach.dot(local_down)
		var displacement = axial_dist - _wheel_rest_y

		# Main linear spring
		var spring_force_mag = - (stiffness * _weight_class) * displacement - (damping * _weight_class) * vel_diff.dot(local_down)

		# 3. BUMP STOPS (Non-linear force at limits)
		var max_travel = _wheel_rest_y * 1.5
		var upper_limit = - max_travel * 0.8 # Wheel hitting chassis
		var lower_limit = max_travel * 0.8 # Wheel over-extending

		# If near upper limit, apply exponentially more force pushing DOWN
		if displacement < upper_limit:
			var over_limit = upper_limit - displacement
			spring_force_mag += (stiffness * 10.0 * _weight_class) * over_limit

		# If near lower limit, apply force pulling UP
		elif displacement > lower_limit:
			var over_limit = displacement - lower_limit
			spring_force_mag -= (stiffness * 5.0 * _weight_class) * over_limit

		w.apply_central_force(local_down * spring_force_mag)
		chassis.apply_central_force(-local_down * spring_force_mag)

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
			for w_body in _wheel_bodies:
				if is_instance_valid(w_body) and abs(w_body.angular_velocity) > 0.1:
					w_body.apply_torque(-sign(w_body.angular_velocity) * brake_torque * brake_mag * chassis.mass * delta)
			throttle = 0.0
		else:
			telemetry.mode = "REVERSE"
			throttle = clamp(dist / 100.0, -1.2, 0.0)

	# Soft Speed Cap (700-800 unit range)
	if speed > 700.0:
		throttle *= (1.0 - clamp((speed - 700.0) / 100.0, 0.0, 1.0))

	telemetry.throttle = throttle
	var torque = propulsion_torque * throttle * chassis.mass * delta
	telemetry.torque = torque

	# Rolling resistance emulated by drag
	for w_body in _wheel_bodies:
		if is_instance_valid(w_body):
			w_body.angular_velocity *= 0.985

	return torque * travel_direction

func _calculate_idle_braking(delta: float) -> float:
	telemetry.mode = "IDLE"
	telemetry.throttle = 0.0
	telemetry.torque = 0.0

	var vel = chassis.linear_velocity.x
	var torque = 0.0
	if abs(vel) > 5.0:
		torque = - sign(vel) * brake_torque * chassis.mass * delta

	for w_body in _wheel_bodies:
		if is_instance_valid(w_body):
			w_body.angular_velocity *= 0.85

	return torque

func _apply_drive_torque(torque: float) -> void:
	if torque == 0.0: return
	for i in range(_wheel_bodies.size()):
		var is_driven = i >= _driven_wheels.size() or _driven_wheels[i]
		if is_driven:
			var w = _wheel_bodies[i]
			if is_instance_valid(w):
				w.apply_torque(torque)
