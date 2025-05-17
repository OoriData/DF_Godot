# map_render.gd
# Translated from map_render.py for Godot 4.4
extends Node

# --- Constants ---
const BASE_TILE_SIZE_FOR_PROPORTIONS: float = 24.0  # Original tile size, used for scaling calculations
const GRID_SIZE: int = 1  # Pixels to reduce each side (used for drawing inside grid lines)
const DEFAULT_LABEL_COLOR: Color = Color.WHITE
const GRID_DARKEN_FACTOR: float = 0.2 # How much to darken the tile color for the grid lines (0.0 to 1.0)

const GRID_COLOR: Color = Color('#303030')   # Background grid color
const WATER_COLOR: Color = Color('#142C55')
const ERROR_COLOR: Color = Color('#FF00FF')  # Error/default color

const TILE_COLORS: Dictionary = {
	1: Color('#303030'),   # Highway
	2: Color('#606060'),   # Road
	3: Color('#CB8664'),   # Trail
	4: Color('#F6D0B0'),   # Desert
	5: Color('#3F5D4B'),   # Plains
	6: Color('#2C412E'),   # Forest
	7: Color('#2A4B46'),   # Swamp
	8: Color('#273833'),   # Mountains
	9: Color('#0F2227'),   # Near Impassable
	0: WATER_COLOR,        # Impassable/Ocean
	-1: Color('#9900FF'),  # Marked
}

const SETTLEMENT_COLORS: Dictionary = {
	'dome': Color('#80A9B6'),
	'city': Color('#ADADAD'),
	'town': Color('#A1662F'),
	'city-state': Color('#581B63'),
	'military_base': Color('#800000'),
	'village': Color('#613D3D'),
	'tutorial': WATER_COLOR
}

const POLITICAL_COLORS: Dictionary = {
	0: Color('#00000000'),  # Null (transparent)
	1: Color('#00000000'),  # Desolate plains
	2: Color('#00000000'),  # Desolate forest
	3: Color('#00000000'),  # Desolate desert
	4: Color('#00000000'),  # Desolate mountains
	5: Color('#00000000'),  # Desolate Swamp
	9: Color('#00000000'),  # Device Detonation Zone
	10: Color('#D5A6BD'),   # Chicago
	11: Color('#D5A6BD'),   # Indianapolis
	13: Color('#D5A6BD'),   # Detroit
	14: Color('#D5A6BD'),   # Cleveland
	15: Color('#D5A6BD'),   # Buffalo
	16: Color('#D5A6BD'),   # Louisville
	17: Color('#D5A6BD'),   # Mackinaw City
	19: Color('#D5A6BD'),   # The Heartland
	20: Color('#B4A7D6'),   # Kansas City
	21: Color('#B4A7D6'),   # St. Louis
	22: Color('#B4A7D6'),   # Des Moines
	29: Color('#B4A7D6'),   # The Breadbasket
	30: Color('#B6D7A8'),   # Minneapolis
	31: Color('#B6D7A8'),   # Fargo
	32: Color('#B6D7A8'),   # Milwaukee
	33: Color('#B6D7A8'),   # Madison
	34: Color('#B6D7A8'),   # Sault Ste. Marie
	35: Color('#B6D7A8'),   # Green Bay
	39: Color('#B6D7A8'),   # Northern Lights
	40: Color('#FFE599'),   # New York
	41: Color('#FFE599'),   # Boston
	42: Color('#FFE599'),   # Philadelphia
	43: Color('#FFE599'),   # Portland, NNE
	49: Color('#FFE599'),   # New New England
	50: Color('#F6B26B'),   # Nashville
	51: Color('#F6B26B'),   # Memphis
	52: Color('#F6B26B'),   # Knoxville
	59: Color('#F6B26B'),   # Greater Tennessee
	60: Color('#E06666'),   # Charlotte
	61: Color('#E06666'),   # Norfolk
	62: Color('#E06666'),   # Richmond
	63: Color('#E06666'),   # Minot AFB
	64: Color('#E06666'),   # Vandenberg AFB
	69: Color('#E06666'),   # Republic of the South Atlantic
	70: Color('#469c22'),   # Jacksonville
	71: Color('#469c22'),   # Tallahassee
	72: Color('#469c22'),   # Orlando
	73: Color('#469c22'),   # Miami
	74: Color('#469c22'),   # New Orleans
	75: Color('#469c22'),   # Pensacola
	76: Color('#469c22'),   # Baton Rouge
	79: Color('#469c22'),   # Gulf Cities
	80: Color('#0d0600'),   # Austin
	81: Color('#0d0600'),   # San Antonio
	82: Color('#0d0600'),   # Dallas
	83: Color('#0d0600'),   # Houston
	85: Color('#0d0600'),   # Oklahoma City
	86: Color('#0d0600'),   # Whichita
	87: Color('#0d0600'),   # Corpus Cristy
	89: Color('#0d0600'),   # Republic of Texas
	90: Color('#0A5394'),   # Denver
	91: Color('#0A5394'),   # Cheyenne
	92: Color('#0A5394'),   # Colorado Springs
	93: Color('#0A5394'),   # Ft. Colins
	99: Color('#0A5394'),   # Front Range Collective
	100: Color('#cf2a08'),  # Los Angeles
	101: Color('#cf2a08'),  # San Diego
	102: Color('#cf2a08'),  # Phoenix
	103: Color('#cf2a08'),  # Tucson
	104: Color('#cf2a08'),  # Flagstaff
	109: Color('#cf2a08'),  # States of Solara
	110: Color('#674EA7'),  # San Francisco
	111: Color('#674EA7'),  # Fresno
	112: Color('#674EA7'),  # Sacramento
	113: Color('#674EA7'),  # Reno
	119: Color('#674EA7'),  # The Golden Bay
	120: Color('#BF9000'),  # Seattle
	121: Color('#BF9000'),  # Portland
	122: Color('#BF9000'),  # Spokane
	123: Color('#BF9000'),  # Spokane
	129: Color('#BF9000'),  # Cascadia
	130: Color('#6e1901'),  # Be'eldííl Dah Sinil
	131: Color('#6e1901'),  # Ysleta
	139: Color('#6e1901'),  # Desert Twins
	140: Color('#391240'),  # Las Vegas
	141: Color('#391240'),  # Boise Mountain Commune
	142: Color('#391240'),  # Salt Lake City
	143: Color('#FFF3CC'),  # Little Rock
	144: Color('#FFF3CC'),  # Birmingham
	145: Color('#FFF3CC'),  # Atlanta
	146: Color('#FFF3CC'),  # Charleston
	147: Color('#FFF3CC'),  # Billings
	148: Color('#FFF3CC'),  # Lincoln
	149: Color('#FFF3CC'),  # Jackson Hole
	150: Color('#FFF3CC'),  # Missoula
	151: Color('#FFF3CC'),  # Savannah
	170: Color('#FF0000'),  # Badlanders
	171: Color('#FF0000'),  # Badland Outposts
	172: Color('#FF0000')   # Appalacian Wastelanders
}

