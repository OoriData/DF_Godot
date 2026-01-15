extends RefCounted
class_name VendorPanelRefreshController

# Refresh/orchestration extracted from vendor_trade_panel.gd.
# Operates on the panel instance to preserve behavior while shrinking the panel script.

static func request_authoritative_refresh(panel: Object, convoy_id: String, vendor_id: String) -> void:
	if convoy_id == "" or vendor_id == "":
		return

	panel._active_convoy_id = convoy_id
	panel._active_vendor_id = vendor_id
	panel._refresh_seq += 1
	panel._current_refresh_id = panel._refresh_seq
	panel._refresh_in_flight = true
	panel._awaiting_panel_data = true
	panel._pending_refresh = false
	panel._refresh_t0_ms = Time.get_ticks_msec()
	if panel.show_loading_overlay:
		panel._show_loading()

	# Ask VendorService for the latest vendor snapshot; convoy snapshot comes from GameStore.
	if is_instance_valid(panel._vendor_service) and panel._vendor_service.has_method("request_vendor_panel"):
		panel._vendor_service.request_vendor_panel(convoy_id, vendor_id)

	# Best-effort: sync convoy snapshot immediately from store
	var c: Dictionary = panel._get_convoy_by_id(convoy_id)
	if c is Dictionary and not c.is_empty():
		panel.convoy_data = c


static func on_api_transaction_result(panel: Object, result: Dictionary) -> void:
	if panel.perf_log_enabled:
		print("DEBUG: _on_api_transaction_result called with result: ", result)
		if int(panel._txn_t0_ms) >= 0:
			var now_ms: int = Time.get_ticks_msec()
			print("[VendorPanel][Perf] API result +%d ms" % int(now_ms - int(panel._txn_t0_ms)))

	# Prefer an immediate refresh for responsiveness.
	if panel.vendor_data and panel.convoy_data and not bool(panel._awaiting_panel_data) and not bool(panel._refresh_in_flight):
		var cid: String = str((panel.convoy_data as Dictionary).get("convoy_id", "")) if (panel.convoy_data is Dictionary) else ""
		var vid: String = str((panel.vendor_data as Dictionary).get("vendor_id", "")) if (panel.vendor_data is Dictionary) else ""
		if cid != "" and vid != "":
			request_authoritative_refresh(panel, cid, vid)
			if panel.perf_log_enabled:
				print("[VendorPanel][Perf] immediate refresh requested cid=", cid, " vid=", vid, " id=", int(panel._current_refresh_id))
			return

	# Fallback: if guards prevent immediate request, schedule a short debounced refresh.
	panel._pending_refresh = true
	panel._schedule_refresh()


static func on_api_transaction_error(panel: Object, error_message: String) -> void:
	# This panel is only interested in errors that happen while it's visible.
	if not panel.is_visible_in_tree():
		return

	if panel.perf_log_enabled and int(panel._txn_t0_ms) >= 0:
		var now_ms: int = Time.get_ticks_msec()
		print("[VendorPanel][Perf] API error +%d ms" % int(now_ms - int(panel._txn_t0_ms)))
		panel._txn_t0_ms = -1

	# Revert optimistic projections.
	if bool(panel._transaction_in_progress):
		# Money revert (if label visible)
		if is_instance_valid(panel.convoy_money_label) and panel.convoy_money_label.visible and (panel.convoy_data is Dictionary) and (panel.convoy_data as Dictionary).has("money"):
			panel.convoy_money_label.text = NumberFormat.format_money(float((panel.convoy_data as Dictionary).get("money", 0.0)), "")
		# Capacity bars revert
		panel._refresh_capacity_bars(-float(panel._pending_tx.volume_delta), -float(panel._pending_tx.weight_delta))

	panel._transaction_in_progress = false
	if is_instance_valid(panel.action_button):
		panel.action_button.disabled = false
	if is_instance_valid(panel.max_button):
		panel.max_button.disabled = false
	if panel.show_loading_overlay and is_instance_valid(panel.loading_panel):
		panel._hide_loading()

	# Show toast if available.
	var friendly_message: String = ErrorTranslator.translate(error_message)
	if not friendly_message.is_empty() and is_instance_valid(panel.toast_notification) and panel.toast_notification.has_method("show_message"):
		panel.toast_notification.call("show_message", friendly_message)

	# Refresh authoritative data.
	if panel.vendor_data and panel.convoy_data:
		var cid: String = str((panel.convoy_data as Dictionary).get("convoy_id", "")) if (panel.convoy_data is Dictionary) else ""
		var vid: String = str((panel.vendor_data as Dictionary).get("vendor_id", "")) if (panel.vendor_data is Dictionary) else ""
		if cid != "" and vid != "":
			request_authoritative_refresh(panel, cid, vid)

