extends RefCounted
class_name VendorPanelTransactionController

# Transaction logic extracted from vendor_trade_panel.gd.
# Owns max-quantity constraints, optimistic projection, and buy/sell dispatch.

static func on_max_button_pressed(panel: Object) -> void:
	if not panel.selected_item:
		return

	if str(panel.current_mode) == "sell":
		var sel_qty: int = int(panel.selected_item.get("total_quantity", 1))
		if panel.selected_item.has("item_data") and bool(panel.selected_item.item_data.get("is_raw_resource", false)):
			var idata: Dictionary = panel.selected_item.item_data
			if idata.get("fuel", 0) > 0:
				sel_qty = int(idata.get("fuel"))
			elif idata.get("water", 0) > 0:
				sel_qty = int(idata.get("water"))
			elif idata.get("food", 0) > 0:
				sel_qty = int(idata.get("food"))
		panel.quantity_spinbox.value = sel_qty
		return

	if str(panel.current_mode) != "buy":
		return

	# BUY: limited by vendor stock, money, remaining weight, remaining volume.
	var item_data_source_any: Variant = panel.selected_item.get("item_data")
	var item_data_source: Dictionary = item_data_source_any if item_data_source_any is Dictionary else {}

	var vendor_stock: int = int(panel.selected_item.get("total_quantity", 0))
	if bool(item_data_source.get("is_raw_resource", false)):
		if item_data_source.get("fuel", 0) > 0:
			vendor_stock = int(item_data_source.get("fuel"))
		elif item_data_source.get("water", 0) > 0:
			vendor_stock = int(item_data_source.get("water"))
		elif item_data_source.get("food", 0) > 0:
			vendor_stock = int(item_data_source.get("food"))

	# Money constraint
	var is_vehicle: bool = VendorTradeVM.is_vehicle_item(item_data_source)
	var unit_price: float = VendorTradeVM.vehicle_price(item_data_source) if is_vehicle else VendorTradeVM.contextual_unit_price(item_data_source, str(panel.current_mode))
	var afford_limit: int = 99999999
	if unit_price > 0.0:
		var money: int = 0
		var have_money: bool = false
		# Prefer authoritative user money from GameStore, fallback to convoy money.
		if is_instance_valid(panel._store) and panel._store.has_method("get_user"):
			var ud_any: Variant = panel._store.get_user()
			if ud_any is Dictionary:
				var ud: Dictionary = ud_any
				var mv: Variant = ud.get("money")
				if mv is int or mv is float:
					money = int(mv)
					have_money = true
		# If user money wasn't available, try convoy money
		if not have_money and panel.convoy_data and (panel.convoy_data is Dictionary):
			var cv: Variant = (panel.convoy_data as Dictionary).get("money")
			if cv is int or cv is float:
				money = int(cv)
				have_money = true
		afford_limit = floori(money / unit_price) if have_money else 99999999

	# Capacity constraints (skip for vehicles)
	var weight_limit: int = 99999999
	var volume_limit: int = 99999999
	if not is_vehicle:
		var unit_weight: float = 0.0
		if panel.selected_item and (panel.selected_item is Dictionary):
			var tq: int = int((panel.selected_item as Dictionary).get("total_quantity", 0))
			var tw: float = float((panel.selected_item as Dictionary).get("total_weight", 0.0))
			if tq > 0 and tw > 0.0:
				unit_weight = tw / float(tq)
		if unit_weight <= 0.0:
			if item_data_source.has("unit_weight"):
				unit_weight = float(item_data_source.get("unit_weight", 0.0))
			elif item_data_source.has("weight") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
				unit_weight = float(item_data_source.get("weight", 0.0)) / float(item_data_source.get("quantity", 1.0))
		var unit_volume: float = 0.0
		if panel.selected_item and (panel.selected_item is Dictionary):
			var tq2: int = int((panel.selected_item as Dictionary).get("total_quantity", 0))
			var tv: float = float((panel.selected_item as Dictionary).get("total_volume", 0.0))
			if tq2 > 0 and tv > 0.0:
				unit_volume = tv / float(tq2)
		if unit_volume <= 0.0:
			if item_data_source.has("unit_volume"):
				unit_volume = float(item_data_source.get("unit_volume", 0.0))
			elif item_data_source.has("volume") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
				unit_volume = float(item_data_source.get("volume", 0.0)) / float(item_data_source.get("quantity", 1.0))

		var remaining_weight: float = max(0.0, float(panel._convoy_total_weight) - float(panel._convoy_used_weight))
		var remaining_volume: float = max(0.0, float(panel._convoy_total_volume) - float(panel._convoy_used_volume))
		if unit_weight > 0.0 and float(panel._convoy_total_weight) > 0.0:
			weight_limit = int(floor(remaining_weight / unit_weight))
		if unit_volume > 0.0 and float(panel._convoy_total_volume) > 0.0:
			volume_limit = int(floor(remaining_volume / unit_volume))

	var max_quantity: int = vendor_stock
	max_quantity = min(max_quantity, afford_limit)
	max_quantity = min(max_quantity, weight_limit)
	max_quantity = min(max_quantity, volume_limit)
	max_quantity = max(1, max_quantity)
	panel.quantity_spinbox.value = max_quantity


