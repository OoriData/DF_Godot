extends Node

## Single source of truth for UI scaling.
##
## We pick one fixed logical width per orientation and lock the viewport to it via
## `content_scale_size`. Combined with the project's `stretch/mode = canvas_items`
## and `stretch/aspect = expand` settings, Godot stretches the entire rendered frame
## to fit the physical window — text, layout, icons, everything together. There is no
## per-node font scaling anywhere; fonts use fixed logical sizes and ride the canvas.

## Fixed logical widths per orientation.
const TARGET_WIDTH_PORTRAIT := 800.0
const TARGET_WIDTH_MOBILE_LANDSCAPE := 1600.0
const TARGET_WIDTH_DESKTOP := 1920.0
## Narrow desktop windows zoom in a little so the UI stays usable.
const TARGET_WIDTH_DESKTOP_SMALL := 1200.0

## Smallest logical width we allow the desktop zoom slider to produce.
const MIN_LOGICAL_WIDTH := 1150.0

## Emitted whenever the logical resolution changes (orientation flip, resize, or a
## desktop zoom change). Consumers re-layout map labels and overlays off this.
signal scale_changed(new_scale)

## Desktop-only manual zoom factor. 1.0 = base target width; higher = larger UI.
## Ignored on mobile/portrait, where the fixed target width is authoritative.
var _user_scale: float = 1.0


func _ready():
	# Pull the persisted desktop zoom before the first apply (SettingsManager is an
	# earlier autoload, so its node already exists here).
	var sm = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		var val = sm.get_value("ui.scale")
		if val != null:
			_user_scale = clampf(float(val), 0.5, 4.0)

	_apply_logical_resolution()
	get_viewport().size_changed.connect(_apply_logical_resolution)
	# Fires when the window is dragged to a monitor with a different DPI.
	get_window().dpi_changed.connect(_apply_logical_resolution)


func _apply_logical_resolution() -> void:
	var win_sz := Vector2(get_window().size)
	var target_w := _base_target_width(win_sz)

	# Desktop manual zoom shrinks the logical width, which enlarges everything.
	if not _is_portrait(win_sz) and not _is_mobile():
		target_w = target_w / _user_scale

	# We scale via content_scale_factor (a pure 2D multiplier), NOT content_scale_size.
	# content_scale_size with a zero axis is silently ignored by Godot, which is why
	# it never worked here. content_scale_factor reliably magnifies all canvas_items.
	#
	# factor = physical window width / target logical width. As the window grows the
	# factor grows, so the UI scales up proportionally (fixed logical design width).
	# Using the physical width also auto-compensates for HiDPI: on a Retina display the
	# physical width is larger, so the factor is larger, keeping apparent size stable.
	var factor := win_sz.x / target_w
	get_window().content_scale_size = Vector2i(0, 0)
	get_window().content_scale_factor = factor
	scale_changed.emit(get_global_ui_scale())


func _base_target_width(win_sz: Vector2) -> float:
	if _is_portrait(win_sz):
		return TARGET_WIDTH_PORTRAIT
	if _is_mobile():
		return TARGET_WIDTH_MOBILE_LANDSCAPE
	if win_sz.x < 1200:
		return TARGET_WIDTH_DESKTOP_SMALL
	return TARGET_WIDTH_DESKTOP


func _is_portrait(win_sz: Vector2) -> bool:
	return win_sz.y > win_sz.x


func _is_mobile() -> bool:
	return DisplayServer.get_name() in ["Android", "iOS"]


## The effective scale applied to all 2D content. This is the content_scale_factor.
func get_global_ui_scale() -> float:
	return get_window().content_scale_factor


## Called by SettingsManager when the desktop UI scale slider changes.
func set_global_ui_scale(value: float) -> void:
	_user_scale = clampf(value, 0.5, 4.0)
	_apply_logical_resolution()


## Upper bound for the desktop zoom slider: the scale that would shrink the logical
## width down to MIN_LOGICAL_WIDTH, below which the layout starts to overlap.
func get_max_safe_scale() -> float:
	var win_sz := get_window().size
	var is_portrait := win_sz.y > win_sz.x
	var min_logical := MIN_LOGICAL_WIDTH
	if is_portrait:
		# Portrait must allow a much smaller logical width for narrow screens.
		min_logical = MIN_LOGICAL_WIDTH * 0.5
	return float(win_sz.x) / min_logical


func get_logical_safe_margins() -> Rect2:
	var safe_area := DisplayServer.get_display_safe_area()
	var margins := Rect2()
	var screen_size := DisplayServer.screen_get_size()
	var scale := get_global_ui_scale()

	if scale <= 0.001:
		return margins

	# Convert physical margins to logical pixels.
	margins.position.x = safe_area.position.x / scale
	margins.position.y = safe_area.position.y / scale
	margins.size.x = (screen_size.x - safe_area.end.x) / scale
	margins.size.y = (screen_size.y - safe_area.end.y) / scale

	return margins
