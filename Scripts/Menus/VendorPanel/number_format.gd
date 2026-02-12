extends Node
class_name NumberFormat

static func _is_all_zeros(s: String) -> bool:
	if s.is_empty():
		return true
	for i in range(s.length()):
		if s[i] != "0":
			return false
	return true

static func format_number(val) -> String:
	if val == null:
		return "0"
	var s = str(val)
	# Only insert commas for integer-like strings
	var parts = s.split(".")
	var int_part = parts[0]
	var sign_str = ""
	if int_part.begins_with("-"):
		sign_str = "-"
		int_part = int_part.substr(1)
	var out = ""
	var count = 0
	for i in range(int_part.length() - 1, -1, -1):
		out = int_part[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = "," + out
	if parts.size() > 1 and not _is_all_zeros(parts[1]):
		return sign_str + out + "." + parts[1]
	return sign_str + out

static func fmt_float(v: Variant, decimals: int = 2) -> String:
	if v == null:
		return "0.00"
	var f = 0.0
	if v is float or v is int:
		f = float(v)
	elif v is String and (v as String).is_valid_float():
		f = float(v)
	else:
		return str(v)
	var s = String.num(f, max(0, decimals))
	return format_number(s)

static func fmt_qty(v: Variant) -> String:
	if v == null:
		return "0"
	if v is float:
		# quantities should be whole numbers in UI
		return format_number(str(int(round(v))))
	return format_number(str(v))

static func format_money(amount: Variant, currency_prefix: String = "$") -> String:
	var f = 0.0
	if amount is float or amount is int:
		f = float(amount)
	else:
		return currency_prefix + str(amount)
	var neg = f < 0.0
	var abs_val = absf(f)
	var s = String.num(abs_val, 2)
	var out = format_number(s)
	return ("-" if neg else "") + currency_prefix + out
