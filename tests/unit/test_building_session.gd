extends GutTest
## Сценарий приёмки этапа 2 на реальных данных из data/ (без сцены, ровный участок):
## дом из всех деталей по сетке тремя материалами, дверь с кодовым замком (чужой не открывает),
## ящик с вещами, знамя базы и право строить, износ без обслуживания, сохранение и загрузка.

const HUT_FEET: Vector3 = Vector3(3.0, 0.25, 7.0)

var s: SurvivalSession
var hy: int


func _new_session() -> SurvivalSession:
	var t: TerrainMath = TerrainMath.new(1, 0.0)
	var ses: SurvivalSession = SurvivalSession.new()
	ses.setup(ItemDB.load_default(), t, ResourceField.new(), -10.0, {
		"game": JsonData.load_dict(SurvivalSession.GAME_CFG_PATH),
		"recipes": JsonData.load_dict(Crafting.DEFAULT_PATH),
		"survival": JsonData.load_dict(SurvivalStats.DEFAULT_PATH),
		"day_night": JsonData.load_dict(DayNightCycle.DEFAULT_PATH),
		"deployables": JsonData.load_dict(Deployables.DEFAULT_PATH),
		"building": JsonData.load_dict(BuildingDefs.DEFAULT_PATH),
	})
	return ses


func before_each() -> void:
	s = _new_session()
	hy = s.building.foundation_hy(0, 0)
	s.inventory.add("wood", 3000)
	s.inventory.add("stone", 1000)
	s.inventory.add("metal", 400)
	s.inventory.add("code_lock", 1)
	_stand(HUT_FEET, Vector3(0, 0, -1))


func _stand(feet: Vector3, look: Vector3) -> void:
	s.set_player_pose(feet, 0.0, 0.0)
	s.set_look_ray(feet + Vector3(0, 1.65, 0), look.normalized())


func _place(type: String, key: Vector4i, mat: int = 0, rot: int = 0) -> int:
	var p: BuildingGrid.Placement = BuildingGrid.Placement.new()
	p.type = type
	p.material = mat
	p.key = key
	p.rot = rot
	p.depth = s.building.foundation_depth(key.x, key.y, key.z)
	var r: SurvivalSession.Build = s.build_place(p)
	assert_eq(r, SurvivalSession.Build.OK, "%s в %s: причина %d" % [type, key, p.reason])
	return s.building.id_at(key)


func _edge(cx: int, side: int, level: int = 0, door: bool = false) -> Vector4i:
	return BuildingGrid.edge_key(cx, 0, hy + level * 12, side, door)


## Дом на 2 клетки: фундаменты, 5 стен + проём с дверью, перекрытие над (0,0), лестница в (1,0),
## на втором этаже стена и крыша над (0,0).
func _build_house() -> void:
	_place("foundation", Vector4i(0, 0, hy, BuildingGrid.Slot.CELL))
	_place("foundation", Vector4i(1, 0, hy, BuildingGrid.Slot.CELL))
	for e: Vector4i in [_edge(0, 0), _edge(0, 3), _edge(1, 0), _edge(1, 1), _edge(1, 2)]:
		_place("wall", e)
	_place("doorway", _edge(0, 2))
	_place("door", _edge(0, 2, 0, true))
	_place("floor", Vector4i(0, 0, hy + 12, BuildingGrid.Slot.CELL))
	_place("stairs", Vector4i(1, 0, hy, BuildingGrid.Slot.STAIRS), 0, 3)
	_place("wall", _edge(0, 0, 1))
	_place("roof", Vector4i(0, 0, hy + 24, BuildingGrid.Slot.CELL), 0, 2)


