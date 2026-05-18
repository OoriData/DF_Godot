@tool
extends Control

@export var max_value: float = 100.0:
	set(val):
		max_value = max(1.0, val)
		queue_redraw()

@export var value: float = 0.0:
	set(val):
		value = clamp(val, 0.0, max_value)
		queue_redraw()

@export var fg_color: Color = Color(0.0, 0.66, 1.0, 1.0) # #00aaff Oori Blue
@export var bg_color: Color = Color(0.08, 0.09, 0.12, 0.9)
@export var thickness: float = 16.0

func _draw() -> void:
	var center = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - thickness / 2.0
	
	# Draw background ring
	draw_arc(center, radius, 0, TAU, 64, bg_color, thickness, true)
	
	# Draw foreground active ring
	if value > 0 and max_value > 0:
		var ratio = value / max_value
		var angle = ratio * TAU
		# Start drawing from the top (-PI/2)
		draw_arc(center, radius, -PI/2.0, -PI/2.0 + angle, 64, fg_color, thickness, true)
