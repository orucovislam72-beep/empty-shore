extends GutTest
## Смена дня и ночи: ход времени, смена суток, солнце, интерполяция освещения.

var c: DayNightCycle


func before_each() -> void:
	c = DayNightCycle.new()
	c.configure({"day_length_min": 24.0, "start_hour": 8.0, "sunrise_hour": 6.0, "sunset_hour": 18.0,
		"max_sun_elevation_deg": 60.0, "shadows_min_elevation_deg": 5.0,
		"keys": [
			{"hour": 0.0, "sun": 0.0, "ambient": 0.2, "sky_top": "#000000"},
			{"hour": 12.0, "sun": 1.0, "ambient": 0.4, "sky_top": "#ffffff"},
		]})


func test_time_advances_one_hour_per_real_minute() -> void:
	c.tick(60.0)
	assert_almost_eq(c.time_hours, 9.0, 0.0001)


func test_day_wraps() -> void:
	c.tick(60.0 * 20.0)
	assert_eq(c.day, 2)
	assert_almost_eq(c.time_hours, 4.0, 0.0001)
	assert_true(c.is_night())


func test_sun_elevation() -> void:
	c.time_hours = 12.0
	assert_almost_eq(c.sun_elevation_deg(), 60.0, 0.001)
	c.time_hours = 6.0
	assert_almost_eq(c.sun_elevation_deg(), 0.0, 0.001)
	c.time_hours = 0.0
	assert_lt(c.sun_elevation_deg(), 0.0)
	assert_false(c.shadows_allowed())


func test_sample_interpolates_and_wraps() -> void:
	var smp: DayNightCycle.Sample = DayNightCycle.Sample.new()
	c.time_hours = 6.0
	c.sample(smp)
	assert_almost_eq(smp.sun_energy, 0.5, 0.0001)
	assert_almost_eq(smp.ambient_energy, 0.3, 0.0001)
	assert_almost_eq(smp.sky_top.r, 0.5, 0.01)
	c.time_hours = 18.0
	c.sample(smp)
	assert_almost_eq(smp.sun_energy, 0.5, 0.0001, "интерполяция через полночь")


func test_total_hours_roundtrip() -> void:
	c.tick(60.0 * 30.0)
	var h: float = c.total_hours()
	var c2: DayNightCycle = DayNightCycle.new()
	c2.configure({"keys": [{"hour": 0.0}]})
	c2.set_total_hours(h)
	assert_eq(c2.day, c.day)
	assert_almost_eq(c2.time_hours, c.time_hours, 0.0001)


func test_default_data_has_night() -> void:
	var d: DayNightCycle = DayNightCycle.new()
	d.configure(JsonData.load_dict(DayNightCycle.DEFAULT_PATH))
	var smp: DayNightCycle.Sample = DayNightCycle.Sample.new()
	d.time_hours = 1.0
	d.sample(smp)
	assert_eq(smp.sun_energy, 0.0)
	assert_gt(smp.ambient_energy, 0.1, "ночью картинка остаётся читаемой")
	d.time_hours = 12.0
	d.sample(smp)
	assert_eq(smp.sun_energy, 1.0)
