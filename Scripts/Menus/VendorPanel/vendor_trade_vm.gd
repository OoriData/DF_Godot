class_name VendorTradeVM
const CompatAdapter = preload("res://Scripts/Menus/VendorPanel/compat_adapter.gd")

static func _to_float_any(v: Variant) -> float:
    if v == null:
        return 0.0
    if v is float or v is int:
        return float(v)
    if v is String:
        var s := (v as String).strip_edges()
        if s.is_valid_float():
            return float(s)
        if s.is_valid_int():
            return float(int(s))
    return 0.0

static func raw_resource_type(item_data_source: Dictionary) -> String:
    if item_data_source == null:
        return ""
    if _to_float_any(item_data_source.get("fuel", 0.0)) > 0.0:
        return "fuel"
    if _to_float_any(item_data_source.get("water", 0.0)) > 0.0:
        return "water"
    if _to_float_any(item_data_source.get("food", 0.0)) > 0.0:
        return "food"
    return ""


static func item_resource_amount(item_data_source: Dictionary, res_key: String) -> float:
    if item_data_source == null:
        return 0.0
    var rk := str(res_key).to_lower()
    if rk == "":
        return 0.0

    # Payloads are not perfectly consistent about key casing (e.g. "Fuel" vs "fuel").
    if item_data_source.has(rk):
        return _to_float_any(item_data_source.get(rk, 0.0))

    var alt := ""
    match rk:
        "fuel":
            alt = "Fuel"
        "water":
            alt = "Water"
        "food":
            alt = "Food"
        _:
            alt = ""

    if alt != "" and item_data_source.has(alt):
        return _to_float_any(item_data_source.get(alt, 0.0))
    return 0.0


static func required_resource_types(item_data_source: Dictionary) -> Array[String]:
    var out: Array[String] = []
    if item_data_source == null:
        return out
    for rt in ["fuel", "water", "food"]:
        if item_resource_amount(item_data_source, rt) > 0.0:
            out.append(rt)
    return out


static func vendor_can_buy_item_resources(vendor_data: Dictionary, item_data_source: Dictionary) -> bool:
    # Cargo that contains resources (fuel/water/food) is only sellable if the vendor
    # has a positive price for ALL contained resource types.
    var required: Array[String] = required_resource_types(item_data_source)
    if required.is_empty():
        return true
    if vendor_data == null:
        return false
    for rt in required:
        if not vendor_can_buy_resource(vendor_data, rt):
            return false
    return true

static func vendor_can_buy_resource(vendor_data: Dictionary, resource_type: String) -> bool:
    if vendor_data == null:
        return false
    var rt := str(resource_type).to_lower()
    if rt == "":
        return false

    # Primary signal: a positive explicit price.
    var key := rt + "_price"
    if vendor_data.has(key) and _to_float_any(vendor_data.get(key)) > 0.0:
        return true

    # Secondary signal: some vendors (notably water-focused ones) may return 0/null prices
    # while still exposing positive stock. Treat positive stock as "vendor supports trading"
    # so resource-bearing containers can be listed in SELL mode and bulk resources can appear.
    if vendor_data.has(rt) and _to_float_any(vendor_data.get(rt)) > 0.0:
        return true

    return false

static func can_show_install_button(is_buy_mode: bool, selected_item: Variant) -> bool:
    return CompatAdapter.can_show_install_button(is_buy_mode, selected_item)

static func contextual_unit_price(item_data_source: Dictionary, mode: String) -> float:
    var p: float = PriceUtil.get_contextual_unit_price(item_data_source, mode)
    if p > 0.0:
        return p

    # Fallbacks for shallow/simple payloads (and unit tests) when PriceUtil cannot
    # infer a price. Prefer explicit fields if present.
    var keys := ["unit_price", "price", "value", "base_value", "base_price", "fuel_price", "water_price", "food_price"]
    for k in keys:
        if item_data_source.has(k):
            var v: Variant = item_data_source.get(k)
            if v is float or v is int:
                var fv := float(v)
                if fv > 0.0:
                    return fv
    return p

