class_name WorldStreamer
extends Node3D
## Мир этапа 3 в сцене: подгрузка чанков вокруг игрока.
## 1. При старте в рабочем потоке строится «раскладка» всего острова — чистые данные: ресурсные узлы
##    (ResourceField.generate_world) и точки лута (WorldContainers.generate_points). Это массивы на ~7 тыс.
##    записей; они нужны логике (и серверу этапа 4) целиком. Сигнал layout_ready.
## 2. Чанк 64 × 64 м подгружается, когда он ближе дальности прорисовки: высоты, нормали, цвета, трава
##    и буферы MultiMesh считаются в WorkerThreadPool (свой WorldGen на поток), а главный поток только
##    создаёт ресурсы и узлы — маленькими шагами, не дольше бюджета на кадр (budget_ms, по умолчанию 2 мс;
##    при загрузке, пока игрок не управляет персонажем, — loading_budget_ms).
## 3. Столкновения (рельеф HeightMapShape3D и цилиндры деревьев/камней) есть только у чанков в радиусе
##    collision_radius_chunks вокруг игрока. Чанки дальше дальности + запаса выгружаются.
## Узлы, точки лута и трава рисуются MultiMesh по чанкам (один draw call на тип в чанке) — замеры
## «до/после» в docs/PERFORMANCE.md (режим render_nodes_as = instances — узел на объект, только для замеров).

signal layout_ready
## Совместимость с этапами 0–2: то же, что layout_ready.
signal built

const CONFIG_PATH: String = "res://data/balance/world.json"

## Строка для отладочной панели (обновляется 4 раза в секунду).
static var debug_text: String = ""

var gen: WorldGen
var terrain_math: TerrainMath
var resource_field: ResourceField
var containers: WorldContainers
var water_level: float = 0.0
var half_size: float = 640.0
var is_built: bool = false

var _cfg: Dictionary = {}
var _stream: Dictionary = {}
var _layout_task: int = -1
var _layout_field: ResourceField
var _layout_containers: WorldContainers
var _chunks: Dictionary = {}
var _order: Array = []
var _focus: Vector3 = Vector3.ZERO
var _focus_set: bool = false
var _focus_chunk: Vector2i = Vector2i(-999, -999)
var _dirty: bool = true
var _gens: Array[WorldGen] = []
var _gen_busy: Array[bool] = []
var _running: int = 0
var _indices: PackedInt32Array = PackedInt32Array()
var _res: int = 33
var _step: float = 2.0
var _draw_distance: float = 200.0
var _grass_density: float = 1.0
var _grass_max: float = 60.0
var _budget_us: int = 2000
var _loading_budget_us: int = 8000
var _collision_r: int = 1
var _keep_margin: float = 48.0
var _batch: int = 16
var _as_instances: bool = false
var _shape_cache: Dictionary = {}
var _playing: bool = false
var _stats_t: float = 0.0
## Замеры главного потока: время подгрузки за кадр (мкс), худший кадр и худший шаг.
var frame_us: int = 0
var worst_frame_us: int = 0
var worst_step_us: int = 0
var steps_done: int = 0
var chunks_built: int = 0


## Состояние чанка: данные из рабочего потока и узлы сцены.
class Chunk:
	extends RefCounted
	var c: Vector2i
	var ci: int = 0
	## 0 — нет, 1 — считается в потоке, 2 — данные готовы, 3 — земля, 4 — узлы, 5 — всё (трава).
	var state: int = 0
	var task: int = -1
	var data: Dictionary = {}
	var node: Node3D
	var dist: float = 0.0
	var mmis: Array = []
	var node_inst: PackedInt32Array = PackedInt32Array()
	var inst_nodes: Array = []
	var loot_mmis: Array = []
	var loot_inst: PackedInt32Array = PackedInt32Array()
	var grass: MultiMeshInstance3D
	var body: StaticBody3D
	## 0 — нет, 1 — рельеф, 2 — рельеф и все цилиндры.
	var col_state: int = 0
	var col_next: int = 0
	var colliders: Array = []


