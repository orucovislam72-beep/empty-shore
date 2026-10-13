class_name AnimalSim
extends RefCounted
## Животные (этап 3): олень, волк, медведь. Чистая логика без сцен и без физики (data/balance/animals.json).
## Состояния ИИ: WANDER (бродит), FLEE (бежит), ATTACK (преследует и кусает), DEAD.
## Движение — простой steering по функции высоты: направление к цели, перед шагом «щупальце» на 2 м вперёд
## проверяет воду, крутизну и постройки; если путь закрыт — пробуем отклониться на ±35°, ±70°, ±105°.
## Решения ИИ — think_hz раз в секунду, движение — каждый вызов tick() (без выделения памяти).
## Появление — в кольце вокруг игрока по весам биомов, исчезновение — дальше despawn_m.

## Животное укусило игрока.
signal attacked(animal: int, damage: float, kind: String)
## Животное погибло (сессия кладёт тушу).
signal died(kind: String, pos: Vector3, yaw: float)

const DEFAULT_PATH: String = "res://data/balance/animals.json"

enum State { WANDER, FLEE, ATTACK, DEAD }

var kind_ids: PackedStringArray = PackedStringArray()
var defs: Array[Dictionary] = []
var terrain: TerrainMath
var water_level: float = 0.0
## Постройки — препятствие (может быть null).
var building: BuildingGrid
## Границы карты (половина стороны).
var half: float = 640.0

var kinds: PackedInt32Array = PackedInt32Array()
var positions: PackedVector3Array = PackedVector3Array()
var yaws: PackedFloat32Array = PackedFloat32Array()
var states: PackedInt32Array = PackedInt32Array()
var hp: PackedFloat32Array = PackedFloat32Array()
var speeds: PackedFloat32Array = PackedFloat32Array()
var _state_t: PackedFloat32Array = PackedFloat32Array()
var _attack_cd: PackedFloat32Array = PackedFloat32Array()
var _goal: PackedVector3Array = PackedVector3Array()
var _threat: PackedVector3Array = PackedVector3Array()

var _cfg: Dictionary = {}
var _think_dt: float = 0.125
var _think_acc: float = 0.0
var _spawn_acc: float = 0.0
var _max_slope: float = 0.9
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Расстояние до последнего попадания find_hit/segment_hit.
var last_hit_t: float = INF


func configure(cfg: Dictionary, p_terrain: TerrainMath, p_water: float, p_half: float) -> void:
	_cfg = cfg
	terrain = p_terrain
	water_level = p_water
	half = p_half
	_think_dt = 1.0 / maxf(JsonData.get_float(cfg, "think_hz", 8.0), 1.0)
	_max_slope = JsonData.get_float(cfg, "max_slope", 0.9)
	kind_ids.clear()
	defs.clear()
	var t: Dictionary = cfg.get("types", {})
	for id: String in t:
		kind_ids.append(id)
		defs.append(t[id])


func count() -> int:
	return positions.size()


func kind_id(i: int) -> String:
	return kind_ids[kinds[i]]


func def_of(i: int) -> Dictionary:
	return defs[kinds[i]]


func radius_of(i: int) -> float:
	return JsonData.get_float(def_of(i), "radius", 0.7)


func center_of(i: int) -> Vector3:
	return positions[i] + Vector3(0.0, JsonData.get_float(def_of(i), "center_h", 0.7), 0.0)


func max_hp_of(i: int) -> float:
	return JsonData.get_float(def_of(i), "hp", 50.0)


## Добавить животное вида id в точку pos. Возвращает индекс или -1.
func spawn(id: String, pos: Vector3, yaw: float = 0.0) -> int:
	var k: int = kind_ids.find(id)
	if k < 0:
		return -1
	kinds.append(k)
	positions.append(Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z))
	yaws.append(yaw)
	states.append(State.WANDER)
	hp.append(JsonData.get_float(defs[k], "hp", 50.0))
	speeds.append(0.0)
	_state_t.append(0.0)
	_attack_cd.append(0.0)
	_goal.append(positions[positions.size() - 1])
	_threat.append(Vector3.ZERO)
	return positions.size() - 1


func remove(i: int) -> void:
	var last: int = positions.size() - 1
	if i < 0 or i > last:
		return
	if i != last:
		kinds[i] = kinds[last]
		positions[i] = positions[last]
		yaws[i] = yaws[last]
		states[i] = states[last]
		hp[i] = hp[last]
		speeds[i] = speeds[last]
		_state_t[i] = _state_t[last]
		_attack_cd[i] = _attack_cd[last]
		_goal[i] = _goal[last]
		_threat[i] = _threat[last]
	kinds.remove_at(last)
	positions.remove_at(last)
	yaws.remove_at(last)
	states.remove_at(last)
	hp.remove_at(last)
	speeds.remove_at(last)
	_state_t.remove_at(last)
	_attack_cd.remove_at(last)
	_goal.remove_at(last)
	_threat.remove_at(last)


