# Scripts/UI/main_screen.gd
extends Control

signal menu_opened(map_view_rect: Rect2)
signal menu_closed(map_view_rect: Rect2)

# To these new paths:
@onready var map_view = $MainContainer/MainContent/MapView
@onready var menu_container = $MainContainer/MainContent/MenuContainer
@onready var top_bar = $MainContainer/TopBar
@onready var main_container = $MainContainer

# Preload the different menu scenes we might want to show
var convoy_menu_scene = preload("res://Scenes/ConvoyMenu.tscn")
# You can add other menu scenes here later, e.g.:
# var settlement_menu_scene = preload("res://Scenes/SettlementMenu.tscn")

var current_menu = null

@onready var main_content = $MainContainer/MainContent

func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS
	# --- Node Validation ---
	if not is_instance_valid(map_view):
		printerr("MainScreen Error: 'map_view' node not found. Check path in main_screen.gd.")
	if not is_instance_valid(menu_container):
		printerr("MainScreen Error: 'menu_container' node not found. Check path in main_screen.gd.")
	if not is_instance_valid(top_bar):
		printerr("MainScreen Error: 'top_bar' node not found. Check path in main_screen.gd.")
		return # Cannot connect button if top_bar is missing

	# Allow mouse input to pass through containers to their children.
	if is_instance_valid(main_container):
		main_container.mouse_filter = Control.MOUSE_FILTER_PASS
	if is_instance_valid(main_content):
		main_content.mouse_filter = Control.MOUSE_FILTER_PASS

	# Explicitly set the map_view to pass mouse events so the camera can receive them.
	if is_instance_valid(map_view):
		map_view.mouse_filter = Control.MOUSE_FILTER_PASS

	# Start with the menu hidden and the map taking up the full width.
	hide_menu()
# ...existing code...


	# Find the button in the top bar and connect its signal to open the convoy menu.
	var convoy_button = top_bar.find_child("ConvoyMenuButton")
	if convoy_button:
		if not convoy_button.is_connected("pressed", Callable(self, "on_convoy_selected")):
			convoy_button.pressed.connect(on_convoy_selected)
	else:
		printerr("MainScreen: Could not find ConvoyMenuButton in TopBar.")


# Call this function to show a menu, passing the scene to instance.
func show_menu(menu_scene):
	if not is_instance_valid(map_view) or not is_instance_valid(menu_container):
		printerr("MainScreen Error: Cannot show menu because map_view or menu_container is not valid.")
		return

	# If there's already a menu, remove it first.
	if current_menu and is_instance_valid(current_menu):
		current_menu.queue_free()

	# Instance the new menu and add it to the container.
	current_menu = menu_scene.instantiate()
	menu_container.add_child(current_menu)

	# Connect the new menu's back signal to the hide_menu function.
	if current_menu.has_user_signal("back_requested"):
		if not current_menu.is_connected("back_requested", Callable(self, "hide_menu")):
			current_menu.back_requested.connect(hide_menu)

	# Make the menu container visible and allow mouse events to pass through except for its children.
	menu_container.visible = true
	menu_container.mouse_filter = Control.MOUSE_FILTER_PASS

	# Adjust the layout to split the screen.
	# Map takes 1/3, Menu takes 2/3
	map_view.size_flags_stretch_ratio = 0.33
	menu_container.size_flags_stretch_ratio = 0.67
	
	# Wait for the layout to update, then emit the signal
	await get_tree().process_frame
	emit_signal("menu_opened")

# Call this function to hide the menu panel.
func hide_menu():
	if not is_instance_valid(map_view) or not is_instance_valid(menu_container):
		printerr("MainScreen Error: Cannot hide menu because map_view or menu_container is not valid.")
		return

	# If there's a menu, remove it.
	if current_menu and is_instance_valid(current_menu):
		current_menu.queue_free()
		current_menu = null

	# Hide the container and make sure it doesn't block any input.
	menu_container.visible = false
	menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Make the map take up the full width again.
	map_view.size_flags_stretch_ratio = 1
	menu_container.size_flags_stretch_ratio = 0
	
	# Wait for the layout to update, then emit the signal
	await get_tree().process_frame
	emit_signal("menu_closed")

# Example function that might be called when a convoy is selected.
# You would call this from another script, e.g., via a signal.
func on_convoy_selected():
	show_menu(convoy_menu_scene)

# Example function to close the menu.
# You could connect the "Back" button in your menu to this.
func on_back_button_pressed():
	hide_menu()

func set_map_interactive(is_interactive: bool):
	if is_instance_valid(map_view) and map_view.has_method("set_interactive"):
		map_view.set_interactive(is_interactive)
		print("MainScreen: MapView interaction set to: %s" % is_interactive)
	else:
		printerr("MainScreen: Could not find MapView or it's missing 'set_interactive' method.")
