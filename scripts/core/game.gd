extends Node3D
## Корень игровой сцены: связывает ландшафт, персонажа, HUD, меню и игровую сессию выживания.
## Вся игровая логика — в SurvivalSession (без сцен); здесь только передача ввода
## в сессию и отображение её состояния. Узлы общаются через сигналы; ссылки только на своих детей.

signal session_ready

const MENU_SCENE: String = "res://scenes/main/main_menu.tscn"
const TARGET_INTERVAL: float = 0.1
const HUD_INTERVAL: float = 0.25
const LIGHT_INTERVAL: float = 0.1

@onready var _terrain: TestTerrain = $Terrain
@onready var _resources_view: ResourceView = $Resources
@onready var _deploy_view: DeployableView = $Deployables
@onready var _player: PlayerController = $Player
@onready var _camera: Camera3D = $Player/Head/Camera
@onready var _held: HeldItemView = $Player/Head/Camera/HeldItem
@onready var _sun: DirectionalLight3D = $Sun
@onready var _env: WorldEnvironment = $WorldEnvironment
@onready var _hud: Hud = $Hud
@onready var _pause: PauseMenu = $PauseMenu
@onready var _inventory: InventoryScreen = $InventoryScreen
@onready var _death: DeathScreen = $DeathScreen

var session: SurvivalSession

var _auto_quality: AutoQualityMonitor = AutoQualityMonitor.new()
var _light: DayNightCycle.Sample = DayNightCycle.Sample.new()
var _sky: ProceduralSkyMaterial
var _target_t: float = 0.0
var _hud_t: float = 0.0
var _light_t: float = 0.0
var _autosave_t: float = 0.0
var _last_target: int = -2
var _last_interact: int = -1
var _last_primary: int = -1
var _shadows_setting: bool = true


func _ready() -> void:
	_auto_quality.configure(Settings.data.auto_quality_params())
	Events.settings_changed.connect(_apply_settings)
	Events.pause_requested.connect(_toggle_pause)
	_pause.resumed.connect(_on_resumed)
	_pause.quit_to_menu_requested.connect(_quit_to_menu)
	_pause.save_requested.connect(_save_now)
	_inventory.closed.connect(_on_inventory_closed)
	_death.respawn_requested.connect(_on_respawn_requested)
	_player.landed.connect(_on_player_landed)
	_terrain.built.connect(_on_terrain_built)
	if _env.environment != null and _env.environment.sky != null:
		_sky = _env.environment.sky.sky_material as ProceduralSkyMaterial
	_apply_settings()


func _on_terrain_built() -> void:
	session = SurvivalSession.create(_terrain.terrain_math, _terrain.resource_field, _terrain.water_level)
	var loaded: bool = false
	if SaveGame.continue_requested and SaveGame.has_slot(SaveGame.MAIN_SLOT):
		var data: Dictionary = SaveGame.load_slot(SaveGame.MAIN_SLOT)
		if data.is_empty():
			Events.toast_requested.emit(tr("TOAST_LOAD_FAILED"))
		else:
			var warnings: PackedStringArray = session.from_dict(data)
			if not warnings.is_empty():
				push_warning("Сохранение загружено с предупреждениями: %s" % [warnings])
			loaded = true
	SaveGame.continue_requested = false

	var icons: ItemIcons = ItemIcons.new(session.items)
	_resources_view.build(session.resources)
	_deploy_view.bind(session.deployables)
	_hud.bind(session, icons)
	_inventory.bind(session, icons)
	session.notice.connect(_on_notice)
	session.gathered.connect(_on_gathered)
	session.player_died.connect(_on_player_died)
	session.respawned.connect(_on_respawned)
	session.active_slot_changed.connect(_on_active_slot_changed)
	session.inventory.changed.connect(_on_inventory_changed)

	_player.activate_at(session.player_position + Vector3(0.0, 0.3, 0.0))
	if loaded:
		_player.set_look(session.player_yaw, session.player_pitch)
		Events.toast_requested.emit(tr("TOAST_GAME_LOADED"))
	else:
		Events.toast_requested.emit(tr("TOAST_NEW_GAME_HINT"))
	_on_active_slot_changed(session.active_slot)
	_apply_lighting()
	_auto_quality.reset()
	if session.stats.is_dead():
		_on_player_died("other")
	print("[game] world ready (%s): %d ms since engine start" % ["loaded" if loaded else "new", Time.get_ticks_msec()])
	session_ready.emit()


