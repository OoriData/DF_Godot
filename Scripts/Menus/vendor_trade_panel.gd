extends Control

const ItemsData = preload("res://Scripts/Data/Items.gd")
const SettlementModel = preload("res://Scripts/Data/Models/Settlement.gd")
const VendorModel = preload("res://Scripts/Data/Models/Vendor.gd")
const CompatAdapter = preload("res://Scripts/Menus/VendorPanel/compat_adapter.gd")
const VendorCargoAggregatorScript = preload("res://Scripts/Menus/VendorPanel/cargo_aggregator.gd")
const SignalWatcherScript = preload("res://addons/gut/signal_watcher.gd")

# Note: panel controllers are globally available via `class_name`.
# Avoid preloading them here to prevent shadowing global identifiers.

# Signals to notify the main menu of transactions
signal item_purchased(item, quantity, total_price)
signal item_sold(item, quantity, total_price)
signal install_requested(item, quantity, vendor_id)

func _emit_item_purchased(item: Variant, quantity: int, total_price: float) -> void:
	emit_signal("item_purchased", item, quantity, total_price)

func _emit_item_sold(item: Variant, quantity: int, total_price: float) -> void:
	emit_signal("item_sold", item, quantity, total_price)

func _emit_install_requested(item: Variant, quantity: int, vendor_id: String) -> void:
	emit_signal("install_requested", item, quantity, vendor_id)

# --- Node References ---
@onready var vendor_item_tree: Tree = %VendorItemTree
@onready var convoy_item_tree: Tree = %ConvoyItemTree
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_preview: TextureRect = %ItemPreview
@onready var item_info_rich_text: RichTextLabel = %ItemInfoRichText
@onready var fitment_panel: VBoxContainer = %FitmentPanel
@onready var fitment_rich_text: RichTextLabel = %FitmentRichText
@onready var comparison_panel: PanelContainer = %ComparisonPanel
@onready var description_toggle_button: Button = %DescriptionToggleButton
@onready var description_panel: VBoxContainer = %DescriptionPanel
@onready var item_description_rich_text: RichTextLabel = %ItemDescriptionRichText
@onready var selected_item_stats: RichTextLabel = %SelectedItemStats
@onready var equipped_item_stats: RichTextLabel = %EquippedItemStats
@onready var quantity_spinbox: SpinBox = %QuantitySpinBox
@onready var delivery_reward_label: RichTextLabel = %DeliveryRewardLabel
@onready var price_label: RichTextLabel = %PriceLabel
@onready var convoy_volume_bar: ProgressBar = %ConvoyVolumeBar
@onready var convoy_weight_bar: ProgressBar = %ConvoyWeightBar
@onready var max_button: Button = %MaxButton
@onready var action_button: Button = %ActionButton
@onready var install_button: Button = %InstallButton
@onready var transaction_quantity_container: HBoxContainer = %TransactionQuantityContainer
@onready var convoy_money_label: Label = %ConvoyMoneyLabel
@onready var convoy_cargo_label: Label = %ConvoyCargoLabel
@onready var trade_mode_tab_container: TabContainer = %TradeModeTabContainer
@onready var toast_notification: Control = %ToastNotification
var loading_panel: Panel = null

# --- Data ---
var vendor_data # Should be set by the parent
var convoy_data = {} # Add this line
var vendor_items = {}
var convoy_items = {}
var current_settlement_data # Will hold the current settlement data for local vendor lookup
var all_settlement_data_global: Array # New: Will hold all settlement data for global vendor lookup
var selected_item = null
var current_mode = "buy" # or "sell"
var _last_selected_item_id = null # <-- Add this line
var _last_selected_ref = null # Track last selected aggregated data reference to avoid resetting quantity repeatedly
var _last_selection_unique_key: String = "" # Used to detect same logical selection even if reference changes
var _last_selected_tree: String = "" # "vendor" or "convoy"; used to restore selection after refreshes
var _last_selected_restore_id: String = "" # Raw cargo_id or vehicle_id string for restoring selection

# Optional deep-link focus intent (set by ConvoySettlementMenu when navigated from preview).
var _pending_focus_intent: Dictionary = {}

var _transaction_in_progress: bool = false
# Backend compatibility cache (per vehicle + part uid), shared semantics with Mechanics menu
var _compat_cache: Dictionary = {} # key: vehicle_id||part_uid -> payload

# Optional: cache install prices per vehicle+part (for future UI use)
var _install_price_cache: Dictionary = {} # key: vehicle_id||part_uid -> float

# Cached convoy cargo stats for transaction projection
var _convoy_used_weight: float = 0.0
var _convoy_total_weight: float = 0.0
var _convoy_used_volume: float = 0.0
var _convoy_total_volume: float = 0.0

# Pending optimistic transaction context (for revert on error)
var _pending_tx: Dictionary = {
	"mode": "",
	"item": {},
	"quantity": 0,
	"selection_key": "",
	"selection_tree": "",
	"money_delta": 0.0,
	"weight_delta": 0.0,
	"volume_delta": 0.0
}

# After a successful transaction, we "commit" the projection for the current selection
# so that when the authoritative convoy snapshot updates, the bars don't double-count.
var _committed_projection: Dictionary = {
	"selection_key": "",
	"selection_tree": "",
	"mode": "",
	"quantity": 0,
}

# Short-lived guard to reject out-of-order convoy snapshots during refresh bursts.
const BASELINE_GUARD_MS: int = 1500
const BASELINE_EPS: float = 0.0001
var _baseline_guard: Dictionary = {
	"active": false,
	"until_ms": 0,
	"mode": "", # "buy" or "sell"
	"min_used_weight": 0.0,
	"min_used_volume": 0.0,
	"max_used_weight": 0.0,
	"max_used_volume": 0.0,
}

# Feedback state for transaction success/failure in the middle panel
var _feedback_data: Dictionary = {} # { "message": "", "type": "success" }

func _clear_committed_projection() -> void:
	_committed_projection.selection_key = ""
	_committed_projection.selection_tree = ""
	_committed_projection.mode = ""
	_committed_projection.quantity = 0

func _apply_committed_projection_scale(quantity: int, added_volume: float, added_weight: float) -> Dictionary:
	# If we just completed a transaction for this same logical selection, treat that
	# quantity as "committed" so we don't double-count when the convoy snapshot updates.
	var committed_applies: bool = (
		str(_committed_projection.get("selection_key", "")) == str(_last_selection_unique_key)
		and str(_committed_projection.get("selection_tree", "")) == str(_last_selected_tree)
		and str(_committed_projection.get("mode", "")) == str(current_mode)
	)
	if not committed_applies or quantity <= 0:
		return {"added_volume": added_volume, "added_weight": added_weight}

	var committed_qty: int = maxi(0, int(_committed_projection.get("quantity", 0)))
	var uncommitted_qty: int = maxi(0, quantity - committed_qty)
	if uncommitted_qty == quantity:
		return {"added_volume": added_volume, "added_weight": added_weight}
	if uncommitted_qty <= 0:
		return {"added_volume": 0.0, "added_weight": 0.0}

	var scale: float = float(uncommitted_qty) / float(quantity)
	return {"added_volume": added_volume * scale, "added_weight": added_weight * scale}

func _get_effective_projection_deltas() -> Dictionary:
	# Used to keep capacity bars stable during background convoy/store refreshes.
	if bool(_transaction_in_progress):
		return {
			"volume": float(_pending_tx.get("volume_delta", 0.0)),
			"weight": float(_pending_tx.get("weight_delta", 0.0)),
		}
	if not (_panel_initialized and selected_item):
		return {"volume": 0.0, "weight": 0.0}

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item
	var quantity: int = int(quantity_spinbox.value) if is_instance_valid(quantity_spinbox) else 1
	var pr = VendorTradeVM.build_price_presenter(item_data_source, str(current_mode), quantity, selected_item)
	var added_w: float = float(pr.get("added_weight", 0.0))
	var added_v: float = float(pr.get("added_volume", 0.0))
	var scaled := _apply_committed_projection_scale(quantity, added_v, added_w)
	return {"volume": float(scaled.get("added_volume", 0.0)), "weight": float(scaled.get("added_weight", 0.0))}

func _commit_projection_from_pending_tx() -> void:
	if not (_pending_tx is Dictionary):
		return
	var qty: int = int(_pending_tx.get("quantity", 0))
	var key: String = str(_pending_tx.get("selection_key", ""))
	var tree: String = str(_pending_tx.get("selection_tree", ""))
	var mode: String = str(_pending_tx.get("mode", ""))
	if qty <= 0 or key.is_empty() or tree.is_empty() or mode.is_empty():
		return
	_committed_projection.selection_key = key
	_committed_projection.selection_tree = tree
	_committed_projection.mode = mode
	_committed_projection.quantity = qty

