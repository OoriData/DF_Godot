class_name VendorTradeVM
const CompatAdapter = preload("res://Scripts/Menus/VendorPanel/compat_adapter.gd")

static func can_show_install_button(is_buy_mode: bool, selected_item: Variant) -> bool:
    return CompatAdapter.can_show_install_button(is_buy_mode, selected_item)

static func contextual_unit_price(item_data_source: Dictionary, mode: String) -> float:
    var p: float = PriceUtil.get_contextual_unit_price(item_data_source, mode)
    if p > 0.0:
        return p

    # Fallbacks for shallow/simple payloads (and unit tests) when PriceUtil cannot
    # infer a price. Prefer explicit fields if present.
    var keys := ["unit_price", "price", "value", "base_value", "base_price"]
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
    var unit_price: float = vehicle_price(item_data_source) if is_vehicle else contextual_unit_price(item_data_source, mode)
    if mode == "sell" and not is_vehicle:
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
        bb += "[b]Price:[/b] %s\n" % NumberFormat.format_money(unit_price)
        bb += "[b]Quantity:[/b] %d\n" % quantity
        bb += "[b]Total Price:[/b] %s" % NumberFormat.format_money(total_price)
    else:
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
            bb += "  [color=gray](Item: %.2f + Resources: %.2f)[/color]\n" % [total_container_value_display, total_resource_value_display]
        bb += "[b]Quantity:[/b] %d\n" % quantity
        bb += "[b]Total Price:[/b] %s\n" % NumberFormat.format_money(total_price)

        var unit_weight := 0.0
        if item_data_source.has("unit_weight") and item_data_source.get("unit_weight") != null:
            unit_weight = float(item_data_source.get("unit_weight"))
        elif item_data_source.has("weight") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
            unit_weight = float(item_data_source.get("weight", 0.0)) / float(item_data_source.get("quantity", 1.0))
        var added_weight := unit_weight * float(quantity)

        var unit_volume := 0.0
        if item_data_source.has("unit_volume") and item_data_source.get("unit_volume") != null:
            unit_volume = float(item_data_source.get("unit_volume"))
        elif item_data_source.has("volume") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 0.0)) > 0.0:
            unit_volume = float(item_data_source.get("volume", 0.0)) / float(item_data_source.get("quantity", 1.0))
        var added_volume := unit_volume * float(quantity)

        if mode == "sell":
            added_weight = -added_weight
            added_volume = -added_volume

        if abs(added_weight) > 0.0001:
            bb += "[color=gray]Order Weight: %.2f[/color]\n" % added_weight
        if abs(added_volume) > 0.0001:
            bb += "[color=gray]Order Volume: %.2f[/color]\n" % added_volume

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
