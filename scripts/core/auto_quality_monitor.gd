class_name AutoQualityMonitor
extends RefCounted
## Следит за частотой кадров: если FPS ниже порога дольше заданного времени,
## tick() возвращает true (пора снизить качество). Без аллокаций — можно звать каждый кадр.

var min_fps: float = 25.0
var seconds_below: float = 10.0
var warmup_seconds: float = 5.0

var _elapsed: float = 0.0
var _below_time: float = 0.0


func configure(params: Dictionary) -> void:
	min_fps = JsonData.get_float(params, "min_fps", min_fps)
	seconds_below = JsonData.get_float(params, "seconds_below", seconds_below)
	warmup_seconds = JsonData.get_float(params, "warmup_seconds", warmup_seconds)


## Сброс после смены сцены или после снижения качества (даём время на стабилизацию).
func reset() -> void:
	_elapsed = 0.0
	_below_time = 0.0


func below_time() -> float:
	return _below_time


## delta — время кадра в секундах, fps — усреднённый FPS (Engine.get_frames_per_second()).
func tick(delta: float, fps: float) -> bool:
	_elapsed += delta
	if _elapsed < warmup_seconds:
		return false
	if fps < min_fps:
		_below_time += delta
	else:
		_below_time = 0.0
	if _below_time >= seconds_below:
		reset()
		return true
	return false
