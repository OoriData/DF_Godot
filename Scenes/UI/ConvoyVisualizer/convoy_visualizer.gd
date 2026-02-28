extends Control

#region Constants & Variables
@onready var vehicles_node: Node2D = $SubViewportContainer/SubViewport/World/Vehicles
@onready var camera: Camera2D = $SubViewportContainer/SubViewport/World/Camera2D
@onready var parallax_bg: ParallaxBackground = $SubViewportContainer/SubViewport/World/ParallaxBackground
@onready var procedural_terrain = $SubViewportContainer/SubViewport/World/ProceduralTerrain

@onready var debug_ui: CanvasLayer = $DebugUI
@onready var state_btn: Button = %StateButton
@onready var direction_btn: Button = %DirectionButton
@onready var reset_btn: Button = %ResetButton
@onready var diff_label: RichTextLabel = %DifficultyLabel
@onready var diff_slider: HSlider = %DifficultySlider

var vehicle_scene: PackedScene = preload("res://Scenes/UI/ConvoyVisualizer/Vehicle2D.tscn")
var current_convoy_data: Dictionary = {}

var vehicle_nodes: Array[Node2D] = []
var vehicle_offsets: Array[float] = []
var vehicle_stuck_timers: Array[float] = [] # Track how long each vehicle has been struggling

var is_moving: bool = false
var is_stuck: bool = false
var travel_direction: float = 1.0

var convoy_center_x: float = 0.0
var convoy_base_speed: float = 500.0
var _stored_difficulty: float = 1.0
#endregion

#region Initialization
func _ready() -> void:
	is_moving = false
	if procedural_terrain:
		procedural_terrain.camera = camera

	if state_btn: state_btn.toggled.connect(_on_state_toggled)
	if direction_btn: direction_btn.toggled.connect(_on_direction_toggled)
	if reset_btn: reset_btn.pressed.connect(reset_convoy)
	if diff_slider: diff_slider.value_changed.connect(set_terrain_difficulty)

	_add_physics_sliders()
#endregion

#region Debug UI & Controls
func _add_physics_sliders() -> void:
	# Find the VBoxContainer and add more controls dynamically
	var vbox = find_child("VBoxContainer", true)
	if not vbox: return

	_create_labeled_slider(vbox, "Propulsion Torque", 0, 500000, 16000, set_global_torque)
	_create_labeled_slider(vbox, "Suspension Stiffness", 0, 1000, 100, set_global_stiffness)
	_create_labeled_slider(vbox, "Suspension Damping", 1, 500, 50, set_global_damping)
	_create_labeled_slider(vbox, "Convoy Base Speed", 0, 2000, 500, func(v): convoy_base_speed = v)
	_create_labeled_slider(vbox, "Throttle P-Gain", 0, 5.0, 1.0, set_global_p_gain)
	_create_labeled_slider(vbox, "Brake Intensity", 0, 5.0, 1.0, set_global_brake_gain)
	_create_labeled_slider(vbox, "Cargo Volume Scalar", 0.0, 5.0, 1.0, set_global_cargo_volume)
	_create_labeled_slider(vbox, "Cargo Weight Scalar", 0.0, 2.0, 0.3, set_global_cargo_weight)

func _create_labeled_slider(container: Control, label_text: String, min_v: float, max_v: float, default_v: float, callback: Callable) -> void:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140

	var sld = HSlider.new()
	sld.min_value = min_v
	sld.max_value = max_v
	sld.value = default_v
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var edit = LineEdit.new()
	edit.text = str(default_v)
	edit.custom_minimum_size.x = 100

	# Sync Slider -> Edit & Callback
	sld.value_changed.connect(func(v):
		edit.text = str(int(v) if v == float(int(v)) else v)
		callback.call(v)
	)

	# Sync Edit -> Slider & Callback
	edit.text_submitted.connect(func(new_text):
		var v = new_text.to_float()
		v = clamp(v, min_v, max_v)
		sld.value = v
		edit.text = str(v)
		callback.call(v)
	)

	hbox.add_child(lbl)
	hbox.add_child(sld)
	hbox.add_child(edit)
	container.add_child(hbox)

