class_name TestTerrain
extends Node3D
## Тестовый ландшафт этапа 0: рельеф из шума по seed, трава и деревья через MultiMesh.
## Тяжёлые расчёты (высоты, нормали, расстановка) идут в WorkerThreadPool,
## в главном потоке только создание ресурсов из готовых массивов.
## Настоящие чанки и биомы — этап 3.

signal built

const CONFIG_PATH: String = "res://data/balance/test_terrain.json"

var terrain_math: TerrainMath
var is_built: bool = false

var _cfg: Dictionary = {}
var _task_id: int = -1
var _result: Dictionary = {}
var _grass_cells: Array[MultiMeshInstance3D] = []
var _tree_nodes: Array[MultiMeshInstance3D] = []
var _grass_density: float = 1.0
var _draw_distance: float = 200.0


func _ready() -> void:
	_cfg = JsonData.load_dict(CONFIG_PATH)
	terrain_math = TerrainMath.from_config(_cfg)
	_task_id = WorkerThreadPool.add_task(_generate, false, "test_terrain_generate")


func _process(_delta: float) -> void:
	if _task_id == -1:
		return
	if not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_build_nodes()
	_result.clear()
	set_process(false)
	is_built = true
	built.emit()


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func height_at(x: float, z: float) -> float:
	return terrain_math.height_at(x, z)


func set_grass_density(density: float) -> void:
	_grass_density = clampf(density, 0.0, 1.0)
	for mmi: MultiMeshInstance3D in _grass_cells:
		var mm: MultiMesh = mmi.multimesh
		mm.visible_instance_count = int(round(mm.instance_count * _grass_density))
		mmi.visible = mm.visible_instance_count > 0


func set_draw_distance(distance: float) -> void:
	_draw_distance = distance
	var grass_max: float = JsonData.get_float(_cfg, "grass_max_distance_m", 60.0)
	for mmi: MultiMeshInstance3D in _grass_cells:
		mmi.visibility_range_end = minf(grass_max, distance)
	for mmi: MultiMeshInstance3D in _tree_nodes:
		mmi.visibility_range_end = distance


## Выполняется в рабочем потоке. Только чистые вычисления, без доступа к дереву сцены.
func _generate() -> void:
	var size: float = JsonData.get_float(_cfg, "size_m", 256.0)
	var res: int = JsonData.get_int(_cfg, "resolution", 129)
	var heights: PackedFloat32Array = terrain_math.build_heights(size, res)
	var step: float = size / float(res - 1)
	var half: float = size * 0.5

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	verts.resize(res * res)
	normals.resize(res * res)
	colors.resize(res * res)
	var c_grass: Color = Color(0.36, 0.52, 0.27)
	var c_dry: Color = Color(0.55, 0.56, 0.33)
	var c_rock: Color = Color(0.47, 0.46, 0.44)
	for zi: int in res:
		for xi: int in res:
			var i: int = zi * res + xi
			var h: float = heights[i]
			var hl: float = heights[zi * res + maxi(xi - 1, 0)]
			var hr: float = heights[zi * res + mini(xi + 1, res - 1)]
			var hd: float = heights[maxi(zi - 1, 0) * res + xi]
			var hu: float = heights[mini(zi + 1, res - 1) * res + xi]
			var n: Vector3 = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			verts[i] = Vector3(-half + xi * step, h, -half + zi * step)
			normals[i] = n
			var slope: float = 1.0 - n.y
			var col: Color = c_grass.lerp(c_dry, clampf(h / 14.0, 0.0, 1.0))
			colors[i] = col.lerp(c_rock, clampf(slope * 6.0, 0.0, 1.0))

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

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = terrain_math.seed_value
	var flat_r: float = terrain_math.flat_radius
	var margin: float = 4.0

	# Трава: transforms по ячейкам сетки, чтобы работал отсев по видимости.
	var cells: int = JsonData.get_int(_cfg, "grass_cells_per_side", 4)
	var total_tufts: int = JsonData.get_int(_cfg, "grass_tufts_at_full_density", 6000)
	var per_cell: int = maxi(total_tufts / (cells * cells), 1)
	var cell_size: float = size / float(cells)
	var grass_buffers: Array[PackedFloat32Array] = []
	for cz: int in cells:
		for cx: int in cells:
			var buf: PackedFloat32Array = PackedFloat32Array()
			buf.resize(per_cell * 12)
			for t: int in per_cell:
				var x: float = -half + (cx + rng.randf()) * cell_size
				var z: float = -half + (cz + rng.randf()) * cell_size
				x = clampf(x, -half + 1.0, half - 1.0)
				z = clampf(z, -half + 1.0, half - 1.0)
				var y: float = terrain_math.height_at(x, z)
				var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
				_write_transform(buf, t, basis, Vector3(x, y, z))
			grass_buffers.append(buf)

	var tree_count: int = JsonData.get_int(_cfg, "tree_count", 200)
	var tree_buf: PackedFloat32Array = PackedFloat32Array()
	tree_buf.resize(tree_count * 12)
	var placed: int = 0
	var attempts: int = 0
	while placed < tree_count and attempts < tree_count * 10:
		attempts += 1
		var x: float = rng.randf_range(-half + margin, half - margin)
		var z: float = rng.randf_range(-half + margin, half - margin)
		if Vector2(x, z).length() < flat_r * 1.5:
			continue
		var y: float = terrain_math.height_at(x, z)
		var slope_h: float = absf(terrain_math.height_at(x + 1.0, z) - y) + absf(terrain_math.height_at(x, z + 1.0) - y)
		if slope_h > 0.9:
			continue
		var s: float = rng.randf_range(0.8, 1.4)
		var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s))
		_write_transform(tree_buf, placed, basis, Vector3(x, y - 0.2, z))
		placed += 1
	tree_buf.resize(placed * 12)

	var rock_count: int = JsonData.get_int(_cfg, "rock_count", 50)
	var rock_buf: PackedFloat32Array = PackedFloat32Array()
	rock_buf.resize(rock_count * 12)
	for r: int in rock_count:
		var x: float = rng.randf_range(-half + margin, half - margin)
		var z: float = rng.randf_range(-half + margin, half - margin)
		if Vector2(x, z).length() < flat_r:
			x += flat_r * 2.0
		var y: float = terrain_math.height_at(x, z)
		var basis: Basis = Basis.from_euler(Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5))
		basis = basis.scaled(Vector3(rng.randf_range(0.6, 1.8), rng.randf_range(0.4, 1.0), rng.randf_range(0.6, 1.8)))
		_write_transform(rock_buf, r, basis, Vector3(x, y, z))

	_result = {
		"res": res,
		"step": step,
		"heights": heights,
		"verts": verts,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"grass": grass_buffers,
		"trees": tree_buf,
		"rocks": rock_buf,
	}


