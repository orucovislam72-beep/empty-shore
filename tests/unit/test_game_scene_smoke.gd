extends GutTest
## Дымовые тесты игровой сцены: ландшафт строится в потоке, персонаж стоит на земле,
## сессия выживания работает в сцене (удар по дереву → дерево в инвентаре),
## сохранение и «Продолжить» восстанавливают состояние.

var _scene: Node


func before_all() -> void:
	# Отдельная папка: тесты не трогают сохранения игрока.
	SaveGame.save_dir = "user://test_saves/scene"


func after_all() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	SaveGame.save_dir = SaveGame.SAVE_DIR


func after_each() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
	get_tree().paused = false
	SaveGame.continue_requested = false
	await wait_physics_frames(2)


func _start_game() -> Node:
	_scene = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(_scene)
	var terrain: TestTerrain = _scene.get_node("Terrain")
	await wait_until(func() -> bool: return terrain.is_built and _scene.get("session") != null, 10.0)
	return _scene


func test_game_scene_builds_terrain_and_player_lands() -> void:
	await _start_game()
	var terrain: TestTerrain = _scene.get_node("Terrain")
	assert_true(terrain.is_built, "ландшафт построен")
	assert_gt(terrain.resource_field.size(), 100, "ресурсные узлы расставлены")
	var player: PlayerController = _scene.get_node("Player")
	await wait_physics_frames(90)
	assert_true(player.is_on_floor(), "персонаж стоит на земле")
	var ground_y: float = terrain.height_at(player.global_position.x, player.global_position.z)
	assert_almost_eq(player.global_position.y, ground_y, 0.5)


func test_pause_toggles_tree_pause() -> void:
	_scene = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(_scene)
	await wait_process_frames(2)
	Events.pause_requested.emit()
	assert_true(get_tree().paused)
	Events.pause_requested.emit()
	assert_false(get_tree().paused, "повторный сигнал закрывает паузу")


func test_gather_in_scene_then_save_and_continue() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	await _start_game()
	var session: SurvivalSession = _scene.get("session")
	var player: PlayerController = _scene.get_node("Player")
	await wait_physics_frames(30)
	# Ставим игрока перед ближайшим деревом и смотрим на него.
	var f: ResourceField = session.resources
	var tree: int = -1
	for i: int in f.size():
		if f.item_of(i) == "wood" and (tree == -1 or f.positions[i].length() < f.positions[tree].length()):
			tree = i
	var c: Vector3 = f.hit_center(tree)
	var stand: Vector3 = f.positions[tree] + Vector3(0.0, 0.0, 2.0)
	player.activate_at(stand + Vector3(0.0, 0.2, 0.0))
	player.set_look(0.0, 0.0)
	await wait_physics_frames(20)
	var cam: Camera3D = _scene.get_node("Player/Head/Camera")
	var dir: Vector3 = (c - cam.global_position).normalized()
	player.set_look(atan2(-dir.x, -dir.z), asin(clampf(dir.y, -1.0, 1.0)))
	await wait_process_frames(2)
	Input.action_press("attack")
	await wait_seconds(2.0)
	Input.action_release("attack")
	assert_gt(session.inventory.count_of("wood"), 0, "удар по дереву в сцене добывает дерево")
	var wood: int = session.inventory.count_of("wood")
	# Сохранение и продолжение.
	_scene.call("_save_now")
	assert_true(SaveGame.has_slot(SaveGame.MAIN_SLOT))
	_scene.queue_free()
	await wait_process_frames(2)
	SaveGame.continue_requested = true
	await _start_game()
	var s2: SurvivalSession = _scene.get("session")
	assert_eq(s2.inventory.count_of("wood"), wood, "дерево сохранилось")
	assert_lt(s2.resources.remaining[tree], s2.resources.stock_of(tree), "запас дерева сохранился")
	var p2: PlayerController = _scene.get_node("Player")
	assert_almost_eq(p2.global_position.x, stand.x, 1.0, "игрок там же")
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)


func test_inventory_screen_opens_and_crafts() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	await _start_game()
	var session: SurvivalSession = _scene.get("session")
	session.inventory.add("wood", 40)
	session.inventory.add("stone", 15)
	var inv_screen: InventoryScreen = _scene.get_node("InventoryScreen")
	_scene.call("_toggle_inventory")
	assert_true(inv_screen.is_open())
	inv_screen.call("_on_craft", "stone_axe")
	assert_eq(session.crafting.queue.size(), 1, "топор в очереди")
	await wait_seconds(4.5)
	assert_eq(session.inventory.count_of("stone_axe"), 1, "топор сделан, пока открыт экран")
	_scene.call("_toggle_inventory")
	assert_false(inv_screen.is_open())


func test_inventory_tap_tap_and_drop_move_items() -> void:
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	await _start_game()
	var session: SurvivalSession = _scene.get("session")
	session.inventory.add("wood", 10)
	var from: int = Inventory.BACKPACK_START
	assert_eq(session.inventory.slot_id(from), "wood")
	var inv_screen: InventoryScreen = _scene.get_node("InventoryScreen")
	_scene.call("_toggle_inventory")
	# «Нажми-нажми»: выбрать предмет, затем пустую ячейку быстрой панели.
	inv_screen.call("_on_slot_tapped", from)
	inv_screen.call("_on_slot_tapped", 3)
	assert_eq(session.inventory.slot_id(3), "wood", "перенос нажатиями")
	# Перетаскивание: проверки ячейки-приёмника и сам перенос.
	var target: InventorySlot = null
	for n: Node in inv_screen.find_children("*", "InventorySlot", true, false):
		if (n as InventorySlot).slot == Inventory.EQUIP_START:
			target = n
	assert_not_null(target)
	assert_false(target.call("_can_drop_data", Vector2.ZERO, {"inv_slot": 3}), "дерево не надеть на голову")
	var back: InventorySlot = null
	for n: Node in inv_screen.find_children("*", "InventorySlot", true, false):
		if (n as InventorySlot).slot == from + 5:
			back = n
	assert_true(back.call("_can_drop_data", Vector2.ZERO, {"inv_slot": 3}))
	back.call("_drop_data", Vector2.ZERO, {"inv_slot": 3})
	assert_eq(session.inventory.slot_id(from + 5), "wood", "перенос перетаскиванием")
	_scene.call("_toggle_inventory")
