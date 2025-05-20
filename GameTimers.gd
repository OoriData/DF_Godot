# GameTimers.gd
extends Node

signal data_refresh_tick
signal visual_update_tick

const REFRESH_INTERVAL_SECONDS: float = 60.0  # Interval for refreshing data (e.g., API calls)
const VISUAL_UPDATE_INTERVAL_SECONDS: float = 1.0 / 60.0  # Interval for visual updates (e.g., animations)

var _refresh_timer: Timer
var _visual_update_timer: Timer

func _ready():
	# Setup and start the data refresh timer
	_refresh_timer = Timer.new()
	_refresh_timer.name = "DataRefreshTimer"
	_refresh_timer.wait_time = REFRESH_INTERVAL_SECONDS
	_refresh_timer.one_shot = false # Make it repeat
	_refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	add_child(_refresh_timer)
	_refresh_timer.start()
	print("GameTimers: Data refresh timer started for every %s seconds." % REFRESH_INTERVAL_SECONDS)

	# Setup and start the visual update timer
	_visual_update_timer = Timer.new()
	_visual_update_timer.name = "VisualUpdateTimer"
	_visual_update_timer.wait_time = VISUAL_UPDATE_INTERVAL_SECONDS
	_visual_update_timer.one_shot = false # Make it repeat
	_visual_update_timer.timeout.connect(_on_visual_update_timer_timeout)
	add_child(_visual_update_timer)
	_visual_update_timer.start()
	print("GameTimers: Visual update timer started for every %s seconds." % VISUAL_UPDATE_INTERVAL_SECONDS)

func _on_refresh_timer_timeout():
	emit_signal("data_refresh_tick")

func _on_visual_update_timer_timeout():
	emit_signal("visual_update_tick")

func get_visual_update_interval() -> float:
	return VISUAL_UPDATE_INTERVAL_SECONDS