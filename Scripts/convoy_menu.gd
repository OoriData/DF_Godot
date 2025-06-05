extends Control # Or Panel, VBoxContainer, etc., depending on your menu's root node

# Signal that MenuManager will listen for
signal back_requested # Ensure this line exists and is spelled correctly

# Optional: If your menu needs to display data passed from MenuManager
var convoy_data_received: Dictionary

func _ready():
	# IMPORTANT: Ensure you have a Button node in your ConvoyMenu.tscn scene
	# and that its name is "BackButton".
	# The third argument 'false' for find_child means 'owned by this node' is not checked,
	# which is usually fine for finding children within a scene instance.
	var back_button = find_child("BackButton", true, false) 

	if back_button and back_button is Button:
		# print("ConvoyMenu: BackButton found. Connecting its 'pressed' signal.") # DEBUG
		# Check if already connected to prevent duplicate connections if _ready is called multiple times (unlikely for menus but good practice)
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT) # Use ONE_SHOT as menu is freed
	else:
		printerr("ConvoyMenu: CRITICAL - BackButton node NOT found or is not a Button. Ensure it's named 'BackButton' in ConvoyMenu.tscn.")

func _on_back_button_pressed():
	print("ConvoyMenu: Back button pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")

func initialize_with_data(data: Dictionary):
		convoy_data_received = data.duplicate() # Duplicate to avoid modifying the original if needed
		# print("ConvoyMenu: Initialized with data: ", convoy_data_received) # DEBUG

		# IMPORTANT: Replace "ConvoyInfoLabel" with the actual name of your main label node in ConvoyMenu.tscn
		# If your label is named "Convoy menu Label" in the scene tree, use that exact name here.
		var info_label_node_path = "Convoy Menu" # Adjusted to match your likely scene structure
		var info_label = get_node_or_null(info_label_node_path)

		if info_label and info_label is Label:
			var display_text = "Convoy Details:\n"
			display_text += "ID: %s\n" % convoy_data_received.get("convoy_id", "N/A")
			display_text += "Name: %s\n" % convoy_data_received.get("convoy_name", "N/A")
			display_text += "Location: (%.1f, %.1f)\n" % [convoy_data_received.get("x", 0.0), convoy_data_received.get("y", 0.0)]
			# Add more basic info as needed
			info_label.text = display_text
		elif info_label:
			printerr("ConvoyMenu: Node at path '%s' was found, but it's not a Label." % info_label_node_path)
		else:
			printerr("ConvoyMenu: Label node NOT found at path '%s'. Please check the name in ConvoyMenu.tscn." % info_label_node_path)

# The _update_label function is no longer needed with this simplified structure.
# You can remove it or comment it out.
# func _update_label(node_path: String, text_content: Variant):
# 	...
