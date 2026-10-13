extends GutTest
## Мир этапа 3: детерминированный генератор по seed, четыре биома, вода, место высадки на берегу,
## точки побережья, раскладка узлов и точек лута по чанкам.

var cfg: Dictionary


func before_all() -> void:
	cfg = JsonData.load_dict(WorldGen.DEFAULT_PATH)


func test_map_size_within_brief() -> void:
	var g: WorldGen = WorldGen.new(cfg)
	var km2: float = g.grid.size_m * g.grid.size_m / 1e6
	assert_between(km2, 1.0, 2.0, "карта 1–2 км²")
	assert_eq(g.grid.count(), g.grid.n * g.grid.n)
	assert_eq(g.grid.chunk_m, 64.0)


func test_same_seed_same_world_and_different_seed_differs() -> void:
	var a: WorldGen = WorldGen.new(cfg)
	var b: WorldGen = WorldGen.new(cfg)
	var c2: Dictionary = cfg.duplicate(true)
	c2["seed"] = 4242
	var c: WorldGen = WorldGen.new(c2)
	var diff: int = 0
	for i: int in 50:
		var x: float = -500.0 + i * 20.0
		var z: float = 300.0 - i * 13.0
		assert_eq(a.height_at(x, z), b.height_at(x, z))
		assert_eq(a.biome_at(x, z), b.biome_at(x, z))
		if absf(a.height_at(x, z) - c.height_at(x, z)) > 0.5:
			diff += 1
	assert_gt(diff, 25, "другой seed — другой рельеф")
	assert_eq(a.landing, b.landing)


func test_clone_matches_original() -> void:
	var a: WorldGen = WorldGen.new(cfg)
	var b: WorldGen = a.clone()
	for i: int in 20:
		var x: float = a.landing.x + i * 7.0
		var z: float = a.landing.z - i * 11.0
		assert_eq(a.height_at(x, z), b.height_at(x, z))


func test_four_biomes_and_water_present() -> void:
	var g: WorldGen = WorldGen.new(cfg)
	var sh: Dictionary = g.biome_shares(16.0)
	for b: String in WorldGen.BIOME_IDS:
		assert_gt(float(sh[b]), 0.08, "биом %s занимает заметную долю суши" % b)
	var land_km2: float = float(sh["land_cells"]) * 256.0 / 1e6
	assert_between(land_km2, 0.6, 1.6, "суша острова")
	assert_true(g.is_water(g.grid.half - 5.0, g.grid.half - 5.0), "угол карты — море")
	assert_true(g.is_water(-g.grid.half + 5.0, 0.0), "край карты — море")


func test_landing_is_flat_beach_above_water() -> void:
	var g: WorldGen = WorldGen.new(cfg)
	var l: Vector3 = g.landing
	assert_gt(l.y, g.water_level + 0.5, "высадка над водой")
	assert_lt(l.y, g.water_level + 4.0, "высадка у берега")
	for a: int in 8:
		var d: Vector2 = Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * 8.0
		assert_almost_eq(g.height_at(l.x + d.x, l.z + d.y), l.y, 0.01, "площадка ровная")
	# Море рядом: в 60 м к югу (от центра острова) — вода.
	var out: Vector2 = Vector2(l.x, l.z).normalized() * 60.0
	assert_true(g.is_water(l.x + out.x, l.z + out.y), "море рядом с местом высадки")


func test_coast_points_on_shore() -> void:
	var g: WorldGen = WorldGen.new(cfg)
	assert_gt(g.coast_points.size(), 10)
	for p: Vector3 in g.coast_points:
		assert_gt(p.y, g.water_level + 0.4)
		assert_lt(p.y, g.water_level + 6.1)
		assert_eq(g.biome_at(p.x, p.z), WorldGen.Biome.COAST, "точка на побережье")


