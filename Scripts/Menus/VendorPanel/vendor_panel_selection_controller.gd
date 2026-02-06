extends RefCounted
class_name VendorPanelSelectionController

# Selection handling extracted from vendor_trade_panel.gd.
# Operates on the panel instance to preserve behavior while shrinking the panel script.

static func handle_new_item_selection(panel: Object, p_selected_item: Variant) -> void:
	var previous_key: String = str(panel._last_selection_unique_key)
	panel.selected_item = p_selected_item
	var new_key: String = ""
	var restore_id: String = ""

	# Prefer stable aggregation key when present (e.g., grouped convoy cargo rows).
	if panel.selected_item and panel.selected_item is Dictionary and panel.selected_item.has("stable_key"):
		var sk := str(panel.selected_item.get("stable_key", ""))
		if not sk.is_empty():
			new_key = sk
			restore_id = sk

	if new_key.is_empty() and panel.selected_item and panel.selected_item.has("item_data"):
		var item_data_local: Dictionary = panel.selected_item.item_data
		if item_data_local.has("cargo_id") and item_data_local.cargo_id != null:
			new_key = "cargo:" + str(item_data_local.cargo_id)
			restore_id = str(item_data_local.cargo_id)
		elif item_data_local.has("vehicle_id") and item_data_local.vehicle_id != null:
			new_key = "veh:" + str(item_data_local.vehicle_id)
			restore_id = str(item_data_local.vehicle_id)
		else:
			if item_data_local.get("fuel", 0) > 0 and item_data_local.get("is_raw_resource", false):
				new_key = "res:fuel"
				restore_id = new_key
			elif item_data_local.get("water", 0) > 0 and item_data_local.get("is_raw_resource", false):
				new_key = "res:water"
				restore_id = new_key
			elif item_data_local.get("food", 0) > 0 and item_data_local.get("is_raw_resource", false):
				new_key = "res:food"
				restore_id = new_key
			else:
				new_key = "name:" + str(item_data_local.get("name", ""))
				restore_id = new_key

	panel._last_selected_item_id = new_key
	panel._last_selection_unique_key = new_key
	var is_same_selection: bool = previous_key == new_key
	if not is_same_selection and panel.has_method("_clear_committed_projection"):
		panel._clear_committed_projection()
	panel._last_selected_ref = panel.selected_item
	panel._last_selected_restore_id = restore_id

	# --- START: Reduced logging to prevent output overflow ---
	var item_summary_for_log := "null"
	if panel.selected_item and panel.selected_item.has("item_data"):
		var item_name_for_log: String = str(panel.selected_item.item_data.get("name", "<no_name>"))
		item_summary_for_log = "Item(name='%s', key='%s')" % [item_name_for_log, new_key]
	if panel.perf_log_enabled:
		print("DEBUG: _handle_new_item_selection - selected_item: ", item_summary_for_log, " is_same_selection: ", is_same_selection)
	# --- END: Reduced logging ---

	# --- Data Prefetching ---
	if panel.selected_item and panel.selected_item.has("item_data"):
		var idata: Dictionary = panel.selected_item.item_data
		# 1. Vehicle details
		if VendorTradeVM.is_vehicle_item(idata):
			# If missing critical pricing/stats, fetch
			if not idata.has("value") or not idata.has("base_top_speed"):
				var vid := str(idata.get("vehicle_id", ""))
				if vid != "" and is_instance_valid(panel._vendor_service):
					panel._vendor_service.request_vehicle(vid)
		# 2. Mission recipient details
		var rid := str(idata.get("recipient", ""))
		if rid == "":
			# Some mission cargo uses `mission_vendor_id` instead of `recipient`.
			var dr_v: Variant = idata.get("delivery_reward")
			var looks_mission := (dr_v is float or dr_v is int) and float(dr_v) > 0.0
			if looks_mission:
				rid = str(idata.get("mission_vendor_id", ""))
		if rid != "" and not panel._vendor_id_to_name.has(rid):
			if is_instance_valid(panel._vendor_service):
				panel._vendor_service.request_vendor_preview(rid)
	# ------------------------

	if panel.selected_item:
		var stock_qty: int = int(panel.selected_item.get("total_quantity", -1))
		if stock_qty < 0 and panel.selected_item.has("item_data") and panel.selected_item.item_data.has("quantity"):
			stock_qty = int(panel.selected_item.item_data.get("quantity", 1))
		if panel.selected_item.has("item_data") and panel.selected_item.item_data.get("is_raw_resource", false):
			var idata2: Dictionary = panel.selected_item.item_data
			if panel.perf_log_enabled:
				print("DEBUG: selected_item is raw resource, idata:", idata2)
			if idata2.get("fuel", 0) > 0:
				stock_qty = int(idata2.get("fuel"))
			elif idata2.get("water", 0) > 0:
				stock_qty = int(idata2.get("water"))
			elif idata2.get("food", 0) > 0:
				stock_qty = int(idata2.get("food"))
			if panel.perf_log_enabled:
				print("DEBUG: raw resource stock_qty chosen=", stock_qty)
		if panel.perf_log_enabled:
			print("DEBUG: stock_qty for selected_item:", stock_qty)
		if stock_qty <= 0:
			stock_qty = 1
		panel.quantity_spinbox.max_value = max(1, stock_qty)
		if panel.perf_log_enabled:
			print("DEBUG: quantity_spinbox.max_value set to:", panel.quantity_spinbox.max_value)
		if not is_same_selection:
			panel.quantity_spinbox.value = 1
		else:
			panel.quantity_spinbox.value = clampi(int(panel.quantity_spinbox.value), 1, int(panel.quantity_spinbox.max_value))
		if panel.perf_log_enabled:
			print("DEBUG: quantity_spinbox.value set to:", panel.quantity_spinbox.value)

		panel._update_inspector()
		panel._update_comparison()

		var item_data_source_debug: Dictionary = panel.selected_item.get("item_data", {})

		# --- START: Reduced logging to prevent output overflow ---
		var item_name_for_log_debug: String = str(item_data_source_debug.get("name", "<no_name>"))
		var item_id_for_log_debug: String = str(item_data_source_debug.get("cargo_id", item_data_source_debug.get("vehicle_id", "<no_id>")))
		if panel.perf_log_enabled:
			print("DEBUG: _handle_new_item_selection - item_data_source (original): name='%s', id='%s'" % [item_name_for_log_debug, item_id_for_log_debug])
		# --- END: Reduced logging ---

		panel._update_transaction_panel()
		panel._update_install_button_state()
		# Fire backend compatibility checks for this item against all convoy vehicles (to align with Mechanics)
		if panel.selected_item and panel.selected_item.has("item_data") and panel.convoy_data and panel.convoy_data.has("vehicle_details_list"):
			var idata3: Dictionary = panel.selected_item.item_data
			var uid := str(idata3.get("cargo_id", idata3.get("part_id", "")))
			# Only request compatibility for items that look like vehicle parts.
			if uid != "" and panel._looks_like_part(idata3):
				for v in panel.convoy_data.vehicle_details_list:
					var vid2 := str(v.get("vehicle_id", ""))
					if vid2 != "" and is_instance_valid(panel._mechanics_service) and panel._mechanics_service.has_method("check_part_compatibility"):
						var key: String = VendorTradeVM.compat_key(vid2, uid)
						if not panel._compat_cache.has(key):
							panel._mechanics_service.check_part_compatibility(vid2, uid)

		if is_instance_valid(panel.action_button):
			panel.action_button.disabled = false
		if is_instance_valid(panel.max_button):
			panel.max_button.disabled = false
	else:
		panel._clear_inspector()
		if is_instance_valid(panel.action_button):
			panel.action_button.disabled = true
		if is_instance_valid(panel.max_button):
			panel.max_button.disabled = true
		panel._update_install_button_state()
