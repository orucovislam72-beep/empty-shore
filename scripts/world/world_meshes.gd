class_name WorldMeshes
extends RefCounted
## Процедурные low-poly модели мира (свои, без сторонних ассетов). Каждая модель — одна поверхность
## с цветами вершин и общим материалом: один draw call на MultiMesh (с этапа 3; на этапе 1–2 деревья,
## руда и кусты были из двух поверхностей). Модели строятся один раз и кэшируются.

static var _cache: Dictionary = {}
static var _material: StandardMaterial3D


## Общий материал «цвет из вершин».
static func vertex_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 1.0
	return _material


## Сборщик одной поверхности из примитивов с цветом.
class Builder:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()

	func add(pm: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
		var arrs: Array = pm.get_mesh_arrays()
		var v: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
		var base: int = verts.size()
		var nb: Basis = xf.basis.inverse().transposed()
		for i: int in v.size():
			verts.append(xf * v[i])
			normals.append((nb * n[i]).normalized())
			colors.append(color)
		for i: int in idx.size():
			indices.append(base + idx[i])

	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, WorldMeshes.vertex_material())
		return mesh


static func get_mesh(id: String) -> Mesh:
	if _cache.has(id):
		return _cache[id]
	var m: Mesh
	match id:
		"tree":
			m = _tree()
		"rock":
			m = _rock(Color(0.5, 0.5, 0.52), Color(0.0, 0.0, 0.0, 0.0))
		"ore":
			m = _rock(Color(0.42, 0.38, 0.35), Color(0.85, 0.55, 0.22))
		"bush":
			m = _bush()
		"crate":
			m = _crate(Color(0.55, 0.38, 0.22), Color(0.38, 0.25, 0.14))
		"crate_military":
			m = _crate(Color(0.33, 0.4, 0.27), Color(0.22, 0.27, 0.18))
		"barrel":
			m = _barrel()
		"bag":
			m = _bag()
		"deer":
			m = _quadruped(Color(0.55, 0.38, 0.24), Vector3(0.45, 0.55, 1.3), 0.95, 0.75, true)
		"wolf":
			m = _quadruped(Color(0.45, 0.45, 0.47), Vector3(0.36, 0.4, 1.1), 0.6, 0.5, false)
		"bear":
			m = _quadruped(Color(0.3, 0.21, 0.15), Vector3(0.9, 0.85, 1.8), 0.75, 0.6, false)
		"arrow":
			m = _arrow()
		"grass":
			m = _grass()
		_:
			push_error("WorldMeshes: нет модели %s" % id)
			m = BoxMesh.new()
	_cache[id] = m
	return m


static func _cyl(top: float, bottom: float, h: float, seg: int, caps: bool = true) -> CylinderMesh:
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 0
	c.cap_top = caps
	c.cap_bottom = caps
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b: BoxMesh = BoxMesh.new()
	b.size = size
	return b


static func _sphere(r: float, h: float, seg: int, rings: int) -> SphereMesh:
	var s: SphereMesh = SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = seg
	s.rings = rings
	return s


## Дерево: ствол и крона-конус, основание в нуле (те же размеры, что на этапах 1–2).
static func _tree() -> ArrayMesh:
	var b: Builder = Builder.new()
	b.add(_cyl(0.12, 0.22, 2.4, 6, false), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Color(0.36, 0.26, 0.18))
	var crown: CylinderMesh = _cyl(0.0, 1.5, 4.0, 7)
	crown.cap_top = false
	b.add(crown, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.4, 0.0)), Color(0.2, 0.38, 0.24))
	return b.commit()


static func _rock(body: Color, vein: Color) -> ArrayMesh:
	var b: Builder = Builder.new()
	b.add(_sphere(0.9, 1.1, 6, 3), Transform3D(Basis.from_scale(Vector3(1.2, 1.0, 1.0)), Vector3(0.0, 0.25, 0.0)), body)
	if vein.a > 0.0:
		var crystal: CylinderMesh = _cyl(0.0, 0.18, 0.45, 4)
		crystal.cap_top = false
		for p: Vector3 in [Vector3(0.4, 0.6, 0.3), Vector3(-0.5, 0.5, -0.2), Vector3(0.1, 0.75, -0.45)]:
			var nd: Vector3 = p.normalized()
			var basis: Basis = Basis.looking_at(nd, Vector3.FORWARD if absf(nd.y) > 0.9 else Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
			b.add(crystal, Transform3D(basis, p), vein)
	return b.commit()


static func _bush() -> ArrayMesh:
	var b: Builder = Builder.new()
	b.add(_sphere(0.7, 1.0, 7, 3), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.45, 0.0)), Color(0.23, 0.42, 0.22))
	var berry: SphereMesh = _sphere(0.12, 0.24, 5, 2)
	for p: Vector3 in [Vector3(0.45, 0.6, 0.35), Vector3(-0.4, 0.7, 0.3), Vector3(0.05, 0.75, -0.55), Vector3(-0.2, 0.95, 0.0)]:
		b.add(berry, Transform3D(Basis.IDENTITY, p), Color(0.7, 0.18, 0.22))
	return b.commit()


