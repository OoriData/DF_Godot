extends Node2D

@onready var sprite: Sprite2D = %VehicleSprite
@onready var error_rect: ColorRect = %ErrorRect

var _color: String = ""
var _shape: String = ""
var _weight_class: float = 0.0

const NORMALIZED_WIDTH: float = 200.0
const SPRITE_DIR = "res://Assets/vehicle_sprites/"

func setup(vehicle_color: String, vehicle_shape: String, vehicle_weight_class: float) -> void:
	_color = vehicle_color
	_shape = vehicle_shape # Keep case for mapping check
	_weight_class = vehicle_weight_class

	_apply_visuals()

func _parse_color(color_str: String) -> Color:
	var s = color_str.strip_edges()
	if s.is_empty():
		return Color(0.7, 0.7, 0.7, 1.0)

	# Try direct string conversion (Godot handles many named colors like "red", "blue")
	if Color.html_is_valid(s):
		return Color.from_string(s, Color.GRAY)

	# Handle complex names with spaces: "Olive Drab" -> "olivedrab"
	var normalized = s.to_lower().replace(" ", "").replace("_", "")

	# Godot's Color() constructor handles many named colors if spaces are removed
	# However, we'll use a small dictionary for common non-standard names
	# or names that might differ from Godot's built-in set.
	var custom_map = {
		"olivedrab": Color(0.42, 0.56, 0.14),
		"drab": Color(0.59, 0.53, 0.44),
		"tan": Color(0.82, 0.71, 0.55),
		"navy": Color.NAVY_BLUE,
		"forest": Color.FOREST_GREEN,
		"maroon": Color.MAROON
	}

	if custom_map.has(normalized):
		return custom_map[normalized]

	# Final attempt: Godot built-in named colors
	# Color() constructor is quite robust in GDScript
	return Color(normalized) if Color.html_is_valid(normalized) else Color.GRAY

func _apply_visuals() -> void:
	# 1. Determine the correct sprite path
	# With formal naming, we use _shape directly
	var path = SPRITE_DIR + _shape + ".png"
	var has_sprite = FileAccess.file_exists(path)

	# 2. Toggle visibility based on asset availability
	sprite.visible = has_sprite
	error_rect.visible = not has_sprite

	if has_sprite:
		var texture = load(path)
		if texture:
			sprite.texture = texture

		# Apply target color to the hue-shift shader
		var target_color = _parse_color(_color)
		if sprite.material is ShaderMaterial:
			sprite.material.set_shader_parameter("target_color", target_color)

		# Ensure modulate is reset to white so it doesn't interfere with the shader
		sprite.modulate = Color.WHITE

		# 3. Handle scaling based on weight_class
		var tex_w = sprite.texture.get_width()
		var base_scale = NORMALIZED_WIDTH / tex_w
		var weight_scale: float = 1.0 + (_weight_class * 0.2)
		sprite.scale = Vector2(base_scale, base_scale) * weight_scale

		# 4. Position bottom-aligned to origin (0,0 is the road line)
		var tex_h = sprite.texture.get_height()
		var scaled_h = tex_h * sprite.scale.y
		sprite.position = Vector2(0, -scaled_h / 2.0)
	else:
		# Error square logic
		var weight_scale: float = 1.0 + (_weight_class * 0.2)
		var target_size = NORMALIZED_WIDTH * weight_scale
		error_rect.size = Vector2(target_size, target_size)
		error_rect.position = Vector2(-target_size / 2.0, -target_size)
		error_rect.color = Color(1, 0, 1, 1) # Magenta fallback
