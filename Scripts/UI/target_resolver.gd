# Scripts/UI/target_resolver.gd
# Resolves tutorial target specs into concrete nodes and highlight rects.
# Designed to be resilient to dynamic UI. Where exact rects are unavailable,
# falls back to the closest stable container control.
extends Node

class_name TutorialTargetResolver

const VENDOR_TRADE_PANEL_SCRIPT_PATH = "res://Scripts/Menus/vendor_trade_panel.gd"

func _safe_get_node(path: String) -> Node:
	if path.is_empty():
		return null
	var n := get_tree().get_root().get_node_or_null(path)
	return n

func resolve(target: Dictionary) -> Dictionary:
	# Returns { ok: bool, node: Node, rect: Rect2, reason: String }
	if target == null:
		return { "ok": false, "node": null, "rect": Rect2(), "reason": "no-target" }

	# Normalize keys
	var kind := String(target.get("resolver", target.get("type", "auto")))
	print("[TutorialResolver] kind=", kind, " target=", target)
	match kind:
		"node_path":
			var r = _resolve_node_path(target)
			_print_resolve_result(kind, r)
			return r
		"tab_title_contains":
			var r = _resolve_vendor_tab_contains(target)
			_print_resolve_result(kind, r)
			return r
		"convoy_return_button":
			# New: highlight the convoy title button in the settlement menu if present,
			# otherwise fall back to the global ConvoyMenuButton in the top bar.
			var r := _resolve_convoy_return_button(target)
			_print_resolve_result(kind, r)
			return r
		"vendor_trade_panel":
			var r = _resolve_vendor_trade_panel(target)
			_print_resolve_result(kind, r)
			return r
		"button_with_text":
			var r = _resolve_button_with_text(target)
			_print_resolve_result(kind, r)
			return r
		"vendor_tree_item_by_text":
			var r = _resolve_vendor_tree_item_by_text(target)
			_print_resolve_result(kind, r)
			return r
		"vendor_action_button":
			var r = _resolve_vendor_action_button(target)
			_print_resolve_result(kind, r)
			return r
		"top_up_button":
			var r = _resolve_top_up_button(target)
			_print_resolve_result(kind, r)
			return r
		"journey_action_button":
			var r = _resolve_journey_action_button(target)
			_print_resolve_result(kind, r)
			return r
		"journey_destination_button":
			var r = _resolve_journey_destination_button(target)
			_print_resolve_result(kind, r)
			return r
		"journey_confirm_button":
			var r = _resolve_journey_confirm_button(target)
			_print_resolve_result(kind, r)
			return r
		"auto":
			# Attempt best-effort common targets
			var r = _resolve_auto(target)
			_print_resolve_result(kind, r)
			return r
		"journey_top_mission_destination":
			# New specialized resolver: pick the first mission destination button (has leading '['cargo']').
			# Falls back to the first destination button if no mission cargo present yet.
			var r := _resolve_journey_top_mission_destination(target)
			_print_resolve_result(kind, r)
			return r
		_:
			return { "ok": false, "node": null, "rect": Rect2(), "reason": "unknown-resolver:" + kind }

func _print_resolve_result(kind: String, r: Dictionary) -> void:
	if r.get("ok", false):
		var node: Node = r.get("node")
		print("[TutorialResolver] OK kind=", kind, " node=", (node.get_path() if node else NodePath("<null>")), " rect=", r.get("rect"))
	else:
		print("[TutorialResolver] FAIL kind=", kind, " reason=", r.get("reason", ""))

func _rect_for_control(ctrl: Control, local_rect: Rect2 = Rect2()) -> Rect2:
	if ctrl == null:
		return Rect2()
	var base := ctrl.get_global_rect()
	if local_rect.size != Vector2.ZERO or local_rect.position != Vector2.ZERO:
		return Rect2(base.position + local_rect.position, local_rect.size)
	return base

func _resolve_node_path(target: Dictionary) -> Dictionary:
	var path := String(target.get("path", ""))
	var node := _safe_get_node(path)
	if node == null:
		return { ok = false, node = null, rect = Rect2(), reason = "node-not-found:" + path }
	var rect := Rect2()
	if node is Control:
		rect = (node as Control).get_global_rect()
	return { ok = true, node = node, rect = rect }

