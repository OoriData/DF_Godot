# map_render.gd
# Translated from map_render.py for Godot 4.4
# Corrected structure to avoid nested function/"lambda" errors.
extends Node

# --- Constants ---
const BASE_TILE_SIZE_FOR_PROPORTIONS: float = 24.0 # Original tile size, used for scaling calculations
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
	0: Color('#00000000'),   # Null (transparent)
	1: Color('#00000000'),   # Desolate plains
	2: Color('#00000000'),   # Desolate forest
	3: Color('#00000000'),   # Desolate desert
	4: Color('#00000000'),   # Desolate mountains
	5: Color('#00000000'),   # Desolate Swamp
	9: Color('#00000000'),   # Device Detonation Zone
	10: Color('#D5A6BD'),    # Chicago
	11: Color('#D5A6BD'),    # Indianapolis
	13: Color('#D5A6BD'),    # Detroit
	14: Color('#D5A6BD'),    # Cleveland
	15: Color('#D5A6BD'),    # Buffalo
	16: Color('#D5A6BD'),    # Louisville
	17: Color('#D5A6BD'),    # Mackinaw City
	19: Color('#D5A6BD'),    # The Heartland
	20: Color('#B4A7D6'),    # Kansas City
	21: Color('#B4A7D6'),    # St. Louis
	22: Color('#B4A7D6'),    # Des Moines
	29: Color('#B4A7D6'),    # The Breadbasket
	30: Color('#B6D7A8'),    # Minneapolis
	31: Color('#B6D7A8'),    # Fargo
	32: Color('#B6D7A8'),    # Milwaukee
	33: Color('#B6D7A8'),    # Madison
	34: Color('#B6D7A8'),    # Sault Ste. Marie
	35: Color('#B6D7A8'),    # Green Bay
	39: Color('#B6D7A8'),    # Northern Lights
	40: Color('#FFE599'),    # New York
	41: Color('#FFE599'),    # Boston
	42: Color('#FFE599'),    # Philadelphia
	43: Color('#FFE599'),    # Portland, NNE
	49: Color('#FFE599'),    # New New England
	50: Color('#F6B26B'),    # Nashville
	51: Color('#F6B26B'),    # Memphis
	52: Color('#F6B26B'),    # Knoxville
	59: Color('#F6B26B'),    # Greater Tennessee
	60: Color('#E06666'),    # Charlotte
	61: Color('#E06666'),    # Norfolk
	62: Color('#E06666'),    # Richmond
	63: Color('#E06666'),    # Minot AFB
	64: Color('#E06666'),    # Vandenberg AFB
	69: Color('#E06666'),    # Republic of the South Atlantic
	70: Color('#469c22'),    # Jacksonville
	71: Color('#469c22'),    # Tallahassee
	72: Color('#469c22'),    # Orlando
	73: Color('#469c22'),    # Miami
	74: Color('#469c22'),    # New Orleans
	75: Color('#469c22'),    # Pensacola
	76: Color('#469c22'),    # Baton Rouge
	79: Color('#469c22'),    # Gulf Cities
	80: Color('#0d0600'),    # Austin
	81: Color('#0d0600'),    # San Antonio
	82: Color('#0d0600'),    # Dallas
	83: Color('#0d0600'),    # Houston
	85: Color('#0d0600'),    # Oklahoma City
	86: Color('#0d0600'),    # Whichita
	87: Color('#0d0600'),    # Corpus Cristy
	89: Color('#0d0600'),    # Republic of Texas
	90: Color('#0A5394'),    # Denver
	91: Color('#0A5394'),    # Cheyenne
	92: Color('#0A5394'),    # Colorado Springs
	93: Color('#0A5394'),    # Ft. Colins
	99: Color('#0A5394'),    # Front Range Collective
	100: Color('#cf2a08'),   # Los Angeles
	101: Color('#cf2a08'),   # San Diego
	102: Color('#cf2a08'),   # Phoenix
	103: Color('#cf2a08'),   # Tucson
	104: Color('#cf2a08'),   # Flagstaff
	109: Color('#cf2a08'),   # States of Solara
	110: Color('#674EA7'),   # San Francisco
	111: Color('#674EA7'),   # Fresno
	112: Color('#674EA7'),   # Sacramento
	113: Color('#674EA7'),   # Reno
	119: Color('#674EA7'),   # The Golden Bay
	120: Color('#BF9000'),   # Seattle
	121: Color('#BF9000'),   # Portland
	122: Color('#BF9000'),   # Spokane
	123: Color('#BF9000'),   # Spokane
	129: Color('#BF9000'),   # Cascadia
	130: Color('#6e1901'),   # Be'eldííl Dah Sinil
	131: Color('#6e1901'),   # Ysleta
	139: Color('#6e1901'),   # Desert Twins
	140: Color('#391240'),   # Las Vegas
	141: Color('#391240'),   # Boise Mountain Commune
	142: Color('#391240'),   # Salt Lake City
	143: Color('#FFF3CC'),   # Little Rock
	144: Color('#FFF3CC'),   # Birmingham
	145: Color('#FFF3CC'),   # Atlanta
	146: Color('#FFF3CC'),   # Charleston
	147: Color('#FFF3CC'),   # Billings
	148: Color('#FFF3CC'),   # Lincoln
	149: Color('#FFF3CC'),   # Jackson Hole
	150: Color('#FFF3CC'),   # Missoula
	151: Color('#FFF3CC'),   # Savannah
	170: Color('#FF0000'),   # Badlanders
	171: Color('#FF0000'),   # Badland Outposts
	172: Color('#FF0000')    # Appalacian Wastelanders
}


