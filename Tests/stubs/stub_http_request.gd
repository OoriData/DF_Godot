extends Node

# A minimal HTTPRequest-like stub for headless unit tests.
# It never performs real IO; tests explicitly emit request_completed.
#
# NOTE: We intentionally do NOT extend HTTPRequest.
# Godot warns (and in this project, errors) when overriding native methods.

signal request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)

var requested_count: int = 0
var last_url: String = ""
var last_headers: PackedStringArray = PackedStringArray()
var last_method: int = HTTPClient.METHOD_GET
var last_body: String = ""

var cancel_called: bool = false
var _status: int = HTTPClient.STATUS_DISCONNECTED

func request(url: String, headers: PackedStringArray = PackedStringArray(), method: int = HTTPClient.METHOD_GET, body: String = "") -> Error:
	requested_count += 1
	last_url = url
	last_headers = headers
	last_method = method
	last_body = body
	cancel_called = false
	_status = HTTPClient.STATUS_REQUESTING
	return OK

func cancel_request() -> void:
	cancel_called = true
	_status = HTTPClient.STATUS_DISCONNECTED

func get_http_client_status() -> int:
	return _status

func emit_json_response(obj: Variant, response_code: int = 200, result_code: int = HTTPRequest.RESULT_SUCCESS) -> void:
	var body_str := ""
	if obj != null:
		body_str = JSON.stringify(obj)
	var bytes := body_str.to_utf8_buffer()
	_status = HTTPClient.STATUS_DISCONNECTED
	request_completed.emit(result_code, response_code, PackedStringArray(), bytes)

func emit_raw_response(body_str: String, response_code: int = 200, result_code: int = HTTPRequest.RESULT_SUCCESS) -> void:
	var bytes := (body_str if body_str != null else "").to_utf8_buffer()
	_status = HTTPClient.STATUS_DISCONNECTED
	request_completed.emit(result_code, response_code, PackedStringArray(), bytes)
