class_name BuildingView
extends Node3D
## Отрисовка и столкновения построек (BuildingGrid). Слушает сигналы логики, сама логики не содержит.
## Детали одного типа и материала рисуются одним MultiMesh (до 6 × 3 групп = 1 draw call на группу),
## цвет экземпляра темнеет по мере износа. Двери — отдельные узлы (открываются поворотом).
## Столкновения: на каждую деталь один StaticBody3D с простыми коробками (создаётся по событию,
## не в кадре). Модели — процедурные low-poly; начало координат моделей:
##   фундамент — центр верхней грани (масштаб по Y = глубина), перекрытие — центр верхней грани,
##   стена/проём — середина нижнего края, вдоль +X; крыша и лестница — центр клетки на уровне пола,
##   подъём в сторону −Z (поворот по направлению rot); дверь — нижний край петли, полотно вдоль +X.

const MATERIAL_COLORS: Array[Color] = [Color(0.66, 0.46, 0.28), Color(0.72, 0.7, 0.66), Color(0.5, 0.58, 0.66)]
const WORN_TINT: Color = Color(0.5, 0.45, 0.42)
const DOOR_SWING_S: float = 0.25

var _grid: BuildingGrid
var _defs: BuildingDefs
var _meshes: Dictionary = {}
var _materials: Array[StandardMaterial3D] = []
## "тип:материал" -> MultiMeshInstance3D
var _groups: Dictionary = {}
var _dirty: Dictionary = {}
var _bodies: Dictionary = {}
var _doors: Dictionary = {}
var _shapes: Dictionary = {}
var _draw_distance: float = 200.0


func bind(grid: BuildingGrid) -> void:
	_grid = grid
	_defs = grid.defs
	for m: int in MATERIAL_COLORS.size():
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = MATERIAL_COLORS[m]
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9 if m < 2 else 0.55
		mat.metallic = 0.0 if m < 2 else 0.15
		_materials.append(mat)
	grid.piece_added.connect(_on_added)
	grid.piece_changed.connect(_on_changed)
	grid.piece_removed.connect(_on_removed)
	grid.cleared.connect(_on_cleared)
	for id: int in grid.capacity():
		if grid.is_alive(id):
			_on_added(id)


func set_draw_distance(distance: float) -> void:
	_draw_distance = distance
	for k: String in _groups:
		(_groups[k] as MultiMeshInstance3D).visibility_range_end = distance


## Модель детали (для призрака постройки).
func mesh_for(type: String) -> Mesh:
	if not _meshes.has(type):
		_meshes[type] = _make_mesh(type)
	return _meshes[type]


func _group_key(type: String, mat: int) -> String:
	return "%s:%d" % [type, mat]


func _on_added(id: int) -> void:
	if _grid.is_door(id):
		_add_door(id)
	else:
		_mark(_group_key(_grid.p_type[id], _grid.p_mat[id]))
		_add_body(id)


func _on_changed(id: int) -> void:
	if _doors.has(id):
		_update_door(id, true)
		return
	# Материал мог смениться — перестраиваем все группы этого типа (их не больше трёх).
	for m: int in _defs.material_order.size():
		_mark(_group_key(_grid.p_type[id], m))


func _on_removed(id: int) -> void:
	if _doors.has(id):
		(_doors[id] as Node3D).queue_free()
		_doors.erase(id)
	if _bodies.has(id):
		(_bodies[id] as Node3D).queue_free()
		_bodies.erase(id)
	for k: String in _groups:
		_dirty[k] = true
	set_process(true)


func _on_cleared() -> void:
	for id: int in _doors:
		(_doors[id] as Node3D).queue_free()
	for id: int in _bodies:
		(_bodies[id] as Node3D).queue_free()
	_doors.clear()
	_bodies.clear()
	for k: String in _groups:
		_dirty[k] = true
	set_process(true)


func _mark(key: String) -> void:
	_dirty[key] = true
	set_process(true)


## Перестройка изменившихся групп — раз в кадр после событий, не каждый кадр.
func _process(_delta: float) -> void:
	if _dirty.is_empty():
		set_process(false)
		return
	for key: String in _dirty:
		_rebuild_group(key)
	_dirty.clear()
	set_process(false)


func _rebuild_group(key: String) -> void:
	var parts: PackedStringArray = key.split(":")
	var type: String = parts[0]
	var mat: int = int(parts[1])
	var n: int = 0
	for id: int in _grid.capacity():
		if _grid.is_alive(id) and _grid.p_type[id] == type and _grid.p_mat[id] == mat and not _grid.is_door(id):
			n += 1
	var mmi: MultiMeshInstance3D = _groups.get(key)
	if mmi == null:
		if n == 0:
			return
		mmi = MultiMeshInstance3D.new()
		mmi.name = "Pieces_%s_%d" % [type, mat]
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh_for(type)
		mmi.multimesh = mm
		mmi.material_override = _materials[mat]
		mmi.visibility_range_end = _draw_distance
		add_child(mmi)
		_groups[key] = mmi
	var mmesh: MultiMesh = mmi.multimesh
	mmesh.instance_count = n
	mmi.visible = n > 0
	var k: int = 0
	for id: int in _grid.capacity():
		if not _grid.is_alive(id) or _grid.p_type[id] != type or _grid.p_mat[id] != mat or _grid.is_door(id):
			continue
		mmesh.set_instance_transform(k, _grid.transform_of(type, _grid.p_key[id], _grid.p_rot[id], _grid.p_depth[id]))
		mmesh.set_instance_color(k, _wear_color(id))
		k += 1


