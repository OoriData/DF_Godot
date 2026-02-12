extends Node
class_name GameScreenManager

# References to the main screens controlled by this manager.
@onready var login_screen: Control = $LoginScreen
@onready var main_screen: Control = $MainScreen

var current_user_id: String = ""

const LOGIN_SCREEN_SCENE_PATH := "res://Scenes/LoginScreen.tscn"


func _ready():
	# Ensure we have the necessary nodes.
	if not is_instance_valid(login_screen) or not is_instance_valid(main_screen):
		printerr("GameScreenManager: LoginScreen or MainScreen node not found. Check the scene tree in GameRoot.")
		return

	# Connect to the login screen's signal.
	# Note: We will need to ensure login_screen.gd defines and emits this signal.
	if not login_screen.is_connected("login_successful", Callable(self, "_on_login_successful")):
		login_screen.connect("login_successful", Callable(self, "_on_login_successful"))

	# Start the game with only the login screen visible and active.
	main_screen.visible = false
	main_screen.process_mode = Node.PROCESS_MODE_DISABLED # Keep it from running in the background
	login_screen.visible = true
	login_screen.process_mode = Node.PROCESS_MODE_ALWAYS # Allow login screen to work while paused
	get_tree().paused = true # Pause the main game tree
	print("GameScreenManager: Ready. Showing Login Screen.")


func _on_login_successful(user_id: String) -> void:
	print("GameScreenManager: Login successful for User ID:", user_id)
	current_user_id = user_id

	# Re-enable periodic refresh now that we're authenticated.
	var refresh := get_node_or_null("/root/RefreshScheduler")
	if is_instance_valid(refresh) and refresh.has_method("enable_polling"):
		refresh.enable_polling(true)

	# Phase 4: bootstrap via Services and Store only (no direct APICalls wiring).
	var user_service := get_node_or_null("/root/UserService")
	if is_instance_valid(user_service) and user_service.has_method("refresh_user"):
		user_service.refresh_user(current_user_id)
	# Trigger convoy refresh after the user snapshot arrives to avoid race conditions.
	var convoy_service := get_node_or_null("/root/ConvoyService")
	var store := get_node_or_null("/root/GameStore")
	if is_instance_valid(store) and store.has_signal("user_changed") and is_instance_valid(convoy_service) and convoy_service.has_method("refresh_all"):
		var cb := func(_u: Dictionary):
			var logger := get_node_or_null("/root/Logger")
			if is_instance_valid(logger) and logger.has_method("info"):
				logger.info("GameScreenManager: user_changed received; triggering convoy refresh")
			convoy_service.refresh_all()
		# Connect as one-shot to auto-disconnect after first emission
		store.user_changed.connect(cb, Object.CONNECT_ONE_SHOT)
	elif is_instance_valid(convoy_service) and convoy_service.has_method("refresh_all"):
		convoy_service.refresh_all()
	var map_service := get_node_or_null("/root/MapService")
	if is_instance_valid(map_service) and map_service.has_method("request_map"):
		map_service.request_map()

	# Remove the login screen completely to prevent any input blocking.
	if is_instance_valid(login_screen):
		login_screen.queue_free()

	# Show and enable the main game screen.
	main_screen.visible = true
	main_screen.process_mode = Node.PROCESS_MODE_INHERIT # Wake up the main screen
	
	get_tree().paused = false # IMPORTANT: Un-pause the game tree

	# NEW: Explicitly enable interaction on the main screen.
	if main_screen.has_method("set_map_interactive"):
		main_screen.set_map_interactive(true)
	else:
		printerr("GameScreenManager: MainScreen is missing the 'set_map_interactive' method.")

	# NEW: Force camera update after main screen is visible and unpaused
	if main_screen.has_method("force_camera_update"):
		await main_screen.force_camera_update()
	else:
		printerr("GameScreenManager: MainScreen is missing the 'force_camera_update' method.")

	print("GameScreenManager: Switched to Main Screen.")


func logout_to_login() -> void:
	# Transition back to the login screen without restarting the app process.
	# Note: autoload singletons persist, so we also clear store snapshots and stop polling.
	current_user_id = ""

	var refresh := get_node_or_null("/root/RefreshScheduler")
	if is_instance_valid(refresh) and refresh.has_method("enable_polling"):
		refresh.enable_polling(false)

	var store := get_node_or_null("/root/GameStore")
	if is_instance_valid(store) and store.has_method("reset_all"):
		store.reset_all()

	if is_instance_valid(main_screen):
		main_screen.visible = false
		main_screen.process_mode = Node.PROCESS_MODE_DISABLED
		if main_screen.has_method("set_map_interactive"):
			main_screen.set_map_interactive(false)

	# Recreate LoginScreen if it was freed after a previous successful login.
	if not is_instance_valid(login_screen):
		var scene_res: Resource = load(LOGIN_SCREEN_SCENE_PATH)
		if scene_res != null and scene_res is PackedScene:
			login_screen = (scene_res as PackedScene).instantiate()
			login_screen.name = "LoginScreen"
			add_child(login_screen)
		else:
			printerr("GameScreenManager: Failed to load LoginScreen scene at ", LOGIN_SCREEN_SCENE_PATH)
			# Fallback: at least reload the current scene so the user can log back in.
			get_tree().reload_current_scene()
			return

	# Ensure signal wired for the new instance.
	if is_instance_valid(login_screen):
		if not login_screen.is_connected("login_successful", Callable(self, "_on_login_successful")):
			login_screen.connect("login_successful", Callable(self, "_on_login_successful"))
		login_screen.visible = true
		login_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	get_tree().paused = true
	print("GameScreenManager: Logged out. Showing Login Screen.")
