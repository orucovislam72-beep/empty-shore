class_name DeployableView
extends Node3D
## Отрисовка размещённых объектов (Deployables): костёр с огнём и светом, верстак,
## с этапа 2 — ящик и знамя базы (со столкновениями, чтобы на них нельзя было встать внутрь).
## Слушает сигналы логики; общие сетки и материалы создаются один раз.
## Свет костра — один OmniLight3D без теней на каждый горящий костёр.

const FLICKER_SPEED: float = 9.0

var _dep: Deployables
var _nodes: Array[Node3D] = []
var _flames: Array[Node3D] = []
var _lights: Array[OmniLight3D] = []
var _time: float = 0.0

var _meshes: Dictionary = {}


func bind(dep: Deployables) -> void:
	_dep = dep
	dep.added.connect(_on_added)
	dep.changed.connect(_on_changed)
	dep.cleared.connect(_on_cleared)
	for i: int in dep.size():
		_on_added(i)


func _on_added(i: int) -> void:
	var kind: String = _dep.kinds[i]
	var root: Node3D = Node3D.new()
	root.name = "%s_%d" % [kind, i]
	root.position = _dep.positions[i]
	root.rotation.y = _dep.yaws[i]
	var flame: Node3D = null
	var light: OmniLight3D = null
	match kind:
		"campfire":
			_add_mesh(root, "campfire_base")
			flame = Node3D.new()
			flame.name = "Flame"
			_add_mesh(flame, "flame")
			root.add_child(flame)
			light = OmniLight3D.new()
			light.name = "Light"
			light.light_color = Color(1.0, 0.68, 0.36)
			light.omni_range = JsonData.get_float(_dep.type_def(kind), "light_range", 9.0)
			light.light_energy = 1.4
			light.shadow_enabled = false
			light.position = Vector3(0.0, 0.8, 0.0)
			root.add_child(light)
		"workbench_1":
			_add_mesh(root, "workbench")
		"storage_box":
			_add_mesh(root, "storage_box")
			_add_box_body(root, Vector3(1.0, 0.7, 0.6), 0.35)
		"base_banner":
			_add_mesh(root, "base_banner")
			_add_box_body(root, Vector3(0.3, 2.6, 0.3), 1.3)
		_:
			push_error("DeployableView: нет модели для %s" % kind)
	add_child(root)
	_nodes.append(root)
	_flames.append(flame)
	_lights.append(light)
	_on_changed(i)


func _on_changed(i: int) -> void:
	if i >= _nodes.size():
		return
	# Объект мог опуститься после обрушения пола.
	_nodes[i].position = _dep.positions[i]
	var lit: bool = _dep.is_lit(i)
	if _flames[i] != null:
		_flames[i].visible = lit
	if _lights[i] != null:
		_lights[i].visible = lit


func _on_cleared() -> void:
	for n: Node3D in _nodes:
		n.queue_free()
	_nodes.clear()
	_flames.clear()
	_lights.clear()


## Мерцание огня: только изменение чисел, без выделения памяти.
func _process(delta: float) -> void:
	_time += delta
	for i: int in _lights.size():
		var l: OmniLight3D = _lights[i]
		if l == null or not l.visible:
			continue
		var f: float = sin(_time * FLICKER_SPEED + float(i)) * 0.5 + sin(_time * 23.0 + float(i) * 2.0) * 0.25
		l.light_energy = 1.4 + f * 0.25
		_flames[i].scale = Vector3(1.0, 1.0 + f * 0.12, 1.0)


func _add_box_body(parent: Node3D, size: Vector3, center_y: float) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = Vector3(0.0, center_y, 0.0)
	body.add_child(col)
	parent.add_child(body)


func _add_mesh(parent: Node3D, key: String) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _mesh(key)
	if key == "flame":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _mesh(key: String) -> Mesh:
	if not _meshes.has(key):
		match key:
			"campfire_base":
				_meshes[key] = _make_campfire_base()
			"flame":
				_meshes[key] = _make_flame()
			"workbench":
				_meshes[key] = _make_workbench()
			"storage_box":
				_meshes[key] = _make_storage_box()
			"base_banner":
				_meshes[key] = _make_banner()
	return _meshes[key]


static func _mat(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


static func _make_campfire_base() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	var log_mesh: CylinderMesh = CylinderMesh.new()
	log_mesh.top_radius = 0.08
	log_mesh.bottom_radius = 0.08
	log_mesh.height = 0.9
	log_mesh.radial_segments = 6
	log_mesh.rings = 0
	for k: int in 4:
		var yaw: float = float(k) * PI * 0.5 + 0.4
		var b: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(65.0))
		st.append_from(log_mesh, 0, Transform3D(b, Vector3(sin(yaw) * -0.12, 0.2, cos(yaw) * -0.12)))
	st.commit(mesh)
	st.clear()
	var stone: SphereMesh = SphereMesh.new()
	stone.radius = 0.12
	stone.height = 0.18
	stone.radial_segments = 5
	stone.rings = 2
	for k: int in 8:
		var a: float = float(k) * TAU / 8.0
		st.append_from(stone, 0, Transform3D(Basis.IDENTITY, Vector3(cos(a) * 0.55, 0.05, sin(a) * 0.55)))
	st.commit(mesh)
	mesh.surface_set_material(0, _mat(Color(0.36, 0.24, 0.15)))
	mesh.surface_set_material(1, _mat(Color(0.45, 0.45, 0.47)))
	return mesh