func _wear_color(id: int) -> Color:
	var f: float = clampf(_grid.p_hp[id] / _grid.max_hp(id), 0.0, 1.0)
	return WORN_TINT.lerp(Color.WHITE, f)


# --- Двери ------------------------------------------------------------------

func _add_door(id: int) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Door_%d" % id
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Panel"
	mi.mesh = mesh_for("door")
	root.add_child(mi)
	var lock: MeshInstance3D = MeshInstance3D.new()
	lock.name = "Lock"
	lock.mesh = mesh_for("lock")
	root.add_child(lock)
	var body: StaticBody3D = StaticBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = _box_shape("door", Vector3(_defs.doorway_w - 0.04, _defs.doorway_h - 0.02, 0.08))
	col.position = Vector3(_defs.doorway_w * 0.5, _defs.doorway_h * 0.5, 0.0)
	body.add_child(col)
	root.add_child(body)
	add_child(root)
	_doors[id] = root
	_update_door(id, false)


func _update_door(id: int, animate: bool) -> void:
	var root: Node3D = _doors[id]
	var mat: int = _grid.p_mat[id]
	(root.get_node("Panel") as MeshInstance3D).material_override = _materials[mat]
	(root.get_node("Lock") as MeshInstance3D).visible = _grid.has_lock(id)
	var xf: Transform3D = _grid.door_transform(_grid.p_key[id], _grid.p_rot[id], _grid.is_open(id))
	root.position = xf.origin
	var target_yaw: float = xf.basis.get_euler().y
	if animate and is_inside_tree():
		var tw: Tween = root.create_tween()
		var from: float = root.rotation.y
		# Кратчайший поворот.
		var to: float = from + wrapf(target_yaw - from, -PI, PI)
		tw.tween_property(root, "rotation:y", to, DOOR_SWING_S)
	else:
		root.rotation = Vector3(0.0, target_yaw, 0.0)


# --- Столкновения -----------------------------------------------------------

func _box_shape(key: String, size: Vector3) -> BoxShape3D:
	if _shapes.has(key):
		return _shapes[key]
	var b: BoxShape3D = BoxShape3D.new()
	b.size = size
	_shapes[key] = b
	return b


func _add_shape(body: StaticBody3D, shape: Shape3D, xf: Transform3D) -> void:
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	col.transform = xf
	body.add_child(col)


func _add_body(id: int) -> void:
	var type: String = _grid.p_type[id]
	var key: Vector4i = _grid.p_key[id]
	var s: float = _defs.grid
	var h: float = _defs.wall_h
	var t: float = _defs.wall_t
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body_%d" % id
	var xf: Transform3D = _grid.transform_of(type, key, _grid.p_rot[id], _grid.p_depth[id])
	match type:
		"foundation":
			# Своя коробка: глубина у каждого фундамента своя. Тело без масштаба.
			var d: float = _grid.p_depth[id]
			var b: BoxShape3D = BoxShape3D.new()
			b.size = Vector3(s, d, s)
			_add_shape(body, b, Transform3D(Basis.IDENTITY, Vector3(0.0, -d * 0.5, 0.0)))
			xf.basis = Basis.IDENTITY
		"floor":
			_add_shape(body, _box_shape("floor", Vector3(s, _defs.floor_t, s)), Transform3D(Basis.IDENTITY, Vector3(0.0, -_defs.floor_t * 0.5, 0.0)))
		"wall":
			_add_shape(body, _box_shape("wall", Vector3(s, h, t)), Transform3D(Basis.IDENTITY, Vector3(0.0, h * 0.5, 0.0)))
		"doorway":
			var side_w: float = (s - _defs.doorway_w) * 0.5
			var post: BoxShape3D = _box_shape("post", Vector3(side_w, h, t))
			_add_shape(body, post, Transform3D(Basis.IDENTITY, Vector3(-s * 0.5 + side_w * 0.5, h * 0.5, 0.0)))
			_add_shape(body, post, Transform3D(Basis.IDENTITY, Vector3(s * 0.5 - side_w * 0.5, h * 0.5, 0.0)))
			var lintel_h: float = h - _defs.doorway_h
			_add_shape(body, _box_shape("lintel", Vector3(_defs.doorway_w, lintel_h, t)), Transform3D(Basis.IDENTITY, Vector3(0.0, _defs.doorway_h + lintel_h * 0.5, 0.0)))
		"roof":
			var ang: float = atan2(_defs.roof_rise, s)
			var len: float = sqrt(s * s + _defs.roof_rise * _defs.roof_rise)
			_add_shape(body, _box_shape("roof", Vector3(s, _defs.floor_t, len)), Transform3D(Basis(Vector3.RIGHT, ang), Vector3(0.0, _defs.roof_rise * 0.5, 0.0)))
		"stairs":
			# Пандус под ступенями: идти по нему проще, чем по ступеням (у персонажа нет «шага вверх»).
			var ang2: float = atan2(h, s)
			var len2: float = sqrt(s * s + h * h)
			_add_shape(body, _box_shape("ramp", Vector3(s - 0.4, 0.1, len2)), Transform3D(Basis(Vector3.RIGHT, ang2), Vector3(0.0, h * 0.5, 0.0)))
	body.transform = xf
	add_child(body)
	_bodies[id] = body


