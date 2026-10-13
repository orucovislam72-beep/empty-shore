extends GutTest
## Постройки по сетке: ключи и стороны, опора, подсказка места по взгляду, препятствия,
## обрушение без опоры, двери и кодовые замки, сохранение. Рельеф — ровный (высота 0).

const NO_FEET: Vector3 = Vector3(0.0, NAN, 0.0)

var g: BuildingGrid
var defs: BuildingDefs


func before_each() -> void:
	defs = BuildingDefs.load_default()
	g = BuildingGrid.new(defs, TerrainMath.new(1, 0.0), -10.0)


func _found(cx: int, cz: int, mat: int = 0) -> int:
	var hy: int = g.foundation_hy(cx, cz)
	var key: Vector4i = Vector4i(cx, cz, hy, BuildingGrid.Slot.CELL)
	assert_eq(g.check("foundation", mat, key, _eye_near(key), NO_FEET), BuildingGrid.Reason.OK, "фундамент %d,%d" % [cx, cz])
	return g.add_piece("foundation", mat, key, 0, "alice")


func _eye_near(key: Vector4i) -> Vector3:
	return Vector3((float(key.x) + 0.5) * defs.grid, defs.height_of(key.z) + 1.6, (float(key.y) + 0.5) * defs.grid + 2.0)


func _add(type: String, key: Vector4i, rot: int = 0) -> int:
	var r: int = g.check(type, 0, key, _eye_near(key), NO_FEET)
	assert_eq(r, BuildingGrid.Reason.OK, "%s в %s" % [type, key])
	return g.add_piece(type, 0, key, rot, "alice") if r == BuildingGrid.Reason.OK else -1


## Дом 1 клетка: фундамент, 3 стены + проём, перекрытие сверху. Возвращает hy пола.
func _hut(cx: int, cz: int) -> int:
	var hy: int = g.foundation_hy(cx, cz)
	_found(cx, cz)
	for side: int in 3:
		_add("wall", BuildingGrid.edge_key(cx, cz, hy, side, false))
	_add("doorway", BuildingGrid.edge_key(cx, cz, hy, 3, false))
	_add("floor", Vector4i(cx, cz, hy + defs.level_steps, BuildingGrid.Slot.CELL))
	return hy


func test_defs_loaded_from_data() -> void:
	assert_eq(defs.level_steps, 12, "этаж 3 м / шаг 0,25 м")
	assert_eq(defs.material_order, PackedStringArray(["wood", "stone", "metal"]))
	for type: String in ["foundation", "wall", "doorway", "door", "floor", "roof", "stairs"]:
		assert_true(defs.has_piece(type), type)
		assert_true(defs.allows(type, 0), "%s из дерева" % type)
		assert_false(defs.cost(type, 0).is_empty(), "стоимость %s" % type)
	assert_true(defs.allows("wall", 1) and defs.allows("wall", 2), "стена: три материала")
	assert_false(defs.allows("door", 1), "каменной двери нет")
	assert_eq(defs.next_material("door", 0), 2, "дверь: дерево → металл")
	assert_eq(defs.next_material("wall", 2), -1)


func test_edge_keys_are_shared_by_neighbours() -> void:
	# Южная сторона клетки (0,0) — та же граница, что северная сторона клетки (0,1).
	assert_eq(BuildingGrid.edge_key(0, 0, 4, 2, false), BuildingGrid.edge_key(0, 1, 4, 0, false))
	assert_eq(BuildingGrid.edge_key(0, 0, 4, 1, false), BuildingGrid.edge_key(1, 0, 4, 3, false))
	var cells: Array[Vector2i] = BuildingGrid.edge_cells(BuildingGrid.edge_key(2, 3, 0, 0, false))
	assert_true(cells.has(Vector2i(2, 3)) and cells.has(Vector2i(2, 2)))


func test_foundation_height_on_flat_ground_and_neighbour() -> void:
	assert_eq(g.foundation_hy(0, 0), 1, "0,15 м над землёй → 0,25 м")
	_found(0, 0)
	assert_eq(g.foundation_hy(1, 0), 1, "сосед — на той же высоте")


