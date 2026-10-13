extends GutTest
## Строительство в настоящей игровой сцене: столкновения с деревьями, режим стройки
## («Поставить» ставит фундамент по призраку), дверь физически не пускает закрытой и пускает открытой,
## кодовый замок через экран цифр, ящик через экран хранилища, сохранение и «Продолжить» с постройками.

var _scene: Node


func before_all() -> void:
	SaveGame.save_dir = "user://test_saves/building_scene"


func after_all() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	SaveGame.save_dir = SaveGame.SAVE_DIR


func after_each() -> void:
	for a: StringName in [&"move_forward", &"attack", &"reload"]:
		Input.action_release(a)
	if is_instance_valid(_scene):
		_scene.queue_free()
	get_tree().paused = false
	SaveGame.continue_requested = false
	await wait_physics_frames(2)


func _start_game() -> Node:
	_scene = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(_scene)
	await wait_until(func() -> bool: return _scene.get("session") != null and bool(_scene.call("is_world_ready")), 20.0)
	await wait_physics_frames(10)
	return _scene


func _player() -> PlayerController:
	return _scene.get_node("Player")


func _session() -> SurvivalSession:
	return _scene.get("session")


func test_player_cannot_walk_through_tree() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	await _start_game()
	var s: SurvivalSession = _session()
	# Самое ровное место у дерева: ищем ближайшее к точке высадки дерево с пологим склоном к югу.
	var f: ResourceField = s.resources
	var tree: int = -1
	var sp: Vector3 = s.spawn_point
	for i: int in f.size():
		if f.item_of(i) != "wood":
			continue
		var p: Vector3 = f.positions[i]
		if absf(s.terrain.height_at(p.x, p.z + 3.0) - p.y) < 0.4 and (tree == -1 or p.distance_to(sp) < f.positions[tree].distance_to(sp)):
			tree = i
	assert_ne(tree, -1)
	var tp: Vector3 = f.positions[tree]
	await _teleport(Vector3(tp.x, s.terrain.height_at(tp.x, tp.z + 3.0) + 0.3, tp.z + 3.0))
	var w: WorldStreamer = _scene.get_node("World")
	assert_gt(w.active_collider_count(), 0, "у деревьев и камней ближних чанков есть столкновения")
	var p: PlayerController = _player()
	p.set_look(0.0, 0.0)
	await wait_physics_frames(20)
	Input.action_press(&"move_forward")
	await wait_seconds(2.0)
	Input.action_release(&"move_forward")
	var d: float = Vector2(p.global_position.x - tp.x, p.global_position.z - tp.z).length()
	assert_gt(d, f.collider_radius(tree) + 0.3, "персонаж упёрся в ствол, а не прошёл сквозь")
	assert_gt(p.global_position.z, tp.z, "остался по свою сторону ствола")


func _flat_cell(s: SurvivalSession) -> Vector2i:
	# Клетка у точки высадки, вглубь острова (там ровная площадка и нет деревьев).
	return s.building.cell_of(s.spawn_point.x + 1.5, s.spawn_point.z - 4.5)


func test_build_mode_places_foundation_by_ghost() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	await _start_game()
	var s: SurvivalSession = _session()
	s.inventory.add("wood", 500)
	var p: PlayerController = _player()
	var sp: Vector3 = s.spawn_point
	p.activate_at(sp + Vector3(1.5, 0.3, 0.0))
	p.set_look(0.0, deg_to_rad(-10.0))
	await wait_physics_frames(20)
	_scene.call("set_build_mode", true)
	assert_true(_scene.call("is_build_mode"))
	assert_true((_scene.get_node("BuildPanel") as BuildPanel).visible, "панель стройки открыта")
	await wait_seconds(0.3)
	var ghost: BuildGhost = _scene.get_node("BuildGhost")
	assert_true(ghost.visible, "призрак фундамента виден")
	Input.action_press(&"attack")
	await wait_process_frames(3)
	Input.action_release(&"attack")
	assert_eq(s.building.count(), 1, "«Поставить» ставит фундамент")
	assert_lt(s.inventory.count_of("wood"), 500)
	await wait_process_frames(3)
	var view: BuildingView = _scene.get_node("Building")
	assert_eq(view.find_children("Body_*", "StaticBody3D", false, false).size(), 1, "у детали есть тело столкновений")
	var mmi: MultiMeshInstance3D = view.get_node("Pieces_foundation_0")
	assert_eq(mmi.multimesh.instance_count, 1, "фундамент нарисован")
	# «Повернуть» (кнопка «Перезар.») в режиме стройки меняет поворот, а не стреляет.
	Input.action_press(&"reload")
	await wait_process_frames(2)
	Input.action_release(&"reload")
	assert_eq(_scene.get("_build_rot"), 1)
	_scene.call("set_build_mode", false)
	assert_false(ghost.visible)


## Фундамент, проём на южной стороне и дверь. Возвращает id двери.
func _door_hut(s: SurvivalSession) -> int:
	var c: Vector2i = _flat_cell(s)
	var b: BuildingGrid = s.building
	var hy: int = b.foundation_hy(c.x, c.y)
	b.add_piece("foundation", 0, Vector4i(c.x, c.y, hy, BuildingGrid.Slot.CELL), 0, s.player_id)
	b.add_piece("doorway", 0, BuildingGrid.edge_key(c.x, c.y, hy, 2, false), 0, s.player_id)
	return b.add_piece("door", 0, BuildingGrid.edge_key(c.x, c.y, hy, 2, true), 0, s.player_id)