func _apply_settings() -> void:
	var s: GameSettings = Settings.data
	var dist: float = s.effective_draw_distance()
	_camera.far = dist
	_shadows_setting = s.effective_shadows()
	_sun.directional_shadow_max_distance = minf(dist, 60.0)
	_terrain.set_draw_distance(dist)
	_terrain.set_grass_density(s.effective_grass_density())
	_resources_view.set_draw_distance(dist)
	var env: Environment = _env.environment
	if env != null:
		# Туман скрывает границу дальности прорисовки.
		env.fog_density = 0.9 / dist
	_update_shadows()


func _update_shadows() -> void:
	var want: bool = _shadows_setting and (session == null or session.clock.shadows_allowed())
	if _sun.shadow_enabled != want:
		_sun.shadow_enabled = want


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if Settings.data.auto_quality and _auto_quality.tick(delta, Engine.get_frames_per_second()):
		if Settings.data.lower_quality_step():
			Settings.commit()
			var name_key: String = "PRESET_" + Settings.data.quality_preset.to_upper()
			Events.quality_auto_lowered.emit(Settings.data.quality_preset)
			Events.toast_requested.emit(tr("TOAST_QUALITY_LOWERED") % tr(name_key))
	if session == null:
		return
	session.tick(delta)
	var feet: Vector3 = _player.global_position
	var yaw: float = _player.rotation.y
	session.set_player_pose(feet, yaw, _player.get_pitch())

	var playing: bool = _player.is_active() and not _inventory.is_open()
	if playing and Input.is_action_pressed("attack") and session.can_swing():
		var r: SurvivalSession.Primary = session.primary(_camera.global_position, -_camera.global_basis.z, feet, yaw)
		if r == SurvivalSession.Primary.SWING:
			_held.swing(session.items.swing_time(session.active_item()))

	_target_t -= delta
	if _target_t <= 0.0:
		_target_t = TARGET_INTERVAL
		_update_target(feet, yaw)
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = HUD_INTERVAL
		var st: SurvivalStats = session.stats
		_hud.set_stats(st.health / st.max_health, st.hunger / st.max_hunger, st.thirst / st.max_thirst)
		var minutes: int = int(session.clock.time_hours * 60.0)
		_hud.set_clock(tr("HUD_CLOCK") % [session.clock.day, minutes / 60, minutes % 60])
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = LIGHT_INTERVAL
		_apply_lighting()
	_autosave_t += delta
	if _autosave_t >= session.autosave_interval() and _player.is_active():
		_autosave_t = 0.0
		SaveGame.save_slot_async(SaveGame.MAIN_SLOT, session.to_dict())


## Цель под прицелом, контекстная кнопка и подпись основной кнопки (10 раз в секунду).
func _update_target(feet: Vector3, yaw: float) -> void:
	var target: int = session.resources.find_target(_camera.global_position, -_camera.global_basis.z)
	if target != _last_target or target >= 0:
		_last_target = target
		if target < 0:
			_hud.set_target("")
		else:
			var f: ResourceField = session.resources
			_hud.set_target(tr("HUD_TARGET") % [tr(f.name_key_of(target)), f.remaining[target], f.stock_of(target)])
	var ik: int = session.interact_kind(feet, yaw)
	if ik != _last_interact:
		_last_interact = ik
		match ik:
			SurvivalSession.Interact.DRINK:
				Events.interact_target_changed.emit("HUD_DRINK")
			SurvivalSession.Interact.REFUEL:
				Events.interact_target_changed.emit("HUD_REFUEL")
			_:
				Events.interact_target_changed.emit("")
	var pk: int = session.primary_kind()
	if pk != _last_primary:
		_last_primary = pk
		match pk:
			SurvivalSession.Primary.EAT:
				Events.primary_action_changed.emit("HUD_EAT")
			SurvivalSession.Primary.PLACE:
				Events.primary_action_changed.emit("HUD_PLACE")
			_:
				Events.primary_action_changed.emit("HUD_ATTACK")


