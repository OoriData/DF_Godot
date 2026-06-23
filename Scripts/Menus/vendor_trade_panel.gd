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
	print("[VendorTradePanel][DIAG] EMITTING item_purchased on instance_id=%d: %s x%d" % [get_instance_id(), str(item.get("name", "Unknown")) if item is Dictionary else str(item), quantity])
	emit_signal("item_purchased", item, quantity, total_price)

func _emit_item_sold(item: Variant, quantity: int, total_price: float) -> void:
	emit_signal("item_sold", item, quantity, total_price)

func _emit_install_requested(item: Variant, quantity: int, vendor_id: String) -> void:
	emit_signal("install_requested", item, quantity, vendor_id)

# --- Node References ---
# These nodes are now VendorItemList (custom inline-expand list) — the names are kept as
# *_tree to limit churn across the panel + controllers; they are NOT Godot Trees anymore.
@onready var vendor_item_tree: VendorItemList = %VendorItemTree
@onready var convoy_item_tree: VendorItemList = %ConvoyItemTree
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_preview: TextureRect = %ItemPreview
@onready var item_info_rich_text: RichTextLabel = %ItemInfoRichText
@onready var fitment_panel: VBoxContainer = %FitmentPanel
@onready var fitment_rich_text: RichTextLabel = %FitmentRichText
@onready var description_toggle_button: Button = %DescriptionToggleButton
@onready var description_panel: VBoxContainer = %DescriptionPanel
@onready var item_description_rich_text: RichTextLabel = %ItemDescriptionRichText
@onready var quantity_spinbox: QuantityWidget = %QuantitySpinBox
@onready var delivery_reward_label: RichTextLabel = %DeliveryRewardLabel
@onready var price_label: RichTextLabel = %PriceLabel
@onready var convoy_volume_bar: ProgressBar = %ConvoyVolumeBar
@onready var convoy_weight_bar: ProgressBar = %ConvoyWeightBar
@onready var convoy_money_label: Label = %ConvoyMoneyLabel
@onready var max_button: Button = %MaxButton
@onready var action_button: Button = %ActionButton
@onready var install_button: Button = %InstallButton
@onready var transaction_quantity_container: HBoxContainer = %TransactionQuantityContainer
@onready var trade_mode_tab_container: TabContainer = %TradeModeTabContainer
@onready var mode_flip_button: Button = get_node_or_null("%ModeFlipButton")
@onready var toast_notification: Control = %ToastNotification
@onready var cargo_sort_button: MenuButton = get_node_or_null("%CargoSortButton")
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
var _cargo_sort_metric: int = 0 # CargoSorter.SortMetric
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
	"volume": 0.0,
	"weight": 0.0
}

# Guard to prevent selection logic from wiping _last_selected_restore_id during tree clear/rebuild.
var _ignore_selection_signals: bool = false

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
var _is_previewing_destination: bool = false

# Portrait Concept A — holds the MiddlePanel inspector so it can be revealed on first item tap
var _portrait_inspector: Control = null

# Landscape compact inspector: a wrapping grid of stat chips (Off-road, Cargo, Value, Profit, …)
# that replaces the tall verbose Per Unit / Total Order section panels.
var _landscape_stat_box: VBoxContainer = null

# The merged control row ([Buy ⇄][Sort ▾]) — cached so the outer settlement menu can mount the
# vendor-type dropdown here as the first child on mobile: [Vendor ▾][Buy ⇄][Sort ▾].
var _control_row_container: Container = null

func _is_portrait_layout() -> bool:
	var dsm = get_node_or_null("/root/DeviceStateManager")
	return is_instance_valid(dsm) and dsm.get_layout_mode() == 2 # 2 == MOBILE_PORTRAIT

func _is_compact_footer_layout() -> bool:
	# Both mobile orientations use the slim, pinned transaction footer (one-line price).
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if not is_instance_valid(dsm):
		return false
	var m: int = dsm.get_layout_mode()
	return m == 1 or m == 2 # MOBILE_LANDSCAPE or MOBILE_PORTRAIT

func _is_landscape_layout() -> bool:
	var dsm = get_node_or_null("/root/DeviceStateManager")
	return is_instance_valid(dsm) and dsm.get_layout_mode() == 1 # MOBILE_LANDSCAPE

func _get_settings_manager() -> Node:
	return get_node_or_null("/root/SettingsManager")

func _load_cargo_sort_metric_from_settings() -> void:
	var sm := _get_settings_manager()
	if is_instance_valid(sm) and sm.has_method("get_value"):
		_cargo_sort_metric = int(sm.get_value("ui.cargo_sort_metric", 0))

func _save_cargo_sort_metric_to_settings(metric: int) -> void:
	var sm := _get_settings_manager()
	if is_instance_valid(sm) and sm.has_method("set_and_save"):
		sm.set_and_save("ui.cargo_sort_metric", metric)

func _set_cargo_sort_ui_visible(visible: bool) -> void:
	# Toggle the Sort button itself (not its container) — the flip button now shares that row,
	# so hiding the whole container would wrongly hide the Buy/Sell flip too.
	if is_instance_valid(cargo_sort_button):
		cargo_sort_button.visible = visible

func _has_delivery_cargo_in_array(inv_any: Variant) -> bool:
	if not (inv_any is Array):
		return false
	for entry_any in (inv_any as Array):
		if not (entry_any is Dictionary):
			continue
		var d: Dictionary = entry_any
		if ItemsData != null and ItemsData.DeliveryCargoItem and ItemsData.DeliveryCargoItem._looks_like_delivery_dict(d):
			return true
		if NumberFormat.to_f(d.get("delivery_reward"), 0.0) > 0.0 or NumberFormat.to_f(d.get("unit_delivery_reward"), 0.0) > 0.0:
			return true
		if d.get("recipient", null) != null:
			return true
	return false

func _has_delivery_cargo_fast_for_mode(mode: String) -> bool:
	if mode == "sell":
		if convoy_data is Dictionary:
			var cd: Dictionary = convoy_data
			if _has_delivery_cargo_in_array(cd.get("cargo_inventory", [])):
				return true
			if _has_delivery_cargo_in_array(cd.get("all_cargo", [])):
				return true
			if cd.has("vehicle_details_list") and cd.get("vehicle_details_list") is Array:
				for v_any in (cd.get("vehicle_details_list") as Array):
					if not (v_any is Dictionary):
						continue
					var v: Dictionary = v_any
					if _has_delivery_cargo_in_array(v.get("cargo_inventory", [])):
						return true
					if _has_delivery_cargo_in_array(v.get("cargo_items_typed", [])):
						return true
		return false

	if vendor_data is Dictionary:
		var vd: Dictionary = vendor_data
		if _has_delivery_cargo_in_array(vd.get("cargo_inventory", [])):
			return true
		if _has_delivery_cargo_in_array(vd.get("all_cargo", [])):
			return true
	return false

func _update_sort_dropdown_visibility_fast() -> void:
	_set_cargo_sort_ui_visible(_has_delivery_cargo_fast_for_mode(current_mode))

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

	var scale_factor: float = float(uncommitted_qty) / float(quantity)
	if not is_finite(scale_factor):
		scale_factor = 0.0
	return {"added_volume": added_volume * scale_factor, "added_weight": added_weight * scale_factor}

func _get_effective_projection_deltas() -> Dictionary:
	# Used to keep capacity bars stable during background convoy/store refreshes.
	if bool(_transaction_in_progress):
		return {
			"volume": float(_pending_tx.get("volume_delta", 0.0)),
			"weight": float(_pending_tx.get("weight_delta", 0.0)),
		}
	if not selected_item:
		return {"volume": 0.0, "weight": 0.0}

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item
	var quantity: int = int(quantity_spinbox.value) if is_instance_valid(quantity_spinbox) else 1
	var pr = VendorTradeVM.build_price_presenter(item_data_source, str(current_mode), quantity, selected_item)
	var added_w: float = float(pr.get("added_weight", 0.0))
	var added_v: float = float(pr.get("added_volume", 0.0))
	var scaled := _apply_committed_projection_scale(quantity, added_v, added_w)
	var final_v = float(scaled.get("added_volume", 0.0))
	var final_w = float(scaled.get("added_weight", 0.0))
	if not is_finite(final_v): final_v = 0.0
	if not is_finite(final_w): final_w = 0.0
	return {"volume": final_v, "weight": final_w}

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
		# The server snapshot already reflects our change.
		# We "commit" the projection (which effectively stops applying the delta on top of the baseline)
		# but we do NOT clear _pending_tx yet, because we still need it for the final API result toast.
		_commit_projection_from_pending_tx()
		_transaction_in_progress = false # This stops the optimistic projection from being added to totals
		# DO NOT call _clear_pending_tx() here!
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

func _get_last_selected_restore_id() -> Variant:
	return _last_selected_restore_id

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
var _pending_cargo_recipient_lookups: Dictionary = {} # cargo_id -> aggregated item dict ref

# Throttles noisy price-fallback diagnostics (vendor_id -> true)
var _price_fallback_diag_seen: Dictionary = {}

# Throttle one-time map cache debug
var _map_cache_diag_printed: bool = false

