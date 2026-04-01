@tool
extends Node
class_name ResponsiveListAdapter

## Automatically resizes child Controls of its parent Container when on mobile.
## Add this as a non-visual child to any Container (e.g. VBoxContainer) to make buttons/items taller for touch.

@export var desktop_min_height: float = 0.0 ## If > 0, enforces on desktop too. Useful for testing.
@export var mobile_min_height: float = 70.0 ## Target minimum height for mobile touch targets.
@export var apply_to_children: bool = true ## If true, applies to all children of parent.
@export var recursive: bool = true ## If true, drills down into sub-containers to find Controls.
@export var apply_to_parent: bool = false ## If true, applies directly to the parent's minimum size.
@export var ledger_style: bool = false ## If true, applies a lighter "ledger" background to the node (if it is a container).

func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	var parent = get_parent()
	if parent:
		if _is_mobile() and parent is Container:
			# Reduce separation on mobile to prevent excessive dead space
			if parent.has_theme_constant_override("separation"):
				var current = parent.get_theme_constant("separation")
				parent.add_theme_constant_override("separation", int(current * 0.5))
			elif parent is VBoxContainer or parent is HBoxContainer:
				parent.add_theme_constant_override("separation", 5)

		if apply_to_children:
			_apply_to_existing_children(parent)
			parent.child_entered_tree.connect(_on_parent_child_entered_tree)
		if apply_to_parent and parent is Control:
			_apply_size_to_node(parent, _get_target_height())
		
		if ledger_style and parent is Control:
			_apply_ledger_style(parent)

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.get_name() in ["Android", "iOS"]

func _get_target_height() -> float:
	if _is_mobile():
		return mobile_min_height
	return desktop_min_height

func _apply_to_existing_children(node: Node) -> void:
	var target_h = _get_target_height()
	if target_h <= 0.0:
		return
		
	for child in node.get_children(true):
		_apply_size_to_node(child, target_h)
		if recursive and (child is Container or child is Control):
			_apply_to_existing_children(child)

func _on_parent_child_entered_tree(node: Node) -> void:
	var target_h = _get_target_height()
	if target_h > 0.0:
		# Defer so node fully initializes first, preventing layout constraint overrides from failing immediately
		_apply_size_to_node.call_deferred(node, target_h)
		if recursive and (node is Container or node is Control):
			_apply_to_existing_children.call_deferred(node)

func _apply_size_to_node(node: Node, target_h: float) -> void:
	if node == self or node.has_meta("responsive_scaled"):
		return
	
	if target_h <= 0.0:
		return
	
	node.set_meta("responsive_scaled", true)

	if node is Tree:
		var extra = max(0.0, target_h - 30.0)
		node.add_theme_constant_override("v_separation", int(extra))
	elif node is TabContainer:
		# Increase tab height via content margins in the tab styleboxes
		for style_name in ["tab_selected", "tab_unselected", "tab_disabled", "tab_hovered"]:
			var style = node.get_theme_stylebox(style_name).duplicate()
			if style is StyleBox:
				var margin = (target_h - 24.0) / 2.0 # Assume font is ~24px
				if style is StyleBoxFlat:
					style.content_margin_top = max(style.content_margin_top, margin)
					style.content_margin_bottom = max(style.content_margin_bottom, margin)
					if _is_mobile():
						style.border_width_left = 1
						style.border_width_right = 1
						style.border_width_top = 1
						style.border_color = Color(0.5, 0.5, 0.5, 1.0)
						# Make tabs wider on mobile
						style.content_margin_left = max(style.content_margin_left, 24.0)
						style.content_margin_right = max(style.content_margin_right, 24.0)
						
						if style_name == "tab_selected":
							style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
						else:
							style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
					node.add_theme_stylebox_override(style_name, style)
	elif node is SpinBox:
		# Basic height for touch; width is NOT forced since Godot 4 arrow sizing is done via updown icon
		node.custom_minimum_size.y = target_h
		# Style internal LineEdit color only
		if _is_mobile():
			for child in node.get_children(true):
				if child is LineEdit:
					child.add_theme_color_override("font_color", Color(0.2, 0.7, 1.0))
	
	elif node is Button:
		if node.custom_minimum_size.y < target_h:
			node.custom_minimum_size.y = target_h
		
		if _is_mobile():
			_apply_style_to_button(node)
			# Widen the Back button specifically as requested
			if "Back" in node.name:
				node.custom_minimum_size.x = max(node.custom_minimum_size.x, 300)
				node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	elif node is Control:
		if _is_mobile():
			_apply_large_text(node)
		
		# For non-clickable elements (Labels, etc), DON'T enforce large height to avoid dead space
		# UNLESS it's a specific named element like a Title that needs more room
		if "Title" in node.name or "Header" in node.name:
			node.custom_minimum_size.y = max(node.custom_minimum_size.y, 40)

