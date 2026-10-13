extends GutTest
## Животные (бродит / бежит / атакует, steering по рельефу) и снаряды; бой в сессии: копьё, лук,
## самопал с перезарядкой, прочность, туша с мясом и шкурой.

var acfg: Dictionary


func before_all() -> void:
	acfg = JsonData.load_dict(AnimalSim.DEFAULT_PATH)


func _sim() -> AnimalSim:
	var a: AnimalSim = AnimalSim.new()
	a.configure(acfg, TerrainMath.new(1, 0.0), -10.0, 500.0)
	a.rng.seed = 7
	return a


func _run(a: AnimalSim, seconds: float, player: Vector3, alive: bool = true) -> void:
	var t: float = 0.0
	while t < seconds:
		a.tick(0.05, player, alive)
		t += 0.05


func test_three_species_from_data() -> void:
	var a: AnimalSim = _sim()
	for id: String in ["deer", "wolf", "bear"]:
		assert_true(a.kind_ids.has(id), id)


func test_deer_wanders_then_flees_from_player() -> void:
	var a: AnimalSim = _sim()
	var d: int = a.spawn("deer", Vector3(0.0, 0.0, 0.0))
	_run(a, 10.0, Vector3(200.0, 0.0, 200.0))
	assert_eq(a.states[d], AnimalSim.State.WANDER, "далеко от игрока — бродит")
	var p0: Vector3 = a.positions[d]
	var player: Vector3 = p0 + Vector3(8.0, 0.0, 0.0)
	_run(a, 0.3, player)
	assert_eq(a.states[d], AnimalSim.State.FLEE, "игрок рядом — бежит")
	_run(a, 2.0, player)
	assert_gt(a.positions[d].distance_to(player), p0.distance_to(player) + 8.0, "убегает от игрока")


func test_wolf_chases_and_bites() -> void:
	var a: AnimalSim = _sim()
	var w: int = a.spawn("wolf", Vector3(0.0, 0.0, 0.0))
	watch_signals(a)
	var player: Vector3 = Vector3(15.0, 0.0, 0.0)
	_run(a, 4.0, player)
	assert_eq(a.states[w], AnimalSim.State.ATTACK, "волк атакует")
	assert_lt(a.positions[w].distance_to(player), 2.5, "догнал")
	assert_signal_emitted(a, "attacked", "укусил")
	_run(a, 1.0, player, false)
	assert_eq(a.states[w], AnimalSim.State.WANDER, "мёртвого не преследует")


func test_wolf_flees_when_hurt_and_dies() -> void:
	var a: AnimalSim = _sim()
	var w: int = a.spawn("wolf", Vector3(0.0, 0.0, 0.0))
	watch_signals(a)
	a.damage(w, 65.0, Vector3(3.0, 0.0, 0.0))
	assert_eq(a.states[w], AnimalSim.State.FLEE, "раненый волк убегает")
	assert_true(a.damage(w, 30.0, Vector3.ZERO), "добит")
	assert_eq(a.count(), 0)
	assert_signal_emitted(a, "died")


func test_bear_attacks_when_hit_from_afar() -> void:
	var a: AnimalSim = _sim()
	var b: int = a.spawn("bear", Vector3(0.0, 0.0, 0.0))
	_run(a, 1.0, Vector3(30.0, 0.0, 0.0))
	assert_eq(a.states[b], AnimalSim.State.WANDER)
	a.damage(b, 20.0, Vector3(30.0, 0.0, 0.0))
	assert_eq(a.states[b], AnimalSim.State.ATTACK, "медведь отвечает на удар")


func test_animals_avoid_water_and_stay_on_ground() -> void:
	var a: AnimalSim = AnimalSim.new()
	# Вода выше уровня рельефа при z > 0: TerrainMath с нулевой амплитудой — ровно 0; вода на 0.5 — везде.
	a.configure(acfg, TerrainMath.new(1, 0.0), 0.5, 500.0)
	assert_false(a.can_stand(Vector3.ZERO, Vector3(1.0, 0.0, 0.0)), "в воду нельзя")
	var real: WorldGen = WorldGen.load_default()
	var b: AnimalSim = AnimalSim.new()
	b.configure(acfg, real, real.water_level, real.grid.half)
	b.rng.seed = 3
	var d: int = b.spawn("deer", real.landing + Vector3(0.0, 0.0, -30.0))
	for k: int in 400:
		b.tick(0.05, real.landing + Vector3(0.0, 0.0, -20.0), true)
	var p: Vector3 = b.positions[d]
	assert_gt(real.height_at(p.x, p.z), real.water_level, "олень не зашёл в море")
	assert_almost_eq(p.y, real.height_at(p.x, p.z), 0.01, "стоит на рельефе")