func _clear_pending_tx() -> void:
	_pending_tx.mode = ""
	_pending_tx.item = {}
	_pending_tx.quantity = 0
	_pending_tx.selection_key = ""
	_pending_tx.selection_tree = ""
	_pending_tx.money_delta = 0.0
	_pending_tx.weight_delta = 0.0
	_pending_tx.volume_delta = 0.0

func _extract_capacity_stats_from_convoy(convoy: Dictionary) -> Dictionary:
	# Returns used/total for volume + weight when the keys exist.
	# If keys are missing, totals will be 0.
	var total_volume: float = float(convoy.get("total_cargo_capacity", 0.0))
	var free_volume: float = float(convoy.get("total_free_space", 0.0))
	var used_volume: float = max(0.0, total_volume - free_volume)
	var total_weight: float = float(convoy.get("total_weight_capacity", 0.0))
	var remaining_weight: float = float(convoy.get("total_remaining_capacity", 0.0))
	var used_weight: float = max(0.0, total_weight - remaining_weight)
	return {
		"total_volume": total_volume,
		"used_volume": used_volume,
		"total_weight": total_weight,
		"used_weight": used_weight,
	}

func _baseline_guard_is_active() -> bool:
	if not bool(_baseline_guard.get("active", false)):
		return false
	var now_ms: int = Time.get_ticks_msec()
	if now_ms > int(_baseline_guard.get("until_ms", 0)):
		_baseline_guard.active = false
		return false
	return true

func _activate_baseline_guard(mode: String, used_volume: float, used_weight: float) -> void:
	_baseline_guard.active = true
	_baseline_guard.until_ms = Time.get_ticks_msec() + BASELINE_GUARD_MS
	_baseline_guard.mode = mode
	if mode == "buy":
		_baseline_guard.min_used_volume = used_volume
		_baseline_guard.min_used_weight = used_weight
		_baseline_guard.max_used_volume = 0.0
		_baseline_guard.max_used_weight = 0.0
	else:
		_baseline_guard.max_used_volume = used_volume
		_baseline_guard.max_used_weight = used_weight
		_baseline_guard.min_used_volume = 0.0
		_baseline_guard.min_used_weight = 0.0

func _should_accept_convoy_snapshot(convoy: Dictionary) -> bool:
	if not _baseline_guard_is_active():
		return true
	var stats := _extract_capacity_stats_from_convoy(convoy)
	var used_v: float = float(stats.get("used_volume", 0.0))
	var used_w: float = float(stats.get("used_weight", 0.0))
	# If totals are missing (0), we can't meaningfully compare; accept.
	if float(stats.get("total_volume", 0.0)) <= 0.0 and float(stats.get("total_weight", 0.0)) <= 0.0:
		return true
	var mode: String = str(_baseline_guard.get("mode", ""))
	if mode == "buy":
		# Reject regressions.
		if used_v + BASELINE_EPS < float(_baseline_guard.get("min_used_volume", 0.0)):
			return false
		if used_w + BASELINE_EPS < float(_baseline_guard.get("min_used_weight", 0.0)):
			return false
		return true
	elif mode == "sell":
		# Reject increases.
		if used_v - BASELINE_EPS > float(_baseline_guard.get("max_used_volume", 0.0)):
			return false
		if used_w - BASELINE_EPS > float(_baseline_guard.get("max_used_weight", 0.0)):
			return false
		return true
	return true

func _maybe_finalize_optimistic_tx_on_incoming_convoy(convoy: Dictionary) -> void:
	# If a convoy snapshot arrives that already includes the optimistic delta,
	# stop applying `_pending_tx` immediately to avoid a brief double-count.
	if not bool(_transaction_in_progress):
		return
	if int(_pending_tx.get("quantity", 0)) <= 0:
		return
	var mode: String = str(_pending_tx.get("mode", ""))
	if mode != "buy" and mode != "sell":
		return
	var stats := _extract_capacity_stats_from_convoy(convoy)
	var incoming_used_v: float = float(stats.get("used_volume", 0.0))
	var incoming_used_w: float = float(stats.get("used_weight", 0.0))
	var start_used_v: float = float(_pending_tx.get("start_used_volume", _convoy_used_volume))
	var start_used_w: float = float(_pending_tx.get("start_used_weight", _convoy_used_weight))
	var expected_used_v: float = start_used_v + float(_pending_tx.get("volume_delta", 0.0))
	var expected_used_w: float = start_used_w + float(_pending_tx.get("weight_delta", 0.0))
	# Tolerance: treat values as matching if they are within 5% of delta or 0.5 absolute.
	var tol_v: float = max(0.5, abs(float(_pending_tx.get("volume_delta", 0.0))) * 0.05)
	var tol_w: float = max(0.5, abs(float(_pending_tx.get("weight_delta", 0.0))) * 0.05)

	var matches_v := true
	var matches_w := true
	if float(stats.get("total_volume", 0.0)) > 0.0:
		matches_v = abs(incoming_used_v - expected_used_v) <= tol_v
	if float(stats.get("total_weight", 0.0)) > 0.0:
		matches_w = abs(incoming_used_w - expected_used_w) <= tol_w

	if matches_v and matches_w:
		_commit_projection_from_pending_tx()
		_transaction_in_progress = false
		_clear_pending_tx()
		_activate_baseline_guard(mode, incoming_used_v, incoming_used_w)

func _try_set_convoy_data(next_convoy: Dictionary) -> bool:
	if not (next_convoy is Dictionary) or next_convoy.is_empty():
		return false
	_maybe_finalize_optimistic_tx_on_incoming_convoy(next_convoy)
	if not _should_accept_convoy_snapshot(next_convoy):
		return false
	self.convoy_data = next_convoy
	return true

func _looks_like_authoritative_convoy_snapshot(d: Dictionary) -> bool:
	# Transaction responses and store snapshots typically include these capacity keys.
	# If present, we should not keep applying optimistic deltas on top of them.
	return d.has("total_cargo_capacity") or d.has("total_free_space") or d.has("total_weight_capacity") or d.has("total_remaining_capacity")

# Debounced vendor refresh to avoid mid-purchase flicker
var _refresh_timer: SceneTreeTimer = null
var _pending_refresh: bool = false
const REFRESH_DEBOUNCE_S: float = 0.25
const DATA_READY_COOLDOWN_MS: int = 600

# Perf and logging controls
@export var perf_log_enabled: bool = true
var _txn_t0_ms: int = -1

# Optional loading overlay toggle (default off to avoid blocking input)
@export var show_loading_overlay: bool = false

# Refresh guards to avoid duplicate panel reloads
var _refresh_in_flight: bool = false
var _awaiting_panel_data: bool = false
var _last_selection_change_ms: int = 0 # guard to avoid interrupting fresh selections
var _bold_font_cache: FontVariation = null # reused bold font for rows to avoid recreating
var _panel_initialized: bool = false # after first full payload populate, ignore stray updates when not in-flight
var _refresh_seq: int = 0 # monotonically increasing refresh session id
var _current_refresh_id: int = -1 # id of the active refresh
var _refresh_t0_ms: int = -1 # start time of active refresh
var _last_data_ready_ms: int = -1 # last time we processed vendor_panel_data_ready
var _watchdog_retries: Dictionary = {} # refresh_id -> true (prevent multiple retries per cycle)
var _signal_watcher = null

func _is_panel_initialized() -> bool:
	return _panel_initialized

# These accessors exist mainly because key pieces of selection logic are now handled
# by external controllers (which Godot's linter does not treat as "usage").
func _get_last_selected_item_id() -> Variant:
	return _last_selected_item_id

func _get_last_selected_ref() -> Variant:
	return _last_selected_ref

func _get_last_selection_unique_key() -> String:
	return _last_selection_unique_key

func _get_mechanics_service() -> Node:
	return _mechanics_service

func _get_install_price_cache() -> Dictionary:
	return _install_price_cache

func _get_refresh_timer() -> SceneTreeTimer:
	return _refresh_timer

func _get_last_data_ready_ms() -> int:
	return _last_data_ready_ms

func _get_watchdog_retries() -> Dictionary:
	return _watchdog_retries

func _get_latest_settlements() -> Array:
	return _latest_settlements

func _get_latest_settlement_models() -> Array:
	return _latest_settlement_models

func _get_vendors_from_settlements_by_id() -> Dictionary:
	return _vendors_from_settlements_by_id

func _get_vendor_id_to_settlement() -> Dictionary:
	return _vendor_id_to_settlement

func _get_vendor_id_to_name() -> Dictionary:
	return _vendor_id_to_name

func _is_transaction_in_progress() -> bool:
	return _transaction_in_progress

func _get_pending_tx() -> Dictionary:
	return _pending_tx

func _get_pending_refresh() -> bool:
	return _pending_refresh

