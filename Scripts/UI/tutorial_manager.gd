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
var _initial_vehicle_count := -1
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

# --- Polling state for _process ---
var _is_polling_for_tab: bool = false
var _polling_tab_target: Dictionary = {}
var _polling_tab_timer: float = 0.0
const _POLL_TAB_INTERVAL: float = 0.5
var _awaiting_menu_open: bool = false

var _supply_checklist_state: Dictionary = { "mre": false, "water": false }

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
	# Resolver instance (using class_name)
	_resolver = TutorialTargetResolver.new()
	add_child(_resolver)
	# Load persisted progress if any
	_load_progress()
	# Do not create overlay yet; only when the tutorial actually starts
	# Try starting after a short defer so MainScreen can show onboarding modal first
	_try_start_deferred()

func _process(delta: float) -> void:
	if _is_polling_for_tab:
		_polling_tab_timer -= delta
		if _polling_tab_timer <= 0.0:
			_polling_tab_timer = _POLL_TAB_INTERVAL
			_check_for_tab_selected_poll()

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

func _get_total_vehicle_count() -> int:
	var count := 0
	if not is_instance_valid(_gdm) or not _gdm.has_method("get_all_convoy_data"):
		return -1 # Indicate data not available
	var all_convoys: Array = _gdm.get_all_convoy_data()
	if not (all_convoys is Array):
		return -1

	for c in all_convoys:
		if c is Dictionary:
			# The augmented data uses 'vehicle_details_list'
			if c.has("vehicle_details_list") and c["vehicle_details_list"] is Array:
				count += c["vehicle_details_list"].size()
	return count
	
func get_current_level() -> int:
	return _level

func _try_start_deferred():
	call_deferred("_maybe_start")

