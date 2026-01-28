extends RefCounted

const TestUtil = preload("res://Tests/test_util.gd")
const APICallsScript = preload("res://Scripts/System/api_calls.gd")
const StubHTTPRequest = preload("res://Tests/stubs/stub_http_request.gd")

func run() -> void:
	_test_enqueue_and_query_helpers()
	_test_timeout_behavior_map_requeue()
	_test_auth_poll_happy_path()


func _get_tree_root() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


func _test_enqueue_and_query_helpers() -> void:
	var api := APICallsScript.new()
	# Avoid running _ready (network/timers); just exercise helper methods.
	TestUtil.assert_eq(api._extract_query_param("http://x/y?a=1&b=hello%20world", "b"), "hello world", "query param decode")
	var before := api._request_queue.size()
	api.buy_cargo("v", "c", "cargo", 2)
	TestUtil.assert_true(api._request_queue.size() == before + 1, "enqueue buy_cargo")
	TestUtil.assert_true(api._request_queue.size() >= 1, "queue non-empty")
	# No tree involvement here; keep it pure.


func _test_timeout_behavior_map_requeue() -> void:
	var root := _get_tree_root()
	TestUtil.assert_true(is_instance_valid(root), "have SceneTree root")
	if not is_instance_valid(root):
		return

	var api := APICallsScript.new()
	api.name = "APICalls_TestTimeout"
	root.add_child(api)
	api.set_disable_request_timeouts_for_tests(true)

	var stub := StubHTTPRequest.new()
	api.set_http_request_for_tests(stub)

	# Simulate an in-flight MAP_DATA request timing out.
	api._is_request_in_progress = true
	api._current_request_purpose = api.RequestPurpose.MAP_DATA
	api._current_request_start_time = Time.get_unix_time_from_system()
	api._request_queue.clear()
	api._handle_request_timeout()

	TestUtil.assert_true(stub.cancel_called, "timeout cancels in-flight map request")
	TestUtil.assert_true(api._is_request_in_progress == false, "timeout clears in-progress")
	TestUtil.assert_eq(int(api._current_request_purpose), int(api.RequestPurpose.NONE), "timeout resets purpose")
	TestUtil.assert_true(api._request_queue.size() >= 1, "timeout requeues map request")
	if api._request_queue.size() > 0:
		var first: Dictionary = api._request_queue[0]
		TestUtil.assert_eq(int(first.get("purpose", -1)), int(api.RequestPurpose.MAP_DATA), "requeued purpose is MAP_DATA")

	if is_instance_valid(api):
		if is_instance_valid(api.get_parent()):
			api.get_parent().remove_child(api)
		api.free()


func _test_auth_poll_happy_path() -> void:
	var api := APICallsScript.new()
	api.set_disable_request_timeouts_for_tests(true)
	var stub := StubHTTPRequest.new()
	api.set_http_request_for_tests(stub)

	var state := {
		"got_auth_url": false,
		"got_poll_finished": null,
		"got_session_token": "",
		"got_user_id": "",
	}

	api.auth_url_received.connect(func(d: Dictionary):
		state["got_auth_url"] = (d.has("url") and String(d.get("url", "")) != "")
	)
	api.auth_poll_finished.connect(func(success: bool):
		state["got_poll_finished"] = success
	)
	api.auth_session_received.connect(func(token: String):
		state["got_session_token"] = token
	)
	api.user_id_resolved.connect(func(uid: String):
		state["got_user_id"] = uid
	)

	# Simulate AUTH_URL completion (avoid calling get_auth_url(), which schedules timers).
	api._is_request_in_progress = true
	api._current_request_purpose = api.RequestPurpose.AUTH_URL
	api._last_requested_url = "%s/auth/discord/url" % api.BASE_URL
	stub.emit_json_response({"url": "https://example/auth", "state": "state123"}, 200)
	TestUtil.assert_true(bool(state["got_auth_url"]), "auth_url_received emitted")
	TestUtil.assert_true(api._auth_poll.active == true, "auth poll marked active")
	TestUtil.assert_true(api._request_queue.size() >= 1, "AUTH_STATUS queued")
	if api._request_queue.size() > 0:
		TestUtil.assert_eq(int(api._request_queue[0].get("purpose", -1)), int(api.RequestPurpose.AUTH_STATUS), "queued purpose is AUTH_STATUS")

	# Simulate AUTH_STATUS completion.
	api._is_request_in_progress = true
	api._current_request_purpose = api.RequestPurpose.AUTH_STATUS
	api._last_requested_url = "%s/auth/status?state=%s" % [api.BASE_URL, "state123"]
	stub.emit_json_response({"status": "complete", "session_token": "test_token_123"}, 200)
	TestUtil.assert_eq(String(state["got_session_token"]), "test_token_123", "auth_session_received token")
	TestUtil.assert_eq(state["got_poll_finished"], true, "auth_poll_finished success")
	TestUtil.assert_true(api._request_queue.size() >= 1, "AUTH_ME queued")
	var has_auth_me := false
	for r in api._request_queue:
		if int(r.get("purpose", -1)) == int(api.RequestPurpose.AUTH_ME):
			has_auth_me = true
			break
	TestUtil.assert_true(has_auth_me, "queued purpose includes AUTH_ME")

	# Simulate AUTH_ME completion.
	api._is_request_in_progress = true
	api._current_request_purpose = api.RequestPurpose.AUTH_ME
	api._last_requested_url = "%s/auth/me" % api.BASE_URL
	var expected_uuid := "123e4567-e89b-12d3-a456-426614174000"
	stub.emit_json_response({"user_id": expected_uuid}, 200)
	TestUtil.assert_eq(String(state["got_user_id"]), expected_uuid, "user_id_resolved emitted")
	# api/stub are unattached; no need to free explicitly.
