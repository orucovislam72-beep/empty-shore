class_name BuildingGrid
extends RefCounted
## Постройки по мировой сетке (этап 2). Чистая логика без сцен и без физики:
## ключи деталей, правила опоры, подсказка места («призрак») по лучу взгляда без точного прицела,
## поиск детали под прицелом, двери и кодовые замки, обрушение без опоры, сохранение.
## Право владения, обслуживание и износ — в BaseClaims; стоимость и инвентарь — в SurvivalSession.
##
## Сетка: клетка (cx, cz) занимает [cx·S, (cx+1)·S] × [cz·S, (cz+1)·S]; высоты — целые шаги hy
## по 0,25 м (y = hy · step). Ключ детали — Vector4i(cx, cz, hy, слот).
## Слоты: CELL — фундамент/перекрытие/крыша в клетке; STAIRS — лестница в клетке;
## EDGE_X — стена/проём на северной границе клетки (вдоль X), EDGE_Z — на западной (вдоль Z);
## DOOR_X/DOOR_Z — дверь в проёме той же границы.
## Стороны клетки: 0 — север (−Z), 1 — восток (+X), 2 — юг (+Z), 3 — запад (−X).

signal piece_added(id: int)
## Изменились материал, прочность, состояние двери или замок.
signal piece_changed(id: int)
signal piece_removed(id: int)
signal cleared

enum Slot { CELL, STAIRS, EDGE_X, EDGE_Z, DOOR_X, DOOR_Z }
enum Reason { OK, OCCUPIED, NO_SUPPORT, TERRAIN, WATER, BLOCKED, PLAYER, TOO_FAR, MATERIAL, NO_DOORWAY, UNKNOWN }

## Подсказка места для детали: заполняется suggest(), переиспользуется (без выделения памяти в кадре).
class Placement:
	extends RefCounted
	var type: String = ""
	var material: int = 0
	var key: Vector4i = Vector4i.ZERO
	var rot: int = 0
	var depth: float = 1.0
	var reason: int = Reason.UNKNOWN

	func is_valid() -> bool:
		return reason == Reason.OK


const BLOCK_SHRINK: float = 0.12
const NO_HY: int = -1073741824

var defs: BuildingDefs
var terrain: TerrainMath
var water_level: float = -1000.0
## Ресурсные узлы и размещённые объекты мешают ставить детали (могут быть null в тестах).
var resources: ResourceField
var deployables: Deployables

var p_type: PackedStringArray = PackedStringArray()
var p_mat: PackedInt32Array = PackedInt32Array()
var p_key: Array[Vector4i] = []
var p_rot: PackedInt32Array = PackedInt32Array()
var p_hp: PackedFloat32Array = PackedFloat32Array()
var p_owner: PackedStringArray = PackedStringArray()
var p_depth: PackedFloat32Array = PackedFloat32Array()
var p_open: PackedByteArray = PackedByteArray()
var p_code: PackedStringArray = PackedStringArray()
var p_lock_auth: Array[PackedStringArray] = []

var _by_key: Dictionary = {}
## Vector3i(cx, cz, слот) -> PackedInt32Array высот hy в этой «колонне».
var _columns: Dictionary = {}
var _alive: int = 0


func _init(p_defs: BuildingDefs = null, p_terrain: TerrainMath = null, p_water: float = -1000.0) -> void:
	defs = p_defs if p_defs != null else BuildingDefs.new()
	terrain = p_terrain
	water_level = p_water


# --- Доступ -----------------------------------------------------------------

func capacity() -> int:
	return p_type.size()


func count() -> int:
	return _alive


func is_alive(id: int) -> bool:
	return id >= 0 and id < p_type.size() and not p_type[id].is_empty()


func id_at(key: Vector4i) -> int:
	return int(_by_key.get(key, -1))


func max_hp(id: int) -> float:
	return defs.max_hp(p_type[id], p_mat[id])


func is_door(id: int) -> bool:
	return is_alive(id) and (p_key[id].w == Slot.DOOR_X or p_key[id].w == Slot.DOOR_Z)


func has_lock(id: int) -> bool:
	return is_door(id) and not p_code[id].is_empty()


func is_open(id: int) -> bool:
	return is_door(id) and p_open[id] != 0


func alive_ids(out: PackedInt32Array) -> void:
	out.clear()
	for i: int in p_type.size():
		if not p_type[i].is_empty():
			out.append(i)


# --- Геометрия --------------------------------------------------------------

