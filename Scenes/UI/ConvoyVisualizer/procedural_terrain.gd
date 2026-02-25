extends Node2D
class_name ProceduralTerrain

@export var camera: Camera2D
@export var chunk_width: float = 2000.0
@export var terrain_depth: float = 1000.0 # How far down the polygon goes
@export var point_step: float = 50.0 # X distance between points in the polygon

var terrain_difficulty: float = 0.5
var noise: FastNoiseLite
var chunks: Dictionary = {}

func _ready() -> void:
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = randi()

func _process(_delta: float) -> void:
	if not camera: return
	
	var cam_x = camera.global_position.x
	var target_chunk_idx = floor(cam_x / chunk_width)
	
	# Ensure chunks around the camera exist
	for i in range(target_chunk_idx - 1, target_chunk_idx + 3):
		if not chunks.has(i):
			_spawn_chunk(i)
			
	# Cleanup old chunks
	var keys = chunks.keys().duplicate()
	for k in keys:
		if k < target_chunk_idx - 2:
			if is_instance_valid(chunks[k]):
				chunks[k].queue_free()
			chunks.erase(k)

func _spawn_chunk(idx: int) -> void:
	var chunk_start_x = idx * chunk_width
	
	var static_body = StaticBody2D.new()
	var collider = CollisionPolygon2D.new()
	var visual = Polygon2D.new()
	
	var points = PackedVector2Array()
	
	# Update noise parameters based on difficulty
	# Higher difficulty = higher amplitude and higher frequency (more bumpy)
	var amplitude = lerp(10.0, 100.0, terrain_difficulty)
	var freq = lerp(0.001, 0.006, terrain_difficulty)
	noise.frequency = freq
	
	for x_offset in range(0, int(chunk_width + point_step), int(point_step)):
		var world_x = chunk_start_x + x_offset
		var height = noise.get_noise_1d(world_x) * amplitude
		points.append(Vector2(x_offset, height))
		
	# Bottom corners to close the polygon
	points.append(Vector2(chunk_width, terrain_depth))
	points.append(Vector2(0, terrain_depth))
	
	collider.polygon = points
	visual.polygon = points
	visual.color = _get_terrain_color()
	
	static_body.position.x = chunk_start_x
	static_body.add_child(collider)
	static_body.add_child(visual)
	
	# Put terrain on collision layer 1
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	
	add_child(static_body)
	chunks[idx] = static_body

func _get_terrain_color() -> Color:
	# Gray (difficulty 0) -> Brown (difficulty ~0.5) -> Green (difficulty 1.0)
	var gray = Color(0.45, 0.44, 0.42)
	var brown = Color(0.45, 0.30, 0.18)
	var green = Color(0.22, 0.42, 0.20)
	
	if terrain_difficulty < 0.5:
		return gray.lerp(brown, terrain_difficulty * 2.0)
	else:
		return brown.lerp(green, (terrain_difficulty - 0.5) * 2.0)

func set_difficulty(d: float) -> void:
	terrain_difficulty = clamp(d, 0.0, 1.0)

func regenerate() -> void:
	for k in chunks.keys():
		if is_instance_valid(chunks[k]):
			chunks[k].queue_free()
	chunks.clear()
	noise.seed = randi() # New seed so terrain visibly changes
