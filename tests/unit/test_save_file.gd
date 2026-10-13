extends GutTest

const DIR: String = "user://test_saves"
var path: String = DIR + "/slot.json"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f: String in [path, path + SaveFile.TMP_SUFFIX]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_write_and_read_roundtrip() -> void:
	var sf: SaveFile = SaveFile.new()
	assert_eq(sf.write(path, {"hp": 100, "name": "Тест"}), OK)
	var res: Dictionary = sf.read(path)
	assert_true(res["ok"])
	assert_eq(int(res["data"]["hp"]), 100)
	assert_eq(res["data"]["name"], "Тест")
	assert_false(FileAccess.file_exists(path + SaveFile.TMP_SUFFIX), "временный файл переименован")


func test_overwrite_existing() -> void:
	var sf: SaveFile = SaveFile.new()
	sf.write(path, {"v": 1})
	sf.write(path, {"v": 2})
	assert_eq(int(sf.read(path)["data"]["v"]), 2)


func test_missing_file() -> void:
	var res: Dictionary = SaveFile.new().read(DIR + "/nope.json")
	assert_false(res["ok"])
	assert_eq(res["error"], "not_found")


func test_corrupt_main_falls_back_to_complete_tmp() -> void:
	var sf: SaveFile = SaveFile.new()
	sf.write(path, {"v": 7})
	# Имитируем вылет: целый .tmp записан, основной файл повреждён.
	DirAccess.copy_absolute(path, path + SaveFile.TMP_SUFFIX)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{обрыв")
	f.close()
	var res: Dictionary = sf.read(path)
	assert_true(res["ok"])
	assert_eq(int(res["data"]["v"]), 7)


func test_corrupt_without_tmp_reports_error() -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	var res: Dictionary = SaveFile.new().read(path)
	assert_false(res["ok"])
	assert_eq(res["error"], "corrupt")


func test_migration_chain_applied_on_read() -> void:
	SaveFile.new(SaveMigrator.new(1)).write(path, {"wood": 5})
	var m: SaveMigrator = SaveMigrator.new(3)
	m.register(1, func(d: Dictionary) -> Dictionary:
		d["stone"] = 0
		return d)
	m.register(2, func(d: Dictionary) -> Dictionary:
		d["resources"] = {"wood": d["wood"], "stone": d["stone"]}
		d.erase("wood")
		d.erase("stone")
		return d)
	var res: Dictionary = SaveFile.new(m).read(path)
	assert_true(res["ok"])
	assert_true(res["migrated"])
	assert_eq(int(res["data"]["resources"]["wood"]), 5)
	assert_eq(int(res["data"]["resources"]["stone"]), 0)


func test_missing_migration_step_fails() -> void:
	SaveFile.new(SaveMigrator.new(1)).write(path, {"a": 1})
	var res: Dictionary = SaveFile.new(SaveMigrator.new(2)).read(path)
	assert_false(res["ok"])
	assert_eq(res["error"], "no_migration_from_1")


func test_save_from_future_version_rejected() -> void:
	SaveFile.new(SaveMigrator.new(5)).write(path, {"a": 1})
	var res: Dictionary = SaveFile.new(SaveMigrator.new(1)).read(path)
	assert_false(res["ok"])
	assert_eq(res["error"], "save_from_future")
