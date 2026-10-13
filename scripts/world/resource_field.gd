class_name ResourceField
extends RefCounted
## Ресурсные узлы мира (деревья, камни, руда, кусты): расстановка по seed, запас, добыча,
## восстановление и поиск цели перед игроком. Чистая логика без сцен и без физики:
## цель ищется пересечением луча взгляда со сферой узла через сетку ячеек 16 м.
## generate() можно вызывать в рабочем потоке (не трогает дерево сцены).

## Узел изменился (удар, истощение, восстановление).
signal node_changed(index: int)

const DEFAULT_PATH: String = "res://data/balance/resources.json"
const CELL: float = 16.0
const TICK_INTERVAL: float = 1.0

var reach: float = 3.0
var layout_hash: int = 0

## Описания типов (по порядку из data/balance/resources.json).
var types: Array[Dictionary] = []
var type_index: PackedInt32Array = PackedInt32Array()
var positions: PackedVector3Array = PackedVector3Array()
var yaws: PackedFloat32Array = PackedFloat32Array()
var scales: PackedFloat32Array = PackedFloat32Array()
var remaining: PackedInt32Array = PackedInt32Array()
var respawn_left: PackedFloat32Array = PackedFloat32Array()

var _grid: Dictionary = {}
var _depleted: PackedInt32Array = PackedInt32Array()
var _tick_acc: float = 0.0


func size() -> int:
	return positions.size()


