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
		print("ConvoyMenu: BackButton found. Connecting its 'pressed' signal.")
		# Check if already connected to prevent duplicate connections if _ready is called multiple times (unlikely for menus but good practice)
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed)
	else:
		printerr("ConvoyMenu: CRITICAL - BackButton node NOT found or is not a Button. Ensure it's named 'BackButton' in ConvoyMenu.tscn.")

func _on_back_button_pressed():
	print("ConvoyMenu: Back button pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")

func initialize_with_data(data: Dictionary):
		convoy_data_received = data.duplicate() # Duplicate to avoid modifying the original if needed
		print("ConvoyMenu: Initialized with data: ", convoy_data_received)

		# --- Populate General Information ---
		_update_label("MainVBox/InfoGrid/ConvoyIDValue", convoy_data_received.get("convoy_id", "N/A"))
		_update_label("MainVBox/InfoGrid/ConvoyNameValue", convoy_data_received.get("convoy_name", "N/A"))
		_update_label("MainVBox/InfoGrid/StatusValue", convoy_data_received.get("status", "N/A")) # Example field

		var loc_x = convoy_data_received.get("x", "N/A")
		var loc_y = convoy_data_received.get("y", "N/A")
		_update_label("MainVBox/InfoGrid/LocationValue", "%s, %s" % [loc_x, loc_y])

		# Example fields - these depend on your actual data structure
		_update_label("MainVBox/InfoGrid/CurrentTileTerrainValue", convoy_data_received.get("current_tile_terrain_type", "N/A"))
		_update_label("MainVBox/InfoGrid/CurrentTileRegionValue", convoy_data_received.get("current_tile_region_name", "N/A"))

		# --- Populate Journey Details ---
		var journey_data: Dictionary = convoy_data_received.get("journey", {})

		# Origin and Destination - these might be names or coordinates
		# If they are coordinates from route_x/route_y:
		var route_x: Array = journey_data.get("route_x", [])
		var route_y: Array = journey_data.get("route_y", [])

		if not route_x.is_empty() and not route_y.is_empty():
			var origin_str = convoy_data_received.get("origin_settlement_name", "X: %s, Y: %s" % [route_x[0], route_y[0]])
			_update_label("MainVBox/JourneyGrid/OriginValue", origin_str)

			var dest_str = convoy_data_received.get("destination_settlement_name", "X: %s, Y: %s" % [route_x[-1], route_y[-1]])
			_update_label("MainVBox/JourneyGrid/DestinationValue", dest_str)
			
			# Next Stop
			var current_x = convoy_data_received.get("x")
			var current_y = convoy_data_received.get("y")
			var next_stop_str = "N/A"
			if current_x != null and current_y != null:
				var current_idx = -1
				for i in range(route_x.size()):
					if abs(float(route_x[i]) - float(current_x)) < 0.001 and abs(float(route_y[i]) - float(current_y)) < 0.001:
						current_idx = i
						break
				if current_idx != -1 and current_idx + 1 < route_x.size():
					next_stop_str = "X: %s, Y: %s" % [route_x[current_idx+1], route_y[current_idx+1]]
				elif current_idx == route_x.size() -1:
					next_stop_str = "Arrived at Destination"
			_update_label("MainVBox/JourneyGrid/NextStopValue", next_stop_str)

		else: # Fallback if no route data
			_update_label("MainVBox/JourneyGrid/OriginValue", convoy_data_received.get("origin_settlement_name", "N/A"))
			_update_label("MainVBox/JourneyGrid/DestinationValue", convoy_data_received.get("destination_settlement_name", "N/A"))
			_update_label("MainVBox/JourneyGrid/NextStopValue", "N/A")

		_update_label("MainVBox/JourneyGrid/ProgressValue", "%s%%" % convoy_data_received.get("progress_percent", "N/A")) # Example field

		# --- Populate Cargo Manifest ---
		var cargo_label_node = get_node_or_null("MainVBox/CargoRichTextLabel")
		if cargo_label_node and cargo_label_node is RichTextLabel:
			var cargo_manifest: Array = convoy_data_received.get("cargo_manifest", [])
			if cargo_manifest.is_empty():
				cargo_label_node.text = "No cargo information available."
			else:
				cargo_label_node.clear() # Clear previous content
				cargo_label_node.bbcode_enabled = true
				var bbcode_text = ""
				for item_entry in cargo_manifest:
					if item_entry is Dictionary:
						var item_name = item_entry.get("item_name", "Unknown Item")
						var quantity = item_entry.get("quantity", 0)
						bbcode_text += "[b]%s[/b]: %s units\n" % [item_name, quantity]
					else:
						bbcode_text += "Invalid cargo entry.\n"
				cargo_label_node.append_text(bbcode_text) # Use append_text or assign to .text
		elif cargo_label_node:
			printerr("ConvoyMenu: CargoRichTextLabel node found but it's not a RichTextLabel.")
		else:
			printerr("ConvoyMenu: CargoRichTextLabel node NOT found at path MainVBox/CargoRichTextLabel.")


func _update_label(node_path: String, text_content: Variant):
	"""
	Helper function to safely find a Label node and update its text.
	The node_path is relative to this ConvoyMenu node.
	"""
	var label_node = get_node_or_null(node_path)
	if label_node and label_node is Label:
		label_node.text = str(text_content) # Ensure content is string
	elif label_node: # Node found but not a Label
		printerr("ConvoyMenu: Node at path '%s' is not a Label. Cannot set text." % node_path)
	else: # Node not found
		printerr("ConvoyMenu: Label node NOT found at path '%s'." % node_path)
