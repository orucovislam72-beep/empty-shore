class_name ItemStorage
extends RefCounted
## Хранилище на N ячеек (ящик, запас обслуживания у знамени базы). Чистая логика без сцен.
## Слоты — упакованные массивы (id, количество, прочность), как в Inventory.
## Перекладывание между хранилищем и инвентарём игрока — put_from_inventory / take_to_inventory.

signal changed

var db: ItemDB
var _ids: PackedStringArray = PackedStringArray()
var _counts: PackedInt32Array = PackedInt32Array()
var _dur: PackedInt32Array = PackedInt32Array()


func _init(p_db: ItemDB = null, slots: int = 12) -> void:
	db = p_db
	_ids.resize(maxi(slots, 1))
	_counts.resize(maxi(slots, 1))
	_dur.resize(maxi(slots, 1))
	_dur.fill(-1)


func size() -> int:
	return _ids.size()


func slot_id(slot: int) -> String:
	return _ids[slot]


func slot_count(slot: int) -> int:
	return _counts[slot]


func slot_durability(slot: int) -> int:
	return _dur[slot]


func is_empty(slot: int) -> bool:
	return _counts[slot] <= 0


func is_all_empty() -> bool:
	for n: int in _counts:
		if n > 0:
			return false
	return true


func count_of(id: String) -> int:
	var n: int = 0
	for i: int in _ids.size():
		if _ids[i] == id:
			n += _counts[i]
	return n


## Добавляет предметы (сначала дополняет стопки, затем пустые ячейки). Возвращает остаток.
func add(id: String, count: int, durability: int = -1) -> int:
	if count <= 0 or db == null or not db.has(id):
		return count
	var left: int = count
	var stack: int = db.max_stack(id)
	var dur: int = durability if durability >= 0 else db.max_durability(id)
	if stack > 1:
		for i: int in _ids.size():
			if left <= 0:
				break
			if _ids[i] == id and _counts[i] > 0 and _counts[i] < stack:
				var put: int = mini(stack - _counts[i], left)
				_counts[i] += put
				left -= put
	for i: int in _ids.size():
		if left <= 0:
			break
		if _counts[i] <= 0:
			var put2: int = mini(stack, left)
			_ids[i] = id
			_counts[i] = put2
			_dur[i] = dur
			left -= put2
	if left != count:
		changed.emit()
	return left


## Убирает count предметов id. Если не хватает — ничего не меняет и возвращает false.
func remove(id: String, count: int) -> bool:
	if count <= 0:
		return true
	if count_of(id) < count:
		return false
	var left: int = count
	for i: int in range(_ids.size() - 1, -1, -1):
		if left <= 0:
			break
		if _ids[i] == id and _counts[i] > 0:
			var take: int = mini(_counts[i], left)
			_counts[i] -= take
			left -= take
			if _counts[i] <= 0:
				_clear(i)
	changed.emit()
	return true


## Переложить стопку из ячейки инвентаря игрока сюда (сколько поместится). Возвращает число переложенных.
func put_from_inventory(inv: Inventory, inv_slot: int) -> int:
	if inv.is_empty(inv_slot):
		return 0
	var id: String = inv.slot_id(inv_slot)
	var n: int = inv.slot_count(inv_slot)
	var left: int = add(id, n, inv.slot_durability(inv_slot))
	var moved: int = n - left
	if moved > 0:
		inv.remove_at(inv_slot, moved)
	return moved


## Забрать стопку из ячейки хранилища в инвентарь игрока (сколько поместится). Возвращает число переложенных.
func take_to_inventory(slot: int, inv: Inventory) -> int:
	if is_empty(slot):
		return 0
	var n: int = _counts[slot]
	var left: int = inv.add(_ids[slot], n, _dur[slot])
	var moved: int = n - left
	if moved > 0:
		_counts[slot] -= moved
		if _counts[slot] <= 0:
			_clear(slot)
		changed.emit()
	return moved


func clear_all() -> void:
	for i: int in _ids.size():
		_clear(i)
	changed.emit()


func to_dict() -> Dictionary:
	var slots: Array = []
	for i: int in _ids.size():
		if _counts[i] > 0:
			slots.append([i, _ids[i], _counts[i], _dur[i]])
	return {"slots": slots}


## Загружает состояние. Возвращает число пропущенных записей (неизвестные предметы, неверные ячейки).
func from_dict(d: Dictionary) -> int:
	for i: int in _ids.size():
		_clear(i)
	var skipped: int = 0
	var slots: Variant = d.get("slots", [])
	if typeof(slots) == TYPE_ARRAY:
		for e: Variant in slots:
			if typeof(e) != TYPE_ARRAY or (e as Array).size() < 4:
				skipped += 1
				continue
			var a: Array = e
			var slot: int = int(a[0])
			var id: String = String(a[1])
			var n: int = int(a[2])
			if slot < 0 or slot >= _ids.size() or db == null or not db.has(id) or n <= 0:
				skipped += 1
				continue
			_ids[slot] = id
			_counts[slot] = mini(n, db.max_stack(id))
			_dur[slot] = int(a[3])
	changed.emit()
	return skipped


func _clear(slot: int) -> void:
	_ids[slot] = ""
	_counts[slot] = 0
	_dur[slot] = -1
