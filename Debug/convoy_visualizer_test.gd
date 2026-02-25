extends Control

@onready var visualizer = $ConvoyVisualizer
@onready var state_button = %StateButton
@onready var difficulty_label = %DifficultyLabel
@onready var difficulty_slider = %DifficultySlider
@onready var direction_button = %DirectionButton
@onready var reset_button = %ResetButton

func _ready() -> void:
	var test_convoy = {
		"convoy_id": "test_convoy_1",
		"name": "Test Run",
		"journey": {"journey_id": "test_j_1"},
		"vehicle_details_list": [
			{
				"vehicle_id": "v1",
				"color": "olivedrab",
				"shape": "jeep",
				"weight_class": 1.0,
				"driven_wheels": [true, true],
				"cargo": [1, 2]
			},
			{
				"vehicle_id": "v2",
				"color": "brown",
				"shape": "semi_truck",
				"weight_class": 3.0,
				"driven_wheels": [false, true, true],
				"cargo": [1, 2, 3, 4]
			}
		]
	}
	
	visualizer.initialize_with_convoy(test_convoy)