func test_population_spawns_in_ring_and_despawns_far() -> void:
	var a: AnimalSim = _sim()
	var player: Vector3 = Vector3.ZERO
	for k: int in 40:
		a.populate(3.1, player, Callable())
	assert_gt(a.count(), 3)
	assert_lt(a.count(), int(acfg["spawn"]["max_near"]) + 3)
	for i: int in a.count():
		var d: float = Vector2(a.positions[i].x, a.positions[i].z).length()
		assert_gt(d, float(acfg["spawn"]["radius_min"]) - 5.0)
	a.populate(3.1, Vector3(400.0, 0.0, 400.0), Callable())
	for i: int in a.count():
		assert_lt(Vector2(a.positions[i].x - 400.0, a.positions[i].z - 400.0).length(), float(acfg["spawn"]["despawn_m"]))


func test_projectile_hits_animal_with_gravity_drop() -> void:
	var a: AnimalSim = _sim()
	var w: int = a.spawn("wolf", Vector3(0.0, 0.0, -20.0))
	var pr: Projectiles = Projectiles.new()
	pr.animals = a
	pr.terrain = a.terrain
	watch_signals(pr)
	pr.fire(Vector3(0.0, 0.8, 0.0), Vector3(0.0, 0.0, -48.0), 42.0, 9.8, "arrow")
	for k: int in 40:
		pr.tick(1.0 / 60.0)
	assert_eq(pr.count(), 0)
	var params: Array = pr.get_signal_parameters("impact")
	assert_eq(params[0], Projectiles.Hit.ANIMAL)
	assert_eq(params[1], w)
	assert_almost_eq(a.hp[w], 80.0 - 42.0, 0.01, "урон стрелы")


func test_projectile_falls_to_ground() -> void:
	var pr: Projectiles = Projectiles.new()
	pr.terrain = TerrainMath.new(1, 0.0)
	watch_signals(pr)
	pr.fire(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -20.0), 10.0, 9.8, "arrow")
	for k: int in 120:
		pr.tick(1.0 / 60.0)
	assert_eq(pr.count(), 0)
	var params: Array = pr.get_signal_parameters("impact")
	assert_eq(params[0], Projectiles.Hit.GROUND)
	assert_between(-(params[2] as Vector3).z, 5.0, 15.0, "стрела упала по баллистике")


# --- Бой в сессии -------------------------------------------------------------

func _session() -> SurvivalSession:
	var t: TerrainMath = TerrainMath.new(1, 0.0)
	var field: ResourceField = ResourceField.generate({"types": []}, t, 128.0, -10.0)
	return SurvivalSession.create(t, field, -10.0)


func _hold(s: SurvivalSession, id: String) -> int:
	s.inventory.add(id, 1)
	for i: int in Inventory.HOTBAR_SIZE:
		if s.inventory.slot_id(i) == id:
			s.select_slot(i)
			return i
	return -1


func test_spear_melee_hurts_animal_and_wears() -> void:
	var s: SurvivalSession = _session()
	var slot: int = _hold(s, "stone_spear")
	var d: int = s.animals.spawn("deer", Vector3(0.0, 0.0, -2.8))
	var dur: int = s.inventory.slot_durability(slot)
	watch_signals(s)
	assert_eq(s.primary(Vector3(0.0, 0.9, 0.0), Vector3.FORWARD, Vector3.ZERO, 0.0), SurvivalSession.Primary.SWING)
	assert_almost_eq(s.animals.hp[d], 60.0 - 32.0, 0.01, "копьё достаёт на 2,8 м")
	assert_eq(s.inventory.slot_durability(slot), dur - 1, "прочность копья")
	assert_signal_emitted(s, "hit_confirmed")
	assert_eq(s.animals.states[d], AnimalSim.State.FLEE)


func test_axe_does_not_reach_as_far_as_spear() -> void:
	var s: SurvivalSession = _session()
	_hold(s, "stone_axe")
	var d: int = s.animals.spawn("deer", Vector3(0.0, 0.0, -3.4))
	s.primary(Vector3(0.0, 0.9, 0.0), Vector3.FORWARD, Vector3.ZERO, 0.0)
	assert_almost_eq(s.animals.hp[d], 60.0, 0.01, "топор не достаёт")


