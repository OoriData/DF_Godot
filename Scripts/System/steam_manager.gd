extends Node

# SteamManager.gd
# Handles Steamworks initialization and callbacks via GodotSteam.

signal steam_initialized
signal steam_init_failed(reason: String)

var _is_initialized: bool = false
var _app_id: int = 480 # Default Spacewar ID for testing, replace with actual AppID
var _steam_ref: Object = null

func _ready() -> void:
	# Attempt to initialize Steam
	_initialize_steam()

func _process(_delta: float) -> void:
	if _is_initialized and _steam_ref:
		_steam_ref.run_callbacks()

func _initialize_steam() -> void:
	print("[SteamManager] Initializing Steam...")
	
	# Set environment variables for macOS/Linux dev
	OS.set_environment("SteamAppId", str(_app_id))
	OS.set_environment("SteamGameId", str(_app_id))
	
	# Verify steam_appid.txt exists
	if not FileAccess.file_exists("res://steam_appid.txt") and not FileAccess.file_exists("steam_appid.txt"):
		printerr("[SteamManager] WARNING: steam_appid.txt not found in project root. This may cause initialization failure.")
	
	# Check if Steam singleton exists (GodotSteam)
	if ClassDB.class_exists("Steam"):
		_steam_ref = Engine.get_singleton("Steam")
	
	if not _steam_ref:
		printerr("[SteamManager] GodotSteam singleton 'Steam' not detected! Check your addons/ folder.")
		emit_signal("steam_init_failed", "GodotSteam missing")
		return
	
	# Try steamInitEx first (recommended for Godot 4)
	print("[SteamManager] Attempting steamInitEx(false, %d)..." % _app_id)
	var init_response: Variant = _steam_ref.steamInitEx(false, _app_id)
	
	var is_failed: bool = false
	var error_msg: String = "Unknown error"
	
	if init_response is Dictionary:
		if init_response.get("status", 1) > 0:
			print("[SteamManager] steamInitEx failed: %s. Falling back to steamInit()..." % init_response.get("verbal", "Unknown error"))
			init_response = _steam_ref.steamInit()
	
	if init_response is Dictionary:
		if init_response.get("status", 1) > 0:
			is_failed = true
			error_msg = init_response.get("verbal", "Unknown failure")
	elif init_response is bool:
		if init_response == false:
			is_failed = true
			error_msg = "steamInit returned false"
	
	if is_failed:
		printerr("[SteamManager] Steam failed to initialize: %s" % error_msg)
		emit_signal("steam_init_failed", error_msg)
		_is_initialized = false
	else:
		_is_initialized = true
		print("[SteamManager] Steam initialized successfully.")
		if _steam_ref.has_method("getSteamID"):
			var sid = _steam_ref.getSteamID()
			print("[SteamManager] Current SteamID: %s" % sid)
		emit_signal("steam_initialized")

func is_steam_running() -> bool:
	if not _is_initialized or not _steam_ref:
		return false
	return _steam_ref.isSteamRunning()

func get_steam_id() -> String:
	if not _is_initialized or not _steam_ref:
		return ""
	# godotsteam returns int usually, cast to String for safety with backend JSON esp. for 64-bit
	return str(_steam_ref.getSteamID())

func get_steam_username() -> String:
	if not _is_initialized or not _steam_ref:
		return ""
	return _steam_ref.getPersonaName()
