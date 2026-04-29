extends SceneTree

func _init():
	var s = load("res://Scripts/UI/main_screen.gd")
	if s == null:
		print("FAILED to load main_screen.gd")
	else:
		print("SUCCESSFULLY loaded main_screen.gd")
	quit()
