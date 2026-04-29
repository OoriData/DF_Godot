extends SceneTree

func _init():
	print("--- Scene Tree Root Nodes ---")
	for child in root.get_children():
		print("- ", child.name, " (", child.get_class(), ")")
	quit()
