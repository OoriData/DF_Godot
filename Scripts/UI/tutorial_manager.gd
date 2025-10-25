# Scripts/UI/tutorial_manager.gd
# High-level tutorial coordinator. Lightweight first pass per tutorial_plan.md
extends Node

# --- Signals ---
signal tutorial_started(level: int, step: int)
signal tutorial_step_changed(level: int, step: int)
signal tutorial_finished

# Public toggles
@export var enabled: bool = true
@export var start_level: int = 1

# Node references
var _main_screen: Node = null
var _overlay: Node = null # Scripts/UI/tutorial_overlay.gd instance
var _gdm: Node = null

# Internal state
var _level: int = 0
var _step: int = 0
var _steps: Array = [] # Array of Dictionaries defining steps for current level
var _started: bool = false
var _resolver: Node = null # Scripts/UI/target_resolver.gd instance

# Persistence
const PROGRESS_PATH := "user://tutorial_progress.json"
var _resume_requested: bool = true

# Overlay scope: "map" (default under MapView onboarding layer) or "ui" (full MainScreen)
var _overlay_scope: String = "map"

# Mirror overlay gating enum values for convenience
const GATING_NONE := 0
const GATING_SOFT := 1
const GATING_HARD := 2

# Simple contract (kept tiny for first pass):
# Step schema: { id: String, copy: String, action: String, target: Dictionary }
# action: "message" | "navigate" | "highlight" (future)

func _ready() -> void:
	if not enabled:
		return
	# Cache references
	_main_screen = get_node_or_null("/root/GameRoot/MainScreen")
	_gdm = get_node_or_null("/root/GameDataManager")
	if _gdm:
		if _gdm.has_signal("initial_data_ready"):
			_gdm.connect("initial_data_ready", Callable(self, "_on_initial_data_ready"))
		if _gdm.has_signal("convoy_data_updated"):
			_gdm.connect("convoy_data_updated", Callable(self, "_on_convoy_data_updated"))
	# MenuManager hooks (for event-driven steps)
	var mm := get_node_or_null("/root/MenuManager")
	if mm:
		if mm.has_signal("menu_opened") and not mm.is_connected("menu_opened", Callable(self, "_on_menu_opened")):
			mm.connect("menu_opened", Callable(self, "_on_menu_opened"))
	# Resolver instance
	_resolver = preload("res://Scripts/UI/target_resolver.gd").new()
	add_child(_resolver)
	# Load persisted progress if any
	_load_progress()
	# Do not create overlay yet; only when the tutorial actually starts
	# Try starting after a short defer so MainScreen can show onboarding modal first
	_try_start_deferred()

func _on_initial_data_ready() -> void:
	_maybe_start()

func _on_convoy_data_updated(_all: Array) -> void:
	_maybe_start()

func _emit_started() -> void:
	emit_signal("tutorial_started", _level, _step)

func _emit_changed() -> void:
	emit_signal("tutorial_step_changed", _level, _step)
	if _step >= 0 and _step < _steps.size():
		var step: Dictionary = _steps[_step]
		print("[Tutorial] step:", step.get("id", str(_step)), " action=", step.get("action", "message"), " lock=", step.get("lock", ""))

func _try_start_deferred():
	call_deferred("_maybe_start")

func _maybe_start() -> void:
	if _started or not enabled:
		return
	# Do not start while the first-convoy modal is visible
	if _is_new_convoy_dialog_visible():
		# print("[Tutorial] Waiting for NewConvoyDialog to close before starting…")
		return
	# Start only when the user has at least one convoy
	var has_any_convoys := false
	if _gdm and _gdm.has_method("get_all_convoy_data"):
		var conv = _gdm.get_all_convoy_data()
		has_any_convoys = (conv is Array) and (conv.size() > 0)
	if not has_any_convoys:
		return
	# Initialize and run (prefer external steps if available)
	if _level <= 0:
		_level = start_level
	_steps = _load_steps_for_level(_level)
	_step = 0
	_started = true
	_emit_started()
	_run_current_step()