const POLITICAL_BORDER_VISIBLE_THICKNESS: int = 1  # How thick the political color border around terrain should be (in base pixels)

const DEFAULT_HIGHLIGHT_OUTLINE_COLOR: Color = Color('#FFFF00')
const HIGHLIGHT_OUTLINE_OFFSET: int = -1
const HIGHLIGHT_OUTLINE_WIDTH: int = 9

const DEFAULT_LOWLIGHT_INLINE_COLOR: Color = Color('#00FFFF')
const LOWLIGHT_INLINE_OFFSET: int = 2
const LOWLIGHT_INLINE_WIDTH: int = 5

const JOURNEY_LINE_THICKNESS: int = 5         # Pixel thickness of the journey line
const FLOAT_MATCH_TOLERANCE: float = 0.00001  # Tolerance for matching float coordinates

const SELECTED_JOURNEY_LINE_THICKNESS: int = 9  # Thickness for selected convoy lines
const SELECTED_JOURNEY_LINE_OUTLINE_EXTRA_THICKNESS_EACH_SIDE: int = 3 # Extra outline for selected

const PREDEFINED_CONVOY_COLORS: Array[Color] = [
	Color.RED,        # Red
	Color.BLUE,       # Blue
	Color.GREEN,      # Green
	Color.YELLOW,     # Yellow
	Color.CYAN,       # Cyan
	Color.MAGENTA,    # Magenta
	Color('orange'),  # Orange
	Color('purple'),  # Purple
	Color('lime'),    # Lime Green
	Color('pink')     # Pink
]

# Icon scaling exponent, similar to FONT_SCALING_EXPONENT in main.gd
const ICON_SCALING_EXPONENT: float = 0.6  # (1.0 = linear, <1.0 less aggressive shrink/grow)

# Arrow dimensions (in pixels)
const CONVOY_ARROW_FORWARD_LENGTH: float = 22.0     # Increased base size
const CONVOY_ARROW_BACKWARD_LENGTH: float = 7.0     # Increased base size
const CONVOY_ARROW_HALF_WIDTH: float = 12.0         # Increased base size
const CONVOY_ARROW_OUTLINE_THICKNESS: float = 2.5   # Slightly increased base size
const MAX_THROB_SIZE_ADDITION: float = 3.0          # Increased base size
const JOURNEY_LINE_OUTLINE_EXTRA_THICKNESS_EACH_SIDE: int = 2  # How many extra pixels for the white outline on each side of the journey line
const MAX_THROB_DARKEN_AMOUNT: float = 0.4          # How much the arrow darkens at its peak (0.0 to 1.0)
const JOURNEY_LINE_OFFSET_STEP_PIXELS: float = 6.0  # Increased base offset for overlapping journey lines to prevent overlap
const TRAILING_JOURNEY_DARKEN_FACTOR: float = 0.5   # How much to darken the trailing line (0.0 to 1.0)


# --- Helper Drawing Functions (Now methods of the class) ---
func _apply_shade_variation(base_color: Color, is_political_border: bool = false) -> Color:
	var variation_magnitude: float

	if is_political_border:
		variation_magnitude = 0.04  # +/- 2% for political borders
	else:
		var water_color_const = TILE_COLORS.get(0)
		if water_color_const != null and base_color.is_equal_approx(water_color_const):
			variation_magnitude = 0.04  # +/- 5% for desert terrain tiles
		else:
			variation_magnitude = 0  # +/- 2% for other terrains and settlements

	var random_variation_factor = (randf() * variation_magnitude) - (variation_magnitude / 2.0)

	var h: float = base_color.h
	var s: float = base_color.s
	var v: float = base_color.v
	var a: float = base_color.a  # Preserve alpha

	v = clamp(v + random_variation_factor, 0.0, 1.0)  # Add absolute variation to V

	return Color.from_hsv(h, s, v, a)


func _get_base_tile_color(tile_data: Dictionary) -> Color:
	""" Determines the primary terrain or settlement color for a tile, without variations. """
	var color: Color = ERROR_COLOR
	if tile_data.has('settlements') and tile_data['settlements'] is Array and not tile_data['settlements'].is_empty():
		var settlement_data = tile_data['settlements'][0]
		var sett_type = settlement_data.get('sett_type', 'MISSING_SETT_TYPE_KEY')
		# Use .get() again for safety, defaulting to ERROR_COLOR if type not found
		color = SETTLEMENT_COLORS.get(sett_type, ERROR_COLOR)
	elif tile_data.has('terrain_difficulty'):
		# Terrain path
		var difficulty_variant = tile_data['terrain_difficulty']  # Get the value (likely float)
		if typeof(difficulty_variant) == TYPE_FLOAT or typeof(difficulty_variant) == TYPE_INT:
			var difficulty_int : int = int(floor(difficulty_variant))  # Cast float/int to integer
			# Use .get() again for safety, defaulting to ERROR_COLOR if key not found
			color = TILE_COLORS.get(difficulty_int, ERROR_COLOR)
		# else: color remains ERROR_COLOR if difficulty_variant is not a number
	# else: color remains ERROR_COLOR if no 'settlements' or 'terrain_difficulty' key
	return color

