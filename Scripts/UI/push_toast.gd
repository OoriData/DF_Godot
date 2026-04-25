extends CanvasLayer

signal toast_tapped(dialogue_id: String)

@onready var panel = %Panel
@onready var title_label = %TitleLabel
@onready var body_label = %BodyLabel
@onready var tap_button = %TapButton
@onready var close_timer = %CloseTimer

var _current_dialogue_id: String = ""
var _is_animating: bool = false
var _is_showing: bool = false

# Original starting Y (off-screen)
const OFFSCREEN_Y: float = -150.0
# Target Y (on-screen)
const ONSCREEN_Y: float = 20.0

func _ready() -> void:
	panel.position.y = OFFSCREEN_Y
	tap_button.pressed.connect(_on_tap_button_pressed)
	close_timer.timeout.connect(_on_close_timer_timeout)

func show_toast(title: String, body: String, dialogue_id: String) -> void:
	title_label.text = title
	body_label.text = body
	_current_dialogue_id = dialogue_id
	
	if _is_showing:
		# Restart timer if already showing
		close_timer.start()
		return
		
	_is_showing = true
	_is_animating = true
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:y", ONSCREEN_Y, 0.4)
	tween.tween_callback(func():
		_is_animating = false
		close_timer.start()
	)

func hide_toast() -> void:
	if not _is_showing: return
	
	_is_showing = false
	close_timer.stop()
	_is_animating = true
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "position:y", OFFSCREEN_Y, 0.3)
	tween.tween_callback(func():
		_is_animating = false
	)

func _on_tap_button_pressed() -> void:
	if _current_dialogue_id != "":
		toast_tapped.emit(_current_dialogue_id)
	hide_toast()

func _on_close_timer_timeout() -> void:
	hide_toast()