func test_chunk_grid_keys_round_trip() -> void:
	var grid: ChunkGrid = ChunkGrid.new(1280.0, 64.0)
	assert_eq(grid.n, 20)
	var c: Vector2i = grid.coord_of(-639.0, 639.0)
	assert_eq(c, Vector2i(0, 19))
	assert_eq(ChunkGrid.parse_key(ChunkGrid.key(c)), c)
	assert_eq(grid.coord_of_index(grid.index_of_coord(Vector2i(7, 3))), Vector2i(7, 3))
	assert_eq(ChunkGrid.parse_key("x,1"), Vector2i(-1, -1))
	assert_almost_eq(grid.distance_to(Vector2i(10, 10), 0.0, 0.0), 0.0, 0.001)
	assert_almost_eq(grid.distance_to(Vector2i(12, 10), 0.0, 0.0), 64.0, 0.001)


func test_world_resource_layout_is_deterministic_and_chunked() -> void:
	var g: WorldGen = WorldGen.new(cfg)
	var rcfg: Dictionary = JsonData.load_dict(ResourceField.DEFAULT_PATH)
	var t0: int = Time.get_ticks_msec()
	var a: ResourceField = ResourceField.generate_world(rcfg, g)
	var ms: int = Time.get_ticks_msec() - t0
	gut.p("раскладка узлов острова: %d узлов за %d мс" % [a.size(), ms])
	var b: ResourceField = ResourceField.generate_world(rcfg, g.clone())
	assert_gt(a.size(), 3000)
	assert_eq(a.size(), b.size())
	assert_eq(a.layout_hash, b.layout_hash)
	assert_eq(a.positions, b.positions)
	# Узлы чанка идут подряд и лежат в своём чанке.
	var checked: int = 0
	for ci: Variant in a.chunk_first:
		var r: Vector2i = a.chunk_range(int(ci))
		for k: int in r.y:
			var i: int = r.x + k
			assert_eq(a.node_chunk[i], int(ci))
			assert_eq(a.node_local[i], k)
			assert_eq(g.grid.index_of(a.positions[i].x, a.positions[i].z), int(ci))
			checked += 1
	assert_eq(checked, a.size())
	# Лес гуще равнины; деревья не в воде и не на площадке высадки.
	var forest: int = 0
	var plain: int = 0
	for i: int in a.size():
		var p: Vector3 = a.positions[i]
		assert_gt(p.y, g.water_level)
		assert_gt(Vector2(p.x - g.landing.x, p.z - g.landing.z).length(), 15.0)
		if a.item_of(i) == "wood":
			var bi: int = g.biome_at(p.x, p.z)
			if bi == WorldGen.Biome.FOREST:
				forest += 1
			elif bi == WorldGen.Biome.PLAIN:
				plain += 1
	assert_gt(forest, plain * 3, "деревьев в лесу больше, чем на равнине")


func test_wood_and_stone_reachable_from_landing() -> void:
	# Приёмка этапа 1 на новой карте: дерево и камень недалеко от места высадки.
	var g: WorldGen = WorldGen.new(cfg)
	var a: ResourceField = ResourceField.generate_world(JsonData.load_dict(ResourceField.DEFAULT_PATH), g)
	var best: Dictionary = {"wood": INF, "stone": INF, "berries": INF}
	for i: int in a.size():
		var it: String = a.item_of(i)
		if best.has(it):
			best[it] = minf(float(best[it]), a.positions[i].distance_to(g.landing))
	gut.p("ближайшие к высадке: %s" % [best])
	assert_lt(float(best["wood"]), 80.0)
	assert_lt(float(best["stone"]), 120.0)


func test_loot_points_by_chunk() -> void:
	var g: WorldGen = WorldGen.new(cfg)
	var lcfg: Dictionary = JsonData.load_dict(WorldContainers.DEFAULT_PATH)
	var a: WorldContainers = WorldContainers.new()
	a.configure(lcfg, ItemDB.load_default(), LootTable.load_default())
	a.generate_points(lcfg, g)
	var b: WorldContainers = WorldContainers.new()
	b.configure(lcfg, ItemDB.load_default(), LootTable.load_default())
	b.generate_points(lcfg, g.clone())
	assert_gt(a.point_count(), 40)
	assert_eq(a.p_pos, b.p_pos)
	assert_eq(a.layout_hash, b.layout_hash)
	var kinds: Dictionary = {}
	for i: int in a.point_count():
		kinds[a.point_type_id(i)] = true
		assert_gt(a.p_pos[i].y, g.water_level)
	assert_eq(kinds.size(), 3, "ящики, бочки и военные ящики")
