extends Node3D
## Корень игровой сцены этапа 0: связывает ландшафт, персонажа, HUD, паузу и автокачество.
## Узлы общаются через сигналы; ссылки только на собственных детей.

const MENU_SCENE: String = "res://scenes/main/main_menu.tscn"

@onready var _terrain: TestTerrain = $Terrain
@onready var _player: PlayerController = $Player
@onready var _camera: Camera3D = $Player/Head/Camera
@onready var _sun: DirectionalLight3D = $Sun
@onready var _env: WorldEnvironment = $WorldEnvironment
@onready var _hud: Hud = $Hud
@onready var _pause: PauseMenu = $PauseMenu

var _auto_quality: AutoQualityMonitor = AutoQualityMonitor.new()


func _ready() -> void:
	_auto_quality.configure(Settings.data.auto_quality_params())
	Events.settings_changed.connect(_apply_settings)
	Events.pause_requested.connect(_toggle_pause)
	_pause.resumed.connect(_on_resumed)
	_pause.quit_to_menu_requested.connect(_quit_to_menu)
	_terrain.built.connect(_on_terrain_built)
	_apply_settings()


func _on_terrain_built() -> void:
	_player.activate_at(Vector3(0.0, _terrain.height_at(0.0, 0.0) + 0.5, 0.0))
	_auto_quality.reset()
	print("[game] terrain built: %d ms since engine start" % Time.get_ticks_msec())


func _apply_settings() -> void:
	var s: GameSettings = Settings.data
	var dist: float = s.effective_draw_distance()
	_camera.far = dist
	_sun.shadow_enabled = s.effective_shadows()
	_sun.directional_shadow_max_distance = minf(dist, 60.0)
	_terrain.set_draw_distance(dist)
	_terrain.set_grass_density(s.effective_grass_density())
	var env: Environment = _env.environment
	if env != null:
		# Туман скрывает границу дальности прорисовки.
		env.fog_density = 0.9 / dist


func _process(delta: float) -> void:
	if not Settings.data.auto_quality or get_tree().paused:
		return
	if _auto_quality.tick(delta, Engine.get_frames_per_second()):
		if Settings.data.lower_quality_step():
			Settings.commit()
			var name_key: String = "PRESET_" + Settings.data.quality_preset.to_upper()
			Events.quality_auto_lowered.emit(Settings.data.quality_preset)
			Events.toast_requested.emit(tr("TOAST_QUALITY_LOWERED") % tr(name_key))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("inventory"):
		Events.toast_requested.emit(tr("TOAST_INVENTORY_LATER"))
	elif event.is_action_pressed("build"):
		Events.toast_requested.emit(tr("TOAST_BUILD_LATER"))
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not Settings.touch_controls_visible() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _toggle_pause() -> void:
	if _pause.is_open():
		_pause.close()
	else:
		_hud.set_touch_enabled(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pause.open()


func _on_resumed() -> void:
	_hud.set_touch_enabled(true)
	_auto_quality.reset()


func _quit_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _pause.is_open():
			_pause.back()
		else:
			_toggle_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED and not _pause.is_open():
		_toggle_pause()