const POLITICAL_BORDER_VISIBLE_THICKNESS: int = 1 # How thick the political color border around terrain should be (in base pixels)
const POLITICAL_INLINE_WIDTH: int = 3 # This constant is still not used by the simplified drawing logic

const DEFAULT_HIGHLIGHT_OUTLINE_COLOR: Color = Color("#FFFF00")
const HIGHLIGHT_OUTLINE_OFFSET: int = -1
const HIGHLIGHT_OUTLINE_WIDTH: int = 9

const DEFAULT_LOWLIGHT_INLINE_COLOR: Color = Color("#00FFFF")
const LOWLIGHT_INLINE_OFFSET: int = 2
const LOWLIGHT_INLINE_WIDTH: int = 5

const CONVOY_DOT_COLOR: Color = Color("#FF0000") # Bright red for convoy dots
const CONVOY_DOT_SIZE: int = 5 # Pixel size of the convoy dot (e.g., 5x5 pixels)

# --- Helper Drawing Functions (Now methods of the class) ---

func _draw_tile_bg(img: Image, tile_data: Dictionary, tile_render_x: int, tile_render_y: int, tile_render_width: int, tile_render_height: int, p_scaled_total_inset: int, grid_x_for_debug: int, grid_y_for_debug: int):
	var color: Color = ERROR_COLOR # Initialized to ERROR_COLOR
	var color_source_debug: String = "Initial ERROR_COLOR" # For debugging

	#if grid_x_for_debug == 0 and grid_y_for_debug == 0: # Debug print for the first tile only
		#print("DEBUG map_render.gd: Processing tile (0,0) data: ", tile_data)

	# Check settlement first - Added 'is Array' check previously
	if tile_data.has("settlements") and tile_data["settlements"] is Array and not tile_data["settlements"].is_empty():
		var settlement_data = tile_data["settlements"][0]
		var sett_type = settlement_data.get("sett_type", "MISSING_SETT_TYPE_KEY")
		# Use .get() again for safety, defaulting to ERROR_COLOR if type not found
		color = SETTLEMENT_COLORS.get(sett_type, ERROR_COLOR)
		if color != ERROR_COLOR: # Check if color was actually found
			color_source_debug = "Settlement: " + sett_type
		else:
			color_source_debug = "Settlement (type '" + sett_type + "' not in SETTLEMENT_COLORS)"
			#if grid_x_for_debug == 0 and grid_y_for_debug == 0: print("DEBUG map_render.gd: Tile (0,0) settlement type '", sett_type, "' not found in SETTLEMENT_COLORS.")
	elif tile_data.has("terrain_difficulty"):
		# Terrain path
		var difficulty_variant = tile_data["terrain_difficulty"] # Get the value (likely float)
		if typeof(difficulty_variant) == TYPE_FLOAT or typeof(difficulty_variant) == TYPE_INT:
			var difficulty_int : int = int(floor(difficulty_variant)) # Cast float/int to integer
			# Use .get() again for safety, defaulting to ERROR_COLOR if key not found
			color = TILE_COLORS.get(difficulty_int, ERROR_COLOR)
			if color != ERROR_COLOR:
				color_source_debug = "Terrain: " + str(difficulty_int)
			else:
				color_source_debug = "Terrain (difficulty '" + str(difficulty_int) + "' not in TILE_COLORS)"
				#if grid_x_for_debug == 0 and grid_y_for_debug == 0: print("DEBUG map_render.gd: Tile (0,0) terrain difficulty '", difficulty_int, "' not found in TILE_COLORS.")
		else: # Non-numeric terrain difficulty
			color_source_debug = "Terrain (value is not INT or FLOAT, type: " + str(typeof(difficulty_variant)) + ")"
			#if grid_x_for_debug == 0 and grid_y_for_debug == 0: print("DEBUG map_render.gd: Tile (0,0) terrain_difficulty is not INT or FLOAT. Type: ", typeof(difficulty_variant), ", Value: ", difficulty_variant)
	else: # Neither settlement nor terrain difficulty found
		color_source_debug = "No 'settlements' or 'terrain_difficulty' key found in tile."
		#if grid_x_for_debug == 0 and grid_y_for_debug == 0: print("DEBUG map_render.gd: Tile (0,0) has no 'settlements' or 'terrain_difficulty' key.")

	#if grid_x_for_debug == 0 and grid_y_for_debug == 0: # Debug print for the first tile only
		#print("DEBUG map_render.gd: Tile (0,0) final color source: ", color_source_debug, ", Resulting Color: ", color)

	# --- Drawing Logic ---
	var rect := Rect2i(
		tile_render_x + p_scaled_total_inset,
		tile_render_y + p_scaled_total_inset,
		tile_render_width - p_scaled_total_inset * 2,
		tile_render_height - p_scaled_total_inset * 2
	)
	if rect.size.x > 0 and rect.size.y > 0:
		img.fill_rect(rect, color) # Uses the 'color' variable determined above
	return color