func _get_txn_t0_ms() -> int:
	return _txn_t0_ms

func _get_refresh_in_flight() -> bool:
	return _refresh_in_flight

func _get_awaiting_panel_data() -> bool:
	return _awaiting_panel_data

func _get_refresh_seq() -> int:
	return _refresh_seq

func _get_current_refresh_id() -> int:
	return _current_refresh_id

func _get_refresh_t0_ms() -> int:
	return _refresh_t0_ms

# --- Services / State (Phase C: no GameDataManager dependency) ---
@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _vendor_service: Node = get_node_or_null("/root/VendorService")
@onready var _mechanics_service: Node = get_node_or_null("/root/MechanicsService")
@onready var _api: Node = get_node_or_null("/root/APICalls")

var _active_convoy_id: String = ""
var _active_vendor_id: String = ""

var _latest_settlements: Array = []

# Typed/cache helpers for high-traffic vendor + settlement lookups
var _latest_settlement_models: Array = []
var _vendors_from_settlements_by_id: Dictionary = {} # vendor_id -> vendor Dictionary
var _vendor_id_to_settlement: Dictionary = {} # vendor_id -> settlement Dictionary
var _vendor_id_to_name: Dictionary = {} # vendor_id -> vendor name String

func _vendor_data_with_price_fallback(vd_in: Variant) -> Dictionary:
	var vd: Dictionary = vd_in if (vd_in is Dictionary) else {}
	var vid: String = str(vd.get("vendor_id", vd.get("id", "")))
	if vid == "":
		return vd
	
	if perf_log_enabled:
		print("[PriceFallback] RAW VENDOR DATA for ", vid, ":")
		print("  water=", str(vd.get("water", "MISSING")), ", water_price=", str(vd.get("water_price", "MISSING")))
		print("  fuel=", str(vd.get("fuel", "MISSING")), ", fuel_price=", str(vd.get("fuel_price", "MISSING")))
		print("  food=", str(vd.get("food", "MISSING")), ", food_price=", str(vd.get("food_price", "MISSING")))
	
	var out: Dictionary = vd.duplicate(true)
	var price_keys = ["fuel_price", "water_price", "food_price"]
	
	# Determine which keys need a fallback
	var keys_to_fix = []
	for k in price_keys:
		var val = out.get(k)
		var valid_positive := false
		if (val is float or val is int) and float(val) > 0.0:
			valid_positive = true
		
		if not valid_positive:
			keys_to_fix.append(k)
	
	if keys_to_fix.is_empty():
		return out

	if perf_log_enabled:
		print("[PriceFallback] Vendor %s needs fallback for keys: %s" % [vid, keys_to_fix])

	# Strategy 1: Look at the specific vendor record from global settlement data
	if not _vendors_from_settlements_by_id.is_empty():
		var global_v = _vendors_from_settlements_by_id.get(vid)
		if global_v is Dictionary:
			for k in keys_to_fix:
				var fv = global_v.get(k)
				if (fv is float or fv is int or fv is String) and float(fv) > 0.0:
					out[k] = fv
					if perf_log_enabled:
						print("[PriceFallback] Found %s = %s via global vendor record for %s" % [k, fv, vid])
	
	# Re-check keys to fix
	var remaining_keys = []
	for k in keys_to_fix:
		var cur_val = out.get(k)
		if not (cur_val is float or cur_val is int) or float(cur_val) <= 0.0:
			remaining_keys.append(k)
	
	if remaining_keys.is_empty():
		return out
		
	# Strategy 2: Look at the settlement and other vendors in the same settlement
	var sett = _vendor_id_to_settlement.get(vid)
	if sett is Dictionary:
		# First check the SETTLEMENT ITSELF for resource prices
		if perf_log_enabled:
			print("[PriceFallback] Strategy 2a: Checking settlement '%s' for resource prices: %s" % [sett.get("name", "Unknown"), remaining_keys])
		
		var still_needed_after_sett = []
		for k in remaining_keys:
			var sv = sett.get(k)
			if sv != null and (sv is float or sv is int or sv is String) and float(sv) > 0.0:
				out[k] = sv
				if perf_log_enabled:
					print("[PriceFallback] Found %s = %s from settlement itself" % [k, sv])
			else:
				still_needed_after_sett.append(k)
		remaining_keys = still_needed_after_sett
		
		if remaining_keys.is_empty():
			return out
		
		# Then check other vendors in the settlement
		var vendors = sett.get("vendors", [])
		if perf_log_enabled:
			print("[PriceFallback] Strategy 2b: Searching %d vendors in settlement for remaining keys: %s" % [vendors.size() if vendors is Array else 0, remaining_keys])
		if vendors is Array:
			for v_any in vendors:
				if not (v_any is Dictionary): continue
				var v_dict: Dictionary = v_any
				var v_id = str(v_dict.get("vendor_id", v_dict.get("id", "")))
				# Don't check ourselves again (already did in Strategy 1 effectively)
				if v_id == vid:
					continue
				
				# Try to fill remaining keys
				var still_needed = []
				for k in remaining_keys:
					var sv = v_dict.get(k)
					if sv != null and (sv is float or sv is int or sv is String) and float(sv) > 0.0:
						out[k] = sv
						if perf_log_enabled:
							print("[PriceFallback] Found %s = %s via neighbor vendor %s in settlement" % [k, sv, v_id])
					else:
						still_needed.append(k)
				remaining_keys = still_needed
				if remaining_keys.is_empty():
					break
	
	if remaining_keys.is_empty():
		return out
		
	# Strategy 3: Global Scan (Last Resort)
	if perf_log_enabled:
		print("[PriceFallback] Strategy 3: Scanning ALL settlements for remaining keys: %s" % [remaining_keys])
	
	for s_any in _latest_settlements:
		if not (s_any is Dictionary): continue
		var s_dict: Dictionary = s_any
		var s_vendors = s_dict.get("vendors", [])
		if s_vendors is Array:
			for v_any in s_vendors:
				if not (v_any is Dictionary): continue
				var v_dict: Dictionary = v_any
				
				var still_needed = []
				for k in remaining_keys:
					var gv = v_dict.get(k)
					if gv != null and (gv is float or gv is int or gv is String) and float(gv) > 0.0:
						out[k] = gv
						if perf_log_enabled:
							print("[PriceFallback] GLOBAL MATCH: Found %s = %s at %s (%s)" % [k, gv, v_dict.get("name", "Unknown"), s_dict.get("name", "Unknown")])
					else:
						still_needed.append(k)
				remaining_keys = still_needed
				if remaining_keys.is_empty():
					break
		if remaining_keys.is_empty():
			break

	return out

func _get_bold_font_for(node: Control) -> FontVariation:
	if _bold_font_cache != null:
		return _bold_font_cache
	var default_font = node.get_theme_font("font") if is_instance_valid(node) else null
	if default_font:
		var bf = FontVariation.new()
		bf.set_base_font(default_font)
		bf.set_variation_embolden(1.0)
		_bold_font_cache = bf
	return _bold_font_cache

