extends Node2D
## settlement_overlay_draw.gd
##
## Draws four world-space overlays for visible settlement labels:
##   1. Route arcs    — curved arrows from focus origin to each cargo destination.
##   2. Callout tails — filled triangle from label panel bottom-center to tile center.
##   3. Tile outlines — contrasting rectangle drawn exactly around a settlement tile.
##   4. Focus pins    — location-pin shape above tiles that are the active focus origin.
##
## This node should be a child of settlement_label_container (Node2D, world-space).
## UIManager calls update_frame() each draw pass to push fresh data.

# --- Data structs fed by UIManager each frame ---

## {
##   "panel_bottom_center": Vector2,
##   "tile_center":         Vector2,
##   "bg_color":            Color,
##   "panel_scale":         float,
## }
var tail_data: Array = []

## {
##   "tile_center": Vector2,
##   "color":       Color,
## }
var outline_data: Array = []

## {
##   "tile_center": Vector2,
##   "color":       Color,
## }
var focus_pins_data: Array = []

## {
##   "from":  Vector2,   # world-space source tile center
##   "to":    Vector2,   # world-space destination tile center
##   "color": Color,
## }
var arc_data: Array = []

# --- Appearance tweakables ---

var tail_half_width_px: float  = 5.5
var tail_min_dist: float       = 6.0
var outline_width_px: float    = 2.0
var outline_color: Color       = Color(1.0, 1.0, 1.0, 0.75)
var outline_inset_px: float    = 1.0
var pin_head_radius_px: float  = 5.0
var pin_gap_px: float          = 2.0

## Stroke width of arc lines in screen-pixels.
var arc_width_px: float        = 1.5
## Arrowhead size in screen-pixels.
var arc_arrow_size_px: float   = 7.0
## Number of line segments used to approximate each arc.
var arc_segments: int          = 28
## How much the arc bows sideways — fraction of the chord length.
var arc_bow_fraction: float    = 0.28

var _tile_size: Vector2 = Vector2(32.0, 32.0)
var _zoom: float        = 1.0


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

func update_frame(
		p_tail_data: Array,
		p_outline_data: Array,
		p_zoom: float,
		p_tile_size: Vector2,
		p_focus_pins_data: Array = [],
		p_arc_data: Array = []
) -> void:
	tail_data       = p_tail_data
	outline_data    = p_outline_data
	focus_pins_data = p_focus_pins_data
	arc_data        = p_arc_data
	_zoom           = p_zoom
	_tile_size      = p_tile_size
	queue_redraw()


func clear_frame() -> void:
	tail_data       = []
	outline_data    = []
	focus_pins_data = []
	arc_data        = []
	queue_redraw()


# -------------------------------------------------------------------
# Draw  (order matters for layering)
# -------------------------------------------------------------------

func _draw() -> void:
	_draw_arcs()          # beneath everything
	_draw_tile_outlines()
	_draw_tails()
	_draw_focus_pins()    # on top


func _draw_arcs() -> void:
	if arc_data.is_empty():
		return
	var inv_zoom: float  = 1.0 / max(0.001, _zoom)
	var line_w: float    = arc_width_px  * inv_zoom
	var arrow_sz: float  = arc_arrow_size_px * inv_zoom

	for d in arc_data:
		var src: Vector2 = d.get("from",  Vector2.ZERO)
		var dst: Vector2 = d.get("to",    Vector2.ZERO)
		var col: Color   = d.get("color", Color(1.0, 1.0, 1.0, 0.55))
		if col.a < 0.01:
			continue
		var chord: float = src.distance_to(dst)
		if chord < _tile_size.x * 0.5:
			continue

		# Control point: perpendicular left of travel direction, bowing outward.
		var dir: Vector2  = (dst - src) / chord
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var ctrl: Vector2 = (src + dst) * 0.5 + perp * chord * arc_bow_fraction

		# Sample quadratic bezier.
		var pts: PackedVector2Array = PackedVector2Array()
		pts.resize(arc_segments + 1)
		for i in range(arc_segments + 1):
			var t: float  = float(i) / float(arc_segments)
			var mt: float = 1.0 - t
			pts[i] = mt * mt * src + 2.0 * mt * t * ctrl + t * t * dst

		draw_polyline(pts, col, line_w, true)

		# Arrowhead at destination — tangent at t=1 is (dst - ctrl).
		var a_dir: Vector2  = (dst - ctrl).normalized()
		var a_perp: Vector2 = Vector2(-a_dir.y, a_dir.x)
		var base: Vector2   = dst - a_dir * arrow_sz
		draw_colored_polygon(PackedVector2Array([
			dst,
			base + a_perp * arrow_sz * 0.45,
			base - a_perp * arrow_sz * 0.45,
		]), col)


func _draw_tile_outlines() -> void:
	var inv_zoom: float = 1.0 / max(0.001, _zoom)
	var stroke: float   = outline_width_px * inv_zoom
	var inset: float    = outline_inset_px * inv_zoom
	var half: Vector2   = _tile_size * 0.5

	for d in outline_data:
		var center: Vector2 = d.get("tile_center", Vector2.ZERO)
		var col: Color      = d.get("color", outline_color)
		if col.a < 0.01:
			continue
		var rect: Rect2 = Rect2(
			center - half + Vector2(inset, inset),
			_tile_size - Vector2(inset, inset) * 2.0
		)
		draw_rect(rect, col, false, stroke)


func _draw_tails() -> void:
	for d in tail_data:
		var bottom: Vector2 = d.get("panel_bottom_center", Vector2.ZERO)
		var tip: Vector2    = d.get("tile_center",          Vector2.ZERO)
		var bg: Color       = d.get("bg_color",             Color(0.14, 0.16, 0.21, 0.90))
		var pscale: float   = d.get("panel_scale",          1.0)
		var dist: float     = bottom.distance_to(tip)
		if dist < tail_min_dist:
			continue
		var dir: Vector2  = (tip - bottom) / dist
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var hw: float     = tail_half_width_px * pscale
		draw_colored_polygon(PackedVector2Array([
			bottom - perp * hw,
			bottom + perp * hw,
			tip,
		]), bg)


func _draw_focus_pins() -> void:
	if focus_pins_data.is_empty():
		return
	var inv_zoom: float = 1.0 / max(0.001, _zoom)
	var head_r: float   = pin_head_radius_px * inv_zoom
	var gap: float      = pin_gap_px * inv_zoom
	var half_y: float   = _tile_size.y * 0.5

	for d in focus_pins_data:
		var center: Vector2 = d.get("tile_center", Vector2.ZERO)
		var col: Color      = d.get("color", Color.WHITE)
		if col.a < 0.01:
			continue
		var tile_top: Vector2 = center + Vector2(0.0, -half_y)
		var pin_tip: Vector2  = tile_top  - Vector2(0.0, gap)
		var head_c: Vector2   = pin_tip   - Vector2(0.0, head_r * 1.8)

		# Shadow.
		draw_circle(head_c + Vector2(inv_zoom, inv_zoom * 1.5), head_r + inv_zoom,
				Color(0.0, 0.0, 0.0, col.a * 0.45))

		# Body triangle.
		var body_hw: float = head_r * 0.55
		draw_colored_polygon(PackedVector2Array([
			head_c + Vector2(-body_hw,  head_r * 0.55),
			head_c + Vector2( body_hw,  head_r * 0.55),
			pin_tip,
		]), col)

		# Head circle + inner dot.
		draw_circle(head_c, head_r, col)
		draw_circle(head_c, head_r * 0.38, Color(1.0, 1.0, 1.0, col.a * 0.85))
