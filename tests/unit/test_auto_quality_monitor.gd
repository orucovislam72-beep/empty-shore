extends GutTest

var m: AutoQualityMonitor


func before_each() -> void:
	m = AutoQualityMonitor.new()
	m.configure({"min_fps": 25.0, "seconds_below": 10.0, "warmup_seconds": 5.0})


func _run(seconds: float, fps: float) -> bool:
	var triggered: bool = false
	var t: float = 0.0
	var dt: float = 1.0 / maxf(fps, 1.0)
	while t < seconds:
		if m.tick(dt, fps):
			triggered = true
		t += dt
	return triggered


func test_no_trigger_during_warmup() -> void:
	assert_false(_run(4.9, 10.0))


func test_triggers_after_10s_below_threshold() -> void:
	assert_false(_run(5.0, 60.0))
	assert_false(_run(9.5, 20.0))
	assert_true(_run(1.0, 20.0))


func test_good_frames_reset_timer() -> void:
	_run(5.0, 60.0)
	_run(8.0, 20.0)
	_run(0.5, 40.0)
	assert_false(_run(8.0, 20.0))


func test_resets_after_trigger() -> void:
	_run(5.0, 60.0)
	assert_true(_run(10.5, 20.0))
	# После срабатывания снова идёт прогрев, второе срабатывание не мгновенное.
	assert_false(_run(4.0, 20.0))
