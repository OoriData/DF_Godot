extends CanvasLayer
class_name ResponsiveModalPanel

@export var max_desktop_width: int = 1100
@export var max_desktop_height: int = 950
@export var portrait_margins: int = 0
@export var default_corner_radius: int = 12

var _dsm: Node
var _dim_bg: ColorRect
var _panel: PanelContainer
var _panel_margin: MarginContainer

func _ready() -> void:
	layer = 100 # Draw over normal UI
	visible = false
	
	_dsm = get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(_dsm):
		_dsm.layout_mode_changed.connect(_on_layout_mode_changed)
	
	# Dimmed background to obscure nav text
	_dim_bg = ColorRect.new()
	_dim_bg.color = Color(0, 0, 0, 0.75)
	_dim_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_bg.gui_input.connect(_on_dim_input)
	add_child(_dim_bg) # Added to CanvasLayer root
	
	# Full-screen margin container
	_panel_margin = MarginContainer.new()
	_panel_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_margin) # Added to CanvasLayer root
	
	# The actual popup window
	_panel = PanelContainer.new()
	# By shrinking center natively, we never have to calculate screen bounds Math!
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel_margin.add_child(_panel)
	
	_setup_panel_style()

# Allows sub-classes to safely insert content into the actual window, not the global canvas.
func add_content(node: Node) -> void:
	if is_instance_valid(_panel):
		_panel.add_child(node)
	else:
		push_error("ResponsiveModalPanel: Cannot add content before super._ready() runs.")

func open_modal() -> void:
	_apply_layout()
	visible = true

func close_modal() -> void:
	visible = false

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_modal()
		if has_method("_on_close_pressed"):
			call("_on_close_pressed")

func _on_layout_mode_changed(mode: int, screen_size: Vector2, is_mobile: bool) -> void:
	_setup_panel_style()
	if visible:
		_apply_layout()

func _apply_layout() -> void:
	if not is_instance_valid(_dsm) or not is_instance_valid(_panel):
		return
		
	var mode = _dsm.get_layout_mode()
	# MUST only use get_visible_rect().size because it corresponds to the layout
	# logical coordinates taking 'content_scale_factor' into account! 
	# Using raw DisplayServer window size mixed physical pixels, causing massive ballooning.
	var vp_size = get_viewport().get_visible_rect().size
	var avail_w = int(vp_size.x)
	var avail_h = int(vp_size.y)
	
	if mode == 2: # MOBILE_PORTRAIT
		# Force the panel to have a small buffer so it doesn't clip
		# the screen's rounded corners. ~5% margin does the trick (90% width).
		var margin = int(avail_w * 0.04)
		if margin < 12: margin = 12
		
		_panel_margin.add_theme_constant_override("margin_left", margin)
		_panel_margin.add_theme_constant_override("margin_right", margin)
		_panel_margin.add_theme_constant_override("margin_top", margin + 12) # Extra top breathing room
		_panel_margin.add_theme_constant_override("margin_bottom", int(margin / 2.0))
		
		_panel.size_flags_horizontal = Control.SIZE_FILL
		_panel.size_flags_vertical = Control.SIZE_FILL
		_panel.custom_minimum_size = Vector2.ZERO # Remove limits
	else:
		# Enforce floating max sizes natively
		var float_margin = int(avail_h * 0.05)
		_panel_margin.add_theme_constant_override("margin_left", float_margin)
		_panel_margin.add_theme_constant_override("margin_right", float_margin)
		_panel_margin.add_theme_constant_override("margin_top", float_margin)
		_panel_margin.add_theme_constant_override("margin_bottom", float_margin)
		
		# Shrink to center, allowing margins to act as hard bounds mathematically
		_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		# Define floating modal max size natively through custom_minimum_size acting as limits
		var win_w = min(max_desktop_width, int(avail_w * 0.85))
		var win_h = min(max_desktop_height, int(avail_h * 0.85))
		_panel.custom_minimum_size = Vector2(win_w, win_h)
	
	call_deferred("_refresh_layout")

func _refresh_layout() -> void:
	if is_instance_valid(_panel):
		_panel.queue_sort()
		_panel.queue_redraw()

func _setup_panel_style() -> void:
	if not is_instance_valid(_dsm) or not is_instance_valid(_panel):
		return
	
	var mode = _dsm.get_layout_mode()
	var is_portrait = (mode == 2) # MOBILE_PORTRAIT
	
	# Apply global dynamic font sizing automatically
	var dyn_font_sz = _dsm.get_scaled_base_font_size(16)
	var curr_theme = _panel.theme
	if curr_theme == null:
		curr_theme = Theme.new()
		_panel.theme = curr_theme
	curr_theme.default_font_size = dyn_font_sz
	
	# Force NO background to be drawn by the native panel
	var empty_style = StyleBoxEmpty.new()
	_panel.add_theme_stylebox_override("panel", empty_style)
	
	_setup_background_texture()

func _setup_background_texture() -> void:
	if not is_instance_valid(_panel): return
	var bg = _panel.get_node_or_null("ModalBackground")
	if not is_instance_valid(bg):
		print("[ResponsiveModalPanel] Applying ModalBackground to ", name)
		bg = TextureRect.new()
		bg.name = "ModalBackground"
		bg.texture = load("res://Assets/Themes/Oori Backround.png")
		if bg.texture == null:
			printerr("[ResponsiveModalPanel] ERROR: Failed to load background texture")
			return
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_TILE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(bg)
		_panel.move_child(bg, 0)
	
	# Keep it covering the whole panel area
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
