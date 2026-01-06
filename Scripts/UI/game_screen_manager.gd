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

	# Phase C: bootstrap via APICalls + Services (no GameDataManager).
	var api := get_node_or_null("/root/APICalls")
	if is_instance_valid(api):
		if api.has_method("set_user_id"):
			api.set_user_id(current_user_id)
		# Refresh user snapshot
		if api.has_method("refresh_user_data"):
			api.refresh_user_data(current_user_id)
		elif api.has_method("get_user_data"):
			api.get_user_data(current_user_id)
		# Fetch convoys for this user
		if api.has_method("get_user_convoys"):
			api.get_user_convoys(current_user_id)
		# Map request is not user-scoped; fetch once here if available
		if api.has_method("get_map_data"):
			api.get_map_data()

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