static func slot_for(slot_kind: String, edge_x: bool) -> int:
	match slot_kind:
		BuildingDefs.SLOT_CELL:
			return Slot.CELL
		BuildingDefs.SLOT_STAIRS:
			return Slot.STAIRS
		BuildingDefs.SLOT_EDGE:
			return Slot.EDGE_X if edge_x else Slot.EDGE_Z
		BuildingDefs.SLOT_DOOR:
			return Slot.DOOR_X if edge_x else Slot.DOOR_Z
	return -1


static func is_edge_slot(slot: int) -> bool:
	return slot == Slot.EDGE_X or slot == Slot.EDGE_Z


static func is_door_slot(slot: int) -> bool:
	return slot == Slot.DOOR_X or slot == Slot.DOOR_Z


static func along_x(slot: int) -> bool:
	return slot == Slot.EDGE_X or slot == Slot.DOOR_X


## Ключ границы клетки (cx, cz) со стороны side (0 С, 1 В, 2 Ю, 3 З) для слота стены или двери.
static func edge_key(cx: int, cz: int, hy: int, side: int, door: bool) -> Vector4i:
	var sx: int = Slot.DOOR_X if door else Slot.EDGE_X
	var sz: int = Slot.DOOR_Z if door else Slot.EDGE_Z
	match posmod(side, 4):
		0:
			return Vector4i(cx, cz, hy, sx)
		1:
			return Vector4i(cx + 1, cz, hy, sz)
		2:
			return Vector4i(cx, cz + 1, hy, sx)
		_:
			return Vector4i(cx, cz, hy, sz)


## Две клетки по сторонам границы (ключ стены или двери).
static func edge_cells(key: Vector4i) -> Array[Vector2i]:
	if along_x(key.w):
		return [Vector2i(key.x, key.y), Vector2i(key.x, key.y - 1)]
	return [Vector2i(key.x, key.y), Vector2i(key.x - 1, key.y)]


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / defs.grid)), int(floor(z / defs.grid)))


func hy_of(y: float) -> int:
	return int(round(y / defs.step))


## Ограничивающий параллелепипед детали (для препятствий, прицела и проверок места).
func aabb_of(type: String, key: Vector4i, depth: float = 1.0) -> AABB:
	var s: float = defs.grid
	var x0: float = float(key.x) * s
	var z0: float = float(key.y) * s
	var y: float = defs.height_of(key.z)
	var t: float = defs.wall_t
	match key.w:
		Slot.CELL:
			match type:
				"foundation":
					return AABB(Vector3(x0, y - depth, z0), Vector3(s, depth, s))
				"roof":
					return AABB(Vector3(x0, y - defs.floor_t, z0), Vector3(s, defs.roof_rise + defs.floor_t * 2.0, s))
				_:
					return AABB(Vector3(x0, y - defs.floor_t, z0), Vector3(s, defs.floor_t, s))
		Slot.STAIRS:
			return AABB(Vector3(x0, y, z0), Vector3(s, defs.wall_h, s))
		Slot.EDGE_X:
			return AABB(Vector3(x0, y, z0 - t * 0.5), Vector3(s, defs.wall_h, t))
		Slot.EDGE_Z:
			return AABB(Vector3(x0 - t * 0.5, y, z0), Vector3(t, defs.wall_h, s))
		Slot.DOOR_X:
			return AABB(Vector3(x0 + (s - defs.doorway_w) * 0.5, y, z0 - t), Vector3(defs.doorway_w, defs.doorway_h, t * 2.0))
		Slot.DOOR_Z:
			return AABB(Vector3(x0 - t, y, z0 + (s - defs.doorway_w) * 0.5), Vector3(t * 2.0, defs.doorway_h, defs.doorway_w))
	return AABB(Vector3(x0, y, z0), Vector3(s, defs.wall_h, s))


func piece_aabb(id: int) -> AABB:
	return aabb_of(p_type[id], p_key[id], p_depth[id])


## Мировое преобразование детали для отрисовки: начало координат и поворот по правилам
## BuildingView (см. там описание моделей). Для фундамента масштаб по Y = глубина.
func transform_of(type: String, key: Vector4i, rot: int, depth: float = 1.0) -> Transform3D:
	var s: float = defs.grid
	var x0: float = float(key.x) * s
	var z0: float = float(key.y) * s
	var y: float = defs.height_of(key.z)
	match key.w:
		Slot.CELL, Slot.STAIRS:
			var b: Basis = Basis(Vector3.UP, -float(posmod(rot, 4)) * PI * 0.5)
			if type == "foundation":
				b = Basis.from_scale(Vector3(1.0, depth, 1.0))
			elif type == "floor":
				b = Basis.IDENTITY
			return Transform3D(b, Vector3(x0 + s * 0.5, y, z0 + s * 0.5))
		Slot.EDGE_X:
			return Transform3D(Basis.IDENTITY, Vector3(x0 + s * 0.5, y, z0))
		Slot.EDGE_Z:
			return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x0, y, z0 + s * 0.5))
		Slot.DOOR_X, Slot.DOOR_Z:
			return door_transform(key, rot, false)
	return Transform3D(Basis.IDENTITY, Vector3(x0, y, z0))