func _vendor_data_with_price_fallback(vd_in: Variant) -> Dictionary:
	var vd: Dictionary = vd_in if (vd_in is Dictionary) else {}
	var vid: String = str(vd.get("vendor_id", vd.get("id", ""))).strip_edges()
	if vid == "":
		return vd
	var vendor_name: String = str(vd.get("name", "")).strip_edges()
	if vendor_name == "" and _vendor_id_to_name.has(vid):
		vendor_name = str(_vendor_id_to_name.get(vid, "")).strip_edges()
	var settlement_name: String = ""
	if _vendor_id_to_settlement.has(vid):
		var s_any: Variant = _vendor_id_to_settlement.get(vid)
		if s_any is Dictionary:
			settlement_name = str((s_any as Dictionary).get("name", "")).strip_edges()
	
	if perf_log_enabled:
		print("[PriceFallback] RAW VENDOR DATA for ", vid, ":")
		print("  water=", str(vd.get("water", "MISSING")), ", water_price=", str(vd.get("water_price", "MISSING")))
		print("  fuel=", str(vd.get("fuel", "MISSING")), ", fuel_price=", str(vd.get("fuel_price", "MISSING")))
		print("  food=", str(vd.get("food", "MISSING")), ", food_price=", str(vd.get("food_price", "MISSING")))
	
	var out: Dictionary = vd.duplicate(true)
	var price_keys = ["fuel_price", "water_price", "food_price"]
	
	# Determine which keys need a fallback
	var keys_to_fix: Array = []
	for k in price_keys:
		# IMPORTANT: we only ever fill from the exact same vendor record (Strategy 1).
		# Some vendor endpoints return 0s as placeholders; allow Strategy 1 to provide
		# the authoritative positive value when available.
		if not out.has(k):
			keys_to_fix.append(k)
			continue
		var val: Variant = out.get(k)
		if val == null:
			keys_to_fix.append(k)
			continue
		# Many vendor payloads are partial and use 0 as a placeholder; allow Strategy 1
		# (exact vendor record from settlements) to fill in a positive value when present.
		if val is float or val is int:
			if float(val) == 0.0:
				keys_to_fix.append(k)
				continue
		# If a non-numeric string sneaks in, treat it as missing.
		if val is String:
			var s := (val as String).strip_edges()
			if s == "":
				keys_to_fix.append(k)
				continue
			if not (s.is_valid_float() or s.is_valid_int()):
				keys_to_fix.append(k)
				continue
			if float(s) == 0.0:
				keys_to_fix.append(k)
				continue
	
	if keys_to_fix.is_empty():
		return out

	if perf_log_enabled:
		print("[PriceFallback] vid=%s name=%s settlement=%s needs_fallback=%s" % [
			vid,
			vendor_name,
			settlement_name,
			str(keys_to_fix),
		])

	# Strategy 1 (ONLY): Look at the specific vendor record from global settlement data.
	# Never borrow prices from a settlement or neighboring vendors; that changes vendor behavior.
	# If our cache isn't ready yet, opportunistically refresh it from GameStore.
	if _vendors_from_settlements_by_id.is_empty() or not _vendors_from_settlements_by_id.has(vid):
		if is_instance_valid(_store) and _store.has_method("get_settlements"):
			var ss2: Variant = _store.get_settlements()
			if ss2 is Array and not (ss2 as Array).is_empty():
				_set_latest_settlements_snapshot(ss2 as Array)
				if perf_log_enabled:
					print("[PriceFallback] Refreshed settlement cache from GameStore (settlements=%d)" % int((ss2 as Array).size()))

	if not _vendors_from_settlements_by_id.is_empty():
		var global_v: Variant = _vendors_from_settlements_by_id.get(vid)
		if not (global_v is Dictionary):
			if perf_log_enabled and not _price_fallback_diag_seen.has(vid):
				_price_fallback_diag_seen[vid] = true
				print("[PriceFallback][Diag] vid=%s name=%s settlement=%s missing_global_vendor_record cache_counts vendors=%d settlements=%d store_settlements=%d" % [
					vid,
					vendor_name,
					settlement_name,
					int(_vendors_from_settlements_by_id.size()),
					int((_latest_settlements.size() if _latest_settlements is Array else -1)),
					int((_store.get_settlements().size() if is_instance_valid(_store) and _store.has_method("get_settlements") else -1)),
				])
		if global_v is Dictionary:
			var filled_any: bool = false
			for k in keys_to_fix:
				var fv = (global_v as Dictionary).get(k)
				if (fv is float or fv is int or fv is String) and float(fv) > 0.0:
					out[k] = fv
					filled_any = true
					if perf_log_enabled:
						print("[PriceFallback] Found %s = %s via global vendor record for %s" % [k, fv, vid])
			# If nothing was filled, print a single diagnostic snapshot of what the cache contains.
			if perf_log_enabled and not filled_any and not _price_fallback_diag_seen.has(vid):
				_price_fallback_diag_seen[vid] = true
				var gv: Dictionary = global_v as Dictionary
				print("[PriceFallback][Diag] vid=%s name=%s settlement=%s global_prices(f/w/food)=%s/%s/%s raw_needed=%s" % [
					vid,
					vendor_name,
					settlement_name,
					str(gv.get("fuel_price", "<none>")),
					str(gv.get("water_price", "<none>")),
					str(gv.get("food_price", "<none>")),
					str(keys_to_fix),
				])
				print("[PriceFallback][Diag] cache_counts vendors=%d settlements=%d store_settlements=%d" % [
					int(_vendors_from_settlements_by_id.size()),
					int((_latest_settlements.size() if _latest_settlements is Array else -1)),
					int((_store.get_settlements().size() if is_instance_valid(_store) and _store.has_method("get_settlements") else -1)),
				])

	# If we still don't have a positive value, leave it missing/null/0.
	# Downstream SELL gating relies on vendor_data having a positive price to allow selling.
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

# Deleted: _get_portrait_font_size

func _on_layout_mode_changed(_mode: int, _screen_size: Vector2, _is_mobile: bool) -> void:
	_update_layout_scaling()

func _update_layout_scaling() -> void:
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if not is_instance_valid(dsm): return
	
	var mode = dsm.get_layout_mode()
	var is_portrait = (mode == 2) # MOBILE_PORTRAIT
	var use_mobile = dsm.is_mobile
	
	var btn_font_sz: int
	var tab_font_sz: int
	var tree_font_sz: int
	var btn_min_h: float
	var bar_min_h: float
	var sort_h: float
	var sort_font_sz: int

	if is_portrait:
		btn_font_sz = 25
		tab_font_sz = 23
		tree_font_sz = 17
		# Footer controls were 100px tall, which made the transaction strip eat ~half the
		# panel once an item was selected and pushed the list off-screen. 60px is still a
		# comfortable touch target while keeping the footer compact.
		btn_min_h = 60.0
		bar_min_h = 22.0 # thin one-line meter (label sits beside the bar now, not above)
		sort_h = 52.0
		sort_font_sz = 21
	elif use_mobile: # MOBILE_LANDSCAPE — short viewport, keep the pinned transaction compact
		btn_font_sz = 20
		tab_font_sz = 20
		tree_font_sz = 16
		btn_min_h = 46.0
		bar_min_h = 18.0
		sort_h = 44.0
		sort_font_sz = 16
	else: # DESKTOP
		btn_font_sz = 30
		tab_font_sz = 26
		tree_font_sz = 22
		btn_min_h = 72.0
		bar_min_h = 22.0
		sort_h = 60.0
		sort_font_sz = 16
	
	if is_instance_valid(trade_mode_tab_container):
		var tab_bar = trade_mode_tab_container.get_tab_bar()
		if is_instance_valid(tab_bar):
			tab_bar.add_theme_font_size_override("font_size", tab_font_sz)
	# Tab bar is hidden; the single flip button is the visible mode selector. It's a compact
	# secondary control (the primary Buy/Sell action lives in the footer), so keep it small —
	# content-sized via size_flags and a modest fixed font rather than the larger tab size.
	if is_instance_valid(mode_flip_button):
		mode_flip_button.add_theme_font_size_override("font_size", 18 if is_portrait else 16)

	if is_instance_valid(vendor_item_tree):
		vendor_item_tree.set_name_font_size(tree_font_sz)
	if is_instance_valid(convoy_item_tree):
		convoy_item_tree.set_name_font_size(tree_font_sz)

	if is_instance_valid(item_name_label):
		var name_sz = 38 if is_portrait else (30 if use_mobile else 38)
		item_name_label.add_theme_font_size_override("font_size", name_sz)

	if is_instance_valid(description_toggle_button):
		description_toggle_button.custom_minimum_size.y = sort_h
		description_toggle_button.add_theme_font_size_override("font_size", tab_font_sz)
	if is_instance_valid(item_description_rich_text):
		var desc_sz = 16 if is_portrait else (14 if use_mobile else 20)
		item_description_rich_text.add_theme_font_size_override("normal_font_size", desc_sz)
		item_description_rich_text.add_theme_font_size_override("bold_font_size", desc_sz)
	if is_instance_valid(item_info_rich_text):
		var desc_sz = 16 if is_portrait else (14 if use_mobile else 20)
		item_info_rich_text.add_theme_font_size_override("normal_font_size", desc_sz)
		item_info_rich_text.add_theme_font_size_override("bold_font_size", desc_sz)
	if is_instance_valid(fitment_rich_text):
		var desc_sz = 16 if is_portrait else (14 if use_mobile else 20)
		fitment_rich_text.add_theme_font_size_override("normal_font_size", desc_sz)
		fitment_rich_text.add_theme_font_size_override("bold_font_size", desc_sz)

	if is_instance_valid(action_button):
		action_button.custom_minimum_size.y = btn_min_h
		action_button.add_theme_font_size_override("font_size", btn_font_sz)
		if is_portrait:
			action_button.add_theme_font_override("font", _get_bold_font_for(action_button))
		else:
			action_button.remove_theme_font_override("font")
			
	if is_instance_valid(max_button):
		max_button.custom_minimum_size.y = btn_min_h
		max_button.add_theme_font_size_override("font_size", btn_font_sz)
		if is_portrait:
			max_button.add_theme_font_override("font", _get_bold_font_for(max_button))
		else:
			max_button.remove_theme_font_override("font")
			
	if is_instance_valid(install_button):
		install_button.custom_minimum_size.y = btn_min_h
		install_button.add_theme_font_size_override("font_size", btn_font_sz)
		if is_portrait:
			install_button.add_theme_font_override("font", _get_bold_font_for(install_button))
		else:
			install_button.remove_theme_font_override("font")
		
	if is_instance_valid(quantity_spinbox):
		quantity_spinbox.custom_minimum_size.y = btn_min_h

	if is_instance_valid(convoy_volume_bar):
		convoy_volume_bar.custom_minimum_size.y = bar_min_h
	if is_instance_valid(convoy_weight_bar):
		convoy_weight_bar.custom_minimum_size.y = bar_min_h

	if is_instance_valid(cargo_sort_button):
		cargo_sort_button.custom_minimum_size.y = sort_h
		cargo_sort_button.add_theme_font_size_override("font_size", sort_font_sz)
		if is_portrait:
			cargo_sort_button.add_theme_font_override("font", _get_bold_font_for(cargo_sort_button))
		else:
			cargo_sort_button.remove_theme_font_override("font")

	var right_panel = get_node_or_null("HBoxContainer/RightPanel")
	if is_instance_valid(right_panel):
		var title_sz = 30 if is_portrait else (22 if use_mobile else 30)
		var label_sz = 24 if is_portrait else (16 if use_mobile else 24)
		var money_sz = 28 if is_portrait else (18 if use_mobile else 28)
		
		var transaction_label = right_panel.get_node_or_null("TransactionLabel")
		if is_instance_valid(transaction_label):
			transaction_label.add_theme_font_size_override("font_size", title_sz)
			
		var convoy_money_lbl = right_panel.get_node_or_null("%ConvoyMoneyLabel")
		if is_instance_valid(convoy_money_lbl):
			convoy_money_lbl.add_theme_font_size_override("font_size", money_sz)
			
		var vol_lbl = get_node_or_null("%VolumeLabel")
		if is_instance_valid(vol_lbl):
			vol_lbl.add_theme_font_size_override("font_size", label_sz)

		var mass_lbl = get_node_or_null("%MassLabel")
		if is_instance_valid(mass_lbl):
			mass_lbl.add_theme_font_size_override("font_size", label_sz)
			
	if is_instance_valid(price_label):
		var price_sz = 24 if is_portrait else (16 if use_mobile else 24)
		price_label.add_theme_font_size_override("normal_font_size", price_sz)
		price_label.add_theme_font_size_override("bold_font_size", price_sz)
		
	if is_instance_valid(delivery_reward_label):
		var reward_sz = 24 if is_portrait else (16 if use_mobile else 24)
		delivery_reward_label.add_theme_font_size_override("normal_font_size", reward_sz)
		delivery_reward_label.add_theme_font_size_override("bold_font_size", reward_sz)
	
	var middle = get_node_or_null("HBoxContainer/MiddlePanel")
	if is_instance_valid(middle):
		_force_top_alignment(middle)
	var right = get_node_or_null("HBoxContainer/RightPanel")
	if is_instance_valid(right):
		_force_top_alignment(right)

