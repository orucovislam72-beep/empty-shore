class_name ItemDB
extends RefCounted
## Справочник предметов из data/items/items.json. Чистые данные без сцен
## (используется в логике инвентаря, крафта и, позже, на сервере).

const DEFAULT_PATH: String = "res://data/items/items.json"
const KIND_RESOURCE: String = "resource"
const KIND_TOOL: String = "tool"
const KIND_FOOD: String = "food"
const KIND_DEPLOYABLE: String = "deployable"
const KIND_WEAPON: String = "weapon"
const KIND_AMMO: String = "ammo"
const WEAPON_NONE: String = ""
const WEAPON_MELEE: String = "melee"
const WEAPON_BOW: String = "bow"
const WEAPON_GUN: String = "gun"

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


## Прочность нового экземпляра инструмента или оружия; -1 — у предмета нет прочности.
func max_durability(id: String) -> int:
	var tool: Dictionary = get_def(id).get("tool", get_def(id).get("weapon", {}))
	if tool.is_empty():
		return -1
	return maxi(JsonData.get_int(tool, "durability", 1), 1)


func is_weapon(id: String) -> bool:
	return kind(id) == KIND_WEAPON


func weapon(id: String) -> Dictionary:
	return get_def(id).get("weapon", {})


## Тип оружия: melee | bow | gun; для инструментов и рук — melee; "" — предмет не для удара (еда, объект).
func weapon_type(id: String) -> String:
	if is_weapon(id):
		return String(weapon(id).get("type", WEAPON_MELEE))
	var k: String = kind(id)
	if id.is_empty() or k == KIND_TOOL or k == KIND_RESOURCE or k == KIND_AMMO:
		return WEAPON_MELEE
	return WEAPON_NONE


func is_ranged(id: String) -> bool:
	var t: String = weapon_type(id)
	return t == WEAPON_BOW or t == WEAPON_GUN


## Урон удара по животному предметом в руке (оружие ближнего боя, инструмент или руки).
func melee_damage(id: String) -> float:
	if is_weapon(id):
		return JsonData.get_float(weapon(id), "damage", 10.0)
	return JsonData.get_float(_tool_params(id), "damage", 6.0)


func melee_range(id: String) -> float:
	if is_weapon(id):
		return JsonData.get_float(weapon(id), "range_m", 2.5)
	return JsonData.get_float(_tool_params(id), "range_m", 2.6)


## Боеприпас оружия ("" — без боеприпасов).
func ammo_of(weapon_id: String) -> String:
	return String(weapon(weapon_id).get("ammo", ""))


func ammo_damage(ammo_id: String) -> float:
	return JsonData.get_float(get_def(ammo_id).get("ammo", {}), "damage", 10.0)


func magazine_size(weapon_id: String) -> int:
	return maxi(JsonData.get_int(weapon(weapon_id), "mag", 0), 0)


## Параметры удара для предмета в руке. Пустой id или не инструмент — голые руки.
func _tool_params(id: String) -> Dictionary:
	if is_tool(id):
		return get_def(id).get("tool", {})
	return _hand


func gather_multiplier(tool_id: String, resource_item: String) -> float:
	var g: Dictionary = _tool_params(tool_id).get("gather", {})
	return maxf(JsonData.get_float(g, resource_item, 0.0), 0.0)


func swing_time(tool_id: String) -> float:
	if is_weapon(tool_id):
		return maxf(JsonData.get_float(weapon(tool_id), "swing_time", 0.8), 0.1)
	return maxf(JsonData.get_float(_tool_params(tool_id), "swing_time", 0.8), 0.1)


func food(id: String) -> Dictionary:
	return get_def(id).get("food", {})


func deploy_type(id: String) -> String:
	return String(get_def(id).get("deploy", ""))


func equip_slot(id: String) -> String:
	return String(get_def(id).get("equip", ""))
