extends Node
## Сервис настроек (autoload «Settings»): хранит GameSettings, сохраняет в user://settings.json,
## применяет глобальные параметры (лимит FPS, масштаб 3D, язык) и рассылает Events.settings_changed.

const SETTINGS_PATH: String = "user://settings.json"
const QUALITY_DATA_PATH: String = "res://data/balance/quality_presets.json"

var data: GameSettings = GameSettings.new()
var _file: SaveFile = SaveFile.new(SaveMigrator.new(1))
var _first_launch: bool = false


func _ready() -> void:
	data.configure(JsonData.load_dict(QUALITY_DATA_PATH))
	var res: Dictionary = _file.read(SETTINGS_PATH)
	if res["ok"]:
		data.from_dict(res["data"])
	else:
		_first_launch = true
		data.apply_preset("medium")
	apply()


func is_first_launch() -> bool:
	return _first_launch


## Применить и сохранить. Вызывать после изменения полей data.
func commit() -> void:
	apply()
	save()


func save() -> void:
	var err: Error = _file.write(SETTINGS_PATH, data.to_dict())
	if err != OK:
		push_error("Settings: не удалось сохранить настройки (%s)" % error_string(err))


func apply() -> void:
	TranslationServer.set_locale(data.locale)
	Engine.max_fps = data.effective_fps_limit()
	var root: Viewport = get_tree().root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = data.effective_render_scale()
	Events.settings_changed.emit()


## true, если нужно показывать сенсорное управление.
func touch_controls_visible() -> bool:
	match data.touch_controls:
		GameSettings.TOUCH_ON:
			return true
		GameSettings.TOUCH_OFF:
			return false
		_:
			return DisplayServer.is_touchscreen_available()


## Короткий вибро-отклик, если он включён в настройках.
func haptic(duration_ms: int = 20) -> void:
	if data.vibration:
		Input.vibrate_handheld(duration_ms)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()