func _force_top_alignment(node: Node) -> void:
	if not is_instance_valid(node): return
	if node is BoxContainer:
		node.alignment = BoxContainer.ALIGNMENT_BEGIN
	for child in node.get_children():
		_force_top_alignment(child)

func _ready() -> void:

	var dsm = get_node_or_null("/root/DeviceStateManager")
	
	# Ensure the whole panel fills the MenuContainer (PanelContainer) provided by MainScreen
	# This prevents the parent from centering the menu if its content is smaller than the screen.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	if is_instance_valid(dsm):
		if not dsm.layout_mode_changed.is_connected(_on_layout_mode_changed):
			dsm.layout_mode_changed.connect(_on_layout_mode_changed)
			
	_update_layout_scaling()
	
	# Fix for "Bottom Alignment" bug: ensure the legacy label doesn't act as a vertical spacer
	var legacy_label = get_node_or_null("%ItemInfoRichText")
	if is_instance_valid(legacy_label):
		legacy_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN



	# The vendor list always shows buyable wares; the convoy list always shows sellable cargo.
	# This drives which price (buy vs sell) the compact stat line computes.
	if is_instance_valid(vendor_item_tree):
		vendor_item_tree.list_mode = "buy"
	if is_instance_valid(convoy_item_tree):
		convoy_item_tree.list_mode = "sell"

	# Connect signals from UI elements
	vendor_item_tree.item_selected.connect(_on_vendor_item_selected)
	# Use item_selected for Tree to update the inspector on a single click.
	convoy_item_tree.item_selected.connect(_on_convoy_item_selected)
	# Inline "Install" button in the expanded row body (portrait) routes through the compat flow.
	if vendor_item_tree.has_signal("install_pressed"):
		vendor_item_tree.install_pressed.connect(_on_inline_install_pressed)
	trade_mode_tab_container.tab_changed.connect(_on_tab_changed)
	# Single Buy/Sell flip button drives the (tab-bar-hidden) TabContainer pages.
	if is_instance_valid(mode_flip_button):
		mode_flip_button.pressed.connect(_on_mode_flip_pressed)
	_style_mode_toggle()
	_sync_mode_toggle_buttons(trade_mode_tab_container.current_tab)

	# Optional loading overlay: bind only if present
	if has_node("%LoadingPanel"):
		loading_panel = %LoadingPanel

	if is_instance_valid(max_button):
		max_button.pressed.connect(_on_max_button_pressed)
		_style_neutral_button(max_button)
	else:
		printerr("VendorTradePanel: 'MaxButton' node not found. Please check the scene file.")

	if is_instance_valid(action_button):
		action_button.pressed.connect(_on_action_button_pressed)
		_style_primary_button(action_button) # the one accented (verdigris) commit button
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

	if is_instance_valid(cargo_sort_button):
		_load_cargo_sort_metric_from_settings()
		cargo_sort_button.custom_minimum_size.x = 100 # Thinner button
		# Sort is compact and pinned to the right edge of the row. It can't be the element that fills
		# the row's slack because it hides itself when there's no delivery cargo (see
		# _set_cargo_sort_ui_visible) — the always-present Buy/Sell flip fills instead (set in
		# _consolidate_control_row). With the flip expanding, SHRINK_END pushes Sort flush right.
		cargo_sort_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		# Filter-control language: recessed well + verdigris trim, distinct from the action buttons.
		# (Also sets flat=false so the MenuButton actually draws its border.)
		_style_filter_control(cargo_sort_button)

		var popup = cargo_sort_button.get_popup()
		popup.clear()
		popup.add_radio_check_item("Profit Margin/Unit", 0)
		popup.add_radio_check_item("Profit Density/Weight", 1)
		popup.add_radio_check_item("Profit Density/Volume", 2)
		popup.add_radio_check_item("Total Order Profit", 3)
		popup.add_radio_check_item("Distance to Recipient", 4)
		
		# Mobile scaling for Vendor Trade Panel sort popup
		var use_mobile = false
		var is_portrait = false
		if is_instance_valid(dsm):
			is_portrait = dsm.get_is_portrait()
			use_mobile = is_portrait or dsm.get_layout_mode() == 1 # MOBILE_LANDSCAPE
			
		if use_mobile:
			popup.add_theme_font_size_override("font_size", 16)
			popup.add_theme_constant_override("v_separation", 16 if is_portrait else 12)
			var popup_style = StyleBoxFlat.new()
			popup_style.bg_color = Color("#25282a") # Oori Dark Grey
			popup_style.content_margin_left = 24
			popup_style.content_margin_right = 24
			popup_style.content_margin_top = 16 if is_portrait else 12
			popup_style.content_margin_bottom = 16 if is_portrait else 12
			popup_style.border_width_left = 1
			popup_style.border_width_right = 1
			popup_style.border_width_top = 1
			popup_style.border_width_bottom = 1
			popup_style.border_color = Color("#393d47") # Oori Grey
			popup_style.corner_radius_top_left = 6
			popup_style.corner_radius_top_right = 6
			popup_style.corner_radius_bottom_left = 6
			popup_style.corner_radius_bottom_right = 6
			popup.add_theme_stylebox_override("panel", popup_style)
		
		_cargo_sort_metric = clampi(_cargo_sort_metric, 0, max(0, popup.item_count - 1))
		for i in range(popup.item_count):
			popup.set_item_checked(i, i == _cargo_sort_metric)
			
		popup.index_pressed.connect(_on_cargo_sort_selected)
		_update_cargo_sort_button_text()
		_update_sort_dropdown_visibility_fast()

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

	if is_instance_valid(_api) and _api.has_signal("cargo_data_received") and not _api.cargo_data_received.is_connected(_on_cargo_data_received):
		_api.cargo_data_received.connect(_on_cargo_data_received)


	# Action buttons minimum sizes are handled by _update_layout_scaling()
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

	_consolidate_control_row()
	_make_panels_responsive()
	_apply_text_readability_fixes()

func _consolidate_control_row() -> void:
	# The flip button (Buy ⇄) and the Sort dropdown lived on two separate sparse rows, leaving a
	# big dead band above the list. Merge them onto ONE row: [ Buy ⇄ ][ Sort ▾ ]. The Sort button
	# still hides itself (via _set_cargo_sort_ui_visible) when there's no delivery cargo, but the
	# row — and the flip button — always remain.
	var sort_container := get_node_or_null("HBoxContainer/LeftPanel/SortSettingsContainer")
	var mode_toggle := get_node_or_null("HBoxContainer/LeftPanel/ModeToggle")
	if not is_instance_valid(sort_container) or not is_instance_valid(mode_toggle) or not is_instance_valid(mode_flip_button):
		return
	_control_row_container = sort_container # cache for mount_external_vendor_selector()
	if sort_container.has_meta("control_row_merged"):
		return
	# Move the flip button to the front of the Sort row, then retire the now-empty toggle row.
	var flip_parent := mode_flip_button.get_parent()
	if is_instance_valid(flip_parent):
		flip_parent.remove_child(mode_flip_button)
	sort_container.add_child(mode_flip_button)
	sort_container.move_child(mode_flip_button, 0)
	# The flip is the only always-visible control on this row, so it absorbs the horizontal slack
	# (the vendor dropdown hugs its name at the left; Sort hugs the right and can hide). This keeps
	# the row filled edge-to-edge instead of left-packing the controls with dead space on the right.
	mode_flip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sort_container.add_theme_constant_override("separation", 10)
	mode_toggle.visible = false
	sort_container.set_meta("control_row_merged", true)

func mount_external_vendor_selector(selector: Control) -> void:
	# Called by ConvoySettlementMenu (mobile only) to place the shared vendor-type dropdown as the
	# first element of this panel's control row → [Vendor ▾][Buy ⇄][Sort ▾]. Idempotent.
	if not is_instance_valid(selector) or not is_instance_valid(_control_row_container):
		return
	if selector.get_parent() == _control_row_container:
		_control_row_container.move_child(selector, 0)
		return
	if is_instance_valid(selector.get_parent()):
		selector.get_parent().remove_child(selector)
	# Hug the current vendor name (no dead space) rather than expanding to fill the row.
	selector.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	selector.size_flags_stretch_ratio = 1.0
	_control_row_container.add_child(selector)
	_control_row_container.move_child(selector, 0)