func _ready() -> void:
	# Connect signals from UI elements
	vendor_item_tree.item_selected.connect(_on_vendor_item_selected)
	# Use item_selected for Tree to update the inspector on a single click.
	convoy_item_tree.item_selected.connect(_on_convoy_item_selected)
	trade_mode_tab_container.tab_changed.connect(_on_tab_changed)

	# Optional loading overlay: bind only if present
	if has_node("%LoadingPanel"):
		loading_panel = %LoadingPanel

	if is_instance_valid(max_button):
		max_button.pressed.connect(_on_max_button_pressed)
	else:
		printerr("VendorTradePanel: 'MaxButton' node not found. Please check the scene file.")

	if is_instance_valid(action_button):
		action_button.pressed.connect(_on_action_button_pressed)
	else:
		printerr("VendorTradePanel: 'ActionButton' node not found. Please check the scene file.")

	# Ensure BBCode is enabled for rich text labels we compose
	if is_instance_valid(price_label):
		price_label.bbcode_enabled = true
	if is_instance_valid(delivery_reward_label):
		delivery_reward_label.bbcode_enabled = true

	if is_instance_valid(install_button):
		install_button.visible = false
		install_button.disabled = true
		install_button.pressed.connect(_on_install_button_pressed)
	else:
		printerr("VendorTradePanel: 'InstallButton' node not found. Please check the scene file.")

	quantity_spinbox.value_changed.connect(_on_quantity_changed)
	if is_instance_valid(description_toggle_button):
		description_toggle_button.pressed.connect(_on_description_toggle_pressed)
	else:
		printerr("VendorTradePanel: 'DescriptionToggleButton' node not found. Please check the scene file.")

	# Subscribe to canonical sources (Hub/Store) instead of GameDataManager.
	if is_instance_valid(_hub):
		var cb_hub_ready := Callable(self, "_on_hub_vendor_panel_ready")
		if _hub.has_signal("vendor_panel_ready") and not _hub.vendor_panel_ready.is_connected(cb_hub_ready):
			_hub.vendor_panel_ready.connect(cb_hub_ready)
		if _hub.has_signal("vendor_preview_ready") and not _hub.vendor_preview_ready.is_connected(_on_hub_vendor_preview_ready):
			_hub.vendor_preview_ready.connect(_on_hub_vendor_preview_ready)
		if _hub.has_signal("convoys_changed") and not _hub.convoys_changed.is_connected(_on_convoys_changed):
			_hub.convoys_changed.connect(_on_convoys_changed)
		if _hub.has_signal("convoy_updated") and not _hub.convoy_updated.is_connected(_on_convoy_updated):
			_hub.convoy_updated.connect(_on_convoy_updated)
	if is_instance_valid(_store):
		var cb_convoys := Callable(self, "_on_convoys_changed")
		var cb_map := Callable(self, "_on_store_map_changed")
		var cb_user := Callable(self, "_on_user_data_updated")
		if _store.has_signal("convoys_changed") and not _store.convoys_changed.is_connected(cb_convoys):
			_store.convoys_changed.connect(cb_convoys)
		if _store.has_signal("map_changed") and not _store.map_changed.is_connected(cb_map):
			_store.map_changed.connect(cb_map)
		if _store.has_signal("user_changed") and not _store.user_changed.is_connected(cb_user):
			_store.user_changed.connect(cb_user)
		# Pull initial snapshots if available
		if _store.has_method("get_settlements"):
			var pre_cached = _store.get_settlements()
			if pre_cached is Array and not (pre_cached as Array).is_empty():
				_set_latest_settlements_snapshot(pre_cached)
		if _store.has_method("get_convoys") and _active_convoy_id != "":
			convoy_data = _get_convoy_by_id(_active_convoy_id)
		if _store.has_method("get_user"):
			_on_user_data_updated(_store.get_user())

	if is_instance_valid(_vendor_service):
		if _vendor_service.has_signal("vehicle_data_received") and not _vendor_service.vehicle_data_received.is_connected(_on_service_vehicle_data_received):
			_vendor_service.vehicle_data_received.connect(_on_service_vehicle_data_received)

	# Hook backend part compatibility so vendor UI can display the same truth as mechanics.
	if is_instance_valid(_api) and _api.has_signal("part_compatibility_checked") and not _api.part_compatibility_checked.is_connected(_on_part_compatibility_ready):
		_api.part_compatibility_checked.connect(_on_part_compatibility_ready)
	var txn_cb = Callable(self, "_on_api_transaction_result")
	for sig in ["cargo_bought", "cargo_sold", "vehicle_bought", "vehicle_sold", "resource_bought", "resource_sold"]:
		if _api.has_signal(sig) and not _api.is_connected(sig, txn_cb):
			_api.connect(sig, txn_cb)

	# Enable wrapping for convoy cargo label so multi-line text keeps panel narrow
	if is_instance_valid(convoy_cargo_label):
		convoy_cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	# Initially hide comparison panel until an item is selected
	comparison_panel.hide()
	if is_instance_valid(action_button):
		action_button.disabled = true
	if is_instance_valid(max_button):
		max_button.disabled = true

	# Ensure loading overlay never blocks input during tutorial debugging
	if is_instance_valid(loading_panel):
		loading_panel.visible = false
		loading_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Phase 4: UI no longer listens directly to APICalls transaction events.
	# Refresh cycles are driven via VendorService -> SignalHub vendor_panel_ready and GameStore snapshots.

	# Diagnostics: confirm this instance and signal hookup
	if perf_log_enabled:
		_signal_watcher = SignalWatcherScript.new()
		_signal_watcher.watch_signal(_hub, "vendor_updated")
		_signal_watcher.watch_signal(_hub, "convoy_updated")

		var conn_ok := false
		if is_instance_valid(_hub) and _hub.has_signal("vendor_panel_ready"):
			conn_ok = _hub.vendor_panel_ready.is_connected(Callable(self, "_on_hub_vendor_panel_ready"))
		print("[VendorPanel][DIAG] _ready instance_id=%d perf=%s hub_vendor_panel_ready_connected=%s" % [get_instance_id(), str(perf_log_enabled), str(conn_ok)])

	_make_panels_responsive()
	_apply_text_readability_fixes()

func _make_panels_responsive() -> void:
	# Programmatically wrap Middle and Right panels in ScrollContainers
	var hbox = get_node_or_null("HBoxContainer")
	if not is_instance_valid(hbox): return
	
	var middle = hbox.get_node_or_null("MiddlePanel")
	if is_instance_valid(middle) and not (middle.get_parent() is ScrollContainer):
		_wrap_inv_scroll(middle, 0.4, 2.0)
		
	var right = hbox.get_node_or_null("RightPanel")
	if is_instance_valid(right) and not (right.get_parent() is ScrollContainer):
		_wrap_inv_scroll(right, 0.3, 1.0)

func _wrap_inv_scroll(panel: Control, stretch_ratio_h: float, stretch_ratio_v: float) -> void:
	var parent = panel.get_parent()
	var scroll = ScrollContainer.new()
	scroll.name = panel.name + "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = stretch_ratio_h
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	# Swap
	var idx = panel.get_index()
	parent.remove_child(panel)
	parent.add_child(scroll)
	parent.move_child(scroll, idx)
	scroll.add_child(panel)
	
	# Reset panel flags to fit inside scroll
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0 # Reset ratio as parent scroll handles it

var _semi_bold_font_cache: FontVariation = null

func _get_semi_bold_font_for(node: Control) -> FontVariation:
	if _semi_bold_font_cache != null:
		return _semi_bold_font_cache
	var default_font = node.get_theme_font("font") if is_instance_valid(node) else null
	if default_font:
		var bf = FontVariation.new()
		bf.set_base_font(default_font)
		bf.set_variation_embolden(0.6) # Moderate weight increase
		_semi_bold_font_cache = bf
	return _semi_bold_font_cache

func _apply_text_readability_fixes() -> void:
	# Apply semibold font to small labels to make them appear "thicker" and more readable
	var labels_to_fix = [
		get_node_or_null("%VolumeLabel"), # Using unique names from tscn
		get_node_or_null("HBoxContainer/RightPanel/CapacityBars/VolumeLabel"), # Fallback path
		get_node_or_null("%MassLabel"),
		get_node_or_null("HBoxContainer/RightPanel/CapacityBars/MassLabel"),
		get_node_or_null("HBoxContainer/RightPanel/TransactionQuantityContainer/Label")
	]
	
	for lbl in labels_to_fix:
		if is_instance_valid(lbl) and lbl is Label:
			lbl.add_theme_font_override("font", _get_semi_bold_font_for(lbl))


func _exit_tree() -> void:
	# Disconnect from Hub/Store/API signals that we connected in _ready
	if is_instance_valid(_hub) and _hub.has_signal("vendor_panel_ready"):
		var cb_hub := Callable(self, "_on_hub_vendor_panel_ready")
		if _hub.vendor_panel_ready.is_connected(cb_hub):
			_hub.vendor_panel_ready.disconnect(cb_hub)
		if _hub.has_signal("vendor_preview_ready") and _hub.vendor_preview_ready.is_connected(_on_hub_vendor_preview_ready):
			_hub.vendor_preview_ready.disconnect(_on_hub_vendor_preview_ready)
		if _hub.has_signal("convoys_changed") and _hub.convoys_changed.is_connected(_on_convoys_changed):
			_hub.convoys_changed.disconnect(_on_convoys_changed)
		if _hub.has_signal("convoy_updated") and _hub.convoy_updated.is_connected(_on_convoy_updated):
			_hub.convoy_updated.disconnect(_on_convoy_updated)
	if is_instance_valid(_store):
		var cb_convoys := Callable(self, "_on_convoys_changed")
		var cb_map := Callable(self, "_on_store_map_changed")
		var cb_user := Callable(self, "_on_user_data_updated")
		if _store.has_signal("convoys_changed") and _store.convoys_changed.is_connected(cb_convoys):
			_store.convoys_changed.disconnect(cb_convoys)
		if _store.has_signal("map_changed") and _store.map_changed.is_connected(cb_map):
			_store.map_changed.disconnect(cb_map)
		if _store.has_signal("user_changed") and _store.user_changed.is_connected(cb_user):
			_store.user_changed.disconnect(cb_user)
	if is_instance_valid(_api) and _api.has_signal("part_compatibility_checked"):
		var cb_api := Callable(self, "_on_part_compatibility_ready")
		if _api.part_compatibility_checked.is_connected(cb_api):
			_api.part_compatibility_checked.disconnect(cb_api)
		var txn_cb = Callable(self, "_on_api_transaction_result")
		for sig in ["cargo_bought", "cargo_sold", "vehicle_bought", "vehicle_sold", "resource_bought", "resource_sold"]:
			if _api.has_signal(sig) and _api.is_connected(sig, txn_cb):
				_api.disconnect(sig, txn_cb)
	if is_instance_valid(_vendor_service) and _vendor_service.has_signal("vehicle_data_received"):
		if _vendor_service.vehicle_data_received.is_connected(_on_service_vehicle_data_received):
			_vendor_service.vehicle_data_received.disconnect(_on_service_vehicle_data_received)
	
	if _signal_watcher:
		_signal_watcher.clear()
		_signal_watcher = null