static func on_hub_vendor_panel_ready(panel: Object, data: Dictionary) -> void:
	if data == null or not (data is Dictionary):
		return

	panel.vendor_data = data

	# Sync convoy snapshot from store (if possible)
	var cid := str((panel.convoy_data if panel.convoy_data is Dictionary else {}).get("convoy_id", panel._active_convoy_id))
	if cid != "":
		var c: Dictionary = panel._get_convoy_by_id(cid)
		if c is Dictionary and not c.is_empty():
			panel.convoy_data = c

	# If we don't have settlements yet, try to pull from GameStore
	if is_instance_valid(panel._store) and panel._store.has_method("get_settlements") and (panel._latest_settlements == null or panel._latest_settlements.is_empty()):
		var ss: Array = panel._store.get_settlements()
		if ss is Array and not ss.is_empty():
			panel._set_latest_settlements_snapshot(ss)

	try_process_refresh(panel)

static func try_process_refresh(panel: Object) -> void:
	if not (panel._refresh_in_flight or panel._awaiting_panel_data):
		return

	var vid := str((panel.vendor_data if panel.vendor_data is Dictionary else {}).get("vendor_id", ""))
	var cid := str((panel.convoy_data if panel.convoy_data is Dictionary else {}).get("convoy_id", ""))
	if panel._active_vendor_id != "" and vid != "" and vid != panel._active_vendor_id:
		return
	if panel._active_convoy_id != "" and cid != "" and cid != panel._active_convoy_id:
		return

	# We require both vendor and convoy context to match the legacy payload semantics.
	if vid == "" or cid == "":
		return

	# Guard: if the user just changed selection, defer processing to avoid selection flicker
	if VendorSelectionManager.should_defer_selection(panel._last_selection_change_ms, panel.DATA_READY_COOLDOWN_MS):
		var defer_t: SceneTreeTimer = panel.get_tree().create_timer(float(panel.DATA_READY_COOLDOWN_MS) / 1000.0)
		defer_t.timeout.connect(Callable(panel, "_try_process_refresh"))
		return

	process_panel_payload_ready(panel)

static func process_panel_payload_ready(panel: Object) -> void:
	if panel.perf_log_enabled:
		print("[VendorPanel][Perf] data_ready PROCESS refresh_id=", panel._current_refresh_id, " vid=", str(panel.vendor_data.get("vendor_id", "")), " cid=", str(panel.convoy_data.get("convoy_id", "")))
		var now_ms := Time.get_ticks_msec()
		if panel._txn_t0_ms >= 0:
			print("[VendorPanel][Perf] panel data ready +%d ms" % int(now_ms - panel._txn_t0_ms))
			panel._txn_t0_ms = -1
		if panel._refresh_t0_ms >= 0:
			print("[VendorPanel][Perf] refresh latency +%d ms (id=%d)" % [int(now_ms - panel._refresh_t0_ms), panel._current_refresh_id])
			panel._refresh_t0_ms = -1

	panel._refresh_in_flight = false
	panel._awaiting_panel_data = false
	panel._transaction_in_progress = false
	panel._refresh_timer = null
	panel._last_data_ready_ms = Time.get_ticks_msec()
	if panel.show_loading_overlay:
		panel._hide_loading()

	# --- START ATOMIC REFRESH to prevent flicker ---
	var c_vendor := Callable(panel, "_on_vendor_item_selected")
	var c_convoy := Callable(panel, "_on_convoy_item_selected")
	if panel.vendor_item_tree.item_selected.is_connected(c_vendor):
		panel.vendor_item_tree.item_selected.disconnect(c_vendor)
	if panel.convoy_item_tree.item_selected.is_connected(c_convoy):
		panel.convoy_item_tree.item_selected.disconnect(c_convoy)

	var prev_selected_id: Variant = panel._last_selected_restore_id
	var prev_tree: String = str(panel._last_selected_tree)

	var t0 := 0
	if panel.perf_log_enabled:
		t0 = Time.get_ticks_msec()

	# Rebuild lists from raw snapshots (vendor_data + convoy_data)
	panel._populate_vendor_list()
	panel._populate_convoy_list()
	panel._update_convoy_info_display()

	if panel.perf_log_enabled:
		var dt = Time.get_ticks_msec() - t0
		print("[VendorPanel][Perf] rebuild dt=", dt, " ms (id=", panel._current_refresh_id, ")")

	var selection_restored := false
	if typeof(prev_selected_id) == TYPE_STRING and str(prev_selected_id) != "":
		if prev_tree == "vendor":
			selection_restored = panel._restore_selection(panel.vendor_item_tree, prev_selected_id)
		elif prev_tree == "convoy":
			selection_restored = panel._restore_selection(panel.convoy_item_tree, prev_selected_id)

	if not selection_restored:
		panel._clear_inspector()
		panel._update_transaction_panel()
		panel.action_button.disabled = true
		panel.max_button.disabled = true

	panel.vendor_item_tree.item_selected.connect(Callable(panel, "_on_vendor_item_selected"))
	panel.convoy_item_tree.item_selected.connect(Callable(panel, "_on_convoy_item_selected"))
	# --- END ATOMIC REFRESH ---

	panel._panel_initialized = true

