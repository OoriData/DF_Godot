# ConvoyNode.gd
extends Node2D

@onready var icon_sprite: Sprite2D = $Sprite2D

# Data for this convoy
var convoy_data: Dictionary
var convoy_color: Color = Color.WHITE

# Reference to the TileMap for coordinate conversion
var terrain_tilemap: TileMapLayer

# Arrow drawing constants (can be tweaked or replaced with a sprite texture)
const ARROW_FORWARD_LENGTH_BASE: float = 30.0  # Was 10.0
const ARROW_BACKWARD_LENGTH_BASE: float = 9.0   # Was 3.0
const ARROW_HALF_WIDTH_BASE: float = 15.0   # Was 5.0
const ARROW_OUTLINE_THICKNESS_BASE: float = 4.5 # Was 1.5
const ARROW_DYNAMIC_SCALING_FACTOR: float = 0.7 # Adjust to make arrows smaller/larger relative to base

# Throb animation parameters
var _throb_phase: float = 0.0
const MAX_THROB_SCALE_ADDITION: float = 0.2 # e.g., 20% larger at peak
const THROB_SPEED: float = 2.0 # Radians per second for sin wave

var gdm: Node = null
var current_convoy_id: String = ""
var current_convoy_data: Dictionary = {}

func _ready():
	# Randomize throb phase slightly to desynchronize convoys
	_throb_phase = randf_range(0, 2.0 * PI)
	
	# Prepare the sprite for dynamic drawing.
	# Ensure the texture is large enough for the biggest possible arrow + outline.
	var max_dim = (ARROW_FORWARD_LENGTH_BASE + ARROW_BACKWARD_LENGTH_BASE + ARROW_OUTLINE_THICKNESS_BASE * 2) * 2
	var arrow_image = Image.create(ceil(max_dim), ceil(max_dim), false, Image.FORMAT_RGBA8)
	var arrow_texture = ImageTexture.create_from_image(arrow_image)
	icon_sprite.texture = arrow_texture
	icon_sprite.centered = true # Important for rotation and positioning around the node's origin

	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_convoy_data_updated")):
			gdm.convoy_data_updated.connect(Callable(self, "_on_convoy_data_updated"))



func set_convoy_data(p_convoy_data: Dictionary, p_color: Color, p_terrain_tilemap: TileMapLayer):
	convoy_data = p_convoy_data
	convoy_color = p_color
	terrain_tilemap = p_terrain_tilemap # Store the tilemap reference
	name = "Convoy_" + str(convoy_data.get("convoy_id", "Unknown"))
	
	# Initial update of visuals based on new data
	_update_visuals()

func _process(delta: float):
	if convoy_data.is_empty():
		return

	# Update throb animation
	_throb_phase += THROB_SPEED * delta
	# Wrap phase to avoid large numbers, though fmod or just letting it grow is fine for sin
	if _throb_phase > 2.0 * PI:
		_throb_phase -= 2.0 * PI
		
	_update_visuals()


func _update_visuals():
	if convoy_data.is_empty() or not is_instance_valid(terrain_tilemap):
		return

	# Defensively get the journey data.
	var raw_journey = convoy_data.get("journey")
	var journey_data: Dictionary = {}
	if raw_journey is Dictionary:
		journey_data = raw_journey
	var route_x: Array = journey_data.get("route_x", [])
	var route_y: Array = journey_data.get("route_y", [])
	
	# Get pre-calculated progress details from convoy_data
	var current_segment_idx: int = convoy_data.get("_current_segment_start_idx", -1)
	var progress_in_segment: float = convoy_data.get("_progress_in_segment", 0.0)

	var final_pixel_pos: Vector2
	var direction_rad: float = icon_sprite.rotation # Keep current rotation if no new direction

	if current_segment_idx != -1 and \
	   route_x.size() > current_segment_idx + 1 and route_y.size() > current_segment_idx + 1:
		
		var p_start_tile_coords = Vector2i(route_x[current_segment_idx], route_y[current_segment_idx])
		var p_end_tile_coords: Vector2i

		if route_x.size() > current_segment_idx + 1: # Standard case: segment has a defined end point
			p_end_tile_coords = Vector2i(route_x[current_segment_idx + 1], route_y[current_segment_idx + 1])
		else: # At the very last point of the path
			p_end_tile_coords = p_start_tile_coords
			if current_segment_idx > 0: # Try to get rotation from previous segment
				var p_prev_tile_coords = Vector2i(route_x[current_segment_idx - 1], route_y[current_segment_idx - 1])
				var dir_vec_tile = p_start_tile_coords - p_prev_tile_coords
				if dir_vec_tile.length_squared() > 0.0001:
					direction_rad = (Vector2(dir_vec_tile)).angle()

		# Convert tile coordinates to local pixel coordinates using the tilemap
		var p_start_pixel = terrain_tilemap.map_to_local(p_start_tile_coords)
		var p_end_pixel = terrain_tilemap.map_to_local(p_end_tile_coords)

		final_pixel_pos = p_start_pixel.lerp(p_end_pixel, progress_in_segment)
		
		# Update rotation
		if not p_start_pixel.is_equal_approx(p_end_pixel):
			var dir_vec_pixel = p_end_pixel - p_start_pixel
			if dir_vec_pixel.length_squared() > 0.0001:
				direction_rad = dir_vec_pixel.angle()
	else: # Fallback: Use the top-level x/y from convoy_data
		var map_x: float = convoy_data.get("x", 0.0)
		var map_y: float = convoy_data.get("y", 0.0)
		# This fallback assumes x/y are tile coordinates.
		final_pixel_pos = terrain_tilemap.map_to_local(Vector2i(int(map_x), int(map_y)))

	var icon_offset_px: Vector2 = convoy_data.get("_pixel_offset_for_icon", Vector2.ZERO)
	position = final_pixel_pos + icon_offset_px # Apply the lateral offset
	icon_sprite.rotation = direction_rad
	
	
	# 3. Update Throb & Arrow Drawing
	var throb_scale_multiplier: float = 1.0 + (sin(_throb_phase) * 0.5 + 0.5) * MAX_THROB_SCALE_ADDITION
	icon_sprite.scale = Vector2(throb_scale_multiplier, throb_scale_multiplier)
	# Redraw the arrow with current color and throb-influenced size (if needed)
	# For simplicity, base arrow size is fixed, throb affects sprite scale.
	_draw_arrow_on_sprite(convoy_color)