func _make_panels_responsive() -> void:
	# Layout-specific restructuring of the native 3-column .tscn:
	#   PORTRAIT  → single vertical stack: inline-expand list + pinned footer (no inspector column).
	#   LANDSCAPE → 2-pane: list (left) | [inspector + pinned transaction] (right). The fixed 320px
	#               transaction column is folded under the inspector so it stops crowding the narrow
	#               (≈55%-width) landscape menu.
	#   DESKTOP   → native 3-column layout (plenty of room).
	var dsm = get_node_or_null("/root/DeviceStateManager")
	var mode: int = dsm.get_layout_mode() if is_instance_valid(dsm) else 0
	var is_portrait: bool = (mode == 2) # 2 == MOBILE_PORTRAIT
	var is_landscape: bool = (mode == 1) # 1 == MOBILE_LANDSCAPE
	# Inline-expand is the inspector in PORTRAIT only. Landscape/desktop keep the separate
	# MiddlePanel inspector (landscape merges it into the right pane), so rows there don't expand.
	if is_instance_valid(vendor_item_tree):
		vendor_item_tree.inline_expand_enabled = is_portrait
	if is_instance_valid(convoy_item_tree):
		convoy_item_tree.inline_expand_enabled = is_portrait

	# Recess each item list into a bordered well so it separates from the patterned background.
	_wrap_list_in_well(vendor_item_tree)
	_wrap_list_in_well(convoy_item_tree)

	var hbox = get_node_or_null("HBoxContainer")
	if not is_instance_valid(hbox):
		return
	if is_portrait:
		_apply_portrait_stack(hbox)
	elif is_landscape:
		_apply_landscape_two_pane(hbox)

func _apply_portrait_stack(hbox: Control) -> void:
	# Godot 4.6 locks `vertical` on HBoxContainer, so we can't flip it. Instead move the
	# three columns into a real VBoxContainer: list → inspector → transaction footer.
	if hbox.has_meta("portrait_stacked"):
		return
	var parent := hbox.get_parent()
	if not is_instance_valid(parent):
		return

	var left = hbox.get_node_or_null("LeftPanel")
	var middle = hbox.get_node_or_null("MiddlePanel")
	var right = hbox.get_node_or_null("RightPanel")

	var vbox := VBoxContainer.new()
	vbox.name = "PortraitStack"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_top = 8
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)

	# Inline-expand Concept A: the LIST owns all the height and each row expands its own
	# inspector in place; the transaction is a slim pinned footer. The separate MiddlePanel
	# inspector is NOT stacked here (the inline row body replaces it in portrait) — it stays
	# parked in the now-hidden hbox.
	for entry in [[left, Control.SIZE_EXPAND_FILL, 3.0], [right, Control.SIZE_SHRINK_END, 1.0]]:
		var p: Control = entry[0]
		if not is_instance_valid(p):
			continue
		hbox.remove_child(p)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = entry[1]
		p.size_flags_stretch_ratio = entry[2]
		p.custom_minimum_size = Vector2(0, p.custom_minimum_size.y) # drop the 320px column width
		vbox.add_child(p)

	# MiddlePanel stays hidden in portrait — the inline row body is the inspector.
	if is_instance_valid(middle):
		middle.visible = false
		_portrait_inspector = null # disable the capped reveal; inline-expand handles inspection

	# Slim the transaction block into a footer: drop the redundant title/money lines
	# (money is already in the top bar) so it reads as one compact strip.
	if is_instance_valid(right):
		_slim_transaction_footer(right)
		_style_footer_module(right)

	parent.add_child(vbox)
	parent.move_child(vbox, hbox.get_index())
	hbox.visible = false # now only holds the (unused) vertical separators
	hbox.set_meta("portrait_stacked", true)

func _apply_landscape_two_pane(hbox: Control) -> void:
	# Collapse the native 3-column layout to 2 panes for the narrow landscape menu:
	#   [ list (left, ~45%) ] | [ inspector (expand) + transaction (pinned bottom) (right, ~55%) ]
	# The transaction column was a 320px FIXED width, which crowded everything in the ~55%-width
	# landscape menu. Folding it under the inspector as a pinned strip frees that horizontal room.
	if hbox.has_meta("landscape_two_paned"):
		return
	var left = hbox.get_node_or_null("LeftPanel")
	var middle = hbox.get_node_or_null("MiddlePanel")
	var right = hbox.get_node_or_null("RightPanel")
	var vsep2 = hbox.get_node_or_null("VSeparator2")
	if not (is_instance_valid(left) and is_instance_valid(middle) and is_instance_valid(right)):
		return

	# Right pane: inspector on top (fills), transaction pinned at the bottom.
	var pane := VBoxContainer.new()
	pane.name = "LandscapeRightPane"
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.size_flags_stretch_ratio = 0.55
	pane.add_theme_constant_override("separation", 6)

	var insert_idx := middle.get_index()
	# Detach inspector + transaction from the HBox and re-home them inside the pane.
	hbox.remove_child(middle)
	if is_instance_valid(vsep2):
		vsep2.visible = false
	hbox.remove_child(right)

	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.size_flags_stretch_ratio = 1.0
	# The 150px preview image + tall transaction block overflowed the short landscape height and
	# pushed the Buy button off the bottom (behind the nav). Drop the preview; the inspector's
	# scrollable stats/description take that space, and the transaction stays pinned + visible.
	_slim_portrait_inspector(middle)
	_build_landscape_stat_label()
	pane.add_child(middle)

	var div := HSeparator.new()
	pane.add_child(div)

	# Transaction pinned at the bottom of the right pane. Slim it (money lives in the top bar) so
	# the Buy button always sits above the nav bar instead of being clipped below it.
	_slim_transaction_footer(right)
	_reorg_landscape_transaction(right)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_END
	right.size_flags_stretch_ratio = 1.0
	right.custom_minimum_size = Vector2(0, right.custom_minimum_size.y) # drop the 320px fixed width
	pane.add_child(right)

	# Wrap the right pane in a styled, bordered "module" panel to match the mockup.
	var pane_wrap := PanelContainer.new()
	pane_wrap.name = "LandscapeRightPaneWrap"
	pane_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane_wrap.size_flags_stretch_ratio = 0.55
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.078, 0.086, 0.106, 0.95)
	ps.set_border_width_all(1)
	ps.border_color = Color(0.224, 0.239, 0.278, 1.0) # #393d47
	ps.set_corner_radius_all(12)
	ps.content_margin_left = 14
	ps.content_margin_right = 14
	ps.content_margin_top = 12
	ps.content_margin_bottom = 12
	pane_wrap.add_theme_stylebox_override("panel", ps)
	pane_wrap.add_child(pane)

	hbox.add_child(pane_wrap)
	hbox.move_child(pane_wrap, insert_idx)

	# List takes the remaining ~45%.
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.45

	hbox.set_meta("landscape_two_paned", true)

func _build_landscape_stat_label() -> void:
	# A wrapping grid of stat chips inserted right under the item name, replacing the verbose
	# Per Unit / Total Order section panels (which were crammed into a scroll strip in landscape).
	if is_instance_valid(_landscape_stat_box):
		return
	if not is_instance_valid(item_name_label):
		return
	var parent_m := item_name_label.get_parent()
	if not is_instance_valid(parent_m):
		return
	var box := VBoxContainer.new()
	box.name = "LandscapeStatBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	box.visible = false
	_landscape_stat_box = box
	parent_m.add_child(box)
	parent_m.move_child(box, item_name_label.get_index() + 1)

func _update_landscape_summary() -> void:
	# Rebuild the stat chips and suppress the verbose sections + description toggle in landscape.
	if not is_instance_valid(_landscape_stat_box):
		return
	for c in _landscape_stat_box.get_children():
		c.queue_free()
	var has_item: bool = selected_item != null
	if has_item:
		_landscape_stat_box.add_child(VendorItemList.build_stat_chips(selected_item, str(current_mode), 16))
	_landscape_stat_box.visible = has_item
	# Hide the tall Per Unit / Total Order / Destination section panels in landscape.
	if is_instance_valid(item_info_rich_text):
		var info_vbox := item_info_rich_text.get_parent()
		if is_instance_valid(info_vbox):
			var sections = info_vbox.get_node_or_null("InfoSectionsContainer")
			if is_instance_valid(sections):
				sections.visible = false
	# Drop the Description toggle in landscape — not needed in the compact inspector.
	if is_instance_valid(description_panel):
		description_panel.visible = false

func _reorg_landscape_transaction(right: Control) -> void:
	# Tidy the bottom of the right pane to match the mockup: the quantity stepper and the Buy
	# button share ONE row (Buy carries the price), with the capacity meters sitting just above.
	# Order ends up: [ … price (hidden) ][ Volume/Mass meters ][ (− qty + Max)  |  Buy $X ].
	if not is_instance_valid(right) or right.has_meta("landscape_tx_reorged"):
		return
	var qty_container := right.get_node_or_null("TransactionQuantityContainer")
	var act := right.get_node_or_null("ActionButton")
	if not (is_instance_valid(qty_container) and is_instance_valid(act)):
		return
	var row := HBoxContainer.new()
	row.name = "TxActionRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	# Re-home the stepper + Buy into the shared row.
	right.remove_child(qty_container)
	right.remove_child(act)
	qty_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_container.size_flags_stretch_ratio = 1.2
	act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.size_flags_stretch_ratio = 1.0
	act.size_flags_vertical = Control.SIZE_FILL
	row.add_child(qty_container)
	row.add_child(act)
	right.add_child(row) # appended last → bottom of the pinned footer
	# The cost rides on the Buy button; _update_transaction_panel repurposes price_label to show
	# the order PROFIT in landscape (or hides it when there's no delivery reward).
	right.set_meta("landscape_tx_reorged", true)

func _style_footer_module(right: Control) -> void:
	# Give the transaction footer a distinct "module" look so it reads as its own panel,
	# visually separated from the scrolling list above it.
	if not (right is Control):
		return
	if right.has_meta("footer_styled"):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.086, 0.094, 0.114, 0.96) # slightly lighter than the page, opaque-ish
	sb.set_border_width_all(0)
	sb.border_width_top = 3
	sb.border_color = Color(0.247, 0.616, 0.322, 0.80) # green accent rail — stronger separation from list
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	# RightPanel is a VBoxContainer (doesn't paint). Wrap it in a PanelContainer so the styled
	# background sits behind the transaction controls.
	var parent := right.get_parent()
	if not is_instance_valid(parent):
		return
	var idx := right.get_index()
	var wrap := PanelContainer.new()
	wrap.name = "FooterModule"
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = right.size_flags_vertical
	wrap.size_flags_stretch_ratio = right.size_flags_stretch_ratio
	wrap.add_theme_stylebox_override("panel", sb)
	parent.remove_child(right)
	wrap.add_child(right)
	parent.add_child(wrap)
	parent.move_child(wrap, idx)
	right.set_meta("footer_styled", true)

