extends GutTest
## Игровая сессия на реальных данных из data/: сценарий приёмки этапа 1 без сцены
## (добыть дерево и камень → топор и костёр → сохранить → загрузить и продолжить),
## а также еда, вода, смерть и возрождение.

const SAVE_PATH: String = "user://test_saves/session.json"
const WALK_SPEED: float = 4.0

var terrain: TerrainMath
var water: float


func _new_session() -> SurvivalSession:
	var tcfg: Dictionary = JsonData.load_dict("res://tests/data/small_map.json")
	terrain = TerrainMath.from_config(tcfg)
	water = JsonData.get_float(tcfg, "water_level", -4.0)
	var half: float = JsonData.get_float(tcfg, "size_m", 256.0) * 0.5
	var field: ResourceField = ResourceField.generate(JsonData.load_dict(ResourceField.DEFAULT_PATH), terrain, half, water)
	return SurvivalSession.create(terrain, field, water)


func _nearest_node(s: SurvivalSession, item: String, from: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in s.resources.size():
		if s.resources.item_of(i) != item or not s.resources.is_available(i):
			continue
		var dd: float = s.resources.positions[i].distance_to(from)
		if dd < best_d:
			best_d = dd
			best = i
	return best


## Бьёт по ближайшим узлам, пока не наберёт need предметов. Возвращает затраченные игровые секунды
## (удары + дорога пешком от точки появления и обратно).
func _gather_until(s: SurvivalSession, item: String, need: int) -> float:
	var t: float = 0.0
	var guard: int = 0
	while s.inventory.count_of(item) < need and guard < 500:
		guard += 1
		var node: int = _nearest_node(s, item, s.spawn_point)
		assert_ne(node, -1, "есть узел с %s" % item)
		if node == -1:
			return INF
		var p: Vector3 = s.resources.positions[node]
		if guard == 1 or not s.resources.is_available(node):
			t += 2.0 * p.distance_to(s.spawn_point) / WALK_SPEED
		# Встаём в 2 м от узла и смотрим на центр — как игрок.
		var c: Vector3 = s.resources.hit_center(node)
		var eye: Vector3 = c + Vector3(2.0, 0.3, 0.0)
		var target: int = s.resources.find_target(eye, (c - eye).normalized())
		assert_eq(target, node, "луч взгляда попадает в узел")
		var r: SurvivalSession.Primary = s.primary(eye, (c - eye).normalized(), p, 0.0)
		assert_eq(r, SurvivalSession.Primary.SWING)
		var swing: float = s.items.swing_time(s.active_item())
		s.tick(swing)
		t += swing
	return t


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func test_acceptance_wood_stone_axe_campfire_save_continue() -> void:
	var s: SurvivalSession = _new_session()
	assert_eq(s.inventory.count_of("wood"), 0, "начинаем с пустыми руками")
	var spent: float = 0.0
	spent += _gather_until(s, "wood", 70)
	spent += _gather_until(s, "stone", 25)
	assert_gte(s.inventory.count_of("wood"), 70)
	assert_gte(s.inventory.count_of("stone"), 25)

	assert_eq(s.craft("stone_axe"), Crafting.Check.OK)
	assert_eq(s.craft("campfire"), Crafting.Check.OK)
	var craft_t: float = s.crafting.time_of("stone_axe") + s.crafting.time_of("campfire")
	for k: int in 20:
		s.tick(craft_t / 10.0)
	spent += craft_t
	assert_eq(s.inventory.count_of("stone_axe"), 1, "топор сделан")
	assert_eq(s.inventory.count_of("campfire"), 1, "костёр сделан")
	gut.p("Сценарий приёмки: %.0f с игрового времени (лимит 900 с)" % spent)
	assert_lt(spent, 900.0, "укладываемся в 15 минут")

	# Топор быстрее рук.
	var axe_slot: int = -1
	var fire_slot: int = -1
	for i: int in Inventory.HOTBAR_SIZE:
		if s.inventory.slot_id(i) == "stone_axe":
			axe_slot = i
		if s.inventory.slot_id(i) == "campfire":
			fire_slot = i
	assert_ne(axe_slot, -1, "топор в быстрой панели")
	assert_gt(s.items.gather_multiplier("stone_axe", "wood"), s.items.gather_multiplier("", "wood"))

	# Ставим костёр и проверяем станцию.
	s.select_slot(fire_slot)
	assert_eq(s.primary_kind(), SurvivalSession.Primary.PLACE)
	s.tick(1.0)
	var feet: Vector3 = s.spawn_point
	assert_eq(s.primary(feet + Vector3.UP, Vector3.FORWARD, feet, 0.0), SurvivalSession.Primary.PLACE)
	assert_eq(s.deployables.size(), 1)
	s.player_position = feet
	assert_true(s.stations_at(feet).has("campfire"), "горящий костёр — станция")
	s.select_slot(axe_slot)
	s.set_player_pose(feet + Vector3(1.0, 0.0, 0.0), 1.25, -0.2)
	s.tick(30.0)

	# Сохраняем через тот же SaveFile, что и игра (конверт с версией, запись через .tmp).
	var file: SaveFile = SaveFile.new(SaveMigrator.new(SaveGame.FORMAT_VERSION))
	assert_eq(file.write(SAVE_PATH, s.to_dict()), OK)
	var res: Dictionary = file.read(SAVE_PATH)
	assert_true(res["ok"], "сохранение читается")

	var s2: SurvivalSession = _new_session()
	var warnings: PackedStringArray = s2.from_dict(res["data"])
	assert_eq(warnings.size(), 0, "загрузка без предупреждений: %s" % [warnings])
	assert_eq(s2.inventory.count_of("stone_axe"), 1)
	assert_eq(s2.inventory.count_of("wood"), s.inventory.count_of("wood"))
	assert_eq(s2.inventory.count_of("stone"), s.inventory.count_of("stone"))
	assert_eq(s2.deployables.size(), 1, "костёр на месте")
	assert_almost_eq(s2.deployables.fuel[0], s.deployables.fuel[0], 0.1)
	assert_eq(s2.active_slot, axe_slot)
	assert_almost_eq(s2.player_position.x, feet.x + 1.0, 0.02)
	assert_almost_eq(s2.player_yaw, 1.25, 0.002)
	assert_almost_eq(s2.clock.total_hours(), s.clock.total_hours(), 0.002)
	assert_almost_eq(s2.stats.hunger, s.stats.hunger, 0.01)
	var depleted_before: int = 0
	var depleted_after: int = 0
	for i: int in s.resources.size():
		if s.resources.remaining[i] != s.resources.stock_of(i):
			depleted_before += 1
		if s2.resources.remaining[i] != s2.resources.stock_of(i):
			depleted_after += 1
	assert_gt(depleted_before, 0)
	assert_eq(depleted_after, depleted_before, "состояние узлов восстановлено")
	# Продолжаем играть: топором рубим быстрее.
	var wood_before: int = s2.inventory.count_of("wood")
	var node: int = _nearest_node(s2, "wood", s2.spawn_point)
	assert_gt(s2.gather(node), 5, "топор даёт больше 5 дерева за удар")
	assert_gt(s2.inventory.count_of("wood"), wood_before)


func test_eat_berries_and_drink_water() -> void:
	var s: SurvivalSession = _new_session()
	s.inventory.add("berries", 3)
	s.stats.hunger = 10.0
	assert_true(s.eat_slot(0))
	assert_gt(s.stats.hunger, 10.0)
	assert_eq(s.inventory.count_of("berries"), 2)
	# Находим точку у воды.
	var shore: Vector3 = Vector3.INF
	for x: int in range(-120, 120, 2):
		for z: int in range(-120, 120, 2):
			if shore == Vector3.INF and terrain.height_at(float(x), float(z)) < water - 0.2:
				shore = Vector3(float(x), water, float(z))
	assert_ne(shore, Vector3.INF, "на карте есть вода")
	s.stats.thirst = 10.0
	assert_eq(s.interact_kind(shore, 0.0), SurvivalSession.Interact.DRINK)
	assert_eq(s.interact(shore, 0.0), SurvivalSession.Interact.DRINK)
	assert_gt(s.stats.thirst, 10.0)
	assert_eq(s.interact_kind(s.spawn_point, 0.0), SurvivalSession.Interact.NONE, "в точке появления воды нет")


func test_ore_needs_pickaxe() -> void:
	var s: SurvivalSession = _new_session()
	var node: int = _nearest_node(s, "metal_ore", s.spawn_point)
	watch_signals(s)
	assert_eq(s.gather(node), 0)
	assert_signal_emitted_with_parameters(s, "notice", ["NOTICE_NEED_PICKAXE", "metal_ore"])
	s.inventory.add("stone_pickaxe", 1)
	assert_gt(s.gather(node), 0)


func test_refuel_campfire_with_wood() -> void:
	var s: SurvivalSession = _new_session()
	var p: Vector3 = s.spawn_point
	s.deployables.place("campfire", p, 0.0)
	s.inventory.add("wood", 3)
	assert_eq(s.interact_kind(p, 0.0), SurvivalSession.Interact.REFUEL)
	var f: float = s.deployables.fuel[0]
	assert_eq(s.interact(p, 0.0), SurvivalSession.Interact.REFUEL)
	assert_gt(s.deployables.fuel[0], f)
	assert_eq(s.inventory.count_of("wood"), 0)


func test_death_and_respawn() -> void:
	var s: SurvivalSession = _new_session()
	s.inventory.add("wood", 10)
	watch_signals(s)
	s.stats.damage(1000.0, "test")
	assert_signal_emitted(s, "player_died")
	assert_eq(s.primary(Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO, 0.0), SurvivalSession.Primary.NONE, "мёртвый не действует")
	s.respawn()
	assert_false(s.stats.is_dead())
	assert_eq(s.inventory.count_of("wood"), 0, "на этапе 1 вещи при гибели теряются")
	assert_eq(s.player_position, s.spawn_point)