func _get_settlement_menu() -> Node:
	return get_tree().get_root().find_child("ConvoySettlementMenu", true, false)

func _get_journey_menu() -> Node:
	return get_tree().get_root().find_child("ConvoyJourneyMenu", true, false)

func _find_node_by_script(start_node: Node, script_path: String) -> Node:
	var queue = [start_node]
	while not queue.is_empty():
		var current = queue.pop_front()
		if current.get_script() and current.get_script().resource_path == script_path:
			if current is Control and current.is_visible_in_tree():
				return current
		for child in current.get_children():
			queue.append(child)
	return null

func _get_vendor_trade_panel() -> Node:
	var menu := _get_settlement_menu()
	if menu == null:
		return null
	# The active panel is the direct child of the current tab in the TabContainer.
	if menu.has_method("get_active_vendor_panel_node"):
		var panel = menu.call("get_active_vendor_panel_node")
		if is_instance_valid(panel):
			return panel
	# Fallback: search for any visible node with the vendor trade panel script.
	return _find_node_by_script(menu, VENDOR_TRADE_PANEL_SCRIPT_PATH)

func _resolve_vendor_tab_contains(target: Dictionary) -> Dictionary:
	var token := String(target.get("token", target.get("tab_contains", "Dealership")))
	var menu := _get_settlement_menu()
	if menu == null:
		return { ok = false, node = null, rect = Rect2(), reason = "settlement-menu-missing" }
	var tabs: TabContainer = menu.get_node_or_null("MainVBox/VendorTabContainer")
	if tabs == null:
		return { ok = false, node = menu, rect = Rect2(), reason = "vendor-tabs-missing" }
	# Try to resolve to the TabContainer header area (approx.)
	var idx := -1
	for i in range(tabs.get_tab_count()):
		var title := tabs.get_tab_title(i)
		if title.findn(token) != -1:
			idx = i
			break
	if idx == -1:
		return { ok = false, node = tabs, rect = _rect_for_control(tabs), reason = "tab-not-found:" + token }
	# Godot doesn't expose individual tab button rects; return container rect as a fallback
	return { ok = true, node = tabs, rect = _rect_for_control(tabs) }

func _resolve_button_with_text(target: Dictionary) -> Dictionary:
	var token := String(target.get("text_contains", target.get("token", "")))
	if token.is_empty():
		return { ok = false, node = null, rect = Rect2(), reason = "no-token" }

	# Special-case: when searching for the Settlement button, prefer the ConvoyMenu's
	# explicit button node to avoid ambiguous matches and ensure stable rects.
	if token.to_lower().find("settlement") != -1:
		var convoy_menu := get_tree().get_root().find_child("ConvoyMenu", true, false)
		if convoy_menu:
			var btn_path := "MainVBox/ScrollContainer/ContentVBox/MenuButtons/SettlementMenuButton"
			var btn_node := convoy_menu.get_node_or_null(btn_path)
			if btn_node == null:
				# Fallback: search by name anywhere under ConvoyMenu
				btn_node = convoy_menu.find_child("SettlementMenuButton", true, false)
			if btn_node and btn_node is Button:
				var rect_direct := _rect_for_control(btn_node)
				# Guard against unstable/zero rects immediately after menu instantiation
				if not rect_direct.has_area() or rect_direct.position.length_squared() < 1.0:
					return { ok = false, node = btn_node, rect = rect_direct, reason = "unstable-layout-direct" }
				return { ok = true, node = btn_node, rect = rect_direct }
	# Search common menu roots
	var roots := [
		get_tree().get_root().find_child("ConvoySettlementMenu", true, false),
		get_tree().get_root().find_child("ConvoyJourneyMenu", true, false),
		get_tree().get_root().find_child("ConvoyMenu", true, false),
		# Top bar containers
		get_tree().get_root().find_child("UserInfoDisplay", true, false),
		get_tree().get_root().find_child("MainScreen", true, false),
	]
	for r in roots:
		if r == null:
			continue
		var btn := _find_button_with_text(r, token)
		if btn:
			var rect := _rect_for_control(btn)
			# Guard against unstable layouts where the button is found but its rect has no size yet.
			# A rect with no area indicates the layout containers have not positioned it.
			# Failing the resolution here forces the TutorialManager to retry after a short delay.
			# We also check for a near-zero position, which is highly suspect for a dynamically
			# created menu item that has not been placed by its parent container yet.
			if not rect.has_area() or rect.position.length_squared() < 1.0:
				# Failing the resolution here forces the TutorialManager to retry after a short delay,
				# giving the layout engine time to work.
				return { ok = false, node = btn, rect = rect, reason = "unstable-layout" }
			return { ok = true, node = btn, rect = rect }
	# Fallback: global search for any visible Button containing token; pick the top-most (smallest y)
	var best_btn: Button = null
	var best_y := INF
	var root_node := get_tree().get_root()
	var queue := [root_node]
	while queue.size() > 0:
		var n: Node = queue.pop_back()
		if n is Button:
			var b: Button = n
			if b.is_visible_in_tree() and b.text.findn(token) != -1:
				var rect := b.get_global_rect()
				if rect.position.y < best_y:
					best_y = rect.position.y
					best_btn = b
		for c in n.get_children():
			queue.push_front(c)
	if best_btn != null:
		var rect := _rect_for_control(best_btn)
		# Also apply unstable layout check to the fallback result.
		if not rect.has_area() or rect.position.length_squared() < 1.0:
			return { ok = false, node = best_btn, rect = rect, reason = "unstable-layout-fallback" }
		return { ok = true, node = best_btn, rect = rect }

	return { ok = false, node = null, rect = Rect2(), reason = "button-not-found:" + token }