## Дверь: начало координат модели — нижний край петли, полотно идёт вдоль +X.
## rot: бит 0 — петли с другой стороны, бит 1 — открывается в другую сторону.
func door_transform(key: Vector4i, rot: int, open: bool) -> Transform3D:
	var s: float = defs.grid
	var y: float = defs.height_of(key.z)
	var half: float = defs.doorway_w * 0.5
	var yaw: float = 0.0
	var center: Vector3
	var axis: Vector3
	if along_x(key.w):
		center = Vector3(float(key.x) * s + s * 0.5, y, float(key.y) * s)
		axis = Vector3(1.0, 0.0, 0.0)
	else:
		center = Vector3(float(key.x) * s, y, float(key.y) * s + s * 0.5)
		axis = Vector3(0.0, 0.0, -1.0)
		yaw = PI * 0.5
	var hinge: Vector3 = center - axis * half
	if rot & 1:
		hinge = center + axis * half
		yaw += PI
	if open:
		yaw += PI * 0.5 if (rot & 2) == 0 else -PI * 0.5
	return Transform3D(Basis(Vector3.UP, yaw), hinge)


# --- Правила опоры ----------------------------------------------------------

func _column(cx: int, cz: int, slot: int) -> PackedInt32Array:
	return _columns.get(Vector3i(cx, cz, slot), PackedInt32Array())


## Тип детали в клетке на высоте hy (слот CELL) или "".
func cell_type(cx: int, cz: int, hy: int) -> String:
	var id: int = id_at(Vector4i(cx, cz, hy, Slot.CELL))
	return p_type[id] if id >= 0 else ""


## Есть ли пол (фундамент или перекрытие) в клетке на высоте hy.
func has_floor(cx: int, cz: int, hy: int) -> bool:
	var t: String = cell_type(cx, cz, hy)
	return t == "foundation" or t == "floor"


func has_edge_piece(key: Vector4i) -> bool:
	return id_at(key) >= 0


func is_supported(type: String, key: Vector4i) -> bool:
	match type:
		"foundation":
			return true
		"floor", "roof":
			var below: int = key.z - defs.level_steps
			for side: int in 4:
				if has_edge_piece(edge_key(key.x, key.y, below, side, false)):
					return true
			return false
		"wall", "doorway":
			for c: Vector2i in edge_cells(key):
				if has_floor(c.x, c.y, key.z):
					return true
			return false
		"stairs":
			return has_floor(key.x, key.y, key.z)
		"door":
			var dw: Vector4i = Vector4i(key.x, key.y, key.z, Slot.EDGE_X if key.w == Slot.DOOR_X else Slot.EDGE_Z)
			var id: int = id_at(dw)
			return id >= 0 and p_type[id] == "doorway"
	return false


## Перепад рельефа под клеткой: (мин, макс) высоты по углам и центру.
func ground_range(cx: int, cz: int) -> Vector2:
	if terrain == null:
		return Vector2.ZERO
	var s: float = defs.grid
	var x0: float = float(cx) * s
	var z0: float = float(cz) * s
	var lo: float = INF
	var hi: float = -INF
	for k: int in 9:
		var h: float = terrain.height_at(x0 + s * 0.5 * float(k % 3), z0 + s * 0.5 * float(k / 3))
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return Vector2(lo, hi)


## Высота hy фундамента в клетке: как у соседнего фундамента, иначе чуть выше рельефа.
func foundation_hy(cx: int, cz: int) -> int:
	var g: Vector2 = ground_range(cx, cz)
	var ground_hy: int = int(ceil((g.y + defs.found_min_above) / defs.step))
	var best: int = ground_hy
	var best_d: int = 1 << 30
	for side: int in 4:
		var n: Vector2i = Vector2i(cx, cz) + _side_dir(side)
		for hy: int in _column(n.x, n.y, Slot.CELL):
			if cell_type(n.x, n.y, hy) == "foundation" and absi(hy - ground_hy) < best_d:
				best_d = absi(hy - ground_hy)
				best = hy
	return best