func _ready() -> void:
	_cfg = JsonData.load_dict(CONFIG_PATH)
	gen = WorldGen.new(_cfg)
	terrain_math = gen
	water_level = gen.water_level
	half_size = gen.grid.half
	_stream = _cfg.get("stream", {})
	_res = maxi(JsonData.get_int(_cfg, "chunk_res", 33), 3)
	_step = gen.grid.chunk_m / float(_res - 1)
	_budget_us = int(JsonData.get_float(_stream, "budget_ms", 2.0) * 1000.0)
	_loading_budget_us = int(JsonData.get_float(_stream, "loading_budget_ms", 8.0) * 1000.0)
	_collision_r = JsonData.get_int(_stream, "collision_radius_chunks", 1)
	_keep_margin = JsonData.get_float(_stream, "keep_margin_m", 48.0)
	_batch = maxi(JsonData.get_int(_stream, "collider_batch", 16), 1)
	_grass_max = JsonData.get_float(_cfg.get("grass", {}), "max_distance_m", 60.0)
	_as_instances = String(_cfg.get("render_nodes_as", "multimesh")) == "instances"
	var tasks: int = maxi(JsonData.get_int(_stream, "max_tasks", 2), 1)
	for i: int in tasks:
		_gens.append(gen.clone())
		_gen_busy.append(false)
	_indices = _make_indices(_res)
	add_child(WorldMeshes.make_water(gen.grid.size_m + 2400.0, water_level))
	# Раскладка мира (узлы и точки лута) — в рабочем потоке.
	_layout_containers = WorldContainers.new()
	_layout_containers.configure(JsonData.load_dict(WorldContainers.DEFAULT_PATH), null, null)
	_layout_task = WorkerThreadPool.add_task(_layout_job.bind(gen.clone(), JsonData.load_dict(ResourceField.DEFAULT_PATH), JsonData.load_dict(WorldContainers.DEFAULT_PATH)), false, "world_layout")


func _exit_tree() -> void:
	if _layout_task != -1:
		WorkerThreadPool.wait_for_task_completion(_layout_task)
		_layout_task = -1
	for k: Variant in _chunks:
		var ch: Chunk = _chunks[k]
		if ch.task != -1:
			WorkerThreadPool.wait_for_task_completion(ch.task)
			ch.task = -1


func _layout_job(g: WorldGen, res_cfg: Dictionary, loot_cfg: Dictionary) -> void:
	_layout_field = ResourceField.generate_world(res_cfg, g)
	_layout_containers.generate_points(loot_cfg, g)


func height_at(x: float, z: float) -> float:
	return gen.height_at(x, z)


## Центр подгрузки (позиция игрока). Дёшево: пересчёт набора чанков — только при смене чанка.
func set_focus(pos: Vector3) -> void:
	_focus = pos
	_focus_set = true
	var c: Vector2i = gen.grid.coord_of(pos.x, pos.z)
	if c != _focus_chunk:
		_focus_chunk = c
		_dirty = true


## Игрок управляет персонажем: бюджет подгрузки — budget_ms, иначе (загрузка, экран гибели) — loading_budget_ms.
func set_playing(on: bool) -> void:
	_playing = on


func set_draw_distance(distance: float) -> void:
	_draw_distance = distance
	_dirty = true
	for k: Variant in _chunks:
		_apply_ranges(_chunks[k])


func set_grass_density(density: float) -> void:
	_grass_density = clampf(density, 0.0, 1.0)
	for k: Variant in _chunks:
		var ch: Chunk = _chunks[k]
		if ch.grass != null:
			_apply_grass_density(ch.grass)


func _apply_grass_density(mmi: MultiMeshInstance3D) -> void:
	var mm: MultiMesh = mmi.multimesh
	mm.visible_instance_count = int(round(mm.instance_count * _grass_density))
	mmi.visible = mm.visible_instance_count > 0


