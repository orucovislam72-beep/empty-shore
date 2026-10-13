class_name DayNightCycle
extends RefCounted
## Смена дня и ночи: игровое время, высота солнца и параметры освещения по опорным точкам
## из data/balance/day_night.json. Чистая логика; sample() пишет в заранее созданный объект,
## чтобы не выделять память каждый кадр.

const DEFAULT_PATH: String = "res://data/balance/day_night.json"


## Освещение в текущий момент (заполняется sample()).
class Sample:
	var sun_energy: float = 1.0
	var ambient_energy: float = 0.35
	var sky_top: Color = Color.WHITE
	var sky_horizon: Color = Color.WHITE
	var fog: Color = Color.WHITE
	var sun_color: Color = Color.WHITE
	var sun_elevation_deg: float = 45.0
	var sun_azimuth_deg: float = 0.0


var time_hours: float = 8.0
var day: int = 1
var day_length_s: float = 1800.0
var sunrise: float = 6.0
var sunset: float = 18.0
var max_elevation: float = 62.0
var shadows_min_elevation: float = 6.0

var _hours: PackedFloat32Array = PackedFloat32Array()
var _sun: PackedFloat32Array = PackedFloat32Array()
var _ambient: PackedFloat32Array = PackedFloat32Array()
var _top: PackedColorArray = PackedColorArray()
var _hor: PackedColorArray = PackedColorArray()
var _fog: PackedColorArray = PackedColorArray()
var _sun_col: PackedColorArray = PackedColorArray()


func configure(cfg: Dictionary) -> void:
	day_length_s = maxf(JsonData.get_float(cfg, "day_length_min", 30.0), 0.1) * 60.0
	time_hours = fposmod(JsonData.get_float(cfg, "start_hour", 8.0), 24.0)
	sunrise = JsonData.get_float(cfg, "sunrise_hour", 6.0)
	sunset = JsonData.get_float(cfg, "sunset_hour", 18.0)
	max_elevation = JsonData.get_float(cfg, "max_sun_elevation_deg", 62.0)
	shadows_min_elevation = JsonData.get_float(cfg, "shadows_min_elevation_deg", 6.0)
	day = 1
	_hours.clear()
	_sun.clear()
	_ambient.clear()
	_top.clear()
	_hor.clear()
	_fog.clear()
	_sun_col.clear()
	var keys: Variant = cfg.get("keys", [])
	if typeof(keys) == TYPE_ARRAY:
		for k: Variant in keys:
			if typeof(k) != TYPE_DICTIONARY:
				continue
			var kd: Dictionary = k
			_hours.append(fposmod(JsonData.get_float(kd, "hour", 0.0), 24.0))
			_sun.append(JsonData.get_float(kd, "sun", 1.0))
			_ambient.append(JsonData.get_float(kd, "ambient", 0.35))
			_top.append(Color.from_string(String(kd.get("sky_top", "#617fa0")), Color.WHITE))
			_hor.append(Color.from_string(String(kd.get("sky_horizon", "#a8b8c2")), Color.WHITE))
			_fog.append(Color.from_string(String(kd.get("fog", "#a8b8c2")), Color.WHITE))
			_sun_col.append(Color.from_string(String(kd.get("sun_color", "#ffffff")), Color.WHITE))
	if _hours.is_empty():
		push_error("DayNightCycle: нет опорных точек keys")


func tick(delta: float) -> void:
	time_hours += delta / day_length_s * 24.0
	while time_hours >= 24.0:
		time_hours -= 24.0
		day += 1


## Полное игровое время в часах с начала (для сохранения).
func total_hours() -> float:
	return float(day - 1) * 24.0 + time_hours


func set_total_hours(h: float) -> void:
	var hh: float = maxf(h, 0.0)
	day = int(floor(hh / 24.0)) + 1
	time_hours = hh - float(day - 1) * 24.0


func is_night() -> bool:
	return time_hours < sunrise or time_hours >= sunset


## Высота солнца над горизонтом в градусах (отрицательная ночью).
func sun_elevation_deg() -> float:
	var day_len: float = sunset - sunrise
	if day_len <= 0.0:
		return max_elevation
	var t: float = (time_hours - sunrise) / day_len
	if t >= 0.0 and t <= 1.0:
		return sin(t * PI) * max_elevation
	# Ночью солнце под горизонтом — нужно только для знака.
	var night_len: float = 24.0 - day_len
	var tn: float = fposmod(time_hours - sunset, 24.0) / night_len
	return -sin(tn * PI) * 30.0


## Азимут солнца: восход на востоке (+X), закат на западе (−X).
func sun_azimuth_deg() -> float:
	var day_len: float = sunset - sunrise
	var t: float = clampf((time_hours - sunrise) / day_len, 0.0, 1.0) if day_len > 0.0 else 0.5
	return lerpf(90.0, 270.0, t)


func shadows_allowed() -> bool:
	return sun_elevation_deg() >= shadows_min_elevation


## Заполняет out параметрами освещения на текущий час (без выделения памяти).
func sample(out: Sample) -> void:
	out.sun_elevation_deg = sun_elevation_deg()
	out.sun_azimuth_deg = sun_azimuth_deg()
	var n: int = _hours.size()
	if n == 0:
		return
	# Ищем отрезок [a, b] по кругу суток, в который попадает текущий час.
	var b: int = 0
	while b < n and _hours[b] <= time_hours:
		b += 1
	var a: int = (b - 1 + n) % n
	b = b % n
	var ha: float = _hours[a]
	var hb: float = _hours[b]
	var span: float = fposmod(hb - ha, 24.0)
	var t: float = 0.0
	if span > 0.0:
		t = clampf(fposmod(time_hours - ha, 24.0) / span, 0.0, 1.0)
	out.sun_energy = lerpf(_sun[a], _sun[b], t)
	out.ambient_energy = lerpf(_ambient[a], _ambient[b], t)
	out.sky_top = _top[a].lerp(_top[b], t)
	out.sky_horizon = _hor[a].lerp(_hor[b], t)
	out.fog = _fog[a].lerp(_fog[b], t)
	out.sun_color = _sun_col[a].lerp(_sun_col[b], t)
