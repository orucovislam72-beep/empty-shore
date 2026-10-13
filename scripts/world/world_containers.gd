class_name WorldContainers
extends RefCounted
## Контейнеры мира (этап 3), чистая логика без сцен:
## - точки лута (ящики, бочки, военные ящики) — расставлены по чанкам детерминированно по seed;
##   при первом открытии наполняются броском по таблице (data/loot); опустевшая точка исчезает
##   и через respawn_s наполняется снова;
## - мешки с вещами на месте гибели и туши животных — появляются в игре и исчезают, когда опустеют
##   или выйдет срок.
## Контейнер задаётся «ручкой»: точка лута — её индекс (0..N-1), мешок/туша — DYN_BASE + номер
## (номер не переиспользуется, поэтому ручка остаётся верной, пока открыт экран).

signal point_changed(index: int)
signal dynamic_added(handle: int)
signal dynamic_removed(handle: int)

const DEFAULT_PATH: String = "res://data/loot/loot_points.json"
const DYN_BASE: int = 1 << 20
const KIND_BAG: String = "bag"
const CORPSE_PREFIX: String = "corpse_"

var db: ItemDB
var tables: LootTable
var interact_radius: float = 2.4
var bag_despawn_s: float = 1800.0
var corpse_despawn_s: float = 600.0
var types: Array[Dictionary] = []
var grid: ChunkGrid = ChunkGrid.single(256.0)
var seed_value: int = 0
var layout_hash: int = 0

# Точки лута.
var p_type: PackedInt32Array = PackedInt32Array()
var p_pos: PackedVector3Array = PackedVector3Array()
var p_yaw: PackedFloat32Array = PackedFloat32Array()
var p_chunk: PackedInt32Array = PackedInt32Array()
var p_local: PackedInt32Array = PackedInt32Array()
## Содержимое (null — точка ещё не открывалась с последнего наполнения).
var p_storage: Array[ItemStorage] = []
## > 0 — точка пуста и ждёт наполнения (секунд).
var p_respawn: PackedFloat32Array = PackedFloat32Array()
## Сколько раз точку опустошали (для seed следующего броска).
var p_rolls: PackedInt32Array = PackedInt32Array()
var chunk_first: Dictionary = {}
var chunk_count: Dictionary = {}

# Мешки и туши.
var d_handle: PackedInt32Array = PackedInt32Array()
var d_kind: PackedStringArray = PackedStringArray()
var d_pos: PackedVector3Array = PackedVector3Array()
var d_yaw: PackedFloat32Array = PackedFloat32Array()
var d_life: PackedFloat32Array = PackedFloat32Array()
var d_owner: PackedStringArray = PackedStringArray()
var d_storage: Array[ItemStorage] = []

var _waiting: PackedInt32Array = PackedInt32Array()
var _next_serial: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func configure(cfg: Dictionary, p_db: ItemDB, p_tables: LootTable) -> void:
	db = p_db
	tables = p_tables
	interact_radius = JsonData.get_float(cfg, "interact_radius_m", 2.4)
	bag_despawn_s = JsonData.get_float(cfg.get("bag", {}), "despawn_s", 1800.0)
	corpse_despawn_s = JsonData.get_float(cfg.get("corpse", {}), "despawn_s", 600.0)
	types.clear()
	for t: Variant in cfg.get("types", []):
		if typeof(t) == TYPE_DICTIONARY:
			types.append(t)


