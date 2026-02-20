extends Control

signal back_requested

@onready var buy_button: Button = $Panel/VBoxContainer/BuyButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var close_button: Button = $Panel/CloseButton

var _pending_order_id: String = ""

func _ready() -> void:
	if is_instance_valid(buy_button):
		buy_button.pressed.connect(_on_buy_pressed)
	if is_instance_valid(close_button):
		close_button.pressed.connect(func(): emit_signal("back_requested"))
	
	close_button.visible = true
	
	# Connect to API signals
	var api = _api()
	if api:
		if not api.premium_order_created.is_connected(_on_order_created):
			api.premium_order_created.connect(_on_order_created)
		if not api.premium_transaction_finalized.is_connected(_on_txn_finalized):
			api.premium_transaction_finalized.connect(_on_txn_finalized)
		if not api.fetch_error.is_connected(_on_error):
			api.fetch_error.connect(_on_error)

	# Connect to Steam signals for overlay
	if SteamManager.is_steam_running():
		# GodotSteam signals are usually on the Steam singleton or use callback polling
		# For MicroTxn, the overlay handles the user interaction.
		# We need to wait for the backend to tell us it's done via Finalize,
		# OR we can listen for MicroTxnAuthorizationResponse from Steam if we want client-side confirmation.
		pass

func _on_buy_pressed() -> void:
	buy_button.disabled = true
	status_label.text = "Contacting Steam..."
	var api = _api()
	if api:
		api.create_premium_order()

func _on_order_created(data: Dictionary) -> void:
	# Backend has called InitTxn. Steam Overlay should open now.
	status_label.text = "Please complete purchase in Steam Overlay..."
	_pending_order_id = str(data.get("order_id", ""))
	
	# In a real flow, we might poll or wait for a "MicroTxnAuthorizationResponse" callback from Steam
	# But typically, if backend handles it, the backend might need a trigger to Finalize.
	# IF the backend just InitTxn, the User authorizes in Overlay.
	# THEN Steam sends a callback to the Game (Client or Server).
	# If Client gets callback, Client tells Backend "Finalize this order".
	
	# For simplicity/robustness, we can add a "Check Status" or "Complete" button, 
	# or listen for the GodotSteam signal `micro_txn_authorization_response`
	
	if SteamManager.is_steam_running():
		var steam_ref = Engine.get_singleton("Steam")
		if steam_ref:
			var steam_signals = steam_ref.get_signal_list()
			# check for micro_txn_authorization_response?
			# Actually, let's just show a "Confirm" button after they return from overlay if we can't detect it easily without more boilerplate.
			pass
	
	# Re-enable button as "Complete Purchase" or similar?
	buy_button.text = "Confirm Completion"
	buy_button.disabled = false
	buy_button.pressed.disconnect(_on_buy_pressed)
	buy_button.pressed.connect(_on_confirm_completion_pressed)

func _on_confirm_completion_pressed() -> void:
	if _pending_order_id == "":
		return
	status_label.text = "Finalizing..."
	buy_button.disabled = true
	var api = _api()
	if api:
		api.finalize_premium_transaction(_pending_order_id)

func _on_txn_finalized(data: Dictionary) -> void:
	status_label.text = "Premium Upgrade Unlocked! Thank you."
	buy_button.visible = false
	close_button.text = "Close"

func _on_error(msg: String) -> void:
	# filter for relevant errors?
	status_label.text = "Error: " + msg
	buy_button.disabled = false

func _api():
	return get_node_or_null("/root/APICalls")