static func _side_dir(side: int) -> Vector2i:
	match posmod(side, 4):
		0:
			return Vector2i(0, -1)
		1:
			return Vector2i(1, 0)
		2:
			return Vector2i(0, 1)
	return Vector2i(-1, 0)


## Глубина фундамента (от верха до чуть ниже самой низкой точки рельефа под ним).
func foundation_depth(cx: int, cz: int, hy: int) -> float:
	var g: Vector2 = ground_range(cx, cz)
	return maxf(defs.height_of(hy) - g.x + defs.found_below, 0.5)


# --- Проверка места ---------------------------------------------------------

## Можно ли поставить деталь (без проверки права владения и стоимости — это делает сессия).
## eye — глаза игрока (дальность), feet — ноги (не замуровать игрока); feet.y = NAN — не проверять.
func check(type: String, mat: int, key: Vector4i, eye: Vector3, feet: Vector3) -> int:
	if not defs.has_piece(type):
		return Reason.UNKNOWN
	if not defs.allows(type, mat):
		return Reason.MATERIAL
	var want_slot: int = slot_for(defs.slot_of(type), along_x(key.w))
	if want_slot != key.w:
		return Reason.UNKNOWN
	if _by_key.has(key):
		return Reason.OCCUPIED
	var depth: float = 1.0
	if type == "foundation":
		var g: Vector2 = ground_range(key.x, key.y)
		var top: float = defs.height_of(key.z)
		if terrain != null:
			var s: float = defs.grid
			var center_h: float = terrain.height_at((float(key.x) + 0.5) * s, (float(key.y) + 0.5) * s)
			if center_h < water_level:
				return Reason.WATER
			if top < g.y - defs.found_max_buried or top - g.x > defs.found_max_above:
				return Reason.TERRAIN
		depth = foundation_depth(key.x, key.y, key.z)
	elif type == "door":
		if not is_supported(type, key):
			return Reason.NO_DOORWAY
	if not is_supported(type, key):
		return Reason.NO_SUPPORT
	var box: AABB = aabb_of(type, key, depth)
	if eye.distance_to(box.get_center()) > defs.build_range:
		return Reason.TOO_FAR
	if _overlaps_pieces(type, key, box):
		return Reason.OCCUPIED
	var probe: AABB = shrink(box, BLOCK_SHRINK)
	if type == "foundation":
		# Проверяем только слой у поверхности: глубокая часть фундамента уходит в землю.
		probe = shrink(AABB(Vector3(box.position.x, defs.height_of(key.z) - 2.0, box.position.z), Vector3(box.size.x, 2.5, box.size.z)), BLOCK_SHRINK)
	if resources != null and resources.blocks_box(probe):
		return Reason.BLOCKED
	if deployables != null and deployables.blocks_box(probe):
		return Reason.BLOCKED
	if not is_nan(feet.y):
		var body: AABB = AABB(Vector3(feet.x - 0.35, feet.y + 0.05, feet.z - 0.35), Vector3(0.7, 1.7, 0.7))
		if body.intersects(box.grow(-0.02)):
			return Reason.PLAYER
	return Reason.OK


## Уменьшает параллелепипед на m с каждой стороны, но не больше чем на 30 % размера по оси
## (тонкие плиты не «выворачиваются»). Касание деталей друг друга — не пересечение.
static func shrink(box: AABB, m: float) -> AABB:
	var out: AABB = box
	for a: int in 3:
		var d: float = minf(m, box.size[a] * 0.3)
		out.position[a] += d
		out.size[a] -= d * 2.0
	return out


func _overlaps_pieces(type: String, key: Vector4i, box: AABB) -> bool:
	var probe: AABB = shrink(box, BLOCK_SHRINK)
	var center: Vector3 = box.get_center()
	var door_pair: Vector4i = Vector4i(key.x, key.y, key.z, Slot.EDGE_X if key.w == Slot.DOOR_X else Slot.EDGE_Z)
	for i: int in p_type.size():
		if p_type[i].is_empty():
			continue
		var k: Vector4i = p_key[i]
		# Дверь стоит внутри своего проёма, это не пересечение.
		if type == "door" and k == door_pair:
			continue
		if is_door_slot(k.w) and type == "doorway" and Vector4i(k.x, k.y, k.z, Slot.EDGE_X if k.w == Slot.DOOR_X else Slot.EDGE_Z) == key:
			continue
		var other: AABB = piece_aabb(i)
		if absf(other.get_center().x - center.x) > 8.0 or absf(other.get_center().z - center.z) > 8.0:
			continue
		if probe.intersects(other):
			return true
	return false