func _maybe_start() -> void:
	if _started or not enabled:
		return
	# Do not start while the first-convoy modal is visible
	if _is_new_convoy_dialog_visible():
		# print("[Tutorial] Waiting for NewConvoyDialog to close before starting…")
		return
	# Start only when the user has at least one convoy.
	var has_any_convoys := false
	if _gdm and _gdm.has_method("get_all_convoy_data"):
		var conv = _gdm.get_all_convoy_data()
		has_any_convoys = (conv is Array) and (conv.size() > 0)
	if not has_any_convoys:
		return

	# Sync level from server if available, otherwise use local progress or default.
	var server_level := -1
	if is_instance_valid(_gdm) and _gdm.has_method("get_current_user_data"):
		var user_data: Dictionary = _gdm.get_current_user_data()
		if user_data.has("metadata") and user_data.metadata is Dictionary:
			var metadata: Dictionary = user_data.metadata
			if metadata.has("tutorial"):
				var tutorial_val = metadata.get("tutorial")
				if tutorial_val is int or tutorial_val is float:
					server_level = int(tutorial_val)

	if server_level > 0:
		# Server state is the source of truth.
		_level = server_level
		_step = 0 # Always start at the beginning of a level
		print("[Tutorial] Starting from server-defined level: ", _level)
	elif _level <= 0:
		# No server state, no local progress file loaded, use default.
		_level = start_level
		print("[Tutorial] Starting from default level: ", _level)
	# else: use _level loaded from local file.

	_steps = _load_steps_for_level(_level)
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
					action = "await_menu_open",
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
		2: # Resources
			return [
				{
					id = "l2_open_market_tab",
					copy = "Now that you have a vehicle, you'll need supplies for the road. Go to the Market tab to purchase some essential items.",
					action = "await_market_tab",
					target = { resolver = "tab_title_contains", token = "Market" },
					lock = "soft"
				},
				{
					id = "l2_buy_supplies",
					copy = "Purchase 2 MRE Boxes and 2 Water Jerry Cans. You can select an item to see its details and choose a quantity to buy.",
					action = "await_supply_purchase",
					target = { resolver = "vendor_trade_panel" },
					lock = "soft"
				},
				{
					id = "l2_top_up_tip",
					copy = "Great! For future reference, you can also use the 'Top Up' button as a shortcut to automatically fill resource containers.",
					action = "message", # Just a message, no action needed.
					target = { resolver = "top_up_button" }, # Highlight it for context
				},
			]
		3: # Journey Planning
			return [
				{
					id = "l3_open_journey_menu",
					copy = "Great! You're stocked up. Now, let's plan a journey. Open the Journey menu from your convoy overview.",
					action = "highlight",
					target = { resolver = "button_with_text", text_contains = "Journey" },
					lock = "soft"
				},
				{
					id = "l3_pick_destination",
					copy = "Choose a nearby settlement as your destination.",
					action = "highlight",
					target = { resolver = "journey_destination_button" },
					lock = "soft"
				},
				{
					id = "l3_review_routes",
					copy = "Review the suggested route and confirm when ready.",
					action = "highlight",
					target = { resolver = "journey_confirm_button" },
					lock = "soft"
				},
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

	# Decide whether to lock or unlock vendor tabs for this step.
	# This prevents the user from switching to other vendor tabs (e.g., Market)
	# before the tutorial allows it.
	var lock_tabs_for_actions := [
		"await_dealership_tab",
		"await_vehicle_purchase",
		"await_market_tab",
		"await_supply_purchase"
	]
	if action in lock_tabs_for_actions:
		_lock_vendor_tabs(step)
	else:
		_unlock_vendor_tabs()

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
					var title := tabs.get_tab_title(idx).to_lower()
					var want := String(step.get("target", {}).get("token", "Dealership")).to_lower()
					# Make the pre-check case-insensitive to match the watcher.
					if title.find(want) != -1:
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
			_watch_for_tab_selected(step.get("target", {}))
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
		"await_market_tab":
			# This logic mirrors `await_dealership_tab` for consistency, as requested.
			# It checks if the tab is already open, and if not, highlights the tab area and waits.
			var tabs := _get_vendor_tab_container()
			if is_instance_valid(tabs):
				var idx := tabs.current_tab
				if idx >= 0:
					var title := tabs.get_tab_title(idx).to_lower()
					var want := String(step.get("target", {}).get("token", "Market")).to_lower()
					#// --- START LOGGING ---
					var all_titles: Array = []
					for i in range(tabs.get_tab_count()): all_titles.append(tabs.get_tab_title(i))
					print("[Tutorial][Pre-check] Checking if market tab is open. Want: '%s', Current: '%s'. All: %s" % [want, title, all_titles])
					#// --- END LOGGING ---
					if title.find(want) != -1:
						# The tab is already open. Defer advance to let UI settle.
						print("[Tutorial] Market tab already open, advancing.")
						call_deferred("_advance")
						return

			_show_message(step.get("copy", ""), false)
			_apply_lock(step)
			_resolve_and_highlight(step)
			_watch_for_tab_selected(step.get("target", {}))
		"await_supply_purchase":
			# Message is now shown via _update_supply_purchase_ui inside the watcher
			_apply_lock(step)
			var corrected_step := step.duplicate(true)
			corrected_step["target"] = { "resolver": "vendor_trade_panel" }
			_resolve_and_highlight(corrected_step)
			_watch_for_supply_purchase()
		"await_top_up":
			_show_message(step.get("copy", ""), false)
			_apply_lock(step)
			_resolve_and_highlight(step)
			_watch_for_top_up()
		_:
			_show_message(step.get("copy", ""), true)

func _show_message(text: String, show_continue: bool = true) -> void:
	var ov = _ensure_overlay()
	if ov and ov.has_method("show_message"):
		if show_continue:
			ov.call("show_message", text, true, func(): _advance(), [])
		else:
			ov.call("show_message", text, false, Callable(), [])
	else:
		# Fallback if overlay not loaded
		print("[Tutorial] ", text, " [Click to continue]")

func _advance() -> void:
	_clear_highlight()

	# Stop any active polling
	if _is_polling_for_tab:
		_is_polling_for_tab = false
		set_process(false)

	_step += 1
	_awaiting_menu_open = false
	_save_progress()
	_emit_changed()
	_run_current_step()

func _clear_highlight() -> void:
	# Clear any existing highlight before moving on
	if _overlay and is_instance_valid(_overlay):
		if _overlay.has_method("clear_highlight_and_gating"):
			_overlay.call("clear_highlight_and_gating")
		elif _overlay.has_method("clear_highlight"):
			_overlay.call("clear_highlight")

func _emit_finished() -> void:
	emit_signal("tutorial_finished")

	# Update backend and advance to next level
	if is_instance_valid(_gdm) and _gdm.has_method("update_user_tutorial_stage"):
		_gdm.call_deferred("update_user_tutorial_stage", _level + 1)

	# Advance to the next level
	_level += 1
	_steps = _load_steps_for_level(_level)
	_step = 0
	_save_progress() # Save progress for the new level

	if _steps.is_empty():
		# No more tutorial levels, truly finish
		if _overlay and is_instance_valid(_overlay):
			_overlay.call_deferred("queue_free")
			_overlay = null
		_save_progress(true) # Mark as fully finished
		print("[Tutorial] All tutorial levels completed.")
	else:
		# Start the next level after a short delay to allow UI to settle
		print("[Tutorial] Advancing to level ", _level)
		var timer := get_tree().create_timer(1.5, true) # Increased delay for safety
		timer.timeout.connect(func():
			_started = true
			_emit_started()
			_run_current_step()
		)

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
	# More robustly get the tab container by accessing the menu's own @onready variable
	# rather than relying on a hardcoded scene path.
	if menu.has_method("get") and "vendor_tab_container" in menu:
		var tabs = menu.get("vendor_tab_container")
		if tabs is TabContainer:
			return tabs
	# Fallback to the old path for safety
	return menu.get_node_or_null("MainVBox/VendorTabContainer")

func _watch_for_tab_selected(target: Dictionary) -> void:
	# This function now starts a polling loop within the _process function,
	# which is more robust than using SceneTreeTimers that might fail in a paused tree.
	var want := String(target.get("token", "Dealership")).to_lower()
	print("[Tutorial][Watcher] Started. Will poll for tab containing '%s'." % want)
	_is_polling_for_tab = true
	_polling_tab_target = target
	_polling_tab_timer = 0.0 # Check immediately on the next process frame
	set_process(true)

func _check_for_tab_selected_poll() -> void:
	var target := _polling_tab_target
	var want := String(target.get("token", "Dealership")).to_lower()

	print("[Tutorial][Watcher] Polling...")
	var tabs := _get_vendor_tab_container()
	if not is_instance_valid(tabs):
		print("  - FAILED: _get_vendor_tab_container() returned an invalid node.")
		return

	var idx := tabs.current_tab
	if idx < 0:
		print("  - INFO: No tab selected (index is %d)." % idx)
		return

	var current_title_raw := tabs.get_tab_title(idx)
	var current_title_lower := current_title_raw.to_lower()
	var all_titles: Array = []
	for i in range(tabs.get_tab_count()): all_titles.append(tabs.get_tab_title(i))

	print("  - Polling for tab title containing: '%s'" % want)
	print("  - Current tab index: %d" % idx)
	print("  - Current tab title (raw): '%s'" % current_title_raw)
	print("  - All available tab titles: %s" % all_titles)

	if current_title_lower.find(want) != -1:
		print("[Tutorial][Watcher] Match found! Advancing step.")
		_advance_after_frame()

func _advance_after_frame() -> void:
	# Wait for one full frame to pass. This allows Godot's layout system
	# to update the size and position of newly visible controls.
	print("[Tutorial] Waiting one frame for layout...")
	await get_tree().process_frame
	print("[Tutorial] Waiting a second frame for good measure...")
	await get_tree().process_frame
	print("[Tutorial] Frames waited. Advancing.")
	_advance()

var _top_up_button_ref: Button = null

func _watch_for_top_up() -> void:
	var menu := _get_settlement_menu()
	if not is_instance_valid(menu):
		call_deferred("_watch_for_top_up")
		return

	_top_up_button_ref = menu.get_node_or_null("MainVBox/TopBarHBox/TopUpButton")
	if is_instance_valid(_top_up_button_ref) and not _top_up_button_ref.is_connected("pressed", Callable(self, "_on_top_up_pressed")):
		_top_up_button_ref.pressed.connect(Callable(self, "_on_top_up_pressed"), CONNECT_ONE_SHOT)
	else:
		# Retry if button not found yet
		var timer := get_tree().create_timer(0.5, true)
		timer.timeout.connect(func(): _watch_for_top_up())

func _on_top_up_pressed() -> void:
	_top_up_button_ref = null
	_advance()
func _watch_for_supply_purchase() -> void:
	if not is_instance_valid(_gdm):
		printerr("[Tutorial] GDM not valid, cannot watch for supply purchase.")
		return
	
	# Reset checklist state at the beginning of the step
	_supply_checklist_state = {"mre": false, "water": false}

	# Connect to the signal that fires after convoy data is updated post-transaction
	if not _gdm.is_connected("convoy_data_updated", Callable(self, "_on_supply_check")):
		_gdm.convoy_data_updated.connect(Callable(self, "_on_supply_check"))
	
	# Also do an initial check and UI update in case the items are already there
	if _gdm.has_method("get_all_convoy_data"):
		_on_supply_check(_gdm.get_all_convoy_data())

func _on_supply_check(_all_convoys: Array) -> void:
	# This function is now connected. Check if the current step is the one we care about.
	if _step < 0 or _step >= _steps.size() or _steps[_step].get("action") != "await_supply_purchase":
		if is_instance_valid(_gdm) and _gdm.is_connected("convoy_data_updated", Callable(self, "_on_supply_check")):
			_gdm.disconnect("convoy_data_updated", Callable(self, "_on_supply_check"))
		return

	if not is_instance_valid(_gdm):
		return

	var current_convoy: Dictionary
	if not _all_convoys.is_empty():
		current_convoy = _all_convoys[0]
	else:
		_update_supply_purchase_ui(0, 0)
		return

	var mre_count := 0
	var water_count := 0

	var cargo_list: Array = []
	if current_convoy.has("vehicle_details_list") and current_convoy.vehicle_details_list is Array:
		for vehicle in current_convoy.vehicle_details_list:
			if vehicle.has("cargo") and vehicle.cargo is Array:
				cargo_list.append_array(vehicle.cargo)
	elif current_convoy.has("cargo_inventory") and current_convoy.cargo_inventory is Array:
		cargo_list = current_convoy.cargo_inventory

	for item in cargo_list:
		if not (item is Dictionary): continue
		var item_name := String(item.get("name", "")).to_lower()
		var quantity := int(item.get("quantity", 0))

		# Make matching more robust
		if item_name.contains("mre"):
			mre_count += quantity
		elif item_name.contains("water") and item_name.contains("jerry"):
			water_count += quantity
	
	_update_supply_purchase_ui(mre_count, water_count)

	if mre_count >= 2 and water_count >= 2:
		if is_instance_valid(_gdm) and _gdm.is_connected("convoy_data_updated", Callable(self, "_on_supply_check")):
			_gdm.disconnect("convoy_data_updated", Callable(self, "_on_supply_check"))
		call_deferred("_advance")

func _update_supply_purchase_ui(mre_count: int, water_count: int) -> void:
	if _step < 0 or _step >= _steps.size() or _steps[_step].get("action") != "await_supply_purchase":
		return

	var step: Dictionary = _steps[_step]
	var copy = step.get("copy", "")

	var mre_needed = 2
	var water_needed = 2

	_supply_checklist_state.mre = mre_count >= mre_needed
	_supply_checklist_state.water = water_count >= water_needed

	var checklist_items = [
		{ "text": "MRE Boxes (%d / %d)" % [min(mre_count, mre_needed), mre_needed], "completed": _supply_checklist_state.mre },
		{ "text": "Water Jerry Cans (%d / %d)" % [min(water_count, water_needed), water_needed], "completed": _supply_checklist_state.water }
	]

	var ov = _ensure_overlay()
	if ov and ov.has_method("show_message"):
		ov.call("show_message", copy, false, Callable(), checklist_items)

func _watch_for_vehicle_purchase() -> void:
	# Get initial vehicle count to detect when a new one is added.
	_initial_vehicle_count = _get_total_vehicle_count()
	print("[Tutorial] Watching for vehicle purchase. Initial vehicle count: ", _initial_vehicle_count)

	if not is_instance_valid(_gdm):
		printerr("[Tutorial] GDM not valid, cannot watch for vehicle purchase.")
		return
	
	# Connect to the signal that fires after convoy data is updated post-transaction.
	# This is more efficient than polling.
	if not _gdm.is_connected("convoy_data_updated", Callable(self, "_on_convoy_updated_for_vehicle_check")):
		_gdm.convoy_data_updated.connect(Callable(self, "_on_convoy_updated_for_vehicle_check"))

	# Try to hint the Buy button if present
	_hint_buy_button()

func _on_convoy_updated_for_vehicle_check(_all_convoys: Array) -> void:
	# Check if this is the correct tutorial step.
	if _step < 0 or _step >= _steps.size() or _steps[_step].get("action") != "await_vehicle_purchase":
		if is_instance_valid(_gdm) and _gdm.is_connected("convoy_data_updated", Callable(self, "_on_convoy_updated_for_vehicle_check")):
			_gdm.disconnect("convoy_data_updated", Callable(self, "_on_convoy_updated_for_vehicle_check"))
		return

	var current_vehicle_count := _get_total_vehicle_count()
	if _initial_vehicle_count >= 0 and current_vehicle_count > _initial_vehicle_count:
		print("[Tutorial] Detected new vehicle via convoy update. Count changed from %d to %d." % [_initial_vehicle_count, current_vehicle_count])
		if is_instance_valid(_gdm):
			_gdm.disconnect("convoy_data_updated", Callable(self, "_on_convoy_updated_for_vehicle_check"))
		call_deferred("_advance")

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
		# Success! The highlight has been set. The overlay's internal _process loop
		# will now track the node if it moves. We can stop the retry timer.
		_active_highlight_step.clear() # Stop retrying.
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
		# The menu has been opened, but its layout (and the position of its buttons)
		# may not be stable until the next frame or two. To prevent a race condition
		# where the next step tries to highlight a button before it's in its final
		# position, we wait for the layout to settle before advancing.
		_advance_after_frame()

# --- External steps & persistence ---
func _load_steps_for_level(level: int) -> Array:
	# --- FIX: Temporarily disable loading from external JSON ---
	# The external file `res://Other/tutorial_steps.json` appears to contain outdated
	# tutorial definitions, causing the journey planning steps to run for Level 2.
	# By commenting this section out, we force the game to use the corrected
	# `_build_level_steps` function defined within this script.
	# var path := "res://Other/tutorial_steps.json"
	# var f := FileAccess.open(path, FileAccess.READ)
	# if f:
	# 	var txt := f.get_as_text()
	# 	f.close()
	# 	var data: Variant = JSON.parse_string(txt)
	# 	if typeof(data) == TYPE_DICTIONARY and data.has(str(level)) and data[str(level)] is Array:
	# 		print("[Tutorial] Loaded steps for level ", level, " from external JSON.")
	# 		return data[str(level)]
	# Fallback to built-in
	return _build_level_steps(level)

func _lock_vendor_tabs(step: Dictionary) -> void:
	var tabs := _get_vendor_tab_container()
	if not is_instance_valid(tabs):
		return

	var target_token := String(step.get("target", {}).get("token", "")).to_lower()
	
	if target_token.is_empty():
		# No token provided, lock all tabs except the current one. This is for steps
		# that happen *after* a tab has been selected, like buying an item.
		var current_tab_idx = tabs.current_tab
		print("[Tutorial] Locking vendor tabs, allowing current tab (index %d)" % current_tab_idx)
		for i in range(tabs.get_tab_count()):
			if i != current_tab_idx:
				tabs.set_tab_disabled(i, true)
			else:
				tabs.set_tab_disabled(i, false)
	else:
		# Token provided, lock all tabs that don't match the token. This is for steps
		# that require the user to click a specific tab.
		print("[Tutorial] Locking vendor tabs, allowing '%s'" % target_token)
		for i in range(tabs.get_tab_count()):
			var title_lower := tabs.get_tab_title(i).to_lower()
			var is_allowed := title_lower.find(target_token) != -1

			# Tutorial Level 1 special case: When targeting the dealership,
			# explicitly block market and gas station to prevent user from skipping ahead,
			# even if their names are unusual.
			if _level == 1 and target_token == "dealership":
				if title_lower.find("market") != -1 or title_lower.find("gas") != -1:
					is_allowed = false
			
			tabs.set_tab_disabled(i, not is_allowed)

func _unlock_vendor_tabs() -> void:
	var tabs := _get_vendor_tab_container()
	if not is_instance_valid(tabs):
		return
	print("[Tutorial] Unlocking all vendor tabs.")
	for i in range(tabs.get_tab_count()):
		tabs.set_tab_disabled(i, false)

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

# --- Stub for dealership tab hinting ---
func _hint_dealership_tab(target: Dictionary) -> void:
	# This function attempts to refine the highlight for a tab, which is often
	# difficult to resolve because Godot doesn't expose tab button nodes directly.
	# It relies on a helper method in the ConvoySettlementMenu script.
	var menu := _get_settlement_menu()
	if not is_instance_valid(menu):
		return

	if not menu.has_method("get_vendor_tab_rect_by_title_contains"):
		print("[Tutorial] Hinting failed: ConvoySettlementMenu is missing 'get_vendor_tab_rect_by_title_contains' helper.")
		return

	var token := String(target.get("token", "Dealership"))
	var rect: Rect2 = menu.call("get_vendor_tab_rect_by_title_contains", token)

	if rect.has_area():
		var ov := _ensure_overlay()
		if is_instance_valid(ov) and ov.has_method("highlight_node"):
			# Refine the highlight to be just the tab button.
			ov.call_deferred("highlight_node", menu, rect)
			print("[Tutorial] Refined highlight for tab: ", token)