func test_support_rules() -> void:
	var hy: int = g.foundation_hy(0, 0)
	var wall_key: Vector4i = BuildingGrid.edge_key(0, 0, hy, 0, false)
	assert_eq(g.check("wall", 0, wall_key, _eye_near(wall_key), NO_FEET), BuildingGrid.Reason.NO_SUPPORT, "стена без фундамента")
	_found(0, 0)
	assert_eq(g.check("wall", 0, wall_key, _eye_near(wall_key), NO_FEET), BuildingGrid.Reason.OK)
	var floor_key: Vector4i = Vector4i(0, 0, hy + 12, BuildingGrid.Slot.CELL)
	assert_eq(g.check("floor", 0, floor_key, _eye_near(floor_key), NO_FEET), BuildingGrid.Reason.NO_SUPPORT, "перекрытие без стен")
	_add("wall", wall_key)
	assert_eq(g.check("floor", 0, floor_key, _eye_near(floor_key), NO_FEET), BuildingGrid.Reason.OK, "одна стена держит перекрытие")
	var door_key: Vector4i = BuildingGrid.edge_key(0, 0, hy, 2, true)
	assert_eq(g.check("door", 0, door_key, _eye_near(door_key), NO_FEET), BuildingGrid.Reason.NO_DOORWAY)
	_add("doorway", BuildingGrid.edge_key(0, 0, hy, 2, false))
	assert_eq(g.check("door", 0, door_key, _eye_near(door_key), NO_FEET), BuildingGrid.Reason.OK)
	assert_eq(g.check("door", 1, door_key, _eye_near(door_key), NO_FEET), BuildingGrid.Reason.MATERIAL, "каменной двери нет")
	var stairs_key: Vector4i = Vector4i(0, 0, hy, BuildingGrid.Slot.STAIRS)
	assert_eq(g.check("stairs", 0, stairs_key, _eye_near(stairs_key), NO_FEET), BuildingGrid.Reason.OK)


func test_occupied_and_overlap() -> void:
	var hy: int = _hut(0, 0)
	var wall_key: Vector4i = BuildingGrid.edge_key(0, 0, hy, 0, false)
	assert_eq(g.check("wall", 0, wall_key, _eye_near(wall_key), NO_FEET), BuildingGrid.Reason.OCCUPIED)
	# Лестница под перекрытием упирается в него.
	var stairs_key: Vector4i = Vector4i(0, 0, hy, BuildingGrid.Slot.STAIRS)
	assert_eq(g.check("stairs", 0, stairs_key, _eye_near(stairs_key), NO_FEET), BuildingGrid.Reason.OCCUPIED)


func test_player_and_distance_checks() -> void:
	var key: Vector4i = Vector4i(0, 0, 1, BuildingGrid.Slot.CELL)
	assert_eq(g.check("foundation", 0, key, Vector3(1.5, 2.0, 1.5), Vector3(1.5, 0.0, 1.5)), BuildingGrid.Reason.PLAYER, "игрок стоит на месте фундамента")
	assert_eq(g.check("foundation", 0, key, Vector3(1.5, 2.0, 30.0), NO_FEET), BuildingGrid.Reason.TOO_FAR)


func test_terrain_and_water_checks() -> void:
	var hill: BuildingGrid = BuildingGrid.new(defs, TerrainMath.new(3, 14.0, 0.05, 2, 0.0), -100.0)
	# Ищем клетку с большим перепадом рельефа.
	var found: bool = false
	for cx: int in range(-20, 20):
		var gr: Vector2 = hill.ground_range(cx, 7)
		if gr.y - gr.x > defs.found_max_above + 0.5:
			var hy: int = hill.foundation_hy(cx, 7)
			var key: Vector4i = Vector4i(cx, 7, hy, BuildingGrid.Slot.CELL)
			assert_eq(hill.check("foundation", 0, key, hill.aabb_of("foundation", key).get_center() + Vector3(0, 2, 0), NO_FEET), BuildingGrid.Reason.TERRAIN)
			found = true
			break
	assert_true(found, "нашлась крутая клетка")
	var wet: BuildingGrid = BuildingGrid.new(defs, TerrainMath.new(1, 0.0), 1.0)
	var k2: Vector4i = Vector4i(0, 0, wet.foundation_hy(0, 0), BuildingGrid.Slot.CELL)
	assert_eq(wet.check("foundation", 0, k2, _eye_near(k2), NO_FEET), BuildingGrid.Reason.WATER)


func test_resource_nodes_and_deployables_block() -> void:
	var t: TerrainMath = TerrainMath.new(1, 0.0)
	var field: ResourceField = ResourceField.generate({"types": [
		{"id": "tree", "item": "wood", "count": 0, "stock": 10, "collider_radius": 0.3, "collider_height": 3.0}]}, t, 50.0, -10.0)
	field._append(0, Vector3(1.5, 0.0, 1.5), 0.0, 1.0, 10)
	g.resources = field
	var key: Vector4i = Vector4i(0, 0, 1, BuildingGrid.Slot.CELL)
	assert_eq(g.check("foundation", 0, key, _eye_near(key), NO_FEET), BuildingGrid.Reason.BLOCKED, "дерево в клетке")
	field.hit(0, 100.0)
	assert_eq(g.check("foundation", 0, key, _eye_near(key), NO_FEET), BuildingGrid.Reason.BLOCKED, "срубленное дерево вырастет — тоже мешает")
	var dep: Deployables = Deployables.new()
	dep.configure({"types": {"campfire": {}}})
	dep.place("campfire", Vector3(4.5, 0.0, 1.5), 0.0)
	g.deployables = dep
	var key2: Vector4i = Vector4i(1, 0, 1, BuildingGrid.Slot.CELL)
	assert_eq(g.check("foundation", 0, key2, _eye_near(key2), NO_FEET), BuildingGrid.Reason.BLOCKED, "костёр в клетке")
	var key3: Vector4i = Vector4i(3, 0, 1, BuildingGrid.Slot.CELL)
	assert_eq(g.check("foundation", 0, key3, _eye_near(key3), NO_FEET), BuildingGrid.Reason.OK, "свободная клетка")