func _on_state_toggled(pressed: bool) -> void:
	is_moving = pressed
	if state_btn:
		state_btn.text = "State: DRIVING" if pressed else "State: STOPPED"
	_update_movement_state_internal()

func _on_direction_toggled(pressed: bool) -> void:
	set_direction(-1.0 if pressed else 1.0)
	if direction_btn:
		direction_btn.text = "Direction: LEFT" if pressed else "Direction: RIGHT"

func _update_movement_state_internal() -> void:
	for v in vehicle_nodes:
		if v.has_method("set_moving"):
			v.set_moving(is_moving)
#endregion

#region Main Processing Loop
func _physics_process(delta: float) -> void:
	if vehicle_nodes.is_empty(): return

	# 1. Update virtual center (Constant speed, unless stuck)
	if is_moving and not is_stuck:
		convoy_center_x += convoy_base_speed * travel_direction * delta

	# 2. Check for stuck vehicles
	_check_stuck_status(delta)

	# 3. Apply moving state and target to vehicles
	var act_center = Vector2.ZERO
	var valid_count = 0
	for i in range(vehicle_nodes.size()):
		var v = vehicle_nodes[i]
		if not is_instance_valid(v): continue

		v.target_world_x = convoy_center_x + (vehicle_offsets[i] * travel_direction)
		if "cruise_speed" in v:
			v.cruise_speed = convoy_base_speed
		if v.has_method("set_moving"):
			v.set_moving(is_moving)

		if v.has_node("Chassis"):
			act_center += v.get_node("Chassis").global_position
			valid_count += 1

	# 4. Camera follows actual vehicles and adjusts zoom
	if valid_count > 0:
		act_center /= valid_count

		# Calculate horizontal spread
		var min_x = float(INF)
		var max_x = float(-INF)
		for v in vehicle_nodes:
			if not is_instance_valid(v) or not v.has_node("Chassis"): continue
			var cx = v.get_node("Chassis").global_position.x
			min_x = min(min_x, cx)
			max_x = max(max_x, cx)

		var spread = max_x - min_x
		var viewport_w = get_viewport_rect().size.x

		# Target zoom: we want spread + padding (e.g. 400px) to fit in viewport
		var padding = 800.0 # Increased padding for wider convoy spread
		var target_zoom_val = clamp(viewport_w / (spread + padding), 0.05, 1.0)
		var target_zoom = Vector2(target_zoom_val, target_zoom_val)

		var smooth = 1.0 - exp(-5.0 * delta)
		camera.global_position = camera.global_position.lerp(act_center, smooth)
		camera.zoom = camera.zoom.lerp(target_zoom, smooth)

		# 5. Update Telemetry UI (from lead vehicle)
		_update_debug_ui_telemetry()

func _check_stuck_status(delta: float) -> void:
	var any_stuck = false
	for i in range(vehicle_nodes.size()):
		var v = vehicle_nodes[i]
		if not is_instance_valid(v) or not "telemetry" in v: continue

		var tel = v.telemetry

		# Calculate distance error from target
		var current_x = v.get_node("Chassis").global_position.x if v.has_node("Chassis") else v.global_position.x
		var dist_error = abs(v.target_world_x - current_x)

		# 1. HARD CUT: Immediate stop if way too far behind
		if is_moving and dist_error > 600.0:
			any_stuck = true
			vehicle_stuck_timers[i] = 2.0 # Force timer full
			continue

		# 2. SOFT CHECK: Target error > 300 + struggling to move
		if is_moving and tel.throttle > 0.1 and abs(tel.speed) < 10.0 and dist_error > 300.0:
			vehicle_stuck_timers[i] += delta
		else:
			vehicle_stuck_timers[i] = 0.0

		if vehicle_stuck_timers[i] > 1.0: # Stuck for > 1 second
			any_stuck = true

	is_stuck = any_stuck
#endregion