## Формат буфера MultiMesh (3D, без цветов): 12 float на экземпляр, строки базиса + origin.
static func _write_transform(buf: PackedFloat32Array, index: int, b: Basis, origin: Vector3) -> void:
	var o: int = index * 12
	buf[o + 0] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = origin.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = origin.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = origin.z


func _build_nodes() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _result["verts"]
	arrays[Mesh.ARRAY_NORMAL] = _result["normals"]
	arrays[Mesh.ARRAY_COLOR] = _result["colors"]
	arrays[Mesh.ARRAY_INDEX] = _result["indices"]
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ground_mat: StandardMaterial3D = StandardMaterial3D.new()
	ground_mat.vertex_color_use_as_albedo = true
	ground_mat.roughness = 1.0
	mesh.surface_set_material(0, ground_mat)

	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	add_child(ground)

	var res: int = _result["res"]
	var step: float = _result["step"]
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = res
	shape.map_depth = res
	shape.map_data = _result["heights"]
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "GroundBody"
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	# HeightMapShape3D строится с шагом 1 м и центром в нуле; масштабируем под шаг сетки.
	col.scale = Vector3(step, 1.0, step)
	body.add_child(col)
	add_child(body)

	var grass_mesh: ArrayMesh = _make_grass_mesh()
	for buf: PackedFloat32Array in _result["grass"]:
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = grass_mesh
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "Grass"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_grass_cells.append(mmi)

	_tree_nodes.append(_make_multimesh("Trees", _make_tree_mesh(), _result["trees"]))
	_tree_nodes.append(_make_multimesh("Rocks", _make_rock_mesh(), _result["rocks"]))

	set_grass_density(_grass_density)
	set_draw_distance(_draw_distance)


func _make_multimesh(node_name: String, mesh: Mesh, buf: PackedFloat32Array) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = buf.size() / 12
	if mm.instance_count > 0:
		mm.buffer = buf
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


static func _flat_material(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


## Пучок травы: три вертикальных треугольника под 60°, цвет от корня к кончику.
static func _make_grass_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_col: Color = Color(0.22, 0.36, 0.17)
	var tip_col: Color = Color(0.52, 0.66, 0.33)
	for i: int in 3:
		var ang: float = i * PI / 3.0
		var dir: Vector3 = Vector3(cos(ang), 0.0, sin(ang)) * 0.25
		st.set_normal(Vector3.UP)
		st.set_color(root_col)
		st.add_vertex(-dir)
		st.set_normal(Vector3.UP)
		st.set_color(tip_col)
		st.add_vertex(Vector3(0.0, 0.55, 0.0))
		st.set_normal(Vector3.UP)
		st.set_color(root_col)
		st.add_vertex(dir)
	var mesh: ArrayMesh = st.commit()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Без освещения: обе стороны травинки одного цвета и дешевле для мобильного GPU.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	return mesh


## Дерево: ствол и крона-конус, основание в нуле. Одна сетка с двумя поверхностями = 2 draw call на все деревья.
static func _make_tree_mesh() -> ArrayMesh:
	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.22
	trunk.height = 2.4
	trunk.radial_segments = 6
	trunk.rings = 0
	trunk.cap_top = false
	trunk.cap_bottom = false
	var crown: CylinderMesh = CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 1.5
	crown.height = 4.0
	crown.radial_segments = 7
	crown.rings = 0
	crown.cap_top = false
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0)))
	st.commit(mesh)
	st.clear()
	st.append_from(crown, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.6, 0.0)))
	st.commit(mesh)
	mesh.surface_set_material(0, _flat_material(Color(0.36, 0.26, 0.18)))
	mesh.surface_set_material(1, _flat_material(Color(0.2, 0.38, 0.24)))
	return mesh


static func _make_rock_mesh() -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = 0.8
	m.height = 1.2
	m.radial_segments = 6
	m.rings = 3
	m.material = _flat_material(Color(0.5, 0.5, 0.52))
	return m
