extends Node2D
## map_grid_overlay.gd
##
## Draws a coordinate grid across the terrain tilemap's used area: one uniform thin
## dark line at every tile boundary (no heavier "major" lines).
##
## Lives in world-space as a child of the terrain TileMapLayer, so its local
## coordinates match TileMapLayer.map_to_local(). UIManager pushes fresh parameters
## each frame via update_grid(); line widths are divided by zoom so they stay a
## roughly constant thickness on screen.
##
## Level-of-detail: when tiles shrink on screen (zoom-out), drawing every single tile
## line crowds into a moiré wash. Instead the grid snaps to power-of-two steps (every
## 1 / 2 / 4 / 8 … tiles) and crossfades the in-between lines, so density stays readable
## with no "pop" as you zoom.

var _enabled: bool      = false
var _origin: Vector2    = Vector2.ZERO          # world-space top-left corner of the grid
var _tile_size: Vector2 = Vector2(32.0, 32.0)
var _cols: int          = 0                     # number of tile columns
var _rows: int          = 0                     # number of tile rows
var _zoom: float        = 1.0

# --- Appearance ---
## Uniform dark grid: one thin line per tile boundary, no heavier "major" lines.
var line_color: Color  = Color(0.0, 0.0, 0.0, 0.30)
var line_width_px: float = 1.0
## Minimum on-screen spacing (world px × zoom) the grid tries to keep between drawn
## lines. Once a tile gets smaller than this on screen, the grid coarsens a level.
var min_screen_spacing: float = 18.0


func update_grid(enabled: bool, origin: Vector2, cols: int, rows: int, tile_size: Vector2, zoom: float) -> void:
	# Skip the redraw entirely when nothing visible changed to avoid per-frame churn.
	if enabled == _enabled and origin == _origin and cols == _cols and rows == _rows \
			and tile_size == _tile_size and is_equal_approx(zoom, _zoom):
		return
	_enabled   = enabled
	_origin    = origin
	_cols      = cols
	_rows      = rows
	_tile_size = tile_size
	_zoom      = zoom
	visible    = enabled
	queue_redraw()


func _draw() -> void:
	if not _enabled or _cols <= 0 or _rows <= 0:
		return
	var inv_zoom: float = 1.0 / max(0.001, _zoom)
	var line_w: float   = line_width_px * inv_zoom

	# --- Level-of-detail step + crossfade ---
	# On-screen spacing of one tile; coarsen the grid when it drops below the target.
	var tile_min: float       = minf(_tile_size.x, _tile_size.y)
	var screen_spacing: float = tile_min * max(0.0001, _zoom)
	# How many power-of-two doublings we need to reach the target spacing (>= 0).
	var ratio: float = max(1.0, min_screen_spacing / max(0.0001, screen_spacing))
	var level: float = maxf(0.0, log(ratio) / log(2.0))
	var step_lo: int = int(pow(2.0, floor(level)))   # finest lines drawn (every step_lo tiles)
	var step_hi: int = step_lo * 2                    # lines that stay at full opacity
	var fade: float  = level - floor(level)           # 0..1 toward the next coarser level

	var full_col: Color = line_color
	var fade_col: Color = Color(line_color.r, line_color.g, line_color.b, line_color.a * (1.0 - fade))

	var width: float  = _cols * _tile_size.x
	var height: float = _rows * _tile_size.y
	var top: float    = _origin.y
	var bottom: float = _origin.y + height
	var left: float   = _origin.x
	var right: float  = _origin.x + width

	# Anti-aliased so lines blend across pixels instead of snapping on/off as the map
	# is scaled. Lines drawn every step_lo tiles; the "in-between" ones fade out as the
	# grid approaches the next coarser level (multiples of step_hi stay full opacity).
	# Vertical lines.
	var c: int = 0
	while c <= _cols:
		var col_v: Color = full_col if (c % step_hi) == 0 else fade_col
		if col_v.a > 0.003:
			var x: float = _origin.x + c * _tile_size.x
			draw_line(Vector2(x, top), Vector2(x, bottom), col_v, line_w, true)
		c += step_lo

	# Horizontal lines.
	var r: int = 0
	while r <= _rows:
		var col_h: Color = full_col if (r % step_hi) == 0 else fade_col
		if col_h.a > 0.003:
			var y: float = _origin.y + r * _tile_size.y
			draw_line(Vector2(left, y), Vector2(right, y), col_h, line_w, true)
		r += step_lo