func _draw_tile_bg(img: Image, tile_data: Dictionary, tile_render_x: int, tile_render_y: int, tile_render_width: int, tile_render_height: int, p_scaled_total_inset: int, _grid_x_for_debug: int, _grid_y_for_debug: int):
	var color: Color = ERROR_COLOR  # Initialized to ERROR_COLOR
	var _color_source_debug: String = 'Initial ERROR_COLOR'  # For debugging

	# if grid_x_for_debug == 0 and grid_y_for_debug == 0: # Debug print for the first tile only
		# print('DEBUG map_render.gd: Processing tile (0,0) data: ', tile_data)

	color = _get_base_tile_color(tile_data) # Get the base color using the new helper

	# Debugging for color source (can be simplified or removed if _get_base_tile_color is trusted)
	if color == ERROR_COLOR:
		if tile_data.has('settlements') and tile_data['settlements'] is Array and not tile_data['settlements'].is_empty():
			var settlement_data = tile_data['settlements'][0]
			var sett_type = settlement_data.get('sett_type', 'MISSING_SETT_TYPE_KEY')
			_color_source_debug ='Settlement (type "' + sett_type + '" not in SETTLEMENT_COLORS or other issue)'
		elif tile_data.has('terrain_difficulty'):
			_color_source_debug = 'Terrain (difficulty not in TILE_COLORS or other issue)'
		else:
			_color_source_debug = 'No "settlements" or "terrain_difficulty" key, or other issue.'

	# if grid_x_for_debug == 0 and grid_y_for_debug == 0:  # Debug print for the first tile only
		# print('DEBUG map_render.gd: Tile (0,0) final color source: ', color_source_debug, ', Resulting Color: ', color)

	# --- Drawing Logic ---
	var rect := Rect2i(
		tile_render_x + p_scaled_total_inset,
		tile_render_y + p_scaled_total_inset,
		tile_render_width - p_scaled_total_inset * 2,
		tile_render_height - p_scaled_total_inset * 2
	)

	var varied_color = _apply_shade_variation(color, false)  # Not a political border

	if rect.size.x > 0 and rect.size.y > 0:
		img.fill_rect(rect, varied_color)  # Use the varied color for drawing
	return color  # Return the original color for checks like ERROR_COLOR comparison


func _draw_political_inline(img: Image, tile_data: Dictionary, tile_render_x: int, tile_render_y: int, tile_render_width: int, tile_render_height: int, p_scaled_inset_from_edge: int):
	var region_variant = tile_data.get('region', -999)  # Can be float or int from JSON
	var region_int: int
	if typeof(region_variant) == TYPE_FLOAT or typeof(region_variant) == TYPE_INT:
		region_int = int(floor(region_variant))  # Use floor to handle potential float values correctly for keys
	else:
		# printerr('Tile (', x, ',', y, ') has non-numeric region: ', region_variant, '. Defaulting to -999.')  # x,y not directly available here
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
		var varied_political_color = _apply_shade_variation(political_color, true) # This IS a political border
		# Simple approach: Just fill the outer_rect, ignoring precise width.
		img.fill_rect(outer_rect, varied_political_color) # Draw the border color rect


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


#
func _draw_filled_triangle_on_image(image: Image, v0: Vector2, v1: Vector2, v2: Vector2, color: Color) -> void:
	""" Helper function to draw a filled triangle on an Image """
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


func _draw_line_on_image(image: Image, start: Vector2i, end: Vector2i, color: Color, thickness: int) -> void:
	""" Helper function to draw a line on an Image """
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
		var brush_offset: int = thickness / 2  # Use integer division
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


func _get_normalized_segment_key(p1_map: Vector2, p2_map: Vector2) -> String:
	""" Helper to get a canonical string key for a line segment (map coordinates) """
	var sp1: Vector2 = p1_map
	var sp2: Vector2 = p2_map
	# Sort points to ensure (A,B) and (B,A) produce the same key
	if (p1_map.x > p2_map.x) or (abs(p1_map.x - p2_map.x) < FLOAT_MATCH_TOLERANCE and p1_map.y > p2_map.y):
		sp1 = p2_map
		sp2 = p1_map
	return '%.4f,%.4f-%.4f,%.4f' % [sp1.x, sp1.y, sp2.x, sp2.y]  # Example: format to 4 decimal places


func _get_journey_segment_offset_vector(
		p1_map: Vector2, p2_map: Vector2,  # map coordinates of the segment
		p1_pixel: Vector2i, p2_pixel: Vector2i,  # pixel coordinates of the segment
		current_convoy_idx: int,
		shared_segments_data: Dictionary,  # Key: segment_key, Value: Array of convoy_indices
		base_offset_magnitude: float
	) -> Vector2:
	""" Helper to calculate offset for a shared journey line segment """
	var segment_key: String = _get_normalized_segment_key(p1_map, p2_map)
	var offset_v := Vector2.ZERO

	if shared_segments_data.has(segment_key):
		var convoy_indices_on_segment: Array = shared_segments_data[segment_key]
		if convoy_indices_on_segment.size() > 1:
			# Determine the order of the current convoy for this segment
			var current_convoy_order_on_segment: int = convoy_indices_on_segment.find(current_convoy_idx)

			if current_convoy_order_on_segment > 0: # Order 0 (first convoy) gets no offset
				var segment_vec_px: Vector2 = Vector2(p2_pixel - p1_pixel)
				if segment_vec_px.length_squared() > FLOAT_MATCH_TOLERANCE * FLOAT_MATCH_TOLERANCE:
					var perp_dir_px: Vector2 = segment_vec_px.normalized().rotated(PI / 2.0)

					# Offset logic:
					# Order 1: +1 * base_offset_magnitude
					# Order 2: -1 * base_offset_magnitude
					# Order 3: +2 * base_offset_magnitude
					# Order 4: -2 * base_offset_magnitude
					# ...and so on
					var magnitude_multiplier: float = ceil(float(current_convoy_order_on_segment) / 2.0)
					var sign_multiplier: float = 1.0 if current_convoy_order_on_segment % 2 != 0 else -1.0

					offset_v = perp_dir_px * sign_multiplier * magnitude_multiplier * base_offset_magnitude
	return offset_v


