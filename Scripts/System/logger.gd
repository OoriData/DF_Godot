# Logger.gd
extends Node

# Simple logging utility with levels and optional HTTP trace flag.
# Loads configuration from res://app_config.cfg if present.

enum Level { DEBUG, INFO, WARN, ERROR }

var level: int = Level.INFO
var http_trace: bool = false

# Recent log ring buffer (for bug reports / diagnostics)
var _recent_lines: Array[String] = []
var _recent_times_ms: Array[int] = []
var _recent_max_lines: int = 400

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_from_config()
	# Allow optional config override
	var cfg := ConfigFile.new()
	if cfg.load("res://app_config.cfg") == OK:
		_recent_max_lines = int(cfg.get_value("logging", "recent_max_lines", _recent_max_lines))
	# Basic startup log
	info("Logger ready (level=%s, http_trace=%s)", _level_to_string(level), str(http_trace))

func get_recent_lines(max_lines: int = 200) -> Array[String]:
	var n := int(max(0, max_lines))
	if n == 0:
		return []
	if _recent_lines.size() <= n:
		return _recent_lines.duplicate()
	return _recent_lines.slice(_recent_lines.size() - n, _recent_lines.size())

func get_recent_lines_since(window_seconds: float, max_lines: int = 200) -> Array[String]:
	var n := int(max(0, max_lines))
	if n == 0:
		return []
	var ws := float(window_seconds)
	if ws <= 0.0:
		return get_recent_lines(n)
	var cutoff_ms := Time.get_ticks_msec() - int(round(ws * 1000.0))
	var out: Array[String] = []
	# Walk backwards so we grab newest first, then reverse.
	for i in range(_recent_lines.size() - 1, -1, -1):
		if i < _recent_times_ms.size() and _recent_times_ms[i] < cutoff_ms:
			break
		out.append(_recent_lines[i])
		if out.size() >= n:
			break
	out.reverse()
	return out

func clear_recent_lines() -> void:
	_recent_lines.clear()
	_recent_times_ms.clear()

func _push_recent_line(line: String) -> void:
	_recent_lines.append(line)
	_recent_times_ms.append(Time.get_ticks_msec())
	if _recent_lines.size() > _recent_max_lines:
		_recent_lines = _recent_lines.slice(_recent_lines.size() - _recent_max_lines, _recent_lines.size())
		if _recent_times_ms.size() > _recent_max_lines:
			_recent_times_ms = _recent_times_ms.slice(_recent_times_ms.size() - _recent_max_lines, _recent_times_ms.size())

func _load_from_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://app_config.cfg")
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
		var line := "[DEBUG] " + _fmt(msg, a, b, c)
		_push_recent_line(line)
		print(line)

func info(msg: String, a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	if level <= Level.INFO:
		var line := "[INFO ] " + _fmt(msg, a, b, c)
		_push_recent_line(line)
		print(line)

func warn(msg: String, a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	if level <= Level.WARN:
		var line := "[WARN ] " + _fmt(msg, a, b, c)
		_push_recent_line(line)
		printerr(line)

func error(msg: String, a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	var line := "[ERROR] " + _fmt(msg, a, b, c)
	_push_recent_line(line)
	printerr(line)

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