func _slim_transaction_footer(right: Control) -> void:
	for child_name in ["TransactionLabel", "ConvoyMoneyLabel"]:
		var n = right.get_node_or_null(child_name)
		if is_instance_valid(n):
			n.visible = false

func _slim_portrait_inspector(middle: Control) -> void:
	# The inspector is revealed in a capped (~25%) section, so drop the big 150px preview image —
	# the name + scrollable stats/description are what matter in that space. The InfoScrollContainer
	# already expands, so the detail scrolls within the capped height instead of overflowing.
	var preview = middle.get_node_or_null("ItemPreview")
	if is_instance_valid(preview):
		preview.visible = false

func _reveal_portrait_inspector() -> void:
	# Called on selection so the inspector appears (capped) once the user picks an item.
	if is_instance_valid(_portrait_inspector) and not _portrait_inspector.visible:
		_portrait_inspector.visible = true

func _wrap_list_in_well(list_node: Control) -> void:
	# Sit the scrolling item list in a recessed, bordered "well" so it reads as its own surface
	# against the patterned Oori background instead of rows floating loose. Idempotent.
	if not is_instance_valid(list_node):
		return
	var parent := list_node.get_parent()
	if not is_instance_valid(parent):
		return
	if parent is PanelContainer and parent.has_meta("list_well"):
		return
	var well := PanelContainer.new()
	well.name = list_node.name + "Well"
	well.set_meta("list_well", true)
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.size_flags_stretch_ratio = list_node.size_flags_stretch_ratio
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.METAL_DARK # recessed: darker than the page surface
	sb.set_border_width_all(1)
	sb.border_color = UITheme.METAL_EDGE
	sb.set_corner_radius_all(UITheme.RADIUS_LG)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	well.add_theme_stylebox_override("panel", sb)
	var idx := list_node.get_index()
	parent.remove_child(list_node)
	well.add_child(list_node)
	parent.add_child(well)
	parent.move_child(well, idx)
	list_node.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _wrap_inv_scroll(panel: Control, stretch_ratio_h: float, _stretch_ratio_v: float) -> void:
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
	if panel is BoxContainer:
		panel.alignment = BoxContainer.ALIGNMENT_BEGIN
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
	# Apply semibold font where needed (sizes scale via root theme natively now!)
	var labels_to_fix = [
		get_node_or_null("%VolumeLabel"), # Using unique names from tscn
		get_node_or_null("HBoxContainer/RightPanel/CapacityBars/VolumeRow/VolumeLabel"), # Fallback path
		get_node_or_null("%MassLabel"),
		get_node_or_null("HBoxContainer/RightPanel/CapacityBars/MassRow/MassLabel"),
		get_node_or_null("HBoxContainer/RightPanel/TransactionQuantityContainer/Label")
	]
	
	for lbl in labels_to_fix:
		if is_instance_valid(lbl) and lbl is Label:
			lbl.add_theme_font_override("font", _get_semi_bold_font_for(lbl))
	
	pass


func _exit_tree() -> void:
	_reset_destination_preview_if_active()
	# Disconnect from Hub/Store/API/Global signals that we connected in _ready
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(dsm) and dsm.has_signal("layout_mode_changed"):
		var cb_dsm := Callable(self, "_on_layout_mode_changed")
		if dsm.layout_mode_changed.is_connected(cb_dsm):
			dsm.layout_mode_changed.disconnect(cb_dsm)
			
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
		if _api.has_signal("cargo_data_received") and _api.cargo_data_received.is_connected(_on_cargo_data_received):
			_api.cargo_data_received.disconnect(_on_cargo_data_received)
	if is_instance_valid(_vendor_service) and _vendor_service.has_signal("vehicle_data_received"):
		if _vendor_service.vehicle_data_received.is_connected(_on_service_vehicle_data_received):
			_vendor_service.vehicle_data_received.disconnect(_on_service_vehicle_data_received)
	
	if _signal_watcher:
		_signal_watcher.clear()
		_signal_watcher = null


func _on_store_map_changed(_tiles: Array, settlements: Array) -> void:
	# Keep settlement/vendor caches fresh for price fallback + recipient name resolution.
	if settlements is Array:
		_set_latest_settlements_snapshot(settlements)
		if perf_log_enabled and not _map_cache_diag_printed:
			_map_cache_diag_printed = true
			print("[VendorPanel][MapCache] settlements=%d vendors_cached=%d" % [
				int((settlements as Array).size()),
				int(_vendors_from_settlements_by_id.size()),
			])

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
		# _update_comparison() removed - deprecated.

func _on_cargo_data_received(cargo: Dictionary) -> void:
	var cargo_id := str(cargo.get("cargo_id", ""))
	if perf_log_enabled:
		print("[VendorPanel][AsyncCargo] Received cargo_data for id=", cargo_id, " has_pending=", _pending_cargo_recipient_lookups.has(cargo_id))
	# Priced part detail arrived: if it belongs to the current selection, re-price the footer and
	# inspector (MechanicsService has already cached it, so _ensure_selection_priced will find it).
	if cargo_id != "" and selected_item and selected_item.has("item_data"):
		var sel_cid := str((selected_item.item_data as Dictionary).get("cargo_id", (selected_item.item_data as Dictionary).get("part_id", "")))
		if sel_cid == cargo_id:
			_update_inspector()
			_update_transaction_panel()
	if not _pending_cargo_recipient_lookups.has(cargo_id):
		return
	var recipient_id := str(cargo.get("recipient", ""))
	if recipient_id == "" or recipient_id == "00000000-0000-0000-0000-000000000000":
		if perf_log_enabled:
			print("[VendorPanel][AsyncCargo] Cargo ", cargo_id, " has no recipient in rich payload.")
		return
	var name := _get_vendor_name_for_recipient(recipient_id)
	if perf_log_enabled:
		print("[VendorPanel][AsyncCargo] Resolved recipient_id=", recipient_id, " to name='", name, "'")
	var item: Dictionary = _pending_cargo_recipient_lookups[cargo_id]
	item["mission_vendor_name"] = name
	_pending_cargo_recipient_lookups.erase(cargo_id)
	# If this item is currently selected, refresh the inspector
	if selected_item and (selected_item as Dictionary).get("item_data", {}).get("cargo_id", "") == cargo_id:
		if perf_log_enabled:
			print("[VendorPanel][AsyncCargo] Refreshing inspector for selected cargo ", cargo_id)
		_update_inspector()

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
		_populate_list_from_agg(vendor_item_tree, self.vendor_items)
	if update_convoy:
		var agg_to_use: Dictionary = self.convoy_items if (self.convoy_items is Dictionary) else {}
		# In SELL mode, allow selling whole vehicles when appropriate for this vendor
		if _should_show_vehicle_sell_category():
			agg_to_use = _convoy_items_with_sellable_vehicles(agg_to_use)
		_populate_list_from_agg(convoy_item_tree, agg_to_use)
	_update_convoy_info_display()

func _should_show_vehicle_sell_category() -> bool:
	return VendorPanelVehicleSellController.should_show_vehicle_sell_category(self)

func _convoy_items_with_sellable_vehicles(base_agg: Dictionary) -> Dictionary:
	return VendorPanelVehicleSellController.convoy_items_with_sellable_vehicles(self, base_agg)

func _populate_list_from_agg(list: VendorItemList, agg: Dictionary) -> void:
	# Mirrors the old VendorTreeBuilder.populate_tree_vendor_rows: rebucket parts out of "other",
	# then add the standard category sections to the custom list.
	if not is_instance_valid(list):
		return
	list.clear_items()
	var display_agg: Dictionary = VendorTreeBuilder.make_display_agg_with_parts_rebucket(agg)
	# Category key -> friendly title (matches the _populate_*_list naming).
	var order := [["missions", "Delivery Cargo"], ["vehicles", "Vehicles"], ["parts", "Parts"], ["other", "Other"], ["resources", "Resources"]]
	for entry in order:
		var key: String = entry[0]
		var title: String = entry[1]
		var bucket: Variant = display_agg.get(key, {})
		if bucket is Dictionary and not (bucket as Dictionary).is_empty():
			var sm: int = _cargo_sort_metric if title == "Delivery Cargo" else -1
			list.add_category(title, bucket, sm)


