extends Control

@onready var vehicles_node: Node2D = $SubViewportContainer/SubViewport/World/Vehicles
@onready var camera: Camera2D = $SubViewportContainer/SubViewport/World/Camera2D
@onready var parallax_bg: ParallaxBackground = $SubViewportContainer/SubViewport/World/ParallaxBackground

var vehicle_scene: PackedScene = preload("res://Scenes/UI/ConvoyVisualizer/Vehicle2D.tscn")
var current_convoy_data: Dictionary = {}

# Keep track of active vehicle nodes
var vehicle_nodes: Array[Node2D] = []
var base_scroll_speed: float = 400.0
var is_moving: bool = false

func _ready() -> void:
	# By default, don't move
	is_moving = false

func _process(delta: float) -> void:
	if is_moving:
		parallax_bg.scroll_offset.x -= base_scroll_speed * delta

func initialize_with_convoy(convoy_data: Dictionary) -> void:
	current_convoy_data = convoy_data.duplicate(true)
	_build_convoy()
	_update_movement_state()

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
	var spacing: float = 250.0
	var current_x: float = 0.0
	
	for v_data in vehicle_data_list:
		if not (v_data is Dictionary): continue
		
		# Assuming standard parsing logic from Vehicle.gd
		var v_id = String(v_data.get("vehicle_id", v_data.get("id", "")))
		var v_color = String(v_data.get("color", ""))
		var v_shape = String(v_data.get("shape", ""))
		var v_weight = float(v_data.get("weight_class", 0.0))
		
		var v_node = vehicle_scene.instantiate()
		vehicles_node.add_child(v_node)
		v_node.position = Vector2(current_x, 0)
		v_node.setup(v_color, v_shape, v_weight)
		
		vehicle_nodes.append(v_node)
		
		# Adjust spacing for the next vehicle, placing newer vehicles behind
		current_x -= spacing
		
	# Adjust camera to roughly center the convoy
	if vehicle_nodes.size() > 0:
		var total_width = (vehicle_nodes.size() - 1) * spacing
		camera.position.x = - total_width / 2.0