static func on_vendor_panel_data_ready(panel: Object, vendor_panel_data: Dictionary) -> void:
	if panel.perf_log_enabled:
		var now0 := Time.get_ticks_msec()
		var delta0: int = int((now0 - panel._last_data_ready_ms) if panel._last_data_ready_ms >= 0 else -1)
		print("[VendorPanel][Perf] data_ready ENTER id=", panel._current_refresh_id, " panelInit=", panel._panel_initialized, " in_flight=", panel._refresh_in_flight, " awaiting=", panel._awaiting_panel_data, " delta_since_last=", delta0, " ms")

	# Cooldown guard: if no refresh is in-flight/awaited, ignore duplicate payloads that arrive
	# immediately after a processed one (or after initial populate once panel is initialized).
	if not panel._refresh_in_flight and not panel._awaiting_panel_data:
		var now_guard := Time.get_ticks_msec()
		var delta_guard: int = int((now_guard - panel._last_data_ready_ms) if panel._last_data_ready_ms >= 0 else -1)
		if panel._panel_initialized or (delta_guard >= 0 and delta_guard < panel.DATA_READY_COOLDOWN_MS):
			if panel.perf_log_enabled:
				print("[VendorPanel][Perf] IGNORE vendor_panel_data_ready (cooldown) delta=", delta_guard, " ms, id=", panel._current_refresh_id)
			return

	# This handler expects the full data payload. If it's a partial "warming" payload
	# (which lacks this key), ignore it. The warming payload is for other menus.
	if not vendor_panel_data.has("all_settlement_data"):
		# Safety: if a partial payload arrives while a refresh is in progress,
		# clear flags and hide overlay (if enabled) so the panel doesn't remain blocked.
		if panel.show_loading_overlay and is_instance_valid(panel.loading_panel) and panel.loading_panel.visible:
			panel._hide_loading()
		panel._refresh_in_flight = false
		panel._awaiting_panel_data = false
		panel._transaction_in_progress = false
		return

	# Ignore payloads for other vendors (warmers can emit multiple payloads)
	var incoming_vid := str((vendor_panel_data.get("vendor_data", {}) as Dictionary).get("vendor_id", ""))
	var current_vid := str((panel.vendor_data if panel.vendor_data is Dictionary else {}).get("vendor_id", ""))
	if current_vid != "" and incoming_vid != "" and incoming_vid != current_vid:
		if panel.perf_log_enabled:
			print("[VendorPanel][Perf] IGNORE vendor mismatch incoming_vid=", incoming_vid, " current_vid=", current_vid)
		return

	# If we've already initialized and no refresh is in-flight, ignore stray payloads
	# to prevent multiple mid-purchase UI rebuilds.
	if panel._panel_initialized and not panel._refresh_in_flight and not panel._awaiting_panel_data:
		if panel.perf_log_enabled:
			print("[VendorPanel][Perf] IGNORE stray vendor_panel_data_ready (no refresh in-flight, id=", panel._current_refresh_id, ")")
		return

	if panel.perf_log_enabled:
		print("[VendorTradePanel][LOG] _on_vendor_panel_data_ready called. Hiding loading panel and updating UI.")
		print("[VendorPanel][Perf] data_ready PROCESS refresh_id=", panel._current_refresh_id, " incoming_vid=", incoming_vid)
		var now_ms := Time.get_ticks_msec()
		if panel._txn_t0_ms >= 0:
			print("[VendorPanel][Perf] panel data ready +%d ms" % int(now_ms - panel._txn_t0_ms))
			panel._txn_t0_ms = -1
		else:
			print("[VendorPanel][Perf] panel data ready (no baseline)")
		if panel._refresh_t0_ms >= 0:
			print("[VendorPanel][Perf] refresh latency +%d ms (id=%d)" % [int(now_ms - panel._refresh_t0_ms), panel._current_refresh_id])
			panel._refresh_t0_ms = -1

	panel._refresh_in_flight = false
	panel._awaiting_panel_data = false
	panel._transaction_in_progress = false # Failsafe reset
	# Cancel any pending debounced refresh now that authoritative data arrived
	panel._refresh_timer = null
	if panel.show_loading_overlay:
		panel._hide_loading() # Hide loading indicator on data arrival with fade
	panel.vendor_data = vendor_panel_data.get("vendor_data")
	panel.convoy_data = vendor_panel_data.get("convoy_data")
	panel.current_settlement_data = vendor_panel_data.get("settlement_data")
	panel.all_settlement_data_global = vendor_panel_data.get("all_settlement_data")
	panel.vendor_items = vendor_panel_data.get("vendor_items", {})
	panel.convoy_items = vendor_panel_data.get("convoy_items", {})
	panel._last_data_ready_ms = Time.get_ticks_msec()

	# --- START ATOMIC REFRESH to prevent flicker ---
	# Disconnect signals to prevent flicker from intermediate states during repopulation.
	var cb_vendor := Callable(panel, "_on_vendor_item_selected")
	var cb_convoy := Callable(panel, "_on_convoy_item_selected")
	if panel.vendor_item_tree.item_selected.is_connected(cb_vendor):
		panel.vendor_item_tree.item_selected.disconnect(cb_vendor)
	if panel.convoy_item_tree.item_selected.is_connected(cb_convoy):
		panel.convoy_item_tree.item_selected.disconnect(cb_convoy)

	var prev_selected_id: Variant = panel._last_selected_restore_id
	var prev_tree: String = str(panel._last_selected_tree)

	# Do not forcibly clear selection; we'll attempt to restore it below.

	var t0 := 0
	if panel.perf_log_enabled:
		t0 = Time.get_ticks_msec()
	# Only rebuild the tree(s) that are relevant (active tab or previously selected tree)
	var need_vendor: bool = (panel.trade_mode_tab_container.current_tab == 0) or (prev_tree == "vendor")
	var need_convoy: bool = (panel.trade_mode_tab_container.current_tab == 1) or (prev_tree == "convoy")
	panel._update_vendor_ui(need_vendor, need_convoy)
	if panel.perf_log_enabled:
		var dt = Time.get_ticks_msec() - t0
		print("[VendorPanel][Perf] _update_vendor_ui dt=", dt, " ms (id=", panel._current_refresh_id, ") vendor_rows=", (panel.vendor_items.keys().size() if panel.vendor_items is Dictionary else 0), " convoy_rows=", (panel.convoy_items.keys().size() if panel.convoy_items is Dictionary else 0))

	var selection_restored := false
	if typeof(prev_selected_id) == TYPE_STRING and not str(prev_selected_id).is_empty():
		if prev_tree == "vendor":
			selection_restored = panel._restore_selection(panel.vendor_item_tree, prev_selected_id)
		elif prev_tree == "convoy":
			selection_restored = panel._restore_selection(panel.convoy_item_tree, prev_selected_id)

	# If selection was not restored, manually clear the inspector panels.
	if not selection_restored:
		panel._clear_inspector()
		panel._update_transaction_panel() # This will correctly show $0 since selected_item is null
		panel.action_button.disabled = true
		panel.max_button.disabled = true
		if panel.perf_log_enabled:
			print("[VendorPanel][Perf] selection restore failed; inspector cleared (id=", panel._current_refresh_id, ")")

	# Reconnect signals
	panel.vendor_item_tree.item_selected.connect(cb_vendor)
	panel.convoy_item_tree.item_selected.connect(cb_convoy)
	# --- END ATOMIC REFRESH ---

	panel._panel_initialized = true