## Расстановка точек по чанкам мира (детерминированно). Можно вызывать в рабочем потоке.
func generate_points(cfg: Dictionary, gen: WorldGen) -> void:
	grid = gen.grid
	seed_value = gen.seed_value
	var off: int = JsonData.get_int(cfg, "seed_offset", 101)
	var clear_r: float = JsonData.get_float(gen.cfg.get("landing", {}), "clear_radius_m", 16.0)
	var hash_src: String = "loot%d:%d:%d" % [gen.seed_value, off, WorldGen.GENERATOR_VERSION]
	for t: Dictionary in types:
		hash_src += "|" + JSON.stringify(t.get("chance", {}))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for ci: int in grid.count():
		var o: Vector2 = grid.origin_of(grid.coord_of_index(ci))
		var first: int = p_pos.size()
		for ti: int in types.size():
			rng.seed = (gen.seed_value + off) * 83492791 ^ (ci + 1) * 73856093 ^ (ti + 1) * 19349663
			var x: float = o.x + rng.randf_range(4.0, grid.chunk_m - 4.0)
			var z: float = o.y + rng.randf_range(4.0, grid.chunk_m - 4.0)
			var roll: float = rng.randf()
			var yaw: float = rng.randf() * TAU
			if Vector2(x - gen.landing.x, z - gen.landing.z).length() < clear_r:
				continue
			var y: float = gen.height_at(x, z)
			if y < gen.water_level + 0.3:
				continue
			var b: String = WorldGen.biome_id(gen.biome_after_height(x, z, y))
			if roll >= JsonData.get_float(types[ti].get("chance", {}), b, 0.0):
				continue
			_add_point(ti, Vector3(x, y, z), yaw, ci, p_pos.size() - first)
		if p_pos.size() > first:
			chunk_first[ci] = first
			chunk_count[ci] = p_pos.size() - first
	layout_hash = hash_src.hash()


## Точка вручную (тесты, маленькие карты).
func add_point(type_id: String, pos: Vector3, yaw: float = 0.0) -> int:
	var ti: int = type_index(type_id)
	if ti < 0:
		return -1
	var ci: int = grid.index_of(pos.x, pos.z)
	var local: int = 0
	for i: int in p_pos.size():
		if p_chunk[i] == ci:
			local += 1
	_add_point(ti, pos, yaw, ci, local)
	if not chunk_first.has(ci):
		chunk_first[ci] = p_pos.size() - 1
	chunk_count[ci] = int(chunk_count.get(ci, 0)) + 1
	return p_pos.size() - 1


func _add_point(ti: int, pos: Vector3, yaw: float, ci: int, local: int) -> void:
	p_type.append(ti)
	p_pos.append(pos)
	p_yaw.append(yaw)
	p_chunk.append(ci)
	p_local.append(local)
	p_storage.append(null)
	p_respawn.append(0.0)
	p_rolls.append(0)


func type_index(id: String) -> int:
	for i: int in types.size():
		if String(types[i].get("id", "")) == id:
			return i
	return -1


func point_count() -> int:
	return p_pos.size()


## id типа точки по номеру типа.
func point_type_id_by_type(t: int) -> String:
	return String(types[t].get("id", "")) if t >= 0 and t < types.size() else ""


func point_type_id(i: int) -> String:
	return String(types[p_type[i]].get("id", ""))


static func is_dynamic(handle: int) -> bool:
	return handle >= DYN_BASE


func is_point_available(i: int) -> bool:
	return p_respawn[i] <= 0.0


func _dyn_index(handle: int) -> int:
	return d_handle.find(handle)


func is_valid(handle: int) -> bool:
	if handle < 0:
		return false
	if is_dynamic(handle):
		return _dyn_index(handle) >= 0
	return handle < p_pos.size() and is_point_available(handle)


func position_of(handle: int) -> Vector3:
	if is_dynamic(handle):
		var j: int = _dyn_index(handle)
		return d_pos[j] if j >= 0 else Vector3.ZERO
	return p_pos[handle]


## Вид контейнера: id типа точки, "bag" или "corpse_<животное>".
func kind_of(handle: int) -> String:
	if is_dynamic(handle):
		var j: int = _dyn_index(handle)
		return d_kind[j] if j >= 0 else ""
	return point_type_id(handle)


## Ключ перевода названия контейнера.
func name_key(handle: int) -> String:
	var k: String = kind_of(handle)
	if k == KIND_BAG:
		return "LOOT_BAG"
	if k.begins_with(CORPSE_PREFIX):
		return "LOOT_CORPSE"
	if not is_dynamic(handle):
		return String(types[p_type[handle]].get("name", "LOOT_CRATE"))
	return "LOOT_CRATE"


