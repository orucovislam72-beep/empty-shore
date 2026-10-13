class_name Deployables
extends RefCounted
## Размещённые игроком объекты: костёр (станция, свет, топливо), верстак 1 уровня,
## с этапа 2 — ящик (хранилище) и знамя базы (право владения, запас на обслуживание).
## Чистая логика без сцен (data/balance/deployables.json); сцена слушает сигналы и рисует.
## У каждого объекта есть владелец (кто поставил), список «своих» (для знамени) и,
## если у типа задано storage_slots, хранилище ItemStorage.

signal added(index: int)
## Состояние изменилось (зажёгся/погас костёр, подбросили дрова).
signal changed(index: int)
signal cleared

const DEFAULT_PATH: String = "res://data/balance/deployables.json"

var place_distance: float = 2.0
var min_spacing: float = 1.6
var interact_radius: float = 2.6

var kinds: PackedStringArray = PackedStringArray()
var positions: PackedVector3Array = PackedVector3Array()
var yaws: PackedFloat32Array = PackedFloat32Array()
var fuel: PackedFloat32Array = PackedFloat32Array()
var owners: PackedStringArray = PackedStringArray()
## Список игроков с правом (для знамени базы).
var auth: Array[PackedStringArray] = []
## Хранилище объекта или null.
var storages: Array[ItemStorage] = []
## Справочник предметов для хранилищ (задаёт сессия).
var db: ItemDB

var _types: Dictionary = {}


func configure(cfg: Dictionary) -> void:
	place_distance = JsonData.get_float(cfg, "place_distance_m", 2.0)
	min_spacing = JsonData.get_float(cfg, "min_spacing_m", 1.6)
	interact_radius = JsonData.get_float(cfg, "interact_radius_m", 2.6)
	_types = cfg.get("types", {})


func size() -> int:
	return kinds.size()


func has_type(kind: String) -> bool:
	return _types.has(kind)


func type_def(kind: String) -> Dictionary:
	return _types.get(kind, {})


func is_fueled(kind: String) -> bool:
	return type_def(kind).has("fuel_per_wood_s")


func is_lit(index: int) -> bool:
	return fuel[index] > 0.0


func has_storage(index: int) -> bool:
	return index >= 0 and index < storages.size() and storages[index] != null


func claim_radius(kind: String) -> float:
	return JsonData.get_float(type_def(kind), "claim_radius_m", 0.0)


func is_authorized(index: int, who: String) -> bool:
	return auth[index].has(who)


func authorize(index: int, who: String) -> void:
	if not auth[index].has(who):
		auth[index].append(who)
		changed.emit(index)


func deauthorize(index: int, who: String) -> void:
	var at: int = auth[index].find(who)
	if at >= 0:
		auth[index].remove_at(at)
		changed.emit(index)


func clear_auth(index: int) -> void:
	auth[index] = PackedStringArray()
	changed.emit(index)


## Опустить объект на высоту y (если пол под ним обрушился).
func drop_to(index: int, y: float) -> void:
	positions[index].y = y
	changed.emit(index)


## Пересекается ли объём box с каким-нибудь объектом (условный куб 1,2 × 1,2 × 1,2 м).
func blocks_box(box: AABB) -> bool:
	for i: int in kinds.size():
		var p: Vector3 = positions[i]
		if box.intersects(AABB(Vector3(p.x - 0.6, p.y, p.z - 0.6), Vector3(1.2, 1.2, 1.2))):
			return true
	return false


## Можно ли поставить объект в точку (не слишком близко к другим).
func can_place(pos: Vector3) -> bool:
	for i: int in kinds.size():
		if positions[i].distance_to(pos) < min_spacing:
			return false
	return true


## Ставит объект. Возвращает индекс или -1.
func place(kind: String, pos: Vector3, yaw: float, owner_id: String = "") -> int:
	if not _types.has(kind) or not can_place(pos):
		return -1
	_append(kind, pos, yaw, JsonData.get_float(type_def(kind), "initial_fuel_s", 0.0), owner_id)
	if claim_radius(kind) > 0.0 and not owner_id.is_empty():
		auth[kinds.size() - 1].append(owner_id)
	var i: int = kinds.size() - 1
	added.emit(i)
	return i


