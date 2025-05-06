# map_render.gd
# Translated from map_render.py for Godot 4.4
# Corrected structure to avoid nested function/"lambda" errors.
extends Node

# --- Constants ---
const TILE_SIZE: int = 24         # Pixels
const GRID_SIZE: int = 1          # Pixels to reduce each side (used for drawing inside grid lines)
# FONT_SIZE, FONT_OUTLINE_SIZE - Text rendering recommended via Label nodes instead.
# @export var font: Font # Export if attempting direct text rendering later.

const GRID_COLOR: Color = Color("#202020")   # Background grid color
const WATER_COLOR: Color = Color("#142C55")
const ERROR_COLOR: Color = Color("#FF00FF")  # Error/default color

const TILE_COLORS: Dictionary = {
	1: Color("#303030"),    # Highway
	2: Color("#606060"),    # Road
	3: Color("#CB8664"),    # Trail
	4: Color("#F6D0B0"),    # Desert
	5: Color("#3F5D4B"),    # Plains
	6: Color("#2C412E"),    # Forest
	7: Color("#2A4B46"),    # Swamp
	8: Color("#273833"),    # Mountains
	9: Color("#0F2227"),    # Near Impassable
	0: WATER_COLOR,         # Impassable/Ocean
	-1: Color("#9900FF"),   # Marked
}

const SETTLEMENT_COLORS: Dictionary = {
	"dome": Color("#80A9B6"),
	"city": Color("#ADADAD"),
	"town": Color("#A1662F"),
	"city-state": Color("#581B63"),
	"military_base": Color("#800000"),
	"village": Color("#613D3D"),
	"tutorial": WATER_COLOR
}

# Ensure ALL political colors from Python are added here correctly
const POLITICAL_COLORS: Dictionary = {
	0: Color("#00000000"),   # Null (transparent)
	1: Color("#00000000"),   # Desolate plains
	2: Color("#00000000"),   # Desolate forest
	# ... (Add ALL political colors from Python code here, using Color("#RRGGBB")) ...
	# Example:
	10: Color("#D5A6BD"),    # Chicago
	19: Color("#D5A6BD"),    # The Heartland
	# Ensure all entries from the Python POLOTICAL_COLORS dictionary are added
	172: Color("#FF0000")    # Appalacian Wastelanders
}

const POLITICAL_INLINE_OFFSET: int = 1
const POLITICAL_INLINE_WIDTH: int = 3

const DEFAULT_HIGHLIGHT_OUTLINE_COLOR: Color = Color("#FFFF00")
const HIGHLIGHT_OUTLINE_OFFSET: int = -1
const HIGHLIGHT_OUTLINE_WIDTH: int = 9

const DEFAULT_LOWLIGHT_INLINE_COLOR: Color = Color("#00FFFF")
const LOWLIGHT_INLINE_OFFSET: int = 2
const LOWLIGHT_INLINE_WIDTH: int = 5

# --- Helper Drawing Functions (Now methods of the class) ---

func _draw_tile_bg(img: Image, x: int, y: int, tile: Dictionary):
	var color: Color = ERROR_COLOR # Initialized to ERROR_COLOR

	# Check settlement first - Added 'is Array' check previously
	if tile.has("settlements") and tile["settlements"] is Array and not tile["settlements"].is_empty():
		var settlement_data = tile["settlements"][0]
		var sett_type = settlement_data.get("sett_type", "MISSING_SETT_TYPE_KEY")
		# Use .get() again for safety, defaulting to ERROR_COLOR if type not found
		color = SETTLEMENT_COLORS.get(sett_type, ERROR_COLOR)

	elif tile.has("terrain_difficulty"):
		# Terrain path
		var difficulty_variant = tile["terrain_difficulty"] # Get the value (likely float)
		if typeof(difficulty_variant) == TYPE_FLOAT or typeof(difficulty_variant) == TYPE_INT:
			var difficulty_int : int = int(difficulty_variant) # Cast float/int to integer
			# Use .get() again for safety, defaulting to ERROR_COLOR if key not found
			color = TILE_COLORS.get(difficulty_int, ERROR_COLOR)
		# else: Non-numeric terrain difficulty, color remains ERROR_COLOR

	# else: Neither settlement nor terrain difficulty found, color remains ERROR_COLOR

	# --- Drawing Logic ---
	var rect := Rect2i(
		x * TILE_SIZE + GRID_SIZE,
		y * TILE_SIZE + GRID_SIZE,
		TILE_SIZE - GRID_SIZE * 2,
		TILE_SIZE - GRID_SIZE * 2
	)
	if rect.size.x > 0 and rect.size.y > 0:
		img.fill_rect(rect, color) # Uses the 'color' variable determined above

