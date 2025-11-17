# /Users/aidan/Work/DF_Godot/Scripts/UI/toast_notification.gd
extends PanelContainer

@onready var label: Label = $MarginContainer/Label
@onready var timer: Timer = $Timer

const DISPLAY_DURATION: float = 4.0

func _ready() -> void:
	# Start hidden
	visible = false
	# When the timer finishes, hide the notification
	timer.wait_time = DISPLAY_DURATION
	timer.one_shot = true
	timer.timeout.connect(func(): visible = false)

func show_message(message: String) -> void:
	label.text = message
	visible = true
	# Reset and start the timer
	timer.start()