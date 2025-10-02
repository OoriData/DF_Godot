extends Control

# Root script for Scenes/OnboardingLayer.tscn. Acts as a container for onboarding UI.
# Keeps references (optional) to helper nodes added at runtime by MainScreen.

var coach: Control = null
var director: Node = null

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