func clear() -> void:
	while not positions.is_empty():
		remove(positions.size() - 1)


## Урон животному. from — откуда пришёл удар (игрок). Возвращает true, если животное погибло.
func damage(i: int, amount: float, from: Vector3) -> bool:
	if i < 0 or i >= positions.size() or states[i] == State.DEAD or amount <= 0.0:
		return false
	hp[i] -= amount
	if hp[i] <= 0.0:
		var kind: String = kind_id(i)
		var p: Vector3 = positions[i]
		var y: float = yaws[i]
		remove(i)
		died.emit(kind, p, y)
		return true
	var d: Dictionary = def_of(i)
	_threat[i] = from
	match String(d.get("behavior", "timid")):
		"timid":
			_set_state(i, State.FLEE, JsonData.get_float(d, "flee_s", 6.0))
		_:
			if hp[i] < max_hp_of(i) * JsonData.get_float(d, "flee_hp", 0.0):
				_set_state(i, State.FLEE, JsonData.get_float(d, "flee_s", 6.0))
			else:
				_set_state(i, State.ATTACK, 0.0)
	return false


func _set_state(i: int, s: State, t: float) -> void:
	states[i] = s
	_state_t[i] = t


## Луч (origin, dir — единичный) против сфер животных в пределах max_d. Возвращает индекс или -1;
## расстояние до попадания — last_hit_t.
func find_hit(origin: Vector3, dir: Vector3, max_d: float) -> int:
	var best: int = -1
	last_hit_t = INF
	for i: int in positions.size():
		var r: float = radius_of(i)
		var v: Vector3 = center_of(i) - origin
		var t: float = v.dot(dir)
		if t < -r or t > max_d + r:
			continue
		var perp2: float = v.length_squared() - t * t
		if perp2 > r * r:
			continue
		if t < last_hit_t:
			last_hit_t = maxf(t, 0.0)
			best = i
	return best


## Отрезок p0 → p1 против животных (для снарядов).
func segment_hit(p0: Vector3, p1: Vector3) -> int:
	var d: Vector3 = p1 - p0
	var len: float = d.length()
	if len <= 0.0001:
		return -1
	return find_hit(p0, d / len, len)


## Шаг симуляции. player — позиция игрока, player_alive — можно ли его атаковать.
func tick(delta: float, player: Vector3, player_alive: bool) -> void:
	_think_acc += delta
	if _think_acc >= _think_dt:
		var dt: float = _think_acc
		_think_acc = 0.0
		for i: int in positions.size():
			_think(i, dt, player, player_alive)
	for i: int in positions.size():
		_move(i, delta)
		if _attack_cd[i] > 0.0:
			_attack_cd[i] -= delta


func _think(i: int, dt: float, player: Vector3, alive: bool) -> void:
	var d: Dictionary = def_of(i)
	var p: Vector3 = positions[i]
	var to_player: Vector3 = player - p
	to_player.y = 0.0
	var dist: float = to_player.length()
	var behavior: String = String(d.get("behavior", "timid"))
	var sense: float = JsonData.get_float(d, "sense_m", 15.0)
	_state_t[i] -= dt
	match states[i]:
		State.WANDER:
			if alive and dist < sense:
				_threat[i] = player
				if behavior == "timid":
					_set_state(i, State.FLEE, JsonData.get_float(d, "flee_s", 6.0))
				else:
					_set_state(i, State.ATTACK, 0.0)
				return
			if _state_t[i] <= 0.0 or Vector2(_goal[i].x - p.x, _goal[i].z - p.z).length() < 1.0:
				# Новая цель прогулки или пауза (пасётся).
				if rng.randf() < 0.35:
					_goal[i] = p
					_state_t[i] = rng.randf_range(2.0, 5.0)
				else:
					var a: float = rng.randf() * TAU
					var r: float = rng.randf_range(6.0, 20.0)
					_goal[i] = p + Vector3(cos(a) * r, 0.0, sin(a) * r)
					_state_t[i] = rng.randf_range(6.0, 12.0)
			speeds[i] = 0.0 if _goal[i].is_equal_approx(p) else JsonData.get_float(d, "walk", 1.5)
		State.FLEE:
			var away: Vector3 = p - _threat[i]
			away.y = 0.0
			if away.length_squared() < 0.01:
				away = Vector3(cos(yaws[i]), 0.0, sin(yaws[i]))
			_goal[i] = p + away.normalized() * 12.0
			speeds[i] = JsonData.get_float(d, "run", 6.0)
			if _state_t[i] <= 0.0:
				_set_state(i, State.WANDER, 0.0)
		State.ATTACK:
			if not alive or dist > JsonData.get_float(d, "leash_m", 40.0):
				_set_state(i, State.WANDER, 0.0)
				return
			_goal[i] = player
			var reach: float = JsonData.get_float(d, "attack_range", 1.8)
			speeds[i] = 0.0 if dist <= reach * 0.8 else JsonData.get_float(d, "run", 6.0)
			if dist <= reach and absf(player.y - p.y) < 2.5 and _attack_cd[i] <= 0.0:
				_attack_cd[i] = JsonData.get_float(d, "attack_cd", 1.2)
				attacked.emit(i, JsonData.get_float(d, "damage", 5.0), kind_id(i))


