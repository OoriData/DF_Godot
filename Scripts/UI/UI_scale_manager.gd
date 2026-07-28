extends Node

## Single source of truth for UI scaling.
##
## We pick one fixed logical width per orientation and lock the viewport to it via
## `content_scale_size`. Combined with the project's `stretch/mode = canvas_items`
## and `stretch/aspect = expand` settings, Godot stretches the entire rendered frame
## to fit the physical window — text, layout, icons, everything together. There is no
## per-node font scaling anywhere; fonts use fixed logical sizes and ride the canvas.
##
## Robustness note (Steam/exported builds): the scale is derived purely from the window
## size, and exported builds do NOT reliably fire `size_changed` once the window reaches
## its final size, after Steam/the window manager places it on a monitor, or after a DPI
## change. A one-shot apply at `_ready` therefore latched a wrong (sometimes zero) factor
## and never corrected — which showed up as the blank login screen (factor ≈ 0 collapses
## every Control) and the offset main screen. This manager now (a) guards against a bogus
## window size, (b) re-applies across the first frames + a short delay after boot, and
## (c) keeps a cheap per-frame safety poll that re-applies whenever the window size
## actually changes without a signal (e.g. dragged to a different-DPI monitor).

## Fixed logical widths per orientation.
const TARGET_WIDTH_PORTRAIT := 800.0
const TARGET_WIDTH_MOBILE_LANDSCAPE := 1600.0
const TARGET_WIDTH_DESKTOP := 1920.0
## Narrow desktop windows zoom in a little so the UI stays usable.
const TARGET_WIDTH_DESKTOP_SMALL := 1200.0

## Smallest logical width we allow the desktop zoom slider to produce.
const MIN_LOGICAL_WIDTH := 1150.0

## Never let content_scale_factor collapse the UI to an invisible point. If the window
## reports a near-zero size for a frame — which happens in exported/Steam builds during
## boot, window placement, or a monitor (DPI) change — factor ≈ 0 shrinks every Control
## to nothing (the "only the background tile shows" bug). Clamp to this floor.
const _MIN_SAFE_FACTOR := 0.05

## Emitted whenever the logical resolution changes (orientation flip, resize, or a
## desktop zoom change). Consumers re-layout map labels and overlays off this.
signal scale_changed(new_scale)

## Desktop-only manual zoom factor. 1.0 = base target width; higher = larger UI.
## Ignored on mobile/portrait, where the fixed target width is authoritative.
var _user_scale: float = 1.0

## Diagnostics: log every scale (re)application with the window/viewport numbers behind
## it, so exported/Steam builds record why the UI scaled the way it did. Set false to mute.
var _debug_scale: bool = true

## Last values actually applied, so the safety poll and signal handlers skip redundant work
## and never re-emit scale_changed (which re-lays-out the whole UI) when nothing changed.
var _last_win_size: Vector2i = Vector2i.ZERO
var _last_factor: float = -1.0

## False while the last computed factor had to be rescued by `_MIN_SAFE_FACTOR` — i.e. the window
## reported a bogus size and the scale is not trustworthy yet. Only matters to callers that
## *divide* by the scale: `get_logical_safe_margins()` turns a ~47px physical notch inset into
## ~940 logical px at the 0.05 floor, and a consumer that latches that value (the top bar did)
## keeps it forever. Read via `is_scale_settled()`.
var _scale_settled: bool = false


func _ready():
	# Pull the persisted desktop zoom before the first apply (SettingsManager is an
	# earlier autoload, so its node already exists here).
	var sm := get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		var val: Variant = sm.get_value("ui.scale")
		if val != null:
			_user_scale = clampf(float(val), 0.5, 4.0)

	_apply_logical_resolution()
	get_viewport().size_changed.connect(_apply_logical_resolution)
	# Fires when the window is dragged to a monitor with a different DPI.
	get_window().dpi_changed.connect(_apply_logical_resolution)
	# Exported/Steam builds don't reliably emit size_changed once the window reaches its
	# final size (or after the window manager / Steam places it on another monitor), so the
	# boot apply above can latch a wrong (or zero) factor and never correct. Re-apply across
	# the first few frames and once more after a short delay to catch a late placement/DPI
	# settle. (Called without await — fire-and-forget coroutine.)
	_settle_scale_after_boot()


func _process(_delta: float) -> void:
	# Safety net for cases no signal covers: a window moved to a different-DPI monitor, or a
	# size change the platform never reported. Cheap — only re-applies on an actual change.
	if get_window().size != _last_win_size:
		_apply_logical_resolution()


