class_name Hud
extends CanvasLayer
## HUD: прицел, индикатор автобега, всплывающие сообщения, кнопка паузы и сенсорное управление.
## С этапа 1: показатели (здоровье, сытость, вода), часы, быстрая панель, цель под прицелом
## и лента добычи. Данные приходят из game.gd методами set_*; сам HUD логики не содержит.

const TOAST_SECONDS: float = 3.0
const FEED_LINES: int = 4
const FEED_SECONDS: float = 2.5
const HOTBAR_SLOT_MAX: float = 88.0

var _touch: TouchControls
var _crosshair: Control
var _autorun_label: Label
var _toast_label: Label
var _pause_button: Button
var _toast_time: float = 0.0
var _toast_queue: PackedStringArray = PackedStringArray()
var _stats: StatBars
var _clock: Label
var _target: Label
var _hotbar: Hotbar
var _feed: Array[Label] = []
var _feed_time: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	layer = 10
	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_crosshair = Crosshair.new()
	_crosshair.name = "Crosshair"
	root.add_child(_crosshair)

	_touch = TouchControls.new()
	_touch.name = "TouchControls"
	root.add_child(_touch)

	_autorun_label = Label.new()
	_autorun_label.name = "Autorun"
	_autorun_label.text = "HUD_AUTORUN_ON"
	_autorun_label.visible = false
	_autorun_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_autorun_label.custom_minimum_size = Vector2(400.0, 0.0)
	root.add_child(_autorun_label)

	_toast_label = Label.new()
	_toast_label.name = "Toast"
	_toast_label.visible = false
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size = Vector2(640.0, 0.0)
	_toast_label.add_theme_stylebox_override(&"normal", _toast_style())
	root.add_child(_toast_label)

	_pause_button = Button.new()
	_pause_button.name = "Pause"
	_pause_button.text = "HUD_PAUSE"
	_pause_button.custom_minimum_size = Vector2(120.0, 72.0)
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.pressed.connect(func() -> void: Events.pause_requested.emit())
	root.add_child(_pause_button)

	_stats = StatBars.new()
	_stats.name = "Stats"
	root.add_child(_stats)

	_clock = Label.new()
	_clock.name = "Clock"
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.custom_minimum_size = Vector2(300.0, 0.0)
	_clock.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_clock.add_theme_font_size_override(&"font_size", 20)
	_clock.add_theme_color_override(&"font_color", Color(0.85, 0.87, 0.88, 0.9))
	_clock.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	root.add_child(_clock)

	_target = Label.new()
	_target.name = "Target"
	_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target.custom_minimum_size = Vector2(400.0, 0.0)
	_target.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_target.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	root.add_child(_target)

	_feed_time.resize(FEED_LINES)
	for i: int in FEED_LINES:
		var l: Label = Label.new()
		l.visible = false
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.add_theme_font_size_override(&"font_size", 22)
		l.add_theme_color_override(&"font_color", Color(0.93, 0.9, 0.8))
		l.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
		root.add_child(l)
		_feed.append(l)

	Events.autorun_changed.connect(_on_autorun_changed)
	Events.toast_requested.connect(show_toast)
	Events.settings_changed.connect(_apply_settings)
	root.resized.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	_touch.visible = Settings.touch_controls_visible()
	var s: GameSettings = Settings.data
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var margin: float = 24.0
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win: Vector2i = DisplayServer.window_get_size()
	if win.y > 0 and safe.size.x > 0:
		var cs: float = float(win.y) / vp.y
		margin += maxf(float(safe.position.x), float(win.x - safe.end.x)) / cs
	var x: float = margin if not s.left_handed else vp.x - margin - _pause_button.custom_minimum_size.x
	_pause_button.position = Vector2(x, 20.0)
	# Центрированные элементы раскладываем от размера экрана.
	_crosshair.position = vp * 0.5 - _crosshair.size * 0.5
	_toast_label.position = Vector2(vp.x * 0.5 - 320.0, 110.0)
	_pause_button.modulate.a = s.hud_opacity
	var stats_x: float = margin if not s.left_handed else vp.x - margin - _stats.size.x
	_stats.position = Vector2(stats_x, 104.0)
	_clock.position = Vector2(vp.x * 0.5 - 150.0, 12.0)
	_target.position = Vector2(vp.x * 0.5 - 200.0, vp.y * 0.5 + 34.0)
	for i: int in FEED_LINES:
		_feed[i].position = Vector2(vp.x * 0.5 + 48.0, vp.y * 0.5 - 70.0 - float(i) * 30.0)
	var bar_bottom: float = vp.y - 16.0
	if _hotbar != null:
		_layout_hotbar(vp)
		bar_bottom = _hotbar.position.y - 8.0
	_autorun_label.position = Vector2(vp.x * 0.5 - 200.0, bar_bottom - 34.0)


