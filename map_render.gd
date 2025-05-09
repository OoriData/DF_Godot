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

const JOURNEY_LINE_THICKNESS: int = 3 # Pixel thickness of the journey line. Let's try 3px.
const FLOAT_MATCH_TOLERANCE: float = 0.00001 # Tolerance for matching float coordinates

const PREDEFINED_CONVOY_COLORS: Array[Color] = [
	Color.RED,          # Red
	Color.BLUE,         # Blue
	Color.GREEN,        # Green
	Color.YELLOW,       # Yellow
	Color.CYAN,         # Cyan
	Color.MAGENTA,      # Magenta
	Color("orange"),    # Orange
	Color("purple"),    # Purple
	Color("lime"),      # Lime Green
	Color("pink")       # Pink
]

# Arrow dimensions (in pixels)
const CONVOY_ARROW_FORWARD_LENGTH: float = 10.0 # From center to tip - Increased
const CONVOY_ARROW_BACKWARD_LENGTH: float = 4.0 # From center to middle of base - Increased
const CONVOY_ARROW_HALF_WIDTH: float = 6.0    # From center-line to a base corner - Increased
const CONVOY_ARROW_OUTLINE_THICKNESS: float = 2.0 # Thickness of the black outline
const MAX_THROB_SIZE_ADDITION: float = 2.0 # How many extra pixels the arrow dimensions can grow
const JOURNEY_LINE_OUTLINE_EXTRA_THICKNESS_EACH_SIDE: int = 1 # How many extra pixels for the white outline on each side of the journey line
const MAX_THROB_DARKEN_AMOUNT: float = 0.4 # How much the arrow darkens at its peak (0.0 to 1.0)
const TRAILING_JOURNEY_DARKEN_FACTOR: float = 0.5 # How much to darken the trailing line (0.0 to 1.0)

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

# Helper function to draw a filled triangle on an Image
func _draw_filled_triangle_on_image(image: Image, v0: Vector2, v1: Vector2, v2: Vector2, color: Color) -> void:
	var polygon: PackedVector2Array = [v0, v1, v2]

	# Calculate bounding box of the triangle
	var min_x: int = floor(min(v0.x, min(v1.x, v2.x)))
	var max_x: int = ceil(max(v0.x, max(v1.x, v2.x)))
	var min_y: int = floor(min(v0.y, min(v1.y, v2.y)))
	var max_y: int = ceil(max(v0.y, max(v1.y, v2.y)))

	# Clamp bounding box to image dimensions
	min_x = max(0, min_x)
	max_x = min(image.get_width() - 1, max_x)
	min_y = max(0, min_y)
	max_y = min(image.get_height() - 1, max_y)

	for y_coord in range(min_y, max_y + 1):
		for x_coord in range(min_x, max_x + 1):
			var current_pixel := Vector2(float(x_coord), float(y_coord))
			# Check center of the pixel for more accuracy with Geometry2D
			if Geometry2D.is_point_in_polygon(current_pixel + Vector2(0.5, 0.5), polygon):
				image.set_pixel(x_coord, y_coord, color)


# Helper function to draw a line on an Image with specified thickness
func _draw_line_on_image(image: Image, start: Vector2i, end: Vector2i, color: Color, thickness: int) -> void:
	if thickness <= 0:
		return

	# Basic Bresenham's line algorithm
	var x1: int = start.x
	var y1: int = start.y
	var x2: int = end.x
	var y2: int = end.y

	var dx: int = abs(x2 - x1)
	var dy: int = -abs(y2 - y1) # Use negative dy for standard algorithm form

	var sx: int = 1 if x1 < x2 else -1
	var sy: int = 1 if y1 < y2 else -1

	var err: int = dx + dy # error value e_xy
	var e2: int

	var current_x: int = x1
	var current_y: int = y1

	while true:
		# Draw a small filled rectangle (square) for thickness
		var brush_offset: int = thickness / 2
		var rect_x: int = current_x - brush_offset
		var rect_y: int = current_y - brush_offset
		
		# Create a Rect2i for the brush
		var brush_rect := Rect2i(rect_x, rect_y, thickness, thickness)
		
		# Fill the brush rectangle (Image.fill_rect handles bounds checking)
		image.fill_rect(brush_rect, color)

		# Check for end of line
		if current_x == x2 and current_y == y2:
			break
		e2 = 2 * err
		if e2 >= dy: # e_xy+e_x > 0
			err += dy; current_x += sx
		if e2 <= dx: # e_xy+e_y < 0
			err += dx; current_y += sy

