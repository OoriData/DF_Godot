extends Control

func _ready() -> void:
	$Panel/VBoxContainer/CloseButton.pressed.connect(_on_close_pressed)

func _on_close_pressed() -> void:
	queue_free()

func open() -> void:
	show()
	# Optional: Add animation here