func _is_new_convoy_dialog_visible() -> bool:
	if _main_screen == null:
		return false
	# Look for the dialog anywhere under the onboarding layer (it may be wrapped in a CenterContainer)
	var layer := _main_screen.get_node_or_null("OnboardingLayer")
	if not is_instance_valid(layer):
		return false
	var dlg := layer.find_child("NewConvoyDialog", true, false)
	return is_instance_valid(dlg) and dlg.visible

func _build_level_steps(level: int) -> Array:
	match level:
		1:
			return [
				{
					id = "l1_intro",
					copy = "Welcome to Desolate Frontiers! This is the very start of your journey.",
					action = "message",
					target = {}
				},
				# placeholders for upcoming steps defined in tutorial_docs.md
				{
					id = "l1_open_convoy_menu",
					copy = "Open the convoy menu using the convoy dropdown in the top bar.",
					action = "highlight",
					target = { resolver = "button_with_text", text_contains = "Convoy" },
					lock = "soft"
				},
				{
					id = "l1_open_settlement",
					copy = "Click the Settlement button to view available vendors.",
					action = "await_settlement_menu",
					target = { resolver = "button_with_text", text_contains = "Settlement" },
					lock = "soft"
				},
				{
					id = "l1_open_dealership",
					copy = "In the settlement, go to the Dealership tab.",
					action = "await_dealership_tab",
					target = { resolver = "tab_title_contains", token = "Dealership" },
					lock = "soft"
				},
				{
					id = "l1_buy_vehicle",
					copy = "Choose one of the available vehicles from the list, then press 'Buy' to purchase it.",
					action = "await_vehicle_purchase",
					# By targeting the whole panel, we create a highlight "hole" for the entire trade UI.
					# The user can now click on items in the list and the buy button.
					target = { resolver = "vendor_trade_panel" },
					lock = "soft"
				},
			]
		2:
			return [
				{ id = "l2_intro", copy = "Let’s plan a journey. Open the Journey menu from your convoy.", action = "message", target = {} },
				{ id = "l2_pick_destination", copy = "Choose a nearby settlement as your destination.", action = "highlight", target = { hint = "map_destinations" } },
				{ id = "l2_review_routes", copy = "Review the suggested route and confirm when ready.", action = "highlight", target = { hint = "route_confirm" } },
			]
		3:
			return [
				{ id = "l3_resources_intro", copy = "Manage your resources: fuel, water, and food.", action = "message", target = {} },
				{ id = "l3_open_settlement", copy = "Visit a settlement and open the Market/Gas tab.", action = "await_settlement_menu", target = {} },
				{ id = "l3_top_up", copy = "Use Top Up to automatically buy what you need.", action = "message", target = {} },
			]
		4:
			return [
				{ id = "l4_parts_intro", copy = "Upgrade vehicles with parts for better performance.", action = "message", target = {} },
				{ id = "l4_open_dealership", copy = "Open the Dealership again to browse parts.", action = "await_dealership_tab", target = { tab_contains = "Dealership" } },
				{ id = "l4_buy_install_hint", copy = "Buy a part and use Install to open Mechanics.", action = "message", target = {} },
			]
		_:
			return []

func _ensure_overlay() -> Node:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	# Ask main_screen for its onboarding layer if available
	var layer: Node = null
	# Prefer the MainScreen's onboarding layer which is already scoped to MapView bounds
	if _main_screen and _main_screen.has_method("get_onboarding_layer"):
		layer = _main_screen.call("get_onboarding_layer")
	elif _main_screen:
		# Fallback to MapView root or MainScreen if accessor missing
		var map_root: Control = _main_screen.get_node_or_null("MainContainer/MainContent/Main")
		layer = map_root if is_instance_valid(map_root) else _main_screen
	if layer == null:
		push_warning("[Tutorial] No host layer for overlay; creating under root")
		layer = get_tree().get_root()
	_overlay = preload("res://Scripts/UI/tutorial_overlay.gd").new()
	layer.add_child(_overlay)
	if layer is Node:
		layer.move_child(_overlay, layer.get_child_count() - 1)
	_overlay_scope = "map"
	# Nudge to top within its parent for safety
	if _overlay and _overlay.has_method("bring_to_front"):
		_overlay.call_deferred("bring_to_front")
	# Ensure it spans full screen
	if _overlay is Control:
		_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Configure safe-area inset based on local parent (MapView has no top bar)
		if _overlay.has_method("set_safe_area_insets"):
			# When overlay sits over MapView, set minimal inset; TopBar is outside.
			_overlay.call("set_safe_area_insets", 8)
		# Log placement for debugging and verify size after layout
		_overlay.call_deferred("_debug_log_placement")
		call_deferred("_verify_overlay_size")
	return _overlay

