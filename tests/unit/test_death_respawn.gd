extends GutTest
## Смерть и возрождение (этап 3): мешок с вещами на месте гибели, возрождение у спальника или кровати
## (с перезарядкой), иначе на побережье; мир по WorldGen — высадка на берегу.

func _session_world() -> SurvivalSession:
	var g: WorldGen = WorldGen.load_default()
	# Узлы не нужны — пустое поле с сеткой мира.
	var field: ResourceField = ResourceField.generate_world({"types": []}, g)
	return SurvivalSession.create(g, field, g.water_level)


func _place(s: SurvivalSession, item: String, pos: Vector3) -> int:
	return s.deployables.place(s.items.deploy_type(item), pos, 0.0, s.player_id)


func test_new_game_starts_on_landing_beach() -> void:
	var s: SurvivalSession = _session_world()
	assert_eq(s.player_position, s.world.landing)
	assert_eq(s.spawn_point, s.world.landing)
	assert_gt(s.coast_points.size(), 10)


func test_death_drops_bag_and_respawn_on_coast() -> void:
	var s: SurvivalSession = _session_world()
	s.inventory.add("wood", 40)
	s.inventory.add("stone_axe", 1)
	s.player_position = s.world.landing + Vector3(0.0, 0.0, -10.0)
	var death_pos: Vector3 = s.player_position
	s.stats.damage(1000.0, "fall")
	assert_true(s.containers.is_valid(s.last_bag))
	assert_almost_eq(s.containers.position_of(s.last_bag).x, death_pos.x, 0.01, "мешок на месте гибели")
	assert_eq(s.respawn_points().size(), 0, "спальников нет")
	s.respawn(-1)
	assert_false(s.stats.is_dead())
	assert_true(s.coast_points.has(s.player_position), "возрождение на побережье")
	assert_eq(s.inventory.count_of("wood"), 0)
	# Вернуться к мешку и забрать вещи.
	s.player_position = death_pos
	var h: int = s.containers.nearest(death_pos)
	assert_eq(h, s.last_bag)
	assert_eq(s.interact_kind(death_pos, 0.0), SurvivalSession.Interact.LOOT)
	var st: ItemStorage = s.containers.storage_of(h)
	for slot: int in st.size():
		s.container_take(h, slot)
	assert_eq(s.inventory.count_of("wood"), 40)
	assert_eq(s.inventory.count_of("stone_axe"), 1)
	assert_false(s.containers.is_valid(h), "пустой мешок исчез")


func test_crafting_queue_refunded_into_bag() -> void:
	var s: SurvivalSession = _session_world()
	s.inventory.add("wood", 30)
	s.inventory.add("stone", 15)
	assert_eq(s.craft("stone_axe"), Crafting.Check.OK)
	assert_eq(s.inventory.count_of("wood"), 0)
	s.stats.damage(1000.0, "test")
	assert_eq(s.containers.storage_of(s.last_bag).count_of("wood"), 30, "ингредиенты из очереди — в мешке")


func test_respawn_at_sleeping_bag_with_cooldown() -> void:
	var s: SurvivalSession = _session_world()
	var p: Vector3 = s.world.landing + Vector3(4.0, 0.0, -6.0)
	p.y = s.terrain.height_at(p.x, p.z)
	var bag: int = _place(s, "sleeping_bag", p)
	assert_ne(bag, -1)
	var other: int = s.deployables.place("sleeping_bag", p + Vector3(5.0, 0.0, 0.0), 0.0, "stranger")
	assert_ne(other, -1)
	var pts: Array[Dictionary] = s.respawn_points()
	assert_eq(pts.size(), 1, "только свой спальник")
	assert_eq(pts[0]["name"], "DEPLOY_SLEEPING_BAG")
	s.stats.damage(1000.0, "test")
	s.respawn(bag)
	assert_lt(s.player_position.distance_to(p), 2.0, "возрождение у спальника")
	assert_gt(float(s.respawn_points()[0]["cooldown"]), 200.0, "перезарядка спальника")
	s.stats.damage(1000.0, "test")
	s.respawn(bag)
	assert_true(s.coast_points.has(s.player_position), "на перезарядке — побережье")
	s.stats.damage(1000.0, "test")
	s.respawn(other)
	assert_true(s.coast_points.has(s.player_position), "у чужого спальника нельзя")
	s.tick(400.0)
	assert_true(s.can_respawn_at(bag), "перезарядка прошла")


func test_bed_shorter_cooldown_and_saved() -> void:
	var s: SurvivalSession = _session_world()
	var p: Vector3 = s.world.landing + Vector3(-4.0, 0.0, -6.0)
	p.y = s.terrain.height_at(p.x, p.z)
	var bed: int = _place(s, "bed", p)
	s.stats.damage(1000.0, "test")
	s.respawn(bed)
	var cd: float = float(s.respawn_points()[0]["cooldown"])
	assert_between(cd, 100.0, 121.0, "кровать — 2 минуты")
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var s2: SurvivalSession = _session_world()
	s2.from_dict(d)
	assert_eq(s2.deployables.kinds[0], "bed")
	assert_almost_eq(float(s2.respawn_points()[0]["cooldown"]), cd, 0.2, "перезарядка сохранилась")
