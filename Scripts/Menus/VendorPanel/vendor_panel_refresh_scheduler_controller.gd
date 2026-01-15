extends RefCounted
class_name VendorPanelRefreshSchedulerController

# Refresh scheduling + watchdog extracted from vendor_trade_panel.gd.
# Keeps the panel thin; operates on the panel instance to preserve behavior.

static func schedule_refresh(panel: Object) -> void:
	# Create a new timer; only the latest one triggers the refresh.
	var t: SceneTreeTimer = VendorSelectionManager.schedule_debounce(panel.get_tree(), panel.REFRESH_DEBOUNCE_S, Callable(panel, "_on_refresh_debounce_timeout"))
	panel._refresh_timer = t
	if panel.perf_log_enabled:
		print("[VendorPanel][Perf] refresh scheduled in %.2fs (seq=%d)" % [float(panel.REFRESH_DEBOUNCE_S), int(panel._refresh_seq) + 1])


static func on_refresh_debounce_timeout(panel: Object, t: SceneTreeTimer) -> void:
	if panel._refresh_timer == t:
		perform_refresh(panel)


static func perform_refresh(panel: Object) -> void:
	if panel.vendor_data == null:
		return
	var vid: String = ""
	if panel.vendor_data is Dictionary:
		vid = str((panel.vendor_data as Dictionary).get("vendor_id", ""))
	if vid == "":
		return

	var cid: String = ""
	if panel.convoy_data is Dictionary:
		cid = str((panel.convoy_data as Dictionary).get("convoy_id", panel._active_convoy_id))
	else:
		cid = str(panel._active_convoy_id)
	if cid == "":
		cid = str(panel._active_convoy_id)
	if cid == "":
		return

	# If the user just changed selection very recently, defer the refresh slightly to avoid
	# interrupting the UI and causing selection flicker. This helps during rapid purchases.
	if VendorSelectionManager.perform_refresh_guard(int(panel._last_selection_change_ms), float(panel.REFRESH_DEBOUNCE_S), Callable(panel, "_on_deferred_refresh_timeout")):
		return

	# Disabled blocking overlay during tutorial work; keep UI interactive.
	panel._refresh_in_flight = true
	panel._awaiting_panel_data = true
	panel._refresh_seq += 1
	panel._current_refresh_id = panel._refresh_seq
	panel._refresh_t0_ms = Time.get_ticks_msec()
	if panel.perf_log_enabled:
		print("[VendorPanel][Perf] refresh started vendor=", vid, " id=", panel._current_refresh_id)

	panel._request_authoritative_refresh(cid, vid)
	panel._pending_refresh = false


static func start_refresh_watchdog(panel: Object, refresh_id: int, timeout_ms: int = 1200) -> void:
	VendorSelectionManager.start_watchdog(panel.get_tree(), refresh_id, timeout_ms, Callable(panel, "_on_refresh_watchdog_timeout"))


static func on_refresh_watchdog_timeout(panel: Object, rid: int) -> void:
	# Only act if still awaiting this refresh and no data_ready processed since start
	var now: int = Time.get_ticks_msec()
	var no_payload: bool = (int(panel._last_data_ready_ms) < int(panel._refresh_t0_ms)) or (int(panel._last_data_ready_ms) < 0)
	if int(panel._current_refresh_id) == rid and (bool(panel._refresh_in_flight) or bool(panel._awaiting_panel_data)) and no_payload:
		if panel._watchdog_retries.has(rid):
			return
		panel._watchdog_retries[rid] = true
		if panel.perf_log_enabled:
			print("[VendorPanel][Perf] Watchdog fired for id=", rid, " after ", (now - int(panel._refresh_t0_ms)), " ms; re-requesting panel payload once.")

		if panel.convoy_data and panel.vendor_data and (panel.convoy_data is Dictionary) and (panel.vendor_data is Dictionary):
			var cid: String = str((panel.convoy_data as Dictionary).get("convoy_id", ""))
			var vid: String = str((panel.vendor_data as Dictionary).get("vendor_id", ""))
			if cid != "" and vid != "":
				panel._request_authoritative_refresh(cid, vid)
				panel._awaiting_panel_data = true
				if panel.perf_log_enabled:
					print("[VendorPanel][Perf] Watchdog re-request issued cid=", cid, " vid=", vid, " (id=", rid, ")")


static func on_deferred_refresh_timeout(panel: Object) -> void:
	# After short defer, perform the refresh if this panel is still alive.
	if is_instance_valid(panel):
		perform_refresh(panel)
