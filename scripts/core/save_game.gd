extends Node
## Сервис сохранений (autoload «SaveGame»). Слоты лежат в user://saves/<slot>.save (с этапа 3).
## Формат v3 — WorldSaveFile: JSON игрока + двоичные записи чанков (ChunkCodec) в одном файле.
## Старые слоты <slot>.json (JSON-конверт SaveFile, v1–v2) читаются и мигрируют до v3; после первой
## записи в новом формате старый файл удаляется. См. docs/ROADMAP.md (этап 3, решение 2).
## Миграции регистрируются в _make_migrator() при смене FORMAT_VERSION.
## save_slot_async() пишет файл в WorkerThreadPool (автосохранение не тормозит кадр);
## save_slot() — синхронно (выход в меню, сворачивание приложения).

signal saved(slot: String)
signal loaded(slot: String, data: Dictionary)
signal failed(slot: String, error: String)

const SAVE_DIR: String = "user://saves"
const MAIN_SLOT: String = "main"
## Текущая версия формата игровых сохранений. При изменении — добавить миграцию в _make_migrator().
## v1 — этап 1: world, player, inventory, crafting, resources, deployables.
## v2 — этап 2: + building (детали построек), claims (обслуживание знамён); у объектов deployables
##      добавлены владелец, список права и хранилище (старые 6-полевые записи читаются как есть).
## v3 — этап 3: мир по чанкам. Узлы, точки лута, мешки/туши, детали построек и объекты лежат в разделе
##      chunks ({"cx,cz": {...}}), на диске — двоичными записями; в world — generator, resources_hash, loot_hash;
##      у игрока — respawn_cd (перезарядка спальников).
const FORMAT_VERSION: int = 3
const LEGACY_EXT: String = ".json"
const SAVE_EXT: String = ".save"

## Папка слотов. Тесты подменяют её, чтобы не трогать сохранения игрока.
var save_dir: String = SAVE_DIR
## Главное меню выставляет true перед переходом в игру, если игрок выбрал «Продолжить».
var continue_requested: bool = false

var _file: WorldSaveFile = WorldSaveFile.new(_make_migrator())
var _legacy: SaveFile = SaveFile.new(_make_migrator())
var _task_id: int = -1
var _task_slot: String = ""
var _task_error: Error = OK
var _pending: Dictionary = {}
var _pending_slot: String = ""


static func _make_migrator() -> SaveMigrator:
	var m: SaveMigrator = SaveMigrator.new(FORMAT_VERSION)
	m.register(1, migrate_1_to_2)
	m.register(2, migrate_2_to_3)
	return m


## 1 → 2: построек и знамён ещё не было — добавляем пустые разделы.
static func migrate_1_to_2(d: Dictionary) -> Dictionary:
	if not d.has("building"):
		d["building"] = {"pieces": []}
	if not d.has("claims"):
		d["claims"] = {"acc": 0.0, "debt": {}}
	return d


## 2 → 3: мир стал чанковым. Детали построек и объекты раскладываются по чанкам (с порядковым номером,
## чтобы ссылки знамён на объекты остались верными); состояние узлов старой тестовой карты 256 м
## не переносится (другая расстановка — узлы и так сбросились бы). Рельеф нового мира другой: постройки
## старой карты остаются на своих координатах и могут оказаться в воздухе или под водой (см. отчёт).
static func migrate_2_to_3(d: Dictionary) -> Dictionary:
	var wcfg: Dictionary = JsonData.load_dict(WorldGen.DEFAULT_PATH)
	var grid: ChunkGrid = ChunkGrid.new(JsonData.get_float(wcfg, "size_m", 1280.0), JsonData.get_float(wcfg, "chunk_m", 64.0))
	var cell: float = JsonData.get_float(JsonData.load_dict(BuildingDefs.DEFAULT_PATH), "grid_m", 3.0)
	var chunks: Dictionary = d.get("chunks", {}) if typeof(d.get("chunks")) == TYPE_DICTIONARY else {}
	var pieces: Variant = (d.get("building", {}) as Dictionary).get("pieces", []) if typeof(d.get("building")) == TYPE_DICTIONARY else []
	if typeof(pieces) == TYPE_ARRAY:
		for i: int in (pieces as Array).size():
			var e: Variant = pieces[i]
			if typeof(e) != TYPE_ARRAY or (e as Array).size() < 4:
				continue
			_chunk_list(chunks, grid.key_of((float(e[2]) + 0.5) * cell, (float(e[3]) + 0.5) * cell), "p").append([i, e])
	var objs: Variant = (d.get("deployables", {}) as Dictionary).get("objects", []) if typeof(d.get("deployables")) == TYPE_DICTIONARY else []
	if typeof(objs) == TYPE_ARRAY:
		for i: int in (objs as Array).size():
			var e2: Variant = objs[i]
			if typeof(e2) != TYPE_ARRAY or (e2 as Array).size() < 6:
				continue
			_chunk_list(chunks, grid.key_of(float(e2[1]), float(e2[3])), "d").append([i, e2])
	d.erase("building")
	d.erase("deployables")
	d.erase("resources")
	d["chunks"] = chunks
	var world: Dictionary = d.get("world", {}) if typeof(d.get("world")) == TYPE_DICTIONARY else {}
	world["generator"] = WorldGen.GENERATOR_VERSION
	world["migrated_from"] = 2
	d["world"] = world
	return d


