extends "res://addons/gut/test.gd"

const ErrorTranslatorScript = preload("res://Scripts/System/error_translator.gd")

func test_translate_ignored_substring_returns_empty() -> void:
	var et := ErrorTranslatorScript.new()
	assert_eq(et.translate("Logged out."), "")

func test_translate_specific_mapping_precedence() -> void:
	var et := ErrorTranslatorScript.new()
	assert_eq(
		et.translate("Convoy does not have enough money (needed 5)"),
		"You do not have enough money for this transaction."
	)

func test_translate_prefix_detail_append() -> void:
	var et := ErrorTranslatorScript.new()
	var msg := et.translate("PATCH 'cargo_bought' failed: Not enough space")
	assert_true(msg.begins_with("Could not buy item:"))
	assert_true(msg.find("Not enough space") != -1)

func test_translate_unknown_fallback() -> void:
	var et := ErrorTranslatorScript.new()
	assert_eq(et.translate("Some totally unknown error"), "An unexpected error occurred. Please try again.")