func _find_button_with_text(root: Node, token: String) -> Button:
	if root is Button:
		var b: Button = root
		if b.text.findn(token) != -1:
			return b
	for c in root.get_children():
		var found := _find_button_with_text(c, token)
		if found:
			return found
	return null

func _resolve_vendor_tree_item_by_text(target: Dictionary) -> Dictionary:
	var token := String(target.get("text_contains", target.get("token", "")))
	var panel := _get_vendor_trade_panel()
	if panel == null:
		return { ok = false, node = null, rect = Rect2(), reason = "vendor-panel-missing" }
	var tree: Tree = panel.get_node_or_null("%VendorItemTree")
	if tree == null:
		return { ok = false, node = panel, rect = _rect_for_control(panel), reason = "vendor-tree-missing" }
	var item := _find_tree_item_contains(tree, token)
	if item == null:
		return { ok = false, node = tree, rect = _rect_for_control(tree), reason = "tree-item-not-found:" + token }
	var area := tree.get_item_area_rect(item, 0)
	return { ok = true, node = tree, rect = _rect_for_control(tree, area) }

func _find_tree_item_contains(tree: Tree, token: String) -> TreeItem:
	var root := tree.get_root()
	if root == null:
		return null
	var stack := [root]
	while stack.size() > 0:
		var it: TreeItem = stack.pop_back()
		for col in range(tree.columns):
			var txt := String(it.get_text(col))
			if txt.findn(token) != -1:
				return it
		var child := it.get_first_child()
		while child:
			stack.push_back(child)
			child = child.get_next()
	return null

func _resolve_vendor_action_button(target: Dictionary) -> Dictionary:
	var which := String(target.get("which", "buy")) # buy|max|install|action
	var panel := _get_vendor_trade_panel()
	if panel == null:
		return { ok = false, node = null, rect = Rect2(), reason = "vendor-panel-missing" }
	var btn: Control = null
	match which:
		"buy", "action":
			btn = panel.get_node_or_null("%ActionButton")
		"max":
			btn = panel.get_node_or_null("%MaxButton")
		"install":
			btn = panel.get_node_or_null("%InstallButton")
		_:
			btn = panel.get_node_or_null("%ActionButton")
	if btn == null:
		return { ok = false, node = panel, rect = _rect_for_control(panel), reason = "vendor-action-btn-missing:" + which }
	return { ok = true, node = btn, rect = _rect_for_control(btn) }

