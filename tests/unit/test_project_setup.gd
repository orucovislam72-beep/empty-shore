extends GutTest
## Проверки конфигурации проекта: действия ввода, переводы, рендер, файлы данных.

const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"look_left", &"look_right", &"look_up", &"look_down",
	&"jump", &"crouch", &"attack", &"aim", &"reload", &"interact",
	&"inventory", &"build", &"toggle_autorun", &"pause", &"toggle_debug",
]


func test_input_actions_exist_with_events() -> void:
	for a: StringName in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(a), "нет действия %s" % a)
		if InputMap.has_action(a):
			assert_gt(InputMap.action_get_events(a).size(), 0, "у %s нет привязок" % a)


func test_gamepad_bound_for_movement_and_jump() -> void:
	for a: StringName in [&"move_forward", &"move_left", &"jump", &"attack", &"look_right"]:
		var has_pad: bool = false
		for ev: InputEvent in InputMap.action_get_events(a):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_pad = true
		assert_true(has_pad, "нет привязки геймпада для %s" % a)


func test_compatibility_renderer_default() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"), "gl_compatibility")


func test_all_used_translation_keys_have_russian_text() -> void:
	TranslationServer.set_locale("ru")
	var keys: PackedStringArray = _collect_keys("res://scripts")
	assert_gt(keys.size(), 30)
	for k: String in keys:
		assert_ne(TranslationServer.translate(k), StringName(k), "нет перевода для %s" % k)


func test_preset_names_have_translations() -> void:
	TranslationServer.set_locale("ru")
	for p: String in ["LOW", "MEDIUM", "HIGH", "CUSTOM"]:
		assert_ne(TranslationServer.translate("PRESET_" + p), StringName("PRESET_" + p))


func test_data_files_parse() -> void:
	for p: String in ["res://data/balance/quality_presets.json", "res://data/balance/player.json", "res://data/balance/test_terrain.json"]:
		assert_false(JsonData.load_dict(p).is_empty(), p)


func test_autoloads_present() -> void:
	for n: String in ["Events", "Settings", "SaveGame"]:
		assert_not_null(get_tree().root.get_node_or_null(n), n)


func test_android_back_button_does_not_quit() -> void:
	assert_false(ProjectSettings.get_setting("application/config/quit_on_go_back"))


func test_android_export_presets() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	var names: Dictionary = {}
	for section: String in cfg.get_sections():
		if section.ends_with(".options") or not section.begins_with("preset."):
			continue
		names[cfg.get_value(section, "name")] = section
		assert_eq(cfg.get_value(section, "platform"), "Android")
		assert_true(String(cfg.get_value(section, "include_filter")).contains("data/*.json"), "JSON-данные попадают в сборку")
		assert_true(String(cfg.get_value(section, "exclude_filter")).contains("addons/gut/*"), "GUT не попадает в сборку")
		var opts: String = section + ".options"
		assert_eq(cfg.get_value(opts, "package/unique_name"), "com.emptyshore.game")
		assert_true(cfg.get_value(opts, "architectures/arm64-v8a"))
		assert_false(cfg.get_value(opts, "architectures/armeabi-v7a"))
		assert_eq(cfg.get_value(opts, "keystore/release_password"), "", "пароли не хранятся в репозитории")
		assert_eq(cfg.get_value(opts, "keystore/release"), "", "путь к ключу — только из окружения")
	assert_true(names.has("Android APK"))
	assert_true(names.has("Android AAB"))
	var aab: String = String(names.get("Android AAB", "")) + ".options"
	assert_true(cfg.get_value(aab, "gradle_build/use_gradle_build"))
	assert_eq(cfg.get_value(aab, "gradle_build/export_format"), 1)
	assert_eq(cfg.get_value(aab, "gradle_build/min_sdk"), "24")
	assert_eq(cfg.get_value(aab, "gradle_build/target_sdk"), "36")


## Ищет строковые литералы вида "UPPER_CASE_KEY" с известными префиксами.
func _collect_keys(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var re: RegEx = RegEx.create_from_string("\"((?:MENU|HUD|SETTINGS|PAUSE|TOAST|DEBUG|UI|UNIT|GAME|PRESET)_[A-Z0-9_]+)\"")
	var dir: DirAccess = DirAccess.open(dir_path)
	for f: String in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string(dir_path.path_join(f))
		for m: RegExMatch in re.search_all(text):
			var k: String = m.get_string(1)
			if not out.has(k):
				out.append(k)
	for sub: String in dir.get_directories():
		out.append_array(_collect_keys(dir_path.path_join(sub)))
	return out
