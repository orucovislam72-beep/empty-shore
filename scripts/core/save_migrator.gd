class_name SaveMigrator
extends RefCounted
## Цепочка миграций формата сохранения: версия N -> N+1.
## Каждая миграция — Callable(data: Dictionary) -> Dictionary.

var current_version: int = 1
var _steps: Dictionary = {}


func _init(version: int = 1) -> void:
	current_version = version


func register(from_version: int, step: Callable) -> void:
	_steps[from_version] = step


## Возвращает {"ok": bool, "data": Dictionary, "error": String}.
func migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version > current_version:
		return {"ok": false, "data": data, "error": "save_from_future"}
	var result: Dictionary = data
	var v: int = from_version
	while v < current_version:
		if not _steps.has(v):
			return {"ok": false, "data": data, "error": "no_migration_from_%d" % v}
		var step: Callable = _steps[v]
		result = step.call(result.duplicate(true))
		v += 1
	return {"ok": true, "data": result, "error": ""}