func _apply_ranges(ch: Chunk) -> void:
	for m: Variant in ch.mmis:
		if m != null:
			(m as GeometryInstance3D).visibility_range_end = _draw_distance
	for m2: Variant in ch.loot_mmis:
		if m2 != null:
			(m2 as GeometryInstance3D).visibility_range_end = _draw_distance
	if ch.grass != null:
		ch.grass.visibility_range_end = minf(_grass_max, _draw_distance)


## Есть ли под точкой рельеф со столкновениями (можно ставить персонажа).
func is_collision_ready(pos: Vector3) -> bool:
	var c: Vector2i = gen.grid.coord_of(pos.x, pos.z)
	var ch: Chunk = _chunks.get(c)
	return ch != null and ch.col_state >= 1


## Готовы ли и цилиндры деревьев/камней чанка под точкой.
func colliders_ready(pos: Vector3) -> bool:
	var ch: Chunk = _chunks.get(gen.grid.coord_of(pos.x, pos.z))
	return ch != null and ch.col_state >= 2


func loaded_count() -> int:
	var n: int = 0
	for k: Variant in _chunks:
		if (_chunks[k] as Chunk).state >= 3:
			n += 1
	return n


func pending_count() -> int:
	var n: int = 0
	for k: Variant in _chunks:
		if (_chunks[k] as Chunk).state < 5:
			n += 1
	return n


## Число включённых цилиндров деревьев и камней (отладка, тесты).
func active_collider_count() -> int:
	var n: int = 0
	for k: Variant in _chunks:
		for col: Variant in (_chunks[k] as Chunk).colliders:
			if col != null and not (col as CollisionShape3D).disabled:
				n += 1
	return n


func reset_stats() -> void:
	worst_frame_us = 0
	worst_step_us = 0


func _process(delta: float) -> void:
	if _layout_task != -1:
		if not WorkerThreadPool.is_task_completed(_layout_task):
			return
		WorkerThreadPool.wait_for_task_completion(_layout_task)
		_layout_task = -1
		resource_field = _layout_field
		containers = _layout_containers
		_layout_field = null
		_layout_containers = null
		resource_field.node_changed.connect(_on_node_changed)
		containers.point_changed.connect(_on_point_changed)
		is_built = true
		layout_ready.emit()
		built.emit()
		return
	if not is_built or not _focus_set:
		return
	if _dirty:
		_dirty = false
		_refresh_set()
	_collect_tasks()
	_start_tasks()
	_build_steps()
	_stats_t -= delta
	if _stats_t <= 0.0:
		_stats_t = 0.25
		debug_text = TranslationServer.translate("DEBUG_WORLD") % [loaded_count(), pending_count(), frame_us / 1000.0, worst_frame_us / 1000.0,
			TranslationServer.translate("BIOME_" + WorldGen.biome_id(gen.biome_at(_focus.x, _focus.z)).to_upper())]


## Какие чанки нужны: ближе дальности прорисовки (порядок — от ближнего). Дальние выгружаются.
func _refresh_set() -> void:
	var g: ChunkGrid = gen.grid
	var r: int = int(ceil(_draw_distance / g.chunk_m)) + 1
	var fc: Vector2i = _focus_chunk
	for dz: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var c: Vector2i = Vector2i(fc.x + dx, fc.y + dz)
			if not g.is_inside(c) or _chunks.has(c):
				continue
			if g.distance_to(c, _focus.x, _focus.z) > _draw_distance:
				continue
			var ch: Chunk = Chunk.new()
			ch.c = c
			ch.ci = g.index_of_coord(c)
			_chunks[c] = ch
	var drop: Array = []
	for k: Variant in _chunks:
		var ch2: Chunk = _chunks[k]
		ch2.dist = g.distance_to(ch2.c, _focus.x, _focus.z)
		if ch2.dist > _draw_distance + _keep_margin and ch2.task == -1:
			drop.append(k)
		elif ch2.body != null and _cheb(ch2.c) > _collision_r + 1:
			_free_collision(ch2)
	for k2: Variant in drop:
		_unload(_chunks[k2])
		_chunks.erase(k2)
	_order = _chunks.values()
	_order.sort_custom(func(a: Chunk, b: Chunk) -> bool: return a.dist < b.dist)