func _draw_arrow_on_sprite(fill_color: Color):
	var img: Image = icon_sprite.texture.get_image()
	if not is_instance_valid(img):
		printerr("ConvoyNode: Cannot get image from icon_sprite texture.") # Already an explicit block
		return
	
	img.fill(Color(0,0,0,0)) # Clear with transparent
	
	var center: Vector2 = img.get_size() / 2.0
	var outline_color: Color = Color.BLACK
	
	# Arrow dimensions (relative to sprite center, sprite will be rotated by node)
	# These are fixed for the sprite's internal drawing. Scaling is handled by icon_sprite.scale
	var fwd_len = ARROW_FORWARD_LENGTH_BASE * ARROW_DYNAMIC_SCALING_FACTOR
	var back_len = ARROW_BACKWARD_LENGTH_BASE * ARROW_DYNAMIC_SCALING_FACTOR
	var half_width = ARROW_HALF_WIDTH_BASE * ARROW_DYNAMIC_SCALING_FACTOR
	var outline_thick = ARROW_OUTLINE_THICKNESS_BASE * ARROW_DYNAMIC_SCALING_FACTOR

	# Outline vertices
	var ov_tip = center + Vector2(fwd_len + outline_thick, 0)
	var ov_rear_center = center + Vector2(-(back_len + outline_thick), 0)
	var ov_base_left = ov_rear_center + Vector2(0, half_width + outline_thick) # Y-up for drawing
	var ov_base_right = ov_rear_center + Vector2(0, -(half_width + outline_thick))

	# Fill vertices
	var v_tip = center + Vector2(fwd_len, 0)
	var v_rear_center = center + Vector2(-back_len, 0)
	var v_base_left = v_rear_center + Vector2(0, half_width)
	var v_base_right = v_rear_center + Vector2(0, -half_width)

	# For a filled polygon with an outline, it's often easier to draw the outline slightly larger,
	# then the fill on top, or use dedicated polygon drawing with outline features if available.
	
	# Draw outline (as a slightly larger filled polygon in black)
	_draw_filled_triangle_on_image(img, ov_tip, ov_base_left, ov_base_right, outline_color)
	# Draw fill
	_draw_filled_triangle_on_image(img, v_tip, v_base_left, v_base_right, fill_color)

	icon_sprite.texture.update(img)

func _draw_filled_triangle_on_image(image: Image, v0: Vector2, v1: Vector2, v2: Vector2, color: Color) -> void:
	""" Helper function to draw a filled triangle on an Image """
	var polygon: PackedVector2Array = [v0, v1, v2]

	# Calculate bounding box of the triangle
	var min_x: int = floor(min(v0.x, min(v1.x, v2.x)))
	var max_x: int = ceil(max(v0.x, max(v1.x, v2.x)))
	var min_y: int = floor(min(v0.y, min(v1.y, v2.y)))
	var max_y: int = ceil(max(v0.y, max(v1.y, v2.y)))

	# Clamp bounding box to image dimensions
	min_x = max(0, min_x)
	max_x = min(image.get_width() - 1, max_x)
	min_y = max(0, min_y)
	max_y = min(image.get_height() - 1, max_y)

	# Lock the image for potentially faster pixel access if drawing many pixels
	# image.lock() # Consider using for many pixel operations in Godot 4
	for y_coord in range(min_y, max_y + 1):
		for x_coord in range(min_x, max_x + 1):
			var current_pixel := Vector2(float(x_coord), float(y_coord))
			# Check center of the pixel for more accuracy with Geometry2D
			if Geometry2D.is_point_in_polygon(current_pixel + Vector2(0.5, 0.5), polygon):
				image.set_pixel(x_coord, y_coord, color)
	# image.unlock() # Pair with lock()

func show_convoy(convoy_id: String) -> void:
	current_convoy_id = convoy_id
	# Optionally, request a data refresh if needed:
	# gdm.request_convoy_data_refresh()
	_update_display()

func _on_convoy_data_updated(all_convoy_data: Array) -> void:
	# Find the convoy with the current ID
	for convoy in all_convoy_data:
		if str(convoy.get("convoy_id", "")) == str(current_convoy_id):
			current_convoy_data = convoy
			_update_display()
			return

func _update_display() -> void:
	if current_convoy_data.is_empty():
		# Hide or clear UI
		return
	# Populate your UI fields using current_convoy_data
	# Example:
	$ConvoyNameLabel.text = current_convoy_data.get("convoy_name", "Unknown Convoy")
	$ConvoyStatusLabel.text = current_convoy_data.get("status", "Unknown Status")
	# ...and so on for other UI elements...