# --- Data Initialization ---
func initialize(p_vendor_data, p_convoy_data, p_current_settlement_data, p_all_settlement_data_global) -> void:
	print("[DIAGNOSTIC] VendorTradePanel initialize called for: ", self.name)
	self.vendor_data = p_vendor_data
	self.convoy_data = p_convoy_data
	self.current_settlement_data = p_current_settlement_data
	self.all_settlement_data_global = p_all_settlement_data_global
	_update_sort_dropdown_visibility_fast()

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
	_update_sort_dropdown_visibility_fast()

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
	_ignore_selection_signals = true
	vendor_item_tree.clear_items()
	if not vendor_data:
		vendor_items = {}
		_ignore_selection_signals = false
		return
	var vd_for_agg := _vendor_data_with_price_fallback(vendor_data)
	var buckets := VendorCargoAggregatorScript.build_vendor_buckets(vd_for_agg, perf_log_enabled, Callable(self, "_get_vendor_name_for_recipient"))
	self.vendor_items = buckets
	var has_delivery_cargo = not buckets.get("delivery", {}).is_empty()
	vendor_item_tree.add_category("Delivery Cargo", buckets.get("delivery", {}), _cargo_sort_metric)
	vendor_item_tree.add_category("Vehicles", buckets.get("vehicles", {}), -1)
	vendor_item_tree.add_category("Parts", buckets.get("parts", {}), -1)
	vendor_item_tree.add_category("Other", buckets.get("other", {}), -1)
	vendor_item_tree.add_category("Resources", buckets.get("resources", {}), -1)
	_ignore_selection_signals = false

	if has_delivery_cargo and is_instance_valid(_api):
		var mission_bucket: Dictionary = buckets.get("delivery", {})
		if perf_log_enabled:
			print("[VendorPanel][AsyncCargo] Mission bucket items: ", mission_bucket.keys())
		for key in mission_bucket:
			var dict: Dictionary = mission_bucket[key]
			var idata: Dictionary = dict.get("item_data", {})
			var cid = str(idata.get("cargo_id", ""))
			var m_v_name = str(dict.get("mission_vendor_name", ""))
			if cid != "" and (m_v_name == "" or m_v_name == "Unknown Vendor" or "00000000" in m_v_name):
				if perf_log_enabled:
					print("[VendorPanel][AsyncCargo] Triggering get_cargo for cid=", cid)
				_pending_cargo_recipient_lookups[cid] = dict
				if _api.has_method("get_cargo"):
					_api.get_cargo(cid)

	if is_instance_valid(cargo_sort_button):
		_set_cargo_sort_ui_visible(has_delivery_cargo or _has_delivery_cargo_fast_for_mode("buy"))

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
	_ignore_selection_signals = true
	convoy_item_tree.clear_items()
	if not (convoy_data is Dictionary) or convoy_data.is_empty():
		convoy_items = {}
		_ignore_selection_signals = false
		return
	var allow_vehicle_sell := _should_show_vehicle_sell_category()
	# Always use price fallback for aggregation to ensure consistent grouping (e.g. water/food).
	# Transaction logic will still enforce vendor's actual buying prices.
	var vd_for_agg = _vendor_data_with_price_fallback(vendor_data)
	var buckets := VendorCargoAggregatorScript.build_convoy_buckets(convoy_data, vd_for_agg, current_mode, perf_log_enabled, Callable(self, "_get_vendor_name_for_recipient"), allow_vehicle_sell)
	self.convoy_items = buckets
	if perf_log_enabled and str(current_mode) == "sell":
		var vd: Dictionary = vendor_data if (vendor_data is Dictionary) else {}
		var vdx: Dictionary = vd_for_agg
		var vid_dbg: String = str(vd.get("vendor_id", vd.get("id", ""))).strip_edges()
		var vname_dbg: String = str(vd.get("name", "")).strip_edges()
		if vname_dbg == "" and _vendor_id_to_name.has(vid_dbg):
			vname_dbg = str(_vendor_id_to_name.get(vid_dbg, "")).strip_edges()
		var sname_dbg: String = ""
		var sv_prices: String = "<no-settlement-vendor>"
		if _vendor_id_to_settlement.has(vid_dbg):
			var ss_any: Variant = _vendor_id_to_settlement.get(vid_dbg)
			if ss_any is Dictionary:
				sname_dbg = str((ss_any as Dictionary).get("name", "")).strip_edges()
		if _vendors_from_settlements_by_id.has(vid_dbg):
			var sv_any: Variant = _vendors_from_settlements_by_id.get(vid_dbg)
			if sv_any is Dictionary:
				var sv: Dictionary = sv_any
				sv_prices = "%s/%s/%s" % [str(sv.get("fuel_price", "<none>")), str(sv.get("water_price", "<none>")), str(sv.get("food_price", "<none>"))]
		print("[VendorPanel][SellDiag] vendor_id=", str(vd.get("vendor_id", "")),
			" vendor_name=", vname_dbg,
			" settlement=", sname_dbg,
			" has_keys(cargo_inventory/vehicle_inventory)=", vd.has("cargo_inventory"), "/", vd.has("vehicle_inventory"),
			" stock_raw(f/w/food)=", str(vd.get("fuel", "<none>")), "/", str(vd.get("water", "<none>")), "/", str(vd.get("food", "<none>")),
			" prices_raw(f/w/food)=", str(vd.get("fuel_price", "<none>")), "/", str(vd.get("water_price", "<none>")), "/", str(vd.get("food_price", "<none>")),
			" prices_used(f/w/food)=", str(vdx.get("fuel_price", "<none>")), "/", str(vdx.get("water_price", "<none>")), "/", str(vdx.get("food_price", "<none>")),
			" settlement_prices(f/w/food)=", sv_prices,
			" allow_vehicle_sell=", allow_vehicle_sell,
			" bucket_sizes(d/v/p/o/r)=", int((buckets.get("delivery", {}) as Dictionary).size()), "/", int((buckets.get("vehicles", {}) as Dictionary).size()), "/", int((buckets.get("parts", {}) as Dictionary).size()), "/", int((buckets.get("other", {}) as Dictionary).size()), "/", int((buckets.get("resources", {}) as Dictionary).size()))
	var has_delivery_cargo = not buckets.get("delivery", {}).is_empty()
	convoy_item_tree.add_category("Delivery Cargo", buckets.get("delivery", {}), _cargo_sort_metric)
	if allow_vehicle_sell and not (buckets.get("vehicles", {}) as Dictionary).is_empty():
		convoy_item_tree.add_category("Vehicles", buckets.get("vehicles", {}), -1)
	# Only show loose/aggregated parts when BUYING. In SELL mode installed vehicle parts are not sellable.
	if current_mode == "buy":
		convoy_item_tree.add_category("Parts", buckets.get("parts", {}), -1)
	convoy_item_tree.add_category("Other", buckets.get("other", {}), -1)
	convoy_item_tree.add_category("Resources", buckets.get("resources", {}), -1)
	_ignore_selection_signals = false

	# Show sorting if either list has delivery cargo, according to Active Tab
	if is_instance_valid(cargo_sort_button):
		if current_mode == "sell":
			_set_cargo_sort_ui_visible(has_delivery_cargo or _has_delivery_cargo_fast_for_mode("sell"))

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
func _select_trade_mode(tab_index: int) -> void:
	# Setting current_tab fires tab_changed → _on_tab_changed → _sync_mode_toggle_buttons.
	if is_instance_valid(trade_mode_tab_container):
		trade_mode_tab_container.current_tab = tab_index

func _on_mode_flip_pressed() -> void:
	# Single flip button: toggle Buy(0) <-> Sell(1).
	if not is_instance_valid(trade_mode_tab_container):
		return
	var next_tab: int = 1 if trade_mode_tab_container.current_tab == 0 else 0
	_select_trade_mode(next_tab)

func _sync_mode_toggle_buttons(tab_index: int) -> void:
	# Reflect the active mode on the single flip button (label + color).
	if not is_instance_valid(mode_flip_button):
		return
	var is_buy: bool = (tab_index == 0)
	mode_flip_button.text = "Buy ⇄" if is_buy else "Sell ⇄"
	_style_mode_toggle()

# Shared neutral button language for the control-row + Max buttons so they all read as one set
# (METAL_BASE fill, METAL_EDGE border, radius MD). The single accented button is the primary Buy.
func _style_neutral_button(b: Button) -> void:
	if not is_instance_valid(b):
		return
	b.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.METAL_BASE
	normal.set_border_width_all(UITheme.BORDER_THIN)
	normal.border_color = UITheme.METAL_EDGE
	normal.set_corner_radius_all(UITheme.RADIUS_MD)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = UITheme.METAL_HOVER
	hover.border_color = UITheme.TEXT_MUTED
	var pressed := normal.duplicate()
	pressed.bg_color = UITheme.METAL_ACTIVE
	var disabled := normal.duplicate()
	disabled.bg_color = UITheme.METAL_DARK
	disabled.border_color = UITheme.METAL_EDGE.lerp(Color.BLACK, 0.3)
	for state in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed], ["focus", hover], ["disabled", disabled]]:
		b.add_theme_stylebox_override(state[0], state[1])
	b.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override("font_disabled_color", UITheme.TEXT_MUTED)

# Filter / parameter controls (vendor-type dropdown, Buy/Sell toggle, Sort). These SET STATE rather
# than commit an action, so they must read differently from the neutral action buttons (Top Up /
# Warehouse / Max): a recessed METAL_DARK well + a verdigris trim border — the design system's
# digital/state cue (verdigris = living/digital; warm grey = economic action). `active` marks the
# currently-selected state (the Buy/Sell flip): a stronger verdigris fill, full-strength border, and
# lighter verdigris text so the live trade direction reads at a glance.
func _style_filter_control(b: Button, active: bool = false) -> void:
	if not is_instance_valid(b):
		return
	# MenuButtons default to flat=true, which suppresses the normal stylebox (and thus the border).
	b.flat = false
	b.focus_mode = Control.FOCUS_NONE
	var trim := UITheme.METAL_EDGE.lerp(UITheme.ACCENT_VERDIGRIS, 0.55)
	var active_fill := Color(0.051, 0.188, 0.145) # deep verdigris well (darker than the Buy commit button)
	var active_fg := Color(0.627, 0.831, 0.784)   # light verdigris text
	var normal := StyleBoxFlat.new()
	normal.bg_color = active_fill if active else UITheme.METAL_DARK
	normal.set_border_width_all(UITheme.BORDER_THIN)
	normal.border_color = UITheme.ACCENT_VERDIGRIS if active else trim
	normal.set_corner_radius_all(UITheme.RADIUS_MD)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = (normal.bg_color as Color).lerp(UITheme.ACCENT_VERDIGRIS, 0.18)
	hover.border_color = UITheme.ACCENT_VERDIGRIS
	var pressed := normal.duplicate()
	pressed.bg_color = (normal.bg_color as Color).lerp(Color.BLACK, 0.2)
	var disabled := normal.duplicate()
	disabled.bg_color = UITheme.METAL_DARK
	disabled.border_color = UITheme.METAL_EDGE.lerp(Color.BLACK, 0.3)
	for state in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed], ["focus", hover], ["disabled", disabled]]:
		b.add_theme_stylebox_override(state[0], state[1])
	var fg := active_fg if active else UITheme.TEXT_PRIMARY
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", UITheme.TEXT_MUTED)

# The one accented button: primary Buy/Sell commit action (verdigris green).
func _style_primary_button(b: Button) -> void:
	if not is_instance_valid(b):
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.176, 0.290, 0.196) # deep verdigris fill
	normal.set_border_width_all(UITheme.BORDER_THIN)
	normal.border_color = UITheme.ACCENT_VERDIGRIS
	normal.set_corner_radius_all(UITheme.RADIUS_MD)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = Color(0.224, 0.357, 0.247)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.137, 0.235, 0.157)
	var disabled := normal.duplicate()
	disabled.bg_color = UITheme.METAL_DARK
	disabled.border_color = UITheme.METAL_EDGE.lerp(Color.BLACK, 0.3)
	for state in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed], ["focus", hover], ["disabled", disabled]]:
		b.add_theme_stylebox_override(state[0], state[1])
	b.add_theme_color_override("font_color", Color(0.85, 0.93, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.93, 0.86))
	b.add_theme_color_override("font_disabled_color", UITheme.TEXT_MUTED)

