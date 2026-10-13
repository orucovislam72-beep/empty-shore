extends GutTest
## Ресурсные узлы: детерминированная расстановка, поиск цели, добыча, восстановление, сохранение.

const CFG: Dictionary = {
	"seed_offset": 7, "reach_m": 3.0, "spawn_clear_radius_m": 6.0, "min_slope_free": 0.9, "water_margin_m": 0.4,
	"types": [
		{"id": "tree", "item": "wood", "count": 60, "stock": 20, "yield": 5, "respawn_s": 10.0, "radius": 0.9, "hit_height": 1.3},
		{"id": "rock", "item": "stone", "count": 20, "stock": 12, "yield": 4, "respawn_s": 10.0, "radius": 1.1, "hit_height": 0.4},
	],
}

var terrain: TerrainMath


func before_each() -> void:
	terrain = TerrainMath.new(42, 14.0, 0.008, 4, 12.0)


func _gen() -> ResourceField:
	return ResourceField.generate(CFG, terrain, 128.0, -4.0)


func test_generation_is_deterministic() -> void:
	var a: ResourceField = _gen()
	var b: ResourceField = _gen()
	assert_eq(a.size(), 80)
	assert_eq(a.positions, b.positions)
	assert_eq(a.layout_hash, b.layout_hash)
	var other: ResourceField = ResourceField.generate(CFG, TerrainMath.new(43), 128.0, -4.0)
	assert_ne(a.layout_hash, other.layout_hash, "другой seed — другая расстановка")


func test_nodes_avoid_water_and_spawn() -> void:
	var f: ResourceField = _gen()
	for i: int in f.size():
		var p: Vector3 = f.positions[i]
		assert_gt(p.y, -4.0, "узел %d не под водой" % i)
		assert_gt(Vector2(p.x, p.z).length(), 6.0, "узел %d не в точке появления" % i)
		assert_almost_eq(p.y, terrain.height_at(p.x, p.z), 0.001)


func test_find_target_on_ray_and_in_reach() -> void:
	var f: ResourceField = _gen()
	var i: int = 0
	var c: Vector3 = f.hit_center(i)
	var origin: Vector3 = c + Vector3(0.0, 0.0, 2.5)
	assert_eq(f.find_target(origin, Vector3(0.0, 0.0, -1.0)), i, "смотрим прямо на узел")
	assert_eq(f.find_target(origin, Vector3(0.0, 0.0, 1.0)), -1, "отвернулись")
	var far: Vector3 = c + Vector3(0.0, 0.0, 6.0)
	assert_eq(f.find_target(far, Vector3(0.0, 0.0, -1.0)), -1, "слишком далеко")
	var off: Vector3 = origin + Vector3(0.5, 0.0, 0.0)
	assert_eq(f.find_target(off, Vector3(0.0, 0.0, -1.0)), i, "не требуем точного попадания")


func test_hit_depletes_and_respawns() -> void:
	var f: ResourceField = _gen()
	watch_signals(f)
	assert_eq(f.hit(0, 1.0), 5)
	assert_eq(f.hit(0, 2.0), 10)
	assert_eq(f.hit(0, 2.0), 5, "не больше остатка")
	assert_false(f.is_available(0))
	assert_eq(f.hit(0, 1.0), 0)
	assert_eq(f.hit(1, 0.0), 0, "этим инструментом не добыть")
	assert_signal_emitted(f, "node_changed")
	var c: Vector3 = f.hit_center(0)
	assert_ne(f.find_target(c + Vector3(0, 0, 2), Vector3(0, 0, -1)), 0, "истощённый узел не цель")
	f.tick(5.0)
	assert_false(f.is_available(0))
	f.tick(6.0)
	assert_true(f.is_available(0), "восстановился")
	assert_eq(f.remaining[0], 20)


func test_minimum_one_per_hit() -> void:
	var f: ResourceField = _gen()
	assert_eq(f.hit(0, 0.05), 1)


func test_save_roundtrip_and_layout_change() -> void:
	var f: ResourceField = _gen()
	f.hit(0, 10.0)
	f.hit(3, 1.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(f.to_dict()))
	assert_eq((d["changed"] as Array).size(), 2, "сохраняются только изменённые узлы")
	var g: ResourceField = _gen()
	assert_true(g.from_dict(d))
	assert_eq(g.remaining[0], 0)
	assert_eq(g.remaining[3], 15)
	g.tick(11.0)
	assert_true(g.is_available(0), "таймер восстановления тоже сохранился")
	var other: ResourceField = ResourceField.generate(CFG, TerrainMath.new(99), 128.0, -4.0)
	assert_false(other.from_dict(d), "чужая расстановка — сброс")
