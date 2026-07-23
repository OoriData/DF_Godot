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
	# Suppress the banner while the tutorial is running. This toast is anchored across the TOP of the vendor
	# panel — the same strip the tutorial highlights (e.g. the return-to-settlement back control) — so a 4s
	# banner shown from a late async transaction result would cover the highlight. The guided flow doesn't
	# need the confirmation, so we skip it entirely rather than race to hide it after the fact.
	var tut := get_node_or_null("/root/TutorialManager")
	if is_instance_valid(tut) and tut.has_method("is_tutorial_active") and tut.call("is_tutorial_active"):
		return
	label.text = message
	visible = true
	# Reset and start the timer
	timer.start()