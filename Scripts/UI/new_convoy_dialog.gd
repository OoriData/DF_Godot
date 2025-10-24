extends PanelContainer

signal create_requested(name: String)
signal canceled

@onready var name_edit: LineEdit = $VBox/NameEdit
@onready var create_button: Button = $VBox/Buttons/CreateButton
@onready var cancel_button: Button = $VBox/Buttons/CancelButton
@onready var error_label: Label = $VBox/ErrorLabel

func _ready():
	visible = false
	_error("")
	if is_instance_valid(create_button):
		create_button.pressed.connect(_on_create_pressed)
	if is_instance_valid(cancel_button):
		cancel_button.pressed.connect(_on_cancel_pressed)
	if is_instance_valid(name_edit):
		name_edit.text_submitted.connect(func(_t): _on_create_pressed())

func open():
	visible = true
	modulate = Color(1,1,1,1)
	set_process_unhandled_input(true)
	var tree = get_tree()
	if is_instance_valid(tree):
		await tree.process_frame
	if is_instance_valid(name_edit):
		name_edit.grab_focus()

func close():
	visible = false
	set_process_unhandled_input(false)

func set_busy(is_busy: bool):
	if is_instance_valid(create_button):
		create_button.disabled = is_busy
	if is_instance_valid(cancel_button):
		cancel_button.disabled = is_busy
	if is_instance_valid(name_edit):
		name_edit.editable = not is_busy

func _on_create_pressed():
	var nm := ""
	if is_instance_valid(name_edit):
		nm = name_edit.text.strip_edges()
	if nm.length() < 3:
		_error("Please enter a name (min 3 characters).")
		return
	if nm.length() > 40:
		_error("Name too long (max 40).")
		return
	_error("")
	set_busy(true)
	emit_signal("create_requested", nm)

func _on_cancel_pressed():
	emit_signal("canceled")
	close()

func _error(msg: String):
	if is_instance_valid(error_label):
		error_label.text = msg
		error_label.visible = not msg.is_empty()