# --- Подсказка места по взгляду --------------------------------------------

## Точка, куда смотрит игрок: первое пересечение луча с полом построек или рельефом,
## иначе точка на расстоянии dist. Не требует точного прицела.
func aim_point(eye: Vector3, dir: Vector3, dist: float) -> Vector3:
	var best: float = dist
	if dir.y < -0.01:
		for i: int in p_type.size():
			if p_type[i].is_empty() or p_key[i].w != Slot.CELL or p_type[i] == "roof":
				continue
			var top: float = defs.height_of(p_key[i].z)
			var t: float = (top - eye.y) / dir.y
			if t <= 0.0 or t >= best:
				continue
			var p: Vector3 = eye + dir * t
			var c: Vector2i = cell_of(p.x, p.z)
			if c.x == p_key[i].x and c.y == p_key[i].y:
				best = t
	if terrain != null:
		var t2: float = 0.25
		while t2 < best:
			var q: Vector3 = eye + dir * t2
			if q.y <= terrain.height_at(q.x, q.z):
				best = t2
				break
			t2 += 0.25
	return eye + dir * best


## Ближайшая к точке сторона клетки (0 С, 1 В, 2 Ю, 3 З).
func nearest_side(p: Vector3) -> int:
	var s: float = defs.grid
	var c: Vector2i = cell_of(p.x, p.z)
	var lx: float = p.x - float(c.x) * s
	var lz: float = p.z - float(c.y) * s
	var best: int = 0
	var best_d: float = lz
	if s - lx < best_d:
		best = 1
		best_d = s - lx
	if s - lz < best_d:
		best = 2
		best_d = s - lz
	if lx < best_d:
		best = 3
	return best


## Подбирает ключ детали по взгляду: клетка — где точка взгляда, высота — ближайший подходящий
## уровень постройки, сторона — ближайшая к точке (rot сдвигает сторону или задаёт направление).
## Результат и причина отказа — в out.
func suggest(type: String, mat: int, eye: Vector3, dir: Vector3, rot: int, feet: Vector3, out: Placement) -> void:
	out.type = type
	out.material = mat
	out.rot = posmod(rot, 4)
	out.depth = 1.0
	var kind: String = defs.slot_of(type)
	var dist: float = defs.aim_edge if kind == BuildingDefs.SLOT_EDGE or kind == BuildingDefs.SLOT_DOOR else defs.aim_cell
	var p: Vector3 = aim_point(eye, dir, dist)
	var c: Vector2i = cell_of(p.x, p.z)
	var ground_hy: int = hy_of(terrain.height_at(p.x, p.z)) if terrain != null else 0
	match kind:
		BuildingDefs.SLOT_CELL:
			if type == "foundation":
				var hy: int = foundation_hy(c.x, c.y)
				out.key = Vector4i(c.x, c.y, hy, Slot.CELL)
				out.depth = foundation_depth(c.x, c.y, hy)
			else:
				# Перекрытие и крыша: точка — где луч взгляда пересекает верх ближайших стен.
				var hit: Vector2 = _ceiling_hit(eye, dir)
				if hit.x < INF:
					var q: Vector3 = eye + dir * hit.x
					var qc: Vector2i = cell_of(q.x, q.z)
					out.key = Vector4i(qc.x, qc.y, int(hit.y), Slot.CELL)
				else:
					out.key = Vector4i(c.x, c.y, _ceiling_hy(c, p.y, ground_hy), Slot.CELL)
		BuildingDefs.SLOT_STAIRS:
			out.key = Vector4i(c.x, c.y, _floor_hy_below([c], p.y, ground_hy), Slot.STAIRS)
		BuildingDefs.SLOT_EDGE:
			# Базовая клетка — та сторона границы, где есть пол; «Повернуть» перебирает её стороны.
			var side0: int = nearest_side(p)
			var base: Vector2i = c
			if not _has_floor_any(c):
				var n: Vector2i = c + _side_dir(side0)
				if _has_floor_any(n):
					base = n
					side0 = posmod(side0 + 2, 4)
			var k0: Vector4i = edge_key(base.x, base.y, 0, posmod(side0 + out.rot, 4), false)
			var hy2: int = _floor_hy_below(edge_cells(k0), p.y, ground_hy)
			out.key = Vector4i(k0.x, k0.y, hy2, k0.w)
		BuildingDefs.SLOT_DOOR:
			out.key = _door_key_near(c, p, ground_hy)
	out.reason = check(type, mat, out.key, eye, feet)


func _has_floor_any(c: Vector2i) -> bool:
	for hy: int in _column(c.x, c.y, Slot.CELL):
		if has_floor(c.x, c.y, hy):
			return true
	return false