func _stand_on_hut(s: SurvivalSession, yaw: float) -> void:
	var c: Vector2i = _flat_cell(s)
	var hy: int = s.building.foundation_hy(c.x, c.y)
	_player().activate_at(Vector3((c.x + 0.5) * 3.0, s.building.defs.height_of(hy) + 0.3, (c.y + 0.5) * 3.0))
	_player().set_look(yaw, deg_to_rad(-12.0))


func test_door_blocks_when_closed_and_lets_through_when_open() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	await _start_game()
	var s: SurvivalSession = _session()
	var door: int = _door_hut(s)
	var south_z: float = float(_flat_cell(s).y + 1) * 3.0
	await wait_process_frames(3)
	_stand_on_hut(s, PI)
	await wait_physics_frames(20)
	Input.action_press(&"move_forward")
	await wait_seconds(1.5)
	Input.action_release(&"move_forward")
	assert_lt(_player().global_position.z, south_z, "закрытая дверь не пускает")
	_stand_on_hut(s, PI)
	await wait_seconds(0.3)
	_scene.call("_do_interact")
	assert_true(s.building.is_open(door), "кнопка «Взять» открыла дверь")
	await wait_seconds(0.5)
	Input.action_press(&"move_forward")
	await wait_seconds(1.5)
	Input.action_release(&"move_forward")
	assert_gt(_player().global_position.z, south_z + 0.3, "в открытую дверь можно выйти")


func test_code_lock_keypad_in_scene() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	await _start_game()
	var s: SurvivalSession = _session()
	var door: int = _door_hut(s)
	s.building.attach_lock(door, s.player_id, "2468")
	s.player_id = "stranger"
	_stand_on_hut(s, PI)
	await wait_seconds(0.3)
	_scene.call("_do_interact")
	var keypad: KeypadScreen = _scene.get_node("KeypadScreen")
	assert_true(keypad.is_open(), "чужому — экран кода")
	assert_false(s.building.is_open(door))
	for d: String in ["1", "1", "1", "1"]:
		keypad.press_digit(d)
	keypad.call("_on_ok")
	assert_false(s.building.is_open(door), "неверный код — дверь закрыта")
	assert_true(keypad.is_open(), "можно попробовать снова")
	for d: String in ["2", "4", "6", "8"]:
		keypad.press_digit(d)
	keypad.call("_on_ok")
	assert_true(s.building.is_open(door), "верный код открыл дверь")
	assert_false(keypad.is_open())


func test_storage_screen_moves_items() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	await _start_game()
	var s: SurvivalSession = _session()
	s.inventory.add("storage_box", 1)
	s.inventory.add("stone", 40)
	for i: int in Inventory.HOTBAR_SIZE:
		if s.inventory.slot_id(i) == "storage_box":
			s.select_slot(i)
	var p: PlayerController = _player()
	p.activate_at(s.spawn_point + Vector3(0.0, 0.3, 0.0))
	p.set_look(0.0, deg_to_rad(-30.0))
	await wait_physics_frames(20)
	assert_true(s.place_active(p.global_position, 0.0), "ящик поставлен")
	await wait_seconds(0.3)
	_scene.call("_do_interact")
	var screen: StorageScreen = _scene.get_node("StorageScreen")
	assert_true(screen.is_open(), "экран ящика открыт")
	var stone_slot: int = -1
	for i: int in Inventory.EQUIP_START:
		if s.inventory.slot_id(i) == "stone":
			stone_slot = i
	screen.call("_on_inv_tapped", stone_slot)
	assert_eq(s.inventory.count_of("stone"), 0, "камень переложен в ящик")
	assert_eq(s.deployables.storages[screen.current_index()].count_of("stone"), 40)
	screen.call("_on_box_tapped", 0)
	assert_eq(s.inventory.count_of("stone"), 40, "и обратно")
	screen.close()
	assert_false(screen.is_open())


func test_save_and_continue_keeps_buildings() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	await _start_game()
	var s: SurvivalSession = _session()
	var door: int = _door_hut(s)
	s.building.attach_lock(door, s.player_id, "1357")
	var n: int = s.building.count()
	_scene.call("_save_now")
	_scene.queue_free()
	await wait_process_frames(2)
	SaveGame.continue_requested = true
	await _start_game()
	var s2: SurvivalSession = _session()
	assert_eq(s2.building.count(), n, "постройки на месте")
	var c: Vector2i = _flat_cell(s2)
	var d2: int = s2.building.id_at(BuildingGrid.edge_key(c.x, c.y, s2.building.foundation_hy(c.x, c.y), 2, true))
	assert_true(s2.building.has_lock(d2), "замок на месте")
	await wait_process_frames(3)
	var view: BuildingView = _scene.get_node("Building")
	assert_eq(view.find_children("Body_*", "StaticBody3D", false, false).size(), 2, "тела фундамента и проёма")
	assert_eq(view.find_children("Door_*", "Node3D", false, false).size(), 1, "дверь")
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)

## Перенести персонажа в pos, дождавшись подгрузки чанка со столкновениями (рельеф и деревья).
func _teleport(pos: Vector3) -> void:
	var p: PlayerController = _scene.get_node("Player")
	p.deactivate()
	p.global_position = pos
	var w: WorldStreamer = _scene.get_node("World")
	await wait_until(func() -> bool: return w.is_collision_ready(pos) and w.colliders_ready(pos), 15.0)
	p.activate_at(pos)