#region Global Setters & Debug Telemetry
func _update_debug_ui_telemetry() -> void:
	if vehicle_nodes.is_empty(): return
	var lead = vehicle_nodes[0]
	if not is_instance_valid(lead) or not "telemetry" in lead: return

	var tel = lead.telemetry
	var tel_text = "[color=cyan]LEAD VEHICLE TELEMETRY[/color]\n"
	tel_text += "MODE: %s | SPEED: %d\n" % [tel.mode, tel.speed]
	tel_text += "ERROR: %d | THROTTLE: %.2f\n" % [tel.distance_error, tel.throttle]
	tel_text += "TORQUE: %d" % [tel.torque]

	# If we have a dedicated label, use it. Otherwise, hijack the diff label for now
	# or better, just print it to the diff label temporarily
	if diff_label:
		var base_text = "[center]Terrain Difficulty: %d[/center]\n" % int(_stored_difficulty)
		diff_label.text = base_text + "[font_size=12]" + tel_text + "[/font_size]"

func set_global_torque(val: float) -> void:
	for v in vehicle_nodes:
		if is_instance_valid(v): v.propulsion_torque = val

func set_global_stiffness(val: float) -> void:
	for v in vehicle_nodes:
		if is_instance_valid(v):
			v.stiffness = val

func set_global_damping(val: float) -> void:
	for v in vehicle_nodes:
		if is_instance_valid(v):
			v.damping = val

func set_global_p_gain(val: float) -> void:
	for v in vehicle_nodes:
		if is_instance_valid(v):
			v.p_gain = val

func set_global_brake_gain(val: float) -> void:
	for v in vehicle_nodes:
		if is_instance_valid(v):
			v.brake_gain = val

func set_global_cargo_volume(val: float) -> void:
	for v in vehicle_nodes:
		if is_instance_valid(v) and v.has_method("set_cargo_volume_scalar"):
			v.cargo_volume_scalar = val

func set_global_cargo_weight(val: float) -> void:
	for v in vehicle_nodes:
		if is_instance_valid(v) and v.has_method("set_cargo_weight_scalar"):
			v.cargo_weight_scalar = val


func set_terrain_difficulty(dif: float) -> void:
	_stored_difficulty = dif
	if procedural_terrain:
		# Normalize integer 1-9 to 0.0-1.0 for the terrain generator
		procedural_terrain.set_difficulty((dif - 1.0) / 8.0)
	if diff_label:
		diff_label.text = "[center]Terrain Difficulty: " + str(int(dif)) + "[/center]"
#endregion

#region Convoy Management
func initialize_with_convoy(convoy_data: Dictionary) -> void:
	current_convoy_data = convoy_data.duplicate(true)

	# Extract convoy top speed or find lowest top speed among vehicles
	var c_top_speed = float(current_convoy_data.get("top_speed", -1.0))
	if c_top_speed < 0:
		var vehicles = current_convoy_data.get("vehicle_details_list", current_convoy_data.get("vehicles", []))
		for v in vehicles:
			if v is Dictionary and v.has("top_speed"):
				var v_spd = float(v["top_speed"])
				if c_top_speed < 0 or v_spd < c_top_speed:
					c_top_speed = v_spd
		if c_top_speed < 0:
			c_top_speed = 50.0 # Default if wholly missing

	# Map: 0 top_speed -> 500 base_speed, 100 top_speed -> 1500 base_speed
	convoy_base_speed = lerp(500.0, 1500.0, clamp(c_top_speed / 100.0, 0.0, 1.0))

	reset_convoy()

func reset_convoy() -> void:
	convoy_center_x = 0.0
	if camera:
		camera.global_position.x = 0.0
	is_stuck = false
	if procedural_terrain:
		procedural_terrain.regenerate()
	_build_convoy()
	_update_movement_state()

func set_direction(dir: float) -> void:
	travel_direction = sign(dir)
	if travel_direction == 0: travel_direction = 1.0
	reset_convoy()

func _update_movement_state() -> void:
	# Check if the convoy is currently moving (e.g. not in a settlement and has a journey)
	var journey = current_convoy_data.get("journey", {})
	if journey and not journey.is_empty():
		is_moving = true
	else:
		is_moving = false