static func on_action_button_pressed(panel: Object) -> void:
	if bool(panel._transaction_in_progress):
		return
	if not panel.selected_item:
		return

	var quantity: int = int(panel.quantity_spinbox.value)
	if quantity <= 0:
		return

	var item_data_source_any: Variant = panel.selected_item.get("item_data")
	if not (item_data_source_any is Dictionary):
		return
	var item_data_source: Dictionary = item_data_source_any

	var vendor_id: String = ""
	if panel.vendor_data and (panel.vendor_data is Dictionary):
		vendor_id = str((panel.vendor_data as Dictionary).get("vendor_id", ""))
	var convoy_id: String = ""
	if panel.convoy_data and (panel.convoy_data is Dictionary):
		convoy_id = str((panel.convoy_data as Dictionary).get("convoy_id", ""))

	if vendor_id == "" or convoy_id == "":
		panel._on_api_transaction_error("Missing vendor/convoy context")
		return

	# Perf baseline for transaction timeline
	if panel.perf_log_enabled:
		panel._txn_t0_ms = Time.get_ticks_msec()
		var item_name: String = str(item_data_source.get("name", "?"))
		print("[VendorPanel][Perf] click '%s' qty=%d t0=%d" % [item_name, quantity, int(panel._txn_t0_ms)])

	# Compute deltas for optimistic projection
	var is_vehicle: bool = VendorTradeVM.is_vehicle_item(item_data_source)
	var unit_price: float = VendorTradeVM.vehicle_price(item_data_source) if is_vehicle else VendorTradeVM.contextual_unit_price(item_data_source, str(panel.current_mode))
	var total_price: float = unit_price * float(quantity)

	var unit_weight: float = 0.0
	if panel.selected_item and (panel.selected_item is Dictionary):
		var tq3: int = int((panel.selected_item as Dictionary).get("total_quantity", 0))
		var tw3: float = float((panel.selected_item as Dictionary).get("total_weight", 0.0))
		if tq3 > 0 and tw3 > 0.0:
			unit_weight = tw3 / float(tq3)
	if unit_weight <= 0.0:
		if item_data_source.has("unit_weight"):
			unit_weight = float(item_data_source.get("unit_weight", 0.0))
		elif item_data_source.has("weight") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
			unit_weight = float(item_data_source.get("weight", 0.0)) / float(item_data_source.get("quantity", 1.0))

	var unit_volume: float = 0.0
	if panel.selected_item and (panel.selected_item is Dictionary):
		var tq4: int = int((panel.selected_item as Dictionary).get("total_quantity", 0))
		var tv4: float = float((panel.selected_item as Dictionary).get("total_volume", 0.0))
		if tq4 > 0 and tv4 > 0.0:
			unit_volume = tv4 / float(tq4)
	if unit_volume <= 0.0:
		if item_data_source.has("unit_volume"):
			unit_volume = float(item_data_source.get("unit_volume", 0.0))
		elif item_data_source.has("volume") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
			unit_volume = float(item_data_source.get("volume", 0.0)) / float(item_data_source.get("quantity", 1.0))

	var w_delta: float = unit_weight * float(quantity)
	var v_delta: float = unit_volume * float(quantity)

	panel._pending_tx.mode = str(panel.current_mode)
	panel._pending_tx.item = item_data_source.duplicate(true)
	panel._pending_tx.quantity = quantity
	panel._pending_tx.selection_key = str(panel._last_selection_unique_key)
	panel._pending_tx.selection_tree = str(panel._last_selected_tree)
	panel._pending_tx.start_used_weight = float(panel._convoy_used_weight)
	panel._pending_tx.start_used_volume = float(panel._convoy_used_volume)
	panel._pending_tx.started_ms = Time.get_ticks_msec()
	panel._pending_tx.money_delta = -total_price if str(panel.current_mode) == "buy" else total_price
	panel._pending_tx.weight_delta = w_delta if str(panel.current_mode) == "buy" else -w_delta
	panel._pending_tx.volume_delta = v_delta if str(panel.current_mode) == "buy" else -v_delta

	# Apply optimistic capacity/money projection without triggering an immediate data refresh.
	panel._transaction_in_progress = true
	# Money projection (if label visible)
	if is_instance_valid(panel.convoy_money_label) and panel.convoy_money_label.visible and panel.convoy_data and (panel.convoy_data is Dictionary) and (panel.convoy_data as Dictionary).has("money"):
		var projected_money: float = float((panel.convoy_data as Dictionary).get("money", 0.0)) + float(panel._pending_tx.money_delta)
		panel.convoy_money_label.text = NumberFormat.format_money(projected_money, "")
	# Capacity bars projection
	panel._refresh_capacity_bars(float(panel._pending_tx.volume_delta), float(panel._pending_tx.weight_delta))

	# Dispatch API via transport
	if str(panel.current_mode) == "buy":
		dispatch_buy(panel, vendor_id, convoy_id, item_data_source, quantity)
		panel._emit_item_purchased(item_data_source, quantity, total_price)
	else:
		var remaining: int = quantity
		if panel.selected_item.has("items") and panel.selected_item.items is Array and not (panel.selected_item.items as Array).is_empty():
			for cargo_item_any in (panel.selected_item.items as Array):
				if remaining <= 0:
					break
				if not (cargo_item_any is Dictionary):
					continue
				var cargo_item: Dictionary = cargo_item_any
				var available: int = int(cargo_item.get("quantity", 0))
				if available <= 0:
					continue
				var to_sell: int = min(available, remaining)
				dispatch_sell(panel, vendor_id, convoy_id, cargo_item, to_sell)
				remaining -= to_sell
		else:
			dispatch_sell(panel, vendor_id, convoy_id, item_data_source, quantity)

		var sell_unit_price: float = unit_price / 2.0
		panel._emit_item_sold(item_data_source, quantity, sell_unit_price * float(quantity))


