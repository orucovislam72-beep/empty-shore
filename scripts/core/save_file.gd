class_name SaveFile
extends RefCounted
## Надёжная запись JSON-сохранений: версия формата, миграции,
## запись во временный файл и переименование (мир не теряется при вылете во время записи).
## Формат файла: {"format_version": int, "saved_at": int (unix), "data": {...}}

const TMP_SUFFIX: String = ".tmp"

var migrator: SaveMigrator


func _init(p_migrator: SaveMigrator = null) -> void:
	migrator = p_migrator if p_migrator != null else SaveMigrator.new(1)


func write(path: String, data: Dictionary) -> Error:
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			return mk
	var envelope: Dictionary = {
		"format_version": migrator.current_version,
		"saved_at": int(Time.get_unix_time_from_system()),
		"data": data,
	}
	var tmp_path: String = path + TMP_SUFFIX
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(envelope, "\t"))
	f.flush()
	var write_err: Error = f.get_error()
	f.close()
	if write_err != OK:
		return write_err
	# На Linux/Android rename() атомарно заменяет файл. Если платформа не позволяет
	# переименовать поверх существующего файла, удаляем старый и повторяем;
	# в этом окне read() подхватит целый .tmp.
	var err: Error = DirAccess.rename_absolute(tmp_path, path)
	if err != OK and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp_path, path)
	return err


## Возвращает {"ok": bool, "data": Dictionary, "error": String, "migrated": bool}.
func read(path: String) -> Dictionary:
	var res: Dictionary = _read_one(path)
	if not res["ok"] and res["error"] != "save_from_future" and FileAccess.file_exists(path + TMP_SUFFIX):
		var tmp_res: Dictionary = _read_one(path + TMP_SUFFIX)
		if tmp_res["ok"]:
			return tmp_res
	return res


func _read_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "error": "not_found", "migrated": false}
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "error": "corrupt", "migrated": false}
	var envelope: Dictionary = json.data
	if not envelope.has("format_version") or typeof(envelope.get("data")) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "error": "corrupt", "migrated": false}
	var version: int = int(envelope["format_version"])
	var mig: Dictionary = migrator.migrate(envelope["data"], version)
	if not mig["ok"]:
		return {"ok": false, "data": {}, "error": mig["error"], "migrated": false}
	return {"ok": true, "data": mig["data"], "error": "", "migrated": version != migrator.current_version}
