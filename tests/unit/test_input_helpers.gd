extends GutTest


func test_stick_dead_zone() -> void:
	assert_eq(StickMath.to_vector(Vector2(5.0, 0.0), 100.0, 0.15), Vector2.ZERO)


func test_stick_full_deflection_is_unit() -> void:
	var v: Vector2 = StickMath.to_vector(Vector2(0.0, -300.0), 100.0, 0.15)
	assert_almost_eq(v.length(), 1.0, 0.001)
	assert_almost_eq(v.y, -1.0, 0.001)


func test_stick_scales_smoothly_after_dead_zone() -> void:
	var v: Vector2 = StickMath.to_vector(Vector2(57.5, 0.0), 100.0, 0.15)
	assert_almost_eq(v.x, 0.5, 0.001)


func test_knob_clamped_to_radius() -> void:
	assert_almost_eq(StickMath.clamp_knob(Vector2(300.0, 400.0), 100.0).length(), 100.0, 0.001)


func test_double_tap_forward_triggers() -> void:
	var d: DoubleTapDetector = DoubleTapDetector.new()
	assert_false(d.update(1.0, 0.0))
	assert_false(d.update(0.0, 0.1))
	assert_true(d.update(1.0, 0.2))


func test_double_tap_too_slow_does_not_trigger() -> void:
	var d: DoubleTapDetector = DoubleTapDetector.new()
	d.update(1.0, 0.0)
	d.update(0.0, 0.2)
	assert_false(d.update(1.0, 0.6))


func test_holding_forward_is_not_double_tap() -> void:
	var d: DoubleTapDetector = DoubleTapDetector.new()
	var hits: int = 0
	for i: int in 30:
		if d.update(1.0, i * 0.016):
			hits += 1
	assert_eq(hits, 0)


func test_min_touch_target_is_at_least_48dp() -> void:
	# Телефон 420 dpi, окно 2400x1080 при базовой высоте холста 720 -> масштаб 1.5.
	var units: float = UiMetrics.min_touch_units(420.0, 1.5, 0.0)
	var px: float = units * 1.5
	assert_almost_eq(px, UiMetrics.dp_to_px(48.0, 420.0), 0.01)
	assert_true(px >= 48.0 * 420.0 / 160.0 - 0.01)


func test_dp_to_px_mdpi() -> void:
	assert_almost_eq(UiMetrics.dp_to_px(48.0, 160.0), 48.0, 0.001)
