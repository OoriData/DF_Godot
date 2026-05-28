extends Node2D
## settlement_overlay_draw.gd
##
## Draws two world-space overlays for every visible settlement label:
##   1. Callout tail  — filled triangle from label panel bottom-center to tile center.
##   2. Tile icon     — settlement-type emoji + backing circle drawn on the tile itself.
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

## One entry per visible settlement.
## {
##   "tile_center": Vector2,
##   "emoji":       String,   # from SETTLEMENT_EMOJIS, may be empty
## }
var icon_data: Array = []

# --- Appearance tweakables (set from UIManager after creation) ---

## Half-width of the tail base in screen-pixels (counter-scaled per tail entry).
var tail_half_width_px: float = 5.5

## Minimum panel-to-tile distance before a tail is drawn (world units at zoom 1).
var tail_min_dist: float = 6.0

## Radius of the backing circle drawn behind each tile icon, in screen-pixels.
var icon_backing_radius_px: float = 11.0

## Font size of tile icons in screen-pixels.
var icon_font_size_px: float = 16.0

## Backing circle color.
var icon_backing_color: Color = Color(0.10, 0.12, 0.16, 0.82)

## Icon tint (alpha controls legibility over varied terrain).
var icon_tint: Color = Color(1.0, 1.0, 1.0, 0.92)

# Set by UIManager after initialising LabelSettings.
var icon_font: Font = null

# Current zoom, used to counter-scale screen-constant elements.
var _zoom: float = 1.0


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

func update_frame(
		p_tail_data: Array,
		p_icon_data: Array,
		p_zoom: float,
		p_font: Font
) -> void:
	tail_data = p_tail_data
	icon_data = p_icon_data
	_zoom = p_zoom
	icon_font = p_font
	queue_redraw()


func clear_frame() -> void:
	tail_data = []
	icon_data = []
	queue_redraw()


# -------------------------------------------------------------------
# Draw
# -------------------------------------------------------------------

func _draw() -> void:
	_draw_tile_icons()
	_draw_tails()


func _draw_tile_icons() -> void:
	if icon_font == null:
		return
	var inv_zoom: float = 1.0 / max(0.001, _zoom)
	var backing_r: float = icon_backing_radius_px * inv_zoom
	var font_sz: int = int(icon_font_size_px * inv_zoom)
	font_sz = clampi(font_sz, 6, 64)

	for d in icon_data:
		var center: Vector2 = d.get("tile_center", Vector2.ZERO)
		var emoji: String = d.get("emoji", "")
		if emoji.is_empty():
			continue

		# Backing circle gives legibility against any terrain colour.
		draw_circle(center, backing_r, icon_backing_color)

		# Emoji centered on the tile. draw_string baseline is the font ascent,
		# so offset upward by ~0.6 * font_sz to visually centre it.
		var text_pos: Vector2 = center + Vector2(0.0, font_sz * 0.35)
		draw_string(
			icon_font,
			text_pos,
			emoji,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_sz,
			icon_tint
		)


func _draw_tails() -> void:
	for d in tail_data:
		var bottom: Vector2 = d.get("panel_bottom_center", Vector2.ZERO)
		var tip: Vector2   = d.get("tile_center",          Vector2.ZERO)
		var bg: Color      = d.get("bg_color",             Color(0.14, 0.16, 0.21, 0.90))
		var pscale: float  = d.get("panel_scale",          1.0)

		var dist: float = bottom.distance_to(tip)
		if dist < tail_min_dist:
			continue

		# Direction from panel bottom toward tile center.
		var dir: Vector2  = (tip - bottom) / dist   # normalised
		var perp: Vector2 = Vector2(-dir.y, dir.x)  # perpendicular

		# Tail base width in world units = screen px * panel_scale (= 1/zoom).
		# This keeps the tail visually the same width as the panel border regardless of zoom.
		var hw: float = tail_half_width_px * pscale

		var pts: PackedVector2Array = PackedVector2Array([
			bottom - perp * hw,   # base left
			bottom + perp * hw,   # base right
			tip                   # tip at tile center
		])
		draw_colored_polygon(pts, bg)
