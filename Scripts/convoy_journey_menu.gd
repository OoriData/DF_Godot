extends Control

# Signal that MenuManager will listen for to go back
signal back_requested

# @onready variables for UI elements
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var scroll_container: ScrollContainer = $MainVBox/ScrollContainer
@onready var content_vbox: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox
@onready var back_button: Button = $MainVBox/BackButton

# Constants for formatting
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func _ready():
	# Connect the back button signal
	if is_instance_valid(back_button):
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT)
	else:
		printerr("ConvoyJourneyMenu: CRITICAL - BackButton node NOT found or is not a Button.")

	# Remove the placeholder label if it exists
	if content_vbox.has_node("PlaceholderLabel"):
		var placeholder = content_vbox.get_node("PlaceholderLabel")
		if is_instance_valid(placeholder):
			placeholder.queue_free()

func _on_back_button_pressed():
	print("ConvoyJourneyMenu: Back button pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")

func initialize_with_data(data: Dictionary):
	print("ConvoyJourneyMenu: Initialized with data.") # DEBUG

	if is_instance_valid(title_label):
		title_label.text = data.get("convoy_name", "Convoy") + " - Journey Details"

	for child in content_vbox.get_children():
		child.queue_free()

	var journey_data: Dictionary = data.get("journey", {})
	var gdm = get_node_or_null("/root/GameDataManager")

	if journey_data.is_empty():
		var no_journey_label = Label.new()
		no_journey_label.text = "This convoy is not currently on a journey."
		no_journey_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content_vbox.add_child(no_journey_label)
		return

	# Current Location
	var current_loc_label = Label.new()
	current_loc_label.text = "Current Location: (%.2f, %.2f)" % [data.get("x", 0.0), data.get("y", 0.0)]
	content_vbox.add_child(current_loc_label)
	content_vbox.add_child(HSeparator.new())

	# Origin
	var origin_x = journey_data.get("origin_x")
	var origin_y = journey_data.get("origin_y")
	var origin_label = Label.new()
	var origin_text = "Origin: N/A"
	if origin_x != null and origin_y != null:
		var origin_name = _get_settlement_name(gdm, origin_x, origin_y)
		origin_text = "Origin: %s (at %.0f, %.0f)" % [origin_name, origin_x, origin_y]
	origin_label.text = origin_text
	content_vbox.add_child(origin_label)

	# Destination
	var dest_x = journey_data.get("dest_x")
	var dest_y = journey_data.get("dest_y")
	var destination_label = Label.new()
	var dest_text = "Destination: N/A"
	if dest_x != null and dest_y != null:
		var dest_name = _get_settlement_name(gdm, dest_x, dest_y)
		dest_text = "Destination: %s (at %.0f, %.0f)" % [dest_name, dest_x, dest_y]
	destination_label.text = dest_text
	content_vbox.add_child(destination_label)
	content_vbox.add_child(HSeparator.new())

	# Departure Time
	var departure_time_str = journey_data.get("departure_time")
	var departure_label = Label.new()
	departure_label.text = "Departed: " + _format_timestamp_display(departure_time_str, false)
	content_vbox.add_child(departure_label)

	# ETA and Time Remaining
	var eta_str = journey_data.get("eta")
	var eta_label = Label.new()
	eta_label.text = "ETA: " + _format_timestamp_display(eta_str, true)
	content_vbox.add_child(eta_label)
	content_vbox.add_child(HSeparator.new())

	# Progress
	var progress = journey_data.get("progress", 0.0)
	var length = journey_data.get("length", 0.0)
	var progress_percentage = 0.0
	if length > 0.001: # Avoid division by zero
		progress_percentage = (progress / length) * 100.0
	
	var progress_text_label = Label.new()
	progress_text_label.text = "Progress: %.1f / %.1f units (%.1f%%)" % [progress, length, progress_percentage]
	content_vbox.add_child(progress_text_label)

	var progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 20
	progress_bar.value = progress_percentage
	content_vbox.add_child(progress_bar)

	call_deferred("update_minimum_size")
	if is_instance_valid(scroll_container):
		scroll_container.call_deferred("update_minimum_size")