## Пламя: два конуса без освещения (не зависит от света сцены и дёшево).
static func _make_flame() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	var outer: CylinderMesh = CylinderMesh.new()
	outer.top_radius = 0.0
	outer.bottom_radius = 0.28
	outer.height = 0.75
	outer.radial_segments = 6
	outer.rings = 0
	st.append_from(outer, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)))
	st.commit(mesh)
	st.clear()
	var inner: CylinderMesh = CylinderMesh.new()
	inner.top_radius = 0.0
	inner.bottom_radius = 0.16
	inner.height = 0.5
	inner.radial_segments = 5
	inner.rings = 0
	st.append_from(inner, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.42, 0.0)))
	st.commit(mesh)
	for s: int in 2:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.95, 0.55, 0.2) if s == 0 else Color(1.0, 0.85, 0.45)
		mesh.surface_set_material(s, m)
	return mesh


static func _make_workbench() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	var top: BoxMesh = BoxMesh.new()
	top.size = Vector3(1.6, 0.12, 0.8)
	st.append_from(top, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0)))
	var leg: BoxMesh = BoxMesh.new()
	leg.size = Vector3(0.12, 0.84, 0.12)
	for x: float in [-0.68, 0.68]:
		for z: float in [-0.3, 0.3]:
			st.append_from(leg, 0, Transform3D(Basis.IDENTITY, Vector3(x, 0.42, z)))
	var shelf: BoxMesh = BoxMesh.new()
	shelf.size = Vector3(1.4, 0.06, 0.6)
	st.append_from(shelf, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)))
	st.commit(mesh)
	st.clear()
	var vise: BoxMesh = BoxMesh.new()
	vise.size = Vector3(0.3, 0.18, 0.2)
	st.append_from(vise, 0, Transform3D(Basis.IDENTITY, Vector3(0.5, 1.05, 0.2)))
	st.commit(mesh)
	mesh.surface_set_material(0, _mat(Color(0.55, 0.38, 0.23)))
	mesh.surface_set_material(1, _mat(Color(0.5, 0.52, 0.55)))
	return mesh


## Ящик: корпус, крышка и металлические уголки.
static func _make_storage_box() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	var body: BoxMesh = BoxMesh.new()
	body.size = Vector3(1.0, 0.6, 0.6)
	st.append_from(body, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)))
	var lid: BoxMesh = BoxMesh.new()
	lid.size = Vector3(1.04, 0.1, 0.64)
	st.append_from(lid, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.65, 0.0)))
	st.commit(mesh)
	st.clear()
	var band: BoxMesh = BoxMesh.new()
	band.size = Vector3(1.06, 0.06, 0.66)
	for y: float in [0.15, 0.45]:
		st.append_from(band, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)))
	var latch: BoxMesh = BoxMesh.new()
	latch.size = Vector3(0.12, 0.14, 0.04)
	st.append_from(latch, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.33)))
	st.commit(mesh)
	mesh.surface_set_material(0, _mat(Color(0.55, 0.38, 0.23)))
	mesh.surface_set_material(1, _mat(Color(0.42, 0.44, 0.47)))
	return mesh


## Знамя базы: столб с перекладиной, полотнище в акцентном цвете, каменное основание.
static func _make_banner() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	var pole: CylinderMesh = CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.07
	pole.height = 2.6
	pole.radial_segments = 6
	pole.rings = 0
	st.append_from(pole, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.3, 0.0)))
	var bar: BoxMesh = BoxMesh.new()
	bar.size = Vector3(1.0, 0.06, 0.06)
	st.append_from(bar, 0, Transform3D(Basis.IDENTITY, Vector3(0.45, 2.45, 0.0)))
	st.commit(mesh)
	st.clear()
	var cloth: BoxMesh = BoxMesh.new()
	cloth.size = Vector3(0.85, 1.2, 0.03)
	st.append_from(cloth, 0, Transform3D(Basis.IDENTITY, Vector3(0.5, 1.8, 0.0)))
	st.commit(mesh)
	st.clear()
	var base: CylinderMesh = CylinderMesh.new()
	base.top_radius = 0.3
	base.bottom_radius = 0.38
	base.height = 0.25
	base.radial_segments = 7
	base.rings = 0
	st.append_from(base, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0)))
	st.commit(mesh)
	mesh.surface_set_material(0, _mat(Color(0.45, 0.31, 0.19)))
	var cm: StandardMaterial3D = _mat(Color(0.85, 0.63, 0.25))
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, cm)
	mesh.surface_set_material(2, _mat(Color(0.45, 0.45, 0.47)))
	return mesh