func _set_latest_settlements_snapshot(settlements: Array) -> void:
	VendorPanelContextController.set_latest_settlements_snapshot(self, settlements)

func _get_convoy_by_id(convoy_id: String) -> Dictionary:
	if convoy_id == "":
		return {}
	if not is_instance_valid(_store) or not _store.has_method("get_convoys"):
		return {}
	var all_convoys: Array = _store.get_convoys()
	for c in all_convoys:
		if c is Dictionary and str((c as Dictionary).get("convoy_id", "")) == convoy_id:
			return c
	return {}

# Central refresh entrypoint used by initialize(), transactions, and watchdog.
func _request_authoritative_refresh(convoy_id: String, vendor_id: String) -> void:
	VendorPanelRefreshController.request_authoritative_refresh(self, convoy_id, vendor_id)

# Hub emits vendor_panel_ready with a vendor Dictionary.
func _on_hub_vendor_panel_ready(data: Dictionary) -> void:
	# Guard against mismatching vendor data arriving late
	var incoming_vid = str(data.get("vendor_id", ""))
	if _active_vendor_id != "" and incoming_vid != "" and incoming_vid != _active_vendor_id:
		return
	VendorPanelRefreshController.on_hub_vendor_panel_ready(self, data)

# Hub emits vendor_preview_ready with a vendor Dictionary.
func _on_hub_vendor_preview_ready(data: Dictionary) -> void:
	if data == null or not (data is Dictionary):
		return
	var vid := str((data as Dictionary).get("vendor_id", (data as Dictionary).get("id", "")))
	var nm := str((data as Dictionary).get("name", ""))
	if vid != "" and nm != "":
		VendorPanelContextController.cache_vendor_name(self, vid, nm)
	# If current selection is mission cargo targeting this vendor, refresh inspector text.
	if selected_item and selected_item.has("item_data"):
		var idata: Dictionary = selected_item.item_data
		var rid := str(idata.get("recipient", ""))
		if rid == "":
			# Some mission cargo uses `mission_vendor_id` instead of `recipient`.
			var dr_v: Variant = idata.get("delivery_reward")
			var looks_mission := (dr_v is float or dr_v is int) and float(dr_v) > 0.0
			if looks_mission:
				rid = str(idata.get("mission_vendor_id", ""))
		if rid != "" and rid == vid:
			# Update the aggregated selection dictionary so the inspector builder sees the new name.
			if selected_item is Dictionary:
				(selected_item as Dictionary)["mission_vendor_name"] = nm
			_update_inspector()

func _on_service_vehicle_data_received(data: Dictionary) -> void:
	# Vehicle data prefetch improves inspector/comparison fidelity.
	if data == null or not (data is Dictionary):
		return
	if not selected_item or not selected_item.has("item_data"):
		return
	var sel: Dictionary = selected_item.item_data
	var sel_vid := str(sel.get("vehicle_id", ""))
	var got_vid := str((data as Dictionary).get("vehicle_id", ""))
	if sel_vid != "" and got_vid != "" and sel_vid == got_vid:
		# Merge missing fields without clobbering existing UI-injected values
		for k in (data as Dictionary).keys():
			if not sel.has(k):
				sel[k] = (data as Dictionary)[k]
		_update_inspector()
		_update_comparison()

func _resolve_settlement_for_vendor_or_convoy(vendor_id: String, convoy_id: String) -> Dictionary:
	return VendorPanelContextController.resolve_settlement_for_vendor_or_convoy(self, vendor_id, convoy_id)

func _try_process_refresh() -> void:
	VendorPanelRefreshController.try_process_refresh(self)

func _process_panel_payload_ready() -> void:
	VendorPanelRefreshController.process_panel_payload_ready(self)

# Handler for when GDM emits vendor_panel_data_ready
func _on_vendor_panel_data_ready(vendor_panel_data: Dictionary) -> void:
	VendorPanelRefreshController.on_vendor_panel_data_ready(self, vendor_panel_data)

 

func _update_vendor_ui(update_vendor: bool = true, update_convoy: bool = true) -> void:
	# Use self.vendor_items and self.convoy_items to populate the UI.
	# Allow callers to update only the relevant tree to reduce rebuild cost.
	if update_vendor:
		_ensure_tree_columns(vendor_item_tree)
		_populate_tree_from_agg(vendor_item_tree, self.vendor_items)
	if update_convoy:
		_ensure_tree_columns(convoy_item_tree)
		var agg_to_use: Dictionary = self.convoy_items if (self.convoy_items is Dictionary) else {}
		# In SELL mode, allow selling whole vehicles when appropriate for this vendor
		if _should_show_vehicle_sell_category():
			agg_to_use = _convoy_items_with_sellable_vehicles(agg_to_use)
		_populate_tree_from_agg(convoy_item_tree, agg_to_use)
	_update_convoy_info_display()

func _should_show_vehicle_sell_category() -> bool:
	return VendorPanelVehicleSellController.should_show_vehicle_sell_category(self)

func _convoy_items_with_sellable_vehicles(base_agg: Dictionary) -> Dictionary:
	return VendorPanelVehicleSellController.convoy_items_with_sellable_vehicles(self, base_agg)

func _populate_tree_from_agg(tree: Tree, agg: Dictionary) -> void:
	var t0 := 0
	if perf_log_enabled:
		t0 = Time.get_ticks_msec()
	var rows := VendorTreeBuilder.populate_tree_vendor_rows(tree, agg)
	if perf_log_enabled:
		var dt = Time.get_ticks_msec() - t0
		print("[VendorPanel][Perf] _populate_tree_from_agg rows=", rows, " dt=", dt, " ms for ", tree.name)


# --- Data Initialization ---
func initialize(p_vendor_data, p_convoy_data, p_current_settlement_data, p_all_settlement_data_global) -> void:
	self.vendor_data = p_vendor_data
	self.convoy_data = p_convoy_data
	self.current_settlement_data = p_current_settlement_data
	self.all_settlement_data_global = p_all_settlement_data_global

	# Request an authoritative refresh via services
	var vid := str((self.vendor_data if self.vendor_data is Dictionary else {}).get("vendor_id", ""))
	var cid := str((self.convoy_data if self.convoy_data is Dictionary else {}).get("convoy_id", ""))
	if vid != "" and cid != "":
		_active_vendor_id = vid
		_active_convoy_id = cid
		_request_authoritative_refresh(cid, vid)

	_populate_vendor_list()
	_populate_convoy_list()
	_update_convoy_info_display()
	_on_tab_changed(trade_mode_tab_container.current_tab)

# Add this method to support UI refreshes without re-initializing signals or state
func refresh_data(p_vendor_data, p_convoy_data, p_current_settlement_data, p_all_settlement_data_global) -> void:
	self.vendor_data = p_vendor_data
	self.convoy_data = p_convoy_data
	self.current_settlement_data = p_current_settlement_data
	self.all_settlement_data_global = p_all_settlement_data_global

	# Preserve current selection context for restore after repopulation
	var prev_selected_id := _last_selected_restore_id
	var prev_tree := _last_selected_tree

	_populate_vendor_list()
	_populate_convoy_list()
	_update_convoy_info_display()
	# Do not forcibly clear selection; instead, restore it if we know what was selected
	if typeof(prev_selected_id) == TYPE_STRING and not str(prev_selected_id).is_empty():
		if prev_tree == "vendor":
			_restore_selection(vendor_item_tree, prev_selected_id)
		elif prev_tree == "convoy":
			_restore_selection(convoy_item_tree, prev_selected_id)
	# Keep buttons and panels in sync
	_update_transaction_panel()
	_update_install_button_state()
	# If we were asked to focus a particular item via deep-link, retry after refresh.
	_try_apply_pending_focus_intent()

