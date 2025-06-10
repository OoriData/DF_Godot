extends Node

# Adjust these paths based on your actual scene tree structure
# These paths are relative to the node where GameScreenManager.gd is attached (e.g., GameRoot)
@onready var map_viewport_container: SubViewportContainer = get_node("MapViewportContainer") # This is correct for Godot 4
@onready var menu_manager: Control = get_node("MenuUILayer/MenuManager")

func _ready():
	if not is_instance_valid(menu_manager):
		printerr("GameScreenManager: MenuManager node not found. Check path.")
		return
	if not is_instance_valid(map_viewport_container):
		printerr("GameScreenManager: MapViewportContainer node not found. Check path.")
		return

	# Connect to signals from MenuManager
	if menu_manager.has_signal("menu_opened"):
		menu_manager.menu_opened.connect(_on_menu_opened)
	else:
		printerr("GameScreenManager: MenuManager does not have 'menu_opened' signal.")

	if menu_manager.has_signal("menus_completely_closed"):
		menu_manager.menus_completely_closed.connect(_on_menus_completely_closed)
	else:
		printerr("GameScreenManager: MenuManager does not have 'menus_completely_closed' signal.")

	# Initial state: map is full screen
	_set_map_view_full_screen()

func _on_menu_opened(_menu_node: Node, menu_type: String):
	# If a menu type that requires a split view is opened
	if menu_type == "convoy_detail": # Add other types if needed
		_set_map_view_partial_screen()
	# Else: You might have other logic, e.g., some menus hide the map,
	# or some menus overlay the full map. For now, only "convoy_detail" shrinks it.
	# If other menus open that don't require split screen, the map remains as is.

func _on_menus_completely_closed():
	_set_map_view_full_screen()

func _set_map_view_partial_screen():
	if not is_instance_valid(map_viewport_container): return
	# Set MapViewportContainer to occupy the left 1/3 of the screen
	map_viewport_container.anchor_right = 1.0 / 3.0
	map_viewport_container.offset_right = 0 # Clear any offset
	print("GameScreenManager: Map view set to partial (left 1/3).")

func _set_map_view_full_screen():
	if not is_instance_valid(map_viewport_container): return
	# Set MapViewportContainer to occupy the full screen
	map_viewport_container.anchor_right = 1.0
	map_viewport_container.offset_right = 0 # Clear any offset
	print("GameScreenManager: Map view set to full screen.")
