extends GutTest

const QUALITY: String = "res://data/balance/quality_presets.json"

var s: GameSettings


func before_each() -> void:
	s = GameSettings.new()
	s.configure(JsonData.load_dict(QUALITY))


func test_presets_loaded_from_data() -> void:
	assert_eq(s.preset_names(), ["low", "medium", "high"])


func test_apply_preset_sets_values() -> void:
	assert_true(s.apply_preset("low"))
	assert_eq(s.quality_preset, "low")
	assert_almost_eq(s.render_scale, 0.6, 0.001)
	assert_false(s.shadows)


func test_unknown_preset_rejected() -> void:
	s.apply_preset("high")
	assert_false(s.apply_preset("ultra"))
	assert_eq(s.quality_preset, "high")


func test_battery_saver_caps_effective_values() -> void:
	s.apply_preset("high")
	s.fps_limit = 60
	s.battery_saver = true
	assert_eq(s.effective_fps_limit(), 30)
	assert_true(s.effective_render_scale() <= 0.7)
	assert_false(s.effective_shadows())
	assert_true(s.effective_grass_density() <= 0.25)
	assert_true(s.effective_draw_distance() <= 150.0)
	# Сами настройки игрока не теряются.
	assert_almost_eq(s.render_scale, 1.0, 0.001)


func test_fps_limit_only_30_or_60() -> void:
	s.from_dict({"fps_limit": 45})
	assert_eq(s.effective_fps_limit(), 30)
	s.from_dict({"fps_limit": 120})
	assert_eq(s.effective_fps_limit(), 60)


func test_roundtrip_dict() -> void:
	s.apply_preset("high")
	s.left_handed = true
	s.hud_opacity = 0.4
	var other: GameSettings = GameSettings.new()
	other.configure(JsonData.load_dict(QUALITY))
	other.from_dict(s.to_dict())
	assert_eq(other.to_dict(), s.to_dict())


func test_from_dict_clamps_and_ignores_garbage() -> void:
	s.from_dict({"render_scale": 9.0, "draw_distance": -5, "hud_scale": "big", "quality_preset": "ultra", "unknown": 1})
	assert_almost_eq(s.render_scale, GameSettings.RENDER_SCALE_MAX, 0.001)
	assert_almost_eq(s.draw_distance, GameSettings.DRAW_DISTANCE_MIN, 0.001)
	assert_almost_eq(s.hud_scale, 1.0, 0.001)
	assert_eq(s.quality_preset, "medium")


func test_lower_quality_steps_down_then_scale_then_stops() -> void:
	s.apply_preset("high")
	assert_true(s.lower_quality_step())
	assert_eq(s.quality_preset, "medium")
	assert_true(s.lower_quality_step())
	assert_eq(s.quality_preset, "low")
	assert_true(s.lower_quality_step())
	assert_almost_eq(s.render_scale, 0.5, 0.001)
	assert_false(s.lower_quality_step(), "ниже минимального масштаба не опускаемся")


func test_lower_quality_from_custom_goes_to_low() -> void:
	s.apply_preset("high")
	s.mark_custom()
	assert_true(s.lower_quality_step())
	assert_eq(s.quality_preset, "low")
