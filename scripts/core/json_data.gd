class_name JsonData
extends RefCounted
## Загрузка параметров из JSON-файлов в data/.
## Важно: JSON не является ресурсом Godot, поэтому в пресете экспорта
## data/*.json добавлены в include_filter.


static func load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("JsonData: файл не найден: %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JsonData: ожидался объект JSON в %s" % path)
		return {}
	return parsed


static func get_float(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return fallback


static func get_int(d: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return int(v)
	return fallback


static func get_bool(d: Dictionary, key: String, fallback: bool) -> bool:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_BOOL:
		return v
	return fallback