func _apply_large_text(node: Control) -> void:
	var boost = 1.6 # 60% larger for deep readability on mobile
	if node is Label:
		var fs = node.get_theme_font_size("font_size")
		node.add_theme_font_size_override("font_size", int(fs * boost))
	elif node is RichTextLabel:
		var fs = node.get_theme_font_size("normal_font_size")
		node.add_theme_font_size_override("normal_font_size", int(fs * boost))
		if node.theme_override_font_sizes.has("bold_font_size"):
			node.add_theme_font_size_override("bold_font_size", int(node.get_theme_font_size("bold_font_size") * boost))

func _apply_style_to_button(btn: Button) -> void:
	# Add a subtle background/border to buttons on mobile so they are recognizable touch targets
	var style_types = ["normal", "hover", "pressed", "focus"]
	for st in style_types:
		var style = btn.get_theme_stylebox(st).duplicate()
		if not (style is StyleBoxFlat):
			var new_style = StyleBoxFlat.new()
			# Default dark but distinct color
			new_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
			new_style.border_width_left = 1
			new_style.border_width_right = 1
			new_style.border_width_top = 1
			new_style.border_width_bottom = 1
			new_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
			new_style.corner_radius_top_left = 4
			new_style.corner_radius_top_right = 4
			new_style.corner_radius_bottom_left = 4
			new_style.corner_radius_bottom_right = 4
			new_style.content_margin_left = 10
			new_style.content_margin_right = 10
			btn.add_theme_stylebox_override(st, new_style)
		else:
			# Ensure it's visible
			if style.bg_color.a < 0.2:
				style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.5, 0.5, 0.5, 1.0)
			btn.add_theme_stylebox_override(st, style)

func _apply_ledger_style(node: Control) -> void:
	if not _is_mobile():
		return
	var ledger := StyleBoxFlat.new()
	# "Ledger feel": slightly lighter, muted slate/gray with a border
	ledger.bg_color = Color(0.2, 0.22, 0.25, 0.9)
	ledger.border_width_left = 2
	ledger.border_width_right = 2
	ledger.border_width_top = 2
	ledger.border_width_bottom = 2
	ledger.border_color = Color(0.35, 0.4, 0.45, 1.0)
	ledger.corner_radius_top_left = 6
	ledger.corner_radius_top_right = 6
	ledger.corner_radius_bottom_left = 6
	ledger.corner_radius_bottom_right = 6
	ledger.content_margin_left = 12
	ledger.content_margin_right = 12
	ledger.content_margin_top = 12
	ledger.content_margin_bottom = 12
	
	if node is PanelContainer:
		node.add_theme_stylebox_override("panel", ledger)
	elif node is Panel:
		node.add_theme_stylebox_override("panel", ledger)
	elif node is Container:
		# Containers don't have backgrounds, so we often need to wrap them or just rely on parent
		# but if we are in Godot 4, we can sometimes use a StyleBox on the container if it supports it
		# or just force a background by adding a Panel sibling behind it via script
		var bg := Panel.new()
		bg.name = "LedgerBackground"
		bg.add_theme_stylebox_override("panel", ledger)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(bg)
		node.move_child(bg, 0) # Put in back
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