func _calculate_offset_pixel_path(
		original_map_coords_path: Array[Vector2],  # Array of Vector2 (map coordinates)
		convoy_idx: int,
		shared_segments_data: Dictionary,
		base_offset_pixel_magnitude: float,
		actual_tile_width_f: float,
		actual_tile_height_f: float
	) -> Array[Vector2i]:  # Returns Array of Vector2i (offset pixel coordinates)
	""" Helper function to calculate the vertices of an offset polyline with mitered/beveled joins """

	if original_map_coords_path.size() < 2:
		return []  # Not enough points for a path

	# 1. Convert map path to original pixel path (Array of Vector2i)
	var pixel_coords_path: Array[Vector2i] = []
	for map_p in original_map_coords_path:
		pixel_coords_path.append(Vector2i(
			round((map_p.x + 0.5) * actual_tile_width_f),
			round((map_p.y + 0.5) * actual_tile_height_f)
		))

	var n_points: int = pixel_coords_path.size()
	# n_points will be >= 2 at this stage

	# 2. Calculate all segment_pixel_offset_vectors (Array of Vector2)
	var segment_pixel_offset_vectors: Array[Vector2] = []
	for k in range(n_points - 1):  # Iterate through segments
		var map_pk: Vector2 = original_map_coords_path[k]
		var map_pkplus1: Vector2 = original_map_coords_path[k+1]
		var px_pk: Vector2i = pixel_coords_path[k]
		var px_pkplus1: Vector2i = pixel_coords_path[k+1]

		var offset_vec: Vector2 = _get_journey_segment_offset_vector(
			map_pk, map_pkplus1,
			px_pk, px_pkplus1,
			convoy_idx,
			shared_segments_data,
			base_offset_pixel_magnitude
		)
		segment_pixel_offset_vectors.append(offset_vec)

	# 3. Compute final_offset_pixel_vertices (Array of Vector2i)
	var final_offset_vertices: Array[Vector2i] = []
	final_offset_vertices.resize(n_points)  # Pre-allocate

	# Handle start point
	final_offset_vertices[0] = pixel_coords_path[0] + Vector2i(round(segment_pixel_offset_vectors[0]))

	# Handle end point
	# segment_pixel_offset_vectors has (n_points - 1) elements. Last index is (n_points - 2).
	final_offset_vertices[n_points - 1] = pixel_coords_path[n_points - 1] + Vector2i(round(segment_pixel_offset_vectors[n_points - 2]))

	# Handle intermediate vertices (miter/bevel joins)
	for k in range(1, n_points - 1):  # Loop from second point P_1 to second-to-last point P_{n-2}
		var P_km1_px: Vector2i = pixel_coords_path[k-1]
		var P_k_px: Vector2i = pixel_coords_path[k]
		var P_kp1_px: Vector2i = pixel_coords_path[k+1]

		var offset_vec_prev_s: Vector2 = segment_pixel_offset_vectors[k-1]  # Offset for segment (P_km1, P_k)
		var offset_vec_curr_s: Vector2 = segment_pixel_offset_vectors[k]    # Offset for segment (P_k, P_kp1)

		var dir_prev_orig_s: Vector2 = Vector2(P_k_px - P_km1_px)
		var dir_curr_orig_s: Vector2 = Vector2(P_kp1_px - P_k_px)

		if dir_prev_orig_s.length_squared() < FLOAT_MATCH_TOLERANCE or dir_curr_orig_s.length_squared() < FLOAT_MATCH_TOLERANCE:
			final_offset_vertices[k] = P_k_px + Vector2i(round(offset_vec_prev_s))  # Fallback for zero-length segment
			continue

		if dir_prev_orig_s.normalized().is_equal_approx(dir_curr_orig_s.normalized()):  # Collinear, same direction
			final_offset_vertices[k] = P_k_px + Vector2i(round(offset_vec_prev_s))
		else:
			var L1_start_pt: Vector2 = Vector2(P_km1_px) + offset_vec_prev_s
			var L2_start_pt: Vector2 = Vector2(P_k_px) + offset_vec_curr_s
			var intersection = Geometry2D.line_intersects_line(L1_start_pt, dir_prev_orig_s, L2_start_pt, dir_curr_orig_s)

			if intersection != null:
				final_offset_vertices[k] = Vector2i(round(intersection))
			else:  # Parallel lines (e.g., 180-degree turn) or other non-intersection. Fallback to bevel.
				var p_k_offset_avg: Vector2 = (offset_vec_prev_s + offset_vec_curr_s) / 2.0
				final_offset_vertices[k] = P_k_px + Vector2i(round(p_k_offset_avg))
	return final_offset_vertices


# --- Main Rendering Function ---
func render_map(
		tiles: Array,
		highlights: Array = [],
		lowlights: Array = [],
		highlight_color: Color = DEFAULT_HIGHLIGHT_OUTLINE_COLOR,
		lowlight_color: Color = DEFAULT_LOWLIGHT_INLINE_COLOR,
		p_viewport_size: Vector2 = Vector2.ZERO,
		p_convoys_data: Array = [],  # New parameter for convoy data
		p_throb_phase: float = 0.0,  # For animating convoy icons,
		p_convoy_id_to_color_map: Dictionary = {},  # For persistent convoy colors
		p_hover_info: Dictionary = {},  # For hover-dependent labels.
		p_selected_convoy_ids: Array = [], # New parameter for selected convoy IDs
		p_show_grid: bool = true,           # New flag for grid visibility
		p_show_political: bool = true       # New flag for political color visibility
	) -> ImageTexture:
	# print("MapRender: render_map called. p_show_grid: %s, p_show_political: %s" % [p_show_grid, p_show_political]) # DEBUG
	if tiles.is_empty() or not tiles[0] is Array or tiles[0].is_empty():
		printerr('MapRender: Invalid or empty tiles data provided.')
		return null

	var rows: int = tiles.size()
	var cols: int = tiles[0].size()

	# Ensure this node is in the scene tree to get viewport
	var viewport_size: Vector2
	if p_viewport_size == Vector2.ZERO:  # If no override is provided (or it's explicitly zero)
		# Try to get viewport size from the tree
		if not is_inside_tree():  # This check might be problematic if map_render is just a class instance
			printerr('MapRender node is not in the scene tree and no p_viewport_size override was given. Cannot determine viewport size.')
			return null
		viewport_size = get_viewport().get_visible_rect().size
	else:
		# Use the provided viewport size override
		viewport_size = p_viewport_size

	# print('MapRender: render_map called. p_hover_info: ', p_hover_info)  # DEBUG - Removed font check as font is no longer a member

	# --- Calculate target image dimensions to fit viewport while maintaining map aspect ratio ---
	var map_aspect_ratio: float = float(cols) / float(rows)
	var viewport_aspect_ratio: float = viewport_size.x / viewport_size.y

	var image_render_width_f: float
	var image_render_height_f: float

	if viewport_aspect_ratio > map_aspect_ratio:  # Viewport is wider than map, so height is the limiting factor
		image_render_height_f = viewport_size.y
		image_render_width_f = image_render_height_f * map_aspect_ratio
	else:  # Viewport is taller or same aspect ratio as map, so width is the limiting factor
		image_render_width_f = viewport_size.x
		image_render_height_f = image_render_width_f / map_aspect_ratio

	var image_render_width: int = int(round(image_render_width_f))
	var image_render_height: int = int(round(image_render_height_f))

	# --- Calculate actual floating-point tile dimensions for drawing within the target image ---
	var actual_tile_width_f: float = image_render_width_f / float(cols)
	var actual_tile_height_f: float = image_render_height_f / float(rows)
	var reference_float_tile_size_for_offsets = min(actual_tile_width_f, actual_tile_height_f)  # Used for scaling offsets

	# Calculate a general visual element scale factor based on tile rendering size
	var base_linear_visual_scale: float = 1.0
	if BASE_TILE_SIZE_FOR_PROPORTIONS > 0.001:
		base_linear_visual_scale = reference_float_tile_size_for_offsets / BASE_TILE_SIZE_FOR_PROPORTIONS

	# DEBUG: Print scaling factors (These are calculated once per render)
	# if rows > 0 and cols > 0: # Print only if map dimensions are valid # DEBUG
		# print("MapRender: base_linear_visual_scale: ", base_linear_visual_scale) # DEBUG

	var visual_element_scale_factor: float = pow(base_linear_visual_scale, ICON_SCALING_EXPONENT)

	# Calculate scaled offsets based on current_tile_size
	var scaled_grid_size: int = max(0, int(round(reference_float_tile_size_for_offsets * (float(GRID_SIZE) / BASE_TILE_SIZE_FOR_PROPORTIONS))))
	var scaled_political_border_thickness: int = max(0, int(round(reference_float_tile_size_for_offsets * (float(POLITICAL_BORDER_VISIBLE_THICKNESS) / BASE_TILE_SIZE_FOR_PROPORTIONS))))
	var scaled_highlight_outline_offset: int = int(round(reference_float_tile_size_for_offsets * (float(HIGHLIGHT_OUTLINE_OFFSET) / BASE_TILE_SIZE_FOR_PROPORTIONS)))  # Can be negative
	var scaled_lowlight_inline_offset: int = max(0, int(round(reference_float_tile_size_for_offsets * (float(LOWLIGHT_INLINE_OFFSET) / BASE_TILE_SIZE_FOR_PROPORTIONS))))

	# if rows > 0 and cols > 0: # Print only if map dimensions are valid # DEBUG
		# print("MapRender: scaled_grid_size: ", scaled_grid_size) # DEBUG

	# Use the calculated image_render_width/height for the Image
	var width: int = image_render_width
	var height: int = image_render_height
	# Create a new image
	var map_image := Image.create(width, height, false, Image.FORMAT_RGB8)
	# map_image.fill(GRID_COLOR) # Removed: We will fill each tile's background individually for the new grid effect


	var _error_color_tile_count: int = 0
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

			# --- New Grid Drawing Logic ---
			# 1. Determine base colors for the current tile (unvaried)
			var base_terrain_settlement_color: Color = _get_base_tile_color(tile)

			var region_variant = tile.get('region', -999)
			var region_int: int = -999
			if typeof(region_variant) == TYPE_FLOAT or typeof(region_variant) == TYPE_INT:
				region_int = int(floor(region_variant))
			var base_political_color: Color = POLITICAL_COLORS.get(region_int, ERROR_COLOR)

			var has_visible_political_color: bool = base_political_color.a > 0.01 and base_political_color != ERROR_COLOR

			# 2. Determine the color for this tile's grid background
			var color_for_grid_lines_base: Color
			if has_visible_political_color:
				color_for_grid_lines_base = base_political_color
			else:
				color_for_grid_lines_base = base_terrain_settlement_color

			if color_for_grid_lines_base == ERROR_COLOR: # Fallback if chosen color is error
				color_for_grid_lines_base = GRID_COLOR # Use original GRID_COLOR as a last resort for this tile's grid

			var actual_grid_line_color: Color = color_for_grid_lines_base.darkened(GRID_DARKEN_FACTOR)

			# 3. Fill the entire tile cell with this darkened color (this forms the grid lines)
			var full_tile_rect := Rect2i(current_tile_pixel_x, current_tile_pixel_y, current_tile_render_w, current_tile_render_h)
			if p_show_grid: # Only draw grid background if toggled on
				if full_tile_rect.size.x > 0 and full_tile_rect.size.y > 0: # DEBUG
					# if x == 0 and y == 0: print("MapRender (0,0): Drawing GRID background with color: ", actual_grid_line_color) # DEBUG
					map_image.fill_rect(full_tile_rect, actual_grid_line_color)
			elif x == 0 and y == 0: # If grid is OFF, what is the background?
				if full_tile_rect.size.x > 0 and full_tile_rect.size.y > 0:
					# If grid is off, the "background" is effectively the terrain/settlement color itself, drawn later.
					# Or, if you want a default background when grid is off, fill it here.
					# For now, let's assume terrain/settlement will cover it.
					pass

			# Determine inset for political layer based on whether grid is shown
			var inset_for_political_drawing: int = 0
			if p_show_grid:
				inset_for_political_drawing = scaled_grid_size # Use the original scaled_grid_size for potential thickness

			# 4. Draw political color layer (inset by grid_size if grid is shown, drawn on top of the darkened grid background or tile background)
			if p_show_political: # Only draw political colors if toggled on
				# The _draw_political_inline function itself checks if the political_color.a > 0.01
				# if x == 0 and y == 0: print("MapRender (0,0): Calling _draw_political_inline. inset_for_political_drawing: ", inset_for_political_drawing) # DEBUG
				_draw_political_inline(map_image, tile, current_tile_pixel_x, current_tile_pixel_y, current_tile_render_w, current_tile_render_h, inset_for_political_drawing)

			# 5. Draw terrain/settlement layer on top
			var inset_for_terrain_content: int = 0
			if p_show_grid: # If grid is shown, inset by grid size
				inset_for_terrain_content += scaled_grid_size
			if p_show_political and has_visible_political_color: # If political is shown AND this tile has political color, inset by political border
				inset_for_terrain_content += scaled_political_border_thickness

			# if x == 0 and y == 0: print("MapRender (0,0): Calling _draw_tile_bg. inset_for_terrain_content: ", inset_for_terrain_content) # DEBUG
			var chosen_color_from_tile_bg = _draw_tile_bg(map_image, tile, current_tile_pixel_x, current_tile_pixel_y, current_tile_render_w, current_tile_render_h, inset_for_terrain_content, x, y)
			if chosen_color_from_tile_bg == ERROR_COLOR:  # If you want to use this count, remove the underscore from _error_color_tile_count
				_error_color_tile_count += 1

			var approx_int_tile_size_for_highlight = int(round(reference_float_tile_size_for_offsets))
			_draw_highlight_or_lowlight(map_image, x, y, lowlights, lowlight_color, approx_int_tile_size_for_highlight, scaled_lowlight_inline_offset, LOWLIGHT_INLINE_WIDTH)

			_draw_highlight_or_lowlight(map_image, x, y, highlights, highlight_color, approx_int_tile_size_for_highlight, scaled_highlight_outline_offset, HIGHLIGHT_OUTLINE_WIDTH)

	# --- Create and return the texture ---

	# --- Pre-computation of shared journey segments ---
	var shared_segments_map_coords: Dictionary = {} # Key: string_segment_key, Value: Array of convoy_indices
	if not p_convoys_data.is_empty():
		# print('MapRender: Pre-computing shared journey segments...')  # DEBUG
		for convoy_idx_precompute in range(p_convoys_data.size()):
			var convoy_data_variant_pre = p_convoys_data[convoy_idx_precompute]
			if not convoy_data_variant_pre is Dictionary:
				continue
			var convoy_item_pre: Dictionary = convoy_data_variant_pre
			var journey_data_pre: Dictionary = convoy_item_pre.get('journey')

			if journey_data_pre is Dictionary:
				var route_x_coords_pre: Array = journey_data_pre.get('route_x')
				var route_y_coords_pre: Array = journey_data_pre.get('route_y')

				if route_x_coords_pre is Array and route_y_coords_pre is Array and \
				   route_x_coords_pre.size() == route_y_coords_pre.size() and route_x_coords_pre.size() >= 2:

					for i_pre in range(route_x_coords_pre.size() - 1):
						var p1_map := Vector2(float(route_x_coords_pre[i_pre]), float(route_y_coords_pre[i_pre]))
						var p2_map := Vector2(float(route_x_coords_pre[i_pre+1]), float(route_y_coords_pre[i_pre+1]))
						var segment_key: String = _get_normalized_segment_key(p1_map, p2_map)

						if not shared_segments_map_coords.has(segment_key):
							shared_segments_map_coords[segment_key] = []
						if not convoy_idx_precompute in shared_segments_map_coords[segment_key]:
							shared_segments_map_coords[segment_key].append(convoy_idx_precompute)
		#print('MapRender: Shared segments pre-computation done. Found %s unique segments with shared convoy info.' % shared_segments_map_coords.size())  # DEBUG


	# --- Draw Convoys ---
	if not p_convoys_data.is_empty():
		# print("MapRender: ==> CONVOY DRAWING SECTION <==") # DEBUG
		# print('MapRender: Received p_convoys_data.size(): %s for drawing.' % p_convoys_data.size()) # DEBUG

		# --- PASS 1: Draw all Journey Lines ---
		# print('MapRender: Pass 1 - Drawing all journey lines.') # DEBUG
		for convoy_idx in range(p_convoys_data.size()):
			var convoy_data_variant = p_convoys_data[convoy_idx]
			if not convoy_data_variant is Dictionary:
				printerr('MapRender: Convoy data item is not a dictionary: ', convoy_data_variant)
				continue

			var convoy_item: Dictionary = convoy_data_variant
			var convoy_id = convoy_item.get('convoy_id')
			# if convoy_idx == 0: # Print for the very first convoy being processed in this pass # DEBUG
				# print("MapRender (Journey Lines): Processing convoy_id: %s, ShortData: %s..." % [convoy_id, str(convoy_item).left(100)]) # DEBUG - Shortened data

			var unique_convoy_color: Color = p_convoy_id_to_color_map.get(
				convoy_id, PREDEFINED_CONVOY_COLORS[convoy_idx % PREDEFINED_CONVOY_COLORS.size()]
			)  # Fallback to old method if ID not in map
			var convoy_x_variant = convoy_item.get('x')
			var convoy_y_variant = convoy_item.get('y')

			if typeof(convoy_x_variant) in [TYPE_INT, TYPE_FLOAT] and \
			   typeof(convoy_y_variant) in [TYPE_INT, TYPE_FLOAT]:

				var journey_data: Dictionary = convoy_item.get('journey')
				if journey_data is Dictionary:
					var route_x_coords: Array = journey_data.get('route_x')
					var route_y_coords: Array = journey_data.get('route_y')

					if route_x_coords is Array and route_y_coords is Array and route_x_coords.size() == route_y_coords.size():
						var start_drawing_from_route_index: int = -1

						# Find the index in the route that matches the convoy's current position
						# This is needed to color leading/trailing parts of the line correctly.
						var convoy_map_x_for_line: float = float(convoy_x_variant)  # Need current pos for this
						var convoy_map_y_for_line: float = float(convoy_y_variant)
						for i in range(route_x_coords.size()):
							var route_point_x: float = float(route_x_coords[i])
							var route_point_y: float = float(route_y_coords[i])
							if abs(route_point_x - convoy_map_x_for_line) < FLOAT_MATCH_TOLERANCE and \
								abs(route_point_y - convoy_map_y_for_line) < FLOAT_MATCH_TOLERANCE:
								start_drawing_from_route_index = i
								break

						# --- Draw Full Journey Line (Trailing part transparent, Leading part opaque) ---
						if route_x_coords.size() >= 2:
							var original_map_path_for_convoy: Array[Vector2] = []
							for point_idx in range(route_x_coords.size()):
								original_map_path_for_convoy.append(Vector2(float(route_x_coords[point_idx]), float(route_y_coords[point_idx])))

							var offset_pixel_vertices: Array[Vector2i] = _calculate_offset_pixel_path(
								original_map_path_for_convoy,
								convoy_idx,  # Pass convoy_idx
								shared_segments_map_coords,
								JOURNEY_LINE_OFFSET_STEP_PIXELS * visual_element_scale_factor,  # Pass scaled offset magnitude
								actual_tile_width_f,
								actual_tile_height_f
							)

							if offset_pixel_vertices.size() >= 2:
								var is_selected: bool = false # Default to not selected
								if convoy_id != null and not p_selected_convoy_ids.is_empty(): # Check if convoy_id is valid and selected list is not empty
									is_selected = p_selected_convoy_ids.has(convoy_id)

								var base_line_thickness_to_use: float
								var base_outline_extra_thickness_to_use: float

								if is_selected:
									base_line_thickness_to_use = SELECTED_JOURNEY_LINE_THICKNESS
									base_outline_extra_thickness_to_use = SELECTED_JOURNEY_LINE_OUTLINE_EXTRA_THICKNESS_EACH_SIDE
								else:
									base_line_thickness_to_use = JOURNEY_LINE_THICKNESS
									base_outline_extra_thickness_to_use = JOURNEY_LINE_OUTLINE_EXTRA_THICKNESS_EACH_SIDE

								var current_scaled_journey_line_thickness: int = max(1, roundi(base_line_thickness_to_use * visual_element_scale_factor))
								var current_scaled_outline_extra_thickness: int = max(0, roundi(base_outline_extra_thickness_to_use * visual_element_scale_factor))
								var leading_line_color: Color = unique_convoy_color
								var trailing_line_color: Color = unique_convoy_color.darkened(TRAILING_JOURNEY_DARKEN_FACTOR)
								var outline_total_thickness: int = current_scaled_journey_line_thickness + (2 * current_scaled_outline_extra_thickness)

								# --- Pass 1: Draw the continuous white outline for the entire path ---
								for j in range(offset_pixel_vertices.size() - 1):
									var start_px: Vector2i = offset_pixel_vertices[j]
									var end_px: Vector2i = offset_pixel_vertices[j+1]
									if start_px == end_px: continue  # Skip zero-length segments
									_draw_line_on_image(map_image, start_px, end_px, Color.WHITE, outline_total_thickness)

								# --- Pass 2: Draw the colored journey line (with trailing/leading variations) on top ---
								for j in range(offset_pixel_vertices.size() - 1):
									var start_px: Vector2i = offset_pixel_vertices[j]
									var end_px: Vector2i = offset_pixel_vertices[j+1]
									if start_px == end_px: continue  # Skip zero-length segments

									var current_segment_color: Color
									# Segment (j, j+1) of the offset path corresponds to segment (j, j+1) of original path.
									# (j+1) is the index of the ENDPOINT of the current original segment.
									if start_drawing_from_route_index != -1 and (j + 1) <= start_drawing_from_route_index:
										current_segment_color = trailing_line_color
									else:
										current_segment_color = leading_line_color

									_draw_line_on_image(map_image, start_px, end_px, current_segment_color, current_scaled_journey_line_thickness)

			# else for invalid convoy coordinates (x,y) - error will be printed in Pass 2 if it affects arrow drawing.
			# For lines, if x/y are invalid, start_drawing_from_route_index remains -1, and all segments are "leading".

		# --- PASS 2: Draw all Convoy Arrows ---
		# print('MapRender: Pass 2 - Drawing all convoy arrows.') # DEBUG
		for convoy_idx in range(p_convoys_data.size()):
			var convoy_data_variant = p_convoys_data[convoy_idx]
			if not convoy_data_variant is Dictionary:
				# Already handled in Pass 1, but good to be safe or if Pass 1 was skipped for this item.
				# printerr('MapRender (Pass 2): Convoy data item is not a dictionary: ', convoy_data_variant)
				continue
			var convoy_item: Dictionary = convoy_data_variant
			var convoy_id = convoy_item.get('convoy_id')
			# if convoy_idx == 0: # Print for the very first convoy being processed in this pass # DEBUG
				# print("MapRender (Arrows): Processing convoy_id: %s, ShortData: %s..." % [convoy_id, str(convoy_item).left(100)]) # DEBUG - Shortened data
			var unique_convoy_color: Color = p_convoy_id_to_color_map.get(
				convoy_id, PREDEFINED_CONVOY_COLORS[convoy_idx % PREDEFINED_CONVOY_COLORS.size()]
			) # Fallback to old method if ID not in map
			var convoy_x_variant = convoy_item.get('x')
			var convoy_y_variant = convoy_item.get('y')

			if typeof(convoy_x_variant) in [TYPE_INT, TYPE_FLOAT] and \
			   typeof(convoy_y_variant) in [TYPE_INT, TYPE_FLOAT]:

				var convoy_map_x: float = float(convoy_x_variant)
				var convoy_map_y: float = float(convoy_y_variant)

				var center_pixel_x: float = (convoy_map_x + 0.5) * actual_tile_width_f
				var center_pixel_y: float = (convoy_map_y + 0.5) * actual_tile_height_f
				var current_convoy_pixel_pos := Vector2(center_pixel_x, center_pixel_y)
				var convoy_icon_offset_vec := Vector2.ZERO  # Initialize offset for the icon

				var direction_norm := Vector2.UP  # Default direction
				var journey_data_for_arrow: Dictionary = convoy_item.get('journey')  # Renamed to avoid conflict if used above
				if journey_data_for_arrow is Dictionary:
					var route_x_coords_for_arrow: Array = journey_data_for_arrow.get('route_x')
					var route_y_coords_for_arrow: Array = journey_data_for_arrow.get('route_y')

					if route_x_coords_for_arrow is Array and route_y_coords_for_arrow is Array and \
					   route_x_coords_for_arrow.size() == route_y_coords_for_arrow.size():

						var current_route_idx_for_arrow: int = -1
						for i in range(route_x_coords_for_arrow.size()):
							var rx: float = float(route_x_coords_for_arrow[i])
							var ry: float = float(route_y_coords_for_arrow[i])
							if abs(rx - convoy_map_x) < FLOAT_MATCH_TOLERANCE and \
							   abs(ry - convoy_map_y) < FLOAT_MATCH_TOLERANCE:
								current_route_idx_for_arrow = i
								break

						# Determine segment for offset and direction
						if current_route_idx_for_arrow != -1 and current_route_idx_for_arrow + 1 < route_x_coords_for_arrow.size():
							# Convoy is on a segment heading to a next point
							var next_route_map_x: float = float(route_x_coords_for_arrow[current_route_idx_for_arrow + 1])
							var next_route_map_y: float = float(route_y_coords_for_arrow[current_route_idx_for_arrow + 1])

							var p1_map_for_offset = Vector2(convoy_map_x, convoy_map_y)  # Current point
							var p2_map_for_offset = Vector2(next_route_map_x, next_route_map_y)  # Next point

							# Pixel coordinates for _get_journey_segment_offset_vector
							var p1_pixel_for_offset = Vector2i(round(current_convoy_pixel_pos))
							var p2_pixel_for_offset = Vector2i(
								round((p2_map_for_offset.x + 0.5) * actual_tile_width_f),
								round((p2_map_for_offset.y + 0.5) * actual_tile_height_f)
							)

							convoy_icon_offset_vec = _get_journey_segment_offset_vector(
								p1_map_for_offset, p2_map_for_offset,
								p1_pixel_for_offset, p2_pixel_for_offset,
								convoy_idx, shared_segments_map_coords, JOURNEY_LINE_OFFSET_STEP_PIXELS
							)

							var next_route_pixel_x: float = (next_route_map_x + 0.5) * actual_tile_width_f
							var next_route_pixel_y: float = (next_route_map_y + 0.5) * actual_tile_height_f
							var target_pixel_for_direction := Vector2(next_route_pixel_x, next_route_pixel_y)

							var direction_vec = target_pixel_for_direction - current_convoy_pixel_pos  # Direction based on original positions
							if direction_vec.length_squared() > FLOAT_MATCH_TOLERANCE * FLOAT_MATCH_TOLERANCE :
								direction_norm = direction_vec.normalized()
						elif current_route_idx_for_arrow != -1 and current_route_idx_for_arrow > 0:
							# Convoy is at the last point, use previous segment for offset
							var prev_route_map_x: float = float(route_x_coords_for_arrow[current_route_idx_for_arrow - 1])
							var prev_route_map_y: float = float(route_y_coords_for_arrow[current_route_idx_for_arrow - 1])

							var p1_map_for_offset = Vector2(prev_route_map_x, prev_route_map_y)  # Previous point
							var p2_map_for_offset = Vector2(convoy_map_x, convoy_map_y)  # Current (last) point

							var p1_pixel_for_offset = Vector2i(
								round((p1_map_for_offset.x + 0.5) * actual_tile_width_f),
								round((p1_map_for_offset.y + 0.5) * actual_tile_height_f)
							)
							var p2_pixel_for_offset = Vector2i(round(current_convoy_pixel_pos))
							convoy_icon_offset_vec = _get_journey_segment_offset_vector(
								p1_map_for_offset, p2_map_for_offset,
								p1_pixel_for_offset, p2_pixel_for_offset,
								convoy_idx, shared_segments_map_coords, JOURNEY_LINE_OFFSET_STEP_PIXELS
							)
							# Direction remains default UP as there's no next segment

				# Apply the calculated offset to the convoy's drawing position
				var final_convoy_pixel_pos = current_convoy_pixel_pos + convoy_icon_offset_vec

				# Use the visual_element_scale_factor calculated earlier

				# --- Draw Convoy Arrow ---
				var throb_factor: float = (sin(p_throb_phase * 2.0 * PI) + 1.0) / 2.0

				var scaled_max_throb_addition: float = MAX_THROB_SIZE_ADDITION * visual_element_scale_factor
				var current_size_addition: float = throb_factor * scaled_max_throb_addition

				var current_forward_len: float = (CONVOY_ARROW_FORWARD_LENGTH * visual_element_scale_factor) + current_size_addition
				var current_backward_len: float = (CONVOY_ARROW_BACKWARD_LENGTH * visual_element_scale_factor) + current_size_addition
				var current_half_width: float = (CONVOY_ARROW_HALF_WIDTH * visual_element_scale_factor) + current_size_addition
				var current_outline_thickness: float = (CONVOY_ARROW_OUTLINE_THICKNESS * visual_element_scale_factor) + (throb_factor * (scaled_max_throb_addition / 2.0))

				var perp_norm: Vector2 = direction_norm.rotated(PI / 2.0)
				var v_tip: Vector2 = final_convoy_pixel_pos + direction_norm * current_forward_len
				var v_rear_center: Vector2 = final_convoy_pixel_pos - direction_norm * current_backward_len
				var v_base_left: Vector2 = v_rear_center + perp_norm * current_half_width
				var v_base_right: Vector2 = v_rear_center - perp_norm * current_half_width

				var outline_forward_len: float = current_forward_len + current_outline_thickness
				var outline_backward_len: float = current_backward_len + current_outline_thickness
				var outline_half_width: float = current_half_width + current_outline_thickness

				var ov_tip: Vector2 = final_convoy_pixel_pos + direction_norm * outline_forward_len
				var ov_rear_center: Vector2 = final_convoy_pixel_pos - direction_norm * outline_backward_len
				var ov_base_left: Vector2 = ov_rear_center + perp_norm * outline_half_width
				var ov_base_right: Vector2 = ov_rear_center - perp_norm * outline_half_width
				_draw_filled_triangle_on_image(map_image, round(ov_tip), round(ov_base_left), round(ov_base_right), Color.BLACK)

				var darken_amount: float = throb_factor * MAX_THROB_DARKEN_AMOUNT
				var throbbing_fill_color: Color = unique_convoy_color.darkened(darken_amount)
				_draw_filled_triangle_on_image(map_image, round(v_tip), round(v_base_left), round(v_base_right), throbbing_fill_color)

			else:  # This 'else' corresponds to 'if typeof(convoy_x_variant) ...'
				printerr('MapRender (Pass 2 Arrows): Convoy item has invalid or missing x/y coordinates, cannot draw arrow: ', convoy_item)
	# else: # p_convoys_data IS empty # DEBUG
		# print("MapRender: ==> CONVOY DRAWING SECTION SKIPPED (p_convoys_data is empty) <==") # DEBUG


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
		printerr('Invalid matrix for truncation.')
		return result

	# Basic bounds check
	if y1 < 0 or y1 >= matrix.size() or y2 < y1 or y2 >= matrix.size():
		printerr('Y coordinates out of bounds for truncation.')
		return result
	if x1 < 0 or x1 >= matrix[0].size() or x2 < x1 or x2 >= matrix[0].size():
		printerr('X coordinates out of bounds for truncation.')
		return result

	for y in range(y1, y2 + 1):
		var row = matrix[y]
		if row is Array:
			result.append(row.slice(x1, x2 + 1))
		else:
			printerr('Row ', y, ' is not an array during truncation.')

	return result

func round(v: Vector2) -> Vector2i:  # Helper to round Vector2 components to Vector2i
	return Vector2i(roundi(v.x), roundi(v.y))