## Солнце, небо, окружение по времени суток. Только присваивания, без выделения памяти.
func _apply_lighting() -> void:
	if session == null:
		return
	session.clock.sample(_light)
	var elev: float = maxf(_light.sun_elevation_deg, 2.0)
	_sun.rotation = Vector3(deg_to_rad(-elev), deg_to_rad(_light.sun_azimuth_deg), 0.0)
	_sun.light_energy = _light.sun_energy
	_sun.light_color = _light.sun_color
	_sun.visible = _light.sun_energy > 0.01
	_update_shadows()
	var env: Environment = _env.environment
	if env != null:
		env.ambient_light_energy = _light.ambient_energy
		env.fog_light_color = _light.fog
	if _sky != null:
		_sky.sky_top_color = _light.sky_top
		_sky.sky_horizon_color = _light.sky_horizon
		_sky.ground_horizon_color = _light.sky_horizon


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("inventory"):
		_toggle_inventory()
	elif event.is_action_pressed("build"):
		Events.toast_requested.emit(tr("TOAST_BUILD_LATER"))
	elif session != null and event.is_action_pressed("interact") and _player.is_active():
		var r: SurvivalSession.Interact = session.interact(_player.global_position, _player.rotation.y)
		if r == SurvivalSession.Interact.DRINK:
			_hud.add_feed(tr("FEED_DRANK"))
		elif r == SurvivalSession.Interact.REFUEL:
			_hud.add_feed(tr("FEED_REFUELED"))
	elif session != null and event.is_action_pressed("hotbar_next"):
		session.select_slot((session.active_slot + 1) % Inventory.HOTBAR_SIZE)
	elif session != null and event.is_action_pressed("hotbar_prev"):
		session.select_slot((session.active_slot + Inventory.HOTBAR_SIZE - 1) % Inventory.HOTBAR_SIZE)
	elif session != null and event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo():
		var k: Key = (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_6:
			session.select_slot(int(k - KEY_1))
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not Settings.touch_controls_visible() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _inventory.is_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _toggle_inventory() -> void:
	if session == null or _death.visible:
		return
	if _inventory.is_open():
		_inventory.close()
	else:
		_hud.set_touch_enabled(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_inventory.open()


func _on_inventory_closed() -> void:
	_hud.set_touch_enabled(true)


func _toggle_pause() -> void:
	if _pause.is_open():
		_pause.close()
	else:
		if _inventory.is_open():
			_inventory.close()
		_hud.set_touch_enabled(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pause.open()
		_autosave_sync()


func _on_resumed() -> void:
	_hud.set_touch_enabled(not _death.visible)
	_auto_quality.reset()


func _save_now() -> void:
	if _autosave_sync():
		Events.toast_requested.emit(tr("TOAST_SAVED"))
	else:
		Events.toast_requested.emit(tr("TOAST_SAVE_FAILED"))


## Синхронное сохранение (пауза, выход, сворачивание). Возвращает false при ошибке записи.
func _autosave_sync() -> bool:
	if session == null:
		return true
	_autosave_t = 0.0
	return SaveGame.save_slot(SaveGame.MAIN_SLOT, session.to_dict())


func _quit_to_menu() -> void:
	_autosave_sync()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Сигналы сессии ---------------------------------------------------------

func _on_notice(key: String, item_id: String) -> void:
	var text: String = tr(key)
	if text.contains("%s"):
		text = text % tr(session.items.name_key(item_id))
	Events.toast_requested.emit(text)


func _on_gathered(item_id: String, amount: int) -> void:
	_hud.add_feed("+%d %s" % [amount, tr(session.items.name_key(item_id))])
	Settings.haptic(12)


func _on_active_slot_changed(_slot: int) -> void:
	_held.show_item(session.active_item())


func _on_inventory_changed() -> void:
	_held.show_item(session.active_item())


func _on_player_landed(fall_speed: float) -> void:
	if session == null:
		return
	var dmg: float = session.stats.fall_damage_for(fall_speed)
	if dmg > 0.0:
		session.stats.damage(dmg, "fall")
		Settings.haptic(40)


func _on_player_died(cause: String) -> void:
	_player.deactivate()
	if _inventory.is_open():
		_inventory.close()
	_hud.set_touch_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_death.show_death(cause)


func _on_respawn_requested() -> void:
	session.respawn()


func _on_respawned(pos: Vector3) -> void:
	_player.activate_at(pos + Vector3(0.0, 0.3, 0.0))
	_hud.set_touch_enabled(true)
	_autosave_sync()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _pause.is_open():
			_pause.back()
		elif _inventory.is_open():
			_inventory.close()
		elif not _death.visible:
			_toggle_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_autosave_sync()
		if not _pause.is_open() and not _death.visible:
			_toggle_pause()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave_sync()
