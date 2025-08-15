extends Node
class_name GameScreenManager

# References to the main screens controlled by this manager.
@onready var login_screen: Control = $LoginScreen
@onready var main_screen: Control = $MainScreen

var current_user_id: String = ""


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

	var already_bootstrapped := false
	if Engine.has_singleton("GameDataManager"):
		# not typical; fallback path
		pass
	if GameDataManager:
		# Access internal flag safely; if missing, defaults false
		if GameDataManager.has_method("get"):
			var val = GameDataManager.get("_user_bootstrap_done")
			already_bootstrapped = (typeof(val) == TYPE_BOOL and val)

	if already_bootstrapped:
		print("GameScreenManager: Data bootstrap already performed; skipping manual initial convoy fetch.")
	elif GameDataManager and GameDataManager.has_method("trigger_initial_convoy_data_fetch"):
		print("GameScreenManager: Triggering initial convoy data fetch (manual path).")
		GameDataManager.trigger_initial_convoy_data_fetch(current_user_id)

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
