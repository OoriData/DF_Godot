extends RefCounted
class_name VendorPanelInspectorController

# Thin controller for the middle-column inspector UI.
# Owns no nodes; operates on references passed in.

static func update_non_vehicle(
	selected_item: Variant,
	current_mode: String,
	item_name_label: Label,
	item_preview: TextureRect,
	description_panel: VBoxContainer,
	description_toggle_button: Button,
	item_description_rich_text: RichTextLabel,
	item_info_rich_text: RichTextLabel,
	fitment_panel: VBoxContainer,
	fitment_rich_text: RichTextLabel,
	convoy_data: Dictionary,
	compat_cache: Dictionary
) -> void:
	if selected_item == null:
		return

	var item_data_source: Dictionary = {}
	if selected_item is Dictionary and (selected_item as Dictionary).has("item_data"):
		item_data_source = (selected_item as Dictionary).get("item_data", {})
	else:
		item_data_source = selected_item as Dictionary

	if is_instance_valid(item_name_label):
		item_name_label.text = str(item_data_source.get("name", "No Name"))

	var item_icon: Variant = item_data_source.get("icon") if item_data_source.has("icon") else null
	if is_instance_valid(item_preview):
		item_preview.texture = item_icon
		item_preview.visible = item_icon != null

	if is_instance_valid(description_panel):
		description_panel.visible = true

	# Description handling
	var description_text: String = "No description available."
	var base_desc_val: Variant = item_data_source.get("base_desc")
	if is_instance_valid(description_toggle_button):
		description_toggle_button.visible = true
		description_toggle_button.text = "Description (Click to Expand)"
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.visible = false

	if base_desc_val is String and not (base_desc_val as String).is_empty():
		description_text = base_desc_val
	else:
		var desc_val: Variant = item_data_source.get("description")
		if desc_val is String and not (desc_val as String).is_empty():
			description_text = desc_val
		elif desc_val is bool:
			description_text = str(desc_val)

	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.bbcode_enabled = true
		item_description_rich_text.clear()
		item_description_rich_text.parse_bbcode("[color=#C9D1D9]" + description_text + "[/color]")

	# Fitment is suppressed; segmented Fitment is built by VendorInspectorBuilder.
	if is_instance_valid(fitment_rich_text):
		fitment_rich_text.visible = false
	if is_instance_valid(fitment_panel):
		fitment_panel.visible = false

	# Segmented sections are the only inspector rendering for non-vehicles.
	if is_instance_valid(item_info_rich_text):
		item_info_rich_text.bbcode_enabled = true
		item_info_rich_text.clear()
		item_info_rich_text.visible = false

	VendorInspectorBuilder.rebuild_info_sections(
		item_info_rich_text,
		item_data_source,
		selected_item,
		str(current_mode),
		convoy_data,
		compat_cache
	)


static func update_vehicle(panel: Object, vehicle_data: Dictionary) -> void:
	if panel == null:
		return
	if vehicle_data == null or vehicle_data.is_empty():
		return

	if is_instance_valid(panel.item_name_label):
		panel.item_name_label.text = str(vehicle_data.get("name", "No Name"))

	# Vehicles don't have a preview icon, so ensure the preview control is hidden
	# to prevent it from taking up space.
	if is_instance_valid(panel.item_preview):
		panel.item_preview.visible = false

	# --- Description Handling for Vehicles ---
	if is_instance_valid(panel.description_panel):
		panel.description_panel.visible = true

	var description_text: String = "No description available."
	var base_desc_val: Variant = vehicle_data.get("base_desc")
	if is_instance_valid(panel.description_toggle_button):
		panel.description_toggle_button.visible = true
		panel.description_toggle_button.text = "Description (Click to Expand)"
	if is_instance_valid(panel.item_description_rich_text):
		panel.item_description_rich_text.visible = false # Always start collapsed

	if base_desc_val is String and not (base_desc_val as String).is_empty():
		description_text = base_desc_val
	else:
		var desc_val: Variant = vehicle_data.get("description")
		if desc_val is String and not (desc_val as String).is_empty():
			description_text = desc_val

	if is_instance_valid(panel.item_description_rich_text):
		panel.item_description_rich_text.text = description_text

	# Vehicles should render via the segmented/stylized panels only.
	# Keep the legacy RichTextLabel hidden to avoid duplicate plain-text blocks.
	if is_instance_valid(panel.item_info_rich_text):
		panel.item_info_rich_text.bbcode_enabled = true
		panel.item_info_rich_text.clear()
		panel.item_info_rich_text.visible = false

	VendorInspectorBuilder.rebuild_info_sections(
		panel.item_info_rich_text,
		vehicle_data,
		panel.selected_item,
		str(panel.current_mode),
		panel.convoy_data,
		panel._compat_cache
	)
