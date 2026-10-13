extends GutTest
## Формат сохранения v3: двоичные записи чанков (ChunkCodec) и JSON игрока в одном файле
## с MD5, запись через .tmp, восстановление из .tmp, миграция 2 → 3, сравнение размера с JSON.

const PATH: String = "user://test_saves/world.save"


func after_each() -> void:
	for p: String in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _sample_chunks(n_nodes: int) -> Dictionary:
	var chunks: Dictionary = {}
	for i: int in n_nodes:
		var k: String = "%d,%d" % [i % 20, (i / 20) % 20]
		if not chunks.has(k):
			chunks[k] = {"r": []}
		(chunks[k]["r"] as Array).append([i % 50, i % 150, snappedf(float(i) * 0.5, 0.1)])
	chunks["3,4"]["l"] = [[2, 0.0, {"slots": [[0, "wood", 50, -1], [1, "bow", 1, 140]]}, 1], [5, 120.5, {}, 2]]
	chunks["3,4"]["c"] = [["bag", 1.5, 2.25, -3.5, 0.0, 1700.0, "local", {"slots": [[0, "stone", 10, -1]]}, 3]]
	chunks["3,4"]["p"] = [[0, ["foundation", "wood", 1, 2, 3, 0, 0, 300.0, "local", 1.0, 0, "", []]]]
	chunks["3,4"]["d"] = [[0, ["campfire", 1.0, 2.0, 3.0, 0.0, 30.0, "local", []]]]
	return chunks


func _sample(n_nodes: int) -> Dictionary:
	return {"world": {"seed": 1337, "generator": 3}, "player": {"pos": [1.0, 2.0, 3.0]}, "inventory": {"slots": [[0, "wood", 10, -1]]}, "chunks": _sample_chunks(n_nodes)}


func _file() -> WorldSaveFile:
	return WorldSaveFile.new(SaveGame._make_migrator())


func test_write_read_round_trip() -> void:
	var f: WorldSaveFile = _file()
	var data: Dictionary = _sample(300)
	assert_eq(f.write(PATH, data), OK)
	var res: Dictionary = f.read(PATH)
	assert_true(res["ok"], String(res["error"]))
	var got: Dictionary = res["data"]
	assert_eq(got["world"]["seed"], 1337.0)
	assert_eq((got["chunks"] as Dictionary).size(), (data["chunks"] as Dictionary).size())
	assert_eq(JSON.stringify(got["chunks"]["3,4"]["r"]), JSON.stringify(data["chunks"]["3,4"]["r"]))
	assert_eq(got["chunks"]["3,4"]["l"][0][2]["slots"][1][1], "bow")
	assert_eq(got["chunks"]["3,4"]["l"][1][3], 2)
	assert_eq(got["chunks"]["3,4"]["c"][0][7]["slots"][0][2], 10)
	assert_eq(got["chunks"]["3,4"]["p"][0][1][0], "foundation")
	assert_eq(got["chunks"]["3,4"]["d"][0][1][0], "campfire")
	assert_false(FileAccess.file_exists(PATH + ".tmp"), "временный файл переименован")


func test_corrupt_file_falls_back_to_tmp() -> void:
	var f: WorldSaveFile = _file()
	assert_eq(f.write(PATH, _sample(10)), OK)
	var good: PackedByteArray = FileAccess.get_file_as_bytes(PATH)
	var tmp: FileAccess = FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	tmp.store_buffer(good)
	tmp.close()
	var bad: PackedByteArray = good.duplicate()
	bad[bad.size() / 2] = bad[bad.size() / 2] ^ 0xFF
	var fw: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	fw.store_buffer(bad)
	fw.close()
	assert_false(f.decode(bad)["ok"], "MD5 ловит повреждение")
	assert_true(f.read(PATH)["ok"], "читается целый .tmp")
	var cut: PackedByteArray = good.slice(0, good.size() - 40)
	assert_false(f.decode(cut)["ok"], "обрезанный файл")


func test_future_version_rejected() -> void:
	var f: WorldSaveFile = WorldSaveFile.new(SaveMigrator.new(99))
	var bytes: PackedByteArray = f.encode(_sample(5))
	var res: Dictionary = _file().decode(bytes)
	assert_false(res["ok"])
	assert_eq(res["error"], "save_from_future")


func test_binary_smaller_than_json() -> void:
	var data: Dictionary = _sample(2000)
	var t0: int = Time.get_ticks_usec()
	var bin: PackedByteArray = _file().encode(data)
	var t1: int = Time.get_ticks_usec()
	var json: String = JSON.stringify({"format_version": 3, "saved_at": 0, "data": data}, "\t")
	var t2: int = Time.get_ticks_usec()
	var dec: Dictionary = _file().decode(bin)
	var t3: int = Time.get_ticks_usec()
	JSON.parse_string(json)
	var t4: int = Time.get_ticks_usec()
	gut.p("2000 изменённых узлов: двоичный %d байт (запись %.1f мс, чтение %.1f мс), JSON %d байт (запись %.1f мс, чтение %.1f мс)" % [
		bin.size(), (t1 - t0) / 1000.0, (t3 - t2) / 1000.0, json.to_utf8_buffer().size(), (t2 - t1) / 1000.0, (t4 - t3) / 1000.0])
	assert_true(dec["ok"])
	assert_lt(bin.size() * 2, json.to_utf8_buffer().size(), "двоичный формат минимум вдвое меньше JSON")