func _settle_scale_after_boot() -> void:
	for _frame in 4:
		await get_tree().process_frame
		_apply_logical_resolution()
	await get_tree().create_timer(0.5).timeout
	_apply_logical_resolution()


## Public re-entry for callers that change the window mode (e.g. the fullscreen toggle)
## and need the logical scale recomputed for the new window geometry.
func reapply_scale() -> void:
	_apply_logical_resolution()


func _apply_logical_resolution() -> void:
	var win_sz_i := get_window().size
	# Guard against a bogus / zero window size during boot or a mode transition. Bail and let
	# the poll (or a later signal) re-apply once the window reports a real size, instead of
	# baking a factor of ~0 that collapses every Control to an invisible point.
	if win_sz_i.x <= 0 or win_sz_i.y <= 0:
		return

	var win_sz := Vector2(win_sz_i)
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
	var factor: float = win_sz.x / target_w
	# A factor that had to be rescued by the floor is NOT a real scale — it means the window
	# reported a bogus size this frame. Remember that, so consumers that DIVIDE by the scale
	# (get_logical_safe_margins) don't bake a 20x-inflated inset from it. See _scale_settled.
	_scale_settled = factor >= _MIN_SAFE_FACTOR
	if factor < _MIN_SAFE_FACTOR:
		factor = _MIN_SAFE_FACTOR

	_last_win_size = win_sz_i

	# Nothing changed → don't re-emit scale_changed (it re-lays-out the whole UI) or thrash
	# content_scale_factor. Keeps the per-frame poll and any signal feedback idempotent.
	if is_equal_approx(factor, _last_factor):
		return
	_last_factor = factor

	get_window().content_scale_size = Vector2i(0, 0)
	get_window().content_scale_factor = factor

	if _debug_scale:
		var scr: int = get_window().current_screen
		print("[UIScale] win=%s factor=%.4f target_w=%.1f vp=%s screen=%d screen_size=%s" % [
			str(win_sz_i), factor, target_w, str(get_viewport().get_visible_rect().size),
			scr, str(DisplayServer.screen_get_size(scr))])

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


## True once a real (non-rescued) scale factor has been applied. Callers that divide by the scale
## should treat a false here as "no safe-area data yet" and re-ask on `scale_changed`.
func is_scale_settled() -> bool:
	return _scale_settled


## Physical safe-area insets converted to LOGICAL pixels.
## Rect2(position = (left, top), size = (right, bottom)).
##
## DANGER — this DIVIDES by `content_scale_factor`. During an exported/Steam boot the window can
## report a bogus size for a frame, pinning the factor at the `_MIN_SAFE_FACTOR` (0.05) floor; a
## ~47px macOS menu-bar/notch inset then converts to ~940 *logical* px. A consumer that writes that
## into a `custom_minimum_size` or a stylebox `content_margin` and never recomputes ends up with a
## chrome element that eats the whole screen. Two guards below:
##   1. Return zero margins until the scale is settled (never emit a value derived from the floor).
##   2. Cap each inset at a sane fraction of the logical viewport — a safe area is a notch, never
##      a third of the screen — so an unforeseen bad divisor still can't produce a screen-eater.
## Consumers must ALSO re-query on `scale_changed`, or they will latch the zero from guard (1).
const _MAX_SAFE_INSET_FRACTION := 0.2

func get_logical_safe_margins() -> Rect2:
	var margins := Rect2()
	if not _scale_settled:
		return margins

	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size := DisplayServer.screen_get_size()
	var scale := get_global_ui_scale()

	if scale <= 0.001:
		return margins

	# Convert physical margins to logical pixels.
	margins.position.x = safe_area.position.x / scale
	margins.position.y = safe_area.position.y / scale
	margins.size.x = (screen_size.x - safe_area.end.x) / scale
	margins.size.y = (screen_size.y - safe_area.end.y) / scale

	var logical: Vector2 = get_viewport().get_visible_rect().size
	var max_x: float = maxf(0.0, logical.x * _MAX_SAFE_INSET_FRACTION)
	var max_y: float = maxf(0.0, logical.y * _MAX_SAFE_INSET_FRACTION)
	margins.position.x = clampf(margins.position.x, 0.0, max_x)
	margins.position.y = clampf(margins.position.y, 0.0, max_y)
	margins.size.x = clampf(margins.size.x, 0.0, max_x)
	margins.size.y = clampf(margins.size.y, 0.0, max_y)

	return margins
