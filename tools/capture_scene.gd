extends SceneTree
## Снимок сцены и замер счётчиков рендера (для отчётов; не для устройства).
## Запуск (нужен реальный рендер, не --headless):
##   godot --path . -s res://tools/capture_scene.gd -- --scene=res://scenes/main/game.tscn --out=user://shot.png --frames=240
## Опции: --call=<метод> (вызвать метод корня сцены за 10 кадров до снимка), --touch=on (показать сенсорное управление), --debug=on (отладочная панель), --preset=low|medium|high
## Для игровой сцены (этап 1): --items=wood:60,stone_axe:1 (выдать предметы), --hour=21.5 (время суток),
## --place=campfire (поставить костёр перед игроком), --slot=N (активная ячейка) — применяются, когда сессия готова.
## Этап 2: --house=on (демонстрационный дом из трёх материалов с дверью, замком, ящиком и знаменем к северу
## от точки появления), --pose=x,z,yaw_deg,pitch_deg (поставить игрока), --build=on|<деталь> (режим стройки),
## --open=storage|keypad|banner (открыть экран у дома), --wear=0.4 (износ всех деталей до доли прочности).

var _frames_left: int = 240
var _out: String = "user://capture.png"
var _scene_path: String = "res://scenes/main/game.tscn"
var _opts: Dictionary = {}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv: PackedStringArray = arg.substr(2).split("=", true, 1)
			_opts[kv[0]] = kv[1]
	_scene_path = _opts.get("scene", _scene_path)
	_out = _opts.get("out", _out)
	_frames_left = int(_opts.get("frames", "240"))
	_setup.call_deferred()


func _setup() -> void:
	var settings: Node = root.get_node_or_null(^"Settings")
	if settings != null:
		var data: GameSettings = settings.get("data")
		data.auto_quality = false
		if _opts.has("preset"):
			data.apply_preset(_opts["preset"])
		if _opts.get("touch", "") == "on":
			data.touch_controls = GameSettings.TOUCH_ON
		if _opts.get("debug", "") == "on":
			data.show_debug = true
		settings.call("apply")
	change_scene_to_file(_scene_path)


var _session_setup_done: bool = false


func _setup_session() -> void:
	if _session_setup_done or current_scene == null:
		return
	var session: Variant = current_scene.get("session")
	if session == null:
		return
	_session_setup_done = true
	var s: SurvivalSession = session
	if _opts.has("hour"):
		s.clock.time_hours = float(_opts["hour"])
	if _opts.has("items"):
		for pair: String in String(_opts["items"]).split(","):
			var kv: PackedStringArray = pair.split(":")
			s.inventory.add(kv[0], int(kv[1]) if kv.size() > 1 else 1)
	if _opts.has("place"):
		var p: Vector3 = s.placement_point(s.player_position, s.player_yaw)
		s.deployables.place(String(_opts["place"]), p, s.player_yaw)
	if _opts.has("slot"):
		s.select_slot(int(_opts["slot"]))
	if _opts.get("house", "") == "on":
		_build_demo_house(s)
	if _opts.has("wear"):
		for id: int in s.building.capacity():
			if s.building.is_alive(id):
				s.building.set_hp(id, s.building.max_hp(id) * float(_opts["wear"]))
	if _opts.has("pose"):
		var v: PackedStringArray = String(_opts["pose"]).split(",")
		var x: float = float(v[0])
		var z: float = float(v[1])
		# Без статических типов сцены: скрипты с autoload (Events, Settings) здесь ещё не компилируются.
		var player: Node = current_scene.get_node("Player")
		player.call("activate_at", Vector3(x, s.building.surface_height(x, z, s.terrain.height_at(x, z) + 2.0) + 0.2, z))
		player.call("set_look", deg_to_rad(float(v[2])), deg_to_rad(float(v[3])))
	if _opts.has("build"):
		current_scene.call("set_build_mode", true)
		if _opts["build"] != "on":
			current_scene.call("_on_build_piece", String(_opts["build"]))
	match String(_opts.get("open", "")):
		"storage":
			current_scene.call("_open_screen")
			current_scene.get_node("StorageScreen").call("open", _demo_box)
		"banner":
			current_scene.call("_open_screen")
			current_scene.get_node("StorageScreen").call("open", _demo_banner)
		"keypad":
			current_scene.call("_open_screen")
			var kp: Node = current_scene.get_node("KeypadScreen")
			kp.call("open", 1, _demo_door)
			for d: String in ["4", "2"]:
				kp.call("press_digit", d)


var _demo_box: int = -1
var _demo_banner: int = -1
var _demo_door: int = -1