func test_migrate_2_to_3_moves_buildings_and_objects_to_chunks() -> void:
	var v2: Dictionary = {
		"world": {"seed": 1337, "hours": 9.0},
		"player": {"pos": [1.0, 2.0, 3.0]},
		"inventory": {"slots": [[0, "wood", 10, -1]]},
		"resources": {"layout_hash": 1, "count": 3, "changed": [[1, 5, 10.0]]},
		"deployables": {"objects": [["campfire", 5.0, 0.0, 5.0, 0.0, 30.0, "local", []], ["base_banner", 100.0, 0.0, -200.0, 0.0, 0.0, "local", ["local"], {"slots": []}]]},
		"building": {"pieces": [["foundation", "stone", 1, 2, 4, 0, 0, 700.0, "local", 1.0, 0, "", []]]},
		"claims": {"acc": 0.0, "debt": {"1": {"wood": 0.5}}},
	}
	var res: Dictionary = SaveGame._make_migrator().migrate(v2, 2)
	assert_true(res["ok"])
	var d: Dictionary = res["data"]
	assert_false(d.has("building"))
	assert_false(d.has("deployables"))
	assert_false(d.has("resources"), "узлы старой карты не переносятся")
	assert_eq(int(d["world"]["generator"]), WorldGen.GENERATOR_VERSION)
	var grid: ChunkGrid = ChunkGrid.new(1280.0, 64.0)
	var k_fire: String = grid.key_of(5.0, 5.0)
	var k_banner: String = grid.key_of(100.0, -200.0)
	assert_eq(d["chunks"][k_fire]["d"][0][1][0], "campfire")
	assert_eq(d["chunks"][k_banner]["d"][0][0], 1, "порядковый номер знамени сохранён")
	assert_eq(d["chunks"][grid.key_of(4.5, 7.5)]["p"][0][1][0], "foundation")
	# Сессия поднимает такой словарь: объекты в прежнем порядке (долг знамени — индекс 1).
	var g: WorldGen = WorldGen.load_default()
	var s: SurvivalSession = SurvivalSession.create(g, ResourceField.generate_world({"types": []}, g), g.water_level)
	var w: PackedStringArray = s.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(s.deployables.kinds, PackedStringArray(["campfire", "base_banner"]))
	assert_eq(s.inventory.count_of("wood"), 10)
	assert_true(w.has("resources_reset"), "предупреждение о сбросе узлов")


func test_legacy_json_slot_is_read_and_replaced() -> void:
	var old_dir: String = SaveGame.save_dir
	SaveGame.save_dir = "user://test_saves/legacy"
	SaveGame.delete_slot("slot")
	var legacy: SaveFile = SaveFile.new(SaveMigrator.new(2))
	assert_eq(legacy.write(SaveGame.legacy_path("slot"), {"world": {"seed": 1337}, "inventory": {"slots": [[0, "stone", 7, -1]]}, "building": {"pieces": []}, "deployables": {"objects": []}}), OK)
	assert_true(SaveGame.has_slot("slot"))
	var d: Dictionary = SaveGame.load_slot("slot")
	assert_true(d.has("chunks"), "старый слот мигрировал до v3")
	assert_true(SaveGame.save_slot("slot", d))
	assert_true(FileAccess.file_exists(SaveGame.slot_path("slot")), "записан .save")
	assert_false(FileAccess.file_exists(SaveGame.legacy_path("slot")), "старый .json удалён")
	assert_eq(int(SaveGame.load_slot("slot")["inventory"]["slots"][0][2]), 7)
	SaveGame.delete_slot("slot")
	SaveGame.save_dir = old_dir


func test_session_chunked_save_round_trip_in_world() -> void:
	var g: WorldGen = WorldGen.load_default()
	var rcfg: Dictionary = JsonData.load_dict(ResourceField.DEFAULT_PATH)
	var lcfg: Dictionary = JsonData.load_dict(WorldContainers.DEFAULT_PATH)
	var boxes: WorldContainers = WorldContainers.new()
	boxes.configure(lcfg, null, null)
	boxes.generate_points(lcfg, g)
	var s: SurvivalSession = SurvivalSession.create(g, ResourceField.generate_world(rcfg, g), g.water_level, boxes)
	s.resources.hit(10, 3.0)
	s.resources.hit(2500, 100.0)
	s.containers.storage_of(5)
	s.inventory.add("arrow", 9)
	var data: Dictionary = s.to_dict()
	var bytes: PackedByteArray = _file().encode(data)
	gut.p("сохранение мира: %d байт, чанков с изменениями: %d" % [bytes.size(), (data["chunks"] as Dictionary).size()])
	var res: Dictionary = _file().decode(bytes)
	assert_true(res["ok"])
	var boxes2: WorldContainers = WorldContainers.new()
	boxes2.configure(lcfg, null, null)
	boxes2.generate_points(lcfg, g)
	var s2: SurvivalSession = SurvivalSession.create(g, ResourceField.generate_world(rcfg, g), g.water_level, boxes2)
	assert_eq(s2.from_dict(res["data"]), PackedStringArray())
	assert_eq(s2.resources.remaining[10], s.resources.remaining[10])
	assert_eq(s2.resources.remaining[2500], s.resources.remaining[2500])
	assert_eq(JSON.stringify(s2.containers.storage_of(5).to_dict()), JSON.stringify(s.containers.storage_of(5).to_dict()))
	assert_eq(s2.inventory.count_of("arrow"), 9)
