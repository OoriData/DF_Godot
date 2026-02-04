func _is_convoy_at_zero() -> bool:
	if not is_instance_valid(_store) or not _store.has_method("get_convoys"):
		return true # Assume bad state if store missing
	var convoys = _store.get_convoys()
	if not (convoys is Array) or convoys.is_empty():
		return true
	
	# Check the first convoy (tutorial assumes single convoy context)
	var c = convoys[0]
	if c is Dictionary:
		var x = float(c.get("x", 0.0))
		var y = float(c.get("y", 0.0))
		# Tolerance for float comparison, though 0.0 is usually exact from API defaults
		if abs(x) < 0.1 and abs(y) < 0.1:
			return true
	
	return false
