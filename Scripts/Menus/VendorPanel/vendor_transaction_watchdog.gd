extends RefCounted
class_name VendorTransactionWatchdog

# S13-6 — bounded lifetime for an in-flight vendor transaction.
#
# `_pending_tx.started_ms` was written on every dispatch and read nowhere in the repo, so a request that
# errored without emitting, timed out, or came back 200-with-a-failure-body left
# `_transaction_in_progress = true` forever. on_action_button_pressed() then rejected every later press
# silently and the button stayed disabled on "Processing...".
#
# The registry is `static` because the panel is not a safe place to keep it: the worst variant of the bug
# is the panel being freed before the reply lands (S13-13), which is precisely when nothing is left to
# time the request out. Entries outlive the panel that started them, and whichever panel is alive at the
# next sweep reports them.

## How long a transaction may stay unresolved before we give up on it. Generous — a slow mobile
## connection on a large convoy payload is normal; anything past this is a lost reply, not latency.
const TIMEOUT_MS: int = 20000

# token -> {
#   "vendor_id": String, "convoy_id": String, "mode": String,
#   "item_name": String, "quantity": int,
#   "started_ms": int, "owner_id": int,   # panel instance id at dispatch (0 once it dies)
# }
static var _pending: Dictionary = {}
static var _next_token: int = 0


## Register a dispatched transaction. Returns the token the panel must hand back to resolve().
static func begin(vendor_id: String, convoy_id: String, mode: String, item_name: String, quantity: int, owner_id: int) -> int:
	_next_token += 1
	_pending[_next_token] = {
		"vendor_id": vendor_id,
		"convoy_id": convoy_id,
		"mode": mode,
		"item_name": item_name,
		"quantity": quantity,
		"started_ms": Time.get_ticks_msec(),
		"owner_id": owner_id,
	}
	print("[VendorPanel][DIAG] watchdog BEGIN token=%d %s %d x %s vendor=%s owner=%d" % [_next_token, mode, quantity, item_name, vendor_id, owner_id])
	return _next_token


## Mark a transaction settled (result or error arrived). Safe to call with an unknown/0 token.
static func resolve(token: int, outcome: String) -> void:
	if token <= 0 or not _pending.has(token):
		return
	var rec: Dictionary = _pending[token]
	print("[VendorPanel][DIAG] watchdog RESOLVE token=%d (%s) after %d ms" % [token, outcome, Time.get_ticks_msec() - int(rec.get("started_ms", 0))])
	_pending.erase(token)


## Expired transactions whose dispatching panel no longer exists — nobody else can recover these, so the
## first live panel to sweep adopts them. Entries are removed from the registry as they are returned.
##
## A transaction whose owner is still alive is deliberately LEFT here: that panel times itself out from
## its own `_pending_tx.started_ms`, and letting a sibling tab claim it first would steal the recovery
## from the panel that actually has the stuck button and the projection to revert.
static func sweep_orphans() -> Array:
	if _pending.is_empty():
		return []
	var now_ms: int = Time.get_ticks_msec()
	var expired: Array = []
	for token in _pending.keys():
		var rec: Dictionary = _pending[token]
		if now_ms - int(rec.get("started_ms", now_ms)) < TIMEOUT_MS:
			continue
		if is_instance_id_valid(int(rec.get("owner_id", 0))):
			continue
		rec["token"] = token
		expired.append(rec)
	for rec in expired:
		_pending.erase(int(rec["token"]))
		print("[VendorPanel][DIAG] watchdog ORPHAN TIMEOUT token=%d %s %d x %s vendor=%s owner=%d (freed) — no reply in %d ms" % [int(rec["token"]), str(rec.get("mode", "?")), int(rec.get("quantity", 0)), str(rec.get("item_name", "?")), str(rec.get("vendor_id", "")), int(rec.get("owner_id", 0)), now_ms - int(rec.get("started_ms", now_ms))])
	return expired


## True while any transaction is registered — used to hold off a panel rebuild (S13-13) even when the
## panel that owns it has already gone.
static func has_pending() -> bool:
	return not _pending.is_empty()
