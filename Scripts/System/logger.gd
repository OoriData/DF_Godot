# Logger.gd
extends Node

# Simple logging utility with levels and optional HTTP trace flag.
# Loads configuration from res://config/app_config.cfg if present.

enum Level { DEBUG, INFO, WARN, ERROR }

var level: int = Level.INFO
var http_trace: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_from_config()
	# Basic startup log
	info("Logger ready (level=%s, http_trace=%s)", _level_to_string(level), str(http_trace))

func _load_from_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://config/app_config.cfg")
	if err != OK:
		return
	var level_str: String = String(cfg.get_value("logging", "level", "info")).to_lower()
	match level_str:
		"debug":
			level = Level.DEBUG
		"info":
			level = Level.INFO
		"warn":
			level = Level.WARN
		"error":
			level = Level.ERROR
		_:
			level = Level.INFO
	http_trace = bool(cfg.get_value("logging", "http_trace", false))

func set_level_str(level_str: String) -> void:
	var s := level_str.to_lower()
	match s:
		"debug": level = Level.DEBUG
		"info": level = Level.INFO
		"warn": level = Level.WARN
		"error": level = Level.ERROR
		_: pass

func debug(msg: String, a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	if level <= Level.DEBUG:
		print("[DEBUG] ", _fmt(msg, a, b, c))

func info(msg: String, a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	if level <= Level.INFO:
		print("[INFO ] ", _fmt(msg, a, b, c))

func warn(msg: String, a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	if level <= Level.WARN:
		printerr("[WARN ] ", _fmt(msg, a, b, c))

func error(msg: String, a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	printerr("[ERROR] ", _fmt(msg, a, b, c))

func _fmt(msg: String, a: Variant, b: Variant, c: Variant) -> String:
	var out := msg
	var args: Array = []
	if a != null: args.append(a)
	if b != null: args.append(b)
	if c != null: args.append(c)
	if args.size() > 0:
		# Support printf-style placeholders if present
		var ok := true
		if ok:
			# JSON stringify non-primitive types for readability
			var mapped := []
			for v in args:
				if typeof(v) in [TYPE_DICTIONARY, TYPE_ARRAY]:
					mapped.append(JSON.stringify(v))
				else:
					mapped.append(v)
			out = out % mapped
	return out

func _level_to_string(l: int) -> String:
	match l:
		Level.DEBUG: return "debug"
		Level.INFO: return "info"
		Level.WARN: return "warn"
		Level.ERROR: return "error"
		_: return "info"
