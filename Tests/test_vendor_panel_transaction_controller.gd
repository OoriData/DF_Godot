extends GutTest

var Tx = preload("res://Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd")


class FakeVendorService:
	extends RefCounted
	var sell_cargo_calls: Array = []
	func sell_cargo(vendor_id: String, convoy_id: String, cargo_id: String, quantity: int) -> void:
		sell_cargo_calls.append({"vendor_id": vendor_id, "convoy_id": convoy_id, "cargo_id": cargo_id, "quantity": quantity})


class DummyPanel:
	extends RefCounted
	var _vendor_service: RefCounted
	var vendor_data: Dictionary = {}
	var last_error: String = ""
	var refresh_calls: Array = []
	func _on_api_transaction_error(msg: String) -> void:
		last_error = msg
	func _request_authoritative_refresh(convoy_id: String, vendor_id: String) -> void:
		refresh_calls.append({"convoy_id": convoy_id, "vendor_id": vendor_id})


func test_dispatch_sell_blocks_resource_bearing_cargo_when_vendor_has_no_price():
	var panel := DummyPanel.new()
	panel.vendor_data = {"fuel_price": 0}
	var svc := FakeVendorService.new()
	panel._vendor_service = svc

	var item := {"cargo_id": "c1", "name": "Jerry Cans", "quantity": 1, "fuel": 20.0}
	Tx.dispatch_sell(panel, "v1", "cv1", item, 1)
	assert_eq(int(svc.sell_cargo_calls.size()), 0, "Should not call sell_cargo when vendor doesn't buy contained resources")
	assert_ne(panel.last_error, "", "Should produce an error message")


func test_dispatch_sell_allows_resource_bearing_cargo_when_vendor_has_price():
	var panel := DummyPanel.new()
	panel.vendor_data = {"fuel_price": 20}
	var svc := FakeVendorService.new()
	panel._vendor_service = svc

	var item := {"cargo_id": "c1", "name": "Jerry Cans", "quantity": 1, "fuel": 20.0}
	Tx.dispatch_sell(panel, "v1", "cv1", item, 1)
	assert_eq(int(svc.sell_cargo_calls.size()), 1, "Should call sell_cargo when vendor buys contained resources")
	assert_eq(int(panel.refresh_calls.size()), 1, "Should request refresh after dispatch")
