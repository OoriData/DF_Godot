extends "res://addons/gut/test.gd"

const APICallsScript = preload("res://Scripts/System/api_calls.gd")
const StubHTTPRequest = preload("res://Tests/stubs/stub_http_request.gd")

func test_extract_query_param_and_enqueue() -> void:
	var api := APICallsScript.new()
	assert_eq(api._extract_query_param("http://x/y?a=1&b=hello%20world", "b"), "hello world")
	var before := api._request_queue.size()
	api.buy_cargo("v", "c", "cargo", 2)
	assert_eq(api._request_queue.size(), before + 1)

func test_timeout_behavior_map_data_requeues_and_cancels() -> void:
	var api := APICallsScript.new()
	api.set_disable_request_timeouts_for_tests(true)
	var stub := StubHTTPRequest.new()
	api.set_http_request_for_tests(stub)

	api._is_request_in_progress = true
	api._current_request_purpose = api.RequestPurpose.MAP_DATA
	api._current_request_start_time = Time.get_unix_time_from_system()
	api._request_queue.clear()
	api._handle_request_timeout()

	assert_true(stub.cancel_called)
	assert_false(api._is_request_in_progress)
	assert_eq(int(api._current_request_purpose), int(api.RequestPurpose.NONE))
	assert_true(api._request_queue.size() >= 1)
	if api._request_queue.size() > 0:
		assert_eq(int(api._request_queue[0].get("purpose", -1)), int(api.RequestPurpose.MAP_DATA))

func test_auth_flow_happy_path_emits_session_and_user_id() -> void:
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

	# AUTH_URL completion triggers start_auth_poll(state)
	api._is_request_in_progress = true
	api._current_request_purpose = api.RequestPurpose.AUTH_URL
	api._last_requested_url = "%s/auth/discord/url" % api.BASE_URL
	stub.emit_json_response({"url": "https://example/auth", "state": "state123"}, 200)
	assert_true(bool(state["got_auth_url"]))
	assert_true(api._auth_poll.active)

	# AUTH_STATUS completion sets token and queues AUTH_ME
	api._is_request_in_progress = true
	api._current_request_purpose = api.RequestPurpose.AUTH_STATUS
	api._last_requested_url = "%s/auth/status?state=%s" % [api.BASE_URL, "state123"]
	stub.emit_json_response({"status": "complete", "session_token": "test_token_123"}, 200)
	assert_eq(String(state["got_session_token"]), "test_token_123")
	assert_eq(state["got_poll_finished"], true)

	# AUTH_ME completion resolves a valid uuid
	api._is_request_in_progress = true
	api._current_request_purpose = api.RequestPurpose.AUTH_ME
	api._last_requested_url = "%s/auth/me" % api.BASE_URL
	var expected_uuid := "123e4567-e89b-12d3-a456-426614174000"
	stub.emit_json_response({"user_id": expected_uuid}, 200)
	assert_eq(String(state["got_user_id"]), expected_uuid)
