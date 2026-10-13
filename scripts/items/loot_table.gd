class_name LootTable
extends RefCounted
## Таблицы лута из data/loot/loot_tables.json: бросок по весам в хранилище. Чистая логика без сцен.

const DEFAULT_PATH: String = "res://data/loot/loot_tables.json"

var _tables: Dictionary = {}


static func load_default() -> LootTable:
	var t: LootTable = LootTable.new()
	t.configure(JsonData.load_dict(DEFAULT_PATH))
	return t


func configure(data: Dictionary) -> void:
	_tables = data.get("tables", {})


func has_table(id: String) -> bool:
	return _tables.has(id)


func table_ids() -> PackedStringArray:
	return PackedStringArray(_tables.keys())


## Все предметы таблицы (для проверок данных).
func items_of(id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var t: Dictionary = _tables.get(id, {})
	for e: Variant in t.get("entries", []):
		if typeof(e) == TYPE_DICTIONARY:
			out.append(String((e as Dictionary).get("item", "")))
	return out


static func _range(v: Variant, fallback: Vector2i) -> Vector2i:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		var a: int = int(v[0])
		return Vector2i(a, maxi(int(v[1]), a))
	return fallback


## Бросок по таблице id: кладёт выпавшее в storage (что не поместилось — теряется). Возвращает число стопок.
func roll(id: String, rng: RandomNumberGenerator, storage: ItemStorage) -> int:
	var t: Dictionary = _tables.get(id, {})
	var entries: Variant = t.get("entries", [])
	if typeof(entries) != TYPE_ARRAY or (entries as Array).is_empty():
		return 0
	var total: float = 0.0
	for e: Variant in entries:
		total += maxf(JsonData.get_float(e as Dictionary, "weight", 1.0), 0.0)
	if total <= 0.0:
		return 0
	var rolls: Vector2i = _range(t.get("rolls", [1, 1]), Vector2i(1, 1))
	var n: int = rng.randi_range(rolls.x, rolls.y)
	var stacks: int = 0
	for r: int in n:
		var pick: float = rng.randf() * total
		for e: Variant in entries:
			var ed: Dictionary = e
			pick -= maxf(JsonData.get_float(ed, "weight", 1.0), 0.0)
			if pick <= 0.0:
				var cnt: Vector2i = _range(ed.get("count", [1, 1]), Vector2i(1, 1))
				if storage.add(String(ed.get("item", "")), rng.randi_range(cnt.x, cnt.y)) == 0:
					stacks += 1
				break
	return stacks