## Содержимое; у нетронутой точки — бросок по таблице при первом обращении. null — контейнера нет.
func storage_of(handle: int) -> ItemStorage:
	if not is_valid(handle):
		return null
	if is_dynamic(handle):
		return d_storage[_dyn_index(handle)]
	var i: int = handle
	if p_storage[i] == null:
		var t: Dictionary = types[p_type[i]]
		var st: ItemStorage = ItemStorage.new(db, JsonData.get_int(t, "slots", 6))
		_rng.seed = seed_value * 31 + i * 7919 + p_rolls[i] * 104729 + 17
		tables.roll(String(t.get("table", "")), _rng, st)
		p_storage[i] = st
	return p_storage[i]


## Ближайший доступный контейнер в радиусе (по умолчанию interact_radius) или -1.
func nearest(pos: Vector3, radius: float = -1.0) -> int:
	var r: float = interact_radius if radius < 0.0 else radius
	var best: int = -1
	var best_d: float = r * r
	for j: int in d_pos.size():
		var dd: float = d_pos[j].distance_squared_to(pos)
		if dd <= best_d:
			best_d = dd
			best = d_handle[j]
	for i: int in p_pos.size():
		if p_respawn[i] > 0.0:
			continue
		var d: float = p_pos[i].distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = i
	return best


## После того как из контейнера что-то взяли: пустая точка уходит на перезарядку, пустой мешок/туша исчезают.
func after_take(handle: int) -> void:
	var st: ItemStorage = storage_of(handle)
	if st == null or not st.is_all_empty():
		return
	if is_dynamic(handle):
		_remove_dynamic(_dyn_index(handle))
	else:
		var i: int = handle
		p_storage[i] = null
		p_respawn[i] = maxf(JsonData.get_float(types[p_type[i]], "respawn_s", 1200.0), 0.01)
		p_rolls[i] += 1
		_waiting.append(i)
		point_changed.emit(i)


func _add_dynamic(kind: String, pos: Vector3, yaw: float, life: float, owner_id: String, st: ItemStorage) -> int:
	var h: int = DYN_BASE + _next_serial
	_next_serial += 1
	d_handle.append(h)
	d_kind.append(kind)
	d_pos.append(pos)
	d_yaw.append(yaw)
	d_life.append(life)
	d_owner.append(owner_id)
	d_storage.append(st)
	dynamic_added.emit(h)
	return h


func _remove_dynamic(j: int) -> void:
	if j < 0:
		return
	var h: int = d_handle[j]
	d_handle.remove_at(j)
	d_kind.remove_at(j)
	d_pos.remove_at(j)
	d_yaw.remove_at(j)
	d_life.remove_at(j)
	d_owner.remove_at(j)
	d_storage.remove_at(j)
	dynamic_removed.emit(h)


## Мешок со всеми вещами игрока на месте гибели. Инвентарь опустошается. -1 — нечего класть.
func add_bag(pos: Vector3, owner_id: String, inv: Inventory) -> int:
	var slots: int = 0
	for i: int in Inventory.TOTAL:
		if not inv.is_empty(i):
			slots += 2 if inv.slot_ammo(i) > 0 else 1
	if slots == 0:
		return -1
	var st: ItemStorage = ItemStorage.new(db, slots)
	for i: int in Inventory.TOTAL:
		if not inv.is_empty(i):
			st.put_from_inventory(inv, i)
	return _add_dynamic(KIND_BAG, pos, 0.0, bag_despawn_s, owner_id, st)


## Туша животного kind с добычей drops ({предмет: количество}).
func add_corpse(kind: String, pos: Vector3, yaw: float, drops: Dictionary) -> int:
	var st: ItemStorage = ItemStorage.new(db, maxi(drops.size(), 1))
	for item: String in drops:
		st.add(item, int(drops[item]))
	return _add_dynamic(CORPSE_PREFIX + kind, pos, yaw, corpse_despawn_s, "", st)


func dynamic_count() -> int:
	return d_handle.size()


