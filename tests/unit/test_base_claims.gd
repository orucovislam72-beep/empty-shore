extends GutTest
## Право владения (знамя базы), обслуживание из запаса знамени и износ построек без обслуживания.

var g: BuildingGrid
var dep: Deployables
var claims: BaseClaims
var db: ItemDB


func before_each() -> void:
	db = ItemDB.load_default()
	g = BuildingGrid.new(BuildingDefs.load_default(), TerrainMath.new(1, 0.0), -10.0)
	dep = Deployables.new()
	dep.db = db
	dep.configure(JsonData.load_dict(Deployables.DEFAULT_PATH))
	claims = BaseClaims.new(g, dep)


func _foundation(cx: int, cz: int, mat: int = 0) -> int:
	return g.add_piece("foundation", mat, Vector4i(cx, cz, g.foundation_hy(cx, cz), BuildingGrid.Slot.CELL), 0, "alice")


func test_privilege_zone() -> void:
	assert_true(claims.can_build("bob", Vector3(5, 0, 5)), "без знамени строить может любой")
	var b: int = dep.place("base_banner", Vector3(0, 0, 0), 0.0, "alice")
	assert_true(claims.is_banner(b))
	assert_true(dep.is_authorized(b, "alice"), "поставивший — свой")
	assert_true(claims.can_build("alice", Vector3(5, 0, 5)))
	assert_false(claims.can_build("bob", Vector3(5, 0, 5)), "чужой в зоне не строит")
	assert_true(claims.can_build("bob", Vector3(30, 0, 0)), "за радиусом 18 м — можно")
	assert_false(claims.can_place_banner(Vector3(10, 0, 0)), "второе знамя в зоне нельзя")
	dep.authorize(b, "bob")
	assert_true(claims.can_build("bob", Vector3(5, 0, 5)))
	dep.deauthorize(b, "bob")
	assert_false(claims.can_build("bob", Vector3(5, 0, 5)))


func test_decay_without_banner_destroys_piece() -> void:
	var id: int = _foundation(0, 0)
	var full: float = g.max_hp(id)
	var decay_s: float = g.defs.decay_full_s(0)
	claims.step(decay_s * 0.5)
	assert_almost_eq(g.p_hp[id], full * 0.5, 0.5, "за половину срока — половина прочности")
	var removed: PackedInt32Array = claims.step(decay_s * 0.6)
	assert_false(g.is_alive(id), "без обслуживания деталь разрушилась")
	assert_true(removed.has(id))


func test_stone_lasts_longer_than_wood() -> void:
	var wood: int = _foundation(0, 0, 0)
	var stone: int = _foundation(5, 5, 1)
	claims.step(g.defs.decay_full_s(0) * 0.5)
	assert_gt(g.p_hp[stone] / g.max_hp(stone), g.p_hp[wood] / g.max_hp(wood), "камень ветшает медленнее")


func test_upkeep_paid_from_banner_stops_decay() -> void:
	var b: int = dep.place("base_banner", Vector3(1.5, 0.25, 1.5) + Vector3(6, 0, 0), 0.0, "alice")
	var id: int = _foundation(0, 0)
	var per: Dictionary = claims.upkeep_per_hour(b)
	assert_almost_eq(float(per.get("wood", 0.0)), 60.0 * 0.05, 0.001, "5 % стоимости в час")
	dep.storages[b].add("wood", 100)
	assert_almost_eq(claims.hours_left(b), 100.0 / 3.0, 0.01)
	claims.step(3600.0)
	assert_almost_eq(g.p_hp[id], g.max_hp(id), 0.001, "оплачено — не изнашивается")
	assert_true(claims.is_protected(id))
	assert_eq(dep.storages[b].count_of("wood"), 97, "списано 3 дерева за час")
	assert_true(claims.was_paid(b))


func test_upkeep_unpaid_means_decay() -> void:
	var b: int = dep.place("base_banner", Vector3(7.5, 0.25, 1.5), 0.0, "alice")
	var id: int = _foundation(0, 0)
	dep.storages[b].add("wood", 1)
	claims.step(3600.0)
	assert_false(claims.was_paid(b), "запаса не хватило")
	assert_lt(g.p_hp[id], g.max_hp(id), "постройка ветшает")
	assert_eq(dep.storages[b].count_of("wood"), 1, "неполная оплата не списывается")


func test_tick_accumulates_until_interval() -> void:
	var id: int = _foundation(0, 0)
	var full: float = g.max_hp(id)
	claims.tick(g.defs.tick_s * 0.5)
	assert_eq(g.p_hp[id], full, "до шага ничего")
	claims.tick(g.defs.tick_s * 0.6)
	assert_lt(g.p_hp[id], full)


func test_save_load_debt() -> void:
	var b: int = dep.place("base_banner", Vector3(7.5, 0.25, 1.5), 0.0, "alice")
	_foundation(0, 0)
	dep.storages[b].add("wood", 100)
	claims.step(600.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(claims.to_dict()))
	var c2: BaseClaims = BaseClaims.new(g, dep)
	c2.from_dict(d)
	assert_eq(JSON.stringify(c2.to_dict()), JSON.stringify(claims.to_dict()))