func test_bow_uses_arrows_and_kills_deer_carcass_has_meat_and_hide() -> void:
	var s: SurvivalSession = _session()
	var slot: int = _hold(s, "bow")
	s.inventory.add("arrow", 3)
	var d: int = s.animals.spawn("deer", Vector3(0.0, 0.0, -15.0))
	s.aiming = true
	assert_eq(s.primary_kind(), SurvivalSession.Primary.SHOOT)
	assert_eq(s.primary(Vector3(0.0, 1.0, 0.0), Vector3.FORWARD, Vector3.ZERO, 0.0), SurvivalSession.Primary.SHOOT)
	assert_eq(s.inventory.count_of("arrow"), 2, "стрела потрачена")
	assert_eq(s.inventory.slot_durability(slot), s.items.max_durability("bow") - 1, "износ лука")
	for k: int in 30:
		s.tick(1.0 / 60.0)
	assert_lt(s.animals.hp[d], 60.0, "стрела попала")
	s.tick(1.1)
	s.animals.positions[d] = Vector3(0.0, 0.0, -10.0)
	s.primary(Vector3(0.0, 1.0, 0.0), Vector3.FORWARD, Vector3.ZERO, 0.0)
	for k: int in 30:
		s.tick(1.0 / 60.0)
	assert_eq(s.animals.count(), 0, "олень убит двумя стрелами")
	assert_eq(s.containers.dynamic_count(), 1, "туша")
	var h: int = s.containers.d_handle[0]
	assert_eq(s.containers.storage_of(h).count_of("meat"), 6)
	assert_eq(s.containers.storage_of(h).count_of("hide"), 4)


func test_bow_without_arrows_does_nothing() -> void:
	var s: SurvivalSession = _session()
	_hold(s, "bow")
	watch_signals(s)
	assert_eq(s.primary(Vector3.UP, Vector3.FORWARD, Vector3.ZERO, 0.0), SurvivalSession.Primary.NONE)
	assert_signal_emitted_with_parameters(s, "notice", ["NOTICE_NO_AMMO", "arrow"])


func test_gun_needs_reload_then_fires_once() -> void:
	var s: SurvivalSession = _session()
	var slot: int = _hold(s, "crude_gun")
	s.inventory.add("gun_ammo", 3)
	# Пустой магазин: выстрел запускает перезарядку.
	assert_eq(s.primary(Vector3.UP, Vector3.FORWARD, Vector3.ZERO, 0.0), SurvivalSession.Primary.NONE)
	assert_true(s.is_reloading())
	assert_false(s.can_swing(), "во время перезарядки не стреляет")
	s.tick(2.5)
	assert_false(s.is_reloading())
	assert_eq(s.inventory.slot_ammo(slot), 1, "заряжен")
	assert_eq(s.inventory.count_of("gun_ammo"), 2)
	assert_eq(s.ammo_status(), Vector2i(1, 2))
	var w: int = s.animals.spawn("wolf", Vector3(0.0, 0.0, -15.0))
	s.aiming = true
	assert_eq(s.primary(Vector3(0.0, 0.6, 0.0), Vector3.FORWARD, Vector3.ZERO, 0.0), SurvivalSession.Primary.SHOOT)
	assert_eq(s.inventory.slot_ammo(slot), 0)
	for k: int in 20:
		s.tick(1.0 / 60.0)
	assert_eq(s.animals.count(), 1)
	assert_almost_eq(s.animals.hp[w], 80.0 - 70.0, 0.01, "пуля самопала: урон 70")
	assert_eq(s.inventory.slot_durability(slot), s.items.max_durability("crude_gun") - 1, "износ самопала")


func test_reload_cancelled_when_switching_slot() -> void:
	var s: SurvivalSession = _session()
	var slot: int = _hold(s, "crude_gun")
	s.inventory.add("gun_ammo", 2)
	assert_true(s.reload())
	s.select_slot((slot + 1) % Inventory.HOTBAR_SIZE)
	s.tick(3.0)
	assert_false(s.is_reloading())
	assert_eq(s.inventory.slot_ammo(slot), 0, "перезарядка отменена")
	assert_eq(s.inventory.count_of("gun_ammo"), 2, "патроны не потеряны")


func test_wolf_bite_damages_player_and_kills_with_cause() -> void:
	var s: SurvivalSession = _session()
	s.inventory.add("wood", 30)
	s.animals.spawn("wolf", Vector3(1.0, 0.0, 0.0))
	watch_signals(s)
	var t: float = 0.0
	while not s.stats.is_dead() and t < 60.0:
		s.tick(0.1)
		t += 0.1
	assert_true(s.stats.is_dead(), "волк загрыз")
	assert_signal_emitted(s, "player_hurt")
	assert_signal_emitted_with_parameters(s, "player_died", ["wolf"])
	assert_eq(s.inventory.count_of("wood"), 0, "вещи ушли в мешок")
	assert_true(s.containers.is_valid(s.last_bag), "мешок на месте гибели")
	assert_eq(s.containers.storage_of(s.last_bag).count_of("wood"), 30)