func _populate_vendor_list() -> void:
	vendor_item_tree.clear()
	if not vendor_data:
		return
	var vd_for_agg := _vendor_data_with_price_fallback(vendor_data)
	var buckets := VendorCargoAggregatorScript.build_vendor_buckets(vd_for_agg, perf_log_enabled, Callable(self, "_get_vendor_name_for_recipient"))
	var root = vendor_item_tree.create_item()
	_populate_category(vendor_item_tree, root, "Mission Cargo", buckets.get("missions", {}))
	_populate_category(vendor_item_tree, root, "Vehicles", buckets.get("vehicles", {}))
	_populate_category(vendor_item_tree, root, "Parts", buckets.get("parts", {}))
	_populate_category(vendor_item_tree, root, "Other", buckets.get("other", {}))
	_populate_category(vendor_item_tree, root, "Resources", buckets.get("resources", {}))
	# Vendor list is now rebuilt; apply any queued deep-link focus request.
	_try_apply_pending_focus_intent()


# --- Deep-link focus API ---

func focus_intent(intent: Dictionary) -> bool:
	# Public API: called by ConvoySettlementMenu to focus a vendor item.
	if not (intent is Dictionary) or intent.is_empty():
		return false
	_pending_focus_intent = intent.duplicate(true)
	return _try_apply_pending_focus_intent()


func try_focus_intent_once(intent: Dictionary) -> bool:
	# Non-persistent focus attempt: returns true only if the item is selectable right now.
	# This is used by ConvoySettlementMenu to probe multiple vendor tabs without leaving
	# pending focus state on every panel.
	if not (intent is Dictionary) or intent.is_empty():
		return false
	if not is_node_ready() or not is_instance_valid(vendor_item_tree):
		return false
	if String(intent.get("target", "")) != "settlement_vendor":
		return false

	var mode := String(intent.get("mode", "buy"))
	if mode == "buy":
		focus_buy_tab()

	var restore_key := String(intent.get("item_restore_key", ""))
	if restore_key == "":
		return false

	return _restore_selection(vendor_item_tree, restore_key)


func _try_apply_pending_focus_intent() -> bool:
	if _pending_focus_intent.is_empty():
		return false
	if not is_node_ready() or not is_instance_valid(vendor_item_tree):
		return false
	if String(_pending_focus_intent.get("target", "")) != "settlement_vendor":
		return false

	# Default to BUY tab for settlement vendor deep-links.
	var mode := String(_pending_focus_intent.get("mode", "buy"))
	if mode == "buy":
		focus_buy_tab()

	var restore_key := String(_pending_focus_intent.get("item_restore_key", ""))
	if restore_key == "":
		return false

	var ok := _restore_selection(vendor_item_tree, restore_key)
	if ok:
		_pending_focus_intent = {}
	return ok

func _populate_convoy_list() -> void:
	convoy_item_tree.clear()
	if not convoy_data:
		return
	var allow_vehicle_sell := _should_show_vehicle_sell_category()
	# Always use price fallback for aggregation to ensure consistent grouping (e.g. water/food).
	# Transaction logic will still enforce vendor's actual buying prices.
	var vd_for_agg = _vendor_data_with_price_fallback(vendor_data)
	var buckets := VendorCargoAggregatorScript.build_convoy_buckets(convoy_data, vd_for_agg, current_mode, perf_log_enabled, Callable(self, "_get_vendor_name_for_recipient"), allow_vehicle_sell)
	if perf_log_enabled and str(current_mode) == "sell":
		var vd: Dictionary = vendor_data if (vendor_data is Dictionary) else {}
		var vdx: Dictionary = vd_for_agg
		print("[VendorPanel][SellDiag] vendor_id=", str(vd.get("vendor_id", "")),
			" has_keys(cargo_inventory/vehicle_inventory)=", vd.has("cargo_inventory"), "/", vd.has("vehicle_inventory"),
			" prices_raw(f/w/food)=", str(vd.get("fuel_price", "<none>")), "/", str(vd.get("water_price", "<none>")), "/", str(vd.get("food_price", "<none>")),
			" prices_used(f/w/food)=", str(vdx.get("fuel_price", "<none>")), "/", str(vdx.get("water_price", "<none>")), "/", str(vdx.get("food_price", "<none>")),
			" allow_vehicle_sell=", allow_vehicle_sell,
			" bucket_sizes(m/v/p/o/r)=", int((buckets.get("missions", {}) as Dictionary).size()), "/", int((buckets.get("vehicles", {}) as Dictionary).size()), "/", int((buckets.get("parts", {}) as Dictionary).size()), "/", int((buckets.get("other", {}) as Dictionary).size()), "/", int((buckets.get("resources", {}) as Dictionary).size()))
	var root = convoy_item_tree.create_item()
	_populate_category(convoy_item_tree, root, "Mission Cargo", buckets.get("missions", {}))
	if allow_vehicle_sell and not (buckets.get("vehicles", {}) as Dictionary).is_empty():
		_populate_category(convoy_item_tree, root, "Vehicles", buckets.get("vehicles", {}))
	# Only show loose/aggregated parts when BUYING. In SELL mode installed vehicle parts are not sellable.
	if current_mode == "buy":
		_populate_category(convoy_item_tree, root, "Parts", buckets.get("parts", {}))
	_populate_category(convoy_item_tree, root, "Other", buckets.get("other", {}))
	_populate_category(convoy_item_tree, root, "Resources", buckets.get("resources", {}))

func _update_convoy_info_display() -> void:
	var deltas := _get_effective_projection_deltas()
	VendorPanelConvoyStatsController.update_convoy_info_display(self, float(deltas.get("volume", 0.0)), float(deltas.get("weight", 0.0)))

func _on_user_data_updated(_user_data: Dictionary):
	# When user data changes (e.g., after a transaction), refresh the display.
	_update_convoy_info_display()

func _on_convoys_changed(convoys: Array) -> void:
	if _active_convoy_id == "":
		return
	for c in convoys:
		if c is Dictionary and str(c.get("convoy_id", "")) == _active_convoy_id:
			_on_convoy_updated(c)
			return

func _on_convoy_updated(convoy: Dictionary) -> void:
	if str(convoy.get("convoy_id", "")) != _active_convoy_id:
		return
	
	if perf_log_enabled and _signal_watcher:
		print("[VendorPanel] Convoy updated via signal. Vendor updated count: ", _signal_watcher.get_emit_count(_hub, "vendor_updated"))

	if not _try_set_convoy_data(convoy):
		return

	# Convoy updates can arrive in bursts after transactions (user refreshes, convoy refreshes).
	# Rebuilding the convoy Tree clears selection and can briefly null out the inspector,
	# which causes capacity bars to "spasm". Only rebuild the convoy tree when it's relevant.
	var is_sell_tab: bool = is_instance_valid(trade_mode_tab_container) and int(trade_mode_tab_container.current_tab) == 1
	var need_convoy_tree_refresh: bool = is_sell_tab or str(_last_selected_tree) == "convoy" or str(current_mode) == "sell"
	if need_convoy_tree_refresh:
		_populate_convoy_list()

	_update_convoy_info_display()


# --- Signal Handlers ---
func _on_tab_changed(tab_index: int) -> void:
	current_mode = "buy" if tab_index == 0 else "sell"
	action_button.text = "Buy" if current_mode == "buy" else "Sell"
	
	# Clear selection and inspector when switching tabs
	selected_item = null
	_clear_committed_projection()
	if vendor_item_tree.get_selected():
		vendor_item_tree.get_selected().deselect(0)
	if convoy_item_tree.get_selected():
		convoy_item_tree.get_selected().deselect(0)
	_clear_inspector()
	if is_instance_valid(action_button):
		action_button.disabled = true
	if is_instance_valid(max_button):
		max_button.disabled = true

	_update_install_button_state()

	# Repopulate convoy list to apply mode-specific filtering (e.g., hide Parts when selling).
	if is_node_ready():
		_populate_convoy_list()

func _on_vendor_item_selected() -> void:
	var tree_item = vendor_item_tree.get_selected()
	# --- START TUTORIAL DEBUG LOG ---
	var item_text = tree_item.get_text(0) if is_instance_valid(tree_item) else "<none>"
	if perf_log_enabled:
		print("[VendorPanel][LOG] _on_vendor_item_selected. Item: '%s'" % item_text)
	# --- END TUTORIAL DEBUG LOG ---
	_last_selected_tree = "vendor"
	_last_selection_change_ms = Time.get_ticks_msec()
	var item = tree_item.get_metadata(0) if tree_item and tree_item.get_metadata(0) != null else null
	# Defer handling to the next idle frame. This is critical to prevent a race condition
	# where the panel resizes in the same frame as the input, causing the Tree to lose focus and deselect the item.
	call_deferred("_handle_new_item_selection", item)

func _on_convoy_item_selected() -> void:
	var tree_item = convoy_item_tree.get_selected()
	_last_selected_tree = "convoy"
	_last_selection_change_ms = Time.get_ticks_msec()
	var item = tree_item.get_metadata(0) if tree_item and tree_item.get_metadata(0) != null else null
	# Defer handling to prevent UI race conditions, same as for the vendor tree.
	call_deferred("_handle_new_item_selection", item)

