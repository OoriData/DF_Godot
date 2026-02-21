extends RigidBody2D

@onready var color_rect: ColorRect = $ColorRect
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _color: String = ""
var _shape: String = ""
var _weight_class: float = 0.0

const COLORS = {
	"red": Color.RED,
	"blue": Color.BLUE,
	"green": Color.GREEN,
	"yellow": Color.YELLOW,
	"black": Color.BLACK,
	"white": Color.WHITE,
	"gray": Color.GRAY,
	"orange": Color.ORANGE,
	"purple": Color.PURPLE
}

func setup(vehicle_color: String, vehicle_shape: String, vehicle_weight_class: float) -> void:
	_color = vehicle_color.to_lower()
	_shape = vehicle_shape.to_lower()
	_weight_class = vehicle_weight_class
	
	_apply_visuals()
	_apply_physics()

func _apply_visuals() -> void:
	# Base color
	if COLORS.has(_color):
		color_rect.color = COLORS[_color]
	else:
		color_rect.color = Color(0.5, 0.5, 0.5, 1.0) # default grey

	# Base shape scaling
	var base_width: float = 100.0
	var base_height: float = 50.0
	
	if _shape == "pickup":
		base_width = 120.0
		base_height = 45.0
	elif _shape == "box":
		base_width = 150.0
		base_height = 80.0
	elif _shape == "suv":
		base_width = 110.0
		base_height = 60.0
	elif _shape == "sedan":
		base_width = 90.0
		base_height = 40.0
	
	# Apply weight class scaling (0 = smallest, 2+ = largest)
	var scale_factor: float = 1.0 + (_weight_class * 0.2)
	base_width *= scale_factor
	base_height *= scale_factor
	
	color_rect.size = Vector2(base_width, base_height)
	color_rect.position = Vector2(-base_width / 2.0, -base_height / 2.0)
	
	if collision_shape.shape is RectangleShape2D:
		var rect_shape = collision_shape.shape as RectangleShape2D
		rect_shape.size = color_rect.size

func _apply_physics() -> void:
	# Higher weight class = higher mass
	mass = 1000.0 + (_weight_class * 1000.0)

func _input_event(_viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	# Add interaction: click to bounce/fling
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			apply_central_impulse(Vector2(0, -600.0 * mass))