# New resolver: convoy_return_button
# Highlights the convoy name button inside the settlement menu (TitleLabel) if present;
# otherwise falls back to the global ConvoyMenuButton in the MainScreen top bar.
func _resolve_convoy_return_button(_target: Dictionary) -> Dictionary:
	# Primary: settlement menu title button
	var settlement_menu := get_tree().get_root().find_child("ConvoySettlementMenu", true, false)
	if is_instance_valid(settlement_menu):
		var title_btn: Button = settlement_menu.get_node_or_null("MainVBox/TopBarHBox/TitleLabel")
		if is_instance_valid(title_btn):
			var rect := _rect_for_control(title_btn)
			if rect.has_area():
				return { ok = true, node = title_btn, rect = rect }
			return { ok = false, node = title_btn, rect = rect, reason = "unstable-title-btn-rect" }

	# Fallback: top bar convoy menu button
	var main_screen := get_tree().get_root().find_child("MainScreen", true, false)
	if is_instance_valid(main_screen):
		var convoy_btn := main_screen.find_child("ConvoyMenuButton", true, false)
		if is_instance_valid(convoy_btn) and convoy_btn is Control:
			var rect2 := _rect_for_control(convoy_btn)
			if rect2.has_area():
				return { ok = true, node = convoy_btn, rect = rect2 }
			return { ok = false, node = convoy_btn, rect = rect2, reason = "unstable-convoy-menu-btn-rect" }

	return { ok = false, node = null, rect = Rect2(), reason = "convoy-return-button-not-found" }

func _resolve_top_up_button(_target: Dictionary) -> Dictionary:
	var menu := _get_settlement_menu()
	if not is_instance_valid(menu):
		return { ok = false, node = null, rect = Rect2(), reason = "settlement-menu-missing" }
	
	var btn: Button = menu.get_node_or_null("MainVBox/TopBarHBox/TopUpButton")
	if not is_instance_valid(btn):
		return { ok = false, node = menu, rect = _rect_for_control(menu), reason = "top-up-button-not-found" }
	
	var rect := _rect_for_control(btn)
	if not rect.has_area():
		return { ok = false, node = btn, rect = rect, reason = "unstable-layout" }
	
	return { ok = true, node = btn, rect = rect }

func _resolve_journey_action_button(target: Dictionary) -> Dictionary:
	var token := String(target.get("text_contains", target.get("token", "Embark")))
	var menu := _get_journey_menu()
	if menu == null:
		return { ok = false, node = null, rect = Rect2(), reason = "journey-menu-missing" }
	var btn := _find_button_with_text(menu, token)
	if btn == null:
		return { ok = false, node = menu, rect = _rect_for_control(menu), reason = "journey-btn-not-found:" + token }
	return { ok = true, node = btn, rect = _rect_for_control(btn) }

func _resolve_journey_destination_button(target: Dictionary) -> Dictionary:
	var token := String(target.get("text_contains", ""))
	var menu := _get_journey_menu()
	if not is_instance_valid(menu):
		return { ok = false, node = null, rect = Rect2(), reason = "journey-menu-missing" }

	var content_vbox: VBoxContainer = menu.get_node_or_null("MainVBox/ScrollContainer/ContentVBox")
	if not is_instance_valid(content_vbox):
		return { ok = false, node = menu, rect = _rect_for_control(menu), reason = "journey-menu-content-missing" }

	var found_button: Button = null
	var needle := token.to_lower()

	for child in content_vbox.get_children():
		if child is Button:
			var b := child as Button
			if b.text == "Back": continue # Skip back button

			if token.is_empty(): # if no token, find first button that is not "Back"
				found_button = b
				break
			
			var txt := String(b.text).to_lower()
			if txt.find(needle) != -1:
				found_button = b
				break
	
	if not is_instance_valid(found_button):
		return { ok = false, node = menu, rect = _rect_for_control(menu), reason = "destination-button-not-found:" + token }

	var rect := _rect_for_control(found_button)
	if not rect.has_area():
		return { ok = false, node = found_button, rect = rect, reason = "unstable-layout" }
	
	return { ok = true, node = found_button, rect = rect }