func _populate_category(target_tree: Tree, root_item: TreeItem, category_name: String, agg_dict: Dictionary) -> void:
	VendorTreeBuilder.populate_category(target_tree, root_item, category_name, agg_dict)

func _ensure_tree_columns(tree: Tree) -> void:
	if not is_instance_valid(tree):
		return
	# Configure a simple single-column layout (previous behavior)
	tree.set_columns(1)
	tree.set_meta("cols", 1)
	tree.set_column_titles_visible(false)
	tree.set_column_expand(0, true)

# --- Display formatting helpers (visual-only) ---
func _fmt_qty(v: Variant) -> String:
	return NumberFormat.fmt_qty(v)

func _fmt_float(v: Variant) -> String:
	return NumberFormat.fmt_float(v, 2)

func _format_number(val) -> String:
	return NumberFormat.format_number(val)

func _tree_column_count(tree: Tree) -> int:
	if not is_instance_valid(tree):
		return 1
	if tree.has_meta("cols"):
		var v = tree.get_meta("cols")
		if v is int:
			return int(v)
	# Fallback to default 1 when metadata is missing
	return 1

func _handle_new_item_selection(p_selected_item) -> void:
	VendorPanelSelectionController.handle_new_item_selection(self, p_selected_item)

func _on_max_button_pressed() -> void:
	VendorPanelTransactionController.on_max_button_pressed(self)

func _on_action_button_pressed() -> void:
	VendorPanelTransactionController.on_action_button_pressed(self)

func _on_quantity_changed(_value: float) -> void:
	_update_transaction_panel()
	_update_install_button_state()

# --- Inspector and Transaction UI Updates ---
func _update_inspector() -> void:
	# --- START TUTORIAL DEBUG LOG ---
	var old_size = size
	if perf_log_enabled:
		print("[VendorPanel][LOG] _update_inspector called. Current panel size: %s" % str(old_size))
	# --- END TUTORIAL DEBUG LOG ---
	if not selected_item:
		return

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item

	# If the selected item is a vehicle, use a dedicated inspector update function and skip the generic one.
	if VendorTradeVM.is_vehicle_item(item_data_source):
		var vehicle_data: Dictionary = item_data_source if item_data_source is Dictionary else {}
		VendorPanelInspectorController.update_vehicle(self, vehicle_data)
		# Fitment panel should be updated for all items, including vehicles (to hide it).
		_update_fitment_panel()
		return

	VendorPanelInspectorController.update_non_vehicle(
		selected_item,
		str(current_mode),
		item_name_label,
		item_preview,
		description_panel,
		description_toggle_button,
		item_description_rich_text,
		item_info_rich_text,
		fitment_panel,
		fitment_rich_text,
		convoy_data,
		_compat_cache
	)
	call_deferred("_log_size_after_update")

func _update_fitment_panel() -> void:
	# Per request: remove the plain-text fitment display to avoid duplicates.
	# The boxed Fitment section is built inside `_rebuild_info_sections`.
	if is_instance_valid(fitment_rich_text):
		fitment_rich_text.visible = false
	if is_instance_valid(fitment_panel):
		fitment_panel.visible = false
	return

func _update_transaction_panel() -> void:
	var item_name_for_log = selected_item.item_data.get("name", "<no_name>") if selected_item and selected_item.has("item_data") else "null"
	if perf_log_enabled:
		if perf_log_enabled:
			print("[VendorTradePanel][LOG] _update_transaction_panel called for item: '%s'" % item_name_for_log)
		

	if not selected_item:
		if perf_log_enabled:
			print("[VendorTradePanel][LOG]   -> No item selected, setting price to $0.")
		price_label.text = "Total Price: %s" % NumberFormat.format_money(0.0)
		if is_instance_valid(delivery_reward_label):
			delivery_reward_label.visible = false
		# Reset capacity bars to current convoy usage
		_refresh_capacity_bars(0.0, 0.0)
		if is_instance_valid(transaction_quantity_container):
			transaction_quantity_container.visible = true
		if is_instance_valid(action_button):
			action_button.disabled = true
		return

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item
	var is_vehicle := VendorTradeVM.is_vehicle_item(item_data_source)
	if is_instance_valid(transaction_quantity_container):
		transaction_quantity_container.visible = not is_vehicle

	# Guard: bulk resources can only be transacted when vendor has a matching positive price.
	var can_transact: bool = true
	if bool(item_data_source.get("is_raw_resource", false)):
		# Use raw vendor pricing here (no fallback), to keep BUY/SELL consistent.
		var vd_guard: Dictionary = vendor_data if (vendor_data is Dictionary) else {}
		var rt_guard: String = VendorTradeVM.raw_resource_type(item_data_source)
		if rt_guard != "" and not VendorTradeVM.vendor_can_buy_resource(vd_guard, rt_guard):
			can_transact = false

	# --- START: UNIFIED PRICE & DISPLAY LOGIC via VM ---
	var quantity = int(quantity_spinbox.value) if is_instance_valid(quantity_spinbox) else 1
	var pr = VendorTradeVM.build_price_presenter(item_data_source, str(current_mode), quantity, selected_item)
	if is_instance_valid(delivery_reward_label):
		delivery_reward_label.visible = float(pr.get("total_delivery_reward", 0.0)) > 0.0
		if float(pr.get("total_delivery_reward", 0.0)) > 0.0:
			delivery_reward_label.text = "[b]Total Delivery Reward:[/b] %s" % NumberFormat.format_money(float(pr.get("total_delivery_reward", 0.0)))
	var bbcode_text = String(pr.get("bbcode_text", ""))
	var added_w: float = float(pr.get("added_weight", 0.0))
	var added_v: float = float(pr.get("added_volume", 0.0))
	var scaled := _apply_committed_projection_scale(quantity, added_v, added_w)
	added_v = float(scaled.get("added_volume", added_v))
	added_w = float(scaled.get("added_weight", added_w))

	_refresh_capacity_bars(added_v, added_w)

	# Trim trailing newline just in case
	if bbcode_text.ends_with("\n"):
		bbcode_text = bbcode_text.substr(0, bbcode_text.length() - 1)
	# Assign composed text
	price_label.text = bbcode_text
	_update_install_button_state()
	if is_instance_valid(action_button):
		action_button.disabled = not can_transact
		if not can_transact:
			action_button.text = "Sell"

func _refresh_capacity_bars(projected_volume_delta: float, projected_weight_delta: float) -> void:
	VendorPanelConvoyStatsController.refresh_capacity_bars(self, projected_volume_delta, projected_weight_delta)

func _is_positive_number(v: Variant) -> bool:
	return (v is float or v is int) and float(v) > 0.0

func _looks_like_part(item_data_source: Dictionary) -> bool:
	# Defer to the centralized classification logic in the ItemsData factory.
	return ItemsData.PartItem._looks_like_part_dict(item_data_source)

# Helper: fetch a modifier value from either top-level or stats dict using a list of alias keys
 

func _update_install_button_state() -> void:
	VendorPanelCompatController.update_install_button_state(self)

func _on_install_button_pressed() -> void:
	VendorPanelCompatController.on_install_button_pressed(self)

# --- Compatibility plumbing (align with Mechanics) ---
 

func _on_part_compatibility_ready(payload: Dictionary) -> void:
	VendorPanelCompatController.on_part_compatibility_ready(self, payload)

 

# Resolve part modifiers from item data or compatibility payload cache
 

# --- Price Calculation Helpers ---

# Returns a Dictionary with container_unit_price and resource_unit_value for the item.
 

# True if this dictionary represents a vehicle record (not cargo that happens to reference a vehicle_id)
 

# Returns the unit price for a vehicle, checking several common fields.
 

# Returns the price per unit for the given item, depending on buy/sell mode.
 