## Расстановка узлов по seed. terrain — функция высоты, half — половина стороны карты.
static func generate(cfg: Dictionary, terrain: TerrainMath, half: float, water_level: float) -> ResourceField:
	var f: ResourceField = ResourceField.new()
	f.reach = JsonData.get_float(cfg, "reach_m", 3.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_v: int = terrain.seed_value + JsonData.get_int(cfg, "seed_offset", 7)
	rng.seed = seed_v
	var clear_r: float = JsonData.get_float(cfg, "spawn_clear_radius_m", 6.0)
	var slope_max: float = JsonData.get_float(cfg, "min_slope_free", 0.9)
	var water_margin: float = JsonData.get_float(cfg, "water_margin_m", 0.4)
	var margin: float = 4.0
	var hash_src: String = str(seed_v)
	var list: Variant = cfg.get("types", [])
	if typeof(list) != TYPE_ARRAY:
		push_error("ResourceField: поле types должно быть массивом")
		return f
	for t: Variant in list:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var td: Dictionary = t
		var ti: int = f.types.size()
		f.types.append(td)
		var count: int = JsonData.get_int(td, "count", 0)
		var stock: int = maxi(JsonData.get_int(td, "stock", 1), 1)
		hash_src += "|%s:%d" % [String(td.get("id", "")), count]
		var placed: int = 0
		var attempts: int = 0
		while placed < count and attempts < count * 20:
			attempts += 1
			var x: float = rng.randf_range(-half + margin, half - margin)
			var z: float = rng.randf_range(-half + margin, half - margin)
			var yaw: float = rng.randf() * TAU
			var sc: float = rng.randf_range(0.8, 1.3)
			if Vector2(x, z).length() < clear_r:
				continue
			var y: float = terrain.height_at(x, z)
			if y < water_level + water_margin:
				continue
			var slope: float = absf(terrain.height_at(x + 1.0, z) - y) + absf(terrain.height_at(x, z + 1.0) - y)
			if slope > slope_max:
				continue
			f._append(ti, Vector3(x, y, z), yaw, sc, stock)
			placed += 1
	f.layout_hash = hash_src.hash()
	return f


func _append(ti: int, pos: Vector3, yaw: float, sc: float, stock: int) -> void:
	var i: int = positions.size()
	type_index.append(ti)
	positions.append(pos)
	yaws.append(yaw)
	scales.append(sc)
	remaining.append(stock)
	respawn_left.append(0.0)
	var key: Vector2i = _cell_of(pos)
	var arr: PackedInt32Array = _grid.get(key, PackedInt32Array())
	arr.append(i)
	_grid[key] = arr


static func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func type_of(index: int) -> Dictionary:
	return types[type_index[index]]


func item_of(index: int) -> String:
	return String(type_of(index).get("item", ""))


func name_key_of(index: int) -> String:
	return String(type_of(index).get("name", ""))


func stock_of(index: int) -> int:
	return maxi(JsonData.get_int(type_of(index), "stock", 1), 1)


func is_available(index: int) -> bool:
	return remaining[index] > 0


## Точка попадания (центр сферы) узла.
func hit_center(index: int) -> Vector3:
	var h: float = JsonData.get_float(type_of(index), "hit_height", 0.5) * scales[index]
	return positions[index] + Vector3(0.0, h, 0.0)


func hit_radius(index: int) -> float:
	return JsonData.get_float(type_of(index), "radius", 0.8) * scales[index]


## Препятствие для персонажа: радиус и высота цилиндра (0 — сквозь узел можно пройти, например куст).
func collider_radius(index: int) -> float:
	return JsonData.get_float(type_of(index), "collider_radius", 0.0) * scales[index]


func collider_height(index: int) -> float:
	return JsonData.get_float(type_of(index), "collider_height", 1.0) * scales[index]


## Мешает ли какой-нибудь узел (в любом состоянии — истощённый вырастет снова) объёму box.
## Для проверки места постройки. Без физики: по сетке ячеек.
func blocks_box(box: AABB) -> bool:
	var c0: Vector2i = _cell_of(box.position - Vector3(2.0, 0.0, 2.0))
	var c1: Vector2i = _cell_of(box.end + Vector3(2.0, 0.0, 2.0))
	for cz: int in range(c0.y, c1.y + 1):
		for cx: int in range(c0.x, c1.x + 1):
			var key: Vector2i = Vector2i(cx, cz)
			if not _grid.has(key):
				continue
			var arr: PackedInt32Array = _grid[key]
			for i: int in arr:
				var r: float = maxf(collider_radius(i), 0.3)
				var h: float = maxf(collider_height(i), 1.0)
				var p: Vector3 = positions[i]
				if box.intersects(AABB(Vector3(p.x - r, p.y - 0.2, p.z - r), Vector3(r * 2.0, h + 0.2, r * 2.0))):
					return true
	return false


## Ближайший доступный узел на луче взгляда в пределах дальности reach_override (или reach).
## Возвращает индекс или -1.
func find_target(origin: Vector3, dir: Vector3, reach_override: float = -1.0) -> int:
	var max_d: float = reach if reach_override < 0.0 else reach_override
	var oc: Vector2i = _cell_of(origin)
	var best: int = -1
	var best_t: float = INF
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var key: Vector2i = Vector2i(oc.x + dx, oc.y + dz)
			if not _grid.has(key):
				continue
			var arr: PackedInt32Array = _grid[key]
			for i: int in arr:
				if remaining[i] <= 0:
					continue
				var r: float = hit_radius(i)
				var v: Vector3 = hit_center(i) - origin
				var t: float = v.dot(dir)
				if t < -r or t > max_d + r:
					continue
				var perp2: float = v.length_squared() - t * t
				if perp2 > r * r:
					continue
				if t < best_t:
					best_t = t
					best = i
	return best


## Удар по узлу с множителем инструмента. Возвращает добытое количество.
func hit(index: int, multiplier: float) -> int:
	if index < 0 or index >= positions.size() or remaining[index] <= 0 or multiplier <= 0.0:
		return 0
	var y: int = JsonData.get_int(type_of(index), "yield", 1)
	var amount: int = mini(maxi(int(round(float(y) * multiplier)), 1), remaining[index])
	remaining[index] -= amount
	if remaining[index] <= 0:
		respawn_left[index] = JsonData.get_float(type_of(index), "respawn_s", 600.0)
		_depleted.append(index)
	node_changed.emit(index)
	return amount


## Восстановление истощённых узлов (проверка раз в секунду).
func tick(delta: float) -> void:
	_tick_acc += delta
	if _tick_acc < TICK_INTERVAL:
		return
	var dt: float = _tick_acc
	_tick_acc = 0.0
	var k: int = _depleted.size() - 1
	while k >= 0:
		var i: int = _depleted[k]
		respawn_left[i] -= dt
		if respawn_left[i] <= 0.0:
			respawn_left[i] = 0.0
			remaining[i] = stock_of(i)
			_depleted.remove_at(k)
			node_changed.emit(i)
		k -= 1


## Сохраняются только изменённые узлы: [индекс, запас, секунд до восстановления].
func to_dict() -> Dictionary:
	var changed: Array = []
	for i: int in positions.size():
		if remaining[i] != stock_of(i):
			changed.append([i, remaining[i], snappedf(respawn_left[i], 0.1)])
	return {"layout_hash": layout_hash, "count": positions.size(), "changed": changed}


## Восстанавливает состояние узлов. Если расстановка изменилась (другой seed или данные),
## состояние сбрасывается — возвращает false.
func from_dict(d: Dictionary) -> bool:
	for i: int in positions.size():
		remaining[i] = stock_of(i)
		respawn_left[i] = 0.0
	_depleted.clear()
	if JsonData.get_int(d, "layout_hash", 0) != layout_hash or JsonData.get_int(d, "count", -1) != positions.size():
		return false
	var changed: Variant = d.get("changed", [])
	if typeof(changed) != TYPE_ARRAY:
		return false
	for e: Variant in changed:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() < 3:
			continue
		var i: int = int(e[0])
		if i < 0 or i >= positions.size():
			continue
		remaining[i] = clampi(int(e[1]), 0, stock_of(i))
		respawn_left[i] = maxf(float(e[2]), 0.0)
		if remaining[i] <= 0:
			if respawn_left[i] <= 0.0:
				respawn_left[i] = 0.01
			_depleted.append(i)
	return true
