class_name Inventory
extends RefCounted
## Инвентарь: быстрая панель (6), рюкзак (24), экипировка (4). Чистая логика без сцен.
## Слоты хранятся в упакованных массивах (id, количество, прочность, патроны в магазине оружия),
## без объектов на слот. Патроны в магазине (этап 3) переезжают вместе с оружием при переносе.
## Номера слотов: 0..5 — быстрая панель, 6..29 — рюкзак, 30..33 — экипировка.

signal changed

const HOTBAR_SIZE: int = 6
const BACKPACK_SIZE: int = 24
const EQUIP_SLOTS: PackedStringArray = ["head", "body", "legs", "feet"]
const HOTBAR_START: int = 0
const BACKPACK_START: int = HOTBAR_SIZE
const EQUIP_START: int = HOTBAR_SIZE + BACKPACK_SIZE
const TOTAL: int = HOTBAR_SIZE + BACKPACK_SIZE + 4

var db: ItemDB
var _ids: PackedStringArray = PackedStringArray()
var _counts: PackedInt32Array = PackedInt32Array()
var _dur: PackedInt32Array = PackedInt32Array()
var _ammo: PackedInt32Array = PackedInt32Array()


func _init(p_db: ItemDB = null) -> void:
	db = p_db
	_ids.resize(TOTAL)
	_counts.resize(TOTAL)
	_dur.resize(TOTAL)
	_dur.fill(-1)
	_ammo.resize(TOTAL)


static func is_hotbar(slot: int) -> bool:
	return slot >= HOTBAR_START and slot < BACKPACK_START


static func is_equip(slot: int) -> bool:
	return slot >= EQUIP_START and slot < TOTAL


func slot_id(slot: int) -> String:
	return _ids[slot]


func slot_count(slot: int) -> int:
	return _counts[slot]


func slot_durability(slot: int) -> int:
	return _dur[slot]


## Патроны в магазине оружия в слоте.
func slot_ammo(slot: int) -> int:
	return _ammo[slot]


func set_slot_ammo(slot: int, n: int) -> void:
	if _counts[slot] <= 0:
		return
	_ammo[slot] = maxi(n, 0)
	changed.emit()


func is_empty(slot: int) -> bool:
	return _counts[slot] <= 0


## Сколько предметов id в быстрой панели и рюкзаке (экипировка не считается).
func count_of(id: String) -> int:
	var n: int = 0
	for i: int in EQUIP_START:
		if _ids[i] == id:
			n += _counts[i]
	return n


## Сколько ещё предметов id поместится в быструю панель и рюкзак.
func free_space_for(id: String) -> int:
	var stack: int = db.max_stack(id)
	var n: int = 0
	for i: int in EQUIP_START:
		if _counts[i] <= 0:
			n += stack
		elif _ids[i] == id:
			n += maxi(stack - _counts[i], 0)
	return n


## Добавляет предметы. Возвращает остаток, который не поместился.
## durability < 0 — новая вещь с полной прочностью.
func add(id: String, count: int, durability: int = -1) -> int:
	if count <= 0 or not db.has(id):
		return count
	var left: int = count
	var stack: int = db.max_stack(id)
	var dur: int = durability if durability >= 0 else db.max_durability(id)
	if stack > 1:
		for i: int in EQUIP_START:
			if left <= 0:
				break
			if _ids[i] == id and _counts[i] > 0 and _counts[i] < stack:
				var put: int = mini(stack - _counts[i], left)
				_counts[i] += put
				left -= put
	# Инструменты, еда и размещаемое — сначала в быструю панель; ресурсы — сначала в рюкзак.
	var hotbar_first: bool = db.kind(id) != ItemDB.KIND_RESOURCE and db.kind(id) != ItemDB.KIND_AMMO
	for pass_i: int in 2:
		var from: int = HOTBAR_START if (pass_i == 0) == hotbar_first else BACKPACK_START
		var to: int = BACKPACK_START if from == HOTBAR_START else EQUIP_START
		for i: int in range(from, to):
			if left <= 0:
				break
			if _counts[i] <= 0:
				var put: int = mini(stack, left)
				_store(i, id, put, dur)
				left -= put
	if left != count:
		changed.emit()
	return left


## Убирает count предметов id (сначала из рюкзака с конца, потом из быстрой панели).
## Если предметов не хватает — ничего не меняет и возвращает false.
func remove(id: String, count: int) -> bool:
	if count <= 0:
		return true
	if count_of(id) < count:
		return false
	var left: int = count
	for i: int in range(EQUIP_START - 1, -1, -1):
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


