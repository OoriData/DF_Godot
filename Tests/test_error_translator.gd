extends RefCounted

const TestUtil = preload("res://Tests/test_util.gd")
const ErrorTranslatorScript = preload("res://Scripts/System/error_translator.gd")

func run() -> void:
	var et := ErrorTranslatorScript.new()
	# ignored
	TestUtil.assert_eq(et.translate("Logged out."), "", "ignored substring")
	# precedence / specific match
	TestUtil.assert_eq(et.translate("Convoy does not have enough money (needed 5)"), "You do not have enough money for this transaction.", "money mapping")
	# prefix detail append
	var msg := et.translate("PATCH 'cargo_bought' failed: Not enough space")
	TestUtil.assert_true(msg.begins_with("Could not buy item:"), "prefix mapping")
	TestUtil.assert_true(msg.find("Not enough space") != -1, "prefix detail")
	# unknown fallback
	TestUtil.assert_eq(et.translate("Some totally unknown error"), "An unexpected error occurred. Please try again.", "unknown fallback")