func _cheb(c: Vector2i) -> int:
	return maxi(absi(c.x - _focus_chunk.x), absi(c.y - _focus_chunk.y))


func _unload(ch: Chunk) -> void:
	if ch.node != null:
		ch.node.queue_free()
	ch.node = null
	ch.body = null
	ch.colliders.clear()
	ch.mmis.clear()
	ch.loot_mmis.clear()
	ch.inst_nodes.clear()
	ch.grass = null
	ch.data.clear()
	ch.state = 0


func _free_collision(ch: Chunk) -> void:
	if ch.body != null:
		ch.body.queue_free()
	ch.body = null
	ch.colliders.clear()
	ch.col_state = 0
	ch.col_next = 0


func _start_tasks() -> void:
	for ch: Chunk in _order:
		if _running >= _gens.size():
			return
		if ch.state != 0 or not _chunks.has(ch.c):
			continue
		var slot: int = _gen_busy.find(false)
		if slot < 0:
			return
		_gen_busy[slot] = true
		_running += 1
		ch.state = 1
		ch.task = WorkerThreadPool.add_task(_chunk_job.bind(ch, slot), false, "world_chunk")


func _collect_tasks() -> void:
	for ch: Chunk in _order:
		if ch.state != 1 or ch.task == -1 or not WorkerThreadPool.is_task_completed(ch.task):
			continue
		WorkerThreadPool.wait_for_task_completion(ch.task)
		ch.task = -1
		_gen_busy[int(ch.data.get("slot", 0))] = false
		_running -= 1
		ch.state = 2


## Рабочий поток: только чистые вычисления над массивами, без дерева сцены.
func _chunk_job(ch: Chunk, slot: int) -> void:
	ch.data = ChunkBuilder.build(_gens[slot], ch.c, _res, _cfg, resource_field, containers)
	ch.data["slot"] = slot


func _budget() -> int:
	return _budget_us if _playing else _loading_budget_us


## Шаги сборки на главном потоке, пока не кончился бюджет кадра (первый шаг выполняется всегда).
func _build_steps() -> void:
	var t0: int = Time.get_ticks_usec()
	var budget: int = _budget()
	var did: bool = false
	for ch: Chunk in _order:
		while true:
			var now: int = Time.get_ticks_usec()
			if did and now - t0 >= budget:
				_end_frame(t0)
				return
			if not _do_step(ch):
				break
			did = true
			var spent: int = Time.get_ticks_usec() - now
			worst_step_us = maxi(worst_step_us, spent)
			steps_done += 1
	_end_frame(t0)


func _end_frame(t0: int) -> void:
	frame_us = Time.get_ticks_usec() - t0
	worst_frame_us = maxi(worst_frame_us, frame_us)


## Один шаг для чанка; false — для него сейчас нечего делать.
func _do_step(ch: Chunk) -> bool:
	if ch.state < 2:
		return false
	var near: bool = _cheb(ch.c) <= _collision_r
	# Сначала столкновения рельефа ближних чанков (под игроком), потом картинка.
	if near and ch.col_state == 0:
		_step_ground_collision(ch)
		return true
	match ch.state:
		2:
			_step_ground(ch)
			return true
		3:
			_step_nodes(ch)
			return true
		4:
			_step_grass(ch)
			return true
	if near and ch.col_state == 1:
		_step_colliders(ch)
		return true
	return false


func _ensure_node(ch: Chunk) -> void:
	if ch.node != null:
		return
	var o: Vector2 = gen.grid.origin_of(ch.c)
	ch.node = Node3D.new()
	ch.node.name = "Chunk_%d_%d" % [ch.c.x, ch.c.y]
	ch.node.position = Vector3(o.x, 0.0, o.y)
	add_child(ch.node)


