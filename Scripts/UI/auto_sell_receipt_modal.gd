# auto_sell_receipt_modal.gd
extends Control

@onready var _item_container: VBoxContainer = %ItemContainer
@onready var _close_button: Button = %CloseButton
@onready var _total_earned_label: Label = %TotalEarnedLabel

func _ready() -> void:
	if is_instance_valid(_close_button):
		_close_button.pressed.connect(_on_close_pressed)

func set_receipt_data(payload: Dictionary) -> void:
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
	row.add_theme_constant_override("separation", 2)
	
	var item_hbox = HBoxContainer.new()
	
	var name_label = Label.new()
	var item_name = item.get("name", item.get("base_name", "Unknown Item"))
	name_label.text = item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 20)
	
	var qty_label = Label.new()
	qty_label.text = "x" + str(item.get("quantity", 1))
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_label.add_theme_font_size_override("font_size", 20)
	
	item_hbox.add_child(name_label)
	item_hbox.add_child(qty_label)
	row.add_child(item_hbox)
	
	# Details (Recipient and Reward)
	var details = Label.new()
	var recipient = item.get("resolved_recipient", item.get("recipient", "Unknown"))
	var reward = item.get("delivery_reward", 0.0)
	details.text = "  To: " + str(recipient) + "  |  Reward: " + str(reward) + " $"
	details.add_theme_color_override("font_color", Color(0.28, 0.72, 0.66)) # Accent color from Tips modal
	details.add_theme_font_size_override("font_size", 14)
	
	row.add_child(details)
	
	# Separator line
	var line = ColorRect.new()
	line.custom_minimum_size.y = 1
	line.color = Color(1, 1, 1, 0.1)
	row.add_child(line)
	
	_item_container.add_child(row)

func _on_close_pressed() -> void:
	queue_free()
