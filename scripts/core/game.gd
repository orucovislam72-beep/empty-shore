extends Node3D
## Корень игровой сцены: связывает ландшафт, персонажа, HUD, меню и игровую сессию выживания.
## С этапа 2 — режим строительства (призрак детали, панель, «Поставить»/«Повернуть»), двери с
## кодовыми замками (экран цифр), ящики и знамя базы (экран хранилища).
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
@onready var _building_view: BuildingView = $Building
@onready var _ghost: BuildGhost = $BuildGhost
@onready var _build_panel: BuildPanel = $BuildPanel
@onready var _storage: StorageScreen = $StorageScreen
@onready var _keypad: KeypadScreen = $KeypadScreen

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
var _build_mode: bool = false
var _build_type: String = "foundation"
var _build_mat: int = 0
var _build_rot: int = 0
var _build_target: int = -1
var _placement: BuildingGrid.Placement = BuildingGrid.Placement.new()


func _ready() -> void:
	_auto_quality.configure(Settings.data.auto_quality_params())
	Events.settings_changed.connect(_apply_settings)
	Events.pause_requested.connect(_toggle_pause)
	_pause.resumed.connect(_on_resumed)
	_pause.quit_to_menu_requested.connect(_quit_to_menu)
	_pause.save_requested.connect(_save_now)
	_inventory.closed.connect(_on_inventory_closed)
	_death.respawn_requested.connect(_on_respawn_requested)
	_storage.closed.connect(_on_screen_closed)
	_keypad.closed.connect(_on_screen_closed)
	_keypad.code_entered.connect(_on_code_entered)
	_build_panel.piece_selected.connect(_on_build_piece)
	_build_panel.material_selected.connect(_on_build_material)
	_build_panel.action_pressed.connect(_on_build_action)
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
	_storage.bind(session, icons)
	_building_view.bind(session.building)
	_build_panel.setup(session.building.defs)
	_hud.add_touch_passthrough(_build_panel.panel)
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
	_building_view.set_draw_distance(dist)
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

	session.set_look_ray(_camera.global_position, -_camera.global_basis.z)
	var playing: bool = _player.is_active() and not _any_screen_open()
	if _build_mode:
		if playing and Input.is_action_just_pressed("attack"):
			_build_place()
		if playing and Input.is_action_just_pressed("reload"):
			_build_rot = (_build_rot + 1) % 4
			_target_t = 0.0
	elif playing and Input.is_action_pressed("attack") and session.can_swing():
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
	var piece: int = session.build_target()
	if target != _last_target or target >= 0 or piece >= 0:
		_last_target = target
		if target >= 0:
			var f: ResourceField = session.resources
			_hud.set_target(tr("HUD_TARGET") % [tr(f.name_key_of(target)), f.remaining[target], f.stock_of(target)])
		elif piece >= 0:
			_hud.set_target(_piece_label(piece))
		else:
			_hud.set_target("")
	var ik: int = session.interact_kind(feet, yaw)
	if ik != _last_interact:
		_last_interact = ik
		Events.interact_target_changed.emit(_interact_label(ik))
	if _build_mode:
		_update_build()
		return
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


func _interact_label(ik: int) -> String:
	match ik:
		SurvivalSession.Interact.DRINK:
			return "HUD_DRINK"
		SurvivalSession.Interact.REFUEL:
			return "HUD_REFUEL"
		SurvivalSession.Interact.OPEN_DOOR:
			return "HUD_OPEN"
		SurvivalSession.Interact.CLOSE_DOOR:
			return "HUD_CLOSE_DOOR"
		SurvivalSession.Interact.UNLOCK:
			return "HUD_UNLOCK"
		SurvivalSession.Interact.STORAGE:
			return "HUD_BOX"
		SurvivalSession.Interact.CLAIM:
			return "HUD_BANNER"
	return ""