static func vehicle_price(vehicle_data: Dictionary) -> float:
    # Vehicles must use API-provided `value` when available.
    if vehicle_data.has("value"):
        var vv: Variant = vehicle_data.get("value")
        if vv is float or vv is int:
            var fvv := float(vv)
            if fvv > 0.0:
                return fvv

    # Fallback for partial vehicle payloads.
    if vehicle_data.has("base_value"):
        var bv: Variant = vehicle_data.get("base_value")
        if bv is float or bv is int:
            var fbv := float(bv)
            if fbv > 0.0:
                return fbv

    return PriceUtil.get_vehicle_price(vehicle_data)

static func is_vehicle_item(d: Dictionary) -> bool:
    if not (d.has("vehicle_id") and d.get("vehicle_id") != null):
        return false
    if (d.has("cargo_id") and d.get("cargo_id") != null) or d.get("is_raw_resource", false):
        return false
    # Phase 2: Relaxed check. If it has a vehicle_id and isn't cargo/resource, treat it as a vehicle.
    # This allows "shallow" vehicle objects (id + name) to be detected so we can trigger
    # the detail fetch.
    return true

static func item_price_components(item_data_source: Dictionary) -> Dictionary:
    return PriceUtil.get_item_price_components(item_data_source)

static func compat_key(vehicle_id: String, part_uid: String) -> String:
    return CompatAdapter.compat_key(vehicle_id, part_uid)

static func compat_payload_is_compatible(payload: Variant) -> bool:
    return CompatAdapter.compat_payload_is_compatible(payload)

static func extract_install_price(payload: Dictionary) -> float:
    return CompatAdapter.extract_install_price(payload)

static func get_part_modifiers_from_cache(part_uid: String, convoy_data: Dictionary, compat_cache: Dictionary) -> Dictionary:
    return CompatAdapter.get_part_modifiers_from_cache(part_uid, convoy_data, compat_cache)