func _verify_overlay_size() -> void:
	# If the overlay's parent (onboarding layer) hasn't been sized yet, we may be at (0,0).
	# In that case, temporarily reparent to full MainScreen scope so highlights work.
	var ov := _overlay as Control
	var ms: Control = _main_screen as Control
	if ov == null or ms == null:
		return
	var rect := ov.get_global_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		print("[Tutorial] Overlay size is zero; switching to UI scope as a fallback.")
		_attach_overlay_scope("ui")
		# Re-log placement after switching
		ov.call_deferred("_debug_log_placement")

func _configure_overlay_insets_deferred() -> void:
	call_deferred("_configure_overlay_insets")

func _configure_overlay_insets() -> void:
	var ov = _ensure_overlay()
	if ov and ov.has_method("set_safe_area_insets"):
		# Minimal inset because overlay is scoped to MapView area
		ov.call("set_safe_area_insets", 8)

func _run_current_step() -> void:
	if _step < 0 or _step >= _steps.size():
		_emit_finished()
		return
	# --- START DEBUG LOG ---
	# Log the entire step dictionary to verify its contents, especially the 'target'.
	# This will show if it's being overridden by an external JSON file.
	print("[Tutorial][DEBUG] Running step: ", _steps[_step])
	# --- END DEBUG LOG ---
	var step: Dictionary = _steps[_step].duplicate() # Use a copy to allow modification
	var action := String(step.get("action", "message"))
	var id := String(step.get("id", ""))

	# FIX: The external tutorial JSON splits "choose vehicle" and "buy vehicle" into two steps.
	# This causes the highlight of the vendor panel to appear one step too late.
	# To correct this, we'll hijack the "l1_choose_vehicle" step to perform the "await_vehicle_purchase" action.
	# This shows the panel highlight and removes the "Continue" button at the correct time.
	# We also combine the instructional text from the next step, so the user has full context.
	# We then skip the original "l1_buy_vehicle" step, as it becomes redundant.
	if id == "l1_choose_vehicle":
		# Combine copy from the next step ("l1_buy_vehicle") into this one.
		if _step + 1 < _steps.size():
			var next_step: Dictionary = _steps[_step + 1]
			if next_step.get("id", "") == "l1_buy_vehicle":
				step["copy"] = str(step.get("copy", "")) + " " + str(next_step.get("copy", ""))
		# Change the action to be interactive, which also hides the "Continue" button.
		action = "await_vehicle_purchase"
	elif id == "l1_buy_vehicle":
		_advance() # This step's action is now performed by l1_choose_vehicle, so we skip it.
		return

	# FIX: The external tutorial JSON splits "choose vehicle" and "buy vehicle" into two steps.
	# This causes the highlight of the vendor panel to appear one step too late.
	# To correct this, we'll hijack the "l1_choose_vehicle" step to perform the "await_vehicle_purchase" action.
	# This will show the panel highlight at the correct time.
	# We then skip the original "l1_buy_vehicle" step, as it becomes redundant.
	if id == "l1_choose_vehicle":
		action = "await_vehicle_purchase"
	elif id == "l1_buy_vehicle":
		_advance() # This step's action is now performed by l1_choose_vehicle, so we skip it.
		return

	match action:
		"message":
			_show_message(step.get("copy", ""), true)
		"highlight":
			_show_message(step.get("copy", ""), true)
			_apply_lock(step)
			_resolve_and_highlight(step)
		"await_menu_open":
			_show_message(step.get("copy", ""), false)
			_apply_lock(step)
			_resolve_and_highlight(step)
			_awaiting_menu_open = true
		"await_settlement_menu":
			_show_message(step.get("copy", ""), false)
			# Apply lock mode from the step definition before trying to resolve the highlight.
			# This ensures the overlay knows how to behave if resolution fails and needs to retry.
			_apply_lock(step)
			_resolve_and_highlight(step) # highlight Settlement button if target provided
			_watch_for_settlement_menu()
		"await_dealership_tab":
			# First, check if the tab is already open. This is the "fail safe" the user mentioned.
			var tabs := _get_vendor_tab_container()
			if is_instance_valid(tabs):
				var idx := tabs.current_tab
				if idx >= 0:
					var title := tabs.get_tab_title(idx)
					var want := String(step.get("target", {}).get("token", "Dealership"))
					if title.findn(want) != -1:
						# The tab is already open. Defer advance to let UI settle before next step.
						call_deferred("_advance")
						return

			# If the tab is not yet open, proceed with the normal highlight and watch logic.
			_show_message(step.get("copy", ""), false)
			# Apply lock mode before resolving. This is crucial for the overlay to handle
			# resolution retries correctly without blocking the whole screen.
			_apply_lock(step)
			_resolve_and_highlight(step) # try to highlight tab container as a hint
			_hint_dealership_tab(step.get("target", {}))
			_watch_for_dealership_selected(step.get("target", {}))
		"await_vehicle_purchase":
			_show_message(step.get("copy", ""), false)
			_apply_lock(step)
			# --- START FIX ---
			# The goal for this step is ALWAYS to highlight the entire vendor panel to allow free interaction.
			# The log shows that a specific button is being highlighted, which suggests the step's 'target'
			# is being overridden (likely by an external tutorial_steps.json file).
			# To fix this definitively, we will ignore the step's target and force the correct one.
			var corrected_step := step.duplicate(true)
			corrected_step["target"] = { "resolver": "vendor_trade_panel" }
			_resolve_and_highlight(corrected_step)
			# --- END FIX ---
			_watch_for_vehicle_purchase()
		_:
			_show_message(step.get("copy", ""), true)

