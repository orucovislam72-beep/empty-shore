class_name WorldGen
extends TerrainMath
## Генератор мира этапа 3 (data/balance/world.json): остров size_m × size_m в океане, рельеф из шума
## по seed, четыре биома (побережье, равнина, лес, горы), вода на уровне water_level (море вокруг и озёра
## в низинах), место высадки на южном берегу (ровная площадка) и точки возрождения на побережье.
## Наследует TerrainMath, поэтому вся логика (постройки, добыча, сессия) работает с ним без изменений.
## Чистая логика без сцен. Одинаковый seed и данные → одинаковый мир (тесты). Для рабочих потоков
## используйте clone(): у каждого потока свой набор объектов шума.

enum Biome { COAST, PLAIN, FOREST, MOUNTAIN }

const DEFAULT_PATH: String = "res://data/balance/world.json"
const BIOME_IDS: PackedStringArray = ["coast", "plain", "forest", "mountain"]
## Версия генератора (пишется в сохранение; другая версия — состояние узлов сбрасывается).
const GENERATOR_VERSION: int = 3

var cfg: Dictionary = {}
var grid: ChunkGrid
var water_level: float = 0.0
## Точка высадки (новая игра) — на берегу, площадка выровнена.
var landing: Vector3 = Vector3.ZERO
## Точки возрождения на побережье (если нет спальника или кровати).
var coast_points: PackedVector3Array = PackedVector3Array()

var _hills: FastNoiseLite = FastNoiseLite.new()
var _coast: FastNoiseLite = FastNoiseLite.new()
var _ridge: FastNoiseLite = FastNoiseLite.new()
var _mask: FastNoiseLite = FastNoiseLite.new()
var _moist: FastNoiseLite = FastNoiseLite.new()

var _isl_inner: float = 0.55
var _isl_outer: float = 0.95
var _coast_warp: float = 0.18
var _ocean_floor: float = -16.0
var _land_base: float = 5.0
var _hills_amp: float = 9.0
var _mount_amp: float = 48.0
var _mask_from: float = 0.55
var _mask_to: float = 0.72
var _coast_max_h: float = 2.6
var _mount_biome_m: float = 0.35
var _mount_h: float = 24.0
var _forest_above: float = 0.0
var _flat_r: float = 12.0
var _landing_h: float = 1.6
## Последний разбор точки (_sample): доля «острова» и гор.
var _last_island: float = 0.0
var _last_mount: float = 0.0


func _init(p_cfg: Dictionary = {}, compute_points: bool = true) -> void:
	super(JsonData.get_int(p_cfg, "seed", 1337), 0.0, 0.01, 1, 0.0)
	cfg = p_cfg
	grid = ChunkGrid.new(JsonData.get_float(p_cfg, "size_m", 1280.0), JsonData.get_float(p_cfg, "chunk_m", 64.0))
	water_level = JsonData.get_float(p_cfg, "water_level", 0.0)
	var isl: Dictionary = p_cfg.get("island", {})
	_isl_inner = JsonData.get_float(isl, "inner", _isl_inner)
	_isl_outer = JsonData.get_float(isl, "outer", _isl_outer)
	_coast_warp = JsonData.get_float(isl, "coast_warp", _coast_warp)
	_ocean_floor = JsonData.get_float(isl, "ocean_floor", _ocean_floor)
	_land_base = JsonData.get_float(isl, "land_base", _land_base)
	var hills: Dictionary = p_cfg.get("hills", {})
	_hills_amp = JsonData.get_float(hills, "amp", _hills_amp)
	var mount: Dictionary = p_cfg.get("mountains", {})
	_mount_amp = JsonData.get_float(mount, "amp", _mount_amp)
	_mask_from = JsonData.get_float(mount, "mask_from", _mask_from)
	_mask_to = JsonData.get_float(mount, "mask_to", _mask_to)
	var bio: Dictionary = p_cfg.get("biomes", {})
	_coast_max_h = JsonData.get_float(bio, "coast_max_h", _coast_max_h)
	_mount_biome_m = JsonData.get_float(bio, "mountain_mask", _mount_biome_m)
	_mount_h = JsonData.get_float(bio, "mountain_h", _mount_h)
	_forest_above = JsonData.get_float(bio, "forest_moisture_above", _forest_above)
	var land: Dictionary = p_cfg.get("landing", {})
	_flat_r = JsonData.get_float(land, "flat_radius_m", _flat_r)
	_landing_h = JsonData.get_float(land, "height_m", _landing_h)

	_setup_noise(_coast, 11, JsonData.get_float(isl, "coast_freq", 0.004), 2, FastNoiseLite.FRACTAL_FBM)
	_setup_noise(_hills, 23, JsonData.get_float(hills, "freq", 0.006), JsonData.get_int(hills, "octaves", 4), FastNoiseLite.FRACTAL_FBM)
	_setup_noise(_ridge, 37, JsonData.get_float(mount, "freq", 0.0045), 4, FastNoiseLite.FRACTAL_RIDGED)
	_setup_noise(_mask, 41, JsonData.get_float(mount, "mask_freq", 0.0022), 2, FastNoiseLite.FRACTAL_FBM)
	_setup_noise(_moist, 53, JsonData.get_float(bio, "moisture_freq", 0.003), 3, FastNoiseLite.FRACTAL_FBM)
	if compute_points:
		_compute_points()


static func load_default() -> WorldGen:
	return WorldGen.new(JsonData.load_dict(DEFAULT_PATH))


## Копия для рабочего потока: свои объекты шума, те же точки высадки и побережья (без пересчёта).
func clone() -> WorldGen:
	var g: WorldGen = WorldGen.new(cfg, false)
	g.landing = landing
	g.coast_points = coast_points
	return g


