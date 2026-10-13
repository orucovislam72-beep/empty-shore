class_name Projectiles
extends RefCounted
## Снаряды (этап 3): стрелы лука и пули самопала. Чистая логика без сцен и без физики:
## баллистика с гравитацией, попадание проверяется отрезком за шаг против животных (сферы),
## ресурсных узлов (сферы), деталей построек (AABB) и рельефа. Пул фиксированного размера,
## без выделения памяти за шаг. На этапе 4 эту же проверку выполнит сервер.

## Снаряд попал: what — Hit, target — индекс животного/узла/детали, pos — точка, ammo — id боеприпаса.
signal impact(what: int, target: int, pos: Vector3, ammo: String)

enum Hit { NONE, GROUND, ANIMAL, NODE, PIECE, EXPIRED }

const MAX: int = 48
const LIFE_S: float = 4.0

var terrain: TerrainMath
var animals: AnimalSim
var resources: ResourceField
var building: BuildingGrid

var positions: PackedVector3Array = PackedVector3Array()
var velocities: PackedVector3Array = PackedVector3Array()
var damages: PackedFloat32Array = PackedFloat32Array()
var gravities: PackedFloat32Array = PackedFloat32Array()
var lives: PackedFloat32Array = PackedFloat32Array()
var ammo_ids: PackedStringArray = PackedStringArray()
var origins: PackedVector3Array = PackedVector3Array()


func count() -> int:
	return positions.size()


## Выпустить снаряд. Возвращает индекс или -1 (пул полон).
func fire(origin: Vector3, velocity: Vector3, dmg: float, gravity: float, ammo: String) -> int:
	if positions.size() >= MAX:
		return -1
	positions.append(origin)
	velocities.append(velocity)
	damages.append(dmg)
	gravities.append(gravity)
	lives.append(LIFE_S)
	ammo_ids.append(ammo)
	origins.append(origin)
	return positions.size() - 1


func _remove(i: int) -> void:
	var last: int = positions.size() - 1
	if i != last:
		positions[i] = positions[last]
		velocities[i] = velocities[last]
		damages[i] = damages[last]
		gravities[i] = gravities[last]
		lives[i] = lives[last]
		ammo_ids[i] = ammo_ids[last]
		origins[i] = origins[last]
	positions.remove_at(last)
	velocities.remove_at(last)
	damages.remove_at(last)
	gravities.remove_at(last)
	lives.remove_at(last)
	ammo_ids.remove_at(last)
	origins.remove_at(last)


func clear() -> void:
	while not positions.is_empty():
		_remove(positions.size() - 1)


func tick(delta: float) -> void:
	var i: int = positions.size() - 1
	while i >= 0:
		_step(i, delta)
		i -= 1


func _step(i: int, delta: float) -> void:
	var p0: Vector3 = positions[i]
	var v: Vector3 = velocities[i]
	v.y -= gravities[i] * delta
	var p1: Vector3 = p0 + v * delta
	velocities[i] = v
	lives[i] -= delta
	var seg: Vector3 = p1 - p0
	var len: float = seg.length()
	if len < 0.0001:
		return
	var dir: Vector3 = seg / len
	var what: int = Hit.NONE
	var target: int = -1
	var best_t: float = len
	if animals != null:
		var a: int = animals.find_hit(p0, dir, len)
		if a >= 0 and animals.last_hit_t <= best_t:
			best_t = animals.last_hit_t
			what = Hit.ANIMAL
			target = a
	if resources != null:
		var n: int = resources.find_target(p0, dir, len)
		if n >= 0:
			var t: float = maxf((resources.hit_center(n) - p0).dot(dir) - resources.hit_radius(n) * 0.5, 0.0)
			if t < best_t:
				best_t = t
				what = Hit.NODE
				target = n
	if building != null:
		var b: int = building.find_target(p0, dir, len)
		if b >= 0:
			var tb: float = BuildingGrid.ray_aabb(p0, dir, building.piece_aabb(b))
			if tb < best_t:
				best_t = tb
				what = Hit.PIECE
				target = b
	if terrain != null:
		# Рельеф: проверка концов отрезка и середины (шаг пули ≤ 8 м — хватает для пологого рельефа).
		var steps: int = maxi(int(ceil(len / 2.0)), 1)
		for s: int in range(1, steps + 1):
			var t2: float = len * float(s) / float(steps)
			if t2 > best_t:
				break
			var q: Vector3 = p0 + dir * t2
			if q.y <= terrain.height_at(q.x, q.z):
				best_t = t2
				what = Hit.GROUND
				target = -1
				break
	if what != Hit.NONE:
		var hit_pos: Vector3 = p0 + dir * best_t
		var ammo: String = ammo_ids[i]
		var dmg: float = damages[i]
		var from: Vector3 = origins[i]
		_remove(i)
		if what == Hit.ANIMAL:
			animals.damage(target, dmg, from)
		impact.emit(what, target, hit_pos, ammo)
		return
	positions[i] = p1
	if lives[i] <= 0.0:
		_remove(i)
		impact.emit(Hit.EXPIRED, -1, p1, "")
