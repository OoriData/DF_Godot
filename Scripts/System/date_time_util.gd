extends Node

const ABBREVIATED_MONTH_NAMES: Array[String] = [
	'N/A',  # Index 0 (unused for months 1-12)
	'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
	'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
]

static func format_eta_string(eta_raw_string: String, departure_raw_string: String) -> String:
	var formatted_eta: String = 'N/A'
	if eta_raw_string != 'N/A' and not eta_raw_string.is_empty() and \
	   departure_raw_string != 'N/A' and not departure_raw_string.is_empty():

		var eta_datetime_local: Dictionary = {}
		var departure_datetime_local: Dictionary = {}

		var eta_utc_dict: Dictionary = parse_iso_to_utc_dict(eta_raw_string)
		var departure_utc_dict: Dictionary = parse_iso_to_utc_dict(departure_raw_string)

		var local_offset_seconds: int = 0
		var current_local_components: Dictionary = Time.get_datetime_dict_from_system(false)
		var current_utc_components: Dictionary = Time.get_datetime_dict_from_system(true)

		if not current_local_components.is_empty() and not current_utc_components.is_empty():
			var current_system_unix_local: int = Time.get_unix_time_from_datetime_dict(current_local_components)
			var current_system_unix_utc: int = Time.get_unix_time_from_datetime_dict(current_utc_components)
			if current_system_unix_local > 0 and current_system_unix_utc > 0:
				local_offset_seconds = current_system_unix_local - current_system_unix_utc

		if not eta_utc_dict.is_empty():
			var eta_unix_time_utc: int = Time.get_unix_time_from_datetime_dict(eta_utc_dict)
			if eta_unix_time_utc > 0:
				var eta_unix_time_local: int = eta_unix_time_utc + local_offset_seconds
				eta_datetime_local = Time.get_datetime_dict_from_unix_time(eta_unix_time_local)

		if not departure_utc_dict.is_empty():
			var departure_unix_time_utc: int = Time.get_unix_time_from_datetime_dict(departure_utc_dict)
			if departure_unix_time_utc > 0:
				var departure_unix_time_local: int = departure_unix_time_utc + local_offset_seconds
				departure_datetime_local = Time.get_datetime_dict_from_unix_time(departure_unix_time_local)

		if not eta_datetime_local.is_empty() and not departure_datetime_local.is_empty():
			var eta_hour_24: int = eta_datetime_local.hour
			var am_pm_str: String = 'AM'
			var eta_hour_12: int = eta_hour_24
			if eta_hour_24 >= 12:
				am_pm_str = 'PM'
				if eta_hour_24 > 12: eta_hour_12 = eta_hour_24 - 12
			if eta_hour_12 == 0: eta_hour_12 = 12

			var eta_hour_str = '%d' % eta_hour_12
			var eta_minute_str = '%02d' % eta_datetime_local.minute

			var years_match: bool = eta_datetime_local.year == departure_datetime_local.year
			var months_match: bool = eta_datetime_local.month == departure_datetime_local.month
			var days_match: bool = eta_datetime_local.day == departure_datetime_local.day

			if years_match and months_match and days_match:
				formatted_eta = '%s:%s %s' % [eta_hour_str, eta_minute_str, am_pm_str]
			else:
				var month_name_str: String = '???'
				if eta_datetime_local.month >= 1 and eta_datetime_local.month <= 12:
					month_name_str = ABBREVIATED_MONTH_NAMES[eta_datetime_local.month]
				var day_to_display = eta_datetime_local.get('day', '??')
				formatted_eta = '%s %s, %s:%s %s' % [month_name_str, day_to_display, eta_hour_str, eta_minute_str, am_pm_str]
		else: # Fallback if proper parsing failed
			if eta_raw_string.length() >= 16:
				formatted_eta = eta_raw_string.substr(0, 16).replace('T', ' ')
			else:
				formatted_eta = eta_raw_string
	return formatted_eta


static func parse_iso_to_utc_dict(iso_string: String) -> Dictionary:
	var components = {'year': 0, 'month': 0, 'day': 0, 'hour': 0, 'minute': 0, 'second': 0}
	if iso_string.length() >= 19: # Need YYYY-MM-DDTHH:MM:SS
		components.year = iso_string.substr(0, 4).to_int()
		components.month = iso_string.substr(5, 2).to_int()
		components.day = iso_string.substr(8, 2).to_int()
		components.hour = iso_string.substr(11, 2).to_int()
		components.minute = iso_string.substr(14, 2).to_int()
		components.second = iso_string.substr(17, 2).to_int()
		if components.year > 0 and components.month > 0 and components.day > 0:
			return components
	return {} # Return empty if parsing failed

static func format_timestamp_display(timestamp_value, include_remaining_time: bool) -> String:
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
		month_str = ABBREVIATED_MONTH_NAMES[datetime_dict.month]
	
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
