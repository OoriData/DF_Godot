extends Control

@onready var visualizer = $ConvoyVisualizer

func _ready() -> void:
    var test_data = {
        "vehicles": [
            {"id": "1", "shape": "pickup", "color": "red", "weight_class": 1.0},
            {"id": "2", "shape": "box", "color": "blue", "weight_class": 2.0},
            {"id": "3", "shape": "suv", "color": "green", "weight_class": 1.5},
            {"id": "4", "shape": "sedan", "color": "yellow", "weight_class": 0.5}
        ],
        "journey": {"status": "moving"} # To trigger moving state
    }
    visualizer.initialize_with_convoy(test_data)