func _step_ground(ch: Chunk) -> void:
	_ensure_node(ch)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ch.data["verts"]
	arrays[Mesh.ARRAY_NORMAL] = ch.data["normals"]
	arrays[Mesh.ARRAY_COLOR] = ch.data["colors"]
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, WorldMeshes.vertex_material())
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.node.add_child(mi)
	ch.state = 3
	chunks_built += 1


func _step_nodes(ch: Chunk) -> void:
	_ensure_node(ch)
	var f: ResourceField = resource_field
	var rng_v: Vector2i = f.chunk_range(ch.ci)
	ch.node_inst = ch.data["node_inst"]
	var bufs: Array = ch.data["node_bufs"]
	ch.mmis.resize(bufs.size())
	if _as_instances:
		ch.inst_nodes.resize(rng_v.y)
		for local: int in rng_v.y:
			var i: int = rng_v.x + local
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = WorldMeshes.get_mesh(String(f.types[f.type_index[i]].get("id", "")))
			mi.position = f.positions[i] - ch.node.position
			mi.rotation.y = f.yaws[i]
			mi.scale = Vector3.ONE * f.scales[i]
			mi.visibility_range_end = _draw_distance
			ch.node.add_child(mi)
			ch.inst_nodes[local] = mi
	else:
		for t: int in bufs.size():
			var buf: PackedFloat32Array = bufs[t]
			if buf.is_empty():
				continue
			ch.mmis[t] = _make_mmi(WorldMeshes.get_mesh(String(f.types[t].get("id", ""))), buf, "Nodes_%d" % t)
			ch.node.add_child(ch.mmis[t])
	for local2: int in rng_v.y:
		if not f.is_available(rng_v.x + local2):
			_update_node(ch, rng_v.x + local2)
	# Точки лута.
	var lbufs: Array = ch.data["loot_bufs"]
	ch.loot_inst = ch.data["loot_inst"]
	ch.loot_mmis.resize(lbufs.size())
	for t2: int in lbufs.size():
		var lb: PackedFloat32Array = lbufs[t2]
		if lb.is_empty():
			continue
		ch.loot_mmis[t2] = _make_mmi(WorldMeshes.get_mesh(containers.point_type_id_by_type(t2)), lb, "Loot_%d" % t2)
		ch.node.add_child(ch.loot_mmis[t2])
	if containers.chunk_first.has(ch.ci):
		var first: int = containers.chunk_first[ch.ci]
		for l: int in int(containers.chunk_count[ch.ci]):
			if not containers.is_point_available(first + l):
				_update_point(ch, first + l)
	ch.state = 4


func _make_mmi(mesh: Mesh, buf: PackedFloat32Array, n: String) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = buf.size() / 12
	mm.buffer = buf
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.visibility_range_end = _draw_distance
	return mmi


func _step_grass(ch: Chunk) -> void:
	var buf: PackedFloat32Array = ch.data["grass"]
	if not buf.is_empty():
		var mmi: MultiMeshInstance3D = _make_mmi(WorldMeshes.get_mesh("grass"), buf, "Grass")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = minf(_grass_max, _draw_distance)
		ch.node.add_child(mmi)
		ch.grass = mmi
		_apply_grass_density(mmi)
	ch.state = 5


func _step_ground_collision(ch: Chunk) -> void:
	_ensure_node(ch)
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = _res
	shape.map_depth = _res
	shape.map_data = ch.data["heights"]
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	# HeightMapShape3D строится с шагом 1 м и центром в нуле; масштабируем под шаг сетки чанка.
	col.scale = Vector3(_step, 1.0, _step)
	col.position = Vector3(gen.grid.chunk_m * 0.5, 0.0, gen.grid.chunk_m * 0.5)
	body.add_child(col)
	ch.node.add_child(body)
	ch.body = body
	ch.col_state = 1
	ch.col_next = 0
	ch.colliders.resize(resource_field.chunk_range(ch.ci).y)


