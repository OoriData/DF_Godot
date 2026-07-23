extends RefCounted
class_name VendorPanelTutorialController

# Tutorial helper utilities extracted from vendor_trade_panel.gd.
# Keeps tutorial-specific traversal/rect math out of the main panel.

static func get_action_button_node(panel: Object) -> Button:
	return panel.action_button


static func focus_buy_tab(panel: Object) -> void:
	if is_instance_valid(panel.trade_mode_tab_container):
		panel.trade_mode_tab_container.current_tab = 0


static func get_vendor_item_rect_by_text_contains(panel: Object, substr: String) -> Rect2:
	# vendor_item_tree is now a VendorItemList (custom inline-expand list), which exposes a
	# global-rect lookup by row name.
	if not is_instance_valid(panel.vendor_item_tree):
		return Rect2()
	if panel.vendor_item_tree.has_method("find_row_rect_by_text"):
		return panel.vendor_item_tree.find_row_rect_by_text(substr)
	return Rect2()