## Первое пересечение луча с плоскостью верха стен поблизости: (расстояние, hy верха) или (INF, 0).
func _ceiling_hit(eye: Vector3, dir: Vector3) -> Vector2:
	var best_t: float = INF
	var best_hy: int = 0
	if absf(dir.y) < 0.05:
		return Vector2(INF, 0.0)
	for i: int in p_type.size():
		if p_type[i].is_empty() or not is_edge_slot(p_key[i].w):
			continue
		var top_hy: int = p_key[i].z + defs.level_steps
		var t: float = (defs.height_of(top_hy) - eye.y) / dir.y
		if t <= 0.0 or t >= best_t or t > defs.build_range:
			continue
		# Плоскость засчитываем, только если точка над клеткой рядом с этой стеной.
		var q: Vector3 = eye + dir * t
		var qc: Vector2i = cell_of(q.x, q.z)
		for c: Vector2i in edge_cells(p_key[i]):
			if c == qc:
				best_t = t
				best_hy = top_hy
				break
	return Vector2(best_t, float(best_hy))


## Верхняя граница стен этой клетки, ближайшая к высоте y (для перекрытия и крыши).
func _ceiling_hy(c: Vector2i, y: float, ground_hy: int) -> int:
	var best: int = ground_hy + defs.level_steps
	var best_d: float = INF
	for side: int in 4:
		var k: Vector4i = edge_key(c.x, c.y, 0, side, false)
		for hy: int in _column(k.x, k.y, k.w):
			var top: int = hy + defs.level_steps
			var d: float = absf(defs.height_of(top) - y)
			if d < best_d:
				best_d = d
				best = top
	return best


## Самый высокий пол (фундамент/перекрытие) в клетках cells не выше y + 0,6 м.
func _floor_hy_below(cells: Array[Vector2i], y: float, ground_hy: int) -> int:
	var best: int = NO_HY
	for c: Vector2i in cells:
		for hy: int in _column(c.x, c.y, Slot.CELL):
			if has_floor(c.x, c.y, hy) and defs.height_of(hy) <= y + 0.6 and hy > best:
				best = hy
	if best == NO_HY:
		# Под точкой пола нет — берём самый низкий пол рядом или рельеф (деталь покажется красной).
		for c: Vector2i in cells:
			for hy: int in _column(c.x, c.y, Slot.CELL):
				if has_floor(c.x, c.y, hy) and (best == NO_HY or hy < best):
					best = hy
	return best if best != NO_HY else ground_hy


## Проём для двери: ближайшая к точке сторона клетки с проёмом на подходящей высоте.
func _door_key_near(c: Vector2i, p: Vector3, ground_hy: int) -> Vector4i:
	var first: int = nearest_side(p)
	for k: int in 4:
		var side: int = posmod(first + k, 4)
		var e: Vector4i = edge_key(c.x, c.y, 0, side, false)
		var best: int = NO_HY
		for hy: int in _column(e.x, e.y, e.w):
			var id: int = id_at(Vector4i(e.x, e.y, hy, e.w))
			if p_type[id] == "doorway" and defs.height_of(hy) <= p.y + 0.6 and hy > best:
				best = hy
		if best != NO_HY:
			var dk: Vector4i = edge_key(c.x, c.y, best, side, true)
			if not _by_key.has(dk):
				return dk
	return edge_key(c.x, c.y, ground_hy, first, true)


# --- Изменения --------------------------------------------------------------

## Ставит деталь без проверок (проверка — check()). Возвращает id.
func add_piece(type: String, mat: int, key: Vector4i, rot: int, owner_id: String, depth: float = -1.0, hp: float = -1.0) -> int:
	var id: int = p_type.size()
	p_type.append(type)
	p_mat.append(mat)
	p_key.append(key)
	p_rot.append(posmod(rot, 4))
	p_hp.append(hp if hp >= 0.0 else defs.max_hp(type, mat))
	p_owner.append(owner_id)
	var d: float = depth
	if d < 0.0:
		d = foundation_depth(key.x, key.y, key.z) if type == "foundation" else 1.0
	p_depth.append(d)
	p_open.append(0)
	p_code.append("")
	p_lock_auth.append(PackedStringArray())
	_by_key[key] = id
	var ck: Vector3i = Vector3i(key.x, key.y, key.w)
	var col: PackedInt32Array = _columns.get(ck, PackedInt32Array())
	col.append(key.z)
	_columns[ck] = col
	_alive += 1
	piece_added.emit(id)
	return id


