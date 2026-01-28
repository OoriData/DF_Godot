extends RefCounted
class_name VendorPanelContextController

const SettlementModel = preload("res://Scripts/Data/Models/Settlement.gd")

# Settlement snapshot + vendor lookup cache logic extracted from vendor_trade_panel.gd.
# Keeps the panel thin while keeping all the parsing and lookup rules in one place.

static func set_latest_settlements_snapshot(panel: Object, settlements: Array) -> void:
	panel._latest_settlements = settlements
	panel.all_settlement_data_global = settlements

	panel._latest_settlement_models.clear()
	panel._vendors_from_settlements_by_id.clear()
	panel._vendor_id_to_settlement.clear()
	panel._vendor_id_to_name.clear()

	for s_any in settlements:
		if not (s_any is Dictionary):
			continue
		var settlement_dict: Dictionary = s_any
		panel._latest_settlement_models.append(SettlementModel.new(settlement_dict))

		var vendors_any: Variant = settlement_dict.get("vendors", [])
		if vendors_any is Array:
			for v_any in (vendors_any as Array):
				if not (v_any is Dictionary):
					continue
				var vendor_dict: Dictionary = v_any
				var vendor_id: String = str(vendor_dict.get("vendor_id", vendor_dict.get("id", "")))
				if vendor_id == "":
					continue
				panel._vendors_from_settlements_by_id[vendor_id] = vendor_dict
				panel._vendor_id_to_settlement[vendor_id] = settlement_dict

				var name: String = str(vendor_dict.get("name", ""))
				if name != "":
					panel._vendor_id_to_name[vendor_id] = name


static func cache_vendor_name(panel: Object, vendor_id: String, vendor_name: String) -> void:
	if vendor_id == "" or vendor_name == "":
		return
	panel._vendor_id_to_name[vendor_id] = vendor_name


static func resolve_settlement_for_vendor_or_convoy(panel: Object, vendor_id: String, convoy_id: String) -> Dictionary:
	# 1) If we know vendor_id, find settlement containing it.
	if vendor_id != "":
		if panel._vendor_id_to_settlement.has(vendor_id):
			var s0: Variant = panel._vendor_id_to_settlement[vendor_id]
			if s0 is Dictionary:
				return s0

	# 2) Fallback: find settlement at convoy coords.
	if convoy_id != "" and panel.convoy_data is Dictionary and str(panel.convoy_data.get("convoy_id", "")) == convoy_id:
		var cx: int = int(panel.convoy_data.get("x", 999999))
		var cy: int = int(panel.convoy_data.get("y", 999999))
		for s2_any in panel.all_settlement_data_global:
			if s2_any is Dictionary:
				var s2: Dictionary = s2_any
				if int(s2.get("x", 999999)) == cx and int(s2.get("y", 999999)) == cy:
					return s2

	return {}


static func get_vendor_name_for_recipient(panel: Object, recipient_id: Variant) -> String:
	var rid: String = str(recipient_id)
	if rid != "" and panel._vendor_id_to_name.has(rid):
		return str(panel._vendor_id_to_name[rid])

	if rid != "" and panel._vendors_from_settlements_by_id.has(rid):
		var vd_any: Variant = panel._vendors_from_settlements_by_id[rid]
		if vd_any is Dictionary:
			var vd: Dictionary = vd_any
			var nm: String = str(vd.get("name", ""))
			if nm != "":
				panel._vendor_id_to_name[rid] = nm
				return nm

	# Fallback: keep legacy behavior.
	return "Unknown Vendor"