static func build_price_presenter(item_data_source: Dictionary, mode: String, quantity: int, selected_item: Variant) -> Dictionary:
    var is_vehicle := is_vehicle_item(item_data_source)
    var is_bulk_resource: bool = bool(item_data_source.get("is_raw_resource", false))

    var unit_price: float = vehicle_price(item_data_source) if is_vehicle else contextual_unit_price(item_data_source, mode)
    # Keep legacy sell behavior (half price) for normal items, but bulk resources sell at full price.
    if mode == "sell" and not is_vehicle and not is_bulk_resource:
        unit_price /= 2.0
    var total_price: float = unit_price * float(quantity)

    var unit_delivery_reward: float = 0.0
    var total_delivery_reward: float = 0.0
    if item_data_source.has("unit_delivery_reward"):
        var udr_val = item_data_source.get("unit_delivery_reward")
        if udr_val is float or udr_val is int:
            unit_delivery_reward = float(udr_val)
            total_delivery_reward = unit_delivery_reward * float(quantity)

    var bb: String = ""
    if is_vehicle:
        bb += "[b]Price:[/b] %s" % NumberFormat.format_money(unit_price)
    else:
        # Bulk resources have a simplified presenter per UI requirements.
        if is_bulk_resource:
            bb += "[b]Unit Price:[/b] %s\n" % NumberFormat.format_money(unit_price)
            bb += "[b]Total Price:[/b] %s\n" % NumberFormat.format_money(total_price)
            var unit_weight_bulk: float = 0.0
            if selected_item and (selected_item is Dictionary):
                var tqb: int = int((selected_item as Dictionary).get("total_quantity", 0))
                var twb: float = float((selected_item as Dictionary).get("total_weight", 0.0))
                if tqb > 0 and twb > 0.0:
                    unit_weight_bulk = twb / float(tqb)
            if unit_weight_bulk <= 0.0 and item_data_source.has("unit_weight"):
                unit_weight_bulk = _to_float_any(item_data_source.get("unit_weight"))
            var added_weight_bulk := unit_weight_bulk * float(quantity)
            if mode == "sell":
                added_weight_bulk = -added_weight_bulk
            if abs(added_weight_bulk) > 0.0001:
                bb += "[color=gray]Weight Change: %s[/color]\n" % NumberFormat.fmt_float(added_weight_bulk, 2)
            return {
                "bbcode_text": bb.rstrip("\n"),
                "unit_price": unit_price,
                "total_price": total_price,
                "added_weight": added_weight_bulk,
                "added_volume": 0.0,
                "total_delivery_reward": total_delivery_reward
            }

        if mode == "sell":
            bb += "[b]Unit Price:[/b] %s\n" % NumberFormat.format_money(unit_price)
        var price_components = PriceUtil.get_item_price_components(item_data_source)
        var resource_unit_value = price_components.resource_unit_value
        var denom := 2.0 if mode == "sell" else 1.0
        var total_container_value_display: float = (price_components.container_unit_price / denom) * float(quantity)
        var total_resource_value_display: float = (resource_unit_value / denom) * float(quantity)
        var is_mission_cargo := false
        if mode == "sell" and selected_item and (selected_item is Dictionary):
            var sid: Dictionary = selected_item as Dictionary
            is_mission_cargo = sid.has("mission_vendor_name") and not String(sid.get("mission_vendor_name", "")).is_empty() and String(sid.get("mission_vendor_name", "")) != "Unknown Vendor"
        if total_resource_value_display > 0.01 and is_mission_cargo:
            bb += "  [color=gray](Item: %s + Resources: %s)[/color]\n" % [
                NumberFormat.fmt_float(total_container_value_display, 2),
                NumberFormat.fmt_float(total_resource_value_display, 2),
            ]
        bb += "[b]Quantity:[/b] %d\n" % quantity
        bb += "[b]Total Price:[/b] %s\n" % NumberFormat.format_money(total_price)

        var unit_weight := 0.0
        # Prefer aggregated totals when available (avoids schema differences between vendor/convoy payloads).
        if selected_item and (selected_item is Dictionary):
            var tq: int = int((selected_item as Dictionary).get("total_quantity", 0))
            var tw: float = float((selected_item as Dictionary).get("total_weight", 0.0))
            if tq > 0 and tw > 0.0:
                unit_weight = tw / float(tq)
        if unit_weight <= 0.0:
            if item_data_source.has("unit_weight") and item_data_source.get("unit_weight") != null:
                unit_weight = float(item_data_source.get("unit_weight"))
            elif item_data_source.has("weight") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
                unit_weight = float(item_data_source.get("weight", 0.0)) / float(item_data_source.get("quantity", 1.0))
        var added_weight := unit_weight * float(quantity)

        var unit_volume := 0.0
        if selected_item and (selected_item is Dictionary):
            var tq2: int = int((selected_item as Dictionary).get("total_quantity", 0))
            var tv: float = float((selected_item as Dictionary).get("total_volume", 0.0))
            if tq2 > 0 and tv > 0.0:
                unit_volume = tv / float(tq2)
        if unit_volume <= 0.0:
            if item_data_source.has("unit_volume") and item_data_source.get("unit_volume") != null:
                unit_volume = float(item_data_source.get("unit_volume"))
            elif item_data_source.has("volume") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
                unit_volume = float(item_data_source.get("volume", 0.0)) / float(item_data_source.get("quantity", 1.0))
        var added_volume := unit_volume * float(quantity)

        if mode == "sell":
            added_weight = -added_weight
            added_volume = -added_volume

        if abs(added_weight) > 0.0001:
            bb += "[color=gray]Order Weight: %s[/color]\n" % NumberFormat.fmt_float(added_weight, 2)
        if abs(added_volume) > 0.0001:
            bb += "[color=gray]Order Volume: %s[/color]\n" % NumberFormat.fmt_float(added_volume, 2)

        return {
            "bbcode_text": bb.rstrip("\n"),
            "unit_price": unit_price,
            "total_price": total_price,
            "added_weight": added_weight,
            "added_volume": added_volume,
            "total_delivery_reward": total_delivery_reward
        }

    return {
        "bbcode_text": bb.rstrip("\n"),
        "unit_price": unit_price,
        "total_price": total_price,
        "added_weight": 0.0,
        "added_volume": 0.0,
        "total_delivery_reward": total_delivery_reward
    }