## Удаляет деталь и всё, что без неё лишилось опоры. Возвращает список удалённых id.
func remove_piece(id: int) -> PackedInt32Array:
	var removed: PackedInt32Array = PackedInt32Array()
	if not is_alive(id):
		return removed
	_remove_one(id)
	removed.append(id)
	var changed: bool = true
	while changed:
		changed = false
		for i: int in p_type.size():
			if not p_type[i].is_empty() and not is_supported(p_type[i], p_key[i]):
				_remove_one(i)
				removed.append(i)
				changed = true
	return removed


func _remove_one(id: int) -> void:
	var key: Vector4i = p_key[id]
	_by_key.erase(key)
	var ck: Vector3i = Vector3i(key.x, key.y, key.w)
	var col: PackedInt32Array = _columns.get(ck, PackedInt32Array())
	var at: int = col.find(key.z)
	if at >= 0:
		col.remove_at(at)
	if col.is_empty():
		_columns.erase(ck)
	else:
		_columns[ck] = col
	p_type[id] = ""
	p_code[id] = ""
	p_lock_auth[id] = PackedStringArray()
	_alive -= 1
	piece_removed.emit(id)


func set_material(id: int, mat: int) -> void:
	p_mat[id] = mat
	p_hp[id] = defs.max_hp(p_type[id], mat)
	piece_changed.emit(id)


func set_hp(id: int, hp: float) -> void:
	p_hp[id] = clampf(hp, 0.0, max_hp(id))
	piece_changed.emit(id)


## Урон детали (износ). Возвращает удалённые детали, если прочность кончилась.
func damage(id: int, amount: float) -> PackedInt32Array:
	if not is_alive(id):
		return PackedInt32Array()
	p_hp[id] -= amount
	if p_hp[id] <= 0.0:
		return remove_piece(id)
	piece_changed.emit(id)
	return PackedInt32Array()


# --- Двери и замки ----------------------------------------------------------

## Может ли игрок who открыть дверь (без замка — любой, с замком — только знающий код).
func can_use_door(id: int, who: String) -> bool:
	if not is_door(id):
		return false
	return p_code[id].is_empty() or p_lock_auth[id].has(who)


## Открыть/закрыть дверь. false — дверь заперта для who.
func toggle_door(id: int, who: String) -> bool:
	if not can_use_door(id, who):
		return false
	p_open[id] = 0 if p_open[id] != 0 else 1
	piece_changed.emit(id)
	return true


static func is_valid_code(code: String) -> bool:
	return code.length() == 4 and code.is_valid_int() and not code.begins_with("-") and not code.begins_with("+")


## Поставить замок с кодом; who сразу знает код. false — нет двери, уже есть замок или код неверный.
func attach_lock(id: int, who: String, code: String) -> bool:
	if not is_door(id) or has_lock(id) or not is_valid_code(code):
		return false
	p_code[id] = code
	p_lock_auth[id] = PackedStringArray([who])
	p_open[id] = 0
	piece_changed.emit(id)
	return true


## Ввод кода: верный — who запоминается замком. Возвращает true, если код верный.
func enter_code(id: int, who: String, code: String) -> bool:
	if not has_lock(id) or code != p_code[id]:
		return false
	if not p_lock_auth[id].has(who):
		p_lock_auth[id].append(who)
	return true


## Сменить код может только тот, кто его знает; остальные «забываются».
func change_code(id: int, who: String, code: String) -> bool:
	if not has_lock(id) or not p_lock_auth[id].has(who) or not is_valid_code(code):
		return false
	p_code[id] = code
	p_lock_auth[id] = PackedStringArray([who])
	piece_changed.emit(id)
	return true


# --- Прицел и поверхности ---------------------------------------------------

## Деталь на луче взгляда в пределах reach (двери в приоритете перед своим проёмом) или -1.
func find_target(eye: Vector3, dir: Vector3, reach: float) -> int:
	var best: int = -1
	var best_t: float = reach
	for i: int in p_type.size():
		if p_type[i].is_empty():
			continue
		var box: AABB = piece_aabb(i)
		var c: Vector3 = box.get_center()
		if absf(c.x - eye.x) > reach + 4.0 or absf(c.z - eye.z) > reach + 4.0:
			continue
		var t: float = ray_aabb(eye, dir, box)
		if is_door_slot(p_key[i].w):
			t -= 0.05
		if t < best_t:
			best_t = t
			best = i
	return best