## Дом 2 × 2 клетки к северу от точки появления: каменные фундаменты, стены из дерева, камня и металла,
## проём с металлической дверью и замком, перекрытие, лестница, второй этаж с крышей; ящик и знамя.
func _build_demo_house(s: SurvivalSession) -> void:
	var b: BuildingGrid = s.building
	var who: String = s.player_id
	var cells: Array[Vector2i] = [Vector2i(-1, -4), Vector2i(0, -4), Vector2i(-1, -3), Vector2i(0, -3)]
	var hy: int = b.foundation_hy(-1, -3)
	for c: Vector2i in cells:
		b.add_piece("foundation", 1, Vector4i(c.x, c.y, hy, BuildingGrid.Slot.CELL), 0, who)
	var L: int = b.defs.level_steps
	# Первый этаж: юг — проём с дверью и металлическая стена, запад — камень, восток и север — дерево.
	b.add_piece("doorway", 1, BuildingGrid.edge_key(-1, -3, hy, 2, false), 0, who)
	_demo_door = b.add_piece("door", 2, BuildingGrid.edge_key(-1, -3, hy, 2, true), 0, who)
	b.attach_lock(_demo_door, who, "4242")
	b.add_piece("wall", 2, BuildingGrid.edge_key(0, -3, hy, 2, false), 0, who)
	b.add_piece("wall", 1, BuildingGrid.edge_key(-1, -3, hy, 3, false), 0, who)
	b.add_piece("wall", 1, BuildingGrid.edge_key(-1, -4, hy, 3, false), 0, who)
	b.add_piece("wall", 0, BuildingGrid.edge_key(0, -3, hy, 1, false), 0, who)
	b.add_piece("wall", 0, BuildingGrid.edge_key(0, -4, hy, 1, false), 0, who)
	b.add_piece("wall", 0, BuildingGrid.edge_key(-1, -4, hy, 0, false), 0, who)
	b.add_piece("wall", 0, BuildingGrid.edge_key(0, -4, hy, 0, false), 0, who)
	# Перекрытия над тремя клетками, над четвёртой — проём для лестницы.
	for c: Vector2i in [Vector2i(-1, -4), Vector2i(0, -4), Vector2i(-1, -3)]:
		b.add_piece("floor", 0, Vector4i(c.x, c.y, hy + L, BuildingGrid.Slot.CELL), 0, who)
	b.add_piece("stairs", 0, Vector4i(0, -3, hy, BuildingGrid.Slot.STAIRS), 0, who)
	# Второй этаж над западной половиной и крыши.
	b.add_piece("wall", 1, BuildingGrid.edge_key(-1, -3, hy + L, 2, false), 0, who)
	b.add_piece("wall", 1, BuildingGrid.edge_key(-1, -3, hy + L, 3, false), 0, who)
	b.add_piece("wall", 1, BuildingGrid.edge_key(-1, -4, hy + L, 3, false), 0, who)
	b.add_piece("wall", 1, BuildingGrid.edge_key(-1, -4, hy + L, 0, false), 0, who)
	b.add_piece("roof", 0, Vector4i(-1, -3, hy + 2 * L, BuildingGrid.Slot.CELL), 0, who)
	b.add_piece("roof", 0, Vector4i(-1, -4, hy + 2 * L, BuildingGrid.Slot.CELL), 0, who)
	var top: float = b.defs.height_of(hy)
	_demo_box = s.deployables.place("storage_box", Vector3(-1.5, top, -10.0), 0.4, who)
	s.deployables.storages[_demo_box].add("wood", 640)
	s.deployables.storages[_demo_box].add("metal_axe", 1)
	s.deployables.storages[_demo_box].add("berries", 12)
	_demo_banner = s.deployables.place("base_banner", Vector3(4.5, s.terrain.height_at(4.5, -7.5), -7.5), 0.0, who)
	s.deployables.storages[_demo_banner].add("wood", 300)
	s.deployables.storages[_demo_banner].add("stone", 400)
	s.deployables.storages[_demo_banner].add("metal", 60)


func _process(_delta: float) -> bool:
	# Этап 3: ждём, пока мир под игроком подгрузится (персонаж включён), и только потом считаем кадры.
	if current_scene != null and current_scene.has_method("is_world_ready") and not bool(current_scene.call("is_world_ready")):
		return false
	_setup_session()
	_frames_left -= 1
	if _frames_left == 10 and _opts.has("call") and current_scene != null:
		current_scene.call(_opts["call"])
	if _frames_left > 0:
		return false
	var img: Image = root.get_texture().get_image()
	var err: Error = img.save_png(_out)
	print("[capture] %s -> %s (%s)" % [_scene_path, ProjectSettings.globalize_path(_out), error_string(err)])
	print("[capture] fps=%.1f draw_calls=%d primitives=%d objects=%d mem_static_mb=%.1f vmem_mb=%.1f" % [
		Performance.get_monitor(Performance.TIME_FPS),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	])
	return true
