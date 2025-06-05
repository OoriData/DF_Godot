# res://Scripts/temp_main_test.gd
extends Node2D

func _ready():
	print("!!!!!!!!!! TEMP_MAIN_TEST.GD _ready() IS RUNNING !!!!!!!!!!")
	print("TEMP_MAIN_TEST.GD: Node Name: ", name)
	print("TEMP_MAIN_TEST.GD: Node Path: ", get_path())
	if get_parent():
		print("TEMP_MAIN_TEST.GD: Parent Name: ", get_parent().name)
	else:
		print("TEMP_MAIN_TEST.GD: No Parent.")
