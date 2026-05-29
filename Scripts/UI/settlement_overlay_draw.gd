extends Node2D
## settlement_overlay_draw.gd
##
## Draws two world-space overlays for every visible settlement label:
##   1. Callout tail  — filled triangle from label panel bottom-center to tile center.
##   2. Tile outline  — contrasting rectangle drawn exactly around the settlement tile.
##
## This node should be a child of settlement_label_container (Node2D, world-space).
## UIManager calls update_frame() each draw pass to push fresh data.

# --- Data structs fed by UIManager each frame ---

## One entry per visible settlement panel.
## {
##   "panel_bottom_center": Vector2,  # world-space bottom-center of the label panel
##   "tile_center":         Vector2,  # world-space tile center (map_to_local)
##   "bg_color":            Color,    # panel background color so the tail blends in
##   "panel_scale":         float,    # 1/zoom — tail width is expressed in world units
## }
var tail_data: Array = []

## One entry per visible settlement — just needs tile_center.
## {
##   "tile_center": Vector2,
## }
var outline_data: Array = []

# --- Appearance tweakables ---

## Half-width of the tail base in screen-pixels (counter-scaled per tail entry).
var tail_half_width_px: float = 5.5

## Minimum panel-to-tile distance before a tail is drawn (world units at zoom 1).
var tail_min_dist: float = 6.0

## Tile outline stroke width in screen-pixels.  Counter-scaled so it stays crisp at any zoom.
var outline_width_px: float = 2.0

## Tile outline color.  Bright with slight transparency so it reads on any terrain.
var outline_color: Color = Color(1.0, 1.0, 1.0, 0.75)

## Inset the outline inward by this many screen-pixels so it sits fully inside the tile edge.
var outline_inset_px: float = 1.0

# Tile size in world units — set from UIManager via update_frame().
var _tile_size: Vector2 = Vector2(32.0, 32.0)

# Current zoom, used to counter-scale screen-constant elements.
var _zoom: float = 1.0


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

func update_frame(
		p_tail_data: Array,
		p_outline_data: Array,
		p_zoom: float,
		p_tile_size: Vector2
) -> void:
	tail_data    = p_tail_data
	outline_data = p_outline_data
	_zoom        = p_zoom
	_tile_size   = p_tile_size
	queue_redraw()


func clear_frame() -> void:
	tail_data    = []
	outline_data = []
	queue_redraw()


# -------------------------------------------------------------------
# Draw
# -------------------------------------------------------------------

func _draw() -> void:
	_draw_tile_outlines()
	_draw_tails()


func _draw_tile_outlines() -> void:
	var inv_zoom: float = 1.0 / max(0.001, _zoom)
	var stroke: float   = outline_width_px * inv_zoom
	var inset: float    = outline_inset_px * inv_zoom
	var half: Vector2   = _tile_size * 0.5

	for d in outline_data:
		var center: Vector2 = d.get("tile_center", Vector2.ZERO)
		# Build the inset rect so the stroke stays fully inside the tile.
		var rect: Rect2 = Rect2(
			center - half + Vector2(inset, inset),
			_tile_size - Vector2(inset, inset) * 2.0
		)
		draw_rect(rect, outline_color, false, stroke)


func _draw_tails() -> void:
	for d in tail_data:
		var bottom: Vector2 = d.get("panel_bottom_center", Vector2.ZERO)
		var tip: Vector2    = d.get("tile_center",          Vector2.ZERO)
		var bg: Color       = d.get("bg_color",             Color(0.14, 0.16, 0.21, 0.90))
		var pscale: float   = d.get("panel_scale",          1.0)

		var dist: float = bottom.distance_to(tip)
		if dist < tail_min_dist:
			continue

		# Direction from panel bottom toward tile center.
		var dir: Vector2  = (tip - bottom) / dist   # normalised
		var perp: Vector2 = Vector2(-dir.y, dir.x)  # perpendicular

		# Tail base width in world units = screen px * panel_scale (= 1/zoom).
		var hw: float = tail_half_width_px * pscale

		var pts: PackedVector2Array = PackedVector2Array([
			bottom - perp * hw,   # base left
			bottom + perp * hw,   # base right
			tip                   # tip at tile center
		])
		draw_colored_polygon(pts, bg)