func _setup_noise(n: FastNoiseLite, salt: int, freq: float, octaves: int, fractal: FastNoiseLite.FractalType) -> void:
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_value * 7919 + salt
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves


## Рельеф без площадки высадки. Запоминает долю острова и гор (_last_*).
func base_height(x: float, z: float) -> float:
	var d: float = sqrt(x * x + z * z) / grid.half
	d += _coast.get_noise_2d(x, z) * _coast_warp
	var island: float = 1.0 - smoothstep(_isl_inner, _isl_outer, d)
	var h: float = lerpf(_ocean_floor, _land_base, island)
	h += _hills.get_noise_2d(x, z) * _hills_amp * island
	var mk: float = _mask.get_noise_2d(x, z) * 0.5 + 0.5
	var m: float = smoothstep(_mask_from, _mask_to, mk) * smoothstep(0.55, 0.85, island)
	if m > 0.0:
		var r: float = _ridge.get_noise_2d(x, z) * 0.5 + 0.5
		h += m * (0.35 + 0.65 * r) * _mount_amp
	_last_island = island
	_last_mount = m
	return h


func height_at(x: float, z: float) -> float:
	var h: float = base_height(x, z)
	if _flat_r > 0.0:
		var dx: float = x - landing.x
		var dz: float = z - landing.z
		var d2: float = dx * dx + dz * dz
		if d2 < 4.0 * _flat_r * _flat_r:
			var t: float = clampf((sqrt(d2) - _flat_r) / _flat_r, 0.0, 1.0)
			h = lerpf(landing.y, h, t * t * (3.0 - 2.0 * t))
	return h


## Биом в точке (по высоте, горам и влажности).
func biome_at(x: float, z: float) -> int:
	return biome_for(x, z, height_at(x, z))


## Биом по уже посчитанной высоте h (доля гор пересчитывается).
func biome_for(x: float, z: float, h: float) -> int:
	if h <= water_level + _coast_max_h:
		return Biome.COAST
	base_height(x, z)
	return biome_after_height(x, z, h)


## Биом сразу после height_at(x, z) той же точки: берёт долю гор из последнего расчёта (без повтора шума).
func biome_after_height(x: float, z: float, h: float) -> int:
	if h <= water_level + _coast_max_h:
		return Biome.COAST
	if _last_mount >= _mount_biome_m or h >= _mount_h:
		return Biome.MOUNTAIN
	if _moist.get_noise_2d(x, z) > _forest_above:
		return Biome.FOREST
	return Biome.PLAIN


static func biome_id(b: int) -> String:
	return BIOME_IDS[clampi(b, 0, BIOME_IDS.size() - 1)]


static func biome_index(id: String) -> int:
	return BIOME_IDS.find(id)


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < water_level


## Ищет берег по лучу от края карты к центру под углом angle (радианы): первая точка выше воды на min_h.
func _find_coast(angle: float, min_h: float) -> Vector3:
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	var r: float = grid.half - 4.0
	while r > 0.0:
		var p: Vector2 = dir * r
		var h: float = base_height(p.x, p.y)
		if h > water_level + min_h:
			return Vector3(p.x, h, p.y)
		r -= 2.0
	return Vector3(0.0, base_height(0.0, 0.0), 0.0)


func _compute_points() -> void:
	var land: Dictionary = cfg.get("landing", {})
	var ang: float = deg_to_rad(JsonData.get_float(land, "angle_deg", 90.0))
	var inland: float = JsonData.get_float(land, "inland_m", 8.0)
	var save_flat: float = _flat_r
	_flat_r = 0.0
	var c: Vector3 = _find_coast(ang, _landing_h)
	var dir: Vector2 = Vector2(c.x, c.z).normalized()
	var p: Vector2 = Vector2(c.x, c.z) - dir * inland
	landing = Vector3(p.x, maxf(base_height(p.x, p.y), water_level + _landing_h), p.y)
	_flat_r = save_flat
	coast_points = PackedVector3Array()
	coast_points.append(landing)
	var count: int = JsonData.get_int(cfg, "coast_points", 24)
	for i: int in count:
		var a: float = TAU * float(i) / float(count) + 0.1
		var q: Vector3 = _find_coast(a, 1.0)
		var qd: Vector2 = Vector2(q.x, q.z).normalized()
		var q2: Vector2 = Vector2(q.x, q.z) - qd * 3.0
		var y: float = height_at(q2.x, q2.y)
		if y > water_level + 0.5 and y < water_level + 6.0:
			coast_points.append(Vector3(q2.x, y, q2.y))


## Нормаль рельефа (по разностям высот с шагом step).
func normal_at(x: float, z: float, step: float = 1.0) -> Vector3:
	var hl: float = height_at(x - step, z)
	var hr: float = height_at(x + step, z)
	var hd: float = height_at(x, z - step)
	var hu: float = height_at(x, z + step)
	return Vector3(hl - hr, 2.0 * step, hd - hu).normalized()


## Доли биомов на суше по сетке с шагом step (для тестов и отчёта): {id: доля}.
func biome_shares(step: float = 16.0) -> Dictionary:
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(BIOME_IDS.size())
	var land: int = 0
	var x: float = -grid.half + step * 0.5
	while x < grid.half:
		var z: float = -grid.half + step * 0.5
		while z < grid.half:
			var h: float = height_at(x, z)
			if h >= water_level:
				land += 1
				counts[biome_for(x, z, h)] += 1
			z += step
		x += step
	var out: Dictionary = {"land_cells": land}
	for i: int in BIOME_IDS.size():
		out[BIOME_IDS[i]] = float(counts[i]) / float(maxi(land, 1))
	return out