func test_build_house_from_all_pieces_and_three_materials() -> void:
	var wood0: int = s.inventory.count_of("wood")
	_build_house()
	assert_eq(s.building.count(), 13, "все детали поставлены")
	assert_lt(s.inventory.count_of("wood"), wood0, "ресурсы списаны")
	# Улучшение: дерево → камень → металл.
	var wall: int = s.building.id_at(_edge(0, 0))
	_stand(HUT_FEET, Vector3(0, 0, -1))
	assert_eq(s.build_upgrade(wall), SurvivalSession.Build.OK)
	assert_eq(s.building.p_mat[wall], 1, "камень")
	assert_eq(s.build_upgrade(wall), SurvivalSession.Build.OK)
	assert_eq(s.building.p_mat[wall], 2, "металл")
	assert_eq(s.build_upgrade(wall), SurvivalSession.Build.MAX_LEVEL)
	# Сразу каменная деталь.
	_place("foundation", Vector4i(2, 0, hy, BuildingGrid.Slot.CELL), 1)
	assert_eq(s.building.p_mat[s.building.id_at(Vector4i(2, 0, hy, BuildingGrid.Slot.CELL))], 1)
	var door: int = s.building.id_at(_edge(0, 2, 0, true))
	assert_eq(s.build_upgrade(door), SurvivalSession.Build.OK, "дверь: дерево → металл")
	assert_eq(s.building.p_mat[door], 2)


func test_not_enough_resources() -> void:
	s.inventory.clear_all()
	var p: BuildingGrid.Placement = BuildingGrid.Placement.new()
	p.type = "foundation"
	p.key = Vector4i(0, 0, hy, BuildingGrid.Slot.CELL)
	p.depth = 1.0
	assert_eq(s.build_place(p), SurvivalSession.Build.NO_RESOURCES)
	assert_eq(s.building.count(), 0)


func test_session_rechecks_place_from_client() -> void:
	# «Клиент» прислал заведомо неверное место — сессия перепроверяет и отказывает.
	var p: BuildingGrid.Placement = BuildingGrid.Placement.new()
	p.type = "wall"
	p.key = _edge(0, 0)
	p.reason = BuildingGrid.Reason.OK
	assert_eq(s.build_place(p), SurvivalSession.Build.BAD_PLACE)
	assert_eq(p.reason, BuildingGrid.Reason.NO_SUPPORT)


func test_ghost_suggest_follows_view() -> void:
	var p: BuildingGrid.Placement = BuildingGrid.Placement.new()
	_stand(Vector3(1.5, 0.0, 6.0), Vector3(0, 0, -1))
	s.build_suggest("foundation", 0, 0, p)
	assert_true(p.is_valid())
	assert_eq(s.build_check(p), SurvivalSession.Build.OK)
	assert_eq(s.build_place(p), SurvivalSession.Build.OK)


func test_door_code_lock_stranger_cannot_open() -> void:
	_build_house()
	var door: int = s.building.id_at(_edge(0, 2, 0, true))
	# Смотрим на дверь снаружи (с юга).
	_stand(Vector3(1.5, 0.0, 5.0), Vector3(0, -0.15, -1))
	assert_eq(s.interact_kind(s.player_position, 0.0), SurvivalSession.Interact.OPEN_DOOR)
	assert_eq(s.lock_attach(door, "12a4"), SurvivalSession.Build.BAD_CODE)
	assert_eq(s.lock_attach(door, "5821"), SurvivalSession.Build.OK)
	assert_eq(s.inventory.count_of("code_lock"), 0, "замок потрачен")
	assert_eq(s.interact(s.player_position, 0.0), SurvivalSession.Interact.OPEN_DOOR, "хозяин открывает")
	assert_true(s.building.is_open(door))
	s.interact(s.player_position, 0.0)
	assert_false(s.building.is_open(door), "и закрывает")
	# Чужой игрок.
	s.player_id = "stranger"
	assert_eq(s.interact(s.player_position, 0.0), SurvivalSession.Interact.UNLOCK, "чужому — ввод кода")
	assert_false(s.building.is_open(door), "дверь не открылась")
	assert_eq(s.lock_enter(door, "0000"), SurvivalSession.Build.BAD_CODE)
	assert_false(s.building.is_open(door))
	assert_eq(s.lock_change(door, "1111"), SurvivalSession.Build.LOCKED, "сменить код чужой не может")
	assert_eq(s.lock_enter(door, "5821"), SurvivalSession.Build.OK, "с кодом — открыл")
	assert_true(s.building.is_open(door))
	s.player_id = "local"
	assert_eq(s.lock_change(door, "7777"), SurvivalSession.Build.OK)
	s.player_id = "stranger"
	assert_false(s.building.can_use_door(door, "stranger"), "после смены кода снова чужой")


func test_storage_box_keeps_items() -> void:
	_build_house()
	s.inventory.add("storage_box", 1)
	var slot: int = -1
	for i: int in Inventory.HOTBAR_SIZE:
		if s.inventory.slot_id(i) == "storage_box":
			slot = i
	s.select_slot(slot)
	var feet: Vector3 = Vector3(1.5, defs_top(), 2.6)
	_stand(feet, Vector3(0, 0, -1))
	assert_true(s.place_active(feet, 0.0), "ящик стоит в доме")
	var box: int = s.deployables.size() - 1
	assert_eq(s.deployables.kinds[box], "storage_box")
	assert_almost_eq(s.deployables.positions[box].y, defs_top(), 0.01, "на полу (верх фундамента)")
	assert_eq(s.interact_kind(feet, 0.0), SurvivalSession.Interact.STORAGE)
	var metal_slot: int = -1
	for i: int in Inventory.EQUIP_START:
		if s.inventory.slot_id(i) == "metal":
			metal_slot = i
	assert_eq(s.storage_put(box, metal_slot), 400)
	assert_eq(s.inventory.count_of("metal"), 0)
	assert_eq(s.deployables.storages[box].count_of("metal"), 400)
	# Сохранение и загрузка — вещи в ящике на месте.
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var s2: SurvivalSession = _new_session()
	assert_eq(s2.from_dict(d), PackedStringArray())
	assert_eq(s2.deployables.storages[box].count_of("metal"), 400, "вещи в ящике сохранились")
	s2.set_player_pose(feet, 0.0, 0.0)
	assert_eq(s2.storage_take(box, 0), 400)
	assert_eq(s2.inventory.count_of("metal"), 400)
	s2.set_player_pose(Vector3(40, 0, 40), 0.0, 0.0)
	assert_eq(s2.storage_put(box, 0), 0, "издалека в ящик не положить")


func defs_top() -> float:
	return s.building.defs.height_of(hy)


func test_banner_privilege_blocks_stranger() -> void:
	s.inventory.add("base_banner", 1)
	for i: int in Inventory.HOTBAR_SIZE:
		if s.inventory.slot_id(i) == "base_banner":
			s.select_slot(i)
	assert_true(s.place_active(Vector3(8.0, 0.0, 8.0), 0.0), "знамя поставлено")
	var banner: int = s.deployables.size() - 1
	assert_true(s.claims.is_banner(banner))
	_build_house()
	s.player_id = "stranger"
	var p: BuildingGrid.Placement = BuildingGrid.Placement.new()
	p.type = "foundation"
	p.key = Vector4i(2, 0, hy, BuildingGrid.Slot.CELL)
	p.depth = 1.0
	assert_eq(s.build_place(p), SurvivalSession.Build.NO_PRIVILEGE, "чужой не строит в зоне знамени")
	var wall: int = s.building.id_at(_edge(0, 0))
	assert_eq(s.build_demolish(wall), SurvivalSession.Build.NO_PRIVILEGE, "и не разбирает")
	assert_eq(s.build_upgrade(wall), SurvivalSession.Build.NO_PRIVILEGE)
	# Добрался до знамени — стал своим (жанровое правило: защищайте знамя стенами и дверью с замком).
	s.set_player_pose(Vector3(8.0, 0.0, 9.0), 0.0, 0.0)
	assert_eq(s.storage_take(banner, 0), 0, "запас знамени чужому не взять")
	assert_true(s.claim_authorize(banner))
	_stand(HUT_FEET, Vector3(0, 0, -1))
	assert_eq(s.build_place(p), SurvivalSession.Build.OK)


