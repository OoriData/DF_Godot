## QuantityWidget - A SpinBox replacement with large, touchscreen-friendly +/- buttons.
## Exposes the same API as SpinBox: value, max_value, step, value_changed signal.
## Add as a child node wherever a SpinBox was used.
extends HBoxContainer
class_name QuantityWidget

signal value_changed(new_value: float)

@export var min_value: float = 0.0
@export var max_value: float = 99.0
@export var step: float = 1.0
@export var value: float = 1.0 : set = set_value

var _minus_btn: Button
var _value_label: LineEdit
var _plus_btn: Button

func _ready() -> void:
	_minus_btn = Button.new()
	_minus_btn.text = "-"
	_minus_btn.custom_minimum_size = Vector2(55, 50)
	_minus_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_btn_style(_minus_btn, Color(0.55, 0.15, 0.15))
	add_child(_minus_btn)
	
	_value_label = LineEdit.new()
	_value_label.text = str(int(value))
	_value_label.custom_minimum_size = Vector2(50, 50)
	_value_label.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_value_label.editable = true
	add_child(_value_label)
	
	_plus_btn = Button.new()
	_plus_btn.text = "+"
	_plus_btn.custom_minimum_size = Vector2(55, 50)
	_plus_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_btn_style(_plus_btn, Color(0.15, 0.45, 0.15))
	add_child(_plus_btn)
	
	_minus_btn.pressed.connect(_on_minus)
	_plus_btn.pressed.connect(_on_plus)
	_value_label.text_submitted.connect(_on_text_submitted)
	_value_label.focus_exited.connect(_on_focus_exited)
	
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 4)

func set_value(new_val: float) -> void:
	value = clampf(new_val, min_value, max_value)
	if is_instance_valid(_value_label):
		_value_label.text = str(int(value))

func _on_minus() -> void:
	set_value(value - step)
	value_changed.emit(value)

func _on_plus() -> void:
	set_value(value + step)
	value_changed.emit(value)

func _on_text_submitted(text: String) -> void:
	_commit_text(text)

func _on_focus_exited() -> void:
	if is_instance_valid(_value_label):
		_commit_text(_value_label.text)

func _commit_text(text: String) -> void:
	if text.is_valid_float():
		set_value(float(text))
		value_changed.emit(value)
	else:
		# Reset to current value if invalid
		if is_instance_valid(_value_label):
			_value_label.text = str(int(value))

func _apply_btn_style(btn: Button, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.3)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style)
	
	var hover_style := style.duplicate()
	hover_style.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style := style.duplicate()
	pressed_style.bg_color = color.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", pressed_style)