func _style_mode_toggle() -> void:
	var b := mode_flip_button
	if not is_instance_valid(b):
		return
	# Content-sized button: must NOT clip_text, or its minimum size drops the label and it
	# collapses to just the margins (no text, hairline-thin).
	b.clip_text = false
	# The Buy/Sell flip is always the "active state" filter control (current trade direction).
	_style_filter_control(b, true)

func _on_tab_changed(tab_index: int) -> void:
	_reset_destination_preview_if_active()
	current_mode = "buy" if tab_index == 0 else "sell"
	action_button.text = "Buy" if current_mode == "buy" else "Sell"
	_sync_mode_toggle_buttons(tab_index)
	_update_sort_dropdown_visibility_fast()
	
	# Clear selection and inspector when switching tabs
	selected_item = null
	_clear_committed_projection()
	if is_instance_valid(vendor_item_tree):
		vendor_item_tree.deselect_all()
	if is_instance_valid(convoy_item_tree):
		convoy_item_tree.deselect_all()
	_clear_inspector()
	if is_instance_valid(action_button):
		action_button.disabled = true
	if is_instance_valid(max_button):
		max_button.disabled = true

	_update_install_button_state()

	# Repopulate convoy list to apply mode-specific filtering (e.g., hide Parts when selling).
	if is_node_ready():
		_populate_convoy_list()

func _on_vendor_item_selected(agg_data = null) -> void:
	if _ignore_selection_signals:
		return
	# VendorItemList.item_selected passes the row's agg_data directly (mirrors Tree get_metadata(0)).
	if agg_data == null and is_instance_valid(vendor_item_tree):
		agg_data = vendor_item_tree.get_selected_data()
	if perf_log_enabled:
		var nm := str((agg_data as Dictionary).get("display_name", "")) if agg_data is Dictionary else "<none>"
		print("[VendorPanel][LOG] _on_vendor_item_selected. Item: '%s'" % nm)
	_last_selected_tree = "vendor"
	_last_selection_change_ms = Time.get_ticks_msec()
	_reveal_portrait_inspector()
	# Defer handling to the next idle frame.
	call_deferred("_handle_new_item_selection", agg_data)

func _on_convoy_item_selected(agg_data = null) -> void:
	if _ignore_selection_signals:
		return
	if agg_data == null and is_instance_valid(convoy_item_tree):
		agg_data = convoy_item_tree.get_selected_data()
	_last_selected_tree = "convoy"
	_last_selection_change_ms = Time.get_ticks_msec()
	_reveal_portrait_inspector()
	# Defer handling to prevent UI race conditions.
	call_deferred("_handle_new_item_selection", agg_data)

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
	if not is_inside_tree():
		return
	_reset_destination_preview_if_active()
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

	# Merge any lazily-fetched part price into the selection so the inspector shows the real price.
	_ensure_selection_priced()

	var item_data_source = selected_item.item_data if selected_item.has("item_data") and not selected_item.item_data.is_empty() else selected_item

	# If the selected item is a vehicle, use a dedicated inspector update function and skip the generic one.
	if VendorTradeVM.is_vehicle_item(item_data_source):
		var vehicle_data: Dictionary = item_data_source if item_data_source is Dictionary else {}
		VendorPanelInspectorController.update_vehicle(self, vehicle_data)
		# Fitment panel should be updated for all items, including vehicles (to hide it).
		_update_fitment_panel()
		if _is_landscape_layout():
			_update_landscape_summary()
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
		_compat_cache,
		perf_log_enabled
	)
	if _is_landscape_layout():
		_update_landscape_summary()
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
	# Vendor stock parts ship as a thin summary with no price; the priced detail is fetched
	# lazily by cargo_id (same path the Mechanics menu uses) and merged into the selection when
	# available, so the presenter below computes a real total.
	_ensure_selection_priced()
	var quantity = int(quantity_spinbox.value) if is_instance_valid(quantity_spinbox) else 1
	var pr = VendorTradeVM.build_price_presenter(item_data_source, str(current_mode), quantity, selected_item)
	var total_reward: float = float(pr.get("total_delivery_reward", 0.0))
	var is_portrait_now := _is_compact_footer_layout()
	if is_instance_valid(delivery_reward_label):
		# In portrait the reward is folded into the single compact price line below, so the
		# separate reward label is only shown on desktop/landscape.
		delivery_reward_label.visible = (not is_portrait_now) and total_reward > 0.0
		if total_reward > 0.0:
			delivery_reward_label.text = "[b]Total Delivery Reward:[/b] %s" % NumberFormat.format_money(total_reward)
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
	# Assign composed text. In portrait, collapse the multi-line breakdown (Quantity / Total
	# Price / Order Weight / Order Volume) into ONE line — the per-unit stats already live in the
	# inline row body, and the order weight/volume are visualized by the capacity bars. This keeps
	# the footer a fixed, compact height instead of exploding when an item is selected.
	var total_price_now: float = float(pr.get("total_price", 0.0))
	var net_profit: float = total_reward - total_price_now # order profit when this is delivery cargo
	var profit_bb := ""
	if total_reward > 0.0:
		var sgn: String = "+" if net_profit >= 0.0 else "-"
		var pcol: String = "#7fd08a" if net_profit >= 0.0 else "#e3736b"
		profit_bb = "[color=%s][b]Profit %s%s[/b][/color]" % [pcol, sgn, NumberFormat.format_money(absf(net_profit))]
	if _is_landscape_layout():
		# Cost rides on the Buy button; show the order PROFIT here when it's delivery cargo.
		if profit_bb != "" and not VendorTradeVM.is_vehicle_item(item_data_source):
			price_label.text = profit_bb
			price_label.visible = true
		else:
			price_label.visible = false
	elif is_portrait_now and not VendorTradeVM.is_vehicle_item(item_data_source):
		var compact := "[b]Total:[/b] %s" % NumberFormat.format_money(total_price_now)
		if profit_bb != "":
			compact += "    " + profit_bb
		price_label.text = compact
		price_label.visible = true
	else:
		price_label.text = bbcode_text
		price_label.visible = true
	_update_install_button_state()
	if is_instance_valid(action_button):
		action_button.disabled = not can_transact
		# Landscape carries the price on the Buy/Sell button itself (the standalone price line is
		# hidden there), matching the mockup's "Buy  $5,000".
		if _is_landscape_layout():
			var verb: String = "Buy" if str(current_mode) == "buy" else "Sell"
			action_button.text = "%s  %s" % [verb, NumberFormat.format_money(float(pr.get("total_price", 0.0)))]
		if not can_transact:
			action_button.text = "Sell"

func _refresh_capacity_bars(projected_volume_delta: float, projected_weight_delta: float) -> void:
	if not is_inside_tree():
		return
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(dsm) and dsm.get_layout_mode() == 2: # MOBILE_PORTRAIT
		# Ensure layout settles before rendering highlight overlays
		VendorPanelConvoyStatsController.refresh_capacity_bars.call_deferred(self, projected_volume_delta, projected_weight_delta)
	else:
		VendorPanelConvoyStatsController.refresh_capacity_bars(self, projected_volume_delta, projected_weight_delta)

func _is_positive_number(v: Variant) -> bool:
	return (v is float or v is int) and float(v) > 0.0

func _looks_like_part(item_data_source: Dictionary) -> bool:
	# Defer to the centralized classification logic in the ItemsData factory.
	return ItemsData.PartItem._looks_like_part_dict(item_data_source)

# Vendor stock parts arrive as a thin summary (cargo_id + name, base_price: 0) with no usable
# price. The full priced detail is fetched lazily by cargo_id via APICalls.get_cargo and cached
# in MechanicsService — the same source the Mechanics/Cargo menus read. When the cached detail is
# available, merge its price fields into the live selection so every consumer (footer, inspector,
# row) resolves the real price. Idempotent: a no-op once the selection already prices > 0.
func _ensure_selection_priced() -> void:
	if not selected_item or not selected_item.has("item_data"):
		return
	var idata: Variant = selected_item.item_data
	if not (idata is Dictionary) or (idata as Dictionary).is_empty():
		return
	var d: Dictionary = idata
	if VendorTradeVM.contextual_unit_price(d, str(current_mode)) > 0.0:
		return
	var cid: String = str(d.get("cargo_id", d.get("part_id", "")))
	if cid == "" or not is_instance_valid(_mechanics_service) or not _mechanics_service.has_method("get_enriched_cargo"):
		return
	var rich: Dictionary = _mechanics_service.get_enriched_cargo(cid)
	if rich.is_empty():
		return
	for k in ["price", "unit_price", "base_unit_price", "value"]:
		if rich.has(k) and rich.get(k) != null:
			d[k] = rich.get(k)

# Helper: fetch a modifier value from either top-level or stats dict using a list of alias keys
 

func _best_install_price_for_selection() -> float:
	# Min install price across all convoy vehicles we've cached a compat result for, for the current
	# selection. Returns -1 when no compat result has arrived yet.
	if not selected_item or not (selected_item is Dictionary) or not selected_item.has("item_data"):
		return -1.0
	var idata: Dictionary = selected_item.item_data
	var uid: String = str(idata.get("cargo_id", idata.get("part_id", "")))
	if uid == "":
		return -1.0
	var best: float = -1.0
	for key in _install_price_cache.keys():
		if str(key).ends_with("||" + uid):
			var p: float = float(_install_price_cache[key])
			if p >= 0.0 and (best < 0.0 or p < best):
				best = p
	return best

func _refresh_install_cost_display() -> void:
	# Show the resolved install cost on whichever Install button is active (inline in portrait,
	# footer otherwise). Cargo price itself is already shown as a stat chip.
	var price: float = _best_install_price_for_selection()
	if _is_portrait_layout():
		if is_instance_valid(vendor_item_tree) and vendor_item_tree.has_method("set_selected_install_cost"):
			vendor_item_tree.set_selected_install_cost(price)
	elif is_instance_valid(install_button) and install_button.visible:
		install_button.text = "Install" if price < 0.0 else "Install · %s" % NumberFormat.format_money(price)

func _update_install_button_state() -> void:
	VendorPanelCompatController.update_install_button_state(self)
	_refresh_install_cost_display()

