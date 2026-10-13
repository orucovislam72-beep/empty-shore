class_name Hud
extends CanvasLayer
## HUD: прицел, индикатор автобега, всплывающие сообщения, кнопка паузы и сенсорное управление.

const TOAST_SECONDS: float = 3.0

var _touch: TouchControls
var _crosshair: Control
var _autorun_label: Label
var _toast_label: Label
var _pause_button: Button
var _toast_time: float = 0.0
var _toast_queue: PackedStringArray = PackedStringArray()


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
	_autorun_label.position = Vector2(vp.x * 0.5 - 200.0, vp.y - 90.0)
	_pause_button.modulate.a = s.hud_opacity


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