func _get_settlement_name(gdm_node, coord_x, coord_y) -> String:
	if not is_instance_valid(gdm_node) or not gdm_node.has_method("get_settlement_name_from_coords"):
		printerr("ConvoyJourneyMenu: GameDataManager not available or method missing for settlement name.")
		return "Unknown"
	
	var x_int = roundi(float(coord_x))
	var y_int = roundi(float(coord_y))
	var name = gdm_node.get_settlement_name_from_coords(x_int, y_int)
	if name.begins_with("N/A"):
		return "Uncharted Location"
	return name

func _format_timestamp_display(timestamp_value, include_remaining_time: bool) -> String:
	if timestamp_value == null:
		return "N/A"

	var eta_timestamp_int: int = -1

	if timestamp_value is String:
		eta_timestamp_int = Time.get_unix_time_from_datetime_string(timestamp_value)
		if eta_timestamp_int == -1 and timestamp_value.is_valid_int():
			eta_timestamp_int = timestamp_value.to_int()
	elif timestamp_value is float:
		eta_timestamp_int = int(timestamp_value)
	elif timestamp_value is int:
		eta_timestamp_int = timestamp_value

	if eta_timestamp_int < 0:
		return "Invalid Date"

	var current_sys_utc_ts: int = Time.get_unix_time_from_system()
	var current_sys_local_dict: Dictionary = Time.get_datetime_dict_from_system(false)
	var current_sys_local_interpreted_as_utc_ts: int = Time.get_unix_time_from_datetime_dict(current_sys_local_dict) # Interprets dict values as if they were UTC
	var timezone_offset_seconds: int = current_sys_utc_ts - current_sys_local_interpreted_as_utc_ts
	var timestamp_for_local_display: int = eta_timestamp_int - timezone_offset_seconds
	var datetime_dict: Dictionary = Time.get_datetime_dict_from_unix_time(timestamp_for_local_display)
	
	var month_str = "Unk"
	if datetime_dict.month >= 1 and datetime_dict.month <= 12:
		month_str = MONTH_NAMES[datetime_dict.month - 1]
	
	var day_val = datetime_dict.day
	var hour_val = datetime_dict.hour
	var minute_val = datetime_dict.minute
	
	var am_pm_str = "AM"
	if hour_val >= 12:
		am_pm_str = "PM"
	if hour_val > 12:
		hour_val -= 12
	elif hour_val == 0:
		hour_val = 12
		
	var display_text = "%s %s, %d:%02d %s" % [month_str, day_val, hour_val, minute_val, am_pm_str]

	if include_remaining_time:
		var time_remaining_seconds = eta_timestamp_int - current_sys_utc_ts
		if time_remaining_seconds > 0:
			var days_remaining = floor(time_remaining_seconds / (24.0 * 3600.0))
			var hours_remaining = floor(fmod(time_remaining_seconds, (24.0 * 3600.0)) / 3600.0)
			var minutes_remaining = floor(fmod(time_remaining_seconds, 3600.0) / 60.0)
			
			var time_remaining_str_parts = []
			if days_remaining > 0: time_remaining_str_parts.append("%dd" % days_remaining)
			if hours_remaining > 0: time_remaining_str_parts.append("%dh" % hours_remaining)
			if minutes_remaining > 0 or (days_remaining == 0 and hours_remaining == 0):
				time_remaining_str_parts.append("%dm" % minutes_remaining)
			
			if not time_remaining_str_parts.is_empty():
				display_text += " (%s remaining)" % " ".join(time_remaining_str_parts)
			else: # Less than a minute
				display_text += " (Arriving Soon)"
		elif time_remaining_seconds <= 0 and time_remaining_seconds > -300: # Within last 5 mins
			display_text += " (Now)"
		else: # Arrived
			display_text += " (Arrived)"
			
	return display_text
