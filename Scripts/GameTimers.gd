# GameTimers.gd
extends Node

signal data_refresh_tick
signal visual_update_tick

@export_group("Timer Intervals") # This helps organize variables in the Inspector
## The time in seconds between each attempt to refresh data (e.g., from an API).
@export var refresh_interval_seconds: float = 60.0  
## The time in seconds between each visual update tick, used for animations like throbbing. (e.g., 1.0/60.0 for 60 FPS).
@export var visual_update_interval_seconds: float = 1.0 / 60.0  

var _refresh_timer: Timer
var _visual_update_timer: Timer

func _ready():
	# Setup and start the data refresh timer
	_refresh_timer = Timer.new()
	_refresh_timer.name = "DataRefreshTimer"
	_refresh_timer.wait_time = refresh_interval_seconds 
	_refresh_timer.one_shot = false # Make it repeat
	_refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	add_child(_refresh_timer)
	_refresh_timer.start()
	print("GameTimers: Data refresh timer started for every %s seconds." % refresh_interval_seconds) 

	# Setup and start the visual update timer
	_visual_update_timer = Timer.new()
	_visual_update_timer.name = "VisualUpdateTimer"
	_visual_update_timer.wait_time = visual_update_interval_seconds 
	_visual_update_timer.one_shot = false # Make it repeat
	_visual_update_timer.timeout.connect(_on_visual_update_timer_timeout)
	add_child(_visual_update_timer)
	_visual_update_timer.start()
	print("GameTimers: Visual update timer started for every %s seconds." % visual_update_interval_seconds) 

func _on_refresh_timer_timeout():
	emit_signal("data_refresh_tick")

func _on_visual_update_timer_timeout():
	emit_signal("visual_update_tick")
func get_visual_update_interval() -> float:
	return visual_update_interval_seconds 
