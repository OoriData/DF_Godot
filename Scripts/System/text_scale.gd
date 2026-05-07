extends Node

## Singleton to handle text scaling across different devices and orientations.
## Ensures font sizes don't drop below a readable minimum on mobile.

const MIN_FONT_SIZE_MOBILE = 12

var _nodes = [] # WeakRefs to registered Control nodes

func _ready() -> void:
	# Connect to DeviceStateManager to react to orientation/layout changes
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if dsm:
		if dsm.has_signal("layout_mode_changed"):
			dsm.layout_mode_changed.connect(_on_layout_mode_changed)
	
	# Fallback: connect to viewport resize if dsm is not available or hasn't updated
	get_viewport().size_changed.connect(_update_all)

## Registers a node for automatic scaling.
## Best called from the node's _ready() function.
## @param node: The Label, Button, or RichTextLabel to scale.
## @param base_size: Optional override for the base font size. If -1, captures current size.
func register(node: Control, base_size: int = -1) -> void:
	if not is_instance_valid(node):
		return
	
	# Store the original font size as metadata so we can scale from a clean base
	if not node.has_meta("original_font_size"):
		var actual_base = base_size if base_size != -1 else _get_font_size(node)
		node.set_meta("original_font_size", actual_base)
		
	# Check if already registered
	for ref in _nodes:
		if ref.get_ref() == node:
			_apply_scale_to_node(node)
			return
			
	_nodes.append(weakref(node))
	_apply_scale_to_node(node)

## Recursively registers all Control children of a node for scaling.
## Useful for entire panels or menus.
func register_tree(parent: Node) -> void:
	if not is_instance_valid(parent):
		return
		
	if parent is Control:
		# Check if it's a type we scale
		if parent is Label or parent is Button or parent is RichTextLabel or parent is LineEdit:
			register(parent)
			
	for child in parent.get_children():
		register_tree(child)

func _on_layout_mode_changed(_mode, _screen_size, _is_mobile) -> void:
	_update_all()

func _update_all() -> void:
	var alive_nodes = []
	for ref in _nodes:
		var node = ref.get_ref()
		if node and is_instance_valid(node):
			_apply_scale_to_node(node)
			alive_nodes.append(ref)
	_nodes = alive_nodes

func _apply_scale_to_node(node: Control) -> void:
	if not is_instance_valid(node):
		return
		
	var original_size = node.get_meta("original_font_size", 16)
	var multiplier = 1.0
	var is_mobile_platform = false
	
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if dsm:
		multiplier = dsm.get_font_multiplier()
		is_mobile_platform = dsm.is_mobile
	else:
		# Fallback if DSM is not present
		is_mobile_platform = OS.has_feature("mobile")
		
	var scaled_size = int(round(original_size * multiplier))
	
	# Apply the mobile cap
	if is_mobile_platform:
		scaled_size = max(scaled_size, MIN_FONT_SIZE_MOBILE)
		
	_set_font_size(node, scaled_size)

func _get_font_size(node: Control) -> int:
	if node is Label:
		if node.label_settings:
			return node.label_settings.font_size
		return node.get_theme_font_size("font_size")
	elif node is Button:
		return node.get_theme_font_size("font_size")
	elif node is RichTextLabel:
		return node.get_theme_font_size("normal_font_size")
	elif node is LineEdit:
		return node.get_theme_font_size("font_size")
	return 16 # Default fallback

func _set_font_size(node: Control, size: int) -> void:
	if node is Label:
		if node.label_settings:
			# Duplicating the resource ensures we don't accidentally scale
			# other labels sharing the same resource that weren't registered.
			if not node.has_meta("text_scale_settings_unique"):
				node.label_settings = node.label_settings.duplicate()
				node.set_meta("text_scale_settings_unique", true)
			node.label_settings.font_size = size
		else:
			node.add_theme_font_size_override("font_size", size)
	elif node is Button:
		node.add_theme_font_size_override("font_size", size)
	elif node is RichTextLabel:
		node.add_theme_font_size_override("normal_font_size", size)
	elif node is LineEdit:
		node.add_theme_font_size_override("font_size", size)
