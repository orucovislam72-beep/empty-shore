extends SceneTree
## Снимок сцены и замер счётчиков рендера (для отчётов; не для устройства).
## Запуск (нужен реальный рендер, не --headless):
##   godot --path . -s res://tools/capture_scene.gd -- --scene=res://scenes/main/game.tscn --out=user://shot.png --frames=240
## Опции: --call=<метод> (вызвать метод корня сцены за 10 кадров до снимка), --touch=on (показать сенсорное управление), --debug=on (отладочная панель), --preset=low|medium|high

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


func _process(_delta: float) -> bool:
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