## Быстрая панель внизу по центру свободного промежутка между стиком и кнопками.
func _layout_hotbar(vp: Vector2) -> void:
	var from: float = 0.0
	var to: float = vp.x
	if _touch.visible and _touch.bottom_free.y > _touch.bottom_free.x:
		from = _touch.bottom_free.x + 12.0
		to = _touch.bottom_free.y - 12.0
	var min_side: float = UiMetrics.min_touch_units(DisplayServer.screen_get_dpi(), _canvas_scale(), 72.0)
	var side: float = clampf((to - from - 5.0 * 6.0) / 6.0, min_side, HOTBAR_SLOT_MAX)
	_hotbar.set_slot_side(side)
	var w: float = side * 6.0 + 5.0 * 6.0
	var cx: float = (from + to) * 0.5
	if to - from < w:
		cx = vp.x * 0.5
	_hotbar.position = Vector2(cx - w * 0.5, vp.y - 12.0 - side)
	_hotbar.modulate.a = maxf(Settings.data.hud_opacity, 0.85)


func _canvas_scale() -> float:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var win: Vector2i = DisplayServer.window_get_size()
	if vis.y <= 0.0 or win.y <= 0:
		return 1.0
	return float(win.y) / vis.y


## Подключение к игровой сессии (после загрузки мира).
func bind(session: SurvivalSession, icons: ItemIcons) -> void:
	_hotbar = Hotbar.new()
	_hotbar.name = "Hotbar"
	_hotbar.setup(session.inventory, icons, HOTBAR_SLOT_MAX)
	_hotbar.slot_selected.connect(session.select_slot)
	session.active_slot_changed.connect(_hotbar.set_active)
	_hotbar.set_active(session.active_slot)
	$Root.add_child(_hotbar)
	_touch.add_passthrough(_hotbar)
	_apply_settings()


## Касания внутри control (например, панели стройки) не уходят в стик и обзор.
func add_touch_passthrough(control: Control) -> void:
	_touch.add_passthrough(control)


func set_stats(health: float, hunger: float, thirst: float) -> void:
	_stats.set_values(health, hunger, thirst)


func set_clock(text: String) -> void:
	if _clock.text != text:
		_clock.text = text


func set_target(text: String) -> void:
	if _target.text != text:
		_target.text = text


## Строка в ленте добычи («+5 Дерево»), новые сверху исчезают через FEED_SECONDS.
func add_feed(text: String) -> void:
	for i: int in range(FEED_LINES - 1, 0, -1):
		_feed[i].text = _feed[i - 1].text
		_feed[i].visible = _feed[i - 1].visible
		_feed_time[i] = _feed_time[i - 1]
	_feed[0].text = text
	_feed[0].visible = true
	_feed_time[0] = FEED_SECONDS


func set_touch_enabled(enabled: bool) -> void:
	if not enabled:
		_touch.release_all()
	_touch.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


func show_toast(text: String) -> void:
	if _toast_label.visible:
		_toast_queue.append(text)
		return
	_toast_label.text = text
	_toast_label.visible = true
	_toast_time = TOAST_SECONDS


func _process(delta: float) -> void:
	for i: int in FEED_LINES:
		if _feed[i].visible:
			_feed_time[i] -= delta
			_feed[i].modulate.a = clampf(_feed_time[i] / 0.6, 0.0, 1.0)
			if _feed_time[i] <= 0.0:
				_feed[i].visible = false
	if not _toast_label.visible:
		return
	_toast_time -= delta
	if _toast_time <= 0.0:
		_toast_label.visible = false
		if not _toast_queue.is_empty():
			var next: String = _toast_queue[0]
			_toast_queue.remove_at(0)
			show_toast(next)


func _on_autorun_changed(enabled: bool) -> void:
	_autorun_label.visible = enabled


static func _toast_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.1, 0.85)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb
