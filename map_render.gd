# map_render.gd
# Translated from map_render.py for Godot 4.4
extends Node

# --- Constants ---
## The original tile size of the map data, used for scaling calculations of visual elements.
@export_group("Base Configuration") 
@export var base_tile_size_for_proportions: float = 24.0 
## The thickness of the grid lines in pixels, relative to the base_tile_size_for_proportions.
@export var grid_size: int = 1 
## Default color for labels if map_render were to draw them (currently unused here).
@export var default_label_color: Color = Color.WHITE 
## How much to darken the base tile color for the grid lines (0.0 = no change, 1.0 = black).
@export var grid_darken_factor: float = 0.2 
## Fallback color for grid lines if a tile's base color cannot be determined.
@export var grid_color: Color = Color('#303030') 
## Default color for water tiles.
@export var water_color: Color = Color('#142C55') 
## Color used to indicate rendering errors or missing data.
@export var error_color: Color = Color('#FF00FF') 

## Color mapping for different terrain types. (Note: Dictionaries are editable in inspector but can be clunky)
@export_group("Tile & Political Colors (Edit in Script)") # Indicate these are better edited in script 
@export var tile_colors: Dictionary = { 
	1: Color('#303030'),   # Highway
	2: Color('#606060'),   # Road
	3: Color('#CB8664'),   # Trail
	4: Color('#F6D0B0'),   # Desert 
	5: Color('#3F5D4B'),   # Plains
	6: Color('#2C412E'),   # Forest
	7: Color('#2A4B46'),   # Swamp
	8: Color('#273833'),   # Mountains
	9: Color('#0F2227'),   # Near Impassable
	0: Color('#142C55'),   # Impassable/Ocean (Will be updated from water_color in _ready)
	-1: Color('#9900FF'),  # Marked
}

## Color mapping for different settlement types.
@export var settlement_colors: Dictionary = { 
	'dome': Color('#80A9B6'),
	'city': Color('#ADADAD'),
	'town': Color('#A1662F'), #
	'city-state': Color('#581B63'),
	'military_base': Color('#800000'),
	'village': Color('#613D3D'),
	'tutorial': Color('#142C55') # Will be updated from water_color in _ready)
}

## Color mapping for political regions.
@export var political_colors: Dictionary = { 
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

## How thick the political color border around terrain should be (in base pixels, scaled).
@export_group("Highlight & Lowlight") 
@export var political_border_visible_thickness: int = 1 
## Default color for the outline around highlighted tiles.
@export var default_highlight_outline_color: Color = Color('#FFFF00') 
## Offset of the highlight outline from the tile edge (negative for outside, positive for inside). Scaled.
@export var highlight_outline_offset: int = -1 
## Width of the highlight outline. Scaled.
@export var highlight_outline_width: int = 9 
## Default color for the inline effect on lowlighted tiles.
@export var default_lowlight_inline_color: Color = Color('#00FFFF') 
## Offset of the lowlight inline from the tile edge (negative for outside, positive for inside). Scaled.
@export var lowlight_inline_offset: int = 2 
## Width of the lowlight inline. Scaled.
@export var lowlight_inline_width: int = 5 

## Pixel thickness of the convoy journey lines. Scaled.
@export_group("Journey Lines") 
@export var journey_line_thickness: int = 5 
## Thickness for selected convoy journey lines. Scaled.
@export var selected_journey_line_thickness: int = 9 
## Extra thickness on each side for the outline of selected journey lines. Scaled.
@export var selected_journey_line_outline_extra_thickness_each_side: int = 3 
## Extra thickness on each side for the outline of regular journey lines. Scaled.
@export var journey_line_outline_extra_thickness_each_side: int = 2
## Base center-to-center offset in pixels for separating parallel journey lines. Scaled.
## This value should be >= the thickest possible line (including outline) to prevent overlap.
## Max selected line width = 9 (base) + 2*3 (outline) = 15.
@export var journey_line_offset_step_pixels: float = 16.0 # Increased from 6.0
## Color for the outline of journey lines.
@export var journey_line_outline_color: Color = Color.WHITE 
## Factor by which to darken the trailing part of a journey line (0.0 = no change, 1.0 = black).
@export var trailing_journey_darken_factor: float = 0.5 

# This constant IS used by the journey line offsetting logic.
const FLOAT_MATCH_TOLERANCE: float = 0.00001  # Tolerance for matching float coordinates

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

# These @export vars are no longer used by map_render.gd if convoys are separate nodes.
## Controls how aggressively convoy icons scale with map zoom (1.0 = linear, <1.0 less aggressive).
@export_group("Convoy Icons & Animation") 
@export var icon_scaling_exponent: float = 0.6 
# Arrow dimensions (in pixels)
## Base forward length of the convoy arrow icon. Scaled.
@export var convoy_arrow_forward_length: float = 22.0 
## Base backward length of the convoy arrow icon. Scaled.
@export var convoy_arrow_backward_length: float = 7.0 
## Base half-width of the convoy arrow icon. Scaled.
@export var convoy_arrow_half_width: float = 12.0 
## Base thickness of the convoy arrow icon's outline. Scaled.
@export var convoy_arrow_outline_thickness: float = 2.5 
## Maximum additional size (in pixels) for the convoy icon during its throbbing animation. Scaled.
@export var max_throb_size_addition: float = 3.0 
## Maximum amount the convoy icon darkens at its throbbing peak (0.0 = no change, 1.0 = black).
@export var max_throb_darken_amount: float = 0.4 


func _ready():
	# Ensure that the specific dictionary keys for water use the
	# current (potentially Inspector-modified) value of self.water_color.
	# This overrides the literal default set in the declaration if water_color was changed.
	if tile_colors.has(0):
		tile_colors[0] = water_color
	if settlement_colors.has('tutorial'):
		settlement_colors['tutorial'] = water_color



# --- Helper Drawing Functions (Now methods of the class) ---
func _apply_shade_variation(base_color: Color, is_political_border: bool = false) -> Color:
	var variation_magnitude: float

	if is_political_border:
		variation_magnitude = 0.04  # +/- 2% for political borders
	else:
		var water_color_const = tile_colors.get(0) # Get current water color
		if water_color_const != null and base_color.is_equal_approx(water_color_const):
			variation_magnitude = 0.04  # +/- 2% for water tiles
		else:
			variation_magnitude = 0.0  # No variation for other terrains and settlements

	var random_variation_factor = (randf() * variation_magnitude) - (variation_magnitude / 2.0)

	var h: float = base_color.h
	var s: float = base_color.s
	var v: float = base_color.v
	var a: float = base_color.a  # Preserve alpha

	v = clamp(v + random_variation_factor, 0.0, 1.0)  # Add absolute variation to V

	return Color.from_hsv(h, s, v, a)


func _get_base_tile_color(tile_data: Dictionary) -> Color:
	""" Determines the primary terrain or settlement color for a tile, without variations. """
	var color: Color = error_color # Use exported instance variable
	if tile_data.has('settlements') and tile_data['settlements'] is Array and not tile_data['settlements'].is_empty(): # Use exported variable
		var settlement_data = tile_data['settlements'][0]
		var sett_type = settlement_data.get('sett_type', 'MISSING_SETT_TYPE_KEY')
		# Use .get() again for safety, defaulting to ERROR_COLOR if type not found
		color = settlement_colors.get(sett_type, error_color) # Use exported variable
	elif tile_data.has('terrain_difficulty'):
		# Terrain path
		var difficulty_variant = tile_data['terrain_difficulty']  # Get the value (likely float)
		if typeof(difficulty_variant) == TYPE_FLOAT or typeof(difficulty_variant) == TYPE_INT:
			var difficulty_int : int = int(floor(difficulty_variant))  # Cast float/int to integer
			# Use .get() again for safety, defaulting to ERROR_COLOR if key not found
			color = tile_colors.get(difficulty_int, error_color) # Use exported variable
		# else: color remains ERROR_COLOR if difficulty_variant is not a number
	# else: color remains ERROR_COLOR if no 'settlements' or 'terrain_difficulty' key
	return color

func _draw_tile_bg(img: Image, tile_data: Dictionary, tile_render_x: int, tile_render_y: int, tile_render_width: int, tile_render_height: int, p_scaled_total_inset: int, _grid_x_for_debug: int, _grid_y_for_debug: int):
	var color: Color = self.error_color  # Initialized to error_color (use exported instance variable)
	var _color_source_debug: String = 'Initial ERROR_COLOR'  # For debugging

	# if grid_x_for_debug == 0 and grid_y_for_debug == 0: # Debug print for the first tile only
		# print('DEBUG map_render.gd: Processing tile (0,0) data: ', tile_data)

	color = _get_base_tile_color(tile_data) # Get the base color using the new helper

	# Debugging for color source (can be simplified or removed if _get_base_tile_color is trusted)
	if color == self.error_color: # Use exported instance variable
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
	var political_color: Color = political_colors.get(region_int, error_color) # Use exported variables

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


func _draw_highlight_or_lowlight(img: Image, x: int, y: int, coords_list: Array, color: Color, current_tile_size: int, p_scaled_offset: int):
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


# This function is no longer used by map_render.gd if convoys are separate nodes.
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


# This function is no longer used by map_render.gd if journey lines are separate nodes or part of ConvoyNode.
func _draw_line_on_image(image: Image, start: Vector2i, end: Vector2i, color: Color, thickness: int, cap_style: String = "square") -> void:
	# print("MapRender: _draw_line_on_image called with start: %s, end: %s, color: %s, thickness: %s" % [start, end, color, thickness]) # DEBUG
	""" Helper function to draw a line on an Image """
	if thickness <= 0:
		return

	# Basic Bresenham's line algorithm
	var x1: int = start.x
	var y1: int = start.y
	var x2: int = end.x
	var y2: int = end.y

	var dx_abs: int = abs(x2 - x1) # Renamed to avoid conflict
	var dy_abs: int = -abs(y2 - y1) # Use negative dy for standard algorithm form

	var sx: int = 1 if x1 < x2 else -1
	var sy: int = 1 if y1 < y2 else -1

	var err: int = dx_abs + dy_abs # error value e_xy
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
		# print("MapRender: _draw_line_on_image drawing rect: %s with color %s" % [brush_rect, color]) # DEBUG
		image.fill_rect(brush_rect, color)

		# Check for end of line
		if current_x == x2 and current_y == y2:
			break
		e2 = 2 * err
		if e2 >= dy_abs: # e_xy+e_x > 0
			err += dy_abs; current_x += sx
		if e2 <= dx_abs: # e_xy+e_y < 0
			err += dx_abs; current_y += sy

	# Draw round caps if specified, after the line body is drawn
	if cap_style == "round":
		var cap_radius = float(thickness) / 2.0
		if cap_radius > 0.1: # Only draw caps if they have some meaningful size
			_draw_filled_circle_on_image(image, start.x, start.y, cap_radius, color)
			# If the line has length (start != end), draw the end cap too.
			if not (start.x == end.x and start.y == end.y):
				_draw_filled_circle_on_image(image, end.x, end.y, cap_radius, color)

# Helper to draw a filled circle on an Image (used for round caps)
func _draw_filled_circle_on_image(image: Image, center_x: int, center_y: int, radius: float, p_color: Color):
	if radius <= 0.1: # Don't draw if radius is too small
		return

	var r_sq = radius * radius
	# Calculate bounding box for the circle
	var min_x = floori(float(center_x) - radius)
	var max_x = ceili(float(center_x) + radius)
	var min_y = floori(float(center_y) - radius)
	var max_y = ceili(float(center_y) + radius)

	# Clamp to image bounds
	min_x = max(0, min_x)
	max_x = min(image.get_width() - 1, max_x)
	min_y = max(0, min_y)
	max_y = min(image.get_height() - 1, max_y)

	for y_px in range(min_y, max_y + 1):
		for x_px in range(min_x, max_x + 1):
			var dx_c = float(x_px) - float(center_x) # Distance from center
			var dy_c = float(y_px) - float(center_y) # Distance from center
			if dx_c*dx_c + dy_c*dy_c <= r_sq: # If point is within circle
				image.set_pixel(x_px, y_px, p_color)

# This function IS used by map_render.gd for drawing journey lines, and will also be called by main.gd
func get_normalized_segment_key(p1_map: Vector2, p2_map: Vector2) -> String:
	"""
	Helper to get a canonical string key for a line segment (map coordinates).
	Rounds coordinates to a fixed precision (e.g., nearest 0.001) to make keys
	more robust to tiny floating point variations before formatting.
	"""
	# Round coordinates to 3 decimal places for key generation
	var p1_r := Vector2(snapped(p1_map.x, 0.001), snapped(p1_map.y, 0.001))
	var p2_r := Vector2(snapped(p2_map.x, 0.001), snapped(p2_map.y, 0.001))

	var sp1: Vector2 = p1_r
	var sp2: Vector2 = p2_r
	
	# Sort points to ensure (A,B) and (B,A) produce the same key
	if (p1_r.x > p2_r.x) or (abs(p1_r.x - p2_r.x) < FLOAT_MATCH_TOLERANCE and p1_r.y > p2_r.y):
		sp1 = p2_r
		sp2 = p1_r
	return '%.4f,%.4f-%.4f,%.4f' % [sp1.x, sp1.y, sp2.x, sp2.y]  # Example: format to 4 decimal places


# This function IS used by map_render.gd for drawing journey lines, and will also be called by main.gd
func get_journey_segment_offset_vector(
		p1_map: Vector2, p2_map: Vector2,  # map coordinates of the segment
		p1_pixel: Vector2i, p2_pixel: Vector2i,  # pixel coordinates of the segment
		current_convoy_idx: int,
		shared_segments_data: Dictionary,  # Key: segment_key, Value: Array of convoy_indices
		base_offset_magnitude: float
	) -> Vector2:
	""" Helper to calculate offset for a shared journey line segment """
	var segment_key: String = get_normalized_segment_key(p1_map, p2_map) # Use public version
	var offset_v := Vector2.ZERO

	if shared_segments_data.has(segment_key):
		var convoy_indices_on_segment: Array = shared_segments_data[segment_key]
		var num_lines_on_segment: int = convoy_indices_on_segment.size()

		if num_lines_on_segment > 1: # Only apply offset if more than one line shares the segment
			# --- DEBUG LOGGING START (conditional) ---
			var should_debug_this_segment = false
			# Example: To debug a specific segment key known from previous logs
			# if segment_key == "149.0000,67.0000-149.0000,68.0000":
			# 	should_debug_this_segment = true
			# Or, to debug any segment with 3 or more lines (set to true to enable):
			if false and num_lines_on_segment >= 3: # Log for segments with 3 or more lines
				should_debug_this_segment = true

			if should_debug_this_segment:
				print_debug("MapRender Offset Debug for Segment: ", segment_key)
				print_debug("  - Current Convoy Original Index (param current_convoy_idx): ", current_convoy_idx)
				print_debug("  - All Convoy Indices On This Segment (from shared_data): ", convoy_indices_on_segment)
				print_debug("  - Num Lines On This Segment: ", num_lines_on_segment)
			# --- DEBUG LOGGING END ---

			# Determine the order of the current convoy for this segment
			var current_convoy_order_on_segment: int = convoy_indices_on_segment.find(current_convoy_idx)

			if current_convoy_order_on_segment != -1: # Ensure the current convoy is actually in the list for this segment
				var segment_vec_px: Vector2 = Vector2(p2_pixel - p1_pixel)
				if segment_vec_px.length_squared() > FLOAT_MATCH_TOLERANCE * FLOAT_MATCH_TOLERANCE:
					var perp_dir_px: Vector2 = segment_vec_px.normalized().rotated(PI / 2.0)
					var center_offset_factor: float = (float(num_lines_on_segment) - 1.0) / 2.0
					var line_specific_offset_factor: float = float(current_convoy_order_on_segment) - center_offset_factor
					offset_v = perp_dir_px * line_specific_offset_factor * base_offset_magnitude # base_offset_magnitude is scaled_journey_line_offset_step_pixels
					if should_debug_this_segment:
						print_debug("    - Calculated Order for Current Convoy (find result): ", current_convoy_order_on_segment)
						print_debug("    - Center Offset Factor: ", center_offset_factor)
						print_debug("    - Line Specific Offset Factor: ", line_specific_offset_factor)
						print_debug("    - Final Offset Vector: ", offset_v)
	return offset_v


# This function is no longer used by map_render.gd if journey lines are separate nodes or part of ConvoyNode.
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

		var offset_vec: Vector2 = get_journey_segment_offset_vector( # Use public version
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

		# The FLOAT_MATCH_TOLERANCE constant would be needed here if this function were still used.
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
		p_highlight_color_override: Color = Color(0,0,0,0), # Use transparent as unassigned
		p_lowlight_color_override: Color = Color(0,0,0,0),  # Use transparent as unassigned
		p_viewport_size: Vector2 = Vector2.ZERO, # Convoy, hover, selection params removed
		p_show_grid: bool = true,           # New flag for grid visibility
		p_show_political: bool = true,      # New flag for political color visibility
		p_render_highlights_lowlights: bool = true # New flag to control highlight/lowlight rendering
		# p_render_convoys parameter is removed
	) -> ImageTexture:
	# Use exported defaults if overrides are not provided (or are transparent)
	var current_highlight_color = default_highlight_outline_color if p_highlight_color_override.a == 0.0 else p_highlight_color_override
	var current_lowlight_color = default_lowlight_inline_color if p_lowlight_color_override.a == 0.0 else p_lowlight_color_override

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
	if base_tile_size_for_proportions > 0.001: # Use exported variable
		base_linear_visual_scale = reference_float_tile_size_for_offsets / base_tile_size_for_proportions

	# visual_element_scale_factor is no longer needed here as convoy icons are separate nodes.
	# var visual_element_scale_factor: float = pow(base_linear_visual_scale, icon_scaling_exponent) 

	# Calculate scaled offsets based on current_tile_size
	var scaled_grid_size: int = max(0, int(round(reference_float_tile_size_for_offsets * (float(grid_size) / base_tile_size_for_proportions)))) # Use exported variables
	var scaled_political_border_thickness: int = max(0, int(round(reference_float_tile_size_for_offsets * (float(political_border_visible_thickness) / base_tile_size_for_proportions)))) # Use exported variables
	var scaled_highlight_outline_offset: int = int(round(reference_float_tile_size_for_offsets * (float(highlight_outline_offset) / base_tile_size_for_proportions)))  # Can be negative, use exported variables
	var scaled_lowlight_inline_offset: int = max(0, int(round(reference_float_tile_size_for_offsets * (float(lowlight_inline_offset) / base_tile_size_for_proportions)))) # Use exported variables

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
			var base_political_color: Color = political_colors.get(region_int, error_color) # Use exported variables
			var has_visible_political_color: bool = base_political_color.a > 0.01 and base_political_color != self.error_color # Use exported instance variable

			# 2. Determine the color for this tile's grid background
			var color_for_grid_lines_base: Color
			if has_visible_political_color:
				color_for_grid_lines_base = base_political_color
			else:
				color_for_grid_lines_base = base_terrain_settlement_color
			if color_for_grid_lines_base == self.error_color: # Fallback if chosen color is error (use exported instance variable)
				color_for_grid_lines_base = grid_color # Use original GRID_COLOR as a last resort for this tile's grid (use exported variable)

			var actual_grid_line_color: Color = color_for_grid_lines_base.darkened(grid_darken_factor) # Use exported variable

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
			if chosen_color_from_tile_bg == self.error_color:  # If you want to use this count, remove the underscore from _error_color_tile_count (use exported instance variable)
				_error_color_tile_count += 1

			if p_render_highlights_lowlights:
				var approx_int_tile_size_for_highlight = int(round(reference_float_tile_size_for_offsets))
				_draw_highlight_or_lowlight(map_image, x, y, lowlights, current_lowlight_color, approx_int_tile_size_for_highlight, scaled_lowlight_inline_offset) # Use current_ and exported variable

				_draw_highlight_or_lowlight(map_image, x, y, highlights, current_highlight_color, approx_int_tile_size_for_highlight, scaled_highlight_outline_offset) # Use current_ and exported variable

	# --- Create and return the texture ---

	# --- Draw Journey Lines from Highlights ---
	# This section processes items in the 'highlights' array that are specifically for journey paths.
	# print("MapRender: Checking for journey_path highlights. p_render_highlights_lowlights: ", p_render_highlights_lowlights) # DEBUG
	# print("MapRender: Received highlights array: ", highlights) # DEBUG
	if p_render_highlights_lowlights: # Journey lines are also controlled by this flag for now
		# Scaled thickness will be determined per line based on selection status

		# --- New: Collect journey paths and build shared_segments_data for offsetting ---
		var journey_path_objects: Array = []
		for h_item in highlights:
			# Ensure h_item is a Dictionary before calling .get()
			if h_item is Dictionary and h_item.has("type") and h_item.get("type") == "journey_path":
				journey_path_objects.append(h_item)
		
		var shared_segments_data: Dictionary = {}
		if not journey_path_objects.is_empty():
			# Build shared_segments_data
			for convoy_idx_for_offset in range(journey_path_objects.size()):
				var current_journey_path_object = journey_path_objects[convoy_idx_for_offset]
				var current_path_tile_coords: Array = current_journey_path_object.get("points", [])
				# Ensure path has at least 2 points and points are Vector2
				if current_path_tile_coords.size() >= 2 and (not current_path_tile_coords.is_empty() and current_path_tile_coords[0] is Vector2):
					for k_segment in range(current_path_tile_coords.size() - 1):
						var p1_map: Vector2 = current_path_tile_coords[k_segment]
						var p2_map: Vector2 = current_path_tile_coords[k_segment + 1]
						var segment_key: String = get_normalized_segment_key(p1_map, p2_map) # Use public version
						if not shared_segments_data.has(segment_key):
							shared_segments_data[segment_key] = []
						shared_segments_data[segment_key].append(convoy_idx_for_offset)
		
		var scaled_journey_line_offset_step_pixels: float = journey_line_offset_step_pixels * base_linear_visual_scale
		# --- End New: Offset calculation setup ---

		var all_paths_render_data: Array = [] # To store data for two-pass rendering

		for convoy_idx_for_offset in range(journey_path_objects.size()):
			var highlight_item = journey_path_objects[convoy_idx_for_offset]
			var path_tile_coords: Array = highlight_item.get("points", []) # These are original map tile coordinates
			# Ensure path has at least 2 points and points are Vector2
			if path_tile_coords.size() >= 2 and (not path_tile_coords.is_empty() and path_tile_coords[0] is Vector2):
				var line_color: Color = highlight_item.get("color", Color.WHITE)
				var is_selected_path: bool = highlight_item.get("is_selected", false)
				var convoy_seg_start_idx: int = highlight_item.get("convoy_segment_start_idx", -1)
				var progress_in_curr_seg: float = highlight_item.get("progress_in_current_segment", 0.0) # Default to 0.0

				var base_thickness_for_scaling: int = selected_journey_line_thickness if is_selected_path else journey_line_thickness
				var scaled_current_line_thickness = max(1, int(round(reference_float_tile_size_for_offsets * (float(base_thickness_for_scaling) / base_tile_size_for_proportions))))
				
				var base_extra_thickness_per_side: int = selected_journey_line_outline_extra_thickness_each_side if is_selected_path else journey_line_outline_extra_thickness_each_side
				var base_total_thickness_for_outline_pass: int = base_thickness_for_scaling + (2 * base_extra_thickness_per_side)
				var scaled_total_thickness_for_outline_pass: int = max(1, int(round(reference_float_tile_size_for_offsets * (float(base_total_thickness_for_outline_pass) / base_tile_size_for_proportions))))

				var offset_pixel_points: Array[Vector2i] = _calculate_offset_pixel_path(
					path_tile_coords, # original_map_coords_path (Array[Vector2])
					convoy_idx_for_offset, # convoy_idx (our temporary index for this render pass)
					shared_segments_data,
					scaled_journey_line_offset_step_pixels, # base_offset_pixel_magnitude
					actual_tile_width_f,
					actual_tile_height_f
				)
				
				if offset_pixel_points.size() >= 2:
					all_paths_render_data.append({
						"points": offset_pixel_points,
						"outline_thickness": scaled_total_thickness_for_outline_pass,
						"fill_color": line_color,
						"fill_thickness": scaled_current_line_thickness,
						"convoy_seg_start_idx": convoy_seg_start_idx,
						"progress_in_curr_seg": progress_in_curr_seg
					})

		# Pass 1: Draw all OUTLINES
		for path_data in all_paths_render_data:
			var points: Array[Vector2i] = path_data.points
			var outline_thick: int = path_data.outline_thickness
			var seg_start_idx: int = path_data.convoy_seg_start_idx
			var prog_in_seg: float = path_data.progress_in_curr_seg
			
			for i in range(points.size() - 1):
				var p1: Vector2i = points[i]
				var p2: Vector2i = points[i+1]
				
				var is_behind: bool = (seg_start_idx != -1 and i < seg_start_idx)
				var is_current: bool = (seg_start_idx != -1 and i == seg_start_idx)
				
				var current_outline_color = journey_line_outline_color # Default
				var darkened_outline_color = journey_line_outline_color.darkened(trailing_journey_darken_factor)

				if is_behind:
					_draw_line_on_image(map_image, p1, p2, darkened_outline_color, outline_thick, "round")
				elif is_current:
					var split_point = Vector2i(Vector2(p1).lerp(Vector2(p2), prog_in_seg))
					_draw_line_on_image(map_image, p1, split_point, darkened_outline_color, outline_thick, "round")
					if prog_in_seg < 0.999: # If there's an "ahead" part
						_draw_line_on_image(map_image, split_point, p2, current_outline_color, outline_thick, "round")
				else: # Fully ahead or no progress info
					_draw_line_on_image(map_image, p1, p2, current_outline_color, outline_thick, "round")

		# Pass 2: Draw all FILLS
		for path_data in all_paths_render_data:
			var points: Array[Vector2i] = path_data.points
			var fill_thick: int = path_data.fill_thickness
			var base_fill_color: Color = path_data.fill_color
			var seg_start_idx: int = path_data.convoy_seg_start_idx
			var prog_in_seg: float = path_data.progress_in_curr_seg

			for i in range(points.size() - 1):
				var p1: Vector2i = points[i]
				var p2: Vector2i = points[i+1]

				var is_behind: bool = (seg_start_idx != -1 and i < seg_start_idx)
				var is_current: bool = (seg_start_idx != -1 and i == seg_start_idx)

				var current_fill_color = base_fill_color # Default
				var darkened_fill_color = base_fill_color.darkened(trailing_journey_darken_factor)

				if is_behind:
					_draw_line_on_image(map_image, p1, p2, darkened_fill_color, fill_thick)
				elif is_current:
					var split_point = Vector2i(Vector2(p1).lerp(Vector2(p2), prog_in_seg))
					_draw_line_on_image(map_image, p1, split_point, darkened_fill_color, fill_thick)
					if prog_in_seg < 0.999: # If there's an "ahead" part
						_draw_line_on_image(map_image, split_point, p2, current_fill_color, fill_thick)
				else: # Fully ahead or no progress info
					_draw_line_on_image(map_image, p1, p2, current_fill_color, fill_thick)

	# The entire block for 'if p_render_convoys:' and drawing convoys/journey lines is removed.
	
	# --- Hardcoded Line Test (Temporary) ---
	# print("MapRender: Hardcoded line test section reached.") # DEBUG
	# _draw_line_on_image(map_image, Vector2i(10, 10), Vector2i(100, 100), Color.RED, 5)
	# _draw_line_on_image(map_image, Vector2i(10, 100), Vector2i(100, 10), Color.LIME, 3)
	# --- End Hardcoded Line Test ---

	# ConvoyNode instances handle their own drawing.

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