func _show_message(text: String, show_continue: bool = true) -> void:
	var ov = _ensure_overlay()
	if ov and ov.has_method("show_message"):
		if show_continue:
			ov.call("show_message", text, true, func(): _advance())
		else:
			ov.call("show_message", text, false, Callable())
	else:
		# Fallback if overlay not loaded
		print("[Tutorial] ", text, " [Click to continue]")

func _advance() -> void:
	# Clear any existing highlight before moving on
	if _overlay and is_instance_valid(_overlay):
		if _overlay.has_method("clear_highlight_and_gating"):
			_overlay.call("clear_highlight_and_gating")
		elif _overlay.has_method("clear_highlight"):
			_overlay.call("clear_highlight")
	_step += 1
	_awaiting_menu_open = false
	_save_progress()
	_emit_changed()
	_run_current_step()

func _emit_finished() -> void:
	emit_signal("tutorial_finished")
	# Hide overlay when done (first pass behavior)
	if _overlay and is_instance_valid(_overlay):
		_overlay.call_deferred("queue_free")
		_overlay = null
	# Mark progress complete for this level
	_save_progress(true)

# ---- Internal watchers and helpers ----

func _get_settlement_menu() -> Node:
	# Find an instance of ConvoySettlementMenu anywhere in the tree
	var root := get_tree().get_root()
	if root == null:
		return null
	var found := root.find_child("ConvoySettlementMenu", true, false)
	return found

func _watch_for_settlement_menu() -> void:
	# Poll briefly until the settlement menu appears, then advance.
	var timer := get_tree().create_timer(0.4)
	timer.timeout.connect(func():
		var menu := _get_settlement_menu()
		if is_instance_valid(menu):
			# The menu has appeared. We need to wait for its internal layout to settle
			# before the next step tries to resolve targets within it. Deferring the
			# advance call pushes it to the next idle frame, solving the race condition.
			call_deferred("_advance")
		else:
			_watch_for_settlement_menu()
	)

func _get_vendor_tab_container() -> TabContainer:
	var menu := _get_settlement_menu()
	if not is_instance_valid(menu):
		return null
	var tabs: TabContainer = menu.get_node_or_null("MainVBox/VendorTabContainer")
	return tabs

func _hint_dealership_tab(target: Dictionary) -> void:
	# Respect current step's gating; do not override here.
	# Previously forced HARD which blocked the highlighted tab. Left empty on purpose.
	pass
	# If we ever expand overlay to cover the full UI, we could compute the tab rect and highlight:
	# var menu := _get_settlement_menu(); if is_instance_valid(menu) and menu.has_method("get_vendor_tab_rect_by_title_contains"): ...