# --- Модели -----------------------------------------------------------------

static func _box(st: SurfaceTool, size: Vector3, center: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var b: BoxMesh = BoxMesh.new()
	b.size = size
	st.append_from(b, 0, Transform3D(basis, center))


func _make_mesh(type: String) -> Mesh:
	var s: float = _defs.grid
	var h: float = _defs.wall_h
	var t: float = _defs.wall_t
	var st: SurfaceTool = SurfaceTool.new()
	match type:
		"foundation":
			_box(st, Vector3(s, 1.0, s), Vector3(0.0, -0.5, 0.0))
		"floor":
			_box(st, Vector3(s, _defs.floor_t, s), Vector3(0.0, -_defs.floor_t * 0.5, 0.0))
			# Балки снизу — чтобы перекрытие читалось снизу.
			for k: int in 3:
				_box(st, Vector3(s - 0.1, 0.14, 0.14), Vector3(0.0, -_defs.floor_t - 0.07, -s * 0.33 + s * 0.33 * float(k)))
		"wall":
			_box(st, Vector3(s, h, t), Vector3(0.0, h * 0.5, 0.0))
			for x: float in [-s * 0.5 + 0.08, s * 0.5 - 0.08]:
				_box(st, Vector3(0.16, h, t + 0.06), Vector3(x, h * 0.5, 0.0))
		"doorway":
			var side_w: float = (s - _defs.doorway_w) * 0.5
			_box(st, Vector3(side_w, h, t), Vector3(-s * 0.5 + side_w * 0.5, h * 0.5, 0.0))
			_box(st, Vector3(side_w, h, t), Vector3(s * 0.5 - side_w * 0.5, h * 0.5, 0.0))
			var lintel_h: float = h - _defs.doorway_h
			_box(st, Vector3(_defs.doorway_w, lintel_h, t), Vector3(0.0, _defs.doorway_h + lintel_h * 0.5, 0.0))
			for x2: float in [-_defs.doorway_w * 0.5 - 0.06, _defs.doorway_w * 0.5 + 0.06]:
				_box(st, Vector3(0.12, _defs.doorway_h, t + 0.06), Vector3(x2, _defs.doorway_h * 0.5, 0.0))
		"roof":
			var ang: float = atan2(_defs.roof_rise, s)
			var len: float = sqrt(s * s + _defs.roof_rise * _defs.roof_rise)
			_box(st, Vector3(s + 0.2, _defs.floor_t, len + 0.1), Vector3(0.0, _defs.roof_rise * 0.5, 0.0), Basis(Vector3.RIGHT, ang))
			# Конёк — балка по верхнему краю.
			_box(st, Vector3(s + 0.2, 0.18, 0.18), Vector3(0.0, _defs.roof_rise + 0.05, -s * 0.5))
		"stairs":
			var steps: int = 10
			var rise: float = h / float(steps)
			var depth: float = s / float(steps)
			for i: int in steps:
				var hh: float = rise * float(i + 1)
				_box(st, Vector3(s - 0.4, hh, depth), Vector3(0.0, hh * 0.5, s * 0.5 - depth * (float(i) + 0.5)))
		"door":
			var w: float = _defs.doorway_w - 0.04
			var dh: float = _defs.doorway_h - 0.02
			_box(st, Vector3(w, dh, 0.08), Vector3(w * 0.5 + 0.02, dh * 0.5, 0.0))
			for y: float in [0.35, dh - 0.35]:
				_box(st, Vector3(w - 0.1, 0.12, 0.12), Vector3(w * 0.5 + 0.02, y, 0.0))
			_box(st, Vector3(0.06, 0.06, 0.2), Vector3(w - 0.12, 1.0, 0.0))
		"lock":
			_box(st, Vector3(0.14, 0.22, 0.2), Vector3(_defs.doorway_w - 0.22, 1.2, 0.0))
		_:
			push_error("BuildingView: нет модели для %s" % type)
			_box(st, Vector3.ONE, Vector3.ZERO)
	var mesh: ArrayMesh = st.commit()
	if type == "lock":
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.21, 0.22)
		m.metallic = 0.4
		m.emission_enabled = true
		m.emission = Color(0.85, 0.63, 0.25)
		m.emission_energy_multiplier = 0.15
		mesh.surface_set_material(0, m)
	return mesh
