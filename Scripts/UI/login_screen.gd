extends Control

signal login_successful(user_id: String)

# It's good practice to also get a reference to the VBoxContainer and its direct children
# if you're going to inspect them, though direct paths are fine for @onready.
@onready var instructions_label: Label = $CenterContainer/VBoxContainer/InstructionsLabel
@onready var user_id_line_edit: LineEdit = $CenterContainer/VBoxContainer/UserIDLineEdit
@onready var center_container: CenterContainer = $CenterContainer
@onready var vbox_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var login_button: Button = $CenterContainer/VBoxContainer/LoginButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

func _ready() -> void:
    login_button.pressed.connect(_on_login_button_pressed)
    user_id_line_edit.grab_focus()

func _on_login_button_pressed() -> void:
    var user_id: String = user_id_line_edit.text.strip_edges()
    if user_id.is_empty():
        status_label.text = "User ID cannot be empty."
        return
        
    status_label.text = "" # Clear previous errors
    emit_signal("login_successful", user_id)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept") and user_id_line_edit.has_focus():
        _on_login_button_pressed()
        get_viewport().set_input_as_handled()

func show_error(message: String) -> void:
    status_label.text = message