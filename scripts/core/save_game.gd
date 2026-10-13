extends Node
## Сервис сохранений (autoload «SaveGame»). Слоты лежат в user://saves/<slot>.json.
## Формат: JSON-конверт с версией (см. SaveFile). Миграции регистрируются здесь при смене версии.
## На этапе 0 игровых данных ещё нет — сервис готов для этапа 1.

signal saved(slot: String)
signal loaded(slot: String, data: Dictionary)
signal failed(slot: String, error: String)

const SAVE_DIR: String = "user://saves"
## Текущая версия формата игровых сохранений. При изменении — добавить миграцию в _make_migrator().
const FORMAT_VERSION: int = 1

var _file: SaveFile = SaveFile.new(_make_migrator())


static func _make_migrator() -> SaveMigrator:
	var m: SaveMigrator = SaveMigrator.new(FORMAT_VERSION)
	# Пример на будущее: m.register(1, func(d: Dictionary) -> Dictionary: d["new_field"] = 0; return d)
	return m


func slot_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot.validate_filename()]


func has_slot(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func save_slot(slot: String, data: Dictionary) -> bool:
	var err: Error = _file.write(slot_path(slot), data)
	if err != OK:
		failed.emit(slot, error_string(err))
		return false
	saved.emit(slot)
	return true


func load_slot(slot: String) -> Dictionary:
	var res: Dictionary = _file.read(slot_path(slot))
	if not res["ok"]:
		failed.emit(slot, String(res["error"]))
		return {}
	loaded.emit(slot, res["data"])
	return res["data"]