func _draw_political_inline(img: Image, tile_data: Dictionary, tile_render_x: int, tile_render_y: int, tile_render_width: int, tile_render_height: int, p_scaled_inset_from_edge: int):
	var region_variant = tile_data.get("region", -999) # Can be float or int from JSON
	var region_int: int
	if typeof(region_variant) == TYPE_FLOAT or typeof(region_variant) == TYPE_INT:
		region_int = int(floor(region_variant)) # Use floor to handle potential float values correctly for keys
	else:
		# printerr("Tile (", x, ",", y, ") has non-numeric region: ", region_variant, ". Defaulting to -999.") # x,y not directly available here
		region_int = -999 # Default if region is not a number
	var political_color: Color = POLITICAL_COLORS.get(region_int, ERROR_COLOR)

	# Only draw if not fully transparent
	if political_color.a > 0.01:
		# Simplified: Draw a rectangle with offset. Ignores exact width.
		var outer_rect := Rect2i(
			tile_render_x + p_scaled_inset_from_edge,
			tile_render_y + p_scaled_inset_from_edge,
			tile_render_width - p_scaled_inset_from_edge * 2,
			tile_render_height - p_scaled_inset_from_edge * 2
		)
		# Simple approach: Just fill the outer_rect, ignoring precise width.
		img.fill_rect(outer_rect, political_color) # Draw the border color rect

func _draw_highlight_or_lowlight(img: Image, x: int, y: int, coords_list: Array, color: Color, current_tile_size: int, p_scaled_offset: int, _width: int):
	var tile_coord := Vector2i(x, y)
	if coords_list.has(tile_coord):
		# This function still uses the old x, y, current_tile_size logic.
		# For full consistency, it should also be adapted to use pre-calculated render bounds.
		# However, since highlights/lowlights are not the primary visual, this might be acceptable for now.
		var rect := Rect2i(
			x * current_tile_size + p_scaled_offset,
			y * current_tile_size + p_scaled_offset,
			current_tile_size - p_scaled_offset * 2,
			current_tile_size - p_scaled_offset * 2
		)
		if rect.size.x > 0 and rect.size.y > 0:
			img.fill_rect(rect, color)