func _build_convoy() -> void:
	# Clear existing vehicles
	for child in vehicles_node.get_children():
		child.queue_free()
	vehicle_nodes.clear()

	var vehicle_data_list: Array = current_convoy_data.get("vehicle_details_list", current_convoy_data.get("vehicles", []))
	if vehicle_data_list.is_empty():
		push_warning("ConvoyVisualizer: No vehicles found in convoy data.")
		return

	# Spawn vehicles
	var spacing: float = 120.0 # Tighter spacing so vehicles stay on screen
	var total_count = vehicle_data_list.size()
	var start_offset: float = ((total_count - 1) * spacing) / 2.0
	var current_offset: float = start_offset

	vehicle_offsets.clear()

	var vehicle_idx = 0

	for v_data in vehicle_data_list:
		if not (v_data is Dictionary): continue

		var _v_id = String(v_data.get("vehicle_id", v_data.get("id", "")))

		var v_node = vehicle_scene.instantiate()
		vehicles_node.add_child(v_node)

		var init_x = convoy_center_x + (current_offset * travel_direction)
		v_node.position = Vector2(init_x, 0)

		# Check if this vehicle has a trailer part equipped
		var trailer_data = null
		# TRAILERS TEMPORARILY DISABLED
		# var parts = v_data.get("parts", [])
		# if parts is Array:
		# 	for p in parts:
		# 		if p is Dictionary and p.get("slot") == "trailer":
		# 			trailer_data = p
		# 			break
		# elif parts is Dictionary and parts.has("trailer"):
		# 	trailer_data = parts["trailer"]

		# Split cargo if there is a trailer
		var main_cargo = []
		var trailer_cargo = []
		var full_cargo = v_data.get("cargo", []).duplicate(true)

		if trailer_data != null:
			# Very rough split: 40% truck, 60% trailer
			var split_idx = max(1, int(full_cargo.size() * 0.4))
			for i in range(full_cargo.size()):
				if i < split_idx:
					main_cargo.append(full_cargo[i])
				else:
					trailer_cargo.append(full_cargo[i])
		else:
			main_cargo = full_cargo

		var main_v_data = v_data.duplicate(true)
		main_v_data["cargo"] = main_cargo

		# Assign a unique collision layer index (internal bits handled in vehicle_2d)
		v_node.setup(main_v_data, travel_direction, vehicle_idx, false)

		vehicle_nodes.append(v_node)
		vehicle_offsets.append(current_offset)
		vehicle_stuck_timers.append(0.0)

		# Now spawn and link the trailer if one exists
		if trailer_data != null and trailer_data is Dictionary:
			var t_node = vehicle_scene.instantiate()
			vehicles_node.add_child(t_node)

			var t_spacing = 80.0
			var t_init_x = init_x - (t_spacing * travel_direction)
			t_node.position = Vector2(t_init_x, 0)

			var t_v_data = trailer_data.duplicate(true)
			t_v_data["cargo"] = trailer_cargo

			# Fallback trailer color to match truck if not specified
			if not t_v_data.has("color") or str(t_v_data["color"]) == "":
				t_v_data["color"] = v_data.get("color", "")

			t_node.setup(t_v_data, travel_direction, vehicle_idx, true)

			vehicle_nodes.append(t_node)
			vehicle_offsets.append(current_offset - t_spacing)
			vehicle_stuck_timers.append(0.0)

			# Link them physically
			var joint = PinJoint2D.new()
			# Place joint between the two vehicles
			joint.position = Vector2(init_x - (t_spacing * travel_direction * 0.5), 0)
			joint.node_a = joint.get_path_to(v_node.get_node("Chassis"))
			joint.node_b = joint.get_path_to(t_node.get_node("Chassis"))
			joint.disable_collision = true
			# Soften the joint slightly
			joint.softness = 0.5
			vehicles_node.add_child(joint)

			# Increase total spacing to account for trailer
			current_offset -= t_spacing

		current_offset -= spacing
		vehicle_idx += 1

	if camera:
		camera.position.x = convoy_center_x
#endregion