func _resolve_journey_confirm_button(_target: Dictionary) -> Dictionary:
	var menu := _get_journey_menu()
	if not is_instance_valid(menu):
		return { ok = false, node = null, rect = Rect2(), reason = "journey-menu-missing" }
	
	if not menu.has_method("get_confirm_button_node"):
		return { ok = false, node = menu, rect = _rect_for_control(menu), reason = "journey-menu-missing-helper" }
	
	var btn: Button = menu.call("get_confirm_button_node")
	if not is_instance_valid(btn):
		return { ok = false, node = menu, rect = _rect_for_control(menu), reason = "journey-confirm-button-not-found" }
	
	var rect := _rect_for_control(btn)
	if not rect.has_area():
		return { ok = false, node = btn, rect = rect, reason = "unstable-layout" }
	
	return { ok = true, node = btn, rect = rect }

# New: resolve first mission destination (button text starts with '[') or fallback to first destination button.
func _resolve_journey_top_mission_destination(_target: Dictionary) -> Dictionary:
	var menu := _get_journey_menu()
	if not is_instance_valid(menu):
		return { ok = false, node = null, rect = Rect2(), reason = "journey-menu-missing" }

	var content_vbox: VBoxContainer = menu.get_node_or_null("MainVBox/ScrollContainer/ContentVBox")
	if not is_instance_valid(content_vbox):
		return { ok = false, node = menu, rect = _rect_for_control(menu), reason = "journey-menu-content-missing" }

	var mission_btn: Button = null
	var first_btn: Button = null
	for child in content_vbox.get_children():
		if child is Button:
			var b := child as Button
			if b.text == "Back":
				continue
			if first_btn == null:
				first_btn = b
			if b.text.begins_with("[") and b.text.find("]") != -1:
				mission_btn = b
				break

	var chosen := mission_btn if mission_btn != null else first_btn
	if chosen == null:
		return { ok = false, node = content_vbox, rect = _rect_for_control(content_vbox), reason = "no-destination-buttons" }

	var rect := _rect_for_control(chosen)
	if not rect.has_area():
		return { ok = false, node = chosen, rect = rect, reason = "unstable-destination-rect" }
	return { ok = true, node = chosen, rect = rect }

func _resolve_auto(target: Dictionary) -> Dictionary:
	# Heuristics based on provided hints
	if target.has("tab_contains") or target.get("token", "").findn("Dealership") != -1:
		return _resolve_vendor_tab_contains(target)
	if String(target.get("hint", "")).findn("buy") != -1:
		return _resolve_vendor_action_button({ which = "buy" })
	if String(target.get("hint", "")).findn("max") != -1:
		return _resolve_vendor_action_button({ which = "max" })
	return { ok = false, node = null, rect = Rect2(), reason = "auto-no-match" }

func _resolve_vendor_trade_panel(_target: Dictionary) -> Dictionary:
	var panel := _get_vendor_trade_panel()
	if not is_instance_valid(panel):
		return { ok = false, node = null, rect = Rect2(), reason = "vendor-trade-panel-not-found" }
	if not panel is Control:
		return { ok = false, node = panel, rect = Rect2(), reason = "vendor-trade-panel-not-a-control" }
	
	# --- START DEBUG LOGS ---
	print("  [DEBUG][resolve_vendor_trade_panel] Found panel: ", panel.name, " path: ", panel.get_path())
	print("  [DEBUG][resolve_vendor_trade_panel] Panel visible in tree: ", panel.is_visible_in_tree())
	var rect := (panel as Control).get_global_rect()
	print("  [DEBUG][resolve_vendor_trade_panel] Panel global_rect: ", rect)
	# --- END DEBUG LOGS ---

	# Guard against unstable layouts where the panel is found but its rect has no size yet,
	# or it's at a near-zero position which is highly suspect for a dynamically placed UI element.
	# Failing the resolution forces the TutorialManager to retry after a short delay,
	# giving the layout engine time to work.
	if not rect.has_area() or rect.position.length_squared() < 1.0:
		var reason := "vendor-trade-panel-unstable-layout (size=" + str(rect.size) + " pos=" + str(rect.position) + ")"
		return { ok = false, node = panel, rect = rect, reason = reason }

	return { ok = true, node = panel, rect = rect }