static func _crate(body: Color, band: Color) -> ArrayMesh:
	var b: Builder = Builder.new()
	b.add(_box(Vector3(1.0, 0.7, 0.7)), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, 0.0)), body)
	b.add(_box(Vector3(1.04, 0.1, 0.74)), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0)), band)
	b.add(_box(Vector3(1.04, 0.1, 0.74)), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.0)), band)
	return b.commit()


static func _barrel() -> ArrayMesh:
	var b: Builder = Builder.new()
	b.add(_cyl(0.36, 0.36, 1.0, 10), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), Color(0.27, 0.42, 0.5))
	b.add(_cyl(0.38, 0.38, 0.07, 10), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25, 0.0)), Color(0.2, 0.22, 0.24))
	b.add(_cyl(0.38, 0.38, 0.07, 10), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.75, 0.0)), Color(0.2, 0.22, 0.24))
	return b.commit()


static func _bag() -> ArrayMesh:
	var b: Builder = Builder.new()
	b.add(_sphere(0.42, 0.62, 8, 4), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.8)), Vector3(0.0, 0.3, 0.0)), Color(0.42, 0.33, 0.22))
	b.add(_cyl(0.08, 0.14, 0.18, 6), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.66, 0.0)), Color(0.3, 0.23, 0.15))
	return b.commit()


## Четвероногое: туловище size, голова впереди (+Z), четыре ноги; основание в нуле.
static func _quadruped(c: Color, size: Vector3, leg_h: float, head_h: float, antlers: bool) -> ArrayMesh:
	var b: Builder = Builder.new()
	var body_y: float = leg_h + size.y * 0.5
	b.add(_box(size), Transform3D(Basis.IDENTITY, Vector3(0.0, body_y, 0.0)), c)
	var dark: Color = c.darkened(0.3)
	var hs: Vector3 = Vector3(size.x * 0.7, size.y * 0.6, size.z * 0.35)
	b.add(_box(hs), Transform3D(Basis.IDENTITY, Vector3(0.0, leg_h + size.y * 0.5 + head_h * 0.35, size.z * 0.5 + hs.z * 0.4)), c.lightened(0.05))
	b.add(_box(Vector3(hs.x * 0.6, hs.y * 0.5, hs.z * 0.5)), Transform3D(Basis.IDENTITY, Vector3(0.0, leg_h + size.y * 0.4 + head_h * 0.3, size.z * 0.5 + hs.z * 0.95)), dark)
	var lw: float = maxf(size.x * 0.22, 0.08)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.add(_box(Vector3(lw, leg_h, lw)), Transform3D(Basis.IDENTITY, Vector3(sx * (size.x * 0.5 - lw * 0.5), leg_h * 0.5, sz * (size.z * 0.5 - lw))), dark)
	if antlers:
		var hy: float = leg_h + size.y * 0.5 + head_h * 0.35 + hs.y * 0.5
		for sx2: float in [-1.0, 1.0]:
			b.add(_box(Vector3(0.05, 0.4, 0.05)), Transform3D(Basis(Vector3.FORWARD, sx2 * 0.4), Vector3(sx2 * 0.12, hy + 0.18, size.z * 0.5 + hs.z * 0.2)), Color(0.85, 0.8, 0.68))
	return b.commit()


## Стрела/пуля: тонкий стержень вдоль +Z длиной 0,8 м.
static func _arrow() -> ArrayMesh:
	var b: Builder = Builder.new()
	b.add(_box(Vector3(0.025, 0.025, 0.8)), Transform3D(Basis.IDENTITY, Vector3.ZERO), Color(0.9, 0.85, 0.7))
	return b.commit()


## Пучок травы: три вертикальных треугольника под 60°, цвет от корня к кончику, без освещения.
static func _grass() -> ArrayMesh:
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
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	return mesh


## Вода: плоскость side × side на высоте level (2 треугольника), непрозрачная — дешевле для мобильного GPU.
static func make_water(side: float, level: float) -> MeshInstance3D:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(side, side)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.33, 0.42)
	mat.roughness = 0.25
	mat.metallic_specular = 0.6
	plane.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.position = Vector3(0.0, level, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Буфер MultiMesh (3D, без цветов): 12 float на экземпляр — строки базиса и origin.
static func write_transform(buf: PackedFloat32Array, index: int, b: Basis, origin: Vector3) -> void:
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
