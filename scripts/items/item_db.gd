class_name ItemDB
extends RefCounted
## Справочник предметов из data/items/items.json. Чистые данные без сцен
## (используется в логике инвентаря, крафта и, позже, на сервере).

const DEFAULT_PATH: String = "res://data/items/items.json"
const KIND_RESOURCE: String = "resource"
const KIND_TOOL: String = "tool"
const KIND_FOOD: String = "food"
const KIND_DEPLOYABLE: String = "deployable"

var _items: Dictionary = {}
var _hand: Dictionary = {}
var _ids: PackedStringArray = PackedStringArray()


static func load_default() -> ItemDB:
	var db: ItemDB = ItemDB.new()
	db.configure(JsonData.load_dict(DEFAULT_PATH))
	return db


func configure(data: Dictionary) -> void:
	_items = data.get("items", {})
	_hand = data.get("hand", {})
	_ids = PackedStringArray(_items.keys())


func has(id: String) -> bool:
	return _items.has(id)


func ids() -> PackedStringArray:
	return _ids


func get_def(id: String) -> Dictionary:
	return _items.get(id, {})


func name_key(id: String) -> String:
	return String(get_def(id).get("name", id))


func desc_key(id: String) -> String:
	return String(get_def(id).get("desc", ""))


func kind(id: String) -> String:
	return String(get_def(id).get("kind", ""))


func icon_path(id: String) -> String:
	return String(get_def(id).get("icon", ""))


func max_stack(id: String) -> int:
	return maxi(JsonData.get_int(get_def(id), "stack", 1), 1)


func is_tool(id: String) -> bool:
	return kind(id) == KIND_TOOL


## Прочность нового экземпляра инструмента; -1 — у предмета нет прочности.
func max_durability(id: String) -> int:
	var tool: Dictionary = get_def(id).get("tool", {})
	if tool.is_empty():
		return -1
	return maxi(JsonData.get_int(tool, "durability", 1), 1)


## Параметры удара для предмета в руке. Пустой id или не инструмент — голые руки.
func _tool_params(id: String) -> Dictionary:
	if is_tool(id):
		return get_def(id).get("tool", {})
	return _hand


func gather_multiplier(tool_id: String, resource_item: String) -> float:
	var g: Dictionary = _tool_params(tool_id).get("gather", {})
	return maxf(JsonData.get_float(g, resource_item, 0.0), 0.0)


func swing_time(tool_id: String) -> float:
	return maxf(JsonData.get_float(_tool_params(tool_id), "swing_time", 0.8), 0.1)


func food(id: String) -> Dictionary:
	return get_def(id).get("food", {})


func deploy_type(id: String) -> String:
	return String(get_def(id).get("deploy", ""))


func equip_slot(id: String) -> String:
	return String(get_def(id).get("equip", ""))
