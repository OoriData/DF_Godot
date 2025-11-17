# /Users/aidan/Work/DF_Godot/Scripts/UI/ErrorDialog.gd
extends AcceptDialog

func _ready() -> void:
	# When the dialog is confirmed (OK button) or closed (X button), it should free itself.
	confirmed.connect(queue_free)
	canceled.connect(queue_free)

	# Ensure the label inside the dialog can wrap long text.
	var label = get_label()
	if is_instance_valid(label):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD

func show_message(message: String) -> void:
	dialog_text = message
	# Popup in the center of the screen.
	# Using call_deferred ensures it happens after the node is ready and sizes are calculated.
	call_deferred("popup_centered")

