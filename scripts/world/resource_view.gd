class_name ResourceView
extends Node3D
## Отрисовка ресурсных узлов (ResourceField) через MultiMesh: один MultiMeshInstance3D на тип,
## 1–2 draw call на тип. Истощённый узел скрывается нулевым масштабом экземпляра
## (без создания и удаления узлов сцены). Модели — простые процедурные low-poly.

var _field: ResourceField
var _mmis: Array[MultiMeshInstance3D] = []
## Для каждого узла поля — номер экземпляра в MultiMesh его типа.
var _local: PackedInt32Array = PackedInt32Array()
var _draw_distance: float = 200.0


func build(field: ResourceField) -> void:
	_field = field
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(field.types.size())
	_local.resize(field.size())
	for i: int in field.size():
		var t: int = field.type_index[i]
		_local[i] = counts[t]
		counts[t] += 1
	for t: int in field.types.size():
		var id: String = String(field.types[t].get("id", ""))
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh_for(id)
		mm.instance_count = counts[t]
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "Nodes_" + id
		mmi.multimesh = mm
		add_child(mmi)
		_mmis.append(mmi)
	for i: int in field.size():
		_update(i)
	field.node_changed.connect(_update)
	set_draw_distance(_draw_distance)


func set_draw_distance(distance: float) -> void:
	_draw_distance = distance
	for mmi: MultiMeshInstance3D in _mmis:
		mmi.visibility_range_end = distance


func _update(i: int) -> void:
	var mm: MultiMesh = _mmis[_field.type_index[i]].multimesh
	var xf: Transform3D
	if _field.is_available(i):
		var s: float = _field.scales[i]
		xf = Transform3D(Basis(Vector3.UP, _field.yaws[i]).scaled(Vector3(s, s, s)), _field.positions[i])
	else:
		xf = Transform3D(Basis.from_scale(Vector3.ZERO), _field.positions[i])
	mm.set_instance_transform(_local[i], xf)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


static func _mesh_for(id: String) -> Mesh:
	match id:
		"tree":
			return make_tree_mesh()
		"rock":
			return make_rock_mesh(Color(0.5, 0.5, 0.52), Color(0.0, 0.0, 0.0, 0.0))
		"ore":
			return make_rock_mesh(Color(0.42, 0.38, 0.35), Color(0.85, 0.55, 0.22))
		"bush":
			return make_bush_mesh()
	push_error("ResourceView: нет модели для типа узла %s" % id)
	return BoxMesh.new()


## Дерево: ствол и крона-конус, основание в нуле. Две поверхности = 2 draw call на все деревья.
static func make_tree_mesh() -> ArrayMesh:
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
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	st.commit(mesh)
	st.clear()
	st.append_from(crown, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.4, 0.0)))
	st.commit(mesh)
	mesh.surface_set_material(0, _flat_material(Color(0.36, 0.26, 0.18)))
	mesh.surface_set_material(1, _flat_material(Color(0.2, 0.38, 0.24)))
	return mesh


## Камень (и рудный камень с вкраплениями, если vein_color.a > 0).
static func make_rock_mesh(body: Color, vein_color: Color) -> ArrayMesh:
	var rock: SphereMesh = SphereMesh.new()
	rock.radius = 0.9
	rock.height = 1.1
	rock.radial_segments = 6
	rock.rings = 3
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	st.append_from(rock, 0, Transform3D(Basis.from_scale(Vector3(1.2, 1.0, 1.0)), Vector3(0.0, 0.25, 0.0)))
	st.commit(mesh)
	mesh.surface_set_material(0, _flat_material(body))
	if vein_color.a > 0.0:
		var crystal: CylinderMesh = CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = 0.18
		crystal.height = 0.45
		crystal.radial_segments = 4
		crystal.rings = 0
		crystal.cap_bottom = false
		st.clear()
		var spots: Array[Vector3] = [Vector3(0.4, 0.6, 0.3), Vector3(-0.5, 0.5, -0.2), Vector3(0.1, 0.75, -0.45)]
		for p: Vector3 in spots:
			var b: Basis = Basis.looking_at(p.normalized(), Vector3.FORWARD if absf(p.normalized().y) > 0.9 else Vector3.UP)
			b = b * Basis(Vector3.RIGHT, -PI * 0.5)
			st.append_from(crystal, 0, Transform3D(b, p))
		st.commit(mesh)
		var m: StandardMaterial3D = _flat_material(vein_color)
		m.roughness = 0.4
		mesh.surface_set_material(1, m)
	return mesh


## Куст с ягодами: зелёная «шапка» и три красные ягоды.
static func make_bush_mesh() -> ArrayMesh:
	var leaves: SphereMesh = SphereMesh.new()
	leaves.radius = 0.7
	leaves.height = 1.0
	leaves.radial_segments = 7
	leaves.rings = 3
	var berry: SphereMesh = SphereMesh.new()
	berry.radius = 0.12
	berry.height = 0.24
	berry.radial_segments = 5
	berry.rings = 2
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	st.append_from(leaves, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.45, 0.0)))
	st.commit(mesh)
	st.clear()
	for p: Vector3 in [Vector3(0.45, 0.6, 0.35), Vector3(-0.4, 0.7, 0.3), Vector3(0.05, 0.75, -0.55), Vector3(-0.2, 0.95, 0.0)]:
		st.append_from(berry, 0, Transform3D(Basis.IDENTITY, p))
	st.commit(mesh)
	mesh.surface_set_material(0, _flat_material(Color(0.23, 0.42, 0.22)))
	mesh.surface_set_material(1, _flat_material(Color(0.7, 0.18, 0.22)))
	return mesh
