class_name ChunkBuilder
extends RefCounted
## Данные чанка для отрисовки и столкновений — чистые вычисления над массивами (без дерева сцены),
## выполняются в рабочем потоке WorkerThreadPool. Координаты — относительно угла чанка.
## Результат: heights (для HeightMapShape3D), verts/normals/colors (рельеф), node_bufs/node_inst (буферы
## MultiMesh узлов по типам и номер экземпляра каждого узла чанка), loot_bufs/loot_inst (точки лута), grass.


static func build(gen: WorldGen, c: Vector2i, res: int, cfg: Dictionary, field: ResourceField, boxes: WorldContainers) -> Dictionary:
	var g: ChunkGrid = gen.grid
	var o: Vector2 = g.origin_of(c)
	var step: float = g.chunk_m / float(res - 1)
	var cols: Dictionary = cfg.get("colors", {})
	var c_coast: Color = _col(cols, "coast", Color(0.66, 0.61, 0.46))
	var c_seabed: Color = _col(cols, "seabed", Color(0.4, 0.42, 0.36))
	var c_rock: Color = _col(cols, "rock", Color(0.42, 0.41, 0.4))
	var c_snow: Color = _col(cols, "snow", Color(0.86, 0.88, 0.9))
	var biome_cols: Array[Color] = [c_coast, _col(cols, "plain", Color(0.5, 0.58, 0.3)), _col(cols, "forest", Color(0.27, 0.42, 0.22)), _col(cols, "mountain", Color(0.47, 0.46, 0.44))]
	var snow_h: float = JsonData.get_float(cfg, "snow_above_m", 38.0)
	var water: float = gen.water_level

	# Высоты с рамкой в одну клетку (для нормалей на стыках чанков).
	var rb: int = res + 2
	var hb: PackedFloat32Array = PackedFloat32Array()
	hb.resize(rb * rb)
	var biomes: PackedByteArray = PackedByteArray()
	biomes.resize(res * res)
	for zi: int in rb:
		for xi: int in rb:
			var x: float = o.x + (xi - 1) * step
			var z: float = o.y + (zi - 1) * step
			var h: float = gen.height_at(x, z)
			hb[zi * rb + xi] = h
			if xi >= 1 and zi >= 1 and xi <= res and zi <= res:
				biomes[(zi - 1) * res + (xi - 1)] = gen.biome_after_height(x, z, h)
	var heights: PackedFloat32Array = PackedFloat32Array()
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	heights.resize(res * res)
	verts.resize(res * res)
	normals.resize(res * res)
	colors.resize(res * res)
	for zi: int in res:
		for xi: int in res:
			var bi: int = (zi + 1) * rb + (xi + 1)
			var h: float = hb[bi]
			var i: int = zi * res + xi
			heights[i] = h
			verts[i] = Vector3(xi * step, h, zi * step)
			var n: Vector3 = Vector3(hb[bi - 1] - hb[bi + 1], 2.0 * step, hb[bi - rb] - hb[bi + rb]).normalized()
			normals[i] = n
			var col: Color = biome_cols[biomes[i]]
			if h < water:
				col = c_coast.lerp(c_seabed, clampf(-h / 4.0, 0.0, 1.0))
			else:
				col = col.lerp(c_rock, clampf((1.0 - n.y) * 5.0 - 0.4, 0.0, 1.0))
				if h > snow_h:
					col = col.lerp(c_snow, clampf((h - snow_h) / 6.0, 0.0, 1.0))
			colors[i] = col

	# Узлы чанка: буфер MultiMesh на тип, номер экземпляра на узел.
	var ci: int = g.index_of_coord(c)
	var rr: Vector2i = field.chunk_range(ci)
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(field.types.size())
	var node_inst: PackedInt32Array = PackedInt32Array()
	node_inst.resize(rr.y)
	for local: int in rr.y:
		var t: int = field.type_index[rr.x + local]
		node_inst[local] = counts[t]
		counts[t] += 1
	var node_bufs: Array = []
	for t: int in field.types.size():
		var buf: PackedFloat32Array = PackedFloat32Array()
		buf.resize(counts[t] * 12)
		node_bufs.append(buf)
	var origin3: Vector3 = Vector3(o.x, 0.0, o.y)
	for local: int in rr.y:
		var i: int = rr.x + local
		var s: float = field.scales[i]
		WorldMeshes.write_transform(node_bufs[field.type_index[i]], node_inst[local], Basis(Vector3.UP, field.yaws[i]).scaled(Vector3(s, s, s)), field.positions[i] - origin3)

	# Точки лута.
	var loot_bufs: Array = []
	var loot_inst: PackedInt32Array = PackedInt32Array()
	var lcounts: PackedInt32Array = PackedInt32Array()
	lcounts.resize(boxes.types.size())
	var lfirst: int = int(boxes.chunk_first.get(ci, 0))
	var lcount: int = int(boxes.chunk_count.get(ci, 0))
	loot_inst.resize(lcount)
	for l: int in lcount:
		var t2: int = boxes.p_type[lfirst + l]
		loot_inst[l] = lcounts[t2]
		lcounts[t2] += 1
	for t3: int in boxes.types.size():
		var lb: PackedFloat32Array = PackedFloat32Array()
		lb.resize(lcounts[t3] * 12)
		loot_bufs.append(lb)
	for l2: int in lcount:
		var pi: int = lfirst + l2
		WorldMeshes.write_transform(loot_bufs[boxes.p_type[pi]], loot_inst[l2], Basis(Vector3.UP, boxes.p_yaw[pi]), boxes.p_pos[pi] - origin3)

	# Трава: число пучков фиксировано, лишние (биом, вода, склон) — нулевым масштабом.
	var gcfg: Dictionary = cfg.get("grass", {})
	var tufts: int = JsonData.get_int(gcfg, "tufts_per_chunk", 260)
	var gdens: Dictionary = gcfg.get("biome_density", {})
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = gen.seed_value * 2654435761 + ci * 40503 + 9
	var grass: PackedFloat32Array = PackedFloat32Array()
	grass.resize(tufts * 12)
	for t4: int in tufts:
		var lx: float = rng.randf() * g.chunk_m
		var lz: float = rng.randf() * g.chunk_m
		var roll: float = rng.randf()
		var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
		var xi2: int = clampi(int(round(lx / step)), 0, res - 1)
		var zi2: int = clampi(int(round(lz / step)), 0, res - 1)
		var b: int = biomes[zi2 * res + xi2]
		var y: float = _sample(heights, res, step, lx, lz)
		if y < water + 0.2 or roll > JsonData.get_float(gdens, WorldGen.biome_id(b), 1.0) or normals[zi2 * res + xi2].y < 0.8:
			basis = Basis.from_scale(Vector3.ZERO)
		WorldMeshes.write_transform(grass, t4, basis, Vector3(lx, y, lz))

	return {
		"heights": heights, "verts": verts, "normals": normals, "colors": colors,
		"node_bufs": node_bufs, "node_inst": node_inst, "loot_bufs": loot_bufs, "loot_inst": loot_inst, "grass": grass,
	}


## Высота внутри чанка билинейно по сетке (как у треугольников рельефа — с точностью до диагонали).
static func _sample(heights: PackedFloat32Array, res: int, step: float, lx: float, lz: float) -> float:
	var fx: float = clampf(lx / step, 0.0, res - 1.001)
	var fz: float = clampf(lz / step, 0.0, res - 1.001)
	var x0: int = int(fx)
	var z0: int = int(fz)
	var tx: float = fx - x0
	var tz: float = fz - z0
	var h00: float = heights[z0 * res + x0]
	var h10: float = heights[z0 * res + x0 + 1]
	var h01: float = heights[(z0 + 1) * res + x0]
	var h11: float = heights[(z0 + 1) * res + x0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


static func _col(cols: Dictionary, k: String, fallback: Color) -> Color:
	var a: Variant = cols.get(k)
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback
