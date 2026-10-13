class_name ChunkGrid
extends RefCounted
## Сетка чанков мира: квадрат size_m × size_m с центром в (0, 0), разбитый на n × n чанков по chunk_m.
## Чанк (cx, cz) начинается в (-half + cx·chunk_m, -half + cz·chunk_m); линейный номер — cz·n + cx.
## Ключ чанка в сохранении — строка "cx,cz" (совместима с JSON). Чистая логика без сцен.

var size_m: float = 1280.0
var chunk_m: float = 64.0
var half: float = 640.0
var n: int = 20


func _init(p_size: float = 1280.0, p_chunk: float = 64.0) -> void:
	chunk_m = maxf(p_chunk, 1.0)
	n = maxi(int(round(p_size / chunk_m)), 1)
	size_m = chunk_m * n
	half = size_m * 0.5


## Один чанк на всю карту (маленькие тестовые карты без чанков).
static func single(p_size: float) -> ChunkGrid:
	return ChunkGrid.new(p_size, p_size)


func count() -> int:
	return n * n


func coord_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floor((x + half) / chunk_m)), 0, n - 1), clampi(int(floor((z + half) / chunk_m)), 0, n - 1))


func index_of_coord(c: Vector2i) -> int:
	return c.y * n + c.x


func coord_of_index(i: int) -> Vector2i:
	return Vector2i(i % n, i / n)


func index_of(x: float, z: float) -> int:
	return index_of_coord(coord_of(x, z))


func origin_of(c: Vector2i) -> Vector2:
	return Vector2(-half + c.x * chunk_m, -half + c.y * chunk_m)


func center_of(c: Vector2i) -> Vector2:
	return origin_of(c) + Vector2(chunk_m, chunk_m) * 0.5


func is_inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n


## Расстояние по горизонтали от точки до ближайшей точки чанка (0 — точка внутри).
func distance_to(c: Vector2i, x: float, z: float) -> float:
	var o: Vector2 = origin_of(c)
	var dx: float = maxf(maxf(o.x - x, x - (o.x + chunk_m)), 0.0)
	var dz: float = maxf(maxf(o.y - z, z - (o.y + chunk_m)), 0.0)
	return sqrt(dx * dx + dz * dz)


static func key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


func key_of(x: float, z: float) -> String:
	return key(coord_of(x, z))


## Разбирает ключ "cx,cz"; неверный ключ — (-1, -1).
static func parse_key(k: String) -> Vector2i:
	var parts: PackedStringArray = k.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))