## Ближайший объект в радиусе interact_radius или -1.
func nearest(pos: Vector3, radius: float = -1.0) -> int:
	var r: float = interact_radius if radius < 0.0 else radius
	var best: int = -1
	var best_d: float = r * r
	for i: int in kinds.size():
		var d: float = positions[i].distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = i
	return best


## Станции крафта в радиусе действия от pos (костёр — только горящий). Пишет в out без дублей.
func stations_near(pos: Vector3, out: PackedStringArray) -> void:
	out.clear()
	for i: int in kinds.size():
		var def: Dictionary = type_def(kinds[i])
		var st: String = String(def.get("station", ""))
		if st.is_empty() or out.has(st):
			continue
		if is_fueled(kinds[i]) and not is_lit(i):
			continue
		var r: float = JsonData.get_float(def, "station_radius", 3.0)
		if positions[i].distance_squared_to(pos) <= r * r:
			out.append(st)


## Сколько дерева возьмёт костёр за одно «подбросить» (0 — полон или не костёр).
func wood_wanted(index: int) -> int:
	var def: Dictionary = type_def(kinds[index])
	if not is_fueled(kinds[index]):
		return 0
	var per: float = JsonData.get_float(def, "fuel_per_wood_s", 30.0)
	var room: float = JsonData.get_float(def, "max_fuel_s", 900.0) - fuel[index]
	if room < per:
		return 0
	return mini(JsonData.get_int(def, "refuel_wood", 5), int(floor(room / per)))


func add_fuel(index: int, wood: int) -> void:
	var def: Dictionary = type_def(kinds[index])
	var per: float = JsonData.get_float(def, "fuel_per_wood_s", 30.0)
	fuel[index] = minf(fuel[index] + per * float(wood), JsonData.get_float(def, "max_fuel_s", 900.0))
	changed.emit(index)


func _append(kind: String, pos: Vector3, yaw: float, p_fuel: float, owner_id: String) -> void:
	kinds.append(kind)
	positions.append(pos)
	yaws.append(yaw)
	fuel.append(p_fuel)
	owners.append(owner_id)
	auth.append(PackedStringArray())
	var slots: int = JsonData.get_int(type_def(kind), "storage_slots", 0)
	storages.append(ItemStorage.new(db, slots) if slots > 0 else null)


func tick(delta: float) -> void:
	for i: int in kinds.size():
		if fuel[i] > 0.0:
			fuel[i] -= delta
			if fuel[i] <= 0.0:
				fuel[i] = 0.0
				changed.emit(i)


func clear() -> void:
	kinds.clear()
	positions.clear()
	yaws.clear()
	fuel.clear()
	owners.clear()
	auth.clear()
	storages.clear()
	cleared.emit()


func to_dict() -> Dictionary:
	var list: Array = []
	for i: int in kinds.size():
		var p: Vector3 = positions[i]
		var e: Array = [kinds[i], snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(yaws[i], 0.01), snappedf(fuel[i], 0.1),
			owners[i], Array(auth[i])]
		if storages[i] != null:
			e.append(storages[i].to_dict())
		list.append(e)
	return {"objects": list}


func from_dict(d: Dictionary) -> void:
	clear()
	var list: Variant = d.get("objects", [])
	if typeof(list) != TYPE_ARRAY:
		return
	for e: Variant in list:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() < 6 or not _types.has(String(e[0])):
			continue
		var a: Array = e
		# Формат этапа 1 — 6 полей; с этапа 2 добавлены владелец, список права и хранилище.
		_append(String(a[0]), Vector3(float(a[1]), float(a[2]), float(a[3])), float(a[4]), maxf(float(a[5]), 0.0), String(a[6]) if a.size() > 6 else "")
		var i: int = kinds.size() - 1
		if a.size() > 7 and typeof(a[7]) == TYPE_ARRAY:
			auth[i] = PackedStringArray(a[7] as Array)
		if a.size() > 8 and typeof(a[8]) == TYPE_DICTIONARY and storages[i] != null:
			storages[i].from_dict(a[8])
		added.emit(i)