func tick(delta: float) -> void:
	var k: int = _waiting.size() - 1
	while k >= 0:
		var i: int = _waiting[k]
		p_respawn[i] -= delta
		if p_respawn[i] <= 0.0:
			p_respawn[i] = 0.0
			_waiting.remove_at(k)
			point_changed.emit(i)
		k -= 1
	var j: int = d_life.size() - 1
	while j >= 0:
		d_life[j] -= delta
		if d_life[j] <= 0.0:
			_remove_dynamic(j)
		j -= 1


# --- Сохранение по чанкам ---------------------------------------------------

static func _chunk(out: Dictionary, k: String) -> Dictionary:
	if not out.has(k):
		out[k] = {}
	return out[k]


## out["cx,cz"]["l"] — изменённые точки: [номер в чанке, секунд до наполнения, содержимое или {}];
## out["cx,cz"]["c"] — мешки и туши: [вид, x, y, z, поворот, срок, владелец, содержимое].
func to_chunks(out: Dictionary) -> void:
	for i: int in p_pos.size():
		if p_storage[i] == null and p_respawn[i] <= 0.0:
			continue
		var ch: Dictionary = _chunk(out, ChunkGrid.key(grid.coord_of_index(p_chunk[i])))
		if not ch.has("l"):
			ch["l"] = []
		(ch["l"] as Array).append([p_local[i], snappedf(p_respawn[i], 0.1), p_storage[i].to_dict() if p_storage[i] != null else {}, p_rolls[i]])
	for j: int in d_pos.size():
		var p: Vector3 = d_pos[j]
		var ch2: Dictionary = _chunk(out, grid.key_of(p.x, p.z))
		if not ch2.has("c"):
			ch2["c"] = []
		(ch2["c"] as Array).append([d_kind[j], snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(d_yaw[j], 0.01),
			snappedf(d_life[j], 0.1), d_owner[j], d_storage[j].to_dict(), d_storage[j].size()])


## points_ok=false — расстановка точек другая (seed или данные): их состояние сбрасывается.
func from_chunks(chunks: Dictionary, points_ok: bool) -> void:
	for i: int in p_pos.size():
		p_storage[i] = null
		p_respawn[i] = 0.0
		p_rolls[i] = 0
	_waiting.clear()
	while not d_handle.is_empty():
		_remove_dynamic(d_handle.size() - 1)
	for k: Variant in chunks:
		if typeof(chunks[k]) != TYPE_DICTIONARY:
			continue
		var ch: Dictionary = chunks[k]
		var c: Vector2i = ChunkGrid.parse_key(String(k))
		var ci: int = grid.index_of_coord(c) if grid.is_inside(c) else -1
		if points_ok and ci >= 0 and chunk_first.has(ci) and typeof(ch.get("l")) == TYPE_ARRAY:
			for e: Variant in ch["l"]:
				if typeof(e) != TYPE_ARRAY or (e as Array).size() < 3:
					continue
				var local: int = int(e[0])
				if local < 0 or local >= int(chunk_count[ci]):
					continue
				var i: int = int(chunk_first[ci]) + local
				p_respawn[i] = maxf(float(e[1]), 0.0)
				p_rolls[i] = int(e[3]) if (e as Array).size() > 3 else 0
				if p_respawn[i] > 0.0:
					_waiting.append(i)
				elif typeof(e[2]) == TYPE_DICTIONARY and not (e[2] as Dictionary).is_empty():
					var st: ItemStorage = ItemStorage.new(db, JsonData.get_int(types[p_type[i]], "slots", 6))
					st.from_dict(e[2])
					p_storage[i] = st
				point_changed.emit(i)
		if typeof(ch.get("c")) == TYPE_ARRAY:
			for e2: Variant in ch["c"]:
				if typeof(e2) != TYPE_ARRAY or (e2 as Array).size() < 8 or typeof(e2[7]) != TYPE_DICTIONARY:
					continue
				var a: Array = e2
				var size: int = int(a[8]) if a.size() > 8 else 34
				var st2: ItemStorage = ItemStorage.new(db, clampi(size, 1, 64))
				st2.from_dict(a[7])
				if st2.is_all_empty():
					continue
				_add_dynamic(String(a[0]), Vector3(float(a[1]), float(a[2]), float(a[3])), float(a[4]), maxf(float(a[5]), 1.0), String(a[6]), st2)
