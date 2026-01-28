extends RefCounted
class_name VendorPanelCompatController

# Compatibility + install-button plumbing extracted from vendor_trade_panel.gd.
# Owns compatibility cache updates and install button visibility state.

static func update_install_button_state(panel: Object) -> void:
	if not is_instance_valid(panel.install_button):
		return
	var is_buy_mode: bool = false
	if is_instance_valid(panel.trade_mode_tab_container):
		is_buy_mode = int(panel.trade_mode_tab_container.current_tab) == 0
	var can_install: bool = VendorTradeVM.can_show_install_button(is_buy_mode, panel.selected_item)
	panel.install_button.visible = can_install
	panel.install_button.disabled = not can_install


static func on_install_button_pressed(panel: Object) -> void:
	if not panel.selected_item or not panel.selected_item.has("item_data"):
		return
	var idata: Dictionary = panel.selected_item.item_data
	var qty: int = 1
	if is_instance_valid(panel.quantity_spinbox):
		qty = int(panel.quantity_spinbox.value)
	if qty <= 0:
		qty = 1
	var vend_id: String = ""
	if panel.vendor_data and (panel.vendor_data is Dictionary):
		vend_id = str((panel.vendor_data as Dictionary).get("vendor_id", ""))
	panel._emit_install_requested(idata, qty, vend_id)


static func on_part_compatibility_ready(panel: Object, payload: Dictionary) -> void:
	# Cache payload
	var part_cargo_id: String = str(payload.get("part_cargo_id", ""))
	var vehicle_id: String = str(payload.get("vehicle_id", ""))
	if part_cargo_id != "" and vehicle_id != "":
		var key: String = VendorTradeVM.compat_key(vehicle_id, part_cargo_id)
		panel._compat_cache[key] = payload
		# Extract and remember install price for potential future display
		var price: float = VendorTradeVM.extract_install_price(payload)
		if price >= 0.0:
			panel._install_price_cache[key] = price

	# If current selection references this part, refresh fitment-related UI.
	if panel.selected_item and panel.selected_item.has("item_data"):
		var idata: Dictionary = panel.selected_item.item_data
		var uid: String = str(idata.get("cargo_id", idata.get("part_id", "")))
		if uid != "" and uid == part_cargo_id:
			# Avoid recursive loops by only touching fitment-related UI.
			panel._update_fitment_panel()
			update_install_button_state(panel)
