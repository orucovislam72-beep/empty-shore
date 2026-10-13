class_name Deployables
extends RefCounted
## Размещённые игроком объекты этапа 1: костёр (станция, свет, топливо) и верстак 1 уровня.
## Чистая логика без сцен (data/balance/deployables.json); сцена слушает сигналы и рисует.

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


## Можно ли поставить объект в точку (не слишком близко к другим).
func can_place(pos: Vector3) -> bool:
	for i: int in kinds.size():
		if positions[i].distance_to(pos) < min_spacing:
			return false
	return true


## Ставит объект. Возвращает индекс или -1.
func place(kind: String, pos: Vector3, yaw: float) -> int:
	if not _types.has(kind) or not can_place(pos):
		return -1
	kinds.append(kind)
	positions.append(pos)
	yaws.append(yaw)
	fuel.append(JsonData.get_float(type_def(kind), "initial_fuel_s", 0.0))
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
	cleared.emit()


func to_dict() -> Dictionary:
	var list: Array = []
	for i: int in kinds.size():
		var p: Vector3 = positions[i]
		list.append([kinds[i], snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(yaws[i], 0.01), snappedf(fuel[i], 0.1)])
	return {"objects": list}


func from_dict(d: Dictionary) -> void:
	clear()
	var list: Variant = d.get("objects", [])
	if typeof(list) != TYPE_ARRAY:
		return
	for e: Variant in list:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() < 6 or not _types.has(String(e[0])):
			continue
		kinds.append(String(e[0]))
		positions.append(Vector3(float(e[1]), float(e[2]), float(e[3])))
		yaws.append(float(e[4]))
		fuel.append(maxf(float(e[5]), 0.0))
		added.emit(kinds.size() - 1)