static func _chunk_list(chunks: Dictionary, k: String, tag: String) -> Array:
	if not chunks.has(k):
		chunks[k] = {}
	var ch: Dictionary = chunks[k]
	if not ch.has(tag):
		ch[tag] = []
	return ch[tag]


func slot_path(slot: String) -> String:
	return "%s/%s%s" % [save_dir, slot.validate_filename(), SAVE_EXT]


## Путь слота старого формата (JSON, этапы 1–2).
func legacy_path(slot: String) -> String:
	return "%s/%s%s" % [save_dir, slot.validate_filename(), LEGACY_EXT]


func has_slot(slot: String) -> bool:
	for p: String in [slot_path(slot), legacy_path(slot)]:
		if FileAccess.file_exists(p) or FileAccess.file_exists(p + SaveFile.TMP_SUFFIX):
			return true
	return false


func delete_slot(slot: String) -> void:
	wait_for_pending()
	for p: String in [slot_path(slot), slot_path(slot) + SaveFile.TMP_SUFFIX, legacy_path(slot), legacy_path(slot) + SaveFile.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _remove_legacy(slot: String) -> void:
	for p: String in [legacy_path(slot), legacy_path(slot) + SaveFile.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func save_slot(slot: String, data: Dictionary) -> bool:
	wait_for_pending()
	var err: Error = _file.write(slot_path(slot), data)
	if err != OK:
		failed.emit(slot, error_string(err))
		return false
	_remove_legacy(slot)
	saved.emit(slot)
	return true


## Запись в рабочем потоке. data должен быть свежим снимком (to_dict()), его больше не трогают.
## Если запись уже идёт — новый снимок ждёт своей очереди (хранится только последний).
func save_slot_async(slot: String, data: Dictionary) -> void:
	if _task_id != -1:
		_pending = data
		_pending_slot = slot
		return
	_task_slot = slot
	_task_id = WorkerThreadPool.add_task(_write_task.bind(slot_path(slot), data), false, "save_game")


func is_saving() -> bool:
	return _task_id != -1


func _write_task(path: String, data: Dictionary) -> void:
	_task_error = _file.write(path, data)


## Дождаться фоновой записи (перед синхронной записью, удалением, выходом).
func wait_for_pending() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_finish_task()
	if not _pending.is_empty():
		var data: Dictionary = _pending
		var slot: String = _pending_slot
		_pending = {}
		var err: Error = _file.write(slot_path(slot), data)
		if err != OK:
			failed.emit(slot, error_string(err))
		else:
			saved.emit(slot)


func _process(_delta: float) -> void:
	if _task_id == -1 or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_finish_task()
	if not _pending.is_empty():
		var data: Dictionary = _pending
		_pending = {}
		save_slot_async(_pending_slot, data)


func _finish_task() -> void:
	_task_id = -1
	if _task_error != OK:
		failed.emit(_task_slot, error_string(_task_error))
	else:
		_remove_legacy(_task_slot)
		saved.emit(_task_slot)


func load_slot(slot: String) -> Dictionary:
	wait_for_pending()
	var res: Dictionary = _file.read(slot_path(slot))
	if not res["ok"] and res["error"] == "not_found":
		# Сохранение этапов 1–2 (JSON) — мигрирует до текущей версии.
		res = _legacy.read(legacy_path(slot))
	if not res["ok"]:
		failed.emit(slot, String(res["error"]))
		return {}
	loaded.emit(slot, res["data"])
	return res["data"]


func _exit_tree() -> void:
	wait_for_pending()
