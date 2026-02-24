extends Node2D

@onready var visual_node: Label = $VisualNode
@onready var background_panel: Panel = $Background

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

const EMOJI_MAP = {
	"compact_hatchback": "🚗",
	"hatchback": "🚗",
	"kammback": "🚗",
	"sedan": "🚗",
	"wagon": "🚗",
	"cuv": "🚙",
	"long_suv": "🚙",
	"minivan": "🚙",
	"short_suv": "🚙",
	"2_door_sedan": "🏎️",
	"convertible": "🏎️",
	"cabover_pickup": "🛻",
	"crew_cab_pickup": "🛻",
	"extended_cab_pickup": "🛻",
	"single_cab_pickup": "🛻",
	"sut": "🛻",
	"ute": "🛻",
	"cargo_van": "🚐",
	"van": "🚐",
	"coach": "🚌",
	"cabover_bus": "🚌",
	"bus": "🚌",
	"short_cabover_bus": "🚌",
	"10x10_cabover": "🚚",
	"6x6": "🚚",
	"6x6_cabover": "🚚",
	"8x8_cabover": "🚚",
	"pickup": "🛻",
	"box": "🚚",
	"suv": "🚙"
}

func setup(vehicle_color: String, vehicle_shape: String, vehicle_weight_class: float) -> void:
	_color = vehicle_color.to_lower()
	_shape = vehicle_shape.to_lower()
	_weight_class = vehicle_weight_class
	
	_apply_visuals()

func _apply_visuals() -> void:
	var emoji_str = EMOJI_MAP.get(_shape, "🚗")
	visual_node.text = emoji_str

	# Dynamic Scale
	var scale_factor: float = 1.0 + (_weight_class * 0.2)
	var base_font_size: int = 80
	var font_size = int(base_font_size * scale_factor)
	
	var settings = LabelSettings.new()
	settings.font = preload("res://Assets/main_font.tres")
	settings.font_size = font_size
	visual_node.label_settings = settings

	# Apply colored border to background panel for the "outline" effect
	var car_color = COLORS.get(_color, Color(0.5, 0.5, 0.5, 1.0))
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.1, 0.1, 0.1, 0.6) # Dim background
	stylebox.border_width_left = 4
	stylebox.border_width_top = 4
	stylebox.border_width_right = 4
	stylebox.border_width_bottom = 4
	stylebox.border_color = car_color
	stylebox.corner_radius_top_left = 12
	stylebox.corner_radius_top_right = 12
	stylebox.corner_radius_bottom_right = 12
	stylebox.corner_radius_bottom_left = 12
	
	background_panel.add_theme_stylebox_override("panel", stylebox)
	
	# Adjust panel size to encase the emoji
	var pad_x = 20 * scale_factor
	var pad_y = 10 * scale_factor
	background_panel.custom_minimum_size = Vector2(font_size + pad_x, font_size * 0.8 + pad_y)
	background_panel.size = background_panel.custom_minimum_size
	# Center horizontally, and place bottom at 0 (the road line)
	background_panel.position = Vector2(-background_panel.size.x / 2.0, -background_panel.size.y)
	
	# Position emoji relative to the road/origin
	# visual_node is anchored BOTTOM in the scene, so we offset its position.
	# We use a fixed vertical alignment for all emojis.
	visual_node.position = Vector2(-visual_node.size.x / 2.0, -visual_node.size.y + 10)