func remove_at(slot: int, count: int) -> bool:
	if count <= 0 or _counts[slot] < count:
		return false
	_counts[slot] -= count
	if _counts[slot] <= 0:
		_clear(slot)
	changed.emit()
	return true


## Можно ли положить предмет id в слот (экипировка принимает только свой тип одежды).
func accepts(slot: int, id: String) -> bool:
	if id.is_empty():
		return true
	if is_equip(slot):
		return db.equip_slot(id) == EQUIP_SLOTS[slot - EQUIP_START]
	return true


## Перенос из слота в слот: объединение стопок, перестановка или перенос части (amount).
## amount <= 0 — вся стопка. Возвращает true, если что-то изменилось.
func move(from: int, to: int, amount: int = 0) -> bool:
	if from == to or from < 0 or to < 0 or from >= TOTAL or to >= TOTAL or _counts[from] <= 0:
		return false
	var id: String = _ids[from]
	var n: int = _counts[from] if amount <= 0 else mini(amount, _counts[from])
	if not accepts(to, id):
		return false
	if _counts[to] <= 0:
		_store(to, id, n, _dur[from], _ammo[from] if n == _counts[from] else 0)
		_counts[from] -= n
		if _counts[from] <= 0:
			_clear(from)
		changed.emit()
		return true
	if _ids[to] == id and db.max_stack(id) > 1:
		var put: int = mini(db.max_stack(id) - _counts[to], n)
		if put <= 0:
			return false
		_counts[to] += put
		_counts[from] -= put
		if _counts[from] <= 0:
			_clear(from)
		changed.emit()
		return true
	# Перестановка — только целыми стопками и если обе стороны принимают предметы.
	if n != _counts[from] or not accepts(from, _ids[to]):
		return false
	var t_id: String = _ids[to]
	var t_n: int = _counts[to]
	var t_d: int = _dur[to]
	var t_a: int = _ammo[to]
	_store(to, id, _counts[from], _dur[from], _ammo[from])
	_store(from, t_id, t_n, t_d, t_a)
	changed.emit()
	return true


## Делит стопку пополам в первый свободный слот (сначала рюкзак). false — нечего делить или нет места.
func split(slot: int) -> bool:
	if _counts[slot] < 2:
		return false
	var target: int = _first_empty(BACKPACK_START, EQUIP_START)
	if target == -1:
		target = _first_empty(HOTBAR_START, BACKPACK_START)
	if target == -1:
		return false
	return move(slot, target, _counts[slot] / 2)


## Тратит прочность инструмента. Возвращает true, если инструмент сломался (слот очищен).
func wear(slot: int, amount: int = 1) -> bool:
	if _counts[slot] <= 0 or _dur[slot] < 0:
		return false
	_dur[slot] = maxi(_dur[slot] - amount, 0)
	var broke: bool = _dur[slot] == 0
	if broke:
		_clear(slot)
	changed.emit()
	return broke


func clear_all() -> void:
	for i: int in TOTAL:
		_clear(i)
	changed.emit()


func to_dict() -> Dictionary:
	var slots: Array = []
	for i: int in TOTAL:
		if _counts[i] > 0:
			var e: Array = [i, _ids[i], _counts[i], _dur[i]]
			if _ammo[i] > 0:
				e.append(_ammo[i])
			slots.append(e)
	return {"slots": slots}


## Загружает состояние. Неизвестные предметы и неверные слоты пропускаются;
## возвращает число пропущенных записей (их стоит показать в логе).
func from_dict(d: Dictionary) -> int:
	for i: int in TOTAL:
		_clear(i)
	var skipped: int = 0
	var slots: Variant = d.get("slots", [])
	if typeof(slots) != TYPE_ARRAY:
		changed.emit()
		return 0
	for e: Variant in slots:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() < 4:
			skipped += 1
			continue
		var a: Array = e
		var slot: int = int(a[0])
		var id: String = String(a[1])
		var n: int = int(a[2])
		if slot < 0 or slot >= TOTAL or not db.has(id) or n <= 0 or not accepts(slot, id):
			skipped += 1
			continue
		_store(slot, id, mini(n, db.max_stack(id)), int(a[3]), maxi(int(a[4]), 0) if a.size() > 4 else 0)
	changed.emit()
	return skipped


func _first_empty(from: int, to: int) -> int:
	for i: int in range(from, to):
		if _counts[i] <= 0:
			return i
	return -1


func _store(slot: int, id: String, count: int, durability: int, ammo: int = 0) -> void:
	_ids[slot] = id
	_counts[slot] = count
	_dur[slot] = durability
	_ammo[slot] = ammo


func _clear(slot: int) -> void:
	_ids[slot] = ""
	_counts[slot] = 0
	_dur[slot] = -1
	_ammo[slot] = 0