func _on_api_transaction_result(result: Dictionary) -> void:
	# Capture feedback info BEFORE we potentially clear _pending_tx
	var mode_str: String = "bought" if str(current_mode) == "buy" else "sold"
	var qty: int = int(_pending_tx.get("quantity", 1))
	var item_name: String = str(_pending_tx.get("item", {}).get("name", "Item"))
	var total_price: float = abs(float(_pending_tx.get("money_delta", 0.0)))
	var msg: String = "Successfully %s %d %s for %s" % [mode_str, qty, item_name, NumberFormat.format_money(total_price, "")]

	# Commit this transaction's projection so subsequent authoritative convoy updates
	# don't reset the bars to an incorrect projected value.
	if bool(_transaction_in_progress):
		_commit_projection_from_pending_tx()

	# If the transaction result contains an updated convoy object, apply it immediately
	# to the UI. This provides faster feedback than waiting for a full refresh cycle.
	if result.has("convoy_id") and (result.has("vehicle_details_list") or result.has("vehicles")):
		_try_set_convoy_data(result)
		var is_sell_tab: bool = is_instance_valid(trade_mode_tab_container) and int(trade_mode_tab_container.current_tab) == 1
		var need_convoy_tree_refresh: bool = is_sell_tab or str(_last_selected_tree) == "convoy" or str(current_mode) == "sell"
		if need_convoy_tree_refresh:
			_populate_convoy_list()
		_update_convoy_info_display()
		# We now have an authoritative convoy baseline; stop applying optimistic deltas
		# (otherwise the next convoy/store update burst briefly double-counts them).
		if _looks_like_authoritative_convoy_snapshot(result):
			_transaction_in_progress = false
			_clear_pending_tx()

	VendorPanelRefreshController.on_api_transaction_result(self, result)
	
	# Show success feedback and flash bars
	show_transaction_feedback(msg, "success")
	_flash_capacity_bars()

	if is_instance_valid(_hub) and _hub.has_signal("user_refresh_requested"):
		_hub.user_refresh_requested.emit()

func _on_api_transaction_error(error_message: String) -> void:
	VendorPanelRefreshController.on_api_transaction_error(self, error_message)
	
	var friendly_message: String = ErrorTranslator.translate(error_message)
	show_transaction_feedback(friendly_message, "error")

# Updates the comparison panel (stub, fill in as needed)
func _update_comparison() -> void:
	# Hide comparison for vehicles, as there's nothing to compare against.
	if selected_item and selected_item.has("item_data") and selected_item.item_data.has("vehicle_id"):
		if is_instance_valid(comparison_panel):
			comparison_panel.hide()
		return
	
	# Future: Implement comparison logic for parts, etc.

# Clears the inspector panel (stub, fill in as needed)
func _clear_inspector() -> void:
	if is_instance_valid(item_info_rich_text):
		item_info_rich_text.text = ""
	if is_instance_valid(item_name_label):
		item_name_label.text = ""
	if is_instance_valid(item_preview):
		item_preview.texture = null
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.text = ""
	if is_instance_valid(fitment_rich_text):
		fitment_rich_text.text = ""
		fitment_rich_text.visible = false
	if is_instance_valid(fitment_panel):
		fitment_panel.visible = false
	if is_instance_valid(description_panel):
		description_panel.visible = false
	
	# Clear feedback if present
	_feedback_data = {}
	
	# Clear the segmented sections container
	# Clear the segmented sections container
	if is_instance_valid(item_info_rich_text):
		var container: Node = item_info_rich_text.get_parent().get_node_or_null("InfoSectionsContainer")
		if is_instance_valid(container):
			for ch in container.get_children():
				ch.queue_free()

# Helper: recompute aggregate convoy cargo stats (not currently used directly; kept for future refactors)
func _recalculate_convoy_cargo_stats() -> Dictionary:
	return {
		"used_weight": _convoy_used_weight,
		"total_weight": _convoy_total_weight,
		"used_volume": _convoy_used_volume,
		"total_volume": _convoy_total_volume
	}

# Formats money as a string with commas (e.g., 1,234,567)
 

# Looks up the vendor name for a recipient ID (stub, fill in as needed)
func _get_vendor_name_for_recipient(recipient_id) -> String:
	return VendorPanelContextController.get_vendor_name_for_recipient(self, recipient_id)

# Handler for description toggle button (stub, fill in as needed)
func _on_description_toggle_pressed() -> void:
	if is_instance_valid(item_description_rich_text):
		item_description_rich_text.visible = not item_description_rich_text.visible

# --- Loading overlay helpers ---
func _show_loading() -> void:
	# No-op to avoid blocking input with an overlay during tutorial.
	if not is_instance_valid(loading_panel):
		return
	loading_panel.visible = false
	loading_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _hide_loading() -> void:
	if not is_instance_valid(loading_panel):
		return
	loading_panel.visible = false
	loading_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

# Debounced refresh scheduler
func _schedule_refresh() -> void:
	VendorPanelRefreshSchedulerController.schedule_refresh(self)

func _on_refresh_debounce_timeout(t: SceneTreeTimer) -> void:
	VendorPanelRefreshSchedulerController.on_refresh_debounce_timeout(self, t)

func _perform_refresh() -> void:
	VendorPanelRefreshSchedulerController.perform_refresh(self)

	# Fallback disabled to avoid duplicate payloads; rely on API-result immediate request and settlement signal.
# Helper to restore selection in a tree after data refresh

# --- Refresh watchdog: ensures we don't stall silently if no payload arrives ---
func _start_refresh_watchdog(refresh_id: int, timeout_ms: int = 1200) -> void:
	VendorPanelRefreshSchedulerController.start_refresh_watchdog(self, refresh_id, timeout_ms)

func _on_refresh_watchdog_timeout(rid: int) -> void:
	VendorPanelRefreshSchedulerController.on_refresh_watchdog_timeout(self, rid)

func _on_deferred_refresh_timeout() -> void:
	VendorPanelRefreshSchedulerController.on_deferred_refresh_timeout(self)

func _log_size_after_update():
	if perf_log_enabled:
		print("[VendorPanel][LOG] _update_inspector finished. New panel size: %s" % str(size))

func _restore_selection(tree: Tree, item_id) -> bool:
	var on_select := Callable(self, "_handle_new_item_selection")
	var match_fn := Callable(self, "_matches_restore_key")
	return VendorSelectionManager.restore_selection(tree, item_id, on_select, match_fn)

# Helper function to match by special restore keys
func _matches_restore_key(agg_data: Dictionary, key: String) -> bool:
	if not agg_data or not agg_data.has("item_data"):
		return false
	# Prefer matching the explicit stable key if present
	if agg_data.has("stable_key") and str(agg_data.get("stable_key", "")) == str(key):
		return true
	var idata: Dictionary = agg_data.item_data
	
	# Match by unique ID if present
	if idata.has("cargo_id") and str(idata.cargo_id) == key:
		return true
	if idata.has("vehicle_id") and str(idata.vehicle_id) == key:
		return true
		
	if key.begins_with("name:"):
		var nm := str(key.substr(5))
		return str(idata.get("name", "")) == nm
	if key == "res:fuel":
		return bool(idata.get("is_raw_resource", false)) and float(idata.get("fuel", 0.0)) > 0.0
	if key == "res:water":
		return bool(idata.get("is_raw_resource", false)) and float(idata.get("water", 0.0)) > 0.0
	if key == "res:food":
		return bool(idata.get("is_raw_resource", false)) and float(idata.get("food", 0.0)) > 0.0
	return false

# --- Tutorial helpers: target resolution for highlight/gating ---

# Expose the primary action button (Buy/Sell) for highlighting
func get_action_button_node() -> Button:
	return VendorPanelTutorialController.get_action_button_node(self)

# Ensure the Buy tab is selected
func focus_buy_tab() -> void:
	VendorPanelTutorialController.focus_buy_tab(self)

# Find the rect of a vendor item in the tree by display text contains (case-insensitive)
func get_vendor_item_rect_by_text_contains(substr: String) -> Rect2:
	return VendorPanelTutorialController.get_vendor_item_rect_by_text_contains(self, substr)

# --- Segmented Info Panel Helpers ---
# (legacy helper removed; segmented inspector is now driven by
#  VendorPanelInspectorController.update_non_vehicle / update_vehicle)

func show_transaction_feedback(message: String, type: String = "success") -> void:
	_feedback_data = {
		"message": message,
		"type": type
	}
	_update_inspector()
	
	# Show toast if available
	if is_instance_valid(toast_notification) and toast_notification.has_method("show_message"):
		toast_notification.call("show_message", message)
	
	# Clear selection to fulfill user's "clear panel" request
	_last_selected_restore_id = ""
	selected_item = null
	
	# Reset feedback after a delay
	var timer: SceneTreeTimer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		_feedback_data = {}
		_update_inspector()
	)

func _flash_capacity_bars() -> void:
	var flash_color: Color = Color(1.5, 1.5, 1.5, 1.0) # Bright white flash
	var duration: float = 0.6
	
	if is_instance_valid(convoy_volume_bar):
		var tv: Tween = create_tween()
		tv.tween_property(convoy_volume_bar, "modulate", flash_color, duration * 0.3)
		tv.tween_property(convoy_volume_bar, "modulate", Color.WHITE, duration * 0.7)
		
	if is_instance_valid(convoy_weight_bar):
		var tw: Tween = create_tween()
		tw.tween_property(convoy_weight_bar, "modulate", flash_color, duration * 0.3)
		tw.tween_property(convoy_weight_bar, "modulate", Color.WHITE, duration * 0.7)
