# auto_sell_receipt_modal.gd
extends Control

@onready var _item_container: VBoxContainer = %ItemContainer
@onready var _close_button: Button = %CloseButton
@onready var _total_earned_label: Label = %TotalEarnedLabel

var _current_payload: Dictionary = {}

func _ready() -> void:
	if is_instance_valid(_close_button):
		_close_button.pressed.connect(_on_close_pressed)
	
	_apply_mobile_scaling()
	get_viewport().size_changed.connect(_apply_mobile_scaling)

func _is_portrait() -> bool:
	if is_inside_tree():
		var win_size = get_viewport().get_visible_rect().size
		return win_size.y > win_size.x
	return false

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"] or _is_portrait()

func _get_font_size(base: int) -> int:
	var boost = 2.5 if _is_portrait() else (1.8 if _is_mobile() else 1.2)
	return int(base * boost)

func _apply_mobile_scaling() -> void:
	if not is_inside_tree(): return
	
	var is_port = _is_portrait()
	var win_size = get_viewport().get_visible_rect().size
	
	var panel = $Panel
	if is_port:
		var target_w = int(win_size.x * 0.92) # Much wider for readability
		var target_h = int(win_size.y * 0.8) # Tall but leaves room
		panel.custom_minimum_size = Vector2(target_w, target_h)
		panel.offset_left = -target_w / 2
		panel.offset_right = target_w / 2
		panel.offset_top = -target_h / 2
		panel.offset_bottom = target_h / 2
	else:
		panel.custom_minimum_size = Vector2(min(800, win_size.x - 60), min(700, win_size.y - 60))
	
	$Panel/VBoxContainer/Title.add_theme_font_size_override("font_size", _get_font_size(28))
	%TotalEarnedLabel.add_theme_font_size_override("font_size", _get_font_size(24))
	$Panel/VBoxContainer/InfoLabel.add_theme_font_size_override("font_size", _get_font_size(14))
	
	_close_button.custom_minimum_size = Vector2(320 if is_port else 250, 110 if is_port else 60)
	_close_button.add_theme_font_size_override("font_size", _get_font_size(18))
	
	# Re-render items if we have payload to ensure font sizes update
	if not _current_payload.is_empty():
		set_receipt_data(_current_payload)

func set_receipt_data(payload: Dictionary) -> void:
	_current_payload = payload
	var items = payload.get("items", [])
	var total_credits = payload.get("total_credits", 0.0)
	
	if is_instance_valid(_total_earned_label):
		_total_earned_label.text = "earnings : " + str(total_credits) + "$"
	
	# Clear existing
	for child in _item_container.get_children():
		child.queue_free()
	
	for item in items:
		_add_item_row(item)

func _add_item_row(item: Dictionary) -> void:
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 4 if _is_portrait() else 2)
	
	var item_hbox = HBoxContainer.new()
	
	var name_label = Label.new()
	var item_name = item.get("name", item.get("base_name", "Unknown Item"))
	name_label.text = item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", _get_font_size(18))
	
	var qty_label = Label.new()
	qty_label.text = "x" + str(item.get("quantity", 1))
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_label.add_theme_font_size_override("font_size", _get_font_size(18))
	
	item_hbox.add_child(name_label)
	item_hbox.add_child(qty_label)
	row.add_child(item_hbox)
	
	# Details (Recipient and Reward)
	var details = Label.new()
	var recipient = item.get("resolved_recipient", item.get("recipient", "Unknown"))
	var reward = item.get("delivery_reward", 0.0)
	details.text = "  To: " + str(recipient) + "  |  Reward: " + str(reward) + " $"
	details.add_theme_color_override("font_color", Color(0.28, 0.72, 0.66)) 
	details.add_theme_font_size_override("font_size", _get_font_size(14))
	
	row.add_child(details)
	
	# Separator line
	var line = ColorRect.new()
	line.custom_minimum_size.y = 2 if _is_portrait() else 1
	line.color = Color(1, 1, 1, 0.1)
	row.add_child(line)
	
	_item_container.add_child(row)

func _on_close_pressed() -> void:
	queue_free()