# --- Main Rendering Function ---
func render_map(
		tiles: Array,
		highlights: Array = [],
		lowlights: Array = [],
		highlight_color: Color = DEFAULT_HIGHLIGHT_OUTLINE_COLOR,
		lowlight_color: Color = DEFAULT_LOWLIGHT_INLINE_COLOR,
		p_viewport_size: Vector2 = Vector2.ZERO,
		p_convoys_data: Array = [], # New parameter for convoy data
		p_throb_phase: float = 0.0 # For animating convoy icons
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
		for convoy_idx in range(p_convoys_data.size()):
			var convoy_data_variant = p_convoys_data[convoy_idx]
			if not convoy_data_variant is Dictionary:
				printerr("MapRender: Convoy data item is not a dictionary: ", convoy_data_variant)
				continue

			var convoy_item: Dictionary = convoy_data_variant
			# Get a unique color for this convoy by cycling through the predefined list
			var unique_convoy_color: Color = PREDEFINED_CONVOY_COLORS[convoy_idx % PREDEFINED_CONVOY_COLORS.size()]
			var convoy_x_variant = convoy_item.get("x")
			var convoy_y_variant = convoy_item.get("y")

			if typeof(convoy_x_variant) in [TYPE_INT, TYPE_FLOAT] and \
			   typeof(convoy_y_variant) in [TYPE_INT, TYPE_FLOAT]:
				
				var convoy_map_x: float = float(convoy_x_variant)
				var convoy_map_y: float = float(convoy_y_variant)

				# Calculate pixel center of the tile where convoy is located
				var center_pixel_x: float = (convoy_map_x + 0.5) * actual_tile_width_f
				var center_pixel_y: float = (convoy_map_y + 0.5) * actual_tile_height_f

				var current_convoy_pixel_pos := Vector2(center_pixel_x, center_pixel_y)

				var journey_data: Dictionary = convoy_item.get("journey")
				if journey_data is Dictionary:
					var route_x_coords: Array = journey_data.get("route_x")
					var route_y_coords: Array = journey_data.get("route_y")

					if route_x_coords is Array and route_y_coords is Array and route_x_coords.size() == route_y_coords.size():
						var start_drawing_from_route_index: int = -1
						var direction_norm := Vector2.UP # Default direction (pointing up on map)

						# Find the index in the route that matches the convoy's current position
						for i in range(route_x_coords.size()):
							var route_point_x: float = float(route_x_coords[i])
							var route_point_y: float = float(route_y_coords[i])
							if abs(route_point_x - convoy_map_x) < FLOAT_MATCH_TOLERANCE and \
								abs(route_point_y - convoy_map_y) < FLOAT_MATCH_TOLERANCE:
								start_drawing_from_route_index = i
								break
						
						# Determine direction for the arrow
						if start_drawing_from_route_index != -1 and start_drawing_from_route_index + 1 < route_x_coords.size():
							var next_route_map_x: float = float(route_x_coords[start_drawing_from_route_index + 1])
							var next_route_map_y: float = float(route_y_coords[start_drawing_from_route_index + 1])
							var next_route_pixel_x: float = (next_route_map_x + 0.5) * actual_tile_width_f
							var next_route_pixel_y: float = (next_route_map_y + 0.5) * actual_tile_height_f
							var target_pixel_for_direction := Vector2(next_route_pixel_x, next_route_pixel_y)
							
							var direction_vec = target_pixel_for_direction - current_convoy_pixel_pos
							if direction_vec.length_squared() > FLOAT_MATCH_TOLERANCE * FLOAT_MATCH_TOLERANCE : # Avoid normalizing zero vector
								direction_norm = direction_vec.normalized()
						# else, keep default direction_norm (UP) if no next point or not on route

						# --- Draw Full Journey Line (Trailing part transparent, Leading part opaque) ---
						if route_x_coords.size() >= 2: # Need at least two points to draw any line segment
							var leading_line_color: Color = unique_convoy_color
							var trailing_line_color: Color = unique_convoy_color.darkened(TRAILING_JOURNEY_DARKEN_FACTOR)							
							var outline_total_thickness: int = JOURNEY_LINE_THICKNESS + (2 * JOURNEY_LINE_OUTLINE_EXTRA_THICKNESS_EACH_SIDE)

							# --- Pass 1: Draw the continuous white outline for the entire path ---
							var prev_map_x_for_line: float = float(route_x_coords[0])
							var prev_map_y_for_line: float = float(route_y_coords[0])
							var prev_pixel_pos_for_line := Vector2i(
								round((prev_map_x_for_line + 0.5) * actual_tile_width_f),
								round((prev_map_y_for_line + 0.5) * actual_tile_height_f)
							)
							for i in range(1, route_x_coords.size()):
								var next_map_x_for_line: float = float(route_x_coords[i])
								var next_map_y_for_line: float = float(route_y_coords[i])
								var next_pixel_pos_for_line := Vector2i(
									round((next_map_x_for_line + 0.5) * actual_tile_width_f),
									round((next_map_y_for_line + 0.5) * actual_tile_height_f)
								)
								_draw_line_on_image(map_image, prev_pixel_pos_for_line, next_pixel_pos_for_line, Color.WHITE, outline_total_thickness)
								prev_pixel_pos_for_line = next_pixel_pos_for_line

							# --- Pass 2: Draw the colored journey line (with trailing/leading variations) on top ---
							prev_map_x_for_line = float(route_x_coords[0]) # Reset for the second pass
							prev_map_y_for_line = float(route_y_coords[0]) # Reset for the second pass
							prev_pixel_pos_for_line = Vector2i(
								round((prev_map_x_for_line + 0.5) * actual_tile_width_f),
								round((prev_map_y_for_line + 0.5) * actual_tile_height_f)
							)

							# Loop through all subsequent points to draw all segments of the journey
							for i in range(1, route_x_coords.size()):
								var next_map_x_for_line: float = float(route_x_coords[i])
								var next_map_y_for_line: float = float(route_y_coords[i])
								var next_pixel_pos_for_line := Vector2i(
									round((next_map_x_for_line + 0.5) * actual_tile_width_f),
									round((next_map_y_for_line + 0.5) * actual_tile_height_f)
								)

								var current_segment_color: Color
								# A segment is "trailing" if its end point (index i) is at or before the convoy's current route index.
								# If convoy is not found on route (start_drawing_from_route_index == -1), all segments are considered leading/opaque.
								if start_drawing_from_route_index != -1 and i <= start_drawing_from_route_index:
									current_segment_color = trailing_line_color
								else:
									current_segment_color = leading_line_color
								
								# Draw the main colored line segment
								_draw_line_on_image(map_image, prev_pixel_pos_for_line, next_pixel_pos_for_line, current_segment_color, JOURNEY_LINE_THICKNESS)

								prev_pixel_pos_for_line = next_pixel_pos_for_line
						#else: # Optional: print if not enough points for a line
							#if route_x_coords.size() < 2:
								#print("MapRender: Journey route for convoy ", convoy_item.get("convoy_id"), " has less than 2 points, cannot draw line.")
					#else: # Optional: print if route_x_coords or route_y_coords are invalid
						#printerr("MapRender: Convoy journey route_x/route_y are invalid or mismatched for convoy: ", convoy_item.get("convoy_id"))

						# --- Draw Convoy Arrow on TOP ---
						# (Arrow drawing logic remains the same, it will be drawn after all lines)
						
						# Calculate throbbing factor (0.0 to 1.0)
						var throb_factor: float = (sin(p_throb_phase * 2.0 * PI) + 1.0) / 2.0

						# Calculate current throbbing dimensions
						var current_size_addition: float = throb_factor * MAX_THROB_SIZE_ADDITION
						var current_forward_len: float = CONVOY_ARROW_FORWARD_LENGTH + current_size_addition
						var current_backward_len: float = CONVOY_ARROW_BACKWARD_LENGTH + current_size_addition
						var current_half_width: float = CONVOY_ARROW_HALF_WIDTH + current_size_addition
						# Optionally, scale outline thickness too, or keep it fixed. Let's scale it slightly.
						var current_outline_thickness: float = CONVOY_ARROW_OUTLINE_THICKNESS + (throb_factor * (MAX_THROB_SIZE_ADDITION / 2.0)) # Scale outline less aggressively

						var perp_norm: Vector2 = direction_norm.rotated(PI / 2.0)
						var v_tip: Vector2 = current_convoy_pixel_pos + direction_norm * current_forward_len
						var v_rear_center: Vector2 = current_convoy_pixel_pos - direction_norm * current_backward_len
						var v_base_left: Vector2 = v_rear_center + perp_norm * current_half_width
						var v_base_right: Vector2 = v_rear_center - perp_norm * current_half_width

						# Calculate vertices for the outline (slightly larger)
						var outline_forward_len: float = current_forward_len + current_outline_thickness
						var outline_backward_len: float = current_backward_len + current_outline_thickness
						var outline_half_width: float = current_half_width + current_outline_thickness

						var ov_tip: Vector2 = current_convoy_pixel_pos + direction_norm * outline_forward_len
						var ov_rear_center: Vector2 = current_convoy_pixel_pos - direction_norm * outline_backward_len
						var ov_base_left: Vector2 = ov_rear_center + perp_norm * outline_half_width
						var ov_base_right: Vector2 = ov_rear_center - perp_norm * outline_half_width
						_draw_filled_triangle_on_image(map_image, ov_tip, ov_base_left, ov_base_right, Color.BLACK)
												
						# Calculate throbbing color for the fill
						var darken_amount: float = throb_factor * MAX_THROB_DARKEN_AMOUNT
						var throbbing_fill_color: Color = unique_convoy_color.darkened(darken_amount)

						# Draw the main filled arrow
						_draw_filled_triangle_on_image(map_image, v_tip, v_base_left, v_base_right, throbbing_fill_color)
			else: # This 'else' corresponds to 'if typeof(convoy_x_variant) ...'
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
