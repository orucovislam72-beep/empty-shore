extends GutTest
## Размещаемые объекты: установка, расстояние, станции, топливо костра, сохранение.

var d: Deployables


func before_each() -> void:
	d = Deployables.new()
	d.configure({"place_distance_m": 2.0, "min_spacing_m": 1.5, "interact_radius_m": 2.5, "types": {
		"campfire": {"station": "campfire", "station_radius": 3.0, "initial_fuel_s": 60.0, "fuel_per_wood_s": 30.0, "max_fuel_s": 300.0, "refuel_wood": 5},
		"workbench_1": {"station": "workbench_1", "station_radius": 3.0},
	}})


func test_place_and_spacing() -> void:
	assert_eq(d.place("campfire", Vector3.ZERO, 0.0), 0)
	assert_eq(d.place("campfire", Vector3(1.0, 0, 0), 0.0), -1, "слишком близко")
	assert_eq(d.place("unknown", Vector3(10, 0, 0), 0.0), -1)
	assert_eq(d.place("workbench_1", Vector3(5, 0, 0), 0.0), 1)


func test_stations_only_lit_campfire() -> void:
	d.place("campfire", Vector3.ZERO, 0.0)
	var out: PackedStringArray = PackedStringArray()
	d.stations_near(Vector3(1, 0, 1), out)
	assert_true(out.has("campfire"))
	d.tick(61.0)
	assert_false(d.is_lit(0))
	d.stations_near(Vector3(1, 0, 1), out)
	assert_false(out.has("campfire"), "погасший костёр — не станция")
	d.stations_near(Vector3(10, 0, 0), out)
	assert_true(out.is_empty(), "далеко")


func test_refuel_limits() -> void:
	d.place("campfire", Vector3.ZERO, 0.0)
	assert_eq(d.wood_wanted(0), 5)
	d.add_fuel(0, 5)
	assert_almost_eq(d.fuel[0], 210.0, 0.001)
	assert_eq(d.wood_wanted(0), 3, "до максимума 300 с — ещё 3 полена")
	d.add_fuel(0, 10)
	assert_eq(d.fuel[0], 300.0)
	assert_eq(d.wood_wanted(0), 0)


func test_roundtrip() -> void:
	d.place("campfire", Vector3(1, 2, 3), 1.5)
	d.place("workbench_1", Vector3(9, 0, 0), 0.0)
	var copy: Deployables = Deployables.new()
	copy.configure({"types": {"campfire": {"fuel_per_wood_s": 30.0}, "workbench_1": {}}})
	watch_signals(copy)
	copy.from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	assert_eq(copy.size(), 2)
	assert_eq(copy.positions[0], Vector3(1, 2, 3))
	assert_almost_eq(copy.fuel[0], 60.0, 0.01)
	assert_signal_emit_count(copy, "added", 2)