static func dispatch_buy(panel: Object, vendor_id: String, convoy_id: String, item_data_source: Dictionary, quantity: int) -> void:
	if not is_instance_valid(panel._vendor_service):
		return

	if VendorTradeVM.is_vehicle_item(item_data_source):
		var vehicle_id: String = str(item_data_source.get("vehicle_id", ""))
		if vehicle_id != "" and panel._vendor_service.has_method("buy_vehicle"):
			panel._vendor_service.buy_vehicle(vendor_id, convoy_id, vehicle_id)
			panel._request_authoritative_refresh(convoy_id, vendor_id)
		return

	if bool(item_data_source.get("is_raw_resource", false)):
		var res_type: String = ""
		if float(item_data_source.get("fuel", 0)) > 0:
			res_type = "fuel"
		elif float(item_data_source.get("water", 0)) > 0:
			res_type = "water"
		elif float(item_data_source.get("food", 0)) > 0:
			res_type = "food"
		if res_type != "" and panel._vendor_service.has_method("buy_resource"):
			panel._vendor_service.buy_resource(vendor_id, convoy_id, res_type, float(quantity))
			panel._request_authoritative_refresh(convoy_id, vendor_id)
		return

	var cargo_id: String = str(item_data_source.get("cargo_id", ""))
	if cargo_id != "" and panel._vendor_service.has_method("buy_cargo"):
		panel._vendor_service.buy_cargo(vendor_id, convoy_id, cargo_id, int(quantity))
		panel._request_authoritative_refresh(convoy_id, vendor_id)


static func dispatch_sell(panel: Object, vendor_id: String, convoy_id: String, item_data_source: Dictionary, quantity: int) -> void:
	if not is_instance_valid(panel._vendor_service):
		return

	if VendorTradeVM.is_vehicle_item(item_data_source):
		var vehicle_id: String = str(item_data_source.get("vehicle_id", ""))
		if vehicle_id != "" and panel._vendor_service.has_method("sell_vehicle"):
			panel._vendor_service.sell_vehicle(vendor_id, convoy_id, vehicle_id)
			panel._request_authoritative_refresh(convoy_id, vendor_id)
		return

	if bool(item_data_source.get("is_raw_resource", false)):
		var res_type: String = ""
		if float(item_data_source.get("fuel", 0)) > 0:
			res_type = "fuel"
		elif float(item_data_source.get("water", 0)) > 0:
			res_type = "water"
		elif float(item_data_source.get("food", 0)) > 0:
			res_type = "food"
		if res_type != "" and panel._vendor_service.has_method("sell_resource"):
			panel._vendor_service.sell_resource(vendor_id, convoy_id, res_type, float(quantity))
			panel._request_authoritative_refresh(convoy_id, vendor_id)
		return

	var cargo_id: String = str(item_data_source.get("cargo_id", ""))
	if cargo_id != "" and panel._vendor_service.has_method("sell_cargo"):
		panel._vendor_service.sell_cargo(vendor_id, convoy_id, cargo_id, int(quantity))
		panel._request_authoritative_refresh(convoy_id, vendor_id)
