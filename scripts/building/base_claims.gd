class_name BaseClaims
extends RefCounted
## Право владения, обслуживание и износ построек (этап 2). Чистая логика без сцен.
##
## Знамя базы (размещаемый объект с claim_radius_m) задаёт зону права: внутри неё строить,
## улучшать, разбирать, ставить объекты и замки могут только игроки из списка знамени.
## Обслуживание: раз в tick_s знамя списывает из своего хранилища долю стоимости деталей своей
## зоны (upkeep_fraction_per_hour). Если ресурсов хватило — детали зоны не изнашиваются.
## Детали вне зон и в зонах без оплаты теряют прочность (полностью за decay_full_s материала)
## и разрушаются; всё, что держалось на них, обрушивается (BuildingGrid.remove_piece).

## Знамя заплатило или не смогло заплатить за обслуживание (для интерфейса).
signal upkeep_paid(banner: int, ok: bool)

var grid: BuildingGrid
var deployables: Deployables

var _acc: float = 0.0
## Индекс знамени -> {предмет: накопленная дробная часть оплаты}.
var _debt: Dictionary = {}
## Индекс знамени -> хватило ли ресурсов на последнем шаге.
var _paid: Dictionary = {}
var _protected: PackedByteArray = PackedByteArray()
var _ids: PackedInt32Array = PackedInt32Array()


func _init(p_grid: BuildingGrid = null, p_dep: Deployables = null) -> void:
	grid = p_grid
	deployables = p_dep


func is_banner(index: int) -> bool:
	return index >= 0 and index < deployables.size() and deployables.claim_radius(deployables.kinds[index]) > 0.0


## Знамя, в зоне которого точка (ближайшее из покрывающих), или -1.
func claim_at(pos: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in deployables.size():
		var r: float = deployables.claim_radius(deployables.kinds[i])
		if r <= 0.0:
			continue
		var p: Vector3 = deployables.positions[i]
		var d: float = Vector2(p.x - pos.x, p.z - pos.z).length_squared()
		if d <= r * r and d < best_d:
			best_d = d
			best = i
	return best


## Может ли who строить, разбирать и ставить объекты в точке.
func can_build(who: String, pos: Vector3) -> bool:
	var c: int = claim_at(pos)
	return c < 0 or deployables.is_authorized(c, who)


## Можно ли поставить новое знамя в точку (не внутри чужой или своей зоны).
func can_place_banner(pos: Vector3) -> bool:
	return claim_at(pos) < 0


## Детали, за которые платит знамя banner (те, для которых оно ближайшее покрывающее).
func pieces_of(banner: int, out: PackedInt32Array) -> void:
	out.clear()
	var r: float = deployables.claim_radius(deployables.kinds[banner])
	grid.ids_within(deployables.positions[banner], r, _ids)
	for id: int in _ids:
		if claim_at(grid.piece_aabb(id).get_center()) == banner:
			out.append(id)


## Расход на обслуживание за час игры: {предмет: количество (дробное)}.
func upkeep_per_hour(banner: int) -> Dictionary:
	var out: Dictionary = {}
	var ids: PackedInt32Array = PackedInt32Array()
	pieces_of(banner, ids)
	for id: int in ids:
		var mat: int = grid.p_mat[id]
		var frac: float = grid.defs.upkeep_fraction(mat)
		var cost: Dictionary = grid.defs.cost(grid.p_type[id], mat)
		for item: String in cost:
			out[item] = float(out.get(item, 0.0)) + float(cost[item]) * frac
	return out


## На сколько часов игры хватит запаса знамени (INF — нечего обслуживать).
func hours_left(banner: int) -> float:
	var per: Dictionary = upkeep_per_hour(banner)
	var st: ItemStorage = deployables.storages[banner]
	var h: float = INF
	for item: String in per:
		var need: float = float(per[item])
		if need <= 0.0:
			continue
		var have: int = st.count_of(item) if st != null else 0
		h = minf(h, float(have) / need)
	return h


func was_paid(banner: int) -> bool:
	return bool(_paid.get(banner, true))


func is_protected(id: int) -> bool:
	return id >= 0 and id < _protected.size() and _protected[id] != 0


## Шаг обслуживания и износа. Возвращает удалённые (разрушенные и обрушившиеся) детали.
func tick(delta: float) -> PackedInt32Array:
	_acc += delta
	if _acc < grid.defs.tick_s:
		return PackedInt32Array()
	var dt: float = _acc
	_acc = 0.0
	return step(dt)


## Один шаг длиной dt секунд (тесты вызывают напрямую).
func step(dt: float) -> PackedInt32Array:
	_protected.resize(grid.capacity())
	_protected.fill(0)
	var ids: PackedInt32Array = PackedInt32Array()
	for b: int in deployables.size():
		if not is_banner(b):
			continue
		pieces_of(b, ids)
		if ids.is_empty():
			continue
		var ok: bool = _pay(b, ids, dt)
		if ok:
			for id: int in ids:
				_protected[id] = 1
		if bool(_paid.get(b, true)) != ok:
			_paid[b] = ok
			upkeep_paid.emit(b, ok)
	var removed: PackedInt32Array = PackedInt32Array()
	for id: int in grid.capacity():
		if not grid.is_alive(id) or _protected[id] != 0:
			continue
		var loss: float = grid.max_hp(id) * dt / grid.defs.decay_full_s(grid.p_mat[id])
		removed.append_array(grid.damage(id, loss))
	return removed


func _pay(banner: int, ids: PackedInt32Array, dt: float) -> bool:
	var debt: Dictionary = _debt.get(banner, {})
	var hours: float = dt / 3600.0
	for id: int in ids:
		var mat: int = grid.p_mat[id]
		var frac: float = grid.defs.upkeep_fraction(mat) * hours
		var cost: Dictionary = grid.defs.cost(grid.p_type[id], mat)
		for item: String in cost:
			debt[item] = float(debt.get(item, 0.0)) + float(cost[item]) * frac
	var st: ItemStorage = deployables.storages[banner]
	for item: String in debt:
		var need: int = int(floor(float(debt[item])))
		if need > 0 and (st == null or st.count_of(item) < need):
			# Не хватило — в этот шаг постройки изнашиваются; долг не копится.
			_debt[banner] = {}
			return false
	for item: String in debt:
		var need2: int = int(floor(float(debt[item])))
		if need2 > 0:
			st.remove(item, need2)
			debt[item] = float(debt[item]) - float(need2)
	_debt[banner] = debt
	return true


func to_dict() -> Dictionary:
	var debts: Dictionary = {}
	for b: int in _debt:
		debts[str(b)] = _debt[b]
	return {"acc": snappedf(_acc, 0.01), "debt": debts}


func from_dict(d: Dictionary) -> void:
	_acc = JsonData.get_float(d, "acc", 0.0)
	_debt.clear()
	_paid.clear()
	var debts: Variant = d.get("debt", {})
	if typeof(debts) != TYPE_DICTIONARY:
		return
	for k: Variant in debts:
		var b: int = int(String(k))
		if is_banner(b) and typeof(debts[k]) == TYPE_DICTIONARY:
			_debt[b] = debts[k]
