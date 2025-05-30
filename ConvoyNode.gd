# ConvoyNode.gd
extends Node2D

@onready var icon_sprite: Sprite2D = $Sprite2D

# Data for this convoy
var convoy_data: Dictionary
var convoy_color: Color = Color.WHITE

# Map metrics passed from main.gd
var tile_pixel_width_on_full_texture: float = 1.0
var tile_pixel_height_on_full_texture: float = 1.0

# Arrow drawing constants (can be tweaked or replaced with a sprite texture)
const ARROW_FORWARD_LENGTH_BASE: float = 10.0
const ARROW_BACKWARD_LENGTH_BASE: float = 3.0
const ARROW_HALF_WIDTH_BASE: float = 5.0
const ARROW_OUTLINE_THICKNESS_BASE: float = 1.5
const ARROW_DYNAMIC_SCALING_FACTOR: float = 0.7 # Adjust to make arrows smaller/larger relative to base

# Throb animation parameters
var _throb_phase: float = 0.0
const MAX_THROB_SCALE_ADDITION: float = 0.2 # e.g., 20% larger at peak
const THROB_SPEED: float = 2.0 # Radians per second for sin wave

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


func set_convoy_data(p_convoy_data: Dictionary, p_color: Color, p_tile_w: float, p_tile_h: float):
	convoy_data = p_convoy_data
	convoy_color = p_color
	tile_pixel_width_on_full_texture = p_tile_w
	tile_pixel_height_on_full_texture = p_tile_h
	name = "Convoy_" + str(convoy_data.get("convoy_id", "Unknown"))
	
	# Initial update of visuals based on new data
	_update_visuals()

func _process(delta: float):
	if convoy_data.is_empty():
		return # Added explicit indent for clarity, though single-line was valid

	# Update throb animation
	_throb_phase += THROB_SPEED * delta
	# Wrap phase to avoid large numbers, though fmod or just letting it grow is fine for sin
	if _throb_phase > 2.0 * PI:
		_throb_phase -= 2.0 * PI # Added explicit indent
		
	_update_visuals()

func _update_visuals():
	if convoy_data.is_empty() or tile_pixel_width_on_full_texture <= 0:
		return # Added explicit indent

	# 1. Update Position
	# The position is local to MapContainer.
	# It's based on the convoy's map coordinates and the pixel size of tiles on the *full* map texture.
	var map_x: float = convoy_data.get("x", 0.0)
	var map_y: float = convoy_data.get("y", 0.0)
	
	position.x = (map_x + 0.5) * tile_pixel_width_on_full_texture
	position.y = (map_y + 0.5) * tile_pixel_height_on_full_texture

	# 2. Update Rotation
	var journey_data: Dictionary = convoy_data.get("journey", {})
	var route_x: Array = journey_data.get("route_x", [])
	var route_y: Array = journey_data.get("route_y", [])
	var current_map_x_float: float = convoy_data.get("x", -1.0) # Ensure float for comparison
	var current_map_y_float: float = convoy_data.get("y", -1.0)

	var direction_rad: float = icon_sprite.rotation # Keep current rotation if no new direction
	if route_x.size() > 1 and route_y.size() == route_x.size():
		var current_segment_idx: int = -1
		# Find current segment convoy is on
		for i in range(route_x.size()):
			# Compare float versions of coordinates
			if abs(float(route_x[i]) - current_map_x_float) < 0.001 and \
			   abs(float(route_y[i]) - current_map_y_float) < 0.001:
				current_segment_idx = i
				break
		
		if current_segment_idx != -1:
			if current_segment_idx + 1 < route_x.size(): # Has a next point
				var next_map_x: float = float(route_x[current_segment_idx + 1])
				var next_map_y: float = float(route_y[current_segment_idx + 1])
				var dir_vec := Vector2(next_map_x - current_map_x_float, next_map_y - current_map_y_float)
				if dir_vec.length_squared() > 0.0001: # Explicit block
					direction_rad = dir_vec.angle() 
			elif current_segment_idx > 0: # At the end of path, use previous segment's direction
				var prev_map_x: float = float(route_x[current_segment_idx - 1])
				var prev_map_y: float = float(route_y[current_segment_idx - 1])
				var dir_vec := Vector2(current_map_x_float - prev_map_x, current_map_y_float - prev_map_y)
				if dir_vec.length_squared() > 0.0001: # Explicit block
					direction_rad = dir_vec.angle() 
	icon_sprite.rotation = direction_rad
	
	# 3. Update Throb & Arrow Drawing (depends on scale from zoom)
	# The ConvoyNode itself is scaled by MapContainer's zoom.
	# We want the arrow to maintain a somewhat consistent *on-screen* size appearance,
	# or scale less aggressively than the map.
	# For now, let's make the arrow scale with zoom but apply throb.
	# A more advanced approach would be to get current_screen_scale and adjust base sizes.
	
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
	# image.lock() # Not available in Godot 3.x
	for y_coord in range(min_y, max_y + 1):
		for x_coord in range(min_x, max_x + 1):
			var current_pixel := Vector2(float(x_coord), float(y_coord))
			# Check center of the pixel for more accuracy with Geometry2D
			if Geometry2D.is_point_in_polygon(current_pixel + Vector2(0.5, 0.5), polygon):
				image.set_pixel(x_coord, y_coord, color)
	# image.unlock() # Not available in Godot 3.x