func test_suggest_foundation_and_walls_by_view() -> void:
	var out: BuildingGrid.Placement = BuildingGrid.Placement.new()
	# Игрок стоит южнее клетки (0,0) и смотрит на север.
	var feet: Vector3 = Vector3(1.5, 0.0, 6.0)
	var eye: Vector3 = feet + Vector3(0, 1.65, 0)
	g.suggest("foundation", 0, eye, Vector3(0, 0, -1), 0, feet, out)
	assert_eq(out.key, Vector4i(0, 0, 1, BuildingGrid.Slot.CELL), "клетка в 4 м перед игроком")
	assert_true(out.is_valid())
	g.add_piece("foundation", 0, out.key, 0, "alice", out.depth)
	# Встаём на фундамент в центр и смотрим на север: стена на северной стороне.
	feet = Vector3(1.5, 0.25, 1.5)
	eye = feet + Vector3(0, 1.65, 0)
	g.suggest("wall", 0, eye, Vector3(0, 0, -1), 0, feet, out)
	assert_eq(out.key, BuildingGrid.edge_key(0, 0, 1, 0, false))
	assert_true(out.is_valid(), "стена на краю фундамента")
	# «Повернуть» переносит стену на следующую сторону.
	g.suggest("wall", 0, eye, Vector3(0, 0, -1), 1, feet, out)
	assert_eq(out.key, BuildingGrid.edge_key(0, 0, 1, 1, false))
	# Немного неточный взгляд (в сторону и вниз) даёт ту же сторону.
	g.suggest("wall", 0, eye, Vector3(0.25, -0.2, -1).normalized(), 0, feet, out)
	assert_eq(out.key, BuildingGrid.edge_key(0, 0, 1, 0, false), "не требуем точного прицела")


func test_suggest_floor_by_looking_up() -> void:
	var hy: int = g.foundation_hy(0, 0)
	_found(0, 0)
	for side: int in 4:
		_add("wall" if side != 2 else "doorway", BuildingGrid.edge_key(0, 0, hy, side, false))
	var out: BuildingGrid.Placement = BuildingGrid.Placement.new()
	var feet: Vector3 = Vector3(1.5, 0.25, 1.5)
	var eye: Vector3 = feet + Vector3(0, 1.65, 0)
	g.suggest("floor", 0, eye, Vector3(0, 1, -1).normalized(), 0, feet, out)
	assert_eq(out.key, Vector4i(0, 0, hy + 12, BuildingGrid.Slot.CELL), "перекрытие над своей комнатой")
	assert_true(out.is_valid())
	g.suggest("door", 0, eye, Vector3(0, 0, 1), 0, feet, out)
	assert_eq(out.key, BuildingGrid.edge_key(0, 0, hy, 2, true), "дверь — в проём, на который смотрим")
	assert_true(out.is_valid())


func test_collapse_without_support() -> void:
	var hy: int = _hut(0, 0)
	var f2: int = _found(1, 0)
	assert_eq(g.count(), 1 + 4 + 1 + 1)
	var floor_id: int = g.id_at(Vector4i(0, 0, hy + 12, BuildingGrid.Slot.CELL))
	assert_true(g.is_alive(floor_id))
	var removed: PackedInt32Array = g.remove_piece(g.id_at(Vector4i(0, 0, hy, BuildingGrid.Slot.CELL)))
	# Восточная стена стоит на границе с фундаментом (1,0) — она держится; остальные падают, перекрытие держит восточная стена.
	assert_true(g.is_alive(g.id_at(BuildingGrid.edge_key(0, 0, hy, 1, false))), "стена на соседнем фундаменте стоит")
	assert_false(g.has_edge_piece(BuildingGrid.edge_key(0, 0, hy, 0, false)), "северная стена упала")
	assert_true(g.is_alive(floor_id), "перекрытие держится на оставшейся стене")
	assert_eq(removed.size(), 4, "фундамент + 3 стены")
	g.remove_piece(f2)
	assert_eq(g.count(), 0, "без фундаментов рушится всё")


