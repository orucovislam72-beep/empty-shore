extends GutTest


func test_same_seed_same_heights() -> void:
	var a: TerrainMath = TerrainMath.new(42)
	var b: TerrainMath = TerrainMath.new(42)
	assert_eq(a.build_heights(64.0, 17), b.build_heights(64.0, 17))


func test_different_seed_different_heights() -> void:
	var a: TerrainMath = TerrainMath.new(1)
	var b: TerrainMath = TerrainMath.new(2)
	assert_ne(a.build_heights(64.0, 17), b.build_heights(64.0, 17))


func test_spawn_area_is_flat() -> void:
	var t: TerrainMath = TerrainMath.new(1337, 14.0, 0.008, 4, 12.0)
	var h0: float = t.height_at(0.0, 0.0)
	assert_almost_eq(t.height_at(5.0, 5.0), h0, 0.001)
	assert_almost_eq(t.height_at(-8.0, 3.0), h0, 0.001)


func test_heights_within_amplitude() -> void:
	var t: TerrainMath = TerrainMath.new(7, 10.0)
	for h: float in t.build_heights(256.0, 33):
		assert_true(absf(h) <= 10.0 + 0.001)


func test_config_from_data_file() -> void:
	var cfg: Dictionary = JsonData.load_dict("res://tests/data/small_map.json")
	var t: TerrainMath = TerrainMath.from_config(cfg)
	assert_eq(t.seed_value, int(cfg["seed"]))
