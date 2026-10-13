class_name DebugOverlay
extends CanvasLayer
## Отладочная панель: FPS, мс на кадр, память, число объектов, draw calls, треугольники;
## с этапа 3 — чанки и время их подгрузки на главном потоке, биом.
## Текст обновляется 4 раза в секунду (без строковых аллокаций каждый кадр).
## Включается в настройках или клавишей F3.

const UPDATE_INTERVAL: float = 0.25

var _label: Label
var _timer: float = 0.0
var _worst_ms: float = 0.0


func _ready() -> void:
	layer = 100
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(170.0, 16.0)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override(&"panel", sb)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 18)
	panel.add_child(_label)
	Events.settings_changed.connect(_sync_visibility)
	Events.debug_overlay_toggled.connect(_on_toggle)
	_sync_visibility()


func _sync_visibility() -> void:
	visible = Settings.data.show_debug


func _on_toggle() -> void:
	Settings.data.show_debug = not Settings.data.show_debug
	Settings.commit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		Events.debug_overlay_toggled.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	_timer += delta
	if _timer < UPDATE_INTERVAL:
		return
	_timer = 0.0
	_label.text = build_text(_worst_ms)
	_worst_ms = 0.0


static func build_text(worst_ms: float) -> String:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms: float = 1000.0 / fps if fps > 0.0 else 0.0
	var cpu_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vmem_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var visible_objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var s: GameSettings = Settings.data
	var lines: PackedStringArray = PackedStringArray([
		TranslationServer.translate("DEBUG_FPS") % [fps, frame_ms, worst_ms],
		TranslationServer.translate("DEBUG_CPU") % [cpu_ms, phys_ms],
		TranslationServer.translate("DEBUG_MEM") % [mem_mb, vmem_mb],
		TranslationServer.translate("DEBUG_OBJECTS") % [objects, nodes, visible_objs],
		TranslationServer.translate("DEBUG_RENDER") % [draw_calls, prims],
		TranslationServer.translate("DEBUG_QUALITY") % [s.quality_preset, s.effective_render_scale(), s.effective_fps_limit()],
	])
	# Этап 3: подгрузка чанков (сколько, очередь, время главного потока) и биом под игроком.
	if not WorldStreamer.debug_text.is_empty():
		lines.append(WorldStreamer.debug_text)
	return "\n".join(lines)