## Цилиндры деревьев и камней — пачками по collider_batch; формы общие для близких размеров.
func _step_colliders(ch: Chunk) -> void:
	var f: ResourceField = resource_field
	var rr: Vector2i = f.chunk_range(ch.ci)
	var done: int = 0
	while ch.col_next < rr.y and done < _batch:
		var i: int = rr.x + ch.col_next
		var r: float = f.collider_radius(i)
		if r > 0.0:
			var h: float = f.collider_height(i)
			var key: Vector2i = Vector2i(int(round(r * 20.0)), int(round(h * 10.0)))
			var shape: CylinderShape3D = _shape_cache.get(key)
			if shape == null:
				shape = CylinderShape3D.new()
				shape.radius = key.x / 20.0
				shape.height = key.y / 10.0
				_shape_cache[key] = shape
			var col: CollisionShape3D = CollisionShape3D.new()
			col.shape = shape
			col.position = f.positions[i] - ch.node.position + Vector3(0.0, shape.height * 0.5, 0.0)
			col.disabled = not f.is_available(i)
			ch.body.add_child(col)
			ch.colliders[ch.col_next] = col
			done += 1
		ch.col_next += 1
	if ch.col_next >= rr.y:
		ch.col_state = 2


func _on_node_changed(i: int) -> void:
	var ch: Chunk = _chunks.get(gen.grid.coord_of_index(resource_field.node_chunk[i]))
	if ch == null or ch.state < 4:
		return
	_update_node(ch, i)


func _update_node(ch: Chunk, i: int) -> void:
	var f: ResourceField = resource_field
	var local: int = f.node_local[i]
	var avail: bool = f.is_available(i)
	if _as_instances:
		if local < ch.inst_nodes.size() and ch.inst_nodes[local] != null:
			(ch.inst_nodes[local] as Node3D).visible = avail
	else:
		var mmi: MultiMeshInstance3D = ch.mmis[f.type_index[i]]
		if mmi != null:
			var xf: Transform3D
			if avail:
				var s: float = f.scales[i]
				xf = Transform3D(Basis(Vector3.UP, f.yaws[i]).scaled(Vector3(s, s, s)), f.positions[i] - ch.node.position)
			else:
				xf = Transform3D(Basis.from_scale(Vector3.ZERO), f.positions[i] - ch.node.position)
			mmi.multimesh.set_instance_transform(ch.node_inst[local], xf)
	if local < ch.colliders.size() and ch.colliders[local] != null:
		# Отложенно: событие может прийти во время шага физики.
		(ch.colliders[local] as CollisionShape3D).set_deferred(&"disabled", not avail)


func _on_point_changed(i: int) -> void:
	var ch: Chunk = _chunks.get(gen.grid.coord_of_index(containers.p_chunk[i]))
	if ch == null or ch.state < 4:
		return
	_update_point(ch, i)


func _update_point(ch: Chunk, i: int) -> void:
	var mmi: MultiMeshInstance3D = ch.loot_mmis[containers.p_type[i]] if containers.p_type[i] < ch.loot_mmis.size() else null
	if mmi == null:
		return
	var local: int = containers.p_local[i]
	var p: Vector3 = containers.p_pos[i] - ch.node.position
	var b: Basis = Basis(Vector3.UP, containers.p_yaw[i]) if containers.is_point_available(i) else Basis.from_scale(Vector3.ZERO)
	mmi.multimesh.set_instance_transform(ch.loot_inst[local], Transform3D(b, p))


static func _make_indices(res: int) -> PackedInt32Array:
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize((res - 1) * (res - 1) * 6)
	var k: int = 0
	for zi: int in res - 1:
		for xi: int in res - 1:
			var a: int = zi * res + xi
			var b: int = a + 1
			var c: int = a + res
			var d: int = c + 1
			# Godot считает лицевой стороной обход по часовой стрелке.
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6
	return indices
