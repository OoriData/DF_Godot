extends Node

# Emitted when a push notification is tapped by the user, or opened from the OS
signal push_dialogue_requested(dialogue_id: String)

var _push_toast_scene = preload("res://Scenes/UI/PushToast.tscn")
var _toast_instance: Node = null

var _has_registered_this_session: bool = false
var _platform: String = ""

func _ready() -> void:
	if OS.get_name() == "iOS":
		_platform = "ios"
		_setup_ios()
	elif OS.get_name() == "Android":
		_platform = "android"
		_setup_android()

	var hub = get_node_or_null("/root/SignalHub")
	if is_instance_valid(hub) and hub.has_signal("user_changed"):
		hub.user_changed.connect(_on_user_changed)

func _setup_ios() -> void:
	if not Engine.has_singleton("APN"):
		push_warning("[PushManager] APN singleton not found — push notifications unavailable.")
		return
	var apn = Engine.get_singleton("APN")
	if apn.has_signal("device_address_changed"):
		apn.connect("device_address_changed", _on_token_received)
	if apn.has_signal("push_message_received"):
		apn.connect("push_message_received", _on_push_message_received)
	print("[PushManager] APN plugin found and signals connected.")
	
	# Start initialization (must happen after connects)
	if apn.has_method("init"):
		apn.init()

func _setup_android() -> void:
	if not Engine.has_singleton("GodotFirebaseCloudMessaging"):
		push_warning("[PushManager] GodotFirebaseCloudMessaging singleton not found — push unavailable.")
		return
	var fcm = Engine.get_singleton("GodotFirebaseCloudMessaging")
	if fcm.has_signal("token_received"):
		fcm.connect("token_received", _on_token_received)
	if fcm.has_signal("message_received"):
		fcm.connect("message_received", _on_push_message_received)
	print("[PushManager] GodotFirebaseCloudMessaging plugin found and signals connected.")

	# Request notification permission on Android 13+
	if fcm.has_method("requestPermission"):
		fcm.requestPermission()

func _on_user_changed(user: Dictionary) -> void:
	if user.is_empty():
		_has_registered_this_session = false
		return
	
	if _has_registered_this_session:
		return
	_has_registered_this_session = true
	
	# Request permissions / fetch token now that we're logged in.
	var api = get_node_or_null("/root/APICalls")
	if not is_instance_valid(api):
		return

	if _platform == "ios" and Engine.has_singleton("APN"):
		var apn = Engine.get_singleton("APN")
		if apn.has_method("register_push_notifications"):
			apn.register_push_notifications(apn.PUSH_SOUND | apn.PUSH_BADGE | apn.PUSH_ALERT)
			print("[PushManager] register_push_notifications() called.")
	elif _platform == "android":
		var fcm = Engine.get_singleton("GodotFirebaseCloudMessaging") \
			if Engine.has_singleton("GodotFirebaseCloudMessaging") else null
		if fcm and fcm.has_method("getToken"):
			fcm.getToken()  # Triggers token_received signal asynchronously

func _on_token_received(token_raw: Variant) -> void:
	var token: String = ""
	if typeof(token_raw) == TYPE_STRING:
		token = token_raw
	elif typeof(token_raw) == TYPE_PACKED_BYTE_ARRAY:
		token = token_raw.hex_encode()
	else:
		token = str(token_raw)
		
	print("[PushManager] Device token received: %s" % token)
	# Whenever the token refreshes, send it to the backend IF we have a user
	var api = get_node_or_null("/root/APICalls")
	if is_instance_valid(api):
		# We let the backend decide if it's logged in based on JWT header
		api.register_push_token(token, _platform)

func _on_push_message_received(payload: Dictionary) -> void:
	print("[PushManager] Received Push Payload: ", payload)
	
	var dialogue_id: String = ""
	var title: String = ""
	var body: String = ""

	if _platform == "ios":
		dialogue_id = payload.get("dialogue_id", "")
		var aps = payload.get("aps", {})
		if aps is Dictionary:
			var alert = aps.get("alert", {})
			if alert is Dictionary:
				title = alert.get("title", "Desolate Frontiers")
				body = alert.get("body", "You have a new message")
	elif _platform == "android":
		# Godot Firebase generally nests the data payload inside the dictionary.
		var data = payload.get("data", payload)
		var notification = payload.get("notification", {})
		
		if data is Dictionary:
			dialogue_id = str(data.get("dialogue_id", ""))
		if notification is Dictionary:
			title = notification.get("title", "Desolate Frontiers")
			body = notification.get("body", "You have a new message")

	if dialogue_id != "":
		# Ensure we have the toast instance
		if not is_instance_valid(_toast_instance):
			_toast_instance = _push_toast_scene.instantiate()
			get_tree().root.add_child.call_deferred(_toast_instance)
			if _toast_instance.has_signal("toast_tapped"):
				_toast_instance.toast_tapped.connect(_fire_dialogue)
		
		# Show the toast so the user can tap it if they are in-game
		if _toast_instance.has_method("show_toast"):
			_toast_instance.call_deferred("show_toast", title, body, dialogue_id)

func _fire_dialogue(dialogue_id: String) -> void:
	print("[PushManager] Firing deep link for dialogue: ", dialogue_id)
	push_dialogue_requested.emit(dialogue_id)
