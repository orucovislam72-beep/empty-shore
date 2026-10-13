class_name HeldItemView
extends Node3D
## Предмет в руке (вид от первого лица): простая процедурная модель инструмента и взмах.
## Вешается на камеру. Анимация — изменение поворота в _process, без выделения памяти.

const REST_POS: Vector3 = Vector3(0.34, -0.42, -0.75)
const MODEL_SCALE: float = 0.7
const REST_ROT: Vector3 = Vector3(deg_to_rad(10.0), deg_to_rad(-12.0), deg_to_rad(-8.0))

var _mi: MeshInstance3D
var _meshes: Dictionary = {}
var _swing_t: float = 1.0
var _swing_len: float = 0.5
var _item: String = "-"


func _ready() -> void:
	position = REST_POS
	rotation = REST_ROT
	_mi = MeshInstance3D.new()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.scale = Vector3.ONE * MODEL_SCALE
	add_child(_mi)
	visible = false


func show_item(item_id: String) -> void:
	if item_id == _item:
		return
	_item = item_id
	var key: String = ""
	match item_id:
		"stone_axe", "metal_axe":
			key = item_id
		"stone_pickaxe", "metal_pickaxe":
			key = item_id
	visible = not key.is_empty()
	if visible:
		if not _meshes.has(key):
			_meshes[key] = _make_tool(key.ends_with("pickaxe"), key.begins_with("metal"))
		_mi.mesh = _meshes[key]


## Взмах длительностью seconds.
func swing(seconds: float) -> void:
	_swing_len = maxf(seconds * 0.85, 0.15)
	_swing_t = 0.0


func _process(delta: float) -> void:
	if _swing_t >= 1.0:
		return
	_swing_t = minf(_swing_t + delta / _swing_len, 1.0)
	# Быстрый замах вниз и плавный возврат.
	var k: float = sin(_swing_t * PI)
	rotation = Vector3(REST_ROT.x - k * deg_to_rad(75.0), REST_ROT.y + k * deg_to_rad(10.0), REST_ROT.z)
	position = REST_POS + Vector3(-0.08 * k, 0.05 * k, -0.1 * k)


static func _mat(c: Color, rough: float = 1.0) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _make_tool(pick: bool, metal: bool) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	var handle: CylinderMesh = CylinderMesh.new()
	handle.top_radius = 0.022
	handle.bottom_radius = 0.026
	handle.height = 0.55
	handle.radial_segments = 6
	handle.rings = 0
	st.append_from(handle, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 0.0)))
	st.commit(mesh)
	st.clear()
	var head: BoxMesh = BoxMesh.new()
	if pick:
		head.size = Vector3(0.36, 0.05, 0.05)
		st.append_from(head, 0, Transform3D(Basis(Vector3.FORWARD, 0.12), Vector3(0.0, 0.36, 0.0)))
	else:
		head.size = Vector3(0.16, 0.13, 0.03)
		st.append_from(head, 0, Transform3D(Basis.IDENTITY, Vector3(0.07, 0.33, 0.0)))
	st.commit(mesh)
	mesh.surface_set_material(0, _mat(Color(0.45, 0.3, 0.18)))
	mesh.surface_set_material(1, _mat(Color(0.75, 0.78, 0.8), 0.4) if metal else _mat(Color(0.66, 0.66, 0.68)))
	return mesh
