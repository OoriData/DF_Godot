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
	if not is_instance_valid(panel.vendor_item_tree):
		return Rect2()
	var root: TreeItem = panel.vendor_item_tree.get_root()
	if root == null:
		return Rect2()

	var needle: String = substr.to_lower()
	var found: TreeItem = null
	var q: Array = [root]
	while not q.is_empty():
		var it: TreeItem = q.pop_back()
		if it != null:
			var txt: String = str(it.get_text(0))
			if txt.to_lower().find(needle) != -1:
				found = it
				break
			# enqueue children
			var child := it.get_first_child()
			while child != null:
				q.push_back(child)
				child = child.get_next()

	if found == null:
		return Rect2()

	# Ensure the item is visible (expand parents) so rect is meaningful
	var parent := found.get_parent()
	while parent != null:
		parent.collapsed = false
		parent = parent.get_parent()

	var local_r: Rect2 = panel.vendor_item_tree.get_item_rect(found, 0, false)
	var tree_global: Rect2 = panel.vendor_item_tree.get_global_rect()
	return Rect2(tree_global.position + local_r.position, local_r.size)
