extends GutTest
## Дымовой тест: игровая сцена загружается, ландшафт строится в потоке, персонаж стоит на земле.

var _scene: Node


func after_each() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
	get_tree().paused = false
	await wait_physics_frames(2)


func test_game_scene_builds_terrain_and_player_lands() -> void:
	_scene = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(_scene)
	var terrain: TestTerrain = _scene.get_node("Terrain")
	await wait_until(func() -> bool: return terrain.is_built, 10.0)
	assert_true(terrain.is_built, "ландшафт построен")
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