func _watch_for_dealership_selected(target: Dictionary) -> void:
	var want := String(target.get("tab_contains", "Dealership"))
	var timer := get_tree().create_timer(0.5)
	timer.timeout.connect(func():
		var tabs := _get_vendor_tab_container()
		if is_instance_valid(tabs):
			var idx := tabs.current_tab
			if idx >= 0:
				var title := tabs.get_tab_title(idx)
				if title.findn(want) != -1:
					# The correct tab is selected. However, the TabContainer needs time to resize
					# its newly visible child (the VendorTradePanel). Advancing immediately, even
					# with call_deferred, can happen before the layout is calculated, causing
					# the highlight resolver to find a zero-sized rectangle.
					# By waiting for the next process_frame, we ensure the layout is stable.
					_advance_after_frame()
					return
		_watch_for_dealership_selected(target)
	)

func _advance_after_frame() -> void:
	# Wait for one full frame to pass. This allows Godot's layout system
	# to update the size and position of newly visible controls.
	print("[Tutorial] Waiting one frame for layout...")
	await get_tree().process_frame
	print("[Tutorial] Waiting a second frame for good measure...")
	await get_tree().process_frame
	print("[Tutorial] Frames waited. Advancing.")
	_advance()

var _vehicle_bought_flag := false

func _watch_for_vehicle_purchase() -> void:
	# Prefer APICalls signal if available; otherwise, observe convoy data updates.
	if not _vehicle_bought_flag:
		var api := get_node_or_null("/root/APICalls")
		if api and api.has_signal("vehicle_bought") and not api.is_connected("vehicle_bought", Callable(self, "_on_vehicle_bought")):
			api.connect("vehicle_bought", Callable(self, "_on_vehicle_bought"))
	# Try to hint the Buy button if present
	_hint_buy_button()
	# Start polling convoy data as a fallback
	_poll_convoy_has_vehicle()

func _on_vehicle_bought(_payload: Dictionary) -> void:
	_vehicle_bought_flag = true
	_advance()

func _poll_convoy_has_vehicle() -> void:
	if _vehicle_bought_flag:
		return
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(func():
		var has_vehicle := false
		if _gdm:
			if _gdm.has_method("get_all_convoy_data"):
				var all: Array = _gdm.get_all_convoy_data()
				if all is Array:
					for c in all:
						if c is Dictionary:
							# Look for common keys that indicate a vehicle presence
							if c.has("vehicles") and c["vehicles"] is Array and c["vehicles"].size() > 0:
								has_vehicle = true
								break
							if c.has("vehicle") and c["vehicle"]:
								has_vehicle = true
								break
		if has_vehicle:
			_vehicle_bought_flag = true
			_advance()
		else:
			_poll_convoy_has_vehicle()
	)

func _get_active_vendor_panel_node() -> Node:
	var tabs := _get_vendor_tab_container()
	if not is_instance_valid(tabs):
		return null
	var idx := tabs.current_tab
	if idx < 0:
		return null
	var container := tabs.get_child(idx) if idx < tabs.get_child_count() else null
	if not is_instance_valid(container):
		return null
	# Look for a VendorTradePanel child
	var panel := container.find_child("VendorTradePanel", true, false)
	return panel

func _hint_buy_button() -> void:
	# Respect current step's gating; do not override here to keep the Buy button clickable.
	pass

# --- Target resolution & highlight helpers ---
var _highlight_timer: SceneTreeTimer = null
var _active_highlight_step: Dictionary = {}
var _awaiting_menu_open: bool = false

func _apply_lock(step: Dictionary) -> void:
	var lock := String(step.get("lock", "soft"))
	match lock:
		"hard":
			print("[Tutorial] gating=HARD for step", step.get("id", ""))
			_gate_map(GATING_HARD)
		"soft":
			print("[Tutorial] gating=SOFT for step", step.get("id", ""))
			_gate_map(GATING_SOFT)
		_:
			print("[Tutorial] gating=NONE for step", step.get("id", ""))
			_gate_map(GATING_NONE)