## Свободна ли точка для животного (суша, не круто, не постройка, внутри карты).
func can_stand(from: Vector3, to: Vector3) -> bool:
	if absf(to.x) > half - 2.0 or absf(to.z) > half - 2.0:
		return false
	var h: float = terrain.height_at(to.x, to.z)
	if h < water_level + 0.2:
		return false
	var run: float = Vector2(to.x - from.x, to.z - from.z).length()
	if run > 0.01 and absf(h - from.y) / run > _max_slope:
		return false
	if building != null and building.blocks_box(AABB(Vector3(to.x - 0.4, h + 0.3, to.z - 0.4), Vector3(0.8, 1.0, 0.8))):
		return false
	return true


const _DETOURS: PackedFloat32Array = [0.0, 0.61, -0.61, 1.22, -1.22, 1.83, -1.83]


func _move(i: int, delta: float) -> void:
	if speeds[i] <= 0.0:
		return
	var p: Vector3 = positions[i]
	var want: Vector3 = _goal[i] - p
	want.y = 0.0
	if want.length_squared() < 0.04:
		return
	var base_yaw: float = atan2(want.x, want.z)
	for off: float in _DETOURS:
		var yaw: float = base_yaw + off
		var dir: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
		if not can_stand(p, p + dir * 2.0):
			continue
		var np: Vector3 = p + dir * speeds[i] * delta
		np.y = terrain.height_at(np.x, np.z)
		positions[i] = np
		# Плавный поворот к направлению движения.
		yaws[i] = lerp_angle(yaws[i], yaw, minf(delta * 8.0, 1.0))
		return
	# Путь закрыт со всех сторон: стоим, на прогулке выбираем другую цель.
	if states[i] == State.WANDER:
		_state_t[i] = 0.0


# --- Появление и исчезновение ----------------------------------------------

## Раз в spawn.interval_s: убирает дальних, добавляет новых в кольце вокруг игрока по биомам.
## biome_at — Callable(x, z) -> int (номер биома WorldGen) или пустой Callable (все биомы одинаковы).
func populate(delta: float, player: Vector3, biome_at: Callable) -> void:
	_spawn_acc += delta
	var sp: Dictionary = _cfg.get("spawn", {})
	if _spawn_acc < JsonData.get_float(sp, "interval_s", 3.0):
		return
	_spawn_acc = 0.0
	var despawn: float = JsonData.get_float(sp, "despawn_m", 220.0)
	var i: int = positions.size() - 1
	while i >= 0:
		if Vector2(positions[i].x - player.x, positions[i].z - player.z).length() > despawn:
			remove(i)
		i -= 1
	if positions.size() >= JsonData.get_int(sp, "max_near", 10):
		return
	var r0: float = JsonData.get_float(sp, "radius_min", 45.0)
	var r1: float = JsonData.get_float(sp, "radius_max", 140.0)
	var a: float = rng.randf() * TAU
	var r: float = rng.randf_range(r0, r1)
	var p: Vector3 = player + Vector3(cos(a) * r, 0.0, sin(a) * r)
	p.y = terrain.height_at(p.x, p.z)
	if not can_stand(p, p):
		return
	var b: String = WorldGen.biome_id(int(biome_at.call(p.x, p.z))) if biome_at.is_valid() else "plain"
	var total: float = 0.0
	for k: int in defs.size():
		total += maxf(JsonData.get_float(defs[k].get("biomes", {}), b, 0.0), 0.0)
	if total <= 0.0:
		return
	var pick: float = rng.randf() * total
	for k: int in defs.size():
		pick -= maxf(JsonData.get_float(defs[k].get("biomes", {}), b, 0.0), 0.0)
		if pick <= 0.0:
			var group: int = maxi(JsonData.get_int(defs[k], "group", 1), 1)
			for g: int in group:
				var gp: Vector3 = p + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
				if can_stand(p, gp):
					spawn(kind_ids[k], gp, rng.randf() * TAU)
			return
