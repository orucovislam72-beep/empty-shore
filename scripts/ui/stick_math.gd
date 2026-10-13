class_name StickMath
extends RefCounted
## Математика виртуального стика: из смещения пальца в вектор -1..1 с мёртвой зоной.


## offset — смещение пальца от центра стика, radius — радиус хода ручки.
## Результат: длина 0..1, внутри dead_zone — ноль, дальше — плавно от 0 до 1.
static func to_vector(offset: Vector2, radius: float, dead_zone: float = 0.15) -> Vector2:
	if radius <= 0.0:
		return Vector2.ZERO
	var v: Vector2 = offset / radius
	var mag: float = v.length()
	if mag <= dead_zone:
		return Vector2.ZERO
	if mag > 1.0:
		v /= mag
		mag = 1.0
	var scaled: float = (mag - dead_zone) / (1.0 - dead_zone)
	return v / mag * scaled


## Ограничивает положение ручки радиусом хода (для отрисовки).
static func clamp_knob(offset: Vector2, radius: float) -> Vector2:
	if offset.length() > radius:
		return offset.normalized() * radius
	return offset