func test_door_and_code_lock() -> void:
	var hy: int = _hut(0, 0)
	var door: int = _add("door", BuildingGrid.edge_key(0, 0, hy, 3, true))
	assert_true(g.is_door(door))
	assert_true(g.toggle_door(door, "bob"), "без замка открывает любой")
	assert_true(g.is_open(door))
	assert_false(g.attach_lock(door, "alice", "12a4"), "код только из цифр")
	assert_false(g.attach_lock(door, "alice", "123"), "ровно 4 цифры")
	assert_true(g.attach_lock(door, "alice", "0420"))
	assert_false(g.is_open(door), "замок закрывает дверь")
	assert_false(g.toggle_door(door, "bob"), "чужой без кода не открывает")
	assert_false(g.enter_code(door, "bob", "1111"))
	assert_false(g.can_use_door(door, "bob"))
	assert_true(g.toggle_door(door, "alice"), "хозяин открывает")
	g.toggle_door(door, "alice")
	assert_true(g.enter_code(door, "bob", "0420"), "верный код")
	assert_true(g.toggle_door(door, "bob"), "узнал код — открывает")
	assert_false(g.change_code(door, "carol", "9999"), "сменить код может только знающий")
	assert_true(g.change_code(door, "alice", "9999"))
	assert_false(g.can_use_door(door, "bob"), "после смены кода надо знать новый")


func test_find_target_prefers_door() -> void:
	var hy: int = _hut(0, 0)
	var door: int = _add("door", BuildingGrid.edge_key(0, 0, hy, 3, true))
	var eye: Vector3 = Vector3(-2.0, 1.5, 1.5)
	assert_eq(g.find_target(eye, Vector3(1, 0, 0), 4.0), door, "дверь, а не проём")
	var wall: int = g.id_at(BuildingGrid.edge_key(0, 0, hy, 0, false))
	assert_eq(g.find_target(Vector3(1.5, 1.5, -2.0), Vector3(0, 0, 1), 4.0), wall)
	assert_eq(g.find_target(Vector3(1.5, 1.5, -9.0), Vector3(0, 0, 1), 4.0), -1, "далеко")


func test_surface_height_for_objects() -> void:
	_found(0, 0)
	assert_almost_eq(g.surface_height(1.5, 1.5, 2.0), 0.25, 0.001, "верх фундамента")
	assert_almost_eq(g.surface_height(1.5, 1.5, 0.1), 0.0, 0.001, "ниже — рельеф")
	assert_almost_eq(g.surface_height(10.0, 1.5, 2.0), 0.0, 0.001)


func test_save_load_round_trip() -> void:
	var hy: int = _hut(0, 0)
	var door: int = _add("door", BuildingGrid.edge_key(0, 0, hy, 3, true), 3)
	g.attach_lock(door, "alice", "1234")
	g.enter_code(door, "bob", "1234")
	g.toggle_door(door, "alice")
	var wall: int = g.id_at(BuildingGrid.edge_key(0, 0, hy, 0, false))
	g.set_material(wall, 2)
	g.set_hp(wall, 300.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var g2: BuildingGrid = BuildingGrid.new(defs, TerrainMath.new(1, 0.0), -10.0)
	assert_eq(g2.from_dict(d), 0)
	assert_eq(g2.count(), g.count())
	var w2: int = g2.id_at(BuildingGrid.edge_key(0, 0, hy, 0, false))
	assert_eq(g2.p_mat[w2], 2, "материал")
	assert_almost_eq(g2.p_hp[w2], 300.0, 0.01, "прочность")
	var d2: int = g2.id_at(BuildingGrid.edge_key(0, 0, hy, 3, true))
	assert_true(g2.has_lock(d2))
	assert_true(g2.is_open(d2))
	assert_eq(g2.p_rot[d2], 3)
	assert_true(g2.can_use_door(d2, "bob"))
	assert_false(g2.can_use_door(d2, "carol"))


func test_load_drops_unsupported_and_invalid() -> void:
	var d: Dictionary = {"pieces": [
		["wall", "wood", 0, 0, 1, BuildingGrid.Slot.EDGE_X, 0, 100.0, "x", 1.0, 0, "", []],
		["laser", "wood", 0, 0, 1, BuildingGrid.Slot.CELL, 0, 100.0, "x", 1.0, 0, "", []],
		["foundation", "gold", 0, 0, 1, BuildingGrid.Slot.CELL, 0, 100.0, "x", 1.0, 0, "", []],
	]}
	assert_eq(g.from_dict(d), 3)
	assert_eq(g.count(), 0)
