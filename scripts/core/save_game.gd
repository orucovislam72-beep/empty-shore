extends Node
## Сервис сохранений (autoload «SaveGame»). Слоты лежат в user://saves/<slot>.json.
## Формат: JSON-конверт с версией (см. SaveFile и docs/ROADMAP.md, раздел «Формат сохранения»).
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
const FORMAT_VERSION: int = 2

## Папка слотов. Тесты подменяют её, чтобы не трогать сохранения игрока.
var save_dir: String = SAVE_DIR
## Главное меню выставляет true перед переходом в игру, если игрок выбрал «Продолжить».
var continue_requested: bool = false

var _file: SaveFile = SaveFile.new(_make_migrator())
var _task_id: int = -1
var _task_slot: String = ""
var _task_error: Error = OK
var _pending: Dictionary = {}
var _pending_slot: String = ""


static func _make_migrator() -> SaveMigrator:
	var m: SaveMigrator = SaveMigrator.new(FORMAT_VERSION)
	m.register(1, migrate_1_to_2)
	return m


## 1 → 2: построек и знамён ещё не было — добавляем пустые разделы.
static func migrate_1_to_2(d: Dictionary) -> Dictionary:
	if not d.has("building"):
		d["building"] = {"pieces": []}
	if not d.has("claims"):
		d["claims"] = {"acc": 0.0, "debt": {}}
	return d


func slot_path(slot: String) -> String:
	return "%s/%s.json" % [save_dir, slot.validate_filename()]


func has_slot(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(slot_path(slot) + SaveFile.TMP_SUFFIX)


func delete_slot(slot: String) -> void:
	wait_for_pending()
	for p: String in [slot_path(slot), slot_path(slot) + SaveFile.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func save_slot(slot: String, data: Dictionary) -> bool:
	wait_for_pending()
	var err: Error = _file.write(slot_path(slot), data)
	if err != OK:
		failed.emit(slot, error_string(err))
		return false
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
		saved.emit(_task_slot)


func load_slot(slot: String) -> Dictionary:
	wait_for_pending()
	var res: Dictionary = _file.read(slot_path(slot))
	if not res["ok"]:
		failed.emit(slot, String(res["error"]))
		return {}
	loaded.emit(slot, res["data"])
	return res["data"]


func _exit_tree() -> void:
	wait_for_pending()
