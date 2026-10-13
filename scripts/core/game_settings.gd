class_name GameSettings
extends RefCounted
## Чистые данные настроек игрока и правила их применения.
## Не зависит от сцен и движковых синглтонов — покрыто тестами (tests/unit/test_game_settings.gd).

const PRESET_CUSTOM: String = "custom"
const TOUCH_AUTO: int = 0
const TOUCH_ON: int = 1
const TOUCH_OFF: int = 2

const RENDER_SCALE_MIN: float = 0.5
const RENDER_SCALE_MAX: float = 1.0
const DRAW_DISTANCE_MIN: float = 60.0
const DRAW_DISTANCE_MAX: float = 400.0

var quality_preset: String = "medium"
var render_scale: float = 0.8
var fps_limit: int = 30
var draw_distance: float = 200.0
var shadows: bool = true
var grass_density: float = 0.5
var battery_saver: bool = false
var auto_quality: bool = true

var look_sensitivity: float = 1.0
var aim_sensitivity: float = 0.6
var invert_y: bool = false
var hud_scale: float = 1.0
var hud_opacity: float = 0.75
var left_handed: bool = false
var vibration: bool = true
var touch_controls: int = TOUCH_AUTO
var show_debug: bool = false
var locale: String = "ru"

## Параметры из data/balance/quality_presets.json.
var _presets: Dictionary = {}
var _order: Array = []
var _battery: Dictionary = {}
var _auto: Dictionary = {}


func configure(quality_data: Dictionary) -> void:
	_presets = quality_data.get("presets", {})
	_order = quality_data.get("order", [])
	_battery = quality_data.get("battery_saver", {})
	_auto = quality_data.get("auto_quality", {})


func preset_names() -> Array:
	return _order.duplicate()


func auto_quality_params() -> Dictionary:
	return _auto


## Применяет пресет по имени. Возвращает false, если такого пресета нет.
func apply_preset(preset_name: String) -> bool:
	if not _presets.has(preset_name):
		return false
	var p: Dictionary = _presets[preset_name]
	quality_preset = preset_name
	render_scale = clampf(JsonData.get_float(p, "render_scale", render_scale), RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	draw_distance = clampf(JsonData.get_float(p, "draw_distance", draw_distance), DRAW_DISTANCE_MIN, DRAW_DISTANCE_MAX)
	shadows = JsonData.get_bool(p, "shadows", shadows)
	grass_density = clampf(JsonData.get_float(p, "grass_density", grass_density), 0.0, 1.0)
	return true


## Вызывается, когда игрок вручную меняет параметр графики.
func mark_custom() -> void:
	quality_preset = PRESET_CUSTOM


## Один шаг автоснижения качества. Возвращает false, если снижать уже некуда.
func lower_quality_step() -> bool:
	var idx: int = _order.find(quality_preset)
	if idx > 0:
		return apply_preset(String(_order[idx - 1]))
	if idx == -1 and not _order.is_empty():
		# Пользовательские настройки: сначала откатываемся к самому низкому пресету,
		# если он действительно легче текущего.
		var lowest: String = String(_order[0])
		var lp: Dictionary = _presets.get(lowest, {})
		if JsonData.get_float(lp, "render_scale", 1.0) < render_scale or (shadows and not JsonData.get_bool(lp, "shadows", false)):
			return apply_preset(lowest)
	var min_scale: float = JsonData.get_float(_auto, "min_render_scale", RENDER_SCALE_MIN)
	var step: float = JsonData.get_float(_auto, "render_scale_step", 0.1)
	if render_scale - step >= min_scale - 0.001:
		render_scale = snappedf(render_scale - step, 0.01)
		quality_preset = PRESET_CUSTOM
		return true
	return false


func effective_fps_limit() -> int:
	if battery_saver:
		return JsonData.get_int(_battery, "fps_limit", 30)
	return 60 if fps_limit >= 60 else 30


func effective_render_scale() -> float:
	if battery_saver:
		return minf(render_scale, JsonData.get_float(_battery, "max_render_scale", 0.7))
	return render_scale


func effective_shadows() -> bool:
	if battery_saver:
		return shadows and JsonData.get_bool(_battery, "shadows", false)
	return shadows


func effective_grass_density() -> float:
	if battery_saver:
		return minf(grass_density, JsonData.get_float(_battery, "max_grass_density", 0.25))
	return grass_density


func effective_draw_distance() -> float:
	if battery_saver:
		return minf(draw_distance, JsonData.get_float(_battery, "max_draw_distance", 150.0))
	return draw_distance


func to_dict() -> Dictionary:
	return {
		"quality_preset": quality_preset,
		"render_scale": render_scale,
		"fps_limit": fps_limit,
		"draw_distance": draw_distance,
		"shadows": shadows,
		"grass_density": grass_density,
		"battery_saver": battery_saver,
		"auto_quality": auto_quality,
		"look_sensitivity": look_sensitivity,
		"aim_sensitivity": aim_sensitivity,
		"invert_y": invert_y,
		"hud_scale": hud_scale,
		"hud_opacity": hud_opacity,
		"left_handed": left_handed,
		"vibration": vibration,
		"touch_controls": touch_controls,
		"show_debug": show_debug,
		"locale": locale,
	}


## Читает словарь, игнорируя неизвестные ключи и зажимая значения в допустимые пределы.
func from_dict(d: Dictionary) -> void:
	var preset: Variant = d.get("quality_preset", quality_preset)
	if typeof(preset) == TYPE_STRING and (_presets.has(preset) or preset == PRESET_CUSTOM):
		quality_preset = preset
	render_scale = clampf(JsonData.get_float(d, "render_scale", render_scale), RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	fps_limit = 60 if JsonData.get_int(d, "fps_limit", fps_limit) >= 60 else 30
	draw_distance = clampf(JsonData.get_float(d, "draw_distance", draw_distance), DRAW_DISTANCE_MIN, DRAW_DISTANCE_MAX)
	shadows = JsonData.get_bool(d, "shadows", shadows)
	grass_density = clampf(JsonData.get_float(d, "grass_density", grass_density), 0.0, 1.0)
	battery_saver = JsonData.get_bool(d, "battery_saver", battery_saver)
	auto_quality = JsonData.get_bool(d, "auto_quality", auto_quality)
	look_sensitivity = clampf(JsonData.get_float(d, "look_sensitivity", look_sensitivity), 0.1, 3.0)
	aim_sensitivity = clampf(JsonData.get_float(d, "aim_sensitivity", aim_sensitivity), 0.1, 3.0)
	invert_y = JsonData.get_bool(d, "invert_y", invert_y)
	hud_scale = clampf(JsonData.get_float(d, "hud_scale", hud_scale), 0.75, 1.5)
	hud_opacity = clampf(JsonData.get_float(d, "hud_opacity", hud_opacity), 0.2, 1.0)
	left_handed = JsonData.get_bool(d, "left_handed", left_handed)
	vibration = JsonData.get_bool(d, "vibration", vibration)
	touch_controls = clampi(JsonData.get_int(d, "touch_controls", touch_controls), TOUCH_AUTO, TOUCH_OFF)
	show_debug = JsonData.get_bool(d, "show_debug", show_debug)
	var loc: Variant = d.get("locale", locale)
	if typeof(loc) == TYPE_STRING and not String(loc).is_empty():
		locale = loc