func _draw_political_inline(img: Image, x: int, y: int, tile: Dictionary):
	var region = tile.get("region", -999)
	var political_color: Color = POLITICAL_COLORS.get(region, ERROR_COLOR)

	# Only draw if not fully transparent
	if political_color.a > 0.01:
		# Simplified: Draw a rectangle with offset. Ignores exact width.
		var outer_rect := Rect2i(
			x * TILE_SIZE + POLITICAL_INLINE_OFFSET,
			y * TILE_SIZE + POLITICAL_INLINE_OFFSET,
			TILE_SIZE - POLITICAL_INLINE_OFFSET * 2,
			TILE_SIZE - POLITICAL_INLINE_OFFSET * 2
		)
		# Simple approach: Just fill the outer_rect, ignoring precise width.
		img.fill_rect(outer_rect, political_color) # Draw the border color rect

func _draw_highlight_or_lowlight(img: Image, x: int, y: int, coords_list: Array, color: Color, offset: int, _width: int):
	var tile_coord := Vector2i(x, y)
	if coords_list.has(tile_coord):
		# Simplified: Draw a rectangle with offset. Ignores exact width parameter.
		var rect := Rect2i(
			x * TILE_SIZE + offset,
			y * TILE_SIZE + offset,
			TILE_SIZE - offset * 2,
			TILE_SIZE - offset * 2
		)
		# Add a check to ensure the rectangle size is positive before drawing
		if rect.size.x > 0 and rect.size.y > 0:
			img.fill_rect(rect, color)


# --- Main Rendering Function ---
func render_map(
		tiles: Array,
		highlights: Array = [],
		lowlights: Array = [],
		highlight_color: Color = DEFAULT_HIGHLIGHT_OUTLINE_COLOR,
		lowlight_color: Color = DEFAULT_LOWLIGHT_INLINE_COLOR
	) -> ImageTexture:

	if tiles.is_empty() or not tiles[0] is Array or tiles[0].is_empty():
		printerr("Invalid or empty tiles data provided.")
		return null

	var rows: int = tiles.size()
	var cols: int = tiles[0].size()
	var width: int = cols * TILE_SIZE
	var height: int = rows * TILE_SIZE

	# Create a new image
	var map_image := Image.create(width, height, false, Image.FORMAT_RGB8)
	map_image.fill(GRID_COLOR) # Start with grid color background

	# --- Render Loop ---
	for y in rows:
		for x in cols:
			# ... (Getting tile data remains the same) ...
			if y >= tiles.size() or x >= tiles[y].size():
				# ... error print ...
				continue
			var tile: Dictionary = tiles[y][x]
			if not tile is Dictionary:
				# ... error print ...
				continue

			# ONLY call _draw_tile_bg for now
			_draw_tile_bg(map_image, x, y, tile)

			# --- Temporarily comment out other drawing calls ---
			# _draw_political_inline(map_image, x, y, tile)
			# _draw_highlight_or_lowlight(map_image, x, y, lowlights, lowlight_color, LOWLIGHT_INLINE_OFFSET, LOWLIGHT_INLINE_WIDTH)
			# _draw_highlight_or_lowlight(map_image, x, y, highlights, highlight_color, HIGHLIGHT_OUTLINE_OFFSET, HIGHLIGHT_OUTLINE_WIDTH)

	# --- Create and return the texture ---
	var map_texture := ImageTexture.create_from_image(map_image)
	return map_texture


# --- Utility Function (Remains the same) ---
func truncate_2d_array(matrix: Array, top_left: Vector2i, bottom_right: Vector2i) -> Array:
	var x1: int = top_left.x
	var y1: int = top_left.y
	var x2: int = bottom_right.x
	var y2: int = bottom_right.y

	var result: Array = []

	if matrix.is_empty() or not matrix[0] is Array:
		printerr("Invalid matrix for truncation.")
		return result

	# Basic bounds check
	if y1 < 0 or y1 >= matrix.size() or y2 < y1 or y2 >= matrix.size():
		printerr("Y coordinates out of bounds for truncation.")
		return result
	if x1 < 0 or x1 >= matrix[0].size() or x2 < x1 or x2 >= matrix[0].size():
		printerr("X coordinates out of bounds for truncation.")
		return result

	for y in range(y1, y2 + 1):
		var row = matrix[y]
		if row is Array:
			result.append(row.slice(x1, x2 + 1))
		else:
			printerr("Row ", y, " is not an array during truncation.")

	return result