func test_decay_without_upkeep_and_repair() -> void:
	_build_house()
	var wall: int = s.building.id_at(_edge(1, 1))
	var full: float = s.building.max_hp(wall)
	s.tick(600.0)
	assert_lt(s.building.p_hp[wall], full, "без обслуживания постройка изнашивается")
	assert_eq(s.build_repair(wall), SurvivalSession.Build.OK)
	assert_almost_eq(s.building.p_hp[wall], full, 0.001, "починили")
	assert_eq(s.build_repair(wall), SurvivalSession.Build.FULL_HP)
	# Знамя с запасом — износа нет.
	s.inventory.add("base_banner", 1)
	for i: int in Inventory.HOTBAR_SIZE:
		if s.inventory.slot_id(i) == "base_banner":
			s.select_slot(i)
	assert_true(s.place_active(Vector3(8.0, 0.0, 8.0), 0.0))
	var banner: int = s.deployables.size() - 1
	s.set_player_pose(Vector3(8.0, 0.0, 9.0), 0.0, 0.0)
	s.deployables.storages[banner].add("wood", 1000)
	s.deployables.storages[banner].add("metal", 100)
	s.tick(1200.0)
	assert_almost_eq(s.building.p_hp[wall], full, 0.001, "обслуживание оплачено")
	assert_lt(s.deployables.storages[banner].count_of("wood"), 1000, "дерево списано")


func test_decay_destroys_and_collapses_house_objects_drop() -> void:
	_build_house()
	s.inventory.add("storage_box", 1)
	for i: int in Inventory.HOTBAR_SIZE:
		if s.inventory.slot_id(i) == "storage_box":
			s.select_slot(i)
	assert_true(s.place_active(Vector3(1.5, defs_top(), 2.8), 0.0))
	var box: int = s.deployables.size() - 1
	# Дерево полностью ветшает за decay_full_s.
	for k: int in 120:
		s.tick(s.building.defs.decay_full_s(0) / 100.0)
	assert_eq(s.building.count(), 0, "всё разрушилось")
	assert_almost_eq(s.deployables.positions[box].y, 0.0, 0.01, "ящик опустился на землю")


func test_demolish_refunds_half_and_lock() -> void:
	_build_house()
	var door: int = s.building.id_at(_edge(0, 2, 0, true))
	s.lock_attach(door, "1234")
	var wood0: int = s.inventory.count_of("wood")
	assert_eq(s.build_demolish(door), SurvivalSession.Build.OK)
	assert_eq(s.inventory.count_of("wood"), wood0 + 25, "половина стоимости двери")
	assert_eq(s.inventory.count_of("code_lock"), 1, "замок вернулся")


## С этапа 3 цепочка идёт до v3: детали и объекты лежат в разделе chunks.
func test_save_v1_migrates_to_v3() -> void:
	var v1: Dictionary = {"world": {"seed": 1}, "deployables": {"objects": [["campfire", 5.0, 0.0, 5.0, 0.0, 30.0]]}}
	var m: SaveMigrator = SaveGame._make_migrator()
	var res: Dictionary = m.migrate(v1, 1)
	assert_true(res["ok"])
	assert_true((res["data"] as Dictionary).has("chunks"), "v1 → v2 → v3: мир по чанкам")
	assert_false((res["data"] as Dictionary).has("building"), "детали перенесены в чанки")
	var s2: SurvivalSession = _new_session()
	var w: PackedStringArray = s2.from_dict(res["data"])
	assert_false(w.has("building_skipped_1"))
	assert_eq(s2.deployables.size(), 1, "костёр из старого сохранения на месте")
	assert_eq(s2.deployables.owners[0], "")
	assert_eq(s2.building.count(), 0)


func test_full_save_load_of_house() -> void:
	_build_house()
	var door: int = s.building.id_at(_edge(0, 2, 0, true))
	s.lock_attach(door, "4321")
	s.build_upgrade(s.building.id_at(_edge(1, 1)))
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var s2: SurvivalSession = _new_session()
	assert_eq(s2.from_dict(d), PackedStringArray())
	assert_eq(s2.building.count(), s.building.count())
	var d2: int = s2.building.id_at(_edge(0, 2, 0, true))
	assert_true(s2.building.has_lock(d2), "замок сохранился")
	assert_false(s2.building.can_use_door(d2, "stranger"))
	assert_eq(s2.building.p_mat[s2.building.id_at(_edge(1, 1))], 1, "камень сохранился")
