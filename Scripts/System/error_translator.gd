# /Users/aidan/Work/DF_Godot/Scripts/System/error_translator.gd
extends Node

# A dictionary mapping parts of technical error messages to user-friendly explanations.
# The dictionary is checked in order, so more specific keys should be placed before general ones.
const ERROR_MAP: Dictionary = {
	# --- Specific Transaction/Action Failures ---
	"not found in the vendor's inventory": "This item is no longer available. The vendor's list has been updated.",
	"Item no longer sold by vendor": "This item is no longer sold here. The vendor's list has been updated.",
	"Not enough money": "You do not have enough money for this transaction.",
	"Vendor does not have enough stock": "The vendor's stock has changed. The list has been updated.",
	"exceeds convoy cargo capacity": "This purchase would exceed your convoy's cargo volume capacity.",
	"exceeds convoy weight capacity": "This purchase would exceed your convoy's weight capacity.",
	"Part is not compatible with the vehicle": "This part is not compatible with the selected vehicle.",
	"No vehicle with compatible slot available": "No vehicle in your convoy has a compatible slot for this part.",
	"Cannot sell mission-critical item": "This item is required for a mission and cannot be sold.",
	"Invalid item for this vendor": "This item cannot be bought or sold at this location.",

	# --- Specific Route Finding Errors ---
	"Route find failed: No path found": "A route to this destination could not be found. The path may be blocked or across an ocean.",
	"Route find failed: Cannot route to current location": "You are already at this destination.",

	# --- General Route Finding Fallback ---
	"Route find failed:": "Could not calculate a route to the destination.",

	# --- Auth/Session Errors ---
	"Session expired": "Your session has expired. Please log in again.",
	"Authentication timed out": "Authentication timed out. Please try logging in again.",
	"Auth complete but no session_token": "There was a problem logging you in. Please try again.",

	# --- Input Validation Errors ---
	"is not a valid UUID": "An internal error occurred (Invalid ID).",
	"Convoy ID cannot be empty": "An internal error occurred (Missing Convoy ID).",
	"User ID cannot be empty": "An internal error occurred (Missing User ID).",

	# --- General Transaction Prefixes (with detail appended) ---
	# These are checked after the specific messages above. A trailing space indicates a prefix.
	"PATCH 'cargo_bought' failed:": "Could not buy item: ",
	"PATCH 'cargo_sold' failed:": "Could not sell item: ",
	"PATCH 'vehicle_bought' failed:": "Could not buy vehicle: ",
	"PATCH 'vehicle_sold' failed:": "Could not sell vehicle: ",
	"PATCH 'resource_bought' failed:": "Could not buy resource: ",
	"PATCH 'resource_sold' failed:": "Could not sell resource: ",

	# --- Network/Parsing Errors ---
	"Failed to parse": "Received an unexpected response from the server. Please try again.",
	"HTTPRequest initiation failed": "Could not connect to the game server. Please check your internet connection.",
	"Network error": "A network error occurred. Please check your internet connection and try again.",
}

# A list of technical error substrings that should NOT be shown to the user.
const IGNORED_SUBSTRINGS: Array[String] = [
	"Logged out.", # This is a normal event, not an error to display.
	"Unauthorized" # This is a standard auth challenge, not an error to display in a modal. The auth flow will handle showing the login screen.
]

# A list of error substrings that should be handled by a local UI component (like a toast)
# instead of the main error popup dialog.
const INLINE_ERROR_KEYS: Array[String] = [
	"Item no longer sold by vendor",
	"Vendor does not have enough stock",
	"not found in the vendor's inventory",
]

func is_inline_error(raw_message: String) -> bool:
	for key in INLINE_ERROR_KEYS:
		if raw_message.find(key) != -1:
			return true
	return false

# This function translates a raw technical error message into a user-friendly one.
func translate(raw_message: String) -> String:
	# 1. Check if the error should be ignored completely.
	for ignored_substring in IGNORED_SUBSTRINGS:
		if raw_message.find(ignored_substring) != -1:
			return "" # Return empty string to signify it should be ignored.

	# 2. Iterate through the map to find the first match.
	for key in ERROR_MAP:
		if raw_message.find(key) != -1:
			var friendly_message = ERROR_MAP[key]
			if friendly_message.ends_with(" "): # It's a prefix
				var detail = raw_message.split(key, false, 1)
				return friendly_message + detail[1].strip_edges() if detail.size() > 1 else friendly_message.strip_edges()
			return friendly_message # It's a full replacement

	# 3. If no match was found, it's an unknown error.
	printerr("Unhandled API Error (add to ErrorTranslator): ", raw_message)
	return "An unexpected error occurred. Please try again."