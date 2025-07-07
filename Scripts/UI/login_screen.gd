extends Control

signal login_requested(user_id: String)

# It's good practice to also get a reference to the VBoxContainer and its direct children
# if you're going to inspect them, though direct paths are fine for @onready.
@onready var instructions_label: Label = $CenterContainer/VBoxContainer/InstructionsLabel
@onready var user_id_line_edit: LineEdit = $CenterContainer/VBoxContainer/UserIDLineEdit
@onready var center_container: CenterContainer = $CenterContainer
@onready var vbox_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var login_button: Button = $CenterContainer/VBoxContainer/LoginButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

func _ready() -> void:
	# print("--- LoginScreen.gd: UI Element Diagnostics ---")

	# var ui_elements: Array = [
		# {"name": "InstructionsLabel", "node": instructions_label},
		# {"name": "UserIDLineEdit", "node": user_id_line_edit},
		# {"name": "LoginButton", "node": login_button},
		# {"name": "StatusLabel", "node": status_label}
	# ]

	# for item in ui_elements:
		# var node_name: String = item.name
		# var node_instance: Control = item.node

		# if is_instance_valid(node_instance):
			# print("  Element: ", node_name)
			# print("    - Path: ", node_instance.get_path())
			# print("    - Visible: ", node_instance.visible)
			# print("    - Modulate: ", node_instance.modulate)
			# print("    - Global Position: ", node_instance.global_position)
			# print("    - Rect Size: ", node_instance.size)
			# print("    - Global Rect: ", node_instance.get_global_rect())
			# print("    - Custom Min Size: ", node_instance.custom_minimum_size)
			# if node_instance is Label:
				# print("    - Text: \"", node_instance.text, "\"")
			# elif node_instance is LineEdit:
				# print("    - Text: \"", node_instance.text, "\"")
				# print("    - Placeholder Text: \"", node_instance.placeholder_text, "\"")
		# else:
			# print("  Element: ", node_name, " - NOT FOUND or INVALID INSTANCE.")
	# print("-------------------------------------------------")
	
	# print("--- LoginScreen.gd: Container Diagnostics ---")
	# var container_elements: Array = [
		# {"name": "CenterContainer", "node": center_container},
		# {"name": "VBoxContainer", "node": vbox_container}
	# ]
	# for item in container_elements:
		# var node_name: String = item.name
		# var node_instance: Control = item.node
		# if is_instance_valid(node_instance):
			# print("  Container: ", node_name)
			# print("    - Path: ", node_instance.get_path())
			# print("    - Visible: ", node_instance.visible)
			# print("    - Modulate: ", node_instance.modulate)
			# print("    - Global Position: ", node_instance.global_position)
			# print("    - Rect Size: ", node_instance.size)
			# print("    - Global Rect: ", node_instance.get_global_rect())
		# else:
			# print("  Container: ", node_name, " - NOT FOUND or INVALID INSTANCE.")
	# print("-------------------------------------------------")

	login_button.pressed.connect(_on_login_button_pressed)
	user_id_line_edit.grab_focus()

# func _is_valid_uuid(uuid_string: String) -> bool: # This validation is moved to APICalls.gd
	# # Basic UUID regex: 8-4-4-4-12 hexadecimal characters
	# var uuid_regex = RegEx.new()
	# uuid_regex.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	# return uuid_regex.search(uuid_string) != null

func _on_login_button_pressed() -> void:
	var user_id: String = user_id_line_edit.text.strip_edges()
	if user_id.is_empty():
		status_label.text = "User ID cannot be empty."
		return
	# UUID validation is removed here. APICalls.gd will handle it.
	# if not _is_valid_uuid(user_id):
		# status_label.text = "Invalid User ID format. Expected UUID (e.g., xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)."
		# return
		
	status_label.text = "" # Clear previous errors
	emit_signal("login_requested", user_id)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and user_id_line_edit.has_focus():
		_on_login_button_pressed()
		get_viewport().set_input_as_handled()

func show_error(message: String) -> void:
	status_label.text = message