func _resolve_and_highlight(step: Dictionary) -> bool:
	var ov := _ensure_overlay()
	if ov == null:
		return false
	var target: Dictionary = step.get("target", {})
	if _resolver == null:
		return false
	var res: Dictionary = _resolver.call("resolve", target)
	if res.get("ok", false):
		var node: Node = res.get("node")
		var rect: Rect2 = res.get("rect", Rect2())
		_maybe_switch_overlay_scope_for_rect(rect)
		if ov.has_method("highlight_node"):
			# DEFERRED CALL: Wait until idle time in the current frame for layouts to settle.
			ov.call_deferred("highlight_node", node, rect)
		elif ov.has_method("set_highlight_rect"): # Fallback for safety
			ov.call_deferred("set_highlight_rect", rect)
		print("[Tutorial] Highlight step=", step.get("id", ""), " rect=", rect, " node=", node)
		return true
	else:
		# Guardrail: if not found, clear highlight and downgrade lock after a short delay
		if ov.has_method("clear_highlight"):
			ov.call("clear_highlight")
		print("[Tutorial] Highlight resolve failed for step=", step.get("id", ""), " reason=", res.get("reason", ""))
		# Start/continue retry loop
	_start_highlight_retry(step)
	return false

func _start_highlight_retry(step: Dictionary) -> void:
	_active_highlight_step = step.duplicate(true)
	if _highlight_timer != null:
		return
	_highlight_timer = get_tree().create_timer(0.6, false)
	_highlight_timer.timeout.connect(_on_highlight_retry)

func _on_highlight_retry() -> void:
	_highlight_timer = null
	if _active_highlight_step.is_empty():
		return
	# Re-resolve, but if still failing a few times, relax lock
	var ov := _ensure_overlay()
	var target: Dictionary = _active_highlight_step.get("target", {})
	var res: Dictionary = _resolver.call("resolve", target)
	if res.get("ok", false):
		var node: Node = res.get("node")
		var rect: Rect2 = res.get("rect", Rect2())
		if ov and ov.has_method("highlight_node"):
			# DEFERRED CALL: Wait until idle time for layouts to settle.
			ov.call_deferred("highlight_node", node, rect)
		elif ov and ov.has_method("set_highlight_rect"): # Fallback
			ov.call_deferred("set_highlight_rect", rect)
		# Now that we have a rect, enforce the intended gating level
		var lock := String(_active_highlight_step.get("lock", "soft"))
		match lock:
			"hard":
				_gate_map(GATING_HARD)
			"soft":
				_gate_map(GATING_SOFT)
			_:
				_gate_map(GATING_NONE)
		# Keep trying periodically to follow dynamic UI if it moves; use a faster cadence
		# to quickly catch post-layout repositioning, then the overlay's own per-frame
		# syncing will keep the rect accurate between retries.
		_highlight_timer = get_tree().create_timer(0.4, false)
		_highlight_timer.timeout.connect(_on_highlight_retry)
	else:
		# After two consecutive failures, downgrade lock to avoid player lockout
		var lock := String(_active_highlight_step.get("lock", "soft"))
		if lock == "hard":
			_gate_map(GATING_SOFT)
		# Try again soon in case UI just rebuilt (faster retry to beat layout races)
		_highlight_timer = get_tree().create_timer(0.3, false)
		_highlight_timer.timeout.connect(_on_highlight_retry)

# Scope switching: reparent overlay to cover Map (default) or full UI
func _maybe_switch_overlay_scope_for_rect(rect: Rect2) -> void:
	var ms: Control = _main_screen as Control
	if ms == null:
		return
	var map_host: Control = null
	if _main_screen and _main_screen.has_method("get_onboarding_layer"):
		map_host = _main_screen.call("get_onboarding_layer")
	map_host = map_host if is_instance_valid(map_host) else ms
	var map_rect := map_host.get_global_rect() if map_host is Control else Rect2(Vector2.ZERO, Vector2.ZERO)
	var ui_rect := ms.get_global_rect() if ms is Control else Rect2(Vector2.ZERO, Vector2.ZERO)
	var intersects_map := rect.intersection(map_rect).has_area()
	var want := "map" if intersects_map else "ui"
	print("[Tutorial] Scope pick: target_rect=", rect, " map_rect=", map_rect, " ui_rect=", ui_rect, " -> ", want)
	if want != _overlay_scope:
		_attach_overlay_scope(want)

