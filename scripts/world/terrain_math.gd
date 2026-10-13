class_name TerrainMath
extends RefCounted
## Детерминированная функция высоты тестового ландшафта по seed.
## Чистая логика без сцены: одинаковый seed -> одинаковый рельеф (проверяется тестами).

var seed_value: int = 0
var amplitude: float = 14.0
var flat_radius: float = 12.0
var _noise: FastNoiseLite = FastNoiseLite.new()


func _init(p_seed: int = 0, p_amplitude: float = 14.0, frequency: float = 0.008, octaves: int = 4, p_flat_radius: float = 12.0) -> void:
	seed_value = p_seed
	amplitude = p_amplitude
	flat_radius = p_flat_radius
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = p_seed
	_noise.frequency = frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = octaves


static func from_config(cfg: Dictionary) -> TerrainMath:
	return TerrainMath.new(
		JsonData.get_int(cfg, "seed", 0),
		JsonData.get_float(cfg, "height_amplitude", 14.0),
		JsonData.get_float(cfg, "noise_frequency", 0.008),
		JsonData.get_int(cfg, "noise_octaves", 4),
		JsonData.get_float(cfg, "flat_spawn_radius_m", 12.0))


## Высота в точке (x, z) мира, метры.
func height_at(x: float, z: float) -> float:
	var h: float = _noise.get_noise_2d(x, z) * amplitude
	# Ровная площадка в центре — точка появления.
	var d: float = sqrt(x * x + z * z)
	if flat_radius > 0.0 and d < flat_radius * 2.0:
		var t: float = clampf((d - flat_radius) / flat_radius, 0.0, 1.0)
		var flat_h: float = _noise.get_noise_2d(0.0, 0.0) * amplitude
		h = lerpf(flat_h, h, t * t * (3.0 - 2.0 * t))
	return h


## Сетка высот resolution x resolution на квадрате size (центр в 0,0), построчно по Z.
## Порядок совпадает с HeightMapShape3D.map_data.
func build_heights(size: float, resolution: int) -> PackedFloat32Array:
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(resolution * resolution)
	var step: float = size / float(resolution - 1)
	var half: float = size * 0.5
	for zi: int in resolution:
		var z: float = -half + zi * step
		for xi: int in resolution:
			heights[zi * resolution + xi] = height_at(-half + xi * step, z)
	return heights
