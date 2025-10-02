extends Node

# A lightweight, reusable tutorial state machine.
# Owns step order and supports next/prev/goto. Emits step_changed so a view/controller can render.

signal step_changed(step_id: String, index: int, total: int)
signal finished

var _steps: Array = [] # Array[Dictionary]: { id: String, title?: String }
var _index: int = -1
var _id_to_index: Dictionary = {}

func set_steps(steps: Array) -> void:
    # steps is an ordered array of dictionaries with at least an 'id' key
    _steps = []
    _id_to_index.clear()
    var i := 0
    for s in steps:
        if typeof(s) == TYPE_DICTIONARY and s.has("id") and typeof(s["id"]) == TYPE_STRING:
            _steps.append(s)
            _id_to_index[s["id"]] = i
            i += 1
        else:
            push_warning("TutorialDirector: skipping invalid step entry (missing id)")
    if _steps.size() == 0:
        _index = -1
    elif _index < 0 or _index >= _steps.size():
        _index = 0

func start(first_step_id: String = "") -> void:
    if _steps.is_empty():
        push_warning("TutorialDirector.start: no steps defined")
        return
    if first_step_id != "" and _id_to_index.has(first_step_id):
        _index = int(_id_to_index[first_step_id])
    else:
        _index = max(0, _index)
    _emit_current()

func next() -> void:
    if _steps.is_empty():
        return
    if _index < _steps.size() - 1:
        _index += 1
        _emit_current()
    else:
        finished.emit()

func prev() -> void:
    if _steps.is_empty():
        return
    if _index > 0:
        _index -= 1
        _emit_current()
    else:
        _emit_current() # stay on first but re-emit to allow UI refresh

func goto(step_id: String) -> void:
    if _steps.is_empty():
        return
    if _id_to_index.has(step_id):
        var new_index: int = int(_id_to_index[step_id])
        if new_index != _index:
            _index = new_index
        _emit_current()
    else:
        push_warning("TutorialDirector.goto: unknown step id: %s" % step_id)

func get_current_step_id() -> String:
    if _index < 0 or _index >= _steps.size():
        return ""
    return String(_steps[_index].get("id", ""))

func get_total_steps() -> int:
    return _steps.size()

func get_step_index() -> int:
    # 0-based index of the current step; returns -1 if not started or no steps.
    return _index

func _emit_current() -> void:
    if _index < 0 or _index >= _steps.size():
        return
    var id := String(_steps[_index].get("id", ""))
    step_changed.emit(id, _index + 1, _steps.size())