func _on_install_button_pressed() -> void:
	VendorPanelCompatController.on_install_button_pressed(self)

func _on_inline_install_pressed(agg_data: Variant) -> void:
	# The inline body is only visible for the selected row, so `selected_item` already equals this
	# agg_data; assert it defensively, then reuse the standard install flow.
	if agg_data is Dictionary:
		selected_item = agg_data
	VendorPanelCompatController.on_install_button_pressed(self)

# --- Compatibility plumbing (align with Mechanics) ---
 

func _on_part_compatibility_ready(payload: Dictionary) -> void:
	VendorPanelCompatController.on_part_compatibility_ready(self, payload)
	# Install price now cached → reflect it on the active Install button.
	_refresh_install_cost_display()

 

# Resolve part modifiers from item data or compatibility payload cache
 

# --- Price Calculation Helpers ---

# Returns a Dictionary with container_unit_price and resource_unit_value for the item.
 

# True if this dictionary represents a vehicle record (not cargo that happens to reference a vehicle_id)
 

# Returns the unit price for a vehicle, checking several common fields.
 

# Returns the price per unit for the given item, depending on buy/sell mode.
 

func _optimistically_update_vendor_stock(item_name: String, qty_delta: int) -> void:
	print("[VendorPanel][DIAG] _optimistically_update_vendor_stock starting for '%s'" % item_name)
	if vendor_items == null or not (vendor_items is Dictionary):
		print("[VendorPanel][DIAG] FAILED: vendor_items is null or invalid")
		return
	
	var target_name := item_name.strip_edges()
	print("[VendorPanel][DIAG] Searching buckets for '%s'..." % target_name)
	
	var found := false
	for bucket_key in (vendor_items as Dictionary):
		var bucket: Variant = (vendor_items as Dictionary).get(bucket_key)
		if bucket is Dictionary:
			# Try exact match and stripped match
			var entry: Dictionary = {}
			if (bucket as Dictionary).has(target_name):
				entry = (bucket as Dictionary).get(target_name)
			else:
				# Search for a stripped match if exact match fails
				for k in (bucket as Dictionary).keys():
					if str(k).strip_edges() == target_name:
						entry = (bucket as Dictionary).get(k)
						break
			
			if not entry.is_empty():
				var old_qty: int = int(entry.get("total_quantity", 0))
				entry["total_quantity"] = max(0, old_qty + qty_delta)
				found = true
				print("[VendorPanel][DIAG] SUCCESS: updated '%s' in bucket '%s': %d -> %d" % [target_name, bucket_key, old_qty, int(entry["total_quantity"])])
				
				# Also update the underlying item_data quantity if it's a raw resource
				var item_data: Variant = entry.get("item_data")
				if item_data is Dictionary and (item_data as Dictionary).get("is_raw_resource", false):
					(item_data as Dictionary)["quantity"] = entry["total_quantity"]
					# Update the top-level vendor_data if applicable
					if vendor_data is Dictionary:
						if target_name.begins_with("Fuel"): vendor_data["fuel"] = entry["total_quantity"]
						elif target_name.begins_with("Water"): vendor_data["water"] = entry["total_quantity"]
						elif target_name.begins_with("Food"): vendor_data["food"] = entry["total_quantity"]
				break
	
	if found:
		_update_vendor_ui(true, false)
	else:
		print("[VendorPanel][DIAG] FAILED: item '%s' not found in any bucket. Buckets searched: %s" % [target_name, (vendor_items as Dictionary).keys()])

func _on_api_transaction_result(result: Dictionary) -> void:
	print("[VendorPanel][DIAG] _on_api_transaction_result ENTERED on instance_id=%d" % get_instance_id())
	var has_pending_data: bool = not _pending_tx.item.is_empty()
	print("[VendorPanel][DIAG] in_progress=%s, has_pending=%s" % [str(_transaction_in_progress), str(has_pending_data)])
	# Capture feedback info regardless of in_progress flag, as long as we have data
	var mode_str: String = "bought" if str(current_mode) == "buy" else "sold"
	var qty: int = int(_pending_tx.get("quantity", 1))
	var item_name: String = str(_pending_tx.get("item", {}).get("name", "Item"))
	var total_price: float = abs(float(_pending_tx.get("money_delta", 0.0)))
	var msg: String = "Successfully %s %d %s for %s" % [mode_str, qty, item_name, NumberFormat.format_money(total_price, "")]

	if has_pending_data:
		# Optimistically update vendor stock
		var stock_delta: int = -qty if str(current_mode) == "buy" else qty
		print("[VendorPanel][DIAG] Triggering optimistic vendor update for '%s' delta %d" % [item_name, stock_delta])
		_optimistically_update_vendor_stock(item_name, stock_delta)
		
		# Ensure projection is committed if it hasn't been yet
		_commit_projection_from_pending_tx()
		
		# Signal that we are done with the transaction part of the UI state
		_transaction_in_progress = false
		# We'll clear _pending_tx below after checking authoritative state

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
	if has_pending_data:
		show_transaction_feedback(msg, "success")
		_clear_pending_tx()
	_flash_capacity_bars()

	if is_instance_valid(_hub) and _hub.has_signal("user_refresh_requested"):
		_hub.user_refresh_requested.emit()

func _on_api_transaction_error(error_message: String) -> void:
	VendorPanelRefreshController.on_api_transaction_error(self, error_message)
	
	var friendly_message: String = ErrorTranslator.translate(error_message)
	show_transaction_feedback(friendly_message, "error")

# Updates the comparison panel (stub, deprecated)
func _update_comparison() -> void:
	pass

# Clears the inspector panel (stub, fill in as needed)
func _clear_inspector() -> void:
	_reset_destination_preview_if_active()
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
	var parent_node = item_info_rich_text.get_parent()
	if not is_instance_valid(parent_node):
		return
	
	# Force top alignment for the container holding segments
	if parent_node is BoxContainer:
		parent_node.alignment = BoxContainer.ALIGNMENT_BEGIN
	
	var container: Node = parent_node.get_node_or_null("InfoSectionsContainer")
	if is_instance_valid(container):
		for ch in container.get_children():
			ch.queue_free()

func _reset_destination_preview_if_active() -> void:
	print("[VendorTradePanel] _reset_destination_preview_if_active: Called. _is_previewing_destination = ", _is_previewing_destination)
	if _is_previewing_destination:
		_is_previewing_destination = false
		if is_instance_valid(_hub) and _hub.has_signal("map_camera_return_to_convoy_requested"):
			print("[VendorTradePanel] _reset_destination_preview_if_active: Emitting map_camera_return_to_convoy_requested to SignalHub")
			_hub.emit_signal("map_camera_return_to_convoy_requested")
		else:
			printerr("[VendorTradePanel] _reset_destination_preview_if_active: SignalHub or signal 'map_camera_return_to_convoy_requested' is missing!")

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

func _restore_selection(list: VendorItemList, item_id, clear_on_fail: bool = true) -> bool:
	# List-native restore: iterate rows, match via the same data-level _matches_restore_key,
	# and drive _handle_new_item_selection exactly like the old Tree path.
	if not is_instance_valid(list):
		return false
	var on_select := Callable(self, "_handle_new_item_selection")
	var match_fn := Callable(self, "_matches_restore_key")
	var ok: bool = list.restore_by_match(item_id, match_fn, on_select)
	if not ok and clear_on_fail:
		list.deselect_all()
	return ok

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

func _on_cargo_sort_selected(index: int) -> void:
	_cargo_sort_metric = index
	_save_cargo_sort_metric_to_settings(index)
	
	if is_instance_valid(cargo_sort_button):
		var popup = cargo_sort_button.get_popup()
		for i in range(popup.item_count):
			popup.set_item_checked(i, i == index)

	_update_cargo_sort_button_text()
	_populate_vendor_list()
	_populate_convoy_list()

func _update_cargo_sort_button_text() -> void:
	if not is_instance_valid(cargo_sort_button):
		return
	var sort_names = ["Margin/Unit", "Profit/Weight", "Profit/Volume", "Total Profit", "Distance"]
	if _cargo_sort_metric >= 0 and _cargo_sort_metric < sort_names.size():
		cargo_sort_button.text = "Sort: " + sort_names[_cargo_sort_metric] + " ▼"
	else:
		cargo_sort_button.text = "Sort ▼"

func get_ui_state() -> Dictionary:
	var state = {}
	state["last_selected_tree"] = _last_selected_tree
	state["last_selected_restore_id"] = _last_selected_restore_id
	if is_instance_valid(trade_mode_tab_container):
		state["current_mode_tab"] = trade_mode_tab_container.current_tab
	print("[DIAGNOSTIC] VendorTradePanel get_ui_state for ", self.name, " returns: ", state)
	return state

func apply_ui_state(state) -> void:
	print("[DIAGNOSTIC] VendorTradePanel apply_ui_state called for vendor: ", self.name, " State: ", state)
	if perf_log_enabled:
		print("[VendorPanel] apply_ui_state: ", state)
	if state.has("last_selected_tree"):
		_last_selected_tree = state["last_selected_tree"]
	if state.has("last_selected_restore_id"):
		_last_selected_restore_id = state["last_selected_restore_id"]
		print("[DIAGNOSTIC] VendorTradePanel _last_selected_restore_id SET to: ", _last_selected_restore_id)
		
	if state.has("current_mode_tab") and is_instance_valid(trade_mode_tab_container):
		var target_tab = state["current_mode_tab"]
		if target_tab >= 0 and target_tab < trade_mode_tab_container.get_child_count():
			trade_mode_tab_container.current_tab = target_tab
			_on_tab_changed(target_tab)
			
	# Trigger immediate restoration if data is already present
	# Do not wipe the restore ID on fail here (pass false), as the full data might still be loading.
	if _last_selected_restore_id != "":
		print("[DIAGNOSTIC] VendorTradePanel Attempting immediate restore of ID: ", _last_selected_restore_id, " in tree: ", _last_selected_tree)
		var success := false
		if _last_selected_tree == "vendor" and is_instance_valid(vendor_item_tree):
			success = _restore_selection(vendor_item_tree, _last_selected_restore_id, false)
		elif _last_selected_tree == "convoy" and is_instance_valid(convoy_item_tree):
			success = _restore_selection(convoy_item_tree, _last_selected_restore_id, false)
		print("[DIAGNOSTIC] VendorTradePanel Immediate restore result: ", success)
