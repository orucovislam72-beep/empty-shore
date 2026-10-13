class_name ResourceField
extends RefCounted
## Ресурсные узлы мира (деревья, камни, руда, кусты): расстановка по seed, запас, добыча,
## восстановление и поиск цели перед игроком. Чистая логика без сцен и без физики:
## цель ищется пересечением луча взгляда со сферой узла через сетку ячеек 16 м.
## generate() можно вызывать в рабочем потоке (не трогает дерево сцены).
## С этапа 3 — generate_world(): узлы расставляются по чанкам (ChunkGrid) детерминированно по seed чанка
## и плотности типа в биоме; узлы одного чанка идут подряд (chunk_first/chunk_count), у каждого узла —
## номер чанка и номер внутри чанка (для сохранения по чанкам и подгрузки отрисовки).

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

## Чанк узла (линейный номер в grid) и номер узла внутри чанка.
var node_chunk: PackedInt32Array = PackedInt32Array()
var node_local: PackedInt32Array = PackedInt32Array()
## Первый глобальный индекс и число узлов чанка: линейный номер → int.
var chunk_first: Dictionary = {}
var chunk_count: Dictionary = {}
var grid: ChunkGrid = ChunkGrid.single(256.0)

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
	f.grid = ChunkGrid.single(half * 2.0)
	f.chunk_first[0] = 0
	f.chunk_count[0] = f.positions.size()
	return f


## Расстановка по чанкам мира этапа 3. Плотность — density[биом] узлов на 1000 м²; кандидаты чанка
## берутся по максимальной плотности типа и отбираются с вероятностью density[биом] / max.
## Без деревьев: вода, крутой склон, площадка высадки (clear_radius_m из world.json).
static func generate_world(cfg: Dictionary, gen: WorldGen) -> ResourceField:
	var f: ResourceField = ResourceField.new()
	f.reach = JsonData.get_float(cfg, "reach_m", 3.0)
	f.grid = gen.grid
	var seed_off: int = JsonData.get_int(cfg, "seed_offset", 7)
	var slope_max: float = JsonData.get_float(cfg, "min_slope_free", 0.9)
	var water_margin: float = JsonData.get_float(cfg, "water_margin_m", 0.4)
	var clear_r: float = JsonData.get_float(gen.cfg.get("landing", {}), "clear_radius_m", 16.0)
	var list: Variant = cfg.get("types", [])
	if typeof(list) != TYPE_ARRAY:
		push_error("ResourceField: поле types должно быть массивом")
		return f
	var dens: Array[PackedFloat32Array] = []
	var max_d: PackedFloat32Array = PackedFloat32Array()
	var stocks: PackedInt32Array = PackedInt32Array()
	var hash_src: String = "w%d:%d:%d" % [gen.seed_value, seed_off, WorldGen.GENERATOR_VERSION]
	for t: Variant in list:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var td: Dictionary = t
		f.types.append(td)
		var dd: Dictionary = td.get("density", {})
		var row: PackedFloat32Array = PackedFloat32Array()
		var m: float = 0.0
		for b: String in WorldGen.BIOME_IDS:
			var v: float = maxf(JsonData.get_float(dd, b, 0.0), 0.0)
			row.append(v)
			m = maxf(m, v)
			hash_src += "|%s:%s:%.3f" % [String(td.get("id", "")), b, v]
		dens.append(row)
		max_d.append(m)
		stocks.append(maxi(JsonData.get_int(td, "stock", 1), 1))
	var cm: float = gen.grid.chunk_m
	var area_k: float = cm * cm / 1000.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for ci: int in gen.grid.count():
		var c: Vector2i = gen.grid.coord_of_index(ci)
		var o: Vector2 = gen.grid.origin_of(c)
		var first: int = f.positions.size()
		for ti: int in f.types.size():
			if max_d[ti] <= 0.0:
				continue
			rng.seed = (gen.seed_value + seed_off) * 73856093 ^ (ci + 1) * 19349663 ^ (ti + 1) * 83492791
			var cand: int = int(ceil(max_d[ti] * area_k))
			for k: int in cand:
				var x: float = o.x + rng.randf() * cm
				var z: float = o.y + rng.randf() * cm
				var yaw: float = rng.randf() * TAU
				var sc: float = rng.randf_range(0.8, 1.3)
				var roll: float = rng.randf() * max_d[ti]
				if Vector2(x - gen.landing.x, z - gen.landing.z).length() < clear_r:
					continue
				var y: float = gen.height_at(x, z)
				if y < gen.water_level + water_margin:
					continue
				var b: int = gen.biome_after_height(x, z, y)
				if roll >= dens[ti][b]:
					continue
				var slope: float = absf(gen.height_at(x + 1.0, z) - y) + absf(gen.height_at(x, z + 1.0) - y)
				if slope > slope_max:
					continue
				f._append(ti, Vector3(x, y, z), yaw, sc, stocks[ti])
				f.node_chunk[f.positions.size() - 1] = ci
				f.node_local[f.positions.size() - 1] = f.positions.size() - 1 - first
		var n_c: int = f.positions.size() - first
		if n_c > 0:
			f.chunk_first[ci] = first
			f.chunk_count[ci] = n_c
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
	node_chunk.append(0)
	node_local.append(i)
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


## Состояние изменённых узлов по чанкам: out["cx,cz"]["r"] = [[номер в чанке, запас, секунд до восстановления]].
func to_chunks(out: Dictionary) -> void:
	for i: int in positions.size():
		if remaining[i] == stock_of(i):
			continue
		var k: String = ChunkGrid.key(grid.coord_of_index(node_chunk[i]))
		if not out.has(k):
			out[k] = {}
		var ch: Dictionary = out[k]
		if not ch.has("r"):
			ch["r"] = []
		(ch["r"] as Array).append([node_local[i], remaining[i], snappedf(respawn_left[i], 0.1)])


## Восстанавливает состояние узлов из записей чанков. hash_ok=false (другая расстановка) — сброс, false.
func from_chunks(chunks: Dictionary, hash_ok: bool) -> bool:
	for i: int in positions.size():
		remaining[i] = stock_of(i)
		respawn_left[i] = 0.0
	_depleted.clear()
	if not hash_ok:
		return false
	for k: Variant in chunks:
		var c: Vector2i = ChunkGrid.parse_key(String(k))
		if not grid.is_inside(c) or typeof(chunks[k]) != TYPE_DICTIONARY:
			continue
		var ci: int = grid.index_of_coord(c)
		var list: Variant = (chunks[k] as Dictionary).get("r", [])
		if typeof(list) != TYPE_ARRAY or not chunk_first.has(ci):
			continue
		var first: int = chunk_first[ci]
		var cnt: int = chunk_count[ci]
		for e: Variant in list:
			if typeof(e) != TYPE_ARRAY or (e as Array).size() < 3:
				continue
			var local: int = int(e[0])
			if local < 0 or local >= cnt:
				continue
			var i: int = first + local
			remaining[i] = clampi(int(e[1]), 0, stock_of(i))
			respawn_left[i] = maxf(float(e[2]), 0.0)
			if remaining[i] <= 0:
				if respawn_left[i] <= 0.0:
					respawn_left[i] = 0.01
				_depleted.append(i)
	return true


## Глобальные индексы узлов чанка ci: [first, count].
func chunk_range(ci: int) -> Vector2i:
	if not chunk_first.has(ci):
		return Vector2i(0, 0)
	return Vector2i(chunk_first[ci], chunk_count[ci])