# --- Main Rendering Function ---
func render_map(
		tiles: Array,
		highlights: Array = [],
		lowlights: Array = [],
		highlight_color: Color = DEFAULT_HIGHLIGHT_OUTLINE_COLOR,
		lowlight_color: Color = DEFAULT_LOWLIGHT_INLINE_COLOR,
		p_viewport_size: Vector2 = Vector2.ZERO,
		p_convoys_data: Array = [] # New parameter for convoy data
	) -> ImageTexture:
	if tiles.is_empty() or not tiles[0] is Array or tiles[0].is_empty():
		printerr("Invalid or empty tiles data provided.")
		return null

	var rows: int = tiles.size()
	var cols: int = tiles[0].size()

	# Ensure this node is in the scene tree to get viewport
	var viewport_size: Vector2
	if p_viewport_size == Vector2.ZERO: # If no override is provided (or it's explicitly zero)
		# Try to get viewport size from the tree
		if not is_inside_tree():
			printerr("MapRender node is not in the scene tree and no p_viewport_size override was given. Cannot determine viewport size.")
			return null
		viewport_size = get_viewport().get_visible_rect().size
	else:
		# Use the provided viewport size override
		viewport_size = p_viewport_size

	# --- Calculate target image dimensions to fit viewport while maintaining map aspect ratio ---
	var map_aspect_ratio: float = float(cols) / float(rows)
	var viewport_aspect_ratio: float = viewport_size.x / viewport_size.y

	var image_render_width_f: float
	var image_render_height_f: float

	if viewport_aspect_ratio > map_aspect_ratio: # Viewport is wider than map, so height is the limiting factor
		image_render_height_f = viewport_size.y
		image_render_width_f = image_render_height_f * map_aspect_ratio
	else: # Viewport is taller or same aspect ratio as map, so width is the limiting factor
		image_render_width_f = viewport_size.x
		image_render_height_f = image_render_width_f / map_aspect_ratio

	var image_render_width: int = int(round(image_render_width_f))
	var image_render_height: int = int(round(image_render_height_f))

	# --- Calculate actual floating-point tile dimensions for drawing within the target image ---
	var actual_tile_width_f: float = image_render_width_f / float(cols)
	var actual_tile_height_f: float = image_render_height_f / float(rows)
	var reference_float_tile_size_for_offsets = min(actual_tile_width_f, actual_tile_height_f) # Used for scaling offsets

	# Calculate scaled offsets based on current_tile_size
	var scaled_grid_size: int = max(0, int(round(reference_float_tile_size_for_offsets * (float(GRID_SIZE) / BASE_TILE_SIZE_FOR_PROPORTIONS))))
	var scaled_political_border_thickness: int = max(0, int(round(reference_float_tile_size_for_offsets * (float(POLITICAL_BORDER_VISIBLE_THICKNESS) / BASE_TILE_SIZE_FOR_PROPORTIONS))))
	var scaled_highlight_outline_offset: int = int(round(reference_float_tile_size_for_offsets * (float(HIGHLIGHT_OUTLINE_OFFSET) / BASE_TILE_SIZE_FOR_PROPORTIONS))) # Can be negative
	var scaled_lowlight_inline_offset: int = max(0, int(round(reference_float_tile_size_for_offsets * (float(LOWLIGHT_INLINE_OFFSET) / BASE_TILE_SIZE_FOR_PROPORTIONS))))

	# Use the calculated image_render_width/height for the Image
	var width: int = image_render_width
	var height: int = image_render_height
	# Create a new image
	var map_image := Image.create(width, height, false, Image.FORMAT_RGB8)
	map_image.fill(GRID_COLOR) # Start with grid color background


	var error_color_tile_count: int = 0
	# --- Render Loop ---
	for y in rows:
		for x in cols:
			if y >= tiles.size() or x >= tiles[y].size():
				continue
			var tile: Dictionary = tiles[y][x]
			if not tile is Dictionary:
				continue

			# Calculate render boundaries for the current tile
			var tile_origin_x_f: float = x * actual_tile_width_f
			var tile_origin_y_f: float = y * actual_tile_height_f
			var next_tile_origin_x_f: float = (x + 1) * actual_tile_width_f
			var next_tile_origin_y_f: float = (y + 1) * actual_tile_height_f

			var current_tile_pixel_x: int = int(round(tile_origin_x_f))
			var current_tile_pixel_y: int = int(round(tile_origin_y_f))
			var next_tile_pixel_x: int = int(round(next_tile_origin_x_f))
			var next_tile_pixel_y: int = int(round(next_tile_origin_y_f))

			var current_tile_render_w: int = next_tile_pixel_x - current_tile_pixel_x
			var current_tile_render_h: int = next_tile_pixel_y - current_tile_pixel_y

			# 1. Draw political color layer (inset by grid_size)
			_draw_political_inline(map_image, tile, current_tile_pixel_x, current_tile_pixel_y, current_tile_render_w, current_tile_render_h, scaled_grid_size)
			
			# 2. Draw terrain/settlement layer on top (inset by grid_size + political_border_thickness)
			var total_inset_for_terrain = scaled_grid_size + scaled_political_border_thickness
			var chosen_color = _draw_tile_bg(map_image, tile, current_tile_pixel_x, current_tile_pixel_y, current_tile_render_w, current_tile_render_h, total_inset_for_terrain, x, y)
			if chosen_color == ERROR_COLOR:
				error_color_tile_count += 1
			# TODO: _draw_highlight_or_lowlight also needs to be adapted to use the new rendering bounds if full consistency is desired.
			# For now, it will use an approximated integer tile size for highlights.
			var approx_int_tile_size_for_highlight = int(round(reference_float_tile_size_for_offsets))
			_draw_highlight_or_lowlight(map_image, x, y, lowlights, lowlight_color, approx_int_tile_size_for_highlight, scaled_lowlight_inline_offset, LOWLIGHT_INLINE_WIDTH)
			_draw_highlight_or_lowlight(map_image, x, y, highlights, highlight_color, approx_int_tile_size_for_highlight, scaled_highlight_outline_offset, HIGHLIGHT_OUTLINE_WIDTH)

	# --- Create and return the texture ---
	# --- Draw Convoys ---
	if not p_convoys_data.is_empty():
		print("MapRender: Drawing %s convoys." % p_convoys_data.size())
		for convoy_data_variant in p_convoys_data:
			if not convoy_data_variant is Dictionary:
				printerr("MapRender: Convoy data item is not a dictionary: ", convoy_data_variant)
				continue

			var convoy_item: Dictionary = convoy_data_variant
			var convoy_x_variant = convoy_item.get("x")
			var convoy_y_variant = convoy_item.get("y")

			if typeof(convoy_x_variant) in [TYPE_INT, TYPE_FLOAT] and \
			   typeof(convoy_y_variant) in [TYPE_INT, TYPE_FLOAT]:
				
				var convoy_map_x: float = float(convoy_x_variant)
				var convoy_map_y: float = float(convoy_y_variant)

				# Calculate pixel center of the tile where convoy is located
				var center_pixel_x: float = (convoy_map_x + 0.5) * actual_tile_width_f
				var center_pixel_y: float = (convoy_map_y + 0.5) * actual_tile_height_f

				# Calculate top-left for the dot rect
				var dot_rect_x: int = int(round(center_pixel_x - CONVOY_DOT_SIZE / 2.0))
				var dot_rect_y: int = int(round(center_pixel_y - CONVOY_DOT_SIZE / 2.0))

				var dot_rect := Rect2i(dot_rect_x, dot_rect_y, CONVOY_DOT_SIZE, CONVOY_DOT_SIZE)
				map_image.fill_rect(dot_rect, CONVOY_DOT_COLOR)
			else:
				printerr("MapRender: Convoy item has invalid or missing x/y coordinates: ", convoy_item)


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