## Пересечение луча с параллелепипедом: расстояние до входа (0, если начало внутри) или INF.
static func ray_aabb(o: Vector3, d: Vector3, box: AABB) -> float:
	var tmin: float = 0.0
	var tmax: float = INF
	var lo: Vector3 = box.position
	var hi: Vector3 = box.end
	for a: int in 3:
		if absf(d[a]) < 1e-6:
			if o[a] < lo[a] or o[a] > hi[a]:
				return INF
			continue
		var inv: float = 1.0 / d[a]
		var t1: float = (lo[a] - o[a]) * inv
		var t2: float = (hi[a] - o[a]) * inv
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return INF
	return tmin


## Высота поверхности для установки объекта в точке: верх пола постройки (не выше y_max) или рельеф.
func surface_height(x: float, z: float, y_max: float) -> float:
	var h: float = terrain.height_at(x, z) if terrain != null else 0.0
	var c: Vector2i = cell_of(x, z)
	for hy: int in _column(c.x, c.y, Slot.CELL):
		var top: float = defs.height_of(hy)
		if has_floor(c.x, c.y, hy) and top <= y_max and top > h:
			h = top
	return h


## Пересекается ли объём box с деталями (для установки ящиков и костров внутри дома).
func blocks_box(box: AABB) -> bool:
	for i: int in p_type.size():
		if p_type[i].is_empty():
			continue
		if piece_aabb(i).grow(-0.02).intersects(box):
			return true
	return false


## Детали в радиусе (по горизонтали) от точки — для права владения и обслуживания.
func ids_within(center: Vector3, radius: float, out: PackedInt32Array) -> void:
	out.clear()
	var r2: float = radius * radius
	for i: int in p_type.size():
		if p_type[i].is_empty():
			continue
		var c: Vector3 = piece_aabb(i).get_center()
		var dx: float = c.x - center.x
		var dz: float = c.z - center.z
		if dx * dx + dz * dz <= r2:
			out.append(i)


# --- Сохранение -------------------------------------------------------------

func clear() -> void:
	p_type.clear()
	p_mat.clear()
	p_key.clear()
	p_rot.clear()
	p_hp.clear()
	p_owner.clear()
	p_depth.clear()
	p_open.clear()
	p_code.clear()
	p_lock_auth.clear()
	_by_key.clear()
	_columns.clear()
	_alive = 0
	cleared.emit()


## Детали: [тип, материал, cx, cz, hy, слот, поворот, прочность, владелец, глубина, открыта, код, [знают код]].
func to_dict() -> Dictionary:
	var list: Array = []
	for i: int in p_type.size():
		if p_type[i].is_empty():
			continue
		var k: Vector4i = p_key[i]
		list.append([p_type[i], defs.material_order[p_mat[i]], k.x, k.y, k.z, k.w, p_rot[i], snappedf(p_hp[i], 0.1),
			p_owner[i], snappedf(p_depth[i], 0.01), p_open[i], p_code[i], Array(p_lock_auth[i])])
	return {"pieces": list}


## Загружает детали (номера id пересчитываются подряд). Возвращает число пропущенных записей.
func from_dict(d: Dictionary) -> int:
	clear()
	var skipped: int = 0
	var list: Variant = d.get("pieces", [])
	if typeof(list) != TYPE_ARRAY:
		return 0
	for e: Variant in list:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() < 13:
			skipped += 1
			continue
		var a: Array = e
		var type: String = String(a[0])
		var mat: int = defs.material_index(String(a[1]))
		var key: Vector4i = Vector4i(int(a[2]), int(a[3]), int(a[4]), int(a[5]))
		if not defs.allows(type, mat) or _by_key.has(key) or slot_for(defs.slot_of(type), along_x(key.w)) != key.w:
			skipped += 1
			continue
		var id: int = add_piece(type, mat, key, int(a[6]), String(a[8]), maxf(float(a[9]), 0.1), clampf(float(a[7]), 1.0, defs.max_hp(type, mat)))
		p_open[id] = 1 if int(a[10]) != 0 else 0
		var code: String = String(a[11])
		if is_valid_code(code) and is_door(id):
			p_code[id] = code
			p_lock_auth[id] = PackedStringArray(a[12] as Array) if typeof(a[12]) == TYPE_ARRAY else PackedStringArray()
		if not p_code[id].is_empty() or p_open[id] != 0:
			piece_changed.emit(id)
	# Детали без опоры (повреждённый файл) не оставляем висеть в воздухе.
	var changed: bool = true
	while changed:
		changed = false
		for i: int in p_type.size():
			if not p_type[i].is_empty() and not is_supported(p_type[i], p_key[i]):
				_remove_one(i)
				skipped += 1
				changed = true
	return skipped