func _attach_overlay_scope(scope: String) -> void:
	var ov := _ensure_overlay() as Control
	if ov == null:
		return
	var ms: Control = _main_screen as Control
	if ms == null:
		return
	if scope == "map":
		# Parent under onboarding layer (covers MapView area only)
		var host: Control = null
		if _main_screen and _main_screen.has_method("get_onboarding_layer"):
			host = _main_screen.call("get_onboarding_layer")
		host = host if is_instance_valid(host) else ms
		if ov.get_parent() != host:
			if ov.get_parent(): ov.get_parent().remove_child(ov)
			host.add_child(ov)
		host.move_child(ov, host.get_child_count() - 1)
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		if ov.has_method("set_safe_area_insets"):
			ov.call("set_safe_area_insets", 8)
		_overlay_scope = "map"
	else:
		# Parent under full MainScreen to cover full UI; offset below TopBar
		if ov.get_parent() != ms:
			if ov.get_parent(): ov.get_parent().remove_child(ov)
			ms.add_child(ov)
		ms.move_child(ov, ms.get_child_count() - 1)
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		if ov.has_method("set_safe_area_insets"):
			ov.call("set_safe_area_insets", _get_top_bar_inset())
		_overlay_scope = "ui"
	# Ensure on top
	if ov.has_method("bring_to_front"):
		ov.call_deferred("bring_to_front")
	print("[Tutorial] Attached overlay scope=", scope, " parent=", (ov.get_parent().name if ov.get_parent() else "<none>"))

func _get_top_bar_inset() -> int:
	var ms: Control = _main_screen as Control
	if ms == null:
		return 0
	var top: Control = ms.get_node_or_null("MainContainer/TopBar")
	if top:
		return int(round(top.size.y))
	return 0

# --- MenuManager integration ---
func _on_menu_opened(menu_node: Node, menu_type: String) -> void:
	if not _awaiting_menu_open:
		return
	var t := (menu_type if typeof(menu_type) == TYPE_STRING else "")
	var is_convoy := false
	if t.to_lower().find("convoy") != -1:
		is_convoy = true
	elif is_instance_valid(menu_node) and String(menu_node.name).to_lower().find("convoymenu") != -1:
		is_convoy = true
	if is_convoy:
		_advance()

# --- External steps & persistence ---
func _load_steps_for_level(level: int) -> Array:
	# Try JSON from res://Other/tutorial_steps.json
	var path := "res://Other/tutorial_steps.json"
	var txt := ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		txt = f.get_as_text()
		f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		var levels: Dictionary = data as Dictionary
		if levels.has(str(level)) and levels[str(level)] is Array:
			return levels[str(level)]
	# Fallback to built-in
	return _build_level_steps(level)

func _load_progress() -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var obj: Variant = JSON.parse_string(txt)
	if typeof(obj) != TYPE_DICTIONARY:
		return
	var level := int(obj.get("level", 0))
	var step := int(obj.get("step", 0))
	if level > 0:
		_level = level
		_steps = _load_steps_for_level(_level)
		_step = clamp(step, 0, max(0, _steps.size() - 1))

func _save_progress(finished_level: bool = false) -> void:
	var obj := {
		"level": _level,
		"step": _step,
		"finished": finished_level
	}
	var txt := JSON.stringify(obj)
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(txt)
		f.close()

# --- Map gating helpers ---
func _gate_map(mode: int) -> void:
	var ov := _ensure_overlay()
	if ov and ov.has_method("set_gating_mode"):
		ov.call("set_gating_mode", mode)

# Generic: highlight a Control node within the map overlay (only works if node lives under MapView)
func _highlight_node_in_map(node: Node, gating_mode: int = GATING_SOFT) -> void:
	var ov := _ensure_overlay()
	if not ov:
		return
	if ov.has_method("set_highlight_for_node"):
		ov.call("set_highlight_for_node", node, 6)
	if ov.has_method("set_gating_mode"):
		ov.call("set_gating_mode", gating_mode)
	if ov.has_method("bring_to_front"):
		ov.call_deferred("bring_to_front")
