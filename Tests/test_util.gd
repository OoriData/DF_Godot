extends RefCounted

class_name TestUtil

static var failures: int = 0

static func reset() -> void:
	failures = 0

static func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		push_error("ASSERT_TRUE failed: %s" % msg)
		failures += 1

static func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		push_error("ASSERT_EQ failed: %s (got=%s expected=%s)" % [msg, str(a), str(b)])
		failures += 1

static func assert_approx(a: float, b: float, eps: float = 0.0001, msg: String = "") -> void:
	if abs(a - b) > eps:
		push_error("ASSERT_APPROX failed: %s (got=%s expected=%s eps=%s)" % [msg, str(a), str(b), str(eps)])
		failures += 1