func _piece_label(id: int) -> String:
	var b: BuildingGrid = session.building
	var key: String = "HUD_TARGET_LOCKED" if b.has_lock(id) else "HUD_TARGET_PIECE"
	return tr(key) % [tr(b.defs.name_key(b.p_type[id])), tr(b.defs.material_name(b.p_mat[id])), int(ceil(b.p_hp[id])), int(b.max_hp(id))]


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
		_toggle_build_mode()
	elif session != null and event.is_action_pressed("interact") and _player.is_active() and not _any_screen_open():
		_do_interact()
	elif _build_mode and _build_hotkey(event):
		get_viewport().set_input_as_handled()
	elif session != null and event.is_action_pressed("hotbar_next"):
		session.select_slot((session.active_slot + 1) % Inventory.HOTBAR_SIZE)
	elif session != null and event.is_action_pressed("hotbar_prev"):
		session.select_slot((session.active_slot + Inventory.HOTBAR_SIZE - 1) % Inventory.HOTBAR_SIZE)
	elif session != null and not _build_mode and event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo():
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
		_close_screens()
		_hud.set_touch_enabled(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_inventory.open()


func _on_inventory_closed() -> void:
	_hud.set_touch_enabled(true)


func _any_screen_open() -> bool:
	return _inventory.is_open() or _storage.is_open() or _keypad.is_open()


## Закрыть экраны хранилища и замка (перед паузой, инвентарём, при гибели).
func _close_screens() -> void:
	if _keypad.is_open():
		_keypad.close()
	if _storage.is_open():
		_storage.close()


func _open_screen() -> void:
	_hud.set_touch_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_screen_closed() -> void:
	if not _any_screen_open() and not _pause.is_open() and not _death.visible:
		_hud.set_touch_enabled(true)


# --- Взаимодействие ---------------------------------------------------------

func _do_interact() -> void:
	var r: SurvivalSession.Interact = session.interact(_player.global_position, _player.rotation.y)
	var target: int = session.interact_target()
	match r:
		SurvivalSession.Interact.DRINK:
			_hud.add_feed(tr("FEED_DRANK"))
		SurvivalSession.Interact.REFUEL:
			_hud.add_feed(tr("FEED_REFUELED"))
		SurvivalSession.Interact.OPEN_DOOR:
			_hud.add_feed(tr("FEED_DOOR_OPEN"))
			Settings.haptic(12)
		SurvivalSession.Interact.CLOSE_DOOR:
			_hud.add_feed(tr("FEED_DOOR_CLOSED"))
			Settings.haptic(12)
		SurvivalSession.Interact.UNLOCK:
			_open_screen()
			_keypad.open(KeypadScreen.Mode.ENTER, target)
		SurvivalSession.Interact.STORAGE, SurvivalSession.Interact.CLAIM:
			_open_screen()
			_storage.open(target)
	_target_t = 0.0


func _on_code_entered(mode: int, door: int, code: String) -> void:
	var r: SurvivalSession.Build
	match mode:
		KeypadScreen.Mode.SET:
			r = session.lock_attach(door, code)
			if r == SurvivalSession.Build.OK:
				_hud.add_feed(tr("FEED_LOCK_SET"))
		KeypadScreen.Mode.CHANGE:
			r = session.lock_change(door, code)
			if r == SurvivalSession.Build.OK:
				_hud.add_feed(tr("FEED_CODE_CHANGED"))
		_:
			r = session.lock_enter(door, code)
			if r == SurvivalSession.Build.OK:
				_hud.add_feed(tr("FEED_CODE_OK"))
	if r == SurvivalSession.Build.OK:
		Settings.haptic(20)
		_keypad.close()
	else:
		Settings.haptic(60)
		_build_result_toast(r)
		_keypad.reject()
	_target_t = 0.0


# --- Режим строительства ----------------------------------------------------

func _toggle_build_mode() -> void:
	if session == null or _death.visible:
		return
	set_build_mode(not _build_mode)


func set_build_mode(on: bool) -> void:
	if _build_mode == on:
		return
	_build_mode = on
	if on:
		_build_panel.open()
		_build_panel.show_selection(_build_type, _build_mat, session.building.defs)
		Events.primary_action_changed.emit("HUD_PLACE")
	else:
		_build_panel.close()
		_ghost.hide_ghost()
		_last_primary = -1
	Events.build_mode_changed.emit(on)
	_target_t = 0.0


func is_build_mode() -> bool:
	return _build_mode


func _on_build_piece(type: String) -> void:
	_build_type = type
	_build_mat = session.building.defs.first_allowed_from(type, _build_mat)
	_build_rot = 0
	_build_panel.show_selection(_build_type, _build_mat, session.building.defs)
	_target_t = 0.0


func _on_build_material(mat: int) -> void:
	if session.building.defs.allows(_build_type, mat):
		_build_mat = mat
	_build_panel.show_selection(_build_type, _build_mat, session.building.defs)
	_target_t = 0.0


## Призрак, цель и подсказка панели (10 раз в секунду).
func _update_build() -> void:
	var b: BuildingGrid = session.building
	var playing: bool = _player.is_active() and not _any_screen_open()
	session.build_suggest(_build_type, _build_mat, _build_rot, _placement)
	var check: SurvivalSession.Build = session.build_check(_placement)
	if playing:
		var xf: Transform3D = b.transform_of(_build_type, _placement.key, _placement.rot, _placement.depth)
		_ghost.show_at(_build_type, _building_view.mesh_for(_build_type), xf, check == SurvivalSession.Build.OK)
	else:
		_ghost.hide_ghost()
	var info: String = tr("BUILD_COST") % _cost_text(b.defs.cost(_build_type, _build_mat))
	if check == SurvivalSession.Build.BAD_PLACE:
		info += " · " + tr("BUILD_REASON_%d" % _placement.reason)
	elif check != SurvivalSession.Build.OK:
		info += " · " + tr("BUILD_RESULT_%d" % check)
	_build_target = session.build_target()
	var t: int = _build_target
	if t >= 0:
		var up: Dictionary = session.upgrade_cost(t)
		var rep: Dictionary = session.repair_cost(t)
		info += "\n" + tr("BUILD_TARGET_INFO") % [tr(b.defs.name_key(b.p_type[t])), tr(b.defs.material_name(b.p_mat[t])), _cost_text(up), _cost_text(rep)]
		var lock_label: String = ""
		if b.is_door(t):
			if not b.has_lock(t):
				lock_label = "BUILD_LOCK"
			elif b.can_use_door(t, session.player_id):
				lock_label = "BUILD_CHANGE_CODE"
		_build_panel.set_actions(not up.is_empty(), not rep.is_empty(), true, lock_label)
	else:
		info += "\n" + tr("BUILD_NO_TARGET")
		_build_panel.set_actions(false, false, false, "")
	_build_panel.set_info(info)


func _cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return tr("BUILD_COST_NONE")
	var parts: PackedStringArray = PackedStringArray()
	for item: String in cost:
		parts.append("%s %d" % [tr(session.items.name_key(item)), int(cost[item])])
	return ", ".join(parts)


func _build_place() -> void:
	session.build_suggest(_build_type, _build_mat, _build_rot, _placement)
	var r: SurvivalSession.Build = session.build_place(_placement)
	if r == SurvivalSession.Build.OK:
		_hud.add_feed(tr("FEED_PLACED") % tr(session.building.defs.name_key(_build_type)))
		Settings.haptic(25)
	else:
		_build_result_toast(r)
	_target_t = 0.0


func _build_result_toast(r: SurvivalSession.Build) -> void:
	if r == SurvivalSession.Build.BAD_PLACE:
		Events.toast_requested.emit(tr("BUILD_REASON_%d" % _placement.reason))
	elif r != SurvivalSession.Build.OK:
		Events.toast_requested.emit(tr("BUILD_RESULT_%d" % r))


func _on_build_action(action: String) -> void:
	var t: int = session.build_target()
	if t < 0:
		Events.toast_requested.emit(tr("BUILD_RESULT_%d" % SurvivalSession.Build.NO_TARGET))
		return
	var name_key: String = session.building.defs.name_key(session.building.p_type[t])
	var r: SurvivalSession.Build = SurvivalSession.Build.OK
	match action:
		"upgrade":
			r = session.build_upgrade(t)
			if r == SurvivalSession.Build.OK:
				_hud.add_feed(tr("FEED_UPGRADED") % tr(session.building.defs.material_name(session.building.p_mat[t])))
		"repair":
			r = session.build_repair(t)
			if r == SurvivalSession.Build.OK:
				_hud.add_feed(tr("FEED_REPAIRED") % tr(name_key))
		"demolish":
			r = session.build_demolish(t)
			if r == SurvivalSession.Build.OK:
				_hud.add_feed(tr("FEED_DEMOLISHED") % tr(name_key))
		"lock":
			var b: BuildingGrid = session.building
			if not b.is_door(t):
				return
			if not b.has_lock(t):
				if session.inventory.count_of("code_lock") <= 0:
					r = SurvivalSession.Build.NO_LOCK_ITEM
				elif not session.claims.can_build(session.player_id, b.piece_aabb(t).get_center()) and b.p_owner[t] != session.player_id:
					r = SurvivalSession.Build.NO_PRIVILEGE
				else:
					_open_screen()
					_keypad.open(KeypadScreen.Mode.SET, t)
			elif b.can_use_door(t, session.player_id):
				_open_screen()
				_keypad.open(KeypadScreen.Mode.CHANGE, t)
			else:
				r = SurvivalSession.Build.LOCKED
	if r != SurvivalSession.Build.OK:
		_build_result_toast(r)
	else:
		Settings.haptic(15)
	_target_t = 0.0


## Клавиатура в режиме стройки (ПК, для отладки): 1–7 — деталь, M — материал, U/H/X/L — действия.
func _build_hotkey(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed or event.is_echo():
		return false
	var k: Key = (event as InputEventKey).physical_keycode
	var order: PackedStringArray = session.building.defs.piece_order
	if k >= KEY_1 and k < KEY_1 + order.size():
		_on_build_piece(order[int(k - KEY_1)])
		return true
	match k:
		KEY_M:
			var n: int = session.building.defs.material_order.size()
			for step: int in range(1, n + 1):
				var m: int = (_build_mat + step) % n
				if session.building.defs.allows(_build_type, m):
					_on_build_material(m)
					break
			return true
		KEY_U:
			_on_build_action("upgrade")
			return true
		KEY_H:
			_on_build_action("repair")
			return true
		KEY_X:
			_on_build_action("demolish")
			return true
		KEY_L:
			_on_build_action("lock")
			return true
	return false


func _toggle_pause() -> void:
	if _pause.is_open():
		_pause.close()
	else:
		if _inventory.is_open():
			_inventory.close()
		_close_screens()
		_hud.set_touch_enabled(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pause.open()
		_autosave_sync()


func _on_resumed() -> void:
	_hud.set_touch_enabled(not _death.visible and not _any_screen_open())
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
	_close_screens()
	set_build_mode(false)
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
		elif _keypad.is_open():
			_keypad.close()
		elif _storage.is_open():
			_storage.close()
		elif _inventory.is_open():
			_inventory.close()
		elif _build_mode:
			set_build_mode(false)
		elif not _death.visible:
			_toggle_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_autosave_sync()
		if not _pause.is_open() and not _death.visible:
			_toggle_pause()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave_sync()
